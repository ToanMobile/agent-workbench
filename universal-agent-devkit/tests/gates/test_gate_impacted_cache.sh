#!/usr/bin/env bash
# Test hồi quy (#645, gộp vào #644): lượt KHÔNG cưỡng bức — lượt task `--run-tests` (impacted) và `--run-tests --scoped` — dùng lại PASS theo
# khoá nội dung (bin/suite_cache.py) cho suite ĐÃ ĐƯỢC CHỌN: một suite đỏ trong 38 thì sửa xong chỉ chạy lại suite đổi input.
#   a. impacted: 3 suite được chọn PASS; sửa input của REG-B ⇒ REG-A, REG-E dùng lại (0 lần chạy thật), REG-B chạy lại; biên nhận task ghi
#      mode "cached" cho suite dùng lại; a2 như vậy với DEVKIT_SLOT_PRIORITY=merge (INSTINCT-066: đổi thứ tự suite)
#   b. --scoped (--diff main, repo không có .agents/gate-core.txt ⇒ lõi mặc định, không leo full): như a; biên nhận scoped ghi mode cached
#   c. suite lần trước FAIL (cùng nội dung) ⇒ chạy lại
#   d. --no-cache ⇒ mọi suite đã chọn chạy
#   e. --scoped với danh sách DEVKIT_SCOPED_TESTS khác (thêm test kit vào diff) ⇒ REG-E (đọc env đó) phải chạy lại
#   f. lượt impacted không mở rộng cached-full: suite không được chọn (REG-B khi chỉ a.py đổi) không chạy, không có mặt
#   g. suite "cache": false vẫn chạy mỗi lượt
#   h. runner run_impacted.sh (phụ thuộc diff, có dấu --list) vẫn chạy mỗi lượt --scoped trên cùng nội dung, suite khác dùng lại
# Chưa có cache cho lượt không cưỡng bức thì a, a2, b ĐỎ. Python stdlib, tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_SUITE_CACHE_MAX_S DEVKIT_SUITE_CACHE DEVKIT_SENTINEL_MAX_S CI \
      DEVKIT_SLOT_PRIORITY DEVKIT_SCOPED_TESTS DEVKIT_IMPACTED_SINCE GATE_TOTAL_BUDGET_S DEVKIT_GATE_MERGE_CHECK \
      DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID WORKTREE_TRUNK_MODE

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"   # khoá slot riêng (không đụng gate thật của máy)
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
n()    { [ -f "$TMP/count.$1" ] && wc -l < "$TMP/count.$1" | tr -d ' ' || echo 0; }
snap() { echo "$(n A) $(n B) $(n E) $(n N) $(n K)"; }
# dlt <trước> <sau>: số lần chạy thật của A B E N K trong khoảng đó
dlt()  { python3 -c 'import sys; a, b = sys.argv[1].split(), sys.argv[2].split(); print(" ".join(str(int(y) - int(x)) for x, y in zip(a, b)))' "$1" "$2"; }

R="$TMP/repo"
mkdir -p "$R/src" "$R/tests" "$R/kit/tests" && cd "$R" || exit 2
git init -q -b main . && git config user.email t@t && git config user.name t
for x in a b e k; do echo "$x = 1" > "src/$x.py"; done
printf '#!/usr/bin/env bash\ngrep -q = src/a.py\n' > tests/test_a.sh
printf '#!/usr/bin/env bash\ngrep -q = src/b.py\n' > tests/test_b.sh
# REG-E đọc danh sách test của lượt --scoped (như run_impacted.sh): PASS của nó chỉ đúng với đúng danh sách đó
printf '#!/usr/bin/env bash\ngrep -q = src/e.py\necho "scoped=${DEVKIT_SCOPED_TESTS-unset}"\n' > tests/test_e.sh
printf '#!/usr/bin/env bash\ngrep -q = src/k.py\n' > kit/tests/test_k.sh
# runner kit giả (khớp _KIT_RUNNER và SELECTION_CMD, có dấu devkit-selection-list: như runner thật ⇒ suite_cache.selection_keyable): test của
# kit đi qua nó; lượt task / --scoped vẫn chạy nó mỗi lượt được chọn (ca h)
cat > kit/tests/run_impacted.sh <<SH
#!/usr/bin/env bash
# devkit-selection-list: --list in tập test chọn, không chạy gì
if [ "\${1-}" = --list ]; then echo tests/test_k.sh; exit 0; fi
echo run >> '$TMP/count.K'
exit 0
SH
printf '.claude/\n' > .gitignore
python3 - "$R/matrix.json" "$TMP" <<'PY'
import json, sys
path, tmp = sys.argv[1:]
c = lambda name: f"echo run >> '{tmp}/count.{name}'"
json.dump({"project": "t", "rules": [
    {"component": "A", "watch_files": ["src/a.py"],
     "mandatory_regression_tests": [{"id": "REG-A", "name": "a", "command": c("A") + "; bash tests/test_a.sh"},
                                    {"id": "REG-N", "name": "no cache", "command": c("N"), "cache": False}]},
    {"component": "B", "watch_files": ["src/b.py"],
     "mandatory_regression_tests": [{"id": "REG-B", "name": "b",
                                     "command": c("B") + f"; test ! -f '{tmp}/flagB' && bash tests/test_b.sh"}]},
    {"component": "E", "watch_files": ["src/e.py", "src/a.py"],
     "mandatory_regression_tests": [{"id": "REG-E", "name": "e", "command": c("E") + "; bash tests/test_e.sh"}]},
    {"component": "K", "watch_files": ["src/k.py"],
     "mandatory_regression_tests": [{"id": "REG-K", "name": "kit", "command": "bash kit/tests/run_impacted.sh"}]},
]}, open(path, "w"))
PY
git add -A && git commit -qm init
git checkout -q -b feat   # ngoài nhánh đích: lượt task ghi biên nhận task
echo 'a = 2' > src/a.py; echo 'b = 2' > src/b.py; echo 'e = 2' > src/e.py
git commit -qam change
GITDIR="$(git rev-parse --absolute-git-dir)"

