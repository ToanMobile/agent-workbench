#!/usr/bin/env bash
# Test hồi quy (audit DevKit 25/10, mục B2): một TIMEOUT của REG-DK-ALL-01 (run_impacted.sh) từng vô hiệu MỌI PASS bên trong nó — lượt sau
# chạy lại cả tập rồi lại quá giờ. Nay run_impacted.sh ghi PASS của từng test ngay khi test đó xong (tests/lib/per_test_cache.py, kho của
# bin/suite_cache.py) và lượt sau trên ĐÚNG CÂY đó bỏ qua test đã PASS. Khoá = khoá cả cây của lệnh `bash <test>` (nội dung mọi file + đường
# dẫn test + môi trường), không theo bao đóng tĩnh: bao đóng bỏ sót `"$D/lib/x"` và `import` trong heredoc python của file .sh (review 26/10,
# N1/N2). Gate bật việc này (DEVKIT_PER_TEST_CACHE); `run_impacted.sh` gọi trực tiếp (agent-kit test) thì chạy hết.
# Kit giả: run_impacted.sh THẬT + helper THẬT, sáu test: t1 đọc lib/in1.txt, t2 không đọc gì, t3 đọc lib/in3.txt và treo / FAIL theo cờ ngoài
# cây, t4 đọc "$D/lib/x4.txt", t5 import mod5 trong heredoc, t6 thoát 139 theo cờ. Mỗi test ghi một dòng vào count.<tên> khi CHẠY XONG.
# P1–P3, P8, P9 qua gate thật; ca cần chạy lại trên CÙNG cây (P4–P7, N1–N3) gọi run_impacted.sh trực tiếp với DEVKIT_PER_TEST_CACHE như gate
# đặt — sau một lượt PASS, gate trên cùng cây dùng lại cả suite REG-ALL (khoá cả cây + tập chọn: test_gate_suite_cache_selection.sh S1).
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
# Tuổi tối đa của PASS dùng lại: mặc định của kho (SuiteCache.hit, 6 h — DEVKIT_SUITE_CACHE_MAX_S / DEVKIT_GATE_CACHE_MAX_S bị unset ở trên); P4.
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
n() { [ -f "$TMP/count.$1" ] && wc -l < "$TMP/count.$1" | tr -d ' ' || echo 0; }
counts() { echo "$(n t1) $(n t2) $(n t3)"; }
delta() { set -- $1; echo "$(( $(n t1) - $1 )) $(( $(n t2) - $2 )) $(( $(n t3) - $3 ))"; }   # delta "<counts trước>"

R="$TMP/repo"; KIT="$R/universal-agent-devkit"
mkdir -p "$KIT/tests/v" "$KIT/tests/lib" "$KIT/lib"
git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
cp "$DEVKIT_DIR/tests/run_impacted.sh" "$KIT/tests/run_impacted.sh"; : > "$KIT/tests/impact_map.txt"
cp "$DEVKIT_DIR/tests/lib/per_test_cache.py" "$DEVKIT_DIR/tests/lib/run_bounded.py" "$KIT/tests/lib/"
ln -s "$DEVKIT_DIR/bin" "$KIT/bin"   # post-fix-gate.py + suite_cache.py mà helper nạp
echo one > "$KIT/lib/in1.txt"; echo three > "$KIT/lib/in3.txt"; echo 0 > "$KIT/notes.txt"; echo x > "$KIT/lib/x4.txt"
echo 'OK = True' > "$KIT/lib/mod5.py"
printf 'cat "$(dirname "$0")/../../lib/in1.txt" >/dev/null\necho 1 >> %s/count.t1\n' "$TMP" > "$KIT/tests/v/test_t1.sh"
printf 'echo 2 >> %s/count.t2\n' "$TMP" > "$KIT/tests/v/test_t2.sh"
printf 'cat "$(dirname "$0")/../../lib/in3.txt" >/dev/null\n[ -f %s/hang3 ] && sleep 120\n[ -f %s/fail3 ] && exit 1\necho 3 >> %s/count.t3\n' \
  "$TMP" "$TMP" "$TMP" > "$KIT/tests/v/test_t3.sh"
