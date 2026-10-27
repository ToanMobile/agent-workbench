#!/usr/bin/env bash
# `worktree.py gc` (gc thường, không --merged) khi `.claude/worktrees` hay `.claude` của main là symlink (#427 vòng 2): os.listdir đi xuyên
# link nên thư mục ở ĐÍCH của link (của người khác, của repo khác) bị coi là worktree mồ côi của checkout này; thư mục không có .git mà mọi
# file trùng main thì bị rmtree. `gc --merged` đã không gỡ gì khi đó (review U2 P3, 26/10); gc thường phải làm y như vậy.
#   WTG_KIT=<devkit dir>   chạy bản kit khác (bản chưa sửa: RED).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WT="${WTG_KIT:-$DEVKIT_DIR}/scripts/git/worktree.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
export WORKTREE_GC_MIN_AGE_S=0

# mkrepo <dir>: repo có một file app.txt đã commit
mkrepo() { mkdir -p "$1" && G "$1" init -q -b main . && echo base > "$1/app.txt" && G "$1" add -A && G "$1" commit -qm base; }
# victim <dir>: thư mục không .git, chỉ chứa bản sao đúng byte của app.txt (gc coi là "không có gì riêng")
victim() { mkdir -p "$1" && echo base > "$1/app.txt"; }

# 1. .claude/worktrees là symlink sang thư mục khác: thư mục ở đích không bị xoá
R="$TMP/r1"; mkrepo "$R"; victim "$TMP/elsewhere1/victim"
mkdir -p "$R/.claude" && ln -s "$TMP/elsewhere1" "$R/.claude/worktrees"
(cd "$R" && python3 "$WT" gc > "$TMP/gc1.out" 2>&1)
[ -e "$TMP/elsewhere1/victim/app.txt" ] && ok "gc: .claude/worktrees is a symlink, the folder at its target is left alone" \
  || fail "gc deleted a folder through a symlinked .claude/worktrees: $(head -c 300 "$TMP/gc1.out")"

# 2. .claude là symlink: như trên
R="$TMP/r2"; mkrepo "$R"; victim "$TMP/elsewhere2/worktrees/victim"
ln -s "$TMP/elsewhere2" "$R/.claude"
(cd "$R" && python3 "$WT" gc > "$TMP/gc2.out" 2>&1)
[ -e "$TMP/elsewhere2/worktrees/victim/app.txt" ] && ok "gc: .claude is a symlink, the folder at its target is left alone" \
  || fail "gc deleted a folder through a symlinked .claude: $(head -c 300 "$TMP/gc2.out")"

# 3. đối chứng (#327): .claude/worktrees là thư mục thật, cùng thư mục mồ côi đó: vẫn bị xoá
R="$TMP/r3"; mkrepo "$R"; victim "$R/.claude/worktrees/orphan"
(cd "$R" && python3 "$WT" gc > "$TMP/gc3.out" 2>&1)
[ ! -e "$R/.claude/worktrees/orphan" ] && ok "control: a real .claude/worktrees orphan with nothing unique is still deleted (#327)" \
  || fail "control orphan kept: $(head -c 300 "$TMP/gc3.out")"

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_gc_symlink_home: all passed" || { echo "❌ test_worktree_gc_symlink_home: $FAILS failed"; exit 1; }
