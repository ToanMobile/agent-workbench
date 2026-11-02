#!/usr/bin/env bash
# super-board-review-plan.sh — bậc review S/M/L của PR (#858, core-rules §18) ⇒ các bên review nội dung theo config `review_tiers`.
#   super-board-review-plan.sh [--config FILE] [--base REF] [--deletes-data]
# Chạy ở gốc worktree review đã ở head PR. In 2 dòng:
#   <S|M|L> product_lines=<N> reasons=<…>   (nguyên văn review_tier.py)
#   reviewers: claude antigravity …         (config review_tiers[<bậc>]; thiếu khoá hay sai kiểu ⇒ mặc định luật chủ repo 02/11)
# review_tier.py thiếu hoặc lỗi ⇒ bậc L (nghiêng bậc cao, không rơi về S) kèm cảnh báo stderr; exit 0 để lane luôn có danh sách.
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
tier="${line%% *}"
case "$tier" in
  S) list="claude" ;;
  M) list="claude antigravity" ;;
  *) list="claude antigravity ocr grok" ;;
esac
if [ -n "$CONFIG" ]; then
  # Danh sách rỗng hay phần tử không phải chuỗi thì không nhận: không có bậc nào 0 bên review.
  conf="$(jq -r --arg t "$tier" '(.review_tiers // {})[$t] // [] | if type == "array" and length > 0
           and all(.[]; type == "string" and test("^[a-z0-9-]+$")) then join(" ") else "" end' "$CONFIG" 2>/dev/null)" \
    || { echo "review-plan: không đọc được review_tiers trong $CONFIG ⇒ danh sách mặc định" >&2; conf=""; }
  [ -z "$conf" ] || list="$conf"
fi
printf '%s\nreviewers: %s\n' "$line" "$list"
