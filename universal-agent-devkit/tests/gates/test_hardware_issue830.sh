#!/usr/bin/env bash
# hooks/hardware_safety_gate.sh, chính sách thiết bị (thẻ #830, lane build): bốn cách lệnh adb lọt denylist.
#   1. adb wait-for-device <lệnh> khi get-serialno lỗi (chưa cắm máy): cổng coi là "adb tự lỗi", lệnh thật chờ rồi chạy trên máy cắm sau.
#   2. ADB Wi-Fi: denylist 192.168.1.20:5555 mà adb -s 192.168.1.20 / tcp:192.168.1.20:5555 vẫn rc 0 (so chuỗi nguyên văn).
#   3. export ANDROID_SERIAL=X; adb reboot: cổng chỉ đọc ANDROID_SERIAL= tiền tố trên cùng lệnh adb.
#   4. case x in x) adb -s X reboot;; esac: `case` / `in` không ở SHELL_LEAD, chữ `x)` chặn việc tìm lệnh adb.
# Chỉ chạy hook, không bao giờ chạy lệnh thật. adb giả (xem check) chỉ trả lời get-serialno, ghi log, trả 97 với lệnh khác.
# HW_HOOK=<đường dẫn hook> chạy bản hook khác (bản chưa sửa: RED).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # bỏ GIT_* thừa kế: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${HW_HOOK:-$DEVKIT_DIR/hooks/hardware_safety_gate.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }

P="$TMP/proj"
mkdir -p "$P" "$TMP/bin" "$TMP/xdg"
# R58PHONE01: điện thoại cá nhân (thiết bị duy nhất adb tự chọn); 0PHONE2: serial bắt đầu bằng số (dạng dính -s0PHONE2)
printf '# máy cá nhân\nR58PHONE01\n0PHONE2\n192.168.1.20:5555\n' > "$P/.adb-denylist"
export ADB_FAKE_LOG="$TMP/adb.log"
: > "$ADB_FAKE_LOG"
# adb giả theo thứ tự chọn thiết bị của adb 37.0.1: -t thắng -s; -s cuối thắng; -s "" = thiết bị adb tự chọn
# (-d / -e / ANDROID_SERIAL chỉ dùng khi không có -s). Transport 1 = emulator-5554, 2 = R58PHONE01; -d = R58PHONE01 (USB),
# -e = emulator-5554. -H khác localhost: không nối được server (lỗi, như adb thật với host không tồn tại).
# FAKE_DEFAULT: thiết bị adb tự chọn (mặc định R58PHONE01); FAKE_FAIL=1: get-serialno lỗi (server đang khởi động lại).
cat > "$TMP/bin/adb" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ADB_FAKE_LOG"
[ "${FAKE_FAIL-}" = 1 ] && { echo "error: closed" >&2; exit 1; }
[ "${FAKE_HANG-}" = 1 ] && { sleep 12; exit 1; }   # server treo: watchdog 7 s của hook phải chặn trước
serial="" sset=0 tid="" usb=0 tcp=0
while [ $# -gt 0 ]; do
  case "$1" in
    -s) serial="${2-}"; sset=1; shift 2 || shift ;;
    -s[0-9]*) serial="${1#-s}"; sset=1; shift ;;
    -t) tid="${2-}"; shift 2 || shift ;;
    -t[0-9]*) tid="${1#-t}"; shift ;;
    -d) usb=1; shift ;;
    -e) tcp=1; shift ;;
    -H) [ "${2-}" = localhost ] || { echo "error: cannot connect to daemon at tcp:${2-}:5037" >&2; exit 1; }; shift 2 ;;
    -P|-L) shift 2 || shift ;;
    -*) echo "adb: unknown command $1" >&2; exit 1 ;;
    *) break ;;
  esac
done
[ "${1-}" = get-serialno ] || { echo "adb giả: lệnh thật không được chạy: $*" >&2; exit 97; }
known() { case "$1" in emulator-5554|R58PHONE01|0PHONE2) echo "$1" ;; model:Phone) echo R58PHONE01 ;; model:Emu) echo emulator-5554 ;;
  *) echo "error: device '$1' not found" >&2; exit 1 ;; esac; }
if [ -n "$tid" ]; then
  case "$tid" in 1) echo emulator-5554 ;; 2) echo R58PHONE01 ;; *) echo "error: no device with transport id '$tid'" >&2; exit 1 ;; esac
  exit 0
fi
[ "$sset" = 1 ] && [ -n "$serial" ] && { known "$serial"; exit 0; }
if [ "$sset" = 0 ]; then
  [ "$usb" = 1 ] && { echo R58PHONE01; exit 0; }
  [ "$tcp" = 1 ] && { echo emulator-5554; exit 0; }
  [ -n "${ANDROID_SERIAL-}" ] && { known "$ANDROID_SERIAL"; exit 0; }
