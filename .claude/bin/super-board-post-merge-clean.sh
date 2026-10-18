#!/usr/bin/env bash
# super-board-post-merge-clean.sh <repo-path> <merged-head-ref> [<merged-sha>]
# Dọn sau merge, do super-board-merge-gate.sh gọi sau squash merge: xoá worktree của CHÍNH thẻ vừa merge
# (của Builder trên <merged-head-ref>, của Tester issue-<N>-qa) và nhánh local của nó, để không ai phải dọn tay.
# issue-<N>-review của Reviewer được giữ: Reviewer là người chạy gate này, còn các bước sau merge phải làm ở đó
# (run.md) rồi tự xoá; worktree đang chứa cwd của lệnh này cũng được giữ.
# Không bao giờ đụng thẻ khác: ngày 2026-10-16 bản đầu khớp mọi issue-*-qa / issue-*-review và xoá --force
# thư mục mà worker của thẻ khác đang dùng. Không mất gì ngoài phần đã merge: worktree còn sửa dở được giữ,
# nhánh chỉ bị xoá khi đầu nhánh vẫn đúng <merged-sha> (đường DevKit: luật của kit, xem remove_wt bên dưới).
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
# Nó cũng xoá nhánh của worktree theo luật của kit, KHÔNG theo chốt MERGED_SHA dưới: nội dung đã trong trunk hoặc origin/<trunk> (tổ
# tiên, hay gộp thử ra đúng cây của trunk) và không còn ref remote; mọi commit chỉ nhánh giữ được cất vào refs/devkit/discarded 30 ngày.
# Không có python3: đường git như cũ (OCR 18/10).
KIT_WT=""
# Kit đi cùng script trước (đã review cùng nó), bản của repo sau — như sync_identical của merge gate.
HERE_UP=$(cd "$(dirname "$0")/../.." && pwd)
command -v python3 >/dev/null 2>&1 && for c in "$HERE_UP/universal-agent-devkit" "$HERE_UP/.agents/devkit" "$REPO_PATH/universal-agent-devkit" "$REPO_PATH/.agents/devkit"; do
  # thử chạy một lần (`list` chỉ đọc): kit có mà không chạy được (cú pháp, python quá cũ) thì đường git như cũ, không giữ mọi thứ lại
  if [ -f "$c/scripts/git/worktree.py" ] && (cd "$REPO_PATH" && python3 "$c/scripts/git/worktree.py" list >/dev/null 2>&1); then
    KIT_WT="$c/scripts/git/worktree.py"; break
  fi
done
remove_wt() {
  local out rc=2
  if [ -n "$KIT_WT" ]; then
    # thành công: in lại lời kit (nhánh đã xoá, commit cất ở refs/devkit/discarded 30 ngày, ⚠ memory note đi theo worktree) — OCR 18/10
    out=$(cd "$REPO_PATH" && python3 "$KIT_WT" remove "$1" 2>&1) && { printf '%s\n' "$out" >&2; return 0; }
    rc=$?
    # 1 kèm dòng ✖ = có việc sẽ mất (sửa dở, commit chỉ reflog giữ, bí mật bị ignore…): giữ, git trần không thấy hết những thứ đó.
    # Khác (2: dùng sai / state không đọc được; kit chết giữa chừng, traceback cũng exit 1): đường git như cũ — git vẫn từ chối worktree
    # bẩn hay bị khoá (OCR 18/10).
    if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q '✖'; then
      echo "kept $1: agent-kit worktree remove refused: $( { printf '%s\n' "$out" | grep -m1 '✖' || printf '%s\n' "$out" | head -1; } | cut -c1-300)" >&2
      return 0
    fi
    [ -e "$1" ] || { echo "removed $1 (agent-kit exited $rc after removing it: $(printf '%s\n' "$out" | tail -1 | cut -c1-200))" >&2; return 0; }
  fi
  git -C "$REPO_PATH" worktree remove "$1" 2>/dev/null || echo "kept $1: git worktree remove failed" >&2
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
      "branch refs/heads/$HEAD_REF")   # chỉ worktree do phiên dựng (.claude/worktrees/<tên>); worktree người tự dựng nơi khác: để yên (OCR 18/10)
        case "$cur" in "$REPO_PATH/.claude/worktrees/"*) CANDS+=("$cur") ;; esac ;;
    esac
  done < <(git -C "$REPO_PATH" worktree list --porcelain 2>/dev/null)
  # không worktree nào của phiên: nhánh local cùng tên là của người dùng, không đụng (như trước: nhánh thường chưa bao giờ bị xoá, OCR 18/10)
  [ "${#CANDS[@]}" -gt 0 ] || exit 0
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
