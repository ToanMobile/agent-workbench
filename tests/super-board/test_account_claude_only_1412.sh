#!/usr/bin/env bash
# Test hồi quy #1412 phía runner (offline, runner source ở lib mode, HOME giả):
# - note_worker_limit ghi đúng loại cửa sổ: 19/11 02:53 "You've hit your weekly limit · resets Nov 22 at 12am" bị ghi thành
#   five_hour 100 % tới 22/11, pool giữ PAUSE 432 phút dù cửa sổ 5 giờ thật còn 35 %;
# - chỉ tài khoản Claude: runner không truyền công tắc dự phòng khác hãng, pool trả engine khác claude thì không giao;
# - pool trả pause ⇒ không giao worker, log ghi giờ reset; lane review vẫn nạp được antigravity-pm (Antigravity là reviewer).
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-claude-only-1412.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home" "$TMP/bin" "$TMP/state" "$TMP/path" "$TMP/repo/docs/super-board" "$TMP/repo/wl"

# ── 0. Mặc định runner dùng script pool nằm cạnh nó trong kit (bản ở ~/.claude/bin chỉ là dự phòng).
got=$(unset SB_ACCOUNT_POOL; SB_LIB_ONLY=1 . "$RUNNER" >/dev/null 2>&1; printf '%s' "$SB_ACCOUNT_POOL")
[ "$got" = "$ROOT/.claude/bin/super-board-account-pool.sh" ] && ok "0: the runner defaults to the kit's own pool script" \
  || fail "0: default SB_ACCOUNT_POOL='$got'"

# Pool giả: ghi lại biến dự phòng runner truyền vào, in $STUB_POOL_JSON, thoát $STUB_POOL_RC.
cat > "$TMP/bin/pool.sh" <<'SH'
#!/usr/bin/env bash
echo "ag=${SB_FALLBACK_ANTIGRAVITY-unset} grok=${SB_FALLBACK_GROK-unset}" > "$STUB_DIR/pool.env"
printf '%s\n' "$STUB_POOL_JSON"
exit "${STUB_POOL_RC:-0}"
SH
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/super-board-github-read.py"
printf 'print("ok")\n' > "$TMP/bin/super-board-skills-ready.py"
cat > "$TMP/path/claude" <<'SH'
#!/usr/bin/env bash
echo "claude cfg=${CLAUDE_CONFIG_DIR:-default}" >> "$STUB_DIR/launched"
SH
chmod +x "$TMP/bin/pool.sh" "$TMP/bin/super-board-github-read.py" "$TMP/path/claude"
export HOME="$TMP/home" STUB_DIR="$TMP" SB_STATE_DIR="$TMP/state" SB_ACCOUNT_POOL="$TMP/bin/pool.sh" PATH="$TMP/path:$PATH"

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
board_notify() { :; }
log() { echo "$*" >> "$TMP/log"; }
cd "$TMP/repo" || exit 1

window() {   # in "<used> <resets_at>" của cửa sổ $2 trong usage-$1.json, rỗng nếu không có
  jq -r --arg w "$2" '.rate_limits[$w] // empty | "\(.used_percentage) \(.resets_at)"' "$TMP/state/usage-$1.json" 2>/dev/null
}
clock() {   # giờ dạng thông báo của Claude Code ("3:07pm", "Nov 22 at 12am") cho epoch $1; $2=date thì kèm ngày
  python3 - "$1" "${2:-}" <<'PY'
import datetime, sys, zoneinfo
t = datetime.datetime.fromtimestamp(int(sys.argv[1]), zoneinfo.ZoneInfo("Asia/Saigon"))
hm = f"{(t.hour % 12) or 12}{':%02d' % t.minute if t.minute else ''}{'pm' if t.hour >= 12 else 'am'}"
print(f"{t.strftime('%b')} {t.day} at {hm}" if sys.argv[2] == "date" else hm)
PY
}

# ── 1. AC2, giới hạn 5 giờ: khoá không bao giờ vượt 5 giờ, kể cả khi giờ trong thông báo bị đọc thành xa hơn
# (runner ghi bản ghi five_hour, pool thật của kit chặn trần 5 giờ kể từ lúc ghi).
now=$(date +%s)
far=$(( (now + 36000) / 60 * 60 ))
cat > "wl/worker-build-51.log" <<LOG
=== dispatch lane=build issue=#51 at 2026-11-21T09:00:00Z ===
account_pool: engine=claude account=finos_team config_dir=/Users/x/.claude-finos_team
You've hit your 5-hour limit · resets $(clock "$far") (Asia/Saigon)
worker_exit: exit=1 signal=none elapsed=9s
LOG
note_worker_limit "wl/worker-build-51.log"
mkdir -p "$HOME/.claude-finos_team" "$TMP/repo/.claude"
echo '{"account":"finos_linh"}' > "$TMP/repo/.claude/settings.local.json"
pj=$(env -u CLAUDE_CONFIG_DIR SB_USAGE_SH="$ROOT/.claude/bin/super-board-usage.sh" bash "$ROOT/.claude/bin/super-board-account-pool.sh" resolve "$TMP/repo" 2>/dev/null); now=$(date +%s)
pr=$(printf '%s' "$pj" | jq -r '.resets_at // 0' 2>/dev/null)
[ -n "$(window finos_team five_hour)" ] && [ "$(printf '%s' "$pj" | jq -r '"\(.state) \(.window) \(.engine)"' 2>/dev/null)" = "pause five_hour claude" ] \
  && [ "${pr:-0}" -gt "$now" ] && [ "${pr:-0}" -le $((now + 18000)) ] \
  && ok "1: a 5-hour limit recorded by the runner freezes the account for at most 5 hours" \
  || fail "1: five_hour='$(window finos_team five_hour)' pool='$pj' (now=$now, limit $((now + 18000)))"
