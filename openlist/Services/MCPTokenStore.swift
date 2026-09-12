import Foundation
import Security

@MainActor
protocol MCPTokenStorage {
    func loadOrCreate() throws -> String
    func rotate() throws -> String
}

struct MCPCredentialError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class MCPKeychainTokenStore: MCPTokenStorage {
    private var query: [String: Any] {
        let bundleID = Bundle.main.bundleIdentifier ?? "solimanali.openlist"
        let suffix = ReviewSession.identifier.map { ".review.\($0)" } ?? ""
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(bundleID).mcp\(suffix)",
            kSecAttrAccount as String: "local-agent-access",
        ]
    }

    func loadOrCreate() throws -> String {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return try rotate() }
        guard status == errSecSuccess else { throw failure(status) }
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8),
              token.utf8.count == 64, token.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw MCPCredentialError(message: "The saved MCP token is invalid. Reset the access token in AI Agents settings.")
        }
        return token
    }

    func rotate() throws -> String {
        let token = try Self.generateToken()
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            item[kSecAttrLabel as String] = "Openlist AI agent access"
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw failure(added) }
        } else if status != errSecSuccess {
            throw failure(status)
        }
        return token
    }

    static func generateToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw MCPCredentialError(message: "macOS could not generate an MCP access token (status \(status)).")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func failure(_ status: OSStatus) -> MCPCredentialError {
        MCPCredentialError(message: "Openlist could not access its MCP token in Keychain (status \(status)). Unlock your login Keychain and retry.")
    }
}
