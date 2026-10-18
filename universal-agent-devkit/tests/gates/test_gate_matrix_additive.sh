#!/usr/bin/env bash
# Test hồi quy (GeelyEx2 PR #60, 18/10) cho bin/post-fix-gate.py: một PR chỉ THÊM một rule vào ma trận hồi quy (REG-HOOK-01) bị exit 2
# "regression matrix không tin được … người review" — pre-push và merge gate dừng, người dùng phải tự push và tự bấm merge.
# Gate nay tin ma trận của thay đổi khi so với ma trận ở base nó chỉ THÊM rule mới (rule cũ giữ nguyên từng giá trị, khoá top-level
# không đổi, id test mới chưa có ở base, không covered_by) VÀ mọi test mới chạy XANH ngay trong lượt đó, kể cả khi không file nào khớp
# watch_files của nó. Sửa, xoá, nới rule cũ, mượn id cũ, đổi khoá top-level: vẫn exit 2 như cũ. Test mới ĐỎ: REJECT (1), không bao giờ 0.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="${GATE_UNDER_TEST:-$DEVKIT_DIR/bin/post-fix-gate.py}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }

# mk <dir> <python biểu thức sửa m (ma trận base) thành ma trận của PR>: repo có ma trận base (rule A, REG-A) đã commit, rồi một commit
# "PR" ghi ma trận mới + tests/t2.sh (ghi dấu vào $1/ran_t2 khi chạy, exit theo $T2_EXIT); đặt BASE = commit base
mk() {
  mkdir -p "$1/src" "$1/tests" "$1/.agents"
  ( cd "$1" && git init -q . && git config user.email t@t && git config user.name t
    echo "x = 1" > src/a.py
    printf '#!/bin/sh\ngrep -q "x = 1" src/a.py\n' > tests/t1.sh
    python3 - <<'PY'
import json, os
m = {"project": "t", "rules": [{"component": "A", "watch_files": ["src/*", "tests/*"],
                                "mandatory_regression_tests": [{"id": "REG-A", "name": "A", "command": "sh tests/t1.sh"}]}]}
exec(os.environ.get("BASE_EXPR") or "")
json.dump(m, open(".agents/regression_matrix.active.json", "w"), indent=2)
PY
    git add -A && git commit -qm base )
  BASE="$(git -C "$1" rev-parse HEAD)"
  ( cd "$1"
    printf '#!/bin/sh\ntouch "%s/ran_t2"\nexit %s\n' "$1" "${T2_EXIT:-0}" > tests/t2.sh
    python3 - "$2" <<'PY'
import json, sys
m = json.load(open(".agents/regression_matrix.active.json"))
B = {"component": "B", "watch_files": ["hooks/*"], "mandatory_regression_tests": [{"id": "REG-B", "name": "B", "command": "sh tests/t2.sh"}]}
exec(sys.argv[1])
json.dump(m, open(".agents/regression_matrix.active.json", "w"), indent=2)
PY
    git add -A && git commit -qm pr )
}
gate() {   # gate <dir> → $TMP/out, $RC (đúng cách merge gate gọi: --diff <base>, thêm --full --force-full)
  ( cd "$1" && CLAUDE_PROJECT_DIR="$1" python3 "$GATE" --lang en --run-tests --full --force-full --no-cache --diff "$BASE" ) >"$TMP/out" 2>&1
  RC=$?
}
tail_out() { tail -8 "$TMP/out" | tr '\n' ' '; }

# 1. Ca GeelyEx2: chỉ thêm rule B. Không file nào khớp hooks/* nhưng test mới vẫn phải chạy, XANH → exit 0
mk "$TMP/add" 'm["rules"].append(B)'; gate "$TMP/add"
[ "$RC" = 0 ] && ok "PR chỉ thêm rule, test mới XANH -> exit 0" || fail "PR chỉ thêm rule -> exit $RC (cần 0): $(tail_out)"
[ -f "$TMP/add/ran_t2" ] && ok "test của rule mới đã chạy thật trong lượt gate" || fail "test của rule mới KHÔNG chạy (không file nào khớp watch_files của nó)"
grep -q 'REG-B' "$TMP/out" && ok "REG-B có trong báo cáo" || fail "REG-B không có trong báo cáo"

