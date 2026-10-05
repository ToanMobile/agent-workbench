#!/usr/bin/env bash
# Regression (W1-f round 6, reviewer A on r5): `agent-kit worktree remove` (scripts/git/worktree.py removal_blockers) is a
# DATA-LOSS gate, so a path git lists in another spelling, a commit only a reflog names, a change git hides, and a submodule
# must each REFUSE the removal (the commit / the bytes stay recoverable), and the legitimate flows must still go:
#   P1-1  the worktree named in another spelling (case-flipped, NFD, a newline in the name, a subdirectory, the main checkout)
#   P1-2  a BRANCH worktree whose commit was made detached (checkout --detach, commit, checkout <branch>); reset/amend/rebase on a
#         branch are NOT refused (the branch reflog still holds the old tip); an unreadable / corrupt reflog reads as a blocker
#   P3    chmod +x only; an edit of a skip-worktree / assume-unchanged file; a git failure while reading the status file; an
#         untracked nested repo whose path also exists in main
#   P2    a submodule: uncommitted edit, a commit whose HEAD moved back, a hand-written refs/remotes in the worktree's own module
# Round 7: a FIFO planted in the git dir (reflog, state file) or a git call that never returns must read as "cannot say" (a bounded
# refusal), never hang a command or a hook; git < 2.36 (no `worktree list -z`) with a newline-path worktree; a squash / fixup brought
# back as ONE diff is not refused; a worktree nested inside the target; a core.worktree pointing elsewhere; the advice is shell-quoted.
# NEEDS git >= 2.36 (`git worktree list -z`: the case-flip / newline / NFD checks). The old-git cases use a shim, not an old git.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
WTPY="$DEVKIT_DIR/scripts/git/worktree.py"
# the scratch dir: a failing mktemp must never leave TMP at the cwd (the EXIT trap below deletes TMP)
mk_tmp() { local t; t="$(mktemp -d 2>/dev/null)" || return 1; case "$t" in /?*) [ -d "$t" ] || return 1 ;; *) return 1 ;; esac; (cd "$t" && pwd -P); }
TMP="$(mk_tmp)" || { echo "✖ cannot make a scratch dir"; exit 1; }
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "✖ cannot make a scratch dir"; exit 1; }
trap 'chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
GITV="$(git --version | sed -n 's/^git version \([0-9]*\)\.\([0-9]*\).*/\1 \2/p')"
set -- $GITV
if [ "${1:-0}" -lt 2 ] || { [ "${1:-0}" = 2 ] && [ "${2:-0}" -lt 36 ]; }; then echo "SKIPPED (git < 2.36): the worktree remove safety test was NOT run - needs git >= 2.36 (worktree list -z); found $(git --version)" >&2; echo "worktree remove safety: SKIPPED (git < 2.36) - NOT RUN"; exit 0; fi
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
NL=$'\n'

R="$TMP/r6"; mkdir -p "$R" && G "$R" init -q -b main . && cd "$R" || exit 1
for f in a b c d e f; do printf '1\n2\n3\n4\n5\n' > "$R/$f.txt"; done
G "$R" add -A && G "$R" commit -qm init
w6() { bash "$KIT" worktree add "../r6-$1" ${2:+"$2"} >/dev/null 2>&1 || fail "add r6-$1"; }   # w6 <name> [branch]
c6() { G "$TMP/r6-$1" add -A && G "$TMP/r6-$1" commit -qm "$2"; }                               # c6 <name> <message>
rm6() { bash "$KIT" worktree remove "$1" >"$TMP/out.txt" 2>&1; return $?; }                      # rm6 <path as typed, from $R>
# refused <label> <rc> <worktree dir> <pattern in the output> [<sha that must still exist>]
refused() {
  local label="$1" rc="$2" dir="$3" pat="$4" sha="${5:-}"
  if [ "$rc" != 0 ] && [ -d "$dir" ] && grep -qiE -e "$pat" "$TMP/out.txt" && { [ -z "$sha" ] || G "$R" cat-file -e "$sha"; }; then ok "$label"
  else fail "$label (rc=$rc, dir_left=$([ -d "$dir" ] && echo yes || echo NO)): $(head -c 400 "$TMP/out.txt")"; fi
}
allowed() {   # allowed <label> <rc> <worktree dir>
  if [ "$2" = 0 ] && [ ! -d "$3" ]; then ok "$1"; else fail "$1 (rc=$2, dir_left=$([ -d "$3" ] && echo yes || echo NO)): $(head -c 400 "$TMP/out.txt")"; fi
}
# a detached worktree with ONE commit only its HEAD reflog names (commit, then checkout --detach HEAD~1)
reflog_only() {   # reflog_only <name>: sets SHA to the precious commit
  w6 "$1"; echo "precious $1" >> "$TMP/r6-$1/b.txt"; c6 "$1" "precious $1"; SHA="$(G "$TMP/r6-$1" rev-parse HEAD)"
  G "$TMP/r6-$1" checkout -q --detach HEAD~1
}

# ── P1-1: the worktree named in another spelling is still THAT worktree: the same checks run, the same refusal ─────────────
reflog_only canon; rm6 ../r6-canon; refused "path: the canonical spelling is refused (control)" $? "$TMP/r6-canon" "UNREACHABLE" "$SHA"

reflog_only "nl${NL}x y"; NLSHA="$SHA"; rm6 "../r6-nl${NL}x y"
refused "path: a newline in the worktree's name (git's own listing splits it) is still identified and refused" $? "$TMP/r6-nl${NL}x y" "UNREACHABLE" "$NLSHA"
G "$R" branch rescue/nl "$NLSHA"; rm6 "../r6-nl${NL}x y"; allowed "path: ... and goes once a branch holds the commit" $? "$TMP/r6-nl${NL}x y"

reflog_only CASE; CASESHA="$SHA"
if [ -d "$TMP/R6-case" ]; then   # case-insensitive filesystem (APFS default): ../R6-case is the same directory
  rm6 ../R6-case; refused "path: a case-flipped spelling (case-insensitive filesystem) is refused like the canonical one" $? "$TMP/r6-CASE" "UNREACHABLE" "$CASESHA"
else ok "path: case-flipped spelling - skipped (this filesystem is case-sensitive)"; fi

EACUTE=$'\xc3\xa9'; EACUTE_NFD=$'e\xcc\x81'
reflog_only "n${EACUTE}"; NFDSHA="$SHA"
if [ -d "$TMP/r6-n${EACUTE_NFD}" ]; then   # normalization-insensitive filesystem (APFS)
  rm6 "../r6-n${EACUTE_NFD}"; refused "path: an NFD spelling of the name (APFS) is refused like the canonical one" $? "$TMP/r6-n${EACUTE}" "UNREACHABLE" "$NFDSHA"
else ok "path: NFD spelling - skipped (this filesystem keeps normalization forms apart)"; fi

reflog_only sub; mkdir -p "$TMP/r6-sub/inner"; rm6 ../r6-sub/inner
refused "path: a SUBDIRECTORY of a worktree is not the worktree: refused, says git does not list it" $? "$TMP/r6-sub" "not listed|does not list" "$SHA"
rm6 ../r6-sub; refused "path: ... and the worktree itself is refused as always" $? "$TMP/r6-sub" "UNREACHABLE" "$SHA"

mkdir -p "$TMP/r6-plain"; rm6 ../r6-plain
[ $? = 2 ] && [ -d "$TMP/r6-plain" ] && ok "path: a plain directory (not a worktree) -> exit 2, kept" || fail "plain directory: $(cat "$TMP/out.txt")"
rm6 ../r6-nowhere; rc=$?
[ "$rc" = 2 ] && grep -q "no such directory" "$TMP/out.txt" && ok "path: a path that does not exist -> exit 2 'no such directory' (as before)" || fail "missing path (rc=$rc): $(cat "$TMP/out.txt")"
rm6 "$R"; rc=$?
[ "$rc" = 2 ] && [ -d "$R/.git" ] && grep -q "main checkout" "$TMP/out.txt" && ok "path: the main checkout -> exit 2, 'that is the main checkout', kept" || fail "main checkout (rc=$rc): $(cat "$TMP/out.txt")"

