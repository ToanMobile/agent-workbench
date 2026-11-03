#!/usr/bin/env bash
# Test hồi quy: hai PR cùng NỐI một rule vào cuối .agents/regression_matrix.active.json sửa cùng dòng cuối ("    }" thành "    },") nên
# PR thứ hai luôn CONFLICTING trên GitHub (GitHub không chạy merge driver devkit-matrix). Sửa: rule mới chèn vào khe
# idx = int(sha256(component).hexdigest(), 16) % len(rules) (TRƯỚC rules[idx], không bao giờ ở cuối) bằng `agent-kit matrix add`;
# gate tin ma trận khi rule base là DÃY CON đúng thứ tự (không chỉ tiền tố), và trust_additive_matrix trả rule base trước, rule thêm sau
# (INSTINCT-050: lệnh do thay đổi đưa vào chạy SAU mọi suite base). Một bộ phân loại (bin/matrix_slot.py) cho post-fix-gate,
# scoped_gate._matrix_append_readers và matrix_merge_driver (INSTINCT-015).
#   1. matrix_additions: rule chèn giữa / đầu ⇒ id thêm (hôm nay None); vẫn None cho: đảo rule base, đảo + thêm, chèn + sửa rule base,
#      component trùng base (luật của scoped twin gatesched, nay chung)
#   2. gate --diff: rule chèn GIỮA, test mới XANH ⇒ exit 0 và test mới đã chạy (hôm nay exit 2 "was modified relative to")
#   3. gate --diff: rule chèn ĐẦU mà test của nó vô hiệu t1 ⇒ vẫn REJECT (1), ma trận được tin ("running the new tests last"),
#      không "was modified relative to" (hôm nay: exit 1 qua đường không tin)
#   4. trust_additive_matrix trả ma trận đã SẮP: component base theo thứ tự base, rule thêm sau (hôm nay trả base + problem)
#   5. driver: hai phía chèn khe KHÁC ⇒ gộp bằng driver (stderr không "an existing rule was edited"), mỗi rule đúng khe
#   6. driver: hai phía chèn CÙNG khe ⇒ gộp sạch, cả hai rule trước rules[i] của base (hôm nay text merge conflict)
#   7. `agent-kit matrix add <rule.json>`: chèn đúng khe băm, file = json.dumps(indent=2, ensure_ascii=False)+"\n" byte y hệt
#   8. `agent-kit matrix add`: id / component đã có ⇒ exit ≠ 0, nêu tên, file không đổi
#   9. hai nhánh, mỗi nhánh `agent-kit matrix add` một rule (khe khác nhau) ⇒ `git merge` KHÔNG driver sạch, gate tin bản gộp
#  10. scoped_gate._matrix_append_readers: ma trận chèn giữa ⇒ danh sách test đọc ma trận (hôm nay None: luật tiền tố)
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="${GATE_UNDER_TEST:-$DEVKIT_DIR/bin/post-fix-gate.py}"
KIT="$DEVKIT_DIR/bin/agent-kit"
DRIVER="$DEVKIT_DIR/scripts/git/matrix_merge_driver.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
unset BASE_EXPR T2_EXIT GATE_TOTAL_BUDGET_S
M=".agents/regression_matrix.active.json"
tail_out() { tail -8 "$TMP/out" | tr '\n' ' '; }

# py_gate <python>: chạy python với g = module post-fix-gate (nạp bằng đường dẫn như test_matrix_merge_driver.sh), argv[1:] = phần còn lại
py_gate() {
  local code="$1"; shift
  python3 - "$GATE" "$@" <<PY
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("g", sys.argv[1]); g = importlib.util.module_from_spec(spec); spec.loader.exec_module(g)
args = sys.argv[2:]
$code
PY
}

# ---- 1. matrix_additions (đơn vị) ----------------------------------------------------------------------------------------------
U='
def R(c, i, cmd="true"): return {"component": c, "watch_files": ["x/" + c], "mandatory_regression_tests": [{"id": i, "command": cmd}]}
A, A2, A3, B = R("A", "REG-A"), R("A2", "REG-A2"), R("A3", "REG-A3"), R("B", "REG-B")
base = {"project": "t", "rules": [A, A2, A3]}
def cur(rules): return {"project": "t", "rules": rules}
'
py_gate "$U"'
sys.exit(0 if g.matrix_additions(base, cur([A, B, A2, A3])) == ["REG-B"] else 1)' \
  && ok "1a: rule chèn GIỮA -> matrix_additions trả [REG-B]" || fail "1a: rule chèn giữa không được nhận (hôm nay None: luật tiền tố)"
