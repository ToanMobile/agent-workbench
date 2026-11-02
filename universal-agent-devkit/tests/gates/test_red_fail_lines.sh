#!/usr/bin/env bash
# Test hồi quy #721: một test đỏ in MỌI dòng hỏng của nó (✖ ✘ ✗ ❌ FAIL not ok ở đầu dòng), không chỉ đuôi.
# Gate-full đêm 31/10: test_game_blender_default.sh 'failures: 2' mà hai dòng ✖ A33/A23 nằm trước 20 dòng đuôi của
# tests/run_impacted.sh và trước 15 dòng cuối của lần chạy lại khi chia đôi (bin/gate_full.py checks_fail): log không có.
#   a. run_impacted.sh: dòng hỏng nằm trước đuôi in dưới tên test đỏ (≤ 40, '… còn N dòng hỏng nữa'), rồi đuôi 20 dòng như cũ;
#      dòng đã ở trong đuôi không in lại; test xanh không in thêm; rc và thứ tự kết quả giữ nguyên.
#   b. gate_full.checks_fail: lần chạy lại đỏ ghi cả dòng hỏng nằm trước 15 dòng cuối; lần chạy lại xanh như cũ.
#   c. post-fix-gate.py: fail_lines giữ mọi dòng "✖ tests/x.sh" (cột 0) của run_impacted dù test đỏ trước có nhiều dòng con
#      (merge-train single_red_test #578 đếm test đỏ từ khối '| ✖ …'), không lặp khi flaky_retry nối hai lần chạy;
#      FAIL_LINE nhận ✘ và 'not ok' ở đầu dòng (cả --brief); --brief giữ dòng `Log:` và khối '| …' của suite không có dòng ✖ (c7).
# Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_GATE_DONE DEVKIT_IMPACT_TEST_CHANGED DEVKIT_SCOPED_TESTS DEVKIT_IMPACTED_DIRS DEVKIT_IMPACTED_SINCE \
  DEVKIT_PER_TEST_CACHE DEVKIT_ALONE_AFTER_FILE DEVKIT_TEST_JOBS FLAKY_RETRY WORKTREE_TRUNK_MODE
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"   # pool slot riêng: hai lượt gate ở khối c không chờ pool gate toàn máy
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
lines() { i=1; while [ "$i" -le "$2" ]; do echo "echo \"$1 $i\""; i=$((i + 1)); done; }   # <prefix> <n> -> n dòng echo

# --- a. tests/run_impacted.sh ----------------------------------------------------------------------------------------------
K="$TMP/a/kit"; mkdir -p "$K/tests/verification"
cp "$DEVKIT_DIR/tests/run_impacted.sh" "$K/tests/run_impacted.sh"; : > "$K/tests/impact_map.txt"
echo 'echo ok' > "$K/tests/verification/test_repo_consistency.sh"
{ echo 'echo "✖ A33 early failure"'; echo 'echo "✘ A40 cross mark"'; echo 'echo "  FAIL: plain"'; echo 'echo "not ok 3 - tap"'
  echo 'echo "✔ D says FAIL in prose"'; lines "✔ case" 25; echo 'echo "✖ A99 in tail"'; echo 'echo "failures: 5"'; echo 'exit 1'
} > "$K/tests/verification/test_red.sh"
{ lines "✖ many" 45; lines "✔ t" 25; echo 'exit 1'; } > "$K/tests/verification/test_many.sh"
{ echo 'echo "✖ fake but green"'; lines "✔ g" 25; } > "$K/tests/verification/test_green.sh"
( cd "$K" && git init -q . && git config user.email t@t && git config user.name t && git add -A && git commit -qm init ) || exit 1
OUT="$(cd "$K" && DEVKIT_TEST_JOBS=2 bash tests/run_impacted.sh --all 2>/dev/null)"; RC=$?
printf '%s\n' "$OUT" > "$TMP/a.out"
at() { grep -n -F -x -- "$1" "$TMP/a.out" | head -1 | cut -d: -f1; }   # số dòng đầu tiên đúng bằng <dòng>
cnt() { grep -c -F -x -- "$1" "$TMP/a.out"; }
show() { tr '\n' '|' < "$TMP/a.out" | cut -c1-900; }
h="$(at "✖ tests/verification/test_red.sh")"; a33="$(at "    ✖ A33 early failure")"; end="$(at "    failures: 5")"
[ -n "$h" ] && [ -n "$a33" ] && [ -n "$end" ] && [ "$h" -lt "$a33" ] && [ "$a33" -lt "$end" ] \
  && ok "a1 test đỏ: dòng ✖ A33 (trước 20 dòng đuôi) in dưới tên test, trước đuôi" || fail "a1 thiếu ✖ A33 hoặc sai chỗ: $(show)"
