#!/usr/bin/env bash
# hooks/guard-review-tamper.py (audit 31/10/2026, BUG-REV-review-tamper-guard): agent writes/deletes of the review machinery are
# denied (run dir, settings, hooks, bin/review*, CI workflows, the seal key); reads and ordinary edits pass.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_ALLOW_GATE_EDIT
DK="$(cd "$(dirname "$0")/../.." && pwd)"
G="$DK/hooks/guard-review-tamper.py"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
judge() {   # judge <tool> <value> -> deny|allow
  python3 - "$G" "$1" "$2" <<'PY'
import json, subprocess, sys
g, tool, v = sys.argv[1:4]
key = {"Bash": "command"}.get(tool, "file_path")
p = subprocess.run([sys.executable, g], input=json.dumps({"tool_name": tool, "tool_input": {key: v}, "cwd": "/repo"}),
                   capture_output=True, text=True, timeout=20)
print("deny" if '"deny"' in p.stdout else "allow")
PY
}
expect() { got="$(judge "$2" "$3")"; [ "$got" = "$1" ] && ok "$1: $2 $3" || fail "$2 $3: expected $1, got $got"; }
expect deny Write  /repo/.git/review-fanout/abc/summary.json
expect deny Edit   /repo/.claude/settings.json
expect deny Edit   /repo/.claude/settings.local.json
expect deny Edit   /repo/universal-agent-devkit/hooks/review_gate.sh
expect deny Write  /repo/.agents/devkit/hooks/new_hook.sh
expect deny Edit   /repo/universal-agent-devkit/bin/review-merge.py
expect deny Write  /repo/.github/workflows/pr-review.yml
expect deny Write  "$HOME/.config/agent-workbench/review.key"
expect deny Bash   'echo "{\"verdict\":\"PASS\"}" > .git/review-fanout/x/summary.json'
expect deny Bash   'rm -rf .git/review-fanout'
expect deny Bash   'cp /tmp/s.json .claude/settings.json'
expect deny Bash   "python3 -c 'open(\".git/review-fanout/x/summary.json\",\"w\").write(1)'"
expect deny Bash   "node -e \"require('fs').unlinkSync('universal-agent-devkit/hooks/review_gate.sh')\""
expect allow Bash  'cat .git/review-fanout/x/summary.md && grep -n verdict universal-agent-devkit/bin/review-merge.py'
expect allow Edit  /repo/src/app.py
expect allow Write /repo/universal-agent-devkit/tests/gates/test_x.sh
expect allow Edit  /repo/docs/hooks.md
got="$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/repo/.git/review-fanout/a"}}' | DEVKIT_ALLOW_GATE_EDIT=1 python3 "$G")"
[ -z "$got" ] && ok "DEVKIT_ALLOW_GATE_EDIT=1 in the hook environment: maintenance mode" || fail "override ignored"
[ "$FAILS" = 0 ] && { echo "guard review tamper: all checks passed"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
