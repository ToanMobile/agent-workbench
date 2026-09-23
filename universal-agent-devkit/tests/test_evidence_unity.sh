#!/usr/bin/env bash
# Regression test: hooks/test_evidence_gate.sh on a Unity project.
#
# A Unity repo has no Gradle and no TEST-*.xml. Its test runs are
# profiles/game/scripts/unity-batch.sh (NUnit 3 XML at Logs/agent-kit/tests_<Platform>.xml
# plus a `PASS:`/`FAIL: <Platform>: N passed, M failed, K skipped` line), a project's own
# scripts/unity-test.sh, a raw `Unity … -runTests`, or the MCP tool
# mcp__antigravity-pm__pm_run kind=test (prints `exit=N`). An honest RED→GREEN on any of
# them must satisfy check 2 and check 7; a red NUnit result must still block; a failure
# count of 0 is never red. No Unity, no Gradle: fake transcripts and fake XML only.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$DEVKIT_DIR/hooks/test_evidence_gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

N=0
# new_project → sets P to a fresh Unity-shaped project (no gradle files) and CS to its .cs.
new_project() {
  N=$((N + 1))
  local p="$TMP/p$N"
  mkdir -p "$p/Assets/Scripts" "$p/ProjectSettings" "$p/.claude/audit-gate"
  printf 'm_EditorVersion: 6000.0.1f1\n' > "$p/ProjectSettings/ProjectVersion.txt"
  printf 'public class Cart { }\n' > "$p/Assets/Scripts/Cart.cs"
  P="$p"; CS="$p/Assets/Scripts/Cart.cs"
}

# nunit_xml <path> <result> <total> <passed> <failed> — NUnit 3 as Unity writes it.
nunit_xml() {
  mkdir -p "$(dirname "$1")"
  python3 - "$@" <<'PY'
import sys
path, result, total, passed, failed = sys.argv[1:6]
cases = []
for i in range(int(total)):
    r = "Failed" if i < int(failed) else "Passed"
    body = '<failure><message><![CDATA[Expected 2 but was 1]]></message></failure>' if r == "Failed" else ""
    cases.append(f'<test-case id="{1002+i}" name="Case{i}" fullname="Cart.CartTests.Case{i}" '
                 f'methodname="Case{i}" classname="Cart.CartTests" result="{r}">{body}</test-case>')
open(path, "w").write(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    f'<test-run id="2" testcasecount="{total}" result="{result}" total="{total}" passed="{passed}" '
    f'failed="{failed}" inconclusive="0" skipped="0" asserts="0">\n'
    f'  <test-suite type="TestFixture" id="1001" name="CartTests" fullname="Cart.CartTests" '
    f'result="{result}" total="{total}" passed="{passed}" failed="{failed}" skipped="0">\n    '
    + "\n    ".join(cases) + "\n  </test-suite>\n</test-run>\n")
PY
}

# transcript <out.jsonl> <step-json-list> — steps:
#   ["bash", command, output, is_error] | ["tool", name, input, output, is_error] | ["edit", path]
transcript() {
  python3 - "$1" "$2" <<'PY'
import json, sys
out, steps = sys.argv[1], json.loads(sys.argv[2])
lines = []
for i, s in enumerate(steps):
    uid = f"tu{i}"
    if s[0] == "bash":
        use = {"type": "tool_use", "id": uid, "name": "Bash", "input": {"command": s[1]}}
        res = {"type": "tool_result", "tool_use_id": uid, "content": s[2], "is_error": s[3]}
    elif s[0] == "tool":
        use = {"type": "tool_use", "id": uid, "name": s[1], "input": s[2]}
        res = {"type": "tool_result", "tool_use_id": uid, "content": s[3], "is_error": s[4]}
    else:
        use = {"type": "tool_use", "id": uid, "name": "Edit",
               "input": {"file_path": s[1], "old_string": "{ }", "new_string": "{ int n; }"}}
        res = {"type": "tool_result", "tool_use_id": uid, "content": "ok"}
    lines.append(json.dumps({"message": {"content": [use]}}))
    lines.append(json.dumps({"message": {"content": [res]}}))
open(out, "w").write("\n".join(lines) + "\n")
PY
}

# gate <project> <transcript> <message> → sets RC and ERR
gate() {
  local payload
  payload="$(python3 -c 'import json,sys; print(json.dumps({"session_id": "unity-" + sys.argv[1].rsplit("/",1)[-1], "transcript_path": sys.argv[2], "last_assistant_message": sys.argv[3]}))' "$1" "$2" "$3")"
  ERR="$(printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$1" LESSON_REMINDER=0 bash "$GATE" 2>&1 >/dev/null)"
  RC=$?
}

