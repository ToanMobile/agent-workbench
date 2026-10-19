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
#   super-board-watchdog.sh install <slug>    ghi + nạp ~/Library/LaunchAgents/com.superboard.watchdog.<slug>.<sha1 repo 8>.plist
#   super-board-watchdog.sh ensure <slug>     install khi chưa có hoặc đã đổi (runner gọi khi khởi động tường minh)
#   super-board-watchdog.sh uninstall <slug>
# Env: SB_LAUNCH_AGENTS_DIR (thư mục plist, cho test), SB_WATCHDOG_AUTOINSTALL=0 (ensure không làm gì).
# Exit: 0 xong · 1 cài launchd lỗi · 64 sai cách gọi.
set -euo pipefail

CMD="${1:-}"; SLUG="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"
ROOT_P="$(pwd -P)"   # đường dẫn vật lý của repo: so với giá trị đọc từ bản ghi (safe_path, runner_log)
case "$CMD" in check|status|install|ensure|uninstall) ;; *) sed -n '2,29p' "$0" >&2; exit 64 ;; esac
case "$SLUG" in ''|*[!A-Za-z0-9._-]*) echo "usage: $0 $CMD <config-slug>" >&2; exit 64 ;; esac

DIR=".claude/super-board/runner"
STATE="$DIR/$SLUG.state"; MARK="$DIR/$SLUG.stopped"; WD="$DIR/$SLUG.watchdog"; WLOG="$DIR/$SLUG.watchdog.log"
# Nhãn theo slug + 8 ký tự sha1 của đường dẫn repo: hai checkout dùng cùng slug không đè watchdog của nhau.
LABEL="com.superboard.watchdog.$SLUG.$(printf '%s' "$ROOT" | shasum | cut -c1-8)"
AGENTS="${SB_LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
PLIST="$AGENTS/$LABEL.plist"
INTERVAL=60; MAX_RESTARTS=5; BACKOFF_BASE=60; HEALTHY_SECONDS=600
RUNNER_TOOLS="gh jq python3 claude git"
NOW=$(date +%s)

field() { sed -n "s/^$1=//p" "$2" 2>/dev/null | head -1 || true; }
# Ghi log/trạng thái hỏng (đĩa đầy) không được làm `check` chết im lặng dưới set -e: in ra stderr (file log launchd).
wlog() {
  { mkdir -p "$DIR" && printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$WLOG"; } 2>/dev/null \
    || echo "watchdog $SLUG: could not write $WLOG: $*" >&2
}
wd_save() {
  { mkdir -p "$DIR" && printf 'RESTARTS=%s\nLAST_RESTART=%s\nVERDICT=%s\nSPAWNED=%s\n' \
      "$RESTARTS" "$LAST_RESTART" "$VERDICT" "$SPAWNED" > "$WD.$$" && mv -f "$WD.$$" "$WD"; } 2>/dev/null \
    || { rm -f "$WD.$$" 2>/dev/null; echo "watchdog $SLUG: could not write $WD" >&2; }
}
load_wd() {   # SPAWNED = PID runner do watchdog khởi động gần nhất
  RESTARTS=$(field RESTARTS "$WD"); RESTARTS=${RESTARTS:-0}
  LAST_RESTART=$(field LAST_RESTART "$WD"); LAST_RESTART=${LAST_RESTART:-0}
  VERDICT=$(field VERDICT "$WD"); SPAWNED=$(field SPAWNED "$WD")
  case "$RESTARTS:$LAST_RESTART:$SPAWNED" in *[!0-9:]*) RESTARTS=$MAX_RESTARTS; LAST_RESTART=0; SPAWNED="" ;; esac   # hỏng: coi như đã bỏ cuộc
}
load_wd

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

