#!/usr/bin/env bash
# Test hồi quy: bin/post-fix-gate.py dùng lại PASS đầy đủ của một worktree ANH EM (cùng repo) khi nội dung trùng byte.
# 17/10 (agent-workbench): merge gate super-board chạy gate --full --force-full trong một scratch `git worktree add` (git dir
# mới, không có biên nhận) nên chạy lại mọi suite dù worktree của agent vừa PASS đúng cây đó: 19 lần/ngày, 154 phút, 0 lần dùng lại.
# Biên nhận anh em chỉ được dùng khi qua ĐÚNG các kiểm tra của cached_full_pass (nội dung, tuổi, ma trận, trạng thái cục bộ), cộng:
# exit 0, không carried_from, và runs.jsonl có dòng của đúng lần chạy đó với verdict PASS (suite thật sự chạy, không phải REUSED).
# Chỉ lượt --full cưỡng bức trong git dir CHƯA có biên nhận của chính nó mới tìm anh em; chỉ file thường (không symlink).
# Mỗi ca dùng worktree mới (git dir mới); số lần suite chạy đo bằng hiệu trước/sau, không phải số tuyệt đối.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_GATE_CACHE_MAX_S DEVKIT_GATE_CACHE   # môi trường của người chạy không được đổi kết quả (OCR 17/10)
# Cache theo khoá nội dung (bin/suite_cache.py, P2 20/10) nằm ở git common dir, dùng chung mọi worktree: nó cho worktree này PASS mà
# anh em vừa chạy thật trên cùng cây, nên các ca "không mượn biên nhận anh em" không còn chạy suite. DEVKIT_SUITE_CACHE=0 giữ test
# này về biên nhận anh em; việc dùng chung theo khoá là tests/gates/test_gate_suite_cache.sh ca 1b.
export DEVKIT_SUITE_CACHE=0

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
COUNT="$TMP/runs.txt"
COUNT2="$TMP/runs2.txt"   # REG-2: suite thứ hai, chỉ ca 18 đếm nó
SIB_MSG="biên nhận của worktree anh em"   # DEVKIT_LANG=vi (clean_git_env.sh)

R="$TMP/repo"
mkdir -p "$R/src" && cd "$R" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
cat > matrix.json <<JSON
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"echo run >> '$COUNT'; test ! -f .hong"},
                               {"id":"REG-2","name":"core2","command":"echo run >> '$COUNT2'"}]}]}
JSON
printf '.hong\n' > .gitignore   # .hong (bị ignore, ngoài fingerprint): suite FAIL ở đúng thư mục có nó
git add -A && git commit -qm init
echo "fun ok() = 2" > src/Core.kt
git commit -qam change

