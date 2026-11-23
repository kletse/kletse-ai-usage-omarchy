"""Unit tests for bin/ai-usage. Run: python3 -m unittest discover -s tests

Ported from the macOS app's Swift tests, plus the refresh and status-file behaviour that is new
here. Nothing touches the network, real credentials, or the Claude CLI.
"""

import importlib.machinery
import importlib.util
import json
import os
import pathlib
import shutil
import tempfile
import time
import sys
import unittest
from unittest import mock

sys.dont_write_bytecode = True
ROOT = pathlib.Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("ai_usage", str(ROOT / "bin" / "ai-usage"))
spec = importlib.util.spec_from_loader("ai_usage", loader)
ai = importlib.util.module_from_spec(spec)
loader.exec_module(ai)


def account(name="Claude", provider="claude", dir="~/.claude", **extra):
    return ai.Account(name, provider, dir, **extra)


def windows(payload):
    return ai.claude_windows(json.loads(payload))


class Sandbox(unittest.TestCase):
    """Points the config and status files at a temporary directory."""

    def setUp(self):
        self.root = pathlib.Path(tempfile.mkdtemp(prefix="ai-usage-test-"))
        self.env = mock.patch.dict(os.environ, {
            "AI_USAGE_CONFIG": str(self.root / "config" / "accounts.json"),
            "AI_USAGE_STATE_DIR": str(self.root / "state"),
        })
        self.env.start()

    def tearDown(self):
        self.env.stop()
        shutil.rmtree(self.root, ignore_errors=True)

    def write_config(self, rows):
        path = pathlib.Path(ai.config_path())
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(rows))


class ClaudeParsing(unittest.TestCase):
    def test_limits_and_legacy(self):
        modern = windows('{"limits":[{"kind":"weekly_scoped","percent":42,"scope":{"model":{"display_name":"Sonnet"}}},'
                         '{"kind":"session","percent":12},{"kind":"new_limit","percent":3},{"kind":"session"}],'
                         '"five_hour":{"utilization":99}}')
        self.assertEqual([w["label"] for w in modern], ["Week · Sonnet", "Session", "New Limit"])
        self.assertEqual([w["usedPercent"] for w in modern], [42, 12, 3])
        self.assertEqual([w["period"] for w in modern], [604800, 18000, None])
        legacy = windows('{"limits":[],"five_hour":{"utilization":0},"seven_day":{"utilization":100},'
                         '"seven_day_opus":{"utilization":20},"seven_day_sonnet":{}}')
        self.assertEqual([w["label"] for w in legacy], ["Session", "Week", "Week · Opus"])
        self.assertEqual(windows("{}"), [])

    def test_money(self):
        for exponent, currency, expected in [(0, "JPY", "¥250 of ¥1,000"), (2, "USD", "$2.50 of $10.00"),
                                             (3, "KWD", "KWD 0.250 of KWD 1.000"), (2, "EUR", "€2.50 of €10.00")]:
            payload = {"spend": {"enabled": True, "used": {"amount_minor": 250},
                                 "limit": {"amount_minor": 1000, "exponent": exponent, "currency": currency}},
                       "extra_usage": {"is_enabled": True, "monthly_limit": 100, "used_credits": 99}}
            first = ai.claude_windows(payload)[0]
            self.assertEqual(first["usedPercent"], 25)
            self.assertEqual(first["detail"], expected)
            self.assertTrue(first["resetIsEstimate"])
            self.assertIsNotNone(first["resetsAt"])
            self.assertEqual(first["kind"], "spend")

    def test_extra_usage(self):
        result = windows('{"spend":{"enabled":false},"extra_usage":{"is_enabled":true,"monthly_limit":1000,'
                         '"used_credits":250,"utilization":30}}')
        self.assertEqual(result[0]["usedPercent"], 30)
        self.assertEqual(windows('{"extra_usage":{"is_enabled":true,"monthly_limit":0}}'), [])

    def test_wrong_types_are_skipped(self):
        self.assertEqual(windows('{"limits":[{"kind":"session","percent":"12"},7,null]}'), [])
        self.assertEqual(windows('{"five_hour":{"utilization":true}}'), [])
        self.assertEqual(ai.claude_windows(["not", "a", "dict"]), [])

    def test_start_of_next_month(self):
        december = time.mktime((2026, 12, 15, 12, 0, 0, 0, 0, -1))
        self.assertEqual(time.localtime(ai.start_of_next_month(december))[:3], (2027, 1, 1))


