#!/usr/bin/env bash
# 13/11 (chủ repo bỏ Grok): super-board-audit-check.py <task> <sha> (comment approved-by / cross-review của board) chỉ nhận biên bản
# audit pass của reviewer antigravity. Biên bản grok (reviewer grok, lượt audit gần nhất grok) cùng auditedHead -> exit 1 (code cũ: 0).
#  A1 biên bản grok tại head -> 1.   A2 đối chứng: biên bản antigravity tại head -> 0.   A3 biên bản cũ (reviewer pm, không dispatch) -> 0.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
CHECK="$ROOT/.claude/bin/super-board-audit-check.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-audit-nogrok.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm" DEVKIT_PM_HOME_TEST=1
unset DEVKIT_AGENT_ID CLAUDECODE CLAUDE_CODE_SESSION_ID GROK_SESSION_ID GROK_WORKSPACE_ROOT GROK_HOOK_EVENT
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"; mkdir -p "$R" && cd "$R" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
echo a > a.txt && git add -A && git commit -qm M0
H="$(git rev-parse HEAD)"
task() {   # task <id> <reviewer> <dispatches-json>
  mkdir -p "$TMP/pm/projects/p-$1/tasks/$1"
  printf '{"id":"%s","project":"%s","dispatches":%s,"verdicts":{"audit":{"verdict":"pass","round":1,"reviewer":"%s","notes":"ok","auditedHead":"%s"}}}\n' \
    "$1" "$(pwd -P)" "$3" "$2" "$H" > "$TMP/pm/projects/p-$1/tasks/$1/task.json"
}
check() { python3 "$CHECK" "$1" "$H" --top "$R" >/dev/null 2>"$TMP/err"; echo $?; }

task T0001-g grok '[{"kind":"audit","agent":"grok","at":"2026-11-04T00:00:00Z"}]'
[ "$(check T0001-g)" = 1 ] && ok "A1: biên bản grok tại head -> không nhận" || fail "A1: biên bản grok vẫn được nhận"
task T0002-a antigravity '[{"kind":"audit","agent":"antigravity","at":"2026-11-04T00:00:00Z"}]'
[ "$(check T0002-a)" = 0 ] && ok "A2: biên bản antigravity tại head -> nhận" || fail "A2: antigravity bị từ chối: $(cat "$TMP/err")"
task T0003-l pm '[]'
[ "$(check T0003-l)" = 0 ] && ok "A3: biên bản cũ (reviewer pm, không dispatch) -> nhận như trước" || fail "A3: biên bản cũ: $(cat "$TMP/err")"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
