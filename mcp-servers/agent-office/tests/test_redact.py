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

    def test_normal_command_unchanged(self):
        s = parse([{"type": "tool_use", "name": "Bash", "input": {"command": "python3 -m unittest tests.test_x"}}])
        self.assertEqual(s["tools"][0]["summary"], "python3 -m unittest tests.test_x")


if __name__ == "__main__":
    unittest.main()