# 1b. Lượt kiểu Stop hook (--run-tests, không --full): test mới vẫn chạy và quyết định kết luận
rm -f "$TMP/add/ran_t2"
( cd "$TMP/add" && CLAUDE_PROJECT_DIR="$TMP/add" python3 "$GATE" --lang en --run-tests --no-cache --diff "$BASE" ) >"$TMP/out" 2>&1; RC=$?
[ "$RC" = 0 ] && [ -f "$TMP/add/ran_t2" ] && ok "--run-tests (không --full): test mới chạy, exit 0" \
  || fail "--run-tests (không --full) -> exit $RC, ran_t2=$([ -f "$TMP/add/ran_t2" ] && echo có || echo không): $(tail_out)"

# 1c. Không --run-tests: test mới không chạy -> ma trận chỉ-thêm KHÔNG được tin (exit 2 + lý do), không bao giờ 0
( cd "$TMP/add" && CLAUDE_PROJECT_DIR="$TMP/add" python3 "$GATE" --lang en --no-cache --diff "$BASE" ) >"$TMP/out" 2>&1; RC=$?
[ "$RC" = 2 ] && grep -q 'did not pass in this run' "$TMP/out" && ok "không --run-tests -> exit 2, nêu test mới chưa XANH" \
  || fail "không --run-tests -> exit $RC (cần 2 + 'did not pass in this run'): $(tail_out)"

# 2. Rule mới chèn ở ĐẦU (review 18/10, P1): nó chạy trước suite base và tác dụng phụ đi vào suite base — chỉ nhận rule thêm ở đuôi.
# t1.sh (base) đỏ vì src đổi; t2.sh (test của rule chèn đầu) ghi đè t1.sh thành `exit 0`: chèn đầu từng biến REJECT thành exit 0.
mk "$TMP/front" 'B["watch_files"] = ["src/*"]; m["rules"].insert(0, B)'
echo "x = 2" > "$TMP/front/src/a.py"
printf '#!/bin/sh\nprintf "exit 0\\n" > tests/t1.sh\n' > "$TMP/front/tests/t2.sh"
git -C "$TMP/front" commit -qam "pr: src đổi, t1 đỏ, t2 vô hiệu t1"
gate "$TMP/front"
[ "$RC" != 0 ] && ok "rule mới chèn ở đầu, test của nó vô hiệu suite base -> exit $RC, không bao giờ 0" \
  || fail "rule mới chèn ở đầu vô hiệu được suite base -> exit 0: $(tail_out)"

# 2a. Test thêm chạy SAU suite STALE của base (--full chạy lại suite STALE): REG-C đỏ vì src/c.py đã đổi sau lần PASS; test của rule
# thêm ghi đè tests/c.sh thành `exit 0` — chạy trước suite STALE thì REJECT thành exit 0.
S="$TMP/stale"; mkdir -p "$S/src" "$S/tests" "$S/.agents"
( cd "$S" && git init -q . && git config user.email t@t && git config user.name t
  echo ok > src/c.py; echo 1 > src/a.py
  printf '#!/bin/sh\nexit 0\n' > tests/t1.sh; printf '#!/bin/sh\ngrep -q ok src/c.py\n' > tests/c.sh
  printf '{"project": "t", "rules": [{"component": "A", "watch_files": ["src/a.py", "tests/*"], "mandatory_regression_tests": [{"id": "REG-A", "command": "sh tests/t1.sh"}]}, {"component": "C", "watch_files": ["src/c.py"], "mandatory_regression_tests": [{"id": "REG-C", "command": "sh tests/c.sh"}]}]}\n' > .agents/regression_matrix.active.json
  git add -A && git commit -qm init
  echo ok2 > src/c.py; echo 2 > src/a.py
  CLAUDE_PROJECT_DIR="$S" python3 "$GATE" --lang en --run-tests --full --force-full --no-cache >/dev/null 2>&1
  git add -A && git commit -qm ran && sleep 1.1
  echo bad > src/c.py && git commit -qam "c đổi, REG-C đỏ khi chạy lại" && sleep 1.1
  python3 "$DEVKIT_DIR/bin/regression_checklist.py" render >/dev/null 2>&1 )