fi
echo "${FAKE_DEFAULT:-R58PHONE01}"
EOF
chmod +x "$TMP/bin/adb"
# PATH không có adb nào (hook không tìm được adb): python3 vẫn là python3 mặc định của máy (link tới đúng bản đó)
mkdir -p "$TMP/noadb" && ln -s "$(python3 -c 'import sys; print(sys.executable)')" "$TMP/noadb/python3" \
  && ln -s "$(command -v bash)" "$TMP/noadb/bash"   # trình thông dịch thật (không phải shim pyenv) và đúng bash đang chạy
NOADB="$TMP/noadb:/usr/bin:/bin"
# check <mong đợi> <lệnh> [VAR=giá trị …]: chạy hook một lần với lệnh Bash đó, cwd = fixture.
# Mong đợi: 0 (cho qua) · 2d (chặn, lý do denylist) · 2u (chặn, không xác định được thiết bị đích).
check() {
  local want="$1" c="$2" why=""; shift 2
  case "$want" in 2d) why='nằm trong denylist' ;; 2u) why='không xác định được thiết bị đích' ;; esac
  want="${want%[du]}"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$c" "$P" > "$TMP/in.json"
  ( cd "$P" && env -u ANDROID_SERIAL -u ADB_DENY_SERIALS -u ADB_ALLOW_SERIALS -u HARDWARE_OVERRIDE -u HARDWARE_SAFETY_GATE \
      PATH="$TMP/bin:$PATH" XDG_CONFIG_HOME="$TMP/xdg" CLAUDE_PROJECT_DIR="$P" "$@" bash "$HOOK" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$?
  # SyntaxWarning: escape sai trong chuỗi Python của hook (in ra stderr ở mọi lần chạy hook)
  if grep -q 'Traceback\|lỗi nội bộ\|SyntaxWarning' "$TMP/err"; then fail "hook lỗi (rc $rc): $c — $(head -c 300 "$TMP/err" | tr '\n' ' ')"; return; fi
  # rc 2 phải đến từ chính sách thiết bị (hook lỗi cũng trả 2 qua _fail_closed: không được tính là chặn đúng)
  if [ -n "$why" ] && [ "$rc" = 2 ] && ! grep -q "$why" "$TMP/err"; then
    fail "rc 2 nhưng lý do không phải \"$why\": $c — $(head -c 200 "$TMP/err" | tr '\n' ' ')"; return
  fi
  if [ "$rc" = "$want" ]; then ok "rc $rc: $c${*:+  [$*]}"; else fail "rc $rc (want $want): $c${*:+  [$*]} — $(head -c 200 "$TMP/err" | tr '\n' ' ')"; fi
}

