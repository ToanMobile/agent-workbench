#!/usr/bin/env bash
# super-board-review-plan.sh — bậc review S/M/L của PR (#858, core-rules §18) ⇒ các bên review nội dung theo config `review_tiers`.
#   super-board-review-plan.sh [--config FILE] [--base REF] [--deletes-data]
# Chạy ở gốc worktree review đã ở head PR. In 2 dòng:
#   <S|M|L> product_lines=<N> reasons=<…>   (nguyên văn review_tier.py)
#   reviewers: claude antigravity …         (mặc định luật chủ repo 02/11 là sàn; config review_tiers[<bậc>] chỉ THÊM bên;
#                                            danh sách sai kiểu / tên ngoài claude|antigravity|ocr ⇒ bỏ cả danh sách;
#                                            13/11 chủ repo bỏ Grok: grok là tên lạ)
# review_tier.py thiếu hoặc lỗi ⇒ bậc L (nghiêng bậc cao, không rơi về S) kèm cảnh báo stderr; exit 0 để lane luôn có danh sách.
# Repo kit: bản review_tier.py ở base cũng tính và chỉ được nâng bậc, để PR sửa chính review_tier.py không tự hạ bậc.
# Audit Antigravity để DUYỆT merge queue (#605) không do danh sách này quyết: nó giữ ở mọi bậc (run.md → Merge protocol).
# Tương thích bash 3.2.
set -u
CONFIG="" BASE="origin/main" DELETES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --config) CONFIG="${2:-}"; shift 2 || shift ;;
    --base) BASE="${2:-}"; shift 2 || shift ;;
    --deletes-data) DELETES=1; shift ;;
    *) echo "review-plan: tham số lạ: $1" >&2; exit 64 ;;
  esac
done
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "review-plan: không phải repo git" >&2; exit 64; }

# Repo kit (agent-workbench) dùng bản trong checkout này, đúng HEAD đang review; repo app dùng bản DevKit đã cài.
TIER_PY="${SB_REVIEW_TIER_PY:-}"
if [ -z "$TIER_PY" ]; then
  for c in "$ROOT/universal-agent-devkit/bin/review_tier.py" "$ROOT/.agents/devkit/bin/review_tier.py"; do
    if [ -f "$c" ]; then TIER_PY="$c"; break; fi
  done
fi
line=""
if [ -n "$TIER_PY" ] && [ -f "$TIER_PY" ]; then
  line="$(cd "$ROOT" && python3 "$TIER_PY" --base "$BASE" ${DELETES:+--deletes-data})" || line=""
fi
case "$line" in
  "S "*|"M "*|"L "*) ;;
  *) echo "review-plan: không tính được bậc (review_tier.py: ${TIER_PY:-không có}) ⇒ bậc L" >&2
     line="L product_lines=- reasons=tier-error" ;;
esac
rank() { case "$1" in S) echo 1 ;; M) echo 2 ;; *) echo 3 ;; esac; }
if [ "$TIER_PY" = "$ROOT/universal-agent-devkit/bin/review_tier.py" ]; then
  bdir="$(mktemp -d "${TMPDIR:-/tmp}/review-plan.XXXXXX")" || bdir=""
  if [ -n "$bdir" ] && git -C "$ROOT" show "$BASE:universal-agent-devkit/bin/review_tier.py" > "$bdir/review_tier.py" 2>/dev/null; then
    bline="$(cd "$ROOT" && python3 "$bdir/review_tier.py" --base "$BASE" ${DELETES:+--deletes-data} 2>/dev/null)" || bline=""
    case "$bline" in
      "S "*|"M "*|"L "*) if [ "$(rank "${bline%% *}")" -gt "$(rank "${line%% *}")" ]; then line="$bline"; fi ;;
    esac
  fi
  [ -z "$bdir" ] || rm -rf "$bdir"
fi
tier="${line%% *}"
case "$tier" in
  S) list="claude" ;;
  M) list="claude antigravity" ;;
  *) list="claude antigravity ocr" ;;
esac
if [ -n "$CONFIG" ]; then
  # Chỉ nhận mảng toàn tên bên đã biết; tên lạ / sai kiểu ⇒ bỏ cả danh sách. Mặc định là sàn: config chỉ thêm bên.
  conf="$(jq -r --arg t "$tier" '(.review_tiers // {})[$t] // [] | if type == "array"
           and all(.[]; . == "claude" or . == "antigravity" or . == "ocr") then join(" ") else "" end' "$CONFIG" 2>/dev/null)" \
    || { echo "review-plan: không đọc được review_tiers trong $CONFIG ⇒ danh sách mặc định" >&2; conf=""; }
  for n in $conf; do
    case " $list " in *" $n "*) ;; *) list="$list $n" ;; esac
  done
fi
printf '%s\nreviewers: %s\n' "$line" "$list"
