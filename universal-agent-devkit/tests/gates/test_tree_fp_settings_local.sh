#!/usr/bin/env bash
# bin/tree_fp.py, #691: bản cài kit thêm hook vào .claude/settings.json của mỗi worktree và không commit, nên tree_fingerprint() của cây
# chạy gate khác commit_fingerprint(HEAD) và biên nhận gate không khớp head đã push (PR #690: cây 48c35c95, head 34406c88). Sửa CHƯA
# commit của đúng file đó không được đổi fingerprint; nội dung ĐÃ commit vẫn tính (nên EXCLUDE không được nêu tên nó: PR sửa settings.json
# thật sẽ dùng lại biên nhận cũ); mọi file tracked khác vẫn tính. Ca 6-10: git lỗi thì fail-closed, thư mục trùng tên, file lớn.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TFP="${TFP_SCRIPT:-$DEVKIT_DIR/bin/tree_fp.py}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

fp()  { python3 -I "$TFP" "$1"; }
cfp() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import tree_fp; print(tree_fp.commit_fingerprint(sys.argv[2]))' "$(dirname "$TFP")" "$1"; }
newrepo() {
    git -C "$1" init -q -b main . && git -C "$1" config user.email t@t && git -C "$1" config user.name t && git -C "$1" config commit.gpgsign false
}

R="$TMP/repo"
mkdir -p "$R/src" "$R/.claude"
newrepo "$R"
printf 'fun ok() = 1\n' > "$R/src/Core.kt"
printf '{"hooks":{}}\n' > "$R/.claude/settings.json"
git -C "$R" add -A && git -C "$R" commit -qm init
HEAD0="$(cfp "$R")"
[ -n "$HEAD0" ] && [ "$(fp "$R")" = "$HEAD0" ] && ok "clean checkout: tree fingerprint = commit fingerprint" || { bad "clean tree differs from commit fp (or empty)"; exit 1; }

# 1. sửa chưa commit settings.json (việc của bản cài kit): fingerprint vẫn là của HEAD
printf '{"hooks":{"PreToolUse":["instincts_file_context.sh"]}}\n' > "$R/.claude/settings.json"
[ "$(fp "$R")" = "$HEAD0" ] && ok "uncommitted settings.json edit: tree fingerprint = commit_fingerprint(HEAD)" || bad "uncommitted settings.json edit moved the fingerprint away from HEAD's"

# 2. commit một thay đổi settings.json: commit fingerprint đổi, tree fingerprint đổi theo
git -C "$R" add .claude/settings.json && git -C "$R" commit -qm "settings change"
HEAD1="$(cfp "$R")"
[ "$HEAD1" != "$HEAD0" ] && ok "committed settings.json change: commit_fingerprint moves" || bad "commit_fingerprint did not move (settings.json is excluded?)"
[ "$(fp "$R")" = "$HEAD1" ] && ok "after the commit: tree fingerprint = new commit fingerprint" || bad "tree fingerprint differs from the new commit fingerprint"
printf '{"hooks":{"local":"again"}}\n' > "$R/.claude/settings.json"
[ "$(fp "$R")" = "$HEAD1" ] && ok "a second uncommitted edit on top of the new commit: still the HEAD one" || bad "second uncommitted settings.json edit moved the fingerprint"
git -C "$R" checkout -q -- .claude/settings.json

# 3. file tracked khác vẫn tính, dù settings.json có bẩn hay không
printf 'fun ok() = 2\n' > "$R/src/Core.kt"
[ "$(fp "$R")" != "$HEAD1" ] && ok "other tracked file edited: fingerprint moves" || bad "an edit of src/Core.kt did not move the fingerprint"
printf '{"hooks":{"local":"again"}}\n' > "$R/.claude/settings.json"
F3="$(fp "$R")"
git -C "$R" checkout -q -- src/Core.kt
[ "$F3" != "$HEAD1" ] && [ "$(fp "$R")" = "$HEAD1" ] && ok "settings.json dirty + other file edited: moves; reverted: back to HEAD's" || bad "mixed edit case wrong"
git -C "$R" checkout -q -- .claude/settings.json

# 4. HEAD không có settings.json: file mới chưa track cũng bị bỏ qua
R2="$TMP/repo2"
mkdir -p "$R2/src"
newrepo "$R2"
printf 'fun ok() = 1\n' > "$R2/src/Core.kt"
git -C "$R2" add -A && git -C "$R2" commit -qm init
H2="$(cfp "$R2")"
mkdir -p "$R2/.claude" && printf '{"hooks":{}}\n' > "$R2/.claude/settings.json"
[ "$(fp "$R2")" = "$H2" ] && ok "HEAD without settings.json, untracked one added: fingerprint = HEAD's" || bad "untracked settings.json moved the fingerprint"

