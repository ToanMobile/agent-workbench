#!/usr/bin/env bash
# super-board-stop.sh — graceful shutdown of an in-flight super-board run.
#
# What it does:
#   0. Write the durable stop marker .claude/super-board/runner/<slug>.stopped — even when nothing is running.
#      super-board-watchdog.sh never restarts a board that has it; `super-board run <slug>` clears it.
#   1. Find every in-flight worker (lock files under .claude/super-board/inflight/).
#      Stop any Codex wave and its lane process groups before comments/releases.
#   2. For each one, post a "stopped mid-flight" comment on the issue AND its PR
#      (with last commit, lane, and resume hint) — so context survives the kill.
#   3. Release the GitHub assignee mutex on each claimed issue.
#   4. SIGTERM → 1s → SIGKILL the worker PIDs.
#   5. Kill the legacy dispatcher loop (super-board-run.sh).
#   6. Remove in-flight locks. Leave worktrees in place (Builder can resume).
#   7. Print summary + resume command.
#
# What it does NOT do:
#   - Wait for workers to reach a clean stopping point (claude -p has no SIGTERM
#     handler that flushes a partial commit). Unsaved in-memory work can be lost;
#     uncommitted files remain in the preserved worktree for inspection.
#   - Touch worktrees. Leaving them lets the next worker pick up faster.
#   - Touch branches or PRs. State lives on the GitHub Project board.
#
# Resume:
#   super-board run <slug>     — same command. The board is the state. Cards sit
#                                in whichever column they were in. Workers re-claim
#                                from the "stopped" comment context.
#
# Usage:
#   scripts/super-board-stop.sh [<config-slug>]
#
# Exit codes:
#   0  clean stop (or nothing to stop)
#   64 missing arg + no .claude/super-board/active
#   66 config not found

set -euo pipefail

# Auto-resolve repository root if called from outside
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [ -d "$REPO_ROOT/.claude/super-board" ]; then
  cd "$REPO_ROOT"
fi

# ───────────────────────────── args + paths ─────────────────────────────
CONFIG_SLUG="${1:-}"
if [ -z "$CONFIG_SLUG" ]; then
  if [ -f .claude/super-board/active ]; then
    CONFIG_SLUG=$(cat .claude/super-board/active)
  else
    echo "usage: $0 <config-slug>  (or set .claude/super-board/active)" >&2
    exit 64
  fi
fi

CONFIG_PATH=".claude/super-board/configs/${CONFIG_SLUG}.json"
if [ ! -f "$CONFIG_PATH" ]; then
  echo "config not found: $CONFIG_PATH" >&2
  exit 66
fi

# Stop marker bền: ghi TRƯỚC mọi bước khác, kể cả khi không còn gì để dừng (runner đã chết vẫn phải được ghi là người
# dùng dừng). super-board-watchdog.sh không bao giờ khởi động lại board có marker; runner thấy marker thì tự thoát ở
# tick kế tiếp. Chỉ một lần khởi động tường minh (`super-board run <slug>`) mới xoá nó.
STOP_MARK=".claude/super-board/runner/${CONFIG_SLUG}.stopped"
MARK_WARN=""
write_stop_mark() {
  # PID: runner đang khởi động cùng giây biết stop này còn chạy (trùng lúc) hay đã xong (`stop && run` tuần tự).
  { mkdir -p "${STOP_MARK%/*}" && printf 'STOPPED_AT=%s\nBY=%s\nPID=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      "${USER:-unknown} via super-board-stop.sh" "$$" > "$STOP_MARK"; } 2>/dev/null
}
# Ghi marker hỏng (đĩa đầy, thư mục không ghi được) không được làm stop bỏ dở việc dừng worker: báo rồi đi tiếp.
if ! write_stop_mark; then
  MARK_WARN="⚠ could not write the stop marker $STOP_MARK (disk full? unwritable?): the watchdog may restart this board"
  echo "$MARK_WARN" >&2
fi

# ───────────────────────────── config read ─────────────────────────────
BOT_LOGIN=$(jq -r '.notifications.bot_identity // .bot_identity // ""' "$CONFIG_PATH")
INFLIGHT_DIR=".claude/super-board/inflight"
RUN_DATE=$(date +%Y-%m-%d)
RUN_MANIFEST="docs/super-board/runs/${RUN_DATE}-${CONFIG_SLUG}.md"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Dùng lại bộ lọc worker theo repo của runner (startup_orphan_workers). Source TRƯỚC các helper bên dưới để
# log/read_lock/kill_pid của stop đè bản của runner; INFLIGHT_DIR đã đặt nên `:=` của runner giữ nguyên.
[ ! -f "$SCRIPT_DIR/super-board-run.sh" ] || SB_LIB_ONLY=1 . "$SCRIPT_DIR/super-board-run.sh"

# ───────────────────────────── helpers ─────────────────────────────
log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
  [ -f "$RUN_MANIFEST" ] && printf '[%s] STOP %s\n' "$(date +%H:%M:%S)" "$*" >> "$RUN_MANIFEST" || true
}

