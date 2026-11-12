#!/usr/bin/env bash
# #862 (#1054): --weekdays entries must each be exactly one digit 0-7. '14' / '17' (a missing comma) passed the per-character
# check and int(d)%7 turned them into other days.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
S="$DEVKIT_DIR/bin/gate-full-schedule.sh"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
for bad in 14 17 "1,47" 10; do
  bash "$S" install --weekdays "$bad" >/dev/null 2>&1; rc=$?
  [ "$rc" = 2 ] && ok "--weekdays $bad rejected (usage, exit 2)" || fail "--weekdays $bad: rc=$rc (want 2)"
done
# a valid list must get past the weekdays check: the failure (if any) is not the weekdays usage line
out="$(bash "$S" status --weekdays 1,4 2>&1)"; echo "$out" | grep -q "usage: gate-full-schedule" && fail "--weekdays 1,4 rejected" || ok "--weekdays 1,4 accepted"
[ "$FAILS" = 0 ]
