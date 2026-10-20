#!/usr/bin/env bash
# Test hồi quy cho quyền chạy việc nặng theo TẢI MÁY (heavy_slot.py / super-board-heavy-slot.py). P1b (người dùng 20/10: "bỏ 2 slot
# gate, tải CPU dưới 100 thì cứ cho chạy"): không còn giới hạn 2 lượt --full; tải 1 phút dưới DEVKIT_SLOT_LOAD_MAX (100) thì chạy ngay,
# cao hơn thì chờ tải xuống rồi vẫn chạy. Tải đọc từ file (DEVKIT_SLOT_LOAD_FILE), không phải tải thật của máy.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SLOT_BIN="$ROOT/.claude/bin/super-board-heavy-slot.py"
# Ca 1–6 gọi thẳng CLI heavy_slot.py của CHÍNH checkout này: wrapper super-board cố ý dùng DevKit của main checkout (thứ tự của
# super-board-scratch-config.sh), nên trong một worktree nó thử code của main chứ không phải code đang đổi (đo 20/10).
DK_BIN="$ROOT/universal-agent-devkit/bin/heavy_slot.py"
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
export DEVKIT_SLOT_LOAD_FILE="$TMP/load"
echo 1 > "$TMP/load"
unset SB_HEAVY_SLOT_HELD SB_HEAVY_SLOT_WAIT_S DEVKIT_SLOT_LOAD_WAIT_S DEVKIT_SLOT_LOAD_MAX DEVKIT_SLOT_PRIORITY DEVKIT_SLOT_ADVISORY_HELD
# Gate lồng ở ca 7–8 chạy trong repo fixture (cd "$REPO"): CLAUDE_PROJECT_DIR kế thừa từ gate cha (khi test này là suite của ma
# trận) làm nó kiểm nhầm repo cha — gate đọc CLAUDE_PROJECT_DIR trước git root (20/10: 4 ca đỏ khi chạy trong gate).
unset CLAUDE_PROJECT_DIR
now() { python3 -c 'import time; print(time.time())'; }
lt() { python3 -c "import sys; sys.exit(0 if $1 < $2 else 1)"; }

# ── 1. Không còn 2 slot: tải thấp, 3 tiến trình cùng giữ quyền chạy một lúc (bản 2 slot: tiến trình thứ 3 chờ).
for n in 1 2 3; do
  python3 "$DK_BIN" -- bash -c "touch '$TMP/held$n'; sleep 30" >/dev/null 2>&1 &
  PIDS="$PIDS $!"
done
for i in $(seq 1 50); do
  [ -f "$TMP/held1" ] && [ -f "$TMP/held2" ] && [ -f "$TMP/held3" ] && break
  sleep 0.1
done
if [ -f "$TMP/held1" ] && [ -f "$TMP/held2" ] && [ -f "$TMP/held3" ]; then
  ok "low load: three processes run at once (no 2-slot limit)"
else
  fail "low load: not all three ran (held3=$([ -f "$TMP/held3" ] && echo yes || echo no))"
fi
for p in $PIDS; do kill "$p" 2>/dev/null || true; done; wait 2>/dev/null; PIDS=""

# ── 2. --nonblock: tải thấp thì chạy; tải cao (≥ 100) thì không chạy, exit 1.
python3 "$DK_BIN" --nonblock -- touch "$TMP/nb_low" >/dev/null 2>&1; rc_low=$?
echo 150 > "$TMP/load"
python3 "$DK_BIN" --nonblock -- touch "$TMP/nb_high" >"$TMP/nb_high.log" 2>&1; rc_high=$?
echo 1 > "$TMP/load"
if [ "$rc_low" -eq 0 ] && [ -f "$TMP/nb_low" ] && [ "$rc_high" -ne 0 ] && [ ! -f "$TMP/nb_high" ]; then
  ok "--nonblock runs at low load and refuses at high load"
else
  fail "--nonblock (low rc=$rc_low ran=$([ -f "$TMP/nb_low" ] && echo yes || echo no); high rc=$rc_high ran=$([ -f "$TMP/nb_high" ] && echo yes || echo no))"
