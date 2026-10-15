#!/usr/bin/env bash
# Regression test (gate speed, 2026-10-15). The Stop hook runs the gate WITHOUT --full ("partial"), and a partial run recorded none of its suite
# results: the full-pass receipt is written by a full run only, and the budget record (.git/postfix-gate/budget_pass.json) only by a run whose time
# budget cut a suite. So a Stop run that ended exit 2 (an edited existing test waits for a person) or exit 4 (a suite cannot run on this machine)
# left nothing, and every later Stop on the SAME content ran every suite again: after the 300 s window of the hook's "tests-touched" reminder, or in
# another session. Measured on the real logs (Neighbours 13/10: one such re-run of a Unity suite took 243 s and printed the same reminder; runs since
# 12/10 20:32 whose suites an exact memo would have skipped, impacted-mode runs left out because they are not recorded: Neighbours 4.0 min,
# GeelyEx2 0.3 min in 2.6 days; OfficeReader's one repeat, 568 s on 13/10, was an impacted run and is NOT covered).
# Now every non-forced run that ended without a FAIL records the suites that PASSED their FULL command, and the next non-forced run on identical
# inputs starts none of them. The record is read under the keys of a receipt (tree fingerprint, matrix, local-config sha, result format, age,
# no device suite) AND the HEAD it was taken at. An impacted-mode PASS is never recorded (the full command did not pass), and a record is read for up
# to 6 h like a receipt: a suite that starts to fail on unchanged content stays unseen until the record ages out or the content changes.
#   A  gate level, real git repos, a Stop-style run (GATE_TOTAL_BUDGET_S set, no --full):
#      A1 same content twice (exit 2: an existing test was edited): run 2 starts no suite, still exit 2, says it re-used them
#      A2 one source byte changed: every suite runs again               A3 the edited test edited again: every suite runs again
#      A4 only the gate's own files changed between the runs (checklist, audit-gate log, inbox): still re-used
#      A5 an ignored local config file (local.properties) changed: every suite runs again (the key holds the local state)
#      A6 a new commit of the same content (HEAD moved): every suite runs again
#      A7 a FAIL on the content: nothing is recorded, the next run re-uses nothing         A8 a --full run never reads the record
#      A11 only the matrix changed (the matrix file sits in a folder the tree fingerprint leaves out): every suite runs again
#      A9 exit 4 (a suite exits with its untested_exit): the suites that can run are recorded, the manual one runs again every time
#      A10 a key that cannot be computed (no tree fingerprint, no HEAD, a local sha "?") re-uses nothing and writes nothing (the unit under the gate)
#   B  the Stop hook end to end: after the 300 s window of the reminder the gate runs again, and starts no suite; another session on the same content
#      starts none either; a changed source byte starts all of them
# The fake suites count their runs in $MARK (outside the repo: a file inside would change the code fingerprint).
# bash 3.2 and Python 3.9 compatible; STOPREC_KIT=<kit dir> tests another copy of the kit (a mutant must go red).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_UNITY_REUSE_MAX_S REGRESSION_GATE_BUDGET_S GATE_TOTAL_BUDGET_S REGRESSION_GATE_TOUCHED_RECHECK_S
export VACUITY_REVERT=0 FLAKY_RETRY=0
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${STOPREC_KIT:-$DEVKIT_DIR}"
GATE="$KIT/bin/post-fix-gate.py"
HOOK="$KIT/hooks/regression_gate.sh"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"
export MARK="$TMP/mark"
OUT=""; RC=0
suite() { printf '{"id":"%s","name":"%s","command":"%s"%s}' "$1" "$1" "$2" "${3:-}"; }
S1='sh tests/s1.sh'; S2='sh tests/s2.sh'