# 5. project_dir nằm dưới gốc repo: đường dẫn tính theo project_dir, như EXCLUDE
R3="$TMP/repo3"
mkdir -p "$R3/app/.claude" "$R3/app/src"
newrepo "$R3"
printf 'x\n' > "$R3/app/src/a.kt"; printf '{}\n' > "$R3/app/.claude/settings.json"
git -C "$R3" add -A && git -C "$R3" commit -qm init
H3="$(cfp "$R3/app")"
printf '{"local":1}\n' > "$R3/app/.claude/settings.json"
[ "$(fp "$R3/app")" = "$H3" ] && ok "sub-folder project: uncommitted app/.claude/settings.json edit ignored" || bad "sub-folder project: settings.json edit moved the fingerprint"
printf 'y\n' > "$R3/app/src/a.kt"
[ "$(fp "$R3/app")" != "$H3" ] && ok "sub-folder project: other edit moves" || bad "sub-folder project: other edit did not move"

# 6-10 (r5, finding 2 của T0156). tfp <dir>: in "fp|lỗi" của tree_fingerprint; shim <lệnh-con>: PATH có `git` giả trả 128 cho đúng lệnh con đó.
tfp() { python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import tree_fp; f = tree_fp.tree_fingerprint(sys.argv[2]); print(f + "|" + (tree_fp.tree_fingerprint.error or ""))' "$(dirname "$TFP")" "$1"; }
REALGIT="$(command -v git)"; SHIM="$TMP/shim"; mkdir -p "$SHIM"
shim() { printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = "%s" ] && exit 128; done\nexec "%s" "$@"\n' "$1" "$REALGIT" > "$SHIM/git"; chmod +x "$SHIM/git"; }

R4="$TMP/repo4"; mkdir -p "$R4/src" "$R4/.claude"; newrepo "$R4"
printf 'fun ok() = 1\n' > "$R4/src/Core.kt"; printf '{"hooks":{}}\n' > "$R4/.claude/settings.json"
git -C "$R4" add -A && git -C "$R4" commit -qm init
shim nosuchsub; OUT="$(PATH="$SHIM:$PATH" tfp "$R4")"
[ -n "${OUT%%|*}" ] && ok "đối chứng: shim không chặn lệnh nào thì tree_fingerprint ra giá trị" || bad "shim trung tính mà fingerprint rỗng: $OUT"
shim ls-tree; OUT="$(PATH="$SHIM:$PATH" tfp "$R4")"
[ -z "${OUT%%|*}" ] && [ -n "${OUT#*|}" ] && ok "6 ls-tree lỗi: fail-closed (fp rỗng, có lý do)" || bad "6 ls-tree lỗi mà fingerprint không rỗng hoặc không có lý do: $OUT"
shim update-index; OUT="$(PATH="$SHIM:$PATH" tfp "$R4")"
[ -z "${OUT%%|*}" ] && [ -n "${OUT#*|}" ] && ok "7 update-index lỗi: fail-closed (fp rỗng, có lý do)" || bad "7 update-index lỗi mà fingerprint không rỗng hoặc không có lý do: $OUT"
rm -f "$SHIM/git"

# 8. HEAD không có settings.json, trên đĩa là THƯ MỤC .claude/settings.json/ có file con: fp bằng của HEAD (rm phải có -r)
R5="$TMP/repo5"; mkdir -p "$R5/src"; newrepo "$R5"
printf 'fun ok() = 1\n' > "$R5/src/Core.kt"; git -C "$R5" add -A && git -C "$R5" commit -qm init
H5="$(cfp "$R5")"; mkdir -p "$R5/.claude/settings.json" && printf 'x\n' > "$R5/.claude/settings.json/foo"
[ "$(fp "$R5")" = "$H5" ] && ok "8 thư mục .claude/settings.json/ chưa track (HEAD không có file): fingerprint = HEAD's" || bad "8 thư mục trùng tên làm lệch fingerprint (rm --cached thiếu -r?)"
rm -rf "$R5/.claude/settings.json"

# 9. file .claude/settings.json chưa track CỠ LỚN (TREE_FP_BIG_MB): không vào chữ ký file lớn, fp bằng của HEAD
mkdir -p "$R5/.claude"; head -c 400 /dev/zero | tr '\0' 'a' > "$R5/.claude/settings.json"
[ "$(TREE_FP_BIG_MB=0.00002 fp "$R5")" = "$H5" ] && ok "9 settings.json chưa track cỡ lớn: fingerprint = HEAD's" || bad "9 file lớn của path ghim làm lệch fingerprint (_big_untracked)"
rm -f "$R5/.claude/settings.json"

# 10. HEAD có .claude/settings.json là THƯ MỤC (mode 040000): không ghim được bằng blob, fail-closed
R6="$TMP/repo6"; mkdir -p "$R6/.claude/settings.json" "$R6/src"; newrepo "$R6"
printf 'x\n' > "$R6/.claude/settings.json/a"; printf 'fun ok() = 1\n' > "$R6/src/Core.kt"; git -C "$R6" add -A && git -C "$R6" commit -qm init
OUT="$(tfp "$R6")"; [ -z "${OUT%%|*}" ] && [ -n "${OUT#*|}" ] && ok "10 HEAD có settings.json là thư mục: fail-closed" || bad "10 HEAD có thư mục trùng tên mà fingerprint không fail-closed: $OUT"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
