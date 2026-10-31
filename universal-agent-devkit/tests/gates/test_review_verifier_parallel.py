#!/usr/bin/env python3
"""BUG-REV-review-verifier-parallel — the verifier checks many P0/P1 candidates in parallel batches (REVIEW_VERIFIER_BATCH),
answers for every id, and fails closed when any batch fails (stub claude, no LLM)."""
import json, os, stat, subprocess, sys, tempfile, time, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
RUNNER = os.path.join(os.path.dirname(os.path.dirname(HERE)), "bin", "review_runner.py")
STUB = r'''#!/usr/bin/env python3
import json, re, sys, time
p = sys.stdin.read()
time.sleep(1.0)
ids = [i for i in re.findall(r'"id": "([^"]+)"', p) if i != "<id>"]
if "bad" in ids:
    print(json.dumps({"type": "result", "is_error": True, "result": "boom"})); sys.exit(1)
ans = {"verifications": [{"id": i, "refuted": False, "reason": "stands"} for i in ids]}
print(json.dumps({"type": "result", "is_error": False, "result": json.dumps(ans), "total_cost_usd": 0.01,
                  "usage": {"input_tokens": 10, "output_tokens": 2}, "modelUsage": {"claude-opus-4-5": {"outputTokens": 2}}}))
'''


class VerifierParallel(unittest.TestCase):
    def setUp(self):
        self.t = tempfile.mkdtemp()
        self.run_dir = os.path.join(self.t, "run")
        os.makedirs(self.run_dir)
        self.stub = os.path.join(self.t, "claude")
        with open(self.stub, "w") as fh:
            fh.write(STUB)
        os.chmod(self.stub, os.stat(self.stub).st_mode | stat.S_IXUSR)
        with open(os.path.join(self.run_dir, "meta.json"), "w") as fh:
            json.dump({"repo": self.t, "base": "HEAD", "depth": "deep", "models": {"claude": "opus"}}, fh)

    def go(self, ids):
        with open(os.path.join(self.run_dir, "candidates.json"), "w") as fh:
            json.dump([{"id": i, "severity": "P1", "file": "a.py", "line": 1, "problem": "x"} for i in ids], fh)
        env = dict(os.environ, REVIEW_CLAUDE_BIN=self.stub, REVIEW_VERIFIER_BATCH="2", REVIEW_CLAUDE_MODEL="opus")
        t0 = time.time()
        subprocess.run([sys.executable, RUNNER, "verifier", "--repo", self.t, "--run", self.run_dir, "--timeout", "60"], env=env,
                       capture_output=True, text=True)
        with open(os.path.join(self.run_dir, "verifier.json")) as fh:
            return json.load(fh), time.time() - t0

    def test_batches_run_in_parallel_and_cover_every_id(self):
        ids = [f"c{i}" for i in range(7)]   # 4 batches of <= 2, each stub call sleeps 1 s
        env, wall = self.go(ids)
        self.assertEqual(env["status"], "ok", env)
        self.assertEqual(sorted(v["id"] for v in env["verifications"]), sorted(ids))
        self.assertEqual(env.get("batches"), 4)
        self.assertLess(wall, 3.5, f"batches did not run in parallel ({wall:.1f}s for 4 x 1 s)")

    def test_one_failed_batch_fails_the_verifier(self):
        env, _ = self.go(["c1", "c2", "bad", "c3"])
        self.assertNotEqual(env["status"], "ok")
        self.assertIn("batch", env.get("reason", ""))


if __name__ == "__main__":
    unittest.main(verbosity=1)
