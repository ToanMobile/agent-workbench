#!/bin/bash
# shims/adb (#867): chặn adb ở điểm thực thi, lớp BỔ SUNG của hooks/hardware_safety_gate.sh (hook không đổi).
#   Corpus: toàn bộ ca của test_hardware_empty_serial.sh (T1, đọc từ chính file đó, không chép) chạy THẬT bằng bash -c trong fixture
#   với adb giả (chọn thiết bị theo adb 37.0.1, ghi mọi lệnh thật vào log). Ca phải chặn (2d / 2u): lệnh KHÔNG được tới điện thoại
#   bị cấm. Ca hợp lệ (0): shim không được từ chối. Đối chứng ĐỎ: cùng corpus không có shim (ADB_SHIM_SRC=none) ⇒ phải có
#   ≥ 85 ca chạm điện thoại, nếu không test này không phân biệt được shim.
#   Mục tiếp: 3 lỗi spike (mktemp, BASH_ENV/hàm export, -s "" trên bash 3.2), 10 ca chạy qua PATH mà hook không thấy, 16 ca đường
#   vòng không qua PATH (residual của shim: ghi rõ hook chặn hay lọt).
# ADB_SHIM_SRC=<đường dẫn shim> chạy bản khác; "none" = không shim (RED).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SHIM_SRC="${ADB_SHIM_SRC:-$DEVKIT_DIR/shims/adb}"
T1="$DEVKIT_DIR/tests/gates/test_hardware_empty_serial.sh"
HOOK="$DEVKIT_DIR/hooks/hardware_safety_gate.sh"
TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }

P="$TMP/proj"; SH="$P/.agents/devkit/shims"; SDK="$TMP/sdk/platform-tools"
mkdir -p "$P" "$SH" "$TMP/bin" "$SDK" "$TMP/home/Library/Android/sdk"
printf '# máy cá nhân\nR58PHONE01\n0PHONE2\n' > "$P/.adb-denylist"
ln -s "$SDK" "$TMP/home/Library/Android/sdk/platform-tools"
[ -f "$SHIM_SRC" ] && { cp "$SHIM_SRC" "$SH/adb"; chmod +x "$SH/adb"; }
[ -f "$SH/adb" ] && SHIM_PATH="$SH:" || SHIM_PATH=""

# adb giả = "adb thật" của fixture: get-serialno chọn thiết bị như adb 37.0.1 (T1); lệnh khác ghi "RUN <serial đích> <argv>" và thoát 0.
cat > "$SDK/adb" <<'FAKE'
#!/bin/bash
printf 'ARGV %s\n' "$*" >> "$ADB_FAKE_LOG"
[ "${FAKE_FAIL-}" = 1 ] && { echo "error: closed" >&2; exit 1; }
[ "${FAKE_HANG-}" = 1 ] && { sleep 12; exit 1; }
args=("$@"); serial="" sset=0 tid="" usb=0 tcp=0
while [ $# -gt 0 ]; do
  case "$1" in
    -s) serial="${2-}"; sset=1; shift 2 || shift ;;
    -s[0-9]*) serial="${1#-s}"; sset=1; shift ;;
    -t) tid="${2-}"; shift 2 || shift ;;
    -t[0-9]*) tid="${1#-t}"; shift ;;
    -d) usb=1; shift ;; -e) tcp=1; shift ;;
    -H) [ "${2-}" = localhost ] || { echo "error: cannot connect to daemon" >&2; exit 1; }; shift 2 ;;
    -P|-L) shift 2 || shift ;;
    -*) echo "adb: unknown command $1" >&2; exit 1 ;;
    *) break ;;
  esac
done
known() { case "$1" in emulator-5554|R58PHONE01|0PHONE2) echo "$1" ;; model:Phone) echo R58PHONE01 ;; model:Emu) echo emulator-5554 ;;
  *) echo "error: device '$1' not found" >&2; exit 1 ;; esac; }
