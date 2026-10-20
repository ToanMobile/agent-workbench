#!/usr/bin/env bash
# Test hồi quy (20/10): một test đã source tests/lib/clean_git_env.sh không được chờ 2 heavy slot THẬT của máy.
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

# Hai merge gate "thật" giữ cả 2 slot của máy. Marker = holder đã vào slot; exec để sleep là chính tiến trình con của wrapper
# (pkill -P giết được), output bỏ đi để sleep sót lại không giữ pipe stdout của gate.
for n in 1 2; do
  python3 "$SLOT_BIN" -- bash -c "touch '$TMP/held$n'; exec sleep 60" >/dev/null 2>&1 &
  PIDS="$PIDS $!"
done
for _ in $(seq 1 300); do
  [ -f "$TMP/held1" ] && [ -f "$TMP/held2" ] && break
  sleep 0.1
done
if [ -f "$TMP/held1" ] && [ -f "$TMP/held2" ] && ! python3 "$SLOT_BIN" --nonblock -- true 2>/dev/null; then
  ok "both machine slots are held"
else
  fail "could not occupy both machine slots"
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
