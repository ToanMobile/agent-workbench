#!/usr/bin/env bash
# Test hồi quy (#685): hooks/tests/hook_contract_test.sh không được xanh giả khi watchdog 7 s của hook bắn, không được treo khi hook treo, và chỉ ghi
# ENV-BLOCKED (không PASS, không FAIL logic) khi chứng minh được là đói tải. Hook production không đổi: watchdog bắn vẫn chặn (fail-closed).
# Gốc: gate-full đêm 30/10 đỏ ở agent-kit test — 5 rồi 1 ca lệch mỗi lượt, đều là "quá lớn / quá phức tạp để phân tích" trên lệnh vô hại.
#   A. ca nhanh (HOOK_CONTRACT_SCENARIO_FILE + hook giả; tải giả HOOK_WATCHDOG_TEST_LOAD/_CORES, không đốt CPU thật):
#      A1 hook treo (sleep vô hạn, cháu giữ pipe) ⇒ FAIL < 10 s ở tải 0 VÀ 500, không còn tiến trình cháu;
#      A2 thông điệp watchdog production, want=2 và want=0: tải 500 + CPU thấp ⇒ ENV-BLOCKED (không PASS, không "deviating", exit 1);
#         tải 0 ⇒ FAIL; hook tự đốt CPU ⇒ FAIL ở cả hai tải; cháu đốt CPU rồi hook exit 2 ngay ⇒ FAIL ở cả hai tải;
#      A3 ngưỡng qua capacity.py: 12 lõi, tải 40: DEVKIT_CAPACITY=0.25 (hold 24) ⇒ ENV-BLOCKED; không đặt (hold 96) ⇒ FAIL; rác ⇒ như không đặt;
#      A4 giới hạn: 3 lần hết giờ ⇒ dừng sớm; 11 lần watchdog ⇒ 10 ENV-BLOCKED rồi FAIL, tổng kết nhánh FAIL (không marker, DEVKIT_SUITE_RED khớp);
#         tổng kết ENV-BLOCKED không khớp DEVKIT_SUITE_GREEN của test_evidence_gate.sh;
#      A5 case_runner.pl: tách stdout/stderr (redirect `2>&1 >/dev/null` giữ nguyên), chạy dưới PATH chỉ có bash+cat, exit của con, hết giờ trong $(...) không treo.
#   B. đầu-cuối: chạy THẬT hook_contract_test.sh trên cây kit mỏng (symlink) với block-dangerous-git.sh giả chỉ ở LẦN GỌI ĐẦU (ca want=2 đầu tiên) in
#      thông điệp watchdog: bản cũ chấm ca đó "ok" (xanh giả, exit 0) ⇒ test ĐỎ; bản mới ENV-BLOCKED + marker + exit 1.
#      Bản cũ để ĐỎ lượt RED của người viết: WATCHDOG_ENV_SCRIPT_UNDER_TEST=<file hook_contract_test.sh cũ> (đặt vào cây mỏng đúng chỗ), WATCHDOG_ENV_ONLY=B.
#   C. không còn lời gọi hook trực tiếp nào chưa bọc chốt hết giờ; ca 937-938 lưu rc (hook treo bị cắt rc 142 không PASS).
#   D. hc_watch (mọi điểm gọi trực tiếp dùng nó): 142 ⇒ FAIL; thông điệp trong stderr hoặc trong `out` JSON của bridge ⇒ ENV-BLOCKED/FAIL, không bao giờ PASS.
# Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="${DEVKIT_DIR}/hooks/tests/hook_contract_test.sh"
LIBDIR="${DEVKIT_DIR}/tests/lib"
ONLY="${WATCHDOG_ENV_ONLY:-}"
UNDER_TEST="${WATCHDOG_ENV_SCRIPT_UNDER_TEST:-}"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/wdenv.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
TMP="$(cd "${TMP}" && pwd)"
PIDS=""
cleanup() {
  local p
  for p in ${PIDS}; do kill "${p}" 2>/dev/null; done
  for p in "${TMP}"/pid.*; do [ -f "${p}" ] && kill "$(cat "${p}")" 2>/dev/null; done
  rm -rf "${TMP}"
}
trap cleanup EXIT

