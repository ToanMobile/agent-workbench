#!/usr/bin/env bash
# super-board-run.sh — headless autonomous runner.
# Spawned as `nohup scripts/super-board-run.sh <config-slug> &`.
# Pure shell while-loop. Dispatches `claude -p` workers per lane.
# Holds NO Claude session state — re-reads GitHub on every tick.
#
# Anti-zombie controls (added 2026-05-22 after #381 worker-storm incident):
#   1. Orphan scan on startup — refuses to start if super-board claude workers already running.
#   2. Issue-level lock files in .claude/super-board/inflight/<N> — survives runner restart.
#   3. Atomic GitHub assignee claim BEFORE spawning worker (closes 10-30s claude -p cold-start race).
#   4. Rate-limit guard — sleeps until reset when GraphQL remaining < 200.
#   5. Per-tick project-items cache — one gh call per tick, not per column lookup.
#   6. Tick interval bumped from 30s → 120s (GraphQL ProjectsV2 query is ~103 pts; 120s keeps usage <3.1k/hr vs 5k budget).
#   7. Lane-zombie watchdog (added 2026-05-24 after fitbox-v4 first-run hang) — kills lane PIDs whose
#      claimed issue has already moved out of the lane's expected source column. The worker's logical
#      work is done; if the claude -p process lingers, lane appears busy forever and downstream cards
#      pile up unprocessed. Uses the project-items cache so it costs zero extra API calls per tick.
#   8. Closed-issue guard (added 2026-08-06, issue #10) — a card is selected by Status column, which
#      says nothing about whether the underlying issue is still open. Before every dispatch the
#      candidate's issue state is checked; a CLOSED issue sitting in a non-terminal column is
#      reconciled to Done instead of being handed another worker.
#   9. Landed-work halt gate (added 2026-08-06, issue #8) — forward progress is measured by the set of
#      cards in Done changing, NOT by lane occupancy. A pipeline that is 100% busy but lands nothing
#      is exactly the runaway this gate must catch, so lane state no longer suppresses it.
#      Config: no_progress_cycles (default 6), max_dispatches (default 0 = unlimited).
#
# PID namespace trap (Git Bash / MSYS, issue #13): `kill -0` inside this script checks MSYS-namespace
# PIDs; PowerShell `Get-Process` checks Windows-namespace PIDs. The two disagree about the same
# process — a live worker can look dead to Windows tooling and vice versa. Always diagnose liveness
# with the same tool family that recorded the PID. Workers are started with `nohup claude -p ... &`
# (no subshell, no `exec` of a native PE), so `$!` names the worker itself rather than a bash stub.

set -euo pipefail
# Mốc ra đời của runner, đặt trước mọi bước đọc config: stop marker ghi từ giây này trở đi là super-board-stop.sh chạy
# trùng lúc runner đang khởi động, và stop thắng (khởi động tường minh không xoá marker đó).
RUNNER_BORN=$(date +%s)
SB_GITHUB_READ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/super-board-github-read.py"
# Lệnh đọc cố định của runner (fields, project, state, quota) đặt SB_GITHUB_READ_STRICT=1 cho TỪNG lệnh: gõ sai ở đây là lỗi
# của script nên vẫn halt board. Không export: worker thừa hưởng nó thì một lệnh gõ sai của agent lại halt cả board.
gh_checkpoint() { python3 "$SB_GITHUB_READ" --check || exit $?; }
gh_write_once() {
  gh_checkpoint
  gh "$@" || {
    python3 "$SB_GITHUB_READ" --halt "GitHub $1 $2 response failed; reconcile the write before restarting" >&2 || true
    exit 79
  }
}

# Auto-resolve repository root if called from outside
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [ -d "$REPO_ROOT/.claude/super-board" ]; then
  cd "$REPO_ROOT"
fi

# ───────────────────────────── args + paths ─────────────────────────────
# SB_LIB_ONLY=1 sources this file for its helpers only (gate tests). Config discovery,
# preconditions and the run loop are all skipped; the caller supplies whatever vars it needs.
CONFIG_SLUG="${1:-}"
if [ "${SB_LIB_ONLY:-0}" = "1" ]; then
  CONFIG_SLUG="${CONFIG_SLUG:-lib}"
  CONFIG_PATH="${CONFIG_PATH:-/dev/null}"
elif [ -z "$CONFIG_SLUG" ]; then
  if [ -f .claude/super-board/active ]; then
    CONFIG_SLUG=$(cat .claude/super-board/active)
  else
    echo "usage: $0 <config-slug>  (or set .claude/super-board/active)" >&2
    exit 64
  fi
fi

if [ "${SB_LIB_ONLY:-0}" != "1" ]; then
CONFIG_PATH=".claude/super-board/configs/${CONFIG_SLUG}.json"
if [ ! -f "$CONFIG_PATH" ]; then
  echo "config not found: $CONFIG_PATH" >&2
  exit 66
fi

# ───────────────────────────── config read ─────────────────────────────
# `variant` was removed in v3.0.0: one board shape, labels route cards (a Ready card
# labelled `qa` goes to the Tester, everything else to the Builder). A config still
# saying "qa-only" is refused, same as the wave planner.
VARIANT=$(jq -r '.variant // "full"' "$CONFIG_PATH")
if [ "$VARIANT" != "full" ]; then
  echo "config still says variant \"$VARIANT\" — removed in v3.0.0. Run /super-board onboard to upgrade." >&2
  exit 65
fi
PROJECT_OWNER=$(jq -r '.project.owner' "$CONFIG_PATH")
PROJECT_NUMBER=$(jq -r '.project.number' "$CONFIG_PATH")
BASE_BRANCH=$(jq -r '.base_branch // "main"' "$CONFIG_PATH")
HUMAN_APPROVES=$(jq -r '.human_approves_merge // false' "$CONFIG_PATH")
REBUILD_CAP=$(jq -r '.rebuild_cap // 2' "$CONFIG_PATH")
BLOCK_ALERT_PCT=$(jq -r '.block_rate_alert_pct // 30' "$CONFIG_PATH")
TICK_SECONDS=$(jq -r '.tick_seconds // 120' "$CONFIG_PATH")
MAX_WORKERS=$(jq -r '.max_workers // 3' "$CONFIG_PATH")
BOT_LOGIN=$(jq -r '.notifications.bot_identity // .bot_identity // ""' "$CONFIG_PATH")
WORKER_BACKEND=$(jq -r '.worker_backend // "workflow"' "$CONFIG_PATH")
# Runaway controls (issue #8). NO_PROGRESS_CYCLES counts dispatch cycles with no
# card reaching Done, regardless of lane occupancy. MAX_DISPATCHES=0 disables the ceiling.
NO_PROGRESS_CYCLES=$(jq -r '.no_progress_cycles // 6' "$CONFIG_PATH")
MAX_DISPATCHES=$(jq -r '.max_dispatches // 0' "$CONFIG_PATH")

# Workflow is the default backend (v1.6.0). This legacy dispatcher only runs
# when the config opts in explicitly — never by accident or stale habit.
if [ "$WORKER_BACKEND" != "claude-p" ]; then
  echo "🛑 board '${CONFIG_SLUG}' uses the workflow backend (worker_backend=${WORKER_BACKEND})." >&2
  echo "    Run it in-session: /super-board run ${CONFIG_SLUG}  (see references/run-workflow.md)" >&2
  echo "    To use this legacy dispatcher, set \"worker_backend\": \"claude-p\" in the config." >&2
  exit 78
fi

python3 "$(dirname "$SB_GITHUB_READ")/super-board-verification-ready.py" --config "$CONFIG_PATH"

RUN_DATE=$(date +%Y-%m-%d)
RUN_MANIFEST="docs/super-board/runs/${RUN_DATE}-${CONFIG_SLUG}.md"
# Per-worker logs (issue #13). Workers used to be spawned with >/dev/null, so the run
# log could never show what a worker was doing during a 13-minute silence.
WORKER_LOG_DIR="docs/super-board/runs/${RUN_DATE}-${CONFIG_SLUG}-workers"
INFLIGHT_DIR=".claude/super-board/inflight"
mkdir -p "docs/super-board/runs" "$WORKER_LOG_DIR" .claude/worktrees "$INFLIGHT_DIR"
fi  # end non-lib-only setup

# Defaults so the helpers below are safe to source under `set -u` in lib-only mode.
: "${RUN_MANIFEST:=/dev/null}"
: "${WORKER_LOG_DIR:=/dev/null}"
: "${INFLIGHT_DIR:=/dev/null}"
: "${PROJECT_OWNER:=}" ; : "${PROJECT_NUMBER:=0}" ; : "${BOT_LOGIN:=}"

# ───────────────────────────── helpers ─────────────────────────────
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$RUN_MANIFEST"; }

PROJECT_ITEMS_JSON=""
fetch_project_items() {
  # One board read per tick; all column lookups read from this cache.
  # super-board-card.sh items: ~1 GraphQL point per 100 cards, where
  # `gh project item-list` spends 101 per 100.
  local fresh
  fresh=$("$(dirname "$SB_GITHUB_READ")/super-board-card.sh" --owner "$PROJECT_OWNER" --number "$PROJECT_NUMBER" items) || return $?
  PROJECT_ITEMS_JSON="$fresh"
}

column_count() {
  echo "$PROJECT_ITEMS_JSON" | jq --arg col "$1" '[.items[] | select(.status == $col)] | length'
}

# #95: a card that waits for a person — labelled needs-you / human-gated (any case, on the item or its content, as a name or {name}).
# Not one carrying loop:rebase / loop:rebuild-N: that card came back from QA/Review (a gate exit or a bounce after the person's `done`
# moved it to Review with its needs-you still on: run.md → resume), so it is work again (review 19/10). One definition for every use.
FOR_A_PERSON_JQ='def for_a_person: [((.labels // []) + (.content.labels // []))[] | (if type == "object" then .name else . end) | ascii_downcase]
  | ((index("needs-you") or index("human-gated")) and (map(. == "loop:rebase" or startswith("loop:rebuild-")) | any | not));'

person_count() {
  # Cards of column $1 waiting for a person: no lane takes them from Ready, so they must not keep a run alive that has nothing else
  # to do (counted in Ready, a non-daemon run never reached its clean "all empty" exit).
  echo "$PROJECT_ITEMS_JSON" | jq --arg col "$1" "$FOR_A_PERSON_JQ"' [.items[] | select(.status == $col) | select(for_a_person)] | length'
}

# ── Status-field resolution (issue #10 reconcile path).
# Option IDs are resolved BY NAME at runtime and cached for the run. Never hard-code
# them: `updateProjectV2Field` replaces the whole option list and remints every ID,
# so a hard-coded map goes stale silently the first time anyone edits the columns.
STATUS_FIELD_ID=""
STATUS_OPTIONS_JSON=""
resolve_status_field() {
  [ -n "$STATUS_FIELD_ID" ] && return 0
  local payload
  payload=$(SB_GITHUB_READ_STRICT=1 python3 "$SB_GITHUB_READ" --kind fields -- project field-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json) || return $?
  STATUS_FIELD_ID=$(echo "$payload" | jq -r '.fields[] | select(.name == "Status") | .id')
  STATUS_OPTIONS_JSON=$(echo "$payload" | jq -c '.fields[] | select(.name == "Status") | .options')
  [ -n "$STATUS_FIELD_ID" ] && [ "$STATUS_FIELD_ID" != "null" ]
}

