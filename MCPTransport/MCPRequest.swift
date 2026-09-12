import Foundation
import MCP

/// SDK response routing and initialization state are local to exactly one HTTP request.
actor MCPRequest {
    private let configuration: ServerConfiguration
    private let registry: ConnectionRegistry
    private let server: Server
    private let transport = StatelessHTTPServerTransport(
        validationPipeline: RequestValidation.sdkPipeline
    )
    private var cancelled = false
    private var toolTask: Task<MCPToolResult, any Error>?
    private var responseFinished = false
    private var responseWaiters: [CheckedContinuation<Void, Never>] = []

    init(configuration: ServerConfiguration, registry: ConnectionRegistry) {
        self.configuration = configuration
        self.registry = registry
        server = Server(
            name: "Openlist", version: configuration.version,
            capabilities: .init(tools: .init()),
            configuration: .default
        )
    }

    func respond(to request: HTTPRequest) async -> HTTPResponse {
        guard !cancelled, !registry.isStopping else { return unavailable() }
        if let error = RequestValidation.envelope(request) {
            return error
        }
        let tools = configuration.tools
        await server.withMethodHandler(ListTools.self) { parameters in
            guard parameters.cursor == nil else {
                throw MCPError.invalidParams("The tool catalog does not use pagination")
            }
            return .init(tools: tools)
        }
        await server.withMethodHandler(CallTool.self) { [weak self] parameters in
            guard let self else { throw CancellationError() }
            return try await self.invoke(parameters)
        }
        do {
            guard !cancelled, !registry.isStopping else { return unavailable() }
            try await server.start(transport: transport)
            guard !cancelled, !registry.isStopping else {
                await cancel()
                return unavailable()
            }
            let response = await transport.handleRequest(request)
            await cancel()
            return response
        } catch {
            await cancel()
            return .error(statusCode: 500, .internalError("Unable to process MCP request"))
        }
    }

    func cancel() async {
        cancelled = true
        toolTask?.cancel()
        // SDK stop does not cancel its inbound handler tasks. Cancel the adapter explicitly,
        // and disconnect to resume the stateless transport's response continuation.
        await transport.disconnect()
        await server.stop()
    }

    func waitForToolCompletion() async {
        if let task = toolTask {
            _ = await task.result
        }
    }

    func finishResponse() {
        responseFinished = true
        for waiter in responseWaiters { waiter.resume() }
        responseWaiters.removeAll()
    }

    func waitForResponse() async {
        guard !responseFinished else { return }
        await withCheckedContinuation { responseWaiters.append($0) }
    }

    private func invoke(_ parameters: CallTool.Parameters) async throws -> MCPToolResult {
        guard !cancelled, !registry.isStopping else { throw CancellationError() }
        guard configuration.tools.contains(where: { $0.name == parameters.name }) else {
            throw MCPError.invalidParams("Unknown tool")
        }
        let callTool = configuration.callTool
        let task = Task {
            try Task.checkCancellation()
            do {
                return try await callTool(parameters.name, parameters.arguments ?? [:])
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw MCPError.internalError("Tool execution failed")
            }
        }
        toolTask = task
        defer { toolTask = nil }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func unavailable() -> HTTPResponse {
        .error(statusCode: 503, .internalError("MCP endpoint is stopping"))
    }
}
