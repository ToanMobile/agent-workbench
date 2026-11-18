#!/usr/bin/env bash
# #1302: sau exit 10 của super-board-qa-head.sh, đưa nhánh PR cục bộ lên <sha> mới để lượt QA K+1 ff được bằng chứng.
# Đóng gói để worker QA không phải gõ lệnh git ghi đè nhánh (hook block-dangerous-git.sh chặn chúng, exit 2).
# Dùng: super-board-qa-sync.sh --branch B --sha S [--worktree W]   (W = worktree đang giữ nhánh B; bỏ cờ nếu không worktree nào giữ)
#   0  synced <sha>    nhánh cục bộ đã ở <sha> (ff, hoặc hủy đúng commit bằng chứng QA chưa push)
#   11 blocked ...     từ chối, nêu lý do: worktree bẩn, nhánh mang thay đổi ngoài docs/super-board/runs/, sha lạ, thiếu cờ
set -u
branch=""; sha=""; wt=""
while [ $# -gt 0 ]; do
  case "$1" in
    --branch|--sha|--worktree) [ $# -ge 2 ] || { echo "blocked: cờ $1 thiếu giá trị"; exit 11; } ;;
  esac
  case "$1" in
    --branch) branch="$2"; shift 2 ;;
    --sha) sha="$2"; shift 2 ;;
    --worktree) wt="$2"; shift 2 ;;
    *) echo "blocked: đối số lạ $1"; exit 11 ;;
  esac
done
[ -n "$branch" ] && [ -n "$sha" ] || { echo "blocked: thiếu --branch hoặc --sha"; exit 11; }
remote="${SB_QA_HEAD_REMOTE:-origin}"
if [ -n "$wt" ]; then g() { git -C "$wt" "$@"; }; else g() { git "$@"; }; fi

ferr="$(g fetch -q "$remote" "refs/heads/$branch" 2>&1)" || { echo "blocked: git fetch $remote lỗi: $ferr"; exit 11; }
full="$(g rev-parse --verify -q "$sha^{commit}")" || { echo "blocked: sha $sha không phải commit sau fetch"; exit 11; }
local_head="$(g rev-parse --verify -q "refs/heads/$branch")" || { echo "blocked: không có nhánh cục bộ $branch"; exit 11; }
if [ -n "$wt" ]; then
  cur="$(g symbolic-ref -q --short HEAD)" || cur=""
  [ "$cur" = "$branch" ] || { echo "blocked: worktree $wt đang ở '${cur:-detached}', không phải $branch"; exit 11; }
  [ -z "$(g status --porcelain)" ] || { echo "blocked: worktree $wt có thay đổi chưa commit"; exit 11; }
fi
if [ "$local_head" = "$full" ]; then echo "synced $full"; exit 0; fi

if [ -n "$wt" ] && g merge --ff-only "$full" >/dev/null 2>&1; then echo "synced $full (ff)"; exit 0; fi
if [ -z "$wt" ] && g merge-base --is-ancestor "$local_head" "$full"; then
  g branch -f "$branch" "$full" >/dev/null 2>&1 || { echo "blocked: không đặt được $branch về $full"; exit 11; }
  echo "synced $full (ff)"; exit 0
fi

# Phân kỳ: chỉ hủy được khi nhánh cục bộ khác <sha> đúng ở bằng chứng QA (docs/super-board/runs/).
extra="$(g diff --name-only "$full...$local_head" | grep -v '^docs/super-board/runs/' || true)"
[ -z "$extra" ] || { echo "blocked: nhánh $branch mang thay đổi ngoài docs/super-board/runs/ ($(echo "$extra" | head -3 | tr '\n' ' ')); không hủy"; exit 11; }
if [ -n "$wt" ]; then
  g reset -q --hard "$full" || { echo "blocked: đặt lại $branch về $full lỗi"; exit 11; }
else
  g branch -f "$branch" "$full" >/dev/null 2>&1 || { echo "blocked: không đặt được $branch về $full"; exit 11; }
fi
echo "synced $full (hủy commit bằng chứng QA chưa push)"; exit 0
