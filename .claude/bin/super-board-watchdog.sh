#!/usr/bin/env bash
# super-board-watchdog.sh — watchdog của runner claude-p (super-board-run.sh): một launchd agent cho mỗi repo (macOS).
#
# 17/10 12:17 → 19/10: một `sleep` bị kill làm chết runner của cả 5 board và không gì phát hiện suốt 2 ngày.
# launchd chạy `check <slug>` mỗi 60 s (StartInterval); runner không phải job của launchd, việc khởi động lại do
# check quyết định. check chỉ khởi động lại runner đã chết khi đủ cả:
#   1. không có stop marker .claude/super-board/runner/<slug>.stopped (super-board-stop.sh ghi; chỉ một lần
#      `super-board run` tường minh mới xoá);
#   2. bản ghi của chính runner (<slug>.state) nói board đang chạy: STATE=running (bị SIGKILL, không kịp ghi) hoặc
#      crashed (thoát ngoài ý muốn). Không có bản ghi (board dừng trước khi có watchdog) = không làm gì; finished,
#      halted (mã 9/10/73/74/75/79) hoặc stopped = runner tự dừng có chủ đích, không khởi động lại;
#   3. PID trong bản ghi không còn là một super-board-run.sh đang chạy;
#   4. PATH có đủ công cụ runner cần để đọc board và giao việc (gh, jq, python3, claude, git);
#   5. GitHub không bị halt (github-halt.json: đối chiếu rồi khởi động tay);
#   6. backoff cho phép: lần thứ n chờ 60·2^(n-1) s sau lần trước; 5 lần liên tiếp thì bỏ cuộc tới khi người dùng
#      khởi động tường minh hoặc runner sống được 10 phút.
# Watchdog không bao giờ kill gì (không pkill theo tên) và không bao giờ xoá marker. Mỗi lần khởi động lại và mỗi lần
# kết luận đổi được ghi vào .claude/super-board/runner/<slug>.watchdog.log.
#
# Usage:
#   super-board-watchdog.sh check <slug>      một lượt kiểm (lệnh launchd chạy)
#   super-board-watchdog.sh status <slug>     launchd, runner, marker, halt, backoff, 5 dòng log cuối
#   super-board-watchdog.sh install <slug>    ghi + nạp ~/Library/LaunchAgents/com.superboard.watchdog.<slug>.plist
#   super-board-watchdog.sh ensure <slug>     install khi chưa có hoặc đã đổi (runner gọi khi khởi động tường minh)
#   super-board-watchdog.sh uninstall <slug>
# Env: SB_LAUNCH_AGENTS_DIR (thư mục plist, cho test), SB_WATCHDOG_AUTOINSTALL=0 (ensure không làm gì).
# Exit: 0 xong · 1 cài launchd lỗi · 64 sai cách gọi.
set -euo pipefail

CMD="${1:-}"; SLUG="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"
case "$CMD" in check|status|install|ensure|uninstall) ;; *) sed -n '2,29p' "$0" >&2; exit 64 ;; esac
case "$SLUG" in ''|*[!A-Za-z0-9._-]*) echo "usage: $0 $CMD <config-slug>" >&2; exit 64 ;; esac

DIR=".claude/super-board/runner"
STATE="$DIR/$SLUG.state"; MARK="$DIR/$SLUG.stopped"; WD="$DIR/$SLUG.watchdog"; WLOG="$DIR/$SLUG.watchdog.log"
LABEL="com.superboard.watchdog.$SLUG"
AGENTS="${SB_LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
PLIST="$AGENTS/$LABEL.plist"
INTERVAL=60; MAX_RESTARTS=5; BACKOFF_BASE=60; HEALTHY_SECONDS=600
RUNNER_TOOLS="gh jq python3 claude git"
NOW=$(date +%s)

