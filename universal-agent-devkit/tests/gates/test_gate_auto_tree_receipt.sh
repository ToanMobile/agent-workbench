#!/usr/bin/env bash
# Regression test (#319, 24/10): a PR ran --full twice on one tree (the push gate's run, then the merge gate's own verify) because the
# tree receipt the merge gate reads (sb_verified_tree_receipt) was written only when a caller remembered `verify-cmd.sh --record`.
# post-fix-gate.py now writes it itself after a --full PASS on a clean tree that holds origin/<base>, under the SAME key function.
# Negative paths write nothing: dirty tree, exit != 0, base not in the tree, no board config.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ROOT="$(cd "$DEVKIT_DIR/.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
BINSRC="$ROOT/.claude/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
[ -f "$BINSRC/super-board-verify-flags.sh" ] || { echo "skip: no super-board scripts at $BINSRC"; exit 0; }

VERIFY_CMD="python3 $GATE --run-tests --full --brief"
make_repo() {   # $1 = with-config|no-config
  rm -rf "$TMP/repo" && mkdir -p "$TMP/repo/src" "$TMP/repo/tests"
  cd "$TMP/repo" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  printf 'def sub(a, b):\n    return a - b\n' > src/calc.py
  printf 'import os, subprocess, sys\nsys.path.insert(0, "src")\nfrom calc import sub\nassert sub(3, 1) == 2, "sub"\nif os.environ.get("COMMIT_DURING_RUN"):   # case 13: a commit lands while the suite runs\n    open("z.txt", "w").write("z")\n    subprocess.run(["git", "add", "z.txt"], check=True)\n    subprocess.run(["git", "commit", "-qm", "during-run"], check=True)\n' > tests/test_calc.py
  cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Calc","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"calc","command":"for f in tests/test_*.py; do python3 \"$f\" || exit 1; done"}]}]}
JSON
  if [ "$1" = with-config ]; then
    mkdir -p .claude/bin .claude/super-board/configs
    cp "$BINSRC/super-board-verify-flags.sh" "$BINSRC/super-board-verify-cmd.sh" .claude/bin/
    jq -n --arg c "$VERIFY_CMD" '{base_branch:"main", verify_commands:[$c]}' > .claude/super-board/configs/t.json
  fi
  printf '.agents/\n.claude/worktrees/\n__pycache__/\n' > .gitignore
  git add -A && git commit -qm init
  git update-ref refs/remotes/origin/main main
  git checkout -q -b feat
  printf 'def sub(a, b):\n    return a - b  # touched\n' > src/calc.py
  git commit -qam "feat edit"
}
receipt_path() {
  ( . "$TMP/repo/.claude/bin/super-board-verify-flags.sh"
    sb_verified_tree_receipt "$(git -C "$TMP/repo" rev-parse 'HEAD^{tree}')" main "$TMP/repo" "$VERIFY_CMD" )
}
run_gate() { CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --matrix "$TMP/repo/matrix.json" --run-tests --full --force-full --lang en --diff origin/main > "$TMP/out" 2>&1; }

# 1. clean tree holding origin/main, --full PASS: the receipt exists under the merge gate's key
make_repo with-config
R=$(receipt_path)
run_gate; rc=$?
[ "$rc" = 0 ] || fail "setup: gate exit $rc (want 0): $(tail -5 "$TMP/out")"
[ -n "$R" ] && [ -f "$R" ] && ok "clean tree + --full PASS writes the tree receipt" || fail "no receipt at '$R' after a clean --full PASS; status: $(git -C "$TMP/repo" status --short | tr '\n' ' '); out: $(grep -i 'receipt' "$TMP/out" | tail -3)"

# 2. dirty tree: no receipt
make_repo with-config
R=$(receipt_path)
printf '# scratch\n' >> src/calc.py
run_gate
[ ! -e "$R" ] && ok "dirty tree writes no receipt" || fail "receipt written for a dirty tree"

# 3. gate exit != 0 (a red suite): no receipt
make_repo with-config
printf 'assert False, "red"\n' >> tests/test_calc.py && git commit -qam "red test"
R=$(receipt_path)
run_gate; rc=$?
[ "$rc" != 0 ] && [ ! -e "$R" ] && ok "exit $rc writes no receipt" || fail "exit $rc, receipt present=$([ -e "$R" ] && echo yes || echo no)"

