import Foundation
import MCP
import NIOCore
import NIOHTTP1

struct TransportLimits: Sendable {
    var bodyBytes = 1024 * 1024
    var headerBytes = 16 * 1024
    var headerFieldBytes = 8 * 1024
    var headerCount = 64
    var connections = 32
    var requests = 16
    var responseBytes = 4 * 1024 * 1024
    var readTimeout: TimeAmount = .seconds(10)
    var requestTimeout: TimeAmount = .seconds(30)
    var writeTimeout: TimeAmount = .seconds(5)

    var wireBytes: Int { bodyBytes + 256 * 1024 }
}

enum RequestRejection: Error {
    case wireLimit
}

enum RequestValidation {
    static let sdkPipeline = StandardValidationPipeline(validators: [
        ExactAcceptValidator(),
        AcceptHeaderValidator(mode: .sseRequired),
        ContentTypeValidator(),
        ProtocolVersionValidator(),
    ])

    static func headers(
        _ head: HTTPRequestHead, port: Int, token: String, limits: TransportLimits
    ) -> Result<[String: String], HTTPRejection> {
        let authorization = head.headers["authorization"]
        guard authorization.count == 1,
            let value = authorization.first,
            value.prefix(7).lowercased() == "bearer ",
            constantTimeEqual(Array(value.dropFirst(7).utf8), Array(token.utf8))
        else {
            return .failure(.init(response: .error(
                statusCode: 401, .invalidRequest("Unauthorized"),
                extraHeaders: ["WWW-Authenticate": "Bearer realm=\"OpenlistMCP\""]
            )))
        }
        guard !head.headers.contains(name: "origin") else {
            return .failure(.status(403, "Browser origins are not allowed"))
        }
        let hosts = head.headers["host"]
        guard hosts.count == 1, let host = hosts.first?.lowercased(),
            host == "127.0.0.1:\(port)" || host == "localhost:\(port)"
        else {
            return .failure(.status(403, "Invalid loopback Host"))
        }

        var headers: [String: String] = [:]
        for (name, value) in head.headers {
            let key = name.lowercased()
            if let previous = headers[key] {
                guard key == "accept" else {
                    return .failure(.status(400, "Duplicate request header"))
                }
                headers[key] = previous + "," + value
            } else {
                headers[key] = value
            }
        }
        guard head.uri == "/mcp" else {
            return .failure(.status(404, "Not Found"))
        }
        guard head.method == .POST else {
            return .failure(.init(response: .error(
                statusCode: 405, .invalidRequest("Method Not Allowed"),
                extraHeaders: ["Allow": "POST"]
            )))
        }
        guard head.version == .http1_1 else {
            return .failure(.status(505, "HTTP/1.1 is required"))
        }
        guard headers["expect"] == nil else {
            return .failure(.status(417, "Expect is not supported"))
        }
        if let encoding = headers["content-encoding"], encoding.lowercased() != "identity" {
            return .failure(.status(415, "Content encoding is not supported"))
        }
        if let encoding = headers["transfer-encoding"], encoding.lowercased() != "chunked" {
            return .failure(.status(400, "Unsupported transfer encoding"))
        }
        if let length = headers["content-length"] {
            guard let size = Int(length), size >= 0 else {
                return .failure(.status(400, "Invalid Content-Length"))
            }
            guard size <= limits.bodyBytes else {
                return .failure(.status(413, "Request body exceeds size limit"))
            }
        }

        // Media types are case-insensitive. The SDK validators expect canonical lowercase types.
        headers["accept"] = headers["accept"]?.lowercased()
        headers["content-type"] = headers["content-type"]?.lowercased()
        let request = HTTPRequest(method: "POST", headers: headers, path: "/mcp")
        let context = HTTPValidationContext(httpMethod: "POST", isInitializationRequest: true)
        if let response = sdkPipeline.validate(request, context: context) {
            return .failure(.init(response: response))
        }
        return .success(headers)
    }

