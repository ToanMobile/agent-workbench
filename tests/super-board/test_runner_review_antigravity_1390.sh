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

mkdir -p "$TMP/bin" "$TMP/path" "$TMP/home/.gemini/config" "$TMP/home/.local/bin" "$TMP/repo/docs/super-board" "$TMP/repo/wl" "$TMP/profile_no_mcp" "$TMP/profile_with_mcp" "$TMP/profile_broken_mcp" "$TMP/broken_mcp/sub" "$TMP/node_modules/@modelcontextprotocol/sdk"
echo '{}' > "$TMP/profile_no_mcp/.claude.json"
printf '{"mcpServers":{"antigravity-pm":{"type":"stdio","command":"node","args":["%s/fake-pm-mcp.js"]}}}\n' "$TMP" > "$TMP/profile_with_mcp/.claude.json"
printf '{"mcpServers":{"antigravity-pm":{"type":"stdio","command":"node","args":["%s/broken_mcp/sub/antigravity-pm-mcp.js"]}}}\n' "$TMP" > "$TMP/profile_broken_mcp/.claude.json"
printf '// fake mcp\n' > "$TMP/fake-pm-mcp.js"
printf '// broken mcp without node_modules\n' > "$TMP/broken_mcp/sub/antigravity-pm-mcp.js"
echo '{"mcpServers":{}}' > "$TMP/home/.gemini/config/mcp_config.json"

cat > "$TMP/home/.local/bin/agy" <<'SH'
#!/usr/bin/env bash
echo $$ >> "$STUB_DIR/stub-pids"
printf '%s\n' "$*" >> "$STUB_DIR/agy-args"
exec sleep 300
SH
chmod +x "$TMP/home/.local/bin/agy"

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

export HOME="$TMP/home" STUB_DIR="$TMP" PATH="$TMP/path:$PATH" WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0
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
  : > "$TMP/log"; : > "$TMP/writes"; : > "$TMP/claude-args"; : > "$TMP/agy-args"
  echo '{"mcpServers":{}}' > "$TMP/home/.gemini/config/mcp_config.json"
  rm -f "$TMP/home/.gemini/settings.json" "$TMP/home/.claude.json"
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
for _ in $(seq 1 50); do [ -s "$TMP/claude-args" ] && break; sleep 0.1; done
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
for _ in $(seq 1 50); do [ -s "$TMP/claude-args" ] && break; sleep 0.1; done
if [ -s "$TMP/claude-args" ] && ! grep -q -- "--mcp-config " "$TMP/claude-args"; then
  ok "C3: profile already having antigravity-pm does not get redundant --mcp-config"
else
  fail "C3: unexpected --mcp-config for profile with antigravity-pm (args=$(cat "$TMP/claude-args"))"
fi

# C4: review_mcp_args khi không có INFLIGHT_DIR tạo hai file tạm riêng biệt, không dính chuỗi literal XXXXXX trên macOS
reset_run
export SB_ANTIGRAVITY_PM_MCP="$TMP/fake-pm-mcp.js"
saved_inflight="$INFLIGHT_DIR"
INFLIGHT_DIR=""
review_mcp_args "$TMP/profile_no_mcp"; mcp_a="${MCP_ARGS[1]:-}"
review_mcp_args "$TMP/profile_no_mcp"; mcp_b="${MCP_ARGS[1]:-}"
INFLIGHT_DIR="$saved_inflight"
if [ -n "$mcp_a" ] && [ -n "$mcp_b" ] && [ "$mcp_a" != "$mcp_b" ] \
   && [ -f "$mcp_a" ] && [ -f "$mcp_b" ] \
   && ! printf '%s\n%s\n' "$mcp_a" "$mcp_b" | grep -q 'XXXXXX'; then
  ok "C4: review_mcp_args fallback mktemp creates distinct randomized files"
else
  fail "C4: review_mcp_args mktemp failed or reused literal template (a=$mcp_a b=$mcp_b)"
fi
rm -f "$mcp_a" "$mcp_b" 2>/dev/null || true