# chạy một lệnh với trần cứng 150 s (lưới an toàn của test: bản cũ có thể treo)
guard() { /usr/bin/perl -e 'alarm 150; exec @ARGV or exit 127' "$@"; }
alive() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }

WD1="BLOCKED: block-dangerous-git.sh: lệnh quá lớn / quá phức tạp để phân tích trong thời hạn (7 s) — chặn để an toàn. Chia thành lệnh nhỏ hơn, hoặc ghi vào file rồi chạy file."

# ── A. ca nhanh ────────────────────────────────────────────────────────────────────────────────────────────────────────────────
if [ "${ONLY}" != "B" ]; then
  FH="${TMP}/fh"; mkdir -p "${FH}"
  # hook giả. HC_PIDFILE (qua ENV=VAL của run_case) ghi pid của tiến trình cháu.
  cat > "${FH}/hang.sh" <<'H'
#!/bin/bash
cat >/dev/null
sleep 1000 &
echo $! > "${HC_PIDFILE}"
wait
H
  cat > "${FH}/wd1.sh" <<'H'
#!/bin/bash
cat >/dev/null
echo "BLOCKED: block-dangerous-git.sh: lệnh quá lớn / quá phức tạp để phân tích trong thời hạn (7 s) — chặn để an toàn. Chia thành lệnh nhỏ hơn, hoặc ghi vào file rồi chạy file." >&2
exit 2
H
  cat > "${FH}/wd2.sh" <<'H'
#!/bin/bash
cat >/dev/null
echo "hook.sh: line 2688:  8203 Done  printf x       8279 Alarm clock: 14         | python3 -I -c" >&2
echo "🛑 [HARDWARE SAFETY GATE] python không chạy được (rc 142) — chặn để an toàn." >&2
exit 2
H
  cat > "${FH}/burn.sh" <<'H'
#!/bin/bash
cat >/dev/null
python3 -c 'import time; t = time.process_time()
while time.process_time() - t < 0.4: pass'
echo "BLOCKED: block-dangerous-git.sh: lệnh quá lớn / quá phức tạp để phân tích trong thời hạn (7 s) — chặn." >&2
exit 2
H
  # cháu đốt 0,4 s CPU rồi ngủ (còn sống khi hook thoát): CPU của nó chỉ thấy được qua ps -g
  cat > "${FH}/grand.sh" <<'H'
#!/bin/bash
cat >/dev/null
python3 -c 'import time
t = time.process_time()
while time.process_time() - t < 0.4: pass
time.sleep(60)' &
echo $! > "${HC_PIDFILE}"
sleep 1.2
echo "BLOCKED: block-dangerous-git.sh: lệnh quá lớn / quá phức tạp để phân tích trong thời hạn (7 s) — chặn." >&2
exit 2
H
  cat > "${FH}/okhook.sh" <<'H'