rm -f "$TMP/repo/.claude/settings.local.json"

# ── 2. AC2, giới hạn tuần: ghi vào cửa sổ seven_day tới đúng giờ reset tuần, không ghi five_hour.
rm -f "$TMP/state/usage-"*.json
wk=$(python3 -c 'import datetime,zoneinfo; t=(datetime.datetime.now(zoneinfo.ZoneInfo("Asia/Saigon"))+datetime.timedelta(days=3)).replace(hour=0,minute=0,second=0,microsecond=0); print(int(t.timestamp()))')
cat > "wl/worker-build-52.log" <<LOG
=== dispatch lane=build issue=#52 at 2026-11-18T19:53:00Z ===
account_pool: engine=claude account=finos_team config_dir=/Users/x/.claude-finos_team
{"is_error":true,"api_error_status":429,"result":"You've hit your weekly limit · resets $(clock "$wk" date) (Asia/Saigon)","type":"result"}
worker_exit: exit=1 signal=none elapsed=7s
LOG
note_worker_limit "wl/worker-build-52.log"
[ "$(window finos_team seven_day)" = "100 $wk" ] && [ -z "$(window finos_team five_hour)" ] \
  && ok "2: a weekly limit is recorded as seven_day until the weekly reset" \
  || fail "2: seven_day='$(window finos_team seven_day)' five_hour='$(window finos_team five_hour)' (weekly reset $wk)"

# ── 3. Chỉ Claude: runner không truyền công tắc dự phòng khác hãng cho pool.
STUB_POOL_JSON='{"state":"ok","engine":"claude","account":"finos_team","config_dir":"/x/.claude-finos_team"}'; STUB_POOL_RC=0; export STUB_POOL_JSON STUB_POOL_RC
resolve_worker_account >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && grep -qx "ag=unset grok=unset" "$TMP/pool.env" && [ "$POOL_ENGINE" = "claude" ] && [ "$POOL_ACCT" = "finos_team" ] \
  && ok "3: no cross-vendor fallback switch is passed to the pool" \
  || fail "3: rc=$rc env='$(cat "$TMP/pool.env" 2>/dev/null)' engine=$POOL_ENGINE"

# ── 4. Pool cũ (bản ngoài kit) còn trả engine=antigravity: runner không giao, không coi đó là account dùng được.
STUB_POOL_JSON='{"state":"ok","engine":"antigravity","account":"antigravity","config_dir":"/x/.gemini/antigravity"}'
resolve_worker_account >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && [ "$POOL_ENGINE" = "claude" ] && [ -z "$POOL_ACCT" ] \
  && ok "4: a non-Claude engine from the pool is refused (no dispatch)" \
  || fail "4: rc=$rc engine=$POOL_ENGINE acct=$POOL_ACCT"

# ── 5. AC4: pool trả pause kèm resets_at ⇒ không nhận thẻ, không khởi worker, log ghi giờ reset.
claim_calls=0
try_claim_assignee() { claim_calls=$((claim_calls + 1)); return 0; }
issue_is_open() { return 0; }
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_60","status":"Ready","labels":["bug"],"content":{"type":"Issue","number":60,"assignees":[]}}]}'
BUILD_PID=""; BUILD_ISSUE=""; : > "$TMP/launched"; : > "$TMP/log"
reset_at=$(( ($(date +%s) + 5400) / 60 * 60 ))
STUB_POOL_JSON="{\"state\":\"pause\",\"engine\":\"claude\",\"account\":null,\"preferred\":\"finos_team\",\"resets_at\":$reset_at}"; STUB_POOL_RC=10
( dispatch_lane build 60; echo "claims=$claim_calls" > "$TMP/claims" ) >/dev/null 2>&1
sleep 1
hhmm=$(date -u -r "$reset_at" +%H:%M 2>/dev/null || date -u -d "@$reset_at" +%H:%M)
[ ! -s "$TMP/launched" ] && [ ! -e "$INFLIGHT_DIR/60" ] && grep -qx "claims=0" "$TMP/claims" \
  && ok "5: pool pause: no worker launched, no lock, card not claimed" \
  || fail "5: launched='$(cat "$TMP/launched")' lock=$([ -e "$INFLIGHT_DIR/60" ] && echo yes || echo no) $(cat "$TMP/claims" 2>/dev/null)"