# Source a lock file. Supports both v1.3.0+ (PID=/LANE=/STARTED= assignments)
# and pre-v1.3.0 (single-line PID) formats.
read_lock() {
  local lock="$INFLIGHT_DIR/$1"
  PID=""; LANE=""; STARTED=""
  [ -f "$lock" ] || return 1
  if grep -q '^PID=' "$lock" 2>/dev/null; then
    # shellcheck disable=SC1090
    . "$lock" 2>/dev/null || true
  else
    PID=$(cat "$lock" 2>/dev/null || echo "")
  fi
  return 0
}

# Look up the PR number for an issue's branch (if any). One gh call.
pr_for_issue() {
  local issue="$1"
  gh pr list --state open --json number,headRefName \
    --jq ".[] | select(.headRefName | startswith(\"issue-${issue}-\")) | .number" 2>/dev/null | head -1
}

# Latest commit on the issue's branch (local or remote). Best-effort.
last_commit_on_branch() {
  local issue="$1" branch
  branch=$(git branch -a --list "*issue-${issue}-*" 2>/dev/null | head -1 | sed 's|^[* ]*||;s|^remotes/[^/]*/||')
  [ -z "$branch" ] && { echo "(no branch yet)"; return; }
  git log -1 --format='%h %s' "$branch" 2>/dev/null || echo "(branch found but no commits)"
}