[ -n "$(at "    ✘ A40 cross mark")" ] && [ -n "$(at "      FAIL: plain")" ] && [ -n "$(at "    not ok 3 - tap")" ] \
  && [ -z "$(at "    ✔ D says FAIL in prose")" ] \
  && ok "a2 ✘ / FAIL / not ok ở đầu dòng được in; dòng ✔ nhắc FAIL giữa câu thì không" || fail "a2: $(show)"
[ "$(cnt "    ✖ A99 in tail")" = 1 ] && ok "a3 dòng hỏng đã nằm trong đuôi chỉ in một lần" || fail "a3 ✖ A99 in $(cnt "    ✖ A99 in tail") lần"
nm="$(grep -c '^    ✖ many ' "$TMP/a.out")"
[ "$nm" = 40 ] && [ -n "$(at "    … còn 5 dòng hỏng nữa")" ] && [ -z "$(at "    ✖ many 41")" ] \
  && ok "a4 45 dòng hỏng trước đuôi: in 40 rồi '… còn 5 dòng hỏng nữa'" || fail "a4 in $nm dòng ✖ many: $(show)"
g="$(at "✔ tests/verification/test_green.sh")"
nx="$(sed -n "$((${g:-0} + 1))p" "$TMP/a.out")"
[ -n "$g" ] && ! grep -q "fake but green" "$TMP/a.out" && case "$nx" in "✔ tests/"*|"✖ tests/"*) true ;; *) false ;; esac \
  && ok "a5 test xanh không in thêm dòng nào (kể cả dòng ✖ trong log của nó)" || fail "a5 sau ✔ test_green: '$nx'"
shown="$(grep -E '^(✔|✖) tests/' "$TMP/a.out" | sed 's/^[^ ]* //')"
[ "$RC" = 1 ] && [ "$shown" = "$(cd "$K" && ls tests/*/test_*.sh)" ] \
  && ok "a6 rc=1 và kết quả in đúng thứ tự danh sách" || fail "a6 rc=$RC, thứ tự: $(printf '%s' "$shown" | tr '\n' ' ')"

# --- b. bin/gate_full.py checks_fail (lần chạy lại khi chia đôi) --------------------------------------------------------------
S="$TMP/b"; mkdir -p "$S/kit/tests"
{ echo 'echo "✖ A33 early failure"'; lines "✔ c" 20; echo 'echo "failures: 1"'; echo 'exit 1'; } > "$S/kit/tests/red.sh"
{ echo 'echo "✖ fake but green"'; lines "✔ c" 20; } > "$S/kit/tests/green.sh"
python3 -I - "$DEVKIT_DIR/bin" "$S" > "$TMP/b.out" 2>&1 <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import gate_full as gf

class R:
    def __init__(self):
        self.buf = []

    def raw(self, text):
        self.buf.append(text)

s = sys.argv[2]
r, g = R(), R()
st = gf.checks_fail(r, s, [("t", "bash tests/red.sh", "kit")], 60)
sg = gf.checks_fail(g, s, [("g", "bash tests/green.sh", "kit")], 60)
txt, gtxt = "".join(r.buf), "".join(g.buf)
b1 = st == "bad" and "✖ A33 early failure" in txt and "failures: 1" in txt \
    and txt.index("✖ A33 early failure") < txt.index("failures: 1")
