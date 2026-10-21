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
#      halted (mã 9/10/73/74/75/79) hoặc stopped = runner tự dừng có chủ đích, không khởi động lại — trừ halt 79 có
#      github-halt.json lưu một lần ĐỌC: mỗi lượt thử `super-board-github-read.py --resume` (chỉ đọc), phát lại được
#      thì khởi động lại (lỗi mạng tạm, vd. máy ngủ dậy);
#   3. PID trong bản ghi không còn là một super-board-run.sh đang chạy;
#   4. PATH có đủ công cụ runner cần để đọc board và giao việc (gh, jq, python3, claude, git);
#   5. GitHub không bị halt (github-halt.json lưu một lần ghi chưa rõ kết quả: đối chiếu rồi khởi động tay);
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
case "$CMD" in check|status|install|ensure|uninstall) ;; *) sed -n '2,31p' "$0" >&2; exit 64 ;; esac
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
  base="$base$tail"
  printf '%s' "${base:-/}"   # gốc "/" in là "/": chuỗi rỗng trong PATH là thư mục hiện tại (= repo root khi khởi động lại runner)
}

raw_entry_ok() {
  # 0 khi $1 (tuyệt đối) viết sạch (không ., .., //) và không đi qua symlink NẰM TRONG repo: khi đó giữ nguyên văn
  # (JAVA_HOME=/opt/homebrew/opt/openjdk@17 không bị ghim vào Cellar/17.0.x, brew upgrade xoá thư mục cũ).
  local p="$1" cur="" rest c par
  case "$p" in */./*|*/../*|*//*|*/.|*/..) return 1 ;; esac
  rest=${p#/}
  while [ -n "$rest" ]; do
    c=${rest%%/*}
    case "$rest" in */*) rest=${rest#*/} ;; *) rest="" ;; esac
    [ -n "$c" ] || continue
    par=${cur:-/}; cur="$cur/$c"
    if [ -L "$cur" ]; then
      par=$(cd -P "$par" 2>/dev/null && pwd -P) || return 1
      case "$par/" in "$ROOT_P"/*) return 1 ;; esac
    fi
  done
  return 0
}

safe_path() {
  # $1 = PATH lấy từ bản ghi. Bỏ mục tương đối và mục nằm trong repo (kể cả .claude/worktrees của worker): một thư mục
  # worker tạo đứng đầu PATH sẽ thay gh/claude/python3 của runner chạy không người giám sát. So trên đường dẫn vật lý của
  # cả hai phía: so tiền tố chuỗi để lọt $TMP/./repo, $TMP/x/../repo và bí danh symlink (/tmp ↔ /private/tmp). Trả mục
  # đã phân giải khi nó đi qua symlink trong repo trỏ ra ngoài (worker không đổi đích được sau lượt kiểm); mục không đi
  # qua symlink trong repo giữ nguyên văn.
  local out="" d raw rest="$1:"
  while [ -n "$rest" ]; do
    raw=${rest%%:*}; rest=${rest#*:}
    d=$(canon_path "$raw") || continue
    [ -n "$d" ] || continue   # mục rỗng trong PATH = thư mục hiện tại (repo root khi khởi động lại runner)
    case "$d/" in "$ROOT_P"/*) continue ;; esac
    if raw_entry_ok "$raw"; then d=$raw; fi
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

file_mtime() {
  # mtime (epoch giây) của $1 trên cả GNU stat (Linux: -c %Y) lẫn BSD stat (macOS: -f %m); chỉ nhận số (GNU `stat -f` in chữ
  # filesystem mà vẫn thành công). Không đọc được thì trả 1. Cùng hàm với super-board-run.sh.
  local t
  for t in "$(stat -c %Y "$1" 2>/dev/null || true)" "$(stat -f %m "$1" 2>/dev/null || true)"; do
    case "$t" in ''|*[!0-9]*) ;; *) printf '%s\n' "$t"; return 0 ;; esac
  done
  return 1
}

take_check_lock() {
  # Hai `check` cùng lúc (launchd + một lần chạy tay) đều thấy runner chết và cùng khởi động: chỉ một lượt kiểm chạy.
  # Khoá bỏ lại quá 120 s (check bị kill) được lấy lại.
  local lock="$DIR/$SLUG.check.lock" m
  mkdir -p "$DIR"
  if ! mkdir "$lock" 2>/dev/null; then
    m=$(file_mtime "$lock") || m=$NOW
    [ $((NOW - m)) -ge 120 ] || return 1
    # Lấy lại tuần tự: một cổng mkdir cho mọi bên muốn lấy lại, rồi kiểm lại tuổi BÊN TRONG cổng. rmdir + mkdir trần để hai
    # check cùng thấy khoá cũ, check sau rmdir đúng khoá mới của check trước và cả hai cùng giữ khoá. Cổng bỏ lại quá 120 s
    # (check bị kill giữa chừng) bị gỡ, lượt check sau lấy lại khoá.
    if ! mkdir "$lock.reclaim" 2>/dev/null; then
      m=$(file_mtime "$lock.reclaim") || m=$NOW
      [ $((NOW - m)) -lt 120 ] || rmdir "$lock.reclaim" 2>/dev/null || true
      return 1
    fi
    m=$(file_mtime "$lock") || m=$NOW
    if [ $((NOW - m)) -ge 120 ]; then
      rmdir "$lock" 2>/dev/null || true
      mkdir "$lock" 2>/dev/null || { rmdir "$lock.reclaim" 2>/dev/null || true; return 1; }
    else
      rmdir "$lock.reclaim" 2>/dev/null || true
      return 1
    fi
    rmdir "$lock.reclaim" 2>/dev/null || true
  fi
  CHECK_LOCK="$lock"
  trap 'rmdir "'"$lock"'" 2>/dev/null || true' EXIT
}
release_check_lock() {
  # Publish lên GitHub chạy SAU khi nhả khoá check: nó có thể mất vài lần gh 20 s, không được đẩy lượt check quá 120 s
  # (khi đó lượt check sau lấy lại khoá và trap EXIT của lượt này xoá khoá của lượt kia).
  [ -n "${CHECK_LOCK:-}" ] || return 0
  rmdir "$CHECK_LOCK" 2>/dev/null || true
  CHECK_LOCK=""; trap - EXIT
}

# ── Trạng thái board trên GitHub ─────────────────────────────────────────────────────────────────────────────────
# 20/10 board halt 09:08 → 12:33 mà nhìn board trên GitHub không biết (người dùng: "thể hiện lên board 1 icon … để biết
# task đang chạy hay bị ngừng", "thêm thời gian để biết task chạy được bao lâu, bắt đầu từ khi nào"). Mỗi check ghi vào
# mô tả ngắn của Project: icon trạng thái, runner chạy từ lúc nào, worker đang sống kèm giờ bắt đầu + thời lượng, giờ cập
# nhật. Chỉ ghi khi trạng thái đổi hoặc nhịp BOARD_STATUS_HEARTBEAT giây: giờ cập nhật cũ hơn nhịp nhiều = máy ngủ hay
# watchdog chết (khi đó không gì ghi được). Không đổi tiêu đề Project (super-qa-file-bug.sh tìm Project theo tiêu đề).
# Lỗi gh/mạng không bao giờ làm check hỏng: lượt sau thử lại. SB_BOARD_STATUS=0 tắt. "cập nhật HH:MM dd/MM" là hợp đồng
# với cron .github/scripts/board_heartbeat.py (agent-workbench): board 🟢 có giờ đó cũ quá 20 phút bị đổi thành 🔴 mất tín
# hiệu. Người dùng 20/10: chỉ 🟢 = đang chạy, 🔴 = không chạy; lane viết bằng chữ (code/test/review), không dùng biểu tượng.
BOARD_STATUS="$DIR/$SLUG.board-status"; BOARD_STATUS_HEARTBEAT=300
BOARD_TZ="${SB_BOARD_TZ:-Asia/Ho_Chi_Minh}"   # giờ hiện trên GitHub luôn +07, máy có đổi múi giờ cũng vậy
CHECKED=0; CHECK_LOCK=""

hhmm() {   # $1 = epoch → "HH:MM" (hôm nay) hoặc "dd/MM HH:MM"
  if [ "$(TZ="$BOARD_TZ" date -r "$1" +%Y%m%d 2>/dev/null)" = "$(TZ="$BOARD_TZ" date +%Y%m%d)" ]; then
    TZ="$BOARD_TZ" date -r "$1" +%H:%M 2>/dev/null
  else TZ="$BOARD_TZ" date -r "$1" '+%d/%m %H:%M' 2>/dev/null; fi
}
span() {   # $1 = số giây → "45p" / "1g15p"
  local m=$(( $1 / 60 ))
  if [ "$m" -lt 60 ]; then printf '%sp' "$m"; else printf '%sg%02dp' $((m / 60)) $((m % 60)); fi
}
iso_epoch() {   # "2026-10-20T06:16:29Z" (UTC) → epoch; BSD date rồi GNU date
  date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || date -u -d "$1" +%s 2>/dev/null
}

board_status_text() {   # đặt BS_KEY (không chứa giờ: biết trạng thái có đổi không), BS_TEXT (mô tả), BS_CARDS ("<số>\t<chữ>" mỗi dòng)
  local f n pid lane st t word started detail="" ctext
  BS_CARDS=""
  case "$VERDICT" in
    running|restarted|starting)
      BS_KEY="🟢 đang chạy"
      # restarted/starting: bản ghi còn là của runner cũ đã chết, giờ của nó sai.
      started=""; [ "$VERDICT" != running ] || started=$(field STARTED "$STATE")
      case "$started" in ''|*[!0-9]*) ;; *) detail=" từ $(hhmm "$started")" ;; esac
      for f in .claude/super-board/inflight/*; do
        n=${f##*/}; case "$n" in ''|*[!0-9]*) continue ;; esac
        [ -f "$f" ] || continue
        pid=$(field PID "$f"); lane=$(field LANE "$f")
        { [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; } || continue
        case "$lane" in build) word=code ;; qa) word=test ;; review) word=review ;; *) word=${lane:-task} ;; esac
        BS_KEY="$BS_KEY #$n:$word"
        st=$(field STARTED "$f"); t=$(iso_epoch "$st") || t=""
        case "$t" in
          ''|*[!0-9]*) ctext="🟢 đang $word"; detail="$detail · #$n $word" ;;
          *) ctext="🟢 đang $word · từ $(hhmm "$t") · $(span $((NOW - t)))"
             detail="$detail · #$n $word từ $(hhmm "$t") ($(span $((NOW - t))))" ;;
        esac
        BS_CARDS="$BS_CARDS$n	$ctext
