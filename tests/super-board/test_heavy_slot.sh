#!/usr/bin/env bash
# Test hồi quy cho semaphore toàn máy giới hạn tối đa 2 lượt chạy --full (heavy_slot.py / super-board-heavy-slot.py).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SLOT_BIN="$ROOT/.claude/bin/super-board-heavy-slot.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-heavyslot-test.XXXXXX")"
PIDS=""
cleanup() {
  for p in $PIDS; do kill "$p" 2>/dev/null || true; done
  rm -rf "$TMP"
}
trap cleanup EXIT

export SB_HEAVY_SLOT_DIR="$TMP/locks"
export SB_HEAVY_SLOT_POLL_S="0.1"
unset SB_HEAVY_SLOT_HELD

# ── 1. Hai tiến trình giữ 2 slot; tiến trình thứ 3 thử LOCK_NB (--nonblock) phải thất bại cho tới khi 1 slot được thả.
python3 "$SLOT_BIN" -- bash -c "touch '$TMP/held1'; sleep 30" >/dev/null 2>&1 &
P1=$!; PIDS="$PIDS $P1"
python3 "$SLOT_BIN" -- bash -c "touch '$TMP/held2'; sleep 30" >/dev/null 2>&1 &
P2=$!; PIDS="$PIDS $P2"

for i in $(seq 1 30); do
  [ -f "$TMP/held1" ] && [ -f "$TMP/held2" ] && break
  sleep 0.1
done

if [ -f "$TMP/held1" ] && [ -f "$TMP/held2" ]; then
  ok "two processes acquired heavy slots concurrently"
else
  fail "two processes could not acquire slots (held1=$([ -f "$TMP/held1" ] && echo yes || echo no) held2=$([ -f "$TMP/held2" ] && echo yes || echo no))"
fi

python3 "$SLOT_BIN" --nonblock -- true >/dev/null 2>&1
rc_nb=$?
if [ "$rc_nb" -ne 0 ]; then
  ok "third process cannot acquire LOCK_NB while both slots are held"
else
  fail "third process acquired LOCK_NB even though 2 slots were already held"
fi

# ── 2. Tiến trình thứ 3 ở chế độ chờ sẽ lấy được slot ngay khi P1 kết thúc và thả khoá.
python3 "$SLOT_BIN" -- bash -c "touch '$TMP/held3'" >"$TMP/wait3.log" 2>&1 &
P3=$!; PIDS="$PIDS $P3"
sleep 0.3
if [ ! -f "$TMP/held3" ]; then
  ok "third blocking process waits while both slots are busy"
else
  fail "third blocking process ran before any slot was released"
fi

kill "$P1" 2>/dev/null || true
wait "$P1" 2>/dev/null || true

for i in $(seq 1 30); do
  [ -f "$TMP/held3" ] && break
  sleep 0.1
done
wait "$P3" 2>/dev/null; rc3=$?
if [ -f "$TMP/held3" ] && [ "$rc3" -eq 0 ]; then
  ok "third process acquired slot and exited 0 once P1 released its slot"
else
  fail "third process did not run after P1 released slot (rc=$rc3)"
fi

kill "$P2" 2>/dev/null || true
wait "$P2" 2>/dev/null || true

# ── 3. Cùng tiến trình (SB_HEAVY_SLOT_HELD=1) gọi acquire lần hai không chiếm slot thứ hai.
rm -f "$TMP/reentrant_ok"
python3 "$SLOT_BIN" -- bash -c "
  # Bên trong tiến trình đã giữ slot 1 (SB_HEAVY_SLOT_HELD=1), gọi lồng thêm một lần và giữ nó:
  python3 '$SLOT_BIN' -- bash -c '
    # Một tiến trình độc lập từ bên ngoài (unset SB_HEAVY_SLOT_HELD) vẫn phải lấy được slot 2 bằng --nonblock:
    env -u SB_HEAVY_SLOT_HELD python3 \"$SLOT_BIN\" --nonblock -- touch \"$TMP/reentrant_ok\"
  '
" >/dev/null 2>&1

if [ -f "$TMP/reentrant_ok" ]; then
  ok "nested acquire with SB_HEAVY_SLOT_HELD=1 does not consume the second slot"
else
  fail "nested acquire consumed the second slot (external --nonblock failed)"
fi

# ── 4. Không tìm thấy heavy_slot.py của DevKit: log một dòng và chạy tiếp lệnh, thoát 0.
mkdir -p "$TMP/standalone/.claude/bin"
cp "$SLOT_BIN" "$TMP/standalone/.claude/bin/super-board-heavy-slot.py"
( cd "$TMP/standalone" && SB_REPO_PATH="$TMP/standalone" python3 "$TMP/standalone/.claude/bin/super-board-heavy-slot.py" -- touch "$TMP/fallback_ok" ) >"$TMP/fallback.log" 2>&1
rc_fb=$?
if [ "$rc_fb" -eq 0 ] && [ -f "$TMP/fallback_ok" ] && [ -s "$TMP/fallback.log" ]; then
  ok "missing DevKit heavy_slot.py: logs one line and runs command with exit 0"
else
  fail "missing DevKit fallback failed (rc=$rc_fb file=$([ -f "$TMP/fallback_ok" ] && echo yes || echo no) log='$(cat "$TMP/fallback.log" 2>/dev/null)')"
fi

[ "$FAILS" -eq 0 ] && echo "✅ test_heavy_slot: all passed" || { echo "❌ test_heavy_slot: $FAILS failed"; exit 1; }
