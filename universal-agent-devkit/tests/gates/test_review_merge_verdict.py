#!/usr/bin/env python3
"""bin/review-merge.py: the 4-way review passes ONLY when Claude Code (on Opus), Antigravity, Grok (pinned model) and OCR all
ran and all said pass (user 31/10/2026),
with no unrefuted P0/P1, no recurring known bug, the budget kept and every accepted P0/P1 fixed with a regression test.
Also bin/known_patterns.py (the registry over .agents/instincts.md) and instincts.py --detect."""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / "bin"))
spec = importlib.util.spec_from_file_location("review_merge", ROOT / "bin" / "review-merge.py")
rm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rm)
import known_patterns as kp  # noqa: E402

INSTINCTS = """# Instincts
### [INSTINCT-001] Silent except
- **Nguyên nhân:** swallowed errors
- **Quy tắc phòng ngừa & Cách fix:** log it
- **detect:** `^\\s*except\\s*:\\s*pass\\s*$`
- **detect-glob:** `*.py`

---

### [INSTINCT-002] Prose only
- **Quy tắc phòng ngừa & Cách fix:** nothing machine-checkable
"""
CODE = "def f(x):\n    try:\n        return 1 / x\n    except: pass\n\n\n\ndef g(items):\n    return items[0]\n"


def git(repo, *a):
    subprocess.run(["git", "-C", repo, *a], check=True, capture_output=True)


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = os.path.realpath(self.tmp.name)
        git(self.repo, "init", "-q")
        git(self.repo, "config", "user.email", "t@t")
        git(self.repo, "config", "user.name", "t")
        os.makedirs(os.path.join(self.repo, ".agents"))
        Path(self.repo, ".agents/instincts.md").write_text(INSTINCTS, encoding="utf-8")
        Path(self.repo, "README").write_text("x\n")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-qm", "init")
        Path(self.repo, "app.py").write_text(CODE)
        self.meta = {"required": ["claude", "antigravity", "grok", "ocr", "registry"], "depth": "light", "base": "HEAD",
                     "code_hash": "h", "max_tokens": 1000, "max_usd": 1.0, "models": {"claude": "opus", "grok": "grok-4.7"}}

    def tearDown(self):
        self.tmp.cleanup()

    MODELS = {"claude": "claude-opus-4-5", "security": "claude-opus-4-5", "verifier": "claude-opus-4-5", "grok": "grok-4.7"}

    def env(self, name, verdict="pass", status="ok", findings=None, tokens=10, usd=0.01, **kw):
        e = {"reviewer": name, "status": status, "verdict": verdict, "findings": findings or [],
             "usage": {"tokens": tokens, "usd": usd}}
        if name in self.MODELS:
            e["model"] = self.MODELS[name]
        e.update(kw)
        return e

    def all_pass(self):
        return {n: self.env(n) for n in ("claude", "antigravity", "grok", "ocr", "registry")}

    def verdict(self, envs, meta=None, rev=None):
        meta = meta or self.meta
        clusters = rm.analyse(self.repo, meta, envs)
        rm.apply_verifications(clusters, envs.get("verifier"))
        v, reasons, _ = rm.decide(meta, envs, clusters, {} if rev is None else rev, "")
        return v, reasons, clusters


