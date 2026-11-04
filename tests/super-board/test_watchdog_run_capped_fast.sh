#!/usr/bin/env bash
# Test hồi quy (tối ưu gate 03/11): run_capped của .claude/bin/super-board-watchdog.sh trả về ngay khi lệnh con xong, không
# ngủ chẵn 0,5 s mỗi vòng chờ. Đo 03/11: mỗi lệnh gh / card của watchdog tốn ≥ 0,5 s dù lệnh xong tức thì; REG-SB-RUNNER-WATCHDOG-01
# 208 s ⇒ 80 s khi vòng chờ ngắn lại (137/137 ca vẫn qua). Chu kỳ chờ tăng dần 0,02 ⇒ 0,5 s: lệnh dài vẫn chỉ thức mỗi 0,5 s.
#   a. 10 lần `run_capped 5 true` tổng < 3 s (bản cũ ≥ 5 s: 10 × 0,5 s);
#   b. hết giờ vẫn exit 124 và giết lệnh con (run_capped 1 sleep 30 xong trong < 10 s);
#   c. mã thoát của lệnh con giữ nguyên (exit 7 ⇒ 7).
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WD="$ROOT/.claude/bin/super-board-watchdog.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
awk '/^run_capped\(\) \{/{p=1} p{print} p&&/^}/{p=0}' "$WD" > "$TMP/rc_fn.sh"
[ -s "$TMP/rc_fn.sh" ] || { echo "FAIL không tách được run_capped từ $WD"; exit 1; }
. "$TMP/rc_fn.sh"
fail=0
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }

t0=$(now)
i=0; while [ $i -lt 10 ]; do run_capped 5 true || { echo "FAIL a. run_capped 5 true exit $?"; fail=1; }; i=$((i + 1)); done
t1=$(now)
if perl -e 'exit(($ARGV[1] - $ARGV[0]) < 3 ? 0 : 1)' "$t0" "$t1"; then
  echo "PASS a. 10 × run_capped true: $(perl -e 'printf "%.2f", $ARGV[1] - $ARGV[0]' "$t0" "$t1") s"
else
  echo "FAIL a. 10 × run_capped true: $(perl -e 'printf "%.2f", $ARGV[1] - $ARGV[0]' "$t0" "$t1") s (muốn < 3 s)"; fail=1
fi

t0=$(now); run_capped 1 sleep 30; rc=$?; t1=$(now)
if [ "$rc" = 124 ] && perl -e 'exit(($ARGV[1] - $ARGV[0]) < 10 ? 0 : 1)' "$t0" "$t1"; then echo "PASS b. hết giờ exit 124"
else echo "FAIL b. hết giờ: rc=$rc sau $(perl -e 'printf "%.1f", $ARGV[1] - $ARGV[0]' "$t0" "$t1") s (muốn 124, < 10 s)"; fail=1; fi

run_capped 5 sh -c 'exit 7'; rc=$?
if [ "$rc" = 7 ]; then echo "PASS c. mã thoát lệnh con giữ nguyên"; else echo "FAIL c. rc=$rc (muốn 7)"; fail=1; fi
exit "$fail"
