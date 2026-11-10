#!/usr/bin/env bash
# Sàn đĩa có tỉa cache: dưới WORKTREE_CACHE_PRUNE_GIB (mặc định 25) `worktree add` xoá cache build dựng lại được của máy
# (~/.gradle/caches/build-cache-1, ~/.npm/_cacache, ~/Library/Caches/go-build); ~/.cache/uv giữ (MCP `uvx` đang chạy từ đó) trước khi tạo worktree; vẫn dưới
# WORKTREE_DISK_MIN_GIB thì exit 4. Mặc định mới: cảnh báo 25 GiB, sàn 15 GiB. HOME giả: không bao giờ đụng cache thật của máy.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WT="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
mkdir -p "$TMP/r" && G "$TMP/r" init -q -b main . && echo base > "$TMP/r/a.txt" && G "$TMP/r" add -A && G "$TMP/r" commit -qm base
H="$TMP/home"
caches() {
  mkdir -p "$H/.gradle/caches/build-cache-1" "$H/.gradle/caches/modules-2" "$H/.npm/_cacache" "$H/Library/Caches/go-build" "$H/.cache/uv"
  for d in .gradle/caches/build-cache-1 .gradle/caches/modules-2 .npm/_cacache Library/Caches/go-build .cache/uv; do echo x > "$H/$d/blob"; done
}
run() { (cd "$TMP/r" && env HOME="$H" PATH="/usr/bin:/bin" WORKTREE_DISK_WARN_GIB=0 "$@" python3 "$WT" add "$TMP/$N" --no-init > "$TMP/out" 2>&1); }

# 1 dưới ngưỡng tỉa: 3 cache dựng lại được bị xoá, modules-2 (dependency đã tải) và uv giữ, worktree vẫn tạo
caches; N=wt1
run WORKTREE_CACHE_PRUNE_GIB=100000 WORKTREE_DISK_MIN_GIB=0; rc=$?
gone=0; for d in .gradle/caches/build-cache-1 .npm/_cacache Library/Caches/go-build; do [ -e "$H/$d" ] || gone=$((gone + 1)); done
if [ "$rc" = 0 ] && [ "$gone" = 3 ] && [ -f "$H/.gradle/caches/modules-2/blob" ] && [ -f "$H/.cache/uv/blob" ] && [ -d "$TMP/wt1" ] && grep -q "build-cache-1" "$TMP/out"; then
  ok "dưới ngưỡng tỉa: 3 cache build đã xoá, modules-2 và uv giữ, worktree tạo, có báo"
else
  fail "tỉa cache: rc=$rc gone=$gone/3: $(cat "$TMP/out")"
fi
# 2 trên ngưỡng tỉa (0 = tắt): không xoá gì
rm -rf "$H"; caches; N=wt2
run WORKTREE_CACHE_PRUNE_GIB=0 WORKTREE_DISK_MIN_GIB=0; rc=$?
[ "$rc" = 0 ] && [ -f "$H/.gradle/caches/build-cache-1/blob" ] && [ -f "$H/.npm/_cacache/blob" ] \
  && ok "WORKTREE_CACHE_PRUNE_GIB=0: không tỉa cache" || fail "tắt tỉa vẫn xoá: rc=$rc $(cat "$TMP/out")"
# 3 tỉa xong vẫn dưới sàn: exit 4, không tạo worktree
rm -rf "$H"; caches; N=wt3
run WORKTREE_CACHE_PRUNE_GIB=100000 WORKTREE_DISK_MIN_GIB=100000; rc=$?
[ "$rc" = 4 ] && [ ! -e "$TMP/wt3" ] && [ ! -e "$H/.gradle/caches/build-cache-1" ] \
  && ok "tỉa rồi vẫn dưới sàn: exit 4, không tạo worktree" || fail "sàn sau tỉa: rc=$rc $(cat "$TMP/out")"
# 4 mặc định mới theo yêu cầu: cảnh báo/tỉa 25 GiB, sàn 15 GiB
d=$(env -u WORKTREE_DISK_WARN_GIB -u WORKTREE_DISK_MIN_GIB -u WORKTREE_CACHE_PRUNE_GIB python3 -c "
import importlib.util,sys; s=importlib.util.spec_from_file_location('w',sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(m.DISK_WARN_GIB, m.DISK_MIN_GIB, m.CACHE_PRUNE_GIB)" "$WT" 2>&1)
[ "$d" = "25.0 15.0 25.0" ] && ok "mặc định: cảnh báo 25, sàn 15, tỉa 25 GiB" || fail "mặc định: $d"
[ "$FAILS" = 0 ]