# C5: review_mcp_args nhánh fallback mktemp phải xoá $cfg_file khi jq hoặc mv lỗi
reset_run
export SB_ANTIGRAVITY_PM_MCP="$TMP/fake-pm-mcp.js"
saved_inflight="$INFLIGHT_DIR"; saved_tmpdir="${TMPDIR:-}"
mkdir -p "$TMP/r3_tmp"
INFLIGHT_DIR=""; export TMPDIR="$TMP/r3_tmp"
jq() { return 1; }
review_mcp_args "$TMP/profile_no_mcp"
unset -f jq
mv() { return 1; }
review_mcp_args "$TMP/profile_no_mcp"
unset -f mv
INFLIGHT_DIR="$saved_inflight"
if [ -n "$saved_tmpdir" ]; then export TMPDIR="$saved_tmpdir"; else unset TMPDIR; fi
leftover_c5=$(find "$TMP/r3_tmp" -maxdepth 1 -name 'sb-ag-mcp.*' 2>/dev/null)
if [ "${#MCP_ARGS[@]}" -eq 0 ] && [ -z "$leftover_c5" ]; then
  ok "C5: review_mcp_args fallback mktemp cleans up cfg_file when jq or mv fails"
else
  fail "C5: review_mcp_args leaked temp file on jq/mv failure ($leftover_c5)"
fi

# C6 (R4): antigravity_probe fallback dưới set -euo pipefail không bị SIGPIPE (rc=141) khi ps khớp sớm và xuất nhiều dòng
reset_run
mkdir -p "$TMP/ps_stub"
cat > "$TMP/ps_stub/ps" <<'SH'
#!/usr/bin/env bash
printf '/Applications/Antigravity.app/Contents/Resources/app/bin/language_server_macos_arm --standalone\n'
i=0
while [ "$i" -lt 2500 ]; do
  printf '/usr/libexec/dummy-process --arg=0123456789abcdef0123456789abcdef0123456789abcdef\n'
  i=$((i + 1))
done
SH
chmod +x "$TMP/ps_stub/ps"
export SB_ANTIGRAVITY_PM_MCP="$TMP/does-not-exist.js"
c6_rc=0
(
  set -euo pipefail
  PATH="$TMP/ps_stub:$PATH"
  antigravity_probe >/dev/null 2>&1
) || c6_rc=$?
if [ "$c6_rc" -eq 0 ]; then
  ok "C6: antigravity_probe fallback succeeds without SIGPIPE under set -euo pipefail"
else
  fail "C6: antigravity_probe fallback failed under set -euo pipefail (rc=$c6_rc)"
fi

# C7 (R5.1): review_needs_antigravity trả 0 khi worker_backend == "workflow" ngay cả khi PR chỉ sửa src
reset_run
echo '{"worker_backend":"workflow","merge_queue":{"enabled":true}}' > "$CONFIG_PATH"
printf '[{"number":98,"headRefName":"issue-1398-src-only","headRefOid":"%s","closingIssuesReferences":[{"number":1398}],"labels":[],"isDraft":false}]' "$SHA_SRC" > "$TMP/prs.json"
if review_needs_antigravity 1398; then
  ok "C7: review_needs_antigravity returns 0 when worker_backend is workflow"
else
  fail "C7: review_needs_antigravity ignored worker_backend=workflow"
fi

# C8 (R5.2): review_needs_antigravity nhận diện PR không mang tiền tố nhánh issue-<N>- qua closingIssuesReferences
reset_run
git checkout -q main
git checkout -q -b fix-custom-test-edit
printf '#!/usr/bin/env bash\necho custom\n' > tests/test_demo.sh
git commit -aq -m "custom branch edit test"
SHA_CUSTOM=$(git rev-parse HEAD)
git checkout -q main
printf '[{"number":199,"headRefName":"fix-custom-test-edit","headRefOid":"%s","closingIssuesReferences":[{"number":1499}],"labels":[],"isDraft":false}]' "$SHA_CUSTOM" > "$TMP/prs.json"
if review_needs_antigravity 1499; then
  ok "C8: review_needs_antigravity finds PR via closingIssuesReferences when branch lacks issue-<N>- prefix"
else
  fail "C8: review_needs_antigravity missed PR linked via closingIssuesReferences"
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

