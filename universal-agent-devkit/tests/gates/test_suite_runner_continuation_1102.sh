#!/usr/bin/env bash
# #1102 (PR #1173): post-fix-gate read `.claude/skills/super-qa/SKILL.md` as a "suite runner" of the matrix because a suite
# script (tests/super-board/test_decision_prompts.sh) lists it on the continuation line of a `for rel in a \` loop: the line
# after the backslash was parsed as a new command, so its first word looked like a script being run. The doc edit then
# blocked the gate (exit 2, "Script lệnh suite của ma trận chạy bị sửa") and `agent-kit approve-tests` cannot approve a
# non-test path, so the card deadlocked. Fix: regression_checklist._command_lines joins backslash-continued lines.
#  a. a doc in a continued `for … in` list is no runner; b. a script really run across a continuation still is.
# Run: bash universal-agent-devkit/tests/gates/test_suite_runner_continuation_1102.sh
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

git -C "$TMP" init -q
mkdir -p "$TMP/tests" "$TMP/docs" "$TMP/scripts"
cat > "$TMP/tests/test_prompts.sh" <<'SH'
#!/usr/bin/env bash
for rel in docs/a.md \
  docs/skill.md docs/b.md; do
  grep -q x "$rel"
done
bash \
  scripts/run.sh
SH
printf 'x\n' > "$TMP/docs/skill.md"
printf 'echo ok\n' > "$TMP/scripts/run.sh"
git -C "$TMP" add -A && git -C "$TMP" -c user.name=t -c user.email=t@t commit -qm base

out="$(cd "$TMP" && CLAUDE_PROJECT_DIR="$TMP" python3 - "$DEVKIT_DIR/bin" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("gate", sys.argv[1] + "/post-fix-gate.py")
g = importlib.util.module_from_spec(spec); spec.loader.exec_module(g)
matrix = {"rules": [{"mandatory_regression_tests": [{"command": "bash tests/test_prompts.sh"}]}]}
print(sorted(g.suite_runner_paths(matrix, "HEAD", {"docs/skill.md", "scripts/run.sh"})))
PY
)"
echo "suite_runner_paths: $out"
case "$out" in
  *docs/skill.md*) echo "FAIL a. a doc on a continued for-list line is read as a suite runner"; fails=$((fails+1)) ;;
  *) echo "ok   a. a doc on a continued for-list line is not a suite runner" ;;
esac
case "$out" in
  *scripts/run.sh*) echo "ok   b. a script run across a backslash continuation is still a suite runner" ;;
  *) echo "FAIL b. a script run across a backslash continuation is no longer found"; fails=$((fails+1)) ;;
esac
[ "$fails" -eq 0 ] && echo "PASS test_suite_runner_continuation_1102" || echo "FAIL test_suite_runner_continuation_1102 ($fails)"
exit $(( fails > 0 ))
