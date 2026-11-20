#!/usr/bin/env bash
# Test hồi quy bổ sung (QA #1390) bắt các ca biên của antigravity_pm_mcp_script và sweep_antigravity_blocked.
#  G1. Worktree/checkout chưa cài node_modules cho antigravity-pm-mcp: phải bỏ qua script thiếu SDK, lấy bản cài hợp lệ ở profile.
#  G2. Thẻ từng bị Blocked vì Antigravity, đã trả về Review, sau đó bị Blocked lại vì lý do khác (vd 🔐): không được tự trả về Review lần nữa.
#  G3. Thẻ bị Blocked vì lý do khác (vd 🛡 rebuild cap) nhưng comment cũ nhắc pm_dispatch/antigravity-pm: không được trả nhầm về Review.
# Chạy offline, tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-1390-qa.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

mkdir -p "$TMP/home" "$TMP/bin" "$TMP/wt/mcp-servers/antigravity-pm-mcp/bin" \
  "$TMP/installed/bin" "$TMP/installed/node_modules/@modelcontextprotocol/sdk" \
  "$TMP/profile" "$TMP/repo/wl"
printf '// unrunnable worktree copy without node_modules\n' > "$TMP/wt/mcp-servers/antigravity-pm-mcp/bin/antigravity-pm-mcp.js"
printf '// runnable installed copy with sdk\n' > "$TMP/installed/bin/antigravity-pm-mcp.js"
printf '{"mcpServers":{"antigravity-pm":{"type":"stdio","command":"node","args":["%s/installed/bin/antigravity-pm-mcp.js"]}}}\n' "$TMP" > "$TMP/profile/.claude.json"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/probe-ok.sh"
chmod +x "$TMP/probe-ok.sh"
printf 'print("ok")\n' > "$TMP/bin/super-board-skills-ready.py"
printf 'import sys\nsys.exit(1)\n' > "$TMP/bin/super-board-github-read.py"

export HOME="$TMP/home" WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0
unset SB_ANTIGRAVITY_PM_MCP SB_ANTIGRAVITY_PROBE SB_ANTIGRAVITY_SWEEP_EVERY

SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
SB_GITHUB_READ="$TMP/bin/super-board-github-read.py"
INFLIGHT_DIR="$TMP/repo/.claude/super-board/inflight"; mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="$TMP/repo/wl"; BOT_LOGIN="bot"; BASE_BRANCH="main"
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }

# G1: Worktree có mcp-servers/antigravity-pm-mcp/bin/antigravity-pm-mcp.js nhưng thiếu node_modules
REPO_ROOT="$TMP/wt"
POOL_CFG="$TMP/profile"
picked=$(antigravity_pm_mcp_script)
if [ "$picked" = "$TMP/installed/bin/antigravity-pm-mcp.js" ]; then
  ok "G1: antigravity_pm_mcp_script skips worktree copy lacking node_modules and selects runnable profile script"
else
  fail "G1: picked unrunnable script without node_modules ($picked)"
fi

# G2 & G3: sweep_antigravity_blocked không được kéo nhầm thẻ đã bị chặn vì lý do khác
: > "$TMP/writes"
export SB_ANTIGRAVITY_PM_MCP="$TMP/installed/bin/antigravity-pm-mcp.js"
export SB_ANTIGRAVITY_PROBE="$TMP/probe-ok.sh"
export SB_ANTIGRAVITY_SWEEP_EVERY=0
AG_NON_AG_CARDS=""; AG_SWEEP_NEXT=0
PROJECT_ITEMS_JSON='{"items":[
  {"id":"PVTI_2001","status":"Blocked","labels":[],"content":{"type":"Issue","number":2001,"title":"reblocked secret","assignees":[]}},
  {"id":"PVTI_2002","status":"Blocked","labels":[],"content":{"type":"Issue","number":2002,"title":"rebuild cap mention","assignees":[]}}
]}'
cap_progress_comments() {
  if [ "$1" = "2001" ]; then
    cat <<'JSON'
[
  {"body":"[orchestrator] [blocker] 🛑 blocked · ❓ Antigravity chưa mở\n<!-- sb-blocked-reason: antigravity-closed -->\nblocked-by:  agent"},
  {"body":"[orchestrator] [report] ↩️ back to Review · Antigravity đã nối lại"},
  {"body":"[builder] [blocker] 🛑 blocked · 🔐 missing API_KEY\nReason tag:  🔐\nMove back:   drag this card to Review after the steps above are done\nblocked-by:  -"}
]
JSON
  else
    cat <<'JSON'
[
  {"body":"[reviewer] [report] ✅ verified pm_dispatch kind=audit ok"},
  {"body":"[orchestrator] [blocker] 🛑 blocked · 🛡 rebuild cap reached\nReason tag:  🛡\nMove back:   drag this card to Review after the steps above are done\nblocked-by:  -"}
]
JSON
  fi
}

sweep_antigravity_blocked
rc_sweep=$?
if ! grep -q "PVTI_2001" "$TMP/writes"; then
  ok "G2: sweep ignores stale sb-blocked-reason once card was later blocked with 🔐"
else
  fail "G2: sweep falsely moved 🔐 re-blocked #2001 back to Review (rc=$rc_sweep writes=$(tr '\n' ';' < "$TMP/writes"))"
fi

if ! grep -q "PVTI_2002" "$TMP/writes"; then
  ok "G3: sweep ignores non-blocker pm_dispatch comment when latest blocker is 🛡 rebuild cap"
else
  fail "G3: sweep falsely moved 🛡 rebuild-cap #2002 back to Review (rc=$rc_sweep writes=$(tr '\n' ';' < "$TMP/writes"))"
fi

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; } || { echo "FAIL ($FAILS)"; exit 1; }