status_option_id() {
  # $1 = option name. Fails loud (exit 1 + empty output) when the name is absent
  # from the live option set, rather than mutating with a stale ID.
  local id
  id=$(echo "${STATUS_OPTIONS_JSON:-[]}" | jq -r --arg n "$1" '
    map(select(.name == $n)) | .[0].id // empty' 2>/dev/null)
  [ -n "$id" ] || return 1
  echo "$id"
}

set_card_status() {
  # $1 = project item id, $2 = target status name. Returns non-zero if unresolvable.
  local item_id="$1" name="$2" opt_id
  resolve_status_field || { gh_checkpoint; log "⚠ could not resolve Status field — skipping reconcile"; return 1; }
  opt_id=$(status_option_id "$name") || {
    log "⚠ Status option '${name}' not present on the board — skipping reconcile"; return 1; }
  local project_id
  project_id=$(project_node_id) || return $?
  gh_checkpoint
  gh_write_once project item-edit --id "$item_id" --project-id "$project_id" \
    --field-id "$STATUS_FIELD_ID" --single-select-option-id "$opt_id" >/dev/null 2>&1
}

PROJECT_NODE_ID=""
project_node_id() {
  if [ -z "$PROJECT_NODE_ID" ]; then
    local payload
    payload=$(SB_GITHUB_READ_STRICT=1 python3 "$SB_GITHUB_READ" --kind project -- project view "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json) || return $?
    PROJECT_NODE_ID=$(echo "$payload" | jq -r .id)
  fi
  echo "$PROJECT_NODE_ID"
}

issue_is_open() {
  # $1 = issue number. Returns 0 when OPEN, 1 when CLOSED.
  # Unreadable is distinct from both OPEN and CLOSED: exit 79 halts the run.
  local state
  state=$(SB_GITHUB_READ_STRICT=1 python3 "$SB_GITHUB_READ" --kind state -- issue view "$1" --json state -q '.state') || return 79
  [ "$state" != "CLOSED" ]
}

TOP_ISSUE=""
TOP_ITEM_ID=""
card_lane() {
  # "qa" when issue $1 carries the `qa` label on the board snapshot, else "build".
  # Labels sit on the item (`labels`) or its content, as names or {name}.
  echo "$PROJECT_ITEMS_JSON" | jq -r --argjson n "$1" '
    [.items[] | select(.content.number == $n)
     | ((.labels // []) + (.content.labels // []))[]
     | (if type == "object" then .name else . end) | ascii_downcase]
    | if index("qa") then "qa" else "build" end' 2>/dev/null || echo build
}

top_card_in_column() {
  # Sets TOP_ISSUE / TOP_ITEM_ID to the FIRST dispatchable card in column $1:
  # no assignee, no local in-flight lock, and the underlying issue still OPEN.
  # A CLOSED issue found in a non-terminal column is reconciled to Done and skipped —
  # dispatching a worker at it is the single largest observed waste category (issue #10).
  #
  # The result is returned via TOP_ISSUE, NOT stdout: this function logs as it
  # reconciles, and log lines on stdout would be captured by a `$(...)` caller and
  # read back as a card number.
  local col="$1" issue item_id
  TOP_ISSUE=""; TOP_ITEM_ID=""
  while IFS=$'\t' read -r issue item_id; do
    [ -n "$issue" ] || continue
    issue_locked "$issue" && continue
    if early_backoff "$issue" "$col"; then   # #94: its worker died at once twice in the window — no claim/release loop
      local key
      key="${col}#${issue}@$( { tail -1 "$(early_death_file "$issue")" 2>/dev/null || true; } | cut -d' ' -f1)"   # one line per backoff
      case " ${BACKOFF_LOGGED:-} " in
        *" ${key} "*) ;;
        *) log "skip #${issue} in ${col}: its worker ended within ${SB_EARLY_DEATH_S:-120}s twice in ${SB_EARLY_WINDOW_S:-600}s — not claimed again until that window passes"
           BACKOFF_LOGGED="${BACKOFF_LOGGED:-} ${key}" ;;
      esac
      continue
    fi
    local issue_rc=0
    issue_is_open "$issue" || issue_rc=$?
    [ "$issue_rc" -le 1 ] || exit "$issue_rc"
    if [ "$issue_rc" -ne 0 ]; then
      log "reconciled closed #${issue} -> Done (was '${col}') — dispatching 0 workers for it"
      set_card_status "$item_id" "Done" || { gh_checkpoint; log "  ↳ reconcile of #${issue} could not be written to the board"; return 1; }
      gh_checkpoint
      [ -n "$BOT_LOGIN" ] && gh_write_once issue edit "$issue" --remove-assignee "$BOT_LOGIN" >/dev/null 2>&1 || true
      rm -f "$INFLIGHT_DIR/$issue"
      continue
    fi
    TOP_ISSUE="$issue"; TOP_ITEM_ID="$item_id"
    return 0
  done <<EOF
$(echo "$PROJECT_ITEMS_JSON" | jq -r --arg col "$col" "$FOR_A_PERSON_JQ"'
    .items[]
    | select(.status == $col and .content.type == "Issue")
    | select((.content.assignees // []) | length == 0)
    # #95: a Ready card waiting for a person (playtest, real device, store account, a ruling): dispatching it only spends a lane
    # and parks it again. Not in QA/Review: the resume path moves a 🙋 card a person approved to Review with its label possibly
    # still on (run.md → resume). Removing the label releases the card.
    | select($col != "Ready" or (for_a_person | not))
    | [(.content.number | tostring), (.id // "")] | @tsv')
EOF
  return 1
}

read_lock() {
  # Reads $INFLIGHT_DIR/$1 (bash-assignment format) into PID/LANE/STARTED.
  # Sets empty strings if the file is missing or legacy single-PID format.
  local lock="$INFLIGHT_DIR/$1"
  PID=""; LANE=""; STARTED=""
  [ -f "$lock" ] || return 1
  if grep -q '^PID=' "$lock" 2>/dev/null; then
    # shellcheck disable=SC1090
    . "$lock" 2>/dev/null || true
  else
    # Legacy format (pre v1.3.0): single line PID only.
    PID=$(cat "$lock" 2>/dev/null || echo "")
  fi
  return 0
}

issue_locked() {
  # Returns 0 if the issue has a live in-flight lock; cleans stale locks.
  gh_checkpoint
  local issue="$1" lock="$INFLIGHT_DIR/$1"
  [ -f "$lock" ] || return 1
  read_lock "$issue"
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    return 0
  fi
  [ -z "$LANE" ] || note_worker_limit "${WORKER_LOG_DIR}/worker-${LANE}-${issue}.log"
  note_early_death "$issue"   # the second place a dead lock goes (a worker that died after this tick's reap): same ledger (#94)
  rm -f "$lock"
  return 1
}

# ── Xoay account của worker (pool: $HOME/.claude/bin/super-board-account-pool.sh, lệnh `ccswitch`).
# Pool chỉ biết account hết limit qua usage-<acct>.json, file mà status line của phiên tương tác ghi; worker
# `claude -p` không có status line. Nên runner tự ghi khi worker chết vì hết limit (16/10: cả 5 runner giao mãi cho
# finos đã hết session limit trong khi còn 5 account khác).
SB_ACCOUNT_POOL="${SB_ACCOUNT_POOL:-$HOME/.claude/bin/super-board-account-pool.sh}"
SB_ACCOUNT_STATE_DIR="${SB_STATE_DIR:-$HOME/.claude/super-board}"
POOL_ENGINE="claude"; POOL_ACCT=""; POOL_CFG=""; POOL_RESETS=""

note_worker_limit() {
  # $1 = log của worker vừa chết. Hết limit (thông báo ở 3 dòng cuối của lần giao CUỐI) thì ghi account trong dòng
  # `account_pool:` của lần giao đó là 100 % tới giờ reset (không đọc được giờ thì 1 giờ), đúng dạng usage-<acct>.json
  # mà pool đọc. Chỉ ghi file của account đó, không ghi usage.json chung (file chung kéo theo `switch` credential
  # toàn cục của người dùng). Lỗi ở đây không bao giờ chặn runner.
  [ -f "$1" ] || return 0
  local out
  out=$(python3 - "$1" "$SB_ACCOUNT_STATE_DIR" <<'PY' 2>/dev/null
import datetime, json, os, re, sys, time
log, state = sys.argv[1], sys.argv[2]
section = open(log, errors='replace').read().rsplit('=== dispatch ', 1)[-1]
acct = re.search(r'^account_pool: engine=\S+ account=([A-Za-z0-9_.-]+)', section, re.M)
tail = '\n'.join([l for l in section.splitlines() if l.strip()][-3:])
# Claude Code: "You've hit your session limit · resets 10:50pm (Asia/Saigon)" (đo 16/10). Ba mẫu sau là mã quota của
# Gemini/xAI, chưa đo trên agy/grok thật.
hit = re.search(r"hit your (?:\w+ )?limit|usage limit reached|RESOURCE_EXHAUSTED|quota exceeded|rate limit exceeded", tail, re.I)
if not acct or not hit:
    sys.exit(0)
now = int(time.time())
resets = now + 3600
m = re.search(r'resets (?:([A-Z][a-z]{2}) (\d{1,2}),? (?:at )?)?(\d{1,2})(?::(\d{2}))?\s*([ap]m)(?:\s*\(([^)]+)\))?', tail, re.I)
if m:
    try:
        from zoneinfo import ZoneInfo
        base = datetime.datetime.now(ZoneInfo(m[6]) if m[6] else None)
        t = base.replace(hour=int(m[3]) % 12 + (12 if m[5].lower() == 'pm' else 0), minute=int(m[4] or 0), second=0, microsecond=0)
        if m[1]:
            t = t.replace(month=datetime.datetime.strptime(m[1], '%b').month, day=int(m[2]))
            if t.timestamp() <= now:
                t = t.replace(year=t.year + 1)
        elif t.timestamp() <= now:
            t += datetime.timedelta(days=1)
        resets = int(t.timestamp())
    except (ValueError, KeyError, ImportError) as error:
        print(f'reset time unreadable ({error}); pausing 1h', file=sys.stderr)
os.makedirs(state, exist_ok=True)
path = os.path.join(state, f'usage-{acct[1]}.json')
tmp = f'{path}.{os.getpid()}'
with open(tmp, 'w') as f:
    json.dump({'recorded_at': now, 'source': 'super-board-run worker log',
               'rate_limits': {'five_hour': {'used_percentage': 100, 'resets_at': resets}}}, f)
os.replace(tmp, path)
print(acct[1], time.strftime('%H:%M', time.localtime(resets)))
PY
) || { log "⚠ could not read worker log $1 for an account limit"; return 0; }
  [ -z "$out" ] || log "account ${out% *} hit its limit — paused until ${out#* }; next dispatch takes the pool's next account"
  return 0
}

account_paused() {
  # 0 khi usage-<acct>.json có cửa sổ ≥ 95 % (ngưỡng mặc định của pool) chưa tới giờ reset.
  local f="$SB_ACCOUNT_STATE_DIR/usage-$1.json"
  [ -f "$f" ] || return 1
  jq -e --argjson now "$(date +%s)" \
    '[.rate_limits[]? | select((.used_percentage // 0) >= 95 and (.resets_at // 0) > $now)] | length > 0' "$f" >/dev/null 2>&1
}

resolve_worker_account() {
  # Đặt POOL_ENGINE/POOL_ACCT/POOL_CFG cho worker kế tiếp. Pool tự xoay finos -> finos_team -> max theo usage; hết cả 3
  # thì theo lựa chọn của người dùng (16/10): Antigravity Ultra -> Antigravity Pro -> Grok, bỏ account đang bị ghi là
  # hết. Trả 1 (POOL_RESETS = giờ reset sớm nhất nếu pool biết) khi mọi account đều hết: không giao.
  POOL_ENGINE="claude"; POOL_ACCT=""; POOL_CFG=""; POOL_RESETS=""
  [ -x "$SB_ACCOUNT_POOL" ] || return 0
  local ag="" grok="" json
  if ! account_paused antigravity; then ag=1; elif ! account_paused antigravity_pro; then ag=pro; fi
  account_paused grok || grok=1
  json=$(SB_FALLBACK_ANTIGRAVITY="$ag" SB_FALLBACK_GROK="$grok" "$SB_ACCOUNT_POOL" resolve "$PWD" 2>/dev/null) || true
  [ -n "$json" ] || { log "⚠ account pool printed nothing; worker uses the default claude account"; return 0; }
  if [ "$(printf '%s' "$json" | jq -r '.state // "ok"' 2>/dev/null)" = "pause" ]; then
    POOL_RESETS=$(printf '%s' "$json" | jq -r '.resets_at // empty | tonumber | strftime("%H:%M UTC")' 2>/dev/null || true)
    return 1
  fi
  POOL_ENGINE=$(printf '%s' "$json" | jq -r '.engine // "claude"' 2>/dev/null || echo claude)
  POOL_ACCT=$(printf '%s' "$json" | jq -r '.account // empty' 2>/dev/null || true)
  POOL_CFG=$(printf '%s' "$json" | jq -r '.config_dir // empty' 2>/dev/null || true)
  return 0
}

lane_idle() {
  local pid="${1:-}"
  [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null
}

tick_sleep() {
  # $1 = số giây. Một `sleep` bị kill không được kết thúc runner: 17/10 12:17 cả 5 runner chết với
  # `Terminated: 15 sleep "$TICK_SECONDS"` (sleep rc 143 dưới `set -e`) và nằm chết 2 ngày. Chỉ stop marker của
  # super-board-stop.sh (kiểm ở đầu mỗi tick) mới dừng vòng lặp.
  local rc=0
  sleep "$1" || rc=$?
  if [ "$rc" -gt 128 ]; then
    log "⚠ sleep ${1}s killed by signal $((rc - 128)) — runner keeps going; stop a board only with super-board-stop.sh"
  elif [ "$rc" -ne 0 ]; then
    # sleep tự lỗi (tick_seconds không hợp lệ): không được quay vòng không nghỉ, đọc GitHub liên tục.
    log "⚠ sleep '${1}' failed (rc=${rc}): check tick_seconds in the config; sleeping 60s instead"
    sleep 60 || true
  fi
}

gh_rate_guard() {
  # Sleep until rate limit resets if GraphQL remaining < 200.
  local payload remaining reset now wait
  payload=$(SB_GITHUB_READ_STRICT=1 python3 "$SB_GITHUB_READ" --kind quota -- api rate_limit) || return $?
  # REST misreports the GraphQL bucket; super-board-gh-guard.sh → sb_gh_quota_merge.
  payload=$(. "$(dirname "$SB_GITHUB_READ")/super-board-gh-guard.sh" && sb_gh_quota_merge "$payload")
  remaining=$(echo "$payload" | jq -r '.resources.graphql.remaining // 5000')
  if [ "$remaining" -lt 200 ]; then
    reset=$(echo "$payload" | jq -r '.resources.graphql.reset // 0')
    now=$(date +%s)
    wait=$((reset - now + 10))
    [ "$wait" -lt 60 ] && wait=60
    log "⚠ GraphQL rate limit low (${remaining} left) — sleeping ${wait}s until reset"
    tick_sleep "$wait"
  fi
}

try_claim_assignee() {
  # Atomic claim. Returns 0 if we won the claim, 1 if someone else beat us.
  # Skipped when bot_identity is unset (solo single-user runs rely on local locks only).
  # We rely on `top_card_in_column` having already filtered out cards with assignees
  # from the cached project item-list — so we attempt the edit directly without a
  # pre-check `gh issue view`. Saves one GraphQL call per dispatch. The edit is
  # idempotent for self-assign; on race-loss, gh returns non-zero and we skip.
  local issue="$1"
  [ -z "$BOT_LOGIN" ] && return 0
  gh_checkpoint
  gh_write_once issue edit "$issue" --add-assignee "$BOT_LOGIN" >/dev/null 2>&1 || {
    log "claim failed on #${issue} (race or gh api error) — skipping this tick"
    return 1
  }
  return 0
}

lane_worktree_hint() {
  # $1 = lane, $2 = issue. Worktree của lane chỉ do DevKit tạo (agent-workbench#93): `git worktree add` trần thiếu .agents/devkit,
  # link profile và các hook bị ignore mà settings gọi (health FAIL; NFH #18: lệnh ma trận exit 127, 5 thẻ Blocked) và import lại cả
  # Library Unity mỗi worktree (Goods ~9,9 GB). --lane không chiếm chỗ WORKTREE_MAX; sàn đĩa vẫn từ chối bằng exit 4.
  local cmd
  case "$1" in
    review) cmd="agent-kit worktree add .claude/worktrees/issue-$2-review --lane=review --base=origin/<PR branch> (detached; refresh with git fetch origin then git checkout --detach origin/<PR branch>)" ;;
    *) cmd="agent-kit worktree add .claude/worktrees/issue-$2-$1 issue-$2-<slug> --lane=$1 --base=origin/<config.base_branch> (an existing issue branch is checked out as it is, one only origin has from origin/<branch>, and the lane's worktree already at that path is reused)" ;;
  esac
  printf '%s' "Worktree: after git fetch origin, create it from the repo root ONLY with the DevKit, never plain git worktree add or EnterWorktree: $cmd. It links the DevKit, copies the git-ignored config and hooks and clones a Unity Library copy-on-write; no agent-kit on PATH: python3 .agents/devkit/scripts/git/worktree.py add with the same arguments. Exit 4 = under the disk floor: stop with its message, card and claims unchanged. Exit 1 naming a worktree that holds the branch: git worktree remove that path (refused = it holds work: Block the card naming it), then add again. Clean up on exit with git worktree remove <path> (the branch stays)."
}

worktree_disk_room() {
  # $1 = đường dẫn worktree của lane. Đúng bước giữ chỗ của `agent-kit worktree add` (worktree.py _make_room: dưới mức cảnh báo thì
  # worktree gc trước, còn dưới sàn WORKTREE_DISK_MIN_GIB thì exit 4): một luật, không chép số, và gc vẫn chạy nên board không đứng
  # chờ người dọn tay. Dưới sàn lane nào cũng dừng ở bước tạo worktree, nên không nhận thẻ và không mở một phiên claude mỗi tick.
  # Worktree lane đã có (git còn nhận nó: không phải thư mục rỗng sót lại, cũng không phải .git trỏ vào admin dir đã bị prune) thì
  # add --lane dùng lại, không tốn thêm đĩa. Kiểm không được (không DevKit, python lỗi): coi là còn chỗ, nhưng ghi log (OCR 19/10).
  [ -e "$1/.git" ] && git -C "$1" rev-parse --git-dir >/dev/null 2>&1 && return 0
  # Under the floor a full `worktree gc` runs once, then rests SB_DISK_GC_BACKOFF_S (300 s): a gc that freed nothing frees nothing more
  # a tick later, and every lane of every tick ran one (OCR batch 19/10). While it rests only the free space is read, so a disk a
  # person cleans is seen at the next check. DISK_GC_NEXT lives in the runner shell (dispatch_lane is called there, not in a subshell).
  local rc=0 err now gc=1 rest
  rest=${SB_DISK_GC_BACKOFF_S:-300}
  case "$rest" in ''|*[!0-9]*) rest=300 ;; esac   # `5m` / `abc` in the arithmetic below would end the runner
  now=$(date +%s)
  [ "$now" -lt "${DISK_GC_NEXT:-0}" ] && gc=0
  err=$(python3 - "$REPO_ROOT/.agents/devkit/scripts/git/worktree.py" "$REPO_ROOT" "$1" "$gc" 2>&1 >/dev/null <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("devkit_worktree", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
free = m.free_gib(sys.argv[3])
if free is not None and m.DISK_MIN_GIB and free < m.DISK_MIN_GIB:   # gc only when already under the floor: above it the own add of the lane does it
    if sys.argv[4] == "1":
        m._make_room(sys.argv[2], sys.argv[3])   # SystemExit(NO_ROOM=4) still under the floor after gc
    else:
        print("only %.1f GiB free on the disk (under %g GiB; worktree gc rests after one that freed too little)" % (free, m.DISK_MIN_GIB), file=sys.stderr)
        sys.exit(4)
PY
  ) || rc=$?
  case "$rc:$gc" in
    4:1) DISK_GC_NEXT=$((now + rest)) ;;   # gc ran and the disk is still under the floor: rest
    0:*) DISK_GC_NEXT=0 ;;                 # back above the floor: a later fall under it gets its gc at once
  esac
  case "$rc" in
    0) ;;
    4) log "worktree_disk_room: $(printf '%s' "$err" | tail -1 | cut -c1-200)" ;;   # the DevKit's own line: free GiB and the floor
    *) log "⚠ worktree_disk_room: DevKit disk check failed (rc=${rc}: $(printf '%s' "$err" | tail -1 | cut -c1-200)) — assuming room" ;;
  esac
  [ "$rc" -ne 4 ]
}

dispatch_lane() {
  # $1 = lane (build|qa|review); $2 = issue number
  local lane="$1" issue="$2" prompt pid
  if issue_locked "$issue"; then
    log "skip dispatch lane=${lane} issue=#${issue} — already locked"
    return 0
  fi
  # Authoritative closed-issue gate (issue #10). top_card_in_column also filters and
  # reconciles, but every dispatch path funnels through here — one guard, one place.
  gh_checkpoint
  local issue_rc=0
  issue_is_open "$issue" || issue_rc=$?
  [ "$issue_rc" -le 1 ] || exit "$issue_rc"
  if [ "$issue_rc" -ne 0 ]; then
    log "skip dispatch lane=${lane} issue=#${issue} — issue is CLOSED"
    return 0
  fi
  local card skills_rc=0 skills_report
  card=$(echo "$PROJECT_ITEMS_JSON" | jq -c --argjson n "$issue" --arg lane "$lane" '
    [.items[] | select(.content.number == $n) | {number:$n, status:(.status // "Ready"), labels:(.labels // .content.labels // []), lane:$lane}]')
  [ "$(printf '%s' "$card" | jq length)" -eq 1 ] || { log "skills-readiness: selected issue #${issue} missing from board cache"; exit 64; }
  skills_report=$(printf '%s' "$card" | python3 "$(dirname "$SB_GITHUB_READ")/super-board-skills-ready.py"     --root "$PWD" --host claude --cards - --hydrate) || skills_rc=$?
  if [ "$skills_rc" -ne 0 ]; then
    log "skills-readiness: halt before claim lane=${lane} issue=#${issue}; ${skills_report}"
    exit "$skills_rc"
  fi
  if ! worktree_disk_room "$REPO_ROOT/.claude/worktrees/issue-${issue}-${lane}"; then
    log "skip dispatch lane=${lane} issue=#${issue} — disk under the DevKit worktree floor (WORKTREE_DISK_MIN_GIB): free space first"
    return 0
  fi
  # Chọn account TRƯỚC khi nhận thẻ: hết cả 6 account thì không nhận, không giao (trước đây rơi về `claude` mặc định
  # trên account đã hết, worker chết sau ~30 s và runner giao lại mãi).
  if ! resolve_worker_account; then
    log "skip dispatch lane=${lane} issue=#${issue} — every worker account is at its limit${POOL_RESETS:+ (earliest reset ${POOL_RESETS})}"
    return 0
  fi
  if ! try_claim_assignee "$issue"; then
    return 0
  fi
  case "$lane" in
    build)  prompt="Run super-build on issue #${issue} for super-board run. Read .claude/skills/super-board/references/run.md → Builder lifecycle. Config: ${CONFIG_PATH}." ;;
    qa)     prompt="Run super-qa on issue #${issue} for super-board run. Read .claude/skills/super-board/references/run.md → Tester lifecycle. Config: ${CONFIG_PATH}." ;;
    review) prompt="Run super-review on issue #${issue} for super-board run. Read .claude/skills/super-board/references/run.md → Reviewer lifecycle. Config: ${CONFIG_PATH}. In headless super-board Review lane, your independent review + truth-check sub-agents satisfy the independent audit requirement; when ACs, tests, and truth-checks pass with no blockers, proceed directly to merge via .claude/bin/super-board-merge-gate.sh and move the card to Done." ;;
    *) log "unknown lane: $lane"; return 1 ;;
  esac
  prompt="First operation: run .claude/bin/super-board-skills-ready.py --root '$PWD' --host claude --cards - --lane '$lane' --hydrate with $card as stdin. Halt on exit 10 before worktree creation or lifecycle writes; preserve claims and approval evidence. Load resolved paths and only declared fallbacks; recheck conditionals with --require before activation. $prompt $(lane_worktree_hint "$lane" "$issue")"
  if [ -f "$REPO_ROOT/.agents/active-profile.json" ] && grep -q '"lang": "vi"' "$REPO_ROOT/.agents/active-profile.json" 2>/dev/null; then
    prompt="$prompt Language policy: This repository uses Vietnamese ('lang': 'vi'). Write all PR descriptions, problem/solution/AC explanations, status comments, and review notes in Vietnamese (Tiếng Việt); identifiers/symbols remain English."
  fi
  # Worker output goes to a per-worker log, not /dev/null (issue #13). Redirect at the
  # `claude` invocation itself — no wrapping subshell, no `exec` — so the wire to the
  # file survives and `$!` names the worker process rather than a bash stub.
  local worker_log="${WORKER_LOG_DIR}/worker-${lane}-${issue}.log"
  # The folder is made at startup only; gone since (19/10: no 2026-10-19-*-workers folder), every `>> $worker_log` below fails and
  # the worker never starts — dying at once, tick after tick (#94). Made again here, before anything is written to it.
  mkdir -p "$WORKER_LOG_DIR" 2>/dev/null || log "⚠ cannot make the worker log folder $WORKER_LOG_DIR"
  {
    printf '=== dispatch lane=%s issue=#%s at %s ===\n' "$lane" "$issue" "$(date -u +%FT%TZ)"
    printf 'prompt: %s\n\n' "$prompt"
  } >> "$worker_log"
  ln -sf "$PWD/$worker_log" "docs/super-board/current-worker.log" 2>/dev/null || true
  gh_checkpoint
  local pool_engine="$POOL_ENGINE" pool_acct="$POOL_ACCT" pool_cfg="$POOL_CFG"
  # note_worker_limit đọc dòng này để biết account nào hết limit.
  [ -n "$pool_acct" ] && printf 'account_pool: engine=%s account=%s config_dir=%s\n' "$pool_engine" "$pool_acct" "$pool_cfg" >> "$worker_log"
  export DEVKIT_ALLOW_BRANCH=1 WORKTREE_MERGE_GATE=0 DEVKIT_LANG="${DEVKIT_LANG:-vi}"
  unset POSTFIX_GATE_FORCE_FULL
  if [ "$pool_engine" = "antigravity" ] && [ -x "$HOME/.local/bin/agy" ]; then
    nohup "$HOME/.local/bin/agy" --model gemini-4-argon-high --effort xhigh --dangerously-skip-permissions -p "$prompt" >> "$worker_log" 2>&1 &
  elif [ "$pool_engine" = "grok" ] && [ -x "$HOME/.grok/bin/grok" ]; then
    nohup "$HOME/.grok/bin/grok" -m grok-4.7 -p "$prompt" >> "$worker_log" 2>&1 &
  elif [ -n "$pool_cfg" ]; then
    CLAUDE_CONFIG_DIR="$pool_cfg" nohup claude --dangerously-skip-permissions -p "$prompt" >> "$worker_log" 2>&1 &
  else
    nohup claude --dangerously-skip-permissions -p "$prompt" >> "$worker_log" 2>&1 &
  fi
  pid=$!
  DISPATCH_COUNT=$((DISPATCH_COUNT + 1))
  DISPATCH_LOG="${DISPATCH_LOG}${issue}
"
  # v1.3.0+ lock format: bash-assignment style so `super-board stop` can source it
  # to recover lane + dispatch time. issue_locked()/reap_finished_locks() still work
  # because PID= is the first line.
  printf 'PID=%s\nLANE=%s\nSTARTED=%s\n' "$pid" "$lane" "$(date -u +%FT%TZ)" > "$INFLIGHT_DIR/$issue"
  case "$lane" in
    build) BUILD_PID="$pid"; BUILD_ISSUE="$issue" ;;
    qa) QA_PID="$pid"; QA_ISSUE="$issue" ;;
    review) REVIEW_PID="$pid"; REVIEW_ISSUE="$issue" ;;
  esac
  log "dispatch lane=${lane} issue=#${issue} pid=${pid} claim=${BOT_LOGIN:-local-only}"
}

