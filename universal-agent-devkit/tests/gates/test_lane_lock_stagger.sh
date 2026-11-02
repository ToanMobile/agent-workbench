#!/usr/bin/env bash
# Test hồi quy (P7, gate kẹt và chậm 02/11): bin/lane_lock.py chống dồn — load1 là trung bình trượt 1 phút, trễ 30–60 s: tải vừa tụt dưới
# ngưỡng thì cả loạt lane đang chờ vào cùng một vòng (9 → 88 → 10). Tải giả DEVKIT_SLOT_LOAD_FILE, LANE_LOCK_STAGGER_S 3:
#   0. lane_lock.py + heavy_slot.py chạy là bản trong CHÍNH checkout chứa test (INSTINCT-057)
#   1. 2 lane nặng chờ ở tải 30, tải xuống 9 ⇒ lane đầu vào ngay (0 slot bị giữ: không chặn), lane sau chỉ vào khi .owner của lane đầu
#      đã ≥ LANE_LOCK_STAGGER_S tuổi, lúc lane đầu còn chạy (2 slot)       1b. log lane sau ghi chống dồn
#   2. như 1 nhưng tải xuống 5 (< LANE_LOCK_STAGGER_LOAD): lane đã phải chờ vì tải ⇒ vẫn chống dồn
#   3. đối chứng: tải 5 vào thẳng (chưa chờ tải, < 6) ⇒ cả hai vào ngay (STAGGER_S 30: chặn sai thì lệch ≥ 30 s)
#   4. tải 8 (≥ 6): việc nặng vừa giữ slot 1 ⇒ gate scoped nhỏ (#849) vẫn lấy slot 2 ngay; việc nặng khác chờ chống dồn
#   5. không file mới trong LANE_LOCK_DIR (chỉ dùng .owner sẵn có)
# Mỗi ca dùng LANE_LOCK_DIR riêng (mktemp -d); SB_HEAVY_SLOT_DIR riêng. Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LL_PY="${DEVKIT_DIR}/bin/lane_lock.py"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/lanelockstagger.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
TMP="$(cd "${TMP}" && pwd -P)"
cleanup() {
  local f
  printf '5\n' > "${TMP}/load" 2>/dev/null
  for f in "${TMP}"/*.pid; do [ -f "${f}" ] && kill "$(cat "${f}")" 2>/dev/null; done
  rm -rf "${TMP}"
}
trap cleanup EXIT
for v in $(env | sed -n 's/^\(LANE_LOCK_[A-Z_]*\)=.*/\1/p'); do unset "${v}"; done   # núm của người gọi không lọt vào ca
unset DEVKIT_SLOT_LOAD_MAX SB_HEAVY_SLOT_HELD DEVKIT_GATE_SLOT_HELD CLAUDE_PROJECT_DIR TARGET_DIR
export LANE_LOCK_SLOTS=2 LANE_LOCK_POLL_S=0.2 LANE_LOCK_LOG_S=1 LANE_LOCK_GRACE_S=0.2 LANE_LOCK_STAGGER_S=3 \
       SB_HEAVY_SLOT_DIR="${TMP}/heavy" DEVKIT_SLOT_LOAD_FILE="${TMP}/load"
mkdir -p "${SB_HEAVY_SLOT_DIR}"
load() { printf '%s\n' "$1" > "${TMP}/load"; }
now() { python3 -c 'import time; print(repr(time.time()))'; }
val() { cat "${TMP}/$1" 2>/dev/null || echo 0; }
ge() { python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) - float(sys.argv[2]) >= float(sys.argv[3]) else 1)' "$1" "$2" "$3"; }   # $1 − $2 ≥ $3
lt() { python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) < float(sys.argv[2]) else 1)' "$1" "$2"; }   # $1 < $2
diff_s() { python3 -c 'import sys; print("%.2f" % (float(sys.argv[1]) - float(sys.argv[2])))' "$1" "$2"; }
# đợi file $1 có nội dung tối đa $2 giây (đếm vòng: chỉ dùng cho điều kiện dương)
has_in() { local i=0 lim; lim="$(python3 -c "print(int(float('$2') * 20))")"
  while [ ! -s "${TMP}/$1" ] && [ "${i}" -lt "${lim}" ]; do sleep 0.05; i=$((i + 1)); done; [ -s "${TMP}/$1" ]; }
