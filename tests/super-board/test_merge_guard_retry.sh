#!/usr/bin/env bash
# Test hồi quy (gate speed v26 mục 7): verify đỏ CHỈ ở guard của điểm gộp ([merge-guard] trong .agents/gate-core.txt CỦA BASE) ⇒ merge gate
# chạy lại mỗi guard đỏ đúng một lần bằng lệnh ma trận; chỉ guard vẫn đỏ mới làm lượt đỏ; đỏ rồi xanh ⇒ comment PR.
#   m1  guard đỏ, chạy lại xanh: merge (exit 0), một comment PR, không biên nhận cây
#   m2  guard đỏ cả lần chạy lại: exit 11
#   m3  guard đỏ cùng một suite thường: không chạy lại, exit 11
#   m4  id chỉ là guard ở cây PR, không ở base: không chạy lại, exit 11
#   m5  JSON có điều kiện bị REJECT che (test sửa chưa duyệt): không chạy lại, exit 11
#   m6  sb_merge_guard_red_ids: dòng TIMEOUT không phải đỏ chạy lại được
#   m8  gate_masked_conditions_clean ở verify-flags.sh (merge gate và train cùng dùng): JSON sạch 0, có điều kiện bị che 1
#   m7  lệnh verify ghép (`post-fix-gate.py … && npm test`): không chạy lại guard (lệnh sau && chưa chạy), exit 11
set -u
export LC_ALL=C LANG=C
export SB_NOTIFY_SKIP=1
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-merge-guard-retry.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/review-x"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n' > "$R/.gitignore"
mkdir -p "$R/.agents"
# guard: đỏ khi có cờ guard.red VÀ cây có file f* của PR; cây base của fixture không có f* nên lệnh này xanh ở đó (ca m2 dựa vào điều này)
GCMD="echo x >> $TMP/guard.count; ! { [ -f $TMP/guard.red ] && ls f* >/dev/null 2>&1; }"
python3 - "$R/.agents/regression_matrix.active.json" "$GCMD" <<'PY'
import json, sys
json.dump([{"component": "g", "watch_files": ["*"], "mandatory_regression_tests": [
    {"id": "REG-G1", "name": "guard", "command": sys.argv[2]},
    {"id": "REG-G2", "name": "guard of the PR only", "command": sys.argv[2]},
    {"id": "REG-PR-ONLY", "name": "red with the PR file", "command": "! ls f* >/dev/null 2>&1"}]}], open(sys.argv[1], "w"))
PY
printf '[core]\n.agents/gate-core.txt\n\n[merge-guard]\nREG-G1\n' > "$R/.agents/gate-core.txt"
echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
git -C "$R" branch -q --no-track issue-5-x main
git -C "$R" worktree add -q "$WT" issue-5-x

mkpr() {   # PR thêm f<n>; cây PR liệt kê thêm REG-G2 là guard (base không có)
  local n="$1" h
  git -C "$R" branch -q --no-track "issue-$n-x" main
  git -C "$WT" checkout -q "issue-$n-x"
  echo "$n" > "$WT/f$n"; echo REG-G2 >> "$WT/.agents/gate-core.txt"
  git -C "$WT" add -A; git -C "$WT" commit -qm "card$n"
  git -C "$R" push -q origin "issue-$n-x"
  h=$(git -C "$R" rev-parse "issue-$n-x")
  git -C "$R" diff "$h~1" "$h" > "$TMP/pr$n.diff"
  printf '{"files":[{"path":"f%s"},{"path":".agents/gate-core.txt"}],"labels":[],"body":"","additions":2,"deletions":0,"changedFiles":2}' "$n" > "$TMP/pr$n.meta"
  rm -f "$TMP/halt.json"; echo "$h" > "$TMP/pr$n.head"
}

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
case " $* " in
  *" issue list "*) echo 0; exit 0 ;;
  *" issue create "*) echo "$*" >> "$FAKE_DIR/created"; echo "https://github.com/o/r/issues/900"; exit 0 ;;
  *" project item-add "*) exit 0 ;;
  *" pr comment "*) echo "$*" >> "$FAKE_DIR/commented"; exit 0 ;;
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
reject() {
  printf '  %s[1mKẾT LUẬN CỔNG POST-FIX AUDIT:%s[0m %s[91mREJECT — CẦN KHẮC PHỤC CÁC ĐIỂM CHƯA ĐẠT%s[0m\n' "$E" "$E" "$E" "$E"
  printf '  • Lớp tĩnh (bí mật, lười biếng, dependency, hiệu năng, nuốt lỗi, log): đạt\n'
}
{ row FAIL REG-G1 guard; reject; } > "$TMP/g1.log"
{ row FAIL REG-G1 guard; row FAIL REG-PR-ONLY "red with the PR file"; reject; } > "$TMP/mixed.log"
{ row FAIL REG-G2 "guard of the PR only"; reject; } > "$TMP/g2.log"
{ row TIMEOUT REG-G1 guard; reject; } > "$TMP/timeout.log"
J='"regression_tests":[{"id":"REG-G1","status":"FAIL"}],"unreadable":[],"uncovered":[],"orphan_tests":[],"busy":false,"budget_exhausted":false'
echo "{\"exit_code\":1,\"matrix_problem\":\"\",\"tests_touched\":[],$J}" > "$TMP/clean.json"
echo "{\"exit_code\":1,\"matrix_problem\":\"\",\"tests_touched\":[\"tests/t.sh\"],$J}" > "$TMP/masked.json"

