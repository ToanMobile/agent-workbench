#!/usr/bin/env bash
# Test hồi quy #619: thẻ Ready mang nhãn waiting-on không được kẹt im lặng.
#  A. Một định nghĩa nhãn `waiting-on:#<số>` cho runner (WAITING_ON_JQ), planner (super-board-wave-plan.sh) và helper
#     (super-board-waiting-on.py LABEL_RE): nhãn sai dạng (`waiting-on:#x`, `waiting-on:#`, `waiting-on:#9x`) không làm thẻ bị bỏ
#     qua khi giao — trước đây runner/planner coi mọi nhãn bắt đầu `waiting-on:#` là đang chờ, còn helper sweep không bao giờ gỡ
#     nhãn sai dạng, nên thẻ nằm Ready mãi. Ba nơi phải cho CÙNG một tập "đang chờ" trên cùng bộ nhãn.
#  B. preflight không giao thẻ top (mark hỏng 69) → thẻ Ready kế tiếp vẫn được giao trong CÙNG tick (dispatch_ready_tick);
#     thẻ bị bỏ qua không được giao, không vào Blocked; tối đa 3 thẻ mỗi tick. Bằng chứng giao = file lock inflight/<N> (ghi đồng bộ
#     lúc phóng worker), không dùng file của worker stub nền (ghi muộn, lọt sang ca sau).
# Chạy offline: runner source ở lib mode, gh/claude/preflight/helper là stub. Dùng runner THẬT của checkout chứa test (ROOT từ $0).
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-wo-skip.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# ── A. cùng một tập "đang chờ" ở ba nơi
LABELS='["waiting-on:#9","Waiting-On:#12","waiting-on:#x","waiting-on:#","waiting-on:#9x","waiting-on:12","bug"]'
WANT='["waiting-on:#12","waiting-on:#9"]'   # chỉ dạng #<số>, không phân biệt hoa/thường (so sánh sau khi hạ chữ)

# A1. helper: LABEL_RE thật của super-board-waiting-on.py
helper_set=$(python3 -I - "$ROOT/.claude/bin/super-board-waiting-on.py" "$LABELS" <<'PY'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("wo", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(json.dumps(sorted(l.lower() for l in json.loads(sys.argv[2]) if m.LABEL_RE.match(l)), separators=(",", ":")))
PY
)
[ "$helper_set" = "$WANT" ] && ok "A1 helper LABEL_RE waits only on waiting-on:#<number>" || fail "A1 helper set=$helper_set want=$WANT"

# A2. runner: WAITING_ON_JQ thật — mỗi nhãn trên một thẻ riêng, đếm thẻ bị coi là đang chờ
ITEMS_A=$(jq -nc --argjson l "$LABELS" '{items: [$l | to_entries[] | {id: "I\(.key)", status: "Ready", labels: [.value],
  content: {type: "Issue", number: (100 + .key), title: .value, assignees: []}}]}')
runner_set=$( ( SB_LIB_ONLY=1 . "$RUNNER" >/dev/null 2>&1 || exit 99
  printf '%s' "$ITEMS_A" | jq -c "$WAITING_ON_JQ"'[.items[] | select(waiting_on) | .content.title | ascii_downcase] | sort' ) 2>/dev/null)
[ "$runner_set" = "$WANT" ] && ok "A2 runner WAITING_ON_JQ waits only on waiting-on:#<number>" || fail "A2 runner set=$runner_set want=$WANT"

# A3. planner: super-board-wave-plan.sh thật (offline --items/--deps): thẻ mang nhãn sai dạng vào `cards`, thẻ #<số> vào `waiting`
DEPS_A=$(jq -nc --argjson l "$LABELS" '[$l | to_entries[] | {key: "\(100 + .key)", value: {runnable: true, parseable: true,
  blockers: [], openBlockers: [], humanGated: false}}] | from_entries')
printf '%s' "$ITEMS_A" > "$TMP/items-a.json"; printf '%s' "$DEPS_A" > "$TMP/deps-a.json"
printf '{"project":{"owner":"x","number":1},"repo":{"path":".","remote":"https://github.com/x/y"},"verify_commands":["bash tests/check.sh"]}' > "$TMP/cfg-a.json"
(cd "$ROOT" && SB_GITHUB_HALT_FILE="$TMP/halt-a.json" bash .claude/bin/super-board-wave-plan.sh --config "$TMP/cfg-a.json" \
   --items "$TMP/items-a.json" --deps "$TMP/deps-a.json" > "$TMP/plan-a.json" 2> "$TMP/plan-a.err")
