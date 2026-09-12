import Foundation
import MCP
import NIOCore
import NIOPosix
import Testing
@testable import OpenlistMCP

let fixtureToken = "isolated-test-token-09b1a881-not-a-real-credential"

let fixtureTools: [MCPTool] = [
    MCPTool(
        name: "echo",
        description: "Echo isolated fixture input.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object(["text": .object(["type": .string("string")])]),
            "required": .array([.string("text")]),
        ]),
        annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
    ),
]

enum FixtureError: Error {
    case noHTTPResponse
    case invalidJSON
    case deadline
    case oversizedResponse
    case privateAdapterFailure
}

actor ToolProbe {
    private(set) var started: [String] = []
    private(set) var completed: [String] = []
    private(set) var cancelled: [String] = []
    private var suspension: CheckedContinuation<Void, Never>?
    private var released = false

    func call(_ name: String, arguments: [String: MCPValue]) async throws -> MCPToolResult {
        let text = arguments["text"]?.stringValue ?? ""
        started.append(text)
        do {
            if text == "hold-until-released", !released {
                await withCheckedContinuation { suspension = $0 }
            }
            if let delay = arguments["delay"]?.intValue {
                try await Task.sleep(for: .milliseconds(delay))
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            cancelled.append(text)
            throw CancellationError()
        }
        if text == "throw-private-error" {
            throw FixtureError.privateAdapterFailure
        }
        if text == "expected-tool-error" {
            return .init(content: [.text(text: "Expected fixture failure", annotations: nil, _meta: nil)],
                         isError: true)
        }
        completed.append(text)
        return .init(
            content: [.text(text: text, annotations: nil, _meta: nil)],
            structuredContent: .object(["echo": .string(text)]),
            isError: false
        )
    }

    func releaseSuspendedCall() {
        released = true
        suspension?.resume()
        suspension = nil
    }
}

struct LoopbackFixture: Sendable {
    let server: LocalMCPServer
    let port: UInt16
    let probe: ToolProbe
    let group: MultiThreadedEventLoopGroup

    func socket(port: UInt16? = nil) async throws -> RawSocket {
        try await RawSocket.connect(port: port ?? self.port, group: group)
    }

    func send(
        _ body: String = pingBody,
        method: String = "POST",
        path: String = "/mcp",
        replacing: [String: String] = [:],
        removing: Set<String> = [],
        extra: [(String, String)] = [],
        port: UInt16? = nil
    ) async throws -> WireResponse {
        let connection = try await socket(port: port)
        try await connection.write(requestBytes(
            body, method: method, path: path, replacing: replacing, removing: removing,
            extra: extra, port: port
        ))
        return try await connection.response()
    }

    func requestBytes(
        _ body: String = pingBody,
        method: String = "POST",
        path: String = "/mcp",
        replacing: [String: String] = [:],
        removing: Set<String> = [],
        extra: [(String, String)] = [],
        port: UInt16? = nil
    ) -> Data {
        var headers = [
            "host": "127.0.0.1:\(port ?? self.port)",
            "authorization": "Bearer \(fixtureToken)",
            "accept": "application/json, text/event-stream",
            "content-type": "application/json",
            "mcp-protocol-version": "2025-11-25",
            "content-length": String(body.utf8.count),
            "connection": "close",
        ]
        for (key, value) in replacing { headers[key.lowercased()] = value }
        for key in removing { headers.removeValue(forKey: key.lowercased()) }
        let lines = headers.sorted(by: { $0.key < $1.key }).map { "\($0.key): \($0.value)" }
            + extra.map { "\($0.0): \($0.1)" }
        return Data(("\(method) \(path) HTTP/1.1\r\n" + lines.joined(separator: "\r\n")
                     + "\r\n\r\n" + body).utf8)
    }
}

func withFixture(
    limits: TransportLimits = TransportLimits(),
    _ operation: @Sendable (LoopbackFixture) async throws -> Void
) async throws {
    let probe = ToolProbe()
    let server = LocalMCPServer(
        port: 0, token: fixtureToken, tools: fixtureTools, version: "fixture-1",
        limits: limits, callTool: { try await probe.call($0, arguments: $1) }
    )
    let port = try await server.start()
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let fixture = LoopbackFixture(server: server, port: port, probe: probe, group: group)
    do {
        try await operation(fixture)
        await server.stop()
        await probe.releaseSuspendedCall()
        try await group.shutdownGracefully()
    } catch {
        await server.stop()
        await probe.releaseSuspendedCall()
        do {
            try await group.shutdownGracefully()
        } catch {
            Issue.record(error, "Fixture event loop cleanup failed")
        }
        throw error
    }
}

let pingBody = #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#

func initializeBody(client: String = "fixture", version: String = "2025-11-25") -> String {
    """
    {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"\(version)",\
    "capabilities":{},"clientInfo":{"name":"\(client)","version":"1"}}}
    """
}

func callBody(text: String, delay: Int = 0) throws -> String {
    let data = try JSONEncoder().encode(CallTool.request(
        id: .number(1), .init(name: "echo", arguments: [
            "text": .string(text), "delay": .int(delay),
        ])
    ))
    return String(decoding: data, as: UTF8.self)
}

func eventually(_ condition: @Sendable () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while !(await condition()) {
        guard ContinuousClock.now < deadline else { throw FixtureError.deadline }
        try await Task.sleep(for: .milliseconds(10))
    }
}

/// Deliberately sends raw bytes so tests can exercise malformed HTTP that URLSession refuses
/// to generate. Normal MCP interoperability is tested independently with the official client.
struct RawSocket: Sendable {
    let channel: any Channel
    private let received: EventLoopFuture<Data>

    static func connect(port: UInt16, group: MultiThreadedEventLoopGroup) async throws -> Self {
        let promise = group.next().makePromise(of: Data.self)
        let channel = try await ClientBootstrap(group: group)
            .connectTimeout(.seconds(2))
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(ResponseCollector(promise: promise))
                }
            }
            .connect(host: "127.0.0.1", port: Int(port)).get()
        let deadline = channel.eventLoop.scheduleTask(in: .seconds(5)) {
            channel.close(mode: .all, promise: nil)
        }
        channel.closeFuture.whenComplete { _ in deadline.cancel() }
        return Self(channel: channel, received: promise.futureResult)
    }

    func write(_ bytes: Data) async throws {
        try await channel.writeAndFlush(channel.allocator.buffer(bytes: bytes)).get()
    }

    func response() async throws -> WireResponse {
        try WireResponse(bytes: await received.get())
    }

    func bytesOnClose() async throws -> Data {
        try await received.get()
    }

    func close() async {
        channel.close(mode: .all, promise: nil)
        await withCheckedContinuation { continuation in
            channel.closeFuture.whenSuccess { continuation.resume() }
        }
    }
}

