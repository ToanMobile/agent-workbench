#!/usr/bin/env bash
# #368: lệch hash giữa bản nguồn super-board và bản sao ở repo app phải được phát hiện tự động (super-board-drift.py).
# Chỉ dùng thư mục tạm; không đọc repo app thật.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DRIFT="${SB_TEST_DRIFT:-$ROOT/.claude/bin/super-board-drift.py}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-drift-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
S="$TMP/src"; A="$TMP/app"
mk() {  # mk <repo>: dựng bộ file super-board tối thiểu
  mkdir -p "$1/.claude/bin" "$1/.claude/workflows" "$1/.claude/skills/super-board/references"
  echo 'echo run' > "$1/.claude/bin/super-board-run.sh"
  echo 'print(1)' > "$1/.claude/bin/super-board-card.py"
  echo 'js' > "$1/.claude/workflows/super-board-wave.js"
  echo '# skill' > "$1/.claude/skills/super-board/SKILL.md"
  echo 'ref' > "$1/.claude/skills/super-board/references/run.md"
  echo 'local' > "$1/.claude/bin/my-own-tool.sh"
}
mk "$S"; mk "$A"
run() { python3 "$DRIFT" --source "$S" --target "$A" >"$TMP/out.json" 2>"$TMP/err.txt"; rc=$?; }

run; [ "$rc" -eq 0 ] && grep -q '"drifted": false' "$TMP/out.json" && ok "identical copy: exit 0, drifted=false" || fail "identical copy flagged (rc=$rc): $(cat "$TMP/out.json")"
echo 'echo edited' > "$A/.claude/bin/super-board-run.sh"
run; [ "$rc" -eq 1 ] && grep -q '"changed": \[".claude/bin/super-board-run.sh"\]' "$TMP/out.json" && ok "edited script reported as changed (exit 1)" || fail "edit not detected (rc=$rc): $(cat "$TMP/out.json")"
echo 'echo run' > "$A/.claude/bin/super-board-run.sh"
rm "$A/.claude/skills/super-board/references/run.md"
run; [ "$rc" -eq 1 ] && grep -q '"missing": \[".claude/skills/super-board/references/run.md"\]' "$TMP/out.json" && ok "deleted skill file reported as missing" || fail "missing file not detected (rc=$rc): $(cat "$TMP/out.json")"
echo 'ref' > "$A/.claude/skills/super-board/references/run.md"
echo 'extra' > "$A/.claude/bin/super-board-extra.sh"
run; [ "$rc" -eq 0 ] && ok "a file only the copy has is not drift" || fail "copy-only file flagged (rc=$rc)"
python3 "$DRIFT" --source "$S" --target "$S" >"$TMP/out.json" 2>&1; [ "$?" -eq 0 ] && ok "target == source is skipped" || fail "self-compare flagged"
python3 "$DRIFT" --source "$S" >"$TMP/out.json" 2>&1; [ "$?" -eq 64 ] && ok "no --target is a usage error (64)" || fail "missing --target not rejected"

# Rác chưa theo dõi ở nguồn (__pycache__/*.pyc, .DS_Store, file chưa git add) không được thành "missing" ở bản sao.
GS="$TMP/gsrc"; GA="$TMP/gapp"
mk "$GS"; mk "$GA"
git init -q "$GS"; git -C "$GS" add -A; git -C "$GS" -c user.email=t@example.invalid -c user.name=t commit -qm init
mkdir -p "$GS/.claude/skills/super-board/__pycache__"
echo x > "$GS/.claude/skills/super-board/__pycache__/m.cpython-314.pyc"; echo x > "$GS/.claude/skills/super-board/.DS_Store"
echo x > "$GS/.claude/bin/super-board-stray.sh"
python3 "$DRIFT" --source "$GS" --target "$GA" >"$TMP/out.json" 2>"$TMP/err.txt"; rc=$?
[ "$rc" -eq 0 ] && grep -q '"drifted": false' "$TMP/out.json" && ok "git source: untracked __pycache__/.DS_Store/stray files are not drift" || fail "untracked junk reported as drift (rc=$rc): $(cat "$TMP/out.json")"
# Nguồn không phải repo git (đường lùi): vẫn bỏ __pycache__, file ẩn, *.pyc.
mkdir -p "$S/.claude/skills/super-board/__pycache__"; echo x > "$S/.claude/skills/super-board/__pycache__/m.pyc"
echo x > "$S/.claude/skills/super-board/.DS_Store"; echo x > "$S/.claude/skills/super-board/stale.pyc"
run; [ "$rc" -eq 0 ] && ok "non-git source fallback skips __pycache__, dotfiles, *.pyc" || fail "fallback reported junk as drift (rc=$rc): $(cat "$TMP/out.json")"
# File thật đã theo dõi ở nguồn mà bản sao thiếu vẫn là missing.
echo real > "$GS/.claude/skills/super-board/references/new.md"; git -C "$GS" add -A; git -C "$GS" -c user.email=t@example.invalid -c user.name=t commit -qm more
python3 "$DRIFT" --source "$GS" --target "$GA" >"$TMP/out.json" 2>&1; rc=$?
[ "$rc" -eq 1 ] && grep -q 'references/new.md' "$TMP/out.json" && ok "a tracked file missing from the copy is still reported" || fail "tracked missing file not reported (rc=$rc)"

[ "$FAILS" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$FAILS FAILED"; exit 1