fi

# ── 3. Tải cao rồi xuống: lệnh chờ, rồi chạy ngay khi tải xuống (trước trần chờ 30 s).
echo 150 > "$TMP/load"
( sleep 1.5; echo 5 > "$TMP/load" ) & PIDS="$PIDS $!"
t0=$(now)
SB_HEAVY_SLOT_WAIT_S=30 python3 "$DK_BIN" -- touch "$TMP/after_drop" >"$TMP/drop.log" 2>&1; rc_drop=$?
w3=$(python3 -c "import time; print(round(time.time() - $t0, 1))")
if [ "$rc_drop" -eq 0 ] && [ -f "$TMP/after_drop" ] && lt "$w3" 25 && lt 1 "$w3"; then
  ok "high load: waited ${w3}s, ran once the load dropped"
else
  fail "high load then drop (rc=$rc_drop ran=$([ -f "$TMP/after_drop" ] && echo yes || echo no) ${w3}s): $(tail -2 "$TMP/drop.log")"
fi
wait 2>/dev/null; PIDS=""

# ── 4. Tải cao mãi: hết thời gian chờ thì VẪN chạy lệnh (tải không chặn), có dòng log (bản 2 slot: hết giờ thì không chạy).
echo 150 > "$TMP/load"
SB_HEAVY_SLOT_WAIT_S=0.5 python3 "$DK_BIN" -- touch "$TMP/still_ran" >"$TMP/still.log" 2>&1; rc_still=$?
echo 1 > "$TMP/load"
if [ "$rc_still" -eq 0 ] && [ -f "$TMP/still_ran" ] && grep -q "vẫn chạy" "$TMP/still.log"; then
  ok "wait expired at high load: the command still ran, with a log line"
else
  fail "wait expired at high load (rc=$rc_still ran=$([ -f "$TMP/still_ran" ] && echo yes || echo no)): $(tail -2 "$TMP/still.log")"
fi

# ── 5. DEVKIT_SLOT_LOAD_WAIT_S=0 (merge gate super-board đặt sau lần chờ tải của chính nó): tải cao mà không chờ.
echo 150 > "$TMP/load"
t0=$(now)
DEVKIT_SLOT_LOAD_WAIT_S=0 python3 "$DK_BIN" -- touch "$TMP/merge_ran" >"$TMP/merge.log" 2>&1; rc_merge=$?
w5=$(python3 -c "import time; print(round(time.time() - $t0, 1))")
echo 1 > "$TMP/load"
if [ "$rc_merge" -eq 0 ] && [ -f "$TMP/merge_ran" ] && lt "$w5" 20 && ! grep -q "chờ tải xuống" "$TMP/merge.log"; then
  ok "DEVKIT_SLOT_LOAD_WAIT_S=0: no load wait at high load (${w5}s)"
else
  fail "DEVKIT_SLOT_LOAD_WAIT_S=0 at high load (rc=$rc_merge ran=$([ -f "$TMP/merge_ran" ] && echo yes || echo no) ${w5}s)"
fi

# ── 6. Lồng nhau (SB_HEAVY_SLOT_HELD=1 do tiến trình ngoài đặt): lệnh trong không chờ tải lại, kể cả --nonblock khi tải đã lên cao.
rm -f "$TMP/nested_ok"
python3 "$DK_BIN" -- bash -c "
  echo 150 > '$TMP/load'
  python3 '$DK_BIN' --nonblock -- touch '$TMP/nested_ok'
" >/dev/null 2>&1
echo 1 > "$TMP/load"
if [ -f "$TMP/nested_ok" ]; then
  ok "nested call under SB_HEAVY_SLOT_HELD=1 does not wait or refuse again"
else
  fail "nested call was refused although the outer process was already admitted"
fi

