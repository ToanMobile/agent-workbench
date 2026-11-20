#!/usr/bin/env bash
# Test hồi quy #1390: review worker thiếu MCP antigravity-pm hoặc Antigravity đóng.
#  A. Trước khi dispatch review cần audit: Antigravity đóng → Blocked với lý do 'Antigravity chưa mở' + cách mở, không phóng worker.
#  B. Trước khi dispatch review cần audit: thiếu MCP antigravity-pm → Blocked với lý do 'thiếu antigravity-pm' + cách cài, không phóng worker.
#  C. Profile thiếu antigravity-pm nhưng tìm thấy script MCP → truyền --mcp-config cho phiên review; edited_existing kích hoạt probe, PR thường bỏ qua.
#  D. Worker thoát 0 không comment (hoặc comment blocked-by: -) vì thiếu MCP / Antigravity đóng → Blocked nêu đúng 'thiếu antigravity-pm' / 'Antigravity chưa mở', không ghi 'waiting on a person', không bounce sang Ready.
#  E. sweep_antigravity_blocked: thẻ Blocked cũ (kiểu Goods/Idle) và thẻ mới tự về Review khi Antigravity nối lại; thẻ Blocked khác giữ nguyên.
# Chạy offline, tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
AUDIT_CHECK="$ROOT/.claude/bin/super-board-audit-check.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-1390.XXXXXX")"
cleanup() {
  for p in $(cat "$TMP/stub-pids" 2>/dev/null); do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done
  rm -rf "$TMP"
}
trap cleanup EXIT

mkdir -p "$TMP/bin" "$TMP/path" "$TMP/repo/docs/super-board" "$TMP/repo/wl" "$TMP/profile_no_mcp" "$TMP/profile_with_mcp"
echo '{}' > "$TMP/profile_no_mcp/.claude.json"
printf '{"mcpServers":{"antigravity-pm":{"type":"stdio","command":"node","args":["%s/fake-pm-mcp.js"]}}}\n' "$TMP" > "$TMP/profile_with_mcp/.claude.json"
printf '// fake mcp\n' > "$TMP/fake-pm-mcp.js"

cat > "$TMP/bin/super-board-github-read.py" <<'PY'
import os, sys
a = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
d = os.environ['STUB_DIR']
if a[:2] == ['pr', 'list']:
    f = d + '/prs.json'
elif a[:2] == ['pr', 'view']:
    f = d + '/comments-pr-' + a[2] + '.json'
elif a[:2] == ['issue', 'view']:
    f = d + '/issue-' + a[2] + '.json'
else:
    sys.exit(1)
if not os.path.exists(f):
    sys.exit(1)
sys.stdout.write(open(f).read())
PY
printf 'print("ok")\n' > "$TMP/bin/super-board-skills-ready.py"

cat > "$TMP/path/claude" <<'SH'
#!/usr/bin/env bash
echo $$ >> "$STUB_DIR/stub-pids"
printf '%s\n' "$*" >> "$STUB_DIR/claude-args"
exec sleep 300
SH
chmod +x "$TMP/path/claude"

cat > "$TMP/probe-fail.sh" <<'SH'
#!/usr/bin/env bash
echo "Antigravity language server: KHONG NOI DUOC — Khong thay tien trinh Antigravity language_server nao dang chay."
exit 1
SH
cat > "$TMP/probe-ok.sh" <<'SH'
#!/usr/bin/env bash
echo "Antigravity language server: noi duoc tai localhost:61544 (nguon: probe)"
exit 0
SH
chmod +x "$TMP/probe-fail.sh" "$TMP/probe-ok.sh"

export STUB_DIR="$TMP" PATH="$TMP/path:$PATH" WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0
unset SB_GITHUB_READ_STRICT SB_ACCOUNT_POOL SB_BUILD_LOAD_MAX DEVKIT_SLOT_LOAD_MAX SB_REVIEW_TRAIN SB_MERGE_QUEUE SB_NOOP_MAX SB_NOOP_WINDOW_S SB_REVIEW_ANTIGRAVITY SB_ANTIGRAVITY_PROBE SB_ANTIGRAVITY_PM_MCP SB_ANTIGRAVITY_SWEEP_EVERY

SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
SB_GITHUB_READ="$TMP/bin/super-board-github-read.py"
SB_AUDIT_CHECK="$AUDIT_CHECK"
CONFIG_PATH="$TMP/cfg.json"; echo '{"worker_backend":"claude-p","merge_queue":{"enabled":true}}' > "$CONFIG_PATH"
INFLIGHT_DIR="$TMP/repo/.claude/super-board/inflight"; mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="wl"; REPO_ROOT="$TMP/repo"; BOT_LOGIN="bot"; BASE_BRANCH="main"
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }
issue_is_open() { return 0; }
resolve_worker_account() { POOL_ENGINE="claude"; POOL_ACCT="max"; POOL_CFG="$TMP/profile_no_mcp"; return 0; }
note_worker_limit() { :; }
note_early_death() { :; }
fetch_project_items() { :; }

cd "$TMP/repo" || exit 1
git init -q -b main . 2>/dev/null || git init -q . 2>/dev/null
git config user.email test@example.invalid
git config user.name test
mkdir -p tests src
printf '#!/usr/bin/env bash\necho ok\n' > tests/test_demo.sh
printf 'print(1)\n' > src/app.py
git add tests/test_demo.sh src/app.py
git commit -q -m "base"

git checkout -q -b issue-1393-edit-test
printf '#!/usr/bin/env bash\necho changed\n' > tests/test_demo.sh
git commit -aq -m "edit test"
SHA_EDITED=$(git rev-parse HEAD)

git checkout -q main
git checkout -q -b issue-1398-src-only
printf 'print(2)\n' > src/app.py
git commit -aq -m "edit src"
SHA_SRC=$(git rev-parse HEAD)
git checkout -q main