issue_status() {
  # Lookup issue #$1 in the cached project items; emit its current column name (or empty).
  echo "$PROJECT_ITEMS_JSON" | jq -r --arg n "$1" '
    .items[] | select(.content.number == ($n | tonumber)) | .status' | head -1
}

check_lane_zombie() {
  # $1 = lane name (build|qa|review); $2 = space-separated list of expected source columns.
  # If the lane's worker PID is alive but its claimed issue has already moved to a column
  # NOT in the expected source set, the worker's logical work is done — kill the zombie
  # process and free the lane. Uses cached project items only (no extra API calls).
  local lane="$1" expected="$2" pid="" issue=""
  case "$lane" in
    build)  pid="$BUILD_PID";  issue="$BUILD_ISSUE" ;;
    qa)     pid="$QA_PID";     issue="$QA_ISSUE" ;;
    review) pid="$REVIEW_PID"; issue="$REVIEW_ISSUE" ;;
    *) return 1 ;;
  esac
  [ -z "$pid" ] && return 0
  [ -z "$issue" ] && return 0
  kill -0 "$pid" 2>/dev/null || return 0   # already dead → reap_finished_locks handles it
  local cur found=0 col
  cur=$(issue_status "$issue")
  [ -z "$cur" ] && return 0                # not in cache (closed/deleted/race) → don't kill
  # Thẻ `qa` được giao từ Ready và Tester tự chuyển Ready → QA sau khi khởi động (run.md, Tester lượt đầu).
  # Khi thẻ của Tester này chưa từng thấy ở QA thì Ready không phải dấu hiệu zombie; sau đó Ready là đường
  # fail của Tester và giải phóng lane như cũ. QA_SEEN_IN_QA giữ PID đã thấy, nên Tester mới trên cùng thẻ
  # bắt đầu sạch.
  # ponytail: Tester treo trước bước chuyển đầu tiên giữ lane QA tới khi được thu hồi tay; thêm trần ân hạn
  # tính theo thời điểm đọc board (không theo đồng hồ, cache có thể cũ ở tick cap-reached) nếu việc này xảy ra.
  if [ "$lane" = qa ]; then
    if [ "$cur" = QA ]; then QA_SEEN_IN_QA="$pid"
    elif [ "${QA_SEEN_IN_QA:-}" != "$pid" ]; then expected="$expected Ready"; fi
  fi
  for col in $expected; do
    [ "$cur" = "$col" ] && found=1
  done
  if [ "$found" -eq 0 ]; then
    gh_checkpoint
    log "💀 zombie ${lane} worker on #${issue} (pid=${pid}) — card moved to '${cur}'; killing"
    kill "$pid" 2>/dev/null || true
    sleep 1 || true
    kill -9 "$pid" 2>/dev/null || true
    gh_checkpoint
    [ -n "$BOT_LOGIN" ] && gh_write_once issue edit "$issue" --remove-assignee "$BOT_LOGIN" >/dev/null 2>&1 || true
    gh_checkpoint
    rm -f "$INFLIGHT_DIR/$issue"
    case "$lane" in
      build)  BUILD_PID="";  BUILD_ISSUE="" ;;
      qa)     QA_PID="";     QA_ISSUE="" ;;
      review) REVIEW_PID=""; REVIEW_ISSUE="" ;;
    esac
  fi
}

