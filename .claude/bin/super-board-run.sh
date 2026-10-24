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
SB_WORKER_WRAP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/super-board-worker-wrap.sh"
SB_GITHUB_READ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/super-board-github-read.py"
# Lệnh đọc cố định của runner (fields, project, state, quota) đặt SB_GITHUB_READ_STRICT=1 cho TỪNG lệnh: gõ sai ở đây là lỗi
# của script nên vẫn halt board. Không export: worker thừa hưởng nó thì một lệnh gõ sai của agent lại halt cả board.
gh_checkpoint() { python3 "$SB_GITHUB_READ" --check || exit $?; }
gh_write_once() {
  gh_checkpoint
  # #190: comment ghi chưa rõ kết quả → kèm cách đọc lại. Marker là token DUY NHẤT gắn vào cuối body (comment HTML ẩn): comment
  # cố định lặp trên cùng issue (back to Ready · …) không được làm reconcile báo "đã áp dụng" nhầm.
  local args=("$@") token="" i
  if [ "$1 $2" = "issue comment" ]; then
    token="sb-write:$(date +%s)-$$-$RANDOM"
    for ((i = 0; i < ${#args[@]} - 1; i++)); do
      [ "${args[i]}" = --body ] && { args[i+1]="${args[i+1]}"$'\n'"<!-- ${token} -->"; break; }
    done
  fi
  gh "${args[@]}" || {
    local verify=() spec=""
    [ -z "$token" ] || spec=$(jq -nc --argjson n "$3" --arg m "$token" '{kind:"comment",issue:$n,marker:$m}' 2>/dev/null) || spec=""
    [ -z "$spec" ] || verify=(--verify "$spec")
    # --halt exits 79 (HALTED) once its record is saved; any other code means the record is not on disk.
    local hrc=0
    python3 "$SB_GITHUB_READ" --halt "GitHub $1 $2 response failed; reconcile the write before restarting" ${verify[@]+"${verify[@]}"} >&2 || hrc=$?
    [ "$hrc" -eq 79 ] || { log "halt record NOT written for the uncertain GitHub $1 $2 write (github-read rc=$hrc): exiting 76, the watchdog will not restart it blind"; exit 76; }
    exit 79
  }
}
# mtime (giây epoch) của một file, chạy đúng trên cả GNU stat (Linux: -c %Y) lẫn BSD stat (macOS: -f %m). Thử -c trước vì BSD stat từ chối
# -c, còn GNU stat nhận `-f` như "filesystem status" và có thể thành công mà in chữ rác. Chỉ nhận kết quả là số nguyên; không lấy được thì
# trả 1 để chỗ gọi giữ hành vi an toàn của nó.
file_mtime() {
  local t
  for t in "$(stat -c %Y "$1" 2>/dev/null || true)" "$(stat -f %m "$1" 2>/dev/null || true)"; do
    case "$t" in ''|*[!0-9]*) ;; *) printf '%s\n' "$t"; return 0 ;; esac
  done
  return 1
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

# Cập nhật đường dẫn manifest và thư mục log worker theo ngày hiện tại để qua 00:00 không ghi đè ngày cũ hoặc thiếu thư mục.
refresh_run_paths() {
  RUN_DATE="${1:-$(${SB_DATE_CMD:-date} +%Y-%m-%d)}"
  RUN_MANIFEST="docs/super-board/runs/${RUN_DATE}-${CONFIG_SLUG}.md"
  # Per-worker logs (issue #13). Workers used to be spawned with >/dev/null, so the run
  # log could never show what a worker was doing during a 13-minute silence.
  WORKER_LOG_DIR="docs/super-board/runs/${RUN_DATE}-${CONFIG_SLUG}-workers"
  mkdir -p "docs/super-board/runs" "$WORKER_LOG_DIR"
}

# One notice through the existing bot. Missing token, lib-only test mode, and network errors stay exit 0.
board_notify() {
  if [ "${SB_NOTIFY_SKIP:-0}" = "1" ] || [ "${SB_LIB_ONLY:-0}" = "1" ] || [ "${CONFIG_SLUG:-}" = "lib" ]; then
    return 0
  fi
  python3 "$SCRIPT_DIR/super-board-notify.py" "$@" || true
}

resolve_pos_int() {
  # $1 = đường dẫn config; $2 = khoá; $3 = mặc định. Số nguyên >= 1; thiếu hoặc sai thì mặc định (#252).
  local v
  v=$(jq -r --arg k "$2" '.[$k] // empty' "$1" 2>/dev/null || true)
  case "$v" in ''|*[!0-9]*) v=$3 ;; esac
  [ "${#v}" -le 6 ] || v=$3
  v=$((10#$v))
  [ "$v" -ge 1 ] || v=$3
  printf '%s\n' "$v"
}


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
# Một trần duy nhất (23/10, người dùng: "tổng số task chạy cùng trên Building + QA + Review tối đa là 5", tính trên cả 6 repo, không đo CPU):
# max_workers (mặc định 5) = tổng worker build + qa + review của MỌI repo trên máy, đếm qua thư mục slot chung (at_worker_cap).
# Mỗi lane được dùng cả max_workers slot; thứ tự giao trong một tick vẫn là Review → QA → Build.
MAX_WORKERS=$(resolve_pos_int "$CONFIG_PATH" max_workers 5)
BUILD_WORKERS=$MAX_WORKERS
QA_WORKERS=$MAX_WORKERS
REVIEW_WORKERS=$MAX_WORKERS
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

refresh_run_paths
INFLIGHT_DIR=".claude/super-board/inflight"
mkdir -p .claude/worktrees "$INFLIGHT_DIR"
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
  # #256: một lần đọc board hỏng tạm thời (card.sh exit 69: số item lệch totalCount, 22/10 22:05 sau khi máy khởi động
  # lại) từng giết runner ngay. Đọc lại có backoff + jitter (SB_FETCH_RETRY_DELAYS, giây). Mã halt có chủ đích
  # (RUNNER_HALT_CODES, vd 79: github-read halt sau lỗi mạng lặp lại) trả về ngay, không đọc lại.
  # Hỏng hết lượt: trả mã của lần đọc cuối, cache cũ giữ nguyên.
  local fresh rc=0 d pause delays
  read -r -a delays <<< "${SB_FETCH_RETRY_DELAYS-10 30 60}"   # tách theo khoảng trắng, không glob ("*" là một giá trị)
  for d in ${delays[@]+"${delays[@]}"} ""; do
    rc=0
    fresh=$("$(dirname "$SB_GITHUB_READ")/super-board-card.sh" --owner "$PROJECT_OWNER" --number "$PROJECT_NUMBER" items) || rc=$?
    if [ "$rc" -eq 0 ]; then PROJECT_ITEMS_JSON="$fresh"; return 0; fi
    case "$RUNNER_HALT_CODES" in *" $rc "*) return "$rc" ;; esac
    [ -n "$d" ] || break
    case "$d" in *[!0-9]*|?????*) d=10 ;; esac   # giá trị lạ (1.5, chữ, quá dài): dùng 10s, không để lỗi số học giết runner
    d=$((10#$d))                                  # 08/09 không bị đọc thành bát phân
    pause=$(( d + RANDOM % (d / 2 + 1) ))   # jitter: các board khởi động lại cùng lúc không đọc cùng nhịp
    log "⚠ board read failed (rc=$rc) — reading again in ${pause}s"
    tick_sleep "$pause"
  done
  return "$rc"
}

READ_SKIPS=0
tick_read_failed() {
  # $1 = mã của lần đọc hỏng, $2 = "nosleep" khi người gọi tự ngủ. Một lần đọc GitHub hỏng trong vòng lặp chính (board
  # hoặc quota) bỏ tick này thay vì để `set -e` giết runner (#256); mã halt có chủ đích vẫn dừng runner như trước. Lỗi kéo
  # dài (quyền Project đổi, lệch số mãi) không được che: quá SB_READ_SKIP_MAX tick bỏ liên tiếp thì thoát với mã của lần
  # đọc (không phải halt) để watchdog khởi động lại có backoff và trần như một lần crash. Luôn trả 1.
  local rc="$1" max="${SB_READ_SKIP_MAX:-5}"
  case "$max" in ''|*[!0-9]*|????*) max=5 ;; esac   # giá trị lạ không được lặng lẽ tắt trần
  case "$RUNNER_HALT_CODES" in *" $rc "*) exit "$rc" ;; esac
  READ_SKIPS=$((READ_SKIPS + 1))
  if [ "$READ_SKIPS" -gt "$((10#$max))" ]; then
    log "✖ GitHub read failed ${READ_SKIPS} ticks in a row (rc=$rc) — exiting so the watchdog restarts the runner"
    exit "$rc"
  fi
  log "⚠ GitHub read still failing (rc=$rc) — skipping this tick (${READ_SKIPS}/${max}), runner keeps going"
  [ "${2:-}" = nosleep ] || tick_sleep "${TICK_SECONDS:-30}"
  return 1
}

tick_fetch() {  # $1 = "nosleep" tuỳ chọn. Trả 1 khi bỏ tick (vòng lặp `continue`).
  local rc=0
  fetch_project_items || rc=$?
  if [ "$rc" -eq 0 ]; then READ_SKIPS=0; return 0; fi
  tick_read_failed "$rc" "${1:-}"
}

tick_guard() {  # gh_rate_guard trong vòng lặp: lỗi đọc quota tạm thời (vd 64) cũng chỉ bỏ tick. $1 = "nosleep" tuỳ chọn.
  local rc=0
  gh_rate_guard || rc=$?
  [ "$rc" -ne 0 ] || return 0
  tick_read_failed "$rc" "${1:-}"
}

column_count() {
  echo "$PROJECT_ITEMS_JSON" | jq --arg col "$1" '[.items[] | select(.status == $col)] | length'
}

# #95: a card that waits for a person — labelled needs-you / human-gated (any case, on the item or its content, as a name or {name}).
# Not one carrying loop:rebase / loop:rebuild-N: that card came back from QA/Review (a gate exit or a bounce after the person's `done`
# moved it to Review with its needs-you still on: run.md → resume), so it is work again (review 19/10). One definition for every use.
FOR_A_PERSON_JQ='def for_a_person: [((.labels // []) + (.content.labels // []))[] | (if type == "object" then .name else . end) | ascii_downcase]
  | ((index("needs-you") or index("human-gated")) and (map(. == "loop:rebase" or startswith("loop:rebuild-")) | any | not));'

# #95: a card whose QA needs a real device (label needs-device, any case) — in QA, or in Ready labelled `qa` (the Tester takes it
# from there) — while none is online ($nodev): a QA lane could only park it in Blocked. Not Review; not a Ready card the Builder
# takes first (it is built, and held when it reaches QA). Same rule: super-board-wave-plan.sh, super-board-status.py.
DEVICE_JQ='def held_for_device($col): $nodev and ([((.labels // []) + (.content.labels // []))[] | (if type == "object" then .name else . end) | ascii_downcase]
  | index("needs-device") != null and ($col == "QA" or ($col == "Ready" and index("qa") != null)));'
NO_DEVICE=false

# #202: dispatch order of Ready cards: priority:high < medium < low < none, then `bug` first, then the issue number ascending.
READY_RANK_JQ='def ready_rank: ([((.labels // []) + (.content.labels // []))[] | (if type == "object" then .name else . end) | ascii_downcase]) as $l
  | [(if ($l | index("priority:high")) then 0 elif ($l | index("priority:medium")) then 1 elif ($l | index("priority:low")) then 2 else 3 end),
     (if ($l | index("bug")) then 0 else 1 end), .content.number];'