"
      done
      [ "$BS_KEY" != "🟢 đang chạy" ] || detail="$detail · không có task nào đang làm"
      BS_TEXT="🟢 đang chạy$detail"
      return 0 ;;
    stopped|ended-stopped) BS_KEY="🔴 đã dừng (bạn stop)" ;;
    halt-wait) BS_KEY="🔴 dừng: lỗi đọc GitHub — watchdog tự thử lại mỗi phút" ;;
    github-halt) BS_KEY="🔴 dừng: lỗi ghi GitHub — cần người đối chiếu (--resume --reconciled)" ;;
    backoff-*) BS_KEY="🔴 runner vừa chết — sắp tự khởi động lại" ;;
    ended-finished) BS_KEY="🔴 dừng: hết việc" ;;
    *) BS_KEY="🔴 runner ngừng (${VERDICT:-?}) — xem $SLUG.watchdog.log" ;;
  esac
  BS_TEXT="$BS_KEY"
}

run_capped() {   # run_capped <giây> <lệnh…>: hết giờ thì TERM rồi KILL cả nhóm tiến trình, exit 124
  # macOS không có `timeout`. `perl -e 'alarm N; exec gh'` KHÔNG cắt được gh: gh là binary Go, bỏ qua SIGALRM (đo 20/10:
  # alarm 2 mà gh vẫn chạy đủ 8 s), và con của python (--resume → gh) cũng sống tiếp. Fork, con lập nhóm riêng, hết giờ
  # giết cả nhóm.
  perl -MPOSIX -e '$t = shift; my $p = 0;
    # Chặn tín hiệu từ trước fork tới khi nhóm đã lập ở cả cha lẫn con: handler không bao giờ chạy khi $p chưa có hay
    # nhóm chưa tồn tại. stop giết cả nhóm lẫn chính PID con.
    sub stop { my ($rc) = @_; if ($p > 0) { kill "TERM", -$p, $p; sleep 1; kill "KILL", -$p, $p } exit $rc }
    $SIG{ALRM} = sub { stop(124) }; $SIG{TERM} = sub { stop(143) }; $SIG{INT} = sub { stop(130) }; $SIG{HUP} = sub { stop(129) };
    my $block = POSIX::SigSet->new(SIGTERM, SIGINT, SIGHUP, SIGALRM); my $old = POSIX::SigSet->new;
    sigprocmask(SIG_BLOCK, $block, $old);
    $p = fork; die "fork: $!" unless defined $p;
    if (!$p) { setpgrp(0, 0); sigprocmask(SIG_SETMASK, $old); exec @ARGV; exit 127 }
    setpgrp($p, 0); sigprocmask(SIG_SETMASK, $old);
    alarm $t; waitpid $p, 0; exit($? & 127 ? 128 + ($? & 127) : $? >> 8)' "$@"
}
GH_CAP="${SB_BOARD_GH_TIMEOUT:-20}"
gh20() { run_capped "$GH_CAP" gh "$@"; }   # gh treo (mạng nửa vời sau khi máy thức) không được giữ lượt check
# P1: card.sh (SB_GITHUB_READ_STRICT) ghi file halt DÙNG CHUNG khi đọc lỗi → runner và mọi worker dừng. Publish chỉ để hiển
# thị: cho nó file halt riêng, xoá sau mỗi lần publish.
card20() { SB_GITHUB_HALT_FILE="$ROOT/$DIR/$SLUG.publish-halt.json" run_capped "$GH_CAP" bash "$SCRIPT_DIR/super-board-card.sh" "$@"; }
# Ngân sách một lần publish: mỗi lệnh ≤ 20 s nhưng nhiều card cộng lại có thể quá hạn khoá publish (300 s) → hai lần publish
# chồng nhau. Hết 200 s thì dừng; card chưa xoá vẫn nằm trong CARDS, lượt sau làm tiếp.
budget_ok() { [ $(( $(date +%s) - NOW )) -lt "${BOARD_STATUS_BUDGET:-200}" ]; }

