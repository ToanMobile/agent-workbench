#!/usr/bin/env bash
# Test #601 (runner): thẻ chỉ chờ thẻ khác (preflight `sequence` có blocker còn MỞ) ở lại Ready với nhãn `waiting-on:#N`,
# không vào Blocked. Luật ở đây:
#  AC1  preflight sequence blockedBy [9] (#9 mở) → không `move … Blocked`, helper `mark --on 9` được gọi, không spawn, cache có
#       nhãn; mark hỏng (69) → không Blocked, không halt, preflight_gate trả 1 (thử lại tick sau).
#  AC1b top_card_in_column Ready bỏ qua thẻ mang `waiting-on:#N` (mọi hoa/thường, chuỗi hay {name}, ở item hay content), chọn lại
#       khi nhãn gỡ; person_count Ready đếm thẻ chờ; file inflight của preflight không chứa thẻ chờ.
#  AC2  sweep_waiting_on: removed khác rỗng → 0; cadence; helper lỗi → không dời mốc; Done đổi → chạy ngay; board không có
#       thẻ chờ → không gọi helper.
#  AC3  preflight hold/unclear vẫn `move … Blocked`, không gọi mark; rebuild_cap → Blocked qua test_merge_queue.sh (PASS).
#  AC4  sau mark, thẻ mang nhãn không được top_card_in_column chọn lại → preflight không chạy lần 2 cho cùng blocker.
#  AC5  startup_migrate_waiting chỉ được luồng chính gọi (sau chốt SB_LIB_ONLY); chạy thật với helper stub: --items + INFLIGHT_DIR,
#       migrated khác rỗng → đọc lại board, rỗng → không, helper lỗi → log, không exit.
#  Audit: mark trả labels=[] → preflight_gate 0 (giao); cache lấy nhãn mark trả về; sweep truyền board qua --items.
# Chạy offline: runner source ở lib mode, gh/claude/preflight/helper là stub. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-waiting-on-runner.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/path" "$TMP/repo/docs/super-board/runs" "$TMP/repo/wl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/super-board-github-read.py"
printf 'print("ok")\n' > "$TMP/bin/super-board-skills-ready.py"
cp "$ROOT/.claude/bin/super-board-blocked-by.py" "$TMP/bin/"
# gh stub cho super-board-blocked-by.py: #8 đã đóng, còn lại mở
cat > "$TMP/path/gh" <<'SH'
#!/bin/sh
case "$3" in
  8) echo "CLOSED https://github.com/acme/widgets/issues/8" ;;
  *) echo "OPEN https://github.com/acme/widgets/issues/$3" ;;