post_stop_comment() {
  local issue="$1" lane="$2" pid="$3" pr commit body
  commit=$(last_commit_on_branch "$issue")
  pr=$(pr_for_issue "$issue" || echo "")

  # Comment format: writing-standard.md § 4.
  body="[orchestrator] [report] 🛑 stopped · ${lane:-unknown} lane
Did: \`super-board stop\` ended worker PID ${pid:-unknown} at ${TS}
✅ Done: resume point is the last pushed commit — ${commit}
❌ Not done: interrupted work may be uncommitted; inspect the preserved worktree
Next: preserve edits before \`super-board run ${CONFIG_SLUG}\`; dirty or legacy worktrees need inspection"

  gh issue comment "$issue" --body "$body" >/dev/null 2>&1 \
    && log "  💬 issue comment posted on #${issue}" \
    || log "  ⚠ failed to comment on issue #${issue} (continuing)"

  if [ -n "$pr" ]; then
    gh pr comment "$pr" --body "$body" >/dev/null 2>&1 \
      && log "  💬 PR comment posted on #${pr}" \
      || log "  ⚠ failed to comment on PR #${pr} (continuing)"
  fi
}

release_claim() {
  local issue="$1"
  [ -z "$BOT_LOGIN" ] && return 0
  gh issue edit "$issue" --remove-assignee "$BOT_LOGIN" >/dev/null 2>&1 || true
  for label in loop:in-build loop:in-qa loop:in-review; do
    gh issue edit "$issue" --remove-label "$label" >/dev/null 2>&1 || true
  done
  log "  🔓 released assignee + lane labels on #${issue}"
}

kill_pid() {
  local pid="$1" name="${2:-process}" grace="${3:-1}" waited=0
  if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
    log "  ⊘ ${name} pid=${pid:-empty} already dead"
    return 0
  fi
  kill -TERM "$pid" 2>/dev/null || true
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt "$grace" ]; do
    sleep 1
    waited=$((waited + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -KILL "$pid" 2>/dev/null || true
    log "  ☠ ${name} pid=${pid} SIGKILLed (didn't respond to SIGTERM)"
  else
    log "  ☠ ${name} pid=${pid} SIGTERMed"
  fi
}

own_dispatcher_pids() {
  # $1 = thư mục repo, $2 = slug. In PID runner `bash|sh <repo>/.claude/bin/super-board-run.sh <slug>` của CHÍNH
  # repo và slug này. 17/10 07:54 `pgrep -f 'super-board-run\.sh'` khớp runner (và shell nohup bọc ngoài) của cả 5
  # board nên stop một board tắt cả 5. Đường dẫn script so nguyên token (repo `X-2` không khớp `X`); argv[0] phải là
  # bash/sh và script là tham số đầu tiên không phải cờ (shell `sh -c "cd … && nohup …"` bọc ngoài và shell chẩn
  # đoán có token đầu là cd/grep nên bị loại). Đường dẫn tương đối thì xác minh cwd bằng lsof; không đọc được cwd
  # thì không dừng (báo ra stderr).
  local root="$1" slug="$2" phys pid exe rest script arg i cwd
  local -a toks
  phys=$(cd "$root" && pwd -P)
  while read -r pid exe rest; do
    [ -n "$pid" ] && [ "$pid" != "$$" ] && [ -n "$rest" ] || continue
    case "${exe##*/}" in bash|sh) ;; *) continue ;; esac
    read -r -a toks <<< "$rest"
    i=0; script=""
    while [ "$i" -lt "${#toks[@]}" ]; do
      case "${toks[$i]}" in -*) i=$((i + 1)) ;; *) script="${toks[$i]}"; break ;; esac
    done
    [ -n "$script" ] || continue
    script=${script#[\'\"]}; script=${script%[\'\"]}
    [ "${script##*/}" = "super-board-run.sh" ] || continue
    arg="${toks[$((i + 1))]:-}"
    if [ -z "$arg" ]; then
      [ "$(cat .claude/super-board/active 2>/dev/null)" = "$slug" ] || continue   # runner không đối số đọc `active`
    elif [ "$arg" != "$slug" ]; then
      continue
    fi
    case "$script" in
      /*) [ "$script" = "$root/.claude/bin/super-board-run.sh" ] || [ "$script" = "$phys/.claude/bin/super-board-run.sh" ] || continue ;;
      *)
        cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1 || true)
        if [ -z "$cwd" ]; then
          log "  ⚠ runner pid=${pid} chạy bằng đường dẫn tương đối, không đọc được cwd: không dừng (kiểm tra: ps -ww -o command= -p ${pid})" >&2
          continue
        fi
        cwd="${cwd%/}/${script#./}"
        [ "$cwd" = "$root/.claude/bin/super-board-run.sh" ] || [ "$cwd" = "$phys/.claude/bin/super-board-run.sh" ] || continue ;;
    esac
    echo "$pid"
  done < <(ps -ww -A -o pid= -o command= 2>/dev/null || true)
}

# ───────────────────────────── main ─────────────────────────────
echo "════════════════════════════════════════════════════════"
echo "  super-board stop · ${CONFIG_SLUG}"
echo "════════════════════════════════════════════════════════"

# 1. Inventory in-flight workers BEFORE killing anything.
WORKERS=()
if [ -d "$INFLIGHT_DIR" ]; then
  for lock in "$INFLIGHT_DIR"/*; do
    [ -f "$lock" ] || continue
    issue=$(basename "$lock")
    # Wave/merge control markers are not GitHub issue numbers.
    case "$issue" in ''|*[!0-9]*) continue ;; esac
    read_lock "$issue"
    WORKERS+=("${issue}|${LANE:-unknown}|${PID:-}")
  done
fi

# Chỉ runner và worker của repo này (worker có lock đã nằm trong WORKERS ở trên).
DISPATCHER_PIDS=$(own_dispatcher_pids "$PWD" "$CONFIG_SLUG" | tr '\n' ' ')
DISPATCHER_PIDS=${DISPATCHER_PIDS% }
ORPHAN_WORKERS=""
if declare -F startup_orphan_workers >/dev/null; then
  ORPHAN_WORKERS=$(startup_orphan_workers "$PWD" | tr '\n' ' ')
  ORPHAN_WORKERS=${ORPHAN_WORKERS% }
else
  log "⚠ super-board-run.sh thiếu startup_orphan_workers: không quét worker mồ côi (cài runner cùng bản với stop)"
fi
CODEX_WAVE_MARKER=".claude/super-board/codex-wave.pid"
CODEX_WAVE_PID=""
if [ -f "$CODEX_WAVE_MARKER" ]; then
  CODEX_WAVE_PID=$(cat "$CODEX_WAVE_MARKER")
  case "$CODEX_WAVE_PID" in ''|*[!0-9]*)
    log "🛑 invalid Codex wave PID marker; preserve claims and inspect $CODEX_WAVE_MARKER"
    exit 1 ;;
  esac
  if kill -0 "$CODEX_WAVE_PID" 2>/dev/null; then
    # Refuse a reused PID, or an unavailable process identity, rather than
    # signal an unrelated process and release a still-running wave's claims.
    if ! ps -p "$CODEX_WAVE_PID" -o args= 2>/dev/null | grep -q 'super-board-codex-wave'; then
      log "🛑 cannot identify Codex wave PID $CODEX_WAVE_PID; preserve claims and inspect $CODEX_WAVE_MARKER"
      exit 1
    fi
  fi
fi

if [ "${#WORKERS[@]}" -eq 0 ] && [ -z "$DISPATCHER_PIDS" ] && [ -z "$ORPHAN_WORKERS" ] && [ -z "$CODEX_WAVE_PID" ]; then
  echo "  ✓ nothing to stop — no dispatcher, no in-flight workers, no orphans"
  echo "  ${MARK_WARN:-🛑 stop marker: $STOP_MARK — the watchdog will not restart this board}"
  echo "════════════════════════════════════════════════════════"
  exit 0
fi

# Stop new Codex dispatch first. Its TERM handler cancels lane process groups
# and reaps them (up to five seconds), before any claim can be released.
if [ -n "$CODEX_WAVE_PID" ]; then
  log "🛑 stopping Codex wave and its lane workers"
  kill_pid "$CODEX_WAVE_PID" "codex-wave" 7
fi

# 2. Per-worker wrap-up: comment, release claim, kill.
if [ "${#WORKERS[@]}" -gt 0 ]; then
  log "📋 ${#WORKERS[@]} in-flight worker(s) to wrap up"
  for entry in "${WORKERS[@]}"; do
    IFS='|' read -r issue lane pid <<< "$entry"
    log ""
    log "─── #${issue} (lane=${lane}, pid=${pid:-unknown}) ───"
    post_stop_comment "$issue" "$lane" "$pid"
    release_claim "$issue"
    kill_pid "$pid" "worker(${lane}/#${issue})"
  done
fi

# 3. Sweep any untracked claude -p super-board workers.
if [ -n "$ORPHAN_WORKERS" ]; then
  log ""
  log "🧹 sweeping untracked claude -p super-board workers"
  for pid in $ORPHAN_WORKERS; do
    kill_pid "$pid" "orphan-worker"
  done
fi

# 4. Kill the dispatcher loop.
if [ -n "$DISPATCHER_PIDS" ]; then
  log ""
  log "🛑 stopping dispatcher loop"
  for pid in $DISPATCHER_PIDS; do
    kill_pid "$pid" "dispatcher"
  done
fi
# Ghi lại marker sau khi đã dừng dispatcher: mtime mới hơn lúc ra đời của bất kỳ runner nào đang khởi động song song,
# nên runner đó tôn trọng marker thay vì coi là cũ và xoá. Lần ghi đầu hỏng đã được báo ở trên.
write_stop_mark || true

# 5. Clear in-flight locks (PIDs are dead now).
if [ -d "$INFLIGHT_DIR" ] && [ -n "$(ls -A "$INFLIGHT_DIR" 2>/dev/null)" ]; then
  for entry in "${WORKERS[@]}"; do
    IFS='|' read -r issue lane pid <<< "$entry"
    rm -f "$INFLIGHT_DIR/$issue"
  done
  log ""
  log "🧽 cleared $INFLIGHT_DIR"
fi
[ -z "$CODEX_WAVE_PID" ] || rm -f "$INFLIGHT_DIR/workflow-wave.lock" "$CODEX_WAVE_MARKER"

# 6. Summary.
DISP_COUNT=$(echo "$DISPATCHER_PIDS" | tr ' ' '\n' | grep -c . || true)
[ -z "$CODEX_WAVE_PID" ] || DISP_COUNT=$((DISP_COUNT + 1))
echo ""
echo "════════════════════════════════════════════════════════"
echo "  ✅ stopped: ${#WORKERS[@]} worker(s), ${DISP_COUNT} dispatcher(s)"
echo "  📝 wrap-up comments posted on each in-flight issue + PR"
echo "  ${MARK_WARN:-🛑 stop marker: $STOP_MARK — the watchdog will not restart this board}"
echo "  ▶  Resume: super-board run ${CONFIG_SLUG}  (clears the marker)"
echo "════════════════════════════════════════════════════════"
