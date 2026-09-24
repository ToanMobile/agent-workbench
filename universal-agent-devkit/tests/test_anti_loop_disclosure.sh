#!/usr/bin/env bash
# Regression test: hooks/test_evidence_gate.sh ANTI-LOOP (6.4) and the "deliberate red"
# disclosure — ported from OfficeReader's pre-DevKit hook (audit G4, 2026-09-24).
# A second red of the same testcase after an edit is a failed fix → block. It is forgiven only
# when the reply names THAT suite and says the red was a mutation in the same sentence:
#  - per testcase, not global: disclosing another suite does not forgive this one
#  - "red-check" is not a marker (the hook prints it itself); editing a test file is not one
#  - "mutation" / "mutant" / "đột biến" are; a fully-qualified name or a decimal point does
#    not split the sentence; a marker inside the test's own name does not count
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$DEVKIT_DIR/hooks/test_evidence_gate.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

N=0
# case <want-exit> <name> <message> [failing testcase …]  (env EDIT_TEST=1: transcript edits a test file)
case_() {
  local want="$1" name="$2" msg="$3"; shift 3
  N=$((N + 1)); local P="$TMP/p$N" sid="al$N"
  mkdir -p "$P/app/build/test-results/testDebugUnitTest" "$P/.claude/audit-gate" "$P/app/src/test/java"
  touch "$P/build.gradle"
  local cases="" t cls name2
  [ $# -eq 0 ] && set -- "com.x.MutantSuite#doesSomething"
  for t in "$@"; do
    cls="${t%%#*}"; name2="${t#*#}"
    printf '<?xml version="1.0"?>\n<testsuite name="%s" tests="1" failures="1" errors="0" skipped="0">\n<testcase classname="%s" name="%s"><failure message="boom">x</failure></testcase>\n</testsuite>\n' \
      "$cls" "$cls" "$name2" > "$P/app/build/test-results/testDebugUnitTest/TEST-$cls.xml"
  done
  python3 - "$P/.claude/audit-gate/failcycle_$sid.json" "$@" <<'PY'
import json, sys
json.dump({"last_run": 0.0, "streak": {t: 1 for t in sys.argv[2:]}}, open(sys.argv[1], "w"))
PY
  python3 - "$P/tr.jsonl" "$P/app/src/test/java/FooTest.kt" "${EDIT_TEST:-0}" <<'PY'
import json, sys
out, f, edit = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
lines = []
if edit:
    open(f, "w").write("class FooTest { val a = 2 }\n")
    lines.append(json.dumps({"message": {"content": [{"type": "tool_use", "id": "e1", "name": "Edit",
        "input": {"file_path": f, "old_string": "1", "new_string": "2"}}]}}))
    lines.append(json.dumps({"message": {"content": [{"type": "tool_result", "tool_use_id": "e1", "content": "ok"}]}}))
open(out, "w").write("\n".join(lines) + ("\n" if lines else ""))
PY
  local rc err
  err="$(python3 -c 'import json,sys; print(json.dumps({"session_id": sys.argv[1], "transcript_path": sys.argv[2], "last_assistant_message": sys.argv[3]}))' "$sid" "$P/tr.jsonl" "$msg" \
        | CLAUDE_PROJECT_DIR="$P" LESSON_REMINDER=0 BUG_LINK_REMINDER=0 RED_PROOF=0 bash "$GATE" 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" = "$want" ]; then ok "$name (exit $rc)"; else fail "$name: want $want, got $rc — $(printf '%s' "$err" | head -2 | tr '\n' ' ')"; fi
}

case_ 2 "second red, no disclosure → ANTI-LOOP" "MutantSuite vẫn đỏ, tôi thử cách khác."
case_ 2 "quoting the gate's own 'RED-check' warning does not disclose" "MutantSuite vẫn đỏ. Nhắc: gate này KHÔNG kiểm RED-check."
EDIT_TEST=1 case_ 2 "editing a test file does not silence ANTI-LOOP" "MutantSuite vẫn đỏ, tôi thử cách khác."
case_ 2 "disclosing ANOTHER suite does not forgive this one" "PaymentSuite: deliberate red do mutation. MutantSuite vẫn đỏ thật."
case_ 0 "same sentence names the suite + 'mutation' → forgiven" "MutantSuite đỏ do mutation cố ý, đã khôi phục dòng gốc."
case_ 0 "'đột biến' discloses a deliberate red" "MutantSuite đỏ vì đột biến dòng kiểm tra null, đã hoàn nguyên."
case_ 0 "fully-qualified name is not split apart" "com.x.MutantSuite đỏ vì mutation có chủ đích."
case_ 0 "a decimal point does not split the disclosure" "Coverage 12.5% — MutantSuite đỏ vì mutation có chủ đích."
case_ 2 "marker only in the test's own name does not disclose" "MutantSuite#mutationGuard vẫn đỏ." "com.x.MutantSuite#mutationGuard"
case_ 2 "one sentence naming two failing suites cannot pin the marker" "MutantSuite và PaymentSuite đỏ do mutation." \
  "com.x.MutantSuite#doesSomething" "com.x.PaymentSuite#pays"

[ "$FAILS" -eq 0 ] && echo "✅ test_anti_loop_disclosure: all passed" || { echo "❌ test_anti_loop_disclosure: $FAILS failed"; exit 1; }