class Unanimity(Base):
    def test_unanimous_pass(self):
        v, reasons, _ = self.verdict(self.all_pass())
        self.assertEqual((v, reasons), ("PASS", []))

    def test_one_reviewer_fails(self):
        for who in ("claude", "antigravity", "grok", "ocr"):
            envs = self.all_pass()
            envs[who] = self.env(who, verdict="fail")
            v, reasons, _ = self.verdict(envs)
            self.assertEqual(v, "FAIL", who)
            self.assertTrue(any(r.startswith(who + ": verdict fail") for r in reasons), reasons)

    def test_one_reviewer_missing(self):
        for who in ("claude", "antigravity", "grok", "ocr"):
            envs = self.all_pass()
            del envs[who]
            v, reasons, _ = self.verdict(envs)
            self.assertEqual(v, "FAIL", who)
            self.assertTrue(any(who + ": missing" in r for r in reasons), reasons)

    def test_core_reviewer_required_even_if_meta_omits_it(self):
        for who in ("antigravity", "grok"):
            envs = self.all_pass()
            del envs[who]
            meta = dict(self.meta, required=["claude", "ocr"])
            self.assertEqual(self.verdict(envs, meta)[0], "FAIL", who)

    def test_grok_missing_is_fail(self):
        envs = self.all_pass()
        del envs["grok"]
        v, reasons, _ = self.verdict(envs)
        self.assertEqual(v, "FAIL")
        self.assertIn("grok: missing — the reviewer produced no result", reasons)

    def test_grok_unavailable_or_out_of_credit_is_fail(self):
        envs = self.all_pass()
        envs["grok"] = self.env("grok", status="failed", reason="grok rc=1: 402 usage balance exhausted", model="")
        v, reasons, _ = self.verdict(envs)
        self.assertEqual(v, "FAIL")
        self.assertTrue(any(r.startswith("grok: failed") for r in reasons), reasons)

    def test_four_way_is_exactly_the_core(self):
        self.assertEqual(set(rm.CORE), {"claude", "antigravity", "grok", "ocr"})


