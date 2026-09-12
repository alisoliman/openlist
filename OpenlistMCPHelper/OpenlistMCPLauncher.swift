import Darwin
import Foundation

private enum Limits {
    static let inputBytes = 1_048_576
    static let responseBytes = 4_194_304
    static let requestTimeout: TimeInterval = 35
    static let resourceTimeout: TimeInterval = 40
}

private struct LauncherError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

private struct Configuration {
    static let defaultURL = "http://127.0.0.1:45873/mcp"

    let url: URL
    let token: String

    init(environment: [String: String]) throws {
        let address = environment["OPENLIST_MCP_URL"] ?? Self.defaultURL
        guard address.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }),
              let components = URLComponents(string: address),
              components.scheme?.lowercased() == "http",
              let host = components.percentEncodedHost?.lowercased(),
              host == "127.0.0.1" || host == "localhost",
              let port = components.port, (1...65535).contains(port),
              components.percentEncodedPath == "/mcp",
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let url = URL(string: "http://127.0.0.1:\(port)/mcp") else {
            throw LauncherError(
                "Invalid OPENLIST_MCP_URL. Use http://127.0.0.1:PORT/mcp or http://localhost:PORT/mcp with an explicit port (1-65535)."
            )
        }
        guard let token = environment["OPENLIST_MCP_TOKEN"], !token.isEmpty,
              token.utf8.count <= 4096,
              token.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else {
            throw LauncherError(
                "OPENLIST_MCP_TOKEN is required and must contain only non-whitespace printable ASCII (at most 4096 bytes). Copy fresh client configuration from Openlist."
            )
        }
        // Pin localhost to IPv4 loopback rather than trusting DNS or a hosts-file override.
        self.url = url
        self.token = token
    }
}

private struct InputReader {
    private var buffered = Data()
    private var reachedEOF = false

    mutating func next() throws -> Data? {
        while true {
            if let newline = buffered.firstIndex(of: 0x0A) {
                let count = buffered.distance(from: buffered.startIndex, to: newline)
                guard count <= Limits.inputBytes else { throw oversizedInput() }
                let line = Data(buffered[..<newline])
                buffered.removeSubrange(...newline)
                if !isBlank(line) { return line }
                continue
            }
            guard buffered.count <= Limits.inputBytes else { throw oversizedInput() }
            if reachedEOF {
                let line = buffered
                buffered = Data()
                return isBlank(line) ? nil : line
            }
            var chunk = [UInt8](repeating: 0, count: 16_384)
            let count = chunk.withUnsafeMutableBytes {
                Darwin.read(STDIN_FILENO, $0.baseAddress, $0.count)
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw LauncherError("Could not read MCP input from stdin.")
            }
            if count == 0 {
                reachedEOF = true
            } else {
                buffered.append(contentsOf: chunk.prefix(count))
            }
        }
    }

    private func isBlank(_ data: Data) -> Bool {
        data.allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }
    }

    private func oversizedInput() -> LauncherError {
        LauncherError("MCP input exceeds the 1 MiB limit per newline-delimited message.")
    }
}

private enum RPCID: Equatable {
    case string(String)
    case number(NSNumber)
    case null

    init?(_ value: Any) {
        if let value = value as? String {
            self = .string(value)
        } else if let value = value as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID(),
                  value.doubleValue.isFinite {
            self = .number(value)
        } else if value is NSNull {
            self = .null
        } else {
            return nil
        }
    }
}

private struct RPCRequest {
    let data: Data
    let method: String
    let id: RPCID?

    init(data: Data) throws {
        guard String(data: data, encoding: .utf8) != nil,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["jsonrpc"] as? String == "2.0",
              let method = object["method"] as? String, !method.isEmpty else {
            throw LauncherError("Invalid MCP input. Expected one UTF-8 JSON-RPC 2.0 request or notification per line.")
        }
        if let params = object["params"], !(params is [String: Any]) && !(params is [Any]) {
            throw LauncherError("Invalid MCP input: JSON-RPC params must be an object or array.")
        }
        if let value = object["id"] {
            guard let id = RPCID(value) else {
                throw LauncherError("Invalid MCP input: a JSON-RPC id must be a string, number, or null.")
            }
            self.id = id
        } else {
            self.id = nil
        }
        self.data = data
        self.method = method
    }