set_card() {
  local n="$1" st="${2:-Review}"
  PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"PVTI_$n\",\"status\":\"$st\",\"labels\":[],\"content\":{\"type\":\"Issue\",\"number\":$n,\"title\":\"card $n\",\"assignees\":[]}}]}"
}
reset_run() {
  for p in $(cat "$TMP/stub-pids" 2>/dev/null); do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done
  : > "$TMP/stub-pids"
  REVIEW_PID=""; REVIEW_ISSUE=""; REVIEW_EXTRA=""; ACTIVE_WORKERS=0; TRAIN_BATCH=""
  rm -rf "$INFLIGHT_DIR"/[0-9]* "$INFLIGHT_DIR"/noops "$INFLIGHT_DIR"/review-stall "$INFLIGHT_DIR"/review-wait "$TMP/prs.json" "$TMP/issue-"*.json wl/*
  : > "$TMP/log"; : > "$TMP/writes"; : > "$TMP/claude-args"
  echo '{"worker_backend":"claude-p","merge_queue":{"enabled":true}}' > "$CONFIG_PATH"
  unset SB_REVIEW_ANTIGRAVITY SB_ANTIGRAVITY_PROBE SB_ANTIGRAVITY_PM_MCP SB_ANTIGRAVITY_SWEEP_EVERY
  AG_NON_AG_CARDS=""; AG_SWEEP_NEXT=0
  resolve_worker_account() { POOL_ENGINE="claude"; POOL_ACCT="max"; POOL_CFG="$TMP/profile_no_mcp"; return 0; }
}

# ── A: Antigravity đóng trước khi dispatch review cần audit → Blocked 'Antigravity chưa mở', không phóng worker
reset_run; set_card 1391 Review
export SB_REVIEW_ANTIGRAVITY=1
export SB_ANTIGRAVITY_PM_MCP="$TMP/fake-pm-mcp.js"
export SB_ANTIGRAVITY_PROBE="$TMP/probe-fail.sh"
dispatch_lane review 1391
if [ ! -e wl/worker-review-1391.log ] && [ ! -e "$INFLIGHT_DIR/1391" ] \
   && grep -qx "move PVTI_1391 Blocked" "$TMP/writes" \
   && grep -q "Antigravity chưa mở" "$TMP/writes" \
   && grep -q "open -a Antigravity" "$TMP/writes" \
   && grep -q "sb-blocked-reason: antigravity-closed" "$TMP/writes" \
   && grep -q "blocked-by:  agent" "$TMP/writes"; then
  ok "A: Antigravity closed pre-dispatch -> Blocked 'Antigravity chưa mở' + open hint, 0 workers spawned"
else
  fail "A: pre-dispatch closed failed (wlog=$([ -e wl/worker-review-1391.log ] && echo y || echo n) writes=$(tr '\n' ';' < "$TMP/writes"))"
fi

# ── B: Thiếu MCP antigravity-pm trước khi dispatch → Blocked 'thiếu antigravity-pm', không phóng worker
reset_run; set_card 1392 Review
export SB_REVIEW_ANTIGRAVITY=1
export SB_ANTIGRAVITY_PM_MCP="$TMP/does-not-exist.js"
export SB_ANTIGRAVITY_PROBE="$TMP/probe-ok.sh"
dispatch_lane review 1392
if [ ! -e wl/worker-review-1392.log ] && [ ! -e "$INFLIGHT_DIR/1392" ] \
   && grep -qx "move PVTI_1392 Blocked" "$TMP/writes" \
   && grep -q "thiếu antigravity-pm" "$TMP/writes" \
   && grep -q "claude mcp add antigravity-pm" "$TMP/writes" \
   && grep -q "sb-blocked-reason: antigravity-missing-mcp" "$TMP/writes" \
   && grep -q "blocked-by:  agent" "$TMP/writes"; then
  ok "B: missing MCP pre-dispatch -> Blocked 'thiếu antigravity-pm' + install hint, 0 workers spawned"
else
  fail "B: pre-dispatch missing MCP failed (wlog=$([ -e wl/worker-review-1392.log ] && echo y || echo n) writes=$(tr '\n' ';' < "$TMP/writes"))"
fi

# ── C: Inject --mcp-config cho profile thiếu antigravity-pm; PR sửa test (edited_existing) kích hoạt probe, PR thường đi thẳng
reset_run; set_card 1393 Review
printf '[{"number":93,"headRefName":"issue-1393-edit-test","headRefOid":"%s","labels":[],"isDraft":false}]' "$SHA_EDITED" > "$TMP/prs.json"
export SB_ANTIGRAVITY_PM_MCP="$TMP/fake-pm-mcp.js"
export SB_ANTIGRAVITY_PROBE="$TMP/probe-fail.sh"
dispatch_lane review 1393
if [ ! -e wl/worker-review-1393.log ] && grep -qx "move PVTI_1393 Blocked" "$TMP/writes" && grep -q "Antigravity chưa mở" "$TMP/writes"; then
  ok "C1: PR editing existing test triggers Antigravity probe even without SB_REVIEW_ANTIGRAVITY"
else
  fail "C1: edited_existing PR did not trigger probe (writes=$(tr '\n' ';' < "$TMP/writes"))"
fi

reset_run; set_card 1398 Review
printf '[{"number":98,"headRefName":"issue-1398-src-only","headRefOid":"%s","labels":[],"isDraft":false}]' "$SHA_SRC" > "$TMP/prs.json"
export SB_ANTIGRAVITY_PM_MCP="$TMP/fake-pm-mcp.js"
export SB_ANTIGRAVITY_PROBE="$TMP/probe-fail.sh"
dispatch_lane review 1398
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TMP/claude-args" ] && break; sleep 0.2; done
if [ -e wl/worker-review-1398.log ] && grep -q -- "--mcp-config " "$TMP/claude-args"; then
  mcp_file=$(sed -n 's/.*--mcp-config \([^ ]*\).*/\1/p' "$TMP/claude-args" | head -1)
  if [ -f "$mcp_file" ] && grep -q "fake-pm-mcp.js" "$mcp_file"; then
    ok "C2: src-only PR proceeds when Antigravity closed AND review gets --mcp-config for profile lacking antigravity-pm"
  else
    fail "C2: --mcp-config file invalid ($mcp_file)"
  fi
else
  fail "C2: src-only PR blocked or missing --mcp-config (args=$(cat "$TMP/claude-args") log=$(tr '\n' '|' < "$TMP/log") wlog=$(tail -n 5 wl/worker-review-1398.log 2>/dev/null | tr '\n' '|'))"
fi

# C3: Profile đã có antigravity-pm (không ép SB_ANTIGRAVITY_PM_MCP) → không chèn --mcp-config thừa
reset_run; set_card 1398 Review
resolve_worker_account() { POOL_ENGINE="claude"; POOL_ACCT="finos"; POOL_CFG="$TMP/profile_with_mcp"; return 0; }
printf '[{"number":98,"headRefName":"issue-1398-src-only","headRefOid":"%s","labels":[],"isDraft":false}]' "$SHA_SRC" > "$TMP/prs.json"
dispatch_lane review 1398
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TMP/claude-args" ] && break; sleep 0.2; done
if [ -s "$TMP/claude-args" ] && ! grep -q -- "--mcp-config " "$TMP/claude-args"; then
  ok "C3: profile already having antigravity-pm does not get redundant --mcp-config"
else
  fail "C3: unexpected --mcp-config for profile with antigravity-pm (args=$(cat "$TMP/claude-args"))"
fi

# ── D: block_noop_workers — worker thoát 0 không comment vì thiếu antigravity-pm → 'thiếu antigravity-pm', KHÔNG 'waiting on a person'
sleep 0 & DEAD=$!; wait "$DEAD"
COUNT=3; LAST_COMMENT=""
issue_comment_count() { printf '%s' "$COUNT"; }
issue_last_comment() { printf '%s' "$LAST_COMMENT"; }

# D1: thoát 0 không comment, log nói thiếu antigravity-pm (kèm issue có comment cũ blocked-by: - giống ca thật)
reset_run; set_card 1394 Review
LAST_COMMENT=$'[reviewer] [report] chưa duyệt\nblocked-by: -'
printf '=== dispatch lane=review issue=#1394 ===\nprompt: Run super-review ...\n{"type":"result","subtype":"success","is_error":false,"result":"Phiên này không có MCP antigravity-pm nên chưa duyệt được."}\nworker_exit: exit=0 signal=none elapsed=45s\n' > "$WORKER_LOG_DIR/worker-review-1394.log"
printf 'PID=%s\nLANE=review\nSTARTED=2026-11-20T10:00:00Z\nWORKER_LOG=%s\nFROM_COL=Review\nCOMMENTS0=3\n' "$DEAD" "$WORKER_LOG_DIR/worker-review-1394.log" > "$INFLIGHT_DIR/1394"
reap_finished_locks; block_noop_workers
if grep -qx "move PVTI_1394 Blocked" "$TMP/writes" \
   && ! grep -q "move PVTI_1394 Ready" "$TMP/writes" \
   && grep -q "thiếu antigravity-pm" "$TMP/writes" \
   && ! grep -q "waiting on a person" "$TMP/writes" \
   && grep -q "blocked-by:  agent" "$TMP/writes"; then
  ok "D1: worker exit 0 no comment because missing MCP -> Blocked 'thiếu antigravity-pm', not 'waiting on a person', not bounced to Ready"
else
  fail "D1: wrong block handling (writes=$(tr '\n' ';' < "$TMP/writes"))"
fi

# D2: worker thoát 0 CÓ comment mới (COUNT > c0) nói thiếu antigravity-pm + blocked-by: - → Blocked ngay (không stall 3 lượt)
reset_run; set_card 1394 Review
COUNT=4; LAST_COMMENT=$'[reviewer] [report] thiếu công cụ MCP antigravity-pm\nblocked-by: -'
printf '=== dispatch lane=review issue=#1394 ===\n{"type":"result","subtype":"success","is_error":false,"result":"thiếu antigravity-pm"}\nworker_exit: exit=0 signal=none elapsed=40s\n' > "$WORKER_LOG_DIR/worker-review-1394.log"
printf 'PID=%s\nLANE=review\nSTARTED=2026-11-20T10:00:00Z\nWORKER_LOG=%s\nFROM_COL=Review\nCOMMENTS0=3\n' "$DEAD" "$WORKER_LOG_DIR/worker-review-1394.log" > "$INFLIGHT_DIR/1394"
reap_finished_locks; block_noop_workers
if grep -qx "move PVTI_1394 Blocked" "$TMP/writes" \
   && grep -q "thiếu antigravity-pm" "$TMP/writes" \
   && grep -q "blocked-by:  agent" "$TMP/writes"; then
  ok "D2: worker commented missing MCP + blocked-by: - -> Blocked at once with 'thiếu antigravity-pm'"
else
  fail "D2: commented missing MCP stalled/wrong (writes=$(tr '\n' ';' < "$TMP/writes"))"
fi

# D3: worker log plain text không comment, chỉ có dòng prompt: nhắc antigravity-pm → KHÔNG bị nhận nhầm là thiếu MCP
reset_run; set_card 1399 Review
COUNT=3; LAST_COMMENT=""
printf '=== dispatch lane=review issue=#1399 ===\nprompt: Run super-review ... antigravity-pm MCP ...\nworker exited without doing anything\nworker_exit: exit=0 signal=none elapsed=10s\n' > "$WORKER_LOG_DIR/worker-review-1399.log"
printf 'PID=%s\nLANE=review\nSTARTED=2026-11-20T10:00:00Z\nWORKER_LOG=%s\nFROM_COL=Review\nCOMMENTS0=3\n' "$DEAD" "$WORKER_LOG_DIR/worker-review-1399.log" > "$INFLIGHT_DIR/1399"
reap_finished_locks; block_noop_workers
if ! grep -q "thiếu antigravity-pm" "$TMP/writes" && ! grep -q "Antigravity chưa mở" "$TMP/writes"; then
  ok "D3: prompt: line mentioning antigravity-pm is ignored (no false positive)"
else
  fail "D3: prompt line falsely matched (writes=$(tr '\n' ';' < "$TMP/writes"))"
fi

# D4: worker thoát 0 không comment vì Khong thay tien trinh Antigravity language_server → Blocked 'Antigravity chưa mở'
reset_run; set_card 1394 Review
COUNT=3; LAST_COMMENT=""
printf '=== dispatch lane=review issue=#1394 ===\n{"type":"result","subtype":"success","is_error":false,"result":"pm_dispatch loi: Khong thay tien trinh Antigravity language_server nao dang chay."}\nworker_exit: exit=0 signal=none elapsed=30s\n' > "$WORKER_LOG_DIR/worker-review-1394.log"
printf 'PID=%s\nLANE=review\nSTARTED=2026-11-20T10:00:00Z\nWORKER_LOG=%s\nFROM_COL=Review\nCOMMENTS0=3\n' "$DEAD" "$WORKER_LOG_DIR/worker-review-1394.log" > "$INFLIGHT_DIR/1394"
reap_finished_locks; block_noop_workers
if grep -qx "move PVTI_1394 Blocked" "$TMP/writes" \
   && grep -q "Antigravity chưa mở" "$TMP/writes" \
   && grep -q "blocked-by:  agent" "$TMP/writes"; then
  ok "D4: worker exit 0 no comment because language_server down -> Blocked 'Antigravity chưa mở'"
else
  fail "D4: wrong block handling for language_server down (writes=$(tr '\n' ';' < "$TMP/writes"))"
fi

# ── E: sweep_antigravity_blocked — thẻ Blocked cũ và mới tự về Review khi Antigravity nối lại
reset_run
PROJECT_ITEMS_JSON='{"items":[
  {"id":"PVTI_1395","status":"Blocked","labels":[],"content":{"type":"Issue","number":1395,"title":"old blocked","assignees":[]}},
  {"id":"PVTI_1396","status":"Blocked","labels":[],"content":{"type":"Issue","number":1396,"title":"new blocked","assignees":[]}},
  {"id":"PVTI_1397","status":"Blocked","labels":[],"content":{"type":"Issue","number":1397,"title":"secret blocked","assignees":[]}}
]}'
cat > "$TMP/issue-1395.json" <<'JSON'
{"comments":[
  {"body":"[reviewer] [report] chưa duyệt\nPhiên này không có MCP antigravity-pm.\nblocked-by: -"},
  {"body":"[orchestrator] [blocker] 🛑 blocked · ❓ review worker exited 2 times\nWhy blocked: the reviewer for #1395 ended its turn waiting on a person (blocked-by: -)\nMove back:   drag this card to Review after the steps above are done\nblocked-by:  -"}
]}
JSON
cat > "$TMP/issue-1396.json" <<'JSON'
{"comments":[
  {"body":"[orchestrator] [blocker] 🛑 blocked · ❓ Antigravity chưa mở\nMove back:   drag this card to Review after the steps above are done\n<!-- sb-blocked-reason: antigravity-closed -->\nblocked-by:  agent"}
]}
JSON
cat > "$TMP/issue-1397.json" <<'JSON'
{"comments":[
  {"body":"[builder] [blocker] 🛑 blocked · 🔐 missing OPENAI_API_KEY\nReason tag:  🔐\nMove back:   drag this card to Ready after the steps above are done\nblocked-by:  -"}
]}
JSON
mkdir -p "$INFLIGHT_DIR/noops" "$INFLIGHT_DIR/review-stall" "$INFLIGHT_DIR/review-wait"
echo "1" > "$INFLIGHT_DIR/noops/1395"
echo "1" > "$INFLIGHT_DIR/review-stall/1395"

