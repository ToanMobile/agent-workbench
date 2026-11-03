#!/usr/bin/env bash
# Test hồi quy (P5, gate kẹt và chậm 02/11): bin/lane_lock.py nhả slot lane khi lệnh là super-board-merge-gate.sh và một HẬU DUỆ của nó
# đang chờ pool gate (vé queue/gate như #849) hoặc đang giữ slot pool gate (<slot_dir>/gate-*.lock.held ghi PID hậu duệ): phần còn lại
# của merge gate ngoài pool chỉ là git/gh. Lệnh khác giữ luật cũ (chỉ chính tiến trình con).
#   0. lane_lock.py và heavy_slot.py chạy là bản trong CHÍNH checkout chứa test (INSTINCT-057)
#   1. merge gate giả (argv[0]) có cháu giữ slot pool gate (.held) ⇒ nhả, lane B (LANE_LOCK_SLOTS=1) vào trước khi merge gate giả xong
#   2. `env K=V bash <…/super-board-merge-gate.sh>`, cháu chờ pool gate (vé queue/gate) ⇒ nhả; pool trống ra ⇒ A xong rc 0 (không deadlock)
#   3. cháu chỉ chờ pool heavy (vé queue/heavy) ⇒ giữ slot     4. `bash -c` bọc gate thường (cháu giữ .held) ⇒ giữ slot
#   5. .held của tiến trình KHÔNG phải hậu duệ ⇒ giữ slot       6. ps lỗi ⇒ giữ slot (fail closed), log đúng một lần
#   7. không file mới trong LANE_LOCK_DIR
# Mỗi ca dùng LANE_LOCK_DIR / SB_HEAVY_SLOT_DIR riêng (mktemp -d), 1 slot lane, tải giả 3. Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LL_PY="${DEVKIT_DIR}/bin/lane_lock.py"
HS_BIN="${DEVKIT_DIR}/bin"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/lanelockmg.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
TMP="$(cd "${TMP}" && pwd -P)"
cleanup() {
  local f
  : > "${TMP}/release" 2>/dev/null
  for f in "${TMP}"/*.pid "${TMP}"/*.gcpid; do [ -f "${f}" ] && kill "$(cat "${f}")" 2>/dev/null; done
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
# đợi file $1 có nội dung tối đa $2 giây (đếm vòng: chỉ dùng cho điều kiện dương)
has_in() { local i=0 lim; lim="$(python3 -c "print(int(float('$2') * 20))")"
  while [ ! -s "${TMP}/$1" ] && [ "${i}" -lt "${lim}" ]; do sleep 0.05; i=$((i + 1)); done; [ -s "${TMP}/$1" ]; }
# đợi tiến trình nền <tên> thoát tối đa $2 giây; ghi <tên>.rc (124 khi quá giờ, tiến trình bị kill)
wait_job() { local p i=0 lim; p="$(cat "${TMP}/$1.pid" 2>/dev/null)"; [ -n "${p}" ] || return 0
  lim="$(python3 -c "print(int(float('${2:-30}') * 20))")"
  while kill -0 "${p}" 2>/dev/null && [ "${i}" -lt "${lim}" ]; do sleep 0.05; i=$((i + 1)); done
  if kill -0 "${p}" 2>/dev/null; then kill -9 "${p}" 2>/dev/null; wait "${p}" 2>/dev/null; echo 124 > "${TMP}/$1.rc"
  else wait "${p}" 2>/dev/null; echo $? > "${TMP}/$1.rc"; fi
  rm -f "${TMP}/$1.pid"; }
log1() { tr '\n' ' ' < "${TMP}/$1.log" 2>/dev/null | cut -c1-240; }

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

# cháu: heavy_slot.acquire_pool THẬT của checkout. held: pool gate trống ⇒ lấy, ghi .held PID cháu; wait: chờ pool gate (vé queue/gate);
# heavy: chờ pool heavy (vé queue/heavy); sleep: không xin pool. Ghi <P>.gcpid, <P>.inpool, <P>.gcend.
cat > "${TMP}/gc.py" <<'PY'
import os, sys, time
sys.path.insert(0, sys.argv[1])
import heavy_slot as hs
p, mode, dur = sys.argv[2], sys.argv[3], float(sys.argv[4])
open(p + ".gcpid", "w").write(str(os.getpid()))
h = None
if mode in ("held", "wait"):
    h = hs.acquire_pool("gate", hs.pool_paths("gate", 1), wait_s=60, label="lanelockmg")
elif mode == "heavy":
    h = hs.acquire_pool("heavy", hs.pool_paths("heavy", 1), wait_s=60, label="lanelockmg")
open(p + ".inpool", "w").write(repr(time.time()) + (" timeout" if h is not None and h.timed_out else ""))
time.sleep(dur)
if h is not None:
    hs.release_pool(h)
open(p + ".gcend", "w").write(repr(time.time()))
PY
# merge gate giả: đúng tên super-board-merge-gate.sh, bash chạy cháu python (không exec) rồi ghi <P>.end
mkdir -p "${TMP}/bin" "${TMP}/fakeps"
cat > "${TMP}/bin/super-board-merge-gate.sh" <<'SH'
#!/usr/bin/env bash
python3 "${MG_GC}" "${MG_HS}" "${MG_P}" "${MG_MODE}" "${MG_DUR:-6}"
python3 -c 'import time, sys; open(sys.argv[1], "w").write(repr(time.time()))' "${MG_P}.end"
SH
chmod +x "${TMP}/bin/super-board-merge-gate.sh"
MG="${TMP}/bin/super-board-merge-gate.sh"
printf '#!/bin/sh\necho "ps: giả lỗi" >&2\nexit 1\n' > "${TMP}/fakeps/ps"; chmod +x "${TMP}/fakeps/ps"
# tiến trình giữ slot duy nhất của pool <pool> (flock, không .held) tới khi có file release
cat > "${TMP}/holder.py" <<'PY'
import os, sys, time
sys.path.insert(0, sys.argv[1])
import heavy_slot as hs
fh = hs._try_lock_path(hs.pool_paths(sys.argv[4], 1)[0])
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

# fresh <ca>: thư mục khoá riêng cho ca; holder <pool>: chiếm pool; mg <tên> <chế độ> <giây> <lệnh…>: lane_lock nền chạy lệnh với env MG_*
fresh() { export LANE_LOCK_DIR="${TMP}/$1/locks" SB_HEAVY_SLOT_DIR="${TMP}/$1/heavy"; mkdir -p "${SB_HEAVY_SLOT_DIR}"; rm -f "${TMP}/release"; }
holder() { rm -f "${TMP}/held" "${TMP}/release"; python3 "${TMP}/holder.py" "${HS_BIN}" "${TMP}/held" "${TMP}/release" "$1" & echo $! > "${TMP}/holder.pid"
  has_in held 5 && [ "$(val held)" = held ]; }
unhold() { : > "${TMP}/release"; wait_job holder 5; }
mg() { local n="$1" m="$2" d="$3"; shift 3
  ( MG_GC="${TMP}/gc.py" MG_HS="${HS_BIN}" MG_P="${TMP}/${n}" MG_MODE="${m}" MG_DUR="${d}" exec python3 "${LL_PY}" "${n}" -- "$@" ) \
    > "${TMP}/${n}.log" 2>&1 & echo $! > "${TMP}/${n}.pid"; }
job() { ( JOB_P="${TMP}/$1" JOB_DUR="$2" exec python3 "${LL_PY}" "$1" -- python3 "${TMP}/job.py" ) > "${TMP}/$1.log" 2>&1 & echo $! > "${TMP}/$1.pid"; }
only_lock() { local left; left="$(ls -A "${LANE_LOCK_DIR}" 2>/dev/null | tr '\n' ' ')"; [ "${left}" = "lane-1.lock " ] || bad "7. $1: LANE_LOCK_DIR còn file lạ" "${left}"; }
# kept <ca> <A> <B> <mốc xong của lệnh A>: A giữ slot (không nhả) và B chỉ bắt đầu sau khi lệnh của A xong
kept() { if ! grep -q 'nhả slot lane' "${TMP}/$2.log" && [ "$(val "$3.start")" != 0 ] && [ "$(val "$4")" != 0 ] && ! lt "$(val "$3.start")" "$(val "$4")"
  then return 0; fi; return 1; }

# 1. merge gate giả (argv[0]) có cháu giữ slot pool gate (.held ghi PID cháu) ⇒ nhả; B vào khi merge gate giả còn chạy
fresh m1
mg A1 held 8 "${MG}"
if has_in A1.inpool 10; then
  job B1 0.2
  has_in B1.start 15 >/dev/null
  wait_job A1; wait_job B1
  if [ "$(val B1.start)" != 0 ] && [ "$(val A1.end)" != 0 ] && lt "$(val B1.start)" "$(val A1.end)" && grep -q 'nhả slot lane' "${TMP}/A1.log"; then
    ok "1. merge gate có cháu giữ slot pool gate ⇒ nhả slot lane, B vào trước khi merge gate xong"
  else bad "1. merge gate có cháu trong pool gate mà vẫn giữ slot lane" "B1 start $(val B1.start), A1 end $(val A1.end); $(log1 A1)"; fi
  if [ "$(val A1.rc)" = 0 ]; then ok "1b. merge gate giả xong rc 0"; else bad "1b. merge gate giả rc $(val A1.rc)" "$(log1 A1)"; fi
else bad "1. cháu của merge gate giả không vào pool gate" "$(log1 A1)"; fi
wait_job A1 5; wait_job B1 5; only_lock m1

# 2. `env K=V bash <…/super-board-merge-gate.sh>`, cháu CHỜ pool gate (vé queue/gate) ⇒ nhả; pool trống ra ⇒ A xong rc 0
fresh m2
if holder gate; then
  mg A2 wait 0.3 env MG_X=1 bash "${MG}"
  if has_in A2.gcpid 10; then
    job B2 0.2
    if has_in B2.start 15 && [ ! -s "${TMP}/A2.inpool" ]; then ok "2. env … bash merge-gate, cháu chờ pool gate ⇒ nhả slot, B vào khi cháu còn chờ"
    else bad "2. cháu chờ pool gate mà merge gate vẫn giữ slot lane" "B2 start $(val B2.start), A2 inpool $(val A2.inpool); $(log1 A2)"; fi
  else bad "2. cháu của merge gate giả không chạy" "$(log1 A2)"; fi
  unhold; wait_job A2 20; wait_job B2 10
  if [ "$(val A2.rc)" = 0 ] && [ -s "${TMP}/A2.end" ]; then ok "2b. pool trống ra ⇒ merge gate giả xong rc 0 (không deadlock)"
  else bad "2b. merge gate giả không xong" "rc $(val A2.rc); $(log1 A2)"; fi
else bad "2. không chiếm được pool gate cho fixture"; fi
unhold; wait_job A2 5; wait_job B2 5; only_lock m2

# 3. cháu chỉ chờ pool HEAVY (vé queue/heavy) ⇒ giữ slot
fresh m3
if holder heavy; then
  mg A3 heavy 0.2 "${MG}"
  has_in A3.gcpid 10 >/dev/null; job B3 0.2
  sleep 2.5   # đủ để bản sai nhả slot (POOL_POLL 0.3 + WAIT 1)
else bad "3. không chiếm được pool heavy cho fixture"; fi
unhold; wait_job A3 20; wait_job B3 10
if kept m3 A3 B3 A3.end; then ok "3. cháu chỉ chờ pool heavy ⇒ merge gate giữ slot"
else bad "3. nhả slot vì vé queue/heavy" "A3 end $(val A3.end), B3 start $(val B3.start); $(log1 A3)"; fi
only_lock m3

# 4. `bash -c` bọc gate thường, cháu giữ slot pool gate (.held) ⇒ giữ slot (luật cũ: chỉ chính tiến trình con)
fresh m4
( exec python3 "${LL_PY}" A4 -- bash -c "python3 '${TMP}/gc.py' '${HS_BIN}' '${TMP}/A4' held 4; true" ) > "${TMP}/A4.log" 2>&1 &
echo $! > "${TMP}/A4.pid"
has_in A4.inpool 10 >/dev/null; job B4 0.2
wait_job A4 20; wait_job B4 10
if kept m4 A4 B4 A4.gcend; then ok "4. bash -c bọc gate thường (cháu giữ .held) ⇒ giữ slot"
else bad "4. bash -c bọc gate thường mà nhả slot" "A4 gcend $(val A4.gcend), B4 start $(val B4.start); $(log1 A4)"; fi
only_lock m4

# 5. .held của tiến trình KHÔNG phải hậu duệ (W5 lấy pool gate SAU lúc merge gate được tạo: mtime mới) ⇒ merge gate giữ slot
fresh m5
mg A5 sleep 5 "${MG}"
if has_in A5.gcpid 10; then
  python3 "${TMP}/gc.py" "${HS_BIN}" "${TMP}/W5" held 8 > /dev/null 2>&1 & echo $! > "${TMP}/W5.pid"
  has_in W5.inpool 10 >/dev/null; job B5 0.2
  wait_job A5 20; wait_job B5 10
  if [ -s "${TMP}/W5.inpool" ] && kept m5 A5 B5 A5.end; then ok "5. .held mới của tiến trình lạ ⇒ merge gate giữ slot"
  else bad "5. nhả slot vì .held của tiến trình không phải hậu duệ" "W5 inpool $(val W5.inpool), A5 end $(val A5.end), B5 start $(val B5.start); $(log1 A5)"; fi
else bad "5. merge gate giả A5 không chạy" "$(log1 A5)"; fi
wait_job W5 15; only_lock m5

# 6. ps lỗi (ps giả trên PATH của lane_lock) ⇒ giữ slot, log lỗi đúng một lần dù thăm nhiều vòng
fresh m6
( PATH="${TMP}/fakeps:${PATH}" MG_GC="${TMP}/gc.py" MG_HS="${HS_BIN}" MG_P="${TMP}/A6" MG_MODE=held MG_DUR=3 \
    exec python3 "${LL_PY}" A6 -- "${MG}" ) > "${TMP}/A6.log" 2>&1 &
echo $! > "${TMP}/A6.pid"
has_in A6.inpool 10 >/dev/null; job B6 0.2
wait_job A6 20; wait_job B6 10
n6="$(grep -c 'ps lỗi' "${TMP}/A6.log" 2>/dev/null)"
if kept m6 A6 B6 A6.end && [ "${n6}" = 1 ]; then ok "6. ps lỗi ⇒ giữ slot (fail closed), log một lần"
else bad "6. ps lỗi xử lý sai" "log ps lỗi ${n6:-0} lần, A6 end $(val A6.end), B6 start $(val B6.start); $(log1 A6)"; fi
only_lock m6

[ "${fails}" -gt 0 ] || ok "7. không file khoá / owner sót trong LANE_LOCK_DIR"

echo
if [ "${fails}" -eq 0 ]; then echo "test_lane_lock_merge_gate_release: tất cả XANH"; exit 0; fi
echo "test_lane_lock_merge_gate_release: ${fails} ca ĐỎ"; exit 1
