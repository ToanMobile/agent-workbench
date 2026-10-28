#!/usr/bin/env bash
# super-board-queue-schedule.sh — lịch rút hàng đợi merge cho backend workflow (Q-schedule, #453): một launchd agent mỗi repo (macOS)
# chạy `super-board-merge-queue.sh --config <cfg> --if-due` mỗi 60 s, độc lập với mọi runner. Backend claude-p đã có runner gọi nó mỗi
# tick nên không cần lịch; workflow không có tiến trình sống giữa các wave, nên PR đã vào hàng (nhãn merge-queue) cần lịch này để được gom.
# Bộ gom tự thoát 0 khi chưa tới hạn / tắt / khoá bận (flock), nên chạy chồng với runner hay lượt trước là an toàn.
#
# Usage: super-board-queue-schedule.sh <install|ensure|uninstall|status> <config-slug>
#   ensure     install khi chưa có hoặc plist đã đổi (super-board-wave-plan.sh gọi mỗi wave; yên lặng nếu không có gì đổi)
# Env: SB_LAUNCH_AGENTS_DIR (thư mục plist, cho test), SB_QUEUE_SCHEDULE_AUTOINSTALL=0 (ensure không làm gì).
# Exit: 0 xong · 1 cài launchd lỗi · 64 sai cách gọi.
# ponytail: chỉ macOS (launchd); máy khác ensure in một dòng rồi thoát 0 và hàng chỉ được rút khi ai đó chạy --if-due. Nâng lên khi có
#   host Linux chạy board: systemd timer / cron cùng ProgramArguments.
set -euo pipefail

CMD="${1:-}"; SLUG="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
case "$CMD" in install|ensure|uninstall|status) ;; *) sed -n '2,11p' "$0" >&2; exit 64 ;; esac
case "$SLUG" in ''|*[!A-Za-z0-9._-]*) echo "usage: $0 $CMD <config-slug>" >&2; exit 64 ;; esac

CONFIG="$ROOT/.claude/super-board/configs/$SLUG.json"
LABEL="com.superboard.mergequeue.$SLUG.$(printf '%s' "$ROOT" | shasum | cut -c1-8)"
AGENTS="${SB_LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
PLIST="$AGENTS/$LABEL.plist"
LOGFILE="$ROOT/.claude/super-board/runner/$SLUG.merge-queue.launchd.log"
INTERVAL=60

xml() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
plist_text() {
  # PATH cố định như watchdog: launchd chỉ có /usr/bin:/bin; gh, jq, python3 của Homebrew phải nằm trong đó.
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$(xml "$LABEL")</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$(xml "$SCRIPT_DIR/super-board-merge-queue.sh")</string>
    <string>--config</string>
    <string>$(xml "$CONFIG")</string>
    <string>--if-due</string>
  </array>
  <key>WorkingDirectory</key><string>$(xml "$ROOT")</string>
  <key>StartInterval</key><integer>$INTERVAL</integer>
  <key>ProcessType</key><string>Interactive</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>$(xml "$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")</string>
    <key>HOME</key><string>$(xml "$HOME")</string>
    <key>LANG</key><string>en_US.UTF-8</string>
  </dict>
  <key>StandardOutPath</key><string>$(xml "$LOGFILE")</string>
  <key>StandardErrorPath</key><string>$(xml "$LOGFILE")</string>
</dict>
</plist>
EOF
}

root_installable() {   # như watchdog: không cài agent thật trỏ vào thư mục tạm hay worktree (nhãn theo slug sẽ đè agent của checkout chính)
  [ -z "${SB_LAUNCH_AGENTS_DIR:-}" ] || return 0
  case "$ROOT/" in
    /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) echo "refusing to install: $ROOT is a temporary directory"; return 1 ;;
  esac
  local gd gc
  gd=$(git -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null || true)
  gc=$(cd "$ROOT" && cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .)" && pwd -P)
  if [ -n "$gd" ] && [ "$(cd "$gd" && pwd -P)" != "$gc" ]; then
    echo "refusing to install: $ROOT is a linked worktree — install from the main checkout"; return 1
  fi
}

install_agent() {   # $1 = quiet: không làm gì khi đúng bản này đã nạp (ensure)
  local uid tmp i why
  if ! command -v launchctl >/dev/null 2>&1; then echo "launchctl not found (not macOS): merge-queue schedule not installed" >&2; return 1; fi
  if ! why=$(root_installable); then
    [ "${1:-}" = quiet ] && { echo "merge-queue schedule not installed: $why" >&2; return 1; }   # no agent = no drainer: wave-plan must not hide queued cards
    echo "$why" >&2; return 1
  fi
  [ -e "$CONFIG" ] || { echo "config not found: $CONFIG" >&2; return 1; }
  uid=$(id -u)
  mkdir -p "$AGENTS" "$(dirname "$LOGFILE")"
  tmp="$PLIST.tmp.$$"
  plist_text > "$tmp"
  if [ "${1:-}" = quiet ] && cmp -s "$tmp" "$PLIST" && launchctl print "gui/$uid/$LABEL" >/dev/null 2>&1; then rm -f "$tmp"; return 0; fi
  mv -f "$tmp" "$PLIST"
  if launchctl print "gui/$uid/$LABEL" >/dev/null 2>&1; then
    launchctl bootout "gui/$uid/$LABEL" >/dev/null 2>&1 || echo "launchctl bootout gui/$uid/$LABEL failed" >&2
    i=0; while launchctl print "gui/$uid/$LABEL" >/dev/null 2>&1 && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  fi
  i=0
  until launchctl bootstrap "gui/$uid" "$PLIST"; do
    i=$((i + 1))
    if [ "$i" -ge 3 ]; then echo "launchctl bootstrap gui/$uid $PLIST failed 3 times: merge-queue schedule NOT loaded" >&2; return 1; fi
    sleep 1
  done
  echo "installed $LABEL: merge-queue --if-due every ${INTERVAL}s ($PLIST)"
}

case "$CMD" in
  install) install_agent ;;
  ensure)   # exit 0 only when an agent is (or just became) loaded; AUTOINSTALL=0 installs nothing and only reports whether one is loaded
    if [ "${SB_QUEUE_SCHEDULE_AUTOINSTALL:-1}" = 0 ]; then
      command -v launchctl >/dev/null 2>&1 && launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1
    else install_agent quiet; fi ;;
  uninstall)
    command -v launchctl >/dev/null 2>&1 && { launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || echo "$LABEL was not loaded"; }
    rm -f "$PLIST"; echo "uninstalled $LABEL" ;;
  status)
    if command -v launchctl >/dev/null 2>&1 && launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then echo "launchd: loaded ($LABEL, every ${INTERVAL}s)"
    elif [ -e "$PLIST" ]; then echo "launchd: $PLIST exists but is NOT loaded — run: $0 install $SLUG"
    else echo "launchd: not installed — run: $0 install $SLUG"; fi ;;
esac
