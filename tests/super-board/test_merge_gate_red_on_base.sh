#!/usr/bin/env bash
# Issue #251: verify đỏ vì suite đã đỏ SẴN trên origin/<base> (không phải lỗi của PR) không được REJECT PR (exit 11) làm kéo bounce +
# rebuild. Luật:
#   - gate REJECT (exit 1), lớp tĩnh "đạt", mọi dòng suite đỏ là FAIL/TIMEOUT có lệnh trong ma trận, và chạy lại từng suite trên
#     cây base (scratch reset về origin/<base>) cũng đỏ → "đỏ sẵn trên base": merge tiếp, mở thẻ bug riêng cho mỗi suite (không trùng).
#   - bất kỳ suite nào xanh trên base (lỗi do PR), suite không có trong ma trận, trạng thái lạ, lớp tĩnh có phát hiện → exit 11 như cũ.
#   - sau khi chạy base, scratch trả về đúng commit đã merge.
# Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
export SB_NOTIFY_SKIP=1
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-red-on-base-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/review-x"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n' > "$R/.gitignore"
mkdir -p "$R/.agents"
# REG-RED-BASE*: đỏ trên mọi cây; REG-PR-ONLY: đỏ chỉ khi cây có file f<n> do PR thêm.
cat > "$R/.agents/regression_matrix.active.json" <<'J'
[{"component":"x","watch_files":["*"],"mandatory_regression_tests":[
 {"id":"REG-RED-BASE","name":"always red","command":"false"},
 {"id":"REG-RED-BASE-2","name":"always red too","command":"exit 3"},
 {"id":"REG-PR-ONLY","name":"red with the PR file","command":"! ls f* >/dev/null 2>&1"}]}]
J
echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
git -C "$R" branch -q --no-track issue-5-x main
git -C "$R" worktree add -q "$WT" issue-5-x

mkpr() {
  local n="$1" h
  git -C "$R" branch -q --no-track "issue-$n-x" main
  git -C "$WT" checkout -q "issue-$n-x"
  echo "$n" > "$WT/f$n"; git -C "$WT" add "f$n"; git -C "$WT" commit -qm "card$n"
  git -C "$R" push -q origin "issue-$n-x"
  h=$(git -C "$R" rev-parse "issue-$n-x")
  git -C "$R" diff "$h~1" "$h" > "$TMP/pr$n.diff"
  printf '{"files":[{"path":"f%s"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' "$n" > "$TMP/pr$n.meta"
  echo "$h" > "$TMP/pr$n.head"
}

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
case " $* " in
  *" issue list "*) cat "$FAKE_DIR/existing-issues" 2>/dev/null || echo 0; exit 0 ;;
  *" issue create "*) echo "$*" >> "$FAKE_DIR/created"; echo "https://github.com/o/r/issues/900"; exit 0 ;;
  *" project item-add "*) echo "$*" >> "$FAKE_DIR/added"; exit 0 ;;
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
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0

E=$(printf '\033')
row() { printf '    %s[91m[ ] %s%s[0m | %s[1m%-15s%s[0m : %s\n' "$E" "$1" "$E" "$E" "$2" "$E" "$3"; }
reject() {
  printf '  %s[1mKẾT LUẬN CỔNG POST-FIX AUDIT:%s[0m %s[91mREJECT — CẦN KHẮC PHỤC CÁC ĐIỂM CHƯA ĐẠT%s[0m\n' "$E" "$E" "$E" "$E"
  printf '  • Lớp tĩnh (bí mật, lười biếng, dependency, hiệu năng, nuốt lỗi, log): %s\n' "$1"
}
{ row FAIL REG-RED-BASE "always red"; reject "đạt"; } > "$TMP/red-base.log"
{ row FAIL REG-RED-BASE "always red"; row FAIL REG-RED-BASE-2 "always red too"; reject "đạt"; } > "$TMP/red-base-two.log"
{ row TIMEOUT REG-RED-BASE "always red"; reject "đạt"; } > "$TMP/red-timeout.log"
{ row FAIL REG-NEW "suite added by the PR"; reject "đạt"; } > "$TMP/red-new.log"
{ row FAIL REG-PR-ONLY "red with the PR file"; reject "đạt"; } > "$TMP/red-pr.log"
{ row FAIL REG-RED-BASE "always red"; row FAIL REG-PR-ONLY "red with the PR file"; reject "đạt"; } > "$TMP/red-mixed.log"
{ row FAIL REG-NOT-IN-MATRIX "gone"; reject "đạt"; } > "$TMP/red-unknown.log"
{ row FAIL REG-RED-BASE "always red"; reject "CÓ PHÁT HIỆN"; } > "$TMP/red-static.log"
{ row UNTESTED REG-RED-BASE "always red"; reject "đạt"; } > "$TMP/red-untested.log"