planner_set=$(jq -c --argjson l "$LABELS" '[.cards[].number] as $c
  | [$l | to_entries[] | select((100 + .key) as $n | $c | index($n) | not) | .value | ascii_downcase] | sort' "$TMP/plan-a.json" 2>/dev/null)
[ "$planner_set" = "$WANT" ] && ok "A3 planner holds back only waiting-on:#<number> cards" \
  || fail "A3 planner held=$planner_set want=$WANT (err: $(head -c 200 "$TMP/plan-a.err"))"
[ "$helper_set" = "$runner_set" ] && [ "$runner_set" = "$planner_set" ] && ok "A4 helper, runner and planner agree on the same label set" \
  || fail "A4 disagreement: helper=$helper_set runner=$runner_set planner=$planner_set"

# ── B. preflight bỏ qua thẻ top → thẻ Ready kế được giao cùng tick
mkdir -p "$TMP/bin" "$TMP/path" "$TMP/repo/docs/super-board/runs" "$TMP/repo/wl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/super-board-github-read.py"
printf 'print("ok")\n' > "$TMP/bin/super-board-skills-ready.py"
cp "$ROOT/.claude/bin/super-board-blocked-by.py" "$TMP/bin/"
cat > "$TMP/path/gh" <<'SH'
#!/bin/sh
echo "OPEN https://github.com/acme/widgets/issues/$3"
SH
# preflight stub: in $STUB_PREFLIGHT_JSON (verdict theo số thẻ), ghi lời gọi
cat > "$TMP/bin/super-board-preflight.sh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$STUB_DIR/preflight-calls"
printf '%s\n' "${STUB_PREFLIGHT_JSON:-}"
exit 0
SH
# waiting-on helper stub: mark luôn hỏng (69) — đúng lỗi kéo dài của #619
cat > "$TMP/bin/super-board-waiting-on.py" <<'PY'
import os, sys
with open(os.path.join(os.environ["STUB_DIR"], "wo-calls"), "a") as f:
    f.write(" ".join(sys.argv[1:]) + "\n")
sys.exit(int(os.environ.get("STUB_WO_RC", "69")))
PY
cat > "$TMP/path/claude" <<'SH'
#!/usr/bin/env bash
echo spawned >> "$STUB_DIR/spawned"
SH
chmod +x "$TMP/bin/"* "$TMP/path/claude" "$TMP/path/gh"
export STUB_DIR="$TMP" PATH="$TMP/path:$PATH" WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0
unset SB_GITHUB_READ_STRICT SB_ACCOUNT_POOL SB_WAITING_ON SB_WAITING_SWEEP_EVERY

SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
SB_GITHUB_READ="$TMP/bin/super-board-github-read.py"
CONFIG_PATH="$TMP/cfg.json"; echo '{"repo":{"remote":"https://github.com/acme/widgets"}}' > "$CONFIG_PATH"
INFLIGHT_DIR="$TMP/repo/.claude/super-board/inflight"; mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="wl"; REPO_ROOT="$TMP/repo"; BOT_LOGIN="bot"
export SB_GITHUB_HALT_FILE="$TMP/halt.json"
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }
issue_is_open() { return 0; }
issue_locked() { [ -e "$INFLIGHT_DIR/$1" ]; }
early_backoff() { return 1; }
ready_card_held() { return 1; }
resolve_worker_account() { POOL_ENGINE=""; POOL_ACCT=""; POOL_CFG=""; return 0; }
note_worker_limit() { :; }
cd "$TMP/repo" || exit 1
PF="$TMP/bin/super-board-preflight.sh"
card() { printf '{"id":"PVTI_%s","status":"Ready","labels":[%s],"content":{"type":"Issue","number":%s,"title":"card %s","assignees":[]}}' "$1" "${2:-}" "$1" "$1"; }
reset() {
  : > "$TMP/writes"; : > "$TMP/log"; rm -f "$TMP/spawned" "$TMP/preflight-calls" "$TMP/wo-calls" "$TMP/halt.json" "$INFLIGHT_DIR"/*
  PREFLIGHT_SKIP=""; CARD_WRITE_BLOCKED=""; BUILD_FREE=1; QA_FREE=0; ACTIVE_WORKERS=0
}
SEQ='{"verdict":"sequence","tag":"overlap","reason":"overlap","blockedBy":[9]}'
GO='{"verdict":"proceed","tag":"","reason":"ok"}'

# B1. #7 (priority:high, đứng đầu) mark hỏng → #8 được giao trong cùng tick
reset
PROJECT_ITEMS_JSON="{\"items\":[$(card 7 '"priority:high"'),$(card 8)]}"
export STUB_PREFLIGHT_JSON="{\"7\":$SEQ,\"8\":$GO}"
SB_PREFLIGHT="$PF" dispatch_ready_tick >/dev/null 2>&1; rc=$?
sleep 0.3
[ "$rc" = 0 ] && [ -e "$INFLIGHT_DIR/8" ] && ok "B1 mark of top card #7 fails → next Ready card #8 dispatched in the same tick" \
  || fail "B1 rc=$rc lock8=$([ -e "$INFLIGHT_DIR/8" ] && echo yes || echo no) log=$(cat "$TMP/log" 2>/dev/null | tr '\n' '|' | cut -c1-300)"
[ ! -e "$INFLIGHT_DIR/7" ] && ! grep -q "move PVTI_7 Blocked" "$TMP/writes" && ok "  … #7 not dispatched, not moved to Blocked (stays Ready, retried next tick)" \
  || fail "  #7 handled wrong: writes=$(cat "$TMP/writes" 2>/dev/null | tr '\n' '|')"
[ "${ACTIVE_WORKERS:-0}" = 1 ] && ok "  … ACTIVE_WORKERS counts the one worker started" || fail "  ACTIVE_WORKERS=${ACTIVE_WORKERS:-unset} (want 1)"

# B2. mỗi thẻ đều bị bỏ qua → tối đa 3 lần preflight trong một tick, không giao gì
reset
PROJECT_ITEMS_JSON="{\"items\":[$(card 11),$(card 12),$(card 13),$(card 14),$(card 15)]}"
export STUB_PREFLIGHT_JSON="{\"11\":$SEQ,\"12\":$SEQ,\"13\":$SEQ,\"14\":$SEQ,\"15\":$SEQ}"
SB_PREFLIGHT="$PF" dispatch_ready_tick >/dev/null 2>&1; rc=$?
n=$(cat "$TMP/wo-calls" 2>/dev/null | wc -l | tr -d ' ')
locks=$(ls "$INFLIGHT_DIR" 2>/dev/null | wc -l | tr -d ' ')
[ "$rc" = 0 ] && [ "${n:-0}" = 3 ] && [ "$locks" = 0 ] && [ "${ACTIVE_WORKERS:-0}" = 0 ] \
  && ok "B2 every Ready card skipped → at most 3 preflights in one tick, nothing dispatched, ACTIVE_WORKERS unchanged" \
  || fail "B2 rc=$rc marks=${n:-0} locks=$locks active=${ACTIVE_WORKERS:-unset}"

# B3. đối chứng: thẻ top giao bình thường → chỉ một preflight, giao đúng thẻ top
reset
PROJECT_ITEMS_JSON="{\"items\":[$(card 21 '"priority:high"'),$(card 22)]}"
export STUB_PREFLIGHT_JSON="{\"21\":$GO,\"22\":$GO}"
SB_PREFLIGHT="$PF" dispatch_ready_tick >/dev/null 2>&1; rc=$?
sleep 0.3
n=$(cat "$TMP/preflight-calls" 2>/dev/null | wc -l | tr -d ' ')
[ "$rc" = 0 ] && [ -e "$INFLIGHT_DIR/21" ] && [ ! -e "$INFLIGHT_DIR/22" ] && [ "${n:-0}" = 1 ] \
  && ok "B3 control — top card proceeds → only it is dispatched, one preflight" \
  || fail "B3 rc=$rc lock21=$([ -e "$INFLIGHT_DIR/21" ] && echo yes || echo no) lock22=$([ -e "$INFLIGHT_DIR/22" ] && echo yes || echo no) preflights=${n:-0}"

# B4. nhãn sai dạng `waiting-on:#x` không làm thẻ bị bỏ qua khi giao
reset
PROJECT_ITEMS_JSON="{\"items\":[$(card 31 '"waiting-on:#x"')]}"
export STUB_PREFLIGHT_JSON="{\"31\":$GO}"
top_card_in_column Ready >/dev/null 2>&1
[ "${TOP_ISSUE:-}" = 31 ] && ok "B4 malformed waiting-on:#x does not hold the card back" || fail "B4 TOP_ISSUE='${TOP_ISSUE:-}' (want 31)"

[ "$FAILS" -eq 0 ] && echo "PASS test_waiting_on_skip_next" || { echo "FAIL test_waiting_on_skip_next ($FAILS)"; exit 1; }
