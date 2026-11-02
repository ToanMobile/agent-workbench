#!/usr/bin/env bash
# #605 (audit T0066 vòng 3, finding 1): super-board-audit-check.py chỉ nhận task_id của `approved-by:` / `cross-review-approved:` khi
# antigravity-pm có audit pass với auditedHead == head. Mọi prompt / tài liệu của lane reviewer phải nói cùng một hợp đồng: reviewer
# chạy audit Antigravity thật qua MCP antigravity-pm (pm_task_create, pm_dispatch kind=audit, đọc audit-agent.json, pm_verdict kind=audit
# verdict=pass auditedHead=<sha>), gate_receipt = biên nhận task impacted (không phải --full), Antigravity không chạy được → thẻ ở Review
# với dòng `blocked-by:`; không câu nào còn bảo sub-agent tự thay audit độc lập hay tự đặt id. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUN_SH="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# check <tên> <văn bản>
check() {
  local name="$1" text="$2" w
  [ -n "$text" ] || { fail "$name: không đọc được văn bản"; return; }
  for w in "pm_task_create" "pm_dispatch kind=audit" "audit-agent.json" "pm_verdict kind=audit verdict=pass auditedHead=" \
           "\"reviewer\":\"antigravity\"" "impacted task receipt" "blocked-by:"; do
    case "$text" in *"$w"*) ;; *) fail "$name thiếu '$w'"; return ;; esac
  done
  for w in "satisfy the independent audit" "--full receipt" "cross-review task id" "\"task_id\":\"<id>\""; do
    case "$text" in *"$w"*) fail "$name còn '$w'"; return ;; esac
  done
  ok "$name: audit Antigravity thật trước approved-by, gate_receipt impacted, blocked-by khi không có Antigravity"
}

# Prompt là chuỗi bash trong ngoặc kép: bỏ \" để được đúng văn bản worker nhận.
check "run.sh (prompt Review, queue bật)" "$(grep -F 'The merge queue is on for this board' "$RUN_SH" | sed 's/\\"/"/g')"
check "run.md" "$(cat "$ROOT/.claude/skills/super-board/references/run.md")"
check "worker-preamble.md" "$(cat "$ROOT/.claude/skills/super-build/references/worker-preamble.md")"
check "super-review/SKILL.md" "$(cat "$ROOT/.claude/skills/super-review/SKILL.md")"
check "ai-factory-superboard-workflow.md" "$(cat "$ROOT/universal-agent-devkit/docs/init_board/ai-factory-superboard-workflow.md")"
# Prompt Review khi queue tắt cũng không còn bảo sub-agent thay audit độc lập.
if grep -F 'Run super-review on issue' "$RUN_SH" | grep -qF 'satisfy the independent audit'; then
  fail "run.sh: prompt Review còn 'satisfy the independent audit'"
else ok "run.sh: không prompt Review nào bảo sub-agent thay audit độc lập"; fi

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
