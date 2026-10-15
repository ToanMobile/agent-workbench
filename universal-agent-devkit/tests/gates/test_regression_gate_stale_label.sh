#!/usr/bin/env bash
# Regression test (A15 lane, round 2, 2026-10-15): bin/post-fix-gate.py now marks a re-used PASS whose source file a concurrent run replaced or deleted
# as UNTESTED with the label STALE (tests/gates/test_gate_stop_reuse_race.sh). hooks/regression_gate.sh read every UNTESTED suite it did not know as
# "cannot run on this machine" and stored a block that carried one for REGRESSION_GATE_REPEAT_TTL_S (1800 s): both wrong for a STALE suite, which
# runs for real at the next Stop. A fake gate (a copy of the kit whose bin/post-fix-gate.py only prints a fixed summary and counts its runs) makes the
# hook see one FAILED suite and one UNTESTED suite with a chosen label:
#   S1 label STALE: the block says the other run changed or deleted the PASS it re-used (not "cannot run on this machine") and the next Stop on the same
#      content runs the gate again (the block is not re-used)
#   S2 control, an UNTESTED suite with a label the hook does not name: the old wording and the block IS re-used (the gate does not run again)
# bash 3.2 compatible; STALELABEL_KIT=<kit dir> tests another copy of the kit (a mutant must go red).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SRC_KIT="${STALELABEL_KIT:-$DEVKIT_DIR}"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
export FLAKY_RETRY=0 VACUITY_REVERT=0 DEVKIT_GATE_CACHE=0
unset REGRESSION_GATE_REPEAT_TTL_S REGRESSION_GATE_TOUCHED_RECHECK_S

# the kit under test with a fake gate: the hook finds the gate next to itself (../bin/post-fix-gate.py)
KIT="$TMP/kit"; mkdir -p "$KIT" && cp -R "$SRC_KIT/hooks" "$KIT/hooks" && cp -R "$SRC_KIT/bin" "$KIT/bin" || { echo "✖ cannot copy the kit"; exit 1; }
cat > "$KIT/bin/post-fix-gate.py" <<'PY'
import json, os, sys
open(os.environ["FAKE_RUNS"], "a").write("x")
print("fake gate")
print(json.dumps({"verdict": "REJECT", "exit_code": 1, "findings": [], "tests_touched": [], "checklist": "c", "report": "r",
                  "regression_tests": [
                      {"id": "REG-F", "name": "fails", "status": "FAIL", "label": "FAIL", "command": "false", "exit_code": 1, "output_tail": "boom"},
                      {"id": "REG-S", "name": "reused", "status": "UNTESTED", "label": os.environ["FAKE_LABEL"], "command": "true", "output_tail": "x"}]}))
sys.exit(1)
PY
HOOK="$KIT/hooks/regression_gate.sh"
export FAKE_RUNS="$TMP/runs"; : > "$FAKE_RUNS"
runs() { wc -c < "$FAKE_RUNS" | tr -d ' '; }

printf '%s\n' '{"type":"user","message":{"role":"user","content":"fix it"},"uuid":"u1","sessionId":"c-r"}' > "$TMP/claude.jsonl"
R="$TMP/repo"; mkdir -p "$R/src" "$R/.agents" && cd "$R" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","adopted":true,"rules":[{"component":"Core","watch_files":["src/*.kt"],
 "mandatory_regression_tests":[{"id":"REG-F","name":"fails","command":"false"}]}]}
JSON
git add -A && git commit -qm init
echo "fun ok() = 2" > src/Core.kt
stopx() { # $1 = session id, $2 = the label of the UNTESTED suite
  printf '{"session_id":"%s","hook_event_name":"Stop","transcript_path":"%s"}' "$1" "$TMP/claude.jsonl" \
    | env FAKE_LABEL="$2" CLAUDE_PROJECT_DIR="$R" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"
  RC=$?
}

stopx s-stale STALE; r1=$(runs)
if [ "$RC" = 2 ] && [ "$r1" = 1 ] && grep -q "REG-S" "$TMP/err" && grep -q "đã đổi/xoá kết quả PASS dùng lại" "$TMP/err" && ! grep -q "không chạy được trên máy này" "$TMP/err"; then
  ok "S1: a STALE suite is listed with its own reason (a concurrent run replaced or deleted the PASS it re-used), not as one that cannot run here"
else
  fail "S1: rc=$RC runs=$r1 err='$(head -c 500 "$TMP/err")'"
fi
stopx s-stale STALE
if [ "$(runs)" = 2 ]; then ok "S1: the next Stop on the same content runs the gate again (a block with a STALE suite is not re-used)"
else fail "S1: the gate ran $(runs) times in two Stops (want 2: the block was re-used)"; fi

echo "fun ok() = 3" > src/Core.kt   # other content: the hook blocks a content at most twice, and S1 used both
stopx s-other UNTESTED; r3=$(runs)
if [ "$RC" = 2 ] && grep -q "REG-S" "$TMP/err" && grep -q "không chạy được trên máy này" "$TMP/err" && ! grep -q "đã đổi/xoá kết quả PASS dùng lại" "$TMP/err"; then
  ok "S2 control: an UNTESTED suite with another label keeps the old reason (cannot run on this machine)"
else
  fail "S2 control: rc=$RC err='$(head -c 500 "$TMP/err")'"
fi
stopx s-other UNTESTED
if [ "$(runs)" = "$r3" ]; then ok "S2 control: the next Stop on the same content re-uses that block (the gate did not run again)"
else fail "S2 control: the gate ran again ($r3 -> $(runs)): a block without a STALE suite should have been re-used"; fi

cd "$TMP" || exit 1
if [ "$FAILS" -ne 0 ]; then echo "regression gate stale label: $FAILS FAILED"; exit 1; fi
echo "regression gate stale label: all checks passed"
