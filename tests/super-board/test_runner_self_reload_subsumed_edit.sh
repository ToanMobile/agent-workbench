#!/usr/bin/env bash
# Regression (#1283, 18/11 board agent-workbench): the main checkout's super-board-run.sh carried an uncommitted hand edit
# (agy --model argon -> hydrogen) that #1264 had since merged on origin/main, and .agents/instincts.md had another
# session's uncommitted lesson. self_reload_tick refused to reload on every tick ("git merge --ff-only failed (uncommitted
# edits in the way?)"), so merged fixes (#1277) never reached the running board and #1266 was Blocked again.
# Rule: a hand edit of the runner whose changes origin/<base> already has (git merge-file current=origin base=HEAD
# other=disk is clean and equals origin) is dropped and the runner reloads, with a notice. Anything else is kept and warned
# (#623 7d): an edit origin lacks, a deletion-only edit, an edit whose new line exists elsewhere in origin, an adjacent
# identical edit that conflicts, a staged edit, or a checkout where no reload follows (non-base branch).
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

FILL=$'a1\na2\na3\na4\na5\na6\na7\na8'
V1=$'#!/usr/bin/env bash\necho v1\n'"$FILL"$'\n# model=argon\nreturn 1\nkeep-me'
mkrepo_m() {   # runner with filler lines so the version line and the "# model=" line are far apart
  mkrepo
  printf '%s\n' "$V1" > "$REL" && git commit -qam v1m && git push -q origin HEAD:main 2>/dev/null
  ( cd "$C/other" && git pull -q origin main 2>/dev/null )
  RELOAD_RUN_SUM=$(git hash-object "$RELOAD_SELF")
}
push_v2() {   # push_v2 <model> [extra sed on the pushed copy]: origin = v2 + given model line (+ optional extra edit), other.txt bumped when $3=up
  ( cd "$C/other" && printf '%s\n' "$V1" | sed -e 's/echo v1/echo v2/' -e "s/argon/$1/" ${2:+-e "$2"} > "$REL" \
      && { [ "${3:-}" != up ] || echo up >> other.txt; } && git add -A && git commit -qm n && git push -q origin HEAD:main 2>/dev/null )
}
warned() { grep -q 'keeps the old code' "$TMP/log"; }
dropped() { grep -q 'đã bỏ' "$TMP/notify"; }

# S1: hand edit already on origin + another dirty file blocks the ff -> runner reloaded, other edit kept, drop notice, no "old code" warning
mkrepo_m; echo dirty >> other.txt; sed -i.bak 's/argon/hydrogen/' "$REL" && rm -f "$REL.bak"
push_v2 hydrogen "" up; self_reload_tick
[ "$(execs)" = 1 ] && grep -q v2 "$RELOAD_SELF" && grep -q dirty other.txt && dropped && ! warned \
  && ok "S1 hand edit already on origin + dirty other file: runner reloaded, other edit kept, drop noticed" \
  || fail "S1: exec=$(execs) notify=$(cat "$TMP/notify") log=$(cat "$TMP/log")"

# S2: hand edit already on origin, nothing else dirty -> fast-forward and reload
mkrepo_m; sed -i.bak 's/argon/hydrogen/' "$REL" && rm -f "$REL.bak"
push_v2 hydrogen; self_reload_tick
[ "$(execs)" = 1 ] && grep -q v2 "$RELOAD_SELF" && [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] && ! warned \
  && ok "S2 hand edit already on origin: main fast-forwarded and runner reloaded" \
  || fail "S2: exec=$(execs) notify=$(cat "$TMP/notify") log=$(cat "$TMP/log")"

# S3: hand edit origin does NOT contain -> kept, warned, no exec
mkrepo_m; echo dirty >> other.txt; sed -i.bak 's/argon/neon/' "$REL" && rm -f "$REL.bak"
push_v2 hydrogen "" up; self_reload_tick
[ "$(execs)" = 0 ] && grep -q neon "$RELOAD_SELF" && warned && ! dropped \
  && ok "S3 hand edit not on origin: kept and warned" || fail "S3: exec=$(execs) notify=$(cat "$TMP/notify")"

# S4: staged hand edit (even if on origin) is someone's in-flight commit -> not touched
mkrepo_m; echo dirty >> other.txt; sed -i.bak 's/argon/hydrogen/' "$REL" && rm -f "$REL.bak" && git add "$REL"
push_v2 hydrogen "" up; self_reload_tick
[ "$(execs)" = 0 ] && grep -q hydrogen "$RELOAD_SELF" && ! grep -q v2 "$RELOAD_SELF" && ! dropped \
  && ok "S4 staged hand edit: not touched, no exec" || fail "S4: exec=$(execs) notify=$(cat "$TMP/notify")"

# S5: deletion-only hand edit (keep-me deleted; origin still has it) -> kept, warned
mkrepo_m; echo dirty >> other.txt; sed -i.bak '/keep-me/d' "$REL" && rm -f "$REL.bak"
push_v2 hydrogen "" up; self_reload_tick
[ "$(execs)" = 0 ] && ! grep -q keep-me "$RELOAD_SELF" && warned && ! dropped \
  && ok "S5 deletion-only hand edit origin lacks: kept and warned" || fail "S5: exec=$(execs) notify=$(cat "$TMP/notify") log=$(cat "$TMP/log")"