esac
SH
# preflight stub: in $STUB_PREFLIGHT_JSON, chép file --inflight nó nhận được ra $STUB_DIR/inflight-seen
cat > "$TMP/bin/super-board-preflight.sh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$STUB_DIR/preflight-calls"
while [ $# -gt 0 ]; do [ "$1" = --inflight ] && cp "$2" "$STUB_DIR/inflight-seen"; shift; done
printf '%s\n' "${STUB_PREFLIGHT_JSON:-}"
exit "${STUB_PREFLIGHT_RC:-0}"
SH
# helper stub (L1 viết helper thật): ghi lời gọi, in $STUB_WO_OUT, exit $STUB_WO_RC
cat > "$TMP/bin/super-board-waiting-on.py" <<'PY'
import os, shutil, sys
with open(os.path.join(os.environ["STUB_DIR"], "wo-calls"), "a") as f:
    f.write(" ".join(sys.argv[1:]) + "\n")
with open(os.path.join(os.environ["STUB_DIR"], "wo-env"), "a") as f:
    f.write(os.environ.get("INFLIGHT_DIR", "") + "\n")
if "--items" in sys.argv:   # chép file board runner truyền vào (runner xoá nó sau lời gọi)
    shutil.copy(sys.argv[sys.argv.index("--items") + 1], os.path.join(os.environ["STUB_DIR"], "items-seen"))
print(os.environ.get("STUB_WO_OUT", ""))
sys.exit(int(os.environ.get("STUB_WO_RC", "0")))
PY
cat > "$TMP/path/claude" <<'SH'
#!/usr/bin/env bash
echo spawned >> "$STUB_DIR/spawned"
SH
chmod +x "$TMP/bin/"* "$TMP/path/claude" "$TMP/path/gh"
ORIG_PATH="$PATH"   # AC3 chạy test_merge_queue.sh với env sạch, không mang stub của test này
export STUB_DIR="$TMP" PATH="$TMP/path:$PATH" WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0

unset SB_GITHUB_READ_STRICT SB_ACCOUNT_POOL SB_WAITING_ON SB_WAITING_SWEEP_EVERY
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
SB_GITHUB_READ="$TMP/bin/super-board-github-read.py"
printf 'import sys\nsys.exit(0)\n' > "$TMP/bin/super-board-needs-you.py"
CONFIG_PATH="$TMP/cfg.json"; echo '{"repo":{"remote":"https://github.com/acme/widgets"}}' > "$CONFIG_PATH"
INFLIGHT_DIR="$TMP/repo/.claude/super-board/inflight"; mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="wl"; REPO_ROOT="$TMP/repo"
BOT_LOGIN="bot"
export SB_GITHUB_HALT_FILE="$TMP/halt.json"
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }
issue_is_open() { return 0; }
issue_locked() { [ -e "$INFLIGHT_DIR/$1" ]; }
early_backoff() { return 1; }
ready_card_held() { return 1; }   # chốt #202 đọc thân issue qua GitHub; test này chỉ kiểm nhãn waiting-on
resolve_worker_account() { POOL_ENGINE=""; POOL_ACCT=""; POOL_CFG=""; return 0; }
note_worker_limit() { :; }
cd "$TMP/repo" || exit 1
BOARD_ONE='{"items":[
 {"id":"PVTI_7","status":"Ready","labels":[],"content":{"type":"Issue","number":7,"title":"card seven","assignees":[]}}]}'
