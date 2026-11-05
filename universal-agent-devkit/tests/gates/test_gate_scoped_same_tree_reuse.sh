#!/usr/bin/env bash
# Test hồi quy (D1(a), đo 7 ngày tới 05/11: 90 882 suite-giây ở agent-workbench, 9 035 ở 5 app): lượt KHÔNG cưỡng bức chạy lại trên CÙNG CÂY
# sau một lượt đỏ phải chạy lại mọi suite đã PASS. 2 ngày cuối gần như toàn bộ là lượt kiểu Stop (GATE_TOTAL_BUDGET_S, regression_gate.sh):
# lượt đó không có sổ khoá (sc), còn budget_pass.json không ghi gì khi có suite FAIL. Lượt --scoped / task bỏ qua suite Gradle (PRECOMMIT_HEAVY).
# Sửa: PASS chạy thật của lượt không cưỡng bức CÓ suite FAIL / TIMEOUT ghi dưới khoá CÙNG CÂY (khoá cả cây của suite + lệnh + base + HEAD + ma trận), hạn
# DEVKIT_SAME_TREE_REUSE_MAX_S (mặc định 3600 s); chỉ lượt không cưỡng bức đọc nó, không bao giờ --full.
#   a. lượt kiểu Stop 1: REG-A, REG-G PASS, REG-B FAIL; lượt 2 cùng cây: chỉ REG-B chạy (A, G dùng lại) — ĐỎ trên code cũ
#   b. đổi 1 byte src/a.py (REG-A đọc nó) ⇒ REG-A chạy lại
#   c. --full ngay sau một lượt kiểu Stop đã ghi (cùng cây) ⇒ chạy REG-A, REG-G (không dùng PASS cùng cây, không rò vào khoá cả cây)
#   d. PASS quá hạn (DEVKIT_SAME_TREE_REUSE_MAX_S=1, chờ 2 s) ⇒ REG-A chạy lại (trong hạn: ca a)
#   e. --scoped 1: A PASS, B FAIL; --scoped 2 cùng cây: REG-A dùng lại (đã xanh trước, #645), REG-G (lệnh Gradle) dùng lại — ĐỎ trên code cũ
#   f. biên nhận: task ghi PASS/cached (như #645), scoped ghi UNTESTED/cached (không mang PASS hạn 1 h vào biên nhận 3 ngày)
# Python stdlib, bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_SUITE_CACHE_MAX_S DEVKIT_SUITE_CACHE DEVKIT_SENTINEL_MAX_S CI \
      DEVKIT_SLOT_PRIORITY DEVKIT_SCOPED_TESTS DEVKIT_IMPACTED_SINCE GATE_TOTAL_BUDGET_S DEVKIT_GATE_MERGE_CHECK \
      DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID WORKTREE_TRUNK_MODE DEVKIT_SAME_TREE_REUSE_MAX_S \
      DEVKIT_SAME_TREE_REUSE REGRESSION_GATE_BUDGET_S
export VACUITY_REVERT=0 FLAKY_RETRY=0 DEVKIT_SLOT_LOAD_MAX=100000

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"   # khoá slot riêng (không đụng gate thật của máy)
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
n()    { [ -f "$TMP/count.$1" ] && wc -l < "$TMP/count.$1" | tr -d ' ' || echo 0; }
snap() { echo "$(n A) $(n G) $(n B)"; }
dlt()  { python3 -c 'import sys; a, b = sys.argv[1].split(), sys.argv[2].split(); print(" ".join(str(int(y) - int(x)) for x, y in zip(a, b)))' "$1" "$2"; }

R="$TMP/repo"
mkdir -p "$R/src" "$R/tests" && cd "$R" || exit 2
git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
for x in a b g; do echo "$x = 1" > "src/$x.py"; done
printf '#!/usr/bin/env bash\ngrep -q = src/a.py\n' > tests/test_a.sh
printf '#!/usr/bin/env bash\ngrep -q = src/b.py\n' > tests/test_b.sh
printf '.claude/\n' > .gitignore
# Thứ tự A, G, B: lượt không --scoped dừng ở suite đỏ đầu (#647), nên B đỏ đứng cuối. REG-G mang chữ gradle (PRECOMMIT_HEAVY, lớp slot gradle) như
# suite Gradle của app: khối tính khoá #645 của post-fix-gate.py (task_keyed, điều kiện `not PRECOMMIT_HEAVY.search(...)`) bỏ qua nó.
python3 - "$R/matrix.json" "$TMP" <<'PY'
import json, sys
path, tmp = sys.argv[1:]
c = lambda name: f"echo run >> '{tmp}/count.{name}'"
json.dump({"project": "t", "rules": [
    {"component": "Core", "watch_files": ["src/*.py"],
     "mandatory_regression_tests": [
         {"id": "REG-A", "name": "a", "command": c("A") + "; bash tests/test_a.sh"},
         {"id": "REG-G", "name": "g", "command": c("G") + "; : gradle; grep -q = src/g.py"},
         {"id": "REG-B", "name": "b", "command": c("B") + f"; test ! -f '{tmp}/flagB' && bash tests/test_b.sh"}]}]}, open(path, "w"))
