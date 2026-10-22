#!/usr/bin/env bash
# Test hồi quy (#247): bin/post-fix-gate.py dùng lại PASS đầy đủ từ store theo cây (<git common dir>/postfix-gate/tree_receipts/<fp>.json)
# khi worktree đã ghi biên nhận bị GỠ trước khi lượt sau chạy.
# 22/10 (agent-workbench): QA chạy lại đủ suite trên đúng cây builder đã PASS (issue-110, 202, 209: 52 phút/ngày) vì Builder bước 9 gỡ worktree,
# biên nhận full_pass.json đi theo git dir của nó nên sibling_receipts không còn thấy gì. Store theo cây (#105) còn đó nhưng chỉ proof_gate đọc.
# Luật mượn từ store: cùng các kiểm tra của cached_full_pass (cây, tuổi theo tested_at, ma trận, định dạng, local_sha) + exit 0, không
# carried_from. Không đòi "lượt chạy thật" như biên nhận anh em: một FAIL trên cây đó xoá đúng mục này (cùng khoá fp), nên bản chép dây chuyền
# (QA dùng lại PASS của builder rồi ghi đè mục) vẫn cho merge gate mượn, và tested_at cũ giữ nguyên nên không kéo dài tuổi.
# Chỉ lượt --full cưỡng bức trong git dir CHƯA từng chạy gate (scratch của merge gate, worktree QA mới) đọc store.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_GATE_CACHE_MAX_S DEVKIT_GATE_CACHE
export DEVKIT_SUITE_CACHE=0   # khoá nội dung từng suite (suite_cache.py) cũng dùng chung git common dir: tắt để chỉ đo biên nhận theo cây

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
COUNT="$TMP/runs.txt"
STORE_MSG="biên nhận theo cây"   # DEVKIT_LANG=vi (clean_git_env.sh)

R="$TMP/repo"
mkdir -p "$R/src" && cd "$R" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
cat > matrix.json <<JSON
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"echo run >> '$COUNT'; test ! -f .hong"}]}]}
JSON
printf '.hong\n' > .gitignore   # .hong (bị ignore, ngoài fingerprint): suite FAIL ở đúng thư mục có nó
git add -A && git commit -qm init
echo "fun ok() = 2" > src/Core.kt
git commit -qam change
COMMON="$(git rev-parse --path-format=absolute --git-common-dir)"
STORE="$COMMON/postfix-gate/tree_receipts"