publish_card_fields() {
  # Field chữ "Đang chạy" trên từng card: lane + giờ bắt đầu + thời lượng khi worker còn sống, xoá khi worker dừng (card
  # ở Building/QA/Review mà trống field = không ai đang làm). Đặt CF_FIELD và CF_CARDS (card đang/có thể còn mang field,
  # để lượt sau xoá). $1 owner, $2 number, $3 config.
  local pid n text item fields live="" keep="" field_known
  FIELD_STALE=""
  CF_FIELD=$(field FIELD "$BOARD_STATUS"); CF_CARDS=$(field CARDS "$BOARD_STATUS"); field_known=$CF_FIELD
  pid=$(card20 --config "$3" ids 2>/dev/null | jq -r '.projectId // empty' 2>/dev/null) || pid=""
  [ -n "$pid" ] || return 0
  if [ -z "$CF_FIELD" ]; then
    # Đọc danh sách hỏng (mạng, quyền) KHÁC với field chưa có: chỉ tạo khi đọc được và thật sự thiếu, không thì lần mạng
    # chập chờn sau sẽ tạo field trùng tên.
    fields=$(gh20 project field-list "$2" --owner "$1" --limit 100 --format json 2>/dev/null) || return 0
    CF_FIELD=$(printf '%s' "$fields" | jq -r '[.fields[]? | select(.name == "Đang chạy") | .id][0] // empty' 2>/dev/null) || return 0
    [ -n "$CF_FIELD" ] || CF_FIELD=$(gh20 project field-create "$2" --owner "$1" --name "Đang chạy" --data-type TEXT \
      --format json 2>/dev/null | jq -r '.id // empty' 2>/dev/null) || CF_FIELD=""
    [ -n "$CF_FIELD" ] || return 0
  fi
  while IFS='	' read -r n text; do
    [ -n "$n" ] || continue
    live="$live $n"; keep="$keep $n"
    budget_ok || continue
    item=$(card20 --config "$3" item-id "$n" 2>/dev/null) || continue
    # Ghi hỏng (mạng, hay field đã bị xoá trên GitHub): lượt sau đọc lại id field.
    gh20 project item-edit --id "$item" --project-id "$pid" --field-id "$CF_FIELD" --text "$text" >/dev/null 2>&1 || FIELD_STALE=1
  done <<EOF
$BS_CARDS
EOF
  # Card ở Building/QA/Review mà không có worker sống: 🔴 không chạy (người dùng 20/10: nhìn card biết task có đang chạy
  # không). Chỉ ghi lần đầu thấy đỏ (REDS); card rời cột hoạt động thì vòng xoá bên dưới gỡ field.
  local items red="" prev_red orig_red
  orig_red=$(field REDS "$BOARD_STATUS"); prev_red=$orig_red; CF_REDS=""
  # Field vừa đọc lại id (tạo lại, hay ghi hỏng lượt trước): dấu đỏ cũ có thể không còn trên GitHub → ghi lại hết.
  [ -n "$field_known" ] || prev_red=""
  if ! items=$(card20 --config "$3" items 2>/dev/null); then
    # Đọc danh sách card lỗi (mạng, đọc thiếu trang): không xoá card đỏ nào (bản gốc, kể cả khi id field vừa đọc lại) và
    # không ghi lại. REDS ("đã ghi đỏ trên field này") theo prev_red: id field vừa đổi thì rỗng, để lượt đọc tốt sau ghi
    # 🔴 lên field mới. Card nay có worker sống (vừa ghi 🟢 ở trên) thì bỏ khỏi cả hai.
    set -f
    for n in $orig_red; do
      case "$n" in ''|*[!0-9]*) continue ;; esac
      case " $live " in *" $n "*) continue ;; esac
      red="$red $n"; keep="$keep $n"
      case " $prev_red " in *" $n "*) CF_REDS="$CF_REDS $n" ;; esac
    done
    set +f
    items=""
  fi
  while IFS='	' read -r n item; do
    case "$n" in ''|*[!0-9]*) continue ;; esac
    case " $live " in *" $n "*) continue ;; esac
    red="$red $n"; keep="$keep $n"
    case " $prev_red " in *" $n "*) CF_REDS="$CF_REDS $n"; continue ;; esac
    budget_ok || continue
    if gh20 project item-edit --id "$item" --project-id "$pid" --field-id "$CF_FIELD" --text "🔴 không chạy" >/dev/null 2>&1; then
      CF_REDS="$CF_REDS $n"
    else FIELD_STALE=1; fi
  done <<EOF