# D5: phiên review gọi ToolSearch nạp antigravity-pm bình thường và duyệt vào merge-queue → KHÔNG bị đẩy sang Blocked
reset_run; set_card 1394 Review
COUNT=4; LAST_COMMENT=$'[reviewer] [report] ✅ merge-ready · queued PR #94 @ deadbeef'
printf '=== dispatch lane=review issue=#1394 ===\n{"type":"assistant","message":{"content":[{"type":"text","text":"Đang gọi ToolSearch để nạp antigravity-pm."}]}}\n{"type":"result","subtype":"success","is_error":false,"result":"Đã duyệt và gắn nhãn merge-queue."}\nworker_exit: exit=0 signal=none elapsed=25s\n' > "$WORKER_LOG_DIR/worker-review-1394.log"
printf 'PID=%s\nLANE=review\nSTARTED=2026-11-20T10:00:00Z\nWORKER_LOG=%s\nFROM_COL=Review\nCOMMENTS0=3\n' "$DEAD" "$WORKER_LOG_DIR/worker-review-1394.log" > "$INFLIGHT_DIR/1394"
(
  review_approved_head() { [ "$1" = "1394" ] && return 0; return 1; }
  reap_finished_locks; block_noop_workers
)
if ! grep -q "move PVTI_1394" "$TMP/writes" && ! grep -q "thiếu antigravity-pm" "$TMP/writes"; then
  ok "D5: normal ToolSearch load + queued review is not misclassified as missing MCP"
else
  fail "D5: normal ToolSearch/queued review was falsely blocked (writes=$(tr '\n' ';' < "$TMP/writes"))"
fi

# D6: block_noop_workers không truyền $last_body cũ vào review_antigravity_failure_reason khi $count <= $c0
reset_run; set_card 1394 Review
COUNT=3
LAST_COMMENT=$'[orchestrator] [blocker] 🛑 blocked · ❓ Antigravity chưa mở\n<!-- sb-blocked-reason: antigravity-closed -->\nblocked-by:  agent'
printf '=== dispatch lane=review issue=#1394 ===\n{"type":"result","subtype":"success","is_error":false,"result":"worker exited without doing anything"}\nworker_exit: exit=0 signal=none elapsed=15s\n' > "$WORKER_LOG_DIR/worker-review-1394.log"
printf 'PID=%s\nLANE=review\nSTARTED=2026-11-20T10:00:00Z\nWORKER_LOG=%s\nFROM_COL=Review\nCOMMENTS0=3\n' "$DEAD" "$WORKER_LOG_DIR/worker-review-1394.log" > "$INFLIGHT_DIR/1394"
reap_finished_locks 2>"$TMP/d6.err"; block_noop_workers 2>>"$TMP/d6.err"
if ! grep -q "move PVTI_1394 Blocked" "$TMP/writes" && ! grep -q "Antigravity chưa mở" "$TMP/writes" \
   && ! grep -q "command not found" "$TMP/d6.err"; then
  ok "D6: stale Antigravity blocker comment is not re-matched when worker posted no new comment (count <= c0)"
else
  fail "D6: stale last_body falsely triggered ag_fail when count <= c0 (err=$(tr '\n' ';' < "$TMP/d6.err") writes=$(tr '\n' ';' < "$TMP/writes"))"
fi

# D7: review_antigravity_failure_reason khớp thứ tự tiếng Việt "ToolSearch không tìm thấy antigravity-pm" (và không bắt nhầm ca bình thường)
reset_run; set_card 1394 Review
COUNT=3; LAST_COMMENT=""
printf '=== dispatch lane=review issue=#1394 ===\n{"type":"result","subtype":"success","is_error":false,"result":"ToolSearch không tìm thấy antigravity-pm trong phiên này."}\nworker_exit: exit=0 signal=none elapsed=20s\n' > "$WORKER_LOG_DIR/worker-review-1394.log"
printf 'PID=%s\nLANE=review\nSTARTED=2026-11-20T10:00:00Z\nWORKER_LOG=%s\nFROM_COL=Review\nCOMMENTS0=3\n' "$DEAD" "$WORKER_LOG_DIR/worker-review-1394.log" > "$INFLIGHT_DIR/1394"
reap_finished_locks 2>"$TMP/d7.err"; block_noop_workers 2>>"$TMP/d7.err"
d7_ok_msg=$(review_antigravity_failure_reason "" "ToolSearch tìm thấy và nạp antigravity-pm thành công.")
if grep -qx "move PVTI_1394 Blocked" "$TMP/writes" \
   && grep -q "thiếu antigravity-pm" "$TMP/writes" \
   && grep -q "blocked-by:  agent" "$TMP/writes" \
   && [ -z "$d7_ok_msg" ] \
   && ! grep -q "command not found" "$TMP/d7.err"; then
  ok "D7: matches Vietnamese order 'ToolSearch không tìm thấy antigravity-pm' without false positive"
