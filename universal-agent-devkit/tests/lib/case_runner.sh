# tests/lib/case_runner.sh — run_case, chốt hết giờ và phân loại watchdog của hooks/tests/hook_contract_test.sh (#685). SOURCE, không chạy.
#
# Vì sao: watchdog 7 s của block-dangerous-git.sh / hardware_safety_gate.sh bắn trên lệnh vô hại khi máy tải (gate-full đêm 30/10), và
# harness cũ (a) chấm exit 2 + watchdog là PASS khi ca mong 2, (b) không có chốt cho hook treo thật. Hook production không đổi (watchdog bắn
# ⇒ chặn). Ở đây: hook treo ⇒ perl cắt ở HOOK_CASE_BELL_S (30 s), rc 142 ⇒ FAIL; thông điệp watchdog ⇒ KHÔNG BAO GIỜ PASS: ENV-BLOCKED chỉ khi
# tests/lib/watchdog_env.py chứng minh đói tải (CPU hook thấp, tải ≥ hold_load, ≤ 10 lần), còn lại FAIL. 3 lần hết giờ hoặc lần watchdog
# thứ 11 ⇒ in tổng kết rồi thoát ngay (trần xấu nhất ~190 s, dưới KIT_TEST_TIMEOUT_S 7200 s của gate_full.py).
#
# Người gọi đặt TRƯỚC khi source: SANDBOX, HOOKS, HC_KIT (gốc kit: bin/, profiles/), PASS, FAIL, FAILED_CASES. Núm của người chạy phải được lưu
# TRƯỚC clean_git_env.sh (nó unset DEVKIT_CAPACITY*): HC_CAP_SAVED, HC_TEST_LOAD, HC_TEST_CORES. bash 3.2.
HC_LIBDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HC_STATE_DIR="${SANDBOX}/.hc"
mkdir -p "${HC_STATE_DIR}"
HC_BELL_S="${HOOK_CASE_BELL_S:-30}"
ENVB=0
HC_TMPDIRS=()
# ponytail: các đường dẫn này không có khoảng trắng (mktemp dưới TMPDIR, kit trong repo); HC_WRAP bị tách từ trên không-ngoặc để đứng trước `bash hook`
# trong cả dạng `env X=… ${HC_WRAP} bash …` lẫn `X=… ${HC_WRAP} bash …`.
HC_WRAP="/usr/bin/perl ${HC_LIBDIR}/case_runner.pl ${HC_BELL_S} ${HC_STATE_DIR}/cpu ${HC_STATE_DIR}/bells --"

hc_cleanup() {
  local d
  for d in ${HC_TMPDIRS[@]+"${HC_TMPDIRS[@]}"}; do rm -rf "${d}"; done
  rm -rf "${SANDBOX}"
}

hc_count() { # số dòng của file đếm (0 khi chưa có): builtin, không fork
  local n=0 _l
  [ -f "$1" ] || { echo 0; return 0; }
  while IFS= read -r _l; do n=$((n + 1)); done < "$1"
  echo "${n}"
}

# Thông điệp watchdog THẬT của hook production (không có chữ "watchdog"): hardware_safety_gate.sh:189 / block-dangerous-git.sh:115
# ("quá lớn / quá phức tạp để phân tích trong thời hạn"), SIGALRM lúc python khởi động/đóng (bash in "Alarm clock: 14" rồi hook báo
# "python không chạy được (rc 142)").
hc_is_wd() {
  case "$1" in
    *"quá lớn / quá phức tạp để phân tích trong thời hạn"*|*"Alarm clock: 14"*|*"python không chạy được (rc 142)"*) return 0 ;;
  esac
  return 1
}

hc_fail_case() { # name lý do
  FAIL=$((FAIL + 1))
  FAILED_CASES="${FAILED_CASES}
  ✗ $1
      $2"
  printf '  FAIL %-46s %s\n' "$1" "$2"
}

hc_summary() { # in tổng kết rồi thoát; 3 nhánh loại trừ nhau (không nhánh nào khớp DEVKIT_SUITE_GREEN khi còn ca chưa có phán quyết)
  echo "─────────────────────────────────────────────"
  if [ "${FAIL}" -ne 0 ]; then
    if [ "${ENVB}" -ne 0 ]; then echo "contract points: ${PASS} ok, ${FAIL} deviating, ${ENVB} env-blocked"
    else echo "contract points: ${PASS} ok, ${FAIL} deviating"; fi
    echo "${FAILED_CASES}"
    echo
    echo "A deviation means the hook and its documented contract disagree."
    echo "Fix the hook, or fix the contract — do not relax the case (CLAUDE.md W4)."
    exit 1
  fi
  if [ "${ENVB}" -ne 0 ]; then
    echo "contract points: ${PASS} ok, ${ENVB} env-blocked (no verdict)"
    echo "ENV-BLOCKED: hook watchdog fired under load, no verdict"
    exit 1
  fi
  echo "contract points: ${PASS} ok, ${FAIL} deviating"
  exit 0
}