run_case() {  # $1 = PR, $2 = log verify giả (exit 1), $3 = JSON, $4 = phần nối sau lệnh post-fix-gate (lệnh ghép)
  local n="$1" cfg="$TMP/cfg$1.json" script
  rm -f "$TMP/created" "$TMP/commented"
  mkdir -p "$TMP/g$n"; script="$TMP/g$n/post-fix-gate.py"
  cat > "$script" <<PY
import sys
sys.stdout.write(open("$2").read())
if "--json" in sys.argv:
    sys.stdout.write(open("${3:-$TMP/clean.json}").read())
sys.exit(1)
PY
  python3 -c 'import json,sys; print(json.dumps({"base_branch":"main","repo":{"path":".","remote":"https://github.com/o/r"},"project":{"owner":"o","number":1},"verify_commands":sys.argv[1:]}))' "python3 $script${4:+ $4}" > "$cfg"
  ( cd "$WT" && bash "$GATE" --config "$cfg" --pr "$n" --expect-head "$(cat "$TMP/pr$n.head")" ) >"$TMP/gate$n.log" 2>&1
  CASE_RC=$?
  RERUNS=$(grep -c "re-running it once" "$TMP/gate$n.log" 2>/dev/null || true); RERUNS=${RERUNS:-0}
  COMMENTS=$(grep -c "merge-guard" "$TMP/commented" 2>/dev/null || true); COMMENTS=${COMMENTS:-0}
}
why() { grep "merge-gate" "$TMP/gate$1.log" | tail -4; }

rm -f "$TMP/guard.red"
mkpr 51; run_case 51 "$TMP/g1.log"
[ "$CASE_RC" -eq 0 ] && [ "$RERUNS" -eq 1 ] && [ "$COMMENTS" -eq 1 ] && ok "m1. guard xanh khi chạy lại: merge, một comment" || fail "m1. rc=$CASE_RC reruns=$RERUNS comments=$COMMENTS: $(why 51)"
[ -z "$(ls "$R/.git/super-board/verified-trees" 2>/dev/null)" ] && ok "m1. không ghi biên nhận cây" || fail "m1. còn biên nhận cây"
touch "$TMP/guard.red"
mkpr 52; run_case 52 "$TMP/g1.log"
[ "$CASE_RC" -eq 11 ] && [ "$RERUNS" -eq 1 ] && [ "$COMMENTS" -eq 0 ] && ok "m2. guard đỏ cả lần chạy lại: exit 11" || fail "m2. rc=$CASE_RC reruns=$RERUNS comments=$COMMENTS: $(why 52)"
rm -f "$TMP/guard.red"
mkpr 53; run_case 53 "$TMP/mixed.log"
[ "$CASE_RC" -eq 11 ] && [ "$RERUNS" -eq 0 ] && ok "m3. guard + suite thường đỏ: không chạy lại, exit 11" || fail "m3. rc=$CASE_RC reruns=$RERUNS: $(why 53)"
mkpr 54; run_case 54 "$TMP/g2.log"
[ "$CASE_RC" -eq 11 ] && [ "$RERUNS" -eq 0 ] && ok "m4. guard chỉ ở cây PR: không chạy lại, exit 11" || fail "m4. rc=$CASE_RC reruns=$RERUNS: $(why 54)"
mkpr 55; run_case 55 "$TMP/g1.log" "$TMP/masked.json"
[ "$CASE_RC" -eq 11 ] && [ "$RERUNS" -eq 0 ] && ok "m5. điều kiện bị REJECT che: không chạy lại, exit 11" || fail "m5. rc=$CASE_RC reruns=$RERUNS: $(why 55)"

rm -f "$TMP/npm.ran"
mkpr 56; run_case 56 "$TMP/g1.log" "" "&& echo ran >> $TMP/npm.ran"
[ "$CASE_RC" -eq 11 ] && [ "$RERUNS" -eq 0 ] && [ ! -f "$TMP/npm.ran" ] && ok "m7. lệnh verify ghép: không chạy lại guard, exit 11" || fail "m7. rc=$CASE_RC reruns=$RERUNS: $(why 56)"

# m6
cp "$TMP/clean.json" "$TMP/t.json"; cat "$TMP/timeout.log" "$TMP/t.json" > "$TMP/timeout.full"
M6=$(cd "$WT" && HERE="$ROOT/.claude/bin" bash -c '. "$1/super-board-verify-flags.sh"; sb_merge_guard_red_ids "$2" "$3" main "python3 post-fix-gate.py --diff origin/main --scoped" && echo HIT || echo MISS' _ "$ROOT/.claude/bin" "$TMP/timeout.full" "$WT")
[ "$M6" = MISS ] && ok "m6. TIMEOUT không vào đường chạy lại guard" || fail "m6. $M6"

# m8
M8=$(bash -c '. "$1/super-board-verify-flags.sh"; gate_masked_conditions_clean "$2"; a=$?; gate_masked_conditions_clean "$3"; echo "$a $?"' _ \
  "$ROOT/.claude/bin" "$TMP/clean.json" "$TMP/masked.json" 2>&1)
[ "$M8" = "0 1" ] && ok "m8. gate_masked_conditions_clean dùng chung từ verify-flags.sh" || fail "m8. $M8"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_guard_retry: PASS"; exit 0; } || { echo "test_merge_guard_retry: FAIL ($FAILS)"; exit 1; }
