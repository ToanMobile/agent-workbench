#!/usr/bin/env bash
# Regression test: hooks/test_evidence_gate.sh ANTI-LOOP counts only the test runs THIS
# session made (audit G5, ported from OfficeReader's hook). build/ is shared: a red suite from
# another agent's run landed in the same tree and was counted as one of our failed fixes.
# A run sits inside the Bash window of the session that ran it (.claude/audit-gate/
# bash_write_ledger.tsv: session \t start|end \t <ts> \t <tool_use_id>); the narrowest window
# containing the XML's mtime wins. Fail-closed: no ledger, no containing window, or a tie
# between sessions → counted as ours. A background command's open window lasts until Stop.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$DEVKIT_DIR/hooks/test_evidence_gate.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

N=0
# case_ <want-exit> <name> <ledger rows: "sid kind offset uid" relative to the XML mtime, ';'-separated>
case_() {
  local want="$1" name="$2" ledger="$3"
  N=$((N + 1)); local P="$TMP/p$N" sid="me"
  mkdir -p "$P/app/build/test-results/testDebugUnitTest" "$P/.claude/audit-gate"
  touch "$P/build.gradle"
  local X="$P/app/build/test-results/testDebugUnitTest/TEST-com.x.PaySuite.xml"
  printf '<?xml version="1.0"?>\n<testsuite name="com.x.PaySuite" tests="1" failures="1" errors="0" skipped="0">\n<testcase classname="com.x.PaySuite" name="pays"><failure message="boom">x</failure></testcase>\n</testsuite>\n' > "$X"
  python3 - "$P" "$X" "$ledger" <<'PY'
import json, os, sys, time
P, X, ledger = sys.argv[1:4]
t = time.time() - 30
os.utime(X, (t, t))
json.dump({"last_run": 0.0, "streak": {"com.x.PaySuite#pays": 1}}, open(f"{P}/.claude/audit-gate/failcycle_me.json", "w"))
if ledger != "none":
    rows = []
    for spec in filter(None, ledger.split(";")):
        sid, kind, off, uid = spec.split()
        rows.append(f"{sid}\t{kind}\t{t + float(off):.3f}\t{uid}\n")
    open(f"{P}/.claude/audit-gate/bash_write_ledger.tsv", "w").write("".join(rows))
PY
  : > "$P/tr.jsonl"
  local rc
  python3 -c 'import json,sys; print(json.dumps({"session_id": "me", "transcript_path": sys.argv[1], "last_assistant_message": "PaySuite vẫn đỏ, tôi thử cách khác."}))' "$P/tr.jsonl" \
    | CLAUDE_PROJECT_DIR="$P" LESSON_REMINDER=0 BUG_LINK_REMINDER=0 RED_PROOF=0 bash "$GATE" >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$want" ]; then ok "$name (exit $rc)"; else fail "$name: want $want, got $rc"; fi
}

case_ 0 "red run inside ANOTHER session's window only → not our failed fix" "other start -5 u1;other end 5 u1"
case_ 2 "red run inside OUR window → ANTI-LOOP" "me start -5 u1;me end 5 u1"
case_ 2 "no ledger → counted as ours (fail-closed)" "none"
case_ 2 "narrowest window wins: ours inside theirs → ours" "other start -50 u1;other end 50 u1;me start -2 u2;me end 2 u2"
case_ 0 "narrowest window wins: theirs inside ours → theirs" "me start -50 u1;me end 50 u1;other start -2 u2;other end 2 u2"
case_ 2 "tie between two sessions → ours (fail-closed)" "other start -5 u1;other end 5 u1;me start -5 u2;me end 5 u2"
case_ 2 "our background command (start, no end) is open until Stop → ours" "me start -5 u1"
case_ 2 "no window contains the run → ours (fail-closed)" "other start -500 u1;other end -400 u1"

[ "$FAILS" -eq 0 ] && echo "✅ test_anti_loop_ownership: all passed" || { echo "❌ test_anti_loop_ownership: $FAILS failed"; exit 1; }