py_gate "$U"'
sys.exit(0 if g.matrix_additions(base, cur([B, A, A2, A3])) == ["REG-B"] else 1)' \
  && ok "1b: rule chèn ĐẦU -> [REG-B] (thứ tự chạy do trust/tail lo)" || fail "1b: rule chèn đầu không được nhận"
py_gate "$U"'
sys.exit(0 if g.matrix_additions(base, cur([A, A2, A3, B])) == ["REG-B"] else 1)' \
  && ok "1c: nối cuối (đường cũ) vẫn [REG-B]" || fail "1c: nối cuối hỏng"
py_gate "$U"'
X = dict(B, component="A2")   # id mới nhưng component trùng rule base
sys.exit(0 if g.matrix_additions(base, cur([A, X, A2, A3])) is None and g.matrix_additions(base, cur([A, A2, A3, X])) is None else 1)' \
  && ok "1d: component trùng rule base -> None (một luật với scoped twin)" || fail "1d: component trùng base vẫn được tin"
py_gate "$U"'
Y = dict(B, component="B")
Z = {"component": "B", "watch_files": ["y/*"], "mandatory_regression_tests": [{"id": "REG-B2", "command": "true"}]}
sys.exit(0 if g.matrix_additions(base, cur([A, A2, A3, Y, Z])) is None else 1)' \
  && ok "1e: hai rule nối cuối cùng component -> None" || fail "1e: hai rule thêm trùng component vẫn được tin"
for neg in 'cur([A2, A, A3])' 'cur([A2, A, B, A3])' 'cur([A, B, dict(A2, watch_files=["**"]), A3])' 'cur([A, B, A3])' \
           'cur([A, dict(B, mandatory_regression_tests=[{"id": "REG-A2", "command": "x"}]), A2, A3])'; do
  py_gate "$U"'
sys.exit(0 if g.matrix_additions(base, '"$neg"') is None else 1)' \
    && ok "1f: không chỉ-thêm vẫn None: $neg" || fail "1f: được tin dù không chỉ-thêm: $neg"
done

# ---- 2–4. gate thật (khuôn test_gate_matrix_additive.sh) -------------------------------------------------------------------------
mk() {   # mk <dir> <python sửa m thành ma trận PR>; base: rule A (REG-A, t1.sh) [+ BASE_EXPR]; PR: tests/t2.sh ghi dấu, exit $T2_EXIT
  mkdir -p "$1/src" "$1/tests" "$1/.agents"
  ( cd "$1" && git init -q . && git config user.email t@t && git config user.name t
    echo "x = 1" > src/a.py
    printf '#!/bin/sh\ngrep -q "x = 1" src/a.py\n' > tests/t1.sh
    python3 - <<'PY'
import json, os
m = {"project": "t", "rules": [{"component": "A", "watch_files": ["src/*", "tests/*"],
                                "mandatory_regression_tests": [{"id": "REG-A", "name": "A", "command": "sh tests/t1.sh"}]}]}
exec(os.environ.get("BASE_EXPR") or "")
open(".agents/regression_matrix.active.json", "w").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
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
open(".agents/regression_matrix.active.json", "w").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
PY
    git add -A && git commit -qm pr )
}
gate() {
  ( cd "$1" && CLAUDE_PROJECT_DIR="$1" python3 "$GATE" --lang en --run-tests --full --force-full --no-cache --diff "$BASE" ) >"$TMP/out" 2>&1
  RC=$?
}
A2='m["rules"].append({"component": "A2", "watch_files": ["src/*"], "mandatory_regression_tests": [{"id": "REG-A2", "command": "sh tests/t1.sh"}]})'

# 2
BASE_EXPR="$A2" mk "$TMP/mid" 'm["rules"].insert(1, B)'; BASE_MID="$BASE"; gate "$TMP/mid"
[ "$RC" = 0 ] && [ -f "$TMP/mid/ran_t2" ] && ! grep -q 'was modified relative to' "$TMP/out" \
  && ok "2: rule chèn GIỮA, test mới XANH -> exit 0, test mới đã chạy" \
  || fail "2: rule chèn giữa -> exit $RC, ran_t2=$([ -f "$TMP/mid/ran_t2" ] && echo có || echo không) (cần 0): $(tail_out)"