# expect <name> <want-exit> [stderr-substring]
expect() {
  if [ "$RC" = "$2" ] && { [ -z "${3:-}" ] || printf '%s' "$ERR" | grep -qF -- "$3"; }; then
    ok "$1"
  else
    fail "$1 — want exit $2${3:+ + '$3'}, got $RC: $(printf '%s' "$ERR" | grep -v '^$' | head -3 | tr '\n' ' ')"
  fi
}

MSG="Đã fix lỗi giỏ hàng: EditMode 4/4 test pass."
UB="bash .agents/active-profile/scripts/unity-batch.sh editmode --filter CartTests"
UB_RED="  [Failed] Cart.CartTests.Case0: Expected 2 but was 1
FAIL: EditMode: 3 passed, 1 failed, 0 skipped (Unity exit 2) — Logs/agent-kit/tests_EditMode.xml"
UB_GREEN="PASS: EditMode: 4 passed, 0 failed, 0 skipped — Logs/agent-kit/tests_EditMode.xml"

# ── 1. unity-batch.sh RED → edit → GREEN, green NUnit XML on disk ───────────
new_project
transcript "$P/tr.jsonl" "$(python3 -c 'import json,sys; print(json.dumps([["bash",sys.argv[1],sys.argv[2],True],["edit",sys.argv[4]],["bash",sys.argv[1],sys.argv[3],False]]))' "$UB" "$UB_RED" "$UB_GREEN" "$CS")"
nunit_xml "$P/Logs/agent-kit/tests_EditMode.xml" Passed 4 4 0
gate "$P" "$P/tr.jsonl" "$MSG"
expect "unity-batch.sh RED→GREEN + green NUnit XML passes checks 2 and 7" 0

# ── 2. same run, no XML on disk: the runner's own summary line is the evidence
new_project
transcript "$P/tr.jsonl" "$(python3 -c 'import json,sys; print(json.dumps([["bash",sys.argv[1],sys.argv[2],True],["edit",sys.argv[4]],["bash",sys.argv[1],sys.argv[3],False]]))' "$UB" "$UB_RED" "$UB_GREEN" "$CS")"
gate "$P" "$P/tr.jsonl" "$MSG"
expect "unity-batch.sh RED→GREEN from its summary lines alone" 0

# ── 3. raw Unity -runTests: exit≠0 red, exit 0 green ────────────────────────
new_project
RAW="/Applications/Unity/Hub/Editor/6000.0.1f1/Unity.app/Contents/MacOS/Unity -batchmode -projectPath . -runTests -testPlatform EditMode -testResults Logs/agent-kit/tests_EditMode.xml -logFile -"
transcript "$P/tr.jsonl" "$(python3 -c 'import json,sys; print(json.dumps([["bash",sys.argv[1],"Exit code 2",True],["edit",sys.argv[2]],["bash",sys.argv[1],"",False]]))' "$RAW" "$CS")"
nunit_xml "$P/Logs/agent-kit/tests_EditMode.xml" Passed 4 4 0
gate "$P" "$P/tr.jsonl" "$MSG"
expect "raw Unity -runTests RED→GREEN" 0

# ── 4. red read from the NUnit <test-run failed="N"> attribute (exit 0 both times)
new_project
CAT="Unity -batchmode -projectPath . -runTests -testPlatform EditMode -testResults r.xml; cat r.xml"
X_RED='<test-run id="2" testcasecount="4" result="Failed" total="4" passed="3" failed="1" inconclusive="0" skipped="0">'
X_GREEN='<test-run id="2" testcasecount="4" result="Passed" total="4" passed="4" failed="0" inconclusive="0" skipped="0">'
transcript "$P/tr.jsonl" "$(python3 -c 'import json,sys; print(json.dumps([["bash",sys.argv[1],sys.argv[2],False],["edit",sys.argv[4]],["bash",sys.argv[1],sys.argv[3],False]]))' "$CAT" "$X_RED" "$X_GREEN" "$CS")"
gate "$P" "$P/tr.jsonl" "$MSG"
expect "NUnit failed=\"1\" is red, failed=\"0\" is green" 0

# ── 5. mcp__antigravity-pm__pm_run kind=test running scripts/unity-test.sh ──
new_project
PM_IN='{"taskId":"T0001","kind":"test"}'
PM_RED='$ bash scripts/unity-test.sh
exit=1 · 312s · log day du: /p/.antigravity-pm/logs/test-r1-1.log
!!! PHA C: Co 1 test case Failed'
PM_GREEN='$ bash scripts/unity-test.sh
exit=0 · 305s · log day du: /p/.antigravity-pm/logs/test-r1-2.log
>>> [PHA C] DAT (Passed: 4, Failed: 0)
===== TAT CA BAI TEST DAT ====='
transcript "$P/tr.jsonl" "$(python3 -c 'import json,sys; i=json.loads(sys.argv[1]); print(json.dumps([["tool","mcp__antigravity-pm__pm_run",i,sys.argv[2],False],["edit",sys.argv[4]],["tool","mcp__antigravity-pm__pm_run",i,sys.argv[3],False]]))' "$PM_IN" "$PM_RED" "$PM_GREEN" "$CS")"
nunit_xml "$P/.antigravity-pm/logs/tests_editmode.xml" Passed 4 4 0
gate "$P" "$P/tr.jsonl" "$MSG"
expect "pm_run kind=test exit=1 → exit=0 is a RED→GREEN pair" 0