else
  fail "D7: Vietnamese ToolSearch order missed or false positive (d7_ok_msg=$d7_ok_msg err=$(tr '\n' ';' < "$TMP/d7.err") writes=$(tr '\n' ';' < "$TMP/writes"))"
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

# E3: Thẻ đã có '↩️ back to Review' sau blocker Antigravity gần nhất (chưa có blocker mới) → không sweep lại lần 2
reset_run
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_1400","status":"Blocked","labels":[],"content":{"type":"Issue","number":1400,"title":"already swept","assignees":[]}}]}'
cat > "$TMP/issue-1400.json" <<'JSON'
{"comments":[
  {"body":"[orchestrator] [blocker] 🛑 blocked · ❓ Antigravity chưa mở\n<!-- sb-blocked-reason: antigravity-closed -->\nblocked-by:  agent"},
  {"body":"[orchestrator] [report] ↩️ back to Review · Antigravity đã nối lại"}
]}
JSON
export SB_ANTIGRAVITY_PM_MCP="$TMP/fake-pm-mcp.js"
export SB_ANTIGRAVITY_PROBE="$TMP/probe-ok.sh"
export SB_ANTIGRAVITY_SWEEP_EVERY=0
sweep_antigravity_blocked
rc_e3=$?
if [ "$rc_e3" -ne 0 ] && ! grep -q "PVTI_1400" "$TMP/writes"; then
  ok "E3: sweep does not re-move a card already followed by '↩️ back to Review'"
else
  fail "E3: sweep re-moved already-swept #1400 (rc=$rc_e3 writes=$(tr '\n' ';' < "$TMP/writes"))"
fi

# E4: AG_NON_AG_CARDS phải tự hết hiệu lực khi thẻ rời cột Blocked rồi về Blocked lại vì Antigravity
reset_run
export SB_ANTIGRAVITY_PM_MCP="$TMP/fake-pm-mcp.js"
export SB_ANTIGRAVITY_PROBE="$TMP/probe-ok.sh"
export SB_ANTIGRAVITY_SWEEP_EVERY=0
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_1401","status":"Blocked","labels":[],"content":{"type":"Issue","number":1401,"title":"re-blocked later","assignees":[]}}]}'
cat > "$TMP/issue-1401.json" <<'JSON'
{"comments":[
  {"body":"[builder] [blocker] 🛑 blocked · 🔐 missing KEY\nReason tag:  🔐\nMove back:   drag this card to Ready\nblocked-by:  -"}
]}
JSON
sweep_antigravity_blocked || true
# Thẻ rời Blocked (sang Review) ở tick tiếp theo
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_1401","status":"Review","labels":[],"content":{"type":"Issue","number":1401,"title":"re-blocked later","assignees":[]}}]}'
sweep_antigravity_blocked || true
# Sau đó bị Blocked lại vì Antigravity đóng
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_1401","status":"Blocked","labels":[],"content":{"type":"Issue","number":1401,"title":"re-blocked later","assignees":[]}}]}'
cat > "$TMP/issue-1401.json" <<'JSON'
{"comments":[
  {"body":"[builder] [blocker] 🛑 blocked · 🔐 missing KEY\nReason tag:  🔐\nMove back:   drag this card to Ready\nblocked-by:  -"},
  {"body":"[orchestrator] [blocker] 🛑 blocked · ❓ Antigravity chưa mở\n<!-- sb-blocked-reason: antigravity-closed -->\nblocked-by:  agent"}
]}
JSON
: > "$TMP/writes"
sweep_antigravity_blocked
rc_e4=$?
if [ "$rc_e4" -eq 0 ] && grep -qx "move PVTI_1401 Review" "$TMP/writes"; then
  ok "E4: AG_NON_AG_CARDS is invalidated after card leaves Blocked so later Antigravity block still sweeps"