refresh_device_state() {
  # Sets NO_DEVICE for this tick. adb is asked only while an unclaimed card would be held (a board with none never runs it);
  # a change is logged once, not every tick.
  local cards was="$NO_DEVICE" note
  cards=$(echo "$PROJECT_ITEMS_JSON" | jq -r --argjson nodev true "$DEVICE_JQ"'
    [.items[] | select(.content.type == "Issue" and ((.content.assignees // []) | length == 0))
     | select(held_for_device(.status)) | "#\(.content.number)"] | join(" ")') || cards=""
  NO_DEVICE=false
  [ -n "$cards" ] || return 0
  note=$(python3 "$SCRIPT_DIR/super-board-device-online.py" 2>&1) || NO_DEVICE=true   # its repo: this checkout
  [ "$NO_DEVICE" = "$was" ] && return 0
  if [ "$NO_DEVICE" = true ]; then
    log "📱 holding ${cards} (needs-device) until a real device is online: ${note}"
  else
    log "📱 real device online — needs-device cards ${cards} can be taken again (${note})"
  fi
}

count_board() {
  # This tick's column counts. Cards no lane takes (person_count) are left out of Ready and QA for dispatch and the exit test,
  # and counted in WAITING (#95).
  refresh_device_state   # #95: needs-device cards wait while no real device is online
  READY=$(column_count "Ready")
  WAITING=$(person_count "Ready")   # #95: Ready cards only a person can move; left out of Ready for dispatch and the exit test
  READY=$((READY - WAITING))
  BUILDING=$(column_count "Building")
  QA_HELD=$(person_count "QA")   # #95: QA cards waiting for a real device, left out the same way
  QA=$(( $(column_count "QA") - QA_HELD ))
  WAITING=$((WAITING + QA_HELD))
  REVIEW=$(column_count "Review")
  BLOCKED=$(column_count "Blocked")
}

person_count() {
  # Cards of column $1 no lane takes this tick — Ready ones waiting for a person, Ready/QA ones waiting for a real device: they
  # must not keep a run alive that has nothing else to do (counted, a non-daemon run never reached its clean "all empty" exit).
  echo "$PROJECT_ITEMS_JSON" | jq --arg col "$1" --argjson nodev "$NO_DEVICE" "$FOR_A_PERSON_JQ$DEVICE_JQ"'
    [.items[] | select(.status == $col) | select(($col == "Ready" and for_a_person) or held_for_device($col))] | length'
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
  local state reason raw
  state=$(SB_GITHUB_READ_STRICT=1 python3 "$SB_GITHUB_READ" --kind state -- issue view "$1" --json state -q '.state') || return 79
  [ "$state" = "CLOSED" ] || return 0
  # T0054: thẻ mang nhãn ac-open đã merge một PR nhưng còn AC chưa chứng minh (merge gate gắn nhãn). Worker vẫn có thể
  # `gh issue close` nó; mọi đường reconcile CLOSED → Done đều qua đây, nên coi nó là OPEN (và mở lại issue) thay vì Done.
  # Nhãn đọc từ snapshot board đã có (card.sh items trả labels): issue đóng không nhãn không tốn thêm lần đọc nào.
  # Người đóng có chủ đích (NOT_PLANNED, run.md §5 "dropped on purpose") thì để yên.
  echo "${PROJECT_ITEMS_JSON:-{\}}" | jq -e --argjson n "$1" 'any(.items[]?; .content.number == $n
      and any(((.labels // []) + (.content.labels // []))[]; ((if type == "object" then .name else . end) // "" | ascii_downcase) == "ac-open"))' >/dev/null 2>&1 \
    || return 1
  # Snapshot có thể cũ: merge gate gỡ nhãn ngay trước khi merge đủ AC rồi Closes đóng thẻ. Đọc nhãn + lý do đóng trực tiếp;
  # nhãn đã gỡ thì CLOSED như thường. Không đọc được: không mở lại (có thể người đã bỏ thẻ) nhưng cũng không đưa vào Done.
  # #319 (T0054): through the bounded github-read helper (not STRICT: a shape error must not halt the board for this optional read), the
  # read failure below is still "not reopened, kept out of Done".
  if ! raw=$(python3 "$SB_GITHUB_READ" --kind json -- issue view "$1" --json stateReason,labels 2>/dev/null) \
     || ! reason=$(printf '%s' "$raw" | jq -r '(.stateReason // "") + " " + ([.labels[].name | ascii_downcase] | join(","))' 2>/dev/null); then
    log "⚠ #$1 closed with label ac-open; close reason unreadable — not reopened, kept out of Done this tick"
    return 0
  fi
  case ",${reason#* }," in *,ac-open,*) ;; *) return 1 ;; esac
  reason="${reason%% *}"
  if [ "$reason" = "NOT_PLANNED" ]; then
    log "#$1 has label ac-open but was closed as not planned — left closed"
    return 1
  fi
  if gh_write_once issue reopen "$1" >/dev/null 2>&1; then
    log "#$1 was closed with label ac-open (AC not proven yet) — reopened, not moved to Done"
  else
    log "⚠ #$1 closed with label ac-open could not be reopened — kept out of Done; reopen it or remove the label"
  fi
  return 0
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

ready_card_held() {
  # #202: $1 = Ready issue, $2 = its project item id. Returns 0 when the card must NOT be dispatched this tick.
  #  - its body points at another repo (a github.com/<owner>/<repo> or <owner>/<repo>#N other than config.repo.remote, or an absolute
  #    checkout path outside this repo): a worker here cannot do it -> Blocked with the block template;
  #  - its `## Fix` section does the work of another card still open in Ready/Building (#N): commented once per runner process, left in Ready.
  # An unreadable or empty body is no verdict (returns 1): the card is dispatched as before.
  local issue="$1" item_id="$2" body self other refs dup r fixlines
  # Dạng đúng của kind issue là --json number,title,body (github-read từ chối -q/--jq: lệnh cũ `--json body -q .body` in chữ thô,
  # bước kiểm JSON hỏng, hàm này không bao giờ ra verdict và ở chế độ STRICT làm halt cả board, 22 và 23/10).
  # #303: stderr của github-read vào log (không 2>/dev/null) và exit 79 (halt) đi lên như gh_checkpoint: một halt không phải "không có verdict".
  local errf out rc
  errf=$(mktemp "${TMPDIR:-/tmp}/sb-ready-held.XXXXXX") || return 1
  rc=0; out=$(python3 "$SB_GITHUB_READ" --kind issue -- issue view "$issue" --json number,title,body 2>"$errf") || rc=$?
  if [ "$rc" -ne 0 ]; then
    log "ready_card_held #${issue}: github-read exit ${rc}: $(tail -n 1 "$errf" | cut -c1-300)"
    rm -f "$errf"
    [ "$rc" -eq 79 ] && exit 79
    return 1
  fi
  rm -f "$errf"
  body=$(printf '%s' "$out" | jq -r '.body // empty' 2>/dev/null) || return 1
  [ -n "$body" ] || return 1
  self=$(jq -r '.repo.remote // empty' "$CONFIG_PATH" 2>/dev/null | sed -E 's#^.*github\.com[:/]##; s#\.git$##' | tr '[:upper:]' '[:lower:]')
  other=""
  if [ -n "$self" ]; then
    # Only forms that name a repo unambiguously: github.com/<o>/<r>/(issues|pull|blob|tree|...) and a standalone <o>/<r>#N.
    # user-attachments/orgs/settings URLs and relative paths (docs/notes.md#12, docs/x#3) are not another repo.
    local cand owner repo
    while IFS= read -r cand; do
      [ -n "$cand" ] || continue
      owner="${cand%%/*}"; repo="${cand#*/}"
      case "$repo" in *.md|*.sh|*.py|*.js|*.ts|*.json|*.yml|*.yaml|*.txt|*.html|*.css|*.kt|*.java|*.swift|*.go|*.rs) continue ;; esac
      [ -e "$REPO_ROOT/$owner" ] && continue
      [ "$cand" = "$self" ] && continue
      other="$cand"; break
    done < <( {
        printf '%s\n' "$body" | grep -oE 'github\.com/[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+/(issues|pull|pulls|blob|tree|commit|commits|actions)([^A-Za-z0-9_-]|$)' \
          | sed -E 's#^github\.com/([^/]+/[^/]+)/.*#\1#'
        printf '%s\n' "$body" | grep -oE '(^|[[:space:](`"])[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+#[0-9]+' \
          | sed -E 's#^[^A-Za-z0-9]##; s/#[0-9]+$//'
      } | sed -E 's#\.git$##; s#\.$##' | tr '[:upper:]' '[:lower:]' | sort -u )
  fi
  if [ -z "$other" ]; then
    # A checkout path counts only in the card's own Fix/Context (not stack traces or prose in Problem) and must go below the disk/user dir.
    other=$( { printf '%s\n' "$body" | awk '/^## /{f = ($0 ~ /^## (Fix|Context)[[:space:]]*$/); next} f' \
        | grep -oE '/(Volumes|Users|home)/[^/[:space:]]+/[^][:space:])`"<>]+' || true; } \
      | grep -vF -e "$REPO_ROOT" -e "${HOME:-/nonexistent}/.claude" | head -1 || true)
  fi
  if [ -n "$other" ]; then
    log "hold #${issue} in Ready: its body points at another repo/checkout (${other}) — Blocked, not dispatched"
    if set_card_status "$item_id" "Blocked"; then
      gh_checkpoint
      gh_write_once issue comment "$issue" --body "[orchestrator] [blocker] 🛑 blocked · ❓ card targets another repo
Card:        #${issue}
Reason tag:  ❓
Why blocked: the body points at \`${other}\`, not at this repo (${self:-unknown}); a worker here would edit the wrong tree
Evidence:    body of #${issue} (\`${other}\`)
Checked:     runner Ready guard (#202) before any claim or worktree
What blocks: the card names a repo or checkout this board does not own
Why I (bot) cannot decide:
             moving the work to another repo's board is a person's call
To unblock:  [ ] Re-file the card on the board of \`${other}\`, or reword it if it is really about this repo
Owner:       repo admin
Move back:   drag this card to Ready once its body is about this repo
blocked-by:  -" >/dev/null 2>&1 || true
    else
      gh_checkpoint
      log "⚠ could not move #${issue} to Blocked — it is skipped this tick only"
    fi
    return 0
  fi
  fixlines=$(printf '%s\n' "$body" | awk '/^## /{f = ($0 ~ /^## Fix[[:space:]]*$/); next} f' \
    | grep -viE '(^|[^[:alnum:]_])(blocked|depends|after|sau khi)([^[:alnum:]_]|$)' || true)
  refs=$( { printf '%s\n' "$fixlines" | grep -oE '#[0-9]+' || true; } | tr -d '#' | sort -un)
  dup=""
  for r in $refs; do
    [ "$r" -lt "$issue" ] || continue   # A<->B: only the higher-numbered card is held, the lower one proceeds
    if echo "$PROJECT_ITEMS_JSON" | jq -e --argjson n "$r" '[.items[] | select(.content.number == $n and (.status == "Ready" or .status == "Building"))] | length > 0' >/dev/null 2>&1; then
      dup="${dup:+$dup }#${r}"
    fi
  done
  [ -n "$dup" ] || return 1
  local noted="$(dirname "$INFLIGHT_DIR")/dup-noted" key="${issue}:${dup// /,}"   # state file: survives a runner restart
  if ! grep -qxF "$key" "$noted" 2>/dev/null; then
    gh_write_once issue comment "$issue" --body "[orchestrator] [report] 👯 not dispatched · its Fix covers ${dup}
Did: runner Ready guard (#202) found ${dup} still open in Ready/Building and named in this card's Fix
❌ Not done: no worker was started for #${issue}, to avoid building the same change twice
Next: Eric — merge this card into ${dup}, or cut the overlap from its Fix" >/dev/null 2>&1 || true
    log "hold #${issue} in Ready: its Fix covers ${dup}, still open — not dispatched"
    echo "$key" >> "$noted" 2>/dev/null || log "⚠ could not record the duplicate note for #${issue} (${noted})"
  fi
  return 0
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
    if [ "$col" = "Ready" ] && ready_card_held "$issue" "$item_id"; then continue; fi   # #202
    TOP_ISSUE="$issue"; TOP_ITEM_ID="$item_id"
    return 0
  done <<EOF
$(echo "$PROJECT_ITEMS_JSON" | jq -r --arg col "$col" --arg bot "${BOT_LOGIN:-}" --argjson nodev "$NO_DEVICE" "$FOR_A_PERSON_JQ$DEVICE_JQ$READY_RANK_JQ"'
    [.items[]
    | select(.status == $col and .content.type == "Issue")
    # Chỉ bỏ qua thẻ đang giao cho người khác; thẻ chỉ mang assignee của chính BOT_LOGIN nhưng không có lock sống sẽ được lọc ở issue_locked phía trên để không bị kẹt.
    | select(((.content.assignees // []) - (if $bot == "" then [] else [$bot] end)) | length == 0)
    # #95: a Ready card waiting for a person (playtest, real device, store account, a ruling): dispatching it only spends a lane
    # and parks it again. Not in QA/Review: the resume path moves a 🙋 card a person approved to Review with its label possibly
    # still on (run.md → resume). Removing the label releases the card.
    | select($col != "Ready" or (for_a_person | not))
    | select(held_for_device($col) | not)]   # #95: its QA needs a real device and none is online (refresh_device_state)
    # #202: Ready is taken by priority label, then bug before the rest, then the lower (older) issue number; other columns keep board order.
    | (if $col == "Ready" then sort_by(ready_rank) else . end)
    | .[] | [(.content.number | tostring), (.id // "")] | @tsv')
EOF
  return 1
}

read_lock() {
  # Reads $INFLIGHT_DIR/$1 (bash-assignment format) into PID/LANE/STARTED/WORKER_LOG.
  # Sets empty strings if the file is missing or legacy single-PID format.
  local lock="$INFLIGHT_DIR/$1"
  PID=""; LANE=""; STARTED=""; WORKER_LOG=""; TRAIN=""; FROM_COL=""; COMMENTS0=""
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
  [ -z "$LANE" ] || note_worker_limit "${WORKER_LOG:-${WORKER_LOG_DIR}/worker-${LANE}-${issue}.log}"
  note_worker_exit "$issue"
  note_early_death "$issue"   # the second place a dead lock goes (a worker that died after this tick's reap): same ledger (#94)
  note_worker_end "$issue"
  [ "${LANE:-}" = "build" ] && RECLAIM_BUILDING="${RECLAIM_BUILDING:-} ${issue}" || true
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
tail = '\n'.join([l for l in section.splitlines() if l.strip() and not l.startswith('worker_exit:')][-3:])
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

# Worker build thứ nhất nằm ở BUILD_PID/BUILD_ISSUE như trước; các worker build thêm nằm ở BUILD_EXTRA ("pid:issue ..."). Số đếm
# dựa trên PID còn sống, nên worker chết là slot được trả lại.
build_workers_count() {
  # Gỡ PID chết khỏi BUILD_EXTRA, đặt BUILD_COUNT = số worker build đang sống (slot đầu + extra).
  local e keep=""
  for e in ${BUILD_EXTRA:-}; do
    kill -0 "${e%%:*}" 2>/dev/null && keep="${keep:+$keep }$e"
  done
  BUILD_EXTRA="$keep"
  BUILD_COUNT=0
  lane_idle "${BUILD_PID:-}" || BUILD_COUNT=1
  for e in $keep; do BUILD_COUNT=$((BUILD_COUNT + 1)); done
}

active_total() {
  # ACTIVE_WORKERS = số worker sống của repo này trên cả 3 lane (đếm từ PID, không cộng dồn nên không lệch).
  build_workers_count; lane_workers_count qa; lane_workers_count review
  ACTIVE_WORKERS=$(( ${BUILD_COUNT:-0} + ${QA_COUNT:-0} + ${REVIEW_COUNT:-0} ))
}

# Chốt lib mode LÚC SOURCE: test gọi `SB_LIB_ONLY=1 . runner`, mà bash chỉ giữ biến gán kèm lệnh `.` trong lúc source — hàm chạy về sau
# không còn thấy SB_LIB_ONLY (23/10: test merge train đếm slot sống của test khác trong HOME thật và bị giữ "3/3 running").
SB_SLOT_LIB_MODE="${SB_LIB_ONLY:-0}"
global_slot_dir() {
  # Thư mục slot chung của mọi repo. Lib mode (test source runner) mà không đặt SB_GLOBAL_SLOT_DIR thì trả rỗng = không đếm, không ghi:
  # test chạy song song không được đếm worker của nhau hay của board thật.
  if [ -n "${SB_GLOBAL_SLOT_DIR:-}" ]; then printf '%s\n' "$SB_GLOBAL_SLOT_DIR"
  elif [ "$SB_SLOT_LIB_MODE" = "1" ]; then printf '\n'
  else printf '%s\n' "$HOME/.claude/super-board-slots"; fi
}

global_slots_used() {
  # Số worker sống của MỌI repo trên máy: mỗi worker một file <pid> trong thư mục chung; file của PID đã chết bị xoá khi đếm.
  local d f n=0
  d=$(global_slot_dir); { [ -n "$d" ] && [ -d "$d" ]; } || { echo 0; return 0; }
  for f in "$d"/[0-9]*; do
    [ -e "$f" ] || continue
    if kill -0 "${f##*/}" 2>/dev/null; then n=$((n + 1)); else rm -f -- "$f"; fi
  done
  echo "$n"
}

global_slot_register() {
  # $1 = pid, $2 = nhãn lane#issue. Lỗi ghi slot không được làm chết lane (trần chung chỉ là heuristic): log rồi đi tiếp.
  local d; d=$(global_slot_dir); [ -n "$d" ] || return 0
  { mkdir -p "$d" && printf '%s:%s\n' "${CONFIG_SLUG:-repo}" "$2" > "$d/$1"; } 2>/dev/null || log "⚠ cannot register worker slot in $d"
}

at_worker_cap() {
  # 0 (và log lý do) khi máy đã đủ max_workers worker: số file slot sống của mọi repo, hoặc số worker của repo này nếu lớn hơn
  # (slot không ghi được thì vẫn có trần). $1 = nhãn lane. Không đo tải CPU. Đặt ACTIVE_WORKERS (repo này) và MACHINE_WORKERS.
  active_total
  MACHINE_WORKERS=$(global_slots_used)
  [ "$MACHINE_WORKERS" -ge "$ACTIVE_WORKERS" ] || MACHINE_WORKERS=$ACTIVE_WORKERS
  [ "$MACHINE_WORKERS" -ge "${MAX_WORKERS:-5}" ] || return 1
  log "$1 workers: ${MACHINE_WORKERS}/${MAX_WORKERS:-5} running on the machine (${ACTIVE_WORKERS} here): holding"
  return 0
}

build_slot_free() {
  # BUILD_FREE=1 (và trả 0) khi lane build được khởi một worker ở tick này: máy còn dưới max_workers (at_worker_cap).
  # Tối đa một worker mỗi tick (vòng chính giao một thẻ). Không đo tải CPU, không kill worker đang chạy.
  build_workers_count
  BUILD_FREE=0
  if fuse_paused; then   # #363; log chỉ khi đổi trạng thái (không tràn log mỗi tick)
    [ -n "${FUSE_PAUSE_LOGGED:-}" ] || log "🔌 suite fuse: Builder dispatch paused (merged card still Blocked)"
    FUSE_PAUSE_LOGGED=1; return 1
  fi
  FUSE_PAUSE_LOGGED=""
  if [ "$BUILD_COUNT" -ge "$BUILD_WORKERS" ]; then
    [ "$BUILD_WORKERS" -le 1 ] || log "build workers ${BUILD_COUNT}/${BUILD_WORKERS}: at the cap, not starting"
    return 1
  fi
  at_worker_cap build && return 1
  BUILD_FREE=1; return 0
}

# Lane QA / Review: worker thứ nhất ở QA_PID/QA_ISSUE (REVIEW_*), worker thêm ở QA_EXTRA / REVIEW_EXTRA ("pid:issue ..."), cùng dạng BUILD_EXTRA (#209).
lane_state() {
  # $1 = qa|review → L_PID, L_EXTRA, L_CAP của lane đó.
  case "$1" in
    qa)     L_PID="${QA_PID:-}";     L_EXTRA="${QA_EXTRA:-}";     L_CAP="${QA_WORKERS:-1}" ;;
    review) L_PID="${REVIEW_PID:-}"; L_EXTRA="${REVIEW_EXTRA:-}"; L_CAP="${REVIEW_WORKERS:-1}" ;;
    *) return 1 ;;
  esac
}

lane_workers_count() {
  # $1 = qa|review. Gỡ PID chết khỏi *_EXTRA; đặt LANE_COUNT (và QA_COUNT / REVIEW_COUNT) = số worker sống (slot đầu + extra).
  lane_state "$1" || return 1
  local e keep=""
  for e in $L_EXTRA; do
    kill -0 "${e%%:*}" 2>/dev/null && keep="${keep:+$keep }$e"
  done
  LANE_COUNT=0
  lane_idle "$L_PID" || LANE_COUNT=1
  for e in $keep; do LANE_COUNT=$((LANE_COUNT + 1)); done
  case "$1" in
    qa)     QA_EXTRA="$keep";     QA_COUNT=$LANE_COUNT ;;
    review) REVIEW_EXTRA="$keep"; REVIEW_COUNT=$LANE_COUNT ;;
  esac
}

lane_slot_free() {
  # 0 khi lane $1 (qa|review) được khởi một worker ở tick này: máy còn dưới max_workers (at_worker_cap).
  # Không đo tải CPU, không bao giờ kill worker đang chạy.
  local lane="$1"
  at_worker_cap "$lane" && return 1
  lane_workers_count "$lane" || return 1   # sau at_worker_cap: nó đếm cả 3 lane và ghi đè LANE_COUNT / L_CAP
  [ "$LANE_COUNT" -lt "$L_CAP" ] || return 1
  return 0
}

lane_dispatch_tick() {
  # $1 = qa|review; $2 = cột nguồn (QA|Review). Giao tối đa MỘT thẻ đầu cột cho lane ở tick này. Lane đã có worker thì worker thêm
  # không tốn thêm slot max_workers (lane = 1 slot, như build) nên không bị trần đó chặn; lane đang rảnh vẫn bị chặn như cũ.
  # LANE_DISPATCHED=1 khi thật sự có worker mới.
  local lane="$1" col="$2" before
  LANE_DISPATCHED=0
  dispatch_paused && return 0
  lane_slot_free "$lane" || return 0
  before=$LANE_COUNT
  TRAIN_BATCH=""
  [ "$lane" != "review" ] || review_train_batch   # #228: ≥2 thẻ đã duyệt thì một worker merge train cho cả đợt
  if [ -n "$TRAIN_BATCH" ]; then
    TOP_ISSUE=${TRAIN_BATCH%% *}
  else
    top_card_in_column "$col" || return 0
    [ -n "$TOP_ISSUE" ] || return 0
  fi
  dispatch_lane "$lane" "$TOP_ISSUE"
  TRAIN_BATCH=""
  lane_workers_count "$lane"
  [ "$LANE_COUNT" -gt "$before" ] || return 0
  LANE_DISPATCHED=1
  ACTIVE_WORKERS=$((ACTIVE_WORKERS + 1))
}

tick_is_cheap() {
  # #288: 0 khi tick này không giao được gì nên khỏi đọc board (GraphQL): máy (mọi repo) đã đủ max_workers worker.
  local m; m=$(global_slots_used)
  [ "$m" -ge "$ACTIVE_WORKERS" ] || m=$ACTIVE_WORKERS
  [ "$m" -ge "$MAX_WORKERS" ]
}

ready_qa_lane_free() {
  # #288: $1 = số thẻ Ready. Lane QA nhận được thẻ `qa` từ Ready khi Ready có thẻ và lane còn chỗ; Ready trống thì không hỏi (mỗi tick
  # một lần lane_slot_free + một dòng log vô ích).
  [ "${1:-0}" -gt 0 ] && lane_slot_free qa
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
  payload=$(. "$(dirname "$SB_GITHUB_READ")/super-board-gh-guard.sh" && sb_gh_quota_merge "$payload") || return $?
  # #256: tick_guard gọi hàm này trong ngữ cảnh `||` (errexit tắt), nên payload hỏng phải tự trả lỗi, không lặng lẽ bỏ guard.
  remaining=$(echo "$payload" | jq -r '.resources.graphql.remaining // 5000') || return 64
  case "$remaining" in ''|*[!0-9]*) return 64 ;; esac
  if [ "$remaining" -lt 200 ]; then
    reset=$(echo "$payload" | jq -r '.resources.graphql.reset // 0') || reset=0
    case "$reset" in ''|*[!0-9]*) reset=0 ;; esac   # reset lạ: ngủ mức sàn 60s, không lỗi số học
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
  printf '%s' "Worktree: after git fetch origin, create it from the repo root ONLY with the DevKit, never plain git worktree add or EnterWorktree: $cmd. It links the DevKit, copies the git-ignored config and hooks and clones a Unity Library copy-on-write; no agent-kit on PATH: python3 .agents/devkit/scripts/git/worktree.py add with the same arguments. Exit 4 = under the disk floor: stop with its message, card and claims unchanged. Exit 1 naming a worktree that holds the branch: agent-kit worktree remove that path (no agent-kit on PATH: python3 .agents/devkit/scripts/git/worktree.py remove; it drops the DevKit set-up a worktree carries, never work; refused with ✖ = it holds work: Block the card naming it), then add again. Clean up on exit with agent-kit worktree remove <path> (the branch stays)."
}

worktree_disk_room() {
  # $1 = đường dẫn worktree của lane. Đúng bước giữ chỗ của `agent-kit worktree add` (worktree.py _make_room: dưới mức cảnh báo thì
  # worktree gc trước, còn dưới sàn WORKTREE_DISK_MIN_GIB thì exit 4): một luật, không chép số, và gc vẫn chạy nên board không đứng
  # chờ người dọn tay. Dưới sàn lane nào cũng dừng ở bước tạo worktree, nên không nhận thẻ và không mở một phiên claude mỗi tick.
  # Worktree lane đã có (git còn nhận nó: không phải thư mục rỗng sót lại, cũng không phải .git trỏ vào admin dir đã bị prune) thì
  # add --lane dùng lại, không tốn thêm đĩa. Kiểm không được (không DevKit, python lỗi): coi là còn chỗ, nhưng ghi log (OCR 19/10).
  [ -e "$1/.git" ] && git -C "$1" rev-parse --git-dir >/dev/null 2>&1 && return 0
  # Under the floor a full `worktree gc` runs once, then rests 300 s: a gc that freed nothing frees nothing more a tick later, and every
  # lane of every tick ran one (OCR batch 19/10). While it rests only the free space is read, so a disk a person cleans is seen at the
  # next check. DISK_GC_NEXT lives in the runner shell (dispatch_lane is called there, not in a subshell). No knob for the 300 s: an
  # odd value (5m, 08) in the arithmetic ended the whole run loop (review 19/10).
  local rc=0 err now gc=1
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
    0:*) DISK_GC_NEXT=0 ;;                 # back above the floor: a later fall under it gets its gc at once
    *:1) DISK_GC_NEXT=$((now + 300)) ;;   # gc ran: still under the floor, or it failed itself (OCR 19/10) — rest either way
  esac
  case "$rc" in
    0) ;;
    4) log "worktree_disk_room: $(printf '%s' "$err" | tail -1 | cut -c1-200)" ;;   # the DevKit's own line: free GiB and the floor
    *) log "⚠ worktree_disk_room: DevKit disk check failed (rc=${rc}: $(printf '%s' "$err" | tail -1 | cut -c1-200)) — assuming room" ;;
  esac
  [ "$rc" -ne 4 ]
}

review_approved_head() {
  # $1 = issue. Thẻ Review đã được duyệt đúng head PR hiện tại (#227): in "<PR> <sha>" và trả 0, để lượt này chỉ chạy lại merge gate
  # (exit 4/conflict/not mergeable không phải lỗi code, review lại tốn 15-30 phút). Duyệt = comment `approved-head:<sha>` của người
  # có quyền ghi (OWNER/MEMBER/COLLABORATOR), comment cuối cùng thắng; head PR đổi thì sha không khớp nên duyệt tự mất hiệu lực.
  # Đọc GitHub hỏng hay thiếu dữ liệu → trả 1 = review đầy đủ như cũ (không bao giờ bỏ qua review vì lỗi đọc). Gate vẫn ghim --expect-head
  # và áp merge_policy nguyên vẹn: hàm này chỉ chọn việc cho worker, không nới luật merge.
  local prs pr head approved
  prs=$(python3 "$SB_GITHUB_READ" --kind array -- pr list --state open --limit 200 --json number,headRefName,headRefOid 2>/dev/null) || return 1
  read -r pr head <<EOF
$(printf '%s' "$prs" | jq -r --arg p "issue-$1-" '[.[] | select(.headRefName | startswith($p))][0] | select(. != null) | "\(.number) \(.headRefOid)"' 2>/dev/null)
EOF
  [ -n "${pr:-}" ] && [ -n "${head:-}" ] || return 1
  approved=$(python3 "$SB_GITHUB_READ" --kind object -- pr view "$pr" --json comments 2>/dev/null | jq -r '
    [.comments[] | select(.authorAssociation == "OWNER" or .authorAssociation == "MEMBER" or .authorAssociation == "COLLABORATOR")
      | (.body | capture("(?m)^approved-head:(?<sha>[0-9a-f]{40})\\s*$")? // empty) | .sha] | last // empty' 2>/dev/null) || return 1
  [ -n "$approved" ] && [ "$approved" = "$head" ] || return 1
  printf '%s %s' "$pr" "$head"
}

review_train_batch() {
  # #228: ≥2 thẻ Review đã duyệt đúng head (review_approved_head, #227) đi cùng MỘT worker chạy super-board-merge-train.sh (verify một
  # lần cho cả đợt) thay vì mỗi reviewer tự chạy merge gate nối tiếp qua merge.lock. Đặt TRAIN_BATCH = các dòng "<issue> <PR> <head>"
  # theo thứ tự bảng (tối đa SB_TRAIN_MAX, mặc định 8); rỗng khi dưới 2 thẻ đủ điều kiện hoặc SB_REVIEW_TRAIN=0 (đường từng thẻ như cũ).
  # Thẻ đủ điều kiện = không khoá, không chết sớm, không giao cho người khác, issue còn mở, và đã duyệt đúng head. Đọc GitHub hỏng thì
  # review_approved_head trả 1 nên thẻ ra khỏi đợt (không bao giờ bỏ qua review vì lỗi đọc). Luật merge không đổi: gate vẫn áp từng PR.
  # ponytail: mỗi thẻ ứng viên tốn một lần `pr list` + `pr view` (Review thường chỉ vài thẻ); nâng lên khi cột Review quá 10 thẻ: đọc pr list một lần.
  TRAIN_BATCH=""
  [ "${SB_REVIEW_TRAIN:-1}" != "0" ] || return 0
  local n=0 max="${SB_TRAIN_MAX:-8}" rows="" issue row cands
  case "$max" in ''|*[!0-9]*) max=8 ;; esac
  # Cùng bộ lọc với top_card_in_column (#95): thẻ cần người / cần thiết bị không đi vào đợt (R2).
  cands=$(echo "$PROJECT_ITEMS_JSON" | jq -r --arg bot "${BOT_LOGIN:-}" --argjson nodev "$NO_DEVICE" "$FOR_A_PERSON_JQ$DEVICE_JQ"'
    .items[] | select(.status == "Review" and .content.type == "Issue")
    | select(((.content.assignees // []) - (if $bot == "" then [] else [$bot] end)) | length == 0)
    | select((for_a_person or held_for_device(.status)) | not)
    | .content.number')
  for issue in $cands; do
    [ "$n" -lt "$max" ] || break
    issue_locked "$issue" && continue
    early_backoff "$issue" Review && continue
    local open_rc=0
    issue_is_open "$issue" || open_rc=$?   # rc 1 = đã đóng (bỏ qua); lỗi đọc >1 đi lên như top_card_in_column, không nuốt
    [ "$open_rc" -le 1 ] || exit "$open_rc"
    [ "$open_rc" -eq 0 ] || continue
    row=$(review_approved_head "$issue") || continue
    rows="${rows}${issue} ${row}"$'\n'; n=$((n + 1))
  done
  [ "$n" -ge 2 ] || return 0
  TRAIN_BATCH="${rows%$'\n'}"
}

claude_model_for_tier() {
  # model_tier của config -> --model của `claude -p` (#254: trước đây không truyền, mọi lượt chạy model mặc định đắt nhất).
  # low=haiku, high=opus; medium, thiếu hoặc lạ = sonnet.
  local tier
  tier=$(jq -r '.model_tier // "medium"' "$CONFIG_PATH" 2>/dev/null || echo medium)
  case "$tier" in
    low) echo haiku ;;
    high) echo opus ;;
    *) echo sonnet ;;
  esac
}

agent_office_args() {
  # Agent Office (mcp-servers/agent-office): có bản cài hook hộp thư thì worker claude nhận lệnh người dùng gõ giữa chừng
  # (hook PostToolUse qua --settings, system prompt mang nonce) và Agent Office biết session id ($1 = log worker).
  # Không có bản cài hoặc tạo cờ lỗi: AO_ARGS rỗng, worker bật y như cũ.
  AO_ARGS=(); AO_NONCE=""
  local hook="$HOME/.agent-office/app/inbox_hook.py" sid nonce settings sys_prompt
  [ -f "$hook" ] || return 0
  sid=$(python3 -I -S -c 'import uuid; print(uuid.uuid4())' 2>/dev/null) || return 0
  nonce=$(python3 -I -S -c 'import uuid; print(uuid.uuid4().hex)' 2>/dev/null) || return 0
  settings=$(python3 -I -S "$hook" --settings-json 2>/dev/null) || return 0
  sys_prompt=$(python3 -I -S "$hook" --system-prompt "$nonce" 2>/dev/null) || return 0
  [ -n "$sid" ] && [ -n "$settings" ] && [ -n "$sys_prompt" ] || return 0
  AO_ARGS=(--session-id "$sid" --settings "$settings" --append-system-prompt "$sys_prompt")
  AO_NONCE="$nonce"
  printf 'agent_office: session_id=%s\n' "$sid" >> "$1" 2>/dev/null || true
}

preflight_gate() {
  # #253: chạy super-board-preflight.sh TRƯỚC khi nhận thẻ build; trước đây LLM mới chạy nó (09:58Z #200 mới thấy "hold" sau khi
  # đã tốn một lượt). Trả 0 = giao, 1 = không giao (thẻ đã sang Blocked, hoặc còn Ready để thử lại tick sau). Chỉ chặn trên bằng chứng CHÍNH XÁC: PR đã merge / đang mở
  # có `closes #N`, thiếu AC, hoặc `sequence` có blocker còn MỞ. Hold dựa trên độ giống tiêu đề / fingerprint / thẻ khác / too-big
  # là phán đoán ("agent hạ được khi nêu lý do", run.md): giao như cũ để Builder bước 0 xét. Exit 79 khi không đọc được bằng chứng
  # GitHub (preflight mù không bao giờ nói proceed); lỗi khác của preflight hoặc không có verdict: log và giao như cũ (không chặn lane,
  # không crash-loop). Thiếu repo.remote trong config: giao như cũ.
  # ponytail: hold chính xác chỉ ghi `blocked-by:` rồi chờ người, không gắn needs-you (mark từ chối việc agent làm được); nâng khi cần.
  local issue="$1" pf repo inf out rc=0 v verdict tag reason blocked title item_id exact tagline csv bline orc
  pf="${SB_PREFLIGHT:-$(dirname "$SB_GITHUB_READ")/super-board-preflight.sh}"
  repo=$(jq -r '.repo.remote // empty' "$CONFIG_PATH" 2>/dev/null | sed -E 's#^(https?://github\.com/|git@github\.com:)##; s#\.git$##')
  if [ -z "$repo" ] || [ ! -f "$pf" ]; then log "preflight skipped for #${issue}: no repo.remote in config or no ${pf}"; return 0; fi
  inf=$(mktemp "${TMPDIR:-/tmp}/sb-inflight.XXXXXX")
  printf '%s' "$PROJECT_ITEMS_JSON" | jq -c '[.items[] | select(.status == "Building" or .status == "QA" or .status == "Review" or .status == "Ready")
    | {number: .content.number, title: (.content.title // ""), status: .status}]' > "$inf" 2>/dev/null || echo '[]' > "$inf"
  # The board's own merge line cap: 0 means one card is one PR whatever its size, so preflight never asks to split it.
  # Read it like super-board-merge-policy.py: unset → 400, else a whole number, and any value <= 0 is "no cap".
  # A value the merge policy cannot read (a word) falls back to 400 here; the merge gate then sends that PR to a human.
  local cap; cap=$(jq -r '.merge_policy.auto_max_lines as $c
    | if $c == null then 400 elif $c == false then 0 elif $c == true then 1
      elif ($c | type) == "number" then ($c | floor)
      elif ($c | type) == "string" and ($c | test("^\\s*[-+]?[0-9]+\\s*$")) then ($c | gsub("\\s"; "") | tonumber)
      else 400 end
    | if . <= 0 then 0 elif . > 1000000000 then 1000000000 else . end' "$CONFIG_PATH" 2>/dev/null) || cap=400
  out=$(bash "$pf" --repo "$repo" --issues "$issue" --inflight "$inf" --cap "${cap:-400}" 2>>"$RUN_MANIFEST") || rc=$?
  rm -f "$inf"
  if [ "$rc" -eq 79 ]; then log "preflight halted for #${issue}: GitHub evidence unavailable (exit 79)"; exit 79; fi
  if [ "$rc" -ne 0 ]; then log "⚠ preflight failed for #${issue} (exit ${rc}) — dispatching without it"; return 0; fi
  v=$(printf '%s' "$out" | jq -c --arg n "$issue" '.[$n] // empty' 2>/dev/null)
  [ -n "$v" ] || { log "⚠ preflight returned no verdict for #${issue} — dispatching without it"; return 0; }
  verdict=$(printf '%s' "$v" | jq -r '.verdict'); tag=$(printf '%s' "$v" | jq -r '.tag // ""')
  reason=$(printf '%s' "$v" | jq -r '.reason // ""')
  blocked=""
  case "$verdict" in
    proceed) return 0 ;;
    sequence)
      # blockedBy đọc từ body PR, không kiểm trạng thái: chỉ số issue còn MỞ mới chặn (số đã đóng là đúng mẫu #200). Một lệnh
      # super-board-blocked-by.py cho cả danh sách: nó không đi qua file halt, số gõ nhầm / số PR không dừng board (review P1/P2).
      csv=$(printf '%s' "$v" | jq -r '(.blockedBy // []) | map(tostring) | join(",")')
      if [ -n "$csv" ]; then
        orc=0
        bline=$(python3 "$(dirname "$SB_GITHUB_READ")/super-board-blocked-by.py" line --repo "$repo" "$csv" 2>>"$RUN_MANIFEST") || orc=$?
        # Không đọc được trạng thái blocker (gh lỗi thoáng qua): không giao, không chặn, thử lại tick sau. Không exit 79: helper không ghi
        # file halt nên watchdog sẽ không tự resume (máy ngủ dậy rồi board chết, #253 review).
        [ "$orc" -ne 79 ] || { log "preflight #${issue}: blocker state unreadable — not dispatched this tick, retrying next"; return 1; }
        if [ "$orc" -ne 0 ]; then log "⚠ preflight #${issue}: blocker check failed (exit ${orc}) — dispatching without it"; return 0; fi
        blocked="${bline#blocked-by: }"; [ "$blocked" != "-" ] || blocked=""
      fi
      [ -n "$blocked" ] || { log "preflight #${issue}: ${reason} — proceeding (merge gate rebases)"; return 0; }
      tagline="⏳" ;;
    hold)
      exact=$(printf '%s' "$v" | jq -r --arg n "$issue" '
        if .tag == "unclear" then "yes"
        elif .tag == "done" or .tag == "in-progress" then
          (if ([.evidence[]? | select(test("closes #" + $n + "$"))] | length) > 0 then "yes" else "no" end)
        else "no" end')
      if [ "$exact" != "yes" ]; then
        log "preflight ${verdict}/${tag} for #${issue} rests on similarity or size (${reason}) — dispatching, Builder step 0 judges"
        return 0
      fi
      case "$tag" in unclear) tagline="❓" ;; *) tagline="👯" ;; esac ;;
    *) log "⚠ preflight verdict '${verdict}' for #${issue} not understood — dispatching without it"; return 0 ;;
  esac
  title=$(printf '%s' "$PROJECT_ITEMS_JSON" | jq -r --argjson n "$issue" '[.items[] | select(.content.number == $n) | .content.title][0] // ""')
  item_id=$(printf '%s' "$PROJECT_ITEMS_JSON" | jq -r --argjson n "$issue" '[.items[] | select(.content.number == $n) | .id][0] // empty')
  log "preflight ${verdict}/${tag} for #${issue}: ${reason} — not dispatched, card to Blocked"
  # Chuyển thẻ TRƯỚC, comment chỉ khi chuyển được: chuyển hỏng thì thẻ còn Ready và tick sau sẽ comment lại (#253 review F6).
  gh_checkpoint
  if [ -z "$item_id" ] || ! set_card_status "$item_id" "Blocked"; then
    log "⚠ preflight: could not move #${issue} to Blocked — not dispatched, no comment"
    return 1
  fi
  gh_write_once issue comment "$issue" --body "[orchestrator] [blocker] 🛑 blocked · ${tagline} pre-flight ${verdict} (${tag})
Card:        #${issue} ${title}
Reason tag:  ${tagline}
Why blocked: ${reason}
Evidence:    super-board-preflight.sh → $(printf '%s' "$v" | jq -c '.evidence // []')
Owner:       Eric
Move back:   drag this card to Ready once the evidence above is resolved
blocked-by:  ${blocked:--}" >/dev/null 2>&1 || true
  return 1
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
    board_notify accounts-limited --card "${CONFIG_SLUG:-board}" --accounts "${POOL_RESETS:-all}" --state-dir "${SB_NOTIFY_STATE_DIR:-$HOME/.claude/super-board}"
    return 0
  fi
  # Sau các kiểm tra đĩa/account (không tốn một lượt preflight mỗi tick khi chưa giao được), trước khi nhận thẻ.
  if [ "$lane" = "build" ]; then preflight_gate "$issue" || return 0; fi
  if ! try_claim_assignee "$issue"; then
    return 0
  fi
  # #228: thẻ còn lại của đợt merge train cũng phải nhận được claim; thẻ thua đua bị bỏ khỏi đợt (lock chỉ ghi cho thẻ đã claim).
  local train_rows="" train_issues="" train_prs="" train_heads="" t_issue t_pr t_head train_n=0
  if [ "$lane" = "review" ] && [ -n "${TRAIN_BATCH:-}" ]; then
    while read -r t_issue t_pr t_head; do
      [ -n "$t_issue" ] || continue
      [ "$t_issue" = "$issue" ] || try_claim_assignee "$t_issue" || continue
      train_rows="${train_rows}${t_issue} ${t_pr} ${t_head}"$'\n'; train_n=$((train_n + 1))
      train_issues="${train_issues:+$train_issues }${t_issue}"
      train_prs="${train_prs:+$train_prs,}${t_pr}:${t_head}"   # N:sha — train từ chối PR có head đã dời khỏi head đã duyệt (R1)
      train_heads="${train_heads:+$train_heads, }PR #${t_pr}=${t_head}"
    done <<EOF
$TRAIN_BATCH
EOF
    if [ "$train_n" -lt 2 ]; then   # R4: thua claim hết, chỉ còn thẻ chính — đường merge-only như cũ, không train 1 PR
      log "review lane: train shrank to ${train_n} card(s) after the claims — #${issue} takes the single-card path"
      train_rows=""; train_issues=""; train_prs=""; train_heads=""
    fi
  fi
  # Chuyển ngay thẻ Ready sang cột Building trên GitHub Project Board khi giao cho Builder để bảng hiển thị tức thì.
  if [ "$lane" = "build" ] && [ -n "$PROJECT_OWNER" ] && [ "${PROJECT_NUMBER:-0}" -gt 0 ]; then
    local build_item_id
    build_item_id=$(echo "$PROJECT_ITEMS_JSON" | jq -r --argjson n "$issue" '[.items[] | select(.content.number == $n and .status == "Ready") | .id][0] // empty' 2>/dev/null || true)
    [ -z "$build_item_id" ] || set_card_status "$build_item_id" "Building" || true
  fi
  local noop_judge=1 baseline
  case "$lane" in
    build)  prompt="Run super-build on issue #${issue} for super-board run. Read .claude/skills/super-board/references/run.md → Builder lifecycle. Config: ${CONFIG_PATH}." ;;
    qa)     prompt="Run super-qa on issue #${issue} for super-board run. Read .claude/skills/super-board/references/run.md → Tester lifecycle. Config: ${CONFIG_PATH}." ;;
    review)
      local merge_only="" mo_pr mo_head
      if [ -n "$train_rows" ]; then
        noop_judge=0
        log "review lane: merge-train for #${train_issues// /, #} (PRs ${train_prs}) — one worker, one verify, no fresh review"
        prompt="Run one merge-train worker on issues #${train_issues// /, #} (PRs ${train_prs}) for super-board run. Read .claude/skills/super-board/references/run.md → Merge protocol (the runner-batched merge train). Config: ${CONFIG_PATH}. These PRs were already reviewed and approved at their current heads (approved-head comments: ${train_heads}); do NOT review any of them again. Mark each PR ready (gh pr ready <PR>), then run ONE command, never the gate per PR: bash .claude/bin/super-board-merge-train.sh --config ${CONFIG_PATH} --prs ${train_prs} (each N:sha pins the approved head; keep the list exactly as given). The train itself drops a PR whose head moved off the approved one (train-result head-moved, exit 6): its card stays in Review for a fresh review. Route every train-result line exactly as the Merge protocol says: head-moved → leave the card in Review; merged → confirm it landed, close the issue, card Review → Done (not when the gate printed ac-open: #N — that card stays open, the gate moved it to Ready); red or train-red (exit 11) → the exit 11 route (card to Ready with loop:rebuild-N); conflict → rebase pass; deferred or timeout → leave the card in Review for the next wave; gate-exit-K → route K like the gate exit code K. Exit 79 or 9 from the train → halt as the Merge protocol says. Every issue of the batch is yours: keep going until each has been routed."
      elif merge_only=$(review_approved_head "$issue"); then
        noop_judge=0
        read -r mo_pr mo_head <<EOF
$merge_only
EOF
        log "review lane issue=#${issue}: PR #${mo_pr} approved at head ${mo_head} — merge-only, no fresh review"
        prompt="Run merge-only on issue #${issue} for super-board run. Read .claude/skills/super-board/references/run.md → Merge protocol. Config: ${CONFIG_PATH}. PR #${mo_pr} was already reviewed and approved at head ${mo_head} (approved-head comment); do NOT review again. Check the PR head is still ${mo_head} (gh pr view ${mo_pr} --json headRefOid); then mark ready and run .claude/bin/super-board-merge-gate.sh --expect-head ${mo_head} --config ${CONFIG_PATH} --pr ${mo_pr} and route its exit code exactly as the Merge protocol says. Head moved (exit 6 or a different sha): leave the card in Review for a fresh review."
      else
      prompt="Run super-review on issue #${issue} for super-board run. Read .claude/skills/super-board/references/run.md → Reviewer lifecycle. Config: ${CONFIG_PATH}. In headless super-board Review lane, your independent review + truth-check sub-agents satisfy the independent audit requirement; when ACs, tests, and truth-checks pass with no blockers, proceed directly to merge via .claude/bin/super-board-merge-gate.sh and move the card to Done (not when the gate printed ac-open: #N — merged with AC still unproven: leave the issue open, the gate moved the card to Ready)."
      fi ;;
    *) log "unknown lane: $lane"; return 1 ;;
  esac
  prompt="First operation: run .claude/bin/super-board-skills-ready.py --root '$PWD' --host claude --cards - --lane '$lane' --hydrate with $card as stdin. Halt on exit 10 before worktree creation or lifecycle writes; preserve claims and approval evidence. Load resolved paths and only declared fallbacks; recheck conditionals with --require before activation. $prompt $(lane_worktree_hint "$lane" "$issue") $(resume_hint "${WORKER_LOG_DIR}/worker-${lane}-${issue}.log") Emulator policy: NEVER launch an Android emulator without -no-window (always run headless in background with -no-window -no-audio -no-boot-anim, or via python3 .agents/devkit/bin/proof-capture.py)."
  if [ -f "$REPO_ROOT/.agents/active-profile.json" ] && grep -q '"lang": "vi"' "$REPO_ROOT/.agents/active-profile.json" 2>/dev/null; then
    prompt="$prompt Language policy: This repository uses Vietnamese ('lang': 'vi'). Write all PR descriptions, problem/solution/AC explanations, status comments, and review notes in Vietnamese (Tiếng Việt); identifiers/symbols remain English."
  fi
  # Worker output goes to a per-worker log, not /dev/null (issue #13). Redirect at the
  # `claude` invocation itself — no wrapping subshell, no `exec` — so the wire to the
  # file survives and `$!` names the worker process rather than a bash stub.
  baseline=$(dispatch_baseline "$issue" "$lane" "$noop_judge")
  mkdir -p "$WORKER_LOG_DIR"
  local worker_log="${WORKER_LOG_DIR}/worker-${lane}-${issue}.log"
  local worker_log_abs
  # The folder is made at startup only; gone since (19/10: no 2026-10-19-*-workers folder), every `>> $worker_log` below fails and
  # the worker never starts — dying at once, tick after tick (#94). Made again here, before anything is written to it.
  mkdir -p "$WORKER_LOG_DIR" 2>/dev/null || log "⚠ cannot make the worker log folder $WORKER_LOG_DIR"
  worker_log_abs="$(cd "$WORKER_LOG_DIR" && pwd)/worker-${lane}-${issue}.log"
  {
    printf '=== dispatch lane=%s issue=#%s at %s ===\n' "$lane" "$issue" "$(date -u +%FT%TZ)"
    printf 'prompt: %s\n\n' "$prompt"
  } >> "$worker_log"
  ln -sf "$PWD/$worker_log" "docs/super-board/current-worker.log" 2>/dev/null || true
  gh_checkpoint
  local pool_engine="$POOL_ENGINE" pool_acct="$POOL_ACCT" pool_cfg="$POOL_CFG"
  # note_worker_limit đọc dòng này để biết account nào hết limit.
  [ -n "$pool_acct" ] && printf 'account_pool: engine=%s account=%s config_dir=%s\n' "$pool_engine" "$pool_acct" "$pool_cfg" >> "$worker_log"
  # CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0: ngăn `claude -p` tự huỷ tác vụ nền (như red_proof.py --pending) sau 10 phút.
  export DEVKIT_ALLOW_BRANCH=1 WORKTREE_MERGE_GATE=0 DEVKIT_LANG="${DEVKIT_LANG:-vi}" CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS="${CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS:-0}"
  # BASH_*_TIMEOUT_MS=1h: Bash tool của worker mặc định bị cắt ở 10 phút, đúng lúc gate còn chờ heavy_slot (≤600 s) (#249).
  export BASH_DEFAULT_TIMEOUT_MS="${BASH_DEFAULT_TIMEOUT_MS:-3600000}" BASH_MAX_TIMEOUT_MS="${BASH_MAX_TIMEOUT_MS:-3600000}"
  unset POSTFIX_GATE_FORCE_FULL
  local claude_model
  claude_model=$(claude_model_for_tier)
  if [ "$pool_engine" = "antigravity" ] && [ -x "$HOME/.local/bin/agy" ]; then
    nohup "$SB_WORKER_WRAP" "$HOME/.local/bin/agy" --model gemini-4-argon-high --effort xhigh --dangerously-skip-permissions -p "$prompt" >> "$worker_log" 2>&1 &
  elif [ "$pool_engine" = "grok" ] && [ -x "$HOME/.grok/bin/grok" ]; then
    nohup "$SB_WORKER_WRAP" "$HOME/.grok/bin/grok" -m grok-4.7 -p "$prompt" >> "$worker_log" 2>&1 &
  elif [ -n "$pool_cfg" ]; then
    agent_office_args "$worker_log"
    AGENT_OFFICE_NONCE="$AO_NONCE" CLAUDE_CONFIG_DIR="$pool_cfg" nohup "$SB_WORKER_WRAP" claude --model "$claude_model" --dangerously-skip-permissions --output-format stream-json --verbose ${AO_ARGS[@]+"${AO_ARGS[@]}"} -p "$prompt" >> "$worker_log" 2>&1 &
  else
    agent_office_args "$worker_log"
    AGENT_OFFICE_NONCE="$AO_NONCE" nohup "$SB_WORKER_WRAP" claude --model "$claude_model" --dangerously-skip-permissions --output-format stream-json --verbose ${AO_ARGS[@]+"${AO_ARGS[@]}"} -p "$prompt" >> "$worker_log" 2>&1 &
  fi
  pid=$!
  global_slot_register "$pid" "${lane}#${issue}"
  DISPATCH_COUNT=$((DISPATCH_COUNT + 1))
  DISPATCH_LOG="${DISPATCH_LOG}${issue}
