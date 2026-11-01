#!/usr/bin/env bash
# #638: hook regression_gate gọi `post-fix-gate.py --since <verified_head>`. Sau khi nhánh worktree gộp origin/main, commit của main
# nằm trong dải <since>..HEAD mà không có trên @{u} của nhánh (nhánh không có upstream, hoặc upstream là origin/<nhánh>), nên test
# main đã sửa (đã qua gate của chính nó, đã merge) bị tính "test đã có bị sửa" và đòi duyệt chéo; placeholder main đã có cũng bị chặn.
# Đúng: commit đã có trên origin/<trunk> được đối xử như commit đã có trên @{u} (since_test_weakened, khối A1 kiểm tĩnh).
#  1. nhánh 1 commit code + gộp origin/main có sửa test_b -> không liệt kê test_b, exit 0 (ĐỎ trên code cũ)
#  2. nhánh tự làm yếu test_a + gộp origin/main có sửa test_b -> chỉ liệt kê test_a, exit 2
#  3. main có placeholder `# ... existing code ...` gộp vào nhánh -> kiểm tĩnh không chặn, exit 0
#  4. không có origin (main chỉ ở local) -> mốc cũ: test_b vẫn bị liệt kê, exit 2, không sập
# Lỗ fail-open plan-review v1 tìm ra (rev-list có pathspec rút gọn lịch sử TREESAME; @{u} của nhánh PR push tự do từ #472):
#  5. <since> có assertion nhánh thêm vào test_a, main cũng sửa test_a, gộp giải xung đột --theirs -> vẫn liệt kê test_a, exit 2
#  6. nhánh thêm test_new ở <since>, commit gộp origin/main xoá test_new -> liệt kê test_new, exit 2 (ĐỎ cả trên code cũ)
#  6b. commit chỉ xoá một test đã có (không file sống nào khác đổi) -> exit 2, không phải 3 "không có gì để kiểm" (ĐỎ cả trên code cũ)
#  7. nhánh PR có upstream origin/feat == HEAD sau push -u, test_a bị làm yếu -> vẫn liệt kê test_a, exit 2 (ĐỎ cả trên code cũ)
#  7b. như 7 nhưng pushurl khác URL fetch: nghi ngờ về nhánh không biến thành tin @{u} -> exit 2
#  8. commit gộp nhánh cắt từ commit cũ của main trả bản test yếu cũ về -> exit 2 (ĐỎ cả trên code cũ; review #834)
#  9. cùng hình dạng, trả placeholder main đã gỡ -> kiểm tĩnh exit 1 (XANH trên code cũ, chốt chặn phần nới A1)
#  10. gộp commit WIP ở cha thứ hai của PR đã merge vào main (yếu test_a + placeholder) -> exit 1, liệt kê test_a (audit #834)
#  11. foxtrot (pull --no-rebase trên main rồi push) đẩy đầu main nhánh đã gộp sang cha thứ hai -> vẫn exit 0 (reflog; review #834)
#  12. đối chứng: upstream origin/develop (giống trunk) được tin -> commit đồng đội không bị tính, exit 0
# bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset WORKTREE_TRUNK_MODE
# Lượt kiểu Stop (GATE_TOTAL_BUDGET_S của regression_gate) / worktree finish (DEVKIT_GATE_MERGE_CHECK=1) chạy suite thay vì dừng ở
# "test đã có bị sửa": ca 6b (test_b đã xoá) thành exit 1. Test này xét phân loại --since, không xét lượt kiểu Stop (OCR #834).
unset GATE_TOTAL_BUDGET_S DEVKIT_GATE_MERGE_CHECK
export DEVKIT_SUITE_CACHE=0
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

