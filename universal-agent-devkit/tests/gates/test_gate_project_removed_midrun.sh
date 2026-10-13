#!/usr/bin/env bash
# W1 R5a (docs/workflow-improvements.md I.0): a gate never re-creates a project folder that went away while it ran. 13/10, measured:
# a gate running in a linked worktree whose folder `worktree finish`/`remove` took away mid-suite wrote its results anyway, and every
# write's mkdir(parents=True) brought the folder back — .agents/regression_status.json, INBOX.md, CHECKLIST.md, evidence, journal and
# lock files — a folder git no longer knows that `worktree gc` rightly keeps (regression_status.json may hold rows people wrote), so it
# waited for the user. The gate now says the project is gone and records nothing there.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"; mkdir -p "$R/src" "$R/.agents" && cd "$R" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
printf '{"project":"t","rules":[{"component":"C","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-1","name":"c","command":"touch %s/started; sleep 4; true"}]}]}\n' \
  "$TMP" > .agents/regression_matrix.active.json
git add -A && git commit -qm init
W="$TMP/repo-wt"; git worktree add -q --detach "$W" && echo "fun ok() = 2" > "$W/src/Core.kt"
(cd "$W" && CLAUDE_PROJECT_DIR="$W" python3 "$DEVKIT_DIR/bin/post-fix-gate.py" --run-tests --json > "$TMP/gate.out" 2>&1; echo $? > "$TMP/gate.rc") & GATE=$!
for _ in $(seq 1 100); do [ -e "$TMP/started" ] && break; sleep 0.1; done   # the suite itself is running (the lock comes before it)
[ -e "$TMP/started" ] || fail "setup: the suite never started, so nothing below tests a removal mid-run"
git -C "$R" worktree remove --force "$W" && [ ! -e "$W" ] || fail "setup: could not remove the worktree mid-run"
for _ in $(seq 1 900); do [ -s "$TMP/gate.rc" ] && break; sleep 0.1; done   # bounded: a gate hung on its vanished folder fails here
[ -s "$TMP/gate.rc" ] || { pkill -P "$GATE" 2>/dev/null; kill "$GATE" 2>/dev/null; fail "the gate hung after its project went away"; }
wait 2>/dev/null
rc="$(cat "$TMP/gate.rc" 2>/dev/null)"
[ ! -e "$W" ] && ok "the folder removed mid-run stays removed" || fail "the gate re-created it: $(cd "$W" 2>/dev/null && find . -type f | head -8 | tr '\n' ' ')"
[ "$rc" = 1 ] && ! grep -q Traceback "$TMP/gate.out" && ok "  … and the gate ends UNVERIFIED, exit 1, no crash" || fail "want exit 1 without a traceback, got rc '$rc'"
grep -qE "project folder was removed|thư mục project đã bị gỡ" "$TMP/gate.out" && ok "  … and it says why" || fail "no reason given: $(tail -3 "$TMP/gate.out")"
[ ! -e "$R/.git/worktrees/repo-wt" ] && ok "  … nor its admin dir in the main repo" || fail "the admin dir came back: $(ls "$R/.git/worktrees/repo-wt")"
[ -z "$(git -C "$R" status --porcelain)" ] && ok "the main checkout is untouched" || fail "main changed: $(git -C "$R" status --porcelain)"
[ "$FAILS" -eq 0 ] && echo "✅ test_gate_project_removed_midrun: all passed" || { echo "❌ test_gate_project_removed_midrun: $FAILS failed"; exit 1; }
