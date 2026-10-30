#!/usr/bin/env bash
# Test hồi quy (#716): bin/lane_lock.py — khoá lane cho việc nặng của phiên điều phối, số slot theo tải (DEVKIT_SLOT_LOAD_FILE giả):
#   1. tải 3: hai việc chạy chồng thời gian (2 slot)            2. tải 15: việc thứ hai chờ việc đầu xong (1 slot)
#   3. tải 30: không bắt đầu cho tới khi tải xuống 5          4. tải 15 sau khi 2 việc đã chạy: việc mới chờ tới khi KHÔNG còn ai giữ
#   5. wrapper bị kill -9: slot được thu hồi ngay (flock)      6. exit của lệnh = exit wrapper, log [lock] giữ / nhả khoá rc=
#   7. TERM gửi wrapper: con nhận TERM, wrapper thoát, slot nhả ngay   8. <tên> -- <lệnh>: bỏ dấu --
# LANE_LOCK_CMD (mặc định python3 bin/lane_lock.py): lượt RED của người viết trỏ vào with_lane_lock.sh cũ (mkdir, 1 slot, không xét tải).
# Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LL="${LANE_LOCK_CMD:-python3 ${DEVKIT_DIR}/bin/lane_lock.py}"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/lanelock.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
TMP="$(cd "${TMP}" && pwd)"
cleanup() {
  local f
  for f in "${TMP}"/*.pid "${TMP}"/*.jobpid; do [ -f "${f}" ] && kill "$(cat "${f}")" 2>/dev/null; done
  rm -rf "${TMP}"
}
trap cleanup EXIT
# núm của người gọi (LANE_LOCK_SLOTS, _LOAD_TWO, _LOAD_MAX, _GRACE_S…) không được lọt vào ca: test tự đặt mọi núm nó cần
for v in $(env | sed -n 's/^\(LANE_LOCK_[A-Z_]*\)=.*/\1/p'); do [ "${v}" = LANE_LOCK_CMD ] || unset "${v}"; done
export LANE_LOCK_DIR="${TMP}/locks" LANE_LOCK_POLL_S=0.1 DEVKIT_SLOT_LOAD_FILE="${TMP}/load"
load() { printf '%s\n' "$1" > "${TMP}/load"; }
now() { python3 -c 'import time; print(repr(time.time()))'; }
lt() { python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) < float(sys.argv[2]) else 1)' "$1" "$2"; }   # $1 < $2
val() { cat "${TMP}/$1" 2>/dev/null || echo 0; }

# việc giả: ghi giờ bắt đầu / kết thúc, pid của mình; TERM ⇒ ghi file .term rồi thoát 143; exit = đối số 3
cat > "${TMP}/job.py" <<'PY'
import os, signal, sys, time
p, dur = sys.argv[1], float(sys.argv[2])
def term(*_):
    open(p + ".term", "w").write("1"); sys.exit(143)
signal.signal(signal.SIGTERM, term)
open(p + ".jobpid", "w").write(str(os.getpid()))
open(p + ".start", "w").write(repr(time.time()))
time.sleep(dur)
open(p + ".end", "w").write(repr(time.time()))
sys.exit(int(sys.argv[3]) if len(sys.argv) > 3 else 0)
PY
job() { # tên thời_lượng [exit] — chạy nền dưới lane lock, pid wrapper vào $TMP/<tên>.pid, log vào $TMP/<tên>.log
  ${LL} "$1" python3 "${TMP}/job.py" "${TMP}/$1" "$2" ${3:+"$3"} > "${TMP}/$1.log" 2>&1 &
  echo $! > "${TMP}/$1.pid"
}
wait_job() { local p; p="$(cat "${TMP}/$1.pid")"; wait "${p}" 2>/dev/null; echo $? > "${TMP}/$1.rc"; rm -f "${TMP}/$1.pid"; }
started() { local i=0; while [ ! -s "${TMP}/$1.start" ] && [ "${i}" -lt 200 ]; do sleep 0.05; i=$((i + 1)); done; }   # chờ việc đã giữ khoá (≤ 10 s)
overlap() { python3 -c 'import sys; a, b, c, d = map(float, sys.argv[1:]); sys.exit(0 if max(a, c) < min(b, d) else 1)' "$@"; }   # sa ea sb eb

# 1. tải thấp: 2 slot ⇒ hai khoảng chạy chồng nhau (max bắt đầu < min kết thúc), cả hai rc 0
load 3; job A1 2; started A1; job B1 2; wait_job A1; wait_job B1
if [ "$(val A1.rc)" = 0 ] && [ "$(val B1.rc)" = 0 ] && overlap "$(val A1.start)" "$(val A1.end)" "$(val B1.start)" "$(val B1.end)"; then
  ok "1. tải 3: hai việc nặng chạy song song (2 slot)"
else bad "1. tải 3: hai việc không chạy song song" "A1 $(val A1.start)–$(val A1.end) rc $(val A1.rc), B1 $(val B1.start)–$(val B1.end) rc $(val B1.rc)"; fi