# A repo whose rule watches app/*; HEAD holds a test, the tree then rewrites one line of it (an EXISTING test line: the gate wants a review = exit 2).
make_repo() { # $1 = suites (json list body), $2 = "notest": do not edit the existing test (the run can then end exit 4 or 0)
  rm -rf "$R" "$MARK" && mkdir -p "$R/app/src/main/kotlin/pkg" "$R/app/src/test/kotlin/pkg" "$R/tests" "$MARK" && cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  printf 'local.properties\n' > .gitignore
  printf 'sdk.dir=/a\n' > local.properties
  printf 'include(":app")\n' > settings.gradle.kts
  printf 'package pkg\n\nclass Lonely {\n    fun value() = 4\n}\n' > app/src/main/kotlin/pkg/Lonely.kt
  printf 'package pkg\n\nimport org.junit.Test\nimport org.junit.Assert.assertEquals\n\nclass OtherTest {\n    @Test fun works() { assertEquals(4, Lonely().value()) }\n}\n' > app/src/test/kotlin/pkg/OtherTest.kt
  printf 'echo x >> "$MARK/s1"\nexit "${FAIL1:-0}"\n' > tests/s1.sh
  printf 'echo x >> "$MARK/s2"\n[ -n "${COMMIT2:-}" ] && git commit --allow-empty -qm "made while the suites ran"\nexit "${EXIT2:-0}"\n' > tests/s2.sh
  printf '{"project":"t","rules":[{"component":"App","watch_files":["app/*"],"mandatory_regression_tests":[%s]}]}\n' "$1" > matrix.json
  git add -A && git commit -qm init
  if [ "${2:-}" != notest ]; then
    printf 'package pkg\n\nimport org.junit.Test\nimport org.junit.Assert.assertEquals\n\nclass OtherTest {\n    @Test fun works() { assertEquals(8, Lonely().value() * 2) }\n}\n' > app/src/test/kotlin/pkg/OtherTest.kt
  fi
  echo "// tweak" >> app/src/main/kotlin/pkg/Lonely.kt
  GD="$(git -C "$R" rev-parse --absolute-git-dir)/postfix-gate"
}
# one gate run the way the Stop hook calls it (a time budget, no --full) unless flags say otherwise; env words first, flags after "--"
run_gate() {
  local envs=() flags=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  flags=("$@")
  OUT="$(CLAUDE_PROJECT_DIR="$R" env GATE_TOTAL_BUDGET_S=900 ${envs[@]+"${envs[@]}"} python3 "$GATE" --matrix "${MATRIX:-$R/matrix.json}" --lang en --run-tests ${flags[@]+"${flags[@]}"} 2>&1)"; RC=$?
}
runs() { if [ -f "$MARK/$1" ]; then wc -l < "$MARK/$1" | tr -d ' '; else echo 0; fi; }
counts() { echo "$(runs s1):$(runs s2)"; }
LAST="0:0"; D=""
delta() {   # the run counts of ONE gate run in $D ("s1:s2"), no subshell: LAST must persist
  local now; now="$(counts)"
  D="$(python3 -I -c 'import sys; a=[int(x) for x in sys.argv[1].split(":")]; b=[int(x) for x in sys.argv[2].split(":")]; print(":".join(str(x-y) for x,y in zip(a,b)))' "$now" "$LAST")"
  LAST="$now"
}
two() { make_repo "$(suite REG-1 "$S1"),$(suite REG-2 "$S2")"; LAST="0:0"; }

# A1 same content twice
two
run_gate; delta; d1="$D"; rc1=$RC
run_gate; delta; d2="$D"; rc2=$RC
if [ "$rc1" = 2 ] && [ "$d1" = "1:1" ]; then ok "A1a: run 1 ran both suites; the edited test makes it exit 2 (UNVERIFIED)"
else bad "A1a: run 1 exit $rc1, runs $d1 (want exit 2, 1:1)"; printf '%s\n' "$OUT" | tail -8; fi
if [ "$rc2" = 2 ] && [ "$d2" = "0:0" ]; then ok "A1b: run 2 on the same content started no suite and is still exit 2 (runs $d2)"
else bad "A1b: run 2 exit $rc2, runs $d2 (want exit 2 and 0:0: the suites that passed in run 1 are not run again)"; printf '%s\n' "$OUT" | tail -8; fi
printf '%s' "$OUT" | grep -q "reusing the suites that passed" && ok "A1c: run 2 says which suites it re-used" || bad "A1c: run 2 does not say it re-used anything"
[ ! -e "$GD/full_pass.json" ] && ok "A1d: neither run wrote a full-pass receipt (a Stop run is never a handover PASS)" || bad "A1d: a full-pass receipt exists"