else
  fail "E4: stale AG_NON_AG_CARDS prevented sweep of re-blocked #1401 (rc=$rc_e4 writes=$(tr '\n' ';' < "$TMP/writes"))"
fi

# ── B2/B3 (R11): POOL_ENGINE=antigravity (agy) kiểm tra cấu hình MCP của agy trước khi dispatch
reset_run; set_card 1392 Review
resolve_worker_account() { POOL_ENGINE="antigravity"; POOL_ACCT="antigravity"; POOL_CFG="$TMP/home/.gemini/antigravity"; return 0; }
export SB_REVIEW_ANTIGRAVITY=1
export SB_ANTIGRAVITY_PM_MCP="$TMP/fake-pm-mcp.js"
export SB_ANTIGRAVITY_PROBE="$TMP/probe-ok.sh"
dispatch_lane review 1392
if [ ! -e wl/worker-review-1392.log ] && [ ! -e "$INFLIGHT_DIR/1392" ] \
   && grep -qx "move PVTI_1392 Blocked" "$TMP/writes" \
   && grep -q "thiếu antigravity-pm" "$TMP/writes" \
   && grep -q "sb-blocked-reason: antigravity-missing-mcp" "$TMP/writes" \
   && grep -q "blocked-by:  agent" "$TMP/writes"; then
  ok "B2 (R11): POOL_ENGINE=antigravity without antigravity-pm in agy MCP config blocks before spawning agy"
else
  fail "B2 (R11): POOL_ENGINE=antigravity was not blocked when agy lacks antigravity-pm (wlog=$([ -e wl/worker-review-1392.log ] && echo y || echo n) writes=$(tr '\n' ';' < "$TMP/writes"))"
fi

reset_run; set_card 1398 Review
resolve_worker_account() { POOL_ENGINE="antigravity"; POOL_ACCT="antigravity"; POOL_CFG="$TMP/home/.gemini/antigravity"; return 0; }
printf '{"mcpServers":{"antigravity-pm":{"command":"node","args":["%s/fake-pm-mcp.js"]}}}\n' "$TMP" > "$TMP/home/.gemini/config/mcp_config.json"
export SB_REVIEW_ANTIGRAVITY=1
export SB_ANTIGRAVITY_PROBE="$TMP/probe-ok.sh"
printf '[{"number":98,"headRefName":"issue-1398-src-only","headRefOid":"%s","labels":[],"isDraft":false}]' "$SHA_SRC" > "$TMP/prs.json"
dispatch_lane review 1398
for _ in $(seq 1 50); do [ -s "$TMP/agy-args" ] && break; sleep 0.1; done
if [ -s "$TMP/agy-args" ] && ! grep -q "move PVTI_1398 Blocked" "$TMP/writes"; then
  ok "B3 (R11): POOL_ENGINE=antigravity with runnable antigravity-pm in ~/.gemini/config/mcp_config.json dispatches agy"
else
  fail "B3 (R11): POOL_ENGINE=antigravity with valid MCP config failed to dispatch (agy=$(cat "$TMP/agy-args") writes=$(tr '\n' ';' < "$TMP/writes"))"
fi

reset_run; set_card 1392 Review
resolve_worker_account() { POOL_ENGINE="antigravity"; POOL_ACCT="antigravity"; POOL_CFG="$TMP/home/.gemini/antigravity"; return 0; }
printf '{"mcpServers":{"antigravity-pm":{"command":"node","args":["%s/broken_mcp/sub/antigravity-pm-mcp.js"]}}}\n' "$TMP" > "$TMP/home/.gemini/config/mcp_config.json"
export SB_REVIEW_ANTIGRAVITY=1
export SB_ANTIGRAVITY_PROBE="$TMP/probe-ok.sh"
dispatch_lane review 1392
if [ ! -e wl/worker-review-1392.log ] && grep -qx "move PVTI_1392 Blocked" "$TMP/writes" && grep -q "thiếu antigravity-pm" "$TMP/writes"; then
  ok "B4 (R11+R9): POOL_ENGINE=antigravity with broken node_modules path in mcp_config.json blocks before spawning agy"
else
  fail "B4 (R11+R9): POOL_ENGINE=antigravity accepted broken MCP path (wlog=$([ -e wl/worker-review-1392.log ] && echo y || echo n) writes=$(tr '\n' ';' < "$TMP/writes"))"
