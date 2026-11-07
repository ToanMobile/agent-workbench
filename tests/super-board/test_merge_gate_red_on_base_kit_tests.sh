#!/usr/bin/env bash
# Test hồi quy (gate speed v26 mục 5a): suite runner kit (REG-DK-ALL-KIT-01, `bash universal-agent-devkit/tests/run_impacted.sh`) đỏ ở merge gate
# thì red-on-base chạy RIÊNG từng test `| ✖ tests/x.sh` của log trên base, không chạy lại lệnh runner (tập test khác, kèm test consistency).
#   k1  test đỏ cả trên base: dung thứ, merge, mở thẻ (exit 0)
#   k2  test đỏ trong log nhưng xanh trên base (runner trên base đỏ vì lý do khác): PR làm hỏng, exit 11
#   k3  danh sách có thể bị cắt (40 dòng ✖): fail closed, exit 11
#   k4  test không có trên base (PR mới thêm): bash 127, không dung thứ, exit 11
#   k5  suite runner đỏ mà log không có dòng ✖ nào: exit 11
#   k6  dòng ✖ không phải đường dẫn test (kit biến mất): exit 11
#   k7  hai test, một đỏ một xanh trên base: exit 11
set -u
export LC_ALL=C LANG=C
export SB_NOTIFY_SKIP=1
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-red-on-base-kit.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/review-x"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n' > "$R/.gitignore"
K="$R/universal-agent-devkit/tests"
mkdir -p "$R/.agents" "$K/gates"
# runner trên base luôn đỏ (giả lập test consistency đỏ sẵn): lệnh runner trên base không chứng minh được gì về test của PR
printf 'exit 1\n' > "$K/run_impacted.sh"
printf 'exit 1\n' > "$K/gates/test_red.sh"
printf 'exit 1\n' > "$K/gates/test_red2.sh"
printf 'exit 0\n' > "$K/gates/test_green.sh"
cat > "$R/.agents/regression_matrix.active.json" <<'J'
[{"component":"kit","watch_files":["*"],"mandatory_regression_tests":[
 {"id":"REG-DK-ALL-KIT-01","name":"kit tests","command":"bash universal-agent-devkit/tests/run_impacted.sh","parallel_safe":true}]}]
J
git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
git -C "$R" branch -q --no-track issue-5-x main
git -C "$R" worktree add -q "$WT" issue-5-x

mkpr() {
  local n="$1" h
  git -C "$R" branch -q --no-track "issue-$n-x" main
  git -C "$WT" checkout -q "issue-$n-x"
  echo "$n" > "$WT/f$n"
  git -C "$WT" add -A; git -C "$WT" commit -qm "card$n"
  git -C "$R" push -q origin "issue-$n-x"
  h=$(git -C "$R" rev-parse "issue-$n-x")
  git -C "$R" diff "$h~1" "$h" > "$TMP/pr$n.diff"
  printf '{"files":[{"path":"f%s"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' "$n" > "$TMP/pr$n.meta"
  rm -f "$TMP/halt.json"; echo "$h" > "$TMP/pr$n.head"
}

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
case " $* " in
  *" issue list "*) echo 0; exit 0 ;;
  *" issue create "*) echo "$*" >> "$FAKE_DIR/created"; echo "https://github.com/o/r/issues/900"; exit 0 ;;
  *" project item-add "*) exit 0 ;;
esac
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr merge "*) echo "merged #$n" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
. "$ROOT/tests/super-board/lib/fake_ci_checks.sh"; sb_ci_checks_fixture "$TMP/bin"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0

