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

# ── 5. Hết thời gian chờ: không chạy lệnh (không nhập hội thành tiến trình --full thứ ba).
export SB_HEAVY_SLOT_WAIT_S=0.3
python3 "$SLOT_BIN" -- bash -c "touch '$TMP/holdA'; sleep 30" >/dev/null 2>&1 &
PA=$!; PIDS="$PIDS $PA"
python3 "$SLOT_BIN" -- bash -c "touch '$TMP/holdB'; sleep 30" >/dev/null 2>&1 &
PB=$!; PIDS="$PIDS $PB"
for i in $(seq 1 30); do
  [ -f "$TMP/holdA" ] && [ -f "$TMP/holdB" ] && break
  sleep 0.1
done
rm -f "$TMP/should_not_run"
python3 "$SLOT_BIN" -- touch "$TMP/should_not_run" >"$TMP/waitfail.log" 2>&1
rc_to=$?
if [ "$rc_to" -ne 0 ] && [ ! -f "$TMP/should_not_run" ]; then
  ok "wait expired: command did not run"
else
  fail "wait expired but command ran (rc=$rc_to file=$([ -f "$TMP/should_not_run" ] && echo yes || echo no))"
fi
kill "$PA" "$PB" 2>/dev/null || true
wait "$PA" "$PB" 2>/dev/null || true
unset SB_HEAVY_SLOT_WAIT_S

# ── 6. post-fix-gate --force-full cũng không chạy suite khi hết slot.
GATE_PY="$ROOT/universal-agent-devkit/bin/post-fix-gate.py"
REPO="$TMP/gate-repo"
MARKER="$TMP/suite_ran"
mkdir -p "$REPO/src" "$REPO/templates"
(
  cd "$REPO" && git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt
  printf '%s\n' '{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],"mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"touch '"$MARKER"'"}]}]}' > templates/regression_matrix.json
  git add -A && git commit -qm init
)
echo "fun ok() = 2" > "$REPO/src/Core.kt"
python3 "$SLOT_BIN" -- bash -c "touch '$TMP/holdC'; sleep 30" >/dev/null 2>&1 &
PC=$!; PIDS="$PIDS $PC"
python3 "$SLOT_BIN" -- bash -c "touch '$TMP/holdD'; sleep 30" >/dev/null 2>&1 &
PD=$!; PIDS="$PIDS $PD"
for i in $(seq 1 30); do
  [ -f "$TMP/holdC" ] && [ -f "$TMP/holdD" ] && break
  sleep 0.1
done
export SB_HEAVY_SLOT_WAIT_S=0.4
( cd "$REPO" && python3 "$GATE_PY" --matrix "$REPO/templates/regression_matrix.json" --run-tests --force-full --allow-no-tests --allow-orphan-tests --brief ) >"$TMP/gate_slot.log" 2>&1
rc_gate=$?
unset SB_HEAVY_SLOT_WAIT_S
kill "$PC" "$PD" 2>/dev/null || true
wait "$PC" "$PD" 2>/dev/null || true
if [ "$rc_gate" -ne 0 ] && [ ! -f "$MARKER" ] && grep -qE "hết thời gian chờ|stayed busy past the wait" "$TMP/gate_slot.log"; then
  ok "post-fix-gate did not start the suite after the slot wait"
else
  fail "post-fix-gate slot wait (rc=$rc_gate marker=$([ -f "$MARKER" ] && echo yes || echo no)): $(grep -E 'KẾT LUẬN|VERDICT' "$TMP/gate_slot.log" | tail -2)"
fi

# ── 7. ./gradlew và unity-batch.sh xin slot dù không --full. Đường dẫn chỉ chứa chữ unity thì vẫn chạy.
python3 "$SLOT_BIN" -- bash -c "touch '$TMP/holdE'; sleep 30" >/dev/null 2>&1 &
PE=$!; PIDS="$PIDS $PE"
python3 "$SLOT_BIN" -- bash -c "touch '$TMP/holdF'; sleep 30" >/dev/null 2>&1 &
PF=$!; PIDS="$PIDS $PF"
for i in $(seq 1 30); do
  [ -f "$TMP/holdE" ] && [ -f "$TMP/holdF" ] && break
  sleep 0.1