# A2 one source byte changed
echo "// one more byte" >> "$R/app/src/main/kotlin/pkg/Lonely.kt"
run_gate; delta; d="$D"
[ "$d" = "1:1" ] && ok "A2: one source byte changed: both suites run again (runs $d)" || bad "A2: runs $d (want 1:1)"
# the run just made recorded the new content: unchanged, it is re-used again (the control of A2)
run_gate; delta; d="$D"
[ "$d" = "0:0" ] && ok "A2 control: the same edited content again is re-used (runs $d)" || bad "A2 control: runs $d (want 0:0)"

# A3 the test edited again
printf 'package pkg\n\nimport org.junit.Test\nimport org.junit.Assert.assertEquals\n\nclass OtherTest {\n    @Test fun works() { assertEquals(12, Lonely().value() * 3) }\n}\n' > "$R/app/src/test/kotlin/pkg/OtherTest.kt"
run_gate; delta; d="$D"
[ "$d" = "1:1" ] && ok "A3: the edited test edited again: both suites run again (runs $d)" || bad "A3: runs $d (want 1:1)"

# A4 only the gate's own files changed
run_gate; delta   # recorded
mkdir -p "$R/.claude/audit-gate" "$R/.agents"
echo "noise $(date +%s)" >> "$R/.claude/audit-gate/regression_gate.log"
echo "- a new inbox line" >> "$R/.agents/INBOX.md"
echo "<!-- rewritten by the gate -->" >> "$R/.agents/CHECKLIST.md"
run_gate; delta; d="$D"
[ "$d" = "0:0" ] && ok "A4: only the gate's own files (audit-gate log, INBOX, CHECKLIST) changed: re-used (runs $d)" || bad "A4: runs $d (want 0:0)"

# A5 an ignored local config file changed
echo "sdk.dir=/b" > "$R/local.properties"
run_gate; delta; d="$D"
[ "$d" = "1:1" ] && ok "A5: an ignored local config file (local.properties) changed: both suites run again (runs $d)" || bad "A5: runs $d (want 1:1)"

# A6 a commit that leaves the content as it is (a notes file, untracked then committed) moves HEAD: the fingerprint does not see it, the record does
two
echo "notes" > "$R/notes.txt"
run_gate; delta
git -C "$R" add notes.txt >/dev/null 2>&1
git -C "$R" commit -qm "commit the notes" >/dev/null 2>&1
run_gate; delta; d="$D"
[ "$d" = "1:1" ] && ok "A6: HEAD moved, the content is the same: both suites run again (runs $d)" || bad "A6: runs $d (want 1:1)"
run_gate; delta; d="$D"
[ "$d" = "0:0" ] && ok "A6 control: a second run at the new HEAD is re-used (runs $d)" || bad "A6 control: runs $d (want 0:0)"

# A7 a FAIL on the content
two
run_gate; delta                       # records both
echo "// edit" >> "$R/app/src/main/kotlin/pkg/Lonely.kt"
run_gate FAIL1=1; delta; d="$D"; rc="$RC"
[ "$rc" = 1 ] && [ "$d" = "1:1" ] && ok "A7a: a FAIL on new content: exit 1, both suites ran (runs $d)" || bad "A7a: exit $rc runs $d (want 1, 1:1)"
[ ! -e "$GD/budget_pass.json" ] && ok "A7b: a run with a FAILED suite leaves no record" || bad "A7b: a record exists after a FAIL"
run_gate; delta; d="$D"
[ "$d" = "1:1" ] && ok "A7c: the next run on that content re-uses nothing (runs $d)" || bad "A7c: runs $d (want 1:1)"

