#!/usr/bin/env python3
"""Exercise the renewal code with the real installed Claude CLI and disposable OAuth credentials.

Every HTTPS request the CLI makes goes through a local proxy that answers with fixture
responses, so no real token is copied or sent, nothing reaches Anthropic, and nothing on the
machine is trusted beyond this one child process (NODE_EXTRA_CA_CERTS). The CLI runs with a
temporary CLAUDE_CONFIG_DIR, so your own login is never read or touched.

Run: python3 tests/check_claude_renewal.py
"""
import http.server
import importlib.machinery
import importlib.util
import json
import os
import pathlib
import shutil
import ssl
import subprocess
import tempfile
import threading
import time
from unittest import mock
from urllib.parse import urlsplit

ROOT = pathlib.Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("ai_usage", str(ROOT / "bin" / "ai-usage"))
spec = importlib.util.spec_from_loader("ai_usage", loader)
ai = importlib.util.module_from_spec(spec)
loader.exec_module(ai)


def main():
    if shutil.which("claude") is None:
        print("Skipped: the Claude CLI is not installed.")
        return
    with tempfile.TemporaryDirectory(prefix="ai-usage-renewal-fixture-") as directory:
        root = pathlib.Path(directory).resolve()
        root.chmod(0o700)
        home = root / "claude-config"
        home.mkdir(mode=0o700)
        certificate, key = root / "cert.pem", root / "key.pem"
        config = root / "openssl.cnf"
        config.write_text("""[req]
prompt=no
distinguished_name=dn
x509_extensions=ext
[dn]
CN=AI Usage disposable OAuth fixture
[ext]
subjectAltName=DNS:*.anthropic.com,DNS:anthropic.com,DNS:*.claude.com,DNS:claude.com,DNS:claude.ai,DNS:*.claude.ai
basicConstraints=critical,CA:TRUE
keyUsage=critical,keyCertSign,digitalSignature,keyEncipherment
""")
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", str(key),
                        "-out", str(certificate), "-days", "1", "-config", str(config)],
                       capture_output=True, check=True)
        key.chmod(0o600)
        now = int(time.time() * 1000)
        scopes = ["user:profile", "user:inference", "user:sessions:claude_code"]
        credentials = home / ".credentials.json"
        credentials.write_text(json.dumps({"claudeAiOauth": {
            "accessToken": "fixture-access-old", "refreshToken": "fixture-refresh-old",
            "expiresAt": now + 120_000, "refreshTokenExpiresAt": now + 25 * 86_400_000,
            "scopes": scopes, "subscriptionType": "max", "rateLimitTier": "default_claude_max_5x",
        }}))
        credentials.chmod(0o600)
        account_info = {
            "accountUuid": "11111111-1111-4111-8111-111111111111",
            "organizationUuid": "22222222-2222-4222-8222-222222222222",
            "emailAddress": "fixture@example.invalid", "organizationType": "claude_max",
            "billingType": "stripe_subscription", "accountCreatedAt": "2025-01-01T00:00:00Z",
            "subscriptionCreatedAt": "2025-01-01T00:00:00Z", "ccOnboardingFlags": {},
        }
        (home / ".claude.json").write_text(json.dumps({"hasCompletedOnboarding": True, "oauthAccount": account_info}))
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(certificate, key)
        requests, refreshes = [], []

        class App(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_GET(self):
                self.respond()

            def do_POST(self):
                self.respond()

            def respond(self):
                body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
                path = urlsplit(self.path).path
                requests.append((self.command, path))
                status = 200
                if path == "/v1/oauth/token":
                    payload = json.loads(body)
                    count = len(refreshes) + 1
                    expected = "fixture-refresh-old" if count == 1 else f"fixture-refresh-new-{count - 1}"
                    # Reject any unexpected credential without ever logging it.
                    assert payload.get("grant_type") == "refresh_token"
                    assert payload.get("refresh_token") == expected
                    refreshes.append(count)
                    result = {
                        "access_token": f"fixture-access-new-{count}",
                        "refresh_token": f"fixture-refresh-new-{count}",
                        "expires_in": 300 if count == 1 else 28800,
                        "refresh_token_expires_in": 30 * 86400,
                        "scope": " ".join(scopes), "token_type": "Bearer",
                    }
                elif path == "/api/oauth/profile":
                    result = {
                        "account": {"uuid": account_info["accountUuid"], "email": "fixture@example.invalid"},
                        "organization": {"uuid": account_info["organizationUuid"], "organization_type": "claude_max",
                                         "rate_limit_tier": "default_claude_max_5x",
                                         "billing_type": "stripe_subscription"},
                    }
                else:
                    status, result = 403, {"error": {"type": "permission_error", "message": "Blocked by fixture"}}
                data = json.dumps(result).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(data)

        class Proxy(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_CONNECT(self):
                self.send_response(200, "Connection established")
                self.end_headers()
                try:
                    with context.wrap_socket(self.connection, server_side=True) as connection:
                        App(connection, self.client_address, self.server)
                except (ssl.SSLError, OSError):
                    pass  # A client that doesn't trust the fixture (e.g. a version manager's update check).

        class Server(http.server.ThreadingHTTPServer):
            daemon_threads = True

        server = Server(("127.0.0.1", 0), Proxy)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        environment = {k: v for k, v in os.environ.items()
                       if not k.startswith(("CLAUDE", "ANTHROPIC", "OTEL"))
                       and k.upper() not in ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY")}
        environment.update({
            "NODE_EXTRA_CA_CERTS": str(certificate),
            "HTTP_PROXY": f"http://127.0.0.1:{server.server_port}",
            "HTTPS_PROXY": f"http://127.0.0.1:{server.server_port}",
            "NO_PROXY": "localhost,127.0.0.1",
            "AI_USAGE_STATE_DIR": str(root / "state"),
        })
        account = ai.Account("Fixture", "claude", str(home))
        failures = {}
        try:
            with mock.patch.dict(os.environ, environment, clear=True):
                first = ai.check_renewal(account, failures)
                assert first["renewed"], f"First renewal not confirmed: {first}"
                saved = json.loads(credentials.read_text())["claudeAiOauth"]
                assert saved["accessToken"] == "fixture-access-new-1", "Renewed token was not saved"
                # The fixture's first token lives five minutes, so its deadline is a minute out.
                assert first["nextCheck"] - time.time() < 120, first
                offset = first["nextCheck"] - time.time() + 1
                second = ai.check_renewal(account, failures, clock=lambda: time.time() + offset)
                assert second["renewed"], f"Second renewal not confirmed: {second}"
                assert second["nextCheck"] - time.time() > 7 * 3600, second
            assert len(refreshes) == 2, f"Expected two confirmed renewals, observed {len(refreshes)}"
            assert not any("messages" in path or "complete" in path for _, path in requests), requests
            assert failures == {}, failures
            print("Real CLI integration passed: two renewals, both saved and rescheduled; no model requests.")
        finally:
            server.shutdown()


if __name__ == "__main__":
    main()
