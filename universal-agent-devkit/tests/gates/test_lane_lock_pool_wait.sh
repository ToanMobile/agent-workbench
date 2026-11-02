#!/usr/bin/env bash
# Test hồi quy (#849, mở rộng 02/11): bin/lane_lock.py nhả slot lane khi lệnh bên trong (hay hậu duệ) đang CHỜ pool gate của heavy_slot.
#   P0. lane_lock.py và heavy_slot.py chạy là bản trong CHÍNH checkout chứa test (INSTINCT-057)
#   P1. A giữ slot lane duy nhất, cháu của A chờ pool gate (đã đầy) ⇒ A nhả slot, B lấy được trong ≤ 15 s khi cháu vẫn chờ
#   P2. cháu gọi setsid (khác nhóm tiến trình) ⇒ vẫn nhận ra qua chuỗi ppid
#   P3. không deadlock: pool gate trống ra khi B giữ slot ⇒ cháu của A vào pool, A xong rc 0 trước khi B xong
#   P4. A xong không xoá file .owner của B      P5. B giữ slot ⇒ C chờ (không quá LANE_LOCK_SLOTS việc chạy thật)
#   P6. vé chờ của tiến trình KHÔNG phải hậu duệ ⇒ A giữ slot
#   P7. vé wait_s 0 (thăm dò chỗ trống của gate) hay vé còn non (< LANE_LOCK_POOL_WAIT_S) ⇒ A giữ slot; vé chết không bị lane_lock xoá
#   P8. TERM cho A sau khi nhả ⇒ rc 143, cháu chết theo nhóm, không để lại owner của A
#   P9. không file mới trong LANE_LOCK_DIR
# Mỗi ca dùng LANE_LOCK_DIR / SB_HEAVY_SLOT_DIR riêng (mktemp -d), 1 slot lane, tải giả 3, pool gate 1 slot bị một tiến trình giữ.
# Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LL_PY="${DEVKIT_DIR}/bin/lane_lock.py"
HS_BIN="${DEVKIT_DIR}/bin"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/lanelockpool.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
TMP="$(cd "${TMP}" && pwd -P)"
cleanup() {
  local f
  : > "${TMP}/release" 2>/dev/null
  for f in "${TMP}"/*.pid "${TMP}"/*.wpid; do [ -f "${f}" ] && kill "$(cat "${f}")" 2>/dev/null; done
  rm -rf "${TMP}"
}
trap cleanup EXIT
for v in $(env | sed -n 's/^\(LANE_LOCK_[A-Z_]*\)=.*/\1/p'); do unset "${v}"; done   # núm của người gọi không lọt vào ca
unset DEVKIT_SLOT_LOAD_MAX SB_HEAVY_SLOT_HELD DEVKIT_GATE_SLOT_HELD DEVKIT_SLOT_PRIORITY CLAUDE_PROJECT_DIR TARGET_DIR
export LANE_LOCK_SLOTS=1 LANE_LOCK_POLL_S=0.1 LANE_LOCK_GRACE_S=0.2 LANE_LOCK_POOL_POLL_S=0.3 LANE_LOCK_POOL_WAIT_S=1 \
       DEVKIT_SLOT_LOAD_FILE="${TMP}/load" SB_HEAVY_SLOT_POLL_S=0.1
printf '3\n' > "${TMP}/load"
lt() { python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) < float(sys.argv[2]) else 1)' "$1" "$2"; }   # $1 < $2
val() { cat "${TMP}/$1" 2>/dev/null || echo 0; }
# đợi file $1 có nội dung tối đa $2 giây
has_in() { local i=0 lim; lim="$(python3 -c "print(int(float('$2') * 20))")"
  while [ ! -s "${TMP}/$1" ] && [ "${i}" -lt "${lim}" ]; do sleep 0.05; i=$((i + 1)); done; [ -s "${TMP}/$1" ]; }
