#!/usr/bin/env bash
# #559: REG-DK-ALL-01 không PASS thì merge gate giữ worktree gộp tạm (git worktree move),
# kèm log test đỏ và env.txt đã che secret. PASS thì dọn như cũ. Tối đa 2 bản giữ.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
RI="$ROOT/universal-agent-devkit/tests/run_impacted.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-keep-scratch.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
MINI="$TMP/mini"
mkdir -p "$MINI/tests/verification" "$MINI/bin"
cp "$RI" "$MINI/tests/run_impacted.sh"
: > "$MINI/tests/impact_map.txt"
printf '#!/bin/sh\nexit 0\n' > "$MINI/tests/verification/test_repo_consistency.sh"
printf '#!/bin/sh\necho stdout-red\necho stderr-red >&2\nexit 1\n' > "$MINI/tests/verification/test_red.sh"
chmod +x "$MINI/tests/verification/"*.sh
git init -q -b main "$MINI"
git -C "$MINI" config user.email t@example.invalid
git -C "$MINI" config user.name t
git -C "$MINI" add tests/run_impacted.sh tests/impact_map.txt tests/verification/test_repo_consistency.sh
git -C "$MINI" commit -qm init
# test_red.sh để untracked: run_impacted chọn đúng bài đó, không chạy suite của repo thật.

DEST="$TMP/direct-evidence"
mkdir -p "$DEST"
DEVKIT_KEEP_FAILED_LOGS_DIR="$DEST" DEVKIT_TEST_JOBS=1 bash "$MINI/tests/run_impacted.sh" >"$TMP/ri.out" 2>&1 || true
REDLOG="$DEST/tests_verification_test_red.sh.log"
PASSLOG="$DEST/tests_verification_test_repo_consistency.sh.log"
[ -f "$REDLOG" ] && grep -q stdout-red "$REDLOG" && grep -q stderr-red "$REDLOG" && [ -f "$DEST/tests_verification_test_red.sh.rc" ] \
  && [ "$(cat "$DEST/tests_verification_test_red.sh.rc")" != 0 ] && [ ! -f "$PASSLOG" ] \
  && ok "run_impacted copies the red test log and rc before deleting dk-run" \
  || fail "run_impacted did not keep the red log (dest=$(ls "$DEST" 2>/dev/null | tr '\n' ' ') out=$(tail -5 "$TMP/ri.out"))"

# ── merge gate ──────────────────────────────────────────────────────────
O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/deploy-x"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n' > "$R/.gitignore"
mkdir -p "$R/.claude/super-board/configs" "$R/.claude/worktrees/leave-me"
echo 'do not delete' > "$R/.claude/worktrees/leave-me/marker"
echo '{}' > "$R/.claude/super-board/configs/x.json"
echo a > "$R/a"
git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
git -C "$R" branch -q --no-track issue-5-x main
git -C "$R" worktree add -q "$WT" issue-5-x
echo b > "$WT/b"; git -C "$WT" add b; git -C "$WT" commit -qm card
git -C "$R" push -q origin issue-5-x
H=$(git -C "$R" rev-parse issue-5-x)
git -C "$R" diff origin/main issue-5-x > "$TMP/pr5.diff"
printf '{"files":[{"path":"b"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' > "$TMP/pr5.meta"
echo "$H" > "$TMP/pr5.head"

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr comment "*) printf '%s\n' "$*" >> "$FAKE_DIR/comments"; exit 0 ;;
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr merge "*) echo "fake gh: must not merge on a red verify" >&2; exit 1 ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
. "$ROOT/tests/super-board/lib/fake_review_fanout.sh"; sb_review_fixture "$TMP/bin"   # signed review PASS + CI checks (new gate preconditions)
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0
unset GH_TOKEN
export GH_TOKEN=secret-xyz SB_KEEP_MARK=visible-mark

cat > "$TMP/verify-red.sh" <<SH
#!/usr/bin/env bash
export DEVKIT_TEST_JOBS=1
bash "$MINI/tests/run_impacted.sh" >"$TMP/ri-gate.out" 2>&1 || true
printf '%s\n' '[ ] FAIL | REG-DK-ALL-01 | devkit'
exit 1
SH
cat > "$TMP/verify-pass.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '[ ] PASS | REG-DK-ALL-01 | devkit'
exit 0
SH
chmod +x "$TMP/verify-red.sh" "$TMP/verify-pass.sh"
# Đường dẫn trong JSON: escape cho jq không cần vì ta ghi thẳng.
python3 - "$TMP/cfg-red.json" "$TMP/verify-red.sh" <<'PY'
import json, sys
json.dump({"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":[sys.argv[2]]}, open(sys.argv[1],"w"))
PY
python3 - "$TMP/cfg-pass.json" "$TMP/verify-pass.sh" <<'PY'
import json, sys
json.dump({"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":[sys.argv[2]]}, open(sys.argv[1],"w"))
PY