BASE="$(git -C "$S" rev-parse HEAD)"
( cd "$S" && printf '#!/bin/sh\nprintf "exit 0\\n" > tests/c.sh\n' > tests/t2.sh
  python3 -c "
import json; p='.agents/regression_matrix.active.json'; m=json.load(open(p))
m['rules'].append({'component': 'B', 'watch_files': ['hooks/*'], 'mandatory_regression_tests': [{'id': 'REG-B', 'command': 'sh tests/t2.sh'}]})
json.dump(m, open(p, 'w'), indent=2)"
  git add -A && git commit -qm "pr: thêm rule B" )
gate "$S"
if grep -q 'REG-C' "$TMP/out"; then
  [ "$RC" = 1 ] && ok "test thêm chạy sau suite STALE của base -> REG-C vẫn đỏ, REJECT" \
    || fail "test thêm vô hiệu suite STALE của base -> exit $RC (cần 1): $(tail_out)"
else fail "setup: REG-C không STALE nên không được chạy lại: $(tail_out)"; fi

# 2b. Test thêm không đẩy script vào DEVKIT_GATE_DONE (run_impacted.sh bỏ qua script đã chạy): B1 `true # sh tests/t3.sh` (tên chỉ
# nằm trong comment) từng làm runner của B2 bỏ qua t3.sh đỏ -> exit 0.
mk "$TMP/done" 'm["rules"].append({"component": "B", "watch_files": ["hooks/*"], "mandatory_regression_tests": [{"id": "REG-B1", "command": "true # sh tests/t3.sh"}, {"id": "REG-B2", "command": "sh tests/r.sh"}]})'
printf '#!/bin/sh\nexit 1\n' > "$TMP/done/tests/t3.sh"
printf '#!/bin/sh\nf="$(pwd -P)/tests/t3.sh"\nprintf "%%s\\n" "$DEVKIT_GATE_DONE" | grep -qxF "$f" && exit 0\nsh tests/t3.sh\n' > "$TMP/done/tests/r.sh"
git -C "$TMP/done" add -A && git -C "$TMP/done" commit -qm "pr: t3 đỏ, r.sh bỏ qua script đã chạy"
gate "$TMP/done"
[ "$RC" = 1 ] && ok "test thêm không ẩn được test thêm khác qua DEVKIT_GATE_DONE -> REJECT" || fail "DEVKIT_GATE_DONE ẩn được t3.sh đỏ -> exit $RC (cần 1): $(tail_out)"

# 3. Test mới ĐỎ: REJECT, không bao giờ 0
T2_EXIT=1 mk "$TMP/red" 'm["rules"].append(B)'; gate "$TMP/red"
[ "$RC" = 1 ] && ok "test mới ĐỎ -> REJECT (1)" || fail "test mới ĐỎ -> exit $RC (cần 1): $(tail_out)"

# 4-11. Mọi thay đổi khác của ma trận vẫn cần người review (exit 2) và test mới không được tin
expect_untrusted() {   # <tên> <biểu thức>
  rm -rf "$TMP/u"; mk "$TMP/u" "$2"; gate "$TMP/u"
  if [ "$RC" = 2 ] && grep -q 'was modified relative to' "$TMP/out"; then ok "$1 -> exit 2, ma trận không tin được"
  else fail "$1 -> exit $RC (cần 2 + 'was modified relative to'): $(tail_out)"; fi
}
expect_untrusted "sửa lệnh test cũ (exit 1 -> true) + thêm rule" \
  'm["rules"][0]["mandatory_regression_tests"][0]["command"] = "true"; m["rules"].append(B)'
