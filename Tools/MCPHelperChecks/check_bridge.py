"""Loopback-only protocol and synthetic release checks for the native launcher."""

import gzip
import http.server
import json
import os
from pathlib import Path
import plistlib
import selectors
import shutil
import socket
import subprocess
import sys
import threading
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]
BINARY = Path(sys.argv[1]).resolve()
WORKSPACE = Path(sys.argv[2]).resolve()
TOKEN = "fixture-only-private-token"
PROTOCOL_VERSION = "2025-06-18"
MAX_INPUT = 1_048_576
MAX_RESPONSE = 4_194_304
sys.argv = [sys.argv[0]]


def encoded(value):
    return json.dumps(value, separators=(",", ":")).encode()


def request(method="tools/list", identifier=1, params=None):
    value = {"jsonrpc": "2.0", "id": identifier, "method": method}
    if params is not None:
        value["params"] = params
    return value


def environment(url=None):
    result = os.environ.copy()
    result.pop("OPENLIST_MCP_URL", None)
    result.pop("OPENLIST_MCP_TOKEN", None)
    result["OPENLIST_MCP_TOKEN"] = TOKEN
    if url is not None:
        result["OPENLIST_MCP_URL"] = url
    return result


class Reply:
    def __init__(
        self, status=200, body=b"", content_type="application/json",
        headers=None, declared_length=None, close_delimited=False,
    ):
        self.status = status
        self.body = body
        self.content_type = content_type
        self.headers = headers or {}
        self.declared_length = declared_length
        self.close_delimited = close_delimited


class QuietServer(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def handle_error(self, request, client_address):
        # Bounded-response tests deliberately disconnect while the fixture writes.
        pass


class LocalServer:
    def __init__(self, respond=None):
        self.requests = []
        self.lock = threading.Lock()
        self.respond = respond or self.standard_response
        fixture = self

        class Handler(http.server.BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, format, *args):
                pass

            def do_POST(self):
                self.reply()

            def do_GET(self):
                self.reply()

            def reply(self):
                size = int(self.headers.get("Content-Length", "0"))
                data = self.rfile.read(size) if size else b""
                record = {
                    "method": self.command,
                    "path": self.path,
                    "headers": {key.lower(): value for key, value in self.headers.items()},
                    "data": data,
                }
                with fixture.lock:
                    fixture.requests.append(record)
                response = fixture.respond(record)
                self.send_response(response.status)
                if response.content_type:
                    self.send_header("Content-Type", response.content_type)
                if not response.close_delimited:
                    length = response.declared_length
                    self.send_header("Content-Length", str(len(response.body) if length is None else length))
                self.send_header("Connection", "close")
                for key, value in response.headers.items():
                    self.send_header(key, value)
                self.end_headers()
                try:
                    for start in range(0, len(response.body), 65_536):
                        self.wfile.write(response.body[start:start + 65_536])
                except (BrokenPipeError, ConnectionResetError):
                    pass
                self.close_connection = True

        self.server = QuietServer(("127.0.0.1", 0), Handler)
        self.port = self.server.server_port
        self.url = "http://127.0.0.1:{}/mcp".format(self.port)
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *args):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    @staticmethod
    def standard_response(record):
        if record["headers"].get("authorization") != "Bearer " + TOKEN:
            return Reply(401, TOKEN.encode())
        message = json.loads(record["data"])
        if "id" not in message:
            return Reply(202, content_type=None)
        if message["method"] == "initialize":
            result = {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "fixture", "version": "1"},
            }
        elif message["method"] == "tools/call":
            result = {"content": [{"type": "text", "text": "fixture\nresult"}]}
        else:
            result = {"tools": []}
        # The bridge must compact a multiline HTTP body to a single stdout line.
        body = json.dumps({"jsonrpc": "2.0", "id": message["id"], "result": result}, indent=2).encode()
        return Reply(body=body, content_type="application/json; charset=utf-8")