field() { sed -n "s/^$1=//p" "$2" 2>/dev/null | head -1 || true; }
wlog() { mkdir -p "$DIR"; printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$WLOG"; }
wd_save() { mkdir -p "$DIR"; printf 'RESTARTS=%s\nLAST_RESTART=%s\nVERDICT=%s\n' "$RESTARTS" "$LAST_RESTART" "$VERDICT" > "$WD.$$" && mv -f "$WD.$$" "$WD"; }

RESTARTS=$(field RESTARTS "$WD"); RESTARTS=${RESTARTS:-0}
LAST_RESTART=$(field LAST_RESTART "$WD"); LAST_RESTART=${LAST_RESTART:-0}
VERDICT=$(field VERDICT "$WD")
case "$RESTARTS:$LAST_RESTART" in *[!0-9:]*) RESTARTS=$MAX_RESTARTS; LAST_RESTART=0 ;; esac   # hỏng: coi như đã bỏ cuộc

verdict() {   # $1 = khoá kết luận, $2 = thông điệp. Chỉ ghi log khi kết luận đổi (check chạy mỗi 60 s).
  [ "$VERDICT" = "$1" ] && return 0
  wlog "$2"; VERDICT="$1"; wd_save
}

runner_alive() {   # 0 khi $1 là PID của runner board này còn sống (PID tái dùng, vd. sau reboot, không tính)
  { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; } || return 1
  # Runner không đối số (đọc .claude/super-board/active) cũng tính.
  case "$(ps -ww -o command= -p "$1" 2>/dev/null || true)" in *"super-board-run.sh $SLUG"|*super-board-run.sh) return 0 ;; esac
  return 1
}

restart_runner() {   # $1 = PID cũ, $2 = STATE cũ, $3 = RC cũ
  local log daemon new
  log=$(field LOG "$STATE"); [ -n "$log" ] || log="docs/super-board/runner.log"
  daemon=$(field DAEMON "$STATE"); [ "$daemon" = 1 ] || daemon=0
  mkdir -p "$(dirname "$log")"
  [ ! -e "$MARK" ] || return 0   # stop vừa chạy giữa lúc kiểm và lúc khởi động
  # Đường dẫn tuyệt đối + bash: đúng dạng super-board-stop.sh nhận ra là runner của repo này. Runner tự từ chối nếu
  # marker xuất hiện trước khi nó chạy tới bước kiểm (SB_WATCHDOG_START=1 không bao giờ xoá marker).
  new=$( (env -u POSTFIX_GATE_FORCE_FULL -u DEVKIT_ALLOW_BRANCH SB_DAEMON="$daemon" SB_WATCHDOG_START=1 \
            nohup /bin/bash "$ROOT/.claude/bin/super-board-run.sh" "$SLUG" >> "$log" 2>&1 < /dev/null & echo $!) )
  RESTARTS=$((RESTARTS + 1)); LAST_RESTART=$NOW; VERDICT=restarted
  wd_save
  wlog "♻ restarted the runner (attempt $RESTARTS/$MAX_RESTARTS): new pid $new; previous pid ${1:-?} STATE=${2:-?} rc=${3:-?}; log $log"
}