class Headlines(unittest.TestCase):
    def test_shortest_period_first(self):
        def w(label, period):
            return ai.window(label, 0, period=period)

        def headline(items):
            found = ai.headline_window({"windows": items}, account(provider="codex", dir="~/.codex"))
            return found["label"] if found else None

        self.assertEqual(headline([w("unknown", None), w("week", 604800), w("first", 18000), w("tie", 18000)]), "first")
        self.assertEqual(headline([w("first", None), w("second", None)]), "first")
        self.assertIsNone(headline([]))

    def test_selected_usage_drives_bar(self):
        for payload in ['{"five_hour":{"utilization":6},"seven_day":{"utilization":1},"seven_day_sonnet":{"utilization":90}}',
                        '{"limits":[{"kind":"weekly_scoped","percent":90,"scope":{"model":{"display_name":"Fable"}}},'
                        '{"kind":"weekly_all","percent":1},{"kind":"session","percent":6}]}']:
            snap = ai.snapshot(windows(payload))
            claude = account()
            self.assertEqual(ai.headline_window(snap, claude)["usedPercent"], 6)
            claude.usage_type = "week"
            self.assertEqual(ai.headline_window(snap, claude)["usedPercent"], 1)
            self.assertEqual(ai.menu_text(snap, claude), "1%")
            codex = account("Codex", "codex", "~/.codex", usage_type="week")
            self.assertEqual(ai.headline_window(snap, codex)["usedPercent"], 6)
            self.assertEqual(ai.menu_text(snap, codex), "6%")

    def test_missing_weekly_allowance_does_not_show_another_limit(self):
        claude = account(usage_type="week")
        snap = ai.snapshot([ai.window("Session", 6, period=18000, kind="session"),
                            ai.window("Week · Fable", 90, period=604800, kind="scopedWeek")])
        self.assertIsNone(ai.headline_window(snap, claude))
        self.assertEqual(ai.menu_text(snap, claude), "–")
        claude.usage_type = "session"
        monthly = ai.snapshot([ai.window("Monthly spend", 82, period=2592000, kind="spend")])
        self.assertEqual(ai.headline_window(monthly, claude)["usedPercent"], 82)

    def test_scoped_week_never_stands_in(self):
        snap = ai.snapshot(windows('{"limits":[{"kind":"weekly_scoped","percent":90},{"kind":"weekly_all","percent":1}]}'))
        self.assertEqual([w["label"] for w in snap["windows"]], ["Week", "Week"])
        self.assertEqual(ai.headline_window(snap, account(usage_type="week"))["usedPercent"], 1)
        self.assertIsNone(ai.headline_window(snap, account()))

    def test_bar_text_rounds_half_up_and_clamps(self):
        claude = account()
        for used, text in [(42.5, "43%"), (41.49, "41%"), (130, "100%"), (-4, "0%")]:
            snap = ai.snapshot([ai.window("Session", used, kind="session")])
            self.assertEqual(ai.menu_text(snap, claude), text)
        self.assertEqual(ai.menu_text(None, claude), "–")


class Dates(unittest.TestCase):
    def test_parse_iso(self):
        self.assertEqual(ai.parse_iso("2026-01-01T00:00:00Z"), 1767225600)
        self.assertEqual(ai.parse_iso("2026-01-01T00:00:00.123456Z"), ai.parse_iso("2026-01-01T00:00:00Z"))
        self.assertEqual(ai.parse_iso("2026-01-01T01:00:00+01:00"), 1767225600)
        self.assertIsNone(ai.parse_iso(None))
        self.assertIsNone(ai.parse_iso("invalid"))