# t4, t5: input chỉ tới qua biến / heredoc — bao đóng tĩnh không thấy (review 26/10, F1)
printf 'D="$(cd "$(dirname "$0")/../.." && pwd)"\ncat "$D/lib/x4.txt" >/dev/null || exit 1\necho 4 >> %s/count.t4\n' "$TMP" > "$KIT/tests/v/test_t4.sh"
printf 'D="$(cd "$(dirname "$0")/../.." && pwd)"\nPYTHONPATH="$D/lib" python3 - <<%sEOF%s || exit 1\nimport mod5\nassert mod5.OK\nEOF\necho 5 >> %s/count.t5\n' \
  "'" "'" "$TMP" > "$KIT/tests/v/test_t5.sh"
printf '[ -f %s/crash6 ] && exit 139\necho 6 >> %s/count.t6\n' "$TMP" "$TMP" > "$KIT/tests/v/test_t6.sh"
# REG-ENV ghi DEVKIT_PER_TEST_CACHE mà một suite KHÁC thấy (P9: chỉ lệnh run_impacted.sh chuẩn nhận biến này)
printf '{"project":"t","rules":[{"component":"K","watch_files":["universal-agent-devkit/*"],"mandatory_regression_tests":[{"id":"REG-ALL","name":"all","command":"bash universal-agent-devkit/tests/run_impacted.sh --all"},{"id":"REG-ENV","name":"env","command":"echo ${DEVKIT_PER_TEST_CACHE:-unset} >> %s/env.txt"}]}]}\n' "$TMP" > "$R/matrix.json"
git -C "$R" add -A && git -C "$R" commit -qm init
STORE="$R/.git/postfix-gate/suite_cache"
# gate <notes> [args]: --full trên cây có notes.txt = <notes> (chưa commit: REG-ALL luôn được chọn). Mốc sentinel CẢ REPO đặt "vừa chạy"
# (hoặc $SENTINEL_AGE giây trước) để lượt này dùng khoá nội dung (repo mới tinh thì lượt nào cũng là sentinel).
gate() {
  local notes="$1"; shift
  echo "$notes" > "$KIT/notes.txt"
  mkdir -p "$STORE"; python3 -c 'import json, sys, time; json.dump({"last_real_full_at": time.time() - float(sys.argv[2])}, open(sys.argv[1], "w"))' \
    "$STORE/sentinel.json" "${SENTINEL_AGE:-0}"
  # DEVKIT_PER_TEST_CACHE=1 sẵn trong môi trường của gate (gate chạy trong một test của run_impacted, hay người dùng đặt): gate tự quyết
  ( cd "$R" && DEVKIT_PER_TEST_CACHE=1 FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" \
    --run-tests --full --no-checklist "$@" >"$TMP/out" 2>&1 ); RC=$?
}
# direct <DEVKIT_PER_TEST_CACHE ("" = không đặt)> <file output>: run_impacted.sh --all gọi thẳng, trên cây đang có
direct() {
  if [ -n "$1" ]; then ( cd "$R" && DEVKIT_PER_TEST_CACHE="$1" bash universal-agent-devkit/tests/run_impacted.sh --all >"$TMP/$2" 2>&1 ); RC=$?
  else ( cd "$R" && bash universal-agent-devkit/tests/run_impacted.sh --all >"$TMP/$2" 2>&1 ); RC=$?; fi
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
if [ "$RC" = 0 ] && [ "$(counts)" = "1 1 1" ]; then ok "P2. lượt sau cùng cây: chỉ t3 chạy (t1, t2 dùng lại PASS ghi trước TIMEOUT)"
else fail "P2. exit $RC, đếm t1 t2 t3 = $(counts) (mong 0, 1 1 1)"; grep -E "REG-ALL|per_test" "$TMP/out" | tail -3; fi

# P3. Đổi input của t1 (lib/in1.txt): cây khác ⇒ khoá của MỌI test khác ⇒ cả ba chạy lại (khoá theo cả cây).
B="$(counts)"; echo uno > "$KIT/lib/in1.txt"
gate 2
if [ "$RC" = 0 ] && [ "$(delta "$B")" = "1 1 1" ]; then ok "P3. đổi input của t1: cây khác, mọi test chạy lại"
else fail "P3. exit $RC, t1 t2 t3 chạy thêm $(delta "$B") (mong 0, 1 1 1)"; fi

# P4. Tuổi tối đa (cùng cây, mặc định 6 h): PASS của t2 từ 7 h trước chạy lại; PASS của t3 từ 5 h trước vẫn dùng lại.
B="$(counts)"; age test_t2.sh 25200; age test_t3.sh 18000
direct 1 out4
if [ "$RC" = 0 ] && [ "$(delta "$B")" = "0 1 0" ]; then ok "P4. PASS dùng lại đã 7 h (> 6 h mặc định): t2 chạy thật lại; 5 h: t3 vẫn dùng lại"
else fail "P4. exit $RC, t1 t2 t3 chạy thêm $(delta "$B") (mong 0, 0 1 0)"; fi

# P5. FAIL trên khoá: cây mới, t3 FAIL (cờ fail3 ngoài cây); lượt sau cùng cây, hết cờ: t3 chạy lại, t1 t2 dùng lại.
echo 3 > "$KIT/notes.txt"; : > "$TMP/fail3"
B="$(counts)"; direct 1 out5a; r5a=$RC; d5a="$(delta "$B")"
rm -f "$TMP/fail3"
B="$(counts)"; direct 1 out5b
if [ "$r5a" != 0 ] && [ "$d5a" = "1 1 0" ] && [ "$RC" = 0 ] && [ "$(delta "$B")" = "0 0 1" ]; then ok "P5. t3 FAIL: lượt sau cùng cây chạy t3 lại (t1, t2 dùng lại)"
else fail "P5. exit $r5a rồi $RC (mong ≠0 rồi 0), chạy thêm $d5a rồi $(delta "$B") (mong 1 1 0 rồi 0 0 1)"; fi

# P6. Chập chờn: t3 FAIL rồi PASS trên CÙNG khoá (P5) ⇒ cách ly. Cây mới (PASS sạch của t3) rồi một lượt nữa cùng cây: t3 vẫn chạy.
echo 4 > "$KIT/notes.txt"
direct 1 out6a
B="$(counts)"; direct 1 out6b
if [ "$RC" = 0 ] && [ "$(delta "$B")" = "0 0 1" ] && grep -q "test_t3.sh" "$STORE/per_test/quarantine.json" 2>/dev/null; then
  ok "P6. FAIL rồi PASS cùng khoá: t3 bị cách ly, PASS sạch trên cây mới cũng không được dùng lại"
else fail "P6. exit $RC, t1 t2 t3 chạy thêm $(delta "$B") (mong 0, 0 0 1); quarantine: $(cat "$STORE/per_test/quarantine.json" 2>/dev/null)"; fi

# P7. run_impacted.sh gọi trực tiếp: không có DEVKIT_PER_TEST_CACHE (agent-kit test) thì chạy hết; có thì in test dùng lại là "↺".
B="$(counts)"; direct "" out7; r7=$RC; d7="$(delta "$B")"
B="$(counts)"; direct 1 out7b
if [ "$r7 $RC" = "0 0" ] && [ "$d7" = "1 1 1" ] && [ "$(delta "$B")" = "0 0 1" ] \
   && grep -q "^↺ tests/v/test_t1.sh" "$TMP/out7b" && grep -q "^✔ tests/v/test_t3.sh" "$TMP/out7b" && ! grep -qE "FAIL|✖" "$TMP/out7b"; then
  ok "P7. không có DEVKIT_PER_TEST_CACHE: chạy hết; có: t1, t2 in '↺' (dùng lại), t3 cách ly vẫn chạy"
else fail "P7. exit $r7 $RC, chạy thêm $d7 rồi $(delta "$B") (mong 1 1 1 rồi 0 0 1)"; cat "$TMP/out7b"; fi

# N1 (review F1). t4 đọc "$D/lib/x4.txt" (token D/lib/x4.txt, kit lồng trong universal-agent-devkit/): đổi x4.txt ⇒ t4 phải chạy lại.
b4=$(n t4); echo x2 > "$KIT/lib/x4.txt"; direct 1 outn1
if [ "$RC" = 0 ] && [ "$(n t4)" = $((b4 + 1)) ] && ! grep -q "^↺ tests/v/test_t4.sh" "$TMP/outn1"; then ok "N1. đổi file t4 đọc qua biến \$D: t4 chạy lại"
else fail "N1. exit $RC, t4 chạy $b4 → $(n t4) (mong +1); $(grep 'test_t4' "$TMP/outn1")"; fi

# N2 (review F1). t5 `import mod5` trong heredoc python của file .sh: đổi mod5.py ⇒ t5 phải chạy lại.
b5=$(n t5); echo 'OK = True  # v2' > "$KIT/lib/mod5.py"; direct 1 outn2
if [ "$RC" = 0 ] && [ "$(n t5)" = $((b5 + 1)) ] && ! grep -q "^↺ tests/v/test_t5.sh" "$TMP/outn2"; then ok "N2. đổi mod5.py (import trong heredoc): t5 chạy lại"
else fail "N2. exit $RC, t5 chạy $b5 → $(n t5) (mong +1); $(grep 'test_t5' "$TMP/outn2")"; fi

# N3 (review F2). t6 có PASS trên khoá này (N2); lượt chỉ-ghi (như sentinel / --no-cache) t6 thoát 139 (như crash SIGSEGV): lượt sau cùng
#    cây không được dùng lại PASS cũ của t6.
b6=$(n t6); : > "$TMP/crash6"; direct record outn3a; r3a=$RC
rm -f "$TMP/crash6"; direct 1 outn3b
if [ "$r3a" != 0 ] && grep -q "^✖ tests/v/test_t6.sh" "$TMP/outn3a" && [ "$RC" = 0 ] && [ "$(n t6)" = $((b6 + 1)) ] \
   && ! grep -q "^↺ tests/v/test_t6.sh" "$TMP/outn3b"; then ok "N3. t6 thoát 139 trên khoá đang PASS: lượt sau chạy t6 lại"
else fail "N3. exit $r3a rồi $RC (mong ≠0 rồi 0), t6 chạy $b6 → $(n t6) (mong +1); $(grep 'test_t6' "$TMP/outn3a" "$TMP/outn3b")"; fi

# P8. --no-cache, và lượt sentinel của cả repo (mốc 2 ngày trước): gate đặt DEVKIT_PER_TEST_CACHE=record ⇒ mọi test chạy thật, kể cả trên
#     cây mà mọi test đã có PASS theo test (N3 trên cây này; lượt sentinel: một lượt trực tiếp ghi PASS trên cây mới trước).
B="$(counts)"; gate 4 --no-cache; r8=$RC; d8="$(delta "$B")"
echo 10 > "$KIT/notes.txt"; direct 1 out8; B="$(counts)"
SENTINEL_AGE=172800 gate 10; r9=$RC
if [ "$r8 $r9" = "0 0" ] && [ "$d8" = "1 1 1" ] && [ "$(delta "$B")" = "1 1 1" ]; then ok "P8. --no-cache và lượt sentinel: mọi test chạy thật"
else fail "P8. exit $r8 $r9 (mong 0 0), chạy thêm $d8 rồi $(delta "$B") (mong 1 1 1 rồi 1 1 1)"; fi

# P9. Suite khác (REG-ENV) không thấy DEVKIT_PER_TEST_CACHE, kể cả khi môi trường của gate có sẵn biến đó.
envs="$(sort -u "$TMP/env.txt" 2>/dev/null | tr '\n' ' ')"
if [ "$envs" = "unset " ]; then ok "P9. chỉ lệnh run_impacted.sh chuẩn nhận DEVKIT_PER_TEST_CACHE (REG-ENV thấy: unset)"
else fail "P9. REG-ENV thấy DEVKIT_PER_TEST_CACHE = '$envs' (mong 'unset ')"; fi

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_per_test_cache: all passed" || { echo "❌ test_gate_per_test_cache: $FAILS failed"; exit 1; }