# ── 6. a fresh RED NUnit XML still blocks a pass claim ─────────────────────
new_project
transcript "$P/tr.jsonl" "$(python3 -c 'import json,sys; print(json.dumps([["edit",sys.argv[1]]]))' "$CS")"
nunit_xml "$P/Logs/agent-kit/tests_EditMode.xml" Failed 4 2 2
gate "$P" "$P/tr.jsonl" "EditMode 4/4 test pass."
expect "red NUnit XML (failed=2) blocks a pass claim" 2 "failures=2"

# ── 7. a zero failure count is never red: no RED before the edit → check 7 blocks
new_project
transcript "$P/tr.jsonl" "$(python3 -c 'import json,sys; print(json.dumps([["bash",sys.argv[1],sys.argv[2]+"\n"+sys.argv[3],False],["edit",sys.argv[4]],["bash",sys.argv[1],sys.argv[2],False]]))' "$UB" "$UB_GREEN" "$X_GREEN" "$CS")"
gate "$P" "$P/tr.jsonl" "$MSG"
expect "\"0 failed\" / failed=\"0\" before the edit is not a RED" 2 "CHECK 7"

# ── 8. a pm_run that never ran (tool error, no exit= line) is not a RED ─────
new_project
transcript "$P/tr.jsonl" "$(python3 -c 'import json,sys; i=json.loads(sys.argv[1]); print(json.dumps([["tool","mcp__antigravity-pm__pm_run",i,"Chua khai testCommand va khong truyen command.",True],["edit",sys.argv[3]],["tool","mcp__antigravity-pm__pm_run",i,sys.argv[2],False]]))' "$PM_IN" "$PM_GREEN" "$CS")"
gate "$P" "$P/tr.jsonl" "$MSG"
expect "pm_run tool error without exit= is not a RED" 2 "CHECK 7"

# ── 9. pm_run kind=audit is not a test run ─────────────────────────────────
new_project
transcript "$P/tr.jsonl" "$(python3 -c 'import json,sys; print(json.dumps([["edit",sys.argv[1]],["tool","mcp__antigravity-pm__pm_run",{"taskId":"T1","kind":"audit"},"exit=0 · 2s",False]]))' "$CS")"
gate "$P" "$P/tr.jsonl" "EditMode 4/4 test pass."
expect "pm_run kind=audit does not back a test claim" 2

# ── 10. unity-batch.sh compile is not a test run ───────────────────────────
new_project
transcript "$P/tr.jsonl" "$(python3 -c 'import json,sys; print(json.dumps([["edit",sys.argv[1]],["bash","bash .agents/active-profile/scripts/unity-batch.sh compile","PASS: compile clean (0 error CS), Unity 6000.0.1f1",False]]))' "$CS")"
gate "$P" "$P/tr.jsonl" "EditMode 4/4 test pass."
expect "unity-batch.sh compile does not back a test claim" 2

# ── 11. a green NUnit XML OLDER than the last .cs edit is stale ─────────────
new_project
transcript "$P/tr.jsonl" "$(python3 -c 'import json,sys; print(json.dumps([["edit",sys.argv[1]]]))' "$CS")"
nunit_xml "$P/Logs/agent-kit/tests_EditMode.xml" Passed 4 4 0
touch -t 202001010000 "$P/Logs/agent-kit/tests_EditMode.xml"
gate "$P" "$P/tr.jsonl" "EditMode 4/4 test pass."
expect "NUnit XML older than the last .cs edit does not back a claim" 2

# ── 12. a project's own scripts/unity-test.sh run directly (red = its non-zero exit)
new_project
UT_RED='!!! PHA C: Co 1 test case Failed
===== [PHA C] THAT BAI (exit 1) — 60 dong cuoi cua log ====='
UT_GREEN='>>> [PHA C] DAT (Passed: 4, Failed: 0)
===== TAT CA BAI TEST DAT ====='
transcript "$P/tr.jsonl" "$(python3 -c 'import json,sys; print(json.dumps([["bash","bash scripts/unity-test.sh",sys.argv[1],True],["edit",sys.argv[3]],["bash","bash scripts/unity-test.sh",sys.argv[2],False]]))' "$UT_RED" "$UT_GREEN" "$CS")"
gate "$P" "$P/tr.jsonl" "$MSG"
expect "scripts/unity-test.sh RED→GREEN (\"Failed: 0\" is green)" 0

if [ "$FAILS" -ne 0 ]; then echo "test_evidence_unity: $FAILS FAILED"; exit 1; fi
echo "test_evidence_unity: all checks passed"
