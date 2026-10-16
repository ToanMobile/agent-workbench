#!/usr/bin/env bash
# Test hồi quy: runner claude-p xoay account khi worker hết limit (offline, runner source ở lib mode).
# 2026-10-16 21:00-22:50: account finos hết session limit ("You've hit your session limit · resets 10:50pm
# (Asia/Saigon)"). Pool (super-board-account-pool.sh) chỉ biết account hết limit qua file usage-<acct>.json mà
# status line của phiên tương tác ghi; worker `claude -p` không có status line nên không ai ghi. Cả 5 runner cứ giao
# cho finos, worker chết sau ~30 s, gỡ lock, giao lại, trong khi còn finos_team, max, 2 Antigravity và Grok.
# Người dùng chọn (16/10): hết Claude thì Antigravity Ultra -> Antigravity Pro -> Grok; hết cả 6 thì không giao.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-acct-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/state" "$TMP/path" "$TMP/repo/docs/super-board" "$TMP/repo/wl"

# Pool giả: ghi lại biến fallback runner truyền vào, in $STUB_POOL_JSON, thoát $STUB_POOL_RC.
cat > "$TMP/bin/pool.sh" <<'SH'
#!/usr/bin/env bash
echo "ag=${SB_FALLBACK_ANTIGRAVITY:-} grok=${SB_FALLBACK_GROK:-}" > "$STUB_DIR/pool.env"
printf '%s\n' "$STUB_POOL_JSON"
exit "${STUB_POOL_RC:-0}"
SH
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/super-board-github-read.py"
printf 'print("ok")\n' > "$TMP/bin/super-board-skills-ready.py"
# Worker giả đứng đầu PATH: ghi lại account mà runner khởi chạy.
cat > "$TMP/path/claude" <<'SH'
#!/usr/bin/env bash
echo "claude cfg=${CLAUDE_CONFIG_DIR:-default}" >> "$STUB_DIR/launched"
SH
chmod +x "$TMP/bin/pool.sh" "$TMP/bin/super-board-github-read.py" "$TMP/path/claude"
export STUB_DIR="$TMP" SB_STATE_DIR="$TMP/state" SB_ACCOUNT_POOL="$TMP/bin/pool.sh" PATH="$TMP/path:$PATH"

unset SB_GITHUB_READ_STRICT SB_FALLBACK_ANTIGRAVITY SB_FALLBACK_GROK
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
SB_GITHUB_READ="$TMP/bin/super-board-github-read.py"
CONFIG_PATH="$TMP/cfg.json"; echo '{}' > "$CONFIG_PATH"
INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="wl"; REPO_ROOT="$TMP/repo"
BOT_LOGIN=""
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }
cd "$TMP/repo" || exit 1

paused_until() {   # in resets_at của cửa sổ đã chạm 100 % trong usage-<acct>.json, rỗng nếu không có
  jq -r '[.rate_limits[]? | select(.used_percentage >= 100) | .resets_at] | first // empty' "$TMP/state/usage-$1.json" 2>/dev/null
}

# ── 1. Worker chết vì hết session limit: account trong dòng account_pool của lần giao CUỐI bị ghi là hết tới giờ reset.
cat > "$TMP/repo/wl/worker-build-36.log" <<'LOG'
=== dispatch lane=build issue=#36 at 2026-10-16T14:28:36Z ===
prompt: Run super-build on issue #36

account_pool: engine=claude account=finos config_dir=/Users/x/.claude-finos
You've hit your session limit · resets 10:50pm (Asia/Saigon)
LOG
note_worker_limit "wl/worker-build-36.log"
r=$(paused_until finos); now=$(date +%s)
hm=$([ -n "$r" ] && python3 -c 'import sys,datetime,zoneinfo; print(datetime.datetime.fromtimestamp(int(sys.argv[1]), zoneinfo.ZoneInfo("Asia/Saigon")).strftime("%H:%M"))' "$r")
[ -n "$r" ] && [ "$r" -gt "$now" ] && [ "$r" -le $((now + 86400)) ] && [ "$hm" = "22:50" ] \
  && ok "session limit in the worker log: finos marked paused until the next 22:50 Asia/Saigon" \
  || fail "finos not marked paused from the worker log (resets_at='$r' local='$hm')"

# ── 2. Chỉ lần giao cuối được tính: limit của một lần giao cũ trong cùng file log không đánh dấu account lại.
cat > "$TMP/repo/wl/worker-qa-37.log" <<'LOG'
=== dispatch lane=qa issue=#37 at 2026-10-16T10:00:00Z ===
account_pool: engine=claude account=max config_dir=/Users/x/.claude-max
You've hit your session limit · resets 3pm (Asia/Saigon)
=== dispatch lane=qa issue=#37 at 2026-10-16T14:00:00Z ===
account_pool: engine=claude account=max config_dir=/Users/x/.claude-max
done
LOG
note_worker_limit "wl/worker-qa-37.log"
[ ! -e "$TMP/state/usage-max.json" ] && ok "a limit from an older dispatch in the same log is ignored" \
  || fail "max marked paused from an older dispatch section"