class Models(Base):
    def test_claude_ran_non_opus_model_is_fail(self):
        for model in ("claude-sonnet-4-5", "claude-haiku-4-5", "claude-3-5-sonnet-20241022"):
            envs = self.all_pass()
            envs["claude"] = self.env("claude", model=model)
            v, reasons, _ = self.verdict(envs)
            self.assertEqual(v, "FAIL", model)
            self.assertIn(f"claude: ran {model}, the review requires Claude Opus", reasons)

    def test_claude_model_not_recorded_is_fail(self):
        envs = self.all_pass()
        envs["claude"].pop("model")
        v, reasons, _ = self.verdict(envs)
        self.assertEqual(v, "FAIL")
        self.assertTrue(any(r.startswith("claude: model not recorded") for r in reasons), reasons)

    def test_security_and_verifier_must_be_opus_too(self):
        meta = dict(self.meta, depth="deep", required=self.meta["required"] + ["security", "verifier"])
        for who in ("security", "verifier"):
            envs = self.all_pass()
            envs["security"] = self.env("security")
            envs["verifier"] = {"reviewer": "verifier", "status": "ok", "verifications": [], "model": "claude-opus-4-5"}
            envs[who]["model"] = "claude-sonnet-4-5"
            v, reasons, _ = self.verdict(envs, meta)
            self.assertEqual(v, "FAIL", who)
            self.assertTrue(any(r.startswith(f"{who}: ran claude-sonnet-4-5") for r in reasons), reasons)

    def test_non_opus_verifier_cannot_refute_even_at_light_depth(self):
        envs = self.all_pass()
        envs["ocr"]["findings"] = [Findings.P1]
        cid = rm.analyse(self.repo, self.meta, envs)[0]["id"]
        envs["verifier"] = {"reviewer": "verifier", "status": "ok", "model": "claude-haiku-4-5",
                            "verifications": [{"id": cid, "refuted": True, "reason": "trust me"}]}
        v, reasons, _ = self.verdict(envs)
        self.assertEqual(v, "FAIL")
        self.assertTrue(any(r.startswith("verifier: ran claude-haiku-4-5") for r in reasons), reasons)

    def test_skipped_verifier_needs_no_model(self):
        meta = dict(self.meta, depth="deep", required=self.meta["required"] + ["security", "verifier"])
        envs = self.all_pass()
        envs["security"] = self.env("security")
        envs["verifier"] = {"reviewer": "verifier", "status": "ok", "verifications": [], "skipped": True, "model": ""}
        self.assertEqual(self.verdict(envs, meta)[0], "PASS")

    def test_grok_wrong_or_unrecorded_model_is_fail(self):
        envs = self.all_pass()
        envs["grok"]["model"] = "grok-4.5"
        v, reasons, _ = self.verdict(envs)
        self.assertEqual(v, "FAIL")
        self.assertIn("grok: ran grok-4.5, the review pins grok-4.7", reasons)
        envs["grok"]["model"] = ""
        self.assertEqual(self.verdict(envs)[0], "FAIL")

    def test_runner_picks_the_model_that_wrote_the_answer(self):
        import importlib
        rr = importlib.import_module("review_runner")
        res = {"modelUsage": {"claude-haiku-4-5": {"outputTokens": 40}, "claude-opus-4-5": {"outputTokens": 2000}}}
        self.assertEqual(rr.models_used(res)[0], "claude-opus-4-5")
        self.assertIsNone(rr.model_problem("claude", "claude-opus-4-5", "opus"))
        res = {"modelUsage": {"claude-sonnet-4-5": {"outputTokens": 2000}, "claude-opus-4-5": {"outputTokens": 3}}}
        self.assertIn("requires Opus", rr.model_problem("claude", rr.models_used(res)[0], "opus"))
        self.assertIn("did not report", rr.model_problem("claude", rr.models_used({})[0], "opus"))
        self.assertIn("pins grok-4.7", rr.model_problem("grok", "grok-4.6", "grok-4.7"))

    def test_timeout_error_unavailable_failed_are_fail(self):
        for st in ("timeout", "error", "unavailable", "failed", None):
            envs = self.all_pass()
            envs["ocr"] = self.env("ocr", status=st, reason="x")
            v, reasons, _ = self.verdict(envs)
            self.assertEqual(v, "FAIL", st)
            self.assertTrue(any(r.startswith("ocr: ") for r in reasons), reasons)

    def test_status_ok_but_no_verdict_is_fail(self):
        envs = self.all_pass()
        envs["claude"].pop("verdict")
        self.assertEqual(self.verdict(envs)[0], "FAIL")

    def test_deep_needs_security_and_verifier(self):
        meta = dict(self.meta, depth="deep", required=self.meta["required"] + ["security", "verifier"])
        v, reasons, _ = self.verdict(self.all_pass(), meta)
        self.assertEqual(v, "FAIL")
        self.assertTrue(any("security: missing" in r for r in reasons) and any("verifier: missing" in r for r in reasons))
        envs = self.all_pass()
        envs["security"] = self.env("security")
        envs["verifier"] = {"reviewer": "verifier", "status": "ok", "verifications": [], "model": "claude-opus-4-5"}
        self.assertEqual(self.verdict(envs, meta)[0], "PASS")


