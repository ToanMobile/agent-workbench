#!/usr/bin/env bash
# Test hồi quy (#377 / #338): gate đã bắt đầu thì chạy cho xong — không chờ tải, không nhường slot nặng lại trước từng suite.
# Đo 24/10: dưới tải ≥ 96 mỗi suite chờ tới 600 s TRƯỚC KHI chạy, kể cả khi gate đã chạy suite đầu; và một suite nặng sau của gate A bị gate B
# chen vào slot trống giữa hai suite (B đã xếp hàng lâu hơn). Luật:
#   - đã có suite của lượt này được cho chạy ⇒ các suite sau KHÔNG chờ tải nữa (tải đã được chờ một lần, ở suite đầu)
#   - hai suite nặng liên tiếp (tuần tự) của một lượt giữ NGUYÊN slot nặng giữa chúng: gate khác không chen được; tổng suite nặng chạy cùng lúc
#     vẫn ≤ heavy_max (suite trong nhóm song song vẫn xin slot riêng; slot nhả khi tới suite không nặng, suite song song hay hết lượt)
# Slot dir riêng (SB_HEAVY_SLOT_DIR), tải đọc từ file (DEVKIT_SLOT_LOAD_FILE): không đụng khoá thật của máy. Suite nặng = stub ./gradlew.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset SB_HEAVY_SLOT_HELD DEVKIT_SLOT_ADVISORY_HELD DEVKIT_SLOT_ADVISORY_BUDGET_S SB_HEAVY_SLOT_WAIT_S DEVKIT_SLOT_LOAD_WAIT_S \
  DEVKIT_SLOT_LOAD_MAX DEVKIT_SLOT_PRIORITY DEVKIT_SLOT_HEAVY_MAX DEVKIT_SLOT_HEAVY_WAIT_S DEVKIT_SLOT_HEAVY_BUDGET_S GATE_TOTAL_BUDGET_S CI \
  ANDROID_SERIAL FLAKY_RETRY DEVKIT_GATE_PARALLEL DEVKIT_GATE_CACHE DEVKIT_SENTINEL_MAX_S