# gate ở thư mục $1, như merge gate gọi: --full --force-full --diff <base>
run_gate() { local d="$1"; shift; ( cd "$d" && CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --matrix "$d/matrix.json" --run-tests --full --force-full --diff HEAD~1 "$@" 2>&1 ); }
# gate kiểu Stop hook: không --full, không --force-full (không CI nào ép full)
run_plain() { local d="$1"; shift; ( cd "$d" && env -u CI CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --matrix "$d/matrix.json" --run-tests --diff HEAD~1 "$@" 2>&1 ); }
runs() { [ -f "$COUNT" ] && wc -l < "$COUNT" | tr -d ' ' || echo 0; }
add_wt() { git -C "$R" worktree add -q --detach "$TMP/$1" HEAD || { echo "✖ setup: worktree add $1"; exit 1; }; }
receipt_of() { echo "$(git -C "$1" rev-parse --absolute-git-dir)/postfix-gate/full_pass.json"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
check() {   # check <tên> <exit mong đợi> <số lần suite chạy THÊM mong đợi> <nhắc biên nhận anh em: yes|no> <runs trước> <exit thật> <output>
  local delta=$(( $(runs) - $5 )) sib=no
  printf '%s\n' "$7" | grep -qF "$SIB_MSG" && sib=yes
  if [ "$6" = "$2" ] && [ "$delta" = "$3" ] && [ "$sib" = "$4" ]; then echo "✔ $1"
  else echo "✖ $1 (exit $6, mong $2; suite chạy thêm $delta lần, mong $3; nhắc anh em $sib, mong $4)"; printf '%s\n' "$7" | tail -12; FAILS=$((FAILS + 1)); fi
}
# xoá mọi biên nhận full-pass của repo (main checkout + mọi worktree): ca sau chỉ còn đúng biên nhận nó tự đặt
# + store theo cây (#247, tests/gates/test_gate_tree_store_reuse.sh): nó giữ PASS thật của lượt setup nên ca "không mượn được" sẽ mượn từ đó
wipe_receipts() { rm -f "$COMMON/postfix-gate/full_pass.json" "$COMMON"/worktrees/*/postfix-gate/full_pass.json "$COMMON"/postfix-gate/tree_receipts/*.json; }

b=$(runs); out="$(run_gate "$R")"; rc=$?
check "setup: --full ở main checkout PASS, suite chạy" 0 1 no "$b" "$rc" "$out"
COMMON="$(git -C "$R" rev-parse --path-format=absolute --git-common-dir)"
MAIN_RECEIPT="$COMMON/postfix-gate/full_pass.json"
LEND="$TMP/lendable.json"   # bản chép biên nhận cho mượn được (lần chạy PASS thật, dòng run-log "repo" PASS): dùng cho ca 7, 8, đối chứng
cp "$MAIN_RECEIPT" "$LEND" || { echo "✖ setup: main checkout không ghi biên nhận"; exit 1; }

# 1. Worktree mới (git dir mới, chưa có biên nhận), --full cưỡng bức, đúng nội dung: dùng lại PASS của main checkout, suite không chạy.
add_wt wt-b
b=$(runs); out="$(run_gate "$TMP/wt-b")"; rc=$?
check "1. worktree anh em cùng nội dung dùng lại PASS của main checkout" 0 0 yes "$b" "$rc" "$out"
printf '%s\n' "$out" | grep -qF "($SIB_MSG: $MAIN_RECEIPT)" && echo "✔ 1. output nêu đúng đường dẫn biên nhận của main checkout" \
  || fail "1. output không nêu đường dẫn biên nhận của main checkout ($MAIN_RECEIPT)"

# 2. Không có dây chuyền: biên nhận của main checkout mất; biên nhận còn lại duy nhất là của wt-b, ghi bởi một lượt DÙNG LẠI (run-log
#    REUSED, không phải PASS) → không được cho mượn tiếp → worktree mới phải chạy suite.
[ -f "$(receipt_of "$TMP/wt-b")" ] && echo "✔ 2. tiền đề: lượt dùng lại ở wt-b ghi biên nhận của chính nó" \
  || fail "2. tiền đề: wt-b không có biên nhận (ca dây chuyền vô nghĩa)"
grep -q '"project":"wt-b".*"verdict":"REUSED"' "$COMMON/postfix-gate/runs.jsonl" && echo "✔ 2. tiền đề: run-log ghi lượt của wt-b là REUSED" \
  || fail "2. tiền đề: run-log không có dòng REUSED của wt-b"
rm -f "$MAIN_RECEIPT" "$COMMON"/postfix-gate/tree_receipts/*.json   # store theo cây (#247) cũng giữ PASS thật của main checkout
add_wt wt-c
b=$(runs); out="$(run_gate "$TMP/wt-c")"; rc=$?
check "2. biên nhận anh em từ lượt REUSED không được cho mượn: chạy suite" 0 1 no "$b" "$rc" "$out"

# 9. Mỗi lượt chạy ghi biên nhận của chính git dir (push_gate/proof_gate chỉ đọc biên nhận của chính nó, tree_fp.receipt_path).
[ -f "$(receipt_of "$TMP/wt-c")" ] && echo "✔ 9. lần chạy ghi biên nhận của chính git dir" || fail "9. lần chạy không ghi biên nhận của chính git dir"

# 10. Biên nhận của CHÍNH git dir không qua các luật riêng của anh em (exit 0, dòng run-log PASS): wt-b chạy lại đúng nội dung đó dùng
#     lại biên nhận của nó dù run-log ghi lượt đó là REUSED (review 17/10: `sibling` tính trước khi path bị gán biên nhận của mình).
b=$(runs); out="$(run_gate "$TMP/wt-b")"; rc=$?
check "10. biên nhận của chính git dir (từ lượt REUSED) vẫn được dùng lại như cũ" 0 0 no "$b" "$rc" "$out"

# 3. Nội dung khác (một file sửa) → không khớp biên nhận nào (wt-c vừa PASS thật, cho mượn được) → chạy suite.
add_wt wt-d
echo "fun ok() = 3" > "$TMP/wt-d/src/Core.kt"
b=$(runs); out="$(run_gate "$TMP/wt-d")"; rc=$?
check "3. nội dung khác: chạy lại suite" 0 1 no "$b" "$rc" "$out"

# 4. Biên nhận anh em quá tuổi (DEVKIT_GATE_CACHE_MAX_S=0) → chạy suite.
add_wt wt-e
b=$(runs); out="$(DEVKIT_GATE_CACHE_MAX_S=0 run_gate "$TMP/wt-e")"; rc=$?
check "4. biên nhận anh em quá tuổi: chạy lại suite" 0 1 no "$b" "$rc" "$out"

# 5. Lượt KHÔNG cưỡng bức (kiểu Stop hook: --run-tests, không --full/--force-full) ở worktree mới, có biên nhận anh em cho mượn được
#    (wt-c, wt-e): không tìm anh em — chọn suite theo thay đổi (REG-1 canh src/Core.kt, --diff HEAD~1 đổi nó) và chạy như cũ.
add_wt wt-f
b=$(runs); out="$(run_plain "$TMP/wt-f")"; rc=$?
check "5. lượt không cưỡng bức không dùng biên nhận anh em" 0 1 no "$b" "$rc" "$out"

# 6. Git dir đã có biên nhận của chính nó (không khớp nội dung) → không tìm anh em → chạy suite. wt-g chưa từng chạy gate (không dòng
#    run-log: _ever_gated không chặn) và có biên nhận anh em cho mượn được — chỉ chốt "đã có biên nhận riêng" giữ nó lại (OCR 17/10).
wipe_receipts; cp "$LEND" "$MAIN_RECEIPT"
add_wt wt-g
mkdir -p "$(dirname "$(receipt_of "$TMP/wt-g")")"
python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); r["fingerprint"]="khong-khop"; json.dump(r, open(sys.argv[2], "w"))' \
  "$LEND" "$(receipt_of "$TMP/wt-g")" || fail "6. setup: không ghi được biên nhận riêng của wt-g"
b=$(runs); out="$(run_gate "$TMP/wt-g")"; rc=$?
check "6. có biên nhận của chính git dir: không tìm anh em, chạy suite" 0 1 no "$b" "$rc" "$out"

# 7. Biên nhận giả: bản chép biên nhận cho mượn được, đổi "project" sang tên không có dòng run-log nào → không cho mượn.
#    Không còn biên nhận nào khác trong repo.
wipe_receipts
python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); r["project"]="/khong-ton-tai/khong-co-dong-log"; json.dump(r, open(sys.argv[2], "w"))' \
  "$LEND" "$MAIN_RECEIPT" || fail "7. setup: không ghi được biên nhận giả"
add_wt wt-h
b=$(runs); out="$(run_gate "$TMP/wt-h")"; rc=$?
check "7. biên nhận anh em không có dòng PASS trong run-log: chạy suite" 0 1 no "$b" "$rc" "$out"

# 8. Biên nhận anh em là symlink trỏ tới một biên nhận cho mượn được → bỏ qua (chỉ file thường).
wipe_receipts
ln -s "$LEND" "$MAIN_RECEIPT" || fail "8. setup: không tạo được symlink"
add_wt wt-i
b=$(runs); out="$(run_gate "$TMP/wt-i")"; rc=$?
check "8. biên nhận anh em là symlink: bỏ qua, chạy suite" 0 1 no "$b" "$rc" "$out"

# Đối chứng cho 7 và 8: đúng bản chép đó, là file thường, đúng "project" → được cho mượn (7, 8 đỏ chỉ vì run-log / symlink).
wipe_receipts
cp "$LEND" "$MAIN_RECEIPT"
add_wt wt-j
b=$(runs); out="$(run_gate "$TMP/wt-j")"; rc=$?
check "đối chứng: bản chép là file thường, có dòng PASS → dùng lại" 0 0 yes "$b" "$rc" "$out"

# 11. Thư mục ĐÃ TỪNG chạy gate không mượn (review 17/10, P1): mọi lượt exit ≠ 0 xoá biên nhận của chính nó, nên "không có biên
#     nhận" không có nghĩa "chưa từng chạy". wt-k FAIL thật (suite hỏng ở đúng thư mục này), rồi --full lại khi suite VẪN hỏng: phải chạy
#     suite và FAIL, không lấy PASS của main checkout. Ở scratch của merge gate (mktemp -d, tên mới) không có dòng run-log nào.
wipe_receipts; cp "$LEND" "$MAIN_RECEIPT"
add_wt wt-k
touch "$TMP/wt-k/.hong"
b=$(runs); out="$(FLAKY_RETRY=0 run_gate "$TMP/wt-k" --no-cache)"; rc=$?   # FLAKY_RETRY=0: số lần chạy không phụ thuộc chính sách chạy lại
check "11. tiền đề: wt-k FAIL thật (suite hỏng ở thư mục này)" 1 1 no "$b" "$rc" "$out"
[ -f "$(receipt_of "$TMP/wt-k")" ] && fail "11. tiền đề: lượt FAIL không xoá biên nhận của wt-k"
b=$(runs); out="$(FLAKY_RETRY=0 run_gate "$TMP/wt-k")"; rc=$?
check "11. thư mục đã từng chạy gate (FAIL) không mượn PASS của anh em: chạy suite, FAIL" 1 1 no "$b" "$rc" "$out"

# 12. Biên nhận anh em exit 2 (UNVERIFIED) hoặc là bản chép `worktree finish` (carried_from) → không cho mượn.
for kind in exit2 carried; do
  wipe_receipts
  python3 -c 'import json,sys; r=json.load(open(sys.argv[1]))
if sys.argv[3] == "exit2": r.update({"exit": 2, "untested": []})
else: r["carried_from"] = r["project"]
json.dump(r, open(sys.argv[2], "w"))' "$LEND" "$MAIN_RECEIPT" "$kind" || fail "12. setup $kind"
  add_wt "wt-m-$kind"
  b=$(runs); out="$(run_gate "$TMP/wt-m-$kind")"; rc=$?
  check "12. biên nhận anh em $kind: không cho mượn, chạy suite" 0 1 no "$b" "$rc" "$out"
done

# 13. Biên nhận có tested_at cũ hơn time (lượt đã dùng lại, một phần hay toàn bộ, giữ tested_at của biên nhận gốc) → không cho mượn.
#     Giờ ghi đặt ngay trước dòng PASS của setup (luật run-log qua được), tested_at sớm hơn 60 s: chỉ luật tested_at chặn.
wipe_receipts
python3 -c 'import json,sys
recs=[json.loads(l) for l in open(sys.argv[3]) if l.strip()]
e=[x["epoch"] for x in recs if x.get("project")=="repo" and x.get("verdict")=="PASS"][0]
r=json.load(open(sys.argv[1])); r["time"]=e-0.5; r["tested_at"]=e-60.5; json.dump(r, open(sys.argv[2], "w"))' \
  "$LEND" "$MAIN_RECEIPT" "$COMMON/postfix-gate/runs.jsonl" || fail "13. setup"
add_wt wt-n
b=$(runs); out="$(run_gate "$TMP/wt-n")"; rc=$?
check "13. biên nhận time − tested_at = 60 s (lượt dùng lại): không cho mượn, chạy suite" 0 1 no "$b" "$rc" "$out"

# 14. Dòng run-log ĐẦU TIÊN của project sau thời điểm ghi biên nhận phải là PASS: main checkout chạy lại (dùng lại biên nhận của nó →
#     dòng "repo" REUSED); một biên nhận đặt giờ ngay trước dòng đó không được bảo lãnh bởi dòng PASS cũ hơn của setup.
wipe_receipts; cp "$LEND" "$MAIN_RECEIPT"
b=$(runs); out="$(run_gate "$R")"; rc=$?
check "14. tiền đề: main checkout dùng lại biên nhận của nó (dòng run-log REUSED)" 0 0 no "$b" "$rc" "$out"
b=$(runs); out="$(run_gate "$R" --no-cache)"; rc=$?   # rồi một dòng PASS "repo" SAU dòng REUSED: chỉ luật "dòng đầu tiên" chặn
check "14. tiền đề: main checkout chạy lại thật (dòng run-log PASS sau REUSED)" 0 1 no "$b" "$rc" "$out"
python3 -c 'import json,sys
recs=[json.loads(l) for l in open(sys.argv[3]) if l.strip()]
e=[x["epoch"] for x in recs if x.get("project")=="repo" and x.get("verdict")=="REUSED"][-1]
r=json.load(open(sys.argv[1])); r["time"]=r["tested_at"]=e-0.5; json.dump(r, open(sys.argv[2], "w"))' \
  "$LEND" "$MAIN_RECEIPT" "$COMMON/postfix-gate/runs.jsonl" || fail "14. setup"
rm -f "$COMMON"/postfix-gate/tree_receipts/*.json   # #247: store theo cây giữ PASS thật của main checkout; ca này chỉ xét luật run-log của biên nhận anh em
add_wt wt-o
b=$(runs); out="$(run_gate "$TMP/wt-o")"; rc=$?
check "14. dòng run-log đầu tiên sau biên nhận là REUSED: không cho mượn, chạy suite" 0 1 no "$b" "$rc" "$out"

# 15. Mượn từ biên nhận của một WORKTREE (đúng kịch bản merge gate: worktree của agent PASS, scratch mới mượn), không phải main checkout.
wipe_receipts
add_wt wt-p
b=$(runs); out="$(run_gate "$TMP/wt-p" --no-cache)"; rc=$?
check "15. tiền đề: wt-p PASS thật" 0 1 no "$b" "$rc" "$out"
add_wt wt-q
b=$(runs); out="$(run_gate "$TMP/wt-q")"; rc=$?
check "15. worktree mới mượn PASS của worktree anh em" 0 0 yes "$b" "$rc" "$out"
printf '%s\n' "$out" | grep -qF "($SIB_MSG: $COMMON/worktrees/wt-p/postfix-gate/full_pass.json)" \
  && echo "✔ 15. output nêu đúng biên nhận của wt-p" || fail "15. output không nêu biên nhận của wt-p"

# 16. Lượt bị kill / crash trước khi ghi dòng run-log (review 17/10, P3-b): thư mục có test_run.lock (gate tạo nó trước khi chạy suite)
#     mà không có dòng log nào → vẫn tính là đã từng chạy gate, không mượn.
wipe_receipts; cp "$LEND" "$MAIN_RECEIPT"
add_wt wt-r
mkdir -p "$TMP/wt-r/.claude/audit-gate" && : > "$TMP/wt-r/.claude/audit-gate/test_run.lock"
b=$(runs); out="$(run_gate "$TMP/wt-r")"; rc=$?
check "16. thư mục có test_run.lock (lượt trước bị kill): không mượn, chạy suite" 0 1 no "$b" "$rc" "$out"

# 18. Biên nhận anh em THIẾU một suite mà lượt này phải chạy (17/10, merge gate #56: scratch không có overlay checklist của worktree nên
#     chạy thêm suite STALE REG-DK-COST-01, biên nhận không có nó, cả 4 suite nặng chạy lại): dùng lại suite biên nhận đã PASS, chạy thật
#     suite thiếu.
runs2() { [ -f "$COUNT2" ] && wc -l < "$COUNT2" | tr -d ' ' || echo 0; }
wipe_receipts
python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); r["tests"]=[t for t in r["tests"] if t["id"]!="REG-2"]; json.dump(r, open(sys.argv[2], "w"))' \
  "$LEND" "$MAIN_RECEIPT" || fail "18. setup"
add_wt wt-t
b=$(runs); b2=$(runs2); out="$(run_gate "$TMP/wt-t")"; rc=$?
check "18. biên nhận anh em thiếu REG-2: dùng lại REG-1 (không chạy)" 0 0 yes "$b" "$rc" "$out"
[ "$(( $(runs2) - b2 ))" = 1 ] && echo "✔ 18. suite thiếu (REG-2) chạy thật" || fail "18. suite thiếu REG-2 không chạy đúng 1 lần ($(( $(runs2) - b2 )))"
printf '%s\n' "$out" | grep -qF "chạy thật 1 suite" && echo "✔ 18. output nói rõ chỉ dùng lại một phần" || fail "18. output không nói suite nào chạy thật"

# 18b. Biên nhận của lượt mượn MỘT PHẦN (run-log PASS vì REG-2 chạy, nhưng reused_full_pass) không cho mượn tiếp (review + OCR 17/10):
#      REG-1 trong đó là PASS mượn. tested_at đặt = time − 1 s (lượt mượn nhanh, review đo 3,77 s): luật tested_at qua được, chỉ luật
#      reused_full_pass của dòng run-log chặn.
python3 -c 'import json,sys; p=sys.argv[1]; r=json.load(open(p)); r["tested_at"]=r["time"]-1; json.dump(r, open(p, "w"))' "$(receipt_of "$TMP/wt-t")" \
  || fail "18b. setup: không sửa được tested_at của wt-t"
rm -f "$MAIN_RECEIPT" "$COMMON"/postfix-gate/tree_receipts/*.json   # chỉ còn biên nhận của wt-t (store theo cây #247 giữ bản chép dây chuyền của nó, hợp lệ: tests/gates/test_gate_tree_store_reuse.sh ca 2)
add_wt wt-u
b=$(runs); b2=$(runs2); out="$(run_gate "$TMP/wt-u")"; rc=$?
check "18b. biên nhận của lượt mượn một phần không cho mượn tiếp: REG-1 chạy" 0 1 no "$b" "$rc" "$out"
[ "$(( $(runs2) - b2 ))" = 1 ] && echo "✔ 18b. REG-2 chạy" || fail "18b. REG-2 không chạy đúng 1 lần"

# 18c. Suite UNTESTED trong biên nhận anh em exit 0 (suite STALE không chạy được trên máy đó: kết luận không tính nó — GeelyEx2 REG-WEB-01,
#      18/10 #64: mọi phép so khớp mà REG-CAR-01 vẫn chạy lại 120 s) → chạy lại đúng suite đó, như danh sách "untested" của biên nhận exit 4;
#      suite PASS vẫn dùng lại.
wipe_receipts
python3 -c 'import json,sys; r=json.load(open(sys.argv[1]))
for t in r["tests"]:
    if t["id"] == "REG-2": t["status"] = "UNTESTED"
json.dump(r, open(sys.argv[2], "w"))' "$LEND" "$MAIN_RECEIPT" || fail "18c. setup"
add_wt wt-v
b=$(runs); b2=$(runs2); out="$(run_gate "$TMP/wt-v")"; rc=$?
check "18c. suite UNTESTED trong biên nhận anh em: REG-1 dùng lại" 0 0 yes "$b" "$rc" "$out"
[ "$(( $(runs2) - b2 ))" = 1 ] && echo "✔ 18c. REG-2 (UNTESTED) chạy lại" || fail "18c. REG-2 không chạy đúng 1 lần"

# 18d. Suite có trong biên nhận mà ở trạng thái khác PASS/UNTESTED (FAIL) → huỷ cả lần dùng lại, mọi suite chạy (như trước).
wipe_receipts
python3 -c 'import json,sys; r=json.load(open(sys.argv[1]))
for t in r["tests"]:
    if t["id"] == "REG-2": t["status"] = "FAIL"
json.dump(r, open(sys.argv[2], "w"))' "$LEND" "$MAIN_RECEIPT" || fail "18d. setup"
add_wt wt-w
b=$(runs); b2=$(runs2); out="$(run_gate "$TMP/wt-w")"; rc=$?
check "18d. suite FAIL trong biên nhận anh em: REG-1 chạy" 0 1 no "$b" "$rc" "$out"
[ "$(( $(runs2) - b2 ))" = 1 ] && echo "✔ 18d. REG-2 chạy" || fail "18d. REG-2 không chạy đúng 1 lần"

# 17. Một dòng runs.jsonl lồng quá sâu (RecursionError khi json.loads, review 17/10 P2) không được làm gate crash: dòng đó bị bỏ qua.
#     Để CUỐI: file run-log dùng chung cho mọi ca sau nó.
wipe_receipts; cp "$LEND" "$MAIN_RECEIPT"
python3 -c 'import sys; open(sys.argv[1], "a").write("[" * 200000 + "]" * 200000 + "\n")' "$COMMON/postfix-gate/runs.jsonl"
add_wt wt-s
b=$(runs); out="$(run_gate "$TMP/wt-s")"; rc=$?
check "17. dòng run-log lồng quá sâu: gate không crash, vẫn mượn PASS" 0 0 yes "$b" "$rc" "$out"

# 19-20. Trạng thái cục bộ (local_state_sha) của scratch phải bằng của worktree khi cây trùng (18/10, đo ở GeelyEx2 #62 và Neighbours #48:
#        tree_fp trùng, local_sha khác, suite nặng chạy lại). Repo riêng R2: suite của nó GHI LẠI một build input (như task Test của
#        CarConnect build lại launcher-whitelist.apk, khai trong red_proof.json "copy"), mỗi lượt ra byte khác.
R2="$TMP/repo2"
mkdir -p "$R2/src" "$R2/.agents/local" && cd "$R2" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
cat > matrix.json <<JSON
{"project":"t2","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-G","name":"gen","command":"echo run >> '$COUNT'; [ -f gen/created.bin ] || echo once > gen/created.bin; [ -n \"\${GEN_UPTODATE:-}\" ] || head -c 32 /dev/urandom > gen/overlay.bin"}]}]}
JSON
printf '{"copy": ["gen/**"]}\n' > .agents/local/red_proof.json
printf 'gen/\nLibrary/\nlocal.properties\n' > .gitignore
git add -A && git commit -qm init
echo "fun ok() = 2" > src/Core.kt
git commit -qam change
add_wt2() {   # như worktree add / scratch-config: build input chép từ main checkout (nội dung "main")
  git -C "$R2" worktree add -q --detach "$TMP/$1" HEAD || { echo "✖ setup: worktree add $1"; exit 1; }
  mkdir -p "$TMP/$1/gen" && printf main > "$TMP/$1/gen/overlay.bin" && printf keep > "$TMP/$1/gen/keep.bin"
}
gate2() { local d="$1"; shift; ( cd "$d" && CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --matrix "$d/matrix.json" --run-tests --full --force-full --diff HEAD~1 "$@" 2>&1 ); }

# 19. Build input do chính suite ghi lại: worktree PASS thật (overlay.bin đổi trong lượt), scratch có bản chép từ main → vẫn mượn.
add_wt2 wt2-a
b=$(runs); out="$(gate2 "$TMP/wt2-a" --no-cache)"; rc=$?
check "19. tiền đề: wt2-a PASS thật, suite ghi lại gen/overlay.bin" 0 1 no "$b" "$rc" "$out"
add_wt2 wt2-b
b=$(runs); out="$(gate2 "$TMP/wt2-b")"; rc=$?
check "19. build input suite tự ghi lại không chặn việc mượn PASS của worktree anh em" 0 0 yes "$b" "$rc" "$out"

# 19b. Đối chứng: build input suite KHÔNG ghi lại mà khác nhau (gen/keep.bin) → không mượn, chạy suite.
add_wt2 wt2-c
printf other > "$TMP/wt2-c/gen/keep.bin"
b=$(runs); out="$(gate2 "$TMP/wt2-c")"; rc=$?
check "19b. build input khác mà suite không ghi lại: không mượn, chạy suite" 0 1 no "$b" "$rc" "$out"

# 22. local_regen sai kiểu trong biên nhận anh em → không đọc biên nhận, gate không crash. Biên nhận gốc là của wt2-a (ca 19: chính nó cho mượn
#     được, local_regen = [gen/overlay.bin]); một dict cùng khoá (lặp ra đúng tên đó) bị chặn chỉ bởi phép kiểm kiểu.
COMMON2="$(git -C "$R2" rev-parse --path-format=absolute --git-common-dir)"
WT2A_RECEIPT="$COMMON2/worktrees/wt2-a/postfix-gate/full_pass.json"
cp "$WT2A_RECEIPT" "$TMP/wt2a.json" || fail "22. setup: wt2-a không có biên nhận"
for bad in 5 '{"gen/overlay.bin": 1}'; do
  rm -f "$COMMON2"/worktrees/*/postfix-gate/full_pass.json "$COMMON2"/postfix-gate/tree_receipts/*.json   # chỉ còn biên nhận giả (kể cả store theo cây #247)
  python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); r["local_regen"]=json.loads(sys.argv[3]); json.dump(r, open(sys.argv[2], "w"))' \
    "$TMP/wt2a.json" "$WT2A_RECEIPT" "$bad" || fail "22. setup $bad"
  n=$(( ${n22:-0} + 1 )); n22=$n
  add_wt2 "wt2-x$n"
  b=$(runs); out="$(gate2 "$TMP/wt2-x$n")"; rc=$?
  check "22. local_regen=$bad: không mượn, chạy suite" 0 1 no "$b" "$rc" "$out"
done
rm -f "$COMMON2"/worktrees/*/postfix-gate/full_pass.json; cp "$TMP/wt2a.json" "$WT2A_RECEIPT"
add_wt2 wt2-y
b=$(runs); out="$(gate2 "$TMP/wt2-y")"; rc=$?
check "22. đối chứng: đúng biên nhận đó với local_regen gốc → mượn" 0 0 yes "$b" "$rc" "$out"

# 19c. Lượt sau mà build KHÔNG ghi lại file đó (Gradle up-to-date: GEN_UPTODATE) vẫn bỏ nó khỏi local_sha: GeelyEx2 #65 (18/10) — APK của
#      worktree còn là bản lượt trước đã ghi, scratch chép bản của main, local_regen của lượt này rỗng nên REG-CAR-01 chạy lại. File mà suite
#      từng ghi lại ở bất kỳ checkout nào của repo được nhớ ở git common dir.
GEN_JSON="$(git -C "$R2" rev-parse --path-format=absolute --git-common-dir)/postfix-gate/local_generated.json"
python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("gen/overlay.bin", 0) >= 2 else 1)' "$GEN_JSON" \
  && echo "✔ 19c. tiền đề: các lượt thật trước (19, 22) đã thấy suite ghi lại gen/overlay.bin ≥ 2 lần" || fail "19c. tiền đề: local_generated.json chưa đếm gen/overlay.bin ≥ 2"
add_wt2 wt2-g
printf 'built-by-an-earlier-run' > "$TMP/wt2-g/gen/overlay.bin"
b=$(runs); out="$(GEN_UPTODATE=1 gate2 "$TMP/wt2-g" --no-cache)"; rc=$?
check "19c. tiền đề: wt2-g PASS thật, lần này suite không ghi lại gen/overlay.bin" 0 1 no "$b" "$rc" "$out"
rm -f "$(git -C "$R2" rev-parse --path-format=absolute --git-common-dir)"/worktrees/wt2-[!g]*/postfix-gate/full_pass.json   # chỉ còn biên nhận của wt2-g
add_wt2 wt2-h
b=$(runs); out="$(gate2 "$TMP/wt2-h")"; rc=$?
check "19c. file suite từng ghi lại vẫn không so ở lượt build không ghi lại nó: mượn PASS" 0 0 yes "$b" "$rc" "$out"

# 19d. File chỉ MỘT lượt thật thấy bị ghi lại (người/tool sửa trong lúc suite chạy) chưa được tin: vẫn so — khác thì không mượn.
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["gen/keep.bin"]=1; json.dump(d, open(sys.argv[1], "w"))' "$GEN_JSON" || fail "19d. setup"
add_wt2 wt2-i
b=$(runs); out="$(GEN_UPTODATE=1 gate2 "$TMP/wt2-i" --no-cache)"; rc=$?
check "19d. tiền đề: wt2-i PASS thật" 0 1 no "$b" "$rc" "$out"
rm -f "$(git -C "$R2" rev-parse --path-format=absolute --git-common-dir)"/worktrees/wt2-[!i]*/postfix-gate/full_pass.json   # chỉ còn biên nhận của wt2-i
add_wt2 wt2-j
printf other > "$TMP/wt2-j/gen/keep.bin"
b=$(runs); out="$(gate2 "$TMP/wt2-j")"; rc=$?
check "19d. file mới thấy bị ghi lại 1 lần vẫn được so: khác thì không mượn" 0 1 no "$b" "$rc" "$out"

# 19e. File suite TẠO khi thiếu (khoá/prebuilt sinh một lần) không được nhớ là output dù nhiều lượt tạo nó (review 18/10, P2): lượt có sẵn file
#      đó (không tạo, không ghi lại) vẫn so nó — bản sửa tay khác thì không mượn.
add_wt2 wt2-k
printf once > "$TMP/wt2-k/gen/created.bin"
b=$(runs); out="$(GEN_UPTODATE=1 gate2 "$TMP/wt2-k" --no-cache)"; rc=$?
check "19e. tiền đề: wt2-k PASS thật, gen/created.bin có sẵn" 0 1 no "$b" "$rc" "$out"
rm -f "$(git -C "$R2" rev-parse --path-format=absolute --git-common-dir)"/worktrees/wt2-[!k]*/postfix-gate/full_pass.json   # chỉ còn biên nhận của wt2-k
add_wt2 wt2-l
printf hand-edited > "$TMP/wt2-l/gen/created.bin"
b=$(runs); out="$(gate2 "$TMP/wt2-l")"; rc=$?
check "19e. file suite chỉ tạo khi thiếu vẫn được so: khác thì không mượn" 0 1 no "$b" "$rc" "$out"

# 20. Config cục bộ nằm trong cache build (Unity Library/Bee/**/Gradle/local.properties, chỉ worktree có vì clone unity/Library) → vẫn mượn.
rm -f "$(git -C "$R2" rev-parse --path-format=absolute --git-common-dir)"/worktrees/*/postfix-gate/full_pass.json
add_wt2 wt2-d
mkdir -p "$TMP/wt2-d/Library/Bee/Gradle" && echo "sdk.dir=/x" > "$TMP/wt2-d/Library/Bee/Gradle/local.properties"
b=$(runs); out="$(gate2 "$TMP/wt2-d" --no-cache)"; rc=$?
check "20. tiền đề: wt2-d (có Library/**/local.properties) PASS thật" 0 1 no "$b" "$rc" "$out"
add_wt2 wt2-e
b=$(runs); out="$(gate2 "$TMP/wt2-e")"; rc=$?
check "20. local.properties trong Library/ (cache build) không chặn việc mượn" 0 0 yes "$b" "$rc" "$out"

