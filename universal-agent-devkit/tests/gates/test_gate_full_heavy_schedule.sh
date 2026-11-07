#!/usr/bin/env bash
# Test hồi quy (gate speed v26 mục 6): heavy gate chạy hai lần một tuần — gate-full-schedule.sh install mặc định ghi StartCalendarInterval
# là MẢNG {Weekday, Hour, Minute} cho thứ Hai (1) và thứ Năm (4) lúc 00:00; --weekdays đổi danh sách (0 và 7 cùng là Chủ nhật, gộp một mục);
# --weekdays sai ⇒ exit 2, không plist. launchctl giả, LaunchAgents trong thư mục tạm, kit chép ra ngoài git (như e1 của test_gate_full_nightly).
#   s1. mặc định: hai mục, Weekday 1 và 4, Hour 0, Minute 0; plist hợp lệ;
#   s2. --weekdays 0,7,3 --hour 2: hai mục Weekday 0 và 3, Hour 2;
#   s3. --weekdays 1,9 / rỗng / ",1": exit 2, không plist.
# Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

T="$(mktemp -d "${TMPDIR:-/tmp}/gate-full-heavy-sched.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT

mkdir -p "$T/kit/bin" "$T/la" "$T/repo"
cp "$DEVKIT_DIR/bin/gate-full-schedule.sh" "$DEVKIT_DIR/bin/gate_full.py" "$T/kit/bin/"
git -c init.defaultBranch=main init -q "$T/repo"
printf '#!/bin/sh\necho "$@" >>"%s/launchctl.calls"\n' "$T" >"$T/fakelaunchctl"
printf '#!/bin/sh\nprintf %%s "/usr/bin:/bin"\n' >"$T/fakeshell"
chmod +x "$T/fakelaunchctl" "$T/fakeshell"
export DEVKIT_LAUNCH_AGENTS_DIR="$T/la" DEVKIT_LAUNCHCTL="$T/fakelaunchctl" DEVKIT_GATE_FULL_LOG_DIR="$T/logs" SHELL="$T/fakeshell"
SCHED="$T/kit/bin/gate-full-schedule.sh"
plist() { ls "$T/la"/com.toanmobile.devkit.gate-full.*.plist 2>/dev/null | head -1; }
cal() {   # in StartCalendarInterval của plist dạng JSON gọn
  python3 -c 'import json, plistlib, sys; print(json.dumps(plistlib.load(open(sys.argv[1], "rb")).get("StartCalendarInterval"), sort_keys=True))' "$1" 2>/dev/null
}

bash "$SCHED" install --repo "$T/repo" >"$T/out" 2>&1; rc=$?
P="$(plist)"
chk "s1. mặc định: mảng Weekday 1 và 4 lúc 00:00, plist hợp lệ" \
  '[ "$rc" = 0 ] && [ -n "$P" ] && plutil -lint "$P" >/dev/null 2>&1 && [ "$(cal "$P")" = "[{\"Hour\": 0, \"Minute\": 0, \"Weekday\": 1}, {\"Hour\": 0, \"Minute\": 0, \"Weekday\": 4}]" ]' \
  "rc=$rc cal=$(cal "$P") $(tail -3 "$T/out")"
chk "s1b. lời báo cài nói các thứ, không nói mỗi ngày" 'grep -q "các thứ 1,4" "$T/out" && ! grep -q "mỗi ngày" "$T/out"' "$(cat "$T/out")"
rm -f "$T/la"/*.plist
bash "$SCHED" install --repo "$T/repo" --weekdays 0,7,3 --hour 2 >"$T/out" 2>&1; rc=$?
P="$(plist)"
chk "s2. --weekdays 0,7,3 --hour 2: Chủ nhật gộp một mục, Weekday 0 và 3, Hour 2" \
  '[ "$rc" = 0 ] && [ "$(cal "$P")" = "[{\"Hour\": 2, \"Minute\": 0, \"Weekday\": 0}, {\"Hour\": 2, \"Minute\": 0, \"Weekday\": 3}]" ]' \
  "rc=$rc cal=$(cal "$P") $(tail -3 "$T/out")"
for w in 1,9 "" ,1 1,,4 x; do
  rm -f "$T/la"/*.plist
  bash "$SCHED" install --repo "$T/repo" --weekdays "$w" >"$T/out" 2>&1; rc=$?
  chk "s3. --weekdays '$w' sai: exit 2, không plist" '[ "$rc" = 2 ] && [ -z "$(plist)" ]' "rc=$rc $(tail -2 "$T/out")"
done

echo
[ "$fails" -eq 0 ] && { echo "PASS test_gate_full_heavy_schedule"; exit 0; }
echo "FAIL test_gate_full_heavy_schedule ($fails)"; exit 1