"
  # v1.3.0+ lock format: bash-assignment style so `super-board stop` can source it
  # to recover lane + dispatch time. issue_locked()/reap_finished_locks() still work
  # because PID= is the first line.
  printf 'PID=%s\nLANE=%s\nSTARTED=%s\nWORKER_LOG=%s\nTRAIN="%s"\n%s' "$pid" "$lane" "$(date -u +%FT%TZ)" "$worker_log_abs" "$train_issues" "$baseline" > "$INFLIGHT_DIR/$issue"
  # #228: cả đợt cùng một worker: mỗi thẻ có lock riêng (cùng PID) để issue_locked và reap_finished_locks xử lý từng thẻ như thường.
  for t_issue in $train_issues; do
    [ "$t_issue" = "$issue" ] || printf 'PID=%s\nLANE=%s\nSTARTED=%s\nWORKER_LOG=%s\nTRAIN="%s"\n' "$pid" "$lane" "$(date -u +%FT%TZ)" "$worker_log_abs" "$train_issues" > "$INFLIGHT_DIR/$t_issue"
  done
  case "$lane" in
    build)
      if lane_idle "${BUILD_PID:-}"; then BUILD_PID="$pid"; BUILD_ISSUE="$issue"
      else BUILD_EXTRA="${BUILD_EXTRA:+$BUILD_EXTRA }${pid}:${issue}"; fi ;;
    qa)
      if lane_idle "${QA_PID:-}"; then QA_PID="$pid"; QA_ISSUE="$issue"
      else QA_EXTRA="${QA_EXTRA:+$QA_EXTRA }${pid}:${issue}"; fi ;;
    review)
      if lane_idle "${REVIEW_PID:-}"; then REVIEW_PID="$pid"; REVIEW_ISSUE="$issue"
      else REVIEW_EXTRA="${REVIEW_EXTRA:+$REVIEW_EXTRA }${pid}:${issue}"; fi ;;
  esac
  log "dispatch lane=${lane} issue=#${issue} pid=${pid} claim=${BOT_LOGIN:-local-only}"
}

