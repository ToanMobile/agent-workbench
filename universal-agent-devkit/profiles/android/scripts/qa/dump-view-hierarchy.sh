#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# dump-view-hierarchy.sh — Real Device UIAutomator Hierarchy Dump
#
# Dumps the active window's UI layout hierarchy to local XML for automated
# layout inspection, touch target auditing, and accessibility verification.
#
# Usage: dump-view-hierarchy.sh [-s SERIAL] [output_xml_path]
#   Device: -s SERIAL, else ANDROID_SERIAL, else the only online device.
#   Every adb call goes through adb-safe-exec.sh, so the device policy of
#   hooks/hardware_safety_gate.sh (.adb-denylist, ADB_DENY_SERIALS, …) applies.
#   Prints `density=<dpi>`: bounds in the XML are px; dp = px * 160 / dpi.
# Exit: 0 dumped · 2 usage / refused by the device policy · 3 UNVERIFIED (no adb,
#       no device or several devices without -s) · other = adb-safe-exec's own exit.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

SAFE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/adb-safe-exec.sh"
SERIAL="${ANDROID_SERIAL:-}"
if [ "${1:-}" = "-s" ]; then
  [ $# -ge 2 ] || { echo "✖ usage: dump-view-hierarchy.sh [-s SERIAL] [output_xml_path]" >&2; exit 2; }
  SERIAL="$2"; shift 2
fi
OUT_FILE="${1:-build/view_hierarchy.xml}"

unverified() { echo "⚠️  UNVERIFIED — [DEVICE QA GATE] $1" >&2; exit 3; }
command -v adb >/dev/null 2>&1 || unverified "adb not found on PATH"
if [ -z "${SERIAL}" ]; then
  ONLINE="$(adb devices 2>/dev/null | tr -d '\r' | awk 'NR>1 && $2=="device"{print $1}')"
  COUNT="$(printf '%s' "${ONLINE}" | grep -c . || true)"
  [ "${COUNT}" -ge 1 ] || unverified "Không phát hiện thiết bị Android online!"
  [ "${COUNT}" -eq 1 ] || unverified "${COUNT} thiết bị online — chọn một bằng -s SERIAL"
  SERIAL="${ONLINE}"
fi

# adb <args> on SERIAL, judged by adb-safe-exec (device policy, error text, exit code). --no-logcat: these commands start no
# app, so a crash on the device meanwhile (another app, or the app under test whose screen is being dumped) is not theirs.
safe() { bash "${SAFE}" -s "${SERIAL}" --wait 0 --no-logcat -- "$@"; }

echo "📱 [UI DUMP] Đang trích xuất cây phân cấp giao diện (UIAutomator dump) trên ${SERIAL}..."
LOG="$(safe shell uiautomator dump /sdcard/view_dump.xml 2>&1)" || { RC=$?; printf '%s\n' "${LOG}" >&2; exit "${RC}"; }
mkdir -p "$(dirname "${OUT_FILE}")"   # only once the device was accepted and dumped: a refused run leaves nothing behind
LOG="$(safe pull /sdcard/view_dump.xml "${OUT_FILE}" 2>&1)" || { RC=$?; printf '%s\n' "${LOG}" >&2; exit "${RC}"; }
DENSITY="$(safe shell wm density 2>/dev/null | tr -d '\r' | awk -F': *' '/density:/{d=$2} END{print d}')"
safe shell rm -f /sdcard/view_dump.xml >/dev/null 2>&1 || echo "⚠️ không xoá được /sdcard/view_dump.xml (bỏ qua)" >&2

echo "✔ Đã xuất cây giao diện thành công vào: ${OUT_FILE}"
if [ -n "${DENSITY}" ]; then
  echo "density=${DENSITY} (bounds là px; dp = px * 160 / ${DENSITY}; vùng chạm cần ≥ 48 dp)"
else
  echo "density=unknown (không đọc được wm density — chưa đổi được px sang dp)"
fi