PY
git add -A && git commit -qm init
git checkout -q -b feat
for x in a b g; do echo "$x = 2" > "src/$x.py"; done
git commit -qam change
GITDIR="$(git rev-parse --absolute-git-dir)"

# stop [env...]: một lượt như Stop hook gọi (ngân sách thời gian, không --full); full / scoped: lượt --full / --scoped
stop()   { OUT="$(env GATE_TOTAL_BUDGET_S=900 "$@" CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --run-tests --diff main --no-checklist 2>&1)"; RC=$?; }
full()   { OUT="$(CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --run-tests --diff main --no-checklist --full 2>&1)"; RC=$?; }
scoped() { OUT="$(CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --run-tests --diff main --no-checklist --scoped 2>&1)"; RC=$?; }
show()   { printf '%s\n' "$OUT" | grep -E "REG-|cùng cây|khoá" | tail -12; }

# ── a. lượt kiểu Stop: A, G PASS, B FAIL; lượt 2 cùng cây chỉ chạy B
: > "$TMP/flagB"
b0="$(snap)"; stop; r1=$RC; b1="$(snap)"
stop; r2=$RC; s1="$(dlt "$b0" "$b1")"; s2="$(dlt "$b1" "$(snap)")"
if [ "$r1" = 1 ] && [ "$s1" = "1 1 1" ]; then ok "a. tiền đề: lượt 1 chạy A, G, B; B đỏ (exit 1)"
else fail "a. tiền đề: exit $r1, số lần chạy A G B = $s1 (mong 1 1 1)"; show; fi
if [ "$r2" = 1 ] && [ "$s2" = "0 0 1" ]; then ok "a. lượt 2 cùng cây: chỉ REG-B chạy, REG-A và REG-G dùng lại"
else fail "a. lượt 2: exit $r2, số lần chạy A G B = $s2 (mong 0 0 1: cùng cây, A và G vừa PASS)"; show; fi
printf '%s\n' "$OUT" | grep -q "cùng cây" && ok "a. log nói rõ suite dùng lại theo khoá cùng cây" || fail "a. log không nói dùng lại theo khoá cùng cây"
rm -f "$TMP/flagB"

# ── b. đổi 1 byte của file REG-A đọc ⇒ REG-A chạy lại (cây khác)
echo "a = 3" > src/a.py
b0="$(snap)"; stop; s="$(dlt "$b0" "$(snap)")"
if [ "$RC" = 0 ] && [ "$s" = "1 1 1" ]; then ok "b. đổi src/a.py: REG-A chạy lại (cả cây khác: mọi suite chạy)"
else fail "b. exit $RC, số lần chạy A G B = $s (mong 1 1 1)"; show; fi

# ── c. --full ngay sau lượt kiểu Stop đã ghi trên đúng cây này: không dùng PASS cùng cây, không rò sang khoá cả cây (3 ngày)
: > "$TMP/flagB"; stop; rm -f "$TMP/flagB"   # lượt đỏ: A, G ghi dưới khoá cùng cây
b0="$(snap)"; full; s="$(dlt "$b0" "$(snap)")"
if [ "$RC" = 0 ] && [ "$s" = "1 1 1" ]; then ok "c. --full sau lượt kiểu Stop cùng cây: chạy thật REG-A, REG-G, REG-B"
else fail "c. --full exit $RC, số lần chạy A G B = $s (mong 1 1 1: PASS cùng cây không bao giờ cho --full)"; show; fi

