#!/usr/bin/env bash
# super-board-status.py: slug trong `.claude/super-board/active` chứa đường dẫn (`../x`, `a/b`, `.`, `..`) bị bỏ qua,
# rơi về config duy nhất; cùng lớp lỗi với repo_board.py (audit PR #1394, thẻ #1402).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-status-slug.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo/.claude/super-board/configs"
echo '{}' > "$TMP/repo/.claude/super-board/configs/home.json"

slug_for() {
  printf '%s\n' "$1" > "$TMP/repo/.claude/super-board/active"
  PYTHONDONTWRITEBYTECODE=1 python3 - "$ROOT/.claude/bin/super-board-status.py" "$TMP/repo" <<'PY'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("sb_status", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(mod.resolve_config_slug(["status"], Path(sys.argv[2])))
PY
}

for bad in '../x' 'a/b' '..' '.' 'a\b'; do
  got="$(slug_for "$bad" 2>&1)"
  if [ "$got" = "home" ]; then ok "slug '$bad' bị bỏ qua, rơi về config duy nhất"; else fail "slug '$bad' được nhận: '$got'"; fi
done
got="$(slug_for 'home' 2>&1)"
if [ "$got" = "home" ]; then ok "slug hợp lệ vẫn được dùng"; else fail "slug hợp lệ: '$got'"; fi

[ "$FAILS" -eq 0 ] && { echo "✅ test_status_active_slug_path_1402: all passed"; exit 0; }
echo "❌ test_status_active_slug_path_1402: $FAILS failed"; exit 1
