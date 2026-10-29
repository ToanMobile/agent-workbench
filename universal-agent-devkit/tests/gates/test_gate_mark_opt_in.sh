#!/usr/bin/env bash
# Regression test (#575, 29/10): a hand-run `post-fix-gate.py --full` (or a repro run) wrote the verified-trees receipt under the merge gate's
# key, so the merge gate later skipped its verify (0 commands run) on a tree it never checked. Only a deliberate flow
# (SB_MARK_VERIFIED_TREE=1, set by the merge gate / QA lane) may write it; a plain --full run writes nothing.
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
mkdir -p "$TMP/repo/src" "$TMP/repo/tests" && cd "$TMP/repo" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
printf 'def sub(a, b):\n    return a - b\n' > src/calc.py
printf 'import sys\nsys.path.insert(0, "src")\nfrom calc import sub\nassert sub(3, 1) == 2, "sub"\n' > tests/test_calc.py
cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Calc","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"calc","command":"for f in tests/test_*.py; do python3 \"$f\" || exit 1; done"}]}]}
JSON
mkdir -p .claude/bin .claude/super-board/configs
cp "$BINSRC/super-board-verify-flags.sh" "$BINSRC/super-board-verify-cmd.sh" .claude/bin/
jq -n --arg c "$VERIFY_CMD" '{base_branch:"main", verify_commands:[$c]}' > .claude/super-board/configs/t.json
printf '.agents/\n.claude/worktrees/\n__pycache__/\n' > .gitignore
git add -A && git commit -qm init
git update-ref refs/remotes/origin/main main
git checkout -q -b feat
printf 'def sub(a, b):\n    return a - b  # touched\n' > src/calc.py
git commit -qam "feat edit"
R=$( . .claude/bin/super-board-verify-flags.sh; sb_verified_tree_receipt "$(git rev-parse 'HEAD^{tree}')" main "$TMP/repo" "$VERIFY_CMD" )
run_gate() { CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --matrix "$TMP/repo/matrix.json" --run-tests --full --force-full --lang en --diff origin/main > "$TMP/out" 2>&1; }

# 1. a hand-run green --full (no flag): no receipt
run_gate; rc=$?
[ "$rc" = 0 ] || fail "setup: gate exit $rc: $(tail -5 "$TMP/out")"
[ -n "$R" ] && [ ! -e "$R" ] && ok "plain --full PASS writes no verified-trees receipt" || fail "receipt present at '$R' after a hand-run --full"

# 2. the deliberate flow (SB_MARK_VERIFIED_TREE=1): receipt written, and the key is the one the merge gate reads
SB_MARK_VERIFIED_TREE=1 run_gate; rc=$?
[ "$rc" = 0 ] && [ -f "$R" ] && ok "SB_MARK_VERIFIED_TREE=1 --full PASS writes the receipt" || fail "rc=$rc, receipt at '$R' present=$([ -e "$R" ] && echo yes || echo no)"

[ "$FAILS" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$FAILS FAILED"; exit 1
