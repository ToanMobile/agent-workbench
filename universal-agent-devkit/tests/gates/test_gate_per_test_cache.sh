#!/usr/bin/env bash
# Test hồi quy (audit DevKit 25/10, mục B2): một TIMEOUT của REG-DK-ALL-01 (run_impacted.sh) từng vô hiệu MỌI PASS bên trong nó — lượt sau
# chạy lại cả tập rồi lại quá giờ. Nay run_impacted.sh ghi PASS của từng test ngay khi test đó xong (tests/lib/per_test_cache.py, kho của
# bin/suite_cache.py, khoá = bao đóng của chính test) và lượt sau bỏ qua test có PASS trên đúng khoá của nó. Gate bật việc này
# (DEVKIT_PER_TEST_CACHE); `run_impacted.sh` gọi trực tiếp (agent-kit test) thì chạy hết.
# Kit giả: run_impacted.sh THẬT + helper THẬT, ba test (t1 đọc lib/in1.txt, t2 không đọc gì, t3 đọc lib/in3.txt và treo / FAIL theo cờ ngoài
# cây). Mỗi test ghi một dòng vào count.<tên> khi CHẠY XONG (lần bị giết không đếm).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_SUITE_CACHE_MAX_S DEVKIT_SENTINEL_MAX_S CI FLAKY_RETRY DEVKIT_GATE_PARALLEL \
  DEVKIT_GATE_DONE DEVKIT_IMPACT_TEST_CHANGED DEVKIT_IMPACTED_SINCE DEVKIT_TEST_JOBS DEVKIT_PER_TEST_CACHE DEVKIT_SUITE_CACHE \
  DEVKIT_TEST_TIMEOUT_S DEVKIT_FLAKY_QUARANTINE_S
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1
mkdir -p "$SB_HEAVY_SLOT_DIR"
# Tuổi PASS do sentinel theo test quyết (DEVKIT_SENTINEL_MAX_S mặc định 24 h), không do tuổi tối đa 6 h của kho.
export DEVKIT_SUITE_CACHE_MAX_S=2592000 DEVKIT_GATE_CACHE_MAX_S=2592000
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
n() { [ -f "$TMP/count.$1" ] && wc -l < "$TMP/count.$1" | tr -d ' ' || echo 0; }
counts() { echo "$(n t1) $(n t2) $(n t3)"; }

R="$TMP/repo"; KIT="$R/universal-agent-devkit"
mkdir -p "$KIT/tests/v" "$KIT/tests/lib" "$KIT/lib"
git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
cp "$DEVKIT_DIR/tests/run_impacted.sh" "$KIT/tests/run_impacted.sh"; : > "$KIT/tests/impact_map.txt"
cp "$DEVKIT_DIR/tests/lib/per_test_cache.py" "$DEVKIT_DIR/tests/lib/run_bounded.py" "$KIT/tests/lib/"
ln -s "$DEVKIT_DIR/bin" "$KIT/bin"   # post-fix-gate.py + suite_cache.py mà helper nạp
echo one > "$KIT/lib/in1.txt"; echo three > "$KIT/lib/in3.txt"; echo 0 > "$KIT/notes.txt"
printf 'cat "$(dirname "$0")/../../lib/in1.txt" >/dev/null\necho 1 >> %s/count.t1\n' "$TMP" > "$KIT/tests/v/test_t1.sh"
printf 'echo 2 >> %s/count.t2\n' "$TMP" > "$KIT/tests/v/test_t2.sh"
printf 'cat "$(dirname "$0")/../../lib/in3.txt" >/dev/null\n[ -f %s/hang3 ] && sleep 120\n[ -f %s/fail3 ] && exit 1\necho 3 >> %s/count.t3\n' \
  "$TMP" "$TMP" "$TMP" > "$KIT/tests/v/test_t3.sh"
