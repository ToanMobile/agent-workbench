#!/usr/bin/env bash
# Regression test: a run that ends UNVERIFIED (exit 2: an edited test waits for review, a code file nothing covers, ...)
# must not make the next --full run every suite again on the SAME code.
# 2026-10-07 (OfficeReader, GeelyEx2: runs.jsonl): after a --full PASS, a Stop-hook run that ended exit != 0 deleted
# full_pass.json, and the next --full ran every suite again (OfficeReader 12:49 -> 12:52: 652 s; GeelyEx2 20:35 -> 20:51:
# 387 s); a --full that itself ended exit 2 left no receipt either, so the "run again with --auto-approve-tests" repeated
# every suite (OfficeReader 14:46 -> 14:51: 269 s, then 254 s).
# What stays as it was: only a receipt with "exit": 0 is accepted by hooks/proof_gate.sh and bin/push_gate.py (both test
# `exit != 0`), so XONG and push are still refused after an exit 2; a suite that FAILED, or code that changed since, still
# leaves nothing to reuse (cached_full_pass checks fingerprint, matrix, result format, local state and age as before).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export VACUITY_REVERT=0
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

PY="${PYTHON:-python3}"
export TMP DEVKIT_DIR
cat > "$TMP/t.py" <<'PY'
import importlib.util, inspect, json, os, subprocess, sys
dk = os.environ["DEVKIT_DIR"]
sys.path.insert(0, os.path.join(dk, "bin"))
spec = importlib.util.spec_from_file_location("pfg", os.path.join(dk, "bin", "post-fix-gate.py"))
pfg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pfg)
import tree_fp

TMP = os.environ["TMP"]
ENV = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
repo = os.path.join(TMP, "repo")
os.makedirs(repo)
def git(*a):
    return subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True, env=ENV).stdout.strip()
git("init", "-q", ".")
open(os.path.join(repo, "a.txt"), "w").write("a\n")
matrix = os.path.join(repo, "matrix.json")
open(matrix, "w").write(json.dumps({"project": "t", "rules": []}))
git("add", "-A")
git("commit", "-qm", "init")
open(os.path.join(repo, "a.txt"), "a").write("edit\n")          # a dirty tree: something to fingerprint

PASS = lambda i: {"id": i, "status": "PASS", "command": "true", "duration": "3s", "log": None}
FAIL = lambda i: {"id": i, "status": "FAIL", "command": "false", "duration": "3s", "log": None}
SUITES = [PASS("T1"), PASS("T2")]
rp = tree_fp.receipt_path(repo)

def write(exit_code, tests, partial=False, tested_fp=None):
    # `partial` is the new argument; against the old code the call is made without it (a partial run is then
    # indistinguishable, which is the old behaviour under test)
    kw = {"partial": True} if partial and "partial" in inspect.signature(pfg.write_full_pass_receipt).parameters else {}
    pfg.write_full_pass_receipt(repo, exit_code, matrix, tests, tested_fp=tested_fp, **kw)

def receipt():
    try:
        return json.load(open(rp))
    except (OSError, ValueError):
        return None

def reusable():
    r = pfg.cached_full_pass(repo, matrix)
    return bool(r) and {t["id"]: t["status"] for t in r["tests"]} == {"T1": "PASS", "T2": "PASS"}

res = []
def check(label, cond, detail=""):
    res.append(("✔ " if cond else "✖ ") + label + ("" if cond else "  [" + str(detail) + "]"))

# control: a full PASS is the one thing XONG and push accept, and the next run reuses it
write(0, SUITES)
check("control: a full PASS writes an exit-0 receipt the next run reuses", (receipt() or {}).get("exit") == 0 and reusable(), receipt() and receipt().get("exit"))

# 1. a PARTIAL run (the Stop hook) that ends exit 2, nothing failed, same code
write(2, [PASS("T1")], partial=True)
r = receipt()
check("partial exit 2: the receipt is no longer an accepted PASS (exit != 0: proof_gate and push_gate refuse)", r is not None and r.get("exit") == 2, r and r.get("exit"))
check("partial exit 2: the suites that passed on this code are still reusable by the next --full", reusable())

# 2. back to a clean PASS: exit 0 again
write(0, SUITES)
check("a later full PASS makes it exit 0 again", (receipt() or {}).get("exit") == 0)

# 3. a FULL run that ends exit 2 with every suite passed leaves its results for the re-run
os.remove(rp)
write(2, SUITES)
r = receipt()
check("full exit 2, no suite failed: the receipt records the run (exit 2, never an accepted PASS)", r is not None and r.get("exit") == 2, r)
check("full exit 2, no suite failed: the re-run reuses the suites", reusable())

# 4. a suite that FAILED leaves nothing to reuse (unchanged policy)
write(0, SUITES)
write(1, [FAIL("T1")], partial=True)
check("partial exit 1 (a suite FAILED): receipt removed", receipt() is None)
write(0, SUITES)
write(2, [PASS("T1"), FAIL("T2")], partial=True)
check("partial exit 2 with a FAILED suite: receipt removed", receipt() is None)
write(0, SUITES)
write(1, [PASS("T1"), FAIL("T2")])
check("full exit 1: receipt removed", receipt() is None)

# 5. the code changed since the receipt: nothing to reuse (the fingerprint decides, as before)
write(0, SUITES)
open(os.path.join(repo, "a.txt"), "a").write("changed again\n")
write(2, [PASS("T1")], partial=True)
check("partial exit 2 on code that differs from the receipt: receipt removed", receipt() is None, receipt() and receipt().get("exit"))
check("... and nothing is reusable", pfg.cached_full_pass(repo, matrix) is None)

# 5b. a suite that is UNTESTED by design (REG-QC-05 in GeelyEx2: "exit 2" on purpose) is named in the receipt, like exit 4 does:
#     reuse_full_pass needs every OTHER suite PASS, so without the id that one suite would cancel the whole reuse
MANUAL = {"id": "T3", "status": "UNTESTED", "command": "exit 2", "duration": "0s", "log": None}
os.remove(rp) if os.path.exists(rp) else None
write(2, SUITES + [MANUAL])
r = receipt()
check("full exit 2 with a by-design UNTESTED suite: its id is recorded as untested", r is not None and r.get("exit") == 2 and r.get("untested") == ["T3"], r and (r.get("exit"), r.get("untested")))
check("... and the receipt is still reusable for the suites that passed", pfg.cached_full_pass(repo, matrix) is not None)

# 5c. code changed while the suites ran: as before this change, a non-zero run leaves no receipt of the code it did not test
write(0, SUITES)
write(2, SUITES, tested_fp="not-the-fingerprint-of-the-tree")
check("full exit 2 on code that changed during the run: no receipt", receipt() is None, receipt() and receipt().get("exit"))

# 6. an exit 2 receipt does not reach the XONG/push consumers
write(0, SUITES)
write(2, [PASS("T1")], partial=True)
check("exit 2 receipt: both consumers' test (`exit != 0`) refuses it", (receipt() or {}).get("exit") not in (0, None))

print("\n".join(res))
sys.exit(1 if any(x.startswith("✖") for x in res) else 0)
PY
out="$("$PY" -I "$TMP/t.py" 2>&1)"; rc=$?
printf '%s\n' "$out"
[ "$rc" = 0 ] && ok "UNVERIFIED runs keep the suite results reusable" || bad "UNVERIFIED runs destroy reusable suite results (rc=$rc)"
[ "$FAILS" = 0 ] && exit 0 || exit 1