issue_status() {
  # Lookup issue #$1 in the cached project items; emit its current column name (or empty).
  echo "$PROJECT_ITEMS_JSON" | jq -r --arg n "$1" '
    .items[] | select(.content.number == ($n | tonumber)) | .status' | head -1
}

started_older_than() {
  # 0 khi mốc $1 (STARTED của lock, ISO UTC) cách nay hơn $2 giây. Mốc trống hoặc sai dạng: 1 (không đo được thì không coi là quá hạn).
  python3 -c 'import calendar, sys, time
sys.exit(0 if time.time() - calendar.timegm(time.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ")) > float(sys.argv[2]) else 1)' "${1:-}" "$2" 2>/dev/null
}

quiet_longer_than() {
  # 0 khi worker im lặng quá $3 giây: tính từ lần ghi cuối của log worker $1 (nhịp tim; stream-json ghi liên tục khi worker còn làm việc).
  # Log không đọc được mtime thì dùng mốc STARTED $2 như trước (started_older_than); cả hai không đo được: 1 (không coi là quá hạn).
  local mt
  if mt=$(file_mtime "${1:-}"); then [ $(( $(date +%s) - mt )) -gt "$3" ]; else started_older_than "${2:-}" "$3"; fi
}

check_lane_zombie() {
  # $1 = lane name (build|qa|review); $2 = space-separated list of expected source columns.
  # If the lane's worker PID is alive but its claimed issue has already moved to a column
  # NOT in the expected source set, the worker's logical work is done — kill the zombie
  # process and free the lane. Uses cached project items only (no extra API calls).
  # $3/$4 = PID/issue của một worker thêm trong BUILD_EXTRA / QA_EXTRA / REVIEW_EXTRA; không có thì xét worker ở slot đầu của lane.
  local lane="$1" expected="$2" pid="" issue="" extra=0
  [ -z "${3:-}" ] || extra=1
  case "$lane" in
    build)  if [ "$extra" -eq 1 ]; then pid="$3"; issue="$4"; else pid="$BUILD_PID"; issue="$BUILD_ISSUE"; fi ;;
    qa)     if [ "$extra" -eq 1 ]; then pid="$3"; issue="$4"; else pid="$QA_PID"; issue="$QA_ISSUE"; fi ;;
    review) if [ "$extra" -eq 1 ]; then pid="$3"; issue="$4"; else pid="$REVIEW_PID"; issue="$REVIEW_ISSUE"; fi ;;
    *) return 1 ;;
  esac
  [ -z "$pid" ] && return 0
  [ -z "$issue" ] && return 0
  kill -0 "$pid" 2>/dev/null || return 0   # already dead → reap_finished_locks handles it
  local cur found=0 col t
  cur=$(issue_status "$issue")
  [ -z "$cur" ] && return 0                # not in cache (closed/deleted/race) → don't kill
  # Thẻ `qa` được giao từ Ready và Tester tự chuyển Ready → QA sau khi khởi động (run.md, Tester lượt đầu).
  # Khi thẻ của Tester này chưa từng thấy ở QA thì Ready không phải dấu hiệu zombie; sau đó Ready là đường
  # fail của Tester và giải phóng lane như cũ. QA_SEEN_IN_QA giữ PID đã thấy, nên Tester mới trên cùng thẻ
  # bắt đầu sạch. QA_SEEN_IN_QA là danh sách PID (nhiều Tester cùng lúc, #209).
  # ponytail: Tester treo trước bước chuyển đầu tiên giữ lane QA tới khi được thu hồi tay; thêm trần ân hạn
  # tính theo thời điểm đọc board (không theo đồng hồ, cache có thể cũ ở tick cap-reached) nếu việc này xảy ra.
  if [ "$lane" = qa ]; then
    case " ${QA_SEEN_IN_QA:-} " in
      *" $pid "*) ;;
      *) if [ "$cur" = QA ]; then QA_SEEN_IN_QA="${QA_SEEN_IN_QA:+$QA_SEEN_IN_QA }$pid"; else expected="$expected Ready"; fi ;;
    esac
  fi
  for col in $expected; do
    [ "$cur" = "$col" ] && found=1
  done
  # #228: worker của đợt merge train giữ lock của mọi thẻ trong đợt (TRAIN): thẻ đầu sang Done không làm nó thành zombie khi thẻ khác
  # của đợt còn ở cột nguồn.
  # #358 mục 6: worker train treo mà còn một thẻ ở Review (head đổi, hoãn, timeout giữ ở Review có chủ đích) thì found=1 mãi và lane không bao
  # giờ được giải phóng; im lặng quá SB_TRAIN_MAX_AGE_S (mặc định 3 giờ, tính từ lần ghi cuối của log worker, không phải STARTED: train khoẻ chạy lâu vẫn ghi log) thì không còn được che bởi thẻ Review.
  # Lock đọc trong subshell: read_lock ghi đè PID/LANE/STARTED/WORKER_LOG toàn cục của vòng chính, mà đây chỉ là kiểm tra.
  if [ "$found" -eq 0 ] && [ "$lane" = review ]; then
    local lk_info lk_train lk_started lk_log
    lk_info=$(read_lock "$issue" && printf '%s|%s|%s' "${TRAIN:-}" "${STARTED:-}" "${WORKER_LOG:-}") || lk_info="||"
    lk_train="${lk_info%%|*}"; lk_info="${lk_info#*|}"; lk_started="${lk_info%%|*}"; lk_log="${lk_info#*|}"
    for t in $lk_train; do
      [ "$(issue_status "$t")" = "Review" ] && found=1
    done
    if [ "$found" -eq 1 ] && quiet_longer_than "$lk_log" "$lk_started" "${SB_TRAIN_MAX_AGE_S:-10800}"; then
      log "⏱ merge-train worker on #${issue} (pid=${pid}) wrote nothing to its log for over ${SB_TRAIN_MAX_AGE_S:-10800}s (started ${lk_started}) with cards still in Review: treated as hung"
      found=0
    fi
  fi
  # Thẻ về cột cũ: bỏ mốc ân hạn để lần rời cột sau tính lại từ đầu.
  [ "$found" -eq 0 ] || ZOMBIE_SEEN=$(printf '%s\n' ${ZOMBIE_SEEN:-} | grep -v "^${pid}:" | tr '\n' ' ' || true)
  if [ "$found" -eq 0 ]; then
    # Ân hạn (#237): worker vừa chuyển thẻ còn đang in báo cáo cuối; kill ngay xoá báo cáo đó khỏi log.
    # ZOMBIE_SEEN = "pid:epoch" lần đầu thấy; kill khi quá SB_ZOMBIE_GRACE giây (mặc định 60).
    local seen_at now
    now=$(date +%s)
    seen_at=$(printf '%s\n' ${ZOMBIE_SEEN:-} | sed -n "s/^${pid}://p" | head -1)
    if [ -z "$seen_at" ]; then seen_at="$now"; ZOMBIE_SEEN="${ZOMBIE_SEEN:+$ZOMBIE_SEEN }${pid}:${now}"; fi
    [ $(( now - seen_at )) -ge "${SB_ZOMBIE_GRACE:-60}" ] || return 0
    gh_checkpoint
    log "💀 zombie ${lane} worker on #${issue} (pid=${pid}) — card moved to '${cur}'; killing"
    # #237: pid trong lock là wrapper; kill -9 chỉ trúng wrapper còn worker con sống tiếp → diệt con trước.
    kill "$pid" 2>/dev/null || true
    sleep 1 || true
    pkill -9 -P "$pid" 2>/dev/null || true
    kill -9 "$pid" 2>/dev/null || true
    ZOMBIE_SEEN=$(printf '%s\n' ${ZOMBIE_SEEN:-} | grep -v "^${pid}:" | tr '\n' ' ' || true)
    gh_checkpoint
    [ -n "$BOT_LOGIN" ] && gh_write_once issue edit "$issue" --remove-assignee "$BOT_LOGIN" >/dev/null 2>&1 || true
    gh_checkpoint
    rm -f "$INFLIGHT_DIR/$issue"
    case "$lane" in
      build)
        if [ "$extra" -eq 1 ]; then
          local e keep=""
          for e in ${BUILD_EXTRA:-}; do [ "$e" = "${pid}:${issue}" ] || keep="${keep:+$keep }$e"; done
          BUILD_EXTRA="$keep"
        else BUILD_PID="";  BUILD_ISSUE=""; fi ;;
      qa)
        if [ "$extra" -eq 1 ]; then
          local e keep=""
          for e in ${QA_EXTRA:-}; do [ "$e" = "${pid}:${issue}" ] || keep="${keep:+$keep }$e"; done
          QA_EXTRA="$keep"
        else QA_PID=""; QA_ISSUE=""; fi ;;
      review)
        if [ "$extra" -eq 1 ]; then
          local e keep=""
          for e in ${REVIEW_EXTRA:-}; do [ "$e" = "${pid}:${issue}" ] || keep="${keep:+$keep }$e"; done
          REVIEW_EXTRA="$keep"
        else REVIEW_PID=""; REVIEW_ISSUE=""; fi ;;
    esac
  fi
}