$(printf '%s' "$items" | jq -r '.items[]? | select(.status == "Building" or .status == "QA" or .status == "Review")
  | "\(.content.number)\t\(.id)"' 2>/dev/null)
EOF
  CF_REDS=${CF_REDS# }
  set -f   # CARDS nằm trong file worker ghi được: không glob, chỉ nhận số
  for n in $CF_CARDS; do
    case "$n" in ''|*[!0-9]*) continue ;; esac
    case " $live $red " in *" $n "*) continue ;; esac
    budget_ok || { keep="$keep $n"; continue; }
    item=$(card20 --config "$3" item-id "$n" 2>/dev/null) || { keep="$keep $n"; continue; }   # đọc lỗi: lượt sau thử
    # Xoá hỏng (mạng, hay field đã bị xoá trên GitHub): giữ card và đọc lại id field lượt sau.
    gh20 project item-edit --id "$item" --project-id "$pid" --field-id "$CF_FIELD" --clear >/dev/null 2>&1 \
      || { keep="$keep $n"; FIELD_STALE=1; }
  done
  set +f
  CF_CARDS=${keep# }
  [ -z "${FIELD_STALE:-}" ] || CF_FIELD=""
}

publish_board_status() {
  [ "${SB_BOARD_STATUS:-1}" != 0 ] && [ "$CHECKED" = 1 ] || return 0
  local cfg=".claude/super-board/configs/$SLUG.json" owner number last_key last_at
  owner=$(jq -r '.project.owner // empty' "$cfg" 2>/dev/null) || return 0
  number=$(jq -r '.project.number // empty' "$cfg" 2>/dev/null) || return 0
  [ -n "$owner" ] || return 0
  case "$number" in ''|*[!0-9]*) return 0 ;; esac
  local plock="$DIR/$SLUG.publish.lock" m
  if ! mkdir "$plock" 2>/dev/null; then
    m=$(file_mtime "$plock") || m=$NOW
    [ $((NOW - m)) -ge 300 ] || return 0
    rmdir "$plock" 2>/dev/null || true
    mkdir "$plock" 2>/dev/null || return 0
  fi
  trap 'rmdir "'"$plock"'" 2>/dev/null || true' EXIT
  board_status_text
  last_key=$(field KEY "$BOARD_STATUS"); last_at=$(field AT "$BOARD_STATUS")
  case "$last_at" in ''|*[!0-9]*) last_at=0 ;; esac
  [ "$BS_KEY" != "$last_key" ] || [ $((NOW - last_at)) -ge "$BOARD_STATUS_HEARTBEAT" ] || return 0
  # Nhiều worker: cắt còn 200 ký tự để "cập nhật …" ở cuối cho cron đọc. Cắt bằng perl theo ký tự UTF-8: launchd chạy
  # bash với locale C, ${#…}/${…:0:n} của bash sẽ đếm và cắt theo byte, giữa một chữ có dấu hay emoji.
  local cut
  cut=$(printf '%s' "$BS_TEXT" | perl -CS -Mutf8 -e 'local $/; my $t = <STDIN>; print length($t) > 200 ? substr($t, 0, 197) . "…" : $t') \
    && [ -n "$cut" ] && BS_TEXT=$cut   # perl hỏng: giữ nguyên chuỗi, không ghi mô tả rỗng
  gh20 project edit "$number" --owner "$owner" --description "$BS_TEXT · cập nhật $(TZ="$BOARD_TZ" date -r "$NOW" "+%H:%M %d/%m")" >/dev/null 2>&1 || return 0
  rm -f "$ROOT/$DIR/$SLUG.publish-halt.json" 2>/dev/null || true   # sót từ lượt bị giết: đừng để nó chặn lượt này
  publish_card_fields "$owner" "$number" "$cfg" || true
  rm -f "$ROOT/$DIR/$SLUG.publish-halt.json" 2>/dev/null || true
  { printf 'KEY=%s\nAT=%s\nFIELD=%s\nCARDS=%s\nREDS=%s\n' "$BS_KEY" "$NOW" "${CF_FIELD:-}" "${CF_CARDS:-}" "${CF_REDS:-}" > "$BOARD_STATUS.$$" \
      && mv -f "$BOARD_STATUS.$$" "$BOARD_STATUS"; } 2>/dev/null || rm -f "$BOARD_STATUS.$$" 2>/dev/null || true
  return 0
}