sweep_lane_zombies() {
  check_lane_zombie build  "Ready Building QA Review"
  check_lane_zombie qa     "QA"
  check_lane_zombie review "Review"
}

done_signature() {
  # The set of cards that have LANDED, as a stable string. This — not lane
  # occupancy — is the run's definition of forward progress (issue #8).
  # A card deliberately dropped is closed and moved to Done too (v3.0.0: no Skipped column).
  echo "$PROJECT_ITEMS_JSON" | jq -r '
    [.items[] | select(.status == "Done") | .content.number // empty]
    | sort | @csv' 2>/dev/null || echo ""
}

record_cycle_progress() {
  # One dispatch cycle's verdict on forward progress (issue #8).
  # Reads/writes PREV_DONE_SIG + NO_PROGRESS_CYCLE_COUNT + LANDED_COUNT.
  # Returns 0 = keep running, 1 = halt (runaway).
  # $1 = the current done signature (injected so tests need no board).
  local cur="$1"
  # Đang hoãn giao việc sau RUNAWAY: không giao gì thì không tính là một chu kỳ không tiến triển.
  dispatch_paused && return 0
  if [ "$cur" != "$PREV_DONE_SIG" ]; then
    LANDED_COUNT=$((LANDED_COUNT + 1))
    NO_PROGRESS_CYCLE_COUNT=0
    PREV_DONE_SIG="$cur"
    return 0
  fi
  NO_PROGRESS_CYCLE_COUNT=$((NO_PROGRESS_CYCLE_COUNT + 1))
  [ "$NO_PROGRESS_CYCLE_COUNT" -lt "$NO_PROGRESS_CYCLES" ]
}

dispatch_ceiling_hit() {
  # Returns 0 when the hard spend ceiling is reached. MAX_DISPATCHES=0 disables it.
  [ "$MAX_DISPATCHES" -gt 0 ] && [ "$DISPATCH_COUNT" -ge "$MAX_DISPATCHES" ]
}

runaway_summary() {
  # Loud, actionable halt line: what the run spent, and on what.
  log "   dispatches=${DISPATCH_COUNT} reaps=${REAP_COUNT} cards-landed-this-run=${LANDED_COUNT}"
  local top
  top=$(printf '%s' "$DISPATCH_LOG" | grep -c . 2>/dev/null || echo 0)
  if [ "${top:-0}" -gt 0 ]; then
    log "   most re-dispatched issues (count issue):"
    printf '%s' "$DISPATCH_LOG" | grep . | sort | uniq -c | sort -rn | head -5 | while read -r line; do
      log "     $line"
    done
  fi
  log "   → inspect worker logs in ${WORKER_LOG_DIR}/"
}

runaway_action() {
  # Cổng "có thẻ về Done" đã bật (issue #8). Lần chạy một lượt thì dừng (trả 1). Daemon (SB_DAEMON=1,
  # super_board_all.py start) giữ board chạy nhưng vẫn có giới hạn: báo runaway, không giao worker mới trong
  # 10 tick (worker đang chạy vẫn tiếp tục), rồi đếm lại (trả 0).
  if [ "${SB_DAEMON:-0}" = "1" ]; then
    log "⚠ RUNAWAY (daemon): no card reached Done in ${NO_PROGRESS_CYCLES} dispatch cycles — no new dispatch for $((TICK_SECONDS * 10))s"
    runaway_summary
    NO_PROGRESS_CYCLE_COUNT=0
    # Hạn chót chứ không sleep: thu hồi lock và quét zombie vẫn chạy mỗi tick, chỉ việc giao mới bị hoãn.
    RUNAWAY_PAUSE_UNTIL=$(( $(date +%s) + TICK_SECONDS * 10 ))
    return 0
  fi
  log "🛑 halt — RUNAWAY: no card reached Done in ${NO_PROGRESS_CYCLES} dispatch cycles"
  runaway_summary
  return 1
}

dispatch_paused() {
  # 0 khi daemon đang trong khoảng hoãn giao việc sau RUNAWAY (runaway_action đặt hạn chót).
  [ "${RUNAWAY_PAUSE_UNTIL:-0}" -gt "$(date +%s)" ]
}

PAUSED_READ_EVERY=3
paused_tick() {
  # Một tick trong khoảng hoãn sau RUNAWAY. Không giao được gì nên tick thường không đọc GraphQL, nhưng cứ
  # PAUSED_READ_EVERY tick thì đọc board một lần và quét zombie trên dữ liệu mới: chỉ quét trên cache cũ (37aec8a
  # bỏ hẳn lần đọc) thì worker có thẻ đã sang cột khác trong lúc hoãn giữ lane tới hết hạn chót.
  PAUSED_TICKS=$(( ${PAUSED_TICKS:-0} + 1 ))
  [ $(( PAUSED_TICKS % PAUSED_READ_EVERY )) -eq 0 ] || return 0
  gh_rate_guard
  fetch_project_items
  sweep_lane_zombies
}

# A folder in inflight/ (git-ignored in every board repo); every reader of inflight/ skips folders and non-numeric names, as merge.lock
early_death_file() { printf '%s/early-deaths/%s' "$INFLIGHT_DIR" "$1"; }

note_early_death() {
  # $1 = issue; the lock just read (LANE, STARTED) is the worker that died. #94 (18/10 19:26–19:47Z): a worker dying ~33 s after
  # each dispatch made reap free the card and the next tick claim it again, every ~40 s, until the board halted. A worker that died
  # within SB_EARLY_DEATH_S (120 s) of its dispatch is recorded here as "<epoch> <lane>", with the last line of its log, so the card
  # can cool down in that lane. Bookkeeping only: under the runner's `set -euo pipefail` no step here may end the runner.
  local age f last n now wlog="${WORKER_LOG_DIR}/worker-${LANE:-?}-${1}.log"
  # How long the worker lived: up to its log's last write. Reap runs once per tick (tick_seconds, 120 by default), so "now" can be a
  # whole tick after the death (review 19/10: measured at reap time, no worker ever counted). No log: now, with one tick of slack.
  # The log's mtime counts only when later than STARTED: `claude -p` (text mode) writes nothing until it ends, so a long silent
  # run that was killed leaves just the dispatch header, written before STARTED (OCR 19/10). Either way the worker must have been
  # dispatched less than the limit plus one tick ago.
  age=$(python3 -c 'import calendar, os, sys, time
start = calendar.timegm(time.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ"))
limit, tick = int(sys.argv[3]), int(sys.argv[4])
since = time.time() - start
try:
    end = os.path.getmtime(sys.argv[2])
except OSError:
    end = None
lived = end - start if end is not None and end > start else None
early = since < limit + tick and (lived is None or lived < limit)
print(int(lived if lived is not None else since), 1 if early else 0)' "${STARTED:-}" "$wlog" "${SB_EARLY_DEATH_S:-120}" "${TICK_SECONDS:-0}" 2>/dev/null) || return 0
  case "$age" in *" 1") age=${age% *} ;; *) return 0 ;; esac
  now=$(date +%s)
  f=$(early_death_file "$1")
  mkdir -p "$(dirname "$f")" 2>/dev/null || return 0
  # keep only the window: the file never grows past a few lines
  { awk -v from=$((now - ${SB_EARLY_WINDOW_S:-600})) '$1 >= from' "$f" 2>/dev/null || true; echo "$now ${LANE:-?}"; } > "$f.tmp" 2>/dev/null \
    && mv "$f.tmp" "$f" 2>/dev/null || return 0
  # the log may be gone or empty (the 19/10 shape): grep exits 1/2, which pipefail would turn into the runner's exit
  last=$( { grep -v '^[[:space:]]*$' "${WORKER_LOG_DIR}/worker-${LANE:-?}-${1}.log" 2>/dev/null || true; } | tail -1 | cut -c1-200)
  n=$( { awk -v l="${LANE:-?}" '$2 == l' "$f" 2>/dev/null || true; } | wc -l | tr -d ' ')
  log "⚠ worker of #${1} (lane ${LANE:-?}) ended ${age}s after dispatch (a crash or a very quick exit) — early end ${n} of this lane in ${SB_EARLY_WINDOW_S:-600}s; last log line: ${last:-<no worker log at ${WORKER_LOG_DIR}/worker-${LANE:-?}-${1}.log>}"
}

early_backoff() {
  # $1 = issue, $2 = the column a lane takes it from. 0 = 2 early deaths of a lane serving that column within SB_EARLY_WINDOW_S: no
  # third claim until the window passes (AC of #94: at most 2 assign/unassign cycles per card in 10 minutes). Per lane: a Reviewer
  # that bounced the card to Ready in seconds says nothing about the Builder taking it next, nor two quick builds about its review.
  local f now n lanes
  case "${2:-}" in
    Ready) lanes=$(card_lane "$1") ;;   # the lane that takes it from Ready: build, or qa for a `qa`-labelled card
    QA) lanes="qa" ;;
    Review) lanes="review" ;;
    *) return 1 ;;
  esac
  f=$(early_death_file "$1")
  [ -f "$f" ] || return 1
  now=$(date +%s)
  n=$( { awk -v from=$((now - ${SB_EARLY_WINDOW_S:-600})) -v lanes=" $lanes " '$1 >= from && index(lanes, " " $2 " ")' "$f" 2>/dev/null || true; } \
       | wc -l | tr -d ' ')
  [ "${n:-0}" -ge 2 ]
}