sweep_lane_zombies() {
  check_lane_zombie build  "Ready Building QA Review"
  local e
  for e in ${BUILD_EXTRA:-}; do check_lane_zombie build "Ready Building QA Review" "${e%%:*}" "${e#*:}"; done
  check_lane_zombie qa     "QA"
  for e in ${QA_EXTRA:-}; do check_lane_zombie qa "QA" "${e%%:*}" "${e#*:}"; done
  check_lane_zombie review "Review"
  for e in ${REVIEW_EXTRA:-}; do check_lane_zombie review "Review" "${e%%:*}" "${e#*:}"; done
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
  tick_guard nosleep || return 0
  tick_fetch nosleep || return 0
  sweep_lane_zombies
}

# A folder in inflight/ (git-ignored in every board repo); every reader of inflight/ skips folders and non-numeric names, as merge.lock
# #237: super-board-worker-wrap.sh ends every worker log section with `worker_exit: exit=<mã> signal=<tên> elapsed=<s>s`.
worker_exit_line() {
  awk '/^=== dispatch /{l=""} /^worker_exit: /{l=$0} END{print l}' "$1" 2>/dev/null || true
}

note_worker_exit() {
  # $1 = issue; the lock just read (LANE) is the worker that died. Logs its exit record and, unless it exited 0, comments on the card.
  # No record = the wrapper itself was killed (SIGKILL, host asleep) or the worker predates the wrapper.
  local line role
  line=$(worker_exit_line "${WORKER_LOG:-${WORKER_LOG_DIR}/worker-${LANE:-?}-${1}.log}")
  log "worker of #${1} (lane ${LANE:-?}) exit record: ${line:-none — wrapper killed or host asleep}"
  # exit=0: finished; exit=143: stopped by the runner itself (super-board stop sends TERM), not a death worth a card comment.
  case "$line" in *"exit=0 "*|*"exit=143 "*) return 0 ;; esac
  case "${LANE:-}" in qa) role=qa ;; review) role=reviewer ;; *) role=builder ;; esac
  # A diagnostic comment must never halt the board: gh_write_once exits 79 on a gh failure and `|| true` cannot catch an exit.
  gh_checkpoint
  gh issue comment "$1" --body "[${role}] [report] ⚠️ worker chết giữa chừng
Did: runner thấy worker lane ${LANE:-?} đã dừng, thẻ sẽ được giao lại.
Exit record: ${line:-không có (wrapper bị kill hoặc máy ngủ)}
Next: lượt giao lại tiếp tục từ commit/comment cuối" >/dev/null 2>&1 || true
}

resume_hint() {
  # $1 = worker log. Words for the next prompt when the previous dispatch of this card died (exit != 0, or no record): continue, never restart.
  local line
  [ -f "$1" ] && grep -q '^=== dispatch ' "$1" || return 0
  line=$(worker_exit_line "$1")
  case "$line" in *"exit=0 "*) return 0 ;; esac
  printf 'Resume: the previous worker of this card died (%s). Do not start over: read the issue comments and PR threads, run git log in the lane worktree, and continue from the last commit and evidence.' "${line:-no exit record}"
}

early_death_file() { printf '%s/early-deaths/%s' "$INFLIGHT_DIR" "$1"; }

note_early_death() {
  # $1 = issue; the lock just read (LANE, STARTED) is the worker that died. #94 (18/10 19:26–19:47Z): a worker dying ~33 s after
  # each dispatch made reap free the card and the next tick claim it again, every ~40 s, until the board halted. A worker that died
  # within SB_EARLY_DEATH_S (120 s) of its dispatch is recorded here as "<epoch> <lane>", with the last line of its log, so the card
  # can cool down in that lane. Bookkeeping only: under the runner's `set -euo pipefail` no step here may end the runner.
  local age f last n now wlog="${WORKER_LOG:-${WORKER_LOG_DIR}/worker-${LANE:-?}-${1}.log}"
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
  # Giữ tối đa 20 dòng gần nhất của thẻ để vừa xét cửa sổ 10 phút vừa áp trần tổng SB_EARLY_MAX_TOTAL (mặc định 3) qua nhiều cửa sổ.
  { tail -n 19 "$f" 2>/dev/null || true; echo "$now ${LANE:-?}"; } > "$f.tmp" 2>/dev/null \
    && mv "$f.tmp" "$f" 2>/dev/null || return 0
  # the log may be gone or empty (the 19/10 shape): grep exits 1/2, which pipefail would turn into the runner's exit
  last=$( { grep -Ev '^[[:space:]]*$|^worker_exit: ' "$wlog" 2>/dev/null || true; } | tail -1 | cut -c1-200)
  n=$( { awk -v from=$((now - ${SB_EARLY_WINDOW_S:-600})) -v l="${LANE:-?}" '$1 >= from && $2 == l' "$f" 2>/dev/null || true; } | wc -l | tr -d ' ')
  log "⚠ worker of #${1} (lane ${LANE:-?}) ended ${age}s after dispatch (a crash or a very quick exit) — early end ${n} of this lane in ${SB_EARLY_WINDOW_S:-600}s; last log line: ${last:-<no worker log at ${wlog}>}"
}

early_backoff() {
  # $1 = issue, $2 = the column a lane takes it from. 0 = 2 early deaths of a lane serving that column within SB_EARLY_WINDOW_S: no
  # third claim until the window passes (AC of #94: at most 2 assign/unassign cycles per card in 10 minutes). Per lane: a Reviewer
  # that bounced the card to Ready in seconds says nothing about the Builder taking it next, nor two quick builds about its review.
  local f now n total lanes
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
  # Cầu chì tổng (circuit breaker): quá SB_EARLY_MAX_TOTAL (mặc định 3) lần chết sớm ở cùng lane thì ngắt hẳn, không lặp mỗi 10 phút.
  total=$( { awk -v lanes=" $lanes " 'index(lanes, " " $2 " ")' "$f" 2>/dev/null || true; } \
       | wc -l | tr -d ' ')
  [ "${n:-0}" -ge 2 ] || [ "${total:-0}" -ge "${SB_EARLY_MAX_TOTAL:-3}" ]
}

# #137 (20/10, OfficeReader): a QA worker that needed a real device exited after 60–120 s, moved nothing and wrote nothing, and the
# runner handed the card to the next worker five times in 40 minutes. dispatch_lane stamps the card's column and its issue comment
# count into the lock; when the worker's lock dies (qa/review lanes only: a build worker moves its card to Building at dispatch, and
# reclaim_dead_builds already caps those) block_noop_workers compares them with the board. Still in that column with no new comment is
# a no-op, one line `<epoch> <lane> <column> <count>` in inflight/noops/<issue>; SB_NOOP_MAX (2) of them inside SB_NOOP_WINDOW_S (24 h) park the card in Blocked instead
# of a third dispatch. Bookkeeping only: nothing here may end the runner.
issue_comment_count() {
  # $1 = issue. Prints its comment count; prints nothing when GitHub cannot say (the caller then concludes nothing).
  python3 "$SB_GITHUB_READ" --kind scalar -- api "repos/{owner}/{repo}/issues/$1" --jq .comments 2>/dev/null | tr -dc '0-9' || true
}

dispatch_baseline() {
  # $1 = issue, $2 = lane, $3 = 1 when the dispatch is judged. Called BEFORE the worker starts (a worker that comments at once would
  # inflate COMMENTS0, #316 R8); prints the FROM_COL/COMMENTS0 lines for dispatch_lane to write into the lock in the same write as PID=.
  # Nothing is printed for a baseline we cannot read, for the build lane, or for merge-only / merge-train (the right exit there is
  # "leave the card in Review", with no comment, #316 R5): that lock is never judged.
  local issue="$1" lane="$2" judge="${3:-1}" col count last_col last_count
  [ "$judge" = 1 ] || return 0
  case "$lane" in qa|review) ;; *) return 0 ;; esac
  col=$(issue_status "$issue")
  count=$(issue_comment_count "$issue")
  [ -n "$col" ] && [ -n "$count" ] || return 0
  # #316 R6: the card moved or got a comment since the last no-op (its ledger line holds column and count): that no-op is stale.
  read -r _ _ last_col last_count <<EOF
$( { tail -n 1 "$INFLIGHT_DIR/noops/$issue" 2>/dev/null || true; } )
EOF
  if [ -n "${last_col:-}" ] && { [ "$last_col" != "$col" ] || [ "${last_count:-0}" -lt "$count" ]; }; then
    rm -f "$INFLIGHT_DIR/noops/$issue" 2>/dev/null || true
  fi
  printf 'FROM_COL=%s\nCOMMENTS0=%s\n' "$col" "$count"
}

note_worker_end() {
  # $1 = issue; the lock just read (LANE, FROM_COL, COMMENTS0) is the worker that ended. Queued for block_noop_workers.
  case "${LANE:-}" in qa|review) ;; *) return 0 ;; esac
  [ -n "${FROM_COL:-}" ] && [ -n "${COMMENTS0:-}" ] || return 0
  NOOP_CHECK="${NOOP_CHECK:-} ${1}:${LANE}:${FROM_COL}:${COMMENTS0}"
}

block_noop_workers() {
  # Expensive tick, after fetch_project_items: judge the workers queued by note_worker_end. Sets NOOP_MOVED=1 when a card was moved.
  local pending="${NOOP_CHECK:-}" window="${SB_NOOP_WINDOW_S:-86400}" max="${SB_NOOP_MAX:-2}"
  local entry issue lane from c0 col count f now n item_id title wlog last tag
  NOOP_CHECK=""
  for entry in $pending; do
    IFS=: read -r issue lane from c0 <<EOF
$entry
EOF
    [ -n "$issue" ] && [ -n "$c0" ] || continue
    issue_locked "$issue" && continue
    f="$INFLIGHT_DIR/noops/$issue"
    col=$(issue_status "$issue")
    [ -n "$col" ] || continue
    count=$(issue_comment_count "$issue")
    [ -n "$count" ] || continue   # GitHub cannot say: conclude nothing
    if [ "$col" != "$from" ] || [ "$count" -gt "$c0" ]; then
      rm -f "$f" 2>/dev/null || true   # it moved the card or wrote something: progress
      continue
    fi
    now=$(date +%s)
    mkdir -p "$INFLIGHT_DIR/noops" 2>/dev/null || true
    { { tail -n 19 "$f" 2>/dev/null || true; } | awk -v from=$((now - window)) '$1 >= from'; echo "$now $lane $col $count"; } > "$f.tmp" 2>/dev/null \
      && mv "$f.tmp" "$f" 2>/dev/null || true
    n=$( { wc -l < "$f"; } 2>/dev/null | tr -d ' ')
    wlog="${WORKER_LOG_DIR:-docs/super-board}/worker-${lane}-${issue}.log"
    last=$( { grep -Ev '^[[:space:]]*$|^worker_exit: ' "$wlog" 2>/dev/null || true; } | tail -1 | cut -c1-200)
    if [ "${n:-0}" -lt "$max" ]; then
      log "⚠ #${issue} (lane ${lane}): worker ended with the card still in ${col} and no new comment — no-op ${n} of ${max}; last log line: ${last:-<no worker log at ${wlog}>}"
      continue
    fi
    item_id=$(echo "$PROJECT_ITEMS_JSON" | jq -r --argjson n "$issue" '[.items[] | select(.content.number == $n) | .id][0] // empty' 2>/dev/null || true)
    title=$(echo "$PROJECT_ITEMS_JSON" | jq -r --argjson n "$issue" '[.items[] | select(.content.number == $n) | .content.title][0] // empty' 2>/dev/null || true)
    tag="❓"
    printf '%s' "$last" | grep -qiE 'máy thật|thiết bị|real device|device|adb' && tag="📱"
    if [ -n "$item_id" ] && set_card_status "$item_id" "Blocked"; then
      NOOP_MOVED=1
      rm -f "$f" 2>/dev/null || true
      [ -n "$BOT_LOGIN" ] && gh_write_once issue edit "$issue" --remove-assignee "$BOT_LOGIN" >/dev/null 2>&1 || true
      gh_checkpoint
      gh_write_once issue comment "$issue" --body "[orchestrator] [blocker] 🛑 blocked · ${tag} ${lane} worker exited ${n} times without moving the card or commenting
Card:        #${issue}${title:+ ${title}}
Reason tag:  ${tag}
Why blocked: the ${lane} worker for #${issue} exited ${n} times in a row with the card still in ${col} and no new comment
Evidence:    ${wlog}; last log line: ${last:-<empty>}
Checked:     inflight lock reaped; card still in ${col}; issue comment count unchanged since dispatch (${c0})
What blocks: the worker cannot finish this card${last:+ — its last log line is quoted above}
Why I (bot) cannot decide:
             dispatching it again would repeat the same exit and keep the ${lane} lane busy while other cards wait
To unblock:  read the worker log and give the worker what it lacked
             [ ] Inspect ${wlog}
             [ ] Fix the cause (connect the device, label the card needs-device), then drag #${issue} back to ${from}
Owner:       repo admin
Move back:   drag this card to ${from} after the steps above are done
blocked-by:  -" >/dev/null 2>&1 || true
      log "🛑 #${issue} ${col} → Blocked: ${lane} worker exited ${n} times without a card move or comment"
    else
      gh_checkpoint
      log "⚠ #${issue} in ${col} — ${lane} worker is a no-op ${n} times but the card could not be moved to Blocked; drag it by hand"
    fi
  done
  return 0
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
      [ -z "$LANE" ] || note_worker_limit "${WORKER_LOG:-${WORKER_LOG_DIR}/worker-${LANE}-${issue}.log}"
      note_worker_exit "$issue"
      note_early_death "$issue"
      note_worker_end "$issue"
      # #288: PID chết rời danh sách "đã thấy ở QA": Tester mới tái dùng PID đó phải bắt đầu sạch (ân hạn Ready → QA).
      [ -z "$PID" ] || QA_SEEN_IN_QA=$(printf '%s\n' ${QA_SEEN_IN_QA:-} | grep -vxF -- "$PID" | tr '\n' ' ') || true
      [ "${LANE:-}" = "build" ] && RECLAIM_BUILDING="${RECLAIM_BUILDING:-} ${issue}" || true
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
      *"merge-train worker on issues "*"#${issue}"[,\ ]*) ;;   # worker train của đợt (#228): prompt liệt kê cả đợt, không có "issue #N for"
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
    # R3: worker merge train giữ lock của MỌI thẻ trong đợt cùng một PID: nhận lại một lần, lock còn lại giữ nguyên (không thêm slot).
    case " ${ADOPTED_PIDS:-} " in *" $PID "*) log "lock on #${issue} belongs to the already adopted worker pid=${PID} (merge train batch)"; continue ;; esac
    case "$LANE" in
      build)
        if lane_idle "${BUILD_PID:-}"; then BUILD_PID="$PID"; BUILD_ISSUE="$issue"
        else BUILD_EXTRA="${BUILD_EXTRA:+$BUILD_EXTRA }${PID}:${issue}"; fi ;;
      qa)
        if lane_idle "${QA_PID:-}"; then QA_PID="$PID"; QA_ISSUE="$issue"
        else QA_EXTRA="${QA_EXTRA:+$QA_EXTRA }${PID}:${issue}"; fi ;;
      review)
        if lane_idle "${REVIEW_PID:-}"; then REVIEW_PID="$PID"; REVIEW_ISSUE="$issue"
        else REVIEW_EXTRA="${REVIEW_EXTRA:+$REVIEW_EXTRA }${PID}:${issue}"; fi ;;
      *) continue ;;
    esac
    ADOPTED_PIDS="${ADOPTED_PIDS:-} $PID"
    log "adopted live ${LANE} worker on #${issue} (pid=${PID}) from the previous run"
  done
}