cfg() { git config user.email t@t && git config user.name t && git config commit.gpgsign false; }
seed() {   # seed: cây đầu tiên trong thư mục hiện tại
  mkdir -p src tests
  printf 'def f():\n    return 1\n' > src/core.py
  printf '#!/bin/sh\n[ 1 = 1 ]\ntrue\n' > tests/test_a.sh
  printf '#!/bin/sh\n[ 2 = 2 ]\ntrue\n' > tests/test_b.sh
  cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh tests/test_a.sh && sh tests/test_b.sh"}]}]}
JSON
  git add -A && git commit -qm init
}
# mk <tên>: origin trần (main) + bản "đồng đội" MATE + bản dev REPO đứng ở nhánh feat; BASE = HEAD đã kiểm (verified_head của hook).
mk() {
  ORIGIN="$TMP/$1.git"; MATE="$TMP/$1-mate"; REPO="$TMP/$1"
  git init -q --bare -b main "$ORIGIN" || exit 1
  git clone -q "$ORIGIN" "$MATE" 2>/dev/null && (cd "$MATE" && cfg && seed && git push -q origin main 2>/dev/null) || exit 1
  git clone -q "$ORIGIN" "$REPO" 2>/dev/null && cd "$REPO" && cfg && git checkout -q -b feat || exit 1
  BASE="$(git rev-parse HEAD)"
}
mate_commit() {   # mate_commit <lệnh sh>: commit trên main của đồng đội rồi push (đã qua gate của chính nó)
  (cd "$MATE" && sh -c "$1" && git add -A && git commit -qm "main: $1" && git push -q origin main 2>/dev/null) || exit 1
}
merge_main() { git fetch -q origin && git merge -q --no-edit origin/main >/dev/null 2>&1 || exit 1; }
gate() {
  OUT="$(CLAUDE_PROJECT_DIR="$PWD" python3 "$GATE" --matrix "$PWD/matrix.json" --lang en --json --run-tests --since "$BASE" 2>&1)"; RC=$?
  JSON="$(printf '%s\n' "$OUT" | grep '^{' | tail -1)"
}
touched() { printf '%s' "$JSON" | python3 -c 'import json,sys; print(" ".join(sorted(json.load(sys.stdin)["tests_touched"])))' 2>/dev/null || echo PARSE_ERROR; }
show() { printf '%s\n' "$OUT" | tail -12; }

# 1. AC1: nhánh 1 commit riêng (code), gộp origin/main có sửa test_b
mk c1
printf 'def f():\n    return 2\n' > src/core.py && git commit -qam "feat: code"
mate_commit "printf '#!/bin/sh\ntrue\n' > tests/test_b.sh"
merge_main
gate
if [ "$RC" = 0 ] && [ -n "$JSON" ] && [ -z "$(touched)" ]; then ok "1: test_b do main sửa (gộp origin/main) không bị tính, exit 0"
else bad "1: rc=$RC tests_touched='$(touched)' (mong 0 và rỗng)"; show; fi

# 2. AC2: nhánh tự làm yếu test_a, gộp origin/main có sửa test_b -> chỉ test_a
mk c2
printf '#!/bin/sh\ntrue\n' > tests/test_a.sh && printf 'def f():\n    return 2\n' > src/core.py && git commit -qam "feat: yếu test_a"
mate_commit "printf '#!/bin/sh\ntrue\n' > tests/test_b.sh"
merge_main
gate
if [ "$RC" = 2 ] && [ "$(touched)" = "tests/test_a.sh" ]; then ok "2: test nhánh tự sửa vẫn đòi duyệt chéo, chỉ liệt kê test_a, exit 2"
else bad "2: rc=$RC tests_touched='$(touched)' (mong 2 và tests/test_a.sh)"; show; fi

# 3. kiểm tĩnh A1 cùng luật: placeholder do main thêm (đã qua gate của main) không chặn nhánh
mk c3
printf 'def f():\n    return 2\n' > src/core.py && git commit -qam "feat: code"
mate_commit "printf 'def h():\n    # ... existing code ...\n    return 3\n' > src/mate.py"
merge_main
gate
if [ "$RC" = 0 ] && [ -n "$JSON" ]; then ok "3: placeholder của main gộp vào nhánh không chặn kiểm tĩnh, exit 0"
else bad "3: rc=$RC (mong 0)"; show; fi