echo "— 1. wait-for-* khi chưa có máy (get-serialno lỗi): đích chưa phân giải được → chặn, bắt ghi rõ -s"
check 2u 'adb wait-for-device reboot' FAKE_FAIL=1
check 2u 'adb -s "" wait-for-device reboot' FAKE_FAIL=1
check 2u 'adb wait-for-device shell pm clear com.ecarx.launcher' FAKE_FAIL=1
check 2u 'adb wait-for-usb-device reboot' FAKE_FAIL=1
check 0 'adb -s emulator-5554 wait-for-device reboot' FAKE_FAIL=1          # -s khác rỗng là lựa chọn duy nhất: cho qua
check 0 'adb wait-for-device' FAKE_FAIL=1                                  # không có lệnh theo sau: không làm gì
check 0 'adb wait-for-device reboot' FAKE_DEFAULT=emulator-5554            # phân giải được máy hợp lệ: cho qua như adb trần
check 2d 'adb wait-for-device reboot'                                      # đối chứng: phân giải ra máy bị cấm
check 0 'adb reboot' FAKE_FAIL=1                                           # đối chứng: adb trần lỗi, lệnh tự lỗi (hành vi cũ)
echo "— 2. ADB Wi-Fi: khớp denylist theo cách adb khớp transport TCP (bỏ tcp:/udp:, host không port khớp mọi port)"
check 2d 'adb -s 192.168.1.20:5555 reboot'                                 # đối chứng: đã chặn
check 2d 'adb -s 192.168.1.20 reboot'
check 2d 'adb -s tcp:192.168.1.20:5555 reboot'
check 2d 'adb -s tcp:192.168.1.20 reboot'
check 2d 'adb -s udp:192.168.1.20:5555 reboot'
check 2d 'adb -s 192.168.1.20 shell pm clear com.x'
check 0 'adb -s 192.168.1.21 reboot'
check 0 'adb -s 192.168.1.20:5556 reboot'                                  # port khác, ghi rõ: máy khác
check 0 'adb -s tcp:192.168.1.21:5555 reboot'
echo "— 3. export ANDROID_SERIAL=X / ANDROID_SERIAL=X; ở lệnh trước adb trong cùng lệnh"
check 2d 'export ANDROID_SERIAL=R58PHONE01; adb reboot' ANDROID_SERIAL=emulator-5554
check 2d 'export ANDROID_SERIAL=R58PHONE01 && adb reboot' ANDROID_SERIAL=emulator-5554
check 2d 'ANDROID_SERIAL=R58PHONE01; adb reboot' ANDROID_SERIAL=emulator-5554
check 2d "$(printf 'export ANDROID_SERIAL=R58PHONE01\nadb reboot')" ANDROID_SERIAL=emulator-5554
check 2d 'export ANDROID_SERIAL=192.168.1.20; adb reboot' ANDROID_SERIAL=emulator-5554
check 2u 'export ANDROID_SERIAL=$X; adb reboot' ANDROID_SERIAL=emulator-5554
check 0 'export FOO=R58PHONE01; adb -s emulator-5554 reboot'
echo "— 4. adb trong nhánh case ở vị trí lệnh"
check 2d 'case x in x) adb -s R58PHONE01 reboot;; esac'
check 2d "$(printf 'case x in\n  x) adb -s R58PHONE01 reboot;;\nesac')"
check 2d 'case $1 in a|b) echo hi; adb -s "" reboot;; esac'
check 2d 'case x in x) export ANDROID_SERIAL=R58PHONE01; adb reboot;; esac' ANDROID_SERIAL=emulator-5554
check 0 'case x in x) adb -s emulator-5554 reboot;; esac'
check 0 'case x in x) echo "adb -s R58PHONE01 reboot";; esac'              # chữ trong nháy không phải lệnh
check 0 "echo 'case x in x) adb -s R58PHONE01 reboot;; esac'"
echo "— #845 (gộp): tên lệnh rm đến từ biến / mở rộng tham số"
check 2 'X=rm; $X -rf ~'
check 2 '${x:-rm} -rf ~'
check 2 '"${x:-rm}" -rf ~'
check 2 "bash -c '\${x:-rm} -rf ~'"
check 2 '${x-rm} -rf ~'
check 2 '$UNKNOWN -rf ~'                                                   # biến chưa biết ở vị trí lệnh trước tham số nguy hiểm: fail closed
check 0 'X=ls; $X -la'
check 0 '${PAGER:-less} README.md'
check 0 "rg 'X=rm; \$X -rf ~' ."
check 0 "grep -E 'rm|x' notes.txt"
check 0 "git grep 'rm -rf' -- ."
check 0 "sed -n '/rm -rf/p' notes.txt"

echo "— vòng 1 (reviewer R1–R5)"
# R1: bản cắt thô không được chặn thêm so với trước #830 (mẫu tìm kiếm có chữ adb trong nháy vẫn qua)
check 0 'grep -E "x|adb wait-for-device reboot" notes.txt' FAKE_FAIL=1
check 0 'grep -E "x|adb -s 192.168.1.20 reboot" notes.txt'
# R2: wait-for-* ở lệnh adb riêng, lệnh thật ở lệnh adb sau
check 2u 'adb wait-for-device && adb reboot' FAKE_FAIL=1
check 2u 'adb wait-for-device; adb shell pm clear x' FAKE_FAIL=1
check 0 'adb wait-for-device && adb -s emulator-5554 reboot' FAKE_FAIL=1
# R4: ANDROID_SERIAL gán bằng giá trị động / dạng khác của export: fail closed
check 2u 'export ANDROID_SERIAL=$(echo R58PHONE01); adb reboot' ANDROID_SERIAL=emulator-5554
check 2d 'declare -x ANDROID_SERIAL=R58PHONE01; adb reboot' ANDROID_SERIAL=emulator-5554
check 2d 'export FOO=1 ANDROID_SERIAL=R58PHONE01; adb reboot' ANDROID_SERIAL=emulator-5554
check 2d 'if true; then export ANDROID_SERIAL=R58PHONE01; fi; adb reboot' ANDROID_SERIAL=emulator-5554
# R5: các dạng gần kề
check 2d 'case x in (x) adb -s R58PHONE01 reboot;; esac'
check 2d 'case x in "a b") adb -s R58PHONE01 reboot;; esac'
check 2d 'adb -s 192.168.1.20:05555 reboot'
check 2 '${X:=rm} -rf ~'
check 2 '$X$Y -rf ~'