reap_finished_locks() {
  # Sweep inflight/ for dead PIDs; remove locks AND sweep stale assignees so the
  # next dispatch can re-claim the card if the worker crashed without releasing.
  # The assignee remove is idempotent — no-op if the worker exited cleanly.
  local lock issue
  for lock in "$INFLIGHT_DIR"/*; do
    gh_checkpoint
    [ -f "$lock" ] || continue
    issue=$(basename "$lock")
    # Issue locks only: basenames are issue numbers. Anything else (e.g. the
    # workflow backend's workflow-wave.lock) is not ours to reap — deleting it
    # would dissolve the backend mutual exclusion mid-run.
    case "$issue" in *[!0-9]*|'') continue ;; esac
    read_lock "$issue"
    if [ -z "$PID" ] || ! kill -0 "$PID" 2>/dev/null; then
      [ -z "$LANE" ] || note_worker_limit "${WORKER_LOG_DIR}/worker-${LANE}-${issue}.log"
      note_early_death "$issue"
      gh_checkpoint
      if [ -n "$BOT_LOGIN" ]; then
        gh_checkpoint
        gh_write_once issue edit "$issue" --remove-assignee "$BOT_LOGIN" >/dev/null 2>&1 || true
        log "reaped stale lock + swept assignee on #${issue} (pid=${PID:-empty})"
      else
        log "reaped stale lock for #${issue} (pid=${PID:-empty})"
      fi
      gh_checkpoint
      rm -f "$lock"
      REAP_COUNT=$((REAP_COUNT + 1))
    fi
  done
}

pid_started_after() {
  # 0 khi tiến trình $1 khởi động muộn hơn thời điểm $2 (STARTED của lock, ISO UTC) quá 5 s. Worker ghi lock ngay sau
  # khi khởi tạo (giờ khởi động trùng STARTED tới từng giây, đo 16/10), nên PID tái dùng luôn khởi động muộn hơn.
  # Không đo được (ps lỗi, STARTED trống hoặc sai dạng) thì trả 1: không gỡ gì.
  local age
  age=$(ps -o etime= -p "$1" 2>/dev/null | awk -F'[-:]' 'NF >= 2 { t = $NF + 60 * $(NF-1); if (NF >= 3) t += 3600 * $(NF-2); if (NF >= 4) t += 86400 * $(NF-3); print t }') || return 1
  [ -n "$age" ] && [ -n "${2:-}" ] || return 1
  python3 -c 'import calendar, sys, time
sys.exit(0 if time.time() - int(sys.argv[2]) > calendar.timegm(time.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ")) + 5 else 1)' "$2" "$age" 2>/dev/null
}

adopt_live_locks() {
  # Lúc khởi động: worker do lần chạy trước khởi tạo (nohup) vẫn sống sau khi runner cũ chết. Đưa từng worker
  # còn sống về lại lane của nó, nếu không lần chạy này thấy lane rảnh và khởi thêm worker thứ hai bên cạnh.
  # Lock chết đã được dọn trước đó.
  local lock issue cmdline
  for lock in "$INFLIGHT_DIR"/*; do
    [ -f "$lock" ] || continue
    issue=$(basename "$lock")
    case "$issue" in *[!0-9]*|'') continue ;; esac
    read_lock "$issue"
    { [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; } || continue
    # Sau khi khởi động lại máy, PID có thể thuộc tiến trình bất kỳ; dòng lệnh của worker luôn mang prompt của lane.
    # ps lỗi hoặc không in gì: không xác minh được, nên không nhận lại và cũng không gỡ lock (có thể là worker thật).
    cmdline=$(ps -ww -o command= -p "$PID" 2>/dev/null || true)
    [ -n "$cmdline" ] || continue
    # PID tái dùng: worker của lock đã chết, nên gỡ lock + assignee như reap_finished_locks (để nguyên thì
    # issue_locked thấy PID sống và bỏ qua thẻ mãi). Tiến trình lạ đó không bao giờ bị gửi tín hiệu.
    case "$cmdline" in
      *"issue #${issue} for super-board run"*) ;;
      *)
        # Dòng lệnh không khớp chưa đủ: chỉ gỡ khi tiến trình khởi động sau STARTED của lock (chắc chắn PID tái
        # dùng); nếu không, có thể là worker thật đã đổi tiêu đề tiến trình, giữ lock như trước.
        pid_started_after "$PID" "$STARTED" || continue
        gh_checkpoint
        if [ -n "$BOT_LOGIN" ]; then
          gh_write_once issue edit "$issue" --remove-assignee "$BOT_LOGIN" >/dev/null 2>&1 || true
        fi
        gh_checkpoint
        rm -f "$lock"
        REAP_COUNT=$((REAP_COUNT + 1))
        log "reaped lock on #${issue}: pid=${PID} is alive but no super-board worker (recycled PID)${BOT_LOGIN:+; swept assignee}"
        continue ;;
    esac
    case "$LANE" in
      build)  BUILD_PID="$PID";  BUILD_ISSUE="$issue" ;;
      qa)     QA_PID="$PID";     QA_ISSUE="$issue" ;;
      review) REVIEW_PID="$PID"; REVIEW_ISSUE="$issue" ;;
      *) continue ;;
    esac
    ADOPTED_PIDS="${ADOPTED_PIDS:-} $PID"
    log "adopted live ${LANE} worker on #${issue} (pid=${PID}) from the previous run"
  done
}

own_lane_pids() {
  # PID trong các lane do chính lần chạy này khởi tạo (không phải nhận lại): khi dừng khẩn chỉ kill các PID này
  # (hợp đồng của halt_cleanup).
  local pid
  for pid in "${BUILD_PID:-}" "${QA_PID:-}" "${REVIEW_PID:-}"; do
    [ -n "$pid" ] || continue
    case " ${ADOPTED_PIDS:-} " in *" $pid "*) continue ;; esac
    echo "$pid"
  done
}

startup_orphan_workers() {
  # $1 = thư mục repo (đúng giá trị dispatch_lane đưa vào `--root '…'` của prompt). In PID của worker super-board
  # (claude/agy/grok) thuộc CHÍNH repo này mà không lock nào trong inflight/ trỏ tới: worker có lock đã được
  # adopt_live_locks nhận lại. So chuỗi cố định kèm dấu nháy đóng (repo `X-2` không khớp repo `X`), và argv[0] phải
  # là claude/agy/grok để shell chẩn đoán có chuỗi đó trong tham số không bị tính (21:52 ngày 16/10).
  local root="$1" locked=" " lock issue pid cmd exe
  for lock in "$INFLIGHT_DIR"/*; do
    [ -f "$lock" ] || continue
    issue=$(basename "$lock")
    case "$issue" in *[!0-9]*|'') continue ;; esac
    read_lock "$issue" || continue
    [ -n "$PID" ] && locked="${locked}${PID} "
  done
  # ps lỗi thì không có dòng nào: không chặn khởi động (adopt_live_locks vẫn chạy sau đó).
  while read -r pid cmd; do
    [ -n "$pid" ] && [ "$pid" != "$$" ] || continue
    case "$cmd" in *"--root '${root}'"*"for super-board run"*) ;; *) continue ;; esac
    exe=${cmd%% *}
    case "${exe##*/}" in claude|agy|grok) ;; *) continue ;; esac
    case "$locked" in *" $pid "*) continue ;; esac
    echo "$pid"
  done < <(ps -ww -A -o pid= -o command= 2>/dev/null || true)
}