    func response(_ data: Data) throws -> (line: Data, protocolVersion: String?) {
        guard let id,
              String(data: data, encoding: .utf8) != nil,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["jsonrpc"] as? String == "2.0",
              let responseID = object["id"].flatMap(RPCID.init), responseID == id,
              (object["result"] != nil) != (object["error"] != nil) else {
            throw LauncherError("Openlist returned an invalid or mismatched JSON-RPC response.")
        }
        if let error = object["error"] {
            guard let error = error as? [String: Any],
                  let code = error["code"] as? NSNumber,
                  CFGetTypeID(code) != CFBooleanGetTypeID(),
                  code.doubleValue.isFinite,
                  code.doubleValue.rounded(.towardZero) == code.doubleValue,
                  error["message"] is String else {
                throw LauncherError("Openlist returned an invalid JSON-RPC error response.")
            }
        }
        var version: String?
        if method == "initialize", object["result"] != nil {
            guard let result = object["result"] as? [String: Any],
                  let negotiated = result["protocolVersion"] as? String,
                  negotiated.utf8.count == 10,
                  negotiated.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil else {
                throw LauncherError("Openlist returned an invalid MCP protocol version during initialization.")
            }
            version = negotiated
        }
        guard var line = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else {
            throw LauncherError("Openlist returned a response that could not be encoded as JSON.")
        }
        line.append(0x0A)
        return (line, version)
    }
}