# 4. origin/main moved past the tree (not an ancestor of HEAD): no receipt
make_repo with-config
git checkout -q main && printf 'x = 1\n' > other.py && git add other.py && git commit -qm "main moves" && git update-ref refs/remotes/origin/main main && git checkout -q feat
R=$(receipt_path)
run_gate
[ ! -e "$R" ] && ok "base not in the tree writes no receipt" || fail "receipt written although origin/main is not merged"

# 5. no board config: old behaviour, nothing written
make_repo no-config
run_gate; rc=$?
[ "$rc" = 0 ] && [ -z "$(git -C "$TMP/repo" rev-parse --git-common-dir | xargs -I{} sh -c 'ls {}/super-board/verified-trees 2>/dev/null')" ] \
  && ok "no board config writes nothing" || fail "no-config run wrote a receipt (rc=$rc)"

# OCR 24/10 (F1-F3): the mark vouches for what the board's merge gate would run. It must not be written when this run is not that verify:
# 6. the config lists a second verify command: this one run proves only the gate line -> no receipt
make_repo with-config
jq --arg c "echo second-suite" '.verify_commands += [$c]' .claude/super-board/configs/t.json > "$TMP/cfg" && mv "$TMP/cfg" .claude/super-board/configs/t.json
git add -A && git commit -qm cfg2
run_gate; rc=$?   # the run itself must PASS, else "no receipt" would only mean "no PASS" (OCR O6)
RC2=$( ( . .claude/bin/super-board-verify-flags.sh; sb_verified_tree_receipt "$(git rev-parse 'HEAD^{tree}')" main "$TMP/repo" "$VERIFY_CMD" "echo second-suite" ) )
[ "$rc" = 0 ] && [ -n "$RC2" ] && [ ! -e "$RC2" ] && ok "two verify commands: a passing gate run writes no receipt" || fail "rc=$rc, receipt at '$RC2' present=$([ -e "$RC2" ] && echo yes || echo no)"

# 7. a relaxing flag in this run (--allow-no-tests): the merge gate's own verify would not accept it -> no receipt
make_repo with-config
R=$(receipt_path)
CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --matrix "$TMP/repo/matrix.json" --run-tests --full --force-full --lang en --allow-no-tests --diff origin/main > "$TMP/out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$R" ] && ok "--allow-no-tests run (PASS, exit 0) writes no receipt" || fail "rc=$rc, receipt present=$([ -e "$R" ] && echo yes || echo no): $(tail -3 "$TMP/out")"

# 8. the tree changed after the run began (a commit or merge while --full ran): the verifier refuses to key the NEW tree
make_repo with-config
OLDTREE=$(git rev-parse 'HEAD^{tree}')
printf 'y = 2\n' > later.py && git add later.py && git commit -qm "after the run began"
R=$(receipt_path)
bash .claude/bin/super-board-verify-cmd.sh --config .claude/super-board/configs/t.json --mark --tree "$OLDTREE" >/dev/null 2>"$TMP/err"; rc=$?
[ "$rc" = 65 ] && [ ! -e "$R" ] && ok "--mark --tree: a tree that moved on gets no receipt (exit 65)" || fail "exit $rc, receipt present=$([ -e "$R" ] && echo yes || echo no): $(cat "$TMP/err")"

# 9. a single verify command that is not post-fix-gate: nothing this gate ran vouches for it
make_repo with-config
jq '.verify_commands = ["npm test"]' .claude/super-board/configs/t.json > "$TMP/cfg" && mv "$TMP/cfg" .claude/super-board/configs/t.json
git add -A && git commit -qm cfg3
TREE=$(git rev-parse 'HEAD^{tree}')
bash .claude/bin/super-board-verify-cmd.sh --config .claude/super-board/configs/t.json --mark --tree "$TREE" >/dev/null 2>"$TMP/err"; rc=$?
[ "$rc" = 65 ] && ok "--mark with a verify command that is not post-fix-gate.py: exit 65" || fail "exit $rc: $(cat "$TMP/err")"

# 9b/9c (OCR O1): "the whole verify is one gate line" is the SHAPE of the command, not a substring: a chained command or one that carries its own flags is refused.
for BAD in 'python3 bin/post-fix-gate.py --full && npm test' 'make lint; python3 bin/post-fix-gate.py --full' 'python3 bin/post-fix-gate.py --full | tee out' \
           "python3 \$(echo x)/post-fix-gate.py --full"; do
  make_repo with-config
  jq --arg c "$BAD" '.verify_commands = [$c]' .claude/super-board/configs/t.json > "$TMP/cfg" && mv "$TMP/cfg" .claude/super-board/configs/t.json
  git add -A && git commit -qm cfg4
  bash .claude/bin/super-board-verify-cmd.sh --config .claude/super-board/configs/t.json --mark --tree "$(git rev-parse 'HEAD^{tree}')" >/dev/null 2>"$TMP/err"; rc=$?
  [ "$rc" = 65 ] && ok "--mark refuses the verify command '$BAD' (exit 65)" || fail "'$BAD': exit $rc: $(cat "$TMP/err")"