b2 = sg == "good" and "fake but green" not in gtxt and "✔ c 20" in gtxt
print("b1", "ok" if b1 else "bad", st, repr(txt[:600]))
print("b2", "ok" if b2 else "bad", sg, repr(gtxt[:300]))
PY
grep -q '^b1 ok' "$TMP/b.out" && ok "b1 chạy lại đỏ: log chia đôi có dòng ✖ A33 nằm trước 15 dòng cuối" || fail "b1: $(grep '^b1' "$TMP/b.out" || cat "$TMP/b.out")"
grep -q '^b2 ok' "$TMP/b.out" && ok "b2 chạy lại xanh: vẫn chỉ 15 dòng cuối" || fail "b2: $(grep '^b2' "$TMP/b.out" || cat "$TMP/b.out")"

# --- c. bin/post-fix-gate.py fail_lines / khối '| …' / --brief ------------------------------------------------------------
ORIGIN="$TMP/c/origin.git"; REPO="$TMP/c/repo"; mkdir -p "$TMP/c"
git init -q --bare -b main "$ORIGIN" && git clone -q "$ORIGIN" "$REPO" 2>/dev/null || exit 1
( cd "$REPO" && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  mkdir -p src templates .agents
  echo "def ok(): return 1" > src/core.py
  echo '{"profile":"backend"}' > .agents/active-profile.json
  printf '.agents/evidence/\n.agents/regression_checklist.md\n.agents/CHECKLIST.md\n.claude/\n' > .gitignore
  cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/core.py"],
 "mandatory_regression_tests":[{"id":"REG-DK-ALL-REST-01","name":"run_impacted giả: hai test đỏ","command":"bash fake.sh"},
  {"id":"REG-DK-DIRECT-01","name":"test chạy thẳng: chỉ ✘ / not ok, không có ✖","command":"bash fake2.sh"}]}]}
JSON
  # như run_impacted.sh in: test đỏ đầu có > 8 dòng hỏng, rồi test đỏ thứ hai
  { echo 'echo "✖ tests/verification/test_a.sh"'; echo 'echo "    ✔ says not ok in the middle"'; echo 'echo "    ✘ a-cross"'
    echo 'echo "    not ok 2 - a-tap"'; lines "    ✖ a" 8; echo 'echo "    failures: 10"'
    echo 'echo "✖ tests/verification/test_b.sh"'; echo 'echo "    ✖ b1"'; lines "    ✔ t" 6; echo 'exit 1'; } > fake.sh
  printf '%s\n' 'echo "✘ x-cross"' 'echo "not ok 1 - x-tap"' 'echo "failures: 1"' 'exit 1' > fake2.sh
  git add -A && git commit -qm init && git push -q origin main ) || exit 1
# flaky_retry để mặc định (bật): fake.sh < 120 s nên out = hai lần chạy nối nhau
CLAUDE_PROJECT_DIR="$REPO" python3 "$GATE" --no-checklist --run-tests --tree HEAD --no-cache --json > "$TMP/c.out" 2>&1
# --no-fail-fast: suite thứ hai (c7) chạy cả khi suite đầu đỏ; lượt --json ở trên để nó NOT_RUN (c1–c6 tra theo id)
CLAUDE_PROJECT_DIR="$REPO" python3 "$GATE" --no-checklist --run-tests --tree HEAD --no-cache --no-fail-fast --brief > "$TMP/c.brief" 2>&1
python3 -I - "$TMP/c.out" "$TMP/c.brief" > "$TMP/c.res" 2>&1 <<'PY'
import json, re, sys
ansi = re.compile(r"\x1b\[[0-9;]*m")
plain = ansi.sub("", open(sys.argv[1], encoding="utf-8", errors="replace").read())
brief = ansi.sub("", open(sys.argv[2], encoding="utf-8", errors="replace").read())
data = {}
for line in reversed(plain.splitlines()):
    if line.strip().startswith("{"):
        try:
            data = json.loads(line)
            break
        except ValueError:
            pass
