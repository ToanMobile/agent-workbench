#!/usr/bin/env bash
# tests/gates/test_guard_shell_norm_monotonic.sh must not go red because the machine is busy (#147): under load the 7 s analysis
# watchdog of hooks/hardware_safety_gate.sh (production budget, unchanged) fires on a harmless CONTROL row and the hook answers rc 2
# with its "quá lớn / quá phức tạp" message. That is no verdict, so the row is run again; the safety net still has to catch a real defect.
# Oracle: HW_HOOK points at a wrapper around the real hook that plays a loaded machine.
#   - "once":   the first run of every payload the real hook passes ends in the watchdog message (rc 2); the second run is the real answer.
#               The monotonic test must PASS (before the fix: ✖ CONTROL hw rc 2 + VACUOUS).
#  03/11 (shard REG-DK-ALL-GATES-01, lane 2): mỗi chế độ một file để shard chạy ba lượt monotonic cùng lúc (nối tiếp: 646 s);
#  test_guard_shell_norm_load_retry.sh = once, _load_retry_always.sh, _load_retry_blocks.sh; wrapper + run_mono: tests/lib/guard_shell_norm_load_lib.sh.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="$DEVKIT_DIR/tests/gates/test_guard_shell_norm_monotonic.sh"
REAL_HW="$DEVKIT_DIR/hooks/hardware_safety_gate.sh"
. "$DEVKIT_DIR/tests/lib/guard_shell_norm_load_lib.sh"   # TMP, fails / ok / bad, wrapper hook máy tải nặng, run_mono

run_mono once;   rc=$?
[ "$rc" = 0 ] && ok "a watchdog answer on the first run of a CONTROL row is retried: the monotonic test passes" \
  || { bad "load simulation 'once': the monotonic test failed (rc $rc)"; head -5 "$TMP/once.out"; }

[ "$fails" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS ($fails)"; exit 1; }