# S6: hand edit's new line exists elsewhere in origin (return 1 -> return 0; origin adds a different 'return 0' line but keeps 'return 1')
mkrepo_m; echo dirty >> other.txt; sed -i.bak 's/^return 1$/return 0/' "$REL" && rm -f "$REL.bak"
push_v2 hydrogen 's/^a4$/return 0/' up; self_reload_tick
[ "$(execs)" = 0 ] && grep -q '^return 0$' "$RELOAD_SELF" && ! grep -q '^return 1$' "$RELOAD_SELF" && warned && ! dropped \
  && ok "S6 hand edit whose new line exists elsewhere in origin: kept and warned" || fail "S6: exec=$(execs) notify=$(cat "$TMP/notify") log=$(cat "$TMP/log")"

# S7: checkout on a non-base branch, hand edit already on origin -> no reload follows, so the edit is not dropped
mkrepo_m; git checkout -q -b side; sed -i.bak 's/argon/hydrogen/' "$REL" && rm -f "$REL.bak"
push_v2 hydrogen; self_reload_tick
[ "$(execs)" = 0 ] && grep -q hydrogen "$RELOAD_SELF" && ! dropped \
  && ok "S7 non-base branch: subsumed edit kept (no reload follows)" || fail "S7: exec=$(execs) notify=$(cat "$TMP/notify")"

# S8: identical edit but origin also changed the adjacent line (merge-file conflict) -> kept, warned (safe side)
mkrepo_m; echo dirty >> other.txt; sed -i.bak 's/argon/hydrogen/' "$REL" && rm -f "$REL.bak"
push_v2 hydrogen 's/^return 1$/return 2/' up; self_reload_tick
[ "$(execs)" = 0 ] && grep -q hydrogen "$RELOAD_SELF" && warned && ! dropped \
  && ok "S8 identical edit next to another origin change (conflict): kept and warned" || fail "S8: exec=$(execs) notify=$(cat "$TMP/notify") log=$(cat "$TMP/log")"

# S9: detached HEAD, hand edit already on origin -> dropped, origin runner swapped in and exec'd (#1107 path)
mkrepo_m; git checkout -q --detach; sed -i.bak 's/argon/hydrogen/' "$REL" && rm -f "$REL.bak"
push_v2 hydrogen; self_reload_tick
[ "$(execs)" = 1 ] && grep -q v2 "$RELOAD_SELF" && dropped \
  && ok "S9 detached HEAD + edit on origin: dropped, swapped, exec'd" || fail "S9: exec=$(execs) notify=$(cat "$TMP/notify") log=$(cat "$TMP/log")"

# S10: main has a local commit (HEAD not an ancestor of origin) + edit on origin + finish fails -> edit kept (no reload follows)
mkrepo_m; ( echo local >> other.txt && git commit -qam local ); sed -i.bak 's/argon/hydrogen/' "$REL" && rm -f "$REL.bak"
push_v2 hydrogen; reload_finish_main() { echo x >> "$TMP/finish"; return 3; }; self_reload_tick
reload_finish_main() { echo x >> "$TMP/finish"; git merge -q --no-edit "origin/${BASE_BRANCH}" >/dev/null 2>&1 || { git merge --abort >/dev/null 2>&1; return 3; }; }
[ "$(execs)" = 0 ] && grep -q hydrogen "$RELOAD_SELF" && ! dropped \
  && ok "S10 main with local commits (finish path) + failing finish: edit kept" || fail "S10: exec=$(execs) notify=$(cat "$TMP/notify")"

# S11: whitespace-only difference vs origin (trailing space added by hand) -> kept, warned
mkrepo_m; echo dirty >> other.txt; sed -i.bak 's/argon$/argon /' "$REL" && rm -f "$REL.bak"
push_v2 hydrogen "" up; self_reload_tick
[ "$(execs)" = 0 ] && grep -q 'argon $' "$RELOAD_SELF" && ! dropped \
  && ok "S11 whitespace-only hand edit: kept" || fail "S11: exec=$(execs) notify=$(cat "$TMP/notify")"

# S12: origin runner fails bash -n -> the subsumed edit is NOT dropped (no reload could follow)
mkrepo_m; echo dirty >> other.txt; sed -i.bak 's/argon/hydrogen/' "$REL" && rm -f "$REL.bak"
push_v2 hydrogen 's/^a1$/if then fi(((/' up; self_reload_tick
[ "$(execs)" = 0 ] && grep -q hydrogen "$RELOAD_SELF" && ! dropped \
  && ok "S12 origin runner fails bash -n: edit kept" || fail "S12: exec=$(execs) notify=$(cat "$TMP/notify")"

# S13: mode changed by hand (chmod -x) besides a subsumed content edit -> kept
mkrepo_m; echo dirty >> other.txt; sed -i.bak 's/argon/hydrogen/' "$REL" && rm -f "$REL.bak"; chmod 644 "$REL"
push_v2 hydrogen "" up; self_reload_tick
[ "$(execs)" = 0 ] && grep -q hydrogen "$RELOAD_SELF" && ! dropped \
  && ok "S13 hand mode change + subsumed edit: kept" || fail "S13: exec=$(execs) notify=$(cat "$TMP/notify")"

cd "$TMP" || exit 1
[ "$FAILS" -eq 0 ] && echo "✅ test_runner_self_reload_subsumed_edit: all passed" || { echo "❌ test_runner_self_reload_subsumed_edit: $FAILS failed"; exit 1; }