class Findings(Base):
    P1 = {"severity": "high", "path": "app.py", "start_line": 9, "content": "items may be empty: IndexError"}

    def test_pass_verdict_with_cited_p1_is_still_fail(self):
        envs = self.all_pass()
        envs["ocr"]["findings"] = [self.P1]
        v, reasons, cl = self.verdict(envs)
        self.assertEqual(v, "FAIL")
        self.assertEqual(cl[0]["state"], "blocking")

    def test_uncited_finding_is_dropped(self):
        envs = self.all_pass()
        envs["claude"]["findings"] = [{"severity": "P0", "file": "app.py", "line": 9, "snippet": "rm -rf /", "problem": "x"},
                                      {"severity": "P0", "file": "nope.py", "line": 1, "snippet": "a", "problem": "y"},
                                      {"severity": "P0", "file": "app.py", "line": 9, "problem": "no snippet"}]
        v, _, cl = self.verdict(envs)
        self.assertEqual(v, "PASS")
        self.assertTrue(all(c["state"] == "uncited" for c in cl))

    def test_dedupe_consensus_across_reviewers(self):
        envs = self.all_pass()
        envs["ocr"]["findings"] = [self.P1]
        envs["claude"]["findings"] = [{"severity": "P1", "category": "bug", "file": "app.py", "line": 9,
                                       "snippet": "return items[0]", "problem": "IndexError when items is empty"}]
        envs["antigravity"]["findings"] = [{"severity": "major", "file": "app.py:9", "snippet": "return items[0]",
                                            "problem": "empty list IndexError"}]
        _, _, cl = self.verdict(envs)
        self.assertEqual(len(cl), 1)
        self.assertEqual(cl[0]["reviewers"], ["antigravity", "claude", "ocr"])
        self.assertTrue(cl[0]["consensus"])
        self.assertFalse(cl[0]["unanimous"])   # 3 of 4: Grok did not report it
        envs["grok"]["findings"] = [{"severity": "P1", "category": "bug", "file": "app.py", "line": 9,
                                     "snippet": "return items[0]", "problem": "items[0] on an empty list"}]
        _, _, cl = self.verdict(envs)
        self.assertEqual(cl[0]["reviewers"], ["antigravity", "claude", "grok", "ocr"])
        self.assertTrue(cl[0]["consensus"] and cl[0]["unanimous"])

    def test_refuted_p1_downgraded_and_pass(self):
        envs = self.all_pass()
        envs["ocr"]["findings"] = [self.P1]
        cid = rm.analyse(self.repo, self.meta, envs)[0]["id"]
        envs["verifier"] = {"reviewer": "verifier", "status": "ok",
                            "verifications": [{"id": cid, "refuted": True, "reason": "callers never pass []"}],
                            "model": "claude-opus-4-5"}
        v, _, cl = self.verdict(envs)
        self.assertEqual(v, "PASS")
        self.assertEqual((cl[0]["state"], cl[0]["severity"], cl[0]["original_severity"]), ("refuted", "P3", "P1"))

    def test_severity_normalisation(self):
        for raw, want in (("critical", "P0"), ("blocker", "P0"), ("high", "P1"), ("major", "P1"), ("medium", "P2"),
                          ("minor", "P2"), ("low", "P3"), ("nit", "P3"), ("P1", "P1")):
            self.assertEqual(rm.norm_sev(raw), want, raw)


class Recurring(Base):
    def test_registry_scan_flags_added_line(self):
        env = kp.scan(self.repo, "HEAD")
        self.assertEqual(env["verdict"], "fail")
        self.assertEqual(env["findings"][0]["known_pattern"], "INSTINCT-001")
        self.assertEqual(env["findings"][0]["line"], 4)

    def test_registry_hit_is_irrefutable_p0(self):
        envs = self.all_pass()
        envs["registry"] = kp.scan(self.repo, "HEAD")
        cid = rm.analyse(self.repo, self.meta, envs)[0]["id"]
        envs["verifier"] = {"reviewer": "verifier", "status": "ok", "verifications": [{"id": cid, "refuted": True}]}
        v, _, cl = self.verdict(envs)
        self.assertEqual(v, "FAIL")
        self.assertEqual((cl[0]["severity"], cl[0]["state"], cl[0]["category"]), ("P0", "blocking", "recurring-bug"))

    def test_llm_finding_matching_pattern_becomes_p0(self):
        envs = self.all_pass()
        envs["claude"]["findings"] = [{"severity": "P3", "file": "app.py", "line": 4, "snippet": "except:",
                                       "problem": "bare except swallows ZeroDivisionError"}]
        envs["claude"]["findings"][0]["snippet"] = "except: pass"
        envs["claude"]["findings"][0]["known_pattern"] = "INSTINCT-001"
        v, _, cl = self.verdict(envs)
        self.assertEqual((v, cl[0]["severity"], cl[0]["known_pattern"]), ("FAIL", "P0", "INSTINCT-001"))

    def test_glob_limits_detect(self):
        Path(self.repo, "notes.md").write_text("except: pass\n")
        hits = [f["file"] for f in kp.scan(self.repo, "HEAD")["findings"]]
        self.assertNotIn("notes.md", hits)

    def test_semgrep_rules_generated(self):
        y = kp.semgrep_yaml(kp.entries(self.repo))
        self.assertIn("id: instinct-001", y)
        self.assertIn("pattern-regex:", y)
        self.assertNotIn("instinct-002", y)

    def test_instincts_add_detect(self):
        r = subprocess.run([sys.executable, str(ROOT / "bin" / "instincts.py"), "add", "Null deref of items", "--rule", "guard",
                            "--detect", r"items\[0\]", "--detect-glob", "*.py", "--file", str(Path(self.repo, ".agents/instincts.md"))],
                           capture_output=True, text=True, env=dict(os.environ, CLAUDE_PROJECT_DIR=self.repo))
        self.assertEqual(r.returncode, 0, r.stderr)
        ids = [e["id"] for e in kp.entries(self.repo) if e["detect"]]
        self.assertEqual(len(ids), 2)
        r = subprocess.run([sys.executable, str(ROOT / "bin" / "instincts.py"), "add", "bad", "--detect", "(", "--file",
                            str(Path(self.repo, ".agents/instincts.md"))], capture_output=True, text=True)
        self.assertNotEqual(r.returncode, 0)


