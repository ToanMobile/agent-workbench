#!/usr/bin/env bash
# hooks/hardware_safety_gate.sh, chính sách thiết bị (lane r31adb, 01/11): `adb -s ""` lọt denylist.
#   Tái hiện trên GeelyEx2 (.adb-denylist có điện thoại thật): `adb -s '' reboot`, `adb -s "" shell pm clear …`,
#   `adb -s "" shell rm -rf /sdcard/Download` đều rc 0, còn `adb -s "" get-serialno` trả đúng serial bị cấm.
#   Nguyên nhân: target_serial trả serial rỗng ("không có serial") nên device_violation bỏ qua. Serial rỗng nghĩa là
#   adb tự chọn thiết bị (như không có -s), nên cổng phải hỏi adb get-serialno như với adb trần.
#   Cùng chỗ đó cổng tin chuỗi -s ĐẦU TIÊN, còn adb 37.0.1 (đo 01/11 bằng serial không tồn tại) dùng -s CUỐI CÙNG
#   (cả dạng dính -s<số>) và -t thắng -s bất kể thứ tự: `adb -s emulator-5554 -s "" reboot`,
#   `adb -s emulator-5554 -t 2 reboot` cũng lọt. Biến chưa biết trong -t/-s sau cũng phải bị từ chối như -s "$X".
#   --serial không phải tuỳ chọn của adb 37 ("unknown command --serial"); cổng vẫn coi nó như -s cho chắc.
# Chỉ chạy hook — không bao giờ chạy lệnh. check() đặt $TMP/bin (adb giả) lên đầu PATH của hook: adb giả chỉ trả lời
# get-serialno, ghi mọi lần gọi vào $ADB_FAKE_LOG và trả 97 với lệnh khác; dòng cuối của test đọc log đó.
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
printf '# máy cá nhân\nR58PHONE01\n0PHONE2\n' > "$P/.adb-denylist"
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
# hook tìm adb theo PATH (shutil.which): adb đầu PATH của check() phải là adb giả, không phải adb thật của máy
[ "$(PATH="$TMP/bin:$PATH"; command -v adb)" = "$TMP/bin/adb" ] || { echo "FAIL: adb giả không đứng đầu PATH"; exit 1; }

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