# an old git has no `worktree list -z`: a path with a newline cannot be parsed there -> refuse (never skip the checks); a plain path still works
SHIM="$TMP/shim"; mkdir -p "$SHIM"; REALGIT="$(command -v git)"
{ echo '#!/bin/bash'
  echo '# stand-in for a git older than 2.36: `worktree list ... -z` is an unknown option there'
  echo 'w=0; l=0; z=0; for a in "$@"; do case "$a" in worktree) w=1;; list) l=1;; -z) z=1;; esac; done'
  echo '[ $w = 1 ] && [ $l = 1 ] && [ $z = 1 ] && { echo "error: unknown switch z" >&2; exit 129; }'
  echo "exec \"$REALGIT\" \"\$@\""; } > "$SHIM/git"
chmod +x "$SHIM/git"
w6 oldgit; echo "x" >> "$TMP/r6-oldgit/c.txt"
PATH="$SHIM:$PATH" bash "$KIT" worktree remove ../r6-oldgit >"$TMP/out.txt" 2>&1; rc=$?
[ "$rc" = 1 ] && [ -d "$TMP/r6-oldgit" ] && grep -q "c.txt" "$TMP/out.txt" && ok "old git: a normal path is still checked (uncommitted c.txt refused)" || fail "old git, plain path (rc=$rc): $(cat "$TMP/out.txt")"
reflog_only "nl2${NL}z"; OLDSHA="$SHA"
PATH="$SHIM:$PATH" bash "$KIT" worktree remove "../r6-nl2${NL}z" >"$TMP/out.txt" 2>&1; rc=$?
refused "old git (no worktree list -z): a newline in the worktree's name -> refused, nothing removed" "$rc" "$TMP/r6-nl2${NL}z" "." "$OLDSHA"
PATH="$SHIM:$PATH" bash "$KIT" worktree remove ../r6-oldgit >"$TMP/out.txt" 2>&1; rc=$?
[ "$rc" = 1 ] && [ -d "$TMP/r6-oldgit" ] && grep -q "c.txt" "$TMP/out.txt" && ok "old git: a normal path is STILL checked while the newline worktree exists (it must not poison the listing)" || fail "old git, plain path next to the newline one (rc=$rc): $(cat "$TMP/out.txt")"
PATH="$SHIM:$PATH" python3 "$WTPY" status >"$TMP/out.txt" 2>&1; rc=$?
[ "$rc" = 0 ] && grep -F "/r6-oldgit  [" "$TMP/out.txt" | grep -q "UNINTEGRATED" && grep -F "r6-nl2  [" "$TMP/out.txt" | grep -q "UNINTEGRATED.*dirty=?" \
  && ok "old git: status lists the truncated newline-path worktree as UNINTEGRATED (cannot say) instead of dying or skipping it" || fail "old git, status (rc=$rc): $(cat "$TMP/out.txt")"
PATH="$SHIM:$PATH" python3 "$WTPY" status --strict >/dev/null 2>&1; [ $? = 1 ] && ok "old git: status --strict exits 1 (held)" || fail "old git: status --strict"
out="$(cd "$R" && PATH="$SHIM:$PATH" python3 - "$DEVKIT_DIR/scripts/git" "$R" "$TMP/r6-oldgit" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import worktree as W
rows = W.inventory(sys.argv[2], only=[sys.argv[3]])   # what the Stop gate asks: it must get the row of the normal worktree, not an exception
print(len(rows), rows[0]["unintegrated"], rows[0]["path"].endswith("r6-oldgit"))
PY
)"
[ "$out" = "1 True True" ] && ok "old git: inventory(only=[a normal path]) answers with its row (the Stop gate holds; it used to exit through SystemExit = pass)" || fail "old git, inventory(only=): '$out'"
bash "$KIT" worktree remove "../r6-nl2${NL}z" >"$TMP/out.txt" 2>&1; refused "... and a current git still finds it (-z) and refuses it for its reflog-only commit" $? "$TMP/r6-nl2${NL}z" "UNREACHABLE" "$OLDSHA"
G "$R" branch rescue/nl2 "$OLDSHA"; bash "$KIT" worktree remove "../r6-nl2${NL}z" >"$TMP/out.txt" 2>&1; allowed "... and removes it once a branch holds the commit (the newline worktree is gone for the rest of the run)" $? "$TMP/r6-nl2${NL}z"
bash "$KIT" worktree remove ../r6-oldgit >/dev/null 2>&1
# ── P1-2: a BRANCH worktree is checked for commits only its reflog names ───────────────────────────────────────────────────────
w6 bdet feat1; G "$TMP/r6-bdet" checkout -q --detach; echo "detached work" >> "$TMP/r6-bdet/b.txt"; c6 bdet "made detached"; BSHA="$(G "$TMP/r6-bdet" rev-parse HEAD)"
G "$TMP/r6-bdet" checkout -q feat1
rm6 ../r6-bdet; refused "branch worktree: a commit made while detached, then back on the branch, is refused (reflog-only)" $? "$TMP/r6-bdet" "reflog" "$BSHA"
G "$R" branch rescue/bdet "$BSHA"; rm6 ../r6-bdet; allowed "branch worktree: ... and goes once a branch holds the commit" $? "$TMP/r6-bdet"

# a branch worktree that ALSO has an ordinary unmerged commit: the refusal talks about the reflog-only commit, not about a "detached HEAD"
w6 bdet2 feat8; echo "ordinary" >> "$TMP/r6-bdet2/c.txt"; c6 bdet2 "ordinary branch commit"
G "$TMP/r6-bdet2" checkout -q --detach; echo "detached work 2" >> "$TMP/r6-bdet2/d.txt"; c6 bdet2 "made detached 2"; B2SHA="$(G "$TMP/r6-bdet2" rev-parse HEAD)"; G "$TMP/r6-bdet2" checkout -q feat8
rm6 ../r6-bdet2; refused "branch worktree with an ordinary unmerged commit too: refused for the reflog-only one" $? "$TMP/r6-bdet2" "reflog" "$B2SHA"
[ -d "$TMP/r6-bdet2" ] && ! grep -q "detached HEAD (" "$TMP/out.txt" && grep -q "reflog" "$TMP/out.txt" && ok "branch worktree: the refusal does not talk about a detached HEAD" || fail "the refusal of a BRANCH worktree must not claim a detached HEAD: $(cat "$TMP/out.txt")"
G "$R" branch rescue/bdet2 "$B2SHA"; rm6 ../r6-bdet2; allowed "branch worktree: ... goes once a branch holds the commit" $? "$TMP/r6-bdet2"

w6 breset feat2; echo "one" >> "$TMP/r6-breset/c.txt"; c6 breset one; echo "two" >> "$TMP/r6-breset/c.txt"; c6 breset two
G "$TMP/r6-breset" reset -q --hard HEAD~1
rm6 ../r6-breset; allowed "branch worktree: reset --hard HEAD~1 (the branch reflog still holds the old tip) -> not a false refusal" $? "$TMP/r6-breset"

w6 bamend feat3; echo "one" >> "$TMP/r6-bamend/d.txt"; c6 bamend one; echo "typo" >> "$TMP/r6-bamend/d.txt"; G "$TMP/r6-bamend" add -A; G "$TMP/r6-bamend" commit -q --amend -m "one amended"
rm6 ../r6-bamend; allowed "branch worktree: commit --amend -> not a false refusal" $? "$TMP/r6-bamend"

w6 brebase feat4; echo "mine" >> "$TMP/r6-brebase/e.txt"; c6 brebase mine
echo "main moves" >> "$R/f.txt"; G "$R" commit -qam "main moves on"
G "$TMP/r6-brebase" rebase -q main >/dev/null 2>&1 || fail "rebase setup"
rm6 ../r6-brebase; allowed "branch worktree: rebased onto a moved main -> not a false refusal" $? "$TMP/r6-brebase"