own_lane_pids() {
  # PID trong các lane do chính lần chạy này khởi tạo (không phải nhận lại): khi dừng khẩn chỉ kill các PID này
  # (hợp đồng của halt_cleanup).
  local pid e extras=""
  for e in ${BUILD_EXTRA:-} ${QA_EXTRA:-} ${REVIEW_EXTRA:-}; do extras="$extras ${e%%:*}"; done
  for pid in "${BUILD_PID:-}" $extras "${QA_PID:-}" "${REVIEW_PID:-}"; do
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
  while read -r pid ppid cmd; do
    [ -n "$pid" ] && [ "$pid" != "$$" ] || continue
    # #237: worker chạy dưới wrapper (pid trong lock) — con của một PID đã khoá không phải orphan.
    case "$locked" in *" $ppid "*) continue ;; esac
    case "$cmd" in *"--root '${root}'"*"for super-board run"*) ;; *) continue ;; esac
    exe=${cmd%% *}
    case "${exe##*/}" in claude|agy|grok) ;; *) continue ;; esac
    case "$locked" in *" $pid "*) continue ;; esac
    echo "$pid"
  done < <(ps -ww -A -o pid= -o ppid= -o command= 2>/dev/null || true)
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
  # Dọn các worktree tạm red-proof-* bị bỏ rơi trong TMPDIR khi không có tiến trình red_proof.py nào đang chạy.
  if ! ps -ww -A -o command= 2>/dev/null | grep -qE '(^|[[:space:]/])python[0-9.]*[[:space:]].*red_proof\.py'; then
    while IFS= read -r wt; do
      case "$wt" in
        */red-proof-*)
          if git worktree remove --force "$wt" 2>/dev/null || git worktree remove "$wt" 2>/dev/null; then
            log "stale red-proof worktree: $wt — removed"
          fi ;;
      esac
    done < <(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' || true)
  fi
  return 0
}