echo "— serial rỗng: adb tự chọn thiết bị (ở đây là điện thoại bị cấm) → chặn"
check 2d 'adb -s "" reboot'
check 2d "adb -s '' reboot"
check 2d 'adb --serial "" reboot'   # adb 37.0.1 từ chối --serial (lệnh tự lỗi, không phải lỗ cũ); cổng vẫn xét như -s
check 2d 'adb -s "" shell pm clear com.ecarx.launcher'
check 2d 'adb -s "" shell rm -rf /sdcard/Download'
check 2d 'adb -s "" install app.apk'
check 2d 'adb -s "" reboot' ANDROID_SERIAL=emulator-5554   # -s "" đè ANDROID_SERIAL: adb vẫn tự chọn
check 2d 'ANDROID_SERIAL= adb reboot'                       # đối chứng: đã chặn từ trước
echo "— lệnh shell có ; && | trong nháy: adb_calls cắt segment giữa chuỗi nháy → vẫn đọc đúng serial"
check 2d 'adb -s "" shell "cd /sdcard; ls"'
check 2d "adb -s '' shell 'cd /sdcard && ls'"
check 2d 'adb -s "" shell "ls | head"'
check 2d 'adb -s "R58PHONE01" shell "cd /sdcard; ls"'      # serial bị cấm trong nháy
check 0 'adb -s "emulator-5554" shell "cd /sdcard; ls"'
check 2d 'adb -s "" shell "find /sdcard -exec ls {} \;"'          # \; trong nháy kép: segment kết thúc bằng \
check 2d 'adb -s "R58PHONE01" shell "find /sdcard -exec ls {} \;"'
check 2d "adb -s \"\" shell \"grep 'x\\|y' /sdcard/a\""
echo "— nháy mở ở segment trước, đóng ở segment có lệnh adb (; | trong giá trị biến) → vẫn thấy lệnh adb"
check 2d 'FOO="a;b" adb -s R58PHONE01 reboot'
check 2d "env FOO='x|y' adb -s R58PHONE01 reboot"
check 0 'FOO="a;b" adb -s emulator-5554 reboot'
check 2d 'FOO="a;b" adb -s R58PHONE01 shell "cd /sdcard; ls"'
check 2d 'FOO="a;b" adb -s "" shell "cd /sdcard; ls"'
check 2d 'env FOO="a|b" adb -s "" shell "ls | head"'
check 2d 'ANDROID_SERIAL= adb reboot' ANDROID_SERIAL=emulator-5554   # ANDROID_SERIAL rỗng đè env của phiên
echo "— chữ \"adb …\" trong chuỗi nháy đơn nhiều câu / nhiều dòng (script, commit, comment) không phải lệnh adb → cho qua"
check 0 "python3 -c 'import sys; cmd = \"adb reboot\"'"
check 0 "git commit -m \$'fix: issue #829\\nCheck \"adb reboot\" case'"
check 0 "gh issue comment 829 --body \$'Summary:\\nTested \"adb shell pm list packages\" on emulator'"
check 0 "echo 'note: a; see \"adb install app.apk\"'"
check 0 "$(printf 'git commit -m %s' "'fix: x
Check \"adb reboot\" case'")"   # xuống dòng thật trong chuỗi nháy đơn
check 0 "git commit -m 'hook: x; \"adb reboot\" is blocked'"
check 0 "git commit -m \"hook: x; 'adb reboot' is blocked\""
check 0 'echo "$(date) adb started"'
check 0 'echo $(date) adb reboot done'
check 2d "$(printf '%s' "cat <<EOF
it's fine
EOF
adb -s \"\" shell \"cd /sdcard; ls\"")"   # nháy đơn trong thân heredoc làm quote_split đọc sai: bản cắt thô vẫn chặn
echo "— -s cuối cùng thắng, -t thắng -s (adb 37.0.1) → chặn"
check 2d 'adb -s emulator-5554 -s "" reboot'
check 2d 'adb -s emulator-5554 -s R58PHONE01 reboot'
check 2d 'adb -s emulator-5554 -s0PHONE2 reboot'
check 2d 'adb -s emulator-5554 -t 2 reboot'
check 2d 'adb -t 2 -s emulator-5554 reboot'
check 2d 'T=2; adb -s emulator-5554 -t "$T" reboot'
echo "— serial / tuỳ chọn lấy từ lệnh con \$( ) hay \` \`: adb_calls cắt segment ở đó → không xác định được → chặn"
check 2u "adb -s \$(adb devices | awk 'NR==2{print \$1}') reboot"
check 2u 'adb -s "$(cat serial.txt)" reboot'
check 2u 'adb -s "`cat serial.txt`" reboot'
check 2u 'adb $(echo -s R58PHONE01) reboot'
check 2u 'adb -s emulator-5554 $(echo -s R58PHONE01) reboot'   # -s cuối do lệnh con đưa ra mới thắng
check 0 'adb -s emulator-5554 shell "echo $(date)"'             # lệnh con nằm trong lệnh shell, serial đã ghi
check 0 'adb -s emulator-5554 shell "echo $((1 + 2))"'
check 0 'X=$(adb -s emulator-5554 shell getprop ro.serialno)'
check 2d 'X=$(pwd) adb -s R58PHONE01 reboot'              # lệnh con ở phép gán tiền tố không che lệnh adb
check 2d 'X=$(pwd) adb -s "" reboot'
check 2u 'ANDROID_SERIAL=$(echo R58PHONE01) adb reboot'
check 0 'adb -P $(echo 5037) -s emulator-5554 install app.apk'   # lệnh con ở -P, serial đã ghi
check 2u "echo '\$('; adb -s \$(echo R58PHONE01) reboot"           # \$( trong nháy đơn trước đó không nuốt phần sau
check 2u "git commit -m 'use \`x'; adb -s \`echo R58PHONE01\` reboot"   # backtick lẻ trong nháy đơn
check 2u '__SUBST__=emulator-5554; adb -s $(echo R58PHONE01) reboot'   # chữ thay lệnh con không bị bung như biến
check 2d 'X=$(echo "(") adb -s R58PHONE01 reboot; echo )'          # ngoặc trong nháy bên trong lệnh con
check 2d 'X=$(echo "a ) b") adb -s R58PHONE01 reboot'
check 2d 'X=$(case a in a) echo 1;; esac) adb -s R58PHONE01 reboot'   # ) của nhánh case bên trong lệnh con
echo "— backtick markdown trong chuỗi nháy đơn (commit, comment) không phải lệnh adb chạy được → cho qua"
check 0 "git commit -m 'fix: block \`adb -s \"\"\` on denylist'"
check 0 "echo 'usage: \`adb -e\` or \`adb -d\`'"
check 0 "rg '\`adb -s\`' docs/"
check 0 "gh issue comment 829 --body 'tested \`adb -s \"\"\` case'"
echo "— mở rộng tham số / biến bị gán lại trong lệnh: không đoán giá trị → không xác định được → chặn"
check 2u 'S=emulator-5554; adb -s "${S##*}" reboot'          # ${S##*} = chuỗi rỗng
check 2u 'S=emulator-5554; adb -s "${S/emulator-5554/R58PHONE01}" reboot'
check 2u 'R31_U=""; adb -s "$R31_U" reboot' R31_U=emulator-5554   # env của hook không phải giá trị lúc chạy
echo "— biến chưa biết ở chỗ subcommand (có thể bung ra -s …) → không xác định được → chặn"
check 2u 'O="-s R58PHONE01"; adb $O reboot'
check 2u 'adb ${O} reboot'
check 2u 'adb "$@" reboot'
check 0 'C=reboot; adb -s emulator-5554 $C'   # biến đã biết
check 2u 'O=-s; adb -s emulator-5554 $O R58PHONE01 reboot'   # biến bung ra tuỳ chọn: -s cuối mới thắng
check 2u 'adb -s emulator-5554 $R31_ARGS reboot' R31_ARGS="-s R58PHONE01"
echo "— lựa chọn thiết bị phải hỏi adb mà adb không trả lời được → không xác định được → chặn"
check 2u 'adb -s "" reboot' FAKE_FAIL=1
check 2 'adb -s "" reboot' FAKE_HANG=1                  # get-serialno treo: chặn (watchdog), không cho qua
check 2d 'adb -s model:Phone reboot'                     # -s model:/usb:/product:/device: phân giải qua adb
check 0 'adb -s model:Emu reboot'
check 2u 'adb -s model:Phone reboot' FAKE_FAIL=1         # không phân giải được: không so chuỗi "model:Phone" với denylist
check 2d 'adb -t2 reboot'                                # dạng dính
check 2d 'adb -s0PHONE2 reboot'
check 2u 'adb -sR58PHONE01 reboot'                       # adb 37 từ chối (-s requires an argument): không đoán
check 2u 'adb -s emulator-5554 -t 2 reboot' FAKE_FAIL=1
check 0 'adb -s emulator-5554 reboot' FAKE_FAIL=1   # serial literal duy nhất: không cần hỏi adb
if [ -x /usr/bin/adb ] || [ -x /bin/adb ]; then echo "skip: có adb ở /usr/bin hay /bin, không dựng được PATH không có adb"
else
  check 2u 'adb -s "" reboot' PATH="$NOADB"
  check 0 'adb -s emulator-5554 reboot' PATH="$NOADB"