check() {
  # Không có bản ghi lẫn marker: board chưa từng chạy với runner này, không có gì để giám sát (không tạo thư mục, khoá).
  [ -f "$STATE" ] || [ -e "$MARK" ] || return 0
  take_check_lock || return 0
  CHECKED=1
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
  env_path=$(safe_path "$(field ENV_PATH "$STATE")"); env_path=${env_path:-$PATH}
  local halt_resume=0
  case "$state" in
    running|crashed) ;;
    # Halt GitHub (rc 79, còn github-halt.json): 20/10 09:00 máy gập nắp ngủ, 09:07 thức khi mạng chưa lên, `gh api
    # rate_limit` hỏng 3 lần → cả 5 board halt và nằm im 3,5 giờ. Halt có lần ĐỌC đã lưu thì `--resume` phát lại được an
    # toàn (chỉ đọc); halt do một lần ghi chưa rõ kết quả thì --resume tự từ chối (cần người đối chiếu).
    halted)
      if [ "$rc" != 79 ] || (PATH="$env_path"; python3 "$SCRIPT_DIR/super-board-github-read.py" --check >/dev/null 2>&1); then
        verdict "ended-$state" "runner ended on purpose (STATE=${state:-?} rc=${rc:-?}) — not restarted"; return 0
      fi
      halt_resume=1 ;;
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
  for t in $RUNNER_TOOLS; do (PATH="$env_path"; command -v "$t" >/dev/null 2>&1) || missing="$missing $t"; done
  if [ -n "$missing" ]; then
    verdict missing-tools "runner pid $pid is dead but its PATH lacks:$missing (PATH=$env_path) — not restarted"
    return 0
  fi
  if [ "$halt_resume" = 0 ] && ! (PATH="$env_path"; python3 "$SCRIPT_DIR/super-board-github-read.py" --check >/dev/null 2>&1); then
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
  if [ "$halt_resume" = 1 ]; then
    # Chỉ resume khi ngay sau đó khởi động lại (sau gave-up và backoff): --resume lưu trữ file halt, resume rồi dừng ở
    # backoff thì lượt sau thấy halted mà hết halt → ended-halted, board nằm im mãi. Mỗi lượt check (60 s) thử lại; cắt ở
    # 90 s (--resume tối đa ~186 s: 2 lần đọc × 3 lần × gh 30 s) để lượt check xong trước khi khoá bị coi là bỏ lại (120 s).
    # Bị cắt giữa chừng vẫn an toàn: --resume chỉ đọc, lưu trữ halt bằng rename.
    local why
    if ! why=$( (PATH="$env_path"; run_capped 90 python3 "$SCRIPT_DIR/super-board-github-read.py" --resume 2>&1 >/dev/null) ); then
      case "$why" in
        *reconcil*) verdict github-halt "runner halted (rc=79) on an uncertain GitHub write — check it on GitHub, then --resume --reconciled \"<what was checked>\" and start the board explicitly" ;;
        *) verdict halt-wait "runner halted (rc=79): its saved GitHub read still fails — retried every check" ;;
      esac
      return 0
    fi
    wlog "auto-resumed the GitHub halt of runner pid $pid: its saved read replayed OK (transient failure, e.g. network down after sleep)"
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
  check) check; release_check_lock; publish_board_status ;;
  status) status ;;
  install) install_agent ;;
  ensure) ensure_agent ;;
  uninstall) uninstall_agent ;;
esac
