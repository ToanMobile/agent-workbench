"""Secrets typed in a Claude Code transcript must not reach /api/state."""
import json, os, sys, tempfile, types, unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
import server  # noqa: E402

# Fake values built at runtime so no token-shaped literal sits in the repo.
GH = "gh" + "p_" + "A1b2" * 9
PAT = "github" + "_pat_" + "Z9y8" * 6
ANT = "sk" + "-ant-" + "Q7w3" * 6
PWD = "Fake" + "Pass" + "12345"
BEARER = "Tok" + "en" + "Qq9" * 7
SECRETS = [GH, PAT, ANT, PWD, BEARER]


AWS = "AK" + "IA" + "ABCDEFGH12345678"
SLACK = "xo" + "xb-" + "1234567890-abcdefghij"
JWT = "ey" + "JhbGciOiJIUzI1NiJ9." + "ey" + "JzdWIiOiIxMjM0NTY3ODkwIn0." + "SflKxwRJSMeKKF2QT4fw"
PEM_BODY = "MIIEvQIBADANBgkqhkiG9w0BAQEFAASC"
PEM = "-----BEGIN RSA PRIVATE " + "KEY-----\n" + PEM_BODY + "\n-----END RSA PRIVATE " + "KEY-----"
SPACED = "Spaced" + "Secret" + "Val99"
BASIC = "dXNlcjpwYXNz" + "d29yZDEyMw=="


def parse(blocks):
    line = json.dumps({"type": "assistant", "timestamp": "2026-10-22T10:00:00Z", "message": {"content": blocks}})
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "s.jsonl")
        with open(p, "w") as f:
            f.write(line + "\n")
        me = types.SimpleNamespace(cache={}, TAIL=600_000)
        return server.LocalScanner.parse_session(me, p)


class Redact(unittest.TestCase):
    def test_tool_command_secrets_masked(self):
        cmds = [f"export GH_TOKEN={GH} && gh api user",
                f"curl -H 'Authorization: Bearer {BEARER}' https://x",
                f"git clone https://x:{PAT}@github.com/a/b",
                f"ANTHROPIC_API_KEY={ANT} claude",
                f"mysql --password={PWD} -e 'select 1'"]
        s = parse([{"type": "tool_use", "name": "Bash", "input": {"command": c}} for c in cmds])
        out = json.dumps(s["tools"])
        for secret in SECRETS:
            self.assertNotIn(secret, out)

    def test_assistant_text_secrets_masked(self):
        s = parse([{"type": "text", "text": f"token is {GH} and PASSWORD={PWD}"}])
        out = json.dumps(s["texts"])
        self.assertNotIn(GH, out)
        self.assertNotIn(PWD, out)

    def test_quoted_and_json_forms_masked(self):
        s = parse([{"type": "tool_use", "name": "mcp__x__call", "input": {"api_key": PWD + "ABC", "n": 1}},
                   {"type": "tool_use", "name": "Bash", "input": {"command": f'export FOO_SECRET="{SPACED} tail words"'}}])
        out = json.dumps(s["tools"])
        self.assertNotIn(PWD + "ABC", out)
        self.assertNotIn(SPACED, out)
        self.assertNotIn("tail words", out)

    def test_other_credential_families_masked(self):
        cmds = [f"export AWS_ACCESS_KEY_ID={AWS}", f"echo {AWS}", f"curl -u x -H 'X: {SLACK}'", f"curl {JWT}",
                f"echo '{PEM}'", f"curl -H 'Authorization: Basic {BASIC}' u", f"tool --token {SPACED} run",
                f"STRIPE_KEY={SPACED}", f"AUTH={SPACED}"]
        s = parse([{"type": "tool_use", "name": "Bash", "input": {"command": c}} for c in cmds])
        out = json.dumps(s["tools"])
        for secret in (AWS, SLACK, JWT, PEM_BODY, BASIC, SPACED):
            self.assertNotIn(secret, out)

    def test_secret_straddling_the_length_cut_is_masked(self):
        cmd = "x" * 590 + " GH_TOKEN=" + GH
        s = parse([{"type": "tool_use", "name": "Bash", "input": {"command": cmd}}])
        self.assertNotIn(GH[:8], json.dumps(s["tools"]))

    def test_redact_is_linear_enough(self):
        import time
        t = time.time()
        server.redact("token" * 300)
        server.redact("a" * 1500)
        self.assertLess(time.time() - t, 0.3)

    def test_ordinary_prose_not_over_masked(self):
        for text in ("sk-learn and task-scheduler-option-thing-here", "Fixed token: expiry is now 5 min",
                     "the password reset flow: passwordField = x", "tests/test_token_refresh.py -k api_key",
                     "total_tokens left 123456", "mkdir -p build/out"):
            self.assertEqual(server.redact(text), text)

    def test_normal_command_unchanged(self):
        s = parse([{"type": "tool_use", "name": "Bash", "input": {"command": "python3 -m unittest tests.test_x"}}])
        self.assertEqual(s["tools"][0]["summary"], "python3 -m unittest tests.test_x")


if __name__ == "__main__":
    unittest.main()