run_gate() { local d="$1"; shift; ( cd "$d" && CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --matrix "$d/matrix.json" --run-tests --full --force-full --diff HEAD~1 "$@" 2>&1 ); }
runs() { [ -f "$COUNT" ] && wc -l < "$COUNT" | tr -d ' ' || echo 0; }
add_wt() { git -C "$R" worktree add -q --detach "$TMP/$1" HEAD || { echo "✖ setup: worktree add $1"; exit 1; }; }
rm_wt() { git -C "$R" worktree remove --force "$TMP/$1" || { echo "✖ setup: worktree remove $1"; exit 1; }; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
check() {   # check <tên> <exit mong đợi> <số lần suite chạy THÊM mong đợi> <nhắc store: yes|no> <runs trước> <exit thật> <output>
  local delta=$(( $(runs) - $5 )) st=no
  printf '%s\n' "$7" | grep -qF "$STORE_MSG" && st=yes
  if [ "$6" = "$2" ] && [ "$delta" = "$3" ] && [ "$st" = "$4" ]; then echo "✔ $1"
  else echo "✖ $1 (exit $6, mong $2; suite chạy thêm $delta lần, mong $3; nhắc store $st, mong $4)"; printf '%s\n' "$7" | tail -12; FAILS=$((FAILS + 1)); fi
}
# sạch mọi biên nhận: main checkout, mọi worktree còn lại, store theo cây
wipe() { rm -f "$COMMON/postfix-gate/full_pass.json" "$COMMON"/worktrees/*/postfix-gate/full_pass.json; rm -rf "$STORE"; }
store_file() { ls "$STORE"/*.json 2>/dev/null | head -1; }

# 1. Builder PASS thật rồi worktree bị gỡ (biên nhận của nó mất); lượt sau ở worktree mới, cùng cây: dùng lại từ store, suite không chạy.
wipe
add_wt wt-build
b=$(runs); out="$(run_gate "$TMP/wt-build" --no-cache)"; rc=$?
check "1. tiền đề: builder PASS thật, suite chạy" 0 1 no "$b" "$rc" "$out"
[ -n "$(store_file)" ] && echo "✔ 1. tiền đề: store theo cây có mục của lượt PASS" || { fail "1. tiền đề: store theo cây không có mục nào (dừng: các ca sau vô nghĩa)"; exit 1; }
rm_wt wt-build
TESTED0="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tested_at"])' "$(store_file)")"
add_wt wt-qa
b=$(runs); out="$(run_gate "$TMP/wt-qa")"; rc=$?
check "1. QA ở worktree mới, builder đã bị gỡ: dùng lại PASS từ store" 0 0 yes "$b" "$rc" "$out"
# lượt dùng lại làm mới mục store (chuỗi của ca 2): trường project giờ là của wt-qa
python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["project"].endswith("wt-qa") else 1)' "$(store_file)" \
  && echo "✔ 1. lượt dùng lại của QA đã ghi đè mục store (project = wt-qa)" || fail "1. mục store không được lượt dùng lại làm mới"

# 2. Dây chuyền: lượt QA (dùng lại) ghi đè mục store của builder; worktree QA cũng bị gỡ; merge gate (scratch mới) vẫn mượn được.
rm_wt wt-qa
add_wt wt-scratch
b=$(runs); out="$(run_gate "$TMP/wt-scratch")"; rc=$?
check "2. mục store do lượt dùng lại ghi đè: scratch mới vẫn mượn" 0 0 yes "$b" "$rc" "$out"
rm_wt wt-scratch
TESTED1="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tested_at"])' "$(store_file)")"
[ "$TESTED0" = "$TESTED1" ] && echo "✔ 2. tested_at của lượt thật giữ nguyên qua các lượt dùng lại (tuổi không bị kéo dài)" \
  || fail "2. tested_at đổi qua lượt dùng lại: $TESTED0 -> $TESTED1"

# 3. Cây khác một byte → không khớp mục nào → chạy đủ suite.
add_wt wt-t2
echo "fun ok() = 3" > "$TMP/wt-t2/src/Core.kt"
b=$(runs); out="$(run_gate "$TMP/wt-t2")"; rc=$?
check "3. cây khác: chạy suite" 0 1 no "$b" "$rc" "$out"
rm_wt wt-t2

# 4. Mục store quá tuổi (tested_at cũ hơn DEVKIT_GATE_CACHE_MAX_S) → chạy suite.
wipe
add_wt wt-b2
out="$(run_gate "$TMP/wt-b2" --no-cache)"; rm_wt wt-b2
[ -n "$(store_file)" ] || fail "4. tiền đề: builder không ghi mục store (ca tuổi vô nghĩa)"
add_wt wt-q2
b=$(runs); out="$(DEVKIT_GATE_CACHE_MAX_S=0 run_gate "$TMP/wt-q2")"; rc=$?
check "4. mục store quá tuổi: chạy suite" 0 1 no "$b" "$rc" "$out"
rm_wt wt-q2

# 5. Mục store không đáng tin: exit 2, carried_from, ma trận khác, fingerprint trong file khác tên file → chạy suite.
for kind in exit2 carried matrix fpname; do
  wipe
  add_wt wt-b5-$kind
  out="$(run_gate "$TMP/wt-b5-$kind" --no-cache)"; rm_wt wt-b5-$kind
  f="$(store_file)"
  python3 -c 'import json,sys; p,k=sys.argv[1:3]; r=json.load(open(p))
if k == "exit2": r.update({"exit": 2, "untested": []})
elif k == "carried": r["carried_from"] = r["project"]
elif k == "matrix": r["matrix_sha"] = "0" * 64
else: r["fingerprint"] = "0" * 24
json.dump(r, open(p, "w"))' "$f" "$kind" || fail "5. setup $kind"
  add_wt wt-q5-$kind
  b=$(runs); out="$(run_gate "$TMP/wt-q5-$kind")"; rc=$?
  check "5. mục store $kind: không mượn, chạy suite" 0 1 no "$b" "$rc" "$out"
  rm_wt wt-q5-$kind
done

# 6. Một lượt FAIL trên đúng cây đó xoá mục store (cùng khoá fp) → worktree sau không mượn PASS cũ, chạy suite.
wipe
add_wt wt-b6
out="$(run_gate "$TMP/wt-b6" --no-cache)"; rm_wt wt-b6
[ -n "$(store_file)" ] || fail "6. tiền đề: không có mục store"
add_wt wt-f6
touch "$TMP/wt-f6/.hong"
b=$(runs); out="$(FLAKY_RETRY=0 run_gate "$TMP/wt-f6" --no-cache)"; rc=$?
check "6. tiền đề: lượt FAIL thật trên cây đó" 1 1 no "$b" "$rc" "$out"
[ -z "$(store_file)" ] && echo "✔ 6. lượt FAIL xoá mục store của cây" || fail "6. mục store còn lại sau lượt FAIL"
rm_wt wt-f6
add_wt wt-q6
b=$(runs); out="$(run_gate "$TMP/wt-q6")"; rc=$?
check "6. sau FAIL không còn PASS để mượn: chạy suite" 0 1 no "$b" "$rc" "$out"
rm_wt wt-q6

# 7. Dây chuyền không sống sót sau FAIL (review 22/10, P1): wt-b PASS thật; wt-c mượn của nó (ghi biên nhận + làm mới mục store); wt-b FAIL
#    trên cùng cây (xoá mục store); wt-c chạy --full lại bằng chính biên nhận của nó (exit 0, không chạy suite) — lượt đó KHÔNG được tạo lại
#    mục store; worktree mới không có gì để mượn: chạy suite.
wipe
add_wt wt-b7; add_wt wt-c7
out="$(run_gate "$TMP/wt-b7" --no-cache)"
b=$(runs); out="$(run_gate "$TMP/wt-c7")"; rc=$?
check "7. tiền đề: wt-c mượn PASS của wt-b (biên nhận anh em)" 0 0 no "$b" "$rc" "$out"
touch "$TMP/wt-b7/.hong"
b=$(runs); out="$(FLAKY_RETRY=0 run_gate "$TMP/wt-b7" --no-cache)"; rc=$?
check "7. tiền đề: wt-b FAIL thật trên cùng cây" 1 1 no "$b" "$rc" "$out"
b=$(runs); out="$(run_gate "$TMP/wt-c7")"; rc=$?
check "7. tiền đề: wt-c dùng lại biên nhận của chính nó" 0 0 no "$b" "$rc" "$out"
[ -z "$(store_file)" ] && echo "✔ 7. lượt dùng lại của wt-c không tạo lại mục store sau FAIL" || fail "7. mục store sống lại sau FAIL"
rm_wt wt-b7; rm_wt wt-c7
add_wt wt-q7
b=$(runs); out="$(run_gate "$TMP/wt-q7")"; rc=$?
check "7. worktree mới sau FAIL: không mượn được, chạy suite" 0 1 no "$b" "$rc" "$out"
rm_wt wt-q7

# 8. FAIL ở lượt --full BỊ HOÃN vì phiên khác đang chạy (lệnh của lane QA: không --force-full): lượt đó không qua write_full_pass_receipt, nên mục
#    store của cây chỉ bị xoá bởi nhánh "FAIL xoá mục store" cạnh drop_budget_record (review 22/10, P2; mutant bỏ nhánh đó → ca này ĐỎ).
wipe
add_wt wt-b8
out="$(run_gate "$TMP/wt-b8" --no-cache)"; rm_wt wt-b8
[ -n "$(store_file)" ] || fail "8. tiền đề: không có mục store"
add_wt wt-f8
touch "$TMP/wt-f8/.hong"
python3 "$DEVKIT_DIR/bin/session_lock.py" --register --session S2 "$TMP/wt-f8" >/dev/null 2>&1 || fail "8. setup: không đăng ký được phiên S2"
b=$(runs); out="$(cd "$TMP/wt-f8" && env -u CI FLAKY_RETRY=0 CLAUDE_PROJECT_DIR="$TMP/wt-f8" python3 "$GATE" --matrix "$TMP/wt-f8/matrix.json" --run-tests --full --session S1 --diff HEAD~1 --no-cache 2>&1)"; rc=$?
printf '%s\n' "$out" | grep -q "hoãn --full" && echo "✔ 8. tiền đề: --full bị hoãn vì phiên khác" || fail "8. tiền đề: --full không bị hoãn (không đi qua nhánh cần test)"
check "8. tiền đề: lượt bị hoãn FAIL thật" 1 1 no "$b" "$rc" "$out"
[ -z "$(store_file)" ] && echo "✔ 8. FAIL ở lượt --full bị hoãn xoá mục store của cây" || fail "8. mục store còn lại sau FAIL của lượt bị hoãn"
python3 "$DEVKIT_DIR/bin/session_lock.py" --unregister --session S2 "$TMP/wt-f8" >/dev/null 2>&1   # S2 không được tính là phiên sống ở ca sau
rm_wt wt-f8

# 9. Chỉ lượt --full cưỡng bức trong git dir CHƯA từng chạy gate đọc store (header): lượt không --full (Stop-hook) và worktree đã từng chạy
#    không mượn; mục store là symlink cũng không.
wipe
add_wt wt-b9
out="$(run_gate "$TMP/wt-b9" --no-cache)"; rm_wt wt-b9
[ -n "$(store_file)" ] || fail "9. tiền đề: không có mục store"
add_wt wt-p9
b=$(runs); out="$( cd "$TMP/wt-p9" && env -u CI CLAUDE_PROJECT_DIR="$TMP/wt-p9" python3 "$GATE" --matrix "$TMP/wt-p9/matrix.json" --run-tests --diff HEAD~1 2>&1 )"; rc=$?
check "9. lượt không --full (Stop-hook): không đọc store, chạy suite" 0 1 no "$b" "$rc" "$out"
# wt-p9 đã từng chạy gate (run-log có dòng của nó). Bỏ biên nhận riêng của nó, giữ run-log: chỉ còn guard `_ever_gated` chặn việc đọc store.
rm -f "$(git -C "$TMP/wt-p9" rev-parse --absolute-git-dir)/postfix-gate/full_pass.json"
b=$(runs); out="$(run_gate "$TMP/wt-p9")"; rc=$?
check "9. worktree đã từng chạy gate, không còn biên nhận riêng: --full không mượn từ store, chạy suite" 0 1 no "$b" "$rc" "$out"
rm_wt wt-p9
f="$(store_file)"; mv "$f" "$TMP/real-entry.json"; ln -s "$TMP/real-entry.json" "$f"
add_wt wt-s9
b=$(runs); out="$(run_gate "$TMP/wt-s9")"; rc=$?
check "9. mục store là symlink: bỏ qua, chạy suite" 0 1 no "$b" "$rc" "$out"
rm_wt wt-s9

# 10. Lượt --full chỉ trúng khoá nội dung (suite cache), không chép PASS từ biên nhận nào, vẫn TẠO mục store cho cây mới (review 22/10, P2: refresh_only
#     bật quá rộng làm builder không để lại mục nào ở repo bật cache). Repo riêng, cache bật.
unset DEVKIT_SUITE_CACHE; export DEVKIT_SENTINEL_MAX_S=999999999
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
R10="$TMP/repo10"; mkdir -p "$R10/src" && cd "$R10" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
echo 'a = 1' > src/a.py; echo 'b = 1' > src/b.py
python3 - "$R10/matrix.json" "$TMP" <<'PY'
import json, sys
path, tmp = sys.argv[1:]
c = lambda n: f"echo run >> '{tmp}/count10.{n}'"
json.dump({"project": "t", "rules": [
  {"component": "A", "watch_files": ["src/a.py"], "mandatory_regression_tests": [{"id": "REG-1", "name": "a", "command": c(1)}]},
  {"component": "B", "watch_files": ["src/b.py"], "mandatory_regression_tests": [{"id": "REG-2", "name": "b", "command": c(2)}]}]}, open(path, "w"))
PY
git add -A && git commit -qm init; echo 'a = 2' > src/a.py; git commit -qam change
STORE10="$(git rev-parse --path-format=absolute --git-common-dir)/postfix-gate/tree_receipts"
n10() { [ -f "$TMP/count10.$1" ] && wc -l < "$TMP/count10.$1" | tr -d ' ' || echo 0; }
gate10() { local d="$1"; ( cd "$d" && CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --matrix "$d/matrix.json" --run-tests --full --force-full --diff HEAD~1 --no-checklist 2>&1 ); }
out="$(gate10 "$R10")"
git -C "$R10" worktree add -q --detach "$TMP/wt-x10" HEAD || { echo "✖ setup: worktree add wt-x10"; exit 1; }; echo 'a = 3' > "$TMP/wt-x10/src/a.py"
b1=$(n10 1); b2=$(n10 2); out="$(gate10 "$TMP/wt-x10")"; rc=$?
FP10="$(python3 "$DEVKIT_DIR/bin/tree_fp.py" "$TMP/wt-x10")"
[ "$rc" = 0 ] && [ "$(( $(n10 1) - b1 ))" = 1 ] && [ "$(( $(n10 2) - b2 ))" = 0 ] && echo "✔ 10. tiền đề: REG-1 chạy (cây mới), REG-2 trúng khoá nội dung" \
  || { fail "10. tiền đề: exit $rc, REG-1 +$(( $(n10 1) - b1 )), REG-2 +$(( $(n10 2) - b2 ))"; printf '%s\n' "$out" | tail -8; }
[ -f "$STORE10/$FP10.json" ] && echo "✔ 10. lượt chỉ trúng khoá nội dung tạo mục store của cây mới" || fail "10. không có mục store cho cây mới (lượt trúng khoá nội dung)"

[ "$FAILS" = 0 ] && echo "PASS: test_gate_tree_store_reuse" || { echo "FAIL: $FAILS ca đỏ"; exit 1; }