w6 bswitch feat5; echo "x" >> "$TMP/r6-bswitch/a.txt"; c6 bswitch x; G "$TMP/r6-bswitch" switch -q -c feat5b; echo "y" >> "$TMP/r6-bswitch/a.txt"; c6 bswitch y; G "$TMP/r6-bswitch" switch -q feat5
rm6 ../r6-bswitch; allowed "branch worktree: switching between branches -> not a false refusal" $? "$TMP/r6-bswitch"

# one broken ref anywhere (an interrupted fetch left a remote-tracking ref on a missing object) must not make every branch worktree look lost,
# nor let a detached worktree's reflog-only commit through
mkdir -p "$R/.git/refs/remotes/origin" && echo "1111111111111111111111111111111111111111" > "$R/.git/refs/remotes/origin/broken"
w6 bbrk feat6; echo "one" >> "$TMP/r6-bbrk/e.txt"; c6 bbrk one; echo "two" >> "$TMP/r6-bbrk/e.txt"; c6 bbrk two; G "$TMP/r6-bbrk" reset -q --hard HEAD~1
rm6 ../r6-bbrk; allowed "broken ref: a branch worktree after reset --hard is still not a false refusal" $? "$TMP/r6-bbrk"
w6 bbrk2 feat7; G "$TMP/r6-bbrk2" checkout -q --detach; echo "detached work" >> "$TMP/r6-bbrk2/b.txt"; c6 bbrk2 "made detached"; BRSHA="$(G "$TMP/r6-bbrk2" rev-parse HEAD)"; G "$TMP/r6-bbrk2" checkout -q feat7
rm6 ../r6-bbrk2; refused "broken ref: a branch worktree's detached-then-returned commit is still refused" $? "$TMP/r6-bbrk2" "reflog" "$BRSHA"
reflog_only brk3; rm6 ../r6-brk3; refused "broken ref: a detached worktree's reflog-only commit is still refused" $? "$TMP/r6-brk3" "UNREACHABLE" "$SHA"
rm -f "$R/.git/refs/remotes/origin/broken"

# unreadable / corrupt HEAD reflog of a detached worktree: git log -g prints NOTHING and exits 0 -> must read as a blocker
reflog_only gar; GD="$(G "$TMP/r6-gar" rev-parse --absolute-git-dir)"; printf 'garbage line without structure\n' > "$GD/logs/HEAD"
rm6 ../r6-gar; refused "reflog: a corrupt HEAD reflog reads as a blocker, not as clean" $? "$TMP/r6-gar" "reflog.*(could not|cannot|unreadable)" "$SHA"
if [ "$(id -u)" != 0 ]; then
  reflog_only perm; GD="$(G "$TMP/r6-perm" rev-parse --absolute-git-dir)"; chmod 000 "$GD/logs/HEAD"
  rm6 ../r6-perm; refused "reflog: an unreadable (chmod 000) HEAD reflog reads as a blocker" $? "$TMP/r6-perm" "reflog.*(could not|cannot|unreadable)" "$SHA"
  chmod 644 "$GD/logs/HEAD"
fi

# ── P3: what the content fingerprint and git status did not see ────────────────────────────────────────────────────────────────
w6 mode; chmod +x "$TMP/r6-mode/a.txt"
rm6 ../r6-mode; refused "mode: chmod +x only on a tracked file is a change main does not hold -> refused, names the file" $? "$TMP/r6-mode" "a.txt"
chmod +x "$R/a.txt"; rm6 ../r6-mode; allowed "mode: ... and goes once main has the file with the same mode" $? "$TMP/r6-mode"; chmod -x "$R/a.txt"

# a worktree made before the mode was recorded (its state has no "fp" marker) keeps its old baselines: an executable file of the setup is not a change
w6 oldst; echo '#!/bin/sh' > "$TMP/r6-oldst/setup.sh"; chmod +x "$TMP/r6-oldst/setup.sh"   # (main does not have it: only the baseline can excuse it)
python3 - "$(G "$TMP/r6-oldst" rev-parse --absolute-git-dir)/devkit-worktree.json" "$TMP/r6-oldst/setup.sh" <<'PY'
import hashlib, json, sys
p, f = sys.argv[1], sys.argv[2]
st = json.load(open(p))
st.pop("fp", None)
st["baseline"]["setup.sh"] = "F:" + hashlib.sha1(open(f, "rb").read()).hexdigest()   # the pre-r6 format: no mode
json.dump(st, open(p, "w"))
PY
rm6 ../r6-oldst; allowed "mode: an OLD state file (baseline without the mode) does not make the setup's executable files look changed" $? "$TMP/r6-oldst"
w6 newst; echo '#!/bin/sh' > "$TMP/r6-newst/setup.sh"; chmod +x "$TMP/r6-newst/setup.sh"
python3 - "$(G "$TMP/r6-newst" rev-parse --absolute-git-dir)/devkit-worktree.json" "$TMP/r6-newst/setup.sh" <<'PY'
import hashlib, json, sys
p, f = sys.argv[1], sys.argv[2]
st = json.load(open(p))
st["baseline"]["setup.sh"] = "F:" + hashlib.sha1(open(f, "rb").read()).hexdigest()   # a baseline WITH the marker but without the mode: not excused
json.dump(st, open(p, "w"))
PY
rm6 ../r6-newst; refused "mode: ... but a state that records the mode compares it (the same file without the bit in its baseline is a change)" $? "$TMP/r6-newst" "setup.sh"

w6 skipw; G "$TMP/r6-skipw" update-index --skip-worktree a.txt; echo "hidden precious edit" >> "$TMP/r6-skipw/a.txt"
python3 "$WTPY" status 2>&1 | grep -F "/r6-skipw  [" | grep -q "UNINTEGRATED" && ok "hidden: worktree status flags the hidden edit as UNINTEGRATED" || fail "hidden edit not seen by status"
rm6 ../r6-skipw; refused "hidden: an edit of a skip-worktree file (git status shows nothing) -> refused" $? "$TMP/r6-skipw" "a.txt"
w6 assume; G "$TMP/r6-assume" update-index --assume-unchanged b.txt; echo "hidden precious edit" >> "$TMP/r6-assume/b.txt"
rm6 ../r6-assume; refused "hidden: an edit of an assume-unchanged file -> refused" $? "$TMP/r6-assume" "b.txt"
w6 gone; G "$TMP/r6-gone" update-index --assume-unchanged b.txt; rm "$TMP/r6-gone/b.txt"
rm6 ../r6-gone; refused "hidden: a DELETED assume-unchanged file (git status shows nothing) -> refused" $? "$TMP/r6-gone" "b.txt"
SHIM2="$TMP/shim2"; mkdir -p "$SHIM2"
{ echo '#!/bin/bash'
  echo 'l=0; v=0; for a in "$@"; do case "$a" in ls-files) l=1;; -v) v=1;; esac; done'
  echo '[ $l = 1 ] && [ $v = 1 ] && { echo "fatal: simulated failure" >&2; exit 128; }'
  echo "exec \"$REALGIT\" \"\$@\""; } > "$SHIM2/git"
chmod +x "$SHIM2/git"
w6 hfail; PATH="$SHIM2:$PATH" bash "$KIT" worktree remove ../r6-hfail >"$TMP/out.txt" 2>&1; rc=$?
refused "hidden: when git cannot list the files it hides, the removal is refused (never read as 'nothing hidden')" "$rc" "$TMP/r6-hfail" "could not be listed"
w6 skipok; G "$TMP/r6-skipok" update-index --skip-worktree a.txt; G "$TMP/r6-skipok" update-index --assume-unchanged b.txt
rm6 ../r6-skipok; allowed "hidden: flagged files nobody edited do not hold the removal" $? "$TMP/r6-skipok"
w6 sparse; G "$TMP/r6-sparse" update-index --skip-worktree c.txt; rm -f "$TMP/r6-sparse/c.txt"
rm6 ../r6-sparse; allowed "hidden: a skip-worktree file that is absent (sparse checkout) does not hold the removal" $? "$TMP/r6-sparse"

