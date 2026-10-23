#!/usr/bin/env bash
# Test hồi quy (P1 + P1b, 20/10): post-fix-gate xin quyền chạy cho TỪNG suite, không giữ slot cả lượt vì --full.
# Đo 20/10: một lượt --full chỉ có suite bash/python chờ 30+ phút ở 2 heavy slot toàn máy sau merge gate Unity/Gradle của repo
# khác mà không chạy suite nào. P1b (người dùng 20/10: "bỏ 2 slot gate, tải CPU dưới 100 thì cứ cho chạy"). Luật:
#   - không còn 2 slot engine: mọi suite (Gradle/xcodebuild/cpu/nhẹ) chạy ngay khi tải 1 phút < DEVKIT_SLOT_LOAD_MAX (100); tải cao
#     thì chờ tải xuống tối đa DEVKIT_SLOT_LOAD_WAIT_S rồi VẪN chạy — tải không bao giờ làm suite thành UNTESTED
#   - tổng giây chờ tải của một lượt có trần (DEVKIT_SLOT_ADVISORY_BUDGET_S); merge gate super-board tự chờ tải trước verify rồi đặt
#     DEVKIT_SLOT_LOAD_WAIT_S=0; DEVKIT_SLOT_PRIORITY=merge một mình (worktree finish) vẫn chờ tải như mọi lượt
#   - chỉ tài nguyên độc quyền còn khoá: Unity (1 Editor); hết SB_HEAVY_SLOT_WAIT_S thì không chạy (SLOT, không PASS). Không còn khoá
#     thiết bị (review 20/10): nhận suite thiết bị bằng regex chữ (`bash -n scripts/qa/adb/x.sh` thành suite thiết bị) và khoá đó không
#     khớp khoá của proof-capture
#   - suite giữ khoá độc quyền thì môi trường của nó có SB_HEAVY_SLOT_HELD=1; suite chỉ được cho chạy theo tải có
#     DEVKIT_SLOT_ADVISORY_HELD=1 (gate lồng không chờ tải lại, vẫn xin khoá Unity); lần chạy lại (FLAKY_RETRY) giữ nguyên các cờ đó
# Slot dir riêng (SB_HEAVY_SLOT_DIR) — không đụng khoá thật của máy. Tải đọc từ file (DEVKIT_SLOT_LOAD_FILE), không phải tải thật.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
# gate cha chạy test này dưới quyền chạy theo tải (DEVKIT_SLOT_ADVISORY_HELD=1; đo 20/10: ca đỏ khi chạy trong gate) và có thể đặt
# DEVKIT_SLOT_LOAD_WAIT_S: test này đo chính việc chờ, nên tự đặt mọi biến của nó. ANDROID_SERIAL / PROOF_DEVICE_LOCK_DIR: không bao giờ
# đụng khoá thiết bị thật của máy (bản có khoá thiết bị khoá serial đó dưới ~/.config/universal-agent-devkit/device-locks).
unset SB_HEAVY_SLOT_HELD DEVKIT_SLOT_ADVISORY_HELD DEVKIT_SLOT_ADVISORY_BUDGET_S SB_HEAVY_SLOT_WAIT_S DEVKIT_SLOT_LOAD_WAIT_S \
  DEVKIT_SLOT_LOAD_MAX DEVKIT_SLOT_PRIORITY GATE_TOTAL_BUDGET_S CI ANDROID_SERIAL FLAKY_RETRY FLAKY_RETRY_MAX_S DEVKIT_GATE_PARALLEL
