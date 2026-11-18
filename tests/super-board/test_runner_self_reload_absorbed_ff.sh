#!/usr/bin/env bash
# Regression (#1285, review of #1282): a hand edit of the runner that origin already has must not leave main behind.
# Before: the absorbed path swapped only the runner file and exec'd; HEAD and every other file of the merged PR stayed old,
# and the ff was not retried until origin changed the runner again. Rule: drop the absorbed edit and fast-forward main;
# only when another dirty file still blocks the ff, fall back to the #623 swap (that file kept). Offline harness. bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-self-reload-absff.XXXXXX")"
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

# A. edit on origin, nothing else dirty: main fast-forwards to origin (the PR's helper file arrives too) and the runner reloads
mkrepo a; sed -i.bak 's/argon/hydrogen/' "$REL"; rm -f "$REL.bak"; RELOAD_RUN_SUM=$(git hash-object "$RELOAD_SELF")
push_other hydrogen
self_reload_tick
[ "$(execs)" = 1 ] && [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] && grep -q helper-v2 other.txt && [ -z "$(git status --porcelain)" ] \
  && ok "A edit on origin: main fast-forwarded, runner reloaded" \
  || fail "A: exec=$(execs) head=$(git rev-parse --short HEAD) origin=$(git rev-parse --short origin/main) st=$(git status --porcelain | tr '\n' ' ')"

# B. edit on origin + another dirty file blocking the ff: runner swapped in and reloaded, the other edit kept
mkrepo b; sed -i.bak 's/argon/hydrogen/' "$REL"; rm -f "$REL.bak"; echo mine > other.txt; RELOAD_RUN_SUM=$(git hash-object "$RELOAD_SELF")
push_other hydrogen
self_reload_tick
[ "$(execs)" = 1 ] && [ "$(git hash-object "$RELOAD_SELF")" = "$(git rev-parse "origin/main:$REL")" ] && grep -q mine other.txt \
  && ok "B edit on origin + other dirty file: swapped, other edit kept" || fail "B: exec=$(execs) log=$(cat "$TMP/log")"

# C. edit origin lacks: kept and warned, main not moved
mkrepo c; sed -i.bak 's/argon/mine/' "$REL"; rm -f "$REL.bak"; RELOAD_RUN_SUM=$(git hash-object "$RELOAD_SELF"); h=$(git rev-parse HEAD)
push_other argon
self_reload_tick
[ "$(execs)" = 0 ] && grep -q model=mine "$RELOAD_SELF" && [ "$(git rev-parse HEAD)" = "$h" ] && [ "$(notes)" = 1 ] \
  && ok "C edit origin lacks: kept, warned, main not moved" || fail "C: exec=$(execs) notify=$(notes)"

cd "$TMP" || exit 1
[ "$FAILS" -eq 0 ] && { echo "✅ test_runner_self_reload_absorbed_ff: all passed"; exit 0; } || { echo "❌ test_runner_self_reload_absorbed_ff: $FAILS failed"; exit 1; }