# a tracked path that is not UTF-8 (staged in the index only: APFS cannot hold such a file) must not make the listing of hidden files raise
w6 badname; python3 - "$TMP/r6-badname" <<'PY'
import subprocess, sys
w = sys.argv[1]
blob = subprocess.run(["git", "-C", w, "hash-object", "-w", "--stdin"], input=b"x\n", capture_output=True, check=True).stdout.strip()
name = b"bad\xff.txt"
subprocess.run(["git", "-C", w, "update-index", "--add", "--cacheinfo", b"100644," + blob + b"," + name], check=True)
subprocess.run(["git", "-C", w, "update-index", "--skip-worktree", name], check=True)
PY
python3 "$WTPY" status >"$TMP/out.txt" 2>&1; rc=$?
[ "$rc" = 0 ] && grep -F "/r6-badname  [" "$TMP/out.txt" | grep -q "UNINTEGRATED.*dirty=1" && ok "non-UTF-8 tracked path: status still counts the worktree (dirty=1, no traceback, no 'dirty=?')" || fail "non-UTF-8 path, status (rc=$rc): $(grep -F -e badname -e Error "$TMP/out.txt" | head -3)"
rm6 ../r6-badname; rc=$?
[ "$rc" = 1 ] && [ -d "$TMP/r6-badname" ] && grep -q "cannot check" "$TMP/out.txt" && ! grep -q "Traceback" "$TMP/out.txt" && ok "non-UTF-8 tracked path: remove refuses with a message (it cannot compare a name that is not UTF-8), no traceback" || fail "non-UTF-8 path, remove (rc=$rc): $(head -c 300 "$TMP/out.txt")"
python3 - "$TMP/r6-badname" <<'PY'
import subprocess, sys
w, name = sys.argv[1], b"bad\xff.txt"
subprocess.run(["git", "-C", w, "update-index", "--no-skip-worktree", name], check=True)
subprocess.run(["git", "-C", w, "update-index", "--force-remove", name], check=True)
PY
rm6 ../r6-badname; allowed "non-UTF-8 tracked path: ... and the worktree goes once the odd entry is gone" $? "$TMP/r6-badname"

w6 nest; mkdir -p "$TMP/r6-nest/vendored" "$R/vendored"; echo "main copy" > "$R/vendored/f"
G "$TMP/r6-nest/vendored" init -q -b main . && echo "precious nested repo" > "$TMP/r6-nest/vendored/f" && G "$TMP/r6-nest/vendored" add -A && G "$TMP/r6-nest/vendored" commit -qm "nested work"
rm6 ../r6-nest; refused "nested repo: an untracked nested repository whose path also exists in main is NOT 'the same' (both are directories)" $? "$TMP/r6-nest" "vendored"
rm -rf "$R/vendored"

# _ignorable (the BOOKKEEPING paths that do not count as work): a git failure must not read as 'no status file in rev'
out="$(cd "$R" && python3 - "$DEVKIT_DIR/scripts/git" "$R" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import worktree as w
head = w.git(sys.argv[2], "rev-parse", "HEAD").stdout.strip()
nofile = w._ignorable(sys.argv[2], head, head)                    # the commit has no status file: nothing authored there -> all ignorable
broken = w._ignorable(sys.argv[2], head, "0" * 40)                # git cannot read that revision -> the status file must count
print(w.STATUS_FILE in nofile, w.STATUS_FILE in broken)
PY
)"
[ "$out" = "True False" ] && ok "_ignorable: no status file in the revision -> bookkeeping ignorable; a git failure -> the status file counts (fail closed)" || fail "_ignorable: '$out' (expected 'True False')"

# ── the contract stream C relies on is unchanged ───────────────────────────────────────────────────────────────────────────────
out="$(cd "$R" && python3 - "$DEVKIT_DIR/scripts/git" "$R" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1])
import worktree as w
try:
    w.removal_blockers("/nonexistent-dir-for-test", "/nonexistent-dir-for-test/x")
    print("returned")
except SystemExit:
    print("SystemExit")   # git failing in main_checkout / worktree list / status: documented in the docstring
except Exception as e:
    print("Exception " + type(e).__name__)
doc = w.removal_blockers.__doc__
print("raises SystemExit" in doc)
PY
)"
[ "$out" = "SystemExit${NL}True" ] && ok "removal_blockers: raises SystemExit when git cannot run, and its docstring says so" || fail "removal_blockers contract: '$out'"

# ── P2: submodules ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
L="$TMP/lib6"; mkdir -p "$L" && G "$L" init -q -b main . && echo 1 > "$L/f" && G "$L" add -A && G "$L" commit -qm lib
G "$R" -c protocol.file.allow=always submodule add -q "$L" lib >/dev/null 2>&1 && G "$R" commit -qm "add the submodule"
subwt() { w6 "$1"; G "$TMP/r6-$1" -c protocol.file.allow=always submodule update -q --init >/dev/null 2>&1; }   # subwt <name>

subwt sclean
rm6 ../r6-sclean; allowed "submodule: initialized, clean, at the recorded commit (main holds it) -> goes" $? "$TMP/r6-sclean"

subwt snomain; mv "$R/.git/modules/lib" "$TMP/lib-module-away"
rm6 ../r6-snomain; refused "submodule: the main checkout has no copy of it to compare with -> refused (cannot verify), says to initialize/fetch there" $? "$TMP/r6-snomain" "submodule"
mv "$TMP/lib-module-away" "$R/.git/modules/lib"
rm6 ../r6-snomain; allowed "submodule: ... and goes once main's copy is back" $? "$TMP/r6-snomain"

subwt sdirty; G "$TMP/r6-sdirty" config diff.ignoreSubmodules all; echo "uncommitted submodule work" > "$TMP/r6-sdirty/lib/f"
[ -z "$(G "$TMP/r6-sdirty" status --porcelain | grep -v '^??')" ] || fail "setup: git status should hide the submodule edit"
rm6 ../r6-sdirty; refused "submodule: an uncommitted edit inside it (hidden from git status) -> refused, names the submodule" $? "$TMP/r6-sdirty" "submodule.*uncommitted|uncommitted.*submodule"
G "$R" config --unset diff.ignoreSubmodules   # (the config is shared by every worktree of the repository)

subwt suntr; echo "untracked precious" > "$TMP/r6-suntr/lib/new-file"
rm6 ../r6-suntr; refused "submodule: an untracked file inside it -> refused" $? "$TMP/r6-suntr" "submodule"

subwt sback; echo "sub work" > "$TMP/r6-sback/lib/f"; G "$TMP/r6-sback/lib" commit -qam "sub work"; SUBSHA="$(G "$TMP/r6-sback/lib" rev-parse HEAD)"
G "$TMP/r6-sback/lib" checkout -q --detach HEAD~1
rm6 ../r6-sback; refused "submodule: a commit, then HEAD moved back (only the submodule's reflog names it) -> refused" $? "$TMP/r6-sback" "submodule"

subwt sfake; echo "sub work" > "$TMP/r6-sfake/lib/f"; G "$TMP/r6-sfake/lib" commit -qam "sub work"
G "$TMP/r6-sfake/lib" update-ref refs/remotes/origin/wip HEAD    # a ref the agent wrote by hand: nothing was pushed
rm6 ../r6-sfake; refused "submodule: a hand-written refs/remotes in the worktree's own module does not count as pushed" $? "$TMP/r6-sfake" "submodule"

