#!/usr/bin/env bash
# Test hồi quy #974: test kit trong tests/super-board nạp clean_git_env.sh và super_board_all.py không có fallback
# .agents/devkit, nên bản sao byte-for-byte vào repo app (DevKit ở .agents/devkit) bỏ qua lặng lẽ bước reset env.
# Test chạy khối nạp thật trích từ từng file trong một ROOT giả chỉ có .agents/devkit. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-kitfb.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# ROOT giả: chỉ có .agents/devkit (không có universal-agent-devkit).
mkdir -p "$TMP/fake/.agents/devkit/tests/lib" "$TMP/fake/.agents/devkit/scripts/governance"
echo 'SENTINEL_CLEAN_ENV=1' > "$TMP/fake/.agents/devkit/tests/lib/clean_git_env.sh"
: > "$TMP/fake/.agents/devkit/scripts/governance/super_board_all.py"

n=0
for f in "$ROOT"/tests/super-board/*.sh; do
  [ "$(basename "$f")" = test_kit_tests_devkit_fallback.sh ] && continue
  # Chỉ xét file nạp clean_git_env.sh bằng lệnh source thật (bỏ dòng comment).
  grep -v '^[[:space:]]*#' "$f" | grep -q 'tests/lib/clean_git_env\.sh' || continue
  n=$((n + 1))
  name="$(basename "$f")"
  # Khối nạp = từ dòng `for _dk in` đến `done` đầu tiên sau đó.
  awk '/^for _dk in /{p=1} p{print} p&&/^done/{exit}' "$f" > "$TMP/block.sh"
  if [ ! -s "$TMP/block.sh" ]; then fail "$name: no .agents/devkit fallback loop for clean_git_env.sh"; continue; fi
  out="$(ROOT="$TMP/fake" bash -c '. "$1"; echo "${SENTINEL_CLEAN_ENV:-unset}"' _ "$TMP/block.sh" 2>&1)"
  [ "$out" = 1 ] && ok "$name sources clean_git_env.sh from .agents/devkit" \
    || fail "$name: block did not source clean_git_env.sh with only .agents/devkit (got: $out)"
done
[ "$n" -ge 70 ] && ok "scanned $n tests that source clean_git_env.sh" || fail "scanned only $n tests (expected >= 70)"

# test_runner_watchdog.sh mục 9: SBA phải phân giải được từ .agents/devkit.
W="$ROOT/tests/super-board/test_runner_watchdog.sh"
grep -Eq '^SBA=.*(\.agents/devkit|_dk)|^for _dk in .*\.agents/devkit.*' "$W" && grep -n 'super_board_all.py' "$W" | grep -q '_dk\|\.agents/devkit' \
  && ok "test_runner_watchdog.sh resolves super_board_all.py with .agents/devkit fallback" \
  || fail "test_runner_watchdog.sh looks for super_board_all.py only under universal-agent-devkit"

[ "$FAILS" = 0 ] && echo "ALL PASS" || { echo "$FAILS FAILED"; exit 1; }