# 2. tải 12–24: 1 slot ⇒ A giữ khoá rồi mới gọi B; B bắt đầu sau khi A xong
load 15; job A2 1.5; started A2; job B2 0.3; wait_job A2; wait_job B2
if [ "$(val B2.start)" != 0 ] && ! overlap "$(val A2.start)" "$(val A2.end)" "$(val B2.start)" "$(val B2.end)"; then ok "2. tải 15: việc thứ hai chờ việc đầu xong (1 slot)"
else bad "2. tải 15: hai việc chạy chồng nhau" "A2 $(val A2.start)–$(val A2.end), B2 $(val B2.start)–$(val B2.end)"; fi

# 3. tải ≥ 24: không bắt đầu tới khi tải xuống
load 30; job A3 0.2; sleep 1.2; t_down="$(now)"; load 5; wait_job A3
if [ "$(val A3.rc)" = 0 ] && ! lt "$(val A3.start)" "${t_down}" && [ "$(val A3.start)" != 0 ]; then ok "3. tải 30: chờ tới khi tải xuống rồi mới chạy"
else bad "3. tải 30: việc nặng bắt đầu khi tải còn cao" "start $(val A3.start), tải xuống lúc ${t_down}"; fi

# 4. A (slot 1, ngắn) rồi B (slot 2, dài) ở tải 3; A xong ⇒ slot 1 trống trong lúc B còn giữ slot 2; tải lên 15: C chỉ chạy khi KHÔNG còn ai giữ
load 3; job A4 1; started A4; job B4 3; started B4; wait_job A4; load 15; job C4 0.2; wait_job B4; wait_job C4
if [ "$(val C4.start)" != 0 ] && ! lt "$(val C4.start)" "$(val B4.end)"; then ok "4. tải lên 15: việc mới chờ tới khi không còn ai giữ slot nào"
else bad "4. tải 15: việc mới chạy khi slot 2 còn bị giữ" "B4 end $(val B4.end), C4 start $(val C4.start)"; fi

# 5. wrapper bị kill -9 khi đang giữ: slot thu hồi ngay, việc sau chạy được trong < 2 s
load 15; job A5 30; started A5
kill -9 "$(cat "${TMP}/A5.pid")" 2>/dev/null; wait "$(cat "${TMP}/A5.pid")" 2>/dev/null; rm -f "${TMP}/A5.pid"
kill "$(cat "${TMP}/A5.jobpid" 2>/dev/null)" 2>/dev/null   # con mồ côi của A5 (không giữ fd khoá): dọn cho test
t_kill="$(now)"; job B5 0.1; wait_job B5
if [ "$(val B5.start)" != 0 ] && lt "$(val B5.start)" "$(python3 -c "print(${t_kill} + 2)")"; then ok "5. kill -9 người giữ: slot thu hồi, việc sau chạy trong < 2 s"
else bad "5. kill -9: slot không được thu hồi kịp" "kill lúc ${t_kill}, B5 start $(val B5.start)"; fi

# 6. exit của lệnh truyền ra wrapper; log giữ / nhả khoá
load 3; job E6 0.1 7; wait_job E6
if [ "$(val E6.rc)" = 7 ] && grep -q '^\[lock\] E6 giữ khoá' "${TMP}/E6.log" && grep -q '^\[lock\] E6 nhả khoá rc=7' "${TMP}/E6.log"; then
  ok "6. exit 7 của lệnh ⇒ wrapper exit 7, log [lock] giữ khoá / nhả khoá rc=7"
else bad "6. exit hoặc log [lock] sai" "rc=$(val E6.rc) log: $(tr '\n' ' ' < "${TMP}/E6.log" | cut -c1-200)"; fi

# 7. TERM gửi wrapper: con nhận TERM, wrapper thoát, slot nhả ngay
load 15; job A7 30; started A7; t_term="$(now)"; kill -TERM "$(cat "${TMP}/A7.pid")"; wait_job A7
job D7 0.1; wait_job D7
if [ -e "${TMP}/A7.term" ] && [ "$(val A7.rc)" = 143 ] && [ "$(val D7.start)" != 0 ] && lt "$(val D7.start)" "$(python3 -c "print(${t_term} + 4)")"; then
  ok "7. TERM: con nhận TERM, wrapper thoát, slot nhả ngay"
else bad "7. TERM không tới con hoặc slot không nhả" "term=$([ -e "${TMP}/A7.term" ] && echo có || echo không) rc=$(val A7.rc) D7 start $(val D7.start)"; fi

# 8. dấu `--` trước lệnh được bỏ (cách gọi `lane_lock.py <tên> -- <lệnh…>`)
load 3; ${LL} F8 -- python3 "${TMP}/job.py" "${TMP}/F8" 0.1 > "${TMP}/F8.log" 2>&1; rc=$?
if [ "${rc}" = 0 ] && [ "$(val F8.start)" != 0 ]; then ok "8. <tên> -- <lệnh>: chạy đúng lệnh sau --"
else bad "8. dấu -- không được bỏ" "rc=${rc} log: $(tr '\n' ' ' < "${TMP}/F8.log" | cut -c1-200)"; fi

echo
if [ "${fails}" -eq 0 ]; then echo "test_lane_lock: tất cả XANH"; exit 0; fi
echo "test_lane_lock: ${fails} FAIL"; exit 1