log_has() { local i=0 lim; lim="$(python3 -c "print(int(float('$3') * 20))")"
  while ! grep -q "$2" "${TMP}/$1.log" 2>/dev/null && [ "${i}" -lt "${lim}" ]; do sleep 0.05; i=$((i + 1)); done; grep -q "$2" "${TMP}/$1.log"; }
wait_job() { local p i=0; p="$(cat "${TMP}/$1.pid" 2>/dev/null)"; [ -n "${p}" ] || return 0
  while kill -0 "${p}" 2>/dev/null && [ "${i}" -lt 1200 ]; do sleep 0.05; i=$((i + 1)); done   # tối đa 60 s
  if kill -0 "${p}" 2>/dev/null; then kill -9 "${p}" 2>/dev/null; wait "${p}" 2>/dev/null; echo 124 > "${TMP}/$1.rc"
  else wait "${p}" 2>/dev/null; echo $? > "${TMP}/$1.rc"; fi
  rm -f "${TMP}/$1.pid"; }
log1() { tr '\n' ' ' < "${TMP}/$1.log" 2>/dev/null | cut -c1-240; }
fresh() { export LANE_LOCK_DIR="${TMP}/$1/locks"; }
# mtime của lane-<k>.owner mà lane <tên> đang giữ (rỗng khi không thấy)
owner_mtime() { python3 - "${LANE_LOCK_DIR}" "$1" <<'PY'
import glob, os, sys
for p in glob.glob(os.path.join(sys.argv[1], "lane-*.owner")):
    try:
        if open(p, encoding="utf-8").read().startswith(sys.argv[2] + " "):
            print(repr(os.stat(p).st_mtime)); break
    except OSError:
        pass
PY
}

# 0. đúng bản: lane_lock.py nằm trong checkout của test; heavy_slot mà lane_lock nạp cũng của checkout đó
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

cat > "${TMP}/job.py" <<'PY'
import os, time
p = os.environ["JOB_P"]
open(p + ".start", "w").write(repr(time.time()))
time.sleep(float(os.environ.get("JOB_DUR", "0.2")))
open(p + ".end", "w").write(repr(time.time()))
PY
# job <tên> <giây>: việc nặng (không phải gate) dưới lane_lock, nền
job() { ( JOB_P="${TMP}/$1" JOB_DUR="$2" exec python3 "${LL_PY}" "$1" -- python3 "${TMP}/job.py" ) > "${TMP}/$1.log" 2>&1 & echo $! > "${TMP}/$1.pid"; }