# A8 a --full run does not read it
two
run_gate; delta
run_gate -- --full; delta; d="$D"
[ "$d" = "1:1" ] && ok "A8: --full ran both suites (it takes nothing from a Stop run)" || bad "A8: --full runs $d (want 1:1)"

# A9 exit 4: a suite that cannot run here
make_repo "$(suite REG-1 "$S1"),$(suite REG-2 "$S2" ',"untested_exit":2')" notest; LAST="0:0"
run_gate EXIT2=2; delta; d1="$D"; rc1=$RC
run_gate EXIT2=2; delta; d2="$D"; rc2=$RC
if [ "$rc1" = 4 ] && [ "$d1" = "1:1" ]; then ok "A9a: REG-2 exits with its untested_exit: exit 4, both suites ran (runs $d1)"
else bad "A9a: exit $rc1 runs $d1 (want 4, 1:1)"; printf '%s\n' "$OUT" | tail -8; fi
if [ "$rc2" = 4 ] && [ "$d2" = "0:1" ]; then ok "A9b: run 2: REG-1 re-used, the suite that cannot run here is tried again (runs $d2)"
else bad "A9b: exit $rc2 runs $d2 (want 4, 0:1)"; fi

# A11 only the matrix changed: it lives under .agents/evidence/, which the tree fingerprint leaves out, so nothing else moves
two
mkdir -p "$R/.agents/evidence" && cp "$R/matrix.json" "$R/.agents/evidence/m.json"
git -C "$R" add -f .agents/evidence/m.json >/dev/null 2>&1
git -C "$R" commit -qm "matrix copy" -- .agents/evidence/m.json >/dev/null 2>&1
MATRIX="$R/.agents/evidence/m.json"
run_gate; delta
run_gate; delta; d="$D"
[ "$d" = "0:0" ] && ok "A11 control: the matrix unchanged, the content unchanged: re-used (runs $d)" || bad "A11 control: runs $d (want 0:0)"
echo " " >> "$MATRIX"
run_gate; delta; d="$D"
[ "$d" = "1:1" ] && ok "A11: only the matrix changed: both suites run again (runs $d)" || bad "A11: runs $d (want 1:1)"
MATRIX=""

# A12 HEAD moves WHILE the suites run (an empty commit: the content stays): the record names the HEAD taken before them, so it is not read after
two
run_gate COMMIT2=1; delta
run_gate; delta; d="$D"
[ "$d" = "1:1" ] && ok "A12: a commit made while the suites ran: the record names the HEAD they ran at, both suites run again (runs $d)" || bad "A12: runs $d (want 1:1)"

