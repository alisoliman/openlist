import Foundation
import MCP
import Observation
import OpenlistMCP

@Observable
@MainActor
final class MCPIntegration {
    enum Status: Equatable {
        case off, starting, running, failed(String)
    }

    enum ClientFormat: String, CaseIterable, Identifiable {
        case stdio, vscode
        var id: String { rawValue }
        var title: String {
            switch self {
            case .stdio: "Claude Desktop / stdio"
            case .vscode: "VS Code / HTTP"
            }
        }
    }

    private(set) var status = Status.off
    var notice: String?
    private let settings: AppSettings
    private let adapter: MCPStoreAdapter
    private let tokenStore: any MCPTokenStorage
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var server: LocalMCPServer?
    @ObservationIgnored private var lifecycle: Task<Void, Never>?
    @ObservationIgnored private var tokenRotationPending = false
    private var generation = 0
    private var storageAvailable = false

    init(store: Store, settings: AppSettings, tokenStore: any MCPTokenStorage = MCPKeychainTokenStore()) {
        self.settings = settings
        self.adapter = MCPStoreAdapter(store: store)
        self.tokenStore = tokenStore
    }

    var url: String { "http://127.0.0.1:\(settings.mcpPort)/mcp" }
    var isRunning: Bool { status == .running }

    var statusText: String {
        switch status {
        case .off: "Off"
        case .starting: "Starting"
        case .running: settings.mcpAllowsWrites ? "Running - read and write" : "Running - read only"
        case .failed: "Unavailable"
        }
    }

    func start(storageAvailable: Bool) {
        self.storageAvailable = storageAvailable
        restart()
    }

    func setEnabled(_ enabled: Bool) {
        settings.mcpEnabled = enabled
        restart()
    }

    func setAllowsWrites(_ allowed: Bool) {
        settings.mcpAllowsWrites = allowed
        restart()
    }

    func setPort(_ text: String) {
        guard let port = Int(text), (1024...65535).contains(port) else {
            notice = "Choose a port from 1024 to 65535."
            return
        }
        settings.mcpPort = port
        restart()
    }

    func restart(rotatingToken: Bool = false) {
        tokenRotationPending = tokenRotationPending || rotatingToken
        generation &+= 1
        let current = generation
        let predecessor = lifecycle
        let oldServer = server
        predecessor?.cancel()
        server = nil
        token = nil
        notice = nil
        status = settings.mcpEnabled ? .starting : .off
        lifecycle = Task { [weak self] in
            await predecessor?.value
            await oldServer?.stop()
            guard let self, generation == current else { return }
            guard settings.mcpEnabled else { return }
            guard storageAvailable else {
                status = .failed("AI agent access is unavailable because Openlist could not open its saved data. Temporary in-memory sessions are never exposed.")
                return
            }
            guard (1024...65535).contains(settings.mcpPort), let port = UInt16(exactly: settings.mcpPort) else {
                status = .failed("Choose a port from 1024 to 65535.")
                return
            }
            var candidate: LocalMCPServer?
            do {
                try Task.checkCancellation()
                let credential = try tokenRotationPending ? tokenStore.rotate() : tokenStore.loadOrCreate()
                tokenRotationPending = false
                let next = LocalMCPServer(
                    port: port, token: credential,
                    tools: OpenlistMCPTool.catalog(allowsWrites: settings.mcpAllowsWrites),
                    version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
                ) { [weak self] name, arguments in
                    guard let self else { throw CancellationError() }
                    return try await handle(name, arguments: arguments, generation: current)
                }
                candidate = next
                server = next
                _ = try await next.start()
                guard generation == current, settings.mcpEnabled, !Task.isCancelled else {
                    await next.stop()
                    return
                }
                token = credential
                status = .running
            } catch {
                await candidate?.stop()
                guard generation == current else { return }
                server = nil
                status = .failed("MCP could not start. \(error.localizedDescription) If this port is in use, choose another.")
            }
        }
    }

    /// Used by checks and by shutdown callers that must wait for the listener to close.
    func waitForTransition() async { await lifecycle?.value }

    func configuration(for format: ClientFormat, bundleURL: URL = Bundle.main.bundleURL) throws -> String {
        let token = try accessToken()
        #if OPENLIST_DEV
        let serverName = "openlist-dev"
        #else
        let serverName = "openlist"
        #endif
        let value: MCPValue
        switch format {
        case .stdio:
            value = .object(["mcpServers": .object([serverName: .object([
                "command": .string(bundleURL.appendingPathComponent("Contents/MacOS/openlist-mcp").path),
                "env": .object(["OPENLIST_MCP_URL": .string(url), "OPENLIST_MCP_TOKEN": .string(token)]),
            ])])])
        case .vscode:
            value = .object(["servers": .object([serverName: .object([
                "type": "http", "url": .string(url),
                "headers": .object(["Authorization": .string("Bearer \(token)")]),
            ])])])
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    func accessToken() throws -> String {
        guard isRunning, let token else {
            throw MCPCredentialError(message: "Enable MCP and wait for Running before copying connection details.")
        }
        return token
    }

    private func handle(_ name: String, arguments: [String: MCPValue], generation: Int) throws -> MCPToolResult {
        try Task.checkCancellation()
        guard generation == self.generation, isRunning, settings.mcpEnabled, storageAvailable else {
            return MCPToolFailure(code: "access_revoked", message: "MCP access changed or was disabled. Reconnect using the current configuration.").result
        }
        return try adapter.call(name, arguments: arguments, allowsWrites: settings.mcpAllowsWrites)
    }
}
