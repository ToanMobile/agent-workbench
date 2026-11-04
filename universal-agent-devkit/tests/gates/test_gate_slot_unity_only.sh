#!/usr/bin/env bash
# P5 (04/11): lượt gate mà mọi suite cần chạy đều là Unity hoặc nhẹ không xin slot pool 'gate'. Đo 04/11 08:48–08:57: hai lane Goods
# giữ cả 2 slot gate của máy, chỉ một lane có khoá unity-1.lock, lane kia giữ slot gate trong lúc chờ khoá Unity ⇒ gate repo khác
# xếp hàng vô ích. Khoá unity (1 Editor cả máy) đã giới hạn các lượt này.
# (u1) khoá unity bị giữ, gate chỉ có suite Unity đang chờ khoá đó: gate-1.lock (DEVKIT_GATE_SLOTS=1) vẫn trống; nhả khoá ⇒ gate exit 0
# (u2) suite nhẹ không phải Unity vẫn xếp hàng pool gate như cũ: gate-1 bị giữ, DEVKIT_GATE_SLOT_WAIT_S=1 ⇒ exit 4 BUSY
# Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/dk-gate-slot-unity.XXXXXX")"
HOLDERS=""
GATE_PID=""
cleanup() {
  local p
  touch "$TMP/release" "$TMP/release2" 2>/dev/null || true
  [ -n "$GATE_PID" ] && { kill "$GATE_PID" 2>/dev/null || true; wait "$GATE_PID" 2>/dev/null || true; }
  for p in $HOLDERS; do kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; done
  rm -rf "$TMP"
}
trap cleanup EXIT

FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

unset CLAUDE_PROJECT_DIR TARGET_DIR SB_HEAVY_SLOT_HELD DEVKIT_GATE_SLOT_HELD DEVKIT_GATE_SLOTS DEVKIT_GATE_SLOT_WAIT_S \
      DEVKIT_SLOT_PRIORITY GATE_TOTAL_BUDGET_S DEVKIT_CAPACITY DEVKIT_CAPACITY_CORES DEVKIT_CAPACITY_LOAD DEVKIT_SLOT_ADVISORY_HELD
export WORKTREE_TRUNK_MODE=0
export VACUITY_REVERT=0
export SB_HEAVY_SLOT_DIR="$TMP/slots"
mkdir -p "$SB_HEAVY_SLOT_DIR"
printf '0\n' > "$TMP/load"
export DEVKIT_SLOT_LOAD_FILE="$TMP/load"
export SB_HEAVY_SLOT_POLL_S=0.05
export DEVKIT_GATE_SLOTS=1
export DEVKIT_SENTINEL_MAX_S=999999999