class Codex(Sandbox):
    def test_labels(self):
        for seconds, expected in [(2700, "45-minute"), (5400, "90-minute"), (18000, "5-hour"), (604800, "Week"),
                                  (172800, "2-day"), (7200, "2-hour"), (61, "61-second"), (0, "Limit"), (-1, "Limit")]:
            self.assertEqual(ai.codex_label(seconds), expected)

    def test_windows(self):
        result = ai.codex_windows(json.loads(
            '{"rate_limit":{"primary_window":{"used_percent":23,"limit_window_seconds":2700,"reset_at":100},'
            '"secondary_window":{}},"additional_rate_limits":[{"limit_name":"Review","rate_limit":'
            '{"primary_window":{"used_percent":45}}}]}'))
        self.assertEqual([w["label"] for w in result], ["45-minute", "Limit · Review"])
        self.assertEqual([w["period"] for w in result], [2700, None])
        self.assertEqual(result[0]["resetsAt"], 100)
        self.assertEqual(ai.codex_windows({}), [])

    def test_session_fallback(self):
        sessions = self.root / "codex" / "sessions" / "2026" / "01"
        sessions.mkdir(parents=True)
        (sessions / "test.jsonl").write_text("\n".join([
            '{"timestamp":"2026-01-01T00:00:00Z","payload":{"rate_limits":{"primary":{"used_percent":10,"window_minutes":300}}}}',
            '{"timestamp":"2026-01-02T00:00:00.123Z","payload":{"rate_limits":{"primary":{"used_percent":35,'
            '"window_minutes":45,"resets_at":100},"secondary":{},"plan_type":"prolite"}}}',
            '{"payload":{"rate_limits":',
            '{"payload":{"other":true}}',
        ]))
        snap = ai.CodexProvider(account("Test", "codex", str(self.root / "codex"))).fetch()
        self.assertEqual([w["usedPercent"] for w in snap["windows"]], [35])
        self.assertEqual(snap["windows"][0]["label"], "45-minute")
        self.assertEqual(snap["windows"][0]["period"], 2700)
        self.assertEqual(snap["plan"], "Pro Lite")
        self.assertEqual(snap["fetchedAt"], ai.parse_iso("2026-01-02T00:00:00Z"))
        self.assertIsNotNone(snap["staleReason"])

    def test_no_login_and_no_logs_fails_safely(self):
        with self.assertRaises(ai.FetchError) as caught:
            ai.CodexProvider(account("Test", "codex", str(self.root / "missing"))).fetch()
        self.assertIn("auth.json", caught.exception.description)

    def test_live_request_uses_account_header_and_plan(self):
        home = self.root / "codex-live"
        home.mkdir()
        claims = {"email": "you@example.invalid",
                  "https://api.openai.com/auth": {"chatgpt_plan_type": "plus", "chatgpt_account_id": "acct-1"}}
        payload = ai.base64.urlsafe_b64encode(json.dumps(claims).encode()).decode().rstrip("=")
        (home / "auth.json").write_text(json.dumps({"tokens": {"access_token": "fixture-token",
                                                               "id_token": f"x.{payload}.y"}}))
        seen = {}

        def fake_get(url, headers, service):
            seen.update(headers)
            return 200, json.dumps({"plan_type": "pro", "rate_limit": {"primary_window": {
                "used_percent": 12, "limit_window_seconds": 18000}}}).encode(), {}

        with mock.patch.object(ai, "http_get", fake_get):
            snap = ai.CodexProvider(account("Codex", "codex", str(home))).fetch()
        self.assertEqual(seen["ChatGPT-Account-Id"], "acct-1")
        self.assertEqual(snap["identity"], "you@example.invalid")
        self.assertEqual(snap["plan"], "Pro")
        self.assertEqual(snap["windows"][0]["label"], "5-hour")

    def test_rate_limit_sets_retry_after(self):
        home = self.root / "codex-limited"
        home.mkdir()
        (home / "auth.json").write_text(json.dumps({"tokens": {"access_token": "fixture-token"}}))
        with mock.patch.object(ai, "http_get", lambda *_: (429, b"", {"Retry-After": "5"})):
            with self.assertRaises(ai.FetchError) as caught:
                ai.CodexProvider(account("Codex", "codex", str(home))).fetch()
        self.assertGreaterEqual(caught.exception.retry_after, time.time() + 59)