reset() {
  : > "$TMP/writes"; : > "$TMP/log"; rm -f "$TMP/spawned" "$TMP/preflight-calls" "$TMP/wo-calls" "$TMP/wo-env" "$TMP/items-seen" "$TMP/inflight-seen" "$TMP/halt.json" "$TMP/fetches" "$INFLIGHT_DIR"/*
  PROJECT_ITEMS_JSON="$BOARD_ONE"; export STUB_WO_RC=0 STUB_WO_OUT='{"issue":7,"labels":["waiting-on:#9"],"commented":true}'
}
PF="$TMP/bin/super-board-preflight.sh"
labels_of() { printf '%s' "$PROJECT_ITEMS_JSON" | jq -c --argjson n "$1" '[.items[] | select(.content.number == $n) | .labels][0]'; }

# ── AC1. sequence blockedBy [9] (#9 mở) → ở Ready, mark --on 9, không spawn, cache có nhãn
reset
export STUB_PREFLIGHT_RC=0 STUB_PREFLIGHT_JSON='{"7":{"number":7,"verdict":"sequence","tag":"overlap","reason":"overlap PR #52","blockedBy":[9]}}'
SB_PREFLIGHT="$PF" dispatch_lane build 7 >/dev/null 2>&1
sleep 0.3
! grep -q "move PVTI_7 Blocked" "$TMP/writes" && ok "AC1 sequence/open blocker: card NOT moved to Blocked" || fail "AC1 card moved to Blocked: $(cat "$TMP/writes")"
grep -q -- "^mark --config $CONFIG_PATH --issue 7 --on 9 " "$TMP/wo-calls" 2>/dev/null && ok "  … helper mark called with --issue 7 --on 9" \
  || fail "  mark call wrong: $(cat "$TMP/wo-calls" 2>/dev/null)"
grep -q -- "--why=overlap PR #52" "$TMP/wo-calls" 2>/dev/null && ok "  … --why carries the preflight reason" || fail "  --why missing: $(cat "$TMP/wo-calls" 2>/dev/null)"
[ ! -e "$TMP/spawned" ] && [ ! -e "$INFLIGHT_DIR/7" ] && ! grep -q -- "--add-assignee" "$TMP/writes" \
  && ok "  … no claim, no worker" || fail "  card dispatched (writes=$(cat "$TMP/writes"))"
! grep -q "blocked-by:" "$TMP/writes" && ok "  … no block-template comment" || fail "  block comment written: $(cat "$TMP/writes")"
[ "$(labels_of 7)" = '["waiting-on:#9"]' ] && ok "  … cache labels updated: $(labels_of 7)" || fail "  cache labels wrong: $(labels_of 7)"

reset; export STUB_WO_OUT='{"issue":7,"labels":["waiting-on:#9","waiting-on:#10"],"commented":true}'
export STUB_PREFLIGHT_JSON='{"7":{"number":7,"verdict":"sequence","tag":"overlap","reason":"overlap","blockedBy":[8,9,10]}}'
SB_PREFLIGHT="$PF" preflight_gate 7 >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q -- "--issue 7 --on 9,10 " "$TMP/wo-calls" 2>/dev/null && [ "$(labels_of 7)" = '["waiting-on:#10","waiting-on:#9"]' ] \
  && ok "AC1 mixed blockers [8,9,10]: only open 9,10 marked, csv without spaces, both labels cached" \
  || fail "AC1 mixed blockers wrong (rc=$rc calls=$(cat "$TMP/wo-calls" 2>/dev/null) labels=$(labels_of 7))"
# cache lấy nhãn helper TRẢ VỀ (mark tự lọc blocker đã đóng), không phải danh sách runner gửi
reset; export STUB_WO_OUT='{"issue":7,"labels":["waiting-on:#10"],"commented":true}'
SB_PREFLIGHT="$PF" preflight_gate 7 >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && [ "$(labels_of 7)" = '["waiting-on:#10"]' ] && ok "AC1 cache takes the labels mark returned (only #10 still open)" \
  || fail "AC1 cache from mark output wrong (rc=$rc labels=$(labels_of 7))"
# audit 2: mark trả labels=[] (mọi blocker đã đóng khi helper đọc lại) → giao như cũ: return 0, không Blocked, cache không đổi
reset; export STUB_WO_OUT='{"issue":7,"labels":[],"commented":false}'
export STUB_PREFLIGHT_JSON='{"7":{"number":7,"verdict":"sequence","tag":"overlap","reason":"overlap","blockedBy":[9]}}'
SB_PREFLIGHT="$PF" preflight_gate 7 >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ -s "$TMP/wo-calls" ] && [ "$(labels_of 7)" = '[]' ] && ! grep -q "move PVTI_7 Blocked" "$TMP/writes" \
  && ok "audit2 mark returns labels=[] → preflight_gate returns 0 (dispatch), no label cached, not Blocked" \
  || fail "audit2 empty labels: rc=$rc labels=$(labels_of 7) writes=$(cat "$TMP/writes")"
# mark exit 0 nhưng stdout không phải JSON → coi như hỏng: không giao, thử lại tick sau
reset; export STUB_WO_OUT='garbage'
SB_PREFLIGHT="$PF" preflight_gate 7 >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && [ "$(labels_of 7)" = '[]' ] && ok "audit2 mark output unreadable → not dispatched (returns 1)" || fail "audit2 garbage output: rc=$rc"

# mark hỏng (69) → không Blocked, không halt, trả 1, runner sống
reset; export STUB_WO_RC=69 STUB_WO_OUT=''
export STUB_PREFLIGHT_JSON='{"7":{"number":7,"verdict":"sequence","tag":"overlap","reason":"overlap","blockedBy":[9]}}'
( SB_PREFLIGHT="$PF" preflight_gate 7 ) >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && ! grep -q "move PVTI_7 Blocked" "$TMP/writes" && [ ! -e "$TMP/halt.json" ] && [ -s "$TMP/wo-calls" ] \
  && ok "AC1 mark exit 69: not Blocked, no halt, preflight_gate returns 1" || fail "AC1 mark failure handling wrong (rc=$rc writes=$(cat "$TMP/writes") halt=$(ls "$TMP/halt.json" 2>/dev/null))"
( SB_PREFLIGHT="$PF" dispatch_lane build 7 ) >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$INFLIGHT_DIR/7" ] && [ "$(labels_of 7)" = '[]' ] && ok "  … dispatch_lane survives, nothing dispatched, cache unchanged" \
  || fail "  dispatch after mark failure wrong (rc=$rc labels=$(labels_of 7))"

# ── AC3. hold / unclear vẫn vào Blocked, không gọi mark
reset
export STUB_PREFLIGHT_JSON='{"7":{"number":7,"verdict":"hold","tag":"unclear","reason":"no AC","evidence":["issue #7 body"],"blockedBy":[]}}'
SB_PREFLIGHT="$PF" dispatch_lane build 7 >/dev/null 2>&1
grep -q "move PVTI_7 Blocked" "$TMP/writes" && [ ! -e "$TMP/wo-calls" ] && ok "AC3 hold/unclear: still Blocked, mark not called" || fail "AC3 hold/unclear wrong: $(cat "$TMP/writes")"
reset
export STUB_PREFLIGHT_JSON='{"7":{"number":7,"verdict":"hold","tag":"done","reason":"delivered","evidence":["PR #31 merged and closes #7"],"blockedBy":[]}}'
SB_PREFLIGHT="$PF" dispatch_lane build 7 >/dev/null 2>&1
grep -q "move PVTI_7 Blocked" "$TMP/writes" && [ ! -e "$TMP/wo-calls" ] && ok "AC3 hold/done (closes #7): still Blocked" || fail "AC3 hold/done wrong: $(cat "$TMP/writes")"

# ── AC1b. top_card_in_column / person_count / inflight
BOARD_MIX='{"items":[
 {"id":"PVTI_7","status":"Ready","labels":["Waiting-On:#9"],"content":{"type":"Issue","number":7,"title":"seven","assignees":[]}},
 {"id":"PVTI_11","status":"Ready","labels":[],"content":{"type":"Issue","number":11,"title":"eleven","assignees":[],"labels":[{"name":"WAITING-ON:#10"}]}},
 {"id":"PVTI_12","status":"Ready","labels":[{"name":"docs"}],"content":{"type":"Issue","number":12,"title":"twelve","assignees":[]}},
 {"id":"PVTI_13","status":"Ready","labels":["needs-you"],"content":{"type":"Issue","number":13,"title":"thirteen","assignees":[]}},
 {"id":"PVTI_14","status":"Building","labels":[],"content":{"type":"Issue","number":14,"title":"fourteen","assignees":[]}}]}'
reset; PROJECT_ITEMS_JSON="$BOARD_MIX"
top_card_in_column Ready
[ "$TOP_ISSUE" = 12 ] && ok "AC1b Ready skips waiting-on cards (any case, string or {name}, item or content) → #12" || fail "AC1b picked '#$TOP_ISSUE'"
PROJECT_ITEMS_JSON=$(printf '%s' "$BOARD_MIX" | jq -c 'del(.items[] | select(.content.number == 12))')
top_card_in_column Ready; rc=$?
[ "$rc" = 1 ] && [ -z "$TOP_ISSUE" ] && ok "  … only waiting cards left: nothing dispatched" || fail "  waiting card picked: '#$TOP_ISSUE' rc=$rc"
PROJECT_ITEMS_JSON=$(printf '%s' "$BOARD_MIX" | jq -c '(.items[] | select(.content.number == 7) | .labels) = []')
top_card_in_column Ready
[ "$TOP_ISSUE" = 7 ] && ok "  … label removed: #7 dispatchable again" || fail "  #7 not picked after label removal: '#$TOP_ISSUE'"
PROJECT_ITEMS_JSON="$BOARD_MIX"
[ "$(person_count Ready)" = 3 ] && ok "AC1b person_count Ready counts waiting cards (7, 11) + needs-you (13) = 3" || fail "AC1b person_count Ready = $(person_count Ready)"
count_board
[ "$READY" = 1 ] && ok "  … count_board READY = 1 (waiting cards do not keep a run alive)" || fail "  count_board READY = $READY"
export STUB_PREFLIGHT_JSON='{"12":{"number":12,"verdict":"proceed","tag":"clean","reason":"","blockedBy":[]}}'
SB_PREFLIGHT="$PF" preflight_gate 12 >/dev/null 2>&1
seen=$(jq -c '[.[].number] | sort' "$TMP/inflight-seen" 2>/dev/null)
[ "$seen" = '[12,13,14]' ] && ok "AC1b preflight inflight file leaves out waiting Ready cards: $seen" || fail "AC1b inflight file wrong: $seen"

# ── AC4. sau mark, thẻ không được chọn lại → preflight không chạy lần 2 cùng blocker
reset
export STUB_PREFLIGHT_JSON='{"7":{"number":7,"verdict":"sequence","tag":"overlap","reason":"overlap","blockedBy":[9]}}'
for t in 1 2; do
  if top_card_in_column Ready; then SB_PREFLIGHT="$PF" dispatch_lane build "$TOP_ISSUE" >/dev/null 2>&1; fi
done
n_mark=$(grep -c "^mark " "$TMP/wo-calls" 2>/dev/null); n_pf=$(wc -l < "$TMP/preflight-calls" 2>/dev/null | tr -d ' ')
[ "$n_mark" = 1 ] && [ "$n_pf" = 1 ] && ! grep -q "move PVTI_7 Blocked" "$TMP/writes" \
  && ok "AC4 two ticks, same blocker: preflight once, mark once" || fail "AC4 mark=$n_mark preflight=$n_pf writes=$(cat "$TMP/writes")"

# ── AC2. sweep_waiting_on
reset; PROJECT_ITEMS_JSON="$BOARD_MIX"; WAITING_SWEEP_NEXT=0; unset WAITING_SWEEP_SIG
export STUB_WO_OUT='{"removed":[[7,9]],"kept":[[11,10]],"errors":[]}'
sweep_waiting_on; rc=$?
[ "$rc" = 0 ] && grep -q -- "^sweep --config $CONFIG_PATH" "$TMP/wo-calls" && ok "AC2 sweep removed [7,9] → returns 0 (caller re-reads the board)" \
  || fail "AC2 sweep rc=$rc calls=$(cat "$TMP/wo-calls" 2>/dev/null)"
# audit 1: runner truyền board đã có qua --items (không tốn thêm GraphQL), file tạm bị xoá sau lời gọi
itf=$(sed -n 's/.*--items \([^ ]*\).*/\1/p' "$TMP/wo-calls" | head -1)
[ -n "$itf" ] && [ ! -e "$itf" ] && jq -e '[.items[].content.number] == [7,11,12,13,14]' "$TMP/items-seen" >/dev/null 2>&1 \
  && ok "audit1 sweep gets the cached board via --items (temp file removed after)" || fail "audit1 sweep --items: file=[$itf] seen=$(jq -c '[.items[].content.number]' "$TMP/items-seen" 2>/dev/null)"
sweep_waiting_on; rc=$?
[ "$rc" = 1 ] && [ "$(grep -c '^sweep ' "$TMP/wo-calls")" = 1 ] && ok "  … second call right after: cadence holds, helper not called" \
  || fail "  cadence broken (rc=$rc calls=$(grep -c '^sweep ' "$TMP/wo-calls"))"
PROJECT_ITEMS_JSON=$(printf '%s' "$BOARD_MIX" | jq -c '.items += [{"id":"PVTI_5","status":"Done","labels":[],"content":{"type":"Issue","number":5,"assignees":[]}}]')
sweep_waiting_on; rc=$?
[ "$(grep -c '^sweep ' "$TMP/wo-calls")" = 2 ] && ok "  … Done set changed: sweep runs before the cadence" || fail "  Done change did not trigger the sweep"
export STUB_WO_OUT='{"removed":[],"kept":[[11,10]],"errors":[]}'
WAITING_SWEEP_NEXT=0; sweep_waiting_on; rc=$?
[ "$rc" = 1 ] && ok "  … nothing removed → returns 1" || fail "  empty removed returned $rc"
reset; PROJECT_ITEMS_JSON="$BOARD_MIX"; WAITING_SWEEP_NEXT=0; unset WAITING_SWEEP_SIG
export STUB_WO_RC=79 STUB_WO_OUT=''
( sweep_waiting_on ); rc=$?
sweep_waiting_on >/dev/null 2>&1
sweep_waiting_on >/dev/null 2>&1; rc2=$?
[ "$rc" = 1 ] && [ "$rc2" = 1 ] && [ "$(grep -c '^sweep ' "$TMP/wo-calls")" = 3 ] && [ ! -e "$TMP/halt.json" ] \
  && ok "AC2 helper exit 79: runner survives, returns 1, retried next tick (no cadence step)" \
  || fail "AC2 helper failure wrong (rc=$rc rc2=$rc2 calls=$(grep -c '^sweep ' "$TMP/wo-calls" 2>/dev/null))"
reset; PROJECT_ITEMS_JSON="$BOARD_ONE"; WAITING_SWEEP_NEXT=0; unset WAITING_SWEEP_SIG
sweep_waiting_on; rc=$?
[ "$rc" = 1 ] && [ ! -e "$TMP/wo-calls" ] && ok "AC2 no waiting-on card on the board: helper not called" || fail "AC2 helper called on a board with no waiting card"
# review P3: thẻ Done còn sót nhãn waiting-on không mở cổng sweep (helper vốn bỏ qua Done).
reset; WAITING_SWEEP_NEXT=0; unset WAITING_SWEEP_SIG
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_5","status":"Done","labels":["waiting-on:#9"],"content":{"type":"Issue","number":5,"assignees":[]}}]}'
sweep_waiting_on; rc=$?
[ "$rc" = 1 ] && [ ! -e "$TMP/wo-calls" ] && ok "AC2 only a Done card carries waiting-on: helper not called" || fail "AC2 Done card opened the sweep gate"

# ── AC5. migrate lúc khởi động: hàm startup_migrate_waiting, luồng chính gọi nó SAU chốt SB_LIB_ONLY
lib_line=$(grep -n 'SB_LIB_ONLY:-0}" = "1" ]; then' "$RUNNER" | tail -1 | cut -d: -f1)
mig_line=$(grep -n '^startup_migrate_waiting$' "$RUNNER" | head -1 | cut -d: -f1)
[ -n "$mig_line" ] && [ -n "$lib_line" ] && [ "$mig_line" -gt "$lib_line" ] && ok "AC5 startup migrate is called only in the main flow (line $mig_line > lib-only return $lib_line)" \
  || fail "AC5 startup_migrate_waiting call missing or before the lib-only return (call=$mig_line lib=$lib_line)"
[ ! -e "$TMP/wo-calls" ] || ! grep -q "^migrate" "$TMP/wo-calls" && ok "  … sourcing the runner did not run migrate" || fail "  migrate ran while sourcing"
# chạy THẬT nhánh khởi động với helper stub
fetch_project_items() { echo fetch >> "$TMP/fetches"; return 0; }
reset; PROJECT_ITEMS_JSON="$BOARD_MIX"; export STUB_WO_OUT='{"migrated":[40,41],"skipped":[]}'
( startup_migrate_waiting; echo alive > "$TMP/alive" ) >/dev/null 2>&1
grep -q -- "^migrate --config $CONFIG_PATH --items " "$TMP/wo-calls" 2>/dev/null && [ "$(head -1 "$TMP/wo-env")" = "$INFLIGHT_DIR" ] \
  && jq -e '[.items[].content.number] == [7,11,12,13,14]' "$TMP/items-seen" >/dev/null 2>&1 \
  && ok "AC5 startup migrate: helper gets --items (cached board) and INFLIGHT_DIR" || fail "AC5 migrate call: $(cat "$TMP/wo-calls" 2>/dev/null) env=$(cat "$TMP/wo-env" 2>/dev/null)"
[ "$(grep -c fetch "$TMP/fetches" 2>/dev/null)" = 1 ] && grep -q "waiting-on migrate: #40 #41" "$TMP/log" \
  && ok "  … migrated [40,41] → logged, board re-read once" || fail "  migrated: fetches=$(grep -c fetch "$TMP/fetches" 2>/dev/null) log=$(cat "$TMP/log")"
reset; PROJECT_ITEMS_JSON="$BOARD_MIX"; export STUB_WO_OUT='{"migrated":[],"skipped":[{"number":41,"why":"needs-you label"}]}'
( startup_migrate_waiting ) >/dev/null 2>&1
[ -s "$TMP/wo-calls" ] && [ ! -e "$TMP/fetches" ] && ok "  … migrated [] → no board re-read" || fail "  empty migrate re-read the board"
reset; PROJECT_ITEMS_JSON=""; export STUB_WO_OUT='{"migrated":[],"skipped":[]}'
( startup_migrate_waiting ) >/dev/null 2>&1
grep -qx -- "migrate --config $CONFIG_PATH" "$TMP/wo-calls" 2>/dev/null && ok "  … empty board cache → helper reads the board itself (no --items)" \
  || fail "  empty cache call: $(cat "$TMP/wo-calls" 2>/dev/null)"
reset; rm -f "$TMP/alive"; PROJECT_ITEMS_JSON="$BOARD_MIX"; export STUB_WO_RC=79 STUB_WO_OUT=''
( startup_migrate_waiting; echo "rc=$?" > "$TMP/alive" ) >/dev/null 2>&1
[ "$(cat "$TMP/alive" 2>/dev/null)" = "rc=0" ] && [ ! -e "$TMP/fetches" ] && grep -q "waiting-on migrate failed (exit 79)" "$TMP/log" && [ ! -e "$TMP/halt.json" ] \
  && ok "  … helper exit 79 → logged, runner keeps going (no exit, no halt, no re-read)" \
  || fail "  migrate failure: alive=$(cat "$TMP/alive" 2>/dev/null) log=$(cat "$TMP/log")"

# ── AC3 (rebuild_cap). rebuild_cap → Blocked 🛡 nằm ở super-board-merge-queue.sh `rebuild_or_rebase` (#601 không đụng file đó).
# merge-queue.sh không có chế độ lib/source (grep SB_LIB_ONLY trong file đó: 0 dòng, 28/10), nên chạy test sẵn có của nó và đòi
# đúng dòng kiểm "at rebuild_cap → Blocked".
mq_out=$(cd "$ROOT" && env -i HOME="$HOME" PATH="$ORIG_PATH" TMPDIR="${TMPDIR:-/tmp}" bash "$ROOT/tests/super-board/test_merge_queue.sh" 2>&1); mq_rc=$?
# #750: grep đọc here-string, không `printf … | grep -q`: runner source ở trên bật pipefail, grep -q thoát ở dòng khớp khi printf còn ghi
# phần đuôi output thì printf dính EPIPE và cả ca đỏ dù test_merge_queue.sh xanh (chập chờn dưới tải)
[ "$mq_rc" = 0 ] && grep -q "✔ gate-exit-5 at rebuild_cap → Blocked, not Ready" <<<"$mq_out" \
  && ok "AC3 rebuild_cap still goes to Blocked (test_merge_queue.sh PASS, rebuild_cap case green)" \
  || fail "AC3 rebuild_cap: test_merge_queue.sh rc=$mq_rc $(printf '%s\n' "$mq_out" | grep -E '✖|rebuild_cap' | head -3)"

[ "$FAILS" -eq 0 ] && { echo "PASS test_waiting_on_runner"; exit 0; }
echo "FAIL test_waiting_on_runner ($FAILS)"; exit 1