echo "— vòng 2 (reviewer R7–R10)"
# R7: giá trị ANDROID_SERIAL lấy từ lượt đọc theo nháy (đã cắt heredoc/comment/nháy), không từ chuỗi thô
check 0 'rg "a|export ANDROID_SERIAL=R58PHONE01|b" . && adb shell ls' ANDROID_SERIAL=emulator-5554
check 0 "grep -E 'x|export ANDROID_SERIAL=R58PHONE01|y' notes.txt && adb shell ls" ANDROID_SERIAL=emulator-5554
check 0 "$(printf 'cat <<\\EOF > n.txt\nexport ANDROID_SERIAL=R58PHONE01\nEOF\nadb shell ls')" ANDROID_SERIAL=emulator-5554
check 2d 'export ANDROID_SERIAL=R58PHONE01; adb reboot' ANDROID_SERIAL=emulator-5554
# R8: ANDROID_SERIAL của phiên vẫn được xét cùng giá trị export (không làm mềm cổng so với main)
check 2d 'ANDROID_SERIAL=emulator-5554; X=$(true) adb reboot' ANDROID_SERIAL=R58PHONE01
check 2d '(export ANDROID_SERIAL=emulator-5554); adb reboot' ANDROID_SERIAL=R58PHONE01
check 2d 'false && export ANDROID_SERIAL=emulator-5554; adb reboot' ANDROID_SERIAL=R58PHONE01
check 2d "export ANDROID_SERIAL=emulator-5554; bash -c 'adb reboot'" ANDROID_SERIAL=R58PHONE01
# R9: biến ở vị trí lệnh chỉ phán như rm khi mọi cờ thuộc tập cờ của rm; xargs giữ tiền tố
check 0 '"$PYTHON" -m pytest -rA .'
check 0 '"$TAR" -rf a.tar .'
check 2 'echo x | xargs $X -rf ~'
check 2 '$UNKNOWN -rf ~'
# R10: -s / -d / -e / -t trong lệnh thắng ANDROID_SERIAL của phiên; -s "" không rơi về serial của phiên
check 2u 'adb -s "" wait-for-device reboot' ANDROID_SERIAL=emulator-5554 FAKE_FAIL=1
check 2u 'adb -d wait-for-device reboot' ANDROID_SERIAL=emulator-5554 FAKE_FAIL=1
check 2u 'adb -e wait-for-device reboot' ANDROID_SERIAL=emulator-5554 FAKE_FAIL=1
check 0 'adb -s emulator-5554 wait-for-device reboot' ANDROID_SERIAL=emulator-5554 FAKE_FAIL=1

echo "— vòng 3 (reviewer R13–R15)"
# R13: ứng viên ${CMD:-export} không được ghi đè env sống (CMD=true thì export không chạy: D vẫn là ~)
check 2 'CMD=true; D=~; ${CMD:-export} D=/tmp/a; rm -rf "$D"'
check 2 'CMD=true; D=~; ${CMD:-declare} -g D=/tmp/a; rm -rf "$D"'
# R14: `--` sau cờ rm không làm lọt
check 2 '$UNKNOWN -rf -- ~'
# R15: đối số tương đối (tên tar) đứng trước: không phải rm ra ngoài dự án
check 0 '"$TAR" -rf a.tar ~/x'

echo "— vòng 4 (reviewer R16–R18)"
# R16: ứng viên ${CMD:-mkdir} không được ghi bẩn MKDIRS toàn cục (cp -R từ nguồn đó vẫn là cây có thật)
check 2 'CMD=true; ${CMD:-mkdir} /tmp/nonexistent_830_a && cp -R /tmp/nonexistent_830_a build/o && rm -rf build/o/x'
check 2 'X=echo; ${X-mkdir} nope_src && cp -R nope_src build/o && rm -rf build/o/'
# R17: token gán ANDROID_SERIAL="…)" không phải nhánh case: không bị nuốt
check 2 'ANDROID_SERIAL="$X;y)" adb reboot' ANDROID_SERIAL=emulator-5554
check 2 'ANDROID_SERIAL="$(echo R58PHONE01))" adb reboot' ANDROID_SERIAL=emulator-5554
# R18: không chặn nhầm so với main
check 0 'export ANDROID_SERIAL="${ANDROID_SERIAL:-emulator-5554}"; adb shell ls' ANDROID_SERIAL=emulator-5554
check 0 '"$TAR" -rf /tmp/a.tar ~/x'
check 0 '"$CP" -rf "$SRC" "$DST"'

# adb giả chỉ được hỏi get-serialno: lệnh thật (reboot, shell, wait-for-device …) không bao giờ chạy
if grep -v 'get-serialno$' "$ADB_FAKE_LOG" | grep -q .; then
  fail "hook chạy adb ngoài get-serialno: $(grep -v 'get-serialno$' "$ADB_FAKE_LOG" | head -3 | tr '\n' ';')"
else ok "adb giả chỉ nhận get-serialno ($(wc -l < "$ADB_FAKE_LOG" | tr -d ' ') lần)"; fi

echo
if [ "$FAILS" -eq 0 ]; then echo "PASS: test_hardware_issue830"; exit 0; fi
echo "FAIL: test_hardware_issue830 ($FAILS)"; exit 1
