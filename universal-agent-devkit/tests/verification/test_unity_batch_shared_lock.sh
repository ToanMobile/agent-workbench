#!/usr/bin/env bash
# P5 (04/11): unity-batch.sh và pool `unity` của heavy_slot dùng CHUNG một khoá máy (<slot dir>/unity-1.lock). Trước đây unity-batch
# chờ khoá riêng (~/.config/universal-agent-devkit/unity-batch.lock) không hạn, bên trong đồng hồ 900 s của suite gate: REG-GAME-02 của
# Goods hết giờ khi Editor chưa chạy được bao lâu (evidence issue-71-build 04/11).
# (a) khoá chung đang bị giữ, không UNITY_BATCH_LOCK: chờ tối đa UNITY_LOCK_WAIT_S rồi exit 2 UNTESTED, không mở Editor
# (b) cùng khoá bị giữ nhưng gate cha đã giữ khoá Unity (SB_HEAVY_SLOT_HELD=1): không xin lại, Editor chạy, exit 0
# (c) UNITY_BATCH_LOCK đặt tường minh: dùng đúng file đó kể cả khi SB_HEAVY_SLOT_HELD=1
# Tương thích bash 3.2.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BATCH="$DEVKIT_DIR/profiles/game/scripts/unity-batch.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/dk-unity-shared-lock.XXXXXX")"
HOLDER=""
cleanup() {
  touch "$TMP/release" 2>/dev/null || true
  [ -n "$HOLDER" ] && { kill "$HOLDER" 2>/dev/null || true; wait "$HOLDER" 2>/dev/null || true; }
  rm -rf "$TMP"
}
trap cleanup EXIT
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

unset UNITY_BATCH_LOCK SB_HEAVY_SLOT_HELD UNITY_LOCK_WAIT_S
BIN="$TMP/bin"
mkdir -p "$BIN"
cat > "$BIN/nice" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "-n" ]; then shift 2; fi
exec "$@"
SH
cat > "$BIN/Unity" <<'SH'
#!/usr/bin/env bash
: > "$STARTED"
log=""
while [ $# -gt 0 ]; do
  case "$1" in -logFile) log="$2"; shift ;; esac
  shift
done
[ -n "$log" ] && echo "fake unity" > "$log"
exit 0
SH
chmod +x "$BIN/nice" "$BIN/Unity"

PROJ="$TMP/proj"
mkdir -p "$PROJ/Assets" "$PROJ/ProjectSettings"
printf 'm_EditorVersion: 6000.0.1f1\n' > "$PROJ/ProjectSettings/ProjectVersion.txt"
printf 'PlayerSettings:\n  companyName: DevKitTest\n  productName: SharedLock\n' > "$PROJ/ProjectSettings/ProjectSettings.asset"

SLOTS="$TMP/slots"
mkdir -p "$SLOTS"

# Giữ flock trên khoá chung của pool unity như heavy_slot.acquire_pool làm, tới khi có file release
python3 - "$SLOTS/unity-1.lock" "$TMP/held" "$TMP/release" <<'PY' &
import fcntl, os, sys, time
with open(sys.argv[1], "a") as fh:
    fcntl.flock(fh, fcntl.LOCK_EX)
    open(sys.argv[2], "w").close()
    end = time.monotonic() + 60
    while time.monotonic() < end and not os.path.exists(sys.argv[3]):
        time.sleep(0.03)
PY
HOLDER=$!
i=0
while [ ! -f "$TMP/held" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done
[ -f "$TMP/held" ] || { fail "thiết lập: không giữ được $SLOTS/unity-1.lock"; exit 1; }

run_batch() {   # run_batch <tên> [biến môi trường thêm …]
  local name="$1"; shift
  env PATH="$BIN:$PATH" STARTED="$TMP/started-$name" UNITY_KEEP_PREFS=1 UNITY_PATH="$BIN/Unity" UNITY_PROJECT="$PROJ" \
    UNITY_BATCH_OUT="$TMP/out-$name" UNITY_TIMEOUT=30 SB_HEAVY_SLOT_DIR="$SLOTS" "$@" \
    bash "$BATCH" compile >"$TMP/$name.out" 2>&1
}

# (a)
run_batch a UNITY_LOCK_WAIT_S=1
rc=$?
if [ "$rc" -eq 2 ] && [ ! -f "$TMP/started-a" ] && grep -q "unity lock busy" "$TMP/a.out"; then
  ok "(a) khoá chung bị giữ: hết UNITY_LOCK_WAIT_S thì exit 2 UNTESTED, không mở Editor"
else
  fail "(a) rc=$rc started=$([ -f "$TMP/started-a" ] && echo yes || echo no) out=$(tail -3 "$TMP/a.out" | tr '\n' ' ')"
fi

# (b)
run_batch b SB_HEAVY_SLOT_HELD=1 UNITY_LOCK_WAIT_S=1
rc=$?
if [ "$rc" -eq 0 ] && [ -f "$TMP/started-b" ]; then
  ok "(b) gate cha đã giữ khoá Unity (SB_HEAVY_SLOT_HELD=1): không xin lại, Editor chạy, exit 0"
else
  fail "(b) rc=$rc started=$([ -f "$TMP/started-b" ] && echo yes || echo no) out=$(tail -3 "$TMP/b.out" | tr '\n' ' ')"
fi

# (c)
python3 - "$TMP/own.lock" "$TMP/held2" "$TMP/release2" <<'PY' &
import fcntl, os, sys, time
with open(sys.argv[1], "a") as fh:
    fcntl.flock(fh, fcntl.LOCK_EX)
    open(sys.argv[2], "w").close()
    end = time.monotonic() + 60
    while time.monotonic() < end and not os.path.exists(sys.argv[3]):
        time.sleep(0.03)
PY
H2=$!
i=0
while [ ! -f "$TMP/held2" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done
run_batch c SB_HEAVY_SLOT_HELD=1 UNITY_BATCH_LOCK="$TMP/own.lock" UNITY_LOCK_WAIT_S=1
rc=$?
touch "$TMP/release2"; wait "$H2" 2>/dev/null || true
if [ "$rc" -eq 2 ] && [ ! -f "$TMP/started-c" ]; then
  ok "(c) UNITY_BATCH_LOCK tường minh vẫn được xin dù SB_HEAVY_SLOT_HELD=1"
else
  fail "(c) rc=$rc started=$([ -f "$TMP/started-c" ] && echo yes || echo no) out=$(tail -3 "$TMP/c.out" | tr '\n' ' ')"
fi

[ "$FAILS" -eq 0 ] && echo "test_unity_batch_shared_lock: PASS" || { echo "test_unity_batch_shared_lock: FAIL ($FAILS)"; exit 1; }
