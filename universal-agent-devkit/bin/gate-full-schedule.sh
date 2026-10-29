#!/usr/bin/env bash
# gate-full-schedule.sh install|uninstall|status [--repo PATH] [--hour 0] [--minute 0]
# Lịch lượt --full đêm (#644): LaunchAgent com.toanmobile.devkit.gate-full chạy bin/gate_full.py run --repo <repo> lúc <hour>:<minute>
# giờ máy (máy đặt Asia/Ho_Chi_Minh; TZ cũng đặt trong EnvironmentVariables để ngày trong log/summary đúng).
# launchd chỉ có PATH /usr/bin:/bin:/usr/sbin:/sbin: đường dẫn TUYỆT ĐỐI của python3 / git / gh lấy lúc cài, PATH của job chứa thư mục
# của chúng. Không sudo: bootstrap vào gui/<uid>. Lượt trùng (đêm trước chưa xong) do khoá pid của gate_full.py bỏ qua.
# Móc test: DEVKIT_LAUNCH_AGENTS_DIR (mặc định ~/Library/LaunchAgents), DEVKIT_LAUNCHCTL (mặc định launchctl),
# DEVKIT_GATE_FULL_LOG_DIR (mặc định ~/Library/Logs/devkit-gate-full). Tương thích bash 3.2.
set -u
LABEL="com.toanmobile.devkit.gate-full"
KIT="$(cd "$(dirname "$0")/.." && pwd)"
GF="$KIT/bin/gate_full.py"
LA_DIR="${DEVKIT_LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
LOG_DIR="${DEVKIT_GATE_FULL_LOG_DIR:-$HOME/Library/Logs/devkit-gate-full}"
LAUNCHCTL="${DEVKIT_LAUNCHCTL:-launchctl}"
PLIST="$LA_DIR/$LABEL.plist"
DOMAIN="gui/$(id -u)"

usage() { echo "usage: gate-full-schedule.sh install|uninstall|status [--repo PATH] [--hour 0] [--minute 0]" >&2; exit 2; }
ACTION="${1:-}"; [ -n "$ACTION" ] || usage; shift
REPO="$(pwd)"; HOUR=0; MINUTE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:?--repo cần đường dẫn}"; shift 2 ;;
    --hour) HOUR="${2:?--hour cần số}"; shift 2 ;;
    --minute) MINUTE="${2:?--minute cần số}"; shift 2 ;;
    *) usage ;;
  esac
done
case "$HOUR" in ''|*[!0-9]*) usage ;; esac
case "$MINUTE" in ''|*[!0-9]*) usage ;; esac
[ "$((10#$HOUR))" -le 23 ] && [ "$((10#$MINUTE))" -le 59 ] || usage

case "$ACTION" in
  install)
    REPO="$(cd "$REPO" 2>/dev/null && pwd)" || { echo "gate-full-schedule: không có repo $REPO" >&2; exit 2; }
    PY="$(command -v python3)" || { echo "gate-full-schedule: không thấy python3 trên PATH" >&2; exit 2; }
    GITB="$(command -v git)" || { echo "gate-full-schedule: không thấy git trên PATH" >&2; exit 2; }
    GHB="$(command -v gh || true)"
    [ -n "$GHB" ] || echo "gate-full-schedule: cảnh báo — không thấy gh: thẻ P1 khi đỏ sẽ không tạo được" >&2
    # PATH của job: thư mục của python3 / git / gh, rồi PATH đăng nhập của người dùng (suite gọi uv ở ~/.local/bin…: thiếu thì exit 127,
    # đêm nào cũng "chưa kết luận"; shell không trả được thì PATH lúc cài), rồi PATH mặc định của launchd — không trùng
    USER_PATH="$("${SHELL:-/bin/sh}" -lc 'printf %s "$PATH"' 2>/dev/null </dev/null | tail -n 1)"
    [ -n "$USER_PATH" ] || USER_PATH="$PATH"
    JOB_PATH=""
    for b in "$PY" "$GITB" "$GHB"; do
      [ -n "$b" ] || continue
      d="$(dirname "$b")"
      case ":$JOB_PATH:" in *":$d:"*) ;; *) JOB_PATH="${JOB_PATH:+$JOB_PATH:}$d" ;; esac
    done
    OLD_IFS="$IFS"; IFS=:
    for d in $USER_PATH /usr/bin /bin /usr/sbin /sbin; do
      case "$d" in /*) ;; *) continue ;; esac   # chỉ đường dẫn tuyệt đối (bỏ "", ".")
      case ":$JOB_PATH:" in *":$d:"*) ;; *) JOB_PATH="$JOB_PATH:$d" ;; esac
    done
    IFS="$OLD_IFS"
    mkdir -p "$LA_DIR" "$LOG_DIR" || exit 2
    # plistlib viết XML: không tự escape chuỗi trong heredoc
    "$PY" - "$PLIST" "$LABEL" "$PY" "$GF" "$REPO" "$HOUR" "$MINUTE" "$JOB_PATH" "$LOG_DIR" <<'PY' || exit 2
import os, plistlib, sys
plist, label, py, gf, repo, hour, minute, path, log_dir = sys.argv[1:]
data = {
    "Label": label,
    "ProgramArguments": ["/usr/bin/nice", "-n", "10", py, gf, "run", "--repo", repo],
    "WorkingDirectory": repo,
    "StartCalendarInterval": {"Hour": int(hour, 10), "Minute": int(minute, 10)},
    "EnvironmentVariables": {"PATH": path, "TZ": "Asia/Ho_Chi_Minh", "DEVKIT_GATE_FULL_LOG_DIR": log_dir},
    "StandardOutPath": os.path.join(log_dir, "launchd.out.log"),
    "StandardErrorPath": os.path.join(log_dir, "launchd.err.log"),
    "RunAtLoad": False,
    "ProcessType": "Background",
}
tmp = plist + ".tmp"
with open(tmp, "wb") as f:
    plistlib.dump(data, f)
os.replace(tmp, plist)
PY
    plutil -lint "$PLIST" >/dev/null || { echo "gate-full-schedule: plist không hợp lệ: $PLIST" >&2; exit 2; }
    "$LAUNCHCTL" bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true   # chưa nạp thì lỗi: bỏ qua
    "$LAUNCHCTL" bootstrap "$DOMAIN" "$PLIST" || { echo "gate-full-schedule: launchctl bootstrap $DOMAIN $PLIST lỗi" >&2; exit 1; }
    echo "gate-full: đã cài $PLIST — chạy $(printf '%02d:%02d' "$((10#$HOUR))" "$((10#$MINUTE))") mỗi ngày cho $REPO; tóm tắt: $LOG_DIR/summary-latest.md"
    ;;
  uninstall)
    "$LAUNCHCTL" bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
    rm -f "$PLIST"
    echo "gate-full: đã gỡ lịch $LABEL"
    ;;
  status)
    if [ -f "$PLIST" ]; then echo "plist: $PLIST"; else echo "plist: chưa cài ($PLIST)"; fi
    if P="$("$LAUNCHCTL" print "$DOMAIN/$LABEL" 2>/dev/null)"; then
      printf '%s\n' "$P" | grep -E '^[[:space:]]*(state|last exit code|runs|pid|program|path) =|Hour|Minute' | head -20
    else
      echo "launchd: chưa nạp $DOMAIN/$LABEL"
    fi
    echo "tóm tắt: $LOG_DIR/summary-latest.md"
    [ -f "$LOG_DIR/summary-latest.md" ] && sed -n '1,12p' "$LOG_DIR/summary-latest.md"
    exit 0
    ;;
  *) usage ;;
esac