# REG-ENV ghi DEVKIT_PER_TEST_CACHE mà một suite KHÁC thấy (P9: chỉ lệnh run_impacted.sh chuẩn nhận biến này)
printf '{"project":"t","rules":[{"component":"K","watch_files":["universal-agent-devkit/*"],"mandatory_regression_tests":[{"id":"REG-ALL","name":"all","command":"bash universal-agent-devkit/tests/run_impacted.sh --all"},{"id":"REG-ENV","name":"env","command":"echo ${DEVKIT_PER_TEST_CACHE:-unset} >> %s/env.txt"}]}]}\n' "$TMP" > "$R/matrix.json"
git -C "$R" add -A && git -C "$R" commit -qm init
STORE="$R/.git/postfix-gate/suite_cache"
# gate <notes> [args]: --full trên cây có notes.txt đổi (chưa commit: REG-ALL luôn được chọn). Mốc sentinel CẢ REPO đặt "vừa chạy" (hoặc
# $SENTINEL_AGE giây trước) để lượt này dùng khoá nội dung (repo mới tinh thì lượt nào cũng là sentinel); sentinel THEO TEST vẫn là 24 h mặc định.
gate() {
  local notes="$1"; shift
  echo "$notes" > "$KIT/notes.txt"
  mkdir -p "$STORE"; python3 -c 'import json, sys, time; json.dump({"last_real_full_at": time.time() - float(sys.argv[2])}, open(sys.argv[1], "w"))' \
    "$STORE/sentinel.json" "${SENTINEL_AGE:-0}"
  # DEVKIT_PER_TEST_CACHE=1 sẵn trong môi trường của gate (gate chạy trong một test của run_impacted, hay người dùng đặt): gate tự quyết
  ( cd "$R" && DEVKIT_PER_TEST_CACHE=1 FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" \
    --run-tests --full --no-checklist "$@" >"$TMP/out" 2>&1 ); RC=$?
}
# age <test> <giây>: lùi last_pass_at của mọi bản ghi per-test của test đó về <giây> trước
age() { python3 - "$STORE/per_test" "$1" "$2" <<'PY'
import json, os, sys, time
store, name, secs = sys.argv[1], sys.argv[2], float(sys.argv[3])
for f in os.listdir(store):
    p = os.path.join(store, f)
    if not f.endswith(".json") or len(f) != 69:
        continue
    rec = json.load(open(p))
    if str(rec.get("id", "")).endswith("/" + name):
        rec["last_pass_at"] = time.time() - secs
        json.dump(rec, open(p, "w"))
PY
}

# P1. REG-ALL quá giờ sau khi t1, t2 PASS (t3 treo): gate giết cả nhóm.
: > "$TMP/hang3"
gate 1 --timeout 40
if [ "$RC" != 0 ] && grep -q "TIMEOUT" "$TMP/out" && [ "$(counts)" = "1 1 0" ]; then ok "P1. REG-ALL TIMEOUT sau hai PASS (t1, t2 xong; t3 bị giết)"
else fail "P1. exit $RC, đếm t1 t2 t3 = $(counts) (mong ≠0, 1 1 0, có TIMEOUT)"; grep -E "REG-ALL|TIMEOUT" "$TMP/out" | tail -3; fi
rm -f "$TMP/hang3"

# P2. Cùng cây, hết treo: chỉ t3 chạy — PASS của t1, t2 ghi trước TIMEOUT được dùng lại; t3 (bị giết, không có kết luận) chạy.
gate 1
if [ "$RC" = 0 ] && [ "$(counts)" = "1 1 1" ]; then ok "P2. lượt sau cùng input: chỉ t3 chạy (t1, t2 dùng lại PASS theo khoá của chính nó)"
else fail "P2. exit $RC, đếm t1 t2 t3 = $(counts) (mong 0, 1 1 1)"; grep -E "REG-ALL|per_test" "$TMP/out" | tail -3; fi

# P3. Đổi input của t1 (lib/in1.txt): chỉ t1 chạy lại; t2, t3 vẫn dùng lại (khoá theo bao đóng của từng test, không theo cả cây).
echo uno > "$KIT/lib/in1.txt"
gate 2
if [ "$RC" = 0 ] && [ "$(counts)" = "2 1 1" ]; then ok "P3. đổi input của t1: chỉ t1 chạy lại"
else fail "P3. exit $RC, đếm t1 t2 t3 = $(counts) (mong 0, 2 1 1)"; fi

# P4. Sentinel theo test: PASS của t2 từ 25 h trước chạy lại; PASS của t3 từ 23 h trước vẫn dùng lại.
age test_t2.sh 90000; age test_t3.sh 82800
gate 3
if [ "$RC" = 0 ] && [ "$(counts)" = "2 2 1" ]; then ok "P4. PASS dùng lại đã 25 h: t2 chạy thật lại; 23 h: t3 vẫn dùng lại"
else fail "P4. exit $RC, đếm t1 t2 t3 = $(counts) (mong 0, 2 2 1)"; fi

# P5. FAIL trên khoá: t3 FAIL (input mới ⇒ khoá mới, cờ fail3 ngoài cây), lượt sau (cùng khoá, hết cờ) chạy t3 lại.
: > "$TMP/fail3"; echo quattro > "$KIT/lib/in3.txt"
gate 4
c5a="$(counts)"; r5a=$RC
rm -f "$TMP/fail3"
gate 5
if [ "$r5a" != 0 ] && [ "$c5a" = "2 2 1" ] && [ "$RC" = 0 ] && [ "$(counts)" = "2 2 2" ]; then ok "P5. t3 FAIL: lượt sau chạy t3 lại (t1, t2 vẫn dùng lại)"
else fail "P5. exit $r5a rồi $RC (mong ≠0 rồi 0), đếm $c5a rồi $(counts) (mong 2 2 1 rồi 2 2 2)"; fi

# P6. Chập chờn: t3 FAIL rồi PASS trên CÙNG khoá (P5) ⇒ cách ly. Đổi input của t3 (khoá mới, PASS sạch) rồi một lượt nữa: t3 vẫn chạy.
echo tres > "$KIT/lib/in3.txt"
gate 6
gate 7
if [ "$RC" = 0 ] && [ "$(counts)" = "2 2 4" ] && grep -q "test_t3.sh" "$STORE/per_test/quarantine.json" 2>/dev/null; then
  ok "P6. FAIL rồi PASS cùng khoá: t3 bị cách ly, PASS sạch trên khoá mới cũng không được dùng lại"
else fail "P6. exit $RC, đếm t1 t2 t3 = $(counts) (mong 0, 2 2 4); quarantine: $(cat "$STORE/per_test/quarantine.json" 2>/dev/null)"; fi

# P7. run_impacted.sh gọi trực tiếp: không có DEVKIT_PER_TEST_CACHE (agent-kit test) thì chạy hết; có thì in test dùng lại là "↺".
B="$(counts)"
( cd "$R" && bash universal-agent-devkit/tests/run_impacted.sh --all >"$TMP/out7" 2>&1 ); r7=$?
plain="$(counts)"
( cd "$R" && DEVKIT_PER_TEST_CACHE=1 bash universal-agent-devkit/tests/run_impacted.sh --all >"$TMP/out7b" 2>&1 ); r7b=$?
if [ "$r7 $r7b" = "0 0" ] && [ "$B" = "2 2 4" ] && [ "$plain" = "3 3 5" ] && [ "$(counts)" = "3 3 6" ] \
   && grep -q "^↺ tests/v/test_t1.sh" "$TMP/out7b" && grep -q "^✔ tests/v/test_t3.sh" "$TMP/out7b" && ! grep -qE "FAIL|✖" "$TMP/out7b"; then
  ok "P7. không có DEVKIT_PER_TEST_CACHE: chạy hết; có: t1, t2 in '↺' (dùng lại), t3 cách ly vẫn chạy"
else fail "P7. exit $r7 $r7b, đếm $B → $plain → $(counts) (mong 2 2 4 → 3 3 5 → 3 3 6)"; cat "$TMP/out7b"; fi

# P8. --no-cache, và lượt sentinel của cả repo (mốc 2 ngày trước): gate đặt DEVKIT_PER_TEST_CACHE=record ⇒ cả ba test chạy thật.
gate 8 --no-cache; r8=$RC; c8="$(counts)"
SENTINEL_AGE=172800 gate 9; r9=$RC
if [ "$r8 $r9" = "0 0" ] && [ "$c8" = "4 4 7" ] && [ "$(counts)" = "5 5 8" ]; then ok "P8. --no-cache và lượt sentinel: mọi test chạy thật"
else fail "P8. exit $r8 $r9 (mong 0 0), đếm $c8 rồi $(counts) (mong 4 4 7 rồi 5 5 8)"; fi

# P9. Suite khác (REG-ENV) không thấy DEVKIT_PER_TEST_CACHE, kể cả khi môi trường của gate có sẵn biến đó.
envs="$(sort -u "$TMP/env.txt" 2>/dev/null | tr '\n' ' ')"
if [ "$envs" = "unset " ]; then ok "P9. chỉ lệnh run_impacted.sh chuẩn nhận DEVKIT_PER_TEST_CACHE (REG-ENV thấy: unset)"
else fail "P9. REG-ENV thấy DEVKIT_PER_TEST_CACHE = '$envs' (mong 'unset ')"; fi

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_per_test_cache: all passed" || { echo "❌ test_gate_per_test_cache: $FAILS failed"; exit 1; }