# 4. AC3: không có origin — main chỉ ở local: mốc cũ (commit main local không được tin), không sập
REPO="$TMP/c4"; mkdir -p "$REPO" && cd "$REPO" && git init -q -b main . && cfg && seed || exit 1
git checkout -q -b feat; BASE="$(git rev-parse HEAD)"
printf 'def f():\n    return 2\n' > src/core.py && git commit -qam "feat: code"
git checkout -q main && printf '#!/bin/sh\ntrue\n' > tests/test_b.sh && git commit -qam "main local: yếu test_b"
git checkout -q feat && git merge -q --no-edit main >/dev/null 2>&1 || exit 1
gate
if [ "$RC" = 2 ] && [ "$(touched)" = "tests/test_b.sh" ] && ! printf '%s' "$OUT" | grep -q Traceback; then
  ok "4: không có origin: mốc cũ, test_b vẫn bị liệt kê, exit 2, không traceback"
else bad "4: rc=$RC tests_touched='$(touched)' (mong 2 và tests/test_b.sh)"; show; fi

# 5. assertion nhánh đã kiểm ở <since> bị bản của main đè khi giải xung đột: commit gộp TREESAME với origin/main
mk c5
printf '#!/bin/sh\n[ 1 = 1 ]\n[ 3 = 3 ]\ntrue\n' > tests/test_a.sh && git commit -qam "feat: thêm assertion test_a"
BASE="$(git rev-parse HEAD)"
mate_commit "printf '#!/bin/sh\n[ 1 = 1 ]\n[ 4 = 4 ]\ntrue\n' > tests/test_a.sh"
git fetch -q origin && ! git merge -q --no-edit origin/main >/dev/null 2>&1 || exit 1   # phải xung đột
git checkout -q --theirs tests/test_a.sh && git add tests/test_a.sh && git commit -qm "merge: lấy bản main" || exit 1
gate
if [ "$RC" = 2 ] && [ "$(touched)" = "tests/test_a.sh" ]; then ok "5: assertion nhánh bị --theirs đè vẫn đòi duyệt chéo, exit 2"
else bad "5: rc=$RC tests_touched='$(touched)' (mong 2 và tests/test_a.sh)"; show; fi

# 6. test nhánh mới thêm ở <since> bị xoá trong commit gộp origin/main (cả commit gộp lẫn origin/main đều không có file)
mk c6
printf '#!/bin/sh\n[ 5 = 5 ]\n' > tests/test_new.sh && git add tests/test_new.sh && git commit -qm "feat: test mới" || exit 1
BASE="$(git rev-parse HEAD)"
mate_commit "printf 'def g():\n    return 9\n' > src/other.py"
git fetch -q origin && git merge -q --no-commit --no-ff origin/main >/dev/null 2>&1 || exit 1
git rm -q tests/test_new.sh && git commit -qm "merge: bỏ test_new" || exit 1
gate
if [ "$RC" = 2 ] && [ "$(touched)" = "tests/test_new.sh" ]; then ok "6: test nhánh bị xoá trong commit gộp vẫn bị liệt kê, exit 2"
else bad "6: rc=$RC tests_touched='$(touched)' (mong 2 và tests/test_new.sh)"; show; fi

# 6b. commit chỉ xoá một test đã có, không file sống nào khác đổi: modified_files rỗng từng là exit 3, hook coi 3 là đã kiểm
mk c6b
git rm -q tests/test_b.sh && git commit -qm "feat: bỏ test_b" || exit 1
gate
if [ "$RC" = 2 ] && [ "$(touched)" = "tests/test_b.sh" ]; then ok "6b: commit chỉ xoá test vẫn đòi duyệt chéo, exit 2 (không phải 3)"
else bad "6b: rc=$RC tests_touched='$(touched)' (mong 2 và tests/test_b.sh)"; show; fi

# 7. nhánh PR push -u không cần biên nhận (#472): @{u} == HEAD không phải bằng chứng commit đã qua gate
mk c7
printf '#!/bin/sh\ntrue\n' > tests/test_a.sh && git commit -qam "feat: yếu test_a"
git push -q -u origin feat 2>/dev/null || exit 1
gate
if [ "$RC" = 2 ] && [ "$(touched)" = "tests/test_a.sh" ]; then ok "7: nhánh PR có upstream == HEAD vẫn đòi duyệt chéo test_a, exit 2"
else bad "7: rc=$RC tests_touched='$(touched)' (mong 2 và tests/test_a.sh)"; show; fi