check_legacy_worktrees() {
  # Never strand a previous run's edits by silently switching its folder.
  local wt
  for wt in .worktrees/issue-*; do
    [ -e "$wt" ] || continue
    log "🛑 legacy worktree $wt exists — stop its worker and inspect/preserve its edits"
    log "    Move it with git worktree move to .claude/worktrees/ before resuming."
    return 73
  done
  return 0
}

cleanup_stale_worktrees() {
  # This directory also holds Claude's unrelated worktrees. Only board names
  # belong to this sweep, and a failed Git removal must never become rm -rf.
  local wt branch
  for wt in .claude/worktrees/issue-*; do
    [ -d "$wt" ] || continue
    [[ "${wt##*/}" =~ ^issue-[0-9]+(-(build|qa|review))?$ ]] || continue
    branch=$(git -C "$wt" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
    # Detached work may contain commits with no other ref; it is not proof of staleness.
    [ -n "$branch" ] || continue
    if ! git rev-parse --verify "refs/heads/$branch" >/dev/null 2>&1; then
      if git worktree remove "$wt" 2>/dev/null; then
        log "stale worktree: $wt (branch '$branch' missing) — removed"
      else
        log "⚠ kept worktree $wt — inspect its edits/lock before cleanup"
      fi
    fi
  done
  return 0
}

reclaim_stranded_building() {
  # Run start only (no worker of ours is alive yet — the orphan guard proved it).
  # A card in Building with no live in-flight lock and no assignee but ours was
  # stranded by a run that stopped mid-build. No lane selects from Building, so
  # left alone it sits there forever and the run can never reach "all columns
  # empty". Move it back to Ready and say so; the issue branch is kept, so the
  # next Builder continues on it instead of starting over.
  local issue item_id branch wt wt_branch
  while IFS=$'\t' read -r issue item_id; do
    [ -n "$issue" ] || continue
    issue_locked "$issue" && continue
    # Chỉ để ghi vào comment: ls-remote lỗi (mạng, không có remote) dưới pipefail không được giết runner.
    branch=$(git ls-remote --heads origin "issue-${issue}-*" 2>/dev/null | head -1 | sed 's#.*refs/heads/##') || branch=""
    wt=".claude/worktrees/issue-${issue}-build"
    if [ -d "$wt" ]; then
      wt_branch=$(git -C "$wt" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
      if [ -z "$wt_branch" ]; then
        log "⚠ stranded #${issue}: kept $wt and Building status — inspect its detached commits/edits/lock before resuming"
        continue
      fi
      git worktree remove "$wt" 2>/dev/null || log "ℹ stranded #${issue}: keeping existing worktree $wt (branch $wt_branch) for Builder to resume"
    fi
    if ! set_card_status "$item_id" "Ready"; then
      gh_checkpoint
      log "⚠ stranded #${issue} in Building — could not move it to Ready; drag it by hand"
      continue
    fi
    [ -n "$BOT_LOGIN" ] && gh_write_once issue edit "$issue" --remove-assignee "$BOT_LOGIN" >/dev/null 2>&1 || true
    # Comment format: writing-standard.md § 4.
    gh_checkpoint
    gh_write_once issue comment "$issue" --body "[orchestrator] [report] ↩️ back to Ready · stranded in Building
Did: found no live worker; the last run stopped mid-build
✅ Done: card moved to Ready · branch ${branch:-none found}${branch:+ kept}
Next: builder (next tick${branch:+, continues on the branch})" >/dev/null 2>&1 || true
    log "↩ stranded #${issue}: Building → Ready (branch ${branch:-none})"
  done <<EOF
$(echo "$PROJECT_ITEMS_JSON" | jq -r --arg bot "$BOT_LOGIN" '
    .items[]
    | select(.status == "Building" and .content.type == "Issue")
    | select(((.content.assignees // []) - [$bot]) | length == 0)
    | [(.content.number | tostring), (.id // "")] | @tsv')
EOF
}

startup_reconcile() {
  # Lúc khởi động, theo thứ tự: dọn lock chết, nhận lại worker còn sống (lock PID tái dùng bị gỡ ở đây), rồi mới trả
  # thẻ Building bị bỏ rơi về Ready. Đảo lại thì reclaim thấy lock PID tái dùng còn "sống" và bỏ qua thẻ, rồi adopt
  # gỡ lock: thẻ nằm Building suốt lần chạy. Worker được nhận lại vẫn giữ lock, nên reclaim vẫn bỏ qua thẻ của nó.
  reap_finished_locks
  BUILD_PID=""; BUILD_ISSUE=""
  QA_PID=""; QA_ISSUE=""
  REVIEW_PID=""; REVIEW_ISSUE=""
  adopt_live_locks
  gh_rate_guard
  fetch_project_items
  reclaim_stranded_building; fetch_project_items
}

sweep_blocked_cards() {
  # Thẻ Blocked có mọi blocker trên dòng `blocked-by:` đã đóng thì về lại Ready: danh sách `sweep` của wave
  # planner, đúng luật backend workflow áp giữa các wave. Thẻ chờ người (`blocked-by: -`) không bao giờ có
  # trong đó. Trả 0 khi có thẻ được chuyển (caller đọc lại board), 1 khi không có, 2 khi planner lỗi.
  local items_file plan rc=0 moved=1 issue item_id cleared
  items_file=$(mktemp "${TMPDIR:-/tmp}/sb-items.XXXXXX")
  printf '%s' "$PROJECT_ITEMS_JSON" > "$items_file"
  plan=$("$(dirname "$SB_GITHUB_READ")/super-board-wave-plan.sh" --config "$CONFIG_PATH" --items "$items_file" 2>>"$RUN_MANIFEST") || rc=$?
  rm -f "$items_file"
  if [ "$rc" -ne 0 ]; then
    gh_checkpoint
    log "⚠ blocked sweep skipped: wave planner exit ${rc}; retrying in ${SWEEP_RETRY_SECONDS}s"
    return 2
  fi
  local next key
  while IFS=$'\t' read -r issue cleared; do
    # Không có blocker nào (thẻ bị kéo tay sang Blocked, body ghi None): không có gì vừa đóng, để người quyết.
    [ -n "$issue" ] && [ -n "$cleared" ] || continue
    # Mỗi (thẻ, bộ blocker) một lần mỗi lần chạy: bị park lại với CÙNG blocker là việc người cần xem, không phải
    # vòng lặp; bị chặn bởi blocker KHÁC (daemon chạy nhiều ngày) thì vẫn được sweep khi blocker mới đóng.
    key="${issue}:$(printf '%s' "$cleared" | tr -d ' #')"
    case " ${SWEPT_CARDS:-} " in *" $key "*) log "blocked sweep: #${issue} already swept this run for ${cleared} — left Blocked"; continue ;; esac
    # `needs-you` là quyết định của người, kể cả khi planner thả thẻ (planner chỉ đọc 8 comment cuối).
    if echo "$PROJECT_ITEMS_JSON" | jq -e --argjson n "$issue" '[.items[] | select(.content.number == $n)
         | ((.labels // []) + (.content.labels // []))[] | (if type == "object" then .name else . end) | ascii_downcase]
         | (index("needs-you") or index("human-gated"))' >/dev/null 2>&1; then   # any case, human-gated too (#95 review 19/10)
      continue
    fi
    item_id=$(echo "$PROJECT_ITEMS_JSON" | jq -r --argjson n "$issue" '[.items[] | select(.content.number == $n) | .id][0] // empty')
    [ -n "$item_id" ] || continue
    if ! set_card_status "$item_id" "Ready"; then
      gh_checkpoint
      log "⚠ blocked sweep: could not move #${issue} to Ready"
      continue
    fi
    SWEPT_CARDS="${SWEPT_CARDS:-} $key"
    next=builder; [ "$(card_lane "$issue")" = qa ] && next=tester
    # Định dạng comment: writing-standard.md § 4.
    gh_checkpoint
    gh_write_once issue comment "$issue" --body "[orchestrator] [report] ↩️ back to Ready · blockers closed
Did: every blocker on the last blocked-by line is closed (${cleared})
✅ Done: card moved Blocked → Ready
Next: ${next} (next tick)" >/dev/null 2>&1 || true
    log "↩ unblocked #${issue}: Blocked → Ready (cleared by ${cleared})"
    moved=0
  done <<EOF
$(printf '%s' "$plan" | jq -r '.sweep[]? | [(.number | tostring), ((.clearedBy // []) | unique | map("#" + tostring) | join(", "))] | @tsv' 2>/dev/null)
EOF
  return "$moved"
}

SWEEP_RETRY_SECONDS=300
maybe_sweep_blocked() {
  # Blocker chỉ được gỡ khi có thẻ về Done, nên planner (một lần đọc GraphQL các issue mở để dựng đồ thị phụ
  # thuộc) chạy lúc khởi động và mỗi khi tập Done đổi, không chạy mỗi tick. Planner lỗi (rate limit, mạng) được
  # thử lại sau SWEEP_RETRY_SECONDS, không phải đợi tới lần có thẻ về Done kế tiếp.
  # ponytail: blocker đóng ngoài board (tập Done không đổi) phải chờ lần về Done sau; sweep theo sự kiện issue nếu việc này gây kẹt.
  local sig rc=0
  sig=$(done_signature)
  if [ "$sig" = "${SWEEP_DONE_SIG-<none>}" ]; then
    [ "${SWEEP_RETRY_AT:-0}" -gt 0 ] && [ "$(date +%s)" -ge "$SWEEP_RETRY_AT" ] || return 1
  fi
  SWEEP_DONE_SIG="$sig"; SWEEP_RETRY_AT=0
  sweep_blocked_cards || rc=$?
  [ "$rc" -ne 2 ] || SWEEP_RETRY_AT=$(( $(date +%s) + SWEEP_RETRY_SECONDS ))
  return "$rc"
}

# ── Bản ghi trạng thái runner cho super-board-watchdog.sh: .claude/super-board/runner/<slug>.state
# (PID/SLUG/STARTED/DAEMON/LOG/STATE, thêm RC/ENDED khi thoát). STATE: running (còn nguyên khi bị SIGKILL) · crashed
# (thoát ngoài ý muốn) · finished (vòng lặp kết thúc: board rỗng, RUNAWAY, trần dispatch) · halted (mã dừng có chủ
# đích) · stopped (người dùng dừng: có stop marker <slug>.stopped của super-board-stop.sh). Watchdog chỉ khởi động lại
# running/crashed khi không có marker.
# Mã dừng có chủ đích sau khi trap EXIT được đặt: 9 verification-ready (mỗi tick) · 10 skills-readiness · 73 worker mồ
# côi / worktree cũ / runner khác còn sống · 74 wave lock · 75 guard production-merge · 79 GitHub halt. 64 không có ở đây:
# nó cũng là lỗi đọc của github-read (payload sai dạng 3 lần), thường tạm thời, nên watchdog thử lại có backoff và trần.
RUNNER_HALT_CODES=" 9 10 73 74 75 79 "
# Môi trường runner trả lại khi watchdog khởi động lại (toolchain + cấu hình pool/account). Token và secret cố ý không
# ghi xuống đĩa: gh và claude đọc chúng từ keychain, mà launchd agent trong phiên GUI của người dùng vẫn đọc được.
RUNNER_ENV_KEYS="PATH JAVA_HOME ANDROID_HOME ANDROID_SDK_ROOT SB_ACCOUNT_POOL SB_STATE_DIR CLAUDE_CONFIG_DIR DEVKIT_LANG"
runner_state_write() {
  # $1 = STATE, $2 = RC (khi thoát). Ghi nguyên tử (tmp + mv) để watchdog không đọc nửa file. Ghi lại mỗi tick:
  # bộ đếm chi tiêu (DISPATCHES, NO_PROGRESS, PAUSE_UNTIL) theo runner qua lần watchdog khởi động lại, để trần
  # max_dispatches và cổng RUNAWAY không bị một lần crash đặt lại về 0. ENV_* là môi trường của lần khởi động tường
  # minh (PATH, JDK, Android SDK): launchd chỉ có PATH tối thiểu, watchdog trả lại các biến này cho runner nó khởi động.
  # Ghi hỏng (đĩa đầy, thư mục không ghi được) không được giết runner dưới `set -e`: chính kiểu chết im lặng mà bản ghi
  # này sinh ra để phát hiện. Cảnh báo một lần, bỏ file tạm, đi tiếp (không có bản ghi thì watchdog không khởi động lại).
  local tmp="$RUNNER_STATE.$$" k
  if { {
    printf 'PID=%s\nSLUG=%s\nSTARTED=%s\nDAEMON=%s\nLOG=%s\nSTATE=%s\n' \
      "$$" "$CONFIG_SLUG" "$RUNNER_STARTED" "${SB_DAEMON:-0}" "$RUNNER_LOG" "$1"
    printf 'DISPATCHES=%s\nNO_PROGRESS=%s\nPAUSE_UNTIL=%s\n' \
      "${DISPATCH_COUNT:-0}" "${NO_PROGRESS_CYCLE_COUNT:-0}" "${RUNAWAY_PAUSE_UNTIL:-0}"
    for k in $RUNNER_ENV_KEYS; do printf 'ENV_%s=%s\n' "$k" "${!k:-}"; done
    [ -z "${2:-}" ] || printf 'RC=%s\nENDED=%s\n' "$2" "$(date +%s)"
  } > "$tmp" && mv -f "$tmp" "$RUNNER_STATE"; } 2>/dev/null; then
    STATE_WRITE_WARNED=""
    return 0
  fi
  rm -f "$tmp" 2>/dev/null || true
  [ -n "${STATE_WRITE_WARNED:-}" ] || log "⚠ could not write $RUNNER_STATE (disk full? unwritable?): the watchdog cannot see this runner"
  STATE_WRITE_WARNED=1
}

state_num() {
  # $1 = khoá số trong bản ghi runner hiện có; 0 khi thiếu hoặc không phải số.
  local v
  v=$(sed -n "s/^$1=//p" "$RUNNER_STATE" 2>/dev/null | head -1) || v=""
  case "$v" in ''|*[!0-9]*) v=0 ;; esac
  echo "$v"
}

runner_state_exit() {
  # Trap EXIT, $1 = mã thoát. Chỉ runner đang giữ bản ghi mới ghi: runner bị từ chối lúc khởi động (board đã dừng,
  # runner khác còn sống) không đè bản ghi của runner kia. bash 3.2 chạy trap EXIT cả khi chính nó bị SIGTERM, với
  # $? = 0, nên "finished" chỉ do RUNNER_END ở cuối script đặt, không suy ra từ rc 0.
  [ -n "${RUNNER_STATE:-}" ] && [ "$(sed -n 's/^PID=//p' "$RUNNER_STATE" 2>/dev/null | head -1)" = "$$" ] || return 0
  local end="${RUNNER_END:-}"
  if [ -z "$end" ]; then
    if [ -e "$STOP_MARK" ]; then
      end=stopped
    else
      case "$RUNNER_HALT_CODES" in *" $1 "*) end=halted ;; *) end=crashed ;; esac
    fi
  fi
  runner_state_write "$end" "$1"
}

# ───────────────────────── run counters (shared state) ─────────────────────────
DISPATCH_COUNT=0
REAP_COUNT=0
LANDED_COUNT=0
DISPATCH_LOG=""

# Sourced by the gate tests (`SB_LIB_ONLY=1 . scripts/super-board-run.sh`) to exercise
# the helpers above without starting a run. Executing the script normally is unaffected.
if [ "${SB_LIB_ONLY:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

# A readiness/read failure stops only workers launched by this dispatcher. Keep their
# locks, worktrees, claims, and approval evidence for explicit recovery.
halt_cleanup() {
  local rc=$?
  if [ "$rc" -eq 9 ] || [ "$rc" -eq 10 ] || ! python3 "$SB_GITHUB_READ" --check >/dev/null 2>&1; then
    for pid in $(own_lane_pids); do
      kill -TERM "$pid" 2>/dev/null || true
    done
  fi
  runner_state_exit "$rc"
}
trap halt_cleanup EXIT
# Ctrl-C trên một lần chạy foreground là người dùng dừng (STATE=stopped, watchdog không khởi động lại). Runner nohup chạy
# nền bỏ qua SIGINT nên trap này không đổi gì ở đó. SIGTERM trần (không qua stop.sh) vẫn tính là crash.
trap 'RUNNER_END=stopped; exit 130' INT

# ── Stop marker của người dùng + bản ghi cho watchdog, trước mọi lần đọc GitHub.
RUNNER_DIR=".claude/super-board/runner"
RUNNER_STATE="$RUNNER_DIR/${CONFIG_SLUG}.state"
STOP_MARK="$RUNNER_DIR/${CONFIG_SLUG}.stopped"
RUNNER_END=""
START_TAG=""
RUNNER_STARTED=$(date +%s)
# stdout của runner (log nohup) để watchdog khởi động lại vào đúng file đó; không phải file thường thì để trống.
RUNNER_LOG=$(lsof -a -p $$ -d 1 -Fn 2>/dev/null | sed -n 's/^n//p' | head -1) || RUNNER_LOG=""
[ -f "$RUNNER_LOG" ] || RUNNER_LOG=""
mkdir -p "$RUNNER_DIR" 2>/dev/null || log "⚠ cannot create $RUNNER_DIR: no runner record, the watchdog cannot see this runner"
stop_in_flight() {
  # 0 khi stop thắng lần khởi động này: marker ghi sau giây runner ra đời, hoặc super-board-stop.sh ghi nó (PID= trong
  # marker) vẫn đang chạy (nó còn comment, dừng worker, rồi ghi lại marker). Marker của một stop.sh đã thoát, không mới
  # hơn runner, là `stop` rồi `run` tuần tự: lần khởi động này mới hơn. Không đọc được mtime thì stop thắng.
  local t p
  t=$(stat -f %m "$STOP_MARK" 2>/dev/null) || return 0
  [ "$t" -le "$RUNNER_BORN" ] || return 0
  p=$(sed -n 's/^PID=//p' "$STOP_MARK" 2>/dev/null | head -1) || p=""
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null || return 1
  case "$(ps -ww -o command= -p "$p" 2>/dev/null || true)" in *super-board-stop.sh*) return 0 ;; esac
  return 1
}
if [ "${SB_WATCHDOG_START:-0}" = "1" ]; then
  START_TAG=" (watchdog restart)"
  if [ -e "$STOP_MARK" ]; then
    log "🛑 watchdog restart refused: board ${CONFIG_SLUG} was stopped by the user ($STOP_MARK); only an explicit super-board run starts it"
    exit 0
  fi
elif [ -e "$STOP_MARK" ] && stop_in_flight; then
  # Stop chạy trùng lúc khởi động tường minh: stop thắng. Xoá marker ở đây thì trap EXIT ghi crashed và watchdog khởi
  # động lại board vừa bị dừng.
  log "🛑 start overruled: super-board-stop.sh wrote $STOP_MARK while this runner was starting — board ${CONFIG_SLUG} stays stopped"
  exit 0
fi
PREV_RUNNER=$(sed -n 's/^PID=//p' "$RUNNER_STATE" 2>/dev/null | head -1) || PREV_RUNNER=""
if [ -n "$PREV_RUNNER" ] && [ "$PREV_RUNNER" != "$$" ] && kill -0 "$PREV_RUNNER" 2>/dev/null; then
  case "$(ps -ww -o command= -p "$PREV_RUNNER" 2>/dev/null || true)" in
    *"super-board-run.sh ${CONFIG_SLUG}"|*super-board-run.sh)
      log "🛑 refusing to start: runner pid ${PREV_RUNNER} of board ${CONFIG_SLUG} is still running"; exit 73 ;;
  esac
fi
# Ghi bản ghi TRƯỚC khi đặt lại backoff và nạp watchdog (RunAtLoad chạy `check` ngay): một `check` đọc bản ghi cũ
# (PID chết) trong khoảng đó sẽ khởi động runner thứ hai.
# ponytail: kiểm-rồi-ghi không nguyên tử, hai lần khởi động trong cùng vài ms vẫn lọt; thêm khoá mkdir nếu thấy 2 runner.
if [ "${SB_WATCHDOG_START:-0}" = "1" ]; then
  DISPATCH_COUNT=$(state_num DISPATCHES)
  NO_PROGRESS_CYCLE_COUNT=$(state_num NO_PROGRESS)   # gán thẳng: bản ghi đầu tiên đã mang giá trị này
  RUNAWAY_PAUSE_UNTIL=$(state_num PAUSE_UNTIL)
fi
runner_state_write running
if [ "${SB_WATCHDOG_START:-0}" != "1" ]; then
  # Khởi động tường minh (super-board run, start-runner.sh, super_board_all.py start): người dùng muốn board chạy.
  if [ -e "$STOP_MARK" ]; then
    # Kiểm lại ngay trước khi xoá: stop.sh có thể vừa ghi lại marker kể từ lần kiểm ở trên.
    if stop_in_flight; then
      log "🛑 start overruled: super-board-stop.sh is still stopping board ${CONFIG_SLUG} — it stays stopped"
      exit 0
    fi
    log "▶ explicit start: cleared the stop marker ($(tr '\n' ' ' < "$STOP_MARK"))"
    rm -f "$STOP_MARK" 2>/dev/null || log "⚠ could not remove $STOP_MARK: this runner exits at its first tick"
  fi
  # Backoff của watchdog bắt đầu lại từ 0. Thư mục bản ghi hỏng (đã cảnh báo ở trên) không được giết runner.
  rm -f "$RUNNER_DIR/${CONFIG_SLUG}.watchdog" 2>/dev/null || true
  if [ -x "$SCRIPT_DIR/super-board-watchdog.sh" ]; then
    "$SCRIPT_DIR/super-board-watchdog.sh" ensure "$CONFIG_SLUG" 2>&1 | while IFS= read -r line; do log "watchdog: $line"; done || true
  else
    log "⚠ $SCRIPT_DIR/super-board-watchdog.sh is missing: nothing restarts this runner if it dies (copy it from agent-workbench)"
  fi
fi
gh_checkpoint

# ───────────────────────────── preconditions ─────────────────────────────
log "super-board run started${START_TAG} — config=${CONFIG_SLUG} base=${BASE_BRANCH} tick=${TICK_SECONDS}s max_workers=${MAX_WORKERS} no_progress_cycles=${NO_PROGRESS_CYCLES} max_dispatches=${MAX_DISPATCHES}"

# Chặn worker mồ côi: worker của repo này còn sống mà không có lock thì lần chạy này không biết nó đang giữ thẻ nào.
ORPHAN_PIDS=$(startup_orphan_workers "$PWD" | tr '\n' ' ')
if [ -n "${ORPHAN_PIDS// /}" ]; then
  log "🛑 refusing to start: super-board workers of this repo are running without an inflight lock: pid ${ORPHAN_PIDS}"
  log "    Check each one (ps -ww -o command= -p <pid>), stop it with kill -TERM <pid>, then re-run: $0 $CONFIG_SLUG"
  exit 73
fi

# Workflow-backend mutual exclusion (see references/run-workflow.md §Preconditions).
WAVE_LOCK=".claude/super-board/inflight/workflow-wave.lock"
if [ -f "$WAVE_LOCK" ]; then
  log "🛑 refusing to start: workflow-backend wave in flight ($WAVE_LOCK exists)."
  log "    If no wave is actually running, remove the stale lock: rm $WAVE_LOCK"
  exit 74
fi

# Production-merge guard.
if [ "$BASE_BRANCH" = "main" ] && [ "$HUMAN_APPROVES" = "false" ]; then
  if rg -qU 'on:\s*\n?\s*push:\s*\n?\s*branches:[^a-z]*main' .github/workflows 2>/dev/null \
     || [ -f vercel.json ] || [ -f netlify.toml ]; then
    log "🛡 refusing to start: would auto-merge to production main."
    exit 75
  fi
fi

# Existing legacy work is inspected/moved by a human, never deleted on upgrade.
check_legacy_worktrees
cleanup_stale_worktrees

startup_reconcile

# ───────────────────────────── main loop ─────────────────────────────
INITIAL_READY=$(( $(column_count "Ready") - $(person_count "Ready") ))   # as READY each tick: cards for a person left out (#95)
log "initial Ready count: $INITIAL_READY"

# Landed-work baseline (issue #8). Progress is a change in this set, not lane state.
PREV_DONE_SIG=$(done_signature)
INITIAL_DONE_SIG="$PREV_DONE_SIG"
NO_PROGRESS_CYCLE_COUNT="${NO_PROGRESS_CYCLE_COUNT:-0}"   # watchdog khởi động lại: đếm tiếp từ runner trước

while true; do
  # Stop marker xuất hiện giữa chừng (super-board-stop.sh không kill được runner này, hoặc watchdog vừa khởi động nó
  # sau lần quét ps của stop): runner tự thoát, không giao thêm việc.
  if [ -e "$STOP_MARK" ]; then
    log "🛑 stop marker ${STOP_MARK} — board stopped by the user; runner exits (super-board run ${CONFIG_SLUG} clears it)"
    RUNNER_END=stopped
    break
  fi
  runner_state_write running   # bộ đếm chi tiêu mới nhất, cho lần watchdog khởi động lại sau một SIGKILL
  python3 "$(dirname "$SB_GITHUB_READ")/super-board-verification-ready.py" --config "$CONFIG_PATH"
  gh_checkpoint
  # Workflow-backend mutual exclusion, re-checked every tick: the startup
  # check alone leaves a TOCTOU window where a workflow run starting at the
  # same moment as this dispatcher is never detected by either side.
  if [ -f "$WAVE_LOCK" ]; then
    log "🛑 workflow-backend wave appeared mid-run ($WAVE_LOCK) — halting for mutual exclusion."
    log "    Resume after the wave: $0 $CONFIG_SLUG"
    exit 74
  fi

  reap_finished_locks  # cheap local sweep; runs every tick

  # ── Zombie sweep against the LAST cached project state (no extra API).
  #    Catches workers whose card already moved out of the lane's source column
  #    but whose claude -p process didn't exit. Runs every tick, even cheap ones,
  #    so a cap-reached pipeline can still self-heal when one lane is a zombie.
  sweep_lane_zombies

  # ── Free pre-check: count active lanes from local PIDs (no API calls).
  BUILD_IDLE=1; QA_IDLE=1; REVIEW_IDLE=1
  lane_idle "$BUILD_PID" || BUILD_IDLE=0
  lane_idle "$QA_PID" || QA_IDLE=0
  lane_idle "$REVIEW_PID" || REVIEW_IDLE=0

  ACTIVE_WORKERS=0
  [ "$BUILD_IDLE" -eq 1 ] || ACTIVE_WORKERS=$((ACTIVE_WORKERS + 1))
  [ "$QA_IDLE" -eq 1 ] || ACTIVE_WORKERS=$((ACTIVE_WORKERS + 1))
  [ "$REVIEW_IDLE" -eq 1 ] || ACTIVE_WORKERS=$((ACTIVE_WORKERS + 1))

  # Đang hoãn sau RUNAWAY: không giao được gì nên chỉ đọc board thưa (paused_tick). Kiểm trước nhánh cap-reached:
  # runaway thường xảy ra khi cả 3 lane đều bận, và lúc đó vẫn phải quét zombie trên dữ liệu mới.
  if dispatch_paused; then
    paused_tick
    log "tick — runaway pause ($(( RUNAWAY_PAUSE_UNTIL - $(date +%s) ))s left) — board read every ${PAUSED_READ_EVERY} ticks, sleeping ${TICK_SECONDS}s"
    tick_sleep "$TICK_SECONDS"
    continue
  fi
  PAUSED_TICKS=0

  # ── Cheap-tick path: workers at cap → skip GraphQL fetch entirely.
  #    The board can't change in a way that helps us until a lane frees up.
  if [ "$ACTIVE_WORKERS" -ge "$MAX_WORKERS" ]; then
    log "tick — cap reached (${ACTIVE_WORKERS}/${MAX_WORKERS} busy) — skipping GraphQL fetch, sleeping ${TICK_SECONDS}s"
    tick_sleep "$TICK_SECONDS"
    continue
  fi

  # ── Expensive-tick path: we have capacity, fetch real state.
  gh_rate_guard
  fetch_project_items

  # Re-sweep zombies against fresh cache; the previous sweep used stale data.
  sweep_lane_zombies
  BUILD_IDLE=1; QA_IDLE=1; REVIEW_IDLE=1
  lane_idle "$BUILD_PID" || BUILD_IDLE=0
  lane_idle "$QA_PID" || QA_IDLE=0
  lane_idle "$REVIEW_PID" || REVIEW_IDLE=0
  ACTIVE_WORKERS=0
  [ "$BUILD_IDLE" -eq 1 ] || ACTIVE_WORKERS=$((ACTIVE_WORKERS + 1))
  [ "$QA_IDLE" -eq 1 ] || ACTIVE_WORKERS=$((ACTIVE_WORKERS + 1))
  [ "$REVIEW_IDLE" -eq 1 ] || ACTIVE_WORKERS=$((ACTIVE_WORKERS + 1))

  # Thẻ Blocked có blocker đã về Done thì trở lại Ready (runner này trước đây không có sweep: Goods #2, 2026-10-16).
  if maybe_sweep_blocked; then fetch_project_items; fi

  READY=$(column_count "Ready")
  WAITING=$(person_count "Ready")   # #95: Ready cards only a person can move; left out of Ready for dispatch and the exit test
  READY=$((READY - WAITING))
  BUILDING=0
  BUILDING=$(column_count "Building")
  QA=$(column_count "QA")
  REVIEW=$(column_count "Review")
  BLOCKED=$(column_count "Blocked")

  log "tick — Ready=$READY Building=$BUILDING QA=$QA Review=$REVIEW Blocked=$BLOCKED lanes: b_idle=$BUILD_IDLE(#${BUILD_ISSUE:-_}) q_idle=$QA_IDLE(#${QA_ISSUE:-_}) r_idle=$REVIEW_IDLE(#${REVIEW_ISSUE:-_}) waiting_on_you=$WAITING"

  if [ "$READY" -eq 0 ] && [ "$BUILDING" -eq 0 ] && [ "$QA" -eq 0 ] && [ "$REVIEW" -eq 0 ] \
     && [ "$BUILD_IDLE" -eq 1 ] && [ "$QA_IDLE" -eq 1 ] && [ "$REVIEW_IDLE" -eq 1 ]; then
    if [ "${SB_DAEMON:-0}" = "1" ]; then
      NO_PROGRESS_CYCLE_COUNT=0
      tick_sleep "$TICK_SECONDS"
      continue
    fi
    log "✅ all active-pipeline columns empty and all lanes idle — exiting cleanly"
    break
  fi

  if [ "${BLOCK_ALERT_SENT:-0}" -eq 0 ] && [ "$INITIAL_READY" -gt 0 ] && [ "$BLOCK_ALERT_PCT" -gt 0 ]; then
    PCT=$(( BLOCKED * 100 / INITIAL_READY ))
    if [ "$PCT" -ge "$BLOCK_ALERT_PCT" ]; then
      log "⚠ block-rate alert: ${BLOCKED}/${INITIAL_READY} (${PCT}%)"
      BLOCK_ALERT_SENT=1
    fi
  fi

  # ACTIVE_WORKERS already computed at top of loop (free pre-check).
  can_dispatch() {
    [ "$ACTIVE_WORKERS" -lt "$MAX_WORKERS" ] && ! dispatch_paused
  }

  if can_dispatch && [ "$REVIEW" -gt 0 ] && [ "$REVIEW_IDLE" -eq 1 ]; then
    if top_card_in_column "Review"; then
      dispatch_lane review "$TOP_ISSUE"
      ACTIVE_WORKERS=$((ACTIVE_WORKERS + 1))
    fi
  fi
  QA_FREE=$QA_IDLE
  if can_dispatch && [ "$QA" -gt 0 ] && [ "$QA_IDLE" -eq 1 ]; then
    if top_card_in_column "QA"; then
      dispatch_lane qa "$TOP_ISSUE"
      ACTIVE_WORKERS=$((ACTIVE_WORKERS + 1)); QA_FREE=0
    fi
  fi
  # Ready: the top card's label picks the lane — `qa` skips Building (Tester),
  # anything else is built first. A busy lane waits for the next tick.
  if can_dispatch && [ "$READY" -gt 0 ] && { [ "$BUILD_IDLE" -eq 1 ] || [ "$QA_FREE" -eq 1 ]; }; then
    if top_card_in_column "Ready"; then
      if [ "$(card_lane "$TOP_ISSUE")" = "qa" ]; then
        [ "$QA_FREE" -eq 1 ] && { dispatch_lane qa "$TOP_ISSUE"; ACTIVE_WORKERS=$((ACTIVE_WORKERS + 1)); }
      elif [ "$BUILD_IDLE" -eq 1 ]; then
        dispatch_lane build "$TOP_ISSUE"
        ACTIVE_WORKERS=$((ACTIVE_WORKERS + 1))
      fi
    fi
  fi

  gh_checkpoint

  # ── Landed-work halt gate (issue #8).
  #    Progress = the Done/Skipped set changed since the last dispatch cycle. Lane
  #    occupancy is deliberately NOT part of this condition: the runaway this gate
  #    exists to catch is a pipeline that is 100% busy and lands nothing, and the old
  #    `AND no lane active` clause made that case unhaltable (293 ticks, 0 merges).
  if ! record_cycle_progress "$(done_signature)"; then
    runaway_action || break
  fi

  # ── Hard dispatch ceiling. Bounds worst-case spend even if the board keeps
  #    trickling just enough Done movement to reset the gate above.
  if dispatch_ceiling_hit; then
    log "🛑 halt — dispatch ceiling reached (${DISPATCH_COUNT}/${MAX_DISPATCHES})"
    runaway_summary
    break
  fi

  tick_sleep "$TICK_SECONDS"
done
RUNNER_END="${RUNNER_END:-finished}"   # kết thúc có chủ đích: watchdog không khởi động lại

log "super-board run finished. manifest: $RUN_MANIFEST"
if jq -e '.calibration.enabled == true' "$CONFIG_PATH" >/dev/null 2>&1; then
  log "calibration skipped: legacy runner has no supervising skill host; final receipt and installed-skill delegation are required. Exit 0 alone does not prove selected work landed."
fi