    /// Reject ambiguous envelopes before the SDK's permissive request/notification classifier.
    /// In particular, invalid IDs must never turn a tools/call into an executable request.
    static func envelope(_ request: HTTPRequest) -> HTTPResponse? {
        let body = request.body ?? Data()
        let value: Value
        do {
            value = try JSONDecoder().decode(Value.self, from: body)
        } catch {
            return .error(statusCode: 400, .parseError("Invalid JSON"))
        }
        guard case .object(let fields) = value,
            fields["jsonrpc"] == .string("2.0"),
            hasBoundedDepth(value, remaining: 64)
        else {
            return .error(statusCode: 400, .invalidRequest("Invalid JSON-RPC envelope"))
        }
        var requestID: ID?
        if let id = fields["id"] {
            switch id {
            case .string(let string):
                guard string.utf8.count <= 1024 else {
                    return .error(statusCode: 400, .invalidRequest("Request ID exceeds size limit"))
                }
                requestID = .string(string)
            case .int(let number):
                requestID = .number(number)
            default:
                return .error(statusCode: 400, .invalidRequest("Invalid request ID"))
            }
        }
        if let method = fields["method"] {
            guard case .string(let name) = method, !name.isEmpty,
                fields["result"] == nil, fields["error"] == nil
            else {
                return .error(statusCode: 400, .invalidRequest("Invalid request method"))
            }
            let context = HTTPValidationContext(
                httpMethod: "POST", isInitializationRequest: name == Initialize.name
            )
            if let response = sdkPipeline.validate(request, context: context) {
                return response
            }
            if let params = fields["params"], case .object = params {
                // MCP method parameters are objects, unlike generic JSON-RPC positional parameters.
            } else if fields["params"] != nil {
                return .error(statusCode: 400, .invalidParams("Parameters must be an object"))
            }
            if name == CallTool.name {
                guard fields["id"] != nil else {
                    return .error(statusCode: 400, .invalidRequest("Tool calls require an ID"))
                }
                if case .object(let params) = fields["params"], let arguments = params["arguments"] {
                    guard case .object = arguments else {
                        return .error(statusCode: 400, .invalidParams("Arguments must be an object"))
                    }
                }
            }
            if let requestID {
                return validateParameters(body, method: name, id: requestID)
            }
            if [Initialize.name, Ping.name, ListTools.name].contains(name) {
                return .error(statusCode: 400, .invalidRequest("MCP requests require an ID"))
            }
            return nil
        }
        guard fields["id"] != nil,
            (fields["result"] != nil) != (fields["error"] != nil)
        else {
            return .error(statusCode: 400, .invalidRequest("Invalid JSON-RPC envelope"))
        }
        return nil
    }

    private static func validateParameters(_ body: Data, method: String, id: ID) -> HTTPResponse? {
        do {
            let decoder = JSONDecoder()
            switch method {
            case Initialize.name:
                _ = try decoder.decode(Request<Initialize>.self, from: body)
            case Ping.name:
                _ = try decoder.decode(Request<Ping>.self, from: body)
            case ListTools.name:
                _ = try decoder.decode(Request<ListTools>.self, from: body)
            case CallTool.name:
                _ = try decoder.decode(Request<CallTool>.self, from: body)
            default:
                break
            }
            return nil
        } catch {
            // SDK 0.12.1 otherwise reports typed parameter decoding errors as internal errors.
            // Use its response encoder, preserving the client's ID without exposing diagnostics.
            do {
                let response = Ping.response(id: id, error: .invalidParams("Invalid method parameters"))
                return .data(
                    try JSONEncoder().encode(response), headers: ["Content-Type": "application/json"]
                )
            } catch {
                return .error(statusCode: 500, .internalError("Unable to encode MCP error"))
            }
        }
    }

    private static func hasBoundedDepth(_ value: Value, remaining: Int) -> Bool {
        guard remaining > 0 else { return false }
        switch value {
        case .object(let fields):
            return fields.values.allSatisfy { hasBoundedDepth($0, remaining: remaining - 1) }
        case .array(let values):
            return values.allSatisfy { hasBoundedDepth($0, remaining: remaining - 1) }
        default:
            return true
        }
    }

    @inline(never)
    static func constantTimeEqual(_ supplied: [UInt8], _ expected: [UInt8]) -> Bool {
        var difference = supplied.count ^ expected.count
        for index in 0..<max(supplied.count, expected.count) {
            let left = index < supplied.count ? supplied[index] : 0
            let right = index < expected.count ? expected[index] : 0
            difference |= Int(left ^ right)
        }
        return difference == 0
    }
}

struct HTTPRejection: Error {
    let response: HTTPResponse

    static func status(_ status: Int, _ message: String) -> Self {
        Self(response: .error(statusCode: status, .invalidRequest(message)))
    }
}

private struct ExactAcceptValidator: HTTPRequestValidator {
    func validate(_ request: HTTPRequest, context: HTTPValidationContext) -> HTTPResponse? {
        var accepted = Set<String>()
        for range in (request.header("Accept") ?? "").split(separator: ",") {
            let parts = range.split(separator: ";").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard let type = parts.first else { continue }
            var quality = 1.0
            for parameter in parts.dropFirst() {
                let pair = parameter.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                if pair.first == "q" {
                    guard pair.count == 2, let parsed = Double(pair[1]),
                        parsed.isFinite, (0...1).contains(parsed)
                    else {
                        return .error(statusCode: 406, .invalidRequest("Invalid Accept quality"))
                    }
                    quality = parsed
                }
            }
            if quality > 0 { accepted.insert(type) }
        }
        guard accepted.contains("application/json"), accepted.contains("text/event-stream") else {
            return .error(
                statusCode: 406,
                .invalidRequest("Accept must include application/json and text/event-stream")
            )
        }
        return nil
    }
}