tests = [t for t in data.get("regression_tests") or [] if t.get("id") == "REG-DK-ALL-REST-01"]
fl = tests[0].get("fail_lines") or [] if tests else []
A, B = "✖ tests/verification/test_a.sh", "✖ tests/verification/test_b.sh"
block = [l.strip() for l in plain.splitlines() if l.strip().startswith("| ")]
bblock = [l.strip() for l in brief.splitlines() if l.strip().startswith("| ")]
red_rows = [l for l in plain.splitlines() if re.match(r"^\s*\| ✖ tests/verification/test_b\.sh\s*$", l)]
# c7: khối của suite thứ hai trong --brief (từ dòng trạng thái của nó tới dòng kết luận)
blines = brief.splitlines()
i7 = next((i for i, l in enumerate(blines) if "REG-DK-DIRECT-01" in l and "[ ]" in l), None)
seg7 = []
for l in blines[i7 + 1:] if i7 is not None else []:
    if "KẾT LUẬN" in l or "VERDICT" in l or re.search(r"\[[ x]\] ", l):
        break
    seg7.append(l.strip())
res = {
    "c1": A in fl and B in fl and fl.count(B) == 1,
    "c2": len(red_rows) == 1,
    "c3": bool(fl) and fl[0] == A and len(fl) >= 8 and B not in fl[:8],
    "c4": "    ✘ a-cross" in fl and "    not ok 2 - a-tap" in fl and "|     ✘ a-cross" in block and "|     not ok 2 - a-tap" in block,
    "c5": "|     ✘ a-cross" in bblock and "|     not ok 2 - a-tap" in bblock and ("| " + B) in bblock,
    "c6": bool(fl) and not any("says not ok in the middle" in l for l in fl),
    "c7": any(l.startswith("Log:") for l in seg7) and "| ✘ x-cross" in seg7 and "| not ok 1 - x-tap" in seg7,
}
for k, v in res.items():
    print(k, "ok" if v else "bad")
print("fail_lines", json.dumps(fl, ensure_ascii=False))
print("brief_block", json.dumps(bblock, ensure_ascii=False))
print("brief_c7", json.dumps(seg7, ensure_ascii=False))
PY
res() { grep -q "^$1 ok" "$TMP/c.res"; }
info() { grep -E '^(fail_lines|brief_block|brief_c7)' "$TMP/c.res" | cut -c1-700 | tr '\n' ' '; [ -s "$TMP/c.res" ] || tail -n 5 "$TMP/c.out"; }
res c1 && ok "c1 fail_lines giữ cả ✖ test_a lẫn ✖ test_b (test_b đúng một lần dù flaky_retry nối hai lần chạy)" || fail "c1: $(info)"
res c2 && ok "c2 khối '| …' có đúng một dòng '| ✖ tests/verification/test_b.sh' (single_red_test đếm được 2 test)" || fail "c2: $(info)"
res c3 && ok "c3 phần đầu fail_lines vẫn là các dòng hỏng đầu tiên, bắt đầu bằng ✖ test_a" || fail "c3: $(info)"
res c4 && ok "c4 ✘ và 'not ok' đầu dòng vào fail_lines và khối '| …'" || fail "c4: $(info)"
res c5 && ok "c5 --brief giữ dòng ✘ / not ok và ✖ test_b" || fail "c5: $(info)"
res c6 && ok "c6 'not ok' giữa câu (dòng ✔) không bị coi là dòng hỏng" || fail "c6: $(info)"
res c7 && ok "c7 --brief giữ dòng Log: và khối '| ✘ / | not ok' của suite không có dòng ✖" || fail "c7: $(info)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_red_fail_lines: PASS"; exit 0; }
echo "test_red_fail_lines: FAIL ($FAILS)"
exit 1