#!/bin/bash
cat >/dev/null
exit 0
H

  # run_sc <tên> <tải giả> <bell s> [ENV=VAL…] ; kịch bản ở ${TMP}/<tên>.sc ; kết quả: ${TMP}/<tên>.out, RC, ELAPSED
  run_sc() {
    local n="$1" load="$2" bell="$3" t0; shift 3
    t0=$SECONDS
    guard env HOOK_CONTRACT_HOOKS_DIR="${FH}" HOOK_CONTRACT_SCENARIO_FILE="${TMP}/${n}.sc" HOOK_WATCHDOG_TEST_CORES=12 HOOK_WATCHDOG_TEST_LOAD="${load}" \
        HOOK_WATCHDOG_WINDOW_S=0.3 HOOK_CASE_BELL_S="${bell}" "$@" bash "${SCRIPT}" > "${TMP}/${n}.out" 2>&1
    RC=$?
    ELAPSED=$((SECONDS - t0))
  }

  if ! grep -q 'HOOK_CONTRACT_SCENARIO_FILE' "${SCRIPT}"; then
    bad "A: hook_contract_test.sh có HOOK_CONTRACT_SCENARIO_FILE" "chưa có: không thể chạy ca nhanh"
  else
    # A1: hook treo ⇒ FAIL ở cả tải 0 và 500
    for L in 0 500; do
      rm -f "${TMP}/pid.h${L}"
      printf '%s\n' "run_case \"hang L${L}\" hang.sh 0 '{}' HC_PIDFILE=${TMP}/pid.h${L}" > "${TMP}/a1_${L}.sc"
      run_sc "a1_${L}" "${L}" 2
      chk "A1 hook treo, tải ${L}: exit 1, FAIL 'hook không trả lời', không PASS" \
        "[ ${RC} -eq 1 ] && grep -q 'hook không trả lời' '${TMP}/a1_${L}.out' && grep -q '1 deviating' '${TMP}/a1_${L}.out' && ! grep -q '  ok   hang' '${TMP}/a1_${L}.out'" "rc=${RC}: $(tail -3 "${TMP}/a1_${L}.out" | tr '\n' ' ')"
      chk "A1 hook treo, tải ${L}: kết thúc < 10 s (${ELAPSED} s) và không còn tiến trình cháu" \
        "[ ${ELAPSED} -lt 10 ] && ! alive '${TMP}/pid.h${L}'" "elapsed=${ELAPSED} alive=$(alive "${TMP}/pid.h${L}" && echo yes || echo no)"
    done

    # A2: watchdog production, want=2 và want=0
    for V in wd1 wd2; do
      for W in 2 0; do
        printf '%s\n' "run_case \"${V} want${W}\" ${V}.sh ${W} '{}'" > "${TMP}/a2_${V}_${W}_hi.sc"
        run_sc "a2_${V}_${W}_hi" 500 30
        chk "A2 ${V} want=${W}, tải 500, CPU thấp: ENV-BLOCKED, không PASS, exit 1, không 'deviating', có marker" \
          "[ ${RC} -eq 1 ] && grep -q '  ENV-BLOCKED  ${V} want${W}' '${TMP}/a2_${V}_${W}_hi.out' && ! grep -q '  ok   ${V}' '${TMP}/a2_${V}_${W}_hi.out' && grep -q 'env-blocked (no verdict)' '${TMP}/a2_${V}_${W}_hi.out' && ! grep -q 'deviating' '${TMP}/a2_${V}_${W}_hi.out' && grep -qx 'ENV-BLOCKED: hook watchdog fired under load, no verdict' '${TMP}/a2_${V}_${W}_hi.out'" \
          "rc=${RC}: $(tail -4 "${TMP}/a2_${V}_${W}_hi.out" | tr '\n' ' ')"
        cp "${TMP}/a2_${V}_${W}_hi.sc" "${TMP}/a2_${V}_${W}_lo.sc"
        run_sc "a2_${V}_${W}_lo" 0 30
        chk "A2 ${V} want=${W}, tải 0: FAIL (máy không bận), không PASS, không marker" \
          "[ ${RC} -eq 1 ] && grep -q '  FAIL ${V} want${W}' '${TMP}/a2_${V}_${W}_lo.out' && ! grep -q '  ok   ${V}' '${TMP}/a2_${V}_${W}_lo.out' && grep -q '1 deviating' '${TMP}/a2_${V}_${W}_lo.out' && ! grep -q '^ENV-BLOCKED:' '${TMP}/a2_${V}_${W}_lo.out'" \
          "rc=${RC}: $(tail -4 "${TMP}/a2_${V}_${W}_lo.out" | tr '\n' ' ')"
      done
    done
    for L in 0 500; do
      printf '%s\n' "run_case \"burn L${L}\" burn.sh 2 '{}'" > "${TMP}/a2_burn_${L}.sc"
      run_sc "a2_burn_${L}" "${L}" 30
      chk "A2 hook tự đốt CPU rồi in watchdog, tải ${L}: FAIL (không phải đói tải), không PASS" \
        "[ ${RC} -eq 1 ] && grep -q '  FAIL burn L${L}' '${TMP}/a2_burn_${L}.out' && ! grep -q '  ok   burn' '${TMP}/a2_burn_${L}.out' && ! grep -q 'ENV-BLOCKED  burn' '${TMP}/a2_burn_${L}.out'" \
        "rc=${RC}: $(tail -4 "${TMP}/a2_burn_${L}.out" | tr '\n' ' ')"
      rm -f "${TMP}/pid.g${L}"
      printf '%s\n' "run_case \"grand L${L}\" grand.sh 2 '{}' HC_PIDFILE=${TMP}/pid.g${L}" > "${TMP}/a2_grand_${L}.sc"
      run_sc "a2_grand_${L}" "${L}" 30
      chk "A2 cháu đốt CPU rồi hook exit 2, tải ${L}: CPU cháu được cộng ⇒ FAIL; cháu bị giết" \
        "[ ${RC} -eq 1 ] && grep -q '  FAIL grand L${L}' '${TMP}/a2_grand_${L}.out' && ! grep -q 'ENV-BLOCKED  grand' '${TMP}/a2_grand_${L}.out' && ! alive '${TMP}/pid.g${L}'" \
        "rc=${RC} alive=$(alive "${TMP}/pid.g${L}" && echo yes || echo no): $(tail -4 "${TMP}/a2_grand_${L}.out" | tr '\n' ' ')"
    done

    # A3: ngưỡng qua capacity.py (12 lõi, tải 40): hold = 8 × 12 × hệ số
    printf '%s\n' "run_case \"thr\" wd1.sh 2 '{}'" > "${TMP}/a3_cap.sc"
    cp "${TMP}/a3_cap.sc" "${TMP}/a3_none.sc"; cp "${TMP}/a3_cap.sc" "${TMP}/a3_junk.sc"
    run_sc a3_cap 40 30 DEVKIT_CAPACITY=0.25
    chk "A3 DEVKIT_CAPACITY=0.25 (hold 24), tải 40 ⇒ ENV-BLOCKED (núm thật không bị clean_git_env nuốt)" \
      "[ ${RC} -eq 1 ] && grep -q 'ENV-BLOCKED  thr' '${TMP}/a3_cap.out'" "rc=${RC}: $(tail -3 "${TMP}/a3_cap.out" | tr '\n' ' ')"
    run_sc a3_none 40 30
    chk "A3 không đặt DEVKIT_CAPACITY (hold 96), tải 40 ⇒ FAIL" \
      "[ ${RC} -eq 1 ] && grep -q '  FAIL thr' '${TMP}/a3_none.out' && ! grep -q 'ENV-BLOCKED  thr' '${TMP}/a3_none.out'" "rc=${RC}: $(tail -3 "${TMP}/a3_none.out" | tr '\n' ' ')"
    run_sc a3_junk 40 30 DEVKIT_CAPACITY=abc
    chk "A3 DEVKIT_CAPACITY=rác ⇒ hệ số 1 (qua capacity.scale()) ⇒ FAIL như không đặt" \
      "[ ${RC} -eq 1 ] && grep -q '  FAIL thr' '${TMP}/a3_junk.out'" "rc=${RC}: $(tail -3 "${TMP}/a3_junk.out" | tr '\n' ' ')"

    # A4: giới hạn
    rm -f "${TMP}"/pid.lim*
    i=0; : > "${TMP}/a4_bell.sc"
    while [ ${i} -lt 5 ]; do i=$((i + 1)); echo "run_case \"limhang${i}\" hang.sh 0 '{}' HC_PIDFILE=${TMP}/pid.lim${i}" >> "${TMP}/a4_bell.sc"; done
    run_sc a4_bell 0 1
    chk "A4 3 lần hết giờ ⇒ dừng sớm ở ca thứ 3 (< 20 s), tổng kết đủ, exit 1" \
      "[ ${RC} -eq 1 ] && [ ${ELAPSED} -lt 20 ] && [ \"\$(grep -c '  FAIL limhang' '${TMP}/a4_bell.out')\" -eq 3 ] && ! grep -q 'limhang4' '${TMP}/a4_bell.out' && grep -q 'dừng sớm' '${TMP}/a4_bell.out' && grep -q 'deviating' '${TMP}/a4_bell.out'" \
      "rc=${RC} elapsed=${ELAPSED}: $(tail -5 "${TMP}/a4_bell.out" | tr '\n' ' ')"
    i=0; : > "${TMP}/a4_wd.sc"
    while [ ${i} -lt 13 ]; do i=$((i + 1)); echo "run_case \"limwd${i}\" wd1.sh 2 '{}'" >> "${TMP}/a4_wd.sc"; done
    run_sc a4_wd 500 30
    chk "A4 11 lần watchdog, tải 500 ⇒ 10 ENV-BLOCKED rồi FAIL, dừng ở ca 11, tổng kết nhánh FAIL không marker" \
      "[ ${RC} -eq 1 ] && [ \"\$(grep -c '  ENV-BLOCKED  limwd' '${TMP}/a4_wd.out')\" -eq 10 ] && grep -q '  FAIL limwd11' '${TMP}/a4_wd.out' && ! grep -q 'limwd12' '${TMP}/a4_wd.out' && ! grep -q '^ENV-BLOCKED:' '${TMP}/a4_wd.out' && grep -Eq '[1-9][0-9]* deviating' '${TMP}/a4_wd.out'" \
      "rc=${RC}: $(tail -6 "${TMP}/a4_wd.out" | tr '\n' ' ')"
    # regex thật của test_evidence_gate.sh (dòng DEVKIT_SUITE_RED / DEVKIT_SUITE_GREEN)
    EG="${DEVKIT_DIR}/hooks/test_evidence_gate.sh"
    cat > "${TMP}/rx.py" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