export SB_ANTIGRAVITY_PM_MCP="$TMP/fake-pm-mcp.js"
export SB_ANTIGRAVITY_PROBE="$TMP/probe-fail.sh"
export SB_ANTIGRAVITY_SWEEP_EVERY=0
sweep_antigravity_blocked
rc_down=$?
if [ "$rc_down" -ne 0 ] && ! grep -q "^move " "$TMP/writes"; then
  ok "E1: sweep keeps cards Blocked while Antigravity is still down"
else
  fail "E1: sweep moved cards while Antigravity down (rc=$rc_down writes=$(tr '\n' ';' < "$TMP/writes"))"
fi

export SB_ANTIGRAVITY_PROBE="$TMP/probe-ok.sh"
sweep_antigravity_blocked
rc_up=$?
if [ "$rc_up" -eq 0 ] \
   && grep -qx "move PVTI_1395 Review" "$TMP/writes" \
   && grep -qx "move PVTI_1396 Review" "$TMP/writes" \
   && ! grep -q "PVTI_1397" "$TMP/writes" \
   && [ ! -e "$INFLIGHT_DIR/noops/1395" ] \
   && [ ! -e "$INFLIGHT_DIR/review-stall/1395" ]; then
  ok "E2: sweep returns old (#1395) and new (#1396) Antigravity-blocked cards to Review once connected; leaves #1397 Blocked"
else
  fail "E2: sweep failed (rc=$rc_up writes=$(tr '\n' ';' < "$TMP/writes"))"
fi

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; } || { echo "FAIL ($FAILS)"; exit 1; }