check() {
  if [ -e "$MARK" ]; then
    verdict stopped "board stopped by the user ($(tr '\n' ' ' < "$MARK")) — never restarted until an explicit super-board run"
    return 0
  fi
  [ -f "$STATE" ] || return 0   # chưa runner nào ghi bản ghi: không có gì để giám sát
  local pid state rc started t missing="" wait
  pid=$(field PID "$STATE"); state=$(field STATE "$STATE"); rc=$(field RC "$STATE"); started=$(field STARTED "$STATE")
  if runner_alive "$pid"; then
    case "$started" in ''|*[!0-9]*) started=$NOW ;; esac
    if [ "$RESTARTS" -gt 0 ] && [ $((NOW - started)) -ge "$HEALTHY_SECONDS" ]; then
      RESTARTS=0
      wlog "runner pid $pid up for $(( (NOW - started) / 60 )) min — restart budget reset"
      wd_save
    fi
    verdict running "runner pid $pid is running"
    return 0
  fi
  case "$state" in
    running|crashed) ;;
    *) verdict "ended-$state" "runner ended on purpose (STATE=${state:-?} rc=${rc:-?}) — not restarted"; return 0 ;;
  esac
  for t in $RUNNER_TOOLS; do command -v "$t" >/dev/null 2>&1 || missing="$missing $t"; done
  if [ -n "$missing" ]; then
    verdict missing-tools "runner pid $pid is dead but PATH lacks:$missing (PATH=$PATH) — not restarted; reinstall: $0 install $SLUG"
    return 0
  fi
  if ! python3 "$SCRIPT_DIR/super-board-github-read.py" --check >/dev/null 2>&1; then
    verdict github-halt "runner pid $pid is dead and GitHub reads are halted (github-halt.json) — reconcile, then start the board explicitly"
    return 0
  fi
  if [ "$RESTARTS" -ge "$MAX_RESTARTS" ]; then
    verdict gave-up "runner died $RESTARTS times in a row — gave up (crash loop): read its log, then start the board explicitly"
    return 0
  fi
  if [ "$RESTARTS" -gt 0 ]; then
    wait=$(( BACKOFF_BASE << (RESTARTS - 1) ))
    if [ $((NOW - LAST_RESTART)) -lt "$wait" ]; then
      verdict "backoff-$RESTARTS" "runner pid $pid dead again (STATE=$state rc=${rc:-?}) — backoff: next restart ${wait}s after the last one"
      return 0
    fi
  fi
  restart_runner "$pid" "$state" "$rc"
}

status() {
  local pid state rc started
  echo "super-board watchdog · $SLUG · $ROOT"
  if command -v launchctl >/dev/null 2>&1 && launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
    echo "launchd: loaded ($LABEL, check every ${INTERVAL}s)"
  elif [ -f "$PLIST" ]; then
    echo "launchd: $PLIST exists but is NOT loaded — run: $0 install $SLUG"
  else
    echo "launchd: not installed — run: $0 install $SLUG (an explicit super-board run installs it)"
  fi
  if [ -f "$STATE" ]; then
    pid=$(field PID "$STATE"); state=$(field STATE "$STATE"); rc=$(field RC "$STATE"); started=$(field STARTED "$STATE")
    if runner_alive "$pid"; then
      echo "runner: pid $pid running since $(date -r "$started" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$started")"
    else
      echo "runner: not running — last pid ${pid:-?} STATE=${state:-?} rc=${rc:-?}"
    fi
  else
    echo "runner: no record (not started since the watchdog exists)"
  fi
  if [ -e "$MARK" ]; then echo "stop marker: set — $(tr '\n' ' ' < "$MARK")"; else echo "stop marker: none"; fi
  if python3 "$SCRIPT_DIR/super-board-github-read.py" --check >/dev/null 2>&1; then echo "github halt: none"
  else echo "github halt: HALTED (github-halt.json)"; fi
  echo "restarts in a row: $RESTARTS/$MAX_RESTARTS; verdict: ${VERDICT:-none}"
  if [ -f "$WLOG" ]; then echo "last log lines ($WLOG):"; tail -5 "$WLOG" | sed 's/^/  /'; fi
}

launchd_path() {
  # PATH mặc định của launchd chỉ có /usr/bin:/bin:/usr/sbin:/sbin (thiếu gh, claude, python3 của Homebrew). Danh sách
  # cố định, không lấy theo PATH của người gọi: hai lần khởi động từ hai shell khác nhau phải sinh cùng một plist,
  # nếu không `ensure` gỡ rồi nạp lại agent mỗi lần.
  printf '%s' "$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
}

xml() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