class Claude(Sandbox):
    def make_login(self, expires_in=3600, **oauth):
        home = self.root / "claude"
        home.mkdir(exist_ok=True)
        data = {"accessToken": "fixture-token", "refreshToken": "fixture-refresh",
                "expiresAt": (time.time() + expires_in) * 1000, "subscriptionType": "max"}
        data.update(oauth)
        (home / ".credentials.json").write_text(json.dumps({"claudeAiOauth": data}))
        (home / ".claude.json").write_text(json.dumps({
            "oauthAccount": {"emailAddress": "you@example.invalid", "organizationType": "claude_team"},
            "cachedUsageUtilization": {"fetchedAtMs": 1_700_000_000_000, "utilization": {"five_hour": {"utilization": 7}}},
        }))
        return account("Claude", "claude", str(home))

    def test_live_request(self):
        login = self.make_login()
        seen = {}

        def fake_get(url, headers, service):
            seen.update(headers, url=url)
            return 200, b'{"limits":[{"kind":"session","percent":12}]}', {}

        with mock.patch.object(ai, "http_get", fake_get):
            snap = ai.ClaudeProvider(login).fetch()
        self.assertEqual(seen["url"], ai.CLAUDE_USAGE_URL)
        self.assertEqual(seen["Authorization"], "Bearer fixture-token")
        self.assertEqual(seen["anthropic-beta"], "oauth-2025-04-20")
        self.assertEqual(snap["identity"], "you@example.invalid")
        self.assertEqual(snap["plan"], "Team")
        self.assertIsNone(snap["staleReason"])

    def test_expired_token_falls_back_to_claude_codes_cache(self):
        login = self.make_login(expires_in=-60)
        with mock.patch.object(ai, "http_get", side_effect=AssertionError("no request expected")):
            snap = ai.ClaudeProvider(login).fetch()
        self.assertEqual(snap["windows"][0]["usedPercent"], 7)
        self.assertEqual(snap["fetchedAt"], 1_700_000_000)
        self.assertIn("Token expired", snap["staleReason"])

    def test_rejected_token_and_errors(self):
        login = self.make_login()
        with mock.patch.object(ai, "http_get", lambda *_: (401, b"", {})):
            self.assertIn("Token rejected", ai.ClaudeProvider(login).fetch()["staleReason"])
        with mock.patch.object(ai, "http_get", lambda *_: (500, b"secret body", {})):
            with self.assertRaises(ai.FetchError) as caught:
                ai.ClaudeProvider(login).fetch()
        self.assertEqual(caught.exception.description, "Anthropic returned HTTP 500")
        with mock.patch.object(ai, "http_get", lambda *_: (200, b"not json", {})):
            with self.assertRaises(ai.FetchError):
                ai.ClaudeProvider(login).fetch()

    def test_default_dir_state_files(self):
        default = ai.ClaudeProvider(account())
        self.assertEqual(default.state_files, [ai.expand_tilde("~/.claude.json"), ai.expand_tilde("~/.claude/.claude.json")])
        self.assertEqual(ai.ClaudeProvider(account(dir="/tmp/x/")).state_files, ["/tmp/x/.claude.json"])

    def test_no_login(self):
        with self.assertRaises(ai.FetchError) as caught:
            ai.ClaudeProvider(account(dir=str(self.root / "none"))).fetch()
        self.assertIn(".credentials.json", caught.exception.description)


class Config(Sandbox):
    def test_defaults_and_duplicates(self):
        self.assertEqual(ai.discovered_defaults(lambda _: False), [])
        self.assertEqual([a.provider for a in ai.discovered_defaults(lambda path: path == "~/.codex")], ["codex"])
        row = {"name": "A", "provider": "claude", "dir": "/tmp/test"}
        with self.assertRaises(ai.ConfigError):
            ai.parse_accounts([row, row])
        self.assertEqual(len(ai.parse_accounts([row])), 1)
        for bad in [{}, [{"name": "A", "provider": "gemini", "dir": "x"}], [{"name": " ", "provider": "claude", "dir": "x"}]]:
            with self.assertRaises(ai.ConfigError):
                ai.parse_accounts(bad)

    def test_usage_type_decoding(self):
        for raw, expected in [("week", "week"), ("Week", "week"), ("weekly", "session"), ("SESSION", "session")]:
            parsed = ai.parse_accounts([{"name": "Claude", "provider": "claude", "dir": "~/.claude", "usageType": raw}])
            self.assertEqual(parsed[0].claude_usage_type, expected)
        legacy = ai.parse_accounts([{"name": "Claude", "provider": "claude", "dir": "~/.claude"}])[0]
        self.assertEqual(legacy.claude_usage_type, "session")

    def test_first_run_writes_defaults(self):
        with mock.patch.object(ai, "discovered_defaults", return_value=[]):
            self.assertEqual(ai.load_accounts(), [])
        self.assertEqual(json.loads(pathlib.Path(ai.config_path()).read_text()), [])
        self.assertTrue(pathlib.Path(ai.config_path() + ".example").exists())

    def test_cli_edits_keep_unknown_fields_and_ids(self):
        self.write_config([{"name": "Claude", "provider": "claude", "dir": "~/.claude", "keychainService": "x", "extra": 1}])
        ai.main(["usage-type", "1", "week"])
        rows = json.loads(pathlib.Path(ai.config_path()).read_text())
        self.assertEqual(rows[0]["usageType"], "week")
        self.assertEqual(rows[0]["extra"], 1)
        self.assertEqual(rows[0]["keychainService"], "x")
        status = json.loads(pathlib.Path(ai.status_path()).read_text())
        self.assertEqual(status["accounts"][0]["usageType"], "week")
        self.assertEqual(status["accounts"][0]["id"], "Claude|~/.claude")
        with mock.patch("sys.stdout"):
            ai.main(["add", "codex", "~/.codex-work", "--group", "Work"])
            ai.main(["remove", "1"])
        rows = json.loads(pathlib.Path(ai.config_path()).read_text())
        self.assertEqual(rows, [{"name": "Codex", "provider": "codex", "dir": "~/.codex-work", "group": "Work"}])
        with self.assertRaises(SystemExit):
            ai.main(["usage-type", "1", "week"])


