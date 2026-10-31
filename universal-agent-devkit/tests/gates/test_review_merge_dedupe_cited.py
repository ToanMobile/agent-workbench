#!/usr/bin/env python3
"""review-merge.py dedupe(): a finding cite-check dropped never backs a cluster (2/2 review of #742, r14d, BUG-REV-9516f93323).
  1. reviewer A's cited P1 + reviewer B's uncited finding at the same file:line: the cluster is A's alone — not "consensus", so one
     verifier may still refute it (_vetoable)
  2. reviewer B votes "fail" on an uncited P0 that dedupe joins to A's cited P2: B's fail rests on no evidence, the run is not FAILed
     for it (INSTINCT-088)
DK_BIN overrides the bin dir (the RED run points it at the previous commit's copy)."""
import importlib.util
import os
import sys
import tempfile

BIN = os.environ.get("DK_BIN") or os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "bin")
sys.dont_write_bytecode = True
sys.path.insert(0, BIN)
spec = importlib.util.spec_from_file_location("review_merge", os.path.join(BIN, "review-merge.py"))
rm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rm)

FAILS = []


def check(cond, msg):
    print(("✔ " if cond else "✖ ") + msg)
    if not cond:
        FAILS.append(msg)


repo = tempfile.mkdtemp()
with open(os.path.join(repo, "app.py"), "w") as fh:
    fh.write("def g(items):\n    return items[0]\n\n\ndef h():\n    pass\n")


def env(findings, verdict):
    return {"status": "ok", "verdict": verdict, "model": "claude-opus-4-5", "findings": findings}


meta = {"required": ["claude", "antigravity", "registry"], "skipped_by_override": ["grok", "ocr"], "depth": "light",
        "models": {"claude": "opus", "antigravity": "gemini-4-argon-high"}}

# 1. A cited P1, B uncited (wrong snippet) at the same line
a1 = {"severity": "P1", "category": "bug", "file": "app.py", "line": 2, "snippet": "return items[0]", "problem": "IndexError on empty list"}
b1 = {"severity": "P1", "category": "bug", "file": "app.py", "line": 2, "snippet": "items.pop()", "problem": "IndexError on empty list"}
envs = {"claude": env([a1], "fail"), "antigravity": dict(env([b1], "fail"), model="gemini-4-argon-high"),
        "registry": {"status": "ok", "verdict": "pass", "findings": []}}
cl = rm.analyse(repo, meta, envs, ents=[])
c = next(x for x in cl if x["file"] == "app.py" and x["line"] == 2)
check(c["reviewers"] == ["claude"], f"case 1: the cluster is backed by the cited reviewer only (got {c['reviewers']})")
check(not c["consensus"], "case 1: an uncited member does not make it consensus")
check(rm._vetoable(c), "case 1: one verifier can still refute it")
rm.apply_verifications(cl, {"status": "ok", "verifications": [{"id": c["id"], "refuted": True, "reason": "items is never empty"}]})
check(c["state"] == "refuted", f"case 1: the verifier's refutation stands (state {c['state']})")

# 2. B fails only on an uncited P0 joined to A's cited P2
a2 = {"severity": "P2", "category": "style", "file": "app.py", "line": 6, "snippet": "pass", "problem": "empty function body h"}
b2 = {"severity": "P0", "category": "style", "file": "app.py", "line": 5, "snippet": "rm -rf /", "problem": "empty function body h"}
envs = {"claude": env([a2], "pass"), "antigravity": dict(env([b2], "fail"), model="gemini-4-argon-high"),
        "registry": {"status": "ok", "verdict": "pass", "findings": []}}
cl = rm.analyse(repo, meta, envs, ents=[])
rm.apply_verifications(cl, None)
verdict, reasons, _ = rm.decide(meta, envs, cl, rev={}, rev_err="")
check(not any(r.startswith("antigravity: verdict") for r in reasons),
      f"case 2: a fail resting only on a cite-dropped P0 does not FAIL the run (reasons {reasons})")
check(verdict == "PASS", f"case 2: verdict PASS (got {verdict})")

# control: B's fail with its OWN cited blocking finding still FAILs
b3 = {"severity": "P1", "category": "bug", "file": "app.py", "line": 2, "snippet": "return items[0]", "problem": "IndexError on empty list"}
envs = {"claude": env([], "pass"), "antigravity": dict(env([b3], "fail"), model="gemini-4-argon-high"),
        "registry": {"status": "ok", "verdict": "pass", "findings": []}}
cl = rm.analyse(repo, meta, envs, ents=[])
rm.apply_verifications(cl, None)
verdict, reasons, _ = rm.decide(meta, envs, cl, rev={}, rev_err="")
check(verdict == "FAIL", f"control: a cited unrefuted P1 still FAILs (got {verdict})")

print("review-merge dedupe cited: " + ("all checks passed" if not FAILS else f"FAILS={len(FAILS)}"))
sys.exit(1 if FAILS else 0)