export DEVKIT_CAPACITY_CORES=12   # ngưỡng tải mặc định = capacity hold_load = 96 (máy giả 12 lõi), như test_gate_slot_classes.sh
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
PIDS=""
cleanup() { for p in $PIDS; do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1 DEVKIT_SLOT_LOAD_FILE="$TMP/load" PROOF_DEVICE_LOCK_DIR="$TMP/devlocks" \
  DEVKIT_SENTINEL_MAX_S=999999999 DEVKIT_SUITE_CACHE=0 DEVKIT_GATE_CACHE=0
mkdir -p "$SB_HEAVY_SLOT_DIR"
echo 1 > "$TMP/load"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# make_repo <tên> <suite:giây ngủ>…: repo có stub ./gradlew (ghi "<suite> start|end <epoch>" vào $TMP/times.<tên>; suite t1 hạ tải giả lên 150), mỗi
# suite một rule theo dõi src/<suite>.py (đổi chưa commit ⇒ được chọn), lệnh `./gradlew <suite>` (lớp gradle = suite nặng)
make_repo() {
  local name="$1" r="$TMP/$1"; shift
  mkdir -p "$r/src"
  ( cd "$r" && git init -q . && git config user.email t@t && git config user.name t
    printf '%s\n' '#!/bin/sh' \
      "T=\"\$1\"; now() { python3 -c 'import time; print(time.time())'; }" \
      "echo \"\$T start \$(now)\" >> '$TMP/times.$name'" \
      "[ \"\$T\" = t1 ] && echo 150 > '$TMP/load'" \
      "sleep \"\$2\"" \
      "echo \"\$T end \$(now)\" >> '$TMP/times.$name'" > gradlew && chmod +x gradlew
    local rules="" first=1 spec s sec
    for spec in "$@"; do
      s="${spec%%:*}"; sec="${spec#*:}"; echo "$s = 1" > "src/$s.py"
      [ "$first" = 1 ] || rules="$rules,"; first=0
      rules="$rules{\"component\":\"$s\",\"watch_files\":[\"src/$s.py\"],\"mandatory_regression_tests\":[{\"id\":\"REG-$s\",\"name\":\"$s\",\"command\":\"./gradlew $s $sec\"}]}"
    done
    printf '{"project":"t","rules":[%s]}\n' "$rules" > matrix.json
    git add -A && git commit -qm init
    for spec in "$@"; do echo "${spec%%:*} = 2" > "src/${spec%%:*}.py"; done ) || { echo "✖ setup: repo $name"; exit 1; }
}
gate() { local n="$1" r="$TMP/$1"; shift; ( cd "$r" && FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$r" python3 "$GATE" --matrix "$r/matrix.json" \
  --run-tests --full --no-checklist "$@" ) >"$TMP/out.$n" 2>&1; }
# at <tên repo> <suite> start|end: epoch của dòng đó (rỗng nếu chưa có)
at() { awk -v s="$2" -v k="$3" '$1 == s && $2 == k { print $3; exit }' "$TMP/times.$1" 2>/dev/null; }
lt() { python3 -c "import sys; sys.exit(0 if $1 < $2 else 1)"; }

# ── G1 (AC6). Ba suite nặng nối nhau; suite 1 đẩy tải lên 150 khi đang chạy. Suite 2, 3 không được chờ tải (DEVKIT_SLOT_LOAD_WAIT_S=3 ⇒ bản cũ
#    chờ 3 s mỗi suite): khoảng nghỉ giữa suite trước xong và suite sau bắt đầu < 2 s, và không có dòng "chờ tải".
make_repo g1 t1:0.3 t2:0.3 t3:0.3
( DEVKIT_SLOT_LOAD_WAIT_S=3 gate g1 ) ; rc=$?
e1=$(at g1 t1 end); s2=$(at g1 t2 start); e2=$(at g1 t2 end); s3=$(at g1 t3 start)
if [ "$rc" = 0 ] && [ -n "$e1" ] && [ -n "$s3" ] && lt "$s2 - $e1" 2 && lt "$s3 - $e2" 2 && ! grep -q "chờ tải xuống" "$TMP/out.g1"; then
  ok "G1. đã có suite chạy: suite 2, 3 không chờ tải dù tải 150 (nghỉ $(python3 -c "print(round($s2 - $e1, 2), round($s3 - $e2, 2))") s)"
else
  fail "G1. (exit $rc; nghỉ 1→2: $([ -n "$e1" ] && python3 -c "print(round(${s2:-0} - $e1, 2))"), 2→3: $([ -n "$e2" ] && python3 -c "print(round(${s3:-0} - $e2, 2))"); dòng chờ tải: $(grep -c 'chờ tải xuống' "$TMP/out.g1"))"
  grep -E "heavy-slot" "$TMP/out.g1" | head -3
fi
echo 1 > "$TMP/load"

# ── G2 (AC7). heavy_max = 1. Gate A: hai suite nặng nối nhau (a1 2 s, a2 1 s). Gate B: một suite (b1 1 s) bắt đầu khi A đang chạy a1, xếp hàng
#    đợi slot. A không bị B chen giữa a1 và a2: thứ tự a1, a2, b1, và không hai suite nặng nào chạy cùng lúc (tổng ≤ heavy_max).
make_repo ga a1:2 a2:1; make_repo gb b1:1
export DEVKIT_SLOT_HEAVY_MAX=1 SB_HEAVY_SLOT_POLL_S=0.02   # B thăm slot mỗi 20 ms: khe hở giữa a1 và a2 mà không giữ slot thì B chen vào
gate ga & PIDS="$PIDS $!"; pa=$!
for _ in $(seq 1 100); do [ -n "$(at ga a1 start)" ] && break; sleep 0.05; done
sleep 0.4
gate gb & PIDS="$PIDS $!"; pb=$!
wait "$pa"; ra=$?; wait "$pb"; rb=$?
unset DEVKIT_SLOT_HEAVY_MAX; export SB_HEAVY_SLOT_POLL_S=0.1
a1s=$(at ga a1 start); a1e=$(at ga a1 end); a2s=$(at ga a2 start); a2e=$(at ga a2 end); b1s=$(at gb b1 start); b1e=$(at gb b1 end)
if [ "$ra $rb" = "0 0" ] && [ -n "$b1e" ] && [ -n "$a2e" ] \
   && lt "$a1e" "$a2s + 0.001" && lt "$a2e" "$b1s + 0.001" ; then
  ok "G2. gate A chạy xong a1, a2 liền nhau; gate B (xếp hàng) chạy sau, không chen, không chạy chồng (heavy_max=1)"
else
  fail "G2. (exit $ra $rb; a1 $a1s..$a1e, a2 $a2s..$a2e, b1 $b1s..$b1e — mong a1 < a2 < b1 không chồng)"
  grep -E "heavy-slot" "$TMP/out.ga" "$TMP/out.gb" | head -4
fi

# ── G3. Thư viện (xác định, không đua): suite nặng 1 nhả slot với keep_heavy ⇒ slot vẫn khoá, gate B đang xếp hàng KHÔNG lấy được; suite nặng 2
#    của cùng lượt (lease) dùng lại slot đó ngay (reused), không xếp hàng; chỉ khi suite 2 nhả hết B mới lấy được. Không có lease (khe hở giữa
#    hai suite) thì B chen vào: đó là điều gate A không được phép.
res3="$(DEVKIT_SLOT_HEAVY_MAX=1 SB_HEAVY_SLOT_POLL_S=0.02 python3 - "$DEVKIT_DIR/bin" <<'PY'
import sys, threading, time
sys.path.insert(0, sys.argv[1])
import heavy_slot as hs
info = {"cls": "cpu", "engine": None, "serial": None}
paths = hs.pool_paths("heavy", hs.heavy_max())
a1 = hs.acquire_for_suite(info, est_s=60, label="a1")
box = {}
def waiter():
    box["h"] = hs.acquire_pool("heavy", paths, wait_s=10, est_s=60, label="b1")
    box["t"] = time.monotonic()
th = threading.Thread(target=waiter); th.start()
time.sleep(0.4)   # B đã có vé và đang thăm slot
lease = hs.release_suite(a1, keep_heavy=True)
time.sleep(0.5)
out = []
out.append("lease_kept=%s" % (lease is not None and lease.fh is not None))
out.append("b_blocked=%s" % ("h" not in box))
a2 = hs.acquire_for_suite(info, est_s=60, label="a2", started=True, lease=lease)
t2 = time.monotonic()
out.append("a2_reused=%s" % (a2.reused is lease and a2.admitted))
out.append("b_still_blocked=%s" % ("h" not in box))
kept = hs.release_suite(a2)   # hết lượt: nhả hết
th.join(5)
out.append("b_after_a2=%s" % ("t" in box and box["t"] >= t2 and not box["h"].timed_out and kept is None))
hs.release_pool(box.get("h"))
print(" ".join(out))
PY
)"
if [ "$res3" = "lease_kept=True b_blocked=True a2_reused=True b_still_blocked=True b_after_a2=True" ]; then ok "G3. keep_heavy giữ slot giữa hai suite nặng: B không chen, suite 2 dùng lại (lease), B vào sau khi A nhả hết"
else fail "G3. ($res3)"; fi

# ── G4 (review R1). Suite theo khoá nội dung vào `sc.inflight` (chờ marker của gate khác cùng khoá) TRƯỚC khi xin slot. Lease giữ qua lần chờ đó
#    thì gate A (giữ slot nặng, chờ marker) và gate B (giữ marker, xếp hàng đúng slot ấy) chờ nhau tới hết hạn marker. Luật: run_suite nhả lease
#    TRƯỚC `with sc.inflight(`. Ghim thứ tự trong mã (ponytail: dựng hai gate tranh một khoá thật cần đồng bộ theo thời gian, test thành flaky;
#    nâng lên e2e khi harness có điểm dừng trong inflight).
if python3 - "$GATE" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"    def run_suite\(t, cmd, mode, env, sequential=False\):\n(.*?)\n\n", src, re.S)
body = m.group(1) if m else ""
i, j = body.find("drop_lease()"), body.find("sc.inflight(")
sys.exit(0 if 0 <= i < j else 1)
PY
then ok "G4. run_suite nhả lease slot nặng trước khi chờ marker cùng khoá (không giữ slot trong lúc chờ gate khác)"
else fail "G4. run_suite phải gọi drop_lease() trước sc.inflight(...): lease giữ qua lần chờ marker → hai gate chờ nhau"; fi

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_slot_started: all passed" || { echo "❌ test_gate_slot_started: $FAILS failed"; exit 1; }
