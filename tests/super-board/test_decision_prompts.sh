#!/usr/bin/env bash
# Test #518: prompt của orchestrator / builder / QA / reviewer biết luật `[orchestrator] [decision]` (#516).
#  1. run.md có mục "### Owner's standing decision": áp luật 1–5 của super-board/references/decision-policy.md theo thứ tự,
#     ghi `[orchestrator] [decision]` kèm marker `<!-- sb-decision:orchestrator -->`, gỡ needs-you (unmark), chuyển cột;
#     danh sách dừng vẫn giữ needs-you; `decision_policy.enabled: false` thì bỏ qua.
#  2. Mỗi prompt lane (super-build SKILL.md + worker-preamble.md, super-qa, super-review, block-template.md) có đoạn
#     "**Owner's standing decision.**": dẫn tới decision-policy.md, coi AC đã được quyết là đã xử lý, không dựng lại blocker,
#     và câu cấm tự đăng `[decision]` cho thẻ mình.
#  3. Prompt lane mà super-board-wave.js dựng mang cùng hai điều đó.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SB="$ROOT/.claude/skills/super-board/references"
POLICY='super-board/references/decision-policy.md'
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
# has <tên> <văn bản> <chuỗi cố định>...: mọi chuỗi phải có trong văn bản (so khớp cố định, không phân biệt hoa thường;
# gộp dòng, bỏ dấu ` của Markdown và dấu \ thoát ` trong template string JS để câu xuống dòng hay có `code` vẫn khớp).
has() {
  local name=$1 text=$2; shift 2
  local flat; flat=$(printf '%s' "$text" | tr '\n' ' ' | tr -d '`\\' | tr -s ' ')
  local s
  for s in "$@"; do
    if printf '%s' "$flat" | grep -qiF -- "$s"; then ok "$name: có '$s'"; else fail "$name: thiếu '$s'"; fi
  done
}

# 1. Orchestrator: mục riêng trong run.md, tới heading kế tiếp.
sec=$(awk '/^### Owner.s standing decision/{f=1; print; next} f && /^##/{exit} f' "$SB/run.md")
if [ -z "$sec" ]; then
  fail "run.md thiếu mục '### Owner's standing decision'"
else
  has "run.md" "$sec" "$POLICY" "rules 1–5" "in order" "[orchestrator] [decision]" "<!-- sb-decision:orchestrator -->" \
    "super-board-needs-you.py unmark" "stop list" "keeps needs-you" "decision_policy.enabled: false" \
    "only the orchestrator writes [decision]" \
    "the same comment on the card's open PR" "Done only when nothing needs merging"
fi
# Ai chạy bước đó: backend claude-p (hợp đồng orchestrator đầu run.md) và backend workflow (bước 2 của run-workflow.md);
# chỗ cũ ghi `waiting` chỉ người gỡ được phải trỏ về mục này.
contract=$(awk '/^## Orchestrator delegation contract/{f=1; next} f && /^## /{exit} f' "$SB/run.md")
has "run.md delegation contract" "$contract" "Owner's standing decision"
sweep=$(awk '/^### The wave-start sweep/{f=1; next} f && /^### /{exit} f' "$SB/run.md")
has "run.md wave-start sweep" "$sweep" "unless the owner's standing decision answers"
has "run-workflow.md" "$(cat "$SB/run-workflow.md")" "run.md → \"Owner's standing decision\""

# 2. Lane prompts: đoạn bắt đầu bằng "**Owner's standing decision.**" tới dòng trống.
para() { awk '/\*\*Owner.s standing decision\.\*\*/{f=1} f && /^[[:space:]]*$/{exit} f' "$1"; }
for rel in .claude/skills/super-build/SKILL.md .claude/skills/super-build/references/worker-preamble.md \
  .claude/skills/super-qa/SKILL.md .claude/skills/super-review/SKILL.md .claude/skills/super-board/references/block-template.md; do
  p=$(para "$ROOT/$rel")
  if [ -z "$p" ]; then fail "$rel thiếu đoạn '**Owner's standing decision.**'"; continue; fi
  has "$rel" "$p" "$POLICY" "[orchestrator] [decision]" "treat that AC as handled" "do not raise the same blocker again" \
    "Never post [decision] yourself"
done
# QA: AC đã được quyết không ghi lại dưới ❌ Not done (qa-report.py chỉ bỏ qua ❌ của report CŨ hơn decision).
has "super-qa decision" "$(para "$ROOT/.claude/skills/super-qa/SKILL.md")" "never under ❌ Not done"

# 3. Prompt lane dựng trong super-board-wave.js (thân lanePrompt). Repo app chỉ chạy board claude-p (không cài wave.js) thì bỏ qua.
WAVE="$ROOT/.claude/workflows/super-board-wave.js"
if [ -f "$WAVE" ]; then
  lp=$(awk '/^const lanePrompt = /{f=1} f{print} f && /^\]\.join/{exit}' "$WAVE")
  has "super-board-wave.js lanePrompt" "$lp" "$POLICY" "[orchestrator] [decision]" "treat that AC as handled" \
    "do not raise the same blocker again" "Never post [decision] yourself"
else
  echo "– bỏ qua: repo không có .claude/workflows/super-board-wave.js"
fi

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; } || { echo "FAIL ($FAILS)"; exit 1; }