# A10 a key that cannot be computed: the unit under the gate (fingerprint, HEAD and local sha are what the record is keyed by)
two
run_gate; delta
python3 -I - "$GATE" "$R" <<'PY' && ok "A10: no fingerprint / no HEAD / local sha '?' / a record of another HEAD: nothing re-used, nothing written" || bad "A10: a key that cannot be computed was used"
import importlib.util, json, os, sys
spec = importlib.util.spec_from_file_location("pfg", sys.argv[1])
m = importlib.util.module_from_spec(spec)
root = sys.argv[2]
os.environ["CLAUDE_PROJECT_DIR"] = root
spec.loader.exec_module(m)
sys.path.insert(0, os.path.dirname(sys.argv[1]))
import tree_fp
matrix = os.path.join(root, "matrix.json")
good = m.cached_full_pass(root, matrix, None, m.BUDGET_RECORD)
assert good, "the record is there and valid before any fault is injected"
real_fp, real_local, real_head = tree_fp.tree_fingerprint, m.local_state_sha, m._head_sha
try:
    tree_fp.tree_fingerprint = lambda d: ""
    assert m.cached_full_pass(root, matrix, None, m.BUDGET_RECORD) is None, "an empty fingerprint re-used the record"
    tree_fp.tree_fingerprint = real_fp
    m.local_state_sha = lambda d: "?"
    assert m.cached_full_pass(root, matrix, None, m.BUDGET_RECORD) is None, "a local sha of ? re-used the record"
    m.local_state_sha = real_local
    m._head_sha = lambda d: None
    assert m.cached_full_pass(root, matrix, None, m.BUDGET_RECORD) is None, "a HEAD that cannot be read re-used the record"
    m._head_sha = lambda d: "0" * 40
    assert m.cached_full_pass(root, matrix, None, m.BUDGET_RECORD) is None, "a record of another HEAD was re-used"
    # a record that names no HEAD at all, while HEAD cannot be read either: None equals None, which must NOT count as "the same HEAD"
    path = os.path.join(os.path.dirname(tree_fp.receipt_path(root)), m.BUDGET_RECORD)
    saved = open(path).read()
    nohead = json.loads(saved)
    nohead.pop("head")
    open(path, "w").write(json.dumps(nohead))
    m._head_sha = lambda d: None
    assert m.cached_full_pass(root, matrix, None, m.BUDGET_RECORD) is None, "a record without a HEAD was re-used while HEAD was unreadable"
    m._head_sha = real_head
    assert m.cached_full_pass(root, matrix, None, m.BUDGET_RECORD) is None, "a record without a HEAD was re-used"
    open(path, "w").write(saved)
    assert m.cached_full_pass(root, matrix, None, m.BUDGET_RECORD), "the control: the intact record is read again"
    # an empty key must not match an empty key: a record that carries "" as its fingerprint / local sha (a damaged or forged one) is not matched by a
    # fingerprint / local sha that could not be computed either
    for field, patch in (("fingerprint", "fp"), ("local_sha", "local")):
        broken = json.loads(saved)
        broken[field] = "" if field == "fingerprint" else "?"
        open(path, "w").write(json.dumps(broken))
        if patch == "fp":
            tree_fp.tree_fingerprint = lambda d: ""
        else:
            m.local_state_sha = lambda d: "?"
        assert m.cached_full_pass(root, matrix, None, m.BUDGET_RECORD) is None, "an uncomputable %s matched a record that holds the same blank" % field
        tree_fp.tree_fingerprint, m.local_state_sha = real_fp, real_local
    open(path, "w").write(saved)
    # the writer: no fingerprint taken before the suites, or no HEAD taken, writes nothing
    os.remove(path)
    tests = [{"id": "A", "status": "PASS", "mode": "full", "command": "x"}, {"id": "B", "status": "UNTESTED", "mode": "full", "command": "y"}]
    m.write_budget_record(root, matrix, tests, "", head=real_head(root))
    assert not os.path.exists(path), "a record was written without a fingerprint"
    tree_fp.tree_fingerprint = lambda d: ""   # even when the fingerprint taken afterwards is blank too (blank == blank)
    m.write_budget_record(root, matrix, tests, "", head=real_head(root))
    tree_fp.tree_fingerprint = real_fp
    assert not os.path.exists(path), "a record was written with a blank fingerprint on both sides"
    m.write_budget_record(root, matrix, tests, real_fp(root), head=None)
    assert not os.path.exists(path), "a record was written without a HEAD"
    m.write_budget_record(root, matrix, tests, real_fp(root), head=real_head(root))
    assert os.path.exists(path) and json.load(open(path)).get("head") == real_head(root), "the control: with both, the record is written and names its HEAD"
finally:
    tree_fp.tree_fingerprint, m.local_state_sha, m._head_sha = real_fp, real_local, real_head
PY