class Refresh(Sandbox):
    def test_merge_backoff_and_dedupe(self):
        self.write_config([{"name": "Claude", "provider": "claude", "dir": "/a"},
                           {"name": "Codex", "group": "Work", "provider": "codex", "dir": "/b"}])
        calls = []
        now = [1_800_000_000.0]

        def fetch(target):
            calls.append(target.name)
            if target.provider == "codex":
                raise ai.FetchError("Rate limited by ChatGPT", retry_after=now[0] + 600)
            return ai.snapshot([ai.window("Session", 42, kind="session")], fetched_at=now[0])

        status = ai.refresh(fetch=fetch, now=now[0], renew=False)
        claude, codex = status["accounts"]
        self.assertEqual(claude["menuText"], "42%")
        self.assertEqual(codex["menuText"], "–")
        self.assertEqual(codex["error"], "Rate limited by ChatGPT")
        self.assertEqual(codex["group"], "Work")
        self.assertEqual(sorted(calls), ["Claude", "Codex"])

        # Within a minute nothing is fetched again; forced, only what isn't backing off is.
        calls.clear()
        ai.refresh(fetch=fetch, now=now[0] + 10, renew=False)
        self.assertEqual(calls, [])
        ai.refresh(fetch=fetch, now=now[0] + 20, force=True, renew=False)
        self.assertEqual(calls, ["Claude"])

        # An older cached copy never replaces fresher live data, but its reason shows.
        def stale(target):
            return ai.snapshot([ai.window("Session", 5, kind="session")], fetched_at=now[0] - 3600,
                               stale_reason="Token expired. Open Claude Code to refresh it.")

        status = ai.refresh(fetch=stale, now=now[0] + 700, force=True, renew=False)
        claude, codex = status["accounts"]
        self.assertEqual(claude["menuText"], "42%")
        self.assertIn("Token expired", claude["error"])
        self.assertIsNone(codex["retryAfter"])

    def test_new_account_is_fetched_at_once_and_removed_ones_forgotten(self):
        self.write_config([{"name": "A", "provider": "claude", "dir": "/a"}])
        fetch = mock.Mock(return_value=ai.snapshot([], fetched_at=1))
        ai.refresh(fetch=fetch, now=1000, renew=False)
        self.write_config([{"name": "B", "provider": "claude", "dir": "/b"}])
        status = ai.refresh(fetch=fetch, now=1001, renew=False)
        self.assertEqual(fetch.call_count, 2)
        self.assertEqual([entry["id"] for entry in status["accounts"]], ["B|/b"])

    def test_provider_change_drops_state(self):
        self.write_config([{"name": "A", "provider": "claude", "dir": "/a"}])
        ai.refresh(fetch=lambda _: ai.snapshot([ai.window("Session", 9, kind="session")], fetched_at=1), now=1000, renew=False)
        self.write_config([{"name": "A", "provider": "codex", "dir": "/a"}])
        status = ai.rebuild_status()
        self.assertIsNone(status["accounts"][0]["snapshot"])

    def test_broken_config_keeps_last_usage(self):
        self.write_config([{"name": "A", "provider": "claude", "dir": "/a"}])
        ai.refresh(fetch=lambda _: ai.snapshot([ai.window("Session", 9, kind="session")], fetched_at=1), now=1000, renew=False)
        pathlib.Path(ai.config_path()).write_text("[{")
        status = ai.refresh(fetch=mock.Mock(), now=2000, renew=False)
        self.assertIn("Could not read", status["configError"])
        self.assertEqual(status["accounts"][0]["menuText"], "9%")

    def test_status_file_is_private_and_holds_no_tokens(self):
        login = Claude.make_login(self)
        self.write_config([{"name": "Claude", "provider": "claude", "dir": login.dir}])
        with mock.patch.object(ai, "http_get", lambda *_: (200, b'{"limits":[{"kind":"session","percent":1}]}', {})):
            ai.refresh(renew=False)
        path = pathlib.Path(ai.status_path())
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertNotIn("fixture-token", path.read_text())
        self.assertNotIn("fixture-refresh", path.read_text())

    def test_sample_reads_nothing(self):
        with mock.patch.object(ai, "load_accounts", side_effect=AssertionError("sample read the config")):
            sample = ai.sample_status()
        self.assertEqual(len(sample["accounts"]), 4)
        self.assertEqual([entry["menuText"] for entry in sample["accounts"]], ["82%", "12%", "23%", "7%"])
        self.assertIn("WORK", ai.render_text(sample))