def grab(name):
    m = re.search(r"^%s = (re\.compile\(.*\))$" % name, src, re.M)
    return eval(m.group(1), {"re": re}) if m else None
red, green = grab("DEVKIT_SUITE_RED"), grab("DEVKIT_SUITE_GREEN")
text = open(sys.argv[2], encoding="utf-8").read()
what = sys.argv[3]
if red is None or green is None:
    print("missing"); sys.exit(0)
print("red=%d green=%d" % (bool(red.search(text)), bool(green.search(text))))
PY
    chk "A4 DEVKIT_SUITE_RED khớp tổng kết FAIL (nhánh 11 watchdog)" \
      "[ \"\$(python3 -I '${TMP}/rx.py' '${EG}' '${TMP}/a4_wd.out' x)\" = 'red=1 green=0' ]" "$(python3 -I "${TMP}/rx.py" "${EG}" "${TMP}/a4_wd.out" x)"
    chk "A4 tổng kết ENV-BLOCKED (FAIL=0) KHÔNG khớp DEVKIT_SUITE_GREEN" \
      "[ \"\$(python3 -I '${TMP}/rx.py' '${EG}' '${TMP}/a2_wd1_2_hi.out' x | sed 's/red=[01] //')\" = 'green=0' ]" "$(python3 -I "${TMP}/rx.py" "${EG}" "${TMP}/a2_wd1_2_hi.out" x)"

    # A5: case_runner.pl
    PLR="/usr/bin/perl ${LIBDIR}/case_runner.pl"
    o="$(${PLR} 5 "${TMP}/cpu" "${TMP}/bells" -- sh -c 'echo OUT; echo ERR >&2' 2>&1 >/dev/null)"
    chk "A5 stdout/stderr tách: '2>&1 >/dev/null' chỉ còn stderr" "[ \"${o}\" = ERR ]" "got='${o}'"
    mkdir -p "${TMP}/nojq"; ln -s "$(command -v bash)" "${TMP}/nojq/bash"; ln -s "$(command -v cat)" "${TMP}/nojq/cat"
    o="$(PATH="${TMP}/nojq" ${PLR} 5 "${TMP}/cpu" "${TMP}/bells" -- bash -c 'echo hi; exit 3')"; r=$?
    chk "A5 dưới PATH chỉ có bash+cat: chạy được, trả đúng exit của con" "[ \"${o}\" = hi ] && [ ${r} -eq 3 ]" "out='${o}' rc=${r}"
    rm -f "${TMP}/bells"; t0=$SECONDS
    o="$(${PLR} 1 "${TMP}/cpu" "${TMP}/bells" -- sh -c 'sleep 1000 & wait' 2>&1)"; r=$?
    chk "A5 hết giờ trong \$(...) không treo: rc 142 < 6 s, ghi bell" "[ ${r} -eq 142 ] && [ $((SECONDS - t0)) -lt 6 ] && [ -s '${TMP}/bells' ]" "rc=${r} t=$((SECONDS - t0))"
  fi