# Đúng danh sách RUNNER_ENV_KEYS mà runner ghi. Không nhận khoá nào khác: bản ghi nằm trong working tree mà worker ghi
# được, một dòng ENV_BASH_ENV / ENV_DYLD_INSERT_LIBRARIES sẽ chạy code tuỳ ý trong runner launchd khởi động không người.
RUNNER_ENV_KEYS="PATH JAVA_HOME ANDROID_HOME ANDROID_SDK_ROOT SB_ACCOUNT_POOL SB_STATE_DIR CLAUDE_CONFIG_DIR DEVKIT_LANG"

canon_path() {
  # In đường dẫn vật lý của $1 (như realpath, bash 3.2, không readlink -f): phần cha đã tồn tại phân giải bằng
  # cd -P/pwd -P (symlink, ., .., //), phần đuôi chưa tồn tại ghép lại nguyên văn. Fail closed (trả 1): đường dẫn tương
  # đối, đuôi có . hoặc .., một mục của đuôi là symlink (symlink treo trỏ vào repo, worker tạo đích sau), cd lỗi.
  local p="$1" tail="" c base
  case "$p" in /*) ;; *) return 1 ;; esac
  while [ ! -d "$p" ]; do
    if [ -L "$p" ]; then return 1; fi
    c=${p##*/}
    case "$c" in .|..) return 1 ;; '') ;; *) tail="/$c$tail" ;; esac
    p=${p%/*}; [ -n "$p" ] || p=/
  done
  base=$(cd -P "$p" 2>/dev/null && pwd -P) || return 1
  [ "$base" != / ] || base=""
  printf '%s' "$base$tail"
}

safe_path() {
  # $1 = PATH lấy từ bản ghi. Bỏ mục tương đối và mục nằm trong repo (kể cả .claude/worktrees của worker): một thư mục
  # worker tạo đứng đầu PATH sẽ thay gh/claude/python3 của runner chạy không người giám sát. So trên đường dẫn vật lý của
  # cả hai phía: so tiền tố chuỗi để lọt $TMP/./repo, $TMP/x/../repo và bí danh symlink (/tmp ↔ /private/tmp). Trả mục
  # đã phân giải: symlink trong repo trỏ ra ngoài không bị worker đổi đích sau lượt kiểm.
  local out="" d rest="$1:"
  while [ -n "$rest" ]; do
    d=${rest%%:*}; rest=${rest#*:}
    d=$(canon_path "$d") || continue
    case "$d/" in "$ROOT_P"/*) continue ;; esac
    out="${out:+$out:}$d"
  done
  printf '%s' "$out"
}

runner_env() {
  # Môi trường runner trước đã ghi (toolchain, cấu hình pool/account): launchd chỉ có PATH tối thiểu, runner và worker
  # cần đúng môi trường như lần khởi động tường minh. Thiếu bản ghi (runner cũ) thì dùng môi trường của chính watchdog.
  local k v
  ENVV=()
  for k in $RUNNER_ENV_KEYS; do
    v=$(field "ENV_$k" "$STATE")
    case "$k" in
      DEVKIT_LANG) ;;
      PATH) v=$(safe_path "$v") ;;
      # Biến đường dẫn (JDK, SDK, thư mục cấu hình claude có hooks, script pool account): cùng luật với PATH.
      *) v=$(safe_path "$v"); case "$v" in *:*) v="" ;; esac ;;
    esac
    [ -z "$v" ] || ENVV+=("$k=$v")
  done
}

runner_log() {
  # LOG trong bản ghi chỉ được nhận khi là file trong thư mục log của board; còn lại dùng log mặc định. So trên đường dẫn
  # vật lý (canon_path): LOG là symlink (hay nằm sau thư mục symlink) trỏ ra ngoài repo thì bị từ chối.
  local l
  l=$(field LOG "$STATE")
  l=$(canon_path "$l") || l=""
  case "$l" in
    "$ROOT_P"/docs/super-board/*.log|"$ROOT_P"/.claude/super-board/*.log) ;;
    *) l="" ;;
  esac
  printf '%s' "${l:-docs/super-board/runner.log}"
}

restart_runner() {   # $1 = PID cũ, $2 = STATE cũ, $3 = RC cũ
  local log daemon new
  log=$(runner_log)
  daemon=$(field DAEMON "$STATE"); [ "$daemon" = 1 ] || daemon=0
  mkdir -p "$(dirname "$log")" 2>/dev/null || { wlog "cannot create the log folder of $log: runner not restarted"; return 0; }
  [ ! -e "$MARK" ] || return 0   # stop vừa chạy giữa lúc kiểm và lúc khởi động
  runner_env
  # Đường dẫn tuyệt đối + bash: đúng dạng super-board-stop.sh nhận ra là runner của repo này. Runner tự từ chối nếu
  # marker xuất hiện trước khi nó chạy tới bước kiểm (SB_WATCHDOG_START=1 không bao giờ xoá marker).
  new=$( (env -u POSTFIX_GATE_FORCE_FULL -u DEVKIT_ALLOW_BRANCH ${ENVV[@]+"${ENVV[@]}"} SB_DAEMON="$daemon" SB_WATCHDOG_START=1 \
            nohup /bin/bash "$ROOT/.claude/bin/super-board-run.sh" "$SLUG" >> "$log" 2>&1 < /dev/null & echo $!) )
  RESTARTS=$((RESTARTS + 1)); LAST_RESTART=$NOW; VERDICT=restarted; SPAWNED=$new
  wd_save
  wlog "♻ restarted the runner (attempt $RESTARTS/$MAX_RESTARTS): new pid $new; previous pid ${1:-?} STATE=${2:-?} rc=${3:-?}; log $log"
}

take_check_lock() {
  # Hai `check` cùng lúc (launchd + một lần chạy tay) đều thấy runner chết và cùng khởi động: chỉ một lượt kiểm chạy.
  # Khoá bỏ lại quá 120 s (check bị kill) được lấy lại.
  local lock="$DIR/$SLUG.check.lock" m
  mkdir -p "$DIR"
  if ! mkdir "$lock" 2>/dev/null; then
    m=$(stat -f %m "$lock" 2>/dev/null || echo "$NOW")
    [ $((NOW - m)) -ge 120 ] || return 1
    rmdir "$lock" 2>/dev/null || true
    mkdir "$lock" 2>/dev/null || return 1
  fi
  trap 'rmdir "'"$lock"'" 2>/dev/null || true' EXIT
}

check() {
  # Không có bản ghi lẫn marker: board chưa từng chạy với runner này, không có gì để giám sát (không tạo thư mục, khoá).
  [ -f "$STATE" ] || [ -e "$MARK" ] || return 0
  take_check_lock || return 0
  load_wd   # đọc sau khi giữ khoá: lượt kiểm vừa xong có thể đã khởi động runner
  if [ -e "$MARK" ]; then
    verdict stopped "board stopped by the user ($(tr '\n' ' ' < "$MARK")) — never restarted until an explicit super-board run"
    return 0
  fi
  [ -f "$STATE" ] || return 0
  local pid state rc started t missing="" wait env_path
  pid=$(field PID "$STATE"); state=$(field STATE "$STATE"); rc=$(field RC "$STATE"); started=$(field STARTED "$STATE")
  if runner_alive "$pid"; then
    case "$started" in ''|*[!0-9]*) started=$NOW ;; esac
    if [ "$RESTARTS" -gt 0 ] && [ $((NOW - started)) -ge "$HEALTHY_SECONDS" ]; then
      RESTARTS=0
      wlog "runner pid $pid up for $(( (NOW - started) / 60 )) min — restart budget reset"
      wd_save
    fi
    # Runner trong bản ghi đang sống: runner watchdog spawn trước đó đã ghi bản ghi hoặc bị thay. Giữ SPAWNED cũ thì lần
    # crash sau bị báo nhầm là spawn-died và board không bao giờ được khởi động lại.
    if [ -n "$SPAWNED" ]; then SPAWNED=""; wd_save; fi
    verdict running "runner pid $pid is running"
    return 0
  fi
  case "$state" in
    running|crashed) ;;
    *) verdict "ended-$state" "runner ended on purpose (STATE=${state:-?} rc=${rc:-?}) — not restarted"; return 0 ;;
  esac
  # Runner watchdog vừa khởi động đã chết trước khi ghi bản ghi của nó (lỗi config, verification-readiness, trước trap
  # EXIT): khởi động lại chỉ lặp lại lỗi đó.
  # Runner watchdog vừa spawn còn sống mà chưa ghi bản ghi: đang khởi động, không spawn thêm runner thứ hai.
  if [ -n "$SPAWNED" ] && [ "$pid" != "$SPAWNED" ] && runner_alive "$SPAWNED"; then
    verdict starting "runner pid $SPAWNED started by the watchdog is still starting (no record yet)"
    return 0
  fi
  if [ -n "$SPAWNED" ] && [ "$pid" != "$SPAWNED" ] && ! kill -0 "$SPAWNED" 2>/dev/null; then
    t=$(field LOG "$STATE")
    verdict spawn-died "runner pid $SPAWNED started by the watchdog exited before recording itself (config or readiness error, see ${t:-docs/super-board/runner.log}) — not restarted until an explicit super-board run"
    return 0
  fi
  env_path=$(safe_path "$(field ENV_PATH "$STATE")"); env_path=${env_path:-$PATH}
  for t in $RUNNER_TOOLS; do (PATH="$env_path"; command -v "$t" >/dev/null 2>&1) || missing="$missing $t"; done
  if [ -n "$missing" ]; then
    verdict missing-tools "runner pid $pid is dead but its PATH lacks:$missing (PATH=$env_path) — not restarted"
    return 0
  fi
  if ! (PATH="$env_path"; python3 "$SCRIPT_DIR/super-board-github-read.py" --check >/dev/null 2>&1); then
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
  # ProcessType Interactive: không đặt thì launchd áp "light resource limits" (man launchd.plist), runner do watchdog
  # khởi động lại và các bản build của worker sẽ chạy chậm hơn lần khởi động tay.
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
  <key>ProcessType</key><string>Interactive</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>$(xml "$(launchd_path)")</string>
    <key>HOME</key><string>$(xml "$HOME")</string>
    <key>LANG</key><string>en_US.UTF-8</string>
  </dict>
  <key>StandardOutPath</key><string>$(xml "$ROOT/$DIR/$SLUG.watchdog.launchd.log")</string>
  <key>StandardErrorPath</key><string>$(xml "$ROOT/$DIR/$SLUG.watchdog.launchd.log")</string>
</dict>
</plist>
EOF
}

root_installable() {
  # Không cài launchd agent thật trỏ vào một thư mục tạm (test, bản sao scratch) hay một worktree: nhãn theo slug sẽ đè
  # watchdog của checkout chính. SB_LAUNCH_AGENTS_DIR (test) bỏ qua kiểm này.
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

install_agent() {   # $1 = "quiet": không làm gì khi đúng bản này đã được nạp (ensure)
  local uid tmp t i missing="" why
  if ! command -v launchctl >/dev/null 2>&1; then echo "launchctl not found (not macOS): watchdog not installed"; return 0; fi
  if ! why=$(root_installable); then
    [ "${1:-}" = quiet ] && return 0
    echo "$why" >&2; return 1
  fi
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
  for t in $RUNNER_TOOLS; do (PATH="$(launchd_path)"; command -v "$t" >/dev/null 2>&1) || missing="$missing $t"; done
  [ -z "$missing" ] || echo "warning: the watchdog's PATH ($(launchd_path)) lacks:$missing — it will not restart the runner" >&2
  echo "installed $LABEL: checks board $SLUG every ${INTERVAL}s ($PLIST)"
}

ensure_agent() {
  [ "${SB_WATCHDOG_AUTOINSTALL:-1}" != 0 ] || return 0
  command -v launchctl >/dev/null 2>&1 || return 0
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