subwt spush; echo "sub work" > "$TMP/r6-spush/lib/f"; G "$TMP/r6-spush/lib" commit -qam "sub work"
G "$TMP/r6-spush/lib" push -q origin HEAD:refs/heads/sub-work >/dev/null 2>&1
rm6 ../r6-spush; refused "submodule: pushed from the worktree, but the MAIN checkout's copy does not have it yet -> refused, says to fetch there" $? "$TMP/r6-spush" "fetch"
G "$R/lib" fetch -q origin >/dev/null 2>&1
rm6 ../r6-spush; refused "submodule: ... fetched there, the worktree's moved pointer (an uncommitted change of the superproject) is still not in main" $? "$TMP/r6-spush" "not in the main checkout"
G "$R/lib" checkout -q "$(G "$TMP/r6-spush/lib" rev-parse HEAD)" && G "$R" add lib && G "$R" commit -qm "bring back the submodule pointer"
rm6 ../r6-spush; allowed "submodule: ... once main's copy holds the commit on a remote ref AND main records the pointer -> goes" $? "$TMP/r6-spush"

# a pointer main records elsewhere, and a nested repo that is not a submodule, are not 'the same'
subwt sptr; echo "sub work 2" > "$TMP/r6-sptr/lib/f"; G "$TMP/r6-sptr/lib" commit -qam "sub work 2"; G "$TMP/r6-sptr/lib" push -q origin HEAD:refs/heads/sub-work2 >/dev/null 2>&1; G "$R/lib" fetch -q origin >/dev/null 2>&1
rm6 ../r6-sptr; refused "submodule: pushed and fetched, but main records another commit for it -> refused" $? "$TMP/r6-sptr" "not in the main checkout"


# ═══ ROUND 7 ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
# the scratch-dir guard itself: a failing / odd mktemp must never leave TMP at the cwd
( mktemp() { return 1; }; mk_tmp >/dev/null 2>&1 ) && fail "TMP guard: a failing mktemp was accepted" || ok "TMP guard: a failing mktemp is refused"
( mktemp() { echo ""; }; mk_tmp >/dev/null 2>&1 ) && fail "TMP guard: an empty mktemp result was accepted" || ok "TMP guard: an empty mktemp result is refused"
( mktemp() { echo "relative-dir"; }; mk_tmp >/dev/null 2>&1 ) && fail "TMP guard: a relative mktemp result was accepted" || ok "TMP guard: a relative mktemp result is refused"

bounded() {   # bounded <seconds> <command...>: output in $TMP/out.txt; exit code 124 when it did not finish
  python3 - "$1" "$TMP/out.txt" "${@:2}" <<'PY'
import subprocess, sys
t, out, argv = float(sys.argv[1]), sys.argv[2], sys.argv[3:]
try:
    r = subprocess.run(argv, capture_output=True, text=True, timeout=t)
    open(out, "w").write(r.stdout + r.stderr)
    sys.exit(r.returncode)
except subprocess.TimeoutExpired:
    open(out, "w").write("TIMED OUT after %ss" % t)
    sys.exit(124)
PY
}
HANGSLEEP=$((3100 + $$ % 800))   # a sleep length no other run of this test uses: the orphan check below looks for exactly this process
mkshim() {   # mkshim <name> '<case pattern over " $* ">': a git that fails (exit 128) on matching calls, or hangs (<name> = hang*)
  mkdir -p "$TMP/shim-$1"
  case "$1" in
    hang*) printf '#!/bin/bash\ncase " $* " in %s) exec sleep %s;; esac\nexec "%s" "$@"\n' "$2" "$HANGSLEEP" "$REALGIT" > "$TMP/shim-$1/git" ;;
    *) printf '#!/bin/bash\ncase " $* " in %s) echo "fatal: simulated failure" >&2; exit 128;; esac\nexec "%s" "$@"\n' "$2" "$REALGIT" > "$TMP/shim-$1/git" ;;
  esac
  chmod +x "$TMP/shim-$1/git"
}
inv() {   # inv <shim name> <worktree>: "dirty ahead unintegrated reflog" of inventory(only=) with that shim first on PATH
  (cd "$R" && PATH="$TMP/shim-$1:$PATH" python3 - "$DEVKIT_DIR/scripts/git" "$R" "$2" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import worktree as W
r = W.inventory(sys.argv[2], only=sys.argv[3])[0]
print(r["dirty"], r["ahead"], r["unintegrated"], r["reflog"])
PY
  )
}

# ── a FIFO planted in the git dir (the agent can write there) or a git call that never returns: a bounded refusal, never a hang ──
reflog_only fifo1; FIFOSHA="$SHA"; GD1="$(G "$TMP/r6-fifo1" rev-parse --absolute-git-dir)"; rm -f "$GD1/logs/HEAD"; mkfifo "$GD1/logs/HEAD"
DEVKIT_WORKTREE_GIT_TIMEOUT_S=120 bounded 40 bash "$KIT" worktree remove ../r6-fifo1; rc=$?   # (a 120 s git timeout: only NOT calling git on the FIFO finishes in time)
refused "FIFO as the HEAD reflog of a DETACHED worktree: remove is refused at once (not hung, not removed)" "$rc" "$TMP/r6-fifo1" "reflog" "$FIFOSHA"
w6 difa; echo "difa-work" > "$TMP/r6-difa/difa.txt"
DEVKIT_WORKTREE_GIT_TIMEOUT_S=120 bounded 40 bash "$KIT" worktree diff ../r6-difa; rc=$?
[ "$rc" = 0 ] && grep -q "difa-work" "$TMP/out.txt" && ok "FIFO reflog in ANOTHER worktree: worktree diff of a clean one still finishes (it ran the inventory of all of them and hung)" || fail "worktree diff next to a FIFO reflog (rc=$rc): $(head -c 300 "$TMP/out.txt")"
rm -f "$GD1/logs/HEAD"
w6 fifo2 feat9; echo "x" >> "$TMP/r6-fifo2/e.txt"; c6 fifo2 "fifo2 work"; GD2="$(G "$TMP/r6-fifo2" rev-parse --absolute-git-dir)"; rm -f "$GD2/logs/HEAD"; mkfifo "$GD2/logs/HEAD"
DEVKIT_WORKTREE_GIT_TIMEOUT_S=120 bounded 40 bash "$KIT" worktree remove ../r6-fifo2; rc=$?
refused "FIFO as the HEAD reflog of a BRANCH worktree: remove is refused at once" "$rc" "$TMP/r6-fifo2" "reflog"
rm -f "$GD2/logs/HEAD"
w6 fifo3; GD3="$(G "$TMP/r6-fifo3" rev-parse --absolute-git-dir)"; rm -f "$GD3/devkit-worktree.json"; mkfifo "$GD3/devkit-worktree.json"
bounded 40 bash "$KIT" worktree remove ../r6-fifo3; rc=$?
[ "$rc" = 2 ] && [ -d "$TMP/r6-fifo3" ] && grep -q "was not made by" "$TMP/out.txt" && ok "FIFO as devkit-worktree.json: remove is refused (state unreadable = not ours), not hung" || fail "FIFO state file (rc=$rc): $(head -c 300 "$TMP/out.txt")"
rm -f "$GD3/devkit-worktree.json"

mkshim hangstatus '*" status "*'
w6 hang; echo "x" >> "$TMP/r6-hang/e.txt"
DEVKIT_WORKTREE_GIT_TIMEOUT_S=2 PATH="$TMP/shim-hangstatus:$PATH" bounded 90 bash "$KIT" worktree remove ../r6-hang; rc=$?
[ "$rc" != 0 ] && [ "$rc" != 124 ] && [ -d "$TMP/r6-hang" ] && ok "a git call that never returns (status hangs): remove is refused after the timeout, not hung" || fail "hanging git (rc=$rc): $(head -c 300 "$TMP/out.txt")"
pgrep -f "sleep $HANGSLEEP" >/dev/null && fail "the timed-out git child was left running (orphan)" || ok "the timed-out git child is killed (no orphan)"
out="$(cd "$R" && PATH="$TMP/shim-hangstatus:$PATH" python3 - "$DEVKIT_DIR/scripts/git" "$R" "$TMP/r6-hang" <<'PY'
import signal, sys, time
sys.path.insert(0, sys.argv[1])
import worktree as W
signal.signal(signal.SIGALRM, lambda *a: (_ for _ in ()).throw(RuntimeError("the hook alarm fired")))
signal.alarm(6)          # a hook (the Stop gate has 8 s) armed its alarm: the verdict must come before it
t = time.time()
r = W.inventory(sys.argv[2], only=sys.argv[3])[0]
signal.alarm(0)
print(round(time.time() - t) < 6, r["unintegrated"], r["dirty"])
PY
)"
[ "$out" = "True True None" ] && ok "inside a hook alarm the timeout stays shorter than the alarm: the row says cannot-say (unintegrated), the alarm never fires" || fail "inventory inside an alarm: '$out'"
pgrep -f "sleep $HANGSLEEP" >/dev/null && fail "orphan after the alarm test" || ok "... and nothing is left running"