# gate [cờ thêm...]: lượt task (không --full) trên main..cây; output $OUT, exit $RC
gate() { OUT="$(CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --run-tests --diff main --no-checklist "$@" 2>&1)"; RC=$?; }
# rcpt <file> <id>: "status/mode" của suite id trong biên nhận (task_pass.json / scoped_pass.json)
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

# ── tiền đề: lượt đầu chạy đủ A, B, E, N (K không được chọn: k.py không đổi)
gate; s="$(snap)"
if [ "$RC" = 0 ] && [ "$s" = "1 1 1 1 0" ]; then ok "tiền đề: lượt task đầu chạy REG-A/B/E/N một lần, PASS"
else fail "tiền đề: exit $RC, đếm A B E N K = $s (mong 1 1 1 1 0)"; printf '%s\n' "$OUT" | tail -25; exit 1; fi

# ── a. sửa input của REG-B ⇒ REG-A, REG-E dùng lại, REG-B chạy lại; REG-N (cache:false) vẫn chạy (g)
echo 'b = 3' > src/b.py
gate; s="$(snap)"
if [ "$RC" = 0 ] && [ "$s" = "1 2 1 2 0" ]; then ok "a. sửa b.py: REG-A, REG-E dùng lại (0 lần chạy), REG-B chạy lại"
else fail "a. exit $RC, đếm A B E N K = $s (mong 1 2 1 2 0)"; printf '%s\n' "$OUT" | grep -E "REG-|khoá|content" | tail -12; fi
printf '%s\n' "$OUT" | grep -q "khoá nội dung" && ok "a. log nói rõ suite dùng lại theo khoá nội dung" \
  || fail "a. log không nói suite nào dùng lại theo khoá nội dung"
[ "$(rcpt task_pass.json REG-A)" = "PASS/cached" ] && [ "$(rcpt task_pass.json REG-B)" = "PASS/full" ] \
  && ok "a. biên nhận task ghi REG-A PASS/cached, REG-B PASS/full" \
  || fail "a. biên nhận task: REG-A=$(rcpt task_pass.json REG-A) REG-B=$(rcpt task_pass.json REG-B) (mong PASS/cached, PASS/full)"
[ "$(n N)" = 2 ] && ok "g. suite cache:false chạy mỗi lượt" || fail "g. REG-N chạy $(n N) lần (mong 2)"

# ── a2. như a ở gate gộp (DEVKIT_SLOT_PRIORITY=merge đổi thứ tự suite): sửa a.py ⇒ REG-B dùng lại, A và E chạy lại
echo 'a = 3' > src/a.py
OUT="$(DEVKIT_SLOT_PRIORITY=merge CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --run-tests --diff main --no-checklist 2>&1)"; RC=$?
s="$(snap)"
if [ "$RC" = 0 ] && [ "$s" = "2 2 2 3 0" ]; then ok "a2. DEVKIT_SLOT_PRIORITY=merge, sửa a.py: REG-B dùng lại, REG-A/E chạy lại"
else fail "a2. exit $RC, đếm A B E N K = $s (mong 2 2 2 3 0)"; printf '%s\n' "$OUT" | grep -E "REG-" | tail -10; fi

# ── f. chỉ a.py đổi so với main ⇒ REG-B không được chọn: lượt impacted không mở rộng cached-full (REG-B không chạy, không có mặt)
git commit -qam "a3 b3"; git checkout -q main; git checkout -q -b feat2; echo 'a = 9' > src/a.py
before="$(snap)"
gate; s="$(dlt "$before" "$(snap)")"
if [ "$RC" = 0 ] && [ "$s" = "1 0 1 1 0" ] && ! printf '%s\n' "$OUT" | grep -q "REG-B"; then ok "f. suite không được chọn không vào lượt impacted"
else fail "f. exit $RC, số lần chạy A B E N K = $s (mong 1 0 1 1 0); REG-B có mặt: $(printf '%s\n' "$OUT" | grep -c REG-B)"; fi
git checkout -q -- src/a.py; git checkout -q feat

