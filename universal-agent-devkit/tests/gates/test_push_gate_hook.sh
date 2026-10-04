#!/usr/bin/env bash
# Regression test: hooks/block-dangerous-git.sh blocks a `git push` that the last full gate PASS
# does not cover (bin/push_gate.py), and lets it through once bin/post-fix-gate.py --full passed
# on that content. Audit 2026-09-28: `git push origin main` passed with no gate run at all.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${HOOK:-$DEVKIT_DIR/hooks/block-dangerous-git.sh}"; GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
hook() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$TMP/repo" \
  | CLAUDE_PROJECT_DIR="$TMP/repo" bash "$HOOK" >/dev/null 2>&1; }
expect() { hook "$2"; local rc=$?; [ "$rc" = "$3" ] && echo "✔ $1 (exit $rc)" || { echo "✖ $1: exit $rc, expected $3"; FAILS=$((FAILS + 1)); }; }
git init -q --bare "$TMP/remote.git"
mkdir -p "$TMP/repo/src" "$TMP/repo/.agents" && cd "$TMP/repo" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t && git remote add origin "$TMP/remote.git"
echo "fun ok() = 1" > src/Core.kt
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}
JSON
git add -A && git commit -qm init && git push -q -u origin main 2>/dev/null
gate() { CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --run-tests --full --brief "$@" >/dev/null 2>&1; }
echo "fun ok() = 2" > src/Core.kt && git commit -qam fix
expect "push with no gate run: blocked" "git push origin main" 2
expect "cd + push with no gate run: blocked" "cd $TMP/repo && git push" 2
gate --diff origin/main
expect "push after a full gate PASS of the commits (--diff origin/main): allowed" "git push origin main" 0
echo "fun ok() = 3" > src/Core.kt && git commit -qam "after gate"
expect "push of a commit made after the gate: blocked" "git push origin main" 2
git reset -q --soft HEAD~1; gate; git commit -qm "gated, then committed"
expect "gate on the dirty tree, then commit: allowed" "git push origin main" 0
git branch -q side HEAD~1 2>/dev/null; git reset -q --soft HEAD~1; gate; git commit -qm "gated again"
git checkout -q side && echo "fun ok() = 9" > src/Core.kt && git commit -qam "side, never gated" && git checkout -q main
expect "one push of a gated branch plus an ungated one: blocked" "git push origin main side" 2
expect "the gated branch alone: allowed" "git push origin main" 0
expect "git status is never checked" "git status" 0
[ "$FAILS" -eq 0 ] && echo "push gate hook: all checks passed" || { echo "push gate hook: $FAILS FAILED"; exit 1; }
