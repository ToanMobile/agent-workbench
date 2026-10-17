#!/usr/bin/env bash
# Hồi quy (17/10, người dùng: "tự xoá worktree, branch cũ hoàn toàn tự động"): `agent-kit worktree remove` (cũng là bước cuối của
# `worktree finish`) gỡ worktree nhưng để lại branch của nó với lời nhắc "git branch -d" cho người dùng, nên khi chạy nhiều task
# song song (worktree do app tạo đều có branch riêng) branch cũ ứ lại và người dùng phải xoá tay.
#   - branch đã gộp hết vào main và chưa publish: bị xoá cùng worktree
#   - branch còn commit chưa có trong main: giữ (không mất commit nào)
#   - branch đã publish (có upstream): giữ (remote là của người dùng)
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

R="$TMP/rb"; mkdir -p "$R" && G "$R" init -q -b main . && cd "$R" || exit 1
echo base > "$R/a.txt"; G "$R" add -A && G "$R" commit -qm init
has_branch() { G "$R" show-ref --verify --quiet "refs/heads/$1"; }

# 1. branch đã gộp vào main (fast-forward), chưa publish: gỡ worktree thì branch cũng đi
bash "$KIT" worktree add ../rb-x feat/x >/dev/null 2>&1 || fail "add rb-x"
echo x > "$TMP/rb-x/x.txt"; G "$TMP/rb-x" add -A && G "$TMP/rb-x" commit -qm x
G "$R" merge -q --ff-only feat/x
bash "$KIT" worktree remove ../rb-x >"$TMP/x.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/rb-x" ] && ! has_branch feat/x \
  && ok "merged, unpublished branch is deleted with its worktree" \
  || { fail "merged branch left behind (rc=$rc, branch $(has_branch feat/x && echo kept || echo gone))"; cat "$TMP/x.out"; }

# 2. branch có commit main chưa có: worktree gỡ được (branch giữ commit) nhưng branch phải còn
bash "$KIT" worktree add ../rb-y feat/y >/dev/null 2>&1 || fail "add rb-y"
echo y > "$TMP/rb-y/y.txt"; G "$TMP/rb-y" add -A && G "$TMP/rb-y" commit -qm y
bash "$KIT" worktree remove ../rb-y >"$TMP/y.out" 2>&1; rc=$?
has_branch feat/y && ok "branch with commits not in main is kept (rc=$rc)" \
  || { fail "unmerged branch was deleted: its commit is lost"; cat "$TMP/y.out"; }

# 3. branch đã gộp nhưng đã publish (có upstream): giữ
bash "$KIT" worktree add ../rb-z feat/z >/dev/null 2>&1 || fail "add rb-z"
echo z > "$TMP/rb-z/z.txt"; G "$TMP/rb-z" add -A && G "$TMP/rb-z" commit -qm z
G "$R" merge -q --ff-only feat/z
G "$R" config branch.feat/z.remote origin; G "$R" config branch.feat/z.merge refs/heads/feat/z
bash "$KIT" worktree remove ../rb-z >"$TMP/z.out" 2>&1; rc=$?
[ "$rc" = 0 ] && has_branch feat/z && ok "merged but published branch is kept" \
  || { fail "published branch deleted or remove failed (rc=$rc)"; cat "$TMP/z.out"; }

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_remove_branch: all passed" || { echo "❌ test_worktree_remove_branch: $FAILS failed"; exit 1; }