# ── d. hạn: quá DEVKIT_SAME_TREE_REUSE_MAX_S thì chạy lại (B đỏ ở cả hai lượt: không biên nhận / budget record nào khác giữ A, G; trong hạn = ca a)
echo "a = 4" > src/a.py
: > "$TMP/flagB"
stop
sleep 2
b0="$(snap)"; stop DEVKIT_SAME_TREE_REUSE_MAX_S=1; s="$(dlt "$b0" "$(snap)")"
rm -f "$TMP/flagB"
if [ "$s" = "1 1 1" ]; then ok "d. PASS cùng cây quá hạn (1 s): REG-A, REG-G chạy lại"
else fail "d. số lần chạy A G B = $s (mong 1 1 1: PASS quá hạn không dùng lại)"; show; fi

# ── e. --scoped: lượt 1 B đỏ, lượt 2 cùng cây chỉ B chạy (REG-A: đã xanh trước nhờ #645; REG-G lệnh Gradle: mới)
echo "a = 5" > src/a.py
: > "$TMP/flagB"
b0="$(snap)"; scoped; r1=$RC; b1="$(snap)"
scoped; r2=$RC; s1="$(dlt "$b0" "$b1")"; s2="$(dlt "$b1" "$(snap)")"
rm -f "$TMP/flagB"
if [ "$r1" = 1 ] && [ "$s1" = "1 1 1" ]; then ok "e. tiền đề: --scoped 1 chạy A, G, B; B đỏ"
else fail "e. tiền đề: exit $r1, số lần chạy A G B = $s1 (mong 1 1 1)"; show; fi
if [ "$r2" = 1 ] && [ "$s2" = "0 0 1" ]; then ok "e. --scoped 2 cùng cây: chỉ REG-B chạy, REG-A và REG-G (Gradle) dùng lại"
else fail "e. --scoped 2: exit $r2, số lần chạy A G B = $s2 (mong 0 0 1)"; show; fi

# rcpt <file> <id>: "status/mode" của suite id trong biên nhận
rcpt() { python3 - "$GITDIR/postfix-gate/$1" "$2" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    print("NO-RECEIPT"); sys.exit()
t = [x for x in d.get("tests") or [] if x.get("id") == sys.argv[2]]
print(f"{t[0].get('status')}/{t[0].get('mode')}" if t else "NO-SUITE")
PY
}
# ── f. biên nhận: task_pass.json (chỉ proof_gate.sh đọc, trong lượt) ghi suite dùng lại là PASS/cached như khoá chính xác #645
#    (test_gate_impacted_cache.sh ca a); scoped_pass.json (đọc lại tới 3 ngày) ghi UNTESTED/cached: PASS hạn 1 h không sống lâu hơn hạn
echo "a = 6" > src/a.py
: > "$TMP/flagB"; stop; rm -f "$TMP/flagB"   # A, G PASS (ghi dưới khoá cùng cây), B đỏ: không biên nhận nào
b0="$(snap)"; stop; s="$(dlt "$b0" "$(snap)")"   # A, G dùng lại theo khoá cùng cây, B PASS: exit 0 ghi biên nhận task
[ "$RC" = 0 ] && [ "$s" = "0 0 1" ] && ok "f. lượt Stop sau chỉ chạy B, exit 0" || { fail "f. exit $RC, số lần chạy A G B = $s (mong 0, 0 0 1)"; show; }
[ "$(rcpt task_pass.json REG-A)" = "PASS/cached" ] && ok "f. biên nhận task ghi REG-A PASS/cached (dùng lại, không phải PASS/full)" \
  || fail "f. biên nhận task: REG-A=$(rcpt task_pass.json REG-A) (mong PASS/cached)"
echo "a = 7" > src/a.py
: > "$TMP/flagB"; scoped; rm -f "$TMP/flagB"
b0="$(snap)"; scoped; s="$(dlt "$b0" "$(snap)")"
[ "$RC" = 0 ] && [ "$s" = "0 0 1" ] && ok "f. --scoped sau chỉ chạy B, exit 0" || { fail "f. --scoped exit $RC, số lần chạy A G B = $s (mong 0, 0 0 1)"; show; }
[ "$(rcpt scoped_pass.json REG-G)" = "UNTESTED/cached" ] && ok "f. biên nhận scoped ghi REG-G (PASS cùng cây) UNTESTED/cached" \
  || fail "f. biên nhận scoped: REG-G=$(rcpt scoped_pass.json REG-G) (mong UNTESTED/cached: PASS hạn 1 h không vào biên nhận 3 ngày)"

echo
[ "$FAILS" = 0 ] && { echo "PASS: test_gate_scoped_same_tree_reuse"; exit 0; }
echo "FAIL: test_gate_scoped_same_tree_reuse ($FAILS)"; exit 1