fi
check 0 'adb -s "" reboot' FAKE_DEFAULT=emulator-5554   # -s "" hỏi adb thật sự, không chặn mù
echo "— -d / -e: adb tự chọn theo loại kết nối"
check 2d 'adb -d reboot'                     # đối chứng: đã chặn từ trước
check 0 'adb -e reboot'
echo "— biến bung ra rỗng ở chỗ subcommand: shell bỏ chữ đó, lệnh thành adb <phần sau> → vẫn xét"
check 2u 'adb $R31_EMPTY reboot' R31_EMPTY=
check 2u 'adb ${R31_EMPTY} reboot' R31_EMPTY=
echo "— \$'…' có \\\\' và nháy đơn trong comment không làm lệch cách đọc theo nháy"
check 2d "FOO=\$'it\\'s ok' adb -s R58PHONE01 reboot"
check 2d "FOO=\$'a\\'b;c' adb -s R58PHONE01 reboot"
check 2d "FOO=\$'it\\'s ok' adb -s \"\" reboot"
check 2d "$(printf '%s\n%s' "# check user's device" 'FOO="a;b" adb -s R58PHONE01 reboot')"
check 2d "$(printf '%s\n%s' "# don't touch phone" 'X=$(echo a b) adb -s R58PHONE01 reboot')"
check 2d "$(printf '%s\n%s' "X=\$( # it's" 'echo ok) adb -s R58PHONE01 reboot')"
check 2d 'X=$(echo "$(echo ") a b")") adb -s R58PHONE01 reboot'   # lệnh con lồng trong nháy kép bên trong lệnh con
echo "— dòng đánh số \"1) adb …\" trong chuỗi / thân heredoc không có lệnh con → cho qua"
check 0 "$(printf '%s\n%s' 'git commit -m "fix: hooks' '1) adb reboot"')"
check 0 "$(printf '%s\n%s\n%s' "gh issue comment 829 --body 'Audit:" '(a) adb -s "" reboot' "(b) ok'")"
check 0 "$(printf '%s\n%s\n%s' "cat <<'EOF' | wc -l" '1) adb reboot' 'EOF')"
check 0 "$(printf '%s\n%s\n%s' "tee /dev/null <<'EOF'" '1) adb reboot' 'EOF')"
echo "— chữ \"x) adb …\" trong chuỗi (lệnh con chỉ nằm trong nháy đơn, | trong nháy kép) → cho qua"
check 0 "git commit -m 'note: \$(date) adb started'"
check 0 'grep -E "a|b) adb -s R58PHONE01 reboot" notes.txt'
echo "— biến chưa biết trong tuỳ chọn chọn thiết bị → không xác định được → chặn"
check 2u 'adb -s emulator-5554 -s "$R31_UNSET_SERIAL" reboot'
check 2u 'adb -t "$R31_UNSET_TID" reboot'
check 2u 'adb -s "$R31_UNSET_SERIAL" reboot'               # đối chứng: đã chặn từ trước
check 2d 'adb -s R58PHONE01 reboot'                         # đối chứng: serial bị cấm
echo "— giữ nguyên: emulator, biến đã biết, host-only, override → cho qua"
check 0 'adb -s emulator-5554 reboot'
check 0 'adb -s emulator-5554 shell rm -rf /sdcard/Download'
check 0 'S=emulator-5554; adb -s "$S" reboot'
check 0 'adb -s R58PHONE01 -s emulator-5554 reboot'      # -s cuối là emulator
check 0 'adb -t 1 reboot'
check 0 'adb -P "$R31_UNSET_PORT" -s emulator-5554 install app.apk'   # cổng server không đổi serial -s đã ghi
check 0 'adb -s "" devices'
check 0 'adb -s "" reboot' HARDWARE_OVERRIDE=1
check 0 'adb -s "" shell rm -rf /sdcard/Download' HARDWARE_OVERRIDE=1
echo "— -s là giá trị của tuỳ chọn khác: không được làm hook lỗi (IndexError); adb không phân giải được → chặn"
check 2u 'adb -H -s reboot'              # -H "-s": không nối được server
check 2u 'T=-s; adb -t "$T" reboot'      # -t "-s": transport id sai

# adb giả chỉ được hỏi get-serialno: lệnh thật (reboot, shell …) không bao giờ chạy
if grep -v 'get-serialno$' "$ADB_FAKE_LOG" | grep -q .; then
  fail "hook chạy adb ngoài get-serialno: $(grep -v 'get-serialno$' "$ADB_FAKE_LOG" | head -3 | tr '\n' ';')"
else ok "adb giả chỉ nhận get-serialno ($(wc -l < "$ADB_FAKE_LOG" | tr -d ' ') lần)"; fi
# -s "" được hỏi adb với đúng tuỳ chọn đó (không phải bị chặn mù hay bỏ -s)
if grep -qx -- '-s  get-serialno' "$ADB_FAKE_LOG"; then ok 'adb giả nhận "-s \"\" get-serialno"'
else fail 'không lần nào hỏi adb "-s \"\" get-serialno"'; fi

echo
if [ "$FAILS" -eq 0 ]; then echo "PASS: test_hardware_empty_serial"; exit 0; fi
echo "FAIL: test_hardware_empty_serial ($FAILS)"; exit 1
