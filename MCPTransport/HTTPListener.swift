import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOPosix
import OSLog

final class ConnectionRegistry: Sendable {
    private struct State {
        var stopping = false
        var channels: [ObjectIdentifier: any Channel] = [:]
        var requests: [UUID: MCPRequest] = [:]
    }

    private let state = NIOLockedValueBox(State())
    private let limits: TransportLimits

    init(limits: TransportLimits) {
        self.limits = limits
    }

    var isStopping: Bool { state.withLockedValue { $0.stopping } }
    var connectionCount: Int { state.withLockedValue { $0.channels.count } }

    func add(_ channel: any Channel) -> Bool {
        state.withLockedValue {
            guard !$0.stopping, $0.channels.count < limits.connections else { return false }
            $0.channels[ObjectIdentifier(channel)] = channel
            return true
        }
    }

    func remove(_ channel: any Channel) {
        _ = state.withLockedValue { $0.channels.removeValue(forKey: ObjectIdentifier(channel)) }
    }

    func beginRequest(configuration: ServerConfiguration) -> (UUID, MCPRequest)? {
        state.withLockedValue {
            guard !$0.stopping, $0.requests.count < limits.requests else { return nil }
            let id = UUID()
            let request = MCPRequest(configuration: configuration, registry: self)
            $0.requests[id] = request
            return (id, request)
        }
    }

    func finishRequest(_ id: UUID) {
        _ = state.withLockedValue { $0.requests.removeValue(forKey: id) }
    }

    func shutdown() -> (channels: [any Channel], requests: [MCPRequest]) {
        state.withLockedValue {
            $0.stopping = true
            return (Array($0.channels.values), Array($0.requests.values))
        }
    }
}

final class HTTPListener: Sendable {
    let port: UInt16
    var connectionCount: Int { registry.connectionCount }
    private let channel: any Channel
    private let group: MultiThreadedEventLoopGroup
    private let registry: ConnectionRegistry

    private init(
        port: UInt16, channel: any Channel,
        group: MultiThreadedEventLoopGroup, registry: ConnectionRegistry
    ) {
        self.port = port
        self.channel = channel
        self.group = group
        self.registry = registry
    }

    static func bind(configuration: ServerConfiguration) async throws -> HTTPListener {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let registry = ConnectionRegistry(limits: configuration.limits)
        var listener: (any Channel)?
        do {
            try Task.checkCancellation()
            let bootstrap = ServerBootstrap(group: group)
                .serverChannelOption(
                    ChannelOptions.backlog, value: Int32(clamping: configuration.limits.connections)
                )
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)
                .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
                .childChannelOption(
                    ChannelOptions.recvAllocator,
                    value: FixedSizeRecvByteBufferAllocator(capacity: 16 * 1024)
                )
                .childChannelInitializer { channel in
                    guard registry.add(channel) else {
                        return channel.close()
                    }
                    channel.closeFuture.whenComplete { _ in registry.remove(channel) }
                    return channel.eventLoop.makeCompletedFuture {
                        let pipeline = channel.pipeline.syncOperations
                        try pipeline.addHandler(WireLimitHandler(limit: configuration.limits.wireBytes))
                        var limits = NIOHTTPDecoderLimitConfiguration()
                        limits.maxHeaderFieldSize = configuration.limits.headerFieldBytes
                        limits.maxHeaderListSize = configuration.limits.headerBytes
                        limits.maxHeaderFieldCount = configuration.limits.headerCount
                        try pipeline.configureHTTPServerPipeline(
                            withPipeliningAssistance: false,
                            withErrorHandling: false,
                            withEncoderConfiguration: .init(),
                            withDecoderLimitConfiguration: limits
                        )
                        try pipeline.addHandler(HTTPConnectionHandler(
                            configuration: configuration, registry: registry
                        ))
                    }
                }
            // An explicit numeric SocketAddress avoids wildcard binding and DNS resolution.
            let address = try SocketAddress(ipAddress: "127.0.0.1", port: Int(configuration.port))
            let channel = try await bootstrap.bind(to: address).get()
            listener = channel
            guard channel.localAddress?.ipAddress == "127.0.0.1",
                let boundPort = channel.localAddress?.port,
                let port = UInt16(exactly: boundPort), port != 0
            else {
                throw LocalMCPServerError.unavailablePort
            }
            try Task.checkCancellation()
            return HTTPListener(port: port, channel: channel, group: group, registry: registry)
        } catch {
            await shutdown(listener: listener, registry: registry, group: group)
            throw error
        }
    }

    func stop() async {
        await Self.shutdown(listener: channel, registry: registry, group: group)
    }

    private static func shutdown(
        listener: (any Channel)?, registry: ConnectionRegistry, group: MultiThreadedEventLoopGroup
    ) async {
        let resources = registry.shutdown()
        let channels = resources.channels + (listener.map { [$0] } ?? [])
        for channel in channels {
            channel.close(mode: .all, promise: nil)
        }
        for request in resources.requests {
            await request.cancel()
        }
        // Drain response callbacks before shutting down their event loop, but do not wait
        // indefinitely for application code that ignores cooperative tool cancellation.
        for request in resources.requests {
            await request.waitForResponse()
        }
        for channel in channels {
            // NIO guarantees closeFuture never fails, including an already-closed channel.
            await withCheckedContinuation { continuation in
                channel.closeFuture.whenSuccess { continuation.resume() }
            }
        }
        do {
            try await group.shutdownGracefully()
        } catch {
            // Lifecycle diagnostics deliberately omit all request data and error descriptions.
            Logger(subsystem: "OpenlistMCP", category: "Lifecycle")
                .error("MCP event loop shutdown failed after channels were closed")
        }
    }
}

private final class WireLimitHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer

    private let limit: Int
    private var received = 0
    private var rejected = false

    init(limit: Int) {
        self.limit = limit
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !rejected else { return }
        let buffer = unwrapInboundIn(data)
        guard buffer.readableBytes <= limit - received else {
            rejected = true
            context.fireErrorCaught(RequestRejection.wireLimit)
            return
        }
        received += buffer.readableBytes
        context.fireChannelRead(data)
    }
}