# B the Stop hook end to end. The first Stop blocks on the edited test (this session wrote it); after the 300 s window the gate runs again.
H="$TMP/hookrepo"
make_hook_repo() {
  rm -rf "$H" "$MARK"; mkdir -p "$H/app/src/main/kotlin/pkg" "$H/app/src/test/kotlin/pkg" "$H/tests" "$H/.agents" "$MARK" && cd "$H" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  printf 'package pkg\n\nclass Lonely {\n    fun value() = 4\n}\n' > app/src/main/kotlin/pkg/Lonely.kt
  printf 'package pkg\n\nimport org.junit.Test\nimport org.junit.Assert.assertEquals\n\nclass OtherTest {\n    @Test fun works() { assertEquals(4, Lonely().value()) }\n}\n' > app/src/test/kotlin/pkg/OtherTest.kt
  cp "$R/tests/s1.sh" "$R/tests/s2.sh" tests/
  cat > .agents/regression_matrix.active.json <<JSON
{"project":"t","adopted":true,"rules":[{"component":"App","watch_files":["app/*"],
 "mandatory_regression_tests":[$(suite REG-1 "$S1"),$(suite REG-2 "$S2")]}]}
JSON
  git add -A && git commit -qm init
  printf 'package pkg\n\nimport org.junit.Test\nimport org.junit.Assert.assertEquals\n\nclass OtherTest {\n    @Test fun works() { assertEquals(8, Lonely().value() * 2) }\n}\n' > app/src/test/kotlin/pkg/OtherTest.kt
  echo "// tweak" >> app/src/main/kotlin/pkg/Lonely.kt
  python3 -I - "$H" "$TMP/sA.jsonl" "$TMP/sB.jsonl" <<'PY'
import json, sys, time
repo, tpa, tpb = sys.argv[1:4]
past = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() - 600))
a = [{"type": "user", "timestamp": past, "message": {"role": "user", "content": "fix it"}},
     {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "e1", "name": "Edit",
        "input": {"file_path": repo + "/app/src/test/kotlin/pkg/OtherTest.kt", "old_string": "a", "new_string": "b"}}]}}]
b = [{"type": "user", "timestamp": past, "message": {"role": "user", "content": "other work"}}]
open(tpa, "w").write("".join(json.dumps(r) + "\n" for r in a))
open(tpb, "w").write("".join(json.dumps(r) + "\n" for r in b))
PY
}
hookstop() { # $1 = session id, $2 = transcript
  printf '{"session_id":"%s","hook_event_name":"Stop","transcript_path":"%s"}' "$1" "$2" | CLAUDE_PROJECT_DIR="$H" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"
}
STATE="$H/.claude/audit-gate/regression_gate.state.json"
age_reminder() { python3 -I -c 'import json,sys,time
p = sys.argv[1]; d = json.load(open(p)); d["touched"]["s-a"]["at"] = time.time() - float(sys.argv[2]); json.dump(d, open(p, "w"))' "$STATE" "$1"; }

make_hook_repo; LAST="0:0"
hookstop s-a "$TMP/sA.jsonl"; rc=$?; delta; d="$D"
if [ "$rc" = 2 ] && [ "$d" = "1:1" ] && grep -q "OtherTest.kt" "$TMP/err"; then ok "B1: first Stop of the session: the gate ran both suites and blocked on the edited test (runs $d)"
else bad "B1: rc=$rc runs=$d err='$(head -3 "$TMP/err")'"; fi
age_reminder 400
hookstop s-a "$TMP/sA.jsonl"; rc=$?; delta; d="$D"
if [ "$rc" = 0 ] && [ "$d" = "0:0" ] && grep -q "OtherTest.kt" "$TMP/out"; then ok "B2: after the 300 s window the gate runs again, starts no suite (runs $d), and the reminder is still printed"
else bad "B2: rc=$rc runs=$d (want 0 and 0:0) out='$(head -c 250 "$TMP/out")' err='$(head -3 "$TMP/err")'"; fi
hookstop s-b "$TMP/sB.jsonl"; rc=$?; delta; d="$D"
[ "$d" = "0:0" ] && ok "B3: another session on the same content starts no suite either (runs $d)" || bad "B3: session B ran suites: $d (want 0:0)"
echo "// one more byte" >> "$H/app/src/main/kotlin/pkg/Lonely.kt"
hookstop s-b "$TMP/sB.jsonl"; delta; d="$D"
[ "$d" = "1:1" ] && ok "B4: a changed source byte starts both suites (runs $d)" || bad "B4: runs $d (want 1:1)"
cd "$TMP" || exit 1

echo
[ "$FAILS" -eq 0 ] && echo "gate stop run record: all checks passed" || { echo "gate stop run record: $FAILS FAILED"; exit 1; }
