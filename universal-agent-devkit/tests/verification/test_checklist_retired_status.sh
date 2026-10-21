#!/usr/bin/env bash
# Regression test (issue #18, AC2): a suite whose matrix entry is gone (its test module deleted) but whose row holds results
# stayed STALE for ever (its watched file is gone: "deleted since a clean run" is a stale hit). sync_from_matrix must mark such
# a row retired: status RETIRED, never STALE, out of the safety %; a bug linked only to it falls back to NEEDS_TEST.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
python3 - "$DEVKIT_DIR/bin" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import regression_checklist as rc

fails = 0
def check(ok, name):
    global fails
    print(("✔ " if ok else "✖ ") + name)
    fails += 0 if ok else 1

matrix = {"rules": [{"component": "core", "watch_files": ["src/*"],
                     "mandatory_regression_tests": [{"id": "REG-NOW", "name": "now", "command": "true"}]}]}
def fresh():
    return {"items": {
        "REG-NOW": {"id": "REG-NOW", "kind": "test", "last": {"status": "PASS"}, "history": [{"status": "PASS"}]},
        "REG-GONE": {"id": "REG-GONE", "kind": "test", "title": "gone", "last": {"status": "PASS"},
                     "history": [{"status": "PASS"}], "stale_since": "2026-01-01"},
        "BUG-1": {"id": "BUG-1", "kind": "bug", "fixed": True, "tests": ["REG-GONE"], "red_proof": {"status": "PROVEN"}},
    }}

d = fresh()
rc.sync_from_matrix(d, matrix)
it = d["items"]
check("REG-GONE" in it, "a retired row with results is kept")
check(rc.effective_status(d, it["REG-GONE"]) == "RETIRED", "a row the matrix no longer has is RETIRED, not STALE")
check(rc.effective_status(d, it["REG-NOW"]) == "PASS", "a matrix row is untouched")
check(rc.effective_status(d, it["BUG-1"]) == "NEEDS_TEST", "a bug linked only to a retired suite is not PASS")

# The real scenario: the suite's watched file was deleted after a clean run. A live suite is STALE, a retired one is not.
import os, pathlib, subprocess, tempfile
with tempfile.TemporaryDirectory() as tmp:
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    def vcs(*a):
        return subprocess.run(["git", "-C", tmp, "-c", "user.name=t", "-c", "user.email=t@t", *a], env=env,
                              capture_output=True, text=True, check=True).stdout.strip()
    vcs("init", "-q")
    (pathlib.Path(tmp) / "src").mkdir()
    (pathlib.Path(tmp) / "src" / "a.py").write_text("x\n")
    vcs("add", "."); vcs("commit", "-qm", "c")
    sha = vcs("rev-parse", "HEAD")
    (pathlib.Path(tmp) / "src" / "a.py").unlink()
    def row(retired):
        r = {"id": "R", "kind": "test", "watch_files": ["src/*"], "last": {"status": "PASS", "ts": 1, "commit": sha}}
        if retired:
            r["retired"] = True
        return r
    live = {"items": {"R": row(False)}}
    rc.mark_stale(live, pathlib.Path(tmp))
    check(rc.effective_status(live, live["items"]["R"]) == "STALE", "control: a live suite with a deleted watched file is STALE")
    gone = {"items": {"R": row(True)}}
    rc.mark_stale(gone, pathlib.Path(tmp))
    check(rc.effective_status(gone, gone["items"]["R"]) == "RETIRED", "a retired suite with a deleted watched file is not STALE")

back = {"rules": [{"component": "core", "watch_files": ["src/*"], "mandatory_regression_tests": [
    {"id": "REG-NOW", "name": "now", "command": "true"}, {"id": "REG-GONE", "name": "again", "command": "true"}]}]}
d["items"]["REG-GONE"].pop("stale_since", None)
rc.sync_from_matrix(d, back)
check(rc.effective_status(d, d["items"]["REG-GONE"]) == "PASS", "a suite back in the matrix is no longer retired")

# The dashboard: a module whose only problem is a retired row still folds.
with tempfile.TemporaryDirectory() as tmp:
    (pathlib.Path(tmp) / ".agents").mkdir()
    r = fresh()
    r["items"]["REG-NOW"]["component"] = r["items"]["REG-GONE"]["component"] = "core"
    rc.sync_from_matrix(r, matrix)
    out = rc.render(pathlib.Path(tmp), r).read_text(encoding="utf-8")
    check("1/1 PASS" in out and "✅ core" in out, "a module with a retired row folds as 1/1 PASS")

e = fresh()
rc.sync_from_matrix(e, {})
check(rc.effective_status(e, e["items"]["REG-GONE"]) != "RETIRED", "no matrix (none found): nothing is retired")

# Retiring never makes a bug or REQ greener.
q = fresh()
q["items"]["REG-GONE"]["last"] = {"status": "FAIL"}
q["items"]["BUG-2"] = {"id": "BUG-2", "kind": "bug", "fixed": True, "tests": ["REG-GONE", "REG-NOW"], "red_proof": {"status": "PROVEN"}}
rc.sync_from_matrix(q, matrix)
check(rc.effective_status(q, q["items"]["BUG-2"]) == "FAIL", "a bug linked to a retired RED suite stays FAIL")
r2 = fresh()
r2["items"]["REQ-1"] = {"id": "REQ-1", "kind": "req", "tests": ["REG-GONE", "REG-NOW"], "red_proof": {"status": "PROVEN"},
                        "criteria": [{"text": "a", "tests": ["REG-GONE"]}, {"text": "b", "tests": ["REG-NOW"]}]}
rc.sync_from_matrix(r2, matrix)
check(rc.effective_status(r2, r2["items"]["REQ-1"]) in ("NEEDS_TEST", "NOT_IN_MATRIX"),
      "a REQ criterion backed only by a retired suite is not PASS")

print("✅ test_checklist_retired_status: all passed" if not fails else "❌ test_checklist_retired_status: %d failed" % fails)
sys.exit(1 if fails else 0)
PY