# 7b. pushurl khác URL fetch (push_gate.pr_branch nghi ngờ ⇒ False): nghi ngờ không được biến thành tin @{u}
mk c7b
git config remote.origin.pushurl "file://$ORIGIN" || exit 1
printf '#!/bin/sh\ntrue\n' > tests/test_a.sh && git commit -qam "feat: yếu test_a"
git push -q -u origin feat 2>/dev/null || exit 1
gate
if [ "$RC" = 2 ] && [ "$(touched)" = "tests/test_a.sh" ]; then ok "7b: pushurl khác fetch url, @{u} nhánh PR vẫn không được tin, exit 2"
else bad "7b: rc=$RC tests_touched='$(touched)' (mong 2 và tests/test_a.sh)"; show; fi

# 8. commit gộp một nhánh cắt từ commit CŨ của main (A, test_a yếu) trả bản yếu về, sau khi main đã làm mạnh test_a (P = <since>):
#    commit gộp TREESAME với nhánh cũ, rev-list rút gọn thành rỗng; bản ở HEAD không phải nội dung đã landed (review #834)
mk c8
mate_commit "printf '#!/bin/sh\n[ 1 = 1 ]\n[ 9 = 9 ]\ntrue\n' > tests/test_a.sh"
git fetch -q origin && git merge -q --ff-only origin/main || exit 1
BASE="$(git rev-parse HEAD)"; OLD="$(git rev-parse HEAD~1)"
git checkout -q -b old "$OLD" && printf 'x = 1\n' > src/u.py && git add src/u.py && git commit -qm "old: việc khác" || exit 1
git checkout -q feat && git merge -q --no-ff --no-commit old >/dev/null 2>&1 || exit 1
git show "$OLD:tests/test_a.sh" > tests/test_a.sh && git add tests/test_a.sh && git commit -qm "merge: trả test_a cũ" && git rev-parse -q --verify HEAD^2 >/dev/null || exit 1
gate
if [ "$RC" = 2 ] && [ "$(touched)" = "tests/test_a.sh" ]; then ok "8: commit gộp trả bản test yếu cũ của main về vẫn bị liệt kê, exit 2"
else bad "8: rc=$RC tests_touched='$(touched)' (mong 2 và tests/test_a.sh)"; show; fi

# 9. cùng hình dạng với file code: main thêm placeholder (A') rồi gỡ (P' = <since>); commit gộp trả bản có placeholder về ->
#    kiểm tĩnh A1 phải bắt (trên code cũ không có @{u} nên không nới, bắt được; review #834)
mk c9
mate_commit "printf 'def h():\n    # ... existing code ...\n    return 3\n' > src/old.py"
mate_commit "printf 'def h():\n    return 3\n' > src/old.py"
git fetch -q origin && git merge -q --ff-only origin/main || exit 1
BASE="$(git rev-parse HEAD)"; OLD="$(git rev-parse HEAD~1)"
git checkout -q -b old "$OLD" && printf 'x = 1\n' > src/u.py && git add src/u.py && git commit -qm "old: việc khác" || exit 1
git checkout -q feat && git merge -q --no-ff --no-commit old >/dev/null 2>&1 || exit 1
git show "$OLD:src/old.py" > src/old.py && git add src/old.py && git commit -qm "merge: trả old.py cũ" && git rev-parse -q --verify HEAD^2 >/dev/null || exit 1
gate
if [ "$RC" = 1 ] && printf '%s' "$JSON" | grep -q 'lazy-placeholder'; then ok "9: commit gộp trả placeholder main đã gỡ vẫn bị kiểm tĩnh chặn, exit 1"
else bad "9: rc=$RC (mong 1 và lazy-placeholder)"; show; fi

