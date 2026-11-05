#!/usr/bin/env bash
# tests/gates/test_guard_shell_norm_monotonic.sh must not go red because the machine is busy (#147): under load the 7 s analysis
# watchdog of hooks/hardware_safety_gate.sh (production budget, unchanged) fires on a harmless CONTROL row and the hook answers rc 2
# with its "quá lớn / quá phức tạp" message. That is no verdict, so the row is run again; the safety net still has to catch a real defect.
# Oracle: HW_HOOK points at a wrapper around the real hook that plays a loaded machine.
#   - "blocks": the hook blocks a control for a real reason (no watchdog message). The monotonic test must FAIL at once.
#  03/11 (shard REG-DK-ALL-GATES-01, lane 2): mỗi chế độ một file để shard chạy ba lượt monotonic cùng lúc (nối tiếp: 646 s);
#  test_guard_shell_norm_load_retry.sh = once, _load_retry_always.sh, _load_retry_blocks.sh; wrapper + run_mono: tests/lib/guard_shell_norm_load_lib.sh.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="$DEVKIT_DIR/tests/gates/test_guard_shell_norm_monotonic.sh"
REAL_HW="$DEVKIT_DIR/hooks/hardware_safety_gate.sh"
. "$DEVKIT_DIR/tests/lib/guard_shell_norm_load_lib.sh"   # TMP, fails / ok / bad, wrapper hook máy tải nặng, run_mono

run_mono blocks; rc=$?
[ "$rc" != 0 ] && grep -q "CONTROL" "$TMP/blocks.out" && ok "a control blocked for a real reason still fails (no retry masks it)" \
  || bad "load simulation 'blocks': a really blocked CONTROL was not reported (rc $rc)"

[ "$fails" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS ($fails)"; exit 1; }
