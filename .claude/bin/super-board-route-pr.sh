#!/usr/bin/env bash
# super-board-route-pr.sh — đưa một PR mở ngoài board vào lane QA của thẻ nó (#1192).
#
# Vì sao: PR mở bằng `gh pr create` từ phiên thường không có thẻ nào ở board, nên không lane nào duyệt nó, mà phiên tác giả bị cấm
# tự duyệt (#605) — agent lại đẩy việc gõ approved-head cho chủ repo. Script này đặt thẻ của PR vào QA; lane QA/Review và merge gate
# làm phần còn lại. Hook route_pr_to_board.py gọi nó sau mỗi `gh pr create` thành công; chạy tay cũng được. Chạy lại không ghi thêm.
#
# Usage: super-board-route-pr.sh <pr> [--config <cfg.json>]
#   Không --config: lấy .claude/super-board/configs/*.json của repo hiện tại (cái có repo.remote khớp origin, hoặc cái duy nhất).
#   Thẻ N = số từ nhánh `issue-<N>-…`, không có thì `Closes|Fixes|Resolves #N` trong body PR.
#   Cột trống/Backlog/Ready/Building → QA; QA/Review/Blocked/Done → giữ. Body thiếu `Closes #N` → thêm.
#
# Exit: 0 xong (kể cả: repo không board, PR draft/đã đóng) · 4 không tìm ra số thẻ · 64 usage · khác: mã lỗi của gh / super-board-card.sh
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CARD="$HERE/super-board-card.sh"
PR=""; CONFIG="${SB_CONFIG:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --config) CONFIG="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *) [ -z "$PR" ] || { echo "usage: super-board-route-pr.sh <pr> [--config <cfg.json>]" >&2; exit 64; }; PR="$1"; shift ;;
  esac
done
PR="${PR#\#}"; PR="${PR##*/pull/}"
case "$PR" in ''|*[!0-9]*) echo "usage: super-board-route-pr.sh <pr-number|pr-url> [--config <cfg.json>]" >&2; exit 64 ;; esac

norm_repo() { sed -E 's#^(https?://github\.com/|git@github\.com:)##; s#\.git$##; s#/+$##'; }

if [ -z "$CONFIG" ]; then
  top=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  origin=$(git remote get-url origin 2>/dev/null | norm_repo || true)
  n=0; only=""
  for f in "$top"/.claude/super-board/configs/*.json; do
    [ -f "$f" ] || continue
    n=$((n + 1)); only="$f"
    r=$(jq -r '.repo.remote // ""' "$f" 2>/dev/null | norm_repo)
    if [ -n "$origin" ] && [ "$r" = "$origin" ]; then CONFIG="$f"; break; fi
  done
  [ -n "$CONFIG" ] || { [ "$n" = 1 ] && CONFIG="$only"; }
  if [ -z "$CONFIG" ]; then
    [ "$n" = 0 ] && { echo "route-pr: no super-board config here: nothing to route"; exit 0; }
    echo "route-pr: $n super-board configs and none matches origin: pass --config" >&2; exit 64
  fi
fi
[ -r "$CONFIG" ] || { echo "route-pr: config not found: $CONFIG" >&2; exit 66; }
OWNER=$(jq -r '.project.owner // ""' "$CONFIG"); NUMBER=$(jq -r '.project.number // ""' "$CONFIG")
REPO=$(jq -r '.repo.remote // ""' "$CONFIG" | norm_repo)
[ -n "$OWNER" ] && [ -n "$NUMBER" ] && [ -n "$REPO" ] || { echo "route-pr: $CONFIG lacks project.owner/number or repo.remote" >&2; exit 66; }

rc=0
PRJ=$(gh pr view "$PR" --repo "$REPO" --json number,isDraft,headRefName,body,title,state,url) || rc=$?
[ "$rc" = 0 ] || { echo "route-pr: could not read PR #$PR of $REPO (gh exit $rc)" >&2; exit "$rc"; }
STATE=$(echo "$PRJ" | jq -r '.state // ""'); DRAFT=$(echo "$PRJ" | jq -r '.isDraft // false')
if [ "$STATE" != OPEN ]; then echo "route-pr: PR #$PR is $STATE: nothing to route"; exit 0; fi
if [ "$DRAFT" = true ]; then echo "route-pr: PR #$PR is a draft: the build lane owns it"; exit 0; fi
HEAD=$(echo "$PRJ" | jq -r '.headRefName // ""'); BODY=$(echo "$PRJ" | jq -r '.body // ""')
CLOSES_RX='(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]]+#([0-9]+)'
N=$(printf '%s\n' "$HEAD" | sed -nE 's/^issue-([0-9]+)-.*/\1/p')
[ -n "$N" ] || N=$(printf '%s\n' "$BODY" | grep -oiE "$CLOSES_RX" | head -1 | grep -oE '[0-9]+$')
if [ -z "$N" ]; then
  echo "route-pr: PR #$PR (branch $HEAD) names no card. Create an issue without the qa label (gh issue create --label bug|feature)," >&2
  echo "  add 'Closes #<N>' to the PR body, then run: .claude/bin/super-board-route-pr.sh $PR" >&2
  exit 4
fi

rc=0
COL=$(bash "$CARD" --config "$CONFIG" status "$N") || rc=$?
if [ "$rc" = 3 ]; then
  rc=0
  gh project item-add "$NUMBER" --owner "$OWNER" --url "https://github.com/$REPO/issues/$N" >/dev/null || rc=$?
  [ "$rc" = 0 ] || { echo "route-pr: could not add #$N to project $OWNER/$NUMBER (gh exit $rc)" >&2; exit "$rc"; }
  COL=""
elif [ "$rc" != 0 ]; then
  echo "route-pr: could not read the card of #$N for PR #$PR (super-board-card.sh exit $rc)" >&2; exit "$rc"
fi

case "$COL" in
  ""|Backlog|Ready|Building)
    rc=0; bash "$CARD" --config "$CONFIG" move "$N" QA >/dev/null || rc=$?
    [ "$rc" = 0 ] || { echo "route-pr: could not move #$N to QA (super-board-card.sh exit $rc)" >&2; exit "$rc"; }
    RESULT="${COL:-no column} → QA" ;;
  *) RESULT="kept in $COL" ;;
esac

if ! printf '%s\n' "$BODY" | grep -qiE "(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]]+#$N([^0-9]|\$)"; then
  tmp=$(mktemp "${TMPDIR:-/tmp}/sb-route-pr.XXXXXX")
  printf '%s\n\nCloses #%s\n' "$BODY" "$N" > "$tmp"
  rc=0; gh pr edit "$PR" --repo "$REPO" --body-file "$tmp" >/dev/null || rc=$?
  rm -f "$tmp"
  [ "$rc" = 0 ] || { echo "route-pr: card moved, but could not add 'Closes #$N' to PR #$PR (gh exit $rc)" >&2; exit "$rc"; }
  RESULT="$RESULT, Closes #$N added"
fi
echo "route-pr: PR #$PR → card #$N: $RESULT"