fi

# ── B. đầu-cuối trên cây kit mỏng ───────────────────────────────────────────────────────────────────────────────────────────────
if [ "${ONLY}" != "A" ]; then
  THIN="${TMP}/kit"; mkdir -p "${THIN}/hooks/tests"
  for e in "${DEVKIT_DIR}"/* "${DEVKIT_DIR}"/.[!.]*; do
    [ -e "${e}" ] || continue
    [ "$(basename "${e}")" = hooks ] && continue
    ln -s "${e}" "${THIN}/$(basename "${e}")"
  done
  for e in "${DEVKIT_DIR}/hooks"/* "${DEVKIT_DIR}/hooks"/.[!.]*; do
    [ -e "${e}" ] || continue
    b="$(basename "${e}")"
    case "${b}" in tests|block-dangerous-git.sh) continue ;; esac
    ln -s "${e}" "${THIN}/hooks/${b}"
  done
  cat > "${THIN}/hooks/block-dangerous-git.sh" <<EOF
#!/bin/bash
# hook giả: LẦN GỌI ĐẦU (ca want=2 đầu tiên của contract) in thông điệp watchdog production rồi exit 2; từ lần thứ 2 chạy hook thật
if [ ! -e "${TMP}/cnt" ]; then
  : > "${TMP}/cnt"; cat >/dev/null
  echo "${WD1}" >&2
  exit 2
fi
exec bash "${DEVKIT_DIR}/hooks/block-dangerous-git.sh" "\$@"
EOF
  chmod +x "${THIN}/hooks/block-dangerous-git.sh"
  if [ -n "${UNDER_TEST}" ]; then
    cp "${UNDER_TEST}" "${THIN}/hooks/tests/hook_contract_test.sh"
    guard env HOOK_WATCHDOG_TEST_CORES=12 HOOK_WATCHDOG_TEST_LOAD=500 bash "${THIN}/hooks/tests/hook_contract_test.sh" > "${TMP}/b.out" 2>&1
  else
    guard env HOOK_WATCHDOG_TEST_CORES=12 HOOK_WATCHDOG_TEST_LOAD=500 HOOK_CONTRACT_HOOKS_DIR="${THIN}/hooks" HOOK_CONTRACT_KIT_DIR="${DEVKIT_DIR}" \
      bash "${SCRIPT}" > "${TMP}/b.out" 2>&1
  fi
  BRC=$?
  chk "B ca want=2 đầu tiên (watchdog giả) KHÔNG được chấm ok" "! grep -q '  ok   destructive reset --hard blocked' '${TMP}/b.out'" "bản cũ chấm ok (xanh giả): $(grep 'destructive reset --hard blocked' "${TMP}/b.out" | head -1)"
  chk "B ca đó là ENV-BLOCKED (tải giả 500, CPU thấp)" "grep -q '  ENV-BLOCKED  destructive reset --hard blocked' '${TMP}/b.out'"
  chk "B tổng kết: 'N ok, 1 env-blocked (no verdict)', marker, exit 1" \
    "[ ${BRC} -eq 1 ] && grep -Eq 'contract points: [0-9]+ ok, 1 env-blocked \(no verdict\)' '${TMP}/b.out' && grep -qx 'ENV-BLOCKED: hook watchdog fired under load, no verdict' '${TMP}/b.out'" "rc=${BRC}: $(tail -3 "${TMP}/b.out" | tr '\n' ' ')"
fi

# ── C. ratchet: không còn lời gọi hook trực tiếp chưa bọc; ca 937-938 lưu rc ─────────────────────────────────────────────────
if [ "${ONLY}" != "B" ]; then
  unwrapped="$(grep -nE '(bash|python3) "\$\{HOOKS\}/' "${SCRIPT}" | grep -v 'HC_WRAP' | cut -c1-120)"
  chk "C mọi 'bash|python3 \"\${HOOKS}/…\"' trong hook_contract_test.sh đi qua \${HC_WRAP} (chốt hết giờ)" "[ -z \"\$unwrapped\" ]" "chưa bọc: ${unwrapped}"
  chk "C ca bridge cursor 'rm -rf src in app/': PASS chỉ khi rc=0 và out rỗng (hook treo bị cắt không PASS)" \
    "grep -q 'elif \[ \"\${rc}\" -eq 0 \] && \[ -z \"\${out}\" \]; then' '${SCRIPT}'"
fi

# ── D. hc_watch: phân loại dùng chung cho mọi điểm gọi trực tiếp ───────────────────────────────────────────────────────────────────
if [ "${ONLY}" != "B" ]; then
  if [ ! -f "${LIBDIR}/case_runner.sh" ]; then
    bad "D tests/lib/case_runner.sh tồn tại" "chưa có"
  else
    # d_watch <rc> <text-in-err> <text-in-out> <cpu_ms> <load> ; in: "ret=<hc_watch rc> FAIL=<n> ENVB=<n> PASS=<n>"
    d_watch() {
      (
        SANDBOX="$(mktemp -d "${TMP}/dw.XXXXXX")"; HOOKS="${SANDBOX}"; HC_KIT="${DEVKIT_DIR}"; PASS=0; FAIL=0; FAILED_CASES=""
        HC_CAP_SAVED=""; HC_TEST_LOAD="$5"; HC_TEST_CORES=12; export HOOK_WATCHDOG_WINDOW_S=7
        . "${LIBDIR}/case_runner.sh"
        echo "$4" > "${HC_STATE_DIR}/cpu"
        printf '%s' "$2" > "${SANDBOX}/err"
        hc_watch "d" "$1" "${SANDBOX}/err" "$3" > /dev/null
        echo "ret=$? FAIL=${FAIL} ENVB=${ENVB} PASS=${PASS}"
      )
    }
    chk "D rc 142 ⇒ FAIL, đã chấm" "[ \"\$(d_watch 142 '' '' 5 0)\" = 'ret=0 FAIL=1 ENVB=0 PASS=0' ]" "$(d_watch 142 '' '' 5 0)"
    chk "D watchdog trong stderr, tải 500, CPU 5 ms ⇒ ENV-BLOCKED" "[ \"\$(d_watch 0 '${WD1}' '' 5 500)\" = 'ret=0 FAIL=0 ENVB=1 PASS=0' ]" "$(d_watch 0 "${WD1}" '' 5 500)"
    chk "D watchdog trong JSON out của bridge (cursor), tải 500 ⇒ ENV-BLOCKED" \
      "[ \"\$(d_watch 0 '' '{\"permission\": \"deny\", \"agent_message\": \"${WD1}\"}' 5 500)\" = 'ret=0 FAIL=0 ENVB=1 PASS=0' ]" "$(d_watch 0 '' "{\"permission\": \"deny\", \"agent_message\": \"${WD1}\"}" 5 500)"
    chk "D watchdog, tải 0 ⇒ FAIL" "[ \"\$(d_watch 0 '${WD1}' '' 5 0)\" = 'ret=0 FAIL=1 ENVB=0 PASS=0' ]" "$(d_watch 0 "${WD1}" '' 5 0)"
    chk "D watchdog, CPU hook 9000 ms ⇒ FAIL (tự tốn CPU)" "[ \"\$(d_watch 0 '${WD1}' '' 9000 500)\" = 'ret=0 FAIL=1 ENVB=0 PASS=0' ]" "$(d_watch 0 "${WD1}" '' 9000 500)"
    chk "D không có bell/watchdog ⇒ trả 1, không đổi bộ đếm (người gọi chấm assertion gốc)" "[ \"\$(d_watch 2 'blocked: reset --hard' '' 5 500)\" = 'ret=1 FAIL=0 ENVB=0 PASS=0' ]" "$(d_watch 2 'blocked: reset --hard' '' 5 500)"
  fi
fi

echo
if [ "${fails}" -ne 0 ]; then echo "test_hook_contract_watchdog_env: ${fails} ĐỎ"; exit 1; fi
echo "test_hook_contract_watchdog_env: tất cả XANH"
exit 0
