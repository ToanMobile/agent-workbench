#!/usr/bin/env bash
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

failed=0
ok() { echo "  ok   $1"; }
fail() { echo "FAIL $1"; failed=$((failed+1)); }

ENRICH="$(cd "$(dirname "$0")/../.." && pwd)/scripts/context/enrich_context.py"

TMP=$(mktemp -d)
trap 'chmod -R 755 "$TMP"; rm -rf "$TMP"' EXIT

cd "$TMP"
git init -q
git config user.email "test@example.com"
git config user.name "Test"

mkdir -p .claude/audit-gate .agents
echo '{"profile":"android"}' > .agents/active-profile.json

export CLAUDE_PROJECT_DIR="$TMP"

echo "(i) valid UI bug prompt"
printf '{"prompt":"fix bug: the button overlaps the nav bar, UI is broken","session_id":"sess1","hook_event_name":"UserPromptSubmit"}' | python3 -B -I "$ENRICH" --hook > out1 2> err1
rc=$?
[ "$rc" = 0 ] || fail "(i) rc != 0"
grep -q "Traceback" err1 && fail "(i) Traceback in stderr: $(cat err1)"
grep -q "NameError" err1 && fail "(i) NameError in stderr: $(cat err1)"
[ -f ".claude/audit-gate/turn_class_sess1.json" ] || fail "(i) file not created"
grep -q "BUG_FIX" ".claude/audit-gate/turn_class_sess1.json" || fail "(i) missing BUG_FIX"
grep -q "UI_INTERACTION" ".claude/audit-gate/turn_class_sess1.json" || fail "(i) missing UI_INTERACTION"
ok "(i) valid UI bug prompt"

echo "(v) non-UI bug prompt on android"
echo '{"profile":"android"}' > .agents/active-profile.json
printf '{"prompt":"fix the failing unit test in DateParser","session_id":"sess3","hook_event_name":"UserPromptSubmit"}' | python3 -B -I "$ENRICH" --hook > out5 2> err5
[ -f ".claude/audit-gate/turn_class_sess3.json" ] && fail "(v) file should not be created for non-UI bug"
ok "(v) non-UI bug prompt on android"

echo "(ii) non-UI prompt"
printf '{"prompt":"hello world","session_id":"sess1","hook_event_name":"UserPromptSubmit"}' | python3 -B -I "$ENRICH" --hook > out2 2> err2
[ -f ".claude/audit-gate/turn_class_sess1.json" ] && fail "(ii) file should be deleted"
ok "(ii) non-UI prompt"

echo "(iii) backend profile"
echo '{"profile":"backend"}' > .agents/active-profile.json
printf '{"prompt":"fix bug: the button overlaps the nav bar, UI is broken","session_id":"sess1","hook_event_name":"UserPromptSubmit"}' | python3 -B -I "$ENRICH" --hook > out3 2> err3
[ -f ".claude/audit-gate/turn_class_sess1.json" ] && fail "(iii) file should not be created for backend"
ok "(iii) backend profile"

echo "(iv) read-only directory fail-open"
echo '{"profile":"android"}' > .agents/active-profile.json
chmod 555 .claude/audit-gate
printf '{"prompt":"fix bug: the button overlaps the nav bar, UI is broken","session_id":"sess2","hook_event_name":"UserPromptSubmit"}' | python3 -B -I "$ENRICH" --hook > out4 2> err4
rc=$?
[ "$rc" = 0 ] || fail "(iv) rc != 0 ($rc)"
grep -q "Traceback" err4 && fail "(iv) Traceback in stderr: $(cat err4)"
ok "(iv) read-only directory fail-open"

if [ "$failed" != 0 ]; then
  echo "$failed FAILED"
  exit 1
fi
echo "ALL OK"