E=$(printf '\033')
row() { printf '    %s[91m[ ] %s%s[0m | %s[1m%-15s%s[0m : %s\n' "$E" "$1" "$E" "$E" "$2" "$E" "$3"; }
tline() { printf '           %s[2m| %s%s[0m\n' "$E" "$1" "$E"; }
reject() {
  printf '  %s[1mKẾT LUẬN CỔNG POST-FIX AUDIT:%s[0m %s[91mREJECT — CẦN KHẮC PHỤC CÁC ĐIỂM CHƯA ĐẠT%s[0m\n' "$E" "$E" "$E" "$E"
  printf '  • Lớp tĩnh (bí mật, lười biếng, dependency, hiệu năng, nuốt lỗi, log): đạt\n'
}
kit() { row FAIL REG-DK-ALL-KIT-01 "kit tests"; tline "Lệnh chạy: bash universal-agent-devkit/tests/run_impacted.sh"; for l in "$@"; do tline "$l"; done; }
{ kit "✖ tests/gates/test_red.sh" "    ✖ A1 nested sub-case" "failures: 1"; reject; } > "$TMP/k1.log"
{ kit "✖ tests/gates/test_green.sh"; reject; } > "$TMP/k2.log"
{ row FAIL REG-DK-ALL-KIT-01 "kit tests"; i=0; while [ "$i" -lt 40 ]; do tline "✖ tests/gates/test_red_$i.sh"; i=$((i + 1)); done; reject; } > "$TMP/k3.log"
{ kit "✖ tests/gates/test_absent.sh"; reject; } > "$TMP/k4.log"
{ kit "failures: 1"; reject; } > "$TMP/k5.log"
{ kit "✖ run_impacted.sh: thư mục kit universal-agent-devkit biến mất giữa lượt"; reject; } > "$TMP/k6.log"
{ kit "✖ tests/gates/test_red.sh" "✖ tests/gates/test_green.sh"; reject; } > "$TMP/k7.log"
echo '{"exit_code":1,"matrix_problem":"","regression_tests":[{"id":"REG-DK-ALL-KIT-01","status":"FAIL"}],"unreadable":[],"tests_touched":[],"uncovered":[],"orphan_tests":[],"busy":false,"budget_exhausted":false}' > "$TMP/clean.json"

run_case() {  # $1 = PR, $2 = log verify giả (exit 1)
  local n="$1" cfg="$TMP/cfg$1.json" script
  rm -f "$TMP/created"
  mkdir -p "$TMP/g$n"; script="$TMP/g$n/post-fix-gate.py"
  cat > "$script" <<PY
import sys
sys.stdout.write(open("$2").read())
if "--json" in sys.argv:
    sys.stdout.write(open("$TMP/clean.json").read())
sys.exit(1)
PY
  python3 -c 'import json,sys; print(json.dumps({"base_branch":"main","repo":{"path":".","remote":"https://github.com/o/r"},"project":{"owner":"o","number":1},"verify_commands":sys.argv[1:]}))' "python3 $script" > "$cfg"
  ( cd "$WT" && bash "$GATE" --config "$cfg" --pr "$n" --expect-head "$(cat "$TMP/pr$n.head")" ) >"$TMP/gate$n.log" 2>&1
  CASE_RC=$?
  CASE_CREATED=$(grep -c "issue create" "$TMP/created" 2>/dev/null || true); CASE_CREATED=${CASE_CREATED:-0}
}
why() { grep "merge-gate" "$TMP/gate$1.log" | tail -4; }

mkpr 41; run_case 41 "$TMP/k1.log"
[ "$CASE_RC" -eq 0 ] && [ "$CASE_CREATED" -eq 1 ] && ok "k1. test đỏ cả trên base: merge, một thẻ" || fail "k1. rc=$CASE_RC issues=$CASE_CREATED: $(why 41)"
mkpr 42; run_case 42 "$TMP/k2.log"
[ "$CASE_RC" -eq 11 ] && [ "$CASE_CREATED" -eq 0 ] && ok "k2. test xanh trên base (runner base đỏ vì lý do khác): PR chịu, exit 11" || fail "k2. rc=$CASE_RC issues=$CASE_CREATED: $(why 42)"
mkpr 43; run_case 43 "$TMP/k3.log"
[ "$CASE_RC" -eq 11 ] && ok "k3. 40 dòng ✖ (có thể bị cắt): fail closed" || fail "k3. rc=$CASE_RC: $(why 43)"
mkpr 44; run_case 44 "$TMP/k4.log"
[ "$CASE_RC" -eq 11 ] && ok "k4. test không có trên base: không dung thứ" || fail "k4. rc=$CASE_RC: $(why 44)"
mkpr 45; run_case 45 "$TMP/k5.log"
[ "$CASE_RC" -eq 11 ] && ok "k5. runner đỏ không có dòng ✖: fail closed" || fail "k5. rc=$CASE_RC: $(why 45)"
mkpr 46; run_case 46 "$TMP/k6.log"
[ "$CASE_RC" -eq 11 ] && ok "k6. dòng ✖ không phải đường dẫn test: fail closed" || fail "k6. rc=$CASE_RC: $(why 46)"
mkpr 47; run_case 47 "$TMP/k7.log"
[ "$CASE_RC" -eq 11 ] && ok "k7. một test xanh trên base: exit 11" || fail "k7. rc=$CASE_RC: $(why 47)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_red_on_base_kit_tests: PASS"; exit 0; } || { echo "test_merge_gate_red_on_base_kit_tests: FAIL ($FAILS)"; exit 1; }