class RegressionLink(Base):
    def test_accepted_finding_without_test_blocks(self):
        for st in ("OPEN", "NEEDS_TEST", "NOT_IN_MATRIX", "NOT_RUN", "FAIL", "VACUOUS"):
            v, reasons, _ = self.verdict(self.all_pass(), rev={"BUG-REV-abc": st})
            self.assertEqual(v, "FAIL", st)
            self.assertTrue(any("BUG-REV-abc" in r and "regression test" in r for r in reasons), reasons)

    def test_fixed_with_passing_test_passes(self):
        self.assertEqual(self.verdict(self.all_pass(), rev={"BUG-REV-abc": "PASS"})[0], "PASS")

    def test_checklist_unreadable_is_fail(self):
        envs = self.all_pass()
        cl = rm.analyse(self.repo, self.meta, envs)
        v, reasons, _ = rm.decide(self.meta, envs, cl, None, "boom")
        self.assertEqual(v, "FAIL")


class Budget(Base):
    def test_tokens_over_budget(self):
        envs = self.all_pass()
        envs["claude"]["usage"]["tokens"] = 5000
        v, reasons, _ = self.verdict(envs)
        self.assertEqual(v, "FAIL")
        self.assertTrue(any("REVIEW_MAX_TOKENS" in r for r in reasons))

    def test_usd_over_budget(self):
        envs = self.all_pass()
        envs["antigravity"]["usage"]["usd"] = 2.5
        self.assertEqual(self.verdict(envs)[0], "FAIL")


class Cli(Base):
    def test_cli_writes_summary_and_outcome(self):
        run = Path(self.repo, "run")
        run.mkdir()
        (run / "meta.json").write_text(json.dumps(self.meta))
        for n, e in self.all_pass().items():
            (run / f"{n}.json").write_text(json.dumps(e))
        (run / "antigravity.json").write_text(json.dumps(self.env("antigravity", status="timeout", reason="no audit")))
        out = Path(self.repo, "outcomes.jsonl")
        r = subprocess.run([sys.executable, str(ROOT / "bin" / "review-merge.py"), "--dir", str(run), "--repo", self.repo,
                            "--outcomes", str(out)], capture_output=True, text=True)
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        s = json.loads((run / "summary.json").read_text())
        self.assertEqual(s["verdict"], "FAIL")
        self.assertTrue(any(x.startswith("antigravity: timeout") for x in s["reasons"]))
        self.assertEqual(json.loads(out.read_text().splitlines()[-1])["verdict"], "FAIL")


if __name__ == "__main__":
    unittest.main(verbosity=1)