# Giới hạn đếm qua FILE (một lời gọi trong $(...) hay pipeline không cộng dồn biến về shell cha): gọi ở SHELL CHA sau mỗi lời gọi.
hc_check_limits() {
  local b w
  b="$(hc_count "${HC_STATE_DIR}/bells")"
  w="$(hc_count "${HC_STATE_DIR}/wd")"
  if [ "${b}" -ge 3 ] || [ "${w}" -ge 11 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES="${FAILED_CASES}
  ✗ dừng sớm: ${b} lần hook không trả lời (hết ${HC_BELL_S} s), ${w} lần watchdog 7 s — hook hỏng, không chạy tiếp"
    hc_summary
  fi
  return 0
}

# hc_watch name rc errfile [extra-text]: một lời gọi trực tiếp vừa chạy. Trả 0 nếu ĐÃ chấm (hết giờ hoặc watchdog: ca đã tính FAIL hoặc ENV-BLOCKED,
# người gọi bỏ qua assertion gốc), 1 nếu không có bell/watchdog (người gọi chấm assertion gốc của ca).
hc_watch() {
  local name="$1" rc="$2" ef="${3:-}" txt="${4-}" v
  [ -n "${ef}" ] && [ -f "${ef}" ] && txt="${txt}$(<"${ef}")"
  if [ "${rc}" = "142" ]; then
    hc_fail_case "${name}" "hook không trả lời (rc 142, bell ${HC_BELL_S} s)"
    hc_check_limits
    return 0
  fi
  if hc_is_wd "${txt}"; then
    v="$(python3 -I "${HC_LIBDIR}/watchdog_env.py" --kit "${HC_KIT}" --state-dir "${HC_STATE_DIR}" --cpu-file "${HC_STATE_DIR}/cpu" \
          --cap-saved "${HC_CAP_SAVED:-}" --test-load "${HC_TEST_LOAD:-}" --test-cores "${HC_TEST_CORES:-}" 2>&1)"
    case "${v}" in
      ENVB*) ENVB=$((ENVB + 1)); printf '  ENV-BLOCKED  %-46s %s\n' "${name}" "${v#ENVB }" ;;
      *)     hc_fail_case "${name}" "watchdog 7 s của hook, không phải PASS: ${v#FAIL }" ;;
    esac
    hc_check_limits
    return 0
  fi
  hc_check_limits
  return 1
}

# run_case <name> <hook.sh> <expected_exit> <stdin-json> [ENV=VAL ...]
# Bỏ marker Grok của phiên cha trước. Ca nào cần thì truyền GROK_HOOK_EVENT=...
# phía sau các cờ -u, nên gán đó vẫn thắng. Không đổi exit mong đợi của ca.
# stdout và stderr của hook vào cùng `out` như trước (perl bơm stdout rồi stderr về hai fd của nó, `2>&1` gộp).
run_case() {
  name="$1"; hook="$2"; want="$3"; payload="$4"; shift 4
  out="$(printf '%s' "${payload}" | env -u GROK_HOOK_EVENT -u GROK_HOOK_NAME -u GROK_SESSION_ID -u DEVKIT_AGENT \
        CLAUDE_PROJECT_DIR="${SANDBOX}" "$@" \
        ${HC_WRAP} bash "${HOOKS}/${hook}" 2>&1)"
  got=$?
  # hết giờ hoặc thông điệp watchdog được xét TRƯỚC khi so got với want: ca mong 2 mà watchdog bắn cũng có got == want, không được PASS
  if [ "${got}" -eq 142 ] || hc_is_wd "${out}"; then
    hc_watch "${name}" "${got}" "" "${out}"
    return 0
  fi
  if [ "${got}" -eq "${want}" ]; then
    PASS=$((PASS + 1))
    printf '  ok   %-46s exit=%s\n' "${name}" "${got}"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES="${FAILED_CASES}
  ✗ ${name}
      hook=${hook} want exit=${want}, got=${got}
      output: $(printf '%s' "${out}" | head -3 | tr '\n' ' ')"
    printf '  FAIL %-46s want=%s got=%s\n' "${name}" "${want}" "${got}"
  fi
  hc_check_limits
}