run_case() {  # $1 = PR, $2 = log verify giả (exit 1)
  local n="$1" cfg="$TMP/cfg$1.json" script="$TMP/verify$1.sh"
  rm -f "$TMP/created" "$TMP/added"
  printf '#!/usr/bin/env bash\ncat %s\nexit 1\n' "$2" > "$script"
  VCMD="${3:-bash $script}"   # $3 = lệnh verify thay thế, $4 = lệnh verify thứ hai
  python3 -c 'import json,sys; print(json.dumps({"base_branch":"main","repo":{"path":".","remote":"https://github.com/o/r"},"project":{"owner":"o","number":1},"verify_commands":sys.argv[1:]}))' "$VCMD" ${4:+"$4"} > "$cfg"
  ( cd "$WT" && bash "$GATE" --config "$cfg" --pr "$n" --expect-head "$(cat "$TMP/pr$n.head")" ) >"$TMP/gate$n.log" 2>&1
  CASE_RC=$?
  CASE_CREATED=$(grep -c "issue create" "$TMP/created" 2>/dev/null || true); CASE_CREATED=${CASE_CREATED:-0}
}
why() { grep "merge-gate" "$TMP/gate$1.log" | tail -4; }

mkpr 31; run_case 31 "$TMP/red-base.log"
[ "$CASE_RC" -eq 0 ] && [ "$CASE_CREATED" -eq 1 ] && grep -q "red on origin/main" "$TMP/gate31.log" && grep -q "REG-RED-BASE" "$TMP/created" \
  && ok "suite red on base too: PR merged, one bug card filed (exit 0, issues=1)" \
  || fail "red on base (rc=$CASE_RC issues=$CASE_CREATED, want 0 and 1): $(why 31)"

mkpr 32; run_case 32 "$TMP/red-base-two.log"
[ "$CASE_RC" -eq 0 ] && [ "$CASE_CREATED" -eq 2 ] \
  && ok "two suites red on base: merged, one card each (exit 0, issues=2)" \
  || fail "two red on base (rc=$CASE_RC issues=$CASE_CREATED, want 0 and 2): $(why 32)"

mkpr 33; run_case 33 "$TMP/red-pr.log"
[ "$CASE_RC" -eq 11 ] && [ "$CASE_CREATED" -eq 0 ] \
  && ok "suite green on base (PR broke it): REJECT as before (exit 11, no card)" \
  || fail "red only on PR (rc=$CASE_RC issues=$CASE_CREATED, want 11 and 0): $(why 33)"

mkpr 34; run_case 34 "$TMP/red-mixed.log"
[ "$CASE_RC" -eq 11 ] && [ "$CASE_CREATED" -eq 0 ] \
  && ok "one red suite is the PR's own: whole verify stays red (exit 11, no card)" \
  || fail "mixed (rc=$CASE_RC issues=$CASE_CREATED, want 11 and 0): $(why 34)"

mkpr 35; run_case 35 "$TMP/red-unknown.log"
[ "$CASE_RC" -eq 11 ] && [ "$CASE_CREATED" -eq 0 ] \
  && ok "red suite with no matrix command: fail-closed (exit 11)" \
  || fail "unknown suite (rc=$CASE_RC issues=$CASE_CREATED, want 11 and 0): $(why 35)"

mkpr 36; run_case 36 "$TMP/red-static.log"
[ "$CASE_RC" -eq 11 ] && [ "$CASE_CREATED" -eq 0 ] \
  && ok "static findings: not classified red-on-base (exit 11)" \
  || fail "static findings (rc=$CASE_RC issues=$CASE_CREATED, want 11 and 0): $(why 36)"

mkpr 37; run_case 37 "$TMP/red-untested.log"
[ "$CASE_RC" -eq 11 ] && [ "$CASE_CREATED" -eq 0 ] \
  && ok "UNTESTED row: fail-closed (exit 11)" \
  || fail "UNTESTED (rc=$CASE_RC issues=$CASE_CREATED, want 11 and 0): $(why 37)"