# 3 (INSTINCT-050 giữ nguyên): rule chèn ĐẦU, t2 ghi đè t1.sh thành exit 0; src đổi nên t1 base ĐỎ ⇒ REJECT dù ma trận được tin
mk "$TMP/front" 'B["watch_files"] = ["src/*"]; m["rules"].insert(0, B)'
echo "x = 2" > "$TMP/front/src/a.py"
printf '#!/bin/sh\nprintf "exit 0\\n" > tests/t1.sh\n' > "$TMP/front/tests/t2.sh"
git -C "$TMP/front" commit -qam "pr: src đổi, t1 đỏ, t2 vô hiệu t1"
gate "$TMP/front"
[ "$RC" = 1 ] && grep -q 'running the new tests last' "$TMP/out" && ! grep -q 'was modified relative to' "$TMP/out" \
  && ok "3: rule chèn ĐẦU được tin nhưng chạy SAU suite base -> t1 ĐỎ, REJECT" \
  || fail "3: rule chèn đầu -> exit $RC (cần 1 + 'running the new tests last', không 'was modified'): $(tail_out)"

# 4: trust_additive_matrix trả base trước, rule thêm sau
( cd "$TMP/mid" && CLAUDE_PROJECT_DIR="$TMP/mid" py_gate '
bm, prob = g.load_active_matrix(None, args[0])
m, p, added = g.trust_additive_matrix(bm, prob, None, args[0])
comps = [r.get("component") for r in m.get("rules", [])]
print("comps", comps, "problem", p, "added", added)
sys.exit(0 if p is None and added == ["REG-B"] and comps == ["A", "A2", "B"] else 1)' "$BASE_MID" ) >"$TMP/out" 2>&1 \
  && ok "4: trust_additive_matrix -> [A, A2, B] (base trước, rule thêm sau), không problem" \
  || fail "4: trust_additive_matrix chưa trả ma trận đã sắp: $(tail_out)"

# ---- 5–6. merge driver -------------------------------------------------------------------------------------------------------
rule() { printf '{"component": "%s", "watch_files": ["x/%s"], "mandatory_regression_tests": [{"id": "%s", "name": "n", "command": "true"}]}' "$1" "$1" "$1"; }
mrepo() {   # repo với driver đăng ký; base = 4 rule BASE-1..4
  R="$(mktemp -d "$TMP/repo.XXXXXX")" && mkdir -p "$R/.agents"
  git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
  echo "$M merge=devkit-matrix" > "$R/.gitattributes"
  git -C "$R" config merge.devkit-matrix.driver "python3 $DRIVER %O %A %B %P"
  ( cd "$R" && python3 - "$(rule BASE-1)" "$(rule BASE-2)" "$(rule BASE-3)" "$(rule BASE-4)" <<'PY'
import json, sys
m = {"version": 1, "project": "t", "rules": [json.loads(a) for a in sys.argv[1:]]}
open(".agents/regression_matrix.active.json", "w", encoding="utf-8").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
PY
  git add -A && git commit -qm base )
}
binsert() {   # binsert <nhánh> <khe> <id>
  git -C "$R" checkout -q -b "$1" main
  ( cd "$R" && python3 - "$2" "$(rule "$3")" <<'PY'
import json, sys
p = ".agents/regression_matrix.active.json"; m = json.load(open(p, encoding="utf-8"))
m["rules"].insert(int(sys.argv[1]), json.loads(sys.argv[2]))
open(p, "w", encoding="utf-8").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
PY
  git commit -qam "$1" )
}
ids() { python3 -c 'import json,sys;print(" ".join(t["id"] for r in json.load(open(sys.argv[1]))["rules"] for t in r["mandatory_regression_tests"]))' "$R/$M"; }

# 5
mrepo; binsert a 1 A-1; binsert b 3 B-1; git -C "$R" checkout -q a
git -C "$R" merge --no-edit b >"$TMP/out" 2>&1; RC=$?
[ "$RC" = 0 ] && [ "$(ids)" = "BASE-1 A-1 BASE-2 BASE-3 B-1 BASE-4" ] && ! grep -q 'an existing rule was edited' "$TMP/out" \
  && ok "5: khe khác nhau -> driver gộp (không rơi về merge-file), mỗi rule đúng khe" \
  || fail "5: rc=$RC ids='$(ids)' $(tr '\n' ' ' < "$TMP/out")"

# 6
mrepo; binsert a 2 A-1; binsert b 2 B-1; git -C "$R" checkout -q a
git -C "$R" merge --no-edit b >"$TMP/out" 2>&1; RC=$?
[ "$RC" = 0 ] && [ "$(ids)" = "BASE-1 BASE-2 A-1 B-1 BASE-3 BASE-4" ] && ! grep -q '^<<<<<<<' "$R/$M" \
  && ok "6: cùng khe -> driver gộp sạch, ours rồi theirs trước rules[2] của base" \
  || fail "6: cùng khe -> rc=$RC ids='$(ids 2>/dev/null)' $(tr '\n' ' ' < "$TMP/out")"

# 6b: cùng component thêm ở cả hai phía (id khác, `matrix add` đưa vào cùng khe): mỗi phía hợp lệ nhưng bản gộp gate không tin ⇒
# driver không được gộp "sạch"; rơi về merge-file như GitHub: cùng khe ⇒ CONFLICT
mrepo; binsert a 2 SAME; git -C "$R" checkout -q -b b main
( cd "$R" && python3 - <<'PY'
import json
p = ".agents/regression_matrix.active.json"; m = json.load(open(p, encoding="utf-8"))
m["rules"].insert(2, {"component": "SAME", "watch_files": ["x/SAME"], "mandatory_regression_tests": [{"id": "SAME-B", "name": "n", "command": "true"}]})
open(p, "w", encoding="utf-8").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
PY
  git commit -qam b )
git -C "$R" checkout -q a
git -C "$R" merge --no-edit b >"$TMP/out" 2>&1; RC=$?
[ "$RC" != 0 ] && grep -q 'same component' "$TMP/out" \
  && ok "6b: cùng component hai phía -> driver không gộp, merge-file CONFLICT" \
  || fail "6b: cùng component hai phía -> rc=$RC $(tr '\n' ' ' < "$TMP/out")"
git -C "$R" merge --abort >/dev/null 2>&1

# ---- 7–9. agent-kit matrix add -------------------------------------------------------------------------------------------------
krepo() {   # krepo <dir>: repo + ma trận 5 rule + rule.json
  mkdir -p "$1/.agents" && git -C "$1" init -q -b main . && git -C "$1" config user.email t@t && git -C "$1" config user.name t
  ( cd "$1" && python3 - <<'PY'
import json
m = {"version": 1, "project": "t", "rules": [{"component": "C%d" % i, "watch_files": ["x/%d" % i],
     "mandatory_regression_tests": [{"id": "REG-%d" % i, "name": "ă %d" % i, "command": "true"}]} for i in range(5)]}
open(".agents/regression_matrix.active.json", "w", encoding="utf-8").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
PY
  git add -A && git commit -qm base )
}
mkrule() { printf '{"component": "%s", "watch_files": ["n/%s"], "mandatory_regression_tests": [{"id": "%s", "name": "mới ư", "command": "true"}]}\n' "$2" "$2" "$3" > "$1"; }
expect_after_add() {   # expect_after_add <dir> <rule.json> → in ra file mong đợi (khe băm theo component)
  python3 - "$1/$M" "$2" <<'PY'
import hashlib, json, sys
m = json.load(open(sys.argv[1], encoding="utf-8")); r = json.load(open(sys.argv[2], encoding="utf-8"))
i = int(hashlib.sha256(r["component"].encode("utf-8")).hexdigest(), 16) % len(m["rules"]) if m["rules"] else 0
m["rules"].insert(i, r)
sys.stdout.write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
PY
}

# 7
K="$TMP/k1"; krepo "$K"; mkrule "$TMP/r1.json" NEW-COMP REG-NEW
expect_after_add "$K" "$TMP/r1.json" > "$TMP/want.json"
( cd "$K" && bash "$KIT" matrix add "$TMP/r1.json" ) >"$TMP/out" 2>&1; RC=$?
[ "$RC" = 0 ] && cmp -s "$TMP/want.json" "$K/$M" && [ "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["rules"][-1]["component"])' "$K/$M")" != NEW-COMP ] \
  && ok "7: agent-kit matrix add chèn đúng khe băm, không ở cuối, byte y hệt json.dumps(indent=2, ensure_ascii=False)" \
  || fail "7: agent-kit matrix add -> rc=$RC, file $(cmp -s "$TMP/want.json" "$K/$M" && echo khớp || echo KHÁC): $(tail_out)"

# 8
for dup in "C2 REG-NEW2" "NEW-C REG-3"; do
  set -- $dup
  K="$TMP/k8.$1"; krepo "$K"; cp "$K/$M" "$TMP/before.json"; mkrule "$TMP/r8.json" "$1" "$2"
  ( cd "$K" && bash "$KIT" matrix add "$TMP/r8.json" ) >"$TMP/out" 2>&1; RC=$?
  { [ "$RC" != 0 ] && cmp -s "$TMP/before.json" "$K/$M" && { grep -q "$1" "$TMP/out" || grep -q "$2" "$TMP/out"; }; } \
    && ok "8: matrix add component/id đã có ($dup) -> từ chối, nêu tên, file không đổi" || fail "8: ($dup) rc=$RC: $(tail_out)"
done

# 9: hai nhánh dùng công cụ, khe khác nhau ⇒ git merge KHÔNG driver sạch; gate tin bản gộp so với base
K="$TMP/k9"; krepo "$K"; BASE9="$(git -C "$K" rev-parse HEAD)"
pick=$(python3 - <<'PY'
import hashlib
n, seen, out = 5, set(), []
for k in range(1000):
    c = "COMP-%d" % k; s = int(hashlib.sha256(c.encode()).hexdigest(), 16) % n
    if s not in seen: seen.add(s); out.append(c)
    if len(out) == 2: break
print(" ".join(out))
PY
)
set -- $pick
mkrule "$TMP/ra.json" "$1" REG-A9; mkrule "$TMP/rb.json" "$2" REG-B9
git -C "$K" checkout -q -b a main && ( cd "$K" && bash "$KIT" matrix add "$TMP/ra.json" >/dev/null 2>&1 ) && git -C "$K" commit -qam a
git -C "$K" checkout -q -b b main && ( cd "$K" && bash "$KIT" matrix add "$TMP/rb.json" >/dev/null 2>&1 ) && git -C "$K" commit -qam b
git -C "$K" checkout -q a
git -C "$K" check-attr merge -- "$M" | grep -q 'unspecified' || fail "9: setup: ma trận có merge driver (cần không driver)"
git -C "$K" merge --no-edit b >"$TMP/out" 2>&1; RC=$?
[ "$RC" = 0 ] && ( cd "$K" && py_gate '
base = json.loads(__import__("subprocess").run(["git", "show", args[0] + ":.agents/regression_matrix.active.json"], capture_output=True, text=True).stdout)
cur = json.load(open(".agents/regression_matrix.active.json", encoding="utf-8"))
sys.exit(0 if sorted(g.matrix_additions(base, cur) or []) == ["REG-A9", "REG-B9"] else 1)' "$BASE9" ) \
  && ok "9: hai nhánh 'matrix add' khe khác -> git merge không driver SẠCH, gate tin bản gộp" \
  || fail "9: rc=$RC (cần merge sạch + matrix_additions = [REG-A9, REG-B9]): $(tail_out)"

# ---- 10. scoped_gate twin (gatesched _matrix_append_readers) ---------------------------------------------------------------------
P="$TMP/sg"; mkdir -p "$P/.agents" "$P/tests" && git -C "$P" init -q -b main . && git -C "$P" config user.email t@t && git -C "$P" config user.name t
printf '#!/bin/bash\nexit 0\n' > "$P/tests/test_reads_matrix.sh"
( cd "$P" && python3 - <<'PY'
import json
m = {"project": "t", "rules": [
  {"component": "M", "watch_files": [".agents/regression_matrix.active.json"], "mandatory_regression_tests": [{"id": "REG-M", "command": "bash tests/test_reads_matrix.sh"}]},
  {"component": "Q", "watch_files": ["q/*"], "mandatory_regression_tests": [{"id": "REG-Q", "command": "true"}]}]}
open(".agents/regression_matrix.active.json", "w").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
PY
  git add -A && git commit -qm base && python3 - <<'PY'
import json
p = ".agents/regression_matrix.active.json"; m = json.load(open(p))
m["rules"].insert(1, {"component": "N", "watch_files": ["n/*"], "mandatory_regression_tests": [{"id": "REG-N", "command": "true"}]})
open(p, "w").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
PY
  git commit -qam pr )
# Twin chỉ có sau khi gatesched PR1 (perf/gate-sched-pr1) merge: chưa có thì in "skip" (không ✔, không ✖), ca tự bật khi nó merge.
python3 - "$DEVKIT_DIR/bin" "$P" <<'PY' >"$TMP/out" 2>&1; RC=$?
import sys
sys.path.insert(0, sys.argv[1]); import scoped_gate as sg
if not hasattr(sg, "_matrix_append_readers"):
    print("no twin"); sys.exit(3)
got = sg._matrix_append_readers(sys.argv[2], "HEAD~1", False)
print("readers", got)
sys.exit(0 if got == ["tests/test_reads_matrix.sh"] else 1)
PY
case "$RC" in
  0) ok "10: scoped_gate: ma trận chèn giữa -> chỉ test đọc ma trận" ;;
  3) echo "skip 10: scoped_gate chưa có _matrix_append_readers (gatesched PR1 chưa merge)" ;;
  *) fail "10: scoped twin: $(tail_out)" ;;
esac

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_matrix_slot: all passed" || { echo "❌ test_gate_matrix_slot: $FAILS failed"; exit 1; }