dev() {
  if [ -n "$tid" ]; then case "$tid" in 1) echo emulator-5554 ;; 2) echo R58PHONE01 ;; *) return 1 ;; esac; return 0; fi
  if [ "$sset" = 1 ] && [ -n "$serial" ]; then known "$serial"; return; fi
  if [ "$sset" = 0 ]; then
    [ "$usb" = 1 ] && { echo R58PHONE01; return 0; }
    [ "$tcp" = 1 ] && { echo emulator-5554; return 0; }
    [ -n "${ANDROID_SERIAL-}" ] && { known "$ANDROID_SERIAL"; return; }
  fi
  echo "${FAKE_DEFAULT:-R58PHONE01}"
}
case "${1-}" in get-serialno) dev; exit ;; devices|version|kill-server|start-server|connect|disconnect) exit 0 ;; esac
d="$(dev)" || exit 1
printf 'RUN %s %s\n' "$d" "$*" >> "$ADB_FAKE_LOG"
exit 0
FAKE
chmod +x "$SDK/adb"
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/gh"; chmod +x "$TMP/bin/gh"   # gh thật không được đăng gì từ corpus

# run_cmd <lệnh> [VAR=giá trị …]: chạy THẬT bằng bash -c; log vào $LOG; stderr vào $TMP/err. PATH: shim, adb giả, PATH máy.
run_cmd() {
  local c="$1"; shift
  : > "$LOG"
  ( cd "$P" && env -u ANDROID_SERIAL -u ADB_DENY_SERIALS -u ADB_ALLOW_SERIALS -u BASH_ENV \
      PATH="$SHIM_PATH$SDK:$TMP/bin:$PATH" ADB_FAKE_LOG="$LOG" HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" \
      GIT_CEILING_DIRECTORIES="$TMP" SDK="$SDK" SDKADB="$SDK/adb" ANDROID_HOME="$TMP/sdk" "$@" \
      /bin/bash -c "$c" > "$TMP/out" 2> "$TMP/err" < /dev/null )
}
reached() { grep -q '^RUN \(R58PHONE01\|0PHONE2\) ' "$LOG"; }
LOG="$TMP/adb.log"; mkdir -p "$TMP/noadb"; NOADB="$TMP/noadb:/usr/bin:/bin"   # corpus T1 dùng $NOADB

# ── 1. corpus T1 ──
WANT=(); CMDS=(); ENVS=()
check() { WANT[${#WANT[@]}]="$1"; CMDS[${#CMDS[@]}]="$2"; shift 2; local e=""; for a in "$@"; do e="$e $(printf '%q' "$a")"; done; ENVS[${#ENVS[@]}]="$e"; }
first="$(grep -n '^echo "— serial rỗng' "$T1" | head -1 | cut -d: -f1)"
last="$(grep -n '^# adb giả chỉ được hỏi' "$T1" | head -1 | cut -d: -f1)"
[ -n "$first" ] && [ -n "$last" ] || { echo "FAIL: không thấy đoạn corpus trong $T1"; exit 1; }
echo() { :; }   # bỏ tiêu đề mục của T1 khi nạp
eval "$(sed -n "${first},$((last - 1))p" "$T1")"
unset -f echo
N=${#WANT[@]}
[ "$N" -ge 200 ] || fail "corpus T1 chỉ có $N ca (kỳ vọng ≥ 200: T1 đổi chỗ?)"

run_corpus() {   # in ra "<chạm phone> <chặn nhầm> <lọt ca phải chặn>"
  local i want reached_n=0 wrong=0 leak=0 envs
  for ((i = 0; i < N; i++)); do
    want="${WANT[$i]}"; envs=(); eval "envs=(${ENVS[$i]})"
    run_cmd "${CMDS[$i]}" ${envs[@]+"${envs[@]}"}
    local r=0; reached && r=1
    [ "$r" = 1 ] && reached_n=$((reached_n + 1))
    case "$want" in
      0) case " ${envs[*]-} " in *HARDWARE_OVERRIDE*) [ "$r" = 1 ] && { leak=$((leak + 1)); echo "  lọt: ${CMDS[$i]} [override không được nhận]"; } ;;
           *) grep -q 'adb-shim:' "$TMP/err" && { wrong=$((wrong + 1)); echo "  chặn nhầm: ${CMDS[$i]} — $(head -c 150 "$TMP/err" | tr '\n' ' ')"; } ;; esac ;;
      *) [ "$r" = 1 ] && { leak=$((leak + 1)); echo "  lọt: ${CMDS[$i]}"; } ;;
    esac
  done
  echo "$reached_n $wrong $leak"
}

if [ -f "$SH/adb" ]; then
  res="$(run_corpus)"; echo "$res" | grep -v '^[0-9]* [0-9]* [0-9]*$'
  set -- $(echo "$res" | tail -1)
  [ "$3" = 0 ] && ok "T1: $N ca chạy thật, không ca phải-chặn nào tới điện thoại bị cấm" || fail "T1: $3 ca lọt tới điện thoại"
  [ "$2" = 0 ] && ok "T1: ca hợp lệ không bị shim chặn nhầm" || fail "T1: $2 ca hợp lệ bị chặn nhầm"
else
  echo "ℹ không có shim: bỏ qua phần chạy với shim (chế độ RED)"
fi
# đối chứng: không shim ⇒ corpus tới được điện thoại (nếu không, test không phân biệt được shim)
SAVE_PATH="$SHIM_PATH"; SHIM_PATH=""
base="$(run_corpus | tail -1)"; set -- $base; SHIM_PATH="$SAVE_PATH"
[ "$1" -ge 85 ] && ok "đối chứng RED: không shim, $1/$N ca chạm điện thoại bị cấm" || fail "đối chứng: chỉ $1 ca chạm điện thoại khi không có shim (cần ≥ 85)"
[ -f "$SH/adb" ] || { echo "FAIL: test_adb_shim (không có shim: $FAILS)"; exit 1; }

# ── 2. 3 lỗi spike tự phát hiện + bất biến của shim ──
echo "— lỗi spike: mktemp lỗi, BASH_ENV / hàm export, -s \"\" trên bash 3.2"
printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/mktemp"; chmod +x "$TMP/bin/mktemp"
run_cmd 'adb -s "" reboot' TMPDIR=/nonexistent; reached && fail "mktemp lỗi: lệnh tới điện thoại (fail-open)" || ok "mktemp lỗi không fail-open (-s \"\" vẫn bị chặn)"
rm -f "$TMP/bin/mktemp"
printf 'read() { serial=emulator-5554; return 0; }\nget-serialno() { echo emulator-5554; }\n' > "$TMP/benv.sh"
run_cmd 'adb -s "" reboot' BASH_ENV="$TMP/benv.sh"; reached && fail "BASH_ENV ghi đè được shim" || ok "BASH_ENV không ghi đè được shim"
run_cmd 'read() { serial=emulator-5554; return 0; }; export -f read; adb -s "" reboot'; reached && fail "hàm export ghi đè được builtin của shim" || ok "hàm export (read) không ghi đè được shim"
run_cmd 'adb -s "" reboot'
grep -qx 'ARGV -s  get-serialno' "$LOG" && ok '-s "" tới adb thật nguyên vẹn (rỗng không rơi thành -s)' || fail '-s "" bị rơi phần tử rỗng: log = '"$(tr '\n' ';' < "$LOG")"
[ "$(/bin/bash -c 'echo ${BASH_VERSINFO[0]}')" = 3 ] && ok "chạy trên bash 3.2 của máy" || echo "ℹ /bin/bash không phải 3.2 ở máy này"
run_cmd 'adb -s emulator-5554 install a.apk'
grep -qx 'ARGV -s emulator-5554 install a.apk' "$LOG" && ok "adb thật nhận -s <serial đã kiểm>" || fail "adb thật không nhận -s đã kiểm: $(tr '\n' ';' < "$LOG")"
run_cmd 'adb -d -e -P 1 -s emulator-5554 shell ls'
reached && fail "-d / -e với -s hợp lệ tới điện thoại" || ok "-s literal thắng -d (như adb)"
run_cmd 'ANDROID_SERIAL=R58PHONE01 adb reboot'; reached && fail "ANDROID_SERIAL=phone lọt" || ok "ANDROID_SERIAL phone bị chặn"
run_cmd 'adb -s emulator-5554 reboot' ADB_DENY_SERIALS=emulator-5554; reached && fail "ADB_DENY_SERIALS không thêm được" || ok "env chỉ THÊM denylist"
run_cmd 'adb -s emulator-5554 reboot' ADB_ALLOW_SERIALS=zzz; reached && fail "allowlist env không chặn" || ok "env allowlist chặn serial ngoài danh sách"
run_cmd 'adb -s emulator-5554 reboot' XDG_CONFIG_HOME=/nonexistent ADB_DENY_SERIALS=; grep -q '^RUN emulator-5554 ' "$LOG" && ok "emulator đi qua khi env rỗng" || fail "emulator bị chặn nhầm"
run_cmd 'adb -s R58PHONE01 reboot' XDG_CONFIG_HOME=/nonexistent ADB_DENY_SERIALS= HARDWARE_OVERRIDE=1 HARDWARE_SAFETY_GATE=0; reached && fail "shim nhận cờ override từ env" || ok "HARDWARE_OVERRIDE / HARDWARE_SAFETY_GATE không tắt shim"
run_cmd 'adb devices; adb version; adb kill-server'; grep -q 'adb-shim:' "$TMP/err" && fail "lệnh host-only bị chặn" || ok "lệnh chỉ nói chuyện với server (devices …) không bị hỏi thiết bị"
run_cmd 'adb reboot' PATH="$SH"; [ "$?" = 2 ] && grep -q 'không tìm thấy adb thật' "$TMP/err" && ok "không có adb thật trong PATH: từ chối rõ ràng" || fail "thiếu adb thật không từ chối"

# ── 3. đường vòng ──
hook_rc() {   # chạy HOOK (chỉ đọc chuỗi) với lệnh $1
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$1" "$P" > "$TMP/in.json"
  ( cd "$P" && env -u ANDROID_SERIAL -u ADB_DENY_SERIALS -u ADB_ALLOW_SERIALS -u HARDWARE_OVERRIDE -u HARDWARE_SAFETY_GATE \
      PATH="$SDK:$PATH" XDG_CONFIG_HOME="$TMP/xdg" CLAUDE_PROJECT_DIR="$P" bash "$HOOK" < "$TMP/in.json" > /dev/null 2> "$TMP/herr" )
}
PH='-s R58PHONE01 reboot'
echo "— 10 dạng chạy qua PATH: shim chặn cả 10 (hook đọc chuỗi: cột ghi lại)"
printf '#!/bin/bash\nadb %s\n' "$PH" > "$P/s.sh"; touch "$P/x"
printf 'all:\n\tadb %s\n' "$PH" > "$P/mk"
via_path() {   # id, hook(block|pass), lệnh
  local id="$1" hk="$2" c="$3" h
  run_cmd "$c"; reached && fail "$id: tới điện thoại dù chạy qua PATH: $c"
  hook_rc "$c"; h=$?; [ "$h" = 2 ] && h=block || h=pass
  [ "$h" = "$hk" ] && ok "$id: shim chặn; hook $h  — $c" || fail "$id: hook $h (ghi nhận $hk): $c"
}
via_path P01 pass 'bash s.sh'
via_path P02 pass "find . -name x -exec adb $PH \;"
command -v make >/dev/null 2>&1 && via_path P03 pass 'make -f mk' || ok "P03: make vắng, bỏ qua"
via_path P04 pass "\$(echo YWRi | base64 -d) $PH"
via_path P05 pass "eval \"a\"\"db $PH\""
via_path P06 pass "bash -c '\$\"adb\" $PH'"
via_path P07 block "echo x | xargs -I{} adb $PH"
via_path P08 block "nohup adb $PH"
via_path P09 pass "python3 -c \"import subprocess; subprocess.run(['adb','-s','R58PHONE01','reboot'])\""
via_path P10 block "env adb $PH"
echo "— 16 đường vòng KHÔNG qua PATH: RESIDUAL của shim (shim không thấy). Cột hook: chặn / lọt. Ca nào cả hai đều lọt là residual hở."
resid() {   # id, hook(block|pass), có-tới-phone(1|0), lệnh
  local id="$1" hk="$2" want="$3" c="$4" h r=0
  run_cmd "$c"; reached && r=1
  hook_rc "$c"; h=$?; [ "$h" = 2 ] && h=block || h=pass
  [ "$r" = "$want" ] && [ "$h" = "$hk" ] && ok "$id: residual shim=$([ "$r" = 1 ] && echo lọt || echo không-tới-phone) hook=$h  — $c" \
    || fail "$id: shim-tới-phone=$r (ghi nhận $want) hook=$h (ghi nhận $hk): $c"
}
resid B01 pass 1 "\$SDKADB $PH"
resid B02 block 1 "\$ANDROID_HOME/platform-tools/adb $PH"
resid B03 block 1 "$TMP/home/Library/Android/sdk/platform-tools/adb $PH"
resid B04 pass 1 "ADB=\$SDKADB; \$ADB $PH"
resid B05 block 1 "PATH=\$SDK:\$PATH adb $PH"
resid B06 block 1 "export PATH=\"\${PATH#*:}\"; adb $PH"
resid B07 block 1 "hash -p \$SDKADB adb; adb $PH"
resid B08 pass 1 "exec -a adb \$SDKADB $PH"
resid B09 block 1 "sh -c \"PATH=\$SDK; adb $PH\""
resid B10 block 1 "env -i PATH=\$SDK ADB_FAKE_LOG=\$ADB_FAKE_LOG adb $PH"
resid B11 pass 1 "python3 -c \"import subprocess,os; subprocess.run(['adb','-s','R58PHONE01','reboot'],env={'PATH':os.environ['SDK'],'ADB_FAKE_LOG':os.environ['ADB_FAKE_LOG']})\""
resid B12 block 1 "adb() { \$SDKADB \"\$@\"; }; adb $PH"
resid B13 pass 1 "ln -sf \$SDKADB ./y; ./y $PH"
resid B14 pass 1 "\$(type -ap adb | sed -n 2p) $PH"
resid B15 block 0 "command -p adb $PH"   # adb không có trong PATH mặc định của máy: không tới phone ở máy này
resid B16 block 1 "cd \$SDK && ./adb $PH"

echo "— cài: hook SessionStart (session_context.sh) ghi PATH có shim vào \$CLAUDE_ENV_FILE"
EF="$TMP/envfile"; : > "$EF"
sess() { ( cd "$P" && env CLAUDE_ENV_FILE="$EF" CLAUDE_PROJECT_DIR="$P" "$@" /bin/bash "$DEVKIT_DIR/hooks/session_context.sh" < /dev/null > /dev/null 2>&1 ); }
sess; sess
[ "$(grep -c "$SH" "$EF")" = 1 ] && ok "SessionStart ghi đúng một dòng export PATH (chạy hai lần không lặp)" || fail "env file: $(cat "$EF")"
[ "$(env PATH="/usr/bin:/bin" /bin/bash -c ". '$EF'; command -v adb")" = "$SH/adb" ] && ok "sau khi nạp env file, adb trong PATH là shim" || fail "adb không phải shim sau khi nạp env file"
: > "$EF"; sess ADB_SHIM=0; [ ! -s "$EF" ] && ok "ADB_SHIM=0 không ghi PATH" || fail "ADB_SHIM=0 vẫn ghi PATH"

echo
if [ "$FAILS" -eq 0 ]; then echo "PASS: test_adb_shim"; exit 0; fi
echo "FAIL: test_adb_shim ($FAILS)"; exit 1
