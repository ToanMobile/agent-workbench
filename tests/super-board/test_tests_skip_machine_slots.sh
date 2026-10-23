#!/usr/bin/env bash
# Test hồi quy (20/10): một test đã source tests/lib/clean_git_env.sh không được chờ máy (tải máy / khoá heavy slot THẬT).
# Merge gate thật của 5 repo giữ slot ở ~/.claude/super-board/locks; verify giả (echo) của test_merge_gate_ff.sh chờ tới 3600 s
# khi chạy ngoài một gate đang giữ slot (chạy tay, gate impacted không có suite nặng, worktree finish) → suite TIMEOUT.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SLOT_BIN="$ROOT/.claude/bin/super-board-heavy-slot.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-machine-slots-test.XXXXXX")"
PIDS=""
cleanup() {
  # Lệnh con (sleep) trước, rồi wrapper giữ slot: chỉ kill wrapper thì sleep còn sống tới hết giờ.
  for p in $PIDS; do pkill -P "$p" 2>/dev/null || true; kill "$p" 2>/dev/null || true; done
  wait 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

# "Máy" giả: HOME riêng, nên slot mặc định là $TMP/home/.claude/super-board/locks, không đụng slot thật.
export HOME="$TMP/home"
mkdir -p "$HOME"
unset SB_HEAVY_SLOT_DIR SB_HEAVY_SLOT_HELD SB_HEAVY_SLOT_WAIT_S
export SB_HEAVY_SLOT_POLL_S="0.1"

# Máy bận theo luật hiện tại (P1 20/10: không còn 2 slot — suite chạy theo tải máy, dưới ngưỡng tải là chạy): tải 1 phút đọc từ file = 150.
# Lệnh bọc heavy slot mà không được cho chạy sẵn thì --nonblock từ chối (đối chứng: máy bận thật sự chặn).
unset DEVKIT_SLOT_ADVISORY_HELD DEVKIT_SLOT_LOAD_MAX DEVKIT_SLOT_LOAD_WAIT_S DEVKIT_CAPACITY DEVKIT_CAPACITY_CORES DEVKIT_CAPACITY_LOAD
# T0052: ngưỡng mặc định là capacity hold_load (8 × lõi); máy giả 12 lõi (96) để tải 150 luôn là "bận", kể cả khi người gọi đặt
# DEVKIT_CAPACITY (suite_env của gate giữ nút đó) hay máy thật ≥ 19 lõi (hold_load ≥ 152).
export DEVKIT_CAPACITY_CORES=12
export DEVKIT_SLOT_LOAD_FILE="$TMP/load"; echo 150 > "$DEVKIT_SLOT_LOAD_FILE"
if ! python3 "$SLOT_BIN" --nonblock -- true 2>/dev/null; then
  ok "the machine is busy (load 150 >= hold_load 96): --nonblock refuses"
else
  fail "could not make the machine busy (--nonblock ran at load 150)"
fi

# Một test source helper rồi chạy verify bọc heavy slot: phải chạy ngay, không đợi slot của máy.
rc=0
( . "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"; python3 "$SLOT_BIN" --nonblock -- true ) || rc=$?
if [ "$rc" -eq 0 ]; then
  ok "a test that sources clean_git_env.sh runs without the machine's heavy slots"
else
  fail "a test that sources clean_git_env.sh is gated on the machine's heavy slots (exit $rc)"
fi

[ "$FAILS" -eq 0 ] && echo "✅ test_tests_skip_machine_slots: all passed" || echo "❌ test_tests_skip_machine_slots: $FAILS failed"
exit "$FAILS"
