#!/usr/bin/env bash
# super-board-queue-label.sh [<pr>] [--repo OWNER/NAME] [--check] — gắn nhãn `merge-queue` cho PR CHỈ KHI PR có approved-head hợp lệ khớp
# head hiện tại (#536). 28/10 một phiên agent tự gắn nhãn cho PR #517/#524 chưa có approved-head; hàng đợi chỉ phát hiện lúc chạy và
# PR nằm im ~3 giờ.
#   Luật duyệt: super-board-approved-head.jq (chung với super-board-merge-queue.sh và review_approved_head của super-board-run.sh):
#   comment `approved-head:<sha40>` MỚI NHẤT của OWNER/MEMBER/COLLABORATOR; bare chỉ của OWNER; kèm `approved-by:` thì đủ trường, không
#   tự duyệt, và task_id phải có audit pass của antigravity-pm với auditedHead == head (super-board-audit-check.py).
#   <pr>: số, URL hoặc nhánh; bỏ trống = PR của nhánh đang đứng (như `gh pr view`).
#   --check: chỉ kiểm, không ghi (guard block-dangerous-git.sh gọi dạng này trước khi cho `gh pr edit … --add-label merge-queue` chạy).
# Đọc GitHub bằng `gh` trực tiếp có timeout (SB_QUEUE_LABEL_GH_TIMEOUT, mặc định 6 s; audit-check cũng 6 s), KHÔNG qua
# super-board-github-read.py: đọc hỏng ở đó ghi file halt dùng chung và dừng cả board, còn helper này chạy trong guard của mọi phiên
# (guard cho cả helper tối đa 8 s, dưới timeout 10 s của hook ở Codex/Gemini/Cursor).
# Exit: 0 đủ điều kiện (không --check: đã gắn nhãn) · 3 từ chối (lý do ra stderr) · 64 sai cách gọi · 69 đọc/ghi GitHub hỏng.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="merge-queue"
usage() { echo "usage: super-board-queue-label.sh [<pr>] [--repo OWNER/NAME] [--check]" >&2; exit 64; }
PR="" REPO="" CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    --repo) [ $# -ge 2 ] && [ -n "$2" ] || usage; REPO="$2"; shift 2 ;;
    --repo=?*) REPO="${1#--repo=}"; shift ;;
    -*) usage ;;
    *) [ -z "$PR" ] || usage; PR="$1"; shift ;;
  esac
done
LIMIT="${SB_QUEUE_LABEL_GH_TIMEOUT:-6}"
case "$LIMIT" in ''|*[!0-9]*|???*) LIMIT=6 ;; esac

# Lệnh có timeout: hết giờ giết cả nhóm tiến trình (gh / git fetch có thể sinh tiến trình con), exit 124.
run_t() {
  python3 -I -c '
import os, signal, subprocess, sys
# Cùng nhóm tiến trình với helper (không start_new_session): guard giết cả nhóm của helper khi hết thời hạn thì gh / git fetch chết theo.
# ponytail: chạy độc lập mà hết giờ thì chỉ giết con trực tiếp; cháu (git fetch của audit-check) tự dừng theo timeout 60 s của nó.
p = subprocess.Popen(sys.argv[2:], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
try:
    o, e = p.communicate(timeout=float(sys.argv[1]))
except subprocess.TimeoutExpired:
    p.kill(); p.communicate()
    print("timed out after " + sys.argv[1] + " s", file=sys.stderr); sys.exit(124)
sys.stdout.write(o); sys.stderr.write(e); sys.exit(p.returncode)
' "$LIMIT" "$@"
}
REPO_ARG=(); [ -z "$REPO" ] || REPO_ARG=(--repo "$REPO")
SEL=(); [ -z "$PR" ] || SEL=("$PR")
ERRF=$(mktemp "${TMPDIR:-/tmp}/sb-qlabel.XXXXXX") || { echo "queue-label: mktemp hỏng — không gắn nhãn" >&2; exit 69; }
trap 'rm -f "$ERRF"' EXIT
# ${a[@]+"${a[@]}"}: mảng rỗng dưới set -u của bash 3.2 (macOS) không bị coi là biến chưa đặt.
view=$(run_t gh pr view ${SEL[@]+"${SEL[@]}"} ${REPO_ARG[@]+"${REPO_ARG[@]}"} --json number,state,url,headRefOid,comments 2>"$ERRF") || {
  echo "queue-label: không đọc được PR ${PR:-của nhánh hiện tại} từ GitHub ($(tail -1 "$ERRF" 2>/dev/null | cut -c1-160)) — không gắn nhãn ${LABEL}" >&2
  exit 69; }
n=$(printf '%s' "$view" | jq -r '.number // empty' 2>/dev/null) || n=""
head=$(printf '%s' "$view" | jq -r '.headRefOid // empty' 2>/dev/null) || head=""
case "$n" in ''|*[!0-9]*) echo "queue-label: PR ${PR}: GitHub trả dữ liệu thiếu số PR — không gắn nhãn" >&2; exit 69 ;; esac
printf '%s' "$head" | grep -Eq '^[0-9a-f]{40}$' || { echo "queue-label: PR #${n}: GitHub trả dữ liệu thiếu head sha — không gắn nhãn" >&2; exit 69; }

