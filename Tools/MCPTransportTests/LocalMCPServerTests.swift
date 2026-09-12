import Foundation
import MCP
import Testing
@testable import OpenlistMCP

@Suite(.serialized)
struct LocalMCPServerTests {
    @Test
    func officialSDKClientRoundTrip() async throws {
        try await withFixture { fixture in
            let endpoint = try #require(URL(string: "http://127.0.0.1:\(fixture.port)/mcp"))
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 3
            configuration.timeoutIntervalForResource = 5
            let transport = HTTPClientTransport(
                endpoint: endpoint, configuration: configuration, streaming: false,
                requestModifier: { request in
                    var request = request
                    request.setValue("Bearer \(fixtureToken)", forHTTPHeaderField: "Authorization")
                    return request
                }
            )
            let client = Client(name: "isolated-swift-client", version: "1", configuration: .strict)
            do {
                let initialization = try await client.connect(transport: transport)
                #expect(initialization.protocolVersion == "2025-11-25")
                #expect(initialization.serverInfo.name == "Openlist")
                #expect(initialization.capabilities.tools != nil)
                #expect(initialization.capabilities.tools?.listChanged != true)
                #expect(initialization.capabilities.resources == nil)
                #expect(initialization.capabilities.prompts == nil)
                #expect(initialization.capabilities.logging == nil)
                #expect(initialization.capabilities.completions == nil)
                let catalog = try await client.listTools()
                #expect(catalog.tools == fixtureTools)
                #expect(catalog.nextCursor == nil)
                let call = try await client.send(CallTool.request(.init(
                    name: "echo", arguments: ["text": .string("native SDK")]
                )))
                let result = try await call.value
                #expect(result.isError == false)
                #expect(result.structuredContent == .object(["echo": .string("native SDK")]))
                #expect(result.content == [.text(text: "native SDK", annotations: nil, _meta: nil)])
                try await client.ping()
                await client.disconnect()
            } catch {
                await client.disconnect()
                throw error
            }
        }
    }

    @Test
    func requestIDsLeaveRoomForTheResponseEnvelope() async throws {
        try await withFixture { fixture in
            func body(length: Int) throws -> String {
                let data = try JSONEncoder().encode(Value.object([
                    "jsonrpc": "2.0", "id": .string(String(repeating: "x", count: length)),
                    "method": "tools/call", "params": [
                        "name": "echo", "arguments": ["text": "bounded-id"],
                    ],
                ]))
                return String(decoding: data, as: UTF8.self)
            }
            #expect(try await fixture.send(body(length: 1025)).status == 400)
            #expect(await fixture.probe.started.isEmpty)
            let valid = try await fixture.send(body(length: 1024))
            #expect(valid.status == 200)
            #expect(try valid.json()["id"]?.stringValue?.utf8.count == 1024)
        }
    }

    @Test
    func simultaneousClientsInitializeAndReuseTheSameRequestIDs() async throws {
        try await withFixture { fixture in
            async let firstInitialization = fixture.send(initializeBody(client: "first"))
            async let secondInitialization = fixture.send(initializeBody(client: "second"))
            let initializations = try await [firstInitialization, secondInitialization]
            for response in initializations {
                #expect(response.status == 200)
                #expect(try response.json()["id"] == .int(1))
                #expect(try response.result()["protocolVersion"] == .string("2025-11-25"))
                #expect(response.headers["mcp-session-id"] == nil)
            }

            // Both clients reuse id 1, concurrently, including while the slower call is suspended.
            async let first = fixture.send(callBody(text: "first-client", delay: 100))
            async let second = fixture.send(callBody(text: "second-client", delay: 10))
            let replies = try await [first, second]
            #expect(try replies[0].result()["structuredContent"] == .object(["echo": .string("first-client")]))
            #expect(try replies[1].result()["structuredContent"] == .object(["echo": .string("second-client")]))
            #expect(try replies.allSatisfy { try $0.json()["id"] == .int(1) })
            #expect(try await fixture.send(initializeBody(client: "first")).status == 200)
        }
    }

