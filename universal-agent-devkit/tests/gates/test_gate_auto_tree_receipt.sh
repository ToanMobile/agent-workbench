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
  printf 'import sys\nsys.path.insert(0, "src")\nfrom calc import sub\nassert sub(3, 1) == 2, "sub"\n' > tests/test_calc.py
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

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_auto_tree_receipt: all passed" || { echo "❌ test_gate_auto_tree_receipt: $FAILS failed"; exit 1; }