fi

# ── C9 (R9): profile_has_antigravity_pm kiểm tra antigravity_pm_mcp_runnable cho args[0]
reset_run; set_card 1398 Review
resolve_worker_account() { POOL_ENGINE="claude"; POOL_ACCT="finos"; POOL_CFG="$TMP/profile_broken_mcp"; return 0; }
printf '{"mcpServers":{"antigravity-pm":{"type":"stdio","command":"node","args":["%s/fake-pm-mcp.js"]}}}\n' "$TMP" > "$TMP/home/.claude.json"
printf '[{"number":98,"headRefName":"issue-1398-src-only","headRefOid":"%s","labels":[],"isDraft":false}]' "$SHA_SRC" > "$TMP/prs.json"
if ! profile_has_antigravity_pm "$TMP/profile_broken_mcp"; then
  dispatch_lane review 1398
  for _ in $(seq 1 50); do [ -s "$TMP/claude-args" ] && break; sleep 0.1; done
  c9_mcp=$(sed -n 's/.*--mcp-config \([^ ]*\).*/\1/p' "$TMP/claude-args" | head -1)
  if [ -n "$c9_mcp" ] && [ -f "$c9_mcp" ] && grep -q "fake-pm-mcp.js" "$c9_mcp"; then
    ok "C9 (R9): broken args[0] in profile fails profile_has_antigravity_pm and injects working --mcp-config"
  else
    fail "C9 (R9): review_mcp_args did not inject working --mcp-config for broken profile (args=$(cat "$TMP/claude-args"))"
  fi
else
  fail "C9 (R9): profile_has_antigravity_pm accepted broken path lacking node_modules"
fi

# ── C10 (R7): review_needs_antigravity coi config thiếu worker_backend là workflow
reset_run
echo '{"merge_queue":{"enabled":true}}' > "$CONFIG_PATH"
printf '[{"number":98,"headRefName":"issue-1398-src-only","headRefOid":"%s","labels":[],"isDraft":false}]' "$SHA_SRC" > "$TMP/prs.json"
if review_needs_antigravity 1398; then
  ok "C10 (R7): review_needs_antigravity treats omitted worker_backend as workflow"
else
  fail "C10 (R7): review_needs_antigravity ignored omitted worker_backend default"
fi

# ── D8 (R12.1): khớp chuỗi bọc backtick `antigravity-pm` và 'MCP server `antigravity-pm`'
reset_run; set_card 1394 Review
COUNT=3; LAST_COMMENT=""
printf '=== dispatch lane=review issue=#1394 ===\naccount_pool: engine=antigravity account=antigravity\nCHƯA XONG — PR #1393 chưa thể vào hàng đợi merge vì phiên review hiện tại thiếu MCP `antigravity-pm`.\nworker_exit: exit=0 signal=none elapsed=20s\n' > "$WORKER_LOG_DIR/worker-review-1394.log"
printf 'PID=%s\nLANE=review\nSTARTED=2026-11-20T10:00:00Z\nWORKER_LOG=%s\nFROM_COL=Review\nCOMMENTS0=3\n' "$DEAD" "$WORKER_LOG_DIR/worker-review-1394.log" > "$INFLIGHT_DIR/1394"
reap_finished_locks; block_noop_workers
d8_c=$(review_antigravity_failure_reason "" $'Phiên này không có MCP server `antigravity-pm` nên chưa gọi được pm_task_create.')
if grep -qx "move PVTI_1394 Blocked" "$TMP/writes" \
   && grep -q "thiếu antigravity-pm" "$TMP/writes" \
   && grep -q "blocked-by:  agent" "$TMP/writes" \
   && [ "$d8_c" = "missing-mcp" ]; then
  ok "D8 (R12.1): matches backtick-wrapped \`antigravity-pm\` and 'MCP server \`antigravity-pm\`'"
else
  fail "D8 (R12.1): missed backtick/MCP-server form (d8_c=$d8_c writes=$(tr '\n' ';' < "$TMP/writes"))"
fi