grep -q "skip dispatch lane=build issue=#60 .*reset ${hhmm} UTC" "$TMP/log" \
  && ok "5: the skip is logged with the reset time (${hhmm} UTC)" \
  || fail "5: log has no reset time ${hhmm} UTC: $(cat "$TMP/log")"

# ── 6. Antigravity trong vai reviewer không đổi: phiên review chạy Claude vẫn nạp được antigravity-pm.
STUB_POOL_JSON='{"state":"ok","engine":"claude","account":"finos_team","config_dir":"/x/.claude-finos_team"}'; STUB_POOL_RC=0
printf '// stub\n' > "$TMP/antigravity-pm-mcp.js"
export SB_ANTIGRAVITY_PM_MCP="$TMP/antigravity-pm-mcp.js"
resolve_worker_account >/dev/null 2>&1
antigravity_can_provide_mcp "$POOL_CFG" "$POOL_ENGINE"; can=$?
review_mcp_args "$POOL_CFG"
[ "$can" -eq 0 ] && [ "${MCP_ARGS[0]:-}" = "--mcp-config" ] \
  && [ "$(jq -r '.mcpServers["antigravity-pm"].args[0]' "${MCP_ARGS[1]}" 2>/dev/null)" = "$SB_ANTIGRAVITY_PM_MCP" ] \
  && ok "6: the review lane on a Claude account still loads antigravity-pm for the audit" \
  || fail "6: can=$can MCP_ARGS='${MCP_ARGS[*]:-}'"

# ── 7. Review đợt gộp #1416 (P2): pool báo misconfigured (thiếu thư mục ~/.claude-<acct> của tài khoản ghim) ⇒ không giao, log và
# thông báo nêu đúng lý do cấu hình, KHÔNG nói "every worker account is at its limit" / accounts-limited "all".
board_notify() { echo "notify $*" >> "$TMP/notify"; }
claim_calls=0; BUILD_PID=""; BUILD_ISSUE=""; : > "$TMP/launched"; : > "$TMP/log"; : > "$TMP/notify"
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_61","status":"Ready","labels":["bug"],"content":{"type":"Issue","number":61,"assignees":[]}}]}'
STUB_POOL_JSON='{"state":"misconfigured","engine":"claude","account":null,"preferred":"finos_lua","resets_at":null,"reason":"missing ~/.claude-finos_lua: the pinned Claude account has no config directory on this machine"}'; STUB_POOL_RC=12
( dispatch_lane build 61; echo "claims=$claim_calls" > "$TMP/claims" ) >/dev/null 2>&1
sleep 1
[ ! -s "$TMP/launched" ] && [ ! -e "$INFLIGHT_DIR/61" ] && grep -qx "claims=0" "$TMP/claims" \
  && ok "7: misconfigured pool: no worker launched, card not claimed" \
  || fail "7: launched='$(cat "$TMP/launched")' $(cat "$TMP/claims" 2>/dev/null)"
grep -q "skip dispatch lane=build issue=#61 .*missing ~/.claude-finos_lua" "$TMP/log" && ! grep -q "at its limit" "$TMP/log" \
  && ok "7: the skip log names the missing account directory, not a limit" \
  || fail "7: log='$(cat "$TMP/log")'"
grep -q "missing ~/.claude-finos_lua" "$TMP/notify" && ! grep -q -- "--accounts all" "$TMP/notify" \
  && ok "7: the notice carries the misconfiguration reason, not 'accounts all'" \
  || fail "7: notify='$(cat "$TMP/notify")'"

# 7b. Tin Telegram của accounts-limited --reason nêu lý do, không còn câu "at its limit" (deliver giả, không mạng).
printf 'TELEGRAM_BOT_TOKEN=t\nTELEGRAM_CHAT_ID=c\n' > "$TMP/telegram.env"
msg=$(SB_TELEGRAM_ENV="$TMP/telegram.env" python3 - "$ROOT/.claude/bin/super-board-notify.py" "$TMP/nstate" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sb_notify_1412", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
sent = []
m.deliver = lambda token, method, body: sent.append(body["text"])
m.main(["accounts-limited", "--card", "board", "--accounts", "pool-blocked", "--state-dir", sys.argv[2],
        "--reason", "account pool misconfigured: missing ~/.claude-finos_lua"])
print(" | ".join(sent))
PY
)
printf '%s' "$msg" | grep -q "no worker dispatch: account pool misconfigured: missing ~/.claude-finos_lua" && ! printf '%s' "$msg" | grep -q "at its limit" \
  && ok "7b: the Telegram notice states the misconfiguration" || fail "7b: notice='$msg'"

[ "$FAILS" -eq 0 ] && echo "✅ test_account_claude_only_1412: all passed" || { echo "❌ test_account_claude_only_1412: $FAILS failed"; exit 1; }