# Thẻ đã có (cùng id suite, còn mở): không mở thẻ thứ hai, vẫn merge.
mkpr 38; echo 1 > "$TMP/existing-issues"; run_case 38 "$TMP/red-base.log"; rm -f "$TMP/existing-issues"
[ "$CASE_RC" -eq 0 ] && [ "$CASE_CREATED" -eq 0 ] \
  && ok "open card for that suite already exists: no duplicate, merged (exit 0, issues=0)" \
  || fail "duplicate card (rc=$CASE_RC issues=$CASE_CREATED, want 0 and 0): $(why 38)"

# --- review 22/10 (fail-open) ---
mkpr 39; run_case 39 "$TMP/red-timeout.log"
[ "$CASE_RC" -eq 11 ] && [ "$CASE_CREATED" -eq 0 ] \
  && ok "TIMEOUT row is never red-on-base (exit 11, no card)" \
  || fail "TIMEOUT row (rc=$CASE_RC issues=$CASE_CREATED, want 11 and 0): $(why 39)"

# PR thêm suite mới vào ma trận (lệnh chỉ có trong PR): base không có id đó → PR chịu.
mkpr_matrix() {
  local n="$1" h
  git -C "$R" branch -q --no-track "issue-$n-x" main
  git -C "$WT" checkout -q "issue-$n-x"
  python3 -c 'import json,sys; p=sys.argv[1]; m=json.load(open(p)); m[0]["mandatory_regression_tests"].append({"id":"REG-NEW","name":"added by the PR","command":"false"}); json.dump(m,open(p,"w"))' "$WT/.agents/regression_matrix.active.json"
  git -C "$WT" add -A; git -C "$WT" commit -qm "card$n"
  git -C "$R" push -q origin "issue-$n-x"
  h=$(git -C "$R" rev-parse "issue-$n-x")
  git -C "$R" diff "$h~1" "$h" > "$TMP/pr$n.diff"
  read -r adds dels _ < <(git -C "$R" diff --numstat "$h~1" "$h")
  printf '{"files":[{"path":".agents/regression_matrix.active.json"}],"labels":[],"body":"","additions":%s,"deletions":%s,"changedFiles":1}' "$adds" "$dels" > "$TMP/pr$n.meta"
  rm -f "$TMP/halt.json"
  echo "$h" > "$TMP/pr$n.head"
}
mkpr_matrix 40; run_case 40 "$TMP/red-new.log"
[ "$CASE_RC" -eq 11 ] && [ "$CASE_CREATED" -eq 0 ] \
  && ok "suite added by the PR (absent from base matrix): PR owns it (exit 11, no card)" \
  || fail "PR-added suite (rc=$CASE_RC issues=$CASE_CREATED, want 11 and 0): $(why 40)"

# Lệnh verify ghép: phần sau && / ; chưa chắc đã chạy hay đỏ vì PR → fail-closed.
mkpr 41; run_case 41 "$TMP/red-base.log" "bash $TMP/verify41.sh && true"
[ "$CASE_RC" -eq 11 ] && [ "$CASE_CREATED" -eq 0 ] \
  && ok "compound verify command (&&): never red-on-base (exit 11)" \
  || fail "compound && (rc=$CASE_RC issues=$CASE_CREATED, want 11 and 0): $(why 41)"
mkpr 42; run_case 42 "$TMP/red-base.log" "true; bash $TMP/verify42.sh"
[ "$CASE_RC" -eq 11 ] && [ "$CASE_CREATED" -eq 0 ] \
  && ok "compound verify command (;): never red-on-base (exit 11)" \
  || fail "compound ; (rc=$CASE_RC issues=$CASE_CREATED, want 11 and 0): $(why 42)"

# Sau khi chạy base, scratch phải về đúng commit đã merge (file của PR có lại, cây sạch) trước lệnh verify tiếp theo.
mkpr 43
printf '#!/usr/bin/env bash\ntest -f f43 && echo present > "%s/seen43"\ntest -z "$(git status --porcelain)" || echo dirty > "%s/dirty43"\nexit 0\n' "$TMP" "$TMP" > "$TMP/second43.sh"
rm -f "$TMP/seen43" "$TMP/dirty43"
run_case 43 "$TMP/red-base.log" "bash $TMP/verify43.sh" "bash $TMP/second43.sh"
[ "$CASE_RC" -eq 0 ] && [ -f "$TMP/seen43" ] && [ ! -f "$TMP/dirty43" ] \
  && ok "scratch restored to the merged commit (PR file back, tree clean) before the next verify command" \
  || fail "scratch not restored (rc=$CASE_RC): $(why 43)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_red_on_base: PASS"; exit 0; } || { echo "test_merge_gate_red_on_base: FAIL ($FAILS)"; exit 1; }