expect_untrusted "xoá rule cũ + thêm rule" 'm["rules"] = [B]'
expect_untrusted "nới watch_files của rule cũ + thêm rule" 'm["rules"][0]["watch_files"] = ["src/*"]; m["rules"].append(B)'
expect_untrusted "thêm covered_by vào test cũ" 'm["rules"][0]["mandatory_regression_tests"][0]["covered_by"] = "REG-B"; m["rules"].append(B)'
expect_untrusted "rule mới mượn id REG-A với lệnh khác" 'B["mandatory_regression_tests"][0]["id"] = "REG-A"; m["rules"].append(B)'
expect_untrusted "test mới covered_by test cũ (không tự chạy)" 'B["mandatory_regression_tests"][0]["covered_by"] = "REG-A"; m["rules"].append(B)'
expect_untrusted "đổi khoá top-level + thêm rule" 'm["project"] = "khac"; m["rules"].append(B)'
expect_untrusted "thêm rule có test + rule không test (rule rỗng làm file 'được phủ')" \
  'm["rules"].append(B); m["rules"].append({"component": "C", "watch_files": ["**"], "mandatory_regression_tests": []})'

# 4b. covered_by treo ở base (REG-A covered_by REG-Z, không suite nào tên REG-Z): id thêm không được "lấp" đích đó
BASE_EXPR='m["rules"][0]["mandatory_regression_tests"][0]["covered_by"] = "REG-Z"' \
  mk "$TMP/cov" 'B["mandatory_regression_tests"][0]["id"] = "REG-Z"; m["rules"].append(B)'; gate "$TMP/cov"
[ "$RC" = 2 ] && grep -q 'was modified relative to' "$TMP/out" && ok "id thêm trùng đích covered_by treo ở base -> exit 2" \
  || fail "id thêm lấp covered_by treo ở base -> exit $RC (cần 2): $(tail_out)"

# 4c. Test thêm được đánh PASS mà không chạy (SKIP compile cạnh suite EditMode) không phải XANH
BASE_EXPR='m["rules"][0]["mandatory_regression_tests"][0]["command"] = "sh tests/t1.sh editmode"' \
  mk "$TMP/skc" 'B["mandatory_regression_tests"][0]["command"] = "sh tests/t2.sh compile"; m["rules"].append(B)'; gate "$TMP/skc"
[ "$RC" = 2 ] && [ ! -f "$TMP/skc/ran_t2" ] && ok "test thêm SKIP compile (không chạy) -> exit 2" \
  || fail "test thêm SKIP compile -> exit $RC, ran_t2=$([ -f "$TMP/skc/ran_t2" ] && echo có || echo không) (cần 2, không chạy): $(tail_out)"

# 4d. Hết ngân sách giờ trước khi test thêm chạy: UNTESTED/BUDGET (exit 4) như mọi suite, không phải "ma trận không tin được"
mk "$TMP/bud" 'm["rules"].append(B)'
( cd "$TMP/bud" && GATE_TOTAL_BUDGET_S=0.000001 CLAUDE_PROJECT_DIR="$TMP/bud" python3 "$GATE" --lang en --run-tests --full --force-full --no-cache --diff "$BASE" ) >"$TMP/out" 2>&1; RC=$?
[ "$RC" = 4 ] && ok "hết ngân sách giờ -> exit 4 (BUDGET)" || fail "hết ngân sách giờ -> exit $RC (cần 4): $(tail_out)"

# 12. Test mới không chạy được trên máy (untested_exit): không phải XANH -> không tin ma trận (exit 2), không phải 0
T2_EXIT=7 mk "$TMP/unt" 'B["mandatory_regression_tests"][0]["untested_exit"] = 7; m["rules"].append(B)'; gate "$TMP/unt"
[ "$RC" = 2 ] && ok "test mới UNTESTED -> exit 2" || fail "test mới UNTESTED -> exit $RC (cần 2): $(tail_out)"
grep -q 'REG-B' "$TMP/unt/.agents/CHECKLIST.md" && fail "ma trận chỉ-thêm KHÔNG được tin vẫn ghi REG-B vào checklist" \
  || ok "ma trận không được tin: checklist theo ma trận base (không có REG-B)"

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_matrix_additive: all passed" || { echo "❌ test_gate_matrix_additive: $FAILS failed"; exit 1; }
