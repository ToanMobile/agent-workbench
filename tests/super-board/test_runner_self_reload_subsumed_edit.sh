#!/usr/bin/env bash
# Regression (18/11, board agent-workbench): the main checkout's super-board-run.sh carried an uncommitted hand edit
# (agy --model argon -> hydrogen) that #1264 had since merged on origin/main, and .agents/instincts.md had another
# session's uncommitted lesson. self_reload_tick saw "runner differs from HEAD" and refused to reload on every tick
# ("git merge --ff-only failed (uncommitted edits in the way?)"), so merged fixes (#1277) never reached the running board
# and #1266 was Blocked again by the very bug #1277 fixed.
# Rule: a hand edit of the runner that origin/<base> already contains (3-way merge HEAD/disk/origin == origin) is not a
# reason to keep old code: drop it and reload. A hand edit origin does not contain is still kept and warned (#623 7d).
# Same offline harness as test_runner_self_reload.sh. bash 3.2 compatible.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-self-reload-subsumed.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
log() { echo "$*" >> "$TMP/log"; }
board_notify() { echo "$*" >> "$TMP/notify"; }
reload_exec() { echo "$1" >> "$TMP/exec"; }
runner_state_write() { :; }
reload_finish_main() {   # stub của worktree finish: gộp origin vào main, xung đột thì trả lại nguyên trạng và khác 0
  echo x >> "$TMP/finish"; git merge -q --no-edit "origin/${BASE_BRANCH}" >/dev/null 2>&1 || { git merge --abort >/dev/null 2>&1; return 3; }
}
CONFIG_SLUG="board"; BASE_BRANCH="main"; ACTIVE_WORKERS=0; SB_RELOAD_EVERY=0

REL=".claude/bin/super-board-run.sh"
CASE=0
mkrepo() {   # mỗi ca một thư mục riêng: origin bare + repo (checkout đang chạy) + other (nơi đẩy bản mới), cùng lịch sử v1
  CASE=$((CASE + 1)); C="$TMP/c$CASE"; mkdir -p "$C"
  git init -q --bare -b main "$C/origin.git"
  git clone -q "$C/origin.git" "$C/repo" 2>/dev/null
  unset SB_RELOAD_SWAPPED_SUM
  ( cd "$C/repo" && mkdir -p .claude/bin && printf '#!/usr/bin/env bash\necho v1\n' > "$REL" && chmod 755 "$REL" \
    && echo base > other.txt && git add -A && git commit -qm v1 && git push -q origin HEAD:main 2>/dev/null )
  git clone -q "$C/origin.git" "$C/other" 2>/dev/null
  : > "$TMP/log"; : > "$TMP/notify"; : > "$TMP/exec"
  cd "$C/repo" || exit 1
  RELOAD_SELF="$C/repo/$REL"; RELOAD_RUN_SUM=$(git hash-object "$RELOAD_SELF"); RELOAD_WARNED=""; RELOAD_NEXT_CHECK=0; ACTIVE_WORKERS=0
}
push_other() {   # push_other <nội dung script>: đẩy bản mới của script lên origin từ clone khác
  ( cd "$C/other" && git pull -q origin main 2>/dev/null; printf '%s\n' "$1" > "$REL" && git add -A && git commit -qm next && git push -q origin HEAD:main 2>/dev/null )
}
execs() { wc -l < "$TMP/exec" | tr -d ' '; }
notes() { wc -l < "$TMP/notify" | tr -d ' '; }

V1=$'#!/usr/bin/env bash\necho v1\n# model=argon'
mkrepo_m() {   # mkrepo with a runner that has a "# model=argon" line (the line the hand edit changes)
  mkrepo
  printf '%s\n' "$V1" > "$REL" && git commit -qam v1m && git push -q origin HEAD:main 2>/dev/null
  ( cd "$C/other" && git pull -q origin main 2>/dev/null )
  RELOAD_RUN_SUM=$(git hash-object "$RELOAD_SELF")
}

# S1: runner hand edit already on origin + another dirty file blocks the ff -> reload origin's runner, other edit kept
mkrepo_m; echo dirty >> other.txt
sed -i.bak 's/argon/hydrogen/' "$REL" && rm -f "$REL.bak"
( cd "$C/other" && echo up >> other.txt && printf '%s\n' $'#!/usr/bin/env bash\necho v2\n# model=hydrogen' > "$REL" && git add -A && git commit -qm n && git push -q origin HEAD:main 2>/dev/null )
self_reload_tick
[ "$(execs)" = 1 ] && [ "$(notes)" = 0 ] && grep -q v2 "$RELOAD_SELF" && grep -q dirty other.txt \
  && ok "S1 hand edit already on origin + dirty other file: runner reloaded, other edit kept, no warning" \
  || fail "S1: exec=$(execs) notify=$(notes) log=$(cat "$TMP/log")"

# S2: runner hand edit already on origin, nothing else dirty -> fast-forward and reload
mkrepo_m
sed -i.bak 's/argon/hydrogen/' "$REL" && rm -f "$REL.bak"
( cd "$C/other" && printf '%s\n' $'#!/usr/bin/env bash\necho v2\n# model=hydrogen' > "$REL" && git add -A && git commit -qm n && git push -q origin HEAD:main 2>/dev/null )
self_reload_tick
[ "$(execs)" = 1 ] && [ "$(notes)" = 0 ] && grep -q v2 "$RELOAD_SELF" && [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
  && ok "S2 hand edit already on origin: main fast-forwarded and runner reloaded" \
  || fail "S2: exec=$(execs) notify=$(notes) log=$(cat "$TMP/log")"

# S3: control (#623 7d) — hand edit origin does NOT contain -> kept, warned, no exec
mkrepo_m; echo dirty >> other.txt
sed -i.bak 's/argon/neon/' "$REL" && rm -f "$REL.bak"
( cd "$C/other" && echo up >> other.txt && printf '%s\n' $'#!/usr/bin/env bash\necho v2\n# model=hydrogen' > "$REL" && git add -A && git commit -qm n && git push -q origin HEAD:main 2>/dev/null )
self_reload_tick
[ "$(execs)" = 0 ] && [ "$(notes)" = 1 ] && grep -q neon "$RELOAD_SELF" \
  && ok "S3 hand edit not on origin: kept and warned" || fail "S3: exec=$(execs) notify=$(notes)"

# S4: staged hand edit (even if on origin) is someone's in-flight commit -> not touched
mkrepo_m; echo dirty >> other.txt
sed -i.bak 's/argon/hydrogen/' "$REL" && rm -f "$REL.bak" && git add "$REL"
( cd "$C/other" && echo up >> other.txt && printf '%s\n' $'#!/usr/bin/env bash\necho v2\n# model=hydrogen' > "$REL" && git add -A && git commit -qm n && git push -q origin HEAD:main 2>/dev/null )
self_reload_tick
[ "$(execs)" = 0 ] && grep -q hydrogen "$RELOAD_SELF" && ! grep -q v2 "$RELOAD_SELF" \
  && ok "S4 staged hand edit: not touched, no exec" || fail "S4: exec=$(execs) notify=$(notes)"

cd "$TMP" || exit 1
[ "$FAILS" -eq 0 ] && echo "✅ test_runner_self_reload_subsumed_edit: all passed" || { echo "❌ test_runner_self_reload_subsumed_edit: $FAILS failed"; exit 1; }
