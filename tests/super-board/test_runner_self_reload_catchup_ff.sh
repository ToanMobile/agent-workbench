#!/usr/bin/env bash
# Regression (18/11): main stayed 14 commits behind origin all day. Tick 1 was blocked by another session's dirty file, so only the
# runner was swapped in and exec'd; on every later tick `new == RELOAD_RUN_SUM` returned early and the ff was never retried.
# Rule: on the base branch, HEAD an ancestor of origin and HEAD != origin, retry the ff even when the runner blob is current
# (first hand the runner's own swapped copy back to HEAD). Still blocked: origin runner back on disk, NO exec (no restart loop),
# one warning per origin sha naming the blocking files, other sessions' edits never stashed or touched. Offline harness. bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-self-reload-catchup.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
log() { echo "$*" >> "$TMP/log"; }
board_notify() { echo "$*" >> "$TMP/notify"; }
reload_exec() { echo "$1" >> "$TMP/exec"; }
runner_state_write() { :; }
CONFIG_SLUG="board"; BASE_BRANCH="main"; ACTIVE_WORKERS=0; SB_RELOAD_EVERY=0
REL=".claude/bin/super-board-run.sh"
mkrepo() {
  C="$TMP/c$1"; mkdir -p "$C"; unset SB_RELOAD_SWAPPED_SUM
  git init -q --bare -b main "$C/origin.git"; git clone -q "$C/origin.git" "$C/repo" 2>/dev/null
  ( cd "$C/repo" && git checkout -q -b main 2>/dev/null; mkdir -p .claude/bin && printf '#!/usr/bin/env bash\nmodel=argon\necho tail\n' > "$REL" && chmod 755 "$REL" \
    && echo base > other.txt && git add -A && git commit -qm v1 && git push -q origin main 2>/dev/null )
  git clone -q "$C/origin.git" "$C/other" 2>/dev/null
  : > "$TMP/log"; : > "$TMP/notify"; : > "$TMP/exec"
  cd "$C/repo" || exit 1
  RELOAD_SELF="$C/repo/$REL"; RELOAD_RUN_SUM=$(git hash-object "$RELOAD_SELF"); RELOAD_WARNED=""; RELOAD_NEXT_CHECK=0
}
push_other() {   # push_other <model>: origin gets the runner with that model plus one more line, and other.txt = helper-v2
  ( cd "$C/other" && printf '#!/usr/bin/env bash\nmodel=%s\necho tail\necho more\n' "$1" > "$REL" && echo helper-v2 > other.txt \
      && git add -A && git commit -qm n && git push -q origin main 2>/dev/null )
}
execs() { wc -l < "$TMP/exec" | tr -d ' '; }
notes() { wc -l < "$TMP/notify" | tr -d ' '; }
restart() { RELOAD_RUN_SUM=$(git hash-object "$RELOAD_SELF"); RELOAD_NEXT_CHECK=0; }   # what the exec'd runner computes at startup

# A. tick 1 blocked by another dirty file (runner swapped, exec); the file is cleaned; tick 2 fast-forwards main
mkrepo a; echo mine > other.txt; push_other hydrogen
self_reload_tick; restart
git restore -- other.txt
self_reload_tick
[ "$(execs)" = 1 ] && [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] && grep -q helper-v2 other.txt && [ -z "$(git status --porcelain)" ] \
  && ok "A catch-up: tick 2 fast-forwards main without a second exec" \
  || fail "A: exec=$(execs) head=$(git rev-parse --short HEAD) origin=$(git rev-parse --short origin/main) st=$(git status --porcelain | tr '\n' ' ')"

# B. tick 2 and 3 still blocked: no exec, origin runner on disk, the other edit untouched, ONE warning naming the file, nothing stashed
mkrepo b; echo mine > other.txt; push_other hydrogen
self_reload_tick; restart; h=$(git rev-parse HEAD)
self_reload_tick; RELOAD_NEXT_CHECK=0; self_reload_tick
[ "$(execs)" = 1 ] && [ "$(git hash-object "$RELOAD_SELF")" = "$(git rev-parse "origin/main:$REL")" ] && grep -q mine other.txt \
  && [ "$(git rev-parse HEAD)" = "$h" ] && [ "$(notes)" = 1 ] && grep -q 'other.txt' "$TMP/notify" && [ -z "$(git stash list)" ] \
  && ok "B still blocked: no exec, origin runner kept, edit untouched, one warning naming the file" \
  || fail "B: exec=$(execs) notify=$(notes) log=$(cat "$TMP/log")"

# C. main has a local commit (not an ancestor of origin): the catch-up must not touch it
mkrepo c; ( cd "$C/other" && echo helper-v2 > other.txt && git add -A && git commit -qm n && git push -q origin main 2>/dev/null ); echo local > mine.txt; git add mine.txt; git commit -qm local; h=$(git rev-parse HEAD)
self_reload_tick
[ "$(git rev-parse HEAD)" = "$h" ] && [ "$(execs)" = 0 ] && ok "C local commit: catch-up leaves main alone" || fail "C: exec=$(execs)"

# D. cold restart (env SB_RELOAD_SWAPPED_SUM lost: watchdog/launchd/by hand) after a blocked swap: the on-disk runner equals origin's blob,
#    so it is not a hand edit and must not block the ff once the other file is cleaned
mkrepo d; echo mine > other.txt; push_other hydrogen
self_reload_tick; unset SB_RELOAD_SWAPPED_SUM; restart
git restore -- other.txt
self_reload_tick
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] && [ -z "$(git status --porcelain)" ] && [ "$(execs)" = 1 ] \
  && ok "D cold restart: absorbed runner copy does not block the catch-up" \
  || fail "D: head=$(git rev-parse --short HEAD) origin=$(git rev-parse --short origin/main) st=$(git status --porcelain | tr '\n' ' ')"

# E. while blocked, the runner file is not rewritten tick after tick (same inode), and untracked blockers are named too
mkrepo e; echo new > other.txt2; ( cd "$C/other" && echo x > other.txt2 && git add -A && git commit -qm n2 && git push -q origin main 2>/dev/null )
push_other hydrogen
self_reload_tick; restart; i1=$(ls -i "$RELOAD_SELF" | cut -d' ' -f1)
self_reload_tick; RELOAD_NEXT_CHECK=0; self_reload_tick
i2=$(ls -i "$RELOAD_SELF" | cut -d' ' -f1)
[ "$i1" = "$i2" ] && [ "$(execs)" = 1 ] && grep -q 'other.txt2' "$TMP/notify" \
  && ok "E blocked: runner file untouched across ticks, untracked blocker named" || fail "E: inode $i1 → $i2 exec=$(execs) notify=$(cat "$TMP/notify")"

cd "$TMP" || exit 1
[ "$FAILS" -eq 0 ] && { echo "✅ test_runner_self_reload_catchup_ff: all passed"; exit 0; } || { echo "❌ test_runner_self_reload_catchup_ff: $FAILS failed"; exit 1; }
