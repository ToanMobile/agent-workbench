#!/usr/bin/env bash
# #1318 R6 (19/11): `build_handed_to_qa` moved a card to QA on exit 0 + `Next: QA` alone. Case #1295: the build commit was never pushed,
# so QA tested the old PR head. A hand-off now also needs an open PR whose head holds every local issue-<N>-* branch commit.
#  - open PR head == local branch tip           -> handed (0)
#  - local branch is ahead of the PR head       -> not handed (1): the old reclaim path runs
#  - no open PR for the card                    -> not handed (1)
# bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-handed-1318.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
unset SB_GITHUB_READ_STRICT
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
WORKER_LOG_DIR="$TMP/wl"; mkdir -p "$WORKER_LOG_DIR"
log() { :; }
issue_comment_count() { echo 4; }
issue_last_comment() { printf '[builder] [report] ✅ built\nNext: QA\n'; }
builder_reported_since() { return 0; }
issue_pr_head() { printf '%s' "$PR_HEAD"; }
printf '=== dispatch #300 at 2026-11-19T10:00:00Z ===\n{"type":"result","subtype":"success","is_error":false,"result":"done"}\nworker_exit: exit=0 signal=none elapsed=205s\n' > "$WORKER_LOG_DIR/worker-build-300.log"

# The fixture repo is born on the card branch, so no branch is created or switched.
R="$TMP/repo"; git init -q -b issue-300-x "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
git -C "$R" commit -q --allow-empty -m c1; C1=$(git -C "$R" rev-parse HEAD)
git -C "$R" commit -q --allow-empty -m c2; C2=$(git -C "$R" rev-parse HEAD)
cd "$R" || exit 1

PR_HEAD="$C2"
build_handed_to_qa 300 && ok "PR head == local tip -> handed to QA" || fail "pushed branch refused"
PR_HEAD="$C1"
build_handed_to_qa 300 && fail "local commit not on the PR head (#1295) still handed to QA" || ok "local branch ahead of the PR head -> not handed"
PR_HEAD=""
build_handed_to_qa 300 && fail "no open PR still handed to QA" || ok "no open PR -> not handed"

echo
[ "$FAILS" -eq 0 ] && { echo "test_runner_handed_to_qa_pushed_1318: PASS"; exit 0; } || { echo "test_runner_handed_to_qa_pushed_1318: FAIL ($FAILS)"; exit 1; }