# ── 6b. Lệnh chạy dưới CLI (chỉ được cho chạy theo tải, không giữ khoá nào) mà bên trong có suite Unity: suite đó VẪN phải chờ khoá
#       Unity (OCR 20/10: CLI từng đặt SB_HEAVY_SLOT_HELD=1 nên gate lồng bỏ qua khoá Unity — hai Editor chạy cùng lúc).
mkdir -p "$SB_HEAVY_SLOT_DIR"
python3 -c 'import fcntl, sys, time
f = open(sys.argv[1], "a+"); fcntl.flock(f.fileno(), fcntl.LOCK_EX); open(sys.argv[2], "w").close(); time.sleep(600)' \
  "$SB_HEAVY_SLOT_DIR/unity-1.lock" "$TMP/u6b.ready" >/dev/null 2>&1 &
U6B=$!; PIDS="$PIDS $U6B"
for _ in $(seq 1 100); do [ -f "$TMP/u6b.ready" ] && break; sleep 0.05; done
R6B="$TMP/nested-unity"; mkdir -p "$R6B/src"
( cd "$R6B" && git init -q . && git config user.email t@t && git config user.name t && echo 'x = 1' > src/a.py \
  && printf '{"project":"t","rules":[{"component":"A","watch_files":["src/a.py"],"mandatory_regression_tests":[{"id":"REG-U","name":"u","command":"touch %s; unity-batch.sh editmode"}]}]}\n' "$TMP/u6b_ran" > matrix.json \
  && git add -A && git commit -qm init && echo 'x = 2' > src/a.py )
SB_HEAVY_SLOT_WAIT_S=0.5 python3 "$DK_BIN" -- bash -c "cd '$R6B' && python3 '$ROOT/universal-agent-devkit/bin/post-fix-gate.py' --matrix '$R6B/matrix.json' --run-tests --no-checklist" >"$TMP/u6b.log" 2>&1
kill "$U6B" 2>/dev/null; wait "$U6B" 2>/dev/null
if [ ! -f "$TMP/u6b_ran" ]; then
  ok "a Unity suite nested under the CLI still waits for the Unity lock"
else
  fail "a Unity suite nested under the CLI ran while the Unity lock was held: $(grep -E 'KẾT LUẬN|VERDICT' "$TMP/u6b.log" | tail -1)"
fi

# ── 7. Không tìm thấy heavy_slot.py của DevKit: log một dòng và chạy tiếp lệnh, thoát 0.
mkdir -p "$TMP/standalone/.claude/bin"
cp "$SLOT_BIN" "$TMP/standalone/.claude/bin/super-board-heavy-slot.py"
( cd "$TMP/standalone" && SB_REPO_PATH="$TMP/standalone" python3 "$TMP/standalone/.claude/bin/super-board-heavy-slot.py" -- touch "$TMP/fallback_ok" ) >"$TMP/fallback.log" 2>&1
rc_fb=$?
if [ "$rc_fb" -eq 0 ] && [ -f "$TMP/fallback_ok" ] && [ -s "$TMP/fallback.log" ]; then
  ok "missing DevKit heavy_slot.py: logs one line and runs command with exit 0"
else
  fail "missing DevKit fallback failed (rc=$rc_fb file=$([ -f "$TMP/fallback_ok" ] && echo yes || echo no) log='$(cat "$TMP/fallback.log" 2>/dev/null)')"
fi