class BridgeChecks(unittest.TestCase):
    def run_helper(self, data=b"", url=None, env=None, arguments=(), timeout=6):
        return subprocess.run(
            [str(BINARY), *arguments], input=data, capture_output=True,
            env=environment(url) if env is None else env, timeout=timeout,
        )

    def assert_failure(self, result, diagnostic=None):
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")
        self.assertIn(b"openlist-mcp:", result.stderr)
        self.assertIn(b"Open Openlist > Settings > AI Agents", result.stderr)
        self.assertNotIn(TOKEN.encode(), result.stderr)
        if diagnostic:
            self.assertIn(diagnostic, result.stderr)

    def test_help_is_offline_and_ignores_configuration(self):
        env = environment("not-a-url")
        env.pop("OPENLIST_MCP_TOKEN")
        result = self.run_helper(env=env, arguments=("--help",))
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stderr, b"")
        self.assertIn(b"Usage: openlist-mcp [--help]", result.stdout)
        self.assertIn(b"http://127.0.0.1:45873/mcp", result.stdout)
        self.assertIn(b"OPENLIST_MCP_TOKEN", result.stdout)
        self.assertNotIn(TOKEN.encode(), result.stdout)

    def test_unsupported_arguments_are_not_silently_ignored(self):
        for arguments in [("--unknown",), ("--help", "extra"), ("--version",), ("-h",)]:
            with self.subTest(arguments=arguments):
                self.assert_failure(self.run_helper(arguments=arguments), b"Unsupported arguments")

    def test_invalid_urls_are_rejected_before_network_access(self):
        urls = [
            "", "https://127.0.0.1:45873/mcp", "http://example.com:45873/mcp",
            "http://127.0.0.2:45873/mcp", "http://localhost/mcp",
            "http://127.0.0.1/mcp", "http://localhost:0/mcp",
            "http://localhost:65536/mcp", "http://localhost:-1/mcp",
            "http://localhost:999999999999999999999999999999/mcp",
            "http://localhost:word/mcp", "http://localhost:45873/",
            "http://localhost:45873/mcp/", "http://localhost:45873/%6dcp",
            "http://localhost:45873/mcp?token=hidden", "http://localhost:45873/mcp?",
            "http://localhost:45873/mcp#fragment", "http://localhost:45873/mcp#",
            "http://user@localhost:45873/mcp", "http://user:secret@localhost:45873/mcp",
            "http://@localhost:45873/mcp", "http://[::1]:45873/mcp",
            "file:///mcp", "http://%6cocalhost:45873/mcp",
            "http://localhost.:45873/mcp", " http://localhost:45873/mcp",
            "http://localhost:45873/mcp\n", "http://localhost:45873/mcp\r\nOther: value",
        ]
        for url in urls:
            with self.subTest(url=url):
                self.assert_failure(self.run_helper(env=environment(url)), b"Invalid OPENLIST_MCP_URL")

    def test_token_is_required_and_header_safe(self):
        for value in [None, "", "has space", "tab\tvalue", "line\nvalue", "line\rvalue", "value\x7f", "café", "a" * 4097]:
            with self.subTest(kind="missing" if value is None else "invalid"):
                env = environment()
                if value is None:
                    env.pop("OPENLIST_MCP_TOKEN")
                else:
                    env["OPENLIST_MCP_TOKEN"] = value
                self.assert_failure(self.run_helper(env=env), b"OPENLIST_MCP_TOKEN is required")

    def test_initialize_tools_notifications_and_clean_eof(self):
        messages = [
            request("initialize", "init", {
                "protocolVersion": PROTOCOL_VERSION, "capabilities": {},
                "clientInfo": {"name": "checks", "version": "1"},
            }),
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            request("tools/list", 2),
            request("tools/call", "call", {"name": "fixture_tool", "arguments": {"title": "fixture"}}),
        ]
        with LocalServer() as server:
            result = self.run_helper(
                b"\n \t\r\n" + b"\r\n".join(encoded(message) for message in messages),
                url=server.url,
            )
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stderr, b"")
            self.assertNotIn(TOKEN.encode(), result.stdout)
            lines = result.stdout.splitlines()
            self.assertEqual(len(lines), 3)
            responses = [json.loads(line) for line in lines]
            self.assertEqual([value["id"] for value in responses], ["init", 2, "call"])
            self.assertEqual(responses[0]["result"]["protocolVersion"], PROTOCOL_VERSION)
            self.assertEqual(responses[2]["result"]["content"][0]["text"], "fixture\nresult")
            self.assertEqual(len(server.requests), len(messages))
            for index, record in enumerate(server.requests):
                self.assertEqual(record["method"], "POST")
                self.assertEqual(record["path"], "/mcp")
                self.assertEqual(json.loads(record["data"]), messages[index])
                headers = record["headers"]
                self.assertTrue(headers.get("authorization") == "Bearer " + TOKEN, "Bearer header was not preserved")
                self.assertEqual(headers.get("content-type"), "application/json")
                self.assertEqual(headers.get("accept"), "application/json, text/event-stream")
                self.assertNotIn("cookie", headers)
                self.assertNotIn("mcp-session-id", headers)
                self.assertEqual(headers.get("mcp-protocol-version"), None if index == 0 else PROTOCOL_VERSION)

    def test_interactive_response_does_not_wait_for_stdin_eof(self):
        with LocalServer() as server:
            process = subprocess.Popen(
                [str(BINARY)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, env=environment(server.url),
            )
            try:
                process.stdin.write(encoded(request()) + b"\n")
                process.stdin.flush()
                line = bytearray()
                deadline = time.monotonic() + 5
                with selectors.DefaultSelector() as selector:
                    selector.register(process.stdout, selectors.EVENT_READ)
                    while b"\n" not in line:
                        remaining = deadline - time.monotonic()
                        self.assertGreater(remaining, 0, "No response while stdin remained open")
                        self.assertTrue(selector.select(remaining), "No response while stdin remained open")
                        chunk = os.read(process.stdout.fileno(), 16_384)
                        self.assertTrue(chunk, "Helper exited before responding")
                        line.extend(chunk)
                self.assertEqual(json.loads(line)["id"], 1)
                self.assertIsNone(process.poll(), "Helper should wait for the next input message")
                stdout, stderr = process.communicate(timeout=5)
                self.assertEqual(process.returncode, 0)
                self.assertEqual(stdout, b"")
                self.assertEqual(stderr, b"")
            finally:
                if process.poll() is None:
                    process.kill()
                process.communicate()

    def test_localhost_is_pinned_to_ipv4_loopback(self):
        with LocalServer() as server:
            result = self.run_helper(encoded(request()) + b"\n", url="http://localhost:{}/mcp".format(server.port))
            self.assertEqual(result.returncode, 0)
            self.assertEqual(server.requests[0]["headers"]["host"], "127.0.0.1:{}".format(server.port))

    def test_notifications_print_nothing(self):
        with LocalServer() as server:
            message = {"jsonrpc": "2.0", "method": "notifications/initialized"}
            result = self.run_helper(encoded(message) + b"\n", url=server.url)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout, b"")
            self.assertEqual(result.stderr, b"")
            self.assertEqual(len(server.requests), 1)

    def test_empty_or_blank_input_exits_without_connecting(self):
        for data in [b"", b"\n \t\r\n", (b" " * 1024 + b"\n") * 1025]:
            result = self.run_helper(data)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout, b"")
            self.assertEqual(result.stderr, b"")

    def test_malformed_input_never_reaches_http(self):
        invalid = [
            b"{\n", b"[]\n", b"null\n", b'{"jsonrpc":"1.0","id":1,"method":"tools/list"}\n',
            b'{"jsonrpc":"2.0","id":1}\n', b'{"jsonrpc":"2.0","method":""}\n',
            b'{"jsonrpc":"2.0","id":true,"method":"tools/list"}\n',
            b'{"jsonrpc":"2.0","id":[],"method":"tools/list"}\n',
            b'{"jsonrpc":"2.0","method":"tools/list","params":42}\n', b"\xff\n",
        ]
        with LocalServer() as server:
            for data in invalid:
                with self.subTest(data=data):
                    self.assert_failure(self.run_helper(data, url=server.url), b"Invalid MCP input")
            self.assertEqual(server.requests, [])

    def test_input_limit_is_enforced_before_eof(self):
        process = subprocess.Popen(
            [str(BINARY)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, env=environment(),
        )
        try:
            def write_input():
                try:
                    process.stdin.write(b"x" * (MAX_INPUT + 32_768))
                    process.stdin.flush()
                except BrokenPipeError:
                    pass

            writer = threading.Thread(target=write_input, daemon=True)
            writer.start()
            process.wait(timeout=5)
            writer.join(timeout=2)
            self.assertFalse(writer.is_alive())
            stdout, stderr = process.communicate()
            self.assert_failure(subprocess.CompletedProcess([], process.returncode, stdout, stderr), b"1 MiB")
        finally:
            if process.poll() is None:
                process.kill()
            process.communicate()

    def test_exact_input_limit_is_accepted(self):
        data = encoded(request())
        data += b" " * (MAX_INPUT - len(data))
        with LocalServer() as server:
            result = self.run_helper(data + b"\n", url=server.url)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(len(server.requests[0]["data"]), MAX_INPUT)

    def test_http_errors_are_actionable_and_not_retried(self):
        for status in [400, 401, 403, 404, 405, 409, 413, 429, 500, 503]:
            with self.subTest(status=status):
                with LocalServer(lambda record: Reply(status, TOKEN.encode())) as server:
                    result = self.run_helper(encoded(request("tools/call")) + b"\n", url=server.url)
                    self.assert_failure(result, str(status).encode())
                    self.assertEqual(len(server.requests), 1, "An explicit HTTP failure must not retry a tool call")

    def test_wrong_token_and_http_auth_challenges_do_not_prompt(self):
        with LocalServer() as server:
            env = environment(server.url)
            env["OPENLIST_MCP_TOKEN"] = "wrong-fixture-secret"
            result = self.run_helper(encoded(request()) + b"\n", env=env)
            self.assert_failure(result, b"authentication")
            self.assertNotIn(b"wrong-fixture-secret", result.stderr)
            self.assertEqual(len(server.requests), 1)
        with LocalServer(lambda record: Reply(401, headers={"WWW-Authenticate": 'Basic realm="fixture"'})) as server:
            self.assert_failure(self.run_helper(encoded(request()) + b"\n", url=server.url), b"authentication")
            self.assertEqual(len(server.requests), 1)

    def test_redirects_never_forward_credentials_or_requests(self):
        with LocalServer() as destination:
            for status in [301, 302, 303, 307, 308]:
                with self.subTest(status=status):
                    with LocalServer(lambda record: Reply(status, headers={"Location": destination.url})) as server:
                        result = self.run_helper(encoded(request("tools/call")) + b"\n", url=server.url)
                        self.assert_failure(result, b"redirect")
                        self.assertEqual(len(server.requests), 1)
            self.assertEqual(destination.requests, [], "Redirect target must receive no request or credentials")

    def test_unavailable_server_does_not_start_the_app(self):
        with socket.socket() as reserved:
            reserved.bind(("127.0.0.1", 0))
            url = "http://127.0.0.1:{}/mcp".format(reserved.getsockname()[1])
            self.assert_failure(self.run_helper(encoded(request()) + b"\n", url=url, timeout=45))

    def test_unexpected_content_type_is_rejected(self):
        for content_type in ["text/event-stream", "text/plain", None]:
            with self.subTest(content_type=content_type):
                body = encoded({"jsonrpc": "2.0", "id": 1, "result": {}})
                with LocalServer(lambda record: Reply(body=body, content_type=content_type)) as server:
                    self.assert_failure(self.run_helper(encoded(request()) + b"\n", url=server.url), b"response type")

    def test_response_size_is_bounded_with_and_without_content_length(self):
        responses = [
            Reply(declared_length=MAX_RESPONSE + 1),
            Reply(body=b"x" * (MAX_RESPONSE + 1), close_delimited=True),
            Reply(body=gzip.compress(b"x" * (MAX_RESPONSE + 1)), headers={"Content-Encoding": "gzip"}),
        ]
        for response in responses:
            with self.subTest(kind="streamed" if response.close_delimited else "declared-or-decoded"):
                with LocalServer(lambda record: response) as server:
                    self.assert_failure(self.run_helper(encoded(request()) + b"\n", url=server.url), b"4 MiB")

    def test_malformed_or_mismatched_responses_are_not_written_to_stdout(self):
        bodies = [
            b"", b"{", b"[]", b"\xff",
            encoded({"jsonrpc": "2.0", "result": {}}),
            encoded({"jsonrpc": "2.0", "id": 2, "result": {}}),
            encoded({"jsonrpc": "2.0", "id": True, "result": {}}),
            encoded({"jsonrpc": "1.0", "id": 1, "result": {}}),
            encoded({"jsonrpc": "2.0", "id": 1, "result": {}, "error": {}}),
            encoded({"jsonrpc": "2.0", "id": 1, "error": {"code": True, "message": TOKEN}}),
            encoded({"jsonrpc": "2.0", "id": 1, "error": {"code": 1.5, "message": TOKEN}}),
            encoded({"jsonrpc": "2.0", "id": 1, "error": None}),
        ]
        for body in bodies:
            with self.subTest(kind="invalid-response"):
                with LocalServer(lambda record: Reply(body=body)) as server:
                    self.assert_failure(self.run_helper(encoded(request()) + b"\n", url=server.url), b"invalid")

    def test_invalid_negotiated_versions_cannot_inject_headers(self):
        for version in [None, "", "unknown", "2025-06-18\r\nAuthorization: leaked"]:
            with self.subTest(kind="invalid-version"):
                body = encoded({"jsonrpc": "2.0", "id": 1, "result": {"protocolVersion": version}})
                with LocalServer(lambda record: Reply(body=body)) as server:
                    self.assert_failure(self.run_helper(encoded(request("initialize")) + b"\n", url=server.url), b"protocol version")

    def test_json_rpc_errors_and_null_ids_are_preserved(self):
        for identifier in [1, "string-id", None]:
            with self.subTest(identifier=identifier):
                body = {"jsonrpc": "2.0", "id": identifier, "error": {"code": -32602, "message": "fixture denial"}}
                with LocalServer(lambda record: Reply(body=encoded(body))) as server:
                    result = self.run_helper(encoded(request(identifier=identifier)) + b"\n", url=server.url)
                    self.assertEqual(result.returncode, 0)
                    self.assertEqual(result.stderr, b"")
                    self.assertEqual(json.loads(result.stdout), body)

    def test_request_202_and_notification_bodies_are_errors(self):
        message = {"jsonrpc": "2.0", "method": "notifications/initialized"}
        cases = [
            (request(), Reply(202, content_type=None)),
            (message, Reply(200, body=encoded({"jsonrpc": "2.0", "id": 1, "result": {}}))),
            (message, Reply(202, body=b"not empty")),
            (message, Reply(202, body=b"not empty", close_delimited=True)),
        ]
        for value, response in cases:
            with self.subTest(status=response.status):
                with LocalServer(lambda record: response) as server:
                    self.assert_failure(self.run_helper(encoded(value) + b"\n", url=server.url))

    def test_disconnected_stdout_is_an_error_not_a_sigpipe_crash(self):
        with LocalServer() as server:
            process = subprocess.Popen(
                [str(BINARY)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, env=environment(server.url),
            )
            process.stdout.close()
            process.stdout = None
            try:
                _, stderr = process.communicate(encoded(request()) + b"\n", timeout=5)
                self.assertEqual(process.returncode, 1)
                self.assertIn(b"stdout", stderr)
                self.assertNotIn(TOKEN.encode(), stderr)
            finally:
                if process.poll() is None:
                    process.kill()
                process.communicate()


class PackagingChecks(unittest.TestCase):
    def setUp(self):
        self.fixture = WORKSPACE / self._testMethodName
        self.fixture.mkdir()
        self.app = self.fixture / "Openlist fixture.app"
        for bundle, name, identifier in [
            (self.app, "openlist", "solimanali.openlist"),
            (self.app / "Contents/PlugIns/OpenlistWidget.appex", "OpenlistWidget", "solimanali.openlist.OpenlistWidget"),
        ]:
            (bundle / "Contents/MacOS").mkdir(parents=True)
            shutil.copy2(BINARY, bundle / "Contents/MacOS" / name)
            with (bundle / "Contents/Info.plist").open("wb") as output:
                plistlib.dump({
                    "CFBundleExecutable": name, "CFBundleIdentifier": identifier,
                    "CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "7",
                    "LSMinimumSystemVersion": "27.0",
                    **({"UTExportedTypeDeclarations": [
                        {"UTTypeIdentifier": "app.openlist.block-drag", "UTTypeConformsTo": ["public.data"]},
                        {"UTTypeIdentifier": "app.openlist.inbox-order", "UTTypeConformsTo": ["public.data"]},
                        {"UTTypeIdentifier": "solimanali.openlist.library-backup", "UTTypeConformsTo": ["com.apple.package"]},
                    ]} if bundle == self.app else {}),
                    **({"CFBundleURLTypes": [{"CFBundleTypeRole": "Viewer", "CFBundleURLName": "solimanali.openlist.item", "CFBundleURLSchemes": ["openlist"]}]} if bundle == self.app else {}),
                }, output)
        self.helper = self.app / "Contents/MacOS/openlist-mcp"
        shutil.copy2(BINARY, self.helper)
        self.notices = self.app / "Contents/Resources/ThirdPartyNotices.txt"
        self.notices.parent.mkdir()
        self.notices.write_text("Synthetic dependency notices for isolated release checks.\n")

    def tearDown(self):
        shutil.rmtree(self.fixture)

    @staticmethod
    def verifier_shells():
        shells = [None, "/bin/bash"]
        path_bash = shutil.which("bash")
        if path_bash and not os.path.samefile(path_bash, "/bin/bash"):
            shells.append(path_bash)
        return shells

    def verify(self, shell=None, extra_env=None):
        command = [str(ROOT / "Tools/verify-release.sh"), str(self.app), "1.2.3", "7"]
        env = environment("invalid-help-must-ignore-this")
        if shell:
            command.insert(0, shell)
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            command, capture_output=True, timeout=8, env=env,
        )

    def test_valid_embedded_layout_and_offline_help(self):
        for shell in self.verifier_shells():
            with self.subTest(shell=shell or "shebang"):
                result = self.verify(shell)
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                self.assertIn(b"Verified native arm64 MCP helper and offline --help", result.stdout)
                self.assertIn(b"Verified bundled dependency notices", result.stdout)
                self.assertNotIn(TOKEN.encode(), result.stdout + result.stderr)

    def assert_invalid_bundle(self, result, bundle, diagnostic):
        self.assertEqual(result.returncode, 1, result.stderr.decode())
        self.assertIn(b"Invalid release bundle", result.stderr)
        self.assertIn(str(bundle).encode(), result.stderr)
        self.assertIn(diagnostic.encode(), result.stderr)
        self.assertNotIn(
            f"Verified arm64, version 1.2.3 (7), macOS 27.0: {bundle}\n".encode(),
            result.stdout,
        )

    def test_missing_dependency_notices_have_clear_diagnostic(self):
        self.notices.unlink()
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"Contents/Resources/ThirdPartyNotices.txt", result.stderr)

    def test_item_links_never_register_development_or_extra_schemes_in_release(self):
        path = self.app / "Contents/Info.plist"
        original = plistlib.loads(path.read_bytes())
        for schemes in ([], ["openlist-dev"], ["openlist", "openlist-dev"], ["openlist", "https"]):
            with self.subTest(schemes=schemes):
                info = dict(original)
                info["CFBundleURLTypes"] = [{"CFBundleTypeRole": "Viewer", "CFBundleURLName": "solimanali.openlist.item", "CFBundleURLSchemes": schemes}]
                path.write_bytes(plistlib.dumps(info))
                for shell in self.verifier_shells():
                    self.assert_invalid_bundle(self.verify(shell), self.app, "item-link registration")

    def test_empty_dependency_notices_are_rejected(self):
        self.notices.write_text("")
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"nonempty bundled dependency notices", result.stderr)

    def test_dependency_notices_must_be_embedded_not_symlinked(self):
        self.notices.unlink()
        self.notices.symlink_to(BINARY)
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"Contents/Resources/ThirdPartyNotices.txt", result.stderr)

    def test_missing_helper_has_clear_diagnostic(self):
        self.helper.unlink()
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"Invalid release MCP helper", result.stderr)
        self.assertIn(b"Contents/MacOS/openlist-mcp", result.stderr)

    def test_nonexecutable_helper_is_rejected(self):
        self.helper.chmod(0o644)
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"Invalid release MCP helper", result.stderr)

    def test_script_helper_cannot_replace_native_binary(self):
        self.helper.write_text("#!/bin/sh\nexit 0\n")
        self.helper.chmod(0o755)
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"native Mach-O executable", result.stderr)

    def test_symlink_outside_bundle_is_not_an_embedded_helper(self):
        self.helper.unlink()
        self.helper.symlink_to(BINARY)
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"Invalid release MCP helper", result.stderr)

    def test_existing_release_metadata_checks_are_preserved(self):
        for bundle in (self.app, self.app / "Contents/PlugIns/OpenlistWidget.appex"):
            plist = bundle / "Contents/Info.plist"
            original = plistlib.loads(plist.read_bytes())
            for key, value in [
                ("CFBundleShortVersionString", "0.0.0"), ("CFBundleVersion", "1"),
                ("LSMinimumSystemVersion", "25.0"), ("CFBundleIdentifier", "invalid"),
            ]:
                with plist.open("wb") as output:
                    plistlib.dump({**original, key: value}, output)
                for shell in self.verifier_shells():
                    with self.subTest(bundle=bundle.name, key=key, shell=shell or "shebang"):
                        self.assert_invalid_bundle(self.verify(shell), bundle, key)
            plist.write_bytes(plistlib.dumps(original))

    def test_missing_metadata_keys_fail_closed_in_every_shell(self):
        for bundle in (self.app, self.app / "Contents/PlugIns/OpenlistWidget.appex"):
            plist = bundle / "Contents/Info.plist"
            original = plistlib.loads(plist.read_bytes())
            for key in original:
                changed = {name: value for name, value in original.items() if name != key}
                plist.write_bytes(plistlib.dumps(changed))
                for shell in self.verifier_shells():
                    with self.subTest(bundle=bundle.name, key=key, shell=shell or "shebang"):
                        self.assert_invalid_bundle(self.verify(shell), bundle, key)
            plist.write_bytes(plistlib.dumps(original))

    def test_private_drag_type_registration_is_required(self):
        plist = self.app / "Contents/Info.plist"
        original = plistlib.loads(plist.read_bytes())
        exports = original["UTExportedTypeDeclarations"]
        for identifier in ("app.openlist.block-drag", "app.openlist.inbox-order"):
            for defect in ("missing", "text-only", "duplicate"):
                changed = [dict(item) for item in exports if item["UTTypeIdentifier"] != identifier]
                if defect == "text-only":
                    changed.append({"UTTypeIdentifier": identifier, "UTTypeConformsTo": ["public.text"]})
                if defect == "duplicate":
                    changed.extend([{"UTTypeIdentifier": identifier, "UTTypeConformsTo": ["public.data"]}] * 2)
                plist.write_bytes(plistlib.dumps({**original, "UTExportedTypeDeclarations": changed}))
                with self.subTest(identifier=identifier, defect=defect):
                    self.assert_invalid_bundle(self.verify(), self.app, identifier)
        plist.write_bytes(plistlib.dumps(original))

    def test_missing_and_malformed_plists_fail_without_success_output(self):
        for bundle in (self.app, self.app / "Contents/PlugIns/OpenlistWidget.appex"):
            plist = bundle / "Contents/Info.plist"
            original = plist.read_bytes()
            for malformed in (False, True):
                if malformed:
                    plist.write_bytes(b"not a property list")
                else:
                    plist.unlink()
                for shell in self.verifier_shells():
                    with self.subTest(bundle=bundle.name, malformed=malformed, shell=shell or "shebang"):
                        self.assert_invalid_bundle(self.verify(shell), bundle, "Info.plist")
                if not malformed:
                    self.assertFalse(plist.exists(), "Verification must not create missing bundle metadata")
            plist.write_bytes(original)

    def test_review_fixture_marker_is_rejected_in_both_bundles(self):
        for bundle in (self.app, self.app / "Contents/PlugIns/OpenlistWidget.appex"):
            plist = bundle / "Contents/Info.plist"
            original = plistlib.loads(plist.read_bytes())
            for marker in (True, False, ""):
                plist.write_bytes(plistlib.dumps({**original, "OpenlistReviewSession": marker}))
                for shell in self.verifier_shells():
                    with self.subTest(bundle=bundle.name, marker=marker, shell=shell or "shebang"):
                        self.assert_invalid_bundle(self.verify(shell), bundle, "OpenlistReviewSession")
            plist.write_bytes(plistlib.dumps(original))

    def test_development_marker_is_rejected_in_both_bundles(self):
        for bundle in (self.app, self.app / "Contents/PlugIns/OpenlistWidget.appex"):
            plist = bundle / "Contents/Info.plist"
            original = plistlib.loads(plist.read_bytes())
            for marker in (True, False, ""):
                plist.write_bytes(plistlib.dumps({**original, "OpenlistDevelopment": marker}))
                for shell in self.verifier_shells():
                    with self.subTest(bundle=bundle.name, marker=marker, shell=shell or "shebang"):
                        self.assert_invalid_bundle(self.verify(shell), bundle, "OpenlistDevelopment")
            plist.write_bytes(plistlib.dumps(original))

    def test_bundle_metadata_must_not_be_a_symlink(self):
        for bundle in (self.app, self.app / "Contents/PlugIns/OpenlistWidget.appex"):
            plist = bundle / "Contents/Info.plist"
            original = plist.read_bytes()
            outside = self.fixture / "outside-info.plist"
            outside.write_bytes(original)
            plist.unlink()
            plist.symlink_to(outside)
            for shell in self.verifier_shells():
                with self.subTest(bundle=bundle.name, shell=shell or "shebang"):
                    self.assert_invalid_bundle(self.verify(shell), bundle, "Info.plist")
            self.assertEqual(outside.read_bytes(), original)
            plist.unlink()
            plist.write_bytes(original)

    def test_executable_metadata_must_name_an_embedded_file(self):
        for bundle in (self.app, self.app / "Contents/PlugIns/OpenlistWidget.appex"):
            plist = bundle / "Contents/Info.plist"
            original = plistlib.loads(plist.read_bytes())
            for executable in ("", ".", "..", "../openlist-mcp", "/usr/bin/true"):
                plist.write_bytes(plistlib.dumps({**original, "CFBundleExecutable": executable}))
                for shell in self.verifier_shells():
                    with self.subTest(bundle=bundle.name, executable=executable, shell=shell or "shebang"):
                        self.assert_invalid_bundle(self.verify(shell), bundle, "CFBundleExecutable")
            plist.write_bytes(plistlib.dumps(original))

    def test_architecture_mismatches_and_probe_errors_fail_closed(self):
        shim_dir = self.fixture / "bin"
        shim_dir.mkdir()
        shim = shim_dir / "lipo"
        shim.write_text(
            '#!/bin/sh\n'
            'if [ "$2" = "$OPENLIST_TEST_ARCH_BINARY" ]; then\n'
            '  printf "%s\\n" "$OPENLIST_TEST_ARCH_VALUE"\n'
            '  exit "$OPENLIST_TEST_ARCH_STATUS"\n'
            'fi\n'
            'exec "$OPENLIST_TEST_REAL_LIPO" "$@"\n'
        )
        shim.chmod(0o755)
        real_lipo = shutil.which("lipo")
        self.assertIsNotNone(real_lipo)
        for bundle, executable in (
            (self.app, "openlist"),
            (self.app / "Contents/PlugIns/OpenlistWidget.appex", "OpenlistWidget"),
        ):
            for architectures, status in (("x86_64", "0"), ("arm64 x86_64", "0"), ("arm64", "1")):
                env = {
                    "PATH": str(shim_dir) + os.pathsep + os.environ["PATH"],
                    "OPENLIST_TEST_ARCH_BINARY": str(bundle / "Contents/MacOS" / executable),
                    "OPENLIST_TEST_ARCH_VALUE": architectures,
                    "OPENLIST_TEST_ARCH_STATUS": status,
                    "OPENLIST_TEST_REAL_LIPO": real_lipo,
                }
                for shell in self.verifier_shells():
                    with self.subTest(bundle=bundle.name, architectures=architectures, status=status, shell=shell or "shebang"):
                        self.assert_invalid_bundle(self.verify(shell, env), bundle, "architecture")

    def test_xcode_links_transport_only_into_app_and_embeds_native_helper(self):
        result = subprocess.run(
            ["plutil", "-convert", "json", "-o", "-", str(ROOT / "openlist.xcodeproj/project.pbxproj")],
            capture_output=True, check=True,
        )
        project = json.loads(result.stdout)
        objects = project["objects"]
        targets = {value["name"]: (key, value) for key, value in objects.items() if value["isa"] == "PBXNativeTarget"}
        app_id, app = targets["openlist"]
        helper_id, helper = targets["openlist-mcp"]
        _, widget = targets["OpenlistWidget"]
        self.assertEqual(helper["productType"], "com.apple.product-type.tool")
        self.assertEqual(helper["packageProductDependencies"], [])
        self.assertEqual(widget["packageProductDependencies"], [])
        products = [objects[key] for key in app["packageProductDependencies"]]
        self.assertEqual([value["productName"] for value in products], ["OpenlistMCP"])
        self.assertEqual(objects[products[0]["package"]]["relativePath"], ".")
        self.assertIn(products[0]["package"], objects[project["rootObject"]]["packageReferences"])
        linked = [
            objects[file_id].get("productRef")
            for phase_id in app["buildPhases"] if objects[phase_id]["isa"] == "PBXFrameworksBuildPhase"
            for file_id in objects[phase_id]["files"]
        ]
        self.assertIn(app["packageProductDependencies"][0], linked)
        self.assertIn(helper_id, [objects[key]["target"] for key in app["dependencies"]])
        group_paths = [objects[key]["path"] for key in helper["fileSystemSynchronizedGroups"]]
        self.assertEqual(group_paths, ["OpenlistMCPHelper"])
        phases = [
            objects[key] for key in app["buildPhases"]
            if objects[key]["isa"] == "PBXCopyFilesBuildPhase" and objects[key]["name"] == "Embed MCP Helper"
        ]
        self.assertEqual(len(phases), 1)
        self.assertEqual(str(phases[0]["dstSubfolderSpec"]), "6")
        self.assertEqual(phases[0]["dstPath"], "")
        embedded = objects[phases[0]["files"][0]]
        self.assertEqual(embedded["fileRef"], helper["productReference"])
        self.assertIn("CodeSignOnCopy", embedded["settings"]["ATTRIBUTES"])
        self.assertEqual(objects[helper["productReference"]]["path"], "openlist-mcp")
        for config_id in objects[helper["buildConfigurationList"]]["buildConfigurations"]:
            settings = objects[config_id]["buildSettings"]
            self.assertEqual(settings["CODE_SIGN_STYLE"], "Automatic")
            self.assertEqual(settings["ENABLE_HARDENED_RUNTIME"], "YES")
            self.assertEqual(settings["ENABLE_APP_SANDBOX"], "NO")
            self.assertEqual(settings["SWIFT_VERSION"], "6.0")
            self.assertNotIn("CODE_SIGN_ENTITLEMENTS", settings)
            self.assertNotIn("ARCHS", settings)
            self.assertNotEqual(settings.get("SWIFT_DEFAULT_ACTOR_ISOLATION"), "MainActor")
        root_configs = objects[objects[project["rootObject"]]["buildConfigurationList"]]["buildConfigurations"]
        for config_id in root_configs:
            settings = objects[config_id]["buildSettings"]
            self.assertEqual(settings["MACOSX_DEPLOYMENT_TARGET"], "27.0")
            self.assertTrue(settings["DEVELOPMENT_TEAM"])
        self.assertNotEqual(app_id, helper_id)

    def test_xcode_dependency_pins_match_root_lockfile(self):
        with (ROOT / "Package.resolved").open() as source:
            root_pins = {pin["identity"]: pin for pin in json.load(source)["pins"]}
        path = ROOT / "openlist.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        with path.open() as source:
            xcode_pins = {pin["identity"]: pin for pin in json.load(source)["pins"]}
        self.assertTrue(root_pins)
        self.assertEqual(xcode_pins, root_pins)


if __name__ == "__main__":
    unittest.main(verbosity=2)