// URLSession callbacks run on a separate serial queue. All shared response state is
// locked; the CLI thread waits for completion without blocking that callback queue.
private final class HTTPExchange: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let isNotification: Bool
    private let lock = NSLock()
    private let completed = DispatchSemaphore(value: 0)
    private var body = Data()
    private var failure: LauncherError?
    private var receivedResponse = false

    init(isNotification: Bool) {
        self.isNotification = isNotification
    }

    static func post(_ request: RPCRequest, configuration: Configuration, protocolVersion: String?) throws -> Data {
        var httpRequest = URLRequest(url: configuration.url)
        httpRequest.httpMethod = "POST"
        httpRequest.httpBody = request.data
        httpRequest.timeoutInterval = Limits.requestTimeout
        httpRequest.httpShouldHandleCookies = false
        httpRequest.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let protocolVersion {
            httpRequest.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        }

        let settings = URLSessionConfiguration.ephemeral
        settings.timeoutIntervalForRequest = Limits.requestTimeout
        settings.timeoutIntervalForResource = Limits.resourceTimeout
        settings.waitsForConnectivity = false
        settings.urlCache = nil
        settings.requestCachePolicy = .reloadIgnoringLocalCacheData
        settings.httpCookieStorage = nil
        settings.httpShouldSetCookies = false
        settings.urlCredentialStorage = nil
        settings.connectionProxyDictionary = [:]
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let exchange = HTTPExchange(isNotification: request.id == nil)
        let session = URLSession(configuration: settings, delegate: exchange, delegateQueue: queue)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: httpRequest)
        task.resume()
        guard exchange.completed.wait(timeout: .now() + Limits.resourceTimeout) == .success else {
            task.cancel()
            throw LauncherError("Openlist did not complete the MCP request within 40 seconds. The request was not retried; its outcome may be unknown.")
        }
        return try exchange.lock.withLock {
            if let failure = exchange.failure { throw failure }
            guard exchange.receivedResponse else {
                throw LauncherError("Openlist did not return an HTTP response.")
            }
            return exchange.body
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        lock.withLock {
            failure = LauncherError("Refused an HTTP redirect. The MCP token is only sent directly to the configured loopback endpoint.")
        }
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        lock.withLock {
            failure = LauncherError("Openlist rejected MCP authentication. Copy fresh client configuration from Settings > AI Agents.")
        }
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        let accept = lock.withLock {
            guard failure == nil else { return false }
            guard let response = response as? HTTPURLResponse else {
                failure = LauncherError("Openlist returned a non-HTTP MCP response.")
                return false
            }
            receivedResponse = true
            switch response.statusCode {
            case 401, 403:
                failure = LauncherError("Openlist rejected MCP authentication (HTTP \(response.statusCode)). Copy fresh client configuration from Settings > AI Agents.")
            case 300...399:
                failure = LauncherError("Refused an HTTP redirect from the MCP endpoint.")
            case 404:
                failure = LauncherError("The Openlist MCP endpoint is unavailable (HTTP 404). Check that MCP is enabled and the configured port is correct.")
            case 200 where !isNotification:
                let contentType = response.value(forHTTPHeaderField: "Content-Type")?
                    .split(separator: ";", maxSplits: 1).first?
                    .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if contentType != "application/json" {
                    failure = LauncherError("Openlist returned an unsupported MCP response type. Expected application/json; this stateless bridge does not consume SSE.")
                }
            case 202 where isNotification:
                if response.expectedContentLength > 0 {
                    failure = LauncherError("Openlist returned a body for an MCP notification; expected an empty HTTP 202 response.")
                }
            default:
                failure = LauncherError("Unexpected MCP HTTP status \(response.statusCode). Expected \(isNotification ? "202 for a notification" : "200 with a JSON-RPC response"). The request was not retried.")
            }
            if failure == nil, response.expectedContentLength > Limits.responseBytes {
                failure = LauncherError("Openlist's MCP response exceeds the 4 MiB limit.")
            }
            return failure == nil
        }
        completionHandler(accept ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let cancel = lock.withLock {
            guard failure == nil else { return true }
            if isNotification, !data.isEmpty {
                failure = LauncherError("Openlist returned a body for an MCP notification; expected an empty HTTP 202 response.")
                return true
            }
            guard data.count <= Limits.responseBytes - body.count else {
                failure = LauncherError("Openlist's MCP response exceeds the 4 MiB limit.")
                return true
            }
            body.append(data)
            return false
        }
        if cancel { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.withLock {
            if failure == nil, let error {
                if (error as? URLError)?.code == .timedOut {
                    failure = LauncherError("The Openlist MCP request timed out. The request was not retried; its outcome may be unknown.")
                } else {
                    failure = LauncherError("Cannot complete the local MCP connection. Keep Openlist running with MCP enabled. The request was not retried; its outcome may be unknown.")
                }
            }
        }
        completed.signal()
    }
}

@main
private enum OpenlistMCPLauncher {
    private static let usage = """
    Usage: openlist-mcp [--help]

    Native stdin/stdout compatibility bridge for Openlist's local MCP server.
    Keep Openlist running and enable MCP in Openlist > Settings > AI Agents.
    This helper never starts the app or opens its database.

    Environment:
      OPENLIST_MCP_URL    Optional; default http://127.0.0.1:45873/mcp.
                         Only http://127.0.0.1:PORT/mcp or
                         http://localhost:PORT/mcp, with an explicit port.
      OPENLIST_MCP_TOKEN  Required secret from Openlist's copied client config.
                         Non-whitespace printable ASCII, at most 4096 bytes.

    Send one UTF-8 JSON-RPC request or notification per line on stdin.
    Blank lines are ignored; EOF ends the helper after pending work completes.
    Responses are one JSON-RPC object per stdout line; notifications print none.
    Limits: 1 MiB per input message, 4 MiB per response, 40 seconds per request.
    Errors go to stderr and exit nonzero. HTTP redirects and SSE are rejected.
    --help works offline without configuration.
    """

    static func main() {
        signal(SIGPIPE, SIG_IGN)
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments == ["--help"] {
                try FileHandle.standardOutput.write(contentsOf: Data((usage + "\n").utf8))
                return
            }
            guard arguments.isEmpty else {
                throw LauncherError("Unsupported arguments. Run openlist-mcp --help for usage.")
            }
            let configuration = try Configuration(environment: ProcessInfo.processInfo.environment)
            var reader = InputReader()
            var protocolVersion: String?
            while let data = try reader.next() {
                let request = try RPCRequest(data: data)
                let body = try HTTPExchange.post(request, configuration: configuration, protocolVersion: protocolVersion)
                if request.id != nil {
                    let response = try request.response(body)
                    if let negotiated = response.protocolVersion { protocolVersion = negotiated }
                    do {
                        try FileHandle.standardOutput.write(contentsOf: response.line)
                    } catch {
                        throw LauncherError("Could not write the MCP response to stdout; the client may have disconnected.")
                    }
                }
            }
        } catch {
            let message = (error as? LauncherError)?.message ?? "The MCP helper could not complete an I/O operation."
            let diagnostic = """
            openlist-mcp: \(message)
            Open Openlist > Settings > AI Agents to enable MCP and copy fresh client configuration. Keep Openlist running.

            """
            try? FileHandle.standardError.write(contentsOf: Data(diagnostic.utf8))
            exit(EXIT_FAILURE)
        }
    }
}