# ── 8. post-fix-gate --force-full và suite ./gradlew / unity-batch.sh không --full, khi 2 khoá heavy-gate CŨ đang bị giữ (bản DevKit
#      cũ): suite nhẹ và Gradle vẫn chạy (không còn 2 slot); unity-batch.sh vẫn chờ khoá Unity (độc quyền) khi khoá đó bận.
hold_lock() { # <file khoá>: giữ flock tới khi bị kill
  python3 -c 'import fcntl, sys, time
f = open(sys.argv[1], "a+"); fcntl.flock(f.fileno(), fcntl.LOCK_EX); open(sys.argv[2], "w").close(); time.sleep(600)' \
    "$1" "$1.ready" >/dev/null 2>&1 &
  PIDS="$PIDS $!"
  for _ in $(seq 1 100); do [ -f "$1.ready" ] && return 0; sleep 0.05; done
  fail "setup: could not hold $1"
}
mkdir -p "$SB_HEAVY_SLOT_DIR"
hold_lock "$SB_HEAVY_SLOT_DIR/heavy-gate-1.lock"; hold_lock "$SB_HEAVY_SLOT_DIR/heavy-gate-2.lock"
hold_lock "$SB_HEAVY_SLOT_DIR/unity-1.lock"
GATE_PY="$ROOT/universal-agent-devkit/bin/post-fix-gate.py"
export SB_HEAVY_SLOT_WAIT_S=0.4
slot_repo() { # $1 name  $2 command  $3 log  [$4 extra gate flag]
  local repo="$TMP/$1" marker_cmd="$2" log="$3"
  mkdir -p "$repo/src" "$repo/templates"
  (
    cd "$repo" && git init -q . && git config user.email t@t && git config user.name t
    echo "fun ok() = 1" > src/Core.kt
    printf '#!/bin/sh\nexit 0\n' > gradlew && chmod +x gradlew
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
  ( cd "$repo" && python3 "$GATE_PY" --matrix "$repo/templates/regression_matrix.json" --run-tests ${4:-} --allow-no-tests --allow-orphan-tests --brief ) >"$log" 2>&1
}
MARKER="$TMP/suite_ran"
GRADLE_MARKER="$TMP/gradle_ran"
UB_MARKER="$TMP/unity_batch_ran"
LIGHT_MARKER="$TMP/light_unity_ran"
LIGHT_CMD="$TMP/test_unity_probe.sh"
printf '#!/usr/bin/env bash\ntouch %q\n' "$LIGHT_MARKER" > "$LIGHT_CMD"
chmod +x "$LIGHT_CMD"
slot_repo full "touch '$MARKER'" "$TMP/gate_slot.log" --force-full
rc_gate=$?
slot_repo gradle "bash -c 'touch $GRADLE_MARKER; exec ./gradlew test'" "$TMP/gradle_slot.log"
rc_gradle=$?
slot_repo ubatch "bash -c 'touch $UB_MARKER; exec unity-batch.sh editmode'" "$TMP/ubatch_slot.log"
rc_ubatch=$?
slot_repo light "bash $LIGHT_CMD" "$TMP/light_slot.log"
rc_light=$?
unset SB_HEAVY_SLOT_WAIT_S
for p in $PIDS; do kill "$p" 2>/dev/null || true; done; wait 2>/dev/null; PIDS=""
if [ "$rc_gate" -eq 0 ] && [ -f "$MARKER" ]; then
  ok "post-fix-gate --force-full runs a light suite while the old heavy-gate locks are held"
else
  fail "post-fix-gate --force-full light suite (rc=$rc_gate marker=$([ -f "$MARKER" ] && echo yes || echo no)): $(grep -E 'KẾT LUẬN|VERDICT' "$TMP/gate_slot.log" | tail -2)"
fi
if [ "$rc_gradle" -eq 0 ] && [ -f "$GRADLE_MARKER" ]; then
  ok "gradlew runs while the old heavy-gate locks are held (no 2-slot limit)"
else
  fail "gradlew without --full (rc=$rc_gradle marker=$([ -f "$GRADLE_MARKER" ] && echo yes || echo no)): $(tail -5 "$TMP/gradle_slot.log")"
fi
if [ "$rc_ubatch" -ne 0 ] && [ ! -f "$UB_MARKER" ] && grep -qE "khoá độc quyền|exclusive lock" "$TMP/ubatch_slot.log"; then
  ok "unity-batch.sh waits for the Unity lock and does not run when it stays held"
else
  fail "unity-batch without --full (rc=$rc_ubatch marker=$([ -f "$UB_MARKER" ] && echo yes || echo no)): $(tail -5 "$TMP/ubatch_slot.log")"
fi
if [ -f "$LIGHT_MARKER" ]; then
  ok "a bash path that only contains the letters unity still runs while the Unity lock is held"
else
  fail "light unity-named test waited on the Unity lock (rc=$rc_light): $(tail -5 "$TMP/light_slot.log")"
fi

[ "$FAILS" -eq 0 ] && echo "✅ test_heavy_slot: all passed" || { echo "❌ test_heavy_slot: $FAILS failed"; exit 1; }