# ── D9 (R12.2): miễn ag_fail khi có báo cáo bounce [reviewer] [report] ❌ hợp lệ và không bắt nhầm block assistant
reset_run; set_card 1394 Review
COUNT=4
LAST_COMMENT=$'<!-- super-review:report -->\n[reviewer] [report] ❌ bounced · round 6 @ deadbeef\n❌ Not done: R11 (`.claude/bin/super-board-run.sh:2188` thiếu MCP `antigravity-pm`)\nNext: builder'
printf '=== dispatch lane=review issue=#1394 ===\n{"type":"assistant","message":{"content":[{"type":"text","text":"Đang phân tích PR: `antigravity-pm` không có trong config."}]}}\n{"type":"result","subtype":"success","is_error":false,"result":"không duyệt — trả về builder sửa R11."}\nworker_exit: exit=0 signal=none elapsed=25s\n' > "$WORKER_LOG_DIR/worker-review-1394.log"
printf 'PID=%s\nLANE=review\nSTARTED=2026-11-20T10:00:00Z\nWORKER_LOG=%s\nFROM_COL=Review\nCOMMENTS0=3\n' "$DEAD" "$WORKER_LOG_DIR/worker-review-1394.log" > "$INFLIGHT_DIR/1394"
reap_finished_locks; block_noop_workers
d9_moves=$(cat "$TMP/writes")
reset_run; set_card 1394 Review
COUNT=3; LAST_COMMENT=""
printf '=== dispatch lane=review issue=#1394 ===\n{"type":"assistant","message":{"content":[{"type":"text","text":"Đang đọc code PR #1393: antigravity-pm không có trong profile cũ."}]}}\n{"type":"result","subtype":"success","is_error":false,"result":"Chưa duyệt: còn bug ở .claude/bin/super-board-run.sh:2188"}\nworker_exit: exit=0 signal=none elapsed=25s\n' > "$WORKER_LOG_DIR/worker-review-1394.log"
printf 'PID=%s\nLANE=review\nSTARTED=2026-11-20T10:00:00Z\nWORKER_LOG=%s\nFROM_COL=Review\nCOMMENTS0=3\n' "$DEAD" "$WORKER_LOG_DIR/worker-review-1394.log" > "$INFLIGHT_DIR/1394"
reap_finished_locks; block_noop_workers
if printf '%s\n' "$d9_moves" | grep -qx "move PVTI_1394 Ready" \
   && ! printf '%s\n' "$d9_moves" | grep -q "move PVTI_1394 Blocked" \
   && grep -qx "move PVTI_1394 Ready" "$TMP/writes" \
   && ! grep -q "move PVTI_1394 Blocked" "$TMP/writes"; then
  ok "D9 (R12.2): valid ❌ bounce mentioning antigravity-pm and intermediate assistant analysis are not misclassified as missing-mcp"
else
  fail "D9 (R12.2): valid bounce falsely blocked (d9_moves=$(printf '%s' "$d9_moves" | tr '\n' ';') writes=$(tr '\n' ';' < "$TMP/writes"))"
fi

# ── E5 (R13.1): sweep_antigravity_blocked không loại trừ nhầm khi payment/migration chỉ nằm ở Card title hoặc Evidence
reset_run
PROJECT_ITEMS_JSON='{"items":[
  {"id":"PVTI_1402","status":"Blocked","labels":[],"content":{"type":"Issue","number":1402,"title":"fix payment migration","assignees":[]}},
  {"id":"PVTI_1403","status":"Blocked","labels":[],"content":{"type":"Issue","number":1403,"title":"legacy billing card","assignees":[]}}
]}'
cat > "$TMP/issue-1402.json" <<'JSON'
{"comments":[
  {"body":"[reviewer] [report] chưa duyệt\nPhiên này thiếu MCP antigravity-pm.\nblocked-by: -"},
  {"body":"[orchestrator] [blocker] 🛑 blocked · ❓ review worker exited 2 times\nCard:        #1402 fix payment migration\nReason tag:  ❓\nWhy blocked: the reviewer for #1402 ended its turn waiting on a person (blocked-by: -)\nEvidence:    docs/super-board/runs/worker-review-1402.log; last log line: migration test\nMove back:   drag this card to Review after the steps above are done\nblocked-by:  -"}
]}
JSON
cat > "$TMP/issue-1403.json" <<'JSON'
{"comments":[
  {"body":"[reviewer] [report] chưa duyệt\nAntigravity language_server chưa chạy.\nblocked-by: -"},
  {"body":"[orchestrator] [blocker] 🛑 blocked · ❓ review worker exited 2 times\nCard:        #1403 legacy billing card\nReason tag:  ❓\nWhy blocked: the reviewer for #1403 ended its turn waiting on a person\nEvidence:    docs/super-board/runs/worker-review-1403.log; payment webhook timeout\nMove back:   drag this card to Review after the steps above are done\nblocked-by:  -"}
]}
JSON
export SB_ANTIGRAVITY_PM_MCP="$TMP/fake-pm-mcp.js"
export SB_ANTIGRAVITY_PROBE="$TMP/probe-ok.sh"
export SB_ANTIGRAVITY_SWEEP_EVERY=0
sweep_antigravity_blocked
rc_e5=$?
if [ "$rc_e5" -eq 0 ] && grep -qx "move PVTI_1402 Review" "$TMP/writes" && grep -qx "move PVTI_1403 Review" "$TMP/writes"; then
  ok "E5 (R13.1): sweep ignores exclusion keywords inside Card title and Evidence lines"