# 20b. Đối chứng: local.properties THẬT ở gốc khác nhau → không mượn, chạy suite.
add_wt2 wt2-f
echo "sdk.dir=/khac" > "$TMP/wt2-f/local.properties"
b=$(runs); out="$(gate2 "$TMP/wt2-f")"; rc=$?
check "20b. local.properties ở gốc khác: không mượn, chạy suite" 0 1 no "$b" "$rc" "$out"

# 21. Config THẬT mà suite sửa tại chỗ (Flutter / Android Studio giữ sdk.dir, ghi lại khoá khác) không bao giờ vào local_regen (review 18/10, P1):
#     scratch có sdk.dir khác thì không mượn, chạy suite — và suite FAIL đúng như ở đó.
R3="$TMP/repo3"
mkdir -p "$R3/src" && cd "$R3" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
cat > matrix.json <<JSON
{"project":"t3","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-L","name":"lp","command":"echo run >> '$COUNT'; grep -q 'sdk.dir=/good' sub/local.properties && echo flutter.x=\$\$ >> sub/local.properties"}]}]}
JSON
printf 'sub/local.properties\n' > .gitignore
git add -A && git commit -qm init
echo "fun ok() = 2" > src/Core.kt
git commit -qam change
add_wt3() { git -C "$R3" worktree add -q --detach "$TMP/$1" HEAD || { echo "✖ setup: worktree add $1"; exit 1; }
            mkdir -p "$TMP/$1/sub" && echo "sdk.dir=$2" > "$TMP/$1/sub/local.properties"; }
add_wt3 wt3-a /good
b=$(runs); out="$(gate2 "$TMP/wt3-a" --no-cache)"; rc=$?
check "21. tiền đề: wt3-a PASS thật, suite sửa sub/local.properties tại chỗ" 0 1 no "$b" "$rc" "$out"
add_wt3 wt3-b /WRONG
b=$(runs); out="$(FLAKY_RETRY=0 gate2 "$TMP/wt3-b")"; rc=$?
check "21. config thật bị suite sửa tại chỗ vẫn được so: sdk.dir khác thì không mượn, suite chạy và FAIL" 1 1 no "$b" "$rc" "$out"

[ "$FAILS" = 0 ] && { echo "PASS test_gate_sibling_receipt"; exit 0; }
echo "FAIL test_gate_sibling_receipt ($FAILS)"; exit 1