# ── 3. Không có giờ reset đọc được (thông báo dạng khác): vẫn đánh dấu, tạm 1 giờ.
cat > "$TMP/repo/wl/worker-build-38.log" <<'LOG'
=== dispatch lane=build issue=#38 at 2026-10-16T14:00:00Z ===
account_pool: engine=antigravity account=antigravity config_dir=/Users/x/.gemini/antigravity
Error: RESOURCE_EXHAUSTED: quota exceeded for model gemini-4-argon-high
LOG
note_worker_limit "wl/worker-build-38.log"
r=$(paused_until antigravity); now=$(date +%s)
[ -n "$r" ] && [ "$r" -gt $((now + 3000)) ] && [ "$r" -le $((now + 3700)) ] \
  && ok "quota error without a reset time: antigravity paused for about an hour" \
  || fail "antigravity quota error not recorded (resets_at='$r')"

# ── 4. reap_finished_locks đọc log của worker vừa chết (theo LANE trong lock) và đánh dấu account đó.
rm -f "$TMP/state/usage-"*.json
printf 'PID=999999\nLANE=build\nSTARTED=2026-10-16T14:28:36Z\n' > "$INFLIGHT_DIR/36"
reap_finished_locks
[ ! -e "$INFLIGHT_DIR/36" ] && [ -n "$(paused_until finos)" ] \
  && ok "reaping a dead worker that hit its limit marks its account paused" \
  || fail "reap did not mark finos paused (lock=$([ -e "$INFLIGHT_DIR/36" ] && echo kept || echo gone))"

# ── 5. Thứ tự dự phòng khi hết Claude: Ultra -> Pro -> Grok, bỏ account đã bị đánh dấu.
STUB_POOL_JSON='{"state":"ok","engine":"claude","account":"max","config_dir":"/x/.claude-max"}'; export STUB_POOL_JSON
resolve_worker_account >/dev/null 2>&1
grep -qx "ag=1 grok=1" "$TMP/pool.env" && ok "no fallback paused: pool may fail over to Antigravity Ultra" \
  || fail "fallback env with nothing paused: $(cat "$TMP/pool.env" 2>/dev/null)"
note_worker_limit "wl/worker-build-38.log"     # antigravity hết
resolve_worker_account >/dev/null 2>&1
grep -qx "ag=pro grok=1" "$TMP/pool.env" && ok "Ultra paused: fall over to Antigravity Pro" \
  || fail "fallback env with Ultra paused: $(cat "$TMP/pool.env" 2>/dev/null)"
jq '.rate_limits.five_hour.resets_at' "$TMP/state/usage-antigravity.json" >/dev/null
cp "$TMP/state/usage-antigravity.json" "$TMP/state/usage-antigravity_pro.json"
resolve_worker_account >/dev/null 2>&1
grep -qx "ag= grok=1" "$TMP/pool.env" && ok "both Antigravity accounts paused: fall over to Grok" \
  || fail "fallback env with both Antigravity paused: $(cat "$TMP/pool.env" 2>/dev/null)"

# ── 6. Hết cả 6 account: không nhận thẻ, không khởi worker (trước đây rơi về `claude` mặc định).
claim_calls=0
try_claim_assignee() { claim_calls=$((claim_calls + 1)); return 0; }
issue_is_open() { return 0; }
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_40","status":"Ready","labels":["bug"],"content":{"type":"Issue","number":40,"assignees":[]}}]}'
BUILD_PID=""; BUILD_ISSUE=""; : > "$TMP/launched"
STUB_POOL_JSON='{"state":"pause","engine":"claude","account":null,"resets_at":null}'; STUB_POOL_RC=10; export STUB_POOL_JSON STUB_POOL_RC
( dispatch_lane build 40 ) >/dev/null 2>&1
sleep 1
[ ! -s "$TMP/launched" ] && [ ! -e "$INFLIGHT_DIR/40" ] && ok "every account paused: no worker launched, no lock" \
  || fail "every account paused: launched='$(cat "$TMP/launched")' lock=$([ -e "$INFLIGHT_DIR/40" ] && echo yes || echo no)"
( dispatch_lane build 40; echo "claims=$claim_calls" > "$TMP/claims" ) >/dev/null 2>&1
grep -qx "claims=0" "$TMP/claims" && ok "every account paused: the card is not claimed" \
  || fail "every account paused: card claimed anyway ($(cat "$TMP/claims"))"

# ── 7. Pool trả account Claude: worker chạy đúng config_dir của account đó (hành vi cũ giữ nguyên).
STUB_POOL_JSON='{"state":"ok","engine":"claude","account":"max","config_dir":"/x/.claude-max"}'; STUB_POOL_RC=0
: > "$TMP/launched"; rm -f "$INFLIGHT_DIR/40"
( dispatch_lane build 40 ) >/dev/null 2>&1
for i in 1 2 3 4 5; do [ -s "$TMP/launched" ] && break; sleep 1; done
grep -qx "claude cfg=/x/.claude-max" "$TMP/launched" && grep -q "account=max" "wl/worker-build-40.log" \
  && ok "pool account max: worker launched with its config dir and logged" \
  || fail "pool account max: launched='$(cat "$TMP/launched")'"

[ "$FAILS" -eq 0 ] && echo "✅ test_account_failover: all passed" || { echo "❌ test_account_failover: $FAILS failed"; exit 1; }