# ── the ref tips are read ONCE per inventory call, also for several worktrees (the Stop gate asks for all of them in one call) ──
w6 cnt1; w6 cnt2; w6 cnt3
out="$(cd "$R" && GIT_TRACE="$TMP/trace.txt" python3 - "$DEVKIT_DIR/scripts/git" "$R" "$TMP/r6-cnt1" "$TMP/r6-cnt2" "$TMP/r6-cnt3" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import worktree as W
rows = W.inventory(sys.argv[2], only=sys.argv[3:])
print(len(rows))
PY
)"
[ "$out" = "3" ] && [ "$(grep -c "built-in: git for-each-ref" "$TMP/trace.txt")" = 1 ] && ok "inventory(only=[3 worktrees]) answers with 3 rows and ONE for-each-ref (not one per worktree)" || fail "ref scans: rows='$out', for-each-ref calls=$(grep -c 'built-in: git for-each-ref' "$TMP/trace.txt")"

# ── a squash / fixup brought back as ONE diff (the documented flow), then the worktree refreshed: nothing is left to lose ────────
printf 'base\n' > "$R/n1.txt"; printf 'base\n' > "$R/n2.txt"; printf '.claude/\n' > "$R/.gitignore"; G "$R" add -A && G "$R" commit -qm "n1 n2 and .gitignore for the round 7 scenarios"
bring_back() { bash "$KIT" worktree diff "../r6-$1" 2>/dev/null | git apply --3way >/dev/null 2>&1 && G "$R" add -A && G "$R" commit -qm "bring back $1" || fail "bring back $1"; }
w6 sq1; for i in 1 2; do echo "s$i" >> "$TMP/r6-sq1/e.txt"; c6 sq1 "s$i"; done
bring_back sq1; G "$TMP/r6-sq1" checkout -q --detach main
rm6 ../r6-sq1; allowed "squash: two commits to one file, brought back as ONE diff, worktree refreshed with checkout --detach main -> allowed" $? "$TMP/r6-sq1"
w6 sq2; for i in 1 2 3; do echo "q$i" >> "$TMP/r6-sq2/d.txt"; c6 sq2 "q$i"; done; G "$TMP/r6-sq2" reset -q --soft HEAD~3; G "$TMP/r6-sq2" commit -qm "squashed"
bring_back sq2
rm6 ../r6-sq2; allowed "squash: three commits squashed with reset --soft, brought back -> allowed" $? "$TMP/r6-sq2"
w6 sq3 featsq3; for i in 1 2 3; do echo "f$i" >> "$TMP/r6-sq3/c.txt"; c6 sq3 "f$i"; done
GIT_SEQUENCE_EDITOR="sed -i.bak -e '2s/^pick/fixup/' -e '3s/^pick/fixup/'" GIT_EDITOR=true git -C "$TMP/r6-sq3" -c user.email=t@t -c user.name=t rebase -q -i HEAD~3 >/dev/null 2>&1 || fail "interactive rebase setup (branch)"
bring_back sq3
rm6 ../r6-sq3; allowed "interactive rebase with fixup on a BRANCH worktree, brought back as one diff -> allowed" $? "$TMP/r6-sq3"
w6 sq4; for i in 1 2 3; do echo "g$i" >> "$TMP/r6-sq4/b.txt"; c6 sq4 "g$i"; done
GIT_SEQUENCE_EDITOR="sed -i.bak -e '2s/^pick/fixup/' -e '3s/^pick/fixup/'" GIT_EDITOR=true git -C "$TMP/r6-sq4" -c user.email=t@t -c user.name=t rebase -q -i HEAD~3 >/dev/null 2>&1 || fail "interactive rebase setup (detached)"
bring_back sq4
rm6 ../r6-sq4; allowed "interactive rebase with fixup on a DETACHED worktree, brought back as one diff -> allowed" $? "$TMP/r6-sq4"
# the counter-cases: the part that is NOT in main must still hold the removal
w6 sq5; echo "x1" >> "$TMP/r6-sq5/n1.txt"; c6 sq5 "x1"; X1="$(G "$TMP/r6-sq5" rev-parse HEAD)"; echo "x2" >> "$TMP/r6-sq5/n1.txt"; c6 sq5 "x2"; X2="$(G "$TMP/r6-sq5" rev-parse HEAD)"
G "$R" cherry-pick "$X1" >/dev/null 2>&1; G "$TMP/r6-sq5" checkout -q --detach main
rm6 ../r6-sq5; refused "squash counter-case: only the FIRST of two commits is in main -> refused, names the second" $? "$TMP/r6-sq5" "${X2:0:7}" "$X2"
w6 sq6; echo "new file" > "$TMP/r6-sq6/g6.txt"; c6 sq6 "adds g6"; Y1="$(G "$TMP/r6-sq6" rev-parse HEAD)"; echo "y2" >> "$TMP/r6-sq6/n2.txt"; c6 sq6 "edits n2"; Y2="$(G "$TMP/r6-sq6" rev-parse HEAD)"
G "$R" cherry-pick "$Y2" >/dev/null 2>&1; G "$TMP/r6-sq6" checkout -q --detach main
rm6 ../r6-sq6; refused "squash counter-case: the LATER commit is in main but the earlier one added a file main lacks -> refused" $? "$TMP/r6-sq6" "${Y1:0:7}" "$Y1"
w6 sq7; G "$TMP/r6-sq7" commit -q --allow-empty -m "decision notes (empty commit)"; Z0="$(G "$TMP/r6-sq7" rev-parse HEAD)"; echo "z1" >> "$TMP/r6-sq7/n1.txt"; c6 sq7 "z1"; Z1="$(G "$TMP/r6-sq7" rev-parse HEAD)"
G "$R" cherry-pick "$Z1" >/dev/null 2>&1; G "$TMP/r6-sq7" checkout -q --detach main
rm6 ../r6-sq7; refused "squash counter-case: an EMPTY commit (a message) in the chain is not covered by the content of its neighbour -> refused" $? "$TMP/r6-sq7" "${Z0:0:7}" "$Z0"

# ── nested registered worktree / core.worktree elsewhere / shell-quoted advice ─────────────────────────────────────────────────
w6 nest2; mkdir -p "$TMP/r6-nest2/.claude/worktrees"; G "$R" worktree add -q --detach "$TMP/r6-nest2/.claude/worktrees/inner" >/dev/null 2>&1; echo "unsaved inner work" > "$TMP/r6-nest2/.claude/worktrees/inner/inner.txt"
rm6 ../r6-nest2; refused "nested: another registered worktree INSIDE the target (in an ignored folder, with unsaved work) -> refused" $? "$TMP/r6-nest2" "INSIDE"
R2="$TMP/r6t"; mkdir -p "$R2" && G "$R2" init -q -b main . && echo t > "$R2/t.txt" && G "$R2" add -A && G "$R2" commit -qm t && ( cd "$R2" && bash "$KIT" worktree add ../r6t-w >/dev/null 2>&1 )
G "$R2" config extensions.worktreeConfig true && G "$TMP/r6t-w" config --worktree core.worktree "$R2"
( cd "$R2" && bash "$KIT" worktree remove ../r6t-w >"$TMP/out.txt" 2>&1 ); rc=$?
refused "core.worktree: a worktree whose work tree git takes to be ANOTHER directory (the checks would run there) -> refused" "$rc" "$TMP/r6t-w" "work tree to be"
G "$TMP/r6t-w" config --worktree --unset core.worktree 2>/dev/null
reflog_only "sp ace"; rm6 "../r6-sp ace"; refused "advice: the path with a space is shell-quoted in the git worktree remove --force text" $? "$TMP/r6-sp ace" "--force '[^']*r6-sp ace'" "$SHA"