    @Test
    func authenticationHostOriginAndRoutingAreEnforcedBeforeDispatch() async throws {
        try await withFixture { fixture in
            let call = try callBody(text: "must-not-run")
            struct RejectionCase {
                var status: Int
                var method = "POST"
                var path = "/mcp"
                var replacing: [String: String] = [:]
                var removing: Set<String> = []
                var extra: [(String, String)] = []
            }
            let cases: [RejectionCase] = [
                .init(status: 401, removing: ["authorization"]),
                .init(status: 401, replacing: ["authorization": "Bearer wrong"]),
                .init(status: 401, replacing: ["authorization": "Bearer "]),
                .init(status: 401, replacing: ["authorization": "Basic \(fixtureToken)"]),
                .init(status: 401, extra: [("Authorization", "Bearer \(fixtureToken)")]),
                .init(status: 401, method: "GET", path: "/health", removing: ["authorization"]),
                .init(status: 403, replacing: ["origin": "https://example.invalid"]),
                .init(status: 403, replacing: ["origin": "http://127.0.0.1:\(fixture.port)"]),
                .init(status: 403, replacing: ["origin": "null"]),
                .init(status: 403, replacing: ["origin": ""]),
                .init(status: 403, removing: ["host"]),
                .init(status: 403, replacing: ["host": "example.invalid:\(fixture.port)"]),
                .init(status: 403, replacing: ["host": "127.0.0.1:1"]),
                .init(status: 403, replacing: ["host": "127.0.0.1"]),
                .init(status: 403, replacing: ["host": "[::1]:\(fixture.port)"]),
                .init(status: 403, replacing: ["host": "localhost.:\(fixture.port)"]),
                .init(status: 403, extra: [("Host", "127.0.0.1:\(fixture.port)")]),
                .init(status: 404, path: "/"),
                .init(status: 404, path: "/mcp?token=not-accepted-in-URL"),
                .init(status: 404, path: "http://127.0.0.1:\(fixture.port)/mcp"),
                .init(status: 404, path: "/mcp/"),
                .init(status: 405, method: "GET"),
                .init(status: 405, method: "DELETE"),
                .init(status: 405, method: "PUT"),
                .init(status: 405, method: "OPTIONS"),
                .init(status: 405, method: "HEAD"),
            ]
            for (index, test) in cases.enumerated() {
                let reply = try await fixture.send(
                    call, method: test.method, path: test.path, replacing: test.replacing,
                    removing: test.removing, extra: test.extra
                )
                #expect(reply.status == test.status, "Security case \(index)")
                #expect(reply.headers["access-control-allow-origin"] == nil)
                #expect(reply.headers["cache-control"] == "no-store")
                if test.status == 401 {
                    #expect(reply.headers["www-authenticate"] == "Bearer realm=\"OpenlistMCP\"")
                }
                if test.status == 405 { #expect(reply.headers["allow"] == "POST") }
                if test.method == "HEAD" { #expect(reply.body.isEmpty) }
            }
            #expect(await fixture.probe.started.isEmpty)
            let valid = try await fixture.send(call, replacing: [
                "host": "LOCALHOST:\(fixture.port)", "authorization": "bearer \(fixtureToken)",
            ])
            #expect(valid.status == 200)
            #expect(await fixture.probe.started == ["must-not-run"])
        }
    }

    @Test
    func exactMediaTypesProtocolHeadersAndEncodingAreValidated() async throws {
        try await withFixture { fixture in
            let call = try callBody(text: "must-not-run")
            let cases: [(Int, [String: String])] = [
                (406, ["accept": ""]),
                (406, ["accept": "application/json"]),
                (406, ["accept": "text/event-stream"]),
                (406, ["accept": "*/*"]),
                (406, ["accept": "application/json-bogus, text/event-stream"]),
                (406, ["accept": "application/json, text/event-stream-bogus"]),
                (406, ["accept": "application/json;q=0, text/event-stream"]),
                (406, ["accept": "application/json, text/event-stream;q=0"]),
                (406, ["accept": "application/json;q=nan, text/event-stream"]),
                (415, ["content-type": "text/plain"]),
                (415, ["content-type": "application/json-bogus"]),
                (400, ["mcp-protocol-version": "2099-01-01"]),
                (415, ["content-encoding": "gzip"]),
                (417, ["expect": "100-continue"]),
            ]
            for (status, headers) in cases {
                #expect(try await fixture.send(call, replacing: headers).status == status)
            }
            #expect(try await fixture.send(call, removing: ["content-type"]).status == 415)
            #expect(try await fixture.send(call, removing: ["accept"]).status == 406)
            #expect(try await fixture.send(call, extra: [
                ("Content-Type", "application/json"),
            ]).status == 400)
            #expect(try await fixture.send(call, extra: [
                ("MCP-Protocol-Version", "2025-11-25"),
            ]).status == 400)
            #expect(await fixture.probe.started.isEmpty)

            let valid = try await fixture.send(call, replacing: [
                "accept": "Application/JSON;q=0.5, Text/Event-Stream",
                "content-type": "Application/JSON; charset=utf-8",
            ])
            #expect(valid.status == 200)
            #expect(valid.headers["content-type"] == "application/json")
            #expect(valid.headers["connection"] == "close")
            #expect(valid.headers["content-length"] == String(valid.body.count))
            #expect(try await fixture.send(replacing: ["accept": "application/json"],
                                          extra: [("Accept", "text/event-stream")]).status == 200)
        }
    }

    @Test
    func SDKNegotiatesCurrentAndOlderVersions() async throws {
        try await withFixture { fixture in
            for version in Version.supported.sorted() {
                let response = try await fixture.send(
                    initializeBody(version: version), removing: ["mcp-protocol-version"]
                )
                #expect(response.status == 200)
                #expect(try response.result()["protocolVersion"] == .string(version))
                #expect(try await fixture.send(replacing: ["mcp-protocol-version": version]).status == 200)
            }
            let fallback = try await fixture.send(
                initializeBody(version: "unknown"), replacing: ["mcp-protocol-version": "unknown"]
            )
            #expect(try fallback.result()["protocolVersion"] == .string("2025-11-25"))
            #expect(try await fixture.send(removing: ["mcp-protocol-version"]).status == 200)
        }
    }

    @Test
    func malformedPacketsDoNotDispatchOrDamageTheListener() async throws {
        try await withFixture { fixture in
            let invalidBodies = [
                "", "{", "null", "[]",
                #"[{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo"}}]"#,
                #"{"id":1,"method":"tools/call","params":{"name":"echo"}}"#,
                #"{"jsonrpc":"1.0","id":1,"method":"tools/call","params":{"name":"echo"}}"#,
                #"{"jsonrpc":"2.0","id":true,"method":"tools/call","params":{"name":"echo"}}"#,
                #"{"jsonrpc":"2.0","id":null,"method":"tools/call","params":{"name":"echo"}}"#,
                #"{"jsonrpc":"2.0","id":1.5,"method":"tools/call","params":{"name":"echo"}}"#,
                #"{"jsonrpc":"2.0","id":1e100,"method":"tools/call","params":{"name":"echo"}}"#,
                #"{"jsonrpc":"2.0","id":1,"method":3}"#,
                #"{"jsonrpc":"2.0","id":1,"method":"tools/call","result":{},"params":{"name":"echo"}}"#,
                #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":null}"#,
                #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":[]}"#,
                #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":"invalid"}"#,
                #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo","arguments":null}}"#,
                #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo","arguments":[]}}"#,
                #"{"jsonrpc":"2.0","method":"tools/call","params":{"name":"echo"}}"#,
            ]
            for (index, body) in invalidBodies.enumerated() {
                let response = try await fixture.send(body)
                #expect(response.status == 400, "Malformed case \(index)")
                #expect(try response.json()["error"] != nil)
            }
            #expect(await fixture.probe.started.isEmpty)
            #expect(try await fixture.send().status == 200)

            for body in [
                #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{}}"#,
                #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"not-in-catalog"}}"#,
            ] {
                let response = try await fixture.send(body)
                #expect(response.status == 200)
                #expect(try response.errorCode() == -32602)
            }
            let unknown = try await fixture.send(#"{"jsonrpc":"2.0","id":"opaque-id","method":"resources/list"}"#)
            #expect(unknown.status == 200)
            #expect(try unknown.json()["id"] == .string("opaque-id"))
            #expect(try unknown.errorCode() == -32601)
            #expect(await fixture.probe.started.isEmpty)
        }
    }

    @Test
    func malformedHTTPAndExcessiveJSONDepthAreRejected() async throws {
        try await withFixture { fixture in
            let connection = try await fixture.socket()
            try await connection.write(Data("POST /mcp HTTP/1.1\r\nInvalid Header\r\n\r\n".utf8))
            #expect(try await connection.response().status == 400)
            let earlyAuthentication = try await fixture.send(
                "", replacing: ["content-length": "1048576"], removing: ["authorization"]
            )
            #expect(earlyAuthentication.status == 401)
            let deepValue = String(repeating: "[", count: 70) + "0" + String(repeating: "]", count: 70)
            let deepCall = """
                {"jsonrpc":"2.0","id":1,"method":"tools/call",\
                "params":{"name":"echo","arguments":{"text":\(deepValue)}}}
                """
            #expect(try await fixture.send(deepCall).status == 400)
            #expect(await fixture.probe.started.isEmpty)
            #expect(try await fixture.send().status == 200)
        }
    }

    @Test
    func notificationsHaveNoResponseBody() async throws {
        try await withFixture { fixture in
            for body in [
                #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
                #"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":1}}"#,
                #"{"jsonrpc":"2.0","method":"notifications/not-supported"}"#,
                #"{"jsonrpc":"2.0","id":1,"result":{}}"#,
            ] {
                let response = try await fixture.send(body)
                #expect(response.status == 202)
                #expect(response.body.isEmpty)
                #expect(response.headers["content-length"] == "0")
            }
            #expect(await fixture.probe.started.isEmpty)
        }
    }

    @Test
    func toolErrorsAndUnexpectedErrorsAreDistinct() async throws {
        try await withFixture { fixture in
            let expected = try await fixture.send(callBody(text: "expected-tool-error"))
            #expect(expected.status == 200)
            #expect(try expected.result()["isError"] == .bool(true))
            let unexpected = try await fixture.send(callBody(text: "throw-private-error"))
            #expect(unexpected.status == 200)
            #expect(try unexpected.errorCode() == -32603)
            let payload = String(decoding: unexpected.body, as: UTF8.self)
            #expect(payload.contains("Tool execution failed"))
            #expect(!payload.contains("privateAdapterFailure"))
            #expect(!payload.contains("throw-private-error"))
            #expect(!payload.contains(fixtureToken))
        }
    }

    @Test
    func bodyAndHeaderLimitsAreEnforcedByTheListener() async throws {
        try await withFixture { fixture in
            let declared = try await fixture.send("", replacing: ["content-length": "1048577"])
            #expect(declared.status == 413)
            let call = try callBody(text: "exact-boundary")
            let padded = call + String(repeating: " ", count: 1024 * 1024 - call.utf8.count)
            #expect(try await fixture.send(padded).status == 200)
            #expect(try await fixture.send(extra: [
                ("X-Large", String(repeating: "a", count: 8193)),
            ]).status == 431)
            #expect(try await fixture.send(extra: (0..<70).map {
                ("X-Header-\($0)", "a")
            }).status == 431)
            #expect(try await fixture.send(extra: (0..<32).map {
                ("X-Header-\($0)", String(repeating: "a", count: 520))
            }).status == 431)
            #expect(try await fixture.send(path: "/" + String(repeating: "a", count: 8193)).status == 431)
            #expect(await fixture.probe.started == ["exact-boundary"])
            #expect(try await fixture.send().status == 200)
        }
    }

    @Test
    func chunkedBodiesAndTrailersCannotBypassLimitsOrAuthentication() async throws {
        var limits = TransportLimits()
        limits.bodyBytes = 256
        try await withFixture(limits: limits) { fixture in
            let valid = pingBody
            let chunked = "\(String(valid.utf8.count, radix: 16))\r\n\(valid)\r\n0\r\n\r\n"
            let validResponse = try await fixture.send(
                chunked, replacing: ["transfer-encoding": "chunked"], removing: ["content-length"]
            )
            #expect(validResponse.status == 200)
            let large = "101\r\n" + String(repeating: " ", count: 257) + "\r\n0\r\n\r\n"
            let largeResponse = try await fixture.send(
                large, replacing: ["transfer-encoding": "chunked"], removing: ["content-length"]
            )
            #expect(largeResponse.status == 413)
            let trailers = "\(String(valid.utf8.count, radix: 16))\r\n\(valid)\r\n0\r\nX-Trailer: a\r\n\r\n"
            let trailerResponse = try await fixture.send(
                trailers, replacing: ["transfer-encoding": "chunked"], removing: ["content-length"]
            )
            #expect(trailerResponse.status == 400)
            let ambiguousResponse = try await fixture.send(
                chunked, replacing: ["transfer-encoding": "chunked"]
            )
            #expect(ambiguousResponse.status == 400)
            #expect(await fixture.probe.started.isEmpty)
        }
    }

    @Test
    func pipeliningCannotQueueMoreSDKWork() async throws {
        try await withFixture { fixture in
            let connection = try await fixture.socket()
            var bytes = fixture.requestBytes(
                try callBody(text: "first", delay: 50), replacing: ["connection": "keep-alive"]
            )
            bytes.append(fixture.requestBytes(try callBody(text: "must-not-run")))
            try await connection.write(bytes)
            let reply = try await connection.response()
            #expect(reply.status == 200)
            #expect(try reply.result()["structuredContent"] == .object(["echo": .string("first")]))
            #expect(await fixture.probe.started == ["first"])
        }
    }

    @Test
    func idlePartialAndExecutingRequestsHaveDeadlines() async throws {
        var limits = TransportLimits()
        limits.readTimeout = .milliseconds(250)
        limits.requestTimeout = .milliseconds(250)
        try await withFixture(limits: limits) { fixture in
            let idle = try await fixture.socket()
            #expect(try await idle.response().status == 408)
            let partial = try await fixture.socket()
            try await partial.write(Data("POST /mcp HTTP/1.1\r\nHost: ".utf8))
            #expect(try await partial.response().status == 408)
            let body = try await fixture.send("{", replacing: ["content-length": "10"])
            #expect(body.status == 408)
            #expect(await fixture.probe.started.isEmpty)
            let executing = try await fixture.send(callBody(text: "timeout", delay: 60_000))
            #expect(executing.status == 504)
            try await eventually { await fixture.probe.cancelled == ["timeout"] }
            #expect(try await fixture.send().status == 200)
        }
    }

    @Test
    func connectionAndRequestAdmissionAreBounded() async throws {
        var limits = TransportLimits()
        limits.connections = 3
        limits.requests = 1
        try await withFixture(limits: limits) { fixture in
            let busy = try await fixture.socket()
            try await busy.write(fixture.requestBytes(try callBody(text: "busy", delay: 60_000)))
            try await eventually { await fixture.probe.started.count == 1 }
            let rejected = try await fixture.send()
            #expect(rejected.status == 503)
            #expect(rejected.headers["retry-after"] == "1")

            let firstIdle = try await fixture.socket()
            let secondIdle = try await fixture.socket()
            try await eventually { await fixture.server.activeConnections == 3 }
            let overflow = try await fixture.socket()
            #expect(try await overflow.bytesOnClose().isEmpty)
            #expect(await fixture.server.activeConnections == 3)
            await firstIdle.close()
            await secondIdle.close()
            await busy.close()
            try await eventually { await fixture.probe.cancelled == ["busy"] }
            try await eventually { await fixture.server.activeConnections == 0 }
            #expect(try await fixture.send().status == 200)
        }
    }

    @Test
    func timedOutAdapterRetainsItsAdmissionSlotUntilItActuallyFinishes() async throws {
        var limits = TransportLimits()
        limits.requests = 1
        limits.requestTimeout = .milliseconds(200)
        try await withFixture(limits: limits) { fixture in
            let response = try await fixture.send(callBody(text: "hold-until-released"))
            #expect(response.status == 504)
            #expect(try await fixture.send().status == 503)
            #expect(await fixture.probe.completed.isEmpty)
            await fixture.probe.releaseSuspendedCall()
            try await eventually { await fixture.probe.cancelled == ["hold-until-released"] }
            #expect(try await fixture.send().status == 200)
        }
    }

    @Test
    func stopClosesIdleAndInFlightConnectionsAndReleasesThePort() async throws {
        try await withFixture { fixture in
            let idle = try await fixture.socket()
            let busy = try await fixture.socket()
            try await busy.write(fixture.requestBytes(try callBody(text: "stop", delay: 60_000)))
            try await eventually { await fixture.probe.started == ["stop"] }
            await fixture.server.stop()
            await fixture.server.stop()
            #expect(try await idle.bytesOnClose().isEmpty)
            #expect(try await busy.bytesOnClose().isEmpty)
            try await eventually { await fixture.probe.cancelled == ["stop"] }

            let replacement = LocalMCPServer(
                port: fixture.port, token: fixtureToken, tools: fixtureTools, version: "replacement",
                callTool: { try await fixture.probe.call($0, arguments: $1) }
            )
            do {
                #expect(try await replacement.start() == fixture.port)
                #expect(try await replacement.start() == fixture.port)
                #expect(try await fixture.send().status == 200)
                await replacement.stop()
                #expect(try await replacement.start() == fixture.port)
                #expect(try await fixture.send().status == 200)
                await replacement.stop()
            } catch {
                await replacement.stop()
                throw error
            }
        }
    }

    @Test
    func failedBindAndConcurrentLifecycleCallsLeaveNoOrphanListener() async throws {
        try await withFixture { fixture in
            let server = LocalMCPServer(
                port: fixture.port, token: fixtureToken, tools: fixtureTools, version: "lifecycle",
                callTool: { try await fixture.probe.call($0, arguments: $1) }
            )
            do {
                await #expect(throws: (any Error).self) { try await server.start() }
                await server.stop()
                #expect(try await fixture.send().status == 200)
                await fixture.server.stop()

                for _ in 0..<10 {
                    let start = Task { try await server.start() }
                    await Task.yield()
                    async let stop: Void = server.stop()
                    _ = await start.result
                    await stop
                    await server.stop()
                }
                let ports = try await withThrowingTaskGroup(of: UInt16.self) { group in
                    for _ in 0..<8 { group.addTask { try await server.start() } }
                    var ports: [UInt16] = []
                    for try await port in group { ports.append(port) }
                    return ports
                }
                #expect(ports.count == 8)
                #expect(ports.allSatisfy { $0 == fixture.port })
                #expect(try await fixture.send().status == 200)
                await server.stop()
            } catch {
                await server.stop()
                throw error
            }
        }
    }

    @Test
    func invalidConfigurationCannotOpenAListener() async throws {
        for token in ["", "contains a space", "line\r\nbreak", "nonASCII-é"] {
            let server = LocalMCPServer(
                port: 0, token: token, tools: fixtureTools, version: "fixture",
                callTool: { _, _ in .init() }
            )
            await #expect(throws: LocalMCPServerError.invalidToken) { try await server.start() }
            await server.stop()
        }
        let server = LocalMCPServer(
            port: 0, token: fixtureToken, tools: fixtureTools + fixtureTools, version: "fixture",
            callTool: { _, _ in .init() }
        )
        await #expect(throws: LocalMCPServerError.invalidToolCatalog) { try await server.start() }
        await server.stop()
        #expect(RequestValidation.constantTimeEqual(Array("same".utf8), Array("same".utf8)))
        #expect(!RequestValidation.constantTimeEqual(Array("same".utf8), Array("sand".utf8)))
        #expect(!RequestValidation.constantTimeEqual(Array("same".utf8), Array("same-longer".utf8)))
    }

    @Test
    func excessivelyLargeToolResponsesAreNotBufferedToTheSocket() async throws {
        var limits = TransportLimits()
        limits.responseBytes = 512
        try await withFixture(limits: limits) { fixture in
            let response = try await fixture.send(callBody(text: String(repeating: "x", count: 1024)))
            #expect(response.status == 500)
            #expect(response.body.count < 512)
            #expect(try response.errorCode() == -32603)
        }
    }
}
