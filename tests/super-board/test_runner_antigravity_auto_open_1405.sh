#!/usr/bin/env bash
# Test hồi quy #1405 (lệnh chủ repo 21/11 "tự mở lên đi chứ"): khi KHÔNG có tiến trình language_server nào, runner tự chạy lệnh mở app
# (mặc định `open -a Antigravity`, tiêm được qua SB_ANTIGRAVITY_OPEN_CMD), chờ sẵn sàng có giới hạn, probe lại, hết cách mới Block.
#  A. App đóng, mở xong thì probe nối được → KHÔNG Block, lệnh mở chạy đúng 1 lần.
#  B. App đóng, mở rồi vẫn không nối được → chờ có giới hạn rồi Block 'Antigravity chưa mở', bằng chứng ghi runner đã tự mở.
#  C. Trong thời gian nghỉ sau lần mở trượt → không mở lại, Block ngay.
#  D. Có tiến trình language_server (app đang mở nhưng probe trượt vì lý do khác) → KHÔNG chạy lệnh mở.
#  E. Không tiêm SB_ANTIGRAVITY_OPEN_CMD mà runner được nạp kiểu SB_LIB_ONLY (E1) hoặc có probe giả SB_ANTIGRAVITY_PROBE (E2) → lệnh mở
#     không chạy (open giả đầu PATH ghi 0 lần gọi).
#  F. Runner chạy thật (không lib mode, không probe giả), không tiêm gì: lệnh mặc định đúng là `open -a Antigravity` (open giả đầu PATH).
#  G. SB_ANTIGRAVITY_AUTO_OPEN=0 → không mở.
#  H. sweep_antigravity_blocked: thẻ Blocked 'antigravity-closed' khi app đóng → runner tự mở, nối được thì thẻ về Review.
# Mọi lệnh mở trong file này là script giả (SB_ANTIGRAVITY_OPEN_CMD hoặc `open` giả đầu PATH). Chạy offline, tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-1405-open.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

mkdir -p "$TMP/bin" "$TMP/path" "$TMP/home" "$TMP/repo/wl"
printf '// fake mcp\n' > "$TMP/fake-pm-mcp.js"

# Probe giả: nối được khi có file $STUB_DIR/ready; đếm số lần bị gọi.
cat > "$TMP/probe.sh" <<'SH'
#!/usr/bin/env bash
echo x >> "$STUB_DIR/probe-calls"
if [ -e "$STUB_DIR/ready" ]; then
  echo "Antigravity language server: noi duoc tai localhost:61544 (nguon: probe)"
  exit 0
fi
echo "Antigravity language server: KHONG NOI DUOC — Khong thay tien trinh Antigravity language_server nao dang chay."
exit 1
SH
# Lệnh mở giả: ghi lại tham số; "app" sẵn sàng khi có file $STUB_DIR/open-works.
cat > "$TMP/open-cmd.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "cmd $*" >> "$STUB_DIR/open-calls"
[ -e "$STUB_DIR/open-works" ] && : > "$STUB_DIR/ready"
exit 0
SH
# `open` giả đứng đầu PATH: runner gọi `open` qua PATH nên rơi vào đây (kiểm bằng `command -v open` bên dưới).
cat > "$TMP/path/open" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "open $*" >> "$STUB_DIR/open-calls"
[ -e "$STUB_DIR/open-works" ] && : > "$STUB_DIR/ready"
exit 0
SH
cat > "$TMP/bin/super-board-github-read.py" <<'PY'
import os, sys
a = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
f = os.environ['STUB_DIR'] + '/issue-' + a[2] + '.json' if a[:2] == ['issue', 'view'] else ''
if not f or not os.path.exists(f):
    sys.exit(1)
sys.stdout.write(open(f).read())
PY
chmod +x "$TMP/probe.sh" "$TMP/open-cmd.sh" "$TMP/path/open"

export HOME="$TMP/home" STUB_DIR="$TMP" PATH="$TMP/path:$PATH" WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0
unset SB_ANTIGRAVITY_PROBE SB_ANTIGRAVITY_PM_MCP SB_ANTIGRAVITY_OPEN_CMD SB_ANTIGRAVITY_AUTO_OPEN SB_ANTIGRAVITY_OPEN_WAIT_S \
      SB_ANTIGRAVITY_OPEN_POLL_S SB_ANTIGRAVITY_OPEN_COOLDOWN_S SB_ANTIGRAVITY_SWEEP_EVERY SB_GITHUB_READ_STRICT SB_ACCOUNT_POOL
[ "$(command -v open)" = "$TMP/path/open" ] || { echo "✖ open giả không đứng đầu PATH — dừng để không mở app thật"; exit 1; }

SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
SB_GITHUB_READ="$TMP/bin/super-board-github-read.py"
CONFIG_PATH="$TMP/cfg.json"; echo '{"worker_backend":"claude-p","merge_queue":{"enabled":true}}' > "$CONFIG_PATH"
INFLIGHT_DIR="$TMP/repo/.claude/super-board/inflight"; mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="wl"; REPO_ROOT="$TMP/repo"; BOT_LOGIN="bot"; BASE_BRANCH="main"
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }
sweep_remove_assignee() { :; }
log() { echo "$*" >> "$TMP/log"; }
resolve_worker_account() { POOL_ENGINE="claude"; POOL_ACCT="max"; POOL_CFG=""; return 0; }
cd "$TMP/repo" || exit 1

LS_RUNNING=1                                    # 1 = không có tiến trình language_server nào (mặc định của test)
antigravity_ls_running() { return "$LS_RUNNING"; }
set_card() {
  PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"PVTI_$1\",\"status\":\"${2:-Review}\",\"labels\":[],\"content\":{\"type\":\"Issue\",\"number\":$1,\"title\":\"card $1\",\"assignees\":[]}}]}"
}
reset_run() {
  rm -f "$TMP/ready" "$TMP/open-works" "$TMP/open-calls" "$TMP/probe-calls" "$TMP/writes" "$TMP/log" "$INFLIGHT_DIR/antigravity-open-at"
  : > "$TMP/writes"; : > "$TMP/log"; : > "$TMP/open-calls"; : > "$TMP/probe-calls"
  LS_RUNNING=1; AG_SWEEP_NEXT=0; AG_NON_AG_CARDS=""
  POOL_ENGINE="claude"; POOL_CFG=""
  export SB_ANTIGRAVITY_PM_MCP="$TMP/fake-pm-mcp.js" SB_ANTIGRAVITY_PROBE="$TMP/probe.sh" SB_ANTIGRAVITY_OPEN_CMD="$TMP/open-cmd.sh --fake"
  export SB_ANTIGRAVITY_OPEN_WAIT_S=2 SB_ANTIGRAVITY_OPEN_POLL_S=1
  unset SB_ANTIGRAVITY_AUTO_OPEN SB_ANTIGRAVITY_OPEN_COOLDOWN_S
}
opens() { grep -c . "$TMP/open-calls" 2>/dev/null || true; }
dump() { echo "opens=$(tr '\n' ';' < "$TMP/open-calls") probes=$(grep -c . "$TMP/probe-calls") writes=$(tr '\n' ';' < "$TMP/writes" | cut -c1-600) log=$(tr '\n' ';' < "$TMP/log")"; }

# ── A: app đóng, mở xong nối được → không Block
reset_run; set_card 1405; : > "$TMP/open-works"
rc=0; review_antigravity_preflight 1405 >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ] && [ "$(opens)" = "1" ] && grep -qx "cmd --fake" "$TMP/open-calls" && ! grep -q "Blocked" "$TMP/writes"; then
  ok "A: no language_server -> runner ran the open command once, probe retried OK, card not Blocked"
else
  fail "A: auto-open then ready failed (rc=$rc $(dump))"
fi

# ── B: app đóng, mở rồi vẫn không nối được → chờ có giới hạn rồi mới Block
reset_run; set_card 1405
t0=$(date +%s); rc=0; review_antigravity_preflight 1405 >/dev/null 2>&1 || rc=$?; t1=$(date +%s)
if [ "$rc" -ne 0 ] && [ "$(opens)" = "1" ] && grep -qx "move PVTI_1405 Blocked" "$TMP/writes" \
   && grep -q "Antigravity chưa mở" "$TMP/writes" && grep -q "sb-blocked-reason: antigravity-closed" "$TMP/writes" \
   && grep -q "runner đã tự mở" "$TMP/writes" && [ "$(grep -c . "$TMP/probe-calls")" -ge 3 ] \
   && [ $((t1 - t0)) -ge 2 ] && [ $((t1 - t0)) -le 20 ]; then
  ok "B: open did not help -> bounded wait ($((t1 - t0))s, $(grep -c . "$TMP/probe-calls") probes) then Blocked with 'runner đã tự mở' evidence"
else
  fail "B: bounded wait then Block failed (rc=$rc elapsed=$((t1 - t0))s $(dump))"
fi

# ── C: còn trong thời gian nghỉ sau lần mở trượt → không mở lại, Block ngay (giữ nguyên dấu thời gian của B)
: > "$TMP/open-calls"; : > "$TMP/writes"; : > "$TMP/probe-calls"
t0=$(date +%s); rc=0; review_antigravity_preflight 1405 >/dev/null 2>&1 || rc=$?; t1=$(date +%s)
if [ "$rc" -ne 0 ] && [ "$(opens)" = "0" ] && grep -qx "move PVTI_1405 Blocked" "$TMP/writes" && [ "$(grep -c . "$TMP/probe-calls")" = "1" ]; then
  ok "C: inside the cooldown after a failed open -> not opened again, Blocked at once"
else
  fail "C: cooldown failed (rc=$rc elapsed=$((t1 - t0))s $(dump))"
