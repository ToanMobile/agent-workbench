#!/usr/bin/env bash
# Regression test: Stop links a bug to its test by itself — only when the evidence is one-to-one:
#   exactly one unlinked bug row this session touched, exactly one test file written/edited
#   this session, a runner RED naming that test after the test was written and BEFORE the
#   first source edit, a GREEN run after the last source edit, and a proven fix claim.
#   The row is marked linked_by=auto (🤖 in the view) and gets a sandbox RED-proof next.
#   Anything ambiguous (two test files, two bugs, red only after the code was touched) →
#   no link, the reminder instead. AUTO_LINK=0 turns it off.
# Also: a REPORTED row nobody touched for 14 days → 💤 AUTO_CLOSED (not counted, not
#   deleted); the same bug prompt again reopens that row.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT_HOOK="$DEVKIT_DIR/hooks/prompt_context.sh"; STOP_GATE="$DEVKIT_DIR/hooks/test_evidence_gate.sh"
SESSION_HOOK="$DEVKIT_DIR/hooks/session_context.sh"; KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
unset PROMPT_CONTEXT BUG_CAPTURE AUTO_LINK

new_project() {
  P="$TMP/p$RANDOM"; mkdir -p "$P/src" "$P/tests" "$P/.agents"
  ( cd "$P" && git init -q . && git config user.email t@t && git config user.name t
    printf 'def add(a, b):\n    return a - b\n' > src/calc.py
    cat > .agents/regression_matrix.active.json <<'JSON'
{"adopted": true, "rules":[{"component":"Calc","watch_files":["src/*.py","tests/*.py"],
 "mandatory_regression_tests":[{"id":"REG-CALC","name":"calc","command":"python3 -m unittest discover -s tests"}]}]}
JSON
    git add -A && git commit -qm init )
}
report() {  # report <session> <prompt> → bug id
  python3 -c 'import json,sys; print(json.dumps({"prompt": sys.argv[1], "session_id": sys.argv[2]}))' "$2" "$1" 2>/dev/null \
    | CLAUDE_PROJECT_DIR="$P" bash "$PROMPT_HOOK" 2>/dev/null | grep -o 'BUG-[A-Za-z0-9_-]*' | head -1; }
# transcript <steps…>: w:<test file> | r:<test file>  (red run naming it) | e:<src file> | g (green run)
transcript() {
  python3 - "$P" "$@" <<'PY'
import json, sys
P, steps = sys.argv[1], sys.argv[2:]
lines = []
for i, s in enumerate(steps):
    kind, _, arg = s.partition(":")
    uid = f"t{i}"
    if kind == "w":
        open(f"{P}/{arg}", "w").write("import unittest\n")      # the Write really happened
        use = {"name": "Write", "input": {"file_path": f"{P}/{arg}", "content": "x"}}; res, err = "ok", False
    elif kind == "e":
        use = {"name": "Edit", "input": {"file_path": f"{P}/{arg}", "old_string": "-", "new_string": "+"}}; res, err = "ok", False
    elif kind == "r":
        use = {"name": "Bash", "input": {"command": "python3 -m unittest discover -s tests"}}
        res, err = f"FAIL: test_add ({arg.rsplit('/', 1)[-1][:-3]}.TestAdd.test_add)\nFAILED (failures=1)", True
    else:
        use = {"name": "Bash", "input": {"command": "python3 -m unittest discover -s tests"}}; res, err = "Ran 1 test\n\nOK", False
    lines.append(json.dumps({"message": {"content": [{"type": "tool_use", "id": uid, **use}]}}))
    lines.append(json.dumps({"message": {"content": [{"type": "tool_result", "tool_use_id": uid, "content": res, "is_error": err}]}}))
open(f"{P}/tr.jsonl", "w").write("\n".join(lines) + "\n")
PY
}
stop() {  # stop <session> → RC, ERR
  ERR="$(python3 -c 'import json,sys; print(json.dumps({"session_id": sys.argv[1], "transcript_path": sys.argv[2], "last_assistant_message": "Đã fix lỗi add, test RED→GREEN."}))' "$1" "$P/tr.jsonl" \
         | CLAUDE_PROJECT_DIR="$P" LESSON_REMINDER=0 RED_PROOF=0 bash "$STOP_GATE" 2>&1 >/dev/null)"; RC=$?; }
row() { python3 -c "import json;it=json.load(open('$P/.agents/regression_status.json'))['items']['$1'];print(','.join(it.get('tests',[])), it.get('linked_by','-'))"; }