private final class ResponseCollector: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    private let promise: EventLoopPromise<Data>
    private var bytes = Data()
    private var failed = false

    init(promise: EventLoopPromise<Data>) { self.promise = promise }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !failed else { return }
        let buffer = unwrapInboundIn(data)
        guard bytes.count + buffer.readableBytes <= 5 * 1024 * 1024 else {
            failed = true
            promise.fail(FixtureError.oversizedResponse)
            context.close(promise: nil)
            return
        }
        bytes.append(contentsOf: buffer.readableBytesView)
    }

    func channelInactive(context: ChannelHandlerContext) {
        if !failed { promise.succeed(bytes) }
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        // A hard close is an expected observable result of connection admission/stop tests.
        context.close(promise: nil)
    }
}

struct WireResponse: Sendable {
    let status: Int
    let headers: [String: String]
    let body: Data
    let bytes: Data

    init(bytes: Data) throws {
        guard let boundary = bytes.range(of: Data("\r\n\r\n".utf8)) else {
            throw FixtureError.noHTTPResponse
        }
        let lines = String(decoding: bytes[..<boundary.lowerBound], as: UTF8.self)
            .components(separatedBy: "\r\n")
        guard let first = lines.first,
            let status = Int(first.split(separator: " ").dropFirst().first ?? "")
        else {
            throw FixtureError.noHTTPResponse
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { throw FixtureError.noHTTPResponse }
            headers[String(pair[0]).lowercased()] = pair[1].trimmingCharacters(in: .whitespaces)
        }
        self.status = status
        self.headers = headers
        self.body = Data(bytes[boundary.upperBound...])
        self.bytes = bytes
    }

    func json() throws -> [String: MCPValue] {
        try JSONDecoder().decode([String: MCPValue].self, from: body)
    }

    func result() throws -> [String: MCPValue] {
        guard case .object(let result) = try json()["result"] else { throw FixtureError.invalidJSON }
        return result
    }

    func errorCode() throws -> Int? {
        guard case .object(let error) = try json()["error"] else { throw FixtureError.invalidJSON }
        return error["code"]?.intValue
    }
}