# ── d. --no-cache ⇒ mọi suite đã chọn chạy
before="$(snap)"
gate --no-cache; s="$(dlt "$before" "$(snap)")"
if [ "$RC" = 0 ] && [ "$s" = "1 1 1 1 0" ]; then ok "d. --no-cache: chạy đủ REG-A/B/E/N (nội dung đã PASS)"
else fail "d. exit $RC, số lần chạy A B E N K = $s (mong 1 1 1 1 0)"; fi

# ── c. REG-B FAIL trên nội dung mới; lượt sau cùng nội dung (cờ đỏ đã gỡ) ⇒ REG-B chạy lại, REG-A dùng lại
before="$(snap)"
echo 'b = 4' > src/b.py; : > "$TMP/flagB"
gate; r1=$RC; rm -f "$TMP/flagB"; mid="$(snap)"   # lượt đỏ có thể chạy lại REG-B một lần nữa (dò chập chờn)
gate; r2=$RC; s="$(dlt "$before" "$mid") / $(dlt "$mid" "$(snap)")"
if [ "$r1" = 1 ] && [ "$r2" = 0 ] && case "$s" in "0 "[12]" 0 1 0 / 0 1 0 1 0") true;; *) false;; esac; then ok "c. suite FAIL lần trước chạy lại (cùng nội dung), suite khác dùng lại"
else fail "c. exit $r1 $r2 (mong 1 0), số lần chạy A B E N K lượt đỏ / lượt sau = $s (mong 0 1|2 0 1 0 / 0 1 0 1 0)"; printf '%s\n' "$OUT" | grep -E "REG-" | tail -8; fi

# ── b. --scoped: lượt đầu chạy đủ (env DEVKIT_SCOPED_TESTS khác lượt impacted ⇒ khoá khác); sửa b.py ⇒ REG-A, REG-E dùng lại
before="$(snap)"
gate --scoped; s0="$(dlt "$before" "$(snap)")"; r0=$RC
before="$(snap)"
echo 'b = 5' > src/b.py
gate --scoped; s="$(dlt "$before" "$(snap)")"
if printf '%s\n' "$OUT" | grep -q -- "--scoped → full"; then fail "b. --scoped leo full: $(printf '%s\n' "$OUT" | grep -- '--scoped → full' | head -1)"
elif [ "$r0" = 0 ] && [ "$RC" = 0 ] && [ "$s0" = "1 1 1 1 0" ] && [ "$s" = "0 1 0 1 0" ]; then
  ok "b. --scoped: sửa b.py ⇒ REG-A, REG-E dùng lại, REG-B chạy lại"
else fail "b. exit $r0 $RC, số lần chạy $s0 rồi $s (mong 1 1 1 1 0 rồi 0 1 0 1 0)"; printf '%s\n' "$OUT" | grep -E "REG-|scoped" | tail -10; fi
# M2 (review): suite dùng lại theo khoá CHÍNH XÁC vào biên nhận scoped như biên nhận full: UNTESTED, label KEYED (mode vẫn cached)
[ "$(rcpt scoped_pass.json REG-A)" = "UNTESTED/cached" ] && ok "b. biên nhận scoped ghi REG-A UNTESTED/cached (KEYED, như biên nhận full)" \
  || fail "b. biên nhận scoped: REG-A=$(rcpt scoped_pass.json REG-A) (mong UNTESTED/cached)"

# ── e. thêm test kit vào diff (sửa k.py ⇒ kit/tests/test_k.sh được chọn ⇒ DEVKIT_SCOPED_TESTS khác): REG-E (input không đổi) chạy lại
before="$(snap)"
echo 'k = 2' > src/k.py
gate --scoped; s="$(dlt "$before" "$(snap)")"
if printf '%s\n' "$OUT" | grep -q -- "--scoped → full"; then fail "e. --scoped leo full: $(printf '%s\n' "$OUT" | grep -- '--scoped → full' | head -1)"
elif [ "$RC" = 0 ] && [ "$s" = "1 1 1 1 1" ]; then ok "e. DEVKIT_SCOPED_TESTS khác: REG-E không dùng lại PASS cũ (chạy lại)"
else fail "e. exit $RC, số lần chạy A B E N K = $s (mong 1 1 1 1 1: env nằm trong khoá của mọi suite)"; printf '%s\n' "$OUT" | grep -E "REG-|scoped" | tail -10; fi

# ── h. --scoped lần nữa trên cùng nội dung: REG-A/B/E dùng lại, runner REG-K (run_impacted.sh) và REG-N (cache:false) chạy như cũ
before="$(snap)"
gate --scoped; s="$(dlt "$before" "$(snap)")"
if [ "$RC" = 0 ] && [ "$s" = "0 0 0 1 1" ]; then ok "h. cùng nội dung: REG-A/B/E dùng lại, runner run_impacted.sh vẫn chạy"
else fail "h. exit $RC, số lần chạy A B E N K = $s (mong 0 0 0 1 1)"; printf '%s\n' "$OUT" | grep -E "REG-|scoped" | tail -10; fi

echo
[ "$FAILS" = 0 ] && { echo "PASS: test_gate_impacted_cache"; exit 0; }
echo "FAIL: test_gate_impacted_cache ($FAILS)"; exit 1