# đợi tiến trình nền <tên> thoát tối đa $2 giây; ghi <tên>.rc (124 khi quá giờ, tiến trình bị kill)
wait_job() { local p i=0 lim; p="$(cat "${TMP}/$1.pid" 2>/dev/null)"; [ -n "${p}" ] || return 0
  lim="$(python3 -c "print(int(float('${2:-20}') * 20))")"
  while kill -0 "${p}" 2>/dev/null && [ "${i}" -lt "${lim}" ]; do sleep 0.05; i=$((i + 1)); done
  if kill -0 "${p}" 2>/dev/null; then kill -9 "${p}" 2>/dev/null; wait "${p}" 2>/dev/null; echo 124 > "${TMP}/$1.rc"
  else wait "${p}" 2>/dev/null; echo $? > "${TMP}/$1.rc"; fi
  rm -f "${TMP}/$1.pid"; }

# 0. đúng bản: lane_lock.py nằm trong checkout của test; heavy_slot mà lane_lock và cháu nạp cũng của checkout đó
top="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)"
if [ -n "${top}" ]; then top="$(cd "${top}" 2>/dev/null && pwd -P)"; fi
[ -n "${top}" ] || top="/không-có-checkout"
loaded="$(python3 -c 'import importlib.util as u, os, sys
s = u.spec_from_file_location("lane_lock_probe", sys.argv[1]); m = u.module_from_spec(s); s.loader.exec_module(m)
print(os.path.realpath(m.__file__), os.path.realpath(m.heavy_slot.__file__))' "${LL_PY}" 2>/dev/null)"
case "${loaded}" in
  "${top}"/*" ${top}"/*) ok "0. lane_lock.py + heavy_slot.py của checkout chứa test: ${loaded}" ;;
  *) bad "0. lane_lock.py / heavy_slot.py không thuộc checkout của test" "nạp ${loaded:-?}, checkout ${top:-?}" ;;
esac

# cháu chờ pool gate bằng heavy_slot.acquire_pool THẬT của checkout (đường dẫn tường minh, không qua sys.path của main)
cat > "${TMP}/waiter.py" <<'PY'
import os, sys, time
sys.path.insert(0, sys.argv[1])
import heavy_slot as hs
p, setsid = sys.argv[2], sys.argv[3] == "1"
if setsid:
    os.setsid()
open(p + ".wpid", "w").write(str(os.getpid()))
h = hs.acquire_pool("gate", hs.pool_paths("gate", 1), wait_s=float(os.environ.get("W_WAIT", "60")), label="lanelockpool")
open(p + ".inpool", "w").write(repr(time.time()) + (" timeout" if h.timed_out else ""))
time.sleep(0.3)
hs.release_pool(h)
open(p + ".end", "w").write(repr(time.time()))
PY
# tiến trình giữ slot duy nhất của pool gate tới khi có file release
cat > "${TMP}/holder.py" <<'PY'
import os, sys, time
sys.path.insert(0, sys.argv[1])
import heavy_slot as hs
fh = hs._try_lock_path(hs.pool_paths("gate", 1)[0])
open(sys.argv[2], "w").write("held" if fh else "busy")
while not os.path.exists(sys.argv[3]):
    time.sleep(0.05)
hs._unlock(fh)
PY
cat > "${TMP}/job.py" <<'PY'
import os, time
p = os.environ["JOB_P"]
open(p + ".start", "w").write(repr(time.time()))
time.sleep(float(os.environ.get("JOB_DUR", "0.2")))
open(p + ".end", "w").write(repr(time.time()))
PY
# vé giả của chính tiến trình con: wait_s 0 (như _gate_pool_has_room của gate); thêm một vé của PID đã chết
cat > "${TMP}/fake_ticket.py" <<'PY'
import json, os, sys, time
q = os.path.join(os.environ["SB_HEAVY_SLOT_DIR"], "queue", "gate")
os.makedirs(q, exist_ok=True)
mine = os.path.join(q, "%d-000000000001.json" % os.getpid())
# t0 lùi 10 s: đủ tuổi (> LANE_LOCK_POOL_WAIT_S 1) mà ticket_alive vẫn sống (≤ wait_s + 60) ⇒ chỉ luật wait_s > 0 loại được vé này
json.dump({"pid": os.getpid(), "prio": "interactive", "est_s": 600.0, "t0": time.time() - 10, "wait_s": 0.0,
           "label": "probe", "cont": False}, open(mine, "w"))
open(sys.argv[1] + ".start", "w").write(repr(time.time()))
time.sleep(3)
os.remove(mine)
open(sys.argv[1] + ".end", "w").write(repr(time.time()))
PY

# fresh <ca>: thư mục khoá riêng cho ca; holder: chiếm pool gate; ll <tên> <lệnh…>: lane_lock nền
fresh() { export LANE_LOCK_DIR="${TMP}/$1/locks" SB_HEAVY_SLOT_DIR="${TMP}/$1/heavy"; mkdir -p "${SB_HEAVY_SLOT_DIR}"; rm -f "${TMP}/release"; }
holder() { rm -f "${TMP}/held" "${TMP}/release"; python3 "${TMP}/holder.py" "${HS_BIN}" "${TMP}/held" "${TMP}/release" & echo $! > "${TMP}/holder.pid"
  has_in held 5 && [ "$(val held)" = held ]; }
unhold() { : > "${TMP}/release"; wait_job holder 5; }
ll() { local n="$1"; shift; ( exec python3 "${LL_PY}" "${n}" -- "$@" ) > "${TMP}/${n}.log" 2>&1 & echo $! > "${TMP}/${n}.pid"; }
waiter_cmd() { echo "python3 '${TMP}/waiter.py' '${HS_BIN}' '${TMP}/$1' '$2'; true"; }
job() { local n="$1" d="$2"; shift 2; ( JOB_P="${TMP}/${n}" JOB_DUR="${d}" exec python3 "${LL_PY}" "${n}" -- python3 "${TMP}/job.py" ) \
  > "${TMP}/${n}.log" 2>&1 & echo $! > "${TMP}/${n}.pid"; }
log1() { tr '\n' ' ' < "${TMP}/$1.log" 2>/dev/null | cut -c1-240; }

# P1–P5: A chờ pool gate ⇒ nhả slot; B lấy slot; C chờ B; pool trống ⇒ A xong trước B; owner của B còn nguyên
fresh p1
if holder; then
  ll A bash -c "$(waiter_cmd A 0)"
  if has_in A.wpid 5; then
    job B 8
    if has_in B.start 15 && [ ! -s "${TMP}/A.inpool" ]; then ok "1. A chờ pool gate ⇒ nhả slot lane, B lấy được khi cháu A vẫn chờ"
    else bad "1. B không lấy được slot khi A chờ pool gate" "B start $(val B.start), A inpool $(val A.inpool); A: $(log1 A)"; fi
    if grep -q 'nhả slot lane' "${TMP}/A.log"; then ok "1b. log của A ghi nhả slot lane"; else bad "1b. log A không ghi nhả slot lane" "$(log1 A)"; fi
    if [ -s "${TMP}/B.start" ]; then
      job C 0.2
      sleep 2   # vé của cháu A còn đó: bản sai (nhả vì vé không phải hậu duệ) sẽ để B nhả slot, C chạy chồng
      unhold
      wait_job A 10
      if [ "$(val A.rc)" = 0 ] && [ -s "${TMP}/A.end" ] && [ ! -s "${TMP}/B.end" ]; then ok "3. không deadlock: cháu A vào pool, A xong rc 0 khi B còn giữ slot"
      else bad "3. A không xong khi B giữ slot" "A rc $(val A.rc), A end $(val A.end), B end $(val B.end)"; fi
      if grep -q '^B ' "${LANE_LOCK_DIR}/lane-1.owner" 2>/dev/null; then ok "4. A xong không xoá owner của B"
      else bad "4. owner của B mất / sai sau khi A xong" "$(cat "${LANE_LOCK_DIR}/lane-1.owner" 2>/dev/null || echo không-có)"; fi
      wait_job B 15; wait_job C 15
      if [ "$(val C.start)" != 0 ] && [ "$(val B.end)" != 0 ] && ! lt "$(val C.start)" "$(val B.end)"; then ok "5. C chỉ chạy sau khi B nhả (không quá 1 việc chạy thật)"
      else bad "5. C chạy chồng B" "B end $(val B.end), C start $(val C.start)"; fi
    else
      bad "3–5. bỏ qua: B chưa từng lấy được slot (ca 1 hỏng)"
    fi
  else bad "1. cháu của A không chạy" "$(log1 A)"; fi
else bad "1. không chiếm được pool gate cho fixture"; fi
unhold; wait_job A 5; wait_job B 5; wait_job C 5
# 9 (một phần): sau ca, thư mục khoá chỉ còn file khoá
left="$(ls -A "${LANE_LOCK_DIR}" 2>/dev/null | tr '\n' ' ')"
if [ "${left}" = "lane-1.lock " ]; then ok "9. không file khoá / owner sót trong LANE_LOCK_DIR"; else bad "9. LANE_LOCK_DIR còn file lạ" "${left}"; fi

# P2: cháu gọi setsid (khác nhóm) ⇒ vẫn là hậu duệ qua chuỗi ppid
fresh p2
if holder; then
  ll A2 bash -c "$(waiter_cmd A2 1)"
  if has_in A2.wpid 5; then
    job B2 0.2
    if has_in B2.start 15; then ok "2. cháu setsid vẫn được nhận ra (chuỗi ppid) ⇒ nhả slot"
    else bad "2. cháu setsid chờ pool mà A2 vẫn giữ slot" "$(log1 A2)"; fi
  else bad "2. cháu của A2 không chạy" "$(log1 A2)"; fi
fi
unhold; wait_job A2 10; wait_job B2 10

# P6: vé chờ của tiến trình KHÔNG phải hậu duệ ⇒ A6 giữ slot
fresh p6
if holder; then
  python3 "${TMP}/waiter.py" "${HS_BIN}" "${TMP}/W6" 0 > /dev/null 2>&1 & echo $! > "${TMP}/W6.pid"
  has_in W6.wpid 5 >/dev/null
  job A6 4; has_in A6.start 5 >/dev/null; job B6 0.2
  sleep 2.5   # vé của W6 còn sống trong lúc A6 chạy: đủ để bản sai nhả slot (POOL_POLL 0.3 + WAIT 1)
fi
unhold; wait_job W6 10; wait_job A6 10; wait_job B6 10
# ca phủ định so MỐC GIỜ (B bắt đầu sau khi A xong), không đếm vòng chờ: dưới tải cao vòng sleep 0.05 dài hơn 0.05 s
if ! grep -q 'nhả slot lane' "${TMP}/A6.log" && [ "$(val B6.start)" != 0 ] && [ "$(val A6.end)" != 0 ] && ! lt "$(val B6.start)" "$(val A6.end)"
then ok "6. vé chờ của tiến trình lạ ⇒ A6 giữ slot"
else bad "6. A6 nhả slot vì vé của tiến trình lạ" "A6 end $(val A6.end), B6 start $(val B6.start); $(log1 A6)"; fi

# P7a: vé wait_s 0 của chính con ⇒ giữ slot; vé của PID chết không bị lane_lock xoá (chỉ đọc)
fresh p7a
mkdir -p "${SB_HEAVY_SLOT_DIR}/queue/gate"
dead="${SB_HEAVY_SLOT_DIR}/queue/gate/999999-0000000000ff.json"
printf '{"pid": 999999, "prio": "interactive", "est_s": 600.0, "t0": 1.0, "wait_s": 60.0, "label": "dead", "cont": false}\n' > "${dead}"
ll A7 python3 "${TMP}/fake_ticket.py" "${TMP}/A7"; has_in A7.start 5 >/dev/null; job B7 0.2
wait_job A7 10; wait_job B7 10
if ! grep -q 'nhả slot lane' "${TMP}/A7.log" && [ "$(val B7.start)" != 0 ] && [ "$(val A7.end)" != 0 ] && ! lt "$(val B7.start)" "$(val A7.end)"
then ok "7a. vé wait_s 0 (thăm dò chỗ trống) ⇒ A7 giữ slot"
else bad "7a. vé wait_s 0 làm A7 nhả slot" "A7 end $(val A7.end), B7 start $(val B7.start); $(log1 A7)"; fi
if [ -f "${dead}" ]; then ok "7c. lane_lock chỉ đọc vé (vé PID chết còn nguyên)"; else bad "7c. lane_lock xoá vé trong hàng đợi"; fi

# P7b: vé còn non (LANE_LOCK_POOL_WAIT_S=30) ⇒ giữ slot
fresh p7b
if holder; then
  ( LANE_LOCK_POOL_WAIT_S=30 exec python3 "${LL_PY}" A7b -- bash -c "$(waiter_cmd A7b 0)" ) > "${TMP}/A7b.log" 2>&1 & echo $! > "${TMP}/A7b.pid"
  has_in A7b.wpid 5 >/dev/null; job B7b 0.2
  sleep 2.5   # đủ để bản sai nhả slot (POOL_POLL 0.3 + WAIT 1) trước khi pool gate trống ra
fi
unhold; wait_job A7b 10; wait_job B7b 10
if ! grep -q 'nhả slot lane' "${TMP}/A7b.log" && [ "$(val B7b.start)" != 0 ] && [ "$(val A7b.end)" != 0 ] && ! lt "$(val B7b.start)" "$(val A7b.end)"
then ok "7b. vé còn non ⇒ A7b giữ slot"
else bad "7b. vé chờ chưa đủ LANE_LOCK_POOL_WAIT_S mà A7b đã nhả" "A7b end $(val A7b.end), B7b start $(val B7b.start); $(log1 A7b)"; fi

# P8: TERM cho A8 sau khi nhả ⇒ rc 143, cháu chết theo nhóm, owner còn là của B8
fresh p8
if holder; then
  ll A8 bash -c "$(waiter_cmd A8 0)"
  if has_in A8.wpid 5 && { job B8 8; has_in B8.start 15; }; then
    kill -TERM "$(cat "${TMP}/A8.pid")"; wait_job A8 8
    wpid="$(val A8.wpid)"; i=0; while kill -0 "${wpid}" 2>/dev/null && [ "${i}" -lt 40 ]; do sleep 0.05; i=$((i + 1)); done
    if [ "$(val A8.rc)" = 143 ] && ! kill -0 "${wpid}" 2>/dev/null; then ok "8. TERM sau khi nhả: rc 143, cháu chết theo nhóm"
    else bad "8. TERM sau khi nhả sai" "rc $(val A8.rc), cháu ${wpid} còn sống: $(kill -0 "${wpid}" 2>/dev/null && echo có || echo không)"; fi
    if grep -q '^B8 ' "${LANE_LOCK_DIR}/lane-1.owner" 2>/dev/null; then ok "8b. owner vẫn của B8 (A8 không để lại / xoá owner)"
    else bad "8b. owner sai sau khi A8 bị TERM" "$(cat "${LANE_LOCK_DIR}/lane-1.owner" 2>/dev/null || echo không-có)"; fi
  else bad "8. không dựng được ca (A8 chờ pool, B8 lấy slot)" "$(log1 A8)"; fi
fi
unhold; wait_job A8 5; wait_job B8 15

echo
if [ "${fails}" -eq 0 ]; then echo "test_lane_lock_pool_wait: tất cả XANH"; exit 0; fi
echo "test_lane_lock_pool_wait: ${fails} ca ĐỎ"; exit 1
