#!/usr/bin/env bash
# #453: `worktree prune-branch` nhận nhánh lane đã squash khi tip của nó nằm trọn trong headRefOid của một PR đã MERGED vào trunk (PR đó
# lấy head từ nhánh KHÁC: gom lane-A..I vào gate-batch-integrate, PR #455), không chỉ khi PR có head đúng tip. Commit nằm ngoài head đó: giữ.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
R="$TMP/r"; mkdir -p "$R" && G "$R" init -q -b main . && cd "$R" || exit 1
G "$R" config devkit.trunkMode true
echo a > a.txt; G "$R" add -A && G "$R" commit -qm init
has_branch() { G "$R" show-ref --verify --quiet "refs/heads/$1"; }
# lane-a (một commit) → integ = lane-a + một commit nữa: head của PR đã MERGED (trunk KHÔNG có nội dung: gh giả, không squash thật).
G "$R" checkout -q -b lane-a; echo 1 > l1.txt; G "$R" add l1.txt; G "$R" commit -qm l1
G "$R" checkout -q -b integ; echo 2 > l2.txt; G "$R" add l2.txt; G "$R" commit -qm l2
G "$R" checkout -q -b lane-x lane-a; echo 3 > l3.txt; G "$R" add l3.txt; G "$R" commit -qm l3-only-on-lane-x
G "$R" checkout -q main
INTEG=$(G "$R" rev-parse integ)
FAKE="$TMP/fakegh"; mkdir -p "$FAKE"
printf '#!/bin/sh\necho %s\n' "'[{\"number\":455,\"headRefOid\":\"$INTEG\",\"baseRefName\":\"main\",\"isCrossRepository\":false}]'" > "$FAKE/gh"; chmod +x "$FAKE/gh"
PATH="$FAKE:$PATH" bash "$KIT" worktree prune-branch lane-a >"$TMP/o1" 2>&1; rc=$?
[ "$rc" = 0 ] && ! has_branch lane-a && ok "a branch whose tip is inside the head of a MERGED PR (another branch) is deleted" || { fail "ancestor of merged PR head kept (rc=$rc)"; cat "$TMP/o1"; }
PATH="$FAKE:$PATH" bash "$KIT" worktree prune-branch lane-x >"$TMP/o2" 2>&1; rc=$?
[ "$rc" != 0 ] && has_branch lane-x && ok "a branch with a commit outside the merged PR head is kept (rc=$rc)" || { fail "lane-x deleted (rc=$rc)"; cat "$TMP/o2"; }
printf '#!/bin/sh\necho %s\n' "'[{\"number\":456,\"headRefOid\":\"$INTEG\",\"baseRefName\":\"feat/parent\",\"isCrossRepository\":false}]'" > "$FAKE/gh"
G "$R" branch lane-b "$(G "$R" rev-parse integ~1)"
PATH="$FAKE:$PATH" bash "$KIT" worktree prune-branch lane-b >"$TMP/o3" 2>&1; rc=$?
[ "$rc" != 0 ] && has_branch lane-b && ok "a PR merged into another branch than the trunk does not count (rc=$rc)" || { fail "lane-b deleted (rc=$rc)"; cat "$TMP/o3"; }
[ "$FAILS" = 0 ]