done
export SB_HEAVY_SLOT_WAIT_S=0.4
slot_repo() { # $1 name  $2 command  $3 log
  local repo="$TMP/$1" marker_cmd="$2" log="$3"
  mkdir -p "$repo/src" "$repo/templates"
  (
    cd "$repo" && git init -q . && git config user.email t@t && git config user.name t
    echo "fun ok() = 1" > src/Core.kt
    python3 - "$repo/templates/regression_matrix.json" "$marker_cmd" <<'PY'
import json, sys
path, command = sys.argv[1:]
doc = {"project": "t", "rules": [{"component": "Core", "watch_files": ["src/Core.kt"],
  "mandatory_regression_tests": [{"id": "REG-1", "name": "core", "command": command}]}]}
open(path, "w").write(json.dumps(doc))
PY
    git add -A && git commit -qm init
  )
  echo "fun ok() = 2" > "$repo/src/Core.kt"
  ( cd "$repo" && python3 "$GATE_PY" --matrix "$repo/templates/regression_matrix.json" --run-tests --allow-no-tests --allow-orphan-tests --brief ) >"$log" 2>&1
}
GRADLE_MARKER="$TMP/gradle_ran"
UB_MARKER="$TMP/unity_batch_ran"
LIGHT_MARKER="$TMP/light_unity_ran"
LIGHT_CMD="$TMP/test_unity_probe.sh"
printf '#!/usr/bin/env bash\ntouch %q\n' "$LIGHT_MARKER" > "$LIGHT_CMD"
chmod +x "$LIGHT_CMD"
slot_repo gradle "bash -c 'touch $GRADLE_MARKER; exec ./gradlew test'" "$TMP/gradle_slot.log"
rc_gradle=$?
slot_repo ubatch "bash -c 'touch $UB_MARKER; exec unity-batch.sh editmode'" "$TMP/ubatch_slot.log"
rc_ubatch=$?
slot_repo light "bash $LIGHT_CMD" "$TMP/light_slot.log"
rc_light=$?
unset SB_HEAVY_SLOT_WAIT_S
kill "$PE" "$PF" 2>/dev/null || true
wait "$PE" "$PF" 2>/dev/null || true
if [ "$rc_gradle" -ne 0 ] && [ ! -f "$GRADLE_MARKER" ] && grep -qE "hết thời gian chờ|stayed busy past the wait" "$TMP/gradle_slot.log"; then
  ok "gradlew takes a heavy slot without --full and does not run when both slots are held"
else
  fail "gradlew without --full (rc=$rc_gradle marker=$([ -f "$GRADLE_MARKER" ] && echo yes || echo no)): $(tail -5 "$TMP/gradle_slot.log")"
fi
if [ "$rc_ubatch" -ne 0 ] && [ ! -f "$UB_MARKER" ] && grep -qE "hết thời gian chờ|stayed busy past the wait" "$TMP/ubatch_slot.log"; then
  ok "unity-batch.sh takes a heavy slot without --full and does not run when both slots are held"
else
  fail "unity-batch without --full (rc=$rc_ubatch marker=$([ -f "$UB_MARKER" ] && echo yes || echo no)): $(tail -5 "$TMP/ubatch_slot.log")"
fi
if [ -f "$LIGHT_MARKER" ]; then
  ok "a bash path that only contains the letters unity still runs while the slots are held"
else
  fail "light unity-named test waited on the heavy slot (rc=$rc_light): $(tail -5 "$TMP/light_slot.log")"
fi

[ "$FAILS" -eq 0 ] && echo "✅ test_heavy_slot: all passed" || { echo "❌ test_heavy_slot: $FAILS failed"; exit 1; }