refuse() {   # refuse <approved-head thấy được hoặc ""> <lý do>
  local seen7="${1:0:7}"
  echo "queue-label: từ chối gắn nhãn ${LABEL} cho PR #${n} — head hiện tại ${head:0:7}; approved-head: ${seen7:-không có}${2:+ ($2)}." >&2
  echo "  Bước đúng: qua lane Review (audit Antigravity rồi reviewer ghi approved-head:<head 40 ký tự> + approved-by), hoặc người duyệt tự ghi approved-head:${head}; xong chạy lại .claude/bin/super-board-queue-label.sh ${n}${REPO:+ --repo ${REPO}}." >&2
  exit 3
}
state=$(printf '%s' "$view" | jq -r '.state // empty' 2>/dev/null) || state=""
[ "$state" = OPEN ] || refuse "" "PR đang ${state:-không rõ trạng thái}, không phải OPEN — hàng đợi chỉ nhận PR mở"
verdict=$(printf '%s' "$view" | jq -r -f "$HERE/super-board-approved-head.jq" 2>/dev/null) || { echo "queue-label: PR #${n}: không đánh giá được comment duyệt (jq lỗi) — không gắn nhãn" >&2; exit 69; }
vstate="" approved="" vwhy=""
IFS=$'\t' read -r vstate approved vwhy <<<"$verdict" || true
[ -n "$approved" ] || refuse "" "không có comment approved-head:<sha40> của OWNER/MEMBER/COLLABORATOR"
[ "$vstate" = ok ] || refuse "$approved" "${vwhy:-duyệt không hợp lệ}"
[ "$approved" = "$head" ] || refuse "$approved" "duyệt cho head cũ, PR đã đổi head sau khi duyệt"
case "$vwhy" in
  owner) ;;
  task:?*)
    # Biên bản audit của task nằm theo project PM: repo (hoặc worktree) đang đứng nếu cùng git-common-dir với repo của helper — một
    # worktree thấy cả biên bản của nó lẫn của checkout chính (push_gate._task_audits) —, không thì repo của helper.
    top="$(cd "$HERE/../.." && pwd)"
    cwd_top=$(git rev-parse --show-toplevel 2>/dev/null) || cwd_top=""
    cwd_common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || cwd_common=""
    top_common=$(git -C "$top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || top_common=""
    if [ -n "$cwd_top" ] && [ -n "$cwd_common" ] && [ "$cwd_common" = "$top_common" ]; then
      top="$cwd_top"
    fi
    # Repo của PR (lấy từ url GitHub trả về, đúng cả khi chọn PR bằng URL / GH_REPO / --repo) phải là origin của repo chứa biên bản:
    # biên bản và fetch refs/pull ở repo khác không chứng minh gì cho PR này → không tính nguồn task:.
    prrepo=$(printf '%s' "$view" | jq -r '.url // empty' 2>/dev/null | sed -nE 's#^https://github\.com/([^/]+/[^/]+)/pull/[0-9]+$#\1#p' | tr 'A-Z' 'a-z') || prrepo=""
    origin=$(git -C "$top" remote get-url origin 2>/dev/null | sed -E 's#^(https?://github\.com/|git@github\.com:|ssh://git@github\.com/)##; s#\.git$##' | tr 'A-Z' 'a-z') || origin=""
    [ -n "$prrepo" ] && [ "$origin" = "$prrepo" ] \
      || refuse "$approved" "approved-by task_id ${vwhy#task:} được audit trong repo ${origin:-không rõ}, PR thuộc repo ${prrepo:-không rõ}"
    run_t python3 "$HERE/super-board-audit-check.py" --top "$top" --pr "$n" "${vwhy#task:}" "$head" >/dev/null 2>&1 \
      || refuse "$approved" "approved-by task_id ${vwhy#task:} chưa có audit pass của antigravity-pm với auditedHead ${head:0:7}" ;;
  *) refuse "$approved" "không rõ nguồn duyệt" ;;
esac
[ "$CHECK" -eq 0 ] || exit 0
if ! run_t gh pr edit "${PR:-$n}" ${REPO_ARG[@]+"${REPO_ARG[@]}"} --add-label "$LABEL" >/dev/null 2>"$ERRF"; then
  echo "queue-label: PR #${n} đủ điều kiện nhưng gắn nhãn ${LABEL} hỏng ($(tail -1 "$ERRF" 2>/dev/null | cut -c1-160))" >&2; exit 69
fi
echo "queue-label: PR #${n} @ ${head:0:7} — đã gắn nhãn ${LABEL}"
