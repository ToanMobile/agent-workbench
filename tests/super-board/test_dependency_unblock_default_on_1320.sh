#!/usr/bin/env bash
# Test hồi quy #1320: cờ dependency_unblock_v1 mặc định BẬT (5 repo app không có .agents/local/flags.json nên thẻ chờ thẻ khác bị
# Blocked ⏳ thay vì ở Ready `waiting-on`). Vẫn tắt được bằng env SB_DEPENDENCY_UNBLOCK_V1=0 hoặc flags.json `false`.
#  A: không env, không flags.json -> bật (ĐỎ trên runner cũ).
#  B: env 0 -> tắt (kể cả khi flags.json true).
#  C: flags.json false -> tắt.
#  D: env 1 -> bật kể cả khi flags.json false.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-1320.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
unset SB_DEPENDENCY_UNBLOCK_V1
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
FR="$TMP/repo"; mkdir -p "$FR/.agents/local"
git -C "$FR" init -q 2>/dev/null
git -C "$FR" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init 2>/dev/null
REPO_ROOT="$FR"
flag() { dependency_unblock_v1_on && echo on || echo off; }

unset SB_DEPENDENCY_UNBLOCK_V1; rm -f "$FR/.agents/local/flags.json"
r=$(flag); [ "$r" = on ] && ok "A: no env, no flags.json -> on" || fail "A: no env, no flags.json -> $r (want on)"

echo '{"dependency_unblock_v1": true}' > "$FR/.agents/local/flags.json"
r=$(export SB_DEPENDENCY_UNBLOCK_V1=0; flag); [ "$r" = off ] && ok "B: env 0 -> off" || fail "B: env 0 -> $r (want off)"

echo '{"dependency_unblock_v1": false}' > "$FR/.agents/local/flags.json"
r=$(flag); [ "$r" = off ] && ok "C: flags.json false -> off" || fail "C: flags.json false -> $r (want off)"

r=$(export SB_DEPENDENCY_UNBLOCK_V1=1; flag); [ "$r" = on ] && ok "D: env 1 beats flags.json false -> on" || fail "D: env 1 -> $r (want on)"

[ "$FAILS" = 0 ] && { echo "PASS test_dependency_unblock_default_on_1320"; exit 0; }
echo "FAIL test_dependency_unblock_default_on_1320 ($FAILS)"; exit 1
