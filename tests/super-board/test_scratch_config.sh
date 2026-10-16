#!/usr/bin/env bash
# Test hồi quy cho .claude/bin/super-board-scratch-config.sh (merge gate dựng worktree sạch để verify).
# 2026-10-16 (OfficeReader #73, PR #126): review đạt, test xanh, nhưng merge gate đỏ vì worktree sạch thiếu
# google-services.json (file bị git ignore), build Android hỏng, thẻ kẹt ở Review chờ người.
# Config cục bộ bị git ignore phải được chép từ main checkout; file không bị ignore thì không chép (không commit nhầm).
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="$ROOT/.claude/bin/super-board-scratch-config.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-scratchcfg-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; S="$TMP/scratch"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
mkdir -p "$R/app"
printf 'google-services.json\nlocal.properties\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add .gitignore a; git -C "$R" commit -qm init
echo '{"project_info":{}}' > "$R/app/google-services.json"
echo 'sdk.dir=/x' > "$R/local.properties"
echo 'TOKEN=x' > "$R/.env"                      # không bị ignore: không được chép
git -C "$R" worktree add -q --detach "$S" main

bash "$HELPER" "$R" "$S" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0" || fail "exit $rc"
[ -f "$S/app/google-services.json" ] && ok "ignored google-services.json copied into the scratch worktree" \
  || fail "google-services.json missing in the scratch worktree (Android build red, card stuck in Review)"
[ -f "$S/local.properties" ] && ok "ignored local.properties copied" || fail "local.properties missing"
[ ! -e "$S/.env" ] && ok "config file git does not ignore is not copied (cannot be committed by mistake)" || fail ".env copied although not ignored"
[ -z "$(git -C "$S" status --porcelain)" ] && ok "scratch worktree stays clean for git" || fail "scratch worktree dirty: $(git -C "$S" status --porcelain | head -3)"

[ "$FAILS" -eq 0 ] && echo "✅ test_scratch_config: all passed" || { echo "❌ test_scratch_config: $FAILS failed"; exit 1; }