reclaim_stranded_building() {
  # Run start (mọi thẻ Building không có lock sống) hoặc giữa lượt chạy ($1 = danh sách issue vừa mất worker build,
  # $2 = câu Did: cho comment). Trả thẻ Building không còn worker sống và không có assignee nào khác ngoài bot về Ready;
  # nhánh issue được giữ nguyên để Builder kế tiếp làm tiếp thay vì làm lại từ đầu.
  local only="${1:-}" did="${2:-found no live worker; the last run stopped mid-build}"
  local issue item_id branch wt wt_branch
  while IFS=$'\t' read -r issue item_id; do
    [ -n "$issue" ] || continue
    issue_locked "$issue" && continue
    # #254: builder đóng issue khi AC đã đạt sẵn trên main (không PR) — thẻ đóng ở Building đi thẳng Done, không quay về Ready.
    local issue_rc=0
    issue_is_open "$issue" || issue_rc=$?
    [ "$issue_rc" -le 1 ] || exit "$issue_rc"
    if [ "$issue_rc" -eq 1 ]; then
      if set_card_status "$item_id" "Done"; then
        gh_checkpoint
        [ -n "$BOT_LOGIN" ] && gh_write_once issue edit "$issue" --remove-assignee "$BOT_LOGIN" >/dev/null 2>&1 || true
        rm -f "$INFLIGHT_DIR/$issue"
        log "reconciled closed #${issue} -> Done (was 'Building') — builder closed it, AC already met"
      else
        gh_checkpoint
        log "⚠ closed #${issue} in Building — could not move it to Done; drag it by hand"
      fi
      continue
    fi
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
    RECLAIM_MOVED=1
    [ -n "$BOT_LOGIN" ] && gh_write_once issue edit "$issue" --remove-assignee "$BOT_LOGIN" >/dev/null 2>&1 || true
    # Comment format: writing-standard.md § 4.
    gh_checkpoint
    gh_write_once issue comment "$issue" --body "[orchestrator] [report] ↩️ back to Ready · stranded in Building
Did: ${did}
✅ Done: card moved to Ready · branch ${branch:-none found}${branch:+ kept}
Next: builder (next tick${branch:+, continues on the branch})" >/dev/null 2>&1 || true
    log "↩ stranded #${issue}: Building → Ready (branch ${branch:-none})"
  done <<EOF
$(echo "$PROJECT_ITEMS_JSON" | jq -r --arg bot "$BOT_LOGIN" --arg only " $only " '
    .items[]
    | select(.status == "Building" and .content.type == "Issue")
    | (" " + (.content.number | tostring) + " ") as $n
    | select($only == "  " or ($only | contains($n)))
    | select(((.content.assignees // []) - [$bot]) | length == 0)
    | [(.content.number | tostring), (.id // "")] | @tsv')
EOF
}

reclaim_dead_builds() {
  # Giữa lượt chạy (expensive tick): các lock lane=build vừa chết ở reap_finished_locks hoặc issue_locked đã ghi số
  # issue vào RECLAIM_BUILDING. Nếu thẻ vẫn ở Building, không có lock sống và không có assignee nào khác ngoài bot:
  #  - Dưới trần SB_RECLAIM_MAX (mặc định 2) lần trong cửa sổ SB_RECLAIM_WINDOW_S (mặc định 86400 s): ghi epoch vào
  #    sổ $INFLIGHT_DIR/reclaims/<issue> rồi trả thẻ về Ready qua reclaim_stranded_building.
  #  - Đạt/vượt trần: chuyển thẻ sang Blocked kèm comment theo block-template (dòng cuối `blocked-by:  -`).
  # Luôn return 0; đặt RECLAIM_MOVED=1 khi có thẻ được chuyển (Ready hoặc Blocked).
  local pending="${RECLAIM_BUILDING:-}"
  RECLAIM_BUILDING=""
  [ -n "${pending// /}" ] || return 0
  local window="${SB_RECLAIM_WINDOW_S:-86400}" max="${SB_RECLAIM_MAX:-2}"
  local issue item_id title seen=" " now f n wlog
  while IFS=$'\t' read -r issue item_id title; do
    [ -n "$issue" ] || continue
    case "$seen" in *" $issue "*) continue ;; esac
    seen="${seen}${issue} "
    issue_locked "$issue" && continue
    now=$(date +%s)
    f="$INFLIGHT_DIR/reclaims/$issue"
    n=0
    if [ -f "$f" ]; then
      n=$( { awk -v from=$((now - window)) '$1 >= from' "$f" 2>/dev/null || true; } | wc -l | tr -d ' ')
    fi
    if [ "${n:-0}" -ge "$max" ]; then
      wlog="${WORKER_LOG_DIR:-docs/super-board}/worker-build-${issue}.log"
      if set_card_status "$item_id" "Blocked"; then
        RECLAIM_MOVED=1
        [ -n "$BOT_LOGIN" ] && gh_write_once issue edit "$issue" --remove-assignee "$BOT_LOGIN" >/dev/null 2>&1 || true
        gh_checkpoint
        gh_write_once issue comment "$issue" --body "[orchestrator] [blocker] 🛑 blocked · 🔁 build worker died mid-run $((n + 1)) times in 24h
Card:        #${issue}${title:+ ${title}}
Reason tag:  🔁
Why blocked: build worker for #${issue} died mid-run $((n + 1)) times within ${window}s after moving the card to Building
Evidence:    ${wlog} (${n} prior reclaims in ${window}s; cap SB_RECLAIM_MAX=${max})
Checked:     inflight lock reaped; card still in Building with no live worker and no human assignee
What blocks: repeated build worker termination mid-run (e.g. gate/test timeout or OOM under load)
Why I (bot) cannot decide:
             re-queuing past ${max} reclaims in ${window}s would burn build slots in an infinite loop
To unblock:  inspect the worker log and resolve the mid-run crash or timeout
             [ ] Inspect ${wlog} for the failing step or timeout
             [ ] Fix or split the task, then drag #${issue} back to Ready
Owner:       repo admin
Move back:   drag this card to Ready after the steps above are done
blocked-by:  -" >/dev/null 2>&1 || true
        log "🛑 #${issue} Building → Blocked: build worker died mid-run $((n + 1)) times in ${window}s"
      else
        gh_checkpoint
        log "⚠ stranded #${issue} in Building — could not move it to Blocked; drag it by hand"
      fi
    else
      mkdir -p "$INFLIGHT_DIR/reclaims" 2>/dev/null || true
      { tail -n 19 "$f" 2>/dev/null || true; echo "$now"; } > "$f.tmp" 2>/dev/null \
        && mv "$f.tmp" "$f" 2>/dev/null || true
      reclaim_stranded_building "$issue" "its build worker died mid-run (lock reaped); the card was left in Building"
    fi
  done <<EOF
$(echo "$PROJECT_ITEMS_JSON" | jq -r --arg bot "$BOT_LOGIN" --arg only " $pending " '
    .items[]
    | select(.status == "Building" and .content.type == "Issue")
    | (" " + (.content.number | tostring) + " ") as $n
    | select($only | contains($n))
    | select(((.content.assignees // []) - [$bot]) | length == 0)
    | [(.content.number | tostring), (.id // ""), (.content.title // "")] | @tsv')
EOF
  RECLAIM_BUILDING=""
  return 0
}

startup_reconcile() {
  # Lúc khởi động, theo thứ tự: dọn lock chết, nhận lại worker còn sống (lock PID tái dùng bị gỡ ở đây), rồi mới trả
  # thẻ Building bị bỏ rơi về Ready. Đảo lại thì reclaim thấy lock PID tái dùng còn "sống" và bỏ qua thẻ, rồi adopt
  # gỡ lock: thẻ nằm Building suốt lần chạy. Worker được nhận lại vẫn giữ lock, nên reclaim vẫn bỏ qua thẻ của nó.
  reap_finished_locks
  BUILD_PID=""; BUILD_ISSUE=""; BUILD_EXTRA=""
  QA_PID=""; QA_ISSUE=""; QA_EXTRA=""
  REVIEW_PID=""; REVIEW_ISSUE=""; REVIEW_EXTRA=""
  adopt_live_locks
  gh_rate_guard
  fetch_project_items
  reclaim_stranded_building; fetch_project_items
  # Sweep sau reap/adopt: lock của lane còn sống đã rõ.
  sweep_merged_lanes
  RECLAIM_BUILDING=""
}
# Dọn worktree lane + nhánh của thẻ đã merge (#96, OCR batch trên #111): lúc khởi động và mỗi tick của vòng chính (#118: runner chạy
# nhiều ngày, worktree issue-7-review của PR #128 nằm tới lần khởi động sau). Chạy NỀN: một `gh pr list` cho mỗi thẻ còn sót có thể mất
# vài phút, không được giữ chân tick (OCR). Sweep tự khoá (sweep.lock), tự chặn lần gọi dày (--min-interval), không bao giờ ghi file
# halt và luôn exit 0; không gì ở đây dừng được runner. Runner tự giãn SWEEP_NEXT 600 s vì sweep không ghi stamp khi đọc GitHub hỏng:
# không có nó thì GitHub hỏng = một lượt gh mỗi tick. --min-interval 300 (< 600): stamp ghi lúc sweep XONG, nên với 600 lượt kế của
# runner hay rơi vào khoảng nghỉ của chính lượt trước và nhịp thành 10/20 phút xen kẽ (review); 300 vẫn chặn wave gọi chồng.
# (${BASE_BRANCH:+…}: ở lib-only BASE_BRANCH chưa đặt; không có thì sweep tự dò origin/HEAD — review)
sweep_merged_lanes() {
  local now
  now=$(date +%s)
  [ "$now" -lt "${SWEEP_NEXT:-0}" ] && return 0
  SWEEP_NEXT=$((now + 600))
  bash "$(dirname "$SB_GITHUB_READ")/super-board-post-merge-clean.sh" --sweep . --min-interval 300 ${BASE_BRANCH:+--base "$BASE_BRANCH"} \
    >>"$RUN_MANIFEST" 2>&1 </dev/null &
}

sweep_ledger() { printf '%s/swept-cards' "$INFLIGHT_DIR"; }
swept_seen() {
  # #253: sổ (thẻ, bộ blocker) đã sweep nằm ở file, không chỉ RAM: runner khởi động lại (4 lần trong ngày 22/10) không được
  # sweep lại đúng cặp đó rồi build lại thẻ vừa bị chặn. $1 = "<issue>:<blockers>". SWEPT_CARDS giữ làm cache RAM.
  case " ${SWEPT_CARDS:-} " in *" $1 "*) return 0 ;; esac
  grep -qxF -- "$1" "$(sweep_ledger)" 2>/dev/null
}
swept_add() {
  SWEPT_CARDS="${SWEPT_CARDS:-} $1"
  printf '%s\n' "$1" >> "$(sweep_ledger)" 2>/dev/null || log "⚠ cannot write the sweep ledger $(sweep_ledger)"
}

WAITING_LABEL="⏳ chờ thẻ khác"
sync_waiting_labels() {
  # #235: $1 = plan JSON. Thẻ Blocked chỉ chờ thẻ khác (plan `pending`) mang nhãn WAITING_LABEL để board phân biệt với thẻ cần người;
  # nhãn ở bất kỳ thẻ nào không còn trong `pending` (sweep vừa thả, kéo tay đi chỗ khác, thành 🙋) bị gỡ. Plan không có khoá `pending`
  # (planner cũ) thì không đụng nhãn nào. Nhãn không bao giờ là căn cứ chặn hay thả thẻ: chỉ hiển thị.
  local plan="$1" n
  printf '%s' "$plan" | jq -e 'has("pending")' >/dev/null 2>&1 || return 0
  local pending
  pending=$(printf '%s' "$plan" | jq -c '[.pending[]?.number]' 2>/dev/null) || return 0
  for n in $(echo "$PROJECT_ITEMS_JSON" | jq -r --argjson p "$pending" --arg l "$WAITING_LABEL" '
      .items[] | select(.status == "Blocked") | .content.number as $n | select($p | index($n))
      | select([((.labels // []) + (.content.labels // []))[] | (if type == "object" then .name else . end)] | index($l) | not)
      | $n' 2>/dev/null); do
    if [ "${WAITING_LABEL_READY:-0}" != 1 ]; then
      gh_write_once label create "$WAITING_LABEL" --color FBCA04 --description "Blocked only on other open cards; the sweep releases it" --force >/dev/null 2>&1 \
        && WAITING_LABEL_READY=1
    fi
    gh_write_once issue edit "$n" --add-label "$WAITING_LABEL" >/dev/null 2>&1 || true
    log "⏳ #${n}: label '${WAITING_LABEL}' (waits on other cards)"
  done
  for n in $(echo "$PROJECT_ITEMS_JSON" | jq -r --argjson p "$pending" --arg l "$WAITING_LABEL" '
      .items[] | .content.number as $n | select($p | index($n) | not)
      | select([((.labels // []) + (.content.labels // []))[] | (if type == "object" then .name else . end)] | index($l))
      | $n' 2>/dev/null); do
    gh_write_once issue edit "$n" --remove-label "$WAITING_LABEL" >/dev/null 2>&1 || true
    log "⏳ #${n}: label '${WAITING_LABEL}' removed"
  done
}

log_unreadable_blocked_by() {
  # #386: $1 = plan JSON. Thẻ Blocked có dòng blocked-by deps không đọc được (vd `#377`) không bao giờ được thả: ghi log một lần mỗi
  # (thẻ, lý do), bền qua lần khởi động lại như sổ sweep. Không đoán thay người viết, không đổi trạng thái thẻ.
  local n why key
  while IFS=$'\t' read -r n why; do
    [ -n "$n" ] || continue
    key="${n}:unreadable:$(printf '%s' "$why" | cksum | cut -d' ' -f1)"
    swept_seen "$key" && continue
    swept_add "$key"
    log "⚠ #${n}: blocked-by line unreadable, the sweep will not release it — ${why}"
  done <<EOF
$(printf '%s' "$1" | jq -r '.flag[]? | [(.number | tostring), ((.why // "") | gsub("[\t\n]"; " "))] | @tsv' 2>/dev/null)
EOF
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
  sync_waiting_labels "$plan"
  log_unreadable_blocked_by "$plan"
  while IFS=$'\t' read -r issue cleared; do
    # Không có blocker nào (thẻ bị kéo tay sang Blocked, body ghi None): không có gì vừa đóng, để người quyết.
    [ -n "$issue" ] && [ -n "$cleared" ] || continue
    # Mỗi (thẻ, bộ blocker) một lần, bền qua lần khởi động lại (người gỡ sổ swept-cards nếu muốn sweep lại): bị park lại với CÙNG blocker là việc người cần xem, không phải
    # vòng lặp; bị chặn bởi blocker KHÁC (daemon chạy nhiều ngày) thì vẫn được sweep khi blocker mới đóng.
    key="${issue}:$(printf '%s' "$cleared" | tr -d ' #')"
    if swept_seen "$key"; then log "blocked sweep: #${issue} already swept for ${cleared} — left Blocked"; continue; fi
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
    swept_add "$key"
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
  # 24/10 (#321): `resume` = a 🙋 card whose current-head request a trusted human answered `done` (super-board-approval.py,
  # verified by the deps helper). Only the workflow backend read it, so the legacy runner never acted on an approval and
  # #321 sat Blocked ~18 h. Back to Review, where the Reviewer re-checks the approval at the merge gate. Once per card.
  local akey why
  while IFS=$'\t' read -r issue akey why; do
    [ -n "$issue" ] || continue
    key="${issue}:resume:${akey:-none}"   # one move per approval (head + request id): a later approval moves it again
    if swept_seen "$key"; then continue; fi
    item_id=$(echo "$PROJECT_ITEMS_JSON" | jq -r --argjson n "$issue" '[.items[] | select(.content.number == $n) | .id][0] // empty')
    [ -n "$item_id" ] || continue
    if ! set_card_status "$item_id" "Review"; then
      gh_checkpoint
      log "⚠ blocked sweep: could not move approved #${issue} to Review"
      continue
    fi
    swept_add "$key"
    gh_checkpoint
    gh_write_once issue comment "$issue" --body "[orchestrator] [report] ↩️ back to Review · approval verified
Did: super-board-approval.py: ${why:-approval verified}
✅ Done: card moved Blocked → Review
Next: reviewer re-checks the approval and merges through the merge gate" >/dev/null 2>&1 || true
    log "↩ approved #${issue}: Blocked → Review (${why:-approval verified})"
    moved=0
  done <<EOF
$(printf '%s' "$plan" | jq -r '.resume[]? | [(.number | tostring), (if (.key // "") == "" then "none" else .key end), (.why // "")] | @tsv' 2>/dev/null)
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
  # #235: cộng thêm tập thẻ Blocked để thẻ vừa bị chặn được gắn nhãn chờ ngay, không phải đợi thẻ Done kế tiếp.
  sig="$(done_signature)|$(echo "$PROJECT_ITEMS_JSON" | jq -r '[.items[] | select(.status == "Blocked") | .content.number // empty] | sort | @csv' 2>/dev/null)"
  if [ "$sig" = "${SWEEP_DONE_SIG-<none>}" ]; then
    [ "${SWEEP_RETRY_AT:-0}" -gt 0 ] && [ "$(date +%s)" -ge "$SWEEP_RETRY_AT" ] || return 1
  fi
  SWEEP_DONE_SIG="$sig"; SWEEP_RETRY_AT=0
  sweep_blocked_cards || rc=$?
  [ "$rc" -ne 2 ] || SWEEP_RETRY_AT=$(( $(date +%s) + SWEEP_RETRY_SECONDS ))
  return "$rc"
}

# ── #363: cầu chì suite. ≥2 thẻ bị Blocked cùng một suite id (REG-…) trong SB_FUSE_WINDOW_H giờ là một nguyên nhân gốc, không phải hai thẻ:
# giữ MỘT thẻ (số nhỏ nhất, hay thẻ đang giữ cờ ngưng), các thẻ còn lại ghi `blocked-by: <thẻ giữ>` và ở nguyên Blocked để sweep thả về khi
# thẻ giữ đóng; NGƯNG giao Builder mới tới khi mọi thẻ giữ rời Blocked. KHÔNG BAO GIỜ đóng thẻ hay chuyển Done (suy đoán sai thì mất thẻ).
# Suite id chỉ lấy từ comment `[builder|qa|reviewer] [blocker]` MỚI NHẤT có cả REG-… lẫn TIMEOUT/FAIL/HANG (không lấy từ comment pass/unblock
# hay tiêu đề); mốc Blocked = createdAt của comment đó (không phải lúc runner thấy: lần triển khai đầu / mất sổ không đóng dấu "bây giờ").
# Thẻ 🙋 needs-you / human-gated và thẻ đã có `blocked-by:` là số thì bỏ qua. Sổ $INFLIGHT_DIR/fuse/blocked.tsv: `issue<TAB>epoch<TAB>suite|-`
# (đọc MỘT lần khi thẻ vào Blocked; thẻ rời Blocked bị xoá khỏi sổ). folded.tsv: thẻ đã ghi blocked-by (ghi TRƯỚC khi gọi gh: comment
# một lần dù board lỗi; thẻ rời Blocked thì xoá). Cờ ngưng $INFLIGHT_DIR/fuse/pause: mỗi thẻ giữ một dòng `keep<TAB>suite<TAB>epoch`.
# ponytail: chỉ lane Builder bị ngưng — QA/Review vẫn chạy; nâng khi cần.
SB_FUSE_WINDOW_H="${SB_FUSE_WINDOW_H:-6}"
fuse_dir() { printf '%s/fuse' "$INFLIGHT_DIR"; }

fuse_card_json() {
  # $1 = issue. In JSON {title, comments[{body,createdAt}]}; exit khác 0 khi đọc hỏng (caller thử lại tick sau, không ghi sổ).
  python3 "$SB_GITHUB_READ" --kind object -- issue view "$1" --json title,comments
}

fuse_card_info() {
  # $1 = issue. In `epoch<TAB>bb|-<TAB>suite suite…` của comment blocker mới nhất ghép suite với TIMEOUT/FAIL/HANG; không có thì in `-`.
  # bb = comment đó đã có `blocked-by:` là số (thẻ chờ thẻ khác, không phải việc của cầu chì).
  local json
  json=$(fuse_card_json "$1") || return $?
  printf '%s' "$json" | jq -r '[.comments[]? | select(.body | test("^\\s*\\[(builder|qa|reviewer)\\]\\s*\\[blocker\\]"))] | reverse
    | map(select(.body | test("TIMEOUT|FAIL|HANG"; "i"))
        | {t: (.createdAt | fromdateiso8601), s: ([.body | scan("REG-[A-Z0-9]+(?:-[A-Z0-9]+)*")] | unique),
           b: (([.body | scan("(?:^|\\n)[ \\t]*blocked-by:[ \\t]*([^\\n]*)"; "i")] | last // [""]) | .[0])}
        | select(.s | length > 0))
    | first // empty
    | "\(.t)\t\(if (.b | test("[0-9]")) then "bb" else "-" end)\t\(.s | join(" "))"' | grep . || echo "-"
}

fuse_paused() {
  # 0 khi cầu chì đang ngưng giao Builder: còn thẻ giữ ở Blocked. Mọi thẻ giữ rời Blocked (người đã xử lý) thì gỡ cờ. Board rỗng/đọc hỏng thì
  # giữ ngưng (không đoán). Chỉ ghi lại file khi bớt thẻ giữ.
  local f line keep cnt rest="" gone=0
  f="$(fuse_dir)/pause"; [ -f "$f" ] || return 1
  while IFS= read -r line; do
    keep=${line%%$'\t'*}
    case "$keep" in ''|*[!0-9]*) gone=1; continue ;; esac   # dòng rác không được ngưng build mãi
    cnt=$(printf '%s' "${PROJECT_ITEMS_JSON:-}" | jq -r --argjson n "$keep" '[.items[] | select(.content.number == $n and .status == "Blocked")] | length' 2>/dev/null)
    case "$cnt" in ''|*[!0-9]*) return 0 ;; esac
    if [ "$cnt" -gt 0 ]; then rest="${rest}${line}"$'\n'; else gone=1; fi
  done < "$f"
  if [ -n "$rest" ]; then
    [ "$gone" -eq 0 ] || printf '%s' "$rest" > "$f"
    return 0
  fi
  rm -f "$f"; FUSE_PAUSE_LOGGED=""
  log "🔌 suite fuse released: every merged card left Blocked — Builder dispatch resumes"
  return 1
}

suite_fuse_tick() {
  # Luôn trả 1: cầu chì không đổi cột của thẻ nào (caller không cần đọc lại board).
  local dir led fol now blocked n info suites s window suite nums keep dups d dl claimed="" members m fresh repo bline orc pauses rc _e bb
  dir=$(fuse_dir); led="$dir/blocked.tsv"; fol="$dir/folded.tsv"; now=$(date +%s)
  mkdir -p "$dir" 2>/dev/null || { log "⚠ suite fuse: cannot create $dir"; return 1; }
  blocked=$(echo "$PROJECT_ITEMS_JSON" | jq -r '.items[] | select(.status == "Blocked") | .content.number // empty' 2>/dev/null) || return 1
  : >> "$led"; : >> "$fol"
  # thẻ rời Blocked ra khỏi sổ và khỏi folded
  while IFS=$'\t' read -r n _e _s; do
    printf '%s\n' "$blocked" | grep -qx "$n" && printf '%s\t%s\t%s\n' "$n" "$_e" "$_s"
  done < "$led" > "$led.new" || true
  mv -f "$led.new" "$led"
  while IFS= read -r n; do
    printf '%s\n' "$blocked" | grep -qx "$n" && printf '%s\n' "$n"
  done < "$fol" > "$fol.new" || true
  mv -f "$fol.new" "$fol"
  for n in $blocked; do
    cut -f1 "$led" | grep -qx "$n" && continue
    rc=0; info=$(fuse_card_info "$n" 2>>"$RUN_MANIFEST") || rc=$?
    if [ "$rc" -ne 0 ]; then
      case "$RUNNER_HALT_CODES" in *" $rc "*) exit "$rc" ;; esac
      log "⚠ suite fuse: cannot read #${n} (exit ${rc}); retry next tick"; continue
    fi
    IFS=$'\t' read -r _e bb suites <<EOF
$info
EOF
    if [ "$info" = "-" ] || [ "$bb" != "-" ] || [ -z "$suites" ]; then printf '%s\t0\t-\n' "$n" >> "$led"
    else for s in $suites; do printf '%s\t%s\t%s\n' "$n" "$_e" "$s" >> "$led"; done; fi
  done
  window=$(( SB_FUSE_WINDOW_H * 3600 ))
  repo=$(jq -r '.repo.remote // empty' "$CONFIG_PATH" 2>/dev/null | sed -E 's#^(https?://github\.com/|git@github\.com:)##; s#\.git$##')
  pauses=""; [ -f "$dir/pause" ] && pauses=$(cut -f1 "$dir/pause")
  while IFS=$'\t' read -r suite nums; do
    [ -n "$suite" ] || continue
    # thẻ đã gộp, thẻ 🙋, thẻ đã dùng ở nhóm trước (thẻ nhiều suite chỉ vào một nhóm) không nhập nhóm
    members=""
    for m in $nums; do
      case " $claimed " in *" $m "*) continue ;; esac
      grep -qx "$m" "$fol" && continue
      echo "$PROJECT_ITEMS_JSON" | jq -e --argjson n "$m" "$FOR_A_PERSON_JQ"' [.items[] | select(.content.number == $n) | for_a_person] | any' >/dev/null 2>&1 && continue
      members="$members $m"
    done
    keep=""
    for m in $members; do case " $pauses " in *" $m "*) keep=$m; break ;; esac; done   # thẻ đang giữ cờ ngưng là thẻ giữ
    [ -n "$keep" ] || keep=$(printf '%s\n' $members | sort -n | head -1)
    dups=""; for d in $members; do [ "$d" = "$keep" ] || dups="$dups $d"; done
    [ -n "$dups" ] || continue
    claimed="$claimed $members"
    fresh=0; dl=""
    for d in $dups; do
      # dòng `blocked-by:` qua helper (số đã đóng bị bỏ; 79 = không đọc được, thử lại tick sau, không ghi sổ)
      if [ -n "$repo" ] && [ -f "$(dirname "$SB_GITHUB_READ")/super-board-blocked-by.py" ]; then
        orc=0; bline=$(python3 "$(dirname "$SB_GITHUB_READ")/super-board-blocked-by.py" line --repo "$repo" "$keep" 2>>"$RUN_MANIFEST") || orc=$?
        if [ "$orc" -ne 0 ]; then log "⚠ suite fuse: blocker check for #${keep} failed (exit ${orc}) — #${d} retried next tick"; continue; fi
      else bline="blocked-by: ${keep}"; fi
      [ "$bline" != "blocked-by: -" ] || continue   # thẻ giữ đã đóng giữa chừng: không còn gì để chờ
      printf '%s\n' "$d" >> "$fol" || { log "⚠ suite fuse: cannot write $fol"; continue; }
      fresh=1; dl="${dl:+$dl, }#${d}"
      gh_checkpoint
      gh_write_once issue comment "$d" --body "[orchestrator] [blocker] 🛑 blocked · 🔌 suite fuse · same suite ${suite} as #${keep}
Card:        #${d}
Reason tag:  🔌
Why blocked: ≥2 cards blocked on ${suite} within ${SB_FUSE_WINDOW_H}h — one root cause, handled in #${keep}
Evidence:    newest [blocker] comment of each card names ${suite} with TIMEOUT/FAIL/HANG
Owner:       whoever takes #${keep}
Move back:   the sweep returns this card to Ready when #${keep} closes
${bline}" >/dev/null 2>&1 || true
    done
    [ "$fresh" -eq 1 ] || continue
    case " $pauses " in *" $keep "*) ;; *)
      printf '%s\t%s\t%s\n' "$keep" "$suite" "$now" >> "$dir/pause"; pauses="$pauses $keep"
      gh_checkpoint
      gh_write_once issue comment "$keep" --body "[orchestrator] [report] 🔌 suite fuse · ${suite}
Did: cards blocked on ${suite} within ${SB_FUSE_WINDOW_H}h (${dl}) now wait on this one (blocked-by: ${keep}); none closed
✅ Done: new Builder dispatch is paused
Next: fix ${suite}, then move this card out of Blocked — Builder dispatch resumes" >/dev/null 2>&1 || true ;;
    esac
    log "🔌 suite fuse: ${suite} blocked ≥2 cards within ${SB_FUSE_WINDOW_H}h (${dl} wait on #${keep}) — Builder dispatch paused until #${keep} leaves Blocked"
  done <<EOF
$(awk -F'\t' -v now="$now" -v w="$window" '$3 != "-" && now - $2 <= w { c[$3] = c[$3] " " $1; k[$3]++ } END { for (s in c) if (k[s] >= 2) print s "\t" substr(c[s], 2) }' "$led" | sort)
EOF
  return 1
}

backlog_pull_enabled() {
  # #189: env SB_BACKLOG_PULL (0 tắt, 1 bật) thắng khoá `backlog_pull` của config; thiếu cả hai thì bật.
  case "${SB_BACKLOG_PULL:-}" in 0) return 1 ;; 1) return 0 ;; esac
  [ "$(jq -r 'if .backlog_pull == false then "off" else "on" end' "$CONFIG_PATH" 2>/dev/null)" != "off" ]
}

backlog_issue_body() {
  # $1 = số issue. In body của issue qua lớp đọc GitHub (exit khác 0 = đọc hỏng, caller dừng như issue_is_open).
  SB_GITHUB_READ_STRICT=1 python3 "$SB_GITHUB_READ" --kind issue -- issue view "$1" --json number,title,body | jq -r '.body'
}

backlog_ticket_gaps() {
  # Body trên stdin; in các phần còn thiếu của thẻ chuẩn (Problem, Fix, Acceptance Criteria có ít nhất một gạch đầu dòng — cùng
  # luật với super-board-preflight.sh nên thẻ kéo lên không bị preflight chặn "unclear"). Rỗng = đủ.
  jq -Rrs '(. / "\n") as $l
    | def sect($h): [ $l | to_entries[] | select(.value | test("^##[ \t]+" + $h + "(?!\\w)")) | .key ] as $k
        | if ($k | length) == 0 then null
          else [ $l[($k | last) + 1:][] ] as $t
            | ([ $t | to_entries[] | select(.value | test("^##[ \t]")) | .key ] | first) as $e
            | (if $e == null then $t else $t[:$e] end) end;
      [ (if (sect("Problem") // [] | any(.[]; test("\\S"))) then empty else "Problem" end),
        (if (sect("Fix") // [] | any(.[]; test("\\S"))) then empty else "Fix" end),
        (if (sect("Acceptance Criteria") // [] | any(.[]; test("^[ \t]*(?:[-*]|[0-9]{1,2}[.)])[ \t]+\\S"))) then empty else "Acceptance Criteria" end) ]
      | join(", ")'
}

pull_backlog_cards() {
  # #189: Ready rỗng mà lane build còn worker rảnh thì kéo thẻ Backlog lên Ready (bug trước, rồi thứ tự bảng), tối đa
  # BUILD_WORKERS - BUILD_COUNT - READY thẻ. Chỉ kéo thẻ không assignee, không chờ người (needs-you/human-gated), không wontfix /
  # loop:halted, đủ Problem/Fix/AC; thẻ thiếu bị comment lý do MỘT lần mỗi nội dung (sổ $INFLIGHT_DIR/backlog-skip). Thẻ đã CLOSED
  # về Done, không đếm vào trần.
  # Trả 0 khi bảng đã đổi (caller đọc lại), 1 khi không có gì.
  # ponytail: tối đa 20 thẻ xét mỗi tick (mỗi thẻ 2 lần đọc REST); Backlog dài hơn thì tick sau xét tiếp từ đầu — đổi sang con trỏ khi cần.
  local want moved=1 tried=0 issue item_id body gaps stamp issue_rc busy
  backlog_pull_enabled || return 1
  [ "${BUILD_COUNT:-0}" -lt "$BUILD_WORKERS" ] || return 1
  busy=$(( ${BUILD_COUNT:-0} + ${READY:-0} ))
  want=$(( BUILD_WORKERS - busy ))
  [ "$want" -gt 0 ] || return 1
  while IFS=$'\t' read -r issue item_id; do
    [ -n "$issue" ] && [ -n "$item_id" ] || continue
    [ "$want" -gt 0 ] && [ "$tried" -lt 20 ] || break
    tried=$((tried + 1))
    issue_rc=0; issue_is_open "$issue" || issue_rc=$?
    [ "$issue_rc" -le 1 ] || exit "$issue_rc"
    if [ "$issue_rc" -ne 0 ]; then
      if set_card_status "$item_id" "Done"; then
        log "backlog pull: #${issue} is CLOSED -> Done (not pulled)"; moved=0
      else
        gh_checkpoint; log "⚠ backlog pull: could not move closed #${issue} to Done"
      fi
      continue
    fi
    body=$(backlog_issue_body "$issue") || exit $?
    gaps=$(printf '%s\n' "$body" | backlog_ticket_gaps)
    if [ -n "$gaps" ]; then
      stamp="${gaps}:$(printf '%s' "$body" | cksum | cut -d' ' -f1)"
      mkdir -p "$INFLIGHT_DIR/backlog-skip"
      if [ "$(cat "$INFLIGHT_DIR/backlog-skip/$issue" 2>/dev/null)" != "$stamp" ]; then
        gh_checkpoint
        gh_write_once issue comment "$issue" --body "[orchestrator] [report] ⏸ not pulled from Backlog · ticket incomplete
Did: checked the body before moving it to Ready
❌ Not done: missing section(s): ${gaps} (Problem, Fix and Acceptance Criteria with at least one item, a dash or star bullet or a numbered line such as 1. or 1), are required)
Next: fill the missing section(s); the next tick pulls it" >/dev/null 2>&1 || true
        printf '%s' "$stamp" > "$INFLIGHT_DIR/backlog-skip/$issue"
        log "backlog pull: #${issue} skipped — missing ${gaps}"
      fi
      continue
    fi
    if ! set_card_status "$item_id" "Ready"; then
      gh_checkpoint; log "⚠ backlog pull: could not move #${issue} to Ready"
      continue
    fi
    rm -f "$INFLIGHT_DIR/backlog-skip/$issue"
    gh_checkpoint
    gh_write_once issue comment "$issue" --body "[orchestrator] [report] ⬆️ Backlog → Ready · build lane idle
Did: the lane had a free worker and the ticket has Problem, Fix and Acceptance Criteria
✅ Done: card moved Backlog → Ready
Next: builder (next tick)" >/dev/null 2>&1 || true
    log "⬆ backlog pull: #${issue} Backlog -> Ready"
    want=$((want - 1)); moved=0
  done <<EOF
$(echo "$PROJECT_ITEMS_JSON" | jq -r --arg bot "${BOT_LOGIN:-}" "$FOR_A_PERSON_JQ"'
    [.items | to_entries[] | select(.value.status == "Backlog" and .value.content.type == "Issue") | .value as $c | .key as $i
      | select((($c.content.assignees // []) - (if $bot == "" then [] else [$bot] end)) | length == 0)
      | select($c | for_a_person | not)
      | ([(($c.labels // []) + ($c.content.labels // []))[] | (if type == "object" then .name else . end) | ascii_downcase]) as $lb
      | select(($lb | index("wontfix") or index("loop:halted")) | not)
      | {n: $c.content.number, id: ($c.id // ""), rank: (if ($lb | index("bug")) then 0 else 1 end), i: $i}]
    | sort_by([.rank, .i])[] | [(.n | tostring), .id] | @tsv')
EOF
  return "$moved"
}

# ── Bản ghi trạng thái runner cho super-board-watchdog.sh: .claude/super-board/runner/<slug>.state
# (PID/SLUG/STARTED/DAEMON/LOG/STATE, thêm RC/ENDED khi thoát). STATE: running (còn nguyên khi bị SIGKILL) · crashed
# (thoát ngoài ý muốn) · finished (vòng lặp kết thúc: board rỗng, RUNAWAY, trần dispatch) · halted (mã dừng có chủ
# đích) · stopped (người dùng dừng: có stop marker <slug>.stopped của super-board-stop.sh). Watchdog chỉ khởi động lại
# running/crashed khi không có marker.
# Mã dừng có chủ đích sau khi trap EXIT được đặt: 9 verification-ready (mỗi tick) · 10 skills-readiness · 73 worker mồ
# côi / worktree cũ / runner khác còn sống · 74 wave lock · 75 guard production-merge · 76 GitHub halt whose record could not be written (never restarted: the uncertain write needs a person) · 79 GitHub halt. 64 không có ở đây:
# nó cũng là lỗi đọc của github-read (payload sai dạng 3 lần), thường tạm thời, nên watchdog thử lại có backoff và trần.
RUNNER_HALT_CODES=" 9 10 73 74 75 76 79 "
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
RECLAIM_BUILDING=""
RECLAIM_MOVED=0
LANDED_COUNT=0
DISPATCH_LOG=""

# ── Tự nạp lại code mới (#229, gap 4 của #226). Runner là bash chạy dài: PR sửa chính super-board-run.sh merge xong mà tiến trình vẫn
# chạy bản cũ cho tới khi ai đó dừng/chạy lại tay. Mỗi tick fetch origin/<base>; blob của script trên
# origin khác blob đang chạy thì: main checkout fast-forward được (đang ở <base>, HEAD là tổ tiên của origin) → ff rồi exec lại chính nó
# (cùng PID, nên bản ghi watchdog vẫn đúng; SB_WATCHDOG_START=1 nạp lại bộ đếm và không xoá stop marker). Gộp xung đột/gate đỏ, ff không áp
# được hoặc bản mới sai cú pháp → notify một lần cho mỗi bản origin, tiếp tục chạy bản cũ: không restart mù, không chạy code cũ im lặng.
# #379: nạp lại cả khi còn worker sống (board luôn bận thì không bao giờ rảnh: 24/10 runner chạy code cũ 5 giờ). exec giữ PID, worker là
# tiến trình con độc lập nên sống tiếp; runner mới chạy startup_reconcile → adopt_live_locks nhận lại. Không giao việc mới bằng code cũ:
# tick chạy self_reload_tick trước mọi dispatch, nên exec xảy ra trước khi giao.
RELOAD_SELF="${RELOAD_SELF:-$SCRIPT_DIR/super-board-run.sh}"
RELOAD_RUN_SUM="${RELOAD_RUN_SUM:-$(git hash-object "$RELOAD_SELF" 2>/dev/null || true)}"
RELOAD_WARNED=""
RELOAD_NEXT_CHECK=0
reload_exec() {
  runner_state_write running
  SB_WATCHDOG_START=1 SB_RELOADED=1 exec bash "$1" "$CONFIG_SLUG"
}
reload_warn() {
  # $1 = blob của script trên origin, $2 = lý do. Một cảnh báo cho mỗi bản origin.
  [ "$RELOAD_WARNED" != "$1" ] || return 0
  RELOAD_WARNED="$1"
  log "⚠ self-reload: origin/${BASE_BRANCH} has a newer super-board-run.sh but this runner keeps the old code — $2"
  board_notify send --card "$CONFIG_SLUG" --text "runner đang chạy code cũ: origin/${BASE_BRANCH} có super-board-run.sh mới nhưng không nạp được — $2"
}
reload_finish_main() {
  # Worktree tạm tại HEAD của main (không phải origin/<base>: finish coi worktree ở origin là PR đã squash và từ chối), gộp origin vào đó
  # rồi finish (gate, fast-forward main). Xung đột/gate đỏ → khác 0, main giữ nguyên.
  local ak wt rc out
  if [ -n "${SB_WORKTREE_CMD:-}" ]; then read -r -a ak <<<"$SB_WORKTREE_CMD"
  elif command -v agent-kit >/dev/null 2>&1; then ak=(agent-kit worktree); else ak=(python3 .agents/devkit/scripts/git/worktree.py); fi
  wt=".claude/worktrees/self-reload-$$-$(date +%s)"   # exec giữ PID: hậu tố thời gian để bản mồ côi của lần trước không chặn lần này
  out=$("${ak[@]}" add "$wt" 2>&1) || { log "⚠ self-reload: cannot create worktree $wt: $(printf '%s' "$out" | tail -c 300)"; return 1; }
  if git -C "$wt" merge --no-edit -q "origin/${BASE_BRANCH}" >/dev/null 2>&1; then
    out=$("${ak[@]}" finish "$wt" 2>&1); rc=$?
  else
    git -C "$wt" merge --abort >/dev/null 2>&1; rc=1
  fi
  [ "$rc" -eq 0 ] || log "⚠ self-reload: merge origin/${BASE_BRANCH} / worktree finish $wt failed (rc=$rc): $(printf '%s' "$out" | tail -c 300)"
  # finish thành công đã gỡ worktree; chỉ gỡ khi thư mục còn đó
  [ ! -d "$wt" ] || "${ak[@]}" remove "$wt" >/dev/null 2>&1 || log "⚠ self-reload: worktree remove $wt failed; left for the cleanup hook"
  return "$rc"
}
self_reload_tick() {
  local now new disk rel cur
  [ -n "$RELOAD_RUN_SUM" ] || return 0
  now=$(date +%s)
  [ "$now" -ge "$RELOAD_NEXT_CHECK" ] || return 0
  RELOAD_NEXT_CHECK=$((now + ${SB_RELOAD_EVERY:-${TICK_SECONDS:-120}}))
  rel=$(git ls-files --full-name -- "$RELOAD_SELF" 2>/dev/null | head -1) || rel=""
  [ -n "$rel" ] || return 0
  git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20 fetch -q origin "$BASE_BRANCH" >/dev/null 2>&1 \
    || { log "⚠ self-reload: git fetch origin ${BASE_BRANCH} failed; retrying next check"; return 0; }
  new=$(git rev-parse -q --verify "origin/${BASE_BRANCH}:${rel}" 2>/dev/null) || return 0
  [ "$new" != "$RELOAD_RUN_SUM" ] || return 0
  disk=$(git hash-object "$RELOAD_SELF" 2>/dev/null) || disk=""
  if [ "$disk" != "$new" ]; then
    cur=$(git symbolic-ref -q --short HEAD 2>/dev/null) || cur=""
    if [ "$cur" != "$BASE_BRANCH" ]; then
      reload_warn "$new" "main checkout is on branch '${cur:-detached}', not ${BASE_BRANCH}; bring it level, then the next idle tick reloads"
      return 0
    fi
    if git merge-base --is-ancestor HEAD "origin/${BASE_BRANCH}" 2>/dev/null; then
      git merge --ff-only -q "origin/${BASE_BRANCH}" >/dev/null 2>&1 \
        || { reload_warn "$new" "git merge --ff-only origin/${BASE_BRANCH} failed (uncommitted edits in the way?)"; return 0; }
    else
      # Main có commit cục bộ của phiên khác (#308): gộp origin vào main bằng đường finish (worktree tạm + gate + ff), không đụng tay.
      reload_finish_main \
        || { reload_warn "$new" "main has local commits and merging origin/${BASE_BRANCH} through worktree finish failed (conflict, red gate or dirty files in the way)"; return 0; }
    fi
    disk=$(git hash-object "$RELOAD_SELF" 2>/dev/null) || disk=""
    [ "$disk" = "$new" ] || { reload_warn "$new" "after the fast-forward the file on disk still differs from origin"; return 0; }
  fi
  bash -n "$RELOAD_SELF" 2>/dev/null || { reload_warn "$new" "the new script fails bash -n"; return 0; }
  log "♻ self-reload: origin/${BASE_BRANCH} changed super-board-run.sh (${RELOAD_RUN_SUM:0:7} → ${new:0:7}) — restarting on the new code (${ACTIVE_WORKERS:-0} live worker(s) will be adopted)"
  reload_exec "$RELOAD_SELF"
}

# Sourced by the gate tests (`SB_LIB_ONLY=1 . scripts/super-board-run.sh`) to exercise
# the helpers above without starting a run. Executing the script normally is unaffected.
if [ "${SB_LIB_ONLY:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

# A readiness failure (9, 10) stops only workers launched by this dispatcher. Keep their
# locks, worktrees, claims, and approval evidence for explicit recovery.
# A GitHub halt (79) does NOT stop workers (#306): they share the github-read layer and stop themselves at
# check_halt, and the next runner adopts the survivors as after a crash. Killing them lost the work done mid-lane.
halt_cleanup() {
  local rc=$?
  if [ "$rc" -eq 9 ] || [ "$rc" -eq 10 ] || [ "$rc" -eq 76 ]; then   # 76: no halt record on disk, so workers cannot see a halt: stop them here
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
  t=$(file_mtime "$STOP_MARK") || return 0
  [ "$t" -le "$RUNNER_BORN" ] || return 0
  p=$(sed -n 's/^PID=//p' "$STOP_MARK" 2>/dev/null | head -1) || p=""
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null || return 1
  case "$(ps -ww -o command= -p "$p" 2>/dev/null || true)" in *super-board-stop.sh*) return 0 ;; esac
  return 1
}
if [ "${SB_WATCHDOG_START:-0}" = "1" ]; then
  START_TAG=" (watchdog restart)"
  [ "${SB_RELOADED:-0}" != "1" ] || START_TAG=" (self-reload)"
  unset SB_RELOADED
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
  # grep -E trên workflow đã nối dòng: rg không phải binary trên mọi máy, thiếu nó guard này cho qua (fail-open).
  workflow_push_main() {
    local f
    for f in .github/workflows/*; do
      [ -f "$f" ] || continue
      tr '\n' ' ' < "$f" | grep -Eq 'on:[[:space:]]*push:[[:space:]]*branches:[^a-z]*main' && return 0
    done
    return 1
  }
  if workflow_push_main || [ -f vercel.json ] || [ -f netlify.toml ]; then
    log "🛡 refusing to start: would auto-merge to production main."
    exit 75
  fi
fi

# Existing legacy work is inspected/moved by a human, never deleted on upgrade.
check_legacy_worktrees
cleanup_stale_worktrees

startup_reconcile

# ───────────────────────────── main loop ─────────────────────────────
refresh_device_state
INITIAL_READY=$(( $(column_count "Ready") - $(person_count "Ready") ))   # as READY each tick: cards for a person left out (#95)
log "initial Ready count: $INITIAL_READY"

# Landed-work baseline (issue #8). Progress is a change in this set, not lane state.
PREV_DONE_SIG=$(done_signature)
INITIAL_DONE_SIG="$PREV_DONE_SIG"
[ "${SB_WATCHDOG_START:-0}" = "1" ] || NO_PROGRESS_CYCLE_COUNT=0   # watchdog khởi động lại: đã nạp từ bản ghi ở trên; khởi động tường minh đếm từ 0, không thừa hưởng môi trường người gọi

while true; do
  refresh_run_paths
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
  sweep_merged_lanes   # trước nhánh cap-reached: worktree của thẻ vừa merge được gỡ cả khi 3 lane đều bận (#118)

  # ── Zombie sweep against the LAST cached project state (no extra API).
  #    Catches workers whose card already moved out of the lane's source column
  #    but whose claude -p process didn't exit. Runs every tick, even cheap ones,
  #    so a cap-reached pipeline can still self-heal when one lane is a zombie.
  sweep_lane_zombies

  # ── Free pre-check: count active lanes from local PIDs (no API calls).
  BUILD_IDLE=1; QA_IDLE=1; REVIEW_IDLE=1
  build_workers_count
  [ "$BUILD_COUNT" -eq 0 ] || BUILD_IDLE=0
  lane_workers_count qa; lane_workers_count review
  [ "$QA_COUNT" -eq 0 ] || QA_IDLE=0
  [ "$REVIEW_COUNT" -eq 0 ] || REVIEW_IDLE=0

  ACTIVE_WORKERS=$(( BUILD_COUNT + QA_COUNT + REVIEW_COUNT ))   # một trần chung cho cả 3 lane

  # Nạp lại code (kể cả khi còn worker, #379) nếu super-board-run.sh trên origin đã đổi (#229). Có thể exec và không quay lại.
  self_reload_tick

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
  #    QA/Review còn chỗ thêm worker (qa_workers/review_workers > số đang chạy) thì KHÔNG coi là đầy: worker thêm không tốn slot lane (#209).
  #    Trần mặc định 1 thì QA_COUNT>=QA_WORKERS khi lane bận, nên điều kiện này đúng như cũ.
  if tick_is_cheap; then
    log "tick — cap reached (machine at ${MAX_WORKERS} workers, ${ACTIVE_WORKERS} here) — skipping GraphQL fetch, sleeping ${TICK_SECONDS}s"
    tick_sleep "$TICK_SECONDS"
    continue
  fi

  # ── Expensive-tick path: we have capacity, fetch real state.
  tick_guard || continue
  tick_fetch || continue

  # Re-sweep zombies against fresh cache; the previous sweep used stale data.
  sweep_lane_zombies
  RECLAIM_MOVED=0
  reclaim_dead_builds
  if [ "$RECLAIM_MOVED" = 1 ]; then tick_fetch || continue; fi
  NOOP_MOVED=0
  block_noop_workers
  if [ "$NOOP_MOVED" = 1 ]; then tick_fetch || continue; fi
  BUILD_IDLE=1; QA_IDLE=1; REVIEW_IDLE=1
  build_workers_count
  [ "$BUILD_COUNT" -eq 0 ] || BUILD_IDLE=0
  lane_workers_count qa; lane_workers_count review
  [ "$QA_COUNT" -eq 0 ] || QA_IDLE=0
  [ "$REVIEW_COUNT" -eq 0 ] || REVIEW_IDLE=0
  ACTIVE_WORKERS=$(( BUILD_COUNT + QA_COUNT + REVIEW_COUNT ))   # một trần chung cho cả 3 lane

  # Thẻ Blocked có blocker đã về Done thì trở lại Ready (runner này trước đây không có sweep: Goods #2, 2026-10-16).
  if maybe_sweep_blocked; then tick_fetch || continue; fi
  # #363: ≥2 thẻ Blocked cùng suite id trong N giờ → một thẻ + ngưng giao Builder (suite_fuse_tick).
  if suite_fuse_tick; then tick_fetch || continue; fi

  count_board

  # #189: lane build còn worker rảnh mà Ready không đủ việc thì kéo thẻ Backlog đủ AC lên (cờ backlog_pull).
  if pull_backlog_cards; then tick_fetch || continue; count_board; fi

  log "tick — Ready=$READY Building=$BUILDING QA=$QA Review=$REVIEW Blocked=$BLOCKED lanes: b_idle=$BUILD_IDLE(#${BUILD_ISSUE:-_}${BUILD_EXTRA:+ +${BUILD_EXTRA}}) b_workers=${BUILD_COUNT}/${BUILD_WORKERS} q_idle=$QA_IDLE(#${QA_ISSUE:-_}${QA_EXTRA:+ +${QA_EXTRA}}) q_workers=${QA_COUNT}/${QA_WORKERS} r_idle=$REVIEW_IDLE(#${REVIEW_ISSUE:-_}${REVIEW_EXTRA:+ +${REVIEW_EXTRA}}) r_workers=${REVIEW_COUNT}/${REVIEW_WORKERS} waiting_on_you=$WAITING"

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

  # Review / QA: lane_dispatch_tick giao tối đa một thẻ mỗi tick; qa_workers / review_workers > 1 cho phép worker thêm khi tải cho phép (#209).
  if [ "$REVIEW" -gt 0 ]; then lane_dispatch_tick review Review; fi
  QA_FREE=0; QA_DISPATCHED=0
  if [ "$QA" -gt 0 ]; then lane_dispatch_tick qa QA; QA_DISPATCHED=$LANE_DISPATCHED; fi
  # Thẻ Ready mang nhãn `qa` đi vào lane QA: chỉ khi tick này lane QA chưa nhận thẻ nào và còn chỗ.
  if [ "$QA_DISPATCHED" -eq 0 ] && ready_qa_lane_free "$READY"; then QA_FREE=1; fi
  # Ready: the top card's label picks the lane — `qa` skips Building (Tester),
  # anything else is built first. A busy lane waits for the next tick.
  # Lane build: worker đầu như trước; worker thêm (build_workers > 1) chỉ khi tải máy cho phép (build_slot_free, một worker mỗi tick).
  BUILD_FREE=0
  if can_dispatch && [ "$READY" -gt 0 ]; then build_slot_free || true; fi
  if can_dispatch && [ "$READY" -gt 0 ] && { [ "$BUILD_FREE" -eq 1 ] || [ "$QA_FREE" -eq 1 ]; }; then
    if top_card_in_column "Ready"; then
      if [ "$(card_lane "$TOP_ISSUE")" = "qa" ]; then
        [ "$QA_FREE" -eq 1 ] && { dispatch_lane qa "$TOP_ISSUE"; ACTIVE_WORKERS=$((ACTIVE_WORKERS + 1)); }
      elif [ "$BUILD_FREE" -eq 1 ]; then
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