keeps() { find "$R/.claude/worktrees" -mindepth 1 -maxdepth 1 -type d -name '.merge-scratch-keep-pr*' | sort; }
run_gate() {
  ( cd "$WT" && TMPDIR="$TMP/tt" GH_TOKEN=secret-xyz SB_KEEP_MARK=visible-mark \
      bash "$GATE" --config "$1" --pr 5 --expect-head "$H" --lock-timeout 20 $2 ) >"$TMP/gate.log" 2>&1
}

mkdir -p "$TMP/tt"
run_gate "$TMP/cfg-red.json" ""
rc=$?
mapfile_keeps=$(keeps)
nkeep=$(printf '%s\n' "$mapfile_keeps" | grep -c . || true)
one=$(printf '%s\n' "$mapfile_keeps" | head -1)
ev=""
[ -n "$one" ] && ev=$(find "$one/.merge-evidence/tests" -name 'tests_verification_test_red.sh.log' 2>/dev/null | head -1)
[ "$rc" -eq 11 ] && [ "$nkeep" = 1 ] && [ -n "$ev" ] && grep -q stdout-red "$ev" && grep -q stderr-red "$ev" \
  && [ -f "$one/.merge-evidence/env.txt" ] \
  && ok "AC1 red REG-DK-ALL-01 keeps one scratch with the red log and env.txt" \
  || fail "AC1 keep wrong rc=$rc nkeep=$nkeep ev=$ev log=$(tail -8 "$TMP/gate.log")"
if [ -n "$one" ] && [ -f "$one/.merge-evidence/env.txt" ]; then
  ! grep -q secret-xyz "$one/.merge-evidence/env.txt" && grep -q 'GH_TOKEN=<masked>' "$one/.merge-evidence/env.txt" \
    && grep -q 'SB_KEEP_MARK=visible-mark' "$one/.merge-evidence/env.txt" \
    && grep -q '^python3=Python ' "$one/.merge-evidence/env.txt" \
    && ok "AC2 env.txt masks GH_TOKEN and keeps a normal variable" \
    || fail "AC2 env.txt leaked or dropped a field: $(grep -E 'GH_TOKEN|SB_KEEP_MARK|python3=' "$one/.merge-evidence/env.txt")"
else
  fail "AC2 no env.txt"
fi
[ -n "$one" ] && git -C "$R" worktree list | grep -F "$(basename "$one")" >/dev/null \
  && ok "AC3 git worktree list still shows the kept scratch" \
  || fail "AC3 worktree list lost the keep ($(basename "$one")): $(git -C "$R" worktree list)"
grep -q "$(basename "$one")" "$TMP/comments" 2>/dev/null && ok "AC3b PR comment names the kept path" \
  || fail "AC3b no PR comment with the path: $(cat "$TMP/comments" 2>/dev/null)"
[ -f "$R/.claude/worktrees/leave-me/marker" ] && [ -d "$WT" ] \
  && ok "decoy worktree and the build worktree stayed" \
  || fail "a non-keep directory was removed"

first="$one"
sleep 1
run_gate "$TMP/cfg-red.json" ""
sleep 1
run_gate "$TMP/cfg-red.json" ""
nkeep=$(keeps | grep -c . || true)
[ "$nkeep" = 2 ] && [ ! -d "$first" ] && [ -f "$R/.claude/worktrees/leave-me/marker" ] \
  && ok "AC5 three red runs leave 2 keeps and drop the oldest only" \
  || fail "AC5 keeps=$nkeep first_gone=$( [ -d "$first" ] && echo no || echo yes ) $(keeps)"

# PASS: không để bản giữ mới, và không còn .merge-scratch- tạm.
before=$(keeps | grep -c . || true)
run_gate "$TMP/cfg-pass.json" "--dry-run"
prc=$?
after=$(keeps | grep -c . || true)
scratch_left=$(find "$R/.claude/worktrees" -mindepth 1 -maxdepth 1 -type d -name '.merge-scratch-*' ! -name '.merge-scratch-keep-pr*' | grep -c . || true)
[ "$prc" -eq 0 ] && [ "$after" = "$before" ] && [ "$scratch_left" = 0 ] \
  && ok "AC4 PASS still deletes the temporary scratch and does not keep another" \
  || fail "AC4 pass path rc=$prc keeps $before->$after scratch_left=$scratch_left log=$(tail -6 "$TMP/gate.log")"

[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_keep_scratch: PASS"; exit 0; }
echo "test_merge_gate_keep_scratch: $FAILS FAILED"
exit 1
