#!/usr/bin/env bash
# tests/run_impacted.sh, DEVKIT_IMPACTED_SINCE (2026-10-09 follow-up, docs/issues-bugs.md B.1 step 4):
# a checkout with no upstream counts the commits of the last 6 hours as "changed" so a commit made inside a turn does not leave the
# gate testing nothing. A RED-proof sandbox (scripts/testing/red_proof.py: a throw-away detached worktree) has no upstream either, so
# each proof ran the tests of EVERY recent commit — 25 minutes per bug instead of the 3 to 120 tests of the one reverted file.
# DEVKIT_IMPACTED_SINCE=0 turns that window off (only the working tree and untracked files are changed); any other value is a git
# date for --since (default 6.hours). With an upstream the window never applies (the unpushed commits are the change).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_IMPACTED_SINCE   # the "default" case must not inherit a caller's value (the RED-proof recipe exports 0)
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

K="$TMP/kit"; mkdir -p "$K/tests/verification" "$K/scripts"
cp "$DEVKIT_DIR/tests/run_impacted.sh" "$K/tests/"
: > "$K/tests/impact_map.txt"
echo 'echo ok' > "$K/tests/verification/test_repo_consistency.sh"
echo 'x = 1' > "$K/scripts/foo.py"
printf 'python3 scripts/foo.py\n' > "$K/tests/verification/test_foo.sh"
( cd "$K" && git init -q . && git config user.email t@t && git config user.name t && git add -A && git commit -qm init )
echo 'x = 2' > "$K/scripts/foo.py"
( cd "$K" && git commit -qam "fix a minute ago" )   # no upstream: this commit is in the last 6 hours
list() { (cd "$K" && "$@" bash tests/run_impacted.sh --list); }

list env | grep -qx "tests/verification/test_foo.sh" && ok "default: a recent commit of a checkout with no upstream is selected" || fail "default: $(list env | tr '\n' ' ')"
[ "$(list env DEVKIT_IMPACTED_SINCE=0)" = "tests/verification/test_repo_consistency.sh" ] && ok "DEVKIT_IMPACTED_SINCE=0: the recent commit is no change, repo consistency only" || fail "since=0: $(list env DEVKIT_IMPACTED_SINCE=0 | tr '\n' ' ')"
list env DEVKIT_IMPACTED_SINCE=1.hour | grep -qx "tests/verification/test_foo.sh" && ok "DEVKIT_IMPACTED_SINCE=1.hour: still inside the window" || fail "since=1.hour: $(list env DEVKIT_IMPACTED_SINCE=1.hour | tr '\n' ' ')"

# the working tree stays a change whatever the window
echo 'x = 3' > "$K/scripts/foo.py"
list env DEVKIT_IMPACTED_SINCE=0 | grep -qx "tests/verification/test_foo.sh" && ok "DEVKIT_IMPACTED_SINCE=0: an uncommitted change is still selected" || fail "since=0 + dirty: $(list env DEVKIT_IMPACTED_SINCE=0 | tr '\n' ' ')"

# A linked worktree with no upstream (`agent-kit worktree add` makes it detached): its change is what it holds that the main
# checkout's HEAD does not (from their merge-base), not every commit of the last 6 hours - those are other sessions' work already
# in main (measured 13/10 in a detached worktree: 157 tests instead of the 11 of its own diff, a gate past 900 s).
( cd "$K" && git checkout -q -- scripts/foo.py )
echo 'z = 1' > "$K/scripts/baz.py"; printf 'python3 scripts/baz.py\n' > "$K/tests/verification/test_baz.sh"
echo 'q = 1' > "$K/scripts/qux.py"; printf 'python3 scripts/qux.py\n' > "$K/tests/verification/test_qux.sh"
( cd "$K" && git add -A && git commit -qm "baz and qux, in main a minute ago" )
W="$TMP/wt"; ( cd "$K" && git worktree add -q --detach "$W" HEAD )
wlist() { (cd "$W" && "$@" bash tests/run_impacted.sh --list); }
[ "$(wlist env)" = "tests/verification/test_repo_consistency.sh" ] && ok "fresh linked worktree: main's recent commits are no change" || fail "fresh worktree: $(wlist env | tr '\n' ' ')"
echo 'z = 2' > "$W/scripts/baz.py"; ( cd "$W" && git commit -qam "baz, in the worktree" )
echo 'q = 2' > "$K/scripts/qux.py"; ( cd "$K" && git commit -qam "qux, main moved on after the worktree was made" )
[ "$(wlist env | tr '\n' ' ')" = "tests/verification/test_baz.sh tests/verification/test_repo_consistency.sh " ] \
  && ok "linked worktree: only its own commit is a change (not main's earlier or later commits)" || fail "worktree commit: $(wlist env | tr '\n' ' ')"
wlist env DEVKIT_IMPACTED_SINCE=6.hours | grep -qx "tests/verification/test_foo.sh" && ok "linked worktree: an explicit DEVKIT_IMPACTED_SINCE window still applies" || fail "worktree since=6.hours: $(wlist env DEVKIT_IMPACTED_SINCE=6.hours | tr '\n' ' ')"
( cd "$W" && git merge -q --no-edit "$(cd "$K" && git rev-parse HEAD)" ) >/dev/null 2>&1
[ "$(wlist env | tr '\n' ' ')" = "tests/verification/test_baz.sh tests/verification/test_repo_consistency.sh " ] \
  && ok "linked worktree after merging main in: main's commit is still no change" || fail "worktree after merge: $(wlist env | tr '\n' ' ')"
( cd "$K" && git worktree remove --force "$W" )

[ "$FAILS" -eq 0 ] && echo "✅ test_run_impacted_since: all passed" || { echo "❌ test_run_impacted_since: $FAILS failed"; exit 1; }
