import Foundation
import MCP
import OpenlistMCP

@MainActor
func helperRoundTrip(executable: URL, endpoint: String, token: String, listID: UUID, directory: URL) async throws -> [MCPValue] {
    let outputURL = directory.appendingPathComponent("helper-stdout.jsonl")
    let errorURL = directory.appendingPathComponent("helper-stderr.txt")
    try Data().write(to: outputURL)
    try Data().write(to: errorURL)
    let output = try FileHandle(forWritingTo: outputURL)
    let errors = try FileHandle(forWritingTo: errorURL)
    defer {
        try? output.close()
        try? errors.close()
    }
    let input = Pipe()
    let process = Process()
    process.executableURL = executable
    var environment = ProcessInfo.processInfo.environment
    environment["OPENLIST_MCP_URL"] = endpoint
    environment["OPENLIST_MCP_TOKEN"] = token
    process.environment = environment
    process.standardInput = input
    process.standardOutput = output
    process.standardError = errors
    let messages: [MCPValue] = [
        ["jsonrpc": "2.0", "id": 10, "method": "initialize", "params": [
            "protocolVersion": "2025-11-25", "capabilities": [:],
            "clientInfo": ["name": "packaged-stdio-check", "version": "1"],
        ]],
        ["jsonrpc": "2.0", "method": "notifications/initialized"],
        ["jsonrpc": "2.0", "id": 11, "method": "tools/list"],
        ["jsonrpc": "2.0", "id": 12, "method": "tools/call", "params": [
            "name": "openlist_create_task",
            "arguments": ["title": "Created through packaged stdio", "list_id": .string(listID.uuidString)],
        ]],
    ]
    var wire = Data()
    for message in messages {
        wire.append(try JSONEncoder().encode(message))
        wire.append(10)
    }
    let deadline = Task {
        try await Task.sleep(for: .seconds(20))
        if process.isRunning { process.terminate() }
    }
    defer { deadline.cancel() }
    let status = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, any Error>) in
        process.terminationHandler = { process in continuation.resume(returning: process.terminationStatus) }
        do {
            try process.run()
        } catch {
            continuation.resume(throwing: error)
            return
        }
        input.fileHandleForWriting.write(wire)
        input.fileHandleForWriting.closeFile()
    }
    guard status == 0 else {
        let diagnostic = try String(contentsOf: errorURL, encoding: .utf8)
        throw MCPCredentialError(message: "Packaged helper failed (\(status)): \(diagnostic)")
    }
    let text = try String(contentsOf: outputURL, encoding: .utf8)
    return try text.split(separator: "\n").map {
        try JSONDecoder().decode(MCPValue.self, from: Data($0.utf8))
    }
}
