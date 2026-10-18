#!/usr/bin/env bash
# super-board-post-merge-clean.sh <repo-path> <merged-head-ref> [<merged-sha>]
# Dọn sau merge, do super-board-merge-gate.sh gọi sau squash merge: xoá worktree của CHÍNH thẻ vừa merge
# (của Builder trên <merged-head-ref>, của Tester issue-<N>-qa) và nhánh local của nó, để không ai phải dọn tay.
# issue-<N>-review của Reviewer được giữ: Reviewer là người chạy gate này, còn các bước sau merge phải làm ở đó
# (run.md) rồi tự xoá; worktree đang chứa cwd của lệnh này cũng được giữ.
# Không bao giờ đụng thẻ khác: ngày 2026-10-16 bản đầu khớp mọi issue-*-qa / issue-*-review và xoá --force
# thư mục mà worker của thẻ khác đang dùng. Không mất gì ngoài phần đã merge: worktree còn sửa dở được giữ,
# nhánh chỉ bị xoá khi đầu nhánh vẫn đúng <merged-sha>.
# Làm hết sức có thể: không bao giờ làm hỏng lần merge đã xảy ra.
set -u
HEAD_REF="${2:?merged head ref}"; MERGED_SHA="${3:-}"
# repo.path là "." trong mọi config board và gate có thể chạy từ một worktree: quy về main checkout.
REPO_PATH=$(git -C "${1:?repo path}" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
[ -n "$REPO_PATH" ] || exit 0
N=$(printf '%s' "$HEAD_REF" | sed -nE 's#^issue-([0-9]+)-.*#\1#p')
HERE_PWD=$(pwd -P)
# 18/10 (NFH PR #38, #45, Geely PR #59): phiên rời worktree của PR bằng ExitWorktree "keep" (khoá devkit-kept) rồi tự chạy merge gate;
# `git worktree remove` trần từ chối worktree bị khoá và phiên phải unlock tay. Có DevKit thì gỡ bằng `worktree.py remove`: nó mở khoá
# devkit-kept của chính phiên gọi hoặc của pid đã chết (khoá của phiên khác còn sống thì git vẫn từ chối) và giữ luật không-mất-việc.
KIT_WT=""
for c in "$REPO_PATH/.agents/devkit" "$REPO_PATH/universal-agent-devkit" "$(cd "$(dirname "$0")/../.." && pwd)/universal-agent-devkit"; do
  if [ -f "$c/scripts/git/worktree.py" ]; then KIT_WT="$c/scripts/git/worktree.py"; break; fi
done
remove_wt() {
  local out
  if [ -n "$KIT_WT" ]; then
    out=$(cd "$REPO_PATH" && python3 "$KIT_WT" remove "$1" 2>&1) \
      || echo "kept $1: agent-kit worktree remove refused: $(printf '%s' "$out" | tail -1 | cut -c1-300)" >&2
  else
    git -C "$REPO_PATH" worktree remove "$1" 2>/dev/null || echo "kept $1: git worktree remove failed" >&2
  fi
}
CANDS=()
if [ -n "$N" ]; then
  for wt in "$REPO_PATH/.claude/worktrees"/issue-"$N"-*; do CANDS+=("$wt"); done
else
  # Nhánh PR thường (không phải của thẻ): chỉ worktree đang ở ĐÚNG nhánh vừa merge (của phiên đã mở PR), không bao giờ main checkout
  cur=""
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) cur="${line#worktree }" ;;
      "branch refs/heads/$HEAD_REF") [ -n "$cur" ] && [ "$cur" != "$REPO_PATH" ] && CANDS+=("$cur") ;;
    esac
  done < <(git -C "$REPO_PATH" worktree list --porcelain 2>/dev/null)
fi
for wt in ${CANDS[@]+"${CANDS[@]}"}; do
  [ -d "$wt" ] || continue
  case "$HERE_PWD/" in "$(cd "$wt" && pwd -P)"/*) continue ;; esac
  case "${wt##*/}" in
    "issue-$N-review") continue ;;
    "issue-$N-qa") ;;
    *) [ "$(git -C "$wt" symbolic-ref --quiet --short HEAD 2>/dev/null)" = "$HEAD_REF" ] || continue ;;
  esac
  if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
    echo "kept $wt: uncommitted edits" >&2
    continue
  fi
  # Commit trên HEAD detached mà không nhánh/remote nào chứa (vd repro Tester chưa push) sẽ chỉ còn trong reflog.
  head=$(git -C "$wt" rev-parse --verify -q HEAD 2>/dev/null || true)
  if [ -z "$head" ] || [ -z "$(git -C "$REPO_PATH" for-each-ref --count=1 --contains "$head" refs/heads refs/remotes 2>/dev/null)" ]; then
    echo "kept $wt: HEAD ${head:-<unknown>} is on no branch or remote" >&2
    continue
  fi
  remove_wt "$wt"
done
tip=$(git -C "$REPO_PATH" rev-parse --verify -q "refs/heads/$HEAD_REF" 2>/dev/null || true)
if [ -n "$tip" ] && [ -n "$MERGED_SHA" ] && [ "$tip" = "$MERGED_SHA" ]; then
  git -C "$REPO_PATH" branch -D "$HEAD_REF" >/dev/null 2>&1 || echo "kept branch $HEAD_REF: still checked out" >&2
elif [ -n "$tip" ]; then
  echo "kept branch $HEAD_REF: its tip ${tip} is not the merged ${MERGED_SHA:-<unknown>}" >&2
fi
exit 0