fi

# ── D: có tiến trình language_server → không chạy lệnh mở
reset_run; set_card 1405; LS_RUNNING=0; : > "$TMP/open-works"
rc=0; review_antigravity_preflight 1405 >/dev/null 2>&1 || rc=$?
if [ "$rc" -ne 0 ] && [ "$(opens)" = "0" ] && grep -qx "move PVTI_1405 Blocked" "$TMP/writes" && ! grep -q "runner đã tự mở" "$TMP/writes"; then
  ok "D: a language_server process exists -> open command not run, Blocked as before"
else
  fail "D: opened although language_server is running (rc=$rc $(dump))"
fi

# ── E1: runner nạp kiểu SB_LIB_ONLY, probe là hàm giả, không tiêm lệnh mở → open giả ghi 0 lần gọi
eval "real_$(declare -f antigravity_probe)"
reset_run; set_card 1405; unset SB_ANTIGRAVITY_OPEN_CMD SB_ANTIGRAVITY_PROBE; : > "$TMP/open-works"
antigravity_probe() { "$TMP/probe.sh"; }
rc=0; review_antigravity_preflight 1405 >/dev/null 2>&1 || rc=$?
if [ "$rc" -ne 0 ] && [ "$(opens)" = "0" ] && grep -qx "move PVTI_1405 Blocked" "$TMP/writes"; then
  ok "E1: lib mode without SB_ANTIGRAVITY_OPEN_CMD -> open not called"
else
  fail "E1: lib mode triggered an open (rc=$rc $(dump))"
fi

# ── E2: không lib mode nhưng có probe giả, không tiêm lệnh mở → open giả ghi 0 lần gọi
reset_run; set_card 1405; unset SB_ANTIGRAVITY_OPEN_CMD; : > "$TMP/open-works"
SB_SLOT_LIB_MODE=0
rc=0; review_antigravity_preflight 1405 >/dev/null 2>&1 || rc=$?
SB_SLOT_LIB_MODE=1
if [ "$rc" -ne 0 ] && [ "$(opens)" = "0" ] && grep -qx "move PVTI_1405 Blocked" "$TMP/writes"; then
  ok "E2: injected test probe without SB_ANTIGRAVITY_OPEN_CMD -> open not called"
else
  fail "E2: fake probe triggered an open (rc=$rc $(dump))"
fi

# ── F: runner chạy thật, không tiêm gì → lệnh mặc định là `open -a Antigravity` (probe thật thay bằng hàm giả, open giả đầu PATH)
reset_run; set_card 1405; unset SB_ANTIGRAVITY_OPEN_CMD SB_ANTIGRAVITY_PROBE; : > "$TMP/open-works"
SB_SLOT_LIB_MODE=0
rc=0; review_antigravity_preflight 1405 >/dev/null 2>&1 || rc=$?
SB_SLOT_LIB_MODE=1
eval "$(declare -f real_antigravity_probe | sed '1s/^real_//')"
if [ "$rc" -eq 0 ] && [ "$(opens)" = "1" ] && grep -qx "open -a Antigravity" "$TMP/open-calls" && ! grep -q "Blocked" "$TMP/writes"; then
  ok "F: default open command is 'open -a Antigravity'"
else
  fail "F: default open command wrong (rc=$rc $(dump))"
fi

# ── G: SB_ANTIGRAVITY_AUTO_OPEN=0 → không mở
reset_run; set_card 1405; export SB_ANTIGRAVITY_AUTO_OPEN=0; : > "$TMP/open-works"
rc=0; review_antigravity_preflight 1405 >/dev/null 2>&1 || rc=$?
if [ "$rc" -ne 0 ] && [ "$(opens)" = "0" ] && grep -qx "move PVTI_1405 Blocked" "$TMP/writes"; then
  ok "G: SB_ANTIGRAVITY_AUTO_OPEN=0 -> no open, Blocked"
else
  fail "G: switch ignored (rc=$rc $(dump))"
fi

# ── H: sweep — thẻ Blocked 'antigravity-closed', app đóng → runner tự mở, nối được thì thẻ về Review
reset_run; set_card 1406 Blocked; : > "$TMP/open-works"
cat > "$TMP/issue-1406.json" <<'JSON'
{"comments":[
  {"body":"[orchestrator] [blocker] 🛑 blocked · ❓ Antigravity chưa mở\n<!-- sb-blocked-reason: antigravity-closed -->\nblocked-by:  agent"}
]}
JSON
rc=0; sweep_antigravity_blocked >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ] && [ "$(opens)" = "1" ] && grep -qx "move PVTI_1406 Review" "$TMP/writes"; then
  ok "H: sweep opened Antigravity itself and moved the Blocked card back to Review"
else
  fail "H: sweep did not self-open (rc=$rc $(dump))"
fi

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; } || { echo "FAIL ($FAILS)"; exit 1; }
