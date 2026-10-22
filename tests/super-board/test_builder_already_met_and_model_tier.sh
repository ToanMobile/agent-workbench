#!/usr/bin/env bash
# Test #254:
#  1. Builder có lối ra "AC đã đạt sẵn trên origin/main": comment bằng chứng + đóng issue, không PR; reconcile của runner chuyển Done.
#  2. dispatch claude-p truyền --model theo model_tier của config (low=haiku, medium=sonnet, high=opus; thiếu/lạ = medium).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
RUN_MD="$ROOT/.claude/skills/super-board/references/run.md"
BUILD_MD="$ROOT/.claude/skills/super-build/SKILL.md"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# 1. Lối ra trong Builder lifecycle (đọc phần từ "### Builder (first pass)" tới "### Tester").
life=$(awk '/^### Builder \(first pass\)/{f=1} /^### Tester/{f=0} f' "$RUN_MD")
if printf '%s' "$life" | grep -qi 'already met' && printf '%s' "$life" | grep -q 'gh issue close' && printf '%s' "$life" | grep -qi 'no PR'; then
  ok "run.md Builder lifecycle có lối ra 'already met' (comment bằng chứng, gh issue close, không PR)"
else
  fail "run.md Builder lifecycle thiếu lối ra 'already met'"
fi
if grep -q 'already met' "$BUILD_MD"; then
  ok "super-build SKILL.md cho phép ngoại lệ đóng issue khi AC đã đạt"
else
  fail "super-build SKILL.md vẫn cấm đóng issue, không có ngoại lệ 'already met'"
fi

# 2. --model theo model_tier.
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sb-model-tier.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
for pair in low:haiku medium:sonnet high:opus bogus:sonnet; do
  tier=${pair%%:*}; want=${pair##*:}
  printf '{"model_tier":"%s"}\n' "$tier" > "$tmp/c.json"
  got=$(SB_LIB_ONLY=1 bash -c '. "$1"; CONFIG_PATH="$2"; claude_model_for_tier' _ "$RUNNER" "$tmp/c.json" 2>/dev/null)
  [ "$got" = "$want" ] && ok "tier=$tier -> --model $want" || fail "tier=$tier cho '$got', cần '$want'"
done
printf '{}\n' > "$tmp/c.json"
got=$(SB_LIB_ONLY=1 bash -c '. "$1"; CONFIG_PATH="$2"; claude_model_for_tier' _ "$RUNNER" "$tmp/c.json" 2>/dev/null)
[ "$got" = "sonnet" ] && ok "thiếu model_tier -> sonnet" || fail "thiếu model_tier cho '$got'"

# Mọi lời gọi claude -p trong dispatch_lane đều mang --model.
n_all=$(grep -c 'nohup claude --' "$RUNNER")
n_model=$(grep 'nohup claude --' "$RUNNER" | grep -c -- '--model "\$claude_model"')
[ "$n_all" -gt 0 ] && [ "$n_all" = "$n_model" ] && ok "cả $n_all lời gọi claude -p truyền --model" || fail "claude -p thiếu --model ($n_model/$n_all)"

# 3. R2/R3 (chạy thật): thẻ issue ĐÃ ĐÓNG đang ở Building -> Done, không về Ready; thẻ issue mở -> Ready như cũ.
run_reclaim() {  # $1 = state của issue (CLOSED|OPEN); in ra các lần set_card_status
  SB_T_STATE="$1" SB_LIB_ONLY=1 bash -c '
    . "$1"; INFLIGHT_DIR="$2"; BOT_LOGIN=""; RECLAIM_MOVED=0
    log() { :; }; gh_checkpoint() { :; }; gh_write_once() { :; }; issue_locked() { return 1; }
    git() { return 1; }
    issue_is_open() { [ "$SB_T_STATE" != "CLOSED" ]; }
    set_card_status() { echo "$1->$2"; }
    PROJECT_ITEMS_JSON='"'"'{"items":[{"id":"ITEM1","status":"Building","content":{"type":"Issue","number":7,"assignees":[]}}]}'"'"'
    reclaim_stranded_building' _ "$RUNNER" "$tmp" 2>&1
}
got=$(run_reclaim CLOSED); [ "$got" = "ITEM1->Done" ] && ok "issue CLOSED ở Building -> Done (không về Ready)" || fail "issue CLOSED ở Building cho '$got', cần 'ITEM1->Done'"
got=$(run_reclaim OPEN); [ "$got" = "ITEM1->Ready" ] && ok "issue OPEN ở Building vẫn về Ready" || fail "issue OPEN ở Building cho '$got', cần 'ITEM1->Ready'"

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; } || { echo "FAIL ($FAILS)"; exit 1; }
