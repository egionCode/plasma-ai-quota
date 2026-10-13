"""
test_fetch_usage.py: testes do coletor (parse das respostas, fallback do Codex, merge
com o clauth e erros tipados). Sem rede: HTTP e clauth sao substituidos por stubs.
Rodar: python3 -m unittest discover -s tests -p 'test_*.py'
"""

import json
import os
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "com.egion.aiquota", "contents", "code"))
import fetch_usage as fu  # noqa: E402

NOW = 1_800_000_000.0  # epoch fixo para os testes nao dependerem do relogio
FUTURE = "2027-06-01T08:00:00+00:00"  # depois de NOW
PAST = "2020-01-01T00:00:00Z"


def args(**kw):
    base = dict(claude_creds="", codex_home="", clauth_bin="", clauth_home="", no_claude=False,
                no_codex=False, no_clauth=False, timeout=1.0)
    base.update(kw)
    return SimpleNamespace(**base)


def write(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(obj if isinstance(obj, str) else json.dumps(obj))


def jwt(exp):
    import base64
    body = base64.urlsafe_b64encode(json.dumps({"exp": exp}).encode()).decode().rstrip("=")
    return "h." + body + ".s"


class HelpersTest(unittest.TestCase):
    def test_key_for_seconds(self):
        self.assertEqual(fu.key_for_seconds(18000), "5h")
        self.assertEqual(fu.key_for_seconds(604800), "7d")
        self.assertEqual(fu.key_for_seconds(90), "1m")
        self.assertEqual(fu.key_for_seconds(None), "window")

    def test_window_reset_in_past_zeroes_usage(self):
        w = fu.window("5h", 80, fu.parse_iso(PAST), NOW)
        self.assertEqual(w["used_pct"], 0.0)
        self.assertIsNone(w["resets_at"])

    def test_window_clamps(self):
        self.assertEqual(fu.window("x", 150, None, NOW)["used_pct"], 100.0)
        self.assertEqual(fu.window("x", -3, None, NOW)["used_pct"], 0.0)

    def test_parse_iso_long_fraction(self):
        self.assertIsNotNone(fu.parse_iso("2026-10-13T20:59:59.792946+00:00"))
        self.assertIsNone(fu.parse_iso("lixo"))

    def test_jwt_exp(self):
        self.assertEqual(fu.jwt_exp(jwt(123)), 123)
        self.assertIsNone(fu.jwt_exp("nao-e-jwt"))


class ClaudeTest(unittest.TestCase):
    def test_parse_keeps_known_windows_only(self):
        data = {
            "five_hour": {"utilization": 4.0, "resets_at": FUTURE},
            "seven_day": {"utilization": 56.0, "resets_at": FUTURE},
            "seven_day_opus": None,
            "codinome_interno": {"utilization": 99},
        }
        ws = fu.parse_claude_usage(data, NOW)
        self.assertEqual([w["key"] for w in ws], ["5h", "7d"])
        self.assertEqual(ws[1]["used_pct"], 56.0)

    def test_parse_empty_is_error(self):
        with self.assertRaises(fu.SourceError) as cm:
            fu.parse_claude_usage({"five_hour": None}, NOW)
        self.assertEqual(cm.exception.code, "parse")

    def test_missing_file(self):
        with self.assertRaises(fu.SourceError) as cm:
            fu.fetch_claude("/nao/existe.json", 1, NOW)
        self.assertEqual(cm.exception.code, "not_found")
        self.assertEqual(cm.exception.path, "/nao/existe.json")

    def test_expired_token_never_calls_network(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, ".credentials.json")
            write(p, {"claudeAiOauth": {"accessToken": "t", "expiresAt": (NOW - 10) * 1000}})
            with mock.patch.object(fu, "http_get_json") as http:
                with self.assertRaises(fu.SourceError) as cm:
                    fu.fetch_claude(p, 1, NOW)
                http.assert_not_called()
            self.assertEqual(cm.exception.code, "expired")

    def test_api_key_login_has_no_subscription(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, ".credentials.json")
            write(p, {"outra": 1})
            with self.assertRaises(fu.SourceError) as cm:
                fu.fetch_claude(p, 1, NOW)
            self.assertEqual(cm.exception.code, "no_subscription")

    def test_live_ok(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, ".credentials.json")
            write(p, {"claudeAiOauth": {"accessToken": "t", "expiresAt": (NOW + 999) * 1000,
                                        "subscriptionType": "max"}})
            resp = {"five_hour": {"utilization": 10, "resets_at": FUTURE}}
            with mock.patch.object(fu, "http_get_json", return_value=resp) as http:
                acc = fu.fetch_claude(p, 1, NOW)
            headers = http.call_args[0][1]
            self.assertEqual(headers["Authorization"], "Bearer t")
            self.assertEqual(acc["plan"], "max")
            self.assertEqual(acc["source"], "live")


class ClauthTest(unittest.TestCase):
    STATUS = {
        "active_profile": "a",
        "profiles": [
            {"name": "a", "active": True, "harness": "claude", "tier": "Team",
             "fetch_status": "Cached", "stale": False, "auth_status": "ok",
             "fetched_at": fu.iso(NOW - 120),
             "windows": [{"label": "7d", "utilization_pct": 50, "resets_at": FUTURE}]},
            {"name": "b", "active": False, "harness": "claude", "tier": "Pro",
             "fetch_status": "Cached", "auth_status": "expired",
             "windows": [{"label": "5h", "utilization_pct": 100, "resets_at": PAST},
                         {"label": "7d", "utilization_pct": 11, "resets_at": FUTURE}]},
            {"name": "c", "harness": "codex", "fetch_status": "Fresh", "windows": []},
        ],
    }

    def test_parse(self):
        active, accs = fu.parse_clauth_status(self.STATUS, NOW)
        self.assertEqual(active, "a")
        self.assertEqual([a["name"] for a in accs], ["a", "b", "c"])
        self.assertFalse(accs[0]["stale"])
        self.assertTrue(accs[1]["stale"])
        self.assertFalse(accs[1]["auth_ok"])
        # 5h de "b" resetou no passado: 0% usado
        self.assertEqual(accs[1]["windows"][0]["used_pct"], 0.0)
        self.assertEqual(accs[2]["provider"], "codex")

    def test_old_cache_is_stale_even_if_clauth_says_not(self):
        st = {"profiles": [{"name": "x", "stale": False, "fetched_at": fu.iso(NOW - 3600), "windows": []}]}
        self.assertTrue(fu.parse_clauth_status(st, NOW)[1][0]["stale"])

    def test_bad_format(self):
        with self.assertRaises(fu.SourceError):
            fu.parse_clauth_status({"x": 1}, NOW)


class CodexTest(unittest.TestCase):
    RESP = {
        "plan_type": "plus",
        "rate_limit": {
            "primary_window": {"used_percent": 12, "limit_window_seconds": 18000,
                               "reset_at": NOW + 3600},
            "secondary_window": {"used_percent": 2, "limit_window_seconds": 604800,
                                 "reset_at": NOW + 86400},
        },
    }

    def test_parse_live(self):
        plan, ws = fu.parse_codex_usage(self.RESP, NOW)
        self.assertEqual(plan, "plus")
        self.assertEqual([(w["key"], w["used_pct"]) for w in ws], [("5h", 12.0), ("7d", 2.0)])

    def session_line(self, used, ts="2027-01-10T00:00:00Z"):
        return json.dumps({"timestamp": ts, "type": "event_msg", "payload": {
            "type": "token_count", "rate_limits": {
                "primary": {"used_percent": used, "window_minutes": 300, "resets_at": NOW + 60},
                "secondary": {"used_percent": 1, "window_minutes": 10080, "resets_at": NOW + 600},
            }}})

    def test_latest_session_uses_last_line(self):
        with tempfile.TemporaryDirectory() as d:
            write(os.path.join(d, "sessions", "2027", "01", "01", "rollout-x.jsonl"),
                  "\n".join([self.session_line(10), '{"outro": 1}', self.session_line(42)]))
            ts, rl = fu.latest_session_rate_limits(d)
            self.assertEqual(rl["primary"]["used_percent"], 42)
            self.assertEqual(ts, fu.parse_iso("2027-01-10T00:00:00Z"))

    def test_expired_token_falls_back_to_session(self):
        with tempfile.TemporaryDirectory() as d:
            write(os.path.join(d, "auth.json"), {"tokens": {"access_token": jwt(NOW - 5)}})
            write(os.path.join(d, "sessions", "rollout-y.jsonl"), self.session_line(30))
            with mock.patch.object(fu, "http_get_json") as http:
                acc, err = fu.fetch_codex(d, 1, NOW)
                http.assert_not_called()
            self.assertEqual(err.code, "expired")
            self.assertEqual(acc["source"], "session")
            self.assertTrue(acc["stale"])
            self.assertEqual(acc["windows"][0]["used_pct"], 30.0)

    def test_network_error_without_sessions_raises(self):
        with tempfile.TemporaryDirectory() as d:
            write(os.path.join(d, "auth.json"), {"tokens": {"access_token": jwt(NOW + 999)}})
            with mock.patch.object(fu, "http_get_json", side_effect=fu.SourceError("network")):
                with self.assertRaises(fu.SourceError) as cm:
                    fu.fetch_codex(d, 1, NOW)
            self.assertEqual(cm.exception.code, "network")

    def test_live_sends_account_header(self):
        with tempfile.TemporaryDirectory() as d:
            write(os.path.join(d, "auth.json"),
                  {"tokens": {"access_token": jwt(NOW + 999), "account_id": "acc"}})
            with mock.patch.object(fu, "http_get_json", return_value=self.RESP) as http:
                acc, err = fu.fetch_codex(d, 1, NOW)
            self.assertIsNone(err)
            self.assertEqual(http.call_args[0][1]["ChatGPT-Account-Id"], "acc")
            self.assertEqual(acc["source"], "live")

    def test_missing_dir(self):
        with self.assertRaises(fu.SourceError) as cm:
            fu.fetch_codex("/nao/existe", 1, NOW)
        self.assertEqual(cm.exception.code, "not_found")


class EmailTest(unittest.TestCase):
    def test_codex_email_from_id_token(self):
        import base64
        claims = base64.urlsafe_b64encode(json.dumps({"email": "a@b.c"}).encode()).decode().rstrip("=")
        with tempfile.TemporaryDirectory() as d:
            write(os.path.join(d, "auth.json"), {"tokens": {"id_token": "h." + claims + ".s"}})
            self.assertEqual(fu.codex_email(d), "a@b.c")
        self.assertEqual(fu.codex_email("/nao/existe"), "")

    def test_claude_local_email_next_to_config_dir(self):
        with tempfile.TemporaryDirectory() as d:
            write(os.path.join(d, ".claude.json"), {"oauthAccount": {"emailAddress": "x@y.z"}})
            self.assertEqual(fu.claude_local_email(os.path.join(d, ".credentials.json")), "x@y.z")

    def profile(self, d, account_id, exp=NOW + 999):
        write(os.path.join(d, "account_id.json"), json.dumps(account_id))
        write(os.path.join(d, "credentials.json"),
              {"claudeAiOauth": {"accessToken": "t", "expiresAt": exp * 1000}})

    def test_clauth_email_fetched_once_then_cached(self):
        with tempfile.TemporaryDirectory() as d:
            self.profile(d, "acc-1")
            cache = {}
            resp = {"account": {"email": "p@q.r"}}
            with mock.patch.object(fu, "http_get_json", return_value=resp) as http:
                self.assertEqual(fu.clauth_profile_email(d, cache, 1, NOW), "p@q.r")
                self.assertEqual(fu.clauth_profile_email(d, cache, 1, NOW), "p@q.r")
            http.assert_called_once()
            self.assertEqual(cache, {"acc-1": "p@q.r"})

    def test_clauth_email_refetched_when_account_changes(self):
        with tempfile.TemporaryDirectory() as d:
            self.profile(d, "acc-2")
            cache = {"acc-1": "velho@x.y"}
            with mock.patch.object(fu, "http_get_json", return_value={"account": {"email": "novo@x.y"}}):
                self.assertEqual(fu.clauth_profile_email(d, cache, 1, NOW), "novo@x.y")

    def test_clauth_email_expired_token_never_calls_network(self):
        with tempfile.TemporaryDirectory() as d:
            self.profile(d, "acc-3", exp=NOW - 5)
            with mock.patch.object(fu, "http_get_json") as http:
                self.assertEqual(fu.clauth_profile_email(d, {}, 1, NOW), "")
            http.assert_not_called()

    def test_cache_file_is_private(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "sub", "emails.json")
            fu.save_email_cache(path, {"a": "b"})
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
            self.assertEqual(fu.load_email_cache(path), {"a": "b"})


class CollectTest(unittest.TestCase):
    CLAUTH = {"active_profile": "a", "profiles": [
        {"name": "a", "harness": "claude", "fetch_status": "Fresh", "windows": []},
        {"name": "b", "harness": "claude", "fetch_status": "Fresh", "windows": []},
    ]}
    LIVE = {"provider": "claude", "name": "Claude", "plan": "", "source": "live", "windows": []}

    def run_collect(self, clauth=None, clauth_error=None, daemon=True, **kw):
        """collect() com clauth e Claude direto substituidos por stubs."""
        found = "/bin/clauth" if (clauth is not None or clauth_error) else None
        patches = [
            mock.patch.object(fu, "find_clauth", return_value=found),
            mock.patch.object(fu, "fetch_clauth", side_effect=clauth_error, return_value=clauth),
            mock.patch.object(fu, "clauth_daemon_running", return_value=daemon),
            mock.patch.object(fu, "fetch_claude", return_value=dict(self.LIVE)),
            mock.patch.object(fu, "add_clauth_emails"),
        ]
        for p in patches:
            p.start()
        try:
            out = fu.collect(args(no_codex=True, **kw), NOW)
            return out, fu.fetch_claude
        finally:
            for p in patches:
                p.stop()

    def test_clauth_is_primary_and_skips_direct_claude(self):
        out, claude = self.run_collect(clauth=self.CLAUTH)
        self.assertEqual([a["name"] for a in out["accounts"]], ["a", "b"])
        claude.assert_not_called()
        self.assertTrue(out["clauth_daemon"])

    def test_reports_daemon_not_running(self):
        out, _ = self.run_collect(clauth=self.CLAUTH, daemon=False)
        self.assertIs(out["clauth_daemon"], False)

    def test_falls_back_to_direct_claude_without_clauth(self):
        out, claude = self.run_collect()
        claude.assert_called_once()
        self.assertEqual([a["source"] for a in out["accounts"]], ["live"])
        self.assertIsNone(out["clauth_daemon"])
        self.assertEqual(out["errors"], [], "clauth ausente sem caminho configurado nao e erro")

    def test_falls_back_when_clauth_fails(self):
        out, claude = self.run_collect(clauth_error=fu.SourceError("parse"))
        claude.assert_called_once()
        self.assertEqual([e["source"] for e in out["errors"]], ["clauth"])

    def test_clauth_disabled_uses_direct_claude(self):
        out, claude = self.run_collect(clauth=self.CLAUTH, no_clauth=True)
        claude.assert_called_once()

    def test_no_claude_disables_fallback(self):
        out, claude = self.run_collect(no_claude=True)
        claude.assert_not_called()
        self.assertEqual(out["accounts"], [])

    def test_configured_clauth_missing_is_error(self):
        out = fu.collect(args(no_claude=True, no_codex=True, clauth_bin="/x/clauth"), NOW)
        self.assertEqual([e["source"] for e in out["errors"]], ["clauth"])

    def test_all_missing_reports_errors(self):
        with mock.patch.object(fu, "find_clauth", return_value=None):
            out = fu.collect(args(claude_creds="/x/c.json", codex_home="/x/codex"), NOW)
        self.assertEqual(out["accounts"], [])
        self.assertEqual(sorted(e["source"] for e in out["errors"]), ["claude", "codex"])

    def test_disabled_sources_are_skipped(self):
        out = fu.collect(args(no_claude=True, no_codex=True, no_clauth=True), NOW)
        self.assertEqual(out, {"generated_at": fu.iso(NOW), "accounts": [], "errors": [],
                               "clauth_daemon": None})

    def test_errors_do_not_leak_response_body(self):
        err = fu.SourceError("auth", "HTTP 401")
        self.assertEqual(set(fu.error_entry("claude", err)), {"source", "code", "detail", "path"})


if __name__ == "__main__":
    unittest.main()