hold_flock() {   # hold_flock <file khoá> <file sẵn sàng> <file nhả>
  python3 - "$1" "$2" "$3" <<'PY' &
import fcntl, os, sys, time
os.makedirs(os.path.dirname(sys.argv[1]), exist_ok=True)
with open(sys.argv[1], "a") as fh:
    fcntl.flock(fh, fcntl.LOCK_EX)
    open(sys.argv[2], "w").close()
    end = time.monotonic() + 60
    while time.monotonic() < end and not os.path.exists(sys.argv[3]):
        time.sleep(0.03)
PY
  LAST_HOLDER=$!
  HOLDERS="$HOLDERS $LAST_HOLDER"
  local i=0
  while [ ! -f "$2" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done
  [ -f "$2" ] || { fail "thiết lập: không giữ được khoá $1"; exit 1; }
}

lock_free() {   # exit 0 khi lấy được flock không chặn trên file
  python3 - "$1" <<'PY'
import fcntl, os, sys
fd = os.open(sys.argv[1], os.O_RDWR | os.O_CREAT, 0o600)
try:
    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
except OSError:
    sys.exit(1)
fcntl.flock(fd, fcntl.LOCK_UN)
os.close(fd)
PY
}

R="$TMP/repo"
make_repo() {   # make_repo <lệnh suite>
  rm -rf "$R" && mkdir -p "$R/src" "$R/.agents"
  git -C "$R" init -q -b main
  git -C "$R" config user.email t@example.invalid
  git -C "$R" config user.name t
  printf '.claude/\n' > "$R/.gitignore"
  printf '{"profile":"backend","lang":"vi"}\n' > "$R/.agents/active-profile.json"
  printf 'x = 1\n' > "$R/src/app.py"
  cat > "$R/unity-batch.sh" <<SH
#!/usr/bin/env bash
echo ran >> "$TMP/ran"
exit 0
SH
  cp "$R/unity-batch.sh" "$R/run_suite.sh"
  chmod +x "$R/unity-batch.sh" "$R/run_suite.sh"
  cat > "$R/.agents/regression_matrix.active.json" <<JSON
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-U","name":"u","command":"$1"}]}]}
JSON
  git -C "$R" add -A && git -C "$R" commit -qm init
  printf 'x = 2\n' > "$R/src/app.py"
  rm -f "$TMP/ran"
}

# ── (u1) ──
make_repo "bash unity-batch.sh editmode"
hold_flock "$SB_HEAVY_SLOT_DIR/unity-1.lock" "$TMP/held" "$TMP/release"
U_HOLDER=$LAST_HOLDER
SB_HEAVY_SLOT_WAIT_S=30 CLAUDE_PROJECT_DIR="$R" DEVKIT_SUITE_CACHE=0 \
  python3 "$GATE" --run-tests --full --json --no-checklist >"$TMP/u1.out" 2>&1 &
GATE_PID=$!
i=0
while ! grep -q "pool unity" "$TMP/u1.out" 2>/dev/null && [ "$i" -lt 400 ]; do sleep 0.05; i=$((i + 1)); done
if grep -q "pool unity" "$TMP/u1.out"; then
  if lock_free "$SB_HEAVY_SLOT_DIR/gate-1.lock"; then
    ok "(u1) gate chỉ có suite Unity chờ khoá unity mà không giữ slot gate"
  else
    fail "(u1) gate giữ gate-1.lock trong lúc chờ khoá unity (nghẽn hàng đợi gate của cả máy)"
  fi
else
  fail "(u1) gate không tới bước chờ khoá unity: $(tail -5 "$TMP/u1.out" | tr '\n' ' ')"
fi
touch "$TMP/release"; wait "$U_HOLDER" 2>/dev/null || true
wait "$GATE_PID"; rc=$?; GATE_PID=""
if [ "$rc" -eq 0 ] && [ -f "$TMP/ran" ]; then
  ok "(u1) nhả khoá unity ⇒ suite Unity chạy, gate exit 0"
else
  fail "(u1) rc=$rc ran=$([ -f "$TMP/ran" ] && echo yes || echo no): $(tail -6 "$TMP/u1.out" | tr '\n' ' ')"
fi

# ── (u2) ──
make_repo "bash run_suite.sh"
hold_flock "$SB_HEAVY_SLOT_DIR/gate-1.lock" "$TMP/held2" "$TMP/release2"
DEVKIT_GATE_SLOT_WAIT_S=1 CLAUDE_PROJECT_DIR="$R" DEVKIT_SUITE_CACHE=0 \
  python3 "$GATE" --run-tests --full --json --no-checklist >"$TMP/u2.out" 2>&1
rc=$?
touch "$TMP/release2"
if [ "$rc" -eq 4 ] && [ ! -f "$TMP/ran" ]; then
  ok "(u2) suite không phải Unity vẫn xếp hàng pool gate: slot bận ⇒ exit 4 BUSY, không chạy"
else
  fail "(u2) rc=$rc ran=$([ -f "$TMP/ran" ] && echo yes || echo no)"
fi

echo
if [ "$FAILS" -eq 0 ]; then
  echo "✅ test_gate_slot_unity_only: tất cả PASS"
  exit 0
fi
echo "❌ test_gate_slot_unity_only: $FAILS lỗi"
exit 1
