#!/usr/bin/env bash
# Hồi quy K4 (17/10): `agent-kit worktree finish <wt>` chạy từ BÊN TRONG worktree bị từ chối "chạy từ MAIN checkout (...)": agent
# làm việc trong worktree gọi đúng lệnh nhưng bị từ chối và phải đoán lại. Giờ: cwd là một worktree của cùng repo thì finish tự
# dùng main checkout; các kiểm tra khác (đường dẫn không phải worktree, ...) giữ nguyên.
#   1 commit trong worktree, `finish .` từ trong worktree: gộp vào main, worktree bị gỡ
#   2 file mới đã commit tay (finish không tự commit việc thật, #366), `finish <đường dẫn tuyệt đối>` từ một thư mục con của worktree: cũng gộp
#   3 từ trong worktree, một đường dẫn không phải worktree: vẫn bị từ chối như cũ
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

P="$TMP/main"; mkdir -p "$P" && G "$P" init -q -b main . && cd "$P" || exit 1
printf '1\n2\n3\n' > "$P/a.txt"; G "$P" add -A && G "$P" commit -qm init
wt() { bash "$KIT" worktree add "../fi-$1" --no-init >/dev/null 2>&1 || fail "add fi-$1"; }

# 1: commit trong worktree, chạy `finish .` từ chính worktree
wt a; echo a > "$TMP/fi-a/a-new.txt"; G "$TMP/fi-a" add -A && G "$TMP/fi-a" commit -qm "a-new"; WH="$(G "$TMP/fi-a" rev-parse HEAD)"
(cd "$TMP/fi-a" && bash "$KIT" worktree finish . >"$TMP/out" 2>&1); rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/fi-a" ] && [ "$(G "$P" rev-parse HEAD)" = "$WH" ] && [ -f "$P/a-new.txt" ] && ! grep -q "MAIN checkout" "$TMP/out" \
  && ok "1: finish . from inside the worktree: merged into main, the worktree is removed" || fail "1: (rc=$rc): $(cat "$TMP/out")"

# 2: file mới commit tay (finish không tự commit việc thật, #366), finish với đường dẫn tuyệt đối từ một thư mục con của worktree
wt b; mkdir -p "$TMP/fi-b/sub"; echo b > "$TMP/fi-b/sub/b.txt"
G "$TMP/fi-b" add -A && G "$TMP/fi-b" commit -qm "b by hand"   # finish never commits real work (#366)
(cd "$TMP/fi-b/sub" && bash "$KIT" worktree finish "$TMP/fi-b" >"$TMP/out" 2>&1); rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/fi-b" ] && [ -f "$P/sub/b.txt" ] && [ -z "$(G "$P" status --porcelain --untracked-files=no)" ] \
  && ok "2: finish <abs path> from a subfolder of the worktree: merged, removed" || fail "2: (rc=$rc): $(cat "$TMP/out")"

# 3: các kiểm tra khác vẫn còn: từ trong worktree, đường dẫn không phải worktree đã đăng ký thì bị từ chối
wt c
(cd "$TMP/fi-c" && bash "$KIT" worktree finish ../nope >"$TMP/out" 2>&1); rc=$?
[ "$rc" = 1 ] && grep -q "not a registered worktree" "$TMP/out" && [ -d "$TMP/fi-c" ] \
  && ok "3: from inside a worktree, a path that is no worktree is still refused" || fail "3: (rc=$rc): $(cat "$TMP/out")"

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_finish_inside: all passed" || { echo "❌ test_worktree_finish_inside: $FAILS failed"; exit 1; }