plist_text() {
  # AbandonProcessGroup: không có nó launchd giết cả nhóm tiến trình khi `check` thoát, kể cả runner vừa khởi động.
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$(xml "$LABEL")</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$(xml "$SCRIPT_DIR/super-board-watchdog.sh")</string>
    <string>check</string>
    <string>$(xml "$SLUG")</string>
  </array>
  <key>WorkingDirectory</key><string>$(xml "$ROOT")</string>
  <key>StartInterval</key><integer>$INTERVAL</integer>
  <key>RunAtLoad</key><true/>
  <key>AbandonProcessGroup</key><true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>$(xml "$(launchd_path)")</string>
    <key>LANG</key><string>en_US.UTF-8</string>
  </dict>
  <key>StandardOutPath</key><string>$(xml "$ROOT/$DIR/$SLUG.watchdog.launchd.log")</string>
  <key>StandardErrorPath</key><string>$(xml "$ROOT/$DIR/$SLUG.watchdog.launchd.log")</string>
</dict>
</plist>
EOF
}

install_agent() {   # $1 = "quiet": không làm gì khi đúng bản này đã được nạp (ensure)
  local uid tmp t i missing=""
  if ! command -v launchctl >/dev/null 2>&1; then echo "launchctl not found (not macOS): watchdog not installed"; return 0; fi
  uid=$(id -u)
  mkdir -p "$AGENTS" "$DIR"
  tmp="$PLIST.tmp.$$"
  plist_text > "$tmp"
  if ! plutil -lint "$tmp" >/dev/null 2>&1; then rm -f "$tmp"; echo "generated plist failed plutil -lint: not installed" >&2; return 1; fi
  if [ "${1:-}" = quiet ] && cmp -s "$tmp" "$PLIST" && launchctl print "gui/$uid/$LABEL" >/dev/null 2>&1; then
    rm -f "$tmp"; return 0
  fi
  mv -f "$tmp" "$PLIST"
  if launchctl print "gui/$uid/$LABEL" >/dev/null 2>&1; then
    launchctl bootout "gui/$uid/$LABEL" >/dev/null 2>&1 || echo "launchctl bootout gui/$uid/$LABEL failed" >&2
    # bootout trả về trước khi launchd gỡ xong job; bootstrap ngay sau đó hay lỗi "5: Input/output error".
    i=0
    while launchctl print "gui/$uid/$LABEL" >/dev/null 2>&1 && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  fi
  i=0
  until launchctl bootstrap "gui/$uid" "$PLIST"; do
    i=$((i + 1))
    if [ "$i" -ge 3 ]; then echo "launchctl bootstrap gui/$uid $PLIST failed 3 times: watchdog NOT loaded" >&2; return 1; fi
    sleep 1
  done
  for t in $RUNNER_TOOLS; do PATH="$(launchd_path)" command -v "$t" >/dev/null 2>&1 || missing="$missing $t"; done
  [ -z "$missing" ] || echo "warning: the watchdog's PATH ($(launchd_path)) lacks:$missing — it will not restart the runner" >&2
  echo "installed $LABEL: checks board $SLUG every ${INTERVAL}s ($PLIST)"
}

ensure_agent() {
  [ "${SB_WATCHDOG_AUTOINSTALL:-1}" != 0 ] || return 0
  command -v launchctl >/dev/null 2>&1 || return 0
  if [ -z "${SB_LAUNCH_AGENTS_DIR:-}" ]; then
    # Không cài launchd agent thật trỏ vào một thư mục tạm (test, bản sao scratch) hay một worktree: nhãn theo slug
    # sẽ đè watchdog của checkout chính.
    case "$ROOT/" in /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) return 0 ;; esac
    local gd gc
    gd=$(git -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null || true)
    gc=$(cd "$ROOT" && cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .)" && pwd -P)
    if [ -n "$gd" ] && [ "$(cd "$gd" && pwd -P)" != "$gc" ]; then return 0; fi
  fi
  install_agent quiet
}

uninstall_agent() {
  if command -v launchctl >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || echo "$LABEL was not loaded"
  fi
  rm -f "$PLIST"
  echo "uninstalled $LABEL"
}

case "$CMD" in
  check) check ;;
  status) status ;;
  install) install_agent ;;
  ensure) ensure_agent ;;
  uninstall) uninstall_agent ;;
esac