# burst <ca> <tải sau>: 2 lane nặng (12 s) chờ ở tải 30, hạ tải; lane đầu vào ngay, lane sau vào khi .owner của lane đầu ≥ 3 s tuổi
burst() {
  local c="$1" to="$2" a="$1a" b="$1b" first="" second="" i=0 om t_drop
  fresh "${c}"; load 30; job "${a}" 12; job "${b}" 12
  if ! { log_has "${a}" 'chờ (load' 15 && log_has "${b}" 'chờ (load' 15; }; then
    bad "${c}. hai lane không chờ ở tải 30" "$(log1 "${a}") | $(log1 "${b}")"; load 5; wait_job "${a}"; wait_job "${b}"; return
  fi
  t_drop="$(now)"; load "${to}"
  while [ -z "${first}" ] && [ "${i}" -lt 600 ]; do   # ≤ 30 s
    if [ -s "${TMP}/${a}.start" ] && [ -s "${TMP}/${b}.start" ]; then
      if lt "$(val "${b}.start")" "$(val "${a}.start")"; then first="${b}"; else first="${a}"; fi
    elif [ -s "${TMP}/${a}.start" ]; then first="${a}"
    elif [ -s "${TMP}/${b}.start" ]; then first="${b}"
    else sleep 0.05; i=$((i + 1)); fi
  done
  if [ -z "${first}" ]; then bad "${c}. không lane nào vào sau khi tải xuống ${to}" "$(log1 "${a}")"; wait_job "${a}"; wait_job "${b}"; return; fi
  om="$(owner_mtime "${first}")"
  if [ "${first}" = "${a}" ]; then second="${b}"; else second="${a}"; fi
  has_in "${second}.start" 40 >/dev/null
  wait_job "${a}"; wait_job "${b}"
  if lt "$(val "${first}.start")" "$(python3 -c "print(${t_drop} + 15)")"; then
    ok "${c}. tải xuống ${to}: lane đầu vào ngay (0 slot bị giữ ⇒ không chặn)"
  else bad "${c}. lane đầu không vào sau khi tải xuống" "tải xuống ${t_drop}, vào $(val "${first}.start")"; fi
  if [ -n "${om}" ] && [ "$(val "${second}.start")" != 0 ] && ge "$(val "${second}.start")" "${om}" 2.9 \
     && lt "$(val "${second}.start")" "$(val "${first}.end")"; then
    ok "${c}. tải 30 → ${to}: lane sau vào $(diff_s "$(val "${second}.start")" "${om}") s sau .owner của lane đầu (≥ 3 s), lúc lane đầu còn chạy"
  else bad "${c}. tải 30 → ${to}: hai lane dồn vào cùng lúc (không chống dồn)" \
      "owner ${om:-không-thấy}, ${second} vào $(val "${second}.start") (lệch $(diff_s "$(val "${second}.start")" "${om:-0}") s), ${first} xong $(val "${first}.end")"; fi
  if grep -q 'chống dồn' "${TMP}/${second}.log"; then ok "${c}b. log lane sau ghi chống dồn"
  else bad "${c}b. log lane sau không ghi chống dồn" "$(log1 "${second}")"; fi
}

# 1. tải 30 → 9 (≥ LANE_LOCK_STAGGER_LOAD)        2. tải 30 → 5: lane đã chờ vì tải ⇒ vẫn chống dồn dù tải < 6
burst s1 9
burst s2 5

# 3. đối chứng: tải 5 vào thẳng ⇒ cả hai vào ngay (STAGGER_S 30: bản chặn sai làm lane sau lệch ≥ 30 s)
fresh s3; load 5
( LANE_LOCK_STAGGER_S=30 JOB_P="${TMP}/A3" JOB_DUR=4 exec python3 "${LL_PY}" A3 -- python3 "${TMP}/job.py" ) > "${TMP}/A3.log" 2>&1 &
echo $! > "${TMP}/A3.pid"
( LANE_LOCK_STAGGER_S=30 JOB_P="${TMP}/B3" JOB_DUR=4 exec python3 "${LL_PY}" B3 -- python3 "${TMP}/job.py" ) > "${TMP}/B3.log" 2>&1 &
echo $! > "${TMP}/B3.pid"
has_in A3.start 20 >/dev/null; has_in B3.start 20 >/dev/null; wait_job A3; wait_job B3
if [ "$(val A3.start)" != 0 ] && [ "$(val B3.start)" != 0 ] && lt "$(val B3.start)" "$(val A3.end)" && lt "$(val A3.start)" "$(val B3.end)" \
   && ! grep -q 'chống dồn' "${TMP}/A3.log" "${TMP}/B3.log"; then ok "3. đối chứng tải 5, chưa chờ tải: hai lane vào ngay, chạy song song"
else bad "3. tải 5 mà lane bị chống dồn" "A3 $(val A3.start)–$(val A3.end), B3 $(val B3.start)–$(val B3.end); $(log1 B3)"; fi

# 4. tải 8: việc nặng H4 vừa giữ slot ⇒ gate scoped nhỏ L4 (#849) lấy slot 2 ngay; việc nặng H4b chờ chống dồn (STAGGER_S 30 > H4)
#    fixture: repo git tạm với post-fix-gate.py giả (là chính việc chạy) và scoped_gate.py giả (3 test) như test_lane_lock_light.sh
REPO="${TMP}/repo"; mkdir -p "${REPO}/kit/bin"
cat > "${REPO}/kit/bin/post-fix-gate.py" <<'PY'
import os, time
def needs_no_test(p): return p.endswith(".md")
def checklist_covers(): return {}
def rule_watch(rule, covers): return list(rule.get("watch_files", []))
def find_matrix_path(_m=None): return None
def load_active_matrix(_m=None, _base="HEAD"): return {}, None
def trust_additive_matrix(matrix, problem, _path, _base): return matrix, problem, []
if __name__ == "__main__":
    p = os.environ["JOB_P"]
    open(p + ".start", "w").write(repr(time.time()))
    time.sleep(float(os.environ.get("JOB_DUR", "0.2")))
    open(p + ".end", "w").write(repr(time.time()))