class Fixture:
    """A fake Claude login whose renewal can succeed or not, on a controllable clock."""

    def __init__(self):
        self.now = 1_800_000_000.0
        self.login = None
        self.calls = 0
        self.advances = True

    def set(self, expiry, token="fixture-access", renewable=True, final=None):
        self.login = ai.ClaudeCredentials(token, expiry, None, renewable, final)

    def read(self, _):
        if self.login is None:
            raise ai.FetchError("No fixture login")
        return self.login

    def run(self, _):
        self.calls += 1
        if self.advances:
            self.login = ai.ClaudeCredentials(self.login.access_token + "-renewed", self.now + 3600, None, True, None)

    def check(self, failures, target=None):
        return ai.check_renewal(target or account(dir="/fixture"), failures, read=self.read, run=self.run,
                                clock=lambda: self.now)


class Renewal(unittest.TestCase):
    def test_schedules_successive_saved_expiries(self):
        fixture, failures = Fixture(), {}
        expiry = fixture.now + 600
        fixture.set(expiry)
        early = fixture.check(failures)
        self.assertEqual(early["nextCheck"], expiry - 240)
        self.assertEqual(fixture.calls, 0)

        fixture.now = early["nextCheck"]
        first = fixture.check(failures)
        self.assertTrue(first["renewed"])
        self.assertIsNone(first["error"])
        self.assertEqual(first["nextCheck"], fixture.now + 3600 - 240)
        self.assertEqual(fixture.calls, 1)

        fixture.check(failures)
        self.assertEqual(fixture.calls, 1)
        fixture.now = first["nextCheck"]
        second = fixture.check(failures)
        self.assertTrue(second["renewed"])
        self.assertEqual(fixture.calls, 2)

    def test_external_renewal_replaces_old_deadline(self):
        fixture, failures = Fixture(), {}
        fixture.set(fixture.now + 600)
        fixture.check(failures)
        fixture.set(fixture.now + 7200, token="external-renewal")
        self.assertEqual(fixture.check(failures)["nextCheck"], fixture.now + 7200 - 240)
        self.assertEqual(fixture.calls, 0)

    def test_failures_back_off_and_reset_on_new_expiry(self):
        fixture, failures = Fixture(), {}
        fixture.advances = False
        fixture.set(fixture.now + 60)
        delays = []
        for _ in range(7):
            result = fixture.check(failures)
            self.assertEqual(result["error"], "Claude renewal did not advance the saved token expiry.")
            delays.append(result["nextCheck"] - fixture.now)
            # Before the retry time nothing runs again.
            calls = fixture.calls
            fixture.check(failures)
            self.assertEqual(fixture.calls, calls)
            fixture.now = result["nextCheck"]
        self.assertEqual(delays, [30, 60, 120, 240, 300, 300, 300])
        # A new expiry (e.g. after `claude` ran elsewhere) starts over.
        fixture.set(fixture.now + 3600, token="fresh")
        self.assertEqual(fixture.check(failures)["error"], None)
        self.assertEqual(failures, {})

    def test_failure_survives_a_status_round_trip(self):
        fixture, failures = Fixture(), {}
        fixture.advances = False
        fixture.set(fixture.now + 60)
        fixture.check(failures)
        failures = json.loads(json.dumps(failures))
        fixture.now += 10
        result = fixture.check(failures)
        self.assertEqual(fixture.calls, 1)
        self.assertEqual(result["error"], "Claude renewal did not advance the saved token expiry.")

    def test_logins_that_cannot_renew(self):
        fixture, failures = Fixture(), {}
        fixture.set(fixture.now + 60, renewable=False)
        self.assertIn("claude auth login", fixture.check(failures)["error"])
        fixture.set(fixture.now + 60, final=fixture.now - 1)
        self.assertIn("expired", fixture.check(failures)["error"])
        fixture.login = None
        self.assertEqual(fixture.check(failures), {"nextCheck": None, "error": None, "renewed": False})
        self.assertEqual(fixture.calls, 0)
        self.assertEqual(ai.check_renewal(account("Codex", "codex", "/x"), failures)["nextCheck"], None)

    def test_unexpected_errors_show_a_safe_message(self):
        fixture, failures = Fixture(), {}
        fixture.set(fixture.now + 60)

        def boom(_):
            raise RuntimeError("secret output")

        fixture.run = boom
        result = fixture.check(failures)
        self.assertEqual(result["error"], "Could not verify Claude renewal. Retrying automatically.")

    def test_environment(self):
        inherited = {"PATH": "/usr/bin", "CLAUDE_CONFIG_DIR": "/elsewhere", "ANTHROPIC_API_KEY": "k", "CLAUDECODE": "1",
                     "HTTPS_PROXY": "http://proxy"}
        work = ai.renewal_environment(account(dir="~/.claude-work"), inherited)
        self.assertEqual(work["CLAUDE_CONFIG_DIR"], ai.expand_tilde("~/.claude-work"))
        self.assertNotIn("ANTHROPIC_API_KEY", work)
        self.assertNotIn("CLAUDECODE", work)
        self.assertEqual(work["HTTPS_PROXY"], "http://proxy")
        self.assertEqual(work["CLAUDE_CODE_SAFE_MODE"], "1")
        default = ai.renewal_environment(account(dir="~/.claude/"), inherited)
        self.assertNotIn("CLAUDE_CONFIG_DIR", default)

    def test_cli_runner_bounds_and_reports(self):
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch.dict(os.environ, {"AI_USAGE_STATE_DIR": directory}):
            for script, expected in [("exit 3", "renewal failed"), ("sleep 5", "timed out")]:
                fake = pathlib.Path(directory) / "claude"
                fake.write_text("#!/bin/sh\n" + script + "\n")
                fake.chmod(0o755)
                with mock.patch.object(ai, "claude_executable", return_value=str(fake)):
                    with self.assertRaises(ai.FetchError) as caught:
                        ai.run_claude_usage(account(dir=directory), timeout=0.5)
                self.assertIn(expected, caught.exception.description)