# 10. gộp commit WIP S1 ở cha thứ hai của một PR đã merge --no-ff vào main (S1 làm yếu test_a + thêm placeholder, S2 trả lại sạch):
#     S1 tới được từ origin/main nhưng chưa từng là đầu main; merge-base(HEAD, origin/main) = S1 không phải nội dung đã landed (audit #834)
mk c10
(cd "$MATE" && git checkout -q -b pr && printf '#!/bin/sh\ntrue\n' > tests/test_a.sh \
  && printf 'def k():\n    # ... existing code ...\n    return 1\n' > src/wip.py && git add -A && git commit -qm "pr: S1 wip" \
  && git rm -q src/wip.py && git checkout -q main -- tests/test_a.sh && git commit -qm "pr: S2 sạch" \
  && git checkout -q main && git merge -q --no-ff --no-edit pr && git push -q origin main 2>/dev/null) || exit 1
S1="$(git -C "$MATE" rev-parse pr~1)"
git fetch -q origin && git merge -q --no-ff --no-edit "$S1" >/dev/null 2>&1 || exit 1
gate
if [ "$RC" = 1 ] && [ "$(touched)" = "tests/test_a.sh" ] && printf '%s' "$JSON" | grep -q 'lazy-placeholder'; then
  ok "10: gộp commit WIP cha thứ hai của PR: test_a vẫn bị liệt kê và placeholder vẫn bị chặn, exit 1"
else bad "10: rc=$RC tests_touched='$(touched)' (mong 1, tests/test_a.sh và lazy-placeholder)"; show; fi

# 11. "foxtrot": nhánh gộp L1 (đầu origin/main lúc đó: main sửa test_b + thêm placeholder); đồng đội pull --no-rebase rồi push nên
#     L1 thành cha thứ hai của origin/main mới. L1 vẫn là nội dung đã landed (có trong reflog của origin/main): exit 0 (review #834)
mk c11
MATE2="$TMP/c11-mate2"; git clone -q "$ORIGIN" "$MATE2" 2>/dev/null && (cd "$MATE2" && cfg) || exit 1
printf 'def f():\n    return 2\n' > src/core.py && git commit -qam "feat: code"
mate_commit "printf '#!/bin/sh\ntrue\n' > tests/test_b.sh && printf 'def m():\n    # ... existing code ...\n    return 4\n' > src/main2.py"
merge_main; L1="$(git rev-parse origin/main)"
(cd "$MATE2" && printf 'y = 2\n' > src/t.py && git add src/t.py && git commit -qm "mate2: T" \
  && git pull -q --no-rebase --no-edit origin main && git push -q origin main 2>/dev/null) || exit 1
git fetch -q origin && [ "$(git rev-parse -q --verify origin/main^2)" = "$L1" ] || exit 1
gate
if [ "$RC" = 0 ] && [ -n "$JSON" ] && [ -z "$(touched)" ]; then ok "11: foxtrot đẩy đầu main đã gộp sang cha thứ hai: không đòi duyệt chéo, exit 0"
else bad "11: rc=$RC tests_touched='$(touched)' (mong 0 và rỗng)"; show; fi

# 12. đối chứng chiều tin: nhánh theo dõi origin/develop (giống trunk), đồng đội làm yếu test_b trên develop, nhánh pull --ff-only
#     -> @{u} được tin, không liệt kê test_b, exit 0 (không chỉ dựa vào task_trunk = origin/main)
mk c12
(cd "$MATE" && git checkout -q -b develop && git push -q origin develop 2>/dev/null) || exit 1
git fetch -q origin && git checkout -q -b dev --track origin/develop >/dev/null 2>&1 || exit 1
BASE="$(git rev-parse HEAD)"
(cd "$MATE" && printf '#!/bin/sh\ntrue\n' > tests/test_b.sh && git commit -qam "develop: yếu test_b" && git push -q origin develop 2>/dev/null) || exit 1
git pull -q --ff-only || exit 1
gate
if [ "$RC" = 0 ] && [ -n "$JSON" ] && [ -z "$(touched)" ]; then ok "12: upstream origin/develop được tin, commit đồng đội không bị tính, exit 0"
else bad "12: rc=$RC tests_touched='$(touched)' (mong 0 và rỗng)"; show; fi

[ "$FAILS" -eq 0 ] && { echo "gate since trunk merge: all passed"; exit 0; }
echo "gate since trunk merge: $FAILS FAILED"; exit 1