PY
cat > "${REPO}/kit/bin/scoped_gate.py" <<'PY'
import fnmatch
def decide(project, base, **_kw):
    return {"mode": "scoped", "tests": ["tests/test_%d.sh" % i for i in range(3)], "smoke": [], "changed": ["src/a.sh"],
            "graph_error": None, "reasons": [], "core_hits": []}
def no_full(res, project): return dict(res)
def match_pattern(path, pat): return fnmatch.fnmatch(path, pat)
PY
git -C "${REPO}" init -q && git -C "${REPO}" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init || bad "4. dựng repo fixture"
fresh s4; load 8
( LANE_LOCK_STAGGER_S=30 JOB_P="${TMP}/H4" JOB_DUR=10 exec python3 "${LL_PY}" H4 -- python3 "${TMP}/job.py" ) > "${TMP}/H4.log" 2>&1 &
echo $! > "${TMP}/H4.pid"
if has_in H4.start 15; then
  ( cd "${REPO}" && LANE_LOCK_STAGGER_S=30 JOB_P="${TMP}/L4" JOB_DUR=0.3 exec python3 "${LL_PY}" L4 -- python3 "${REPO}/kit/bin/post-fix-gate.py" \
      --run-tests --scoped --brief ) > "${TMP}/L4.log" 2>&1 &
  echo $! > "${TMP}/L4.pid"
  ( LANE_LOCK_STAGGER_S=30 JOB_P="${TMP}/H4b" JOB_DUR=0.2 exec python3 "${LL_PY}" H4b -- python3 "${TMP}/job.py" ) > "${TMP}/H4b.log" 2>&1 &
  echo $! > "${TMP}/H4b.pid"
  has_in L4.start 15 >/dev/null
  wait_job H4; wait_job L4; wait_job H4b
  if [ "$(val L4.start)" != 0 ] && lt "$(val L4.start)" "$(val H4.end)"; then
    ok "4. tải 8: gate scoped nhỏ không bị chống dồn (lấy slot 2 khi việc nặng còn chạy)"
  else bad "4. gate scoped nhỏ bị chống dồn chặn" "H4 $(val H4.start)–$(val H4.end), L4 start $(val L4.start); $(log1 L4)"; fi
  if [ "$(val H4b.start)" != 0 ] && ! lt "$(val H4b.start)" "$(val H4.end)" && grep -q 'chống dồn' "${TMP}/H4b.log"; then
    ok "4b. tải 8: việc nặng thứ hai chờ chống dồn (không vào khi slot kia vừa được lấy)"
  else bad "4b. tải 8: việc nặng thứ hai vào ngay sau việc nặng đầu" "H4 $(val H4.start)–$(val H4.end), H4b start $(val H4b.start); $(log1 H4b)"; fi
else bad "4. việc nặng H4 không vào ở tải 8" "$(log1 H4)"; fi

# 5. không file mới: mỗi thư mục khoá chỉ còn lane-1.lock, lane-2.lock
for c in s1 s2 s3 s4; do
  left="$(ls -A "${TMP}/${c}/locks" 2>/dev/null | tr '\n' ' ')"
  [ "${left}" = "lane-1.lock lane-2.lock " ] || bad "5. ${c}: file lạ trong LANE_LOCK_DIR" "${left}"
done
[ "${fails}" -gt 0 ] || ok "5. không file khoá / owner / marker mới trong LANE_LOCK_DIR"

echo
if [ "${fails}" -eq 0 ]; then echo "test_lane_lock_stagger: tất cả XANH"; exit 0; fi
echo "test_lane_lock_stagger: ${fails} ca ĐỎ"; exit 1
