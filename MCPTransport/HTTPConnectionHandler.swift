import Foundation
import MCP
import NIOCore
import NIOHTTP1

/// All handler and ChannelHandlerContext access stays on the NIO event loop. NIOLoopBound
/// carries them through Sendable callbacks without declaring the handler unchecked Sendable.
final class HTTPConnectionHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let configuration: ServerConfiguration
    private let registry: ConnectionRegistry
    private var head: HTTPRequestHead?
    private var headers: [String: String] = [:]
    private var body = ByteBuffer()
    private var processing = false
    private var responded = false
    private var deadline: Scheduled<Void>?
    private var task: Task<Void, Never>?
    private var request: MCPRequest?

    init(configuration: ServerConfiguration, registry: ConnectionRegistry) {
        self.configuration = configuration
        self.registry = registry
    }

    func channelActive(context: ChannelHandlerContext) {
        setDeadline(configuration.limits.readTimeout, status: 408, context: context)
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        // One request per connection: do not queue pipelined requests or SDK tasks.
        guard !processing, !responded else { return }
        switch unwrapInboundIn(data) {
        case .head(let head):
            guard self.head == nil else {
                write(.error(statusCode: 400, .invalidRequest("Unexpected request head")), context: context)
                return
            }
            self.head = head
            guard let port = context.channel.localAddress?.port else {
                write(.error(statusCode: 503, .internalError("Listener unavailable")), context: context)
                return
            }
            switch RequestValidation.headers(
                head, port: port, token: configuration.token, limits: configuration.limits
            ) {
            case .success(let headers):
                self.headers = headers
            case .failure(let rejection):
                write(rejection.response, context: context)
            }
        case .body(var buffer):
            guard head != nil else {
                write(.error(statusCode: 400, .invalidRequest("Missing request head")), context: context)
                return
            }
            guard buffer.readableBytes <= configuration.limits.bodyBytes - body.readableBytes else {
                write(.error(statusCode: 413, .invalidRequest("Request body exceeds size limit")), context: context)
                return
            }
            body.writeBuffer(&buffer)
        case .end(let trailers):
            guard head != nil, trailers == nil || trailers?.isEmpty == true else {
                write(.error(statusCode: 400, .invalidRequest("Request trailers are not supported")), context: context)
                return
            }
            beginRequest(context: context)
        }
    }

    private func beginRequest(context: ChannelHandlerContext) {
        guard let (id, execution) = registry.beginRequest(configuration: configuration) else {
            write(.error(
                statusCode: 503, .internalError("MCP request capacity reached"),
                extraHeaders: ["Retry-After": "1"]
            ), context: context)
            return
        }
        processing = true
        request = execution
        setDeadline(configuration.limits.requestTimeout, status: 504, context: context)
        let request = HTTPRequest(
            method: "POST", headers: headers, body: Data(body.readableBytesView), path: "/mcp"
        )
        body = ByteBuffer()
        let bound = NIOLoopBound((self, context), eventLoop: context.eventLoop)
        let eventLoop = context.eventLoop
        let registry = registry
        task = Task {
            let response = await execution.respond(to: request)
            await withCheckedContinuation { continuation in
                eventLoop.execute {
                    let (handler, context) = bound.value
                    handler.write(response, context: context)
                    continuation.resume()
                }
            }
            await execution.finishResponse()
            // A non-cooperative adapter retains its admission slot rather than allowing an
            // attacker to create unbounded orphan work by timing out successive requests.
            await execution.waitForToolCompletion()
            registry.finishRequest(id)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        deadline?.cancel()
        task?.cancel()
        if let request {
            Task { await request.cancel() }
        }
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        let status: Int
        if case HTTPParserError.headerOverflow = error {
            status = 431
        } else if case RequestRejection.wireLimit = error {
            status = 413
        } else {
            status = 400
        }
        write(.error(statusCode: status, .invalidRequest("Invalid HTTP request")), context: context)
    }

    private func setDeadline(
        _ duration: TimeAmount, status: Int, context: ChannelHandlerContext
    ) {
        deadline?.cancel()
        let bound = NIOLoopBound((self, context), eventLoop: context.eventLoop)
        deadline = context.eventLoop.scheduleTask(in: duration) {
            let (handler, context) = bound.value
            if handler.responded {
                context.close(promise: nil)
            } else {
                handler.write(.error(
                    statusCode: status, .internalError("MCP request timed out")
                ), context: context)
            }
        }
    }

    private func write(_ response: HTTPResponse, context: ChannelHandlerContext) {
        guard !responded, context.channel.isActive else { return }
        responded = true
        task?.cancel()
        if let request {
            Task { await request.cancel() }
        }
        body = ByteBuffer()
        headers = [:]
        setDeadline(configuration.limits.writeTimeout, status: 504, context: context)

        var response = response
        var data = response.bodyData ?? Data()
        if data.count > configuration.limits.responseBytes {
            response = .error(statusCode: 500, .internalError("MCP response exceeds size limit"))
            data = response.bodyData ?? Data()
        }
        var responseHeaders = HTTPHeaders()
        for (name, value) in response.headers {
            responseHeaders.replaceOrAdd(name: name, value: value)
        }
        responseHeaders.replaceOrAdd(name: "Content-Length", value: String(data.count))
        responseHeaders.replaceOrAdd(name: "Connection", value: "close")
        responseHeaders.replaceOrAdd(name: "Cache-Control", value: "no-store")
        responseHeaders.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
        let responseHead = HTTPResponseHead(
            version: .http1_1,
            status: HTTPResponseStatus(statusCode: response.statusCode),
            headers: responseHeaders
        )
        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
        if !data.isEmpty, head?.method != .HEAD {
            context.write(
                wrapOutboundOut(.body(.byteBuffer(context.channel.allocator.buffer(bytes: data)))),
                promise: nil
            )
        }
        let flushed = context.eventLoop.makePromise(of: Void.self)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: flushed)
        let bound = NIOLoopBound(context, eventLoop: context.eventLoop)
        flushed.futureResult.whenComplete { _ in
            bound.value.close(promise: nil)
        }
    }
}