else
  fail "E5 (R13.1): sweep falsely excluded card by title/Evidence (rc=$rc_e5 writes=$(tr '\n' ';' < "$TMP/writes"))"
fi

# ── E6 (R13.2): sweep_antigravity_blocked không phụ thuộc POOL_CFG/POOL_ENGINE toàn cục còn sót lại
reset_run
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_1404","status":"Blocked","labels":[],"content":{"type":"Issue","number":1404,"title":"stale pool cfg","assignees":[]}}]}'
cat > "$TMP/issue-1404.json" <<'JSON'
{"comments":[
  {"body":"[orchestrator] [blocker] 🛑 blocked · ❓ thiếu antigravity-pm cho phiên review\nMove back:   drag this card to Review\n<!-- sb-blocked-reason: antigravity-missing-mcp -->\nblocked-by:  agent"}
]}
JSON
POOL_CFG="$TMP/nonexistent_stale_profile"
POOL_ENGINE="antigravity"
resolve_worker_account() { POOL_ENGINE="claude"; POOL_ACCT="finos"; POOL_CFG="$TMP/profile_with_mcp"; return 0; }
export SB_ANTIGRAVITY_PROBE="$TMP/probe-ok.sh"
export SB_ANTIGRAVITY_SWEEP_EVERY=0
sweep_antigravity_blocked
rc_e6a=$?
e6a_writes=$(cat "$TMP/writes")
reset_run
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_1404","status":"Blocked","labels":[],"content":{"type":"Issue","number":1404,"title":"agy missing mcp","assignees":[]}}]}'
cat > "$TMP/issue-1404.json" <<'JSON'
{"comments":[
  {"body":"[orchestrator] [blocker] 🛑 blocked · ❓ thiếu antigravity-pm cho phiên review\nMove back:   drag this card to Review\n<!-- sb-blocked-reason: antigravity-missing-mcp -->\nblocked-by:  agent"}
]}
JSON
POOL_CFG="$TMP/profile_with_mcp"
POOL_ENGINE="claude"
resolve_worker_account() { POOL_ENGINE="antigravity"; POOL_ACCT="antigravity"; POOL_CFG="$TMP/home/.gemini/antigravity"; return 0; }
export SB_ANTIGRAVITY_PROBE="$TMP/probe-ok.sh"
export SB_ANTIGRAVITY_SWEEP_EVERY=0
sweep_antigravity_blocked
rc_e6b=$?
if [ "$rc_e6a" -eq 0 ] && printf '%s\n' "$e6a_writes" | grep -qx "move PVTI_1404 Review" \
   && [ "$rc_e6b" -ne 0 ] && ! grep -q "PVTI_1404" "$TMP/writes"; then
  ok "E6 (R13.2): sweep probes MCP independently of stale global POOL_CFG/POOL_ENGINE"
else
  fail "E6 (R13.2): sweep depended on stale POOL_CFG/POOL_ENGINE (rc_e6a=$rc_e6a e6a=$(printf '%s' "$e6a_writes" | tr '\n' ';') rc_e6b=$rc_e6b writes=$(tr '\n' ';' < "$TMP/writes"))"
fi

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; } || { echo "FAIL ($FAILS)"; exit 1; }
