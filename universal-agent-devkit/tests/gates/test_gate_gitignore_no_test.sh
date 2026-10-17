#!/usr/bin/env bash
# Hồi quy (17/10, đưa .gitignore của bộ cài K7 lên 4 repo): diff chỉ đổi `.gitignore` bị gate trả exit 2 "không có test hồi quy
# nào khớp thay đổi (--allow-no-tests để chấp nhận)". Merge gate của super-board (OfficeReader PR #140, Neighbours) không truyền
# cờ đó, nên PR không gộp được và người dùng phải can thiệp. `.gitignore` chỉ git đọc, không chương trình nào của dự án đọc: giống
# `.claude/settings.json` (29/09, Goods), nó không cần test hồi quy.
#  Đối chứng: `.gitignore` kèm code không rule nào phủ vẫn exit 2; một file tên khác chứa "gitignore" vẫn cần test.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

mk() {
  R="$TMP/$1"; mkdir -p "$R/src" "$R/lib" "$R/.agents" "$R/app" && cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt; echo "fun lib() = 1" > lib/X.kt
  printf '.env\n' > .gitignore; printf 'build/\n' > app/.gitignore; echo "a" > lib/gitignore_rules.kt
  printf '{"project":"t","rules":[{"component":"C","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-1","name":"c","command":"true"}]}]}\n' \
    > .agents/regression_matrix.active.json
  git add -A && git commit -qm init
}
exit_of() { ( cd "$TMP/$1" && CLAUDE_PROJECT_DIR="$TMP/$1" python3 "$DEVKIT_DIR/bin/post-fix-gate.py" --run-tests --json > "$TMP/$1.out" 2>&1; echo $? ); }
expect() {   # name, description, expected exit
  local rc; rc="$(exit_of "$1")"
  [ "$rc" = "$3" ] && ok "$2 → exit $rc" || fail "$2: exit $rc, expected $3 ($(grep -o '"verdict": "[^"]*"' "$TMP/$1.out" | tail -1 | cut -c1-110))"
}

mk a; printf '.env\n.agents/hooks/\n' > .gitignore
expect a "root .gitignore only (K7 sync)" 0
mk b; printf 'build/\n*.apk\n' > app/.gitignore
expect b "a nested app/.gitignore only" 0
mk c; printf '.env\n.agents/hooks/\n' > .gitignore; echo "fun lib() = 2" > lib/X.kt
expect c ".gitignore + code no rule covers still stops" 2
mk d; echo "b" > lib/gitignore_rules.kt
expect d "a source file whose name contains gitignore still needs a test" 2

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_gitignore_no_test: all passed" || { echo "❌ test_gate_gitignore_no_test: $FAILS failed"; exit 1; }