# ── the failures the mutation run found unguarded: each one must read as cannot-say, never as clean ─────────────────────────────
mkshim failstatus '*" status "*'; mkshim failcount '*" rev-list --count "*'; mkshim failhidden '*" ls-files -v "*'; mkshim failglob '*"--glob=refs/heads"*'
w6 sf; echo "x" >> "$TMP/r6-sf/e.txt"
[ "$(inv failstatus "$TMP/r6-sf")" = "None 0 True []" ] && ok "git status fails: dirty is None (unintegrated), not 0" || fail "status failure: '$(inv failstatus "$TMP/r6-sf")'"
[ "$(inv failcount "$TMP/r6-sf" | cut -d' ' -f2-3)" = "None True" ] && ok "git rev-list --count fails: ahead is None (unintegrated), not 0" || fail "count failure: '$(inv failcount "$TMP/r6-sf")'"
[ "$(inv failhidden "$TMP/r6-sf" | cut -d' ' -f1,3)" = "None True" ] && ok "git ls-files -v fails: the dirty count of the inventory is None (unintegrated)" || fail "ls-files -v failure: '$(inv failhidden "$TMP/r6-sf")'"
w6 m29 feat29; echo "one" >> "$TMP/r6-m29/f.txt"; c6 m29 one; echo "two" >> "$TMP/r6-m29/f.txt"; c6 m29 two; G "$TMP/r6-m29" reset -q --hard HEAD~1
PATH="$TMP/shim-failglob:$PATH" bash "$KIT" worktree remove ../r6-m29 >"$TMP/out.txt" 2>&1; rc=$?
refused "the branch reflogs cannot be listed: the reset --hard on a branch is refused (cannot say), not waved through" "$rc" "$TMP/r6-m29" "reflog"
mkshim failsubstatus '*"/lib "*"status "*'
subwt ssf; PATH="$TMP/shim-failsubstatus:$PATH" bash "$KIT" worktree remove ../r6-ssf >"$TMP/out.txt" 2>&1; rc=$?
refused "submodule: its git status fails -> refused (cannot say), never read as clean" "$rc" "$TMP/r6-ssf" "submodule"
out="$(cd "$R" && python3 - "$DEVKIT_DIR/scripts/git" "$R" "$TMP/r6-sf" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1])
import worktree as W
w = sys.argv[3]
for n in ("h1", "h2", "h3"):
    open(os.path.join(w, n + ".txt"), "w").write("x\n")
os.system("git -C '%s' add -A >/dev/null 2>&1 && git -C '%s' -c user.email=t@t -c user.name=t commit -qm hid >/dev/null 2>&1 && git -C '%s' update-index --assume-unchanged h1.txt h2.txt h3.txt" % (w, w, w))
W.HIDDEN_CHECK_MAX = 2
many = W._hidden_edits(w)
os.symlink("e.txt", os.path.join(w, "lnk"))
print(sorted(many), W.fingerprint(os.path.join(w, "lnk")).startswith("L:"))
PY
)"
[ "$out" = "['h1.txt', 'h2.txt', 'h3.txt'] True" ] && ok "more flagged files than can be compared: they all count; a symlink fingerprints as a link, not as its target" || fail "limits: '$out'"


# ═══ ROUND 8 ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
# ONE shared deadline for a whole inventory: after the first hung git call every worktree not judged yet is held, not waved through by the hook alarm
mkshim hangstatus2 '*" status "*'
w6 bd1; w6 bd2; w6 bd3
out="$(cd "$R" && PATH="$TMP/shim-hangstatus2:$PATH" python3 - "$DEVKIT_DIR/scripts/git" "$R" "$TMP/r6-bd1" "$TMP/r6-bd2" "$TMP/r6-bd3" <<'PY'
import signal, sys, time
sys.path.insert(0, sys.argv[1])
import worktree as W
signal.signal(signal.SIGALRM, lambda *a: (_ for _ in ()).throw(RuntimeError("the hook alarm fired")))
signal.alarm(6)          # a hook armed its alarm (the Stop gate has 8 s); the budget must end before it
t = time.time()
rows = W.inventory(sys.argv[2], only=sys.argv[3:])
signal.alarm(0)
print(len(rows), round(time.time() - t) < 6, all(r["unintegrated"] for r in rows))
PY
)"
[ "$out" = "3 True True" ] && ok "3 worktrees, the first git status hangs inside a hook alarm: all 3 rows come back unintegrated before the alarm (one shared deadline)" || fail "shared deadline inside an alarm: '$out'"
out="$(cd "$R" && DEVKIT_WORKTREE_BUDGET_S=3 PATH="$TMP/shim-hangstatus2:$PATH" python3 - "$DEVKIT_DIR/scripts/git" "$R" "$TMP/r6-bd1" "$TMP/r6-bd2" "$TMP/r6-bd3" <<'PY'
import sys, time
sys.path.insert(0, sys.argv[1])
import worktree as W
t = time.time()
rows = W.inventory(sys.argv[2], only=sys.argv[3:])
print(len(rows), round(time.time() - t) < 8, all(r["unintegrated"] for r in rows))
PY
)"
[ "$out" = "3 True True" ] && ok "no alarm: DEVKIT_WORKTREE_BUDGET_S=3 ends the whole inventory after 3 s, not 3 hung calls of 30 s" || fail "shared deadline without an alarm: '$out'"
pgrep -f "sleep $HANGSLEEP" >/dev/null && fail "orphan after the shared-deadline tests" || ok "... and nothing is left running"
# the per-tip loop of _reflog_only honours the deadline: what is not judged yet is lost (held), also when the commits would all be fine
out="$(cd "$R" && python3 - "$DEVKIT_DIR/scripts/git" "$R" "$TMP/r6-sq1" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import worktree as W
mh = W.git(sys.argv[2], "rev-parse", "HEAD").stdout.strip()
# a detached worktree whose two reflog-only commits are both in main as one patch (squash): judged clean while the budget lasts
import subprocess, os, tempfile
wt = tempfile.mkdtemp(prefix="dl.")
os.rmdir(wt)
subprocess.run(["git", "-C", sys.argv[2], "worktree", "add", "-q", "--detach", wt], check=True, capture_output=True)
env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
for i in (1, 2):
    open(os.path.join(wt, "dl.txt"), "a").write("dl%d\n" % i)
    subprocess.run(["git", "-C", wt, "add", "-A"], check=True, env=env)
    subprocess.run(["git", "-C", wt, "commit", "-qm", "dl%d" % i], check=True, env=env)
subprocess.run(["cp", os.path.join(wt, "dl.txt"), os.path.join(sys.argv[2], "dl.txt")], check=True)
subprocess.run(["git", "-C", sys.argv[2], "add", "-A"], check=True, env=env)
subprocess.run(["git", "-C", sys.argv[2], "commit", "-qm", "dl brought back"], check=True, env=env)
subprocess.run(["git", "-C", wt, "checkout", "-q", "--detach", "main"], check=True, env=env)
head = W.git(wt, "rev-parse", "HEAD").stdout.strip()
mh = W.git(sys.argv[2], "rev-parse", "HEAD").stdout.strip()
live = W._reflog_only(wt, head, mh, [], attached=False)
orig, real_spent, n = W._run, W._spent, [0]
def counting(*a, **k):
    r = orig(*a, **k)
    n[0] += 1
    return r