# T0052: ngưỡng tải mặc định là capacity busy_load (bin/capacity.py): máy giả 12 lõi = 36, tải giả 1/5 dưới và 150 trên ngưỡng ở mọi máy
export DEVKIT_CAPACITY_CORES=12

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
PIDS=""
cleanup() { for p in $PIDS; do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1 DEVKIT_SLOT_LOAD_FILE="$TMP/load" PROOF_DEVICE_LOCK_DIR="$TMP/devlocks"
mkdir -p "$SB_HEAVY_SLOT_DIR"
echo 1 > "$TMP/load"   # tải thấp; ca nào cần tải cao thì tự ghi
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
now() { python3 -c 'import time; print(time.time())'; }
lt() { python3 -c "import sys; sys.exit(0 if $1 < $2 else 1)"; }

# hold <tên file khoá trong slot dir>: giữ flock tới khi bị kill; chờ tới khi khoá đã giữ
hold() {
  local lock="$SB_HEAVY_SLOT_DIR/$1" ready="$TMP/ready.$1"
  python3 -c 'import fcntl, sys, time
f = open(sys.argv[1], "a+")
fcntl.flock(f.fileno(), fcntl.LOCK_EX)
open(sys.argv[2], "w").close()
time.sleep(600)' "$lock" "$ready" >/dev/null 2>&1 &
  PIDS="$PIDS $!"
  for _ in $(seq 1 100); do [ -f "$ready" ] && return 0; sleep 0.05; done
  echo "✖ setup: không giữ được $1"; exit 1
}
release_all() { for p in $PIDS; do kill "$p" 2>/dev/null; done; wait 2>/dev/null; PIDS=""; rm -f "$TMP"/ready.*; }

# make_repo <thư mục> <lệnh suite> [<file stub> <nội dung>]: repo một suite (stub, vd gradlew, được commit cùng), có thay đổi chưa
# commit khớp watch_files
make_repo() {
  local r="$1" cmd="$2" stub="${3:-}" body="${4:-}"
  mkdir -p "$r/src"
  ( cd "$r" && git init -q . && git config user.email t@t && git config user.name t
    echo 'x = 1' > src/a.py
    if [ -n "$stub" ]; then mkdir -p "$(dirname "$stub")" && printf '%s\n' '#!/bin/sh' "$body" > "$stub" && chmod +x "$stub"; fi
    python3 - "$r/matrix.json" "$cmd" <<'PY'
import json, sys
path, command = sys.argv[1:]
json.dump({"project": "t", "rules": [{"component": "A", "watch_files": ["src/a.py"],
           "mandatory_regression_tests": [{"id": "REG-1", "name": "one", "command": command}]}]}, open(path, "w"))
PY
    git add -A && git commit -qm init && echo 'x = 2' > src/a.py ) || { echo "✖ setup: repo $r"; exit 1; }
}

run_gate() {   # run_gate <repo> [cờ…]: in output vào $OUT, exit code vào $RC, giây vào $WALL
  local r="$1"; shift
  local t0; t0=$(now)
  ( cd "$r" && CLAUDE_PROJECT_DIR="$r" python3 "$GATE" --matrix "$r/matrix.json" --run-tests --no-checklist "$@" ) >"$TMP/out" 2>&1
  RC=$?
  WALL=$(python3 -c "import time; print(round(time.time() - $t0, 1))")
  OUT="$(cat "$TMP/out")"
}

# ── 1. 2 khoá heavy-gate cũ đang bị giữ (bản DevKit cũ), ma trận chỉ suite nhẹ: --full chạy ngay và PASS.
hold heavy-gate-1.lock; hold heavy-gate-2.lock
make_repo "$TMP/light" "touch '$TMP/light_ran'"
SB_HEAVY_SLOT_WAIT_S=120 run_gate "$TMP/light" --full
if [ "$RC" = 0 ] && [ -f "$TMP/light_ran" ] && lt "$WALL" 100; then
  ok "1. khoá heavy-gate cũ bận + chỉ suite nhẹ: --full PASS sau ${WALL}s"
else
  fail "1. --full chỉ suite nhẹ (exit $RC, ${WALL}s, suite chạy: $([ -f "$TMP/light_ran" ] && echo có || echo không))"
  printf '%s\n' "$OUT" | grep -E "SLOT|heavy-slot|KẾT LUẬN" | head -4
fi

# ── 2. Không còn 2 slot (P1b): khoá heavy-gate cũ bận, tải thấp ⇒ suite ./gradlew CHẠY ngay (bản 2 slot: chờ rồi UNTESTED/SLOT).
make_repo "$TMP/gradle" "touch '$TMP/gradle_ran'; ./gradlew test" gradlew "exit 0"
SB_HEAVY_SLOT_WAIT_S=0.5 run_gate "$TMP/gradle" --full
if [ "$RC" = 0 ] && [ -f "$TMP/gradle_ran" ]; then
  ok "2. tải thấp: suite Gradle chạy ngay dù 2 khoá heavy-gate cũ bận (${WALL}s)"
else
  fail "2. suite Gradle khi tải thấp (exit $RC, chạy: $([ -f "$TMP/gradle_ran" ] && echo có || echo không))"
  printf '%s\n' "$OUT" | grep -E "SLOT|heavy-slot|KẾT LUẬN" | head -4
fi
release_all

# ── 2b. Tải cao không bao giờ đổi xuống: suite chờ đúng DEVKIT_SLOT_LOAD_WAIT_S rồi VẪN chạy, exit 0, có ghi chú (không UNTESTED).
echo 150 > "$TMP/load"; rm -f "$TMP/gradle_ran"
DEVKIT_SLOT_LOAD_WAIT_S=1 run_gate "$TMP/gradle" --full --no-cache
if [ "$RC" = 0 ] && [ -f "$TMP/gradle_ran" ] && printf '%s\n' "$OUT" | grep -q "vẫn chạy"; then
  ok "2b. tải cao mãi: chờ ${WALL}s rồi vẫn chạy, có ghi chú"
else
  fail "2b. tải cao mãi (exit $RC, ${WALL}s, chạy: $([ -f "$TMP/gradle_ran" ] && echo có || echo không), ghi chú: $(printf '%s\n' "$OUT" | grep -c 'vẫn chạy'))"
fi

# ── 2c. Tải cao rồi xuống giữa chừng: suite chạy ngay khi tải xuống (không đợi hết 60 s chờ).
rm -f "$TMP/gradle_ran"; ( sleep 8; echo 5 > "$TMP/load" ) & PIDS="$PIDS $!"   # 8 s: gate khởi động chậm hơn 1,5 s khi máy tải cao thì không còn gì để chờ (flake 21/10)
DEVKIT_SLOT_LOAD_WAIT_S=60 run_gate "$TMP/gradle" --full --no-cache
if [ "$RC" = 0 ] && [ -f "$TMP/gradle_ran" ] && lt "$WALL" 45 && printf '%s\n' "$OUT" | grep -q "chờ tải máy xuống"; then
  ok "2c. tải xuống giữa chừng: suite chạy sau ${WALL}s (trần chờ 60 s)"
else
  fail "2c. tải xuống giữa chừng (exit $RC, ${WALL}s, chạy: $([ -f "$TMP/gradle_ran" ] && echo có || echo không))"
fi
release_all; echo 1 > "$TMP/load"

# ── 3. Khoá Unity bận (một Editor đang chạy): suite unity-batch chờ khoá Unity, hết giờ thì không chạy — hai Editor không cùng lúc.
hold unity-1.lock
make_repo "$TMP/unity" "touch '$TMP/unity_ran'; unity-batch.sh editmode"
SB_HEAVY_SLOT_WAIT_S=0.5 run_gate "$TMP/unity" --full
if [ "$RC" != 0 ] && [ ! -f "$TMP/unity_ran" ] && printf '%s\n' "$OUT" | grep -q "khoá độc quyền"; then
  ok "3. suite Unity chờ khoá Unity, hết giờ thì không chạy (khoá độc quyền)"
else
  fail "3. suite Unity khi khoá Unity bận (exit $RC, chạy: $([ -f "$TMP/unity_ran" ] && echo có || echo không))"
fi
release_all

# ── 4. Môi trường của suite: được cho chạy theo tải ⇒ chỉ DEVKIT_SLOT_ADVISORY_HELD=1 (gate lồng không chờ tải lại nhưng VẪN xin khoá
#      Unity: một unity-batch.sh nằm sâu hai cấp script không lách được khoá Unity); giữ khoá Unity ⇒ SB_HEAVY_SLOT_HELD=1.
make_repo "$TMP/held" "printf 'HELD=%s;ADV=%s' \"\${SB_HEAVY_SLOT_HELD:-}\" \"\${DEVKIT_SLOT_ADVISORY_HELD:-}\" > '$TMP/held_env'"
run_gate "$TMP/held"
if [ "$RC" = 0 ] && [ "$(cat "$TMP/held_env" 2>/dev/null)" = "HELD=;ADV=1" ]; then
  ok "4a. suite nhẹ: chỉ cờ tải (DEVKIT_SLOT_ADVISORY_HELD=1), không SB_HEAVY_SLOT_HELD"
else
  fail "4a. môi trường suite nhẹ: '$(cat "$TMP/held_env" 2>/dev/null)' (exit $RC), mong 'HELD=;ADV=1'"
fi
make_repo "$TMP/heldeng" "./gradlew test" gradlew "printf 'HELD=%s;ADV=%s' \"\${SB_HEAVY_SLOT_HELD:-}\" \"\${DEVKIT_SLOT_ADVISORY_HELD:-}\" > '$TMP/heldeng_env'"
run_gate "$TMP/heldeng"
if [ "$(cat "$TMP/heldeng_env" 2>/dev/null)" = "HELD=;ADV=1" ]; then
  ok "4b. suite Gradle (không còn slot engine): chỉ cờ tải, không SB_HEAVY_SLOT_HELD"
else
  fail "4b. môi trường suite Gradle: '$(cat "$TMP/heldeng_env" 2>/dev/null)' (exit $RC), mong 'HELD=;ADV=1'"
fi
make_repo "$TMP/heldunity" "./unity-batch.sh editmode" unity-batch.sh "printf 'HELD=%s' \"\${SB_HEAVY_SLOT_HELD:-}\" > '$TMP/heldunity_env'"
run_gate "$TMP/heldunity"
if [ "$(cat "$TMP/heldunity_env" 2>/dev/null)" = "HELD=1" ]; then
  ok "4c. suite Unity giữ khoá Unity: SB_HEAVY_SLOT_HELD=1"
else
  fail "4c. môi trường suite Unity: '$(cat "$TMP/heldunity_env" 2>/dev/null)' (exit $RC), mong 'HELD=1'"
fi
# 4d. Suite khớp regex thiết bị (`bash -n scripts/qa/adb/check.sh` chỉ kiểm cú pháp) không còn khoá thiết bị (review 20/10): tải thấp
#     ⇒ chạy, chỉ cờ tải. Bản có khoá thiết bị: khoá serial "default", SB_HEAVY_SLOT_HELD=1.
make_repo "$TMP/helddev" "bash -n scripts/qa/adb/check.sh && printf 'HELD=%s;ADV=%s' \"\${SB_HEAVY_SLOT_HELD:-}\" \"\${DEVKIT_SLOT_ADVISORY_HELD:-}\" > '$TMP/helddev_env'" \
  scripts/qa/adb/check.sh "exit 0"
run_gate "$TMP/helddev"
if [ "$RC" = 0 ] && [ "$(cat "$TMP/helddev_env" 2>/dev/null)" = "HELD=;ADV=1" ]; then
  ok "4d. suite khớp regex thiết bị: không khoá thiết bị, chỉ cờ tải"
else
  fail "4d. môi trường suite khớp regex thiết bị: '$(cat "$TMP/helddev_env" 2>/dev/null)' (exit $RC), mong 'HELD=;ADV=1'"
fi

# ── 5. DEVKIT_SLOT_PRIORITY=merge một mình (worktree finish: không tự chờ tải trước) VẪN chờ tải như mọi lượt (OCR 20/10); chỉ
#      merge gate super-board, đã chờ tải trước verify, đặt DEVKIT_SLOT_LOAD_WAIT_S=0. Tải cao, trần chờ 1 s: có dòng chờ, suite vẫn chạy.
echo 150 > "$TMP/load"; rm -f "$TMP/light_ran"
DEVKIT_SLOT_LOAD_WAIT_S=1 DEVKIT_SLOT_PRIORITY=merge run_gate "$TMP/light" --full --no-cache
if [ "$RC" = 0 ] && [ -f "$TMP/light_ran" ] && printf '%s\n' "$OUT" | grep -q "chờ tải xuống"; then
  ok "5. ưu tiên merge một mình vẫn chờ tải (${WALL}s) rồi chạy"
else
  fail "5. ưu tiên merge khi tải cao (exit $RC, ${WALL}s, chạy: $([ -f "$TMP/light_ran" ] && echo có || echo không), dòng chờ: $(printf '%s\n' "$OUT" | grep -c 'chờ tải xuống'))"
fi
echo 1 > "$TMP/load"

# ── 6. Hàng đợi ưu tiên (đơn vị, heavy_slot.py; còn dùng cho khoá Unity): merge trước stop; trong cùng mức thì việc ngắn
#      trước; chờ lâu được bù (không đói); vé của tiến trình đã chết bị bỏ.
python3 - "$DEVKIT_DIR/bin" <<'PY' || FAILS=$((FAILS + 1))
import os, sys
sys.path.insert(0, sys.argv[1])
import heavy_slot as hs
now = 1000.0
t = lambda pid, prio, est, t0: {"pid": pid, "prio": prio, "est_s": est, "t0": t0}
ok = True
def check(name, cond):
    global ok
    print(("✔ 6. " if cond else "✖ 6. ") + name)
    ok = ok and cond
order = hs.queue_order([t(1, "stop", 5, 990), t(2, "merge", 500, 999)], now)
check("merge đứng trước stop dù đến sau và dài hơn", [x["pid"] for x in order] == [2, 1])
order = hs.queue_order([t(1, "interactive", 500, 999), t(2, "interactive", 5, 999.5)], now)
check("cùng mức: việc ngắn trước (SJF)", [x["pid"] for x in order] == [2, 1])
order = hs.queue_order([t(1, "interactive", 500, now - 900), t(2, "interactive", 5, now)], now)
check("việc dài đã chờ 900 s đứng trước việc ngắn mới đến (bù thời gian chờ)", [x["pid"] for x in order] == [1, 2])
check("vé của PID đã chết không còn sống", not hs.ticket_alive({"pid": 2 ** 22 + 12345, "t0": now}, now, wait_s=60))
check("vé của chính tiến trình này còn sống", hs.ticket_alive({"pid": os.getpid(), "t0": now}, now, wait_s=60))
sys.exit(0 if ok else 1)
PY

# ── 7. stale_rerun.run_one (nightly, chạy lại STALE) cũng xin quyền chạy theo suite: khoá Unity bận ⇒ suite Unity không chạy, trả SLOT;
#      khoá heavy-gate cũ bận ⇒ suite Gradle vẫn chạy. STALE_RUN_DIR: thư mục scripts/testing cần thử (mặc định của DevKit này).
hold unity-1.lock; hold heavy-gate-1.lock; hold heavy-gate-2.lock
mkdir -p "$TMP/rr" && ( cd "$TMP/rr" && git init -q . && git config user.email t@t && git config user.name t \
  && echo x > a && printf '#!/bin/sh\nexit 0\n' > gradlew && chmod +x gradlew && git add -A && git commit -qm init ) || { echo "✖ setup: repo rr"; exit 1; }
if SB_HEAVY_SLOT_WAIT_S=0.5 python3 - "${STALE_RUN_DIR:-$DEVKIT_DIR/scripts/testing}" "$TMP/rr" "$TMP/rr_ran" "$TMP/rr_g" <<'PY'
import sys
from pathlib import Path
here, proj, marker, gmarker = sys.argv[1:]
sys.path.insert(0, here)
import stale_rerun as sr
out = sr.run_one(Path(proj), "REG-U", f"touch '{marker}'; unity-batch.sh editmode", [], 30)
print("   ", out)
out_g = sr.run_one(Path(proj), "REG-G", f"touch '{gmarker}'; ./gradlew test", [], 30)
print("   ", out_g)
sys.exit(0 if out.startswith("REG-U: SLOT") and not out_g.startswith("REG-G: SLOT") else 1)
PY
then
  { [ ! -f "$TMP/rr_ran" ] && [ -f "$TMP/rr_g" ]; } && ok "7. run_one: suite Unity chờ khoá Unity (SLOT, không chạy); suite Gradle chạy" \
    || fail "7. run_one: Unity chạy=$([ -f "$TMP/rr_ran" ] && echo có || echo không), Gradle chạy=$([ -f "$TMP/rr_g" ] && echo có || echo không)"
else
  fail "7. run_one (Unity chạy: $([ -f "$TMP/rr_ran" ] && echo có || echo không), Gradle chạy: $([ -f "$TMP/rr_g" ] && echo có || echo không))"
fi
release_all

# ── 8. Suite STALE (thêm vào --full từ checklist) bị UNTESTED vì SLOT (khoá Unity) không được ra ngoài kết luận: gate không exit 0.
#      Chỉ suite STALE "không chạy được trên máy này" (untested_exit) mới đứng ngoài kết luận (Antigravity plan_review T0046).
hold unity-1.lock
S8="$TMP/stale"; mkdir -p "$S8/src" "$S8/.agents"
( cd "$S8" && git init -q . && git config user.email t@t && git config user.name t
  echo 'x = 1' > src/a.py && echo 'k = 1' > src/heavy.cs
  python3 - "$S8/matrix.json" "$TMP/stale_heavy_ran" <<'PY'
import json, sys
path, marker = sys.argv[1:]
json.dump({"project": "t", "rules": [
    {"component": "A", "watch_files": ["src/a.py"], "mandatory_regression_tests": [{"id": "REG-1", "name": "light", "command": "true"}]},
    {"component": "H", "watch_files": ["src/heavy.cs"], "mandatory_regression_tests": [
        {"id": "REG-H", "name": "heavy", "command": f"touch '{marker}'; unity-batch.sh editmode"}]}]}, open(path, "w"))
PY
  git add -A && git commit -qm init ) || { echo "✖ setup: repo stale"; exit 1; }
OLD="$(git -C "$S8" rev-parse --short HEAD)"
python3 - "$S8/.agents/regression_status.json" "$OLD" <<'PY'
import json, sys, time
path, sha = sys.argv[1:]
json.dump({"version": 1, "items": {"REG-H": {"id": "REG-H", "kind": "test", "title": "heavy", "component": "H",
           "command": "x", "watch_files": ["src/heavy.cs"],
           "last": {"status": "PASS", "at": "2026-01-01 00:00:00", "ts": time.time() - 3600, "commit": sha, "duration": "1s"}}},
           "meta": {}, "stats": {}}, open(path, "w"))
PY
( cd "$S8" && echo 'k = 2' > src/heavy.cs && git commit -qam heavy && echo 'x = 2' > src/a.py )
SB_HEAVY_SLOT_WAIT_S=0.5 run_gate "$S8" --full
if [ "$RC" = 4 ] && [ ! -f "$TMP/stale_heavy_ran" ] && printf '%s\n' "$OUT" | grep -q "heavy-slot SLOT: REG-H"; then
  ok "8. suite STALE bị SLOT: gate exit 4, nhãn SLOT"
else
  fail "8. suite STALE bị SLOT mà gate exit $RC (chạy: $([ -f "$TMP/stale_heavy_ran" ] && echo có || echo không))"
  printf '%s\n' "$OUT" | grep -E "STALE|REG-H|KẾT LUẬN" | head -5
fi
release_all

# ── 9. Chờ tải có ngân sách TỔNG cho cả lượt: hai suite nối tiếp, tải cao mãi, ngân sách 2 s ⇒ chỉ suite đầu chờ, suite sau chạy luôn
#      (không phải 2 × thời gian chờ). Đếm dòng "chờ tải xuống" (không đo giờ: máy tải cao).
S9="$TMP/budget"; mkdir -p "$S9/src"
( cd "$S9" && git init -q . && git config user.email t@t && git config user.name t && echo 'x = 1' > src/a.py
  python3 - "$S9/matrix.json" <<'PY'
import json, sys
json.dump({"project": "t", "rules": [{"component": "A", "watch_files": ["src/a.py"], "mandatory_regression_tests": [
    {"id": "REG-B1", "name": "one", "command": "true"}, {"id": "REG-B2", "name": "two", "command": "true; true"}]}]},
    open(sys.argv[1], "w"))
PY
  git add -A && git commit -qm init && echo 'x = 2' > src/a.py ) || { echo "✖ setup: repo budget"; exit 1; }
echo 150 > "$TMP/load"
DEVKIT_SLOT_LOAD_WAIT_S=2 DEVKIT_SLOT_ADVISORY_BUDGET_S=2 run_gate "$S9"
waits=$(printf '%s\n' "$OUT" | grep -c "chờ tải xuống")
if [ "$RC" = 0 ] && [ "$waits" = 1 ] && printf '%s\n' "$OUT" | grep -q "ngân sách chờ tải"; then
  ok "9. hết ngân sách chờ tải: suite sau chạy luôn (1 lần chờ, có ghi chú)"
else
  fail "9. ngân sách chờ tải (exit $RC, số lần chờ $waits, mong 1)"
fi
echo 1 > "$TMP/load"

# ── 10. run_one (nightly / chạy lại STALE) giữ test_run.lock của dự án trong lúc chờ: lần chờ có trần là timeout còn lại của nó, không
#       phải SB_HEAVY_SLOT_WAIT_S (3600 s) — Stop hook của người dùng chờ khoá 45 s rồi ra BUSY (review 20/10, P1-7).
hold unity-1.lock
mkdir -p "$TMP/rr10" && ( cd "$TMP/rr10" && git init -q . && git config user.email t@t && git config user.name t \
  && echo x > a && git add -A && git commit -qm init ) || { echo "✖ setup: repo rr10"; exit 1; }
t0=$(now)
SB_HEAVY_SLOT_WAIT_S=120 python3 - "${STALE_RUN_DIR:-$DEVKIT_DIR/scripts/testing}" "$TMP/rr10" <<'PY' >/dev/null 2>&1
import sys
from pathlib import Path
here, proj = sys.argv[1:]
sys.path.insert(0, here)
import stale_rerun as sr
print(sr.run_one(Path(proj), "REG-U", "unity-batch.sh editmode", [], 3))
PY
w10=$(python3 -c "import time; print(round(time.time() - $t0, 1))")
lt "$w10" 60 && ok "10. run_one: chờ khoá có trần là timeout của nó (${w10}s)" \
  || fail "10. run_one chờ khoá ${w10}s dù timeout 3 s (giữ test_run.lock suốt lúc đó)"

# ── 11. Gate có ngân sách GATE_TOTAL_BUDGET_S (Stop hook: 900 s, hạn cứng 1800 s): lần chờ khoá có trần là ngân sách còn lại.
make_repo "$TMP/budget11" "touch '$TMP/budget11_ran'; unity-batch.sh editmode"
SB_HEAVY_SLOT_WAIT_S=120 GATE_TOTAL_BUDGET_S=3 run_gate "$TMP/budget11"
if [ ! -f "$TMP/budget11_ran" ] && [ "$RC" = 4 ] && lt "$WALL" 60 \
    && printf '%s\n' "$OUT" | grep -qE "heavy-slot SLOT: REG-1|UNTESTED — (hết ngân sách thời gian|khoá độc quyền)"; then
  ok "11. chờ khoá Unity bị giới hạn bởi ngân sách của gate (${WALL}s, exit 4, SLOT/BUDGET)"
else
  fail "11. ngân sách gate không giới hạn lần chờ khoá (${WALL}s, exit $RC, chạy: $([ -f "$TMP/budget11_ran" ] && echo có || echo không))"
  printf '%s\n' "$OUT" | grep -E "SLOT|BUDGET|KẾT LUẬN|UNTESTED" | head -5
fi
release_all

# ── 12. classify (đơn vị): `bash -lc '…'`, `bash -euc '…'`, `bash -o pipefail -c '…'` và tiền tố gán biến có "-c" (X=my-config) vẫn đọc
#       mã trong chuỗi: unity-batch.sh bên trong là suite Unity (khoá Unity), không phải suite nhẹ (OCR 20/10).
python3 - "$DEVKIT_DIR/bin" "$TMP" <<'PY' || FAILS=$((FAILS + 1))
import sys
sys.path.insert(0, sys.argv[1])
import heavy_slot as hs
ok = True
for cmd in ("bash -lc 'touch m; unity-batch.sh editmode'", "bash -euc 'unity-batch.sh editmode'",
            "bash -o pipefail -c 'unity-batch.sh editmode'", "CFG=my-config bash -c 'unity-batch.sh editmode'",
            # trình bọc đứng trước chương trình thật (review 20/10): timeout/gtimeout + thời lượng, xvfb-run, caffeinate, nice -n N
            "timeout 600 unity-batch.sh editmode", "xvfb-run -a unity-batch.sh editmode", "nice -n 10 unity-batch.sh editmode",
            "gtimeout -k 5 --signal=TERM 600 unity-batch.sh editmode", "caffeinate -i -t 3600 unity-batch.sh editmode",
            "caffeinate -s unity-batch.sh editmode",
            "xvfb-run -a -s '-screen 0 640x480x24' unity-batch.sh editmode", "timeout 600 nice -n 5 bash -c 'unity-batch.sh editmode'"):
    cls = hs.classify(cmd, sys.argv[2])["cls"]
    good = cls == "unity"
    ok = ok and good
    print(("✔ 12. " if good else "✖ 12. ") + f"{cmd!r} → {cls} (mong unity)")
# trình bọc không biến lệnh nhẹ thành nặng; `$VAR` làm từ chương trình để nguyên (unity-batch.sh có khoá máy riêng)
for cmd in ("timeout 600 true", "xvfb-run -a true", "nice -n 10 python3 -c 'print(1)'", "caffeinate -s true",
            "timeout 600 $UNITY_BATCH editmode"):
    cls = hs.classify(cmd, sys.argv[2])["cls"]
    good = cls == "light"
    ok = ok and good
    print(("✔ 12. " if good else "✖ 12. ") + f"{cmd!r} → {cls} (mong light)")
# Không phân lớp được thì coi là unity, không phải cpu (OCR 20/10: cpu không còn khoá nào, nên một suite Unity thật đọc lỗi từng chạy
# không khoá Unity — hai Editor cùng lúc). (a) quét lệnh ném lỗi; (b) script ở dòng lệnh không đọc được (chmod 000: isfile/getsize
# vẫn được, open ném PermissionError).
import os
real_rc = hs._rc
def broken_rc():
    raise RuntimeError("regression_checklist hỏng")
hs._rc = broken_rc
try:
    cls = hs.classify("unity-batch.sh editmode", sys.argv[2])["cls"]
finally:
    hs._rc = real_rc
good = cls == "unity"
ok = ok and good
print(("✔ 12. " if good else "✖ 12. ") + f"quét lệnh ném lỗi → {cls} (mong unity)")
locked = os.path.join(sys.argv[2], "locked_suite.sh")
with open(locked, "w") as f:
    f.write("unity-batch.sh editmode\n")
os.chmod(locked, 0)
try:
    try:
        open(locked).close()
        readable = True   # root đọc được cả file 000: không dựng được ca này
    except OSError:
        readable = False
    if readable:
        print("✔ 12. (bỏ qua: file chmod 000 vẫn đọc được — đang chạy bằng root)")
    else:
        cls = hs.classify("bash locked_suite.sh", sys.argv[2])["cls"]
        good = cls == "unity"
        ok = ok and good
        print(("✔ 12. " if good else "✖ 12. ") + f"script không đọc được → {cls} (mong unity)")
finally:
    os.chmod(locked, 0o600)
sys.exit(0 if ok else 1)
PY

# ── 13. Thời gian chờ tải không ăn vào thời gian chờ khoá độc quyền (OCR 20/10): tải cao mãi (chờ tải 3 s rồi chạy), khoá Unity bận và
#       được thả ở giây thứ 9, chờ tải 5 s, SB_HEAVY_SLOT_WAIT_S=5. Đúng: chờ khoá tính sau lần chờ tải (tới ~giây 11–13) ⇒ lấy được
#       khoá, suite chạy. Sai: hạn khoá tính từ lúc vào (~giây 6–8) ⇒ SLOT dù chưa chờ khoá đủ 5 s.
echo 150 > "$TMP/load"
hold unity-1.lock; HOLDER13="${PIDS##* }"
( sleep 9; kill "$HOLDER13" 2>/dev/null ) & PIDS="$PIDS $!"
make_repo "$TMP/lockwait" "touch '$TMP/lockwait_ran'; unity-batch.sh editmode"
DEVKIT_SLOT_LOAD_WAIT_S=5 SB_HEAVY_SLOT_WAIT_S=5 run_gate "$TMP/lockwait"
if [ -f "$TMP/lockwait_ran" ] && ! printf '%s\n' "$OUT" | grep -q "khoá độc quyền"; then
  ok "13. chờ tải không ăn vào thời gian chờ khoá Unity: suite chạy sau ${WALL}s"
else
  fail "13. chờ khoá bị trừ thời gian chờ tải (${WALL}s, exit $RC, chạy: $([ -f "$TMP/lockwait_ran" ] && echo có || echo không))"
fi
release_all; echo 1 > "$TMP/load"

# ── 14. Stop hook đặt ngân sách chờ tải ngắn (review 20/10): tải ≥ 100 kéo dài, lượt Stop có GATE_TOTAL_BUDGET_S 900 từng chờ tải tới
#       600 s (DEVKIT_SLOT_ADVISORY_BUDGET_S mặc định) rồi các suite sau thành BUDGET (exit 4). Hook phải truyền mặc định 120.
if grep -Eq '"DEVKIT_SLOT_ADVISORY_BUDGET_S": *os\.environ\.get\("DEVKIT_SLOT_ADVISORY_BUDGET_S", *"120"\)' "$DEVKIT_DIR/hooks/regression_gate.sh"; then
  ok "14. Stop hook truyền DEVKIT_SLOT_ADVISORY_BUDGET_S (mặc định 120) cho gate"
else
  fail "14. hooks/regression_gate.sh không truyền DEVKIT_SLOT_ADVISORY_BUDGET_S mặc định 120 cho gate"
fi

# ── 15. stale_rerun.main (SessionStart, chạy nền) không chờ tải (review 20/10): run_one chờ tải trong lúc giữ test_run.lock của dự án,
#       Stop gate của người dùng chờ khoá đó 45 s rồi ra BUSY. main đặt mặc định DEVKIT_SLOT_LOAD_WAIT_S=0, giá trị người gọi đặt vẫn giữ.
r15=$(python3 - "${STALE_RUN_DIR:-$DEVKIT_DIR/scripts/testing}" "$TMP/no-such-project" <<'PY' 2>/dev/null
import os, sys
here, proj = sys.argv[1:]
sys.path.insert(0, here)
import stale_rerun as sr
os.environ.pop("DEVKIT_SLOT_LOAD_WAIT_S", None)
sr.main([proj])
first = os.environ.get("DEVKIT_SLOT_LOAD_WAIT_S")
os.environ["DEVKIT_SLOT_LOAD_WAIT_S"] = "30"
sr.main([proj])
print(first, os.environ.get("DEVKIT_SLOT_LOAD_WAIT_S"))
PY
)
[ "$r15" = "0 30" ] && ok "15. stale_rerun.main: mặc định không chờ tải (0), giữ giá trị người gọi đặt" \
  || fail "15. stale_rerun.main: DEVKIT_SLOT_LOAD_WAIT_S '$r15', mong '0 30'"

# ── 16. Lần chạy lại (FLAKY_RETRY) giữ môi trường của suite (review 20/10): suite Unity giữ khoá Unity, lần 1 đỏ, lần 2 xanh. Lần 2 phải
#       còn SB_HEAVY_SLOT_HELD=1 — thiếu nó thì gate lồng trong lần chạy lại chờ chính khoá Unity của gate cha rồi ra SLOT (FAIL giả).
release_all; echo 1 > "$TMP/load"; rm -f "$TMP/flaky_env" "$TMP/flaky_once"
make_repo "$TMP/flaky" "./unity-batch.sh editmode" unity-batch.sh \
  "printf 'HELD=%s\\n' \"\${SB_HEAVY_SLOT_HELD:-}\" >> '$TMP/flaky_env'; [ -f '$TMP/flaky_once' ] && exit 0; touch '$TMP/flaky_once'; exit 1"
FLAKY_RETRY=1 run_gate "$TMP/flaky"
f16="$(tr '\n' ' ' < "$TMP/flaky_env" 2>/dev/null)"
if [ "$f16" = "HELD=1 HELD=1 " ]; then
  ok "16. lần chạy lại flaky vẫn có SB_HEAVY_SLOT_HELD=1 (exit $RC)"
else
  fail "16. môi trường 2 lần chạy suite Unity: '$f16' (exit $RC), mong 'HELD=1 HELD=1 '"
fi

# ── 17. Đường song song (parallel_safe): hai suite nhẹ cùng nhóm, tải cao mãi, trần chờ tải 1 s ⇒ cả hai chờ rồi VẪN chạy, exit 0.
#       Mỗi suite chờ marker của suite kia (tối đa ~5 s): chỉ xanh khi hai suite chạy CÙNG LÚC (DEVKIT_GATE_PARALLEL=1 thì đỏ).
S17="$TMP/par"; mkdir -p "$S17/src"
( cd "$S17" && git init -q . && git config user.email t@t && git config user.name t && echo 'x = 1' > src/a.py
  python3 - "$S17/matrix.json" "$TMP/par_a" "$TMP/par_b" <<'PY'
import json, sys
path, ma, mb = sys.argv[1:]
meet = lambda mine, other: (f"touch '{mine}'; i=0; while [ ! -f '{other}' ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done; "
                            f"[ -f '{other}' ]")
json.dump({"project": "t", "rules": [{"component": "A", "watch_files": ["src/a.py"], "mandatory_regression_tests": [
    {"id": "REG-P1", "name": "one", "command": meet(ma, mb), "parallel_safe": True},
    {"id": "REG-P2", "name": "two", "command": meet(mb, ma), "parallel_safe": True}]}]}, open(path, "w"))
PY
  git add -A && git commit -qm init && echo 'x = 2' > src/a.py ) || { echo "✖ setup: repo par"; exit 1; }
echo 150 > "$TMP/load"
DEVKIT_SLOT_LOAD_WAIT_S=1 DEVKIT_GATE_PARALLEL="${SLOT_TEST_PARALLEL:-2}" run_gate "$S17"
if [ "$RC" = 0 ] && [ -f "$TMP/par_a" ] && [ -f "$TMP/par_b" ] && printf '%s\n' "$OUT" | grep -q "vẫn chạy"; then
  ok "17. song song: hai suite nhẹ tải cao chờ rồi vẫn chạy, exit 0 (${WALL}s)"
else
  fail "17. song song tải cao (exit $RC, a: $([ -f "$TMP/par_a" ] && echo có || echo không), b: $([ -f "$TMP/par_b" ] && echo có || echo không))"
  printf '%s\n' "$OUT" | grep -E "REG-P|KẾT LUẬN|heavy-slot" | head -6
fi
echo 1 > "$TMP/load"

# ── 18. Như ca 13 nhưng gate có ngân sách (GATE_TOTAL_BUDGET_S=60 ⇒ acquire_for_suite nhận max_wait; Stop hook và run_one luôn có):
#       chờ khoá Unity vẫn tính SAU lần chờ tải (Antigravity audit 20/10: hạn khoá t_start + min(SB_HEAVY_SLOT_WAIT_S, max_wait) để lần
#       chờ tải ăn mất SB_HEAVY_SLOT_WAIT_S ⇒ SLOT ở ~giây 5 dù khoá được thả ở giây 9).
echo 150 > "$TMP/load"
hold unity-1.lock; HOLDER18="${PIDS##* }"
( sleep 9; kill "$HOLDER18" 2>/dev/null ) & PIDS="$PIDS $!"
make_repo "$TMP/lockwait18" "touch '$TMP/lockwait18_ran'; unity-batch.sh editmode"
DEVKIT_SLOT_LOAD_WAIT_S=5 SB_HEAVY_SLOT_WAIT_S=5 GATE_TOTAL_BUDGET_S=60 run_gate "$TMP/lockwait18"
# (unity-batch.sh không có trên PATH ở máy test: suite chạy rồi FAIL exit 1 — đúng; SLOT/UNTESTED thì exit 4)
if [ -f "$TMP/lockwait18_ran" ] && [ "$RC" != 4 ] && ! printf '%s\n' "$OUT" | grep -q "khoá độc quyền"; then
  ok "18. có ngân sách gate: chờ tải không ăn vào thời gian chờ khoá Unity, suite chạy sau ${WALL}s"
else
  fail "18. có ngân sách gate: chờ khoá bị trừ thời gian chờ tải (${WALL}s, exit $RC, chạy: $([ -f "$TMP/lockwait18_ran" ] && echo có || echo không))"
fi
release_all
# 18b. max_wait vẫn là trần TỔNG từ lúc vào: ngân sách 4 s, chờ tải 2 s, khoá Unity bận mãi, SB_HEAVY_SLOT_WAIT_S=120 ⇒ exit 4 sớm
#      (không phải 2 s chờ tải + 120 s chờ khoá).
hold unity-1.lock
make_repo "$TMP/lockwait18b" "touch '$TMP/lockwait18b_ran'; unity-batch.sh editmode"
DEVKIT_SLOT_LOAD_WAIT_S=2 SB_HEAVY_SLOT_WAIT_S=120 GATE_TOTAL_BUDGET_S=4 run_gate "$TMP/lockwait18b"
if [ ! -f "$TMP/lockwait18b_ran" ] && [ "$RC" = 4 ] && lt "$WALL" 40; then
  ok "18b. ngân sách gate vẫn là trần tổng của chờ tải + chờ khoá (${WALL}s, exit 4)"
else
  fail "18b. ngân sách gate không chặn tổng thời gian chờ (${WALL}s, exit $RC, chạy: $([ -f "$TMP/lockwait18b_ran" ] && echo có || echo không))"
fi
release_all; echo 1 > "$TMP/load"

# ── 19. Ngân sách chờ tải trên đường song song (đơn vị; OCR 20/10 và OCR 21/10): ngân sách là thời gian ĐỒNG HỒ tiến trình chờ tải —
#       các lần chờ chồng nhau chỉ tính một lần, và suite nào vào lúc tải cao cũng chờ (không suite nào chạy ngay vì suite khác đã giữ
#       hết ngân sách). Ngân sách 2 s, tải 150 mãi, 3 luồng vào lệch nhau 0 / 0.5 / 1 s: luồng nào cũng chờ (≥ 0.7 s) và cả lượt xong
#       trong ≈ 2 s tính từ lúc luồng đầu vào. Bản cộng phần chi sau khi chờ: luồng thứ ba chờ tới giây 3. Bản giữ chỗ trước: luồng 2–3
#       không chờ. Đo bằng đồng hồ quanh acquire_for_suite, không đọc sổ nội bộ.
echo 150 > "$TMP/load19"
DEVKIT_SLOT_LOAD_FILE="$TMP/load19" DEVKIT_SLOT_LOAD_WAIT_S=2 DEVKIT_SLOT_ADVISORY_BUDGET_S=2 SB_HEAVY_SLOT_POLL_S=0.2 \
  python3 - "$DEVKIT_DIR/bin" <<'PY' || FAILS=$((FAILS + 1))
import sys, threading, time
sys.path.insert(0, sys.argv[1])
import heavy_slot as hs
waits, ends, lock = {}, [], threading.Lock()
t_first = time.monotonic()
def run(i):
    time.sleep(0.5 * i)
    t0 = time.monotonic()
    hs.acquire_for_suite({"engine": None}, label=f"t19-{i}")
    t1 = time.monotonic()
    with lock:
        waits[i] = t1 - t0
        ends.append(t1)
threads = [threading.Thread(target=run, args=(i,)) for i in range(3)]
for t in threads:
    t.start()
for t in threads:
    t.join()
wall = max(ends) - t_first if ends else 99.0
shortest = min(waits.values()) if len(waits) == 3 else 0.0
last = waits.get(2, 99.0)
# luồng vào sau cùng (giây 1) chỉ còn 1 s ngân sách: chờ ≈ 1 (≤ 1.3). Bản đặt lại mốc bắt đầu khi có suite mới vào (đếm thiếu): ≈ 1.5.
good = len(waits) == 3 and shortest >= 0.7 and last <= 1.3 and wall < 2.4
print(("✔ 19. " if good else "✖ 19. ") + f"3 suite song song vào lệch 0.5 s, ngân sách 2 s: chờ ngắn nhất {shortest:.1f}s (mong ≥ 0.7), "
      f"luồng cuối {last:.1f}s (mong ≤ 1.3), cả lượt {wall:.1f}s (mong < 2.4; bản cộng sau ≈ 3, bản giữ chỗ: luồng sau chờ 0)")
sys.exit(0 if good else 1)
PY
# 19b. Mong đợi: phần giữ chỗ chưa dùng được trả lại — suite đầu chạy lúc tải thấp (chờ 0 s), rồi suite sau lúc tải cao chờ ~2 s.
#      Bản giữ chỗ mà quên trả lại sẽ cho suite sau ngân sách 0 (chờ ~0 s) và ca này đỏ.
echo 1 > "$TMP/load19"
DEVKIT_SLOT_LOAD_FILE="$TMP/load19" DEVKIT_SLOT_LOAD_WAIT_S=2 DEVKIT_SLOT_ADVISORY_BUDGET_S=2 \
  python3 - "$DEVKIT_DIR/bin" "$TMP/load19" <<'PY' || FAILS=$((FAILS + 1))
import sys, time
sys.path.insert(0, sys.argv[1])
import heavy_slot as hs
hs.acquire_for_suite({"engine": None}, label="t19b-low")
open(sys.argv[2], "w").write("150\n")
t0 = time.monotonic()
hs.acquire_for_suite({"engine": None}, label="t19b-high")
waited = time.monotonic() - t0
good = waited >= 1.5
print(("✔ 19b. " if good else "✖ 19b. ") + f"lần chờ 0 s trả lại chỗ giữ: suite sau chờ {waited:.1f}s (mong ≈ 2)")
sys.exit(0 if good else 1)
PY

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_slot_classes: all passed" || { echo "❌ test_gate_slot_classes: $FAILS failed"; exit 1; }
