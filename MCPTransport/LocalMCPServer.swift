import Foundation

/// An authenticated, IPv4-loopback-only, stateless MCP endpoint at `/mcp`.
///
/// The app owns credential generation/storage and must supply a high-entropy bearer token.
/// A fresh SDK server handles each HTTP request; initialization is not a global session gate.
/// The immutable catalog is the allowlist for tool dispatch. Restart with a new instance to
/// change credentials or the catalog.
///
/// Each connection serves one request and closes. Limits are 1 MiB of body, 16 KiB of headers,
/// 32 connections, and 16 concurrent requests; read/processing/write deadlines are 10/30/5 seconds.
/// Responses are limited to 4 MiB. No browser origins, streaming, or HTTP sessions are supported.
public actor LocalMCPServer {
    public typealias ToolHandler =
        @Sendable (String, [String: MCPValue]) async throws -> MCPToolResult

    private enum State {
        case stopped
        case starting(UUID, Task<HTTPListener, any Error>)
        case running(UUID, HTTPListener)
        case stopping(UUID, Task<Void, Never>)
    }

    private let configuration: ServerConfiguration
    private var state = State.stopped

    var activeConnections: Int {
        if case .running(_, let listener) = state { return listener.connectionCount }
        return 0
    }

    /// `callTool` must validate its arguments and runtime access policy. Expected tool failures
    /// should be returned with `isError: true`; thrown errors are replaced with a generic MCP error.
    /// Cancellation is cooperative: check `Task.checkCancellation()` before actor-isolated
    /// mutations, and do not detach work that should end when the endpoint is disabled.
    public init(
        port: UInt16,
        token: String,
        tools: [MCPTool],
        version: String,
        callTool: @escaping ToolHandler
    ) {
        configuration = ServerConfiguration(
            port: port, token: token, tools: tools, version: version,
            limits: TransportLimits(), callTool: callTool
        )
    }

    init(
        port: UInt16,
        token: String,
        tools: [MCPTool],
        version: String,
        limits: TransportLimits,
        callTool: @escaping ToolHandler
    ) {
        configuration = ServerConfiguration(
            port: port, token: token, tools: tools, version: version,
            limits: limits, callTool: callTool
        )
    }

    /// Starts listening, or returns the existing port. Concurrent starts share a single bind.
    /// A concurrent `stop()` cancels that generation and waits for its complete cleanup.
    public func start() async throws -> UInt16 {
        try Task.checkCancellation()
        switch state {
        case .running(_, let listener):
            return listener.port
        case .starting(let id, let task):
            return try await finishStarting(id: id, task: task)
        case .stopping(let id, let task):
            await task.value
            if case .stopping(id, _) = state {
                state = .stopped
            }
            return try await start()
        case .stopped:
            try configuration.validate()
            let id = UUID()
            let configuration = configuration
            let task = Task.detached {
                try await HTTPListener.bind(configuration: configuration)
            }
            state = .starting(id, task)
            return try await finishStarting(id: id, task: task)
        }
    }

    /// Immediately closes the listener and accepted connections, and cancels SDK/tool work.
    /// Safe after a failed or partial start, and safe to call repeatedly or concurrently.
    /// An adapter that ignores Swift task cancellation cannot be forcibly interrupted.
    public func stop() async {
        let id: UUID
        let task: Task<Void, Never>
        switch state {
        case .stopped:
            return
        case .stopping(_, let existing):
            await existing.value
            return
        case .running(let generation, let listener):
            id = generation
            task = Task { await listener.stop() }
        case .starting(let generation, let startup):
            id = generation
            startup.cancel()
            task = Task {
                // Binding owns failure cleanup; the awaiting start receives the original error.
                if case .success(let listener) = await startup.result {
                    await listener.stop()
                }
            }
        }
        state = .stopping(id, task)
        await task.value
        if case .stopping(id, _) = state {
            state = .stopped
        }
    }

    private func finishStarting(
        id: UUID, task: Task<HTTPListener, any Error>
    ) async throws -> UInt16 {
        do {
            let listener = try await task.value
            switch state {
            case .starting(id, _):
                if Task.isCancelled {
                    await stop()
                    throw CancellationError()
                }
                state = .running(id, listener)
                return listener.port
            case .running(id, _):
                try Task.checkCancellation()
                return listener.port
            default:
                // The stop task owns this listener even if bind completed before cancellation.
                throw CancellationError()
            }
        } catch {
            if case .starting(id, _) = state {
                state = .stopped
            }
            throw error
        }
    }
}

public enum LocalMCPServerError: Error, Sendable, Equatable, LocalizedError {
    case invalidToken
    case invalidToolCatalog
    case unavailablePort

    public var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "A nonempty, header-safe bearer token is required."
        case .invalidToolCatalog:
            return "The MCP catalog must contain unique, valid tool names."
        case .unavailablePort:
            return "The MCP listener did not acquire a loopback port."
        }
    }
}

struct ServerConfiguration: Sendable {
    let port: UInt16
    let token: String
    let tools: [MCPTool]
    let version: String
    let limits: TransportLimits
    let callTool: LocalMCPServer.ToolHandler

    func validate() throws {
        let tokenBytes = Array(token.utf8)
        let bearerCharacters = Set(
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~+/=".utf8
        )
        guard !tokenBytes.isEmpty, tokenBytes.count <= 1024,
            tokenBytes.allSatisfy({ bearerCharacters.contains($0) })
        else {
            throw LocalMCPServerError.invalidToken
        }
        let nameCharacters = Set(
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-.".utf8
        )
        guard Set(tools.map(\.name)).count == tools.count,
            tools.allSatisfy({
                !$0.name.isEmpty && $0.name.utf8.count <= 128
                    && $0.name.utf8.allSatisfy { nameCharacters.contains($0) }
            })
        else {
            throw LocalMCPServerError.invalidToolCatalog
        }
    }
}