# ── one-to-one → auto-link ──────────────────────────────────────────────────
new_project; B="$(report s1 "App bị crash khi cộng hai số")"
transcript w:tests/test_calc.py r:tests/test_calc.py e:src/calc.py g
stop s1
[ "$RC" = 0 ] && [ "$(row "$B")" = "REG-CALC auto" ] && ok "one bug, one test, red before the fix, green after → linked by itself (🤖)" \
  || fail "auto-link: rc=$RC row=$(row "$B") $ERR"
python3 -c "import json;it=json.load(open('$P/.agents/regression_status.json'))['items']['$B'];assert 'tests/test_calc.py' in it.get('runs_in_suite',[])" 2>/dev/null \
  && ok "the test file is kept on the row (for the sandbox RED-proof)" || fail "no test file on row"
grep -q "🤖" "$P/.agents/regression_checklist.md" && ok "view marks the auto link 🤖" || fail "view: no 🤖"

# ── ambiguous → no link, reminder instead ───────────────────────────────────
new_project; B="$(report s2 "App bị crash khi cộng hai số")"
transcript w:tests/test_calc.py w:tests/test_other.py r:tests/test_calc.py e:src/calc.py g
stop s2
[ "$(row "$B")" = " -" ] && [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q "bugs link $B" && ok "two test files edited → no auto-link, reminder" \
  || fail "two tests: rc=$RC row=$(row "$B")"

new_project; B="$(report s3 "App bị crash khi cộng hai số")"
transcript w:tests/test_calc.py e:src/calc.py r:tests/test_calc.py e:src/calc.py g
stop s3
[ "$(row "$B")" = " -" ] && ok "red only after the code was touched → no auto-link" || fail "late red: $(row "$B")"

new_project; B="$(report s4 "App bị crash khi cộng hai số")"; B2="$(report s4 "Màn hình bị treo khi mở")"
transcript w:tests/test_calc.py r:tests/test_calc.py e:src/calc.py g
stop s4
[ "$(row "$B")" = " -" ] && [ "$(row "$B2")" = " -" ] && ok "two unlinked bugs in the session → no auto-link" || fail "two bugs: $(row "$B") / $(row "$B2")"

new_project; B="$(report s5 "App bị crash khi cộng hai số")"
transcript w:tests/test_calc.py r:tests/test_calc.py e:src/calc.py g
ERR="$(python3 -c 'import json,sys; print(json.dumps({"session_id": "s5", "transcript_path": sys.argv[1], "last_assistant_message": "Đã fix lỗi add, test RED→GREEN."}))' "$P/tr.jsonl" \
       | CLAUDE_PROJECT_DIR="$P" LESSON_REMINDER=0 RED_PROOF=0 AUTO_LINK=0 bash "$STOP_GATE" 2>&1 >/dev/null)"
[ "$(row "$B")" = " -" ] && ok "AUTO_LINK=0 → no auto-link" || fail "AUTO_LINK=0 linked"

# ── 💤 auto-close stale REPORTED ────────────────────────────────────────────
new_project; B="$(report s6 "Nút lưu không hoạt động trên tablet")"
python3 - "$P" "$B" <<'PY'
import json, sys, time
p = sys.argv[1] + "/.agents/regression_status.json"; d = json.load(open(p))
old = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(time.time() - 15 * 86400))
d["items"][sys.argv[2]].update({"created_at": old, "touched_at": old}); json.dump(d, open(p, "w"))
PY
echo '{}' | CLAUDE_PROJECT_DIR="$P" bash "$SESSION_HOOK" >/dev/null 2>&1
st() { python3 -c "
import sys; sys.path.insert(0,'$DEVKIT_DIR/bin'); import regression_checklist as r, pathlib
d=r.load(pathlib.Path('$P')); print(r.effective_status(d, d['items']['$1']))"; }
[ "$(st "$B")" = AUTO_CLOSED ] && ok "REPORTED untouched for 14 days → 💤 AUTO_CLOSED at session start" || fail "auto-close: $(st "$B")"
[ "$(report s7 "Nút lưu không hoạt động trên tablet")" = "$B" ] && [ "$(st "$B")" = REPORTED ] \
  && ok "the same bug prompt again reopens that row (no duplicate)" || fail "reopen: $(st "$B")"

[ "$FAILS" -eq 0 ] && echo "✅ test_auto_link: all passed" || { echo "❌ test_auto_link: $FAILS failed"; exit 1; }