W._run = counting
W._spent = lambda: n[0] >= 3     # the three calls before the per-commit loop (reflog path, log -g, rev-list) ran; the deadline is gone from here on
spent = W._reflog_only(wt, head, mh, [], attached=False)
after = n[0]                     # 3 = the loop started NO git call once the deadline was gone
W._run, W._spent = orig, real_spent
import time
W._BUDGET.append(time.monotonic() - 1)       # a spent deadline: git() must not even start the process
refused = W.git(sys.argv[2], "rev-parse", "HEAD", check=False).returncode
del W._BUDGET[:]
print(len(live), len(spent), after, refused)
PY
)"
[ "$out" = "0 2 3 124" ] && ok "_reflog_only: both squashed commits are clean while the budget lasts (0 lost), both are lost once it is spent (2) without another git call; git() starts nothing once the deadline is spent (124)" || fail "_reflog_only deadline: '$out'"

# mutating git calls (worktree add, remove --force) are NOT bounded by the 30 s read-only limit: a killed one leaves a half checkout / a half-deleted folder
{ printf '#!/bin/bash\ncase " $* " in *" worktree add "*|*" worktree remove "*) sleep 3;; esac\nexec "%s" "$@"\n' "$REALGIT"; } > "$TMP/shim-slowmut.git"; mkdir -p "$TMP/shim-slowmut"; mv "$TMP/shim-slowmut.git" "$TMP/shim-slowmut/git"; chmod +x "$TMP/shim-slowmut/git"
DEVKIT_WORKTREE_GIT_TIMEOUT_S=1 PATH="$TMP/shim-slowmut:$PATH" bounded 60 bash "$KIT" worktree add ../r6-slowadd --no-init; rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/r6-slowadd/.git" ] && ok "worktree add that takes 3 s completes under a 1 s read-only bound" || fail "slow worktree add (rc=$rc): $(head -c 300 "$TMP/out.txt")"
DEVKIT_WORKTREE_GIT_TIMEOUT_S=1 PATH="$TMP/shim-slowmut:$PATH" bounded 60 bash "$KIT" worktree remove ../r6-slowadd; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/r6-slowadd" ] && ok "worktree remove --force that takes 3 s completes under a 1 s read-only bound" || fail "slow worktree remove (rc=$rc): $(head -c 300 "$TMP/out.txt")"

# a diff.ignoreSubmodules=all in the (agent-writable) repo config must not hide a moved submodule pointer from the squash rule
subwt glk; echo "upstream moved on" >> "$L/f"; G "$L" commit -qam "upstream moves"
G "$TMP/r6-glk/lib" -c protocol.file.allow=always fetch -q origin; G "$R/lib" fetch -q origin
G "$TMP/r6-glk/lib" checkout -q origin/main; GLP="$(G "$TMP/r6-glk/lib" rev-parse HEAD)"
echo "glk edit" >> "$TMP/r6-glk/n2.txt"; G "$TMP/r6-glk" add n2.txt; G "$TMP/r6-glk" update-index --cacheinfo "160000,$GLP,lib"; G "$TMP/r6-glk" commit -qm "pointer and n2 in ONE commit"; GLSHA="$(G "$TMP/r6-glk" rev-parse HEAD)"
cp "$TMP/r6-glk/n2.txt" "$R/n2.txt"; G "$R" commit -qam "n2 from glk (the pointer stays where it was in main)"
G "$TMP/r6-glk" checkout -q --detach main; G "$R" config diff.ignoreSubmodules all
rm6 ../r6-glk; refused "gitlink: a reflog-only commit that moves a submodule pointer AND edits a file main has is refused although diff.ignoreSubmodules=all" $? "$TMP/r6-glk" "UNREACHABLE" "$GLSHA"
G "$R" config --unset diff.ignoreSubmodules

# two separate chains: the newer one is in main, the older one is not -> the older one still holds the removal
w6 tc; echo "tcB" >> "$TMP/r6-tc/d.txt"; c6 tc "chain B (not in main)"; TCB="$(G "$TMP/r6-tc" rev-parse HEAD)"; G "$TMP/r6-tc" checkout -q --detach main
echo "tcA" >> "$TMP/r6-tc/c.txt"; c6 tc "chain A (cherry-picked)"; TCA="$(G "$TMP/r6-tc" rev-parse HEAD)"; cp "$TMP/r6-tc/c.txt" "$R/c.txt"; G "$R" commit -qam "chain A, brought back by content (another commit than A)"; G "$TMP/r6-tc" checkout -q --detach main
rm6 ../r6-tc; refused "two chains: the newer chain is in main, the OLDER one (not an ancestor of it) is not -> refused, names the older" $? "$TMP/r6-tc" "${TCB:0:7}" "$TCB"

# a HEAD reflog file over the size limit reads as unreadable (cannot say) even when its lines are blank
w6 bigrl; GDB="$(G "$TMP/r6-bigrl" rev-parse --absolute-git-dir)"; python3 -c "open('$GDB/logs/HEAD', 'ab').write(b' ' * 33000000 + b'\n')"
rm6 ../r6-bigrl; refused "a 33 MB HEAD reflog is refused (cannot read it all)" $? "$TMP/r6-bigrl" "reflog"

# a submodule whose reflog cannot be listed is cannot-say, not 'nothing named'
mkshim failsublog '*"log -g --format=%H HEAD"*'
subwt ssl; PATH="$TMP/shim-failsublog:$PATH" bash "$KIT" worktree remove ../r6-ssl >"$TMP/out.txt" 2>&1; rc=$?
refused "submodule: its reflog cannot be listed -> refused (cannot say)" "$rc" "$TMP/r6-ssl" "submodule"

# git < 2.36: a worktree nested inside the target whose path has a newline is still seen (its first piece lies inside)
w6 nestb; mkdir -p "$TMP/r6-nestb/.claude/worktrees"; G "$R" worktree add -q --detach "$TMP/r6-nestb/.claude/worktrees/in${NL}ner" >/dev/null 2>&1; echo "unsaved" > "$TMP/r6-nestb/.claude/worktrees/in${NL}ner/u.txt"
PATH="$SHIM:$PATH" bash "$KIT" worktree remove ../r6-nestb >"$TMP/out.txt" 2>&1; rc=$?
refused "old git: a nested worktree with a newline in its path is still seen inside the target" "$rc" "$TMP/r6-nestb" "INSIDE"


# ═══ ROUND 9 ═══ cannot-say about an operation in progress is BUSY, never "nothing in progress"
w6 ipr; G "$TMP/r6-ipr" bisect start >/dev/null 2>&1
out="$(cd "$R" && python3 - "$DEVKIT_DIR/scripts/git" "$TMP/r6-ipr" <<'PY'
import sys, time
sys.path.insert(0, sys.argv[1])
import worktree as W
live = W._in_progress(sys.argv[2])
W._BUDGET.append(time.monotonic() - 1)       # a spent shared deadline
spent = W._in_progress(sys.argv[2])
del W._BUDGET[:]
print(live, bool(spent), spent != "bisect")
PY
)"
[ "$out" = "bisect True True" ] && ok "_in_progress: a bisect is named while the budget lasts; once it is spent the answer is busy (unknown operation), not None" || fail "_in_progress under a spent deadline: '$out'"
mkshim failgitdir '*"--absolute-git-dir"*'
w6 ipc
out="$(cd "$R" && PATH="$TMP/shim-failgitdir:$PATH" python3 - "$DEVKIT_DIR/scripts/git" "$R" "$TMP/r6-ipc" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import worktree as W
r = W.inventory(sys.argv[2], only=sys.argv[3])[0]
print(bool(r["busy"]), r["unintegrated"])
PY
)"
[ "$out" = "True True" ] && ok "git cannot tell where the worktree state lives: the row is busy and unintegrated (held), not clean" || fail "git-dir failure row: '$out'"

if [ "$FAILS" -ne 0 ]; then echo "worktree remove safety: $FAILS FAILED"; exit 1; fi
echo "worktree remove safety: all checks passed"