done
# control: one plain gate line (any path, any ordinary flags) is accepted
make_repo with-config
git add -A; TREE=$(git rev-parse 'HEAD^{tree}')
bash .claude/bin/super-board-verify-cmd.sh --config .claude/super-board/configs/t.json --mark --tree "$TREE" >/dev/null 2>"$TMP/err"; rc=$?
[ "$rc" = 0 ] && [ -f "$(receipt_path)" ] && ok "--mark accepts the plain single gate line (exit 0, receipt written)" || fail "plain gate line: exit $rc: $(cat "$TMP/err")"

# 10. --record together with --mark is a usage error, not a silent skip of the commands
make_repo with-config
bash .claude/bin/super-board-verify-cmd.sh --config .claude/super-board/configs/t.json --record --mark --tree "$(git rev-parse 'HEAD^{tree}')" >/dev/null 2>&1; rc=$?
[ "$rc" = 64 ] && ok "--record --mark --tree: usage error (exit 64: not 'missing --tree')" || fail "--record --mark exit $rc (want 64)"

# 11. the board's REAL shape (this repo's config): the verify line itself carries --auto-approve-tests and the run used it too -> the receipt IS written
#     (a flag the verify line carries is not a relaxation of it; OCR review: the first version never wrote a receipt for the only real config)
VERIFY_CMD="python3 $GATE --run-tests --full --brief --auto-approve-tests"
make_repo with-config
R=$(receipt_path)
CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --matrix "$TMP/repo/matrix.json" --run-tests --full --force-full --lang en --auto-approve-tests --diff origin/main > "$TMP/out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ -f "$R" ] && ok "verify line carries --auto-approve-tests and the run used it: receipt written" || fail "rc=$rc, receipt present=$([ -f "$R" ] && echo yes || echo no): $(tail -3 "$TMP/out")"
# 12. same config, but the run used a flag the verify line does NOT carry (--allow-no-tests): no receipt
make_repo with-config
R=$(receipt_path)
CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --matrix "$TMP/repo/matrix.json" --run-tests --full --force-full --lang en --auto-approve-tests --allow-no-tests --diff origin/main > "$TMP/out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$R" ] && ok "a relaxing flag the verify line lacks (--allow-no-tests): no receipt" || fail "rc=$rc, receipt present=$([ -e "$R" ] && echo yes || echo no)"
# 12b. DEVKIT_AUTO_APPROVE_TESTS=1 in the environment relaxes exactly like the flag: a verify line WITHOUT the flag gets no receipt
VERIFY_CMD="python3 $GATE --run-tests --full --brief"
make_repo with-config
R=$(receipt_path)
DEVKIT_AUTO_APPROVE_TESTS=1 CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --matrix "$TMP/repo/matrix.json" --run-tests --full --force-full --lang en --diff origin/main > "$TMP/out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$R" ] && ok "DEVKIT_AUTO_APPROVE_TESTS=1 with a verify line lacking the flag: no receipt" || fail "rc=$rc, receipt present=$([ -e "$R" ] && echo yes || echo no)"

# 13. a commit made WHILE the run executes (the tree at the end is clean but was never tested): the receipt keys the tree the run STARTED on, so none is written
make_repo with-config
COMMIT_DURING_RUN=1 run_gate; rc=$?
RA=$(receipt_path)   # the key of the tree that exists NOW (after the suite's own commit)
[ "$rc" = 0 ] && [ ! -e "$RA" ] && ok "a commit during the run: the new tree gets no receipt (gate rc=0)" || fail "rc=$rc receipt present=$([ -e "$RA" ] && echo yes || echo no): $(grep -E 'KẾT LUẬN|UNVERIFIED|CHƯA XÁC MINH|REJECT|•' "$TMP/out" | head -6 | tr '\n' '|')"

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_auto_tree_receipt: all passed" || { echo "❌ test_gate_auto_tree_receipt: $FAILS failed"; exit 1; }