class ReviewRegressions(Sandbox):
    """Cases from an independent review of the port against the Swift app."""

    def setUp(self):
        super().setUp()
        self.write_config([{"name": "Claude", "provider": "claude", "dir": "/a"}])
        self.login = {"expires": 1_800_000_000.0 + 60, "token": "t1", "advance": False}

    def read(self, _):
        return ai.ClaudeCredentials(self.login["token"], self.login["expires"], None, True, None)

    def run_cli(self, _):
        if self.login["advance"]:
            self.login.update(token="t2", expires=self.clock + 3600)

    def refresh(self, at, fetch, **kwargs):
        self.clock = at
        original = ai.check_renewal
        with mock.patch.object(ai, "check_renewal", lambda account, failures: original(
                account, failures, read=self.read, run=self.run_cli, clock=lambda: self.clock)):
            return ai.refresh(fetch=fetch, now=at, **kwargs)

    def test_a_renewal_inside_the_dedupe_window_is_followed_by_a_fetch(self):
        fetch = mock.Mock(side_effect=ai.FetchError("Token expired. Open Claude Code to refresh it."))
        start = 1_800_000_000.0
        first = self.refresh(start, fetch)
        self.assertIn("renewal did not advance", first["accounts"][0]["error"])
        self.login["advance"] = True
        fetch.side_effect = None
        fetch.return_value = ai.snapshot([ai.window("Session", 3, kind="session")], fetched_at=start + 31)
        second = self.refresh(start + 31, fetch)
        self.assertEqual(fetch.call_count, 2)
        self.assertIsNone(second["accounts"][0]["error"])
        self.assertEqual(second["accounts"][0]["menuText"], "3%")

    def test_a_renewal_error_does_not_hide_a_cached_copys_reason_and_clears(self):
        start = 1_800_000_000.0
        stale = ai.snapshot([ai.window("Session", 3, kind="session")], fetched_at=start,
                            stale_reason="Token rejected. Open Claude Code to refresh it.")
        status = self.refresh(start, mock.Mock(return_value=stale), force=True)
        self.assertEqual(status["accounts"][0]["error"], "Token rejected. Open Claude Code to refresh it.")
        status = self.refresh(start + 40, mock.Mock(side_effect=AssertionError("deduped")))
        self.assertEqual(status["accounts"][0]["error"], "Token rejected. Open Claude Code to refresh it.")
        self.assertEqual(status["accounts"][0]["renewalError"], "Claude renewal did not advance the saved token expiry.")

    def test_a_clock_that_steps_back_still_fetches(self):
        fetch = mock.Mock(return_value=ai.snapshot([], fetched_at=1))
        ai.refresh(fetch=fetch, now=2_000_000_000, renew=False)
        ai.refresh(fetch=fetch, now=2_000_000_000 - 3600, renew=False)
        self.assertEqual(fetch.call_count, 2)

    def test_no_renew_keeps_the_schedule_and_back_off(self):
        start = 1_800_000_000.0
        self.refresh(start, mock.Mock(return_value=ai.snapshot([], fetched_at=start)))
        saved = ai.load_status()
        self.assertTrue(saved["renewal"])
        ai.refresh(fetch=mock.Mock(return_value=ai.snapshot([], fetched_at=start)), now=start + 5, renew=False,
                   force=True)
        after = ai.load_status()
        self.assertEqual(after["renewal"], saved["renewal"])
        self.assertEqual(after["nextCheck"], saved["nextCheck"])
        self.assertIsNone(after["accounts"][0]["error"])

    def test_a_damaged_status_file_heals(self):
        path = pathlib.Path(ai.status_path())
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"version": 1, "lastFetch": "soon", "renewal": {"/a": "x", 3: {}},
                                    "accounts": [{"id": "Claude|/a", "provider": "claude", "snapshot": "oops"},
                                                 {"id": "x", "provider": "claude", "snapshot": {
                                                     "fetchedAt": 1, "windows": [None, {"label": "S", "usedPercent": None}]}},
                                                 "junk", None]}))
        status = ai.refresh(fetch=mock.Mock(return_value=ai.snapshot([ai.window("Session", 1, kind="session")])),
                            renew=False)
        self.assertEqual(status["accounts"][0]["menuText"], "1%")
        ai.main(["usage-type", "1", "week"])
        with mock.patch("sys.stdout"):
            ai.main(["show"])

    def test_text_that_isnt_valid_unicode_still_saves(self):
        ai.refresh(fetch=lambda _: ai.snapshot([ai.window("Session \ud800", 1, kind="session")]), renew=False)
        self.assertIn("\\ud800", pathlib.Path(ai.status_path()).read_text())

    def test_malformed_http_reads_as_unreachable(self):
        class Opener:
            def open(self, *_args, **_kwargs):
                raise ai.http.client.BadStatusLine("x")

        with mock.patch.object(ai, "OPENER", Opener()):
            with self.assertRaises(ai.FetchError) as caught:
                ai.http_get("https://example.invalid", {}, "Anthropic")
        self.assertEqual(caught.exception.description, "Could not reach Anthropic")

    def test_whole_floats_count_as_integers(self):
        result = ai.codex_windows({"rate_limit": {"primary_window": {"used_percent": 1, "limit_window_seconds": 18000.0}}})
        self.assertEqual((result[0]["label"], result[0]["period"]), ("5-hour", 18000))
        self.assertEqual(ai.as_int(True), None)
        self.assertEqual(ai.as_int(2.5), None)

    def test_config_field_types_and_bare_file_names(self):
        with self.assertRaises(ai.ConfigError):
            ai.parse_accounts([{"name": "A", "provider": "claude", "dir": "/a", "group": 3}])
        with mock.patch.dict(os.environ, {"AI_USAGE_CONFIG": "accounts.json"}):
            self.assertTrue(os.path.isabs(ai.config_path()))

    def test_a_stuck_lock_is_reported(self):
        with ai.Lock():
            with mock.patch.object(ai, "LOCK_TIMEOUT_SECONDS", 0.3), mock.patch("sys.stderr"):
                lock = ai.Lock(timeout=0.3)
                with self.assertRaises(ai.LockTimeout):
                    lock.__enter__()


if __name__ == "__main__":
    unittest.main()
