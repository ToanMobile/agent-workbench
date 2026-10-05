#!/usr/bin/env bash
# Regression (DevKit speed 1d): several agents, ONE worktree EACH, at the same time.
# Every gate run (bin/post-fix-gate.py) rewrites the tracked checklist files (.agents/regression_status.json,
# .agents/CHECKLIST.md: GeelyEx2, Goods, the workbench track them), so two worktrees that each ran the gate
# conflicted the moment their work came back into main (`agent-kit worktree diff <path> | git apply --3way`,
# scripts/git/worktree.py): UU .agents/regression_status.json.
#   (a) the gate in a LINKED worktree leaves those files alone (as --no-checklist); same verdict, same exit code
#       as in the main checkout, which still writes them; --checklist asks for the write
#   (b) worktree diff leaves the bookkeeping files out (committed or not, tracked or not), says so on stderr,
#       and --with-checklist brings them; a file the gate does not write (.agents/agent-note.md) always stays in
#   (c) end to end: two worktrees gated at the same time, both brought back, no conflict, both removable
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export VACUITY_REVERT=0 DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# make_repo <dir> <exit code of the suite> [untracked]: a repo whose matrix runs `sh ok.sh`; unless "untracked", the
# project TRACKS its checklist, as the workbench does (one gate run in the main checkout makes the files, a commit tracks them)
make_repo() {
  mkdir -p "$1/src" && cd "$1" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t
  echo "A = 1" > src/a.py; echo "B = 1" > src/b.py; printf 'exit %s\n' "$2" > ok.sh
  mkdir -p .agents && echo "# index" > .agents/instincts-index.md
  cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-OK","name":"core","command":"sh ok.sh"}]}]}
JSON
  printf '.claude/\n.agents/regression_journal/\n' > .gitignore
  git add -A && git commit -qm init
  if [ "${3:-}" != untracked ]; then
    echo "A = 1 # seed" > src/a.py
    gate "$1" >/dev/null 2>&1
    git checkout -q src/a.py && git add -A .agents && git commit -qm "track the checklist"
  fi
}
# gate <checkout> [args]: the gate as an agent runs it in that checkout; prints its output
gate() {
  local d="$1"; shift
  ( cd "$d" && CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --matrix "$d/matrix.json" --run-tests --no-cache --lang en "$@" 2>&1 )
}
verdict() { printf '%s\n' "$1" | sed -e 's/\x1b\[[0-9;]*m//g' | grep -E "POST-FIX AUDIT GATE VERDICT" | head -1; }
bk() { git -C "$1" status --porcelain -- .agents/regression_status.json .agents/CHECKLIST.md .agents/regression_checklist.md; }   # the bookkeeping files' state

# --- (a) the gate: main checkout writes the checklist, a linked worktree does not, same verdict ----------------
make_repo "$TMP/cp" 0; make_repo "$TMP/cf" 1; make_repo "$TMP/m" 0; make_repo "$TMP/mf" 1
for r in cp cf; do echo "A = 2" > "$TMP/$r/src/a.py"; done
out_cp="$(gate "$TMP/cp")"; rc_cp=$?; out_cf="$(gate "$TMP/cf")"; rc_cf=$?
[ -n "$(bk "$TMP/cp")" ] && [ -n "$(bk "$TMP/cf")" ] \
  && ok "control: the main checkout's gate still writes the tracked checklist files (pass and fail)" \
  || fail "control: the main checkout did not write the checklist (the fixture proves nothing)"
[ "$rc_cp" = 0 ] && [ "$rc_cf" = 1 ] && ok "control: exit codes 0 (suite passes) and 1 (suite fails)" || fail "control exit codes: $rc_cp / $rc_cf"

cd "$TMP/m" && bash "$KIT" worktree add ../wt-a >/dev/null 2>&1 || fail "add wt-a"
bash "$KIT" worktree add ../wt-b >/dev/null 2>&1 || fail "add wt-b"
cd "$TMP/mf" && bash "$KIT" worktree add ../wt-f >/dev/null 2>&1 || fail "add wt-f"
echo "A = 2" > "$TMP/wt-a/src/a.py"; echo "B = 2" > "$TMP/wt-b/src/b.py"; echo "A = 2" > "$TMP/wt-f/src/a.py"
out_f="$(gate "$TMP/wt-f")"; rc_f=$?
[ "$rc_f" = "$rc_cf" ] && [ "$(verdict "$out_f")" = "$(verdict "$out_cf")" ] && [ -n "$(verdict "$out_f")" ] \
  && ok "linked worktree: a FAILING suite gives the same exit code ($rc_f) and verdict as the main checkout" \
  || fail "failing suite: worktree rc=$rc_f '$(verdict "$out_f")' vs main rc=$rc_cf '$(verdict "$out_cf")'"
[ -z "$(bk "$TMP/wt-f")" ] && ok "linked worktree: a failing run leaves the checklist files untouched" \
  || fail "linked worktree (failing suite) modified the checklist: $(bk "$TMP/wt-f")"

# two gates in two worktrees AT THE SAME TIME (each has its own test-run lock)
( gate "$TMP/wt-a" > "$TMP/gate-a.out"; echo $? > "$TMP/gate-a.rc" ) &
( gate "$TMP/wt-b" > "$TMP/gate-b.out"; echo $? > "$TMP/gate-b.rc" ) &
wait
[ "$(cat "$TMP/gate-a.rc")" = "$rc_cp" ] && [ "$(cat "$TMP/gate-b.rc")" = "$rc_cp" ] \
  && [ "$(verdict "$(cat "$TMP/gate-a.out")")" = "$(verdict "$out_cp")" ] \
  && ok "linked worktrees: two gates at the same time, same exit code ($rc_cp) and verdict as the main checkout" \
  || fail "concurrent gates: rc $(cat "$TMP/gate-a.rc")/$(cat "$TMP/gate-b.rc") vs $rc_cp; '$(verdict "$(cat "$TMP/gate-a.out")")' vs '$(verdict "$out_cp")'"
[ -z "$(bk "$TMP/wt-a")" ] && [ -z "$(bk "$TMP/wt-b")" ] \
  && ok "linked worktrees: the gate leaves the tracked checklist files unmodified" \
  || fail "gate in a linked worktree modified the checklist: [$(bk "$TMP/wt-a")] [$(bk "$TMP/wt-b")]"
[ "$(git -C "$TMP/wt-a" status --porcelain)" = " M src/a.py" ] \
  && ok "linked worktree: nothing but the agent's own edit shows in git status" || fail "wt-a status: $(git -C "$TMP/wt-a" status --porcelain)"

# (c) end to end: both agents' work comes back into main without a conflict, and both worktrees can go
cd "$TMP/m" || exit 1
for n in a b; do
  bash "$KIT" worktree diff "../wt-$n" 2>/dev/null | git apply --3way >/dev/null 2>"$TMP/apply-$n.err"; rc=$?
  [ "$rc" = 0 ] && ok "wt-$n: diff | git apply --3way into main applies cleanly" || { fail "wt-$n apply rc=$rc"; cat "$TMP/apply-$n.err"; }
done
[ -z "$(git status --porcelain | grep -E '^(UU|AA|DU|UD)|\.agents/')" ] && grep -q "A = 2" src/a.py && grep -q "B = 2" src/b.py \
  && ok "main: both agents' source edits arrived, no conflict, no checklist file in the change" \
  || fail "main after both applies: $(git status --porcelain | tr '\n' ' ')"
for n in a b; do
  bash "$KIT" worktree remove "../wt-$n" >/dev/null 2>"$TMP/rm-$n.err"; rc=$?
  [ "$rc" = 0 ] && [ ! -e "$TMP/wt-$n" ] && ok "wt-$n: removable once its work is in main" || { fail "remove wt-$n rc=$rc"; cat "$TMP/rm-$n.err"; }
done

# explicit ask: --checklist writes in a linked worktree
cd "$TMP/m" && bash "$KIT" worktree add ../wt-c >/dev/null 2>&1 || fail "add wt-c"
echo "A = 3" > "$TMP/wt-c/src/a.py"
gate "$TMP/wt-c" --checklist >/dev/null; rc=$?
[ "$rc" = 0 ] && [ -n "$(bk "$TMP/wt-c")" ] && ok "linked worktree: --checklist asks for the write explicitly" || fail "--checklist did not write (rc=$rc)"
git -C "$TMP/wt-c" checkout -q -- .agents
# --record-lesson in a linked worktree: the lesson (.agents/instincts.md, a real file) reaches main with `diff | git apply`;
# the checklist ROW would not (the bookkeeping file is left out), so the gate does not write it and says where to add the bug
make_repo "$TMP/ml" 0; cd "$TMP/ml" && bash "$KIT" worktree add ../wt-l >/dev/null 2>&1 || fail "add wt-l"
echo "A = 3" > "$TMP/wt-l/src/a.py"
out_l="$(gate "$TMP/wt-l" --record-lesson "lesson x" --cause "cause x" --prevention "prevention x")"; rc=$?
[ "$rc" = 0 ] && grep -q "lesson x" "$TMP/wt-l/.agents/instincts.md" && [ -z "$(bk "$TMP/wt-l")" ] \
  && printf '%s' "$out_l" | grep -q "bugs add" \
  && ok "linked worktree: --record-lesson writes the lesson (instincts.md), no checklist row, and says to add the bug in main" \
  || fail "--record-lesson in a linked worktree (rc=$rc): bk=[$(bk "$TMP/wt-l")]"
bash "$KIT" worktree diff ../wt-l 2>/dev/null | git apply --3way >/dev/null 2>&1; grep -q "lesson x" "$TMP/ml/.agents/instincts.md" \
  && ok "linked worktree: the recorded lesson reaches the main checkout through diff | git apply" || fail "the lesson did not reach main"

# a worktree made by plain `git worktree add` (not agent-kit) and one of a bare repo are linked worktrees too
cd "$TMP/m" && git worktree add -q --detach "$TMP/plain" >/dev/null 2>&1 && echo "A = 4" > "$TMP/plain/src/a.py"
gate "$TMP/plain" >/dev/null; rc=$?
[ "$rc" = 0 ] && [ -z "$(bk "$TMP/plain")" ] && ok "a plain 'git worktree add' worktree behaves the same" || fail "plain worktree: rc=$rc [$(bk "$TMP/plain")]"
git clone -q --bare "$TMP/m" "$TMP/bare.git" && git -C "$TMP/bare.git" worktree add -q --detach "$TMP/bw" >/dev/null 2>&1 \
  && echo "A = 5" > "$TMP/bw/src/a.py"
gate "$TMP/bw" >/dev/null; rc=$?
[ "$rc" = 0 ] && [ -n "$(bk "$TMP/bw")" ] && ok "a worktree of a BARE repo has no main checkout to conflict with: the gate writes its checklist" || fail "bare-repo worktree: rc=$rc [$(bk "$TMP/bw")]"
cd "$TMP/m" && git worktree remove --force "$TMP/plain" >/dev/null 2>&1; git worktree remove --force "$TMP/wt-c" >/dev/null 2>&1

# --- (b) worktree diff leaves the bookkeeping files out ---------------------------------------------------------
cd "$TMP/m" && git reset -q HEAD . && git checkout -q -- . && git clean -fdq   # main back to HEAD
bash "$KIT" worktree add ../wt-y >/dev/null 2>&1 || fail "add wt-y"
out="$(bash "$KIT" worktree diff ../wt-y 2>&1)"
[ -z "$out" ] && ok "diff: a fresh worktree gives an empty patch and no note" || fail "fresh worktree diff: $out"
bash "$KIT" worktree remove ../wt-y >/dev/null 2>&1

bash "$KIT" worktree add ../wt-x >/dev/null 2>&1 || fail "add wt-x"
W="$TMP/wt-x"
echo "A = 9" > "$W/src/a.py"                                  # uncommitted source edit
echo "note" > "$W/.agents/agent-note.md"                      # work inside .agents/ that the gate does not write
echo "odd" > "$W/:lit.py"                                     # a name that looks like pathspec magic
echo "C = 1" > "$W/src/c.py" && git -C "$W" add src/c.py && git -C "$W" commit -qm "c"        # committed source
echo "<!-- committed -->" >> "$W/.agents/CHECKLIST.md" && git -C "$W" add .agents/CHECKLIST.md && git -C "$W" commit -qm "bookkeeping"
python3 - "$W/.agents/regression_status.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d.setdefault("meta", {})["touched"] = "worktree"; json.dump(d, open(sys.argv[1], "w"), indent=2)
PY
echo "idx" >> "$W/.agents/instincts-index.md"
mkdir -p "$W/.agents/archive" && echo "archived" > "$W/.agents/archive/BUG_ARCHIVE.md"
[ -e "$W/.agents/regression_checklist.md" ] && echo "<!-- link -->" >> "$W/.agents/regression_checklist.md"
patch="$(GIT_LITERAL_PATHSPECS=1 bash "$KIT" worktree diff ../wt-x 2>"$TMP/diff.err")"       # an inherited GIT_LITERAL_PATHSPECS must not matter
for f in src/a.py src/c.py .agents/agent-note.md :lit.py; do
  printf '%s\n' "$patch" | grep -qF "diff --git a/$f " || fail "diff misses the agent's own $f"
done
printf '%s\n' "$patch" | grep -qE '^diff --git a/\.agents/(CHECKLIST\.md|regression_status\.json|regression_checklist\.md|instincts-index\.md|archive/BUG_ARCHIVE\.md) ' \
  && fail "diff carries bookkeeping files: $(printf '%s\n' "$patch" | grep '^diff --git a/.agents/')" \
  || ok "diff: the agent's edits (committed, uncommitted, new, odd-named, .agents/agent-note.md) are in, the bookkeeping files are out"
for f in CHECKLIST.md regression_status.json instincts-index.md BUG_ARCHIVE.md; do
  grep -q "$f" "$TMP/diff.err" || fail "stderr does not name the excluded $f"
done
grep -q "with-checklist" "$TMP/diff.err" && ok "diff: stderr names every excluded file and the flag that brings them" || fail "no hint on stderr: $(cat "$TMP/diff.err")"
patch_all="$(bash "$KIT" worktree diff ../wt-x --with-checklist 2>/dev/null)"
missing=""
for f in .agents/CHECKLIST.md .agents/regression_status.json .agents/instincts-index.md .agents/archive/BUG_ARCHIVE.md src/a.py; do
  printf '%s\n' "$patch_all" | grep -qF "diff --git a/$f " || missing="$missing $f"
done
[ -z "$missing" ] && ok "diff --with-checklist: asked for explicitly, the bookkeeping files come too" || fail "--with-checklist misses:$missing"
printf '%s\n' "$patch" | git apply --check && ok "diff: the patch applies to the main checkout" || fail "patch does not apply"
bash "$KIT" worktree remove ../wt-x >"$TMP/rm.out" 2>&1; rc=$?
[ "$rc" = 1 ] && [ -d "$W" ] && ok "remove: still refused while the worktree holds work that is not in main (unchanged rule)" || fail "remove rc=$rc"
git -C "$TMP/m" worktree remove --force "$W" >/dev/null 2>&1

# bug / REQ rows made by `agent-kit bugs add` in the worktree are real work (nothing regenerates them): they ride in the patch,
# the regenerated rest of regression_status.json and the CHECKLIST.md view do not
make_repo "$TMP/mr" 0; cd "$TMP/mr" && bash "$KIT" worktree add ../wt-r >/dev/null 2>&1 || fail "add wt-r"
( cd "$TMP/wt-r" && CLAUDE_PROJECT_DIR="$TMP/wt-r" bash "$KIT" bugs add "worktree bug" --fixed >/dev/null 2>&1 ) || fail "bugs add in the worktree"
patch="$(bash "$KIT" worktree diff ../wt-r 2>"$TMP/diff-r.err")"
printf '%s\n' "$patch" | grep -qF "diff --git a/.agents/regression_status.json " && printf '%s\n' "$patch" | grep -q "worktree bug" \
  && ! printf '%s\n' "$patch" | grep -qF "diff --git a/.agents/CHECKLIST.md " \
  && ok "diff: a bug row made with agent-kit bugs add rides in the patch; the CHECKLIST.md view does not" \
  || fail "authored bug row not carried: $(printf '%s\n' "$patch" | grep '^diff --git')"
printf '%s\n' "$patch" | git apply --3way >/dev/null 2>&1; grep -q "worktree bug" "$TMP/mr/.agents/regression_status.json" \
  && ok "diff: ... and it arrives in the main checkout" || fail "the bug row did not reach main"
cd "$TMP/mr" && git reset -q HEAD . && git restore -- . && git clean -fdq
bash "$KIT" worktree add ../wt-r2 >/dev/null 2>&1 || fail "add wt-r2"
CLAUDE_PROJECT_DIR="$TMP/wt-r2" python3 "$DEVKIT_DIR/bin/regression_checklist.py" render >/dev/null 2>&1
echo "x" >> "$TMP/wt-r2/.agents/CHECKLIST.md"
patch="$(bash "$KIT" worktree diff ../wt-r2 2>/dev/null)"
printf '%s\n' "$patch" | grep -qF "regression_status.json" && fail "a worktree with only regenerated bookkeeping still carries the status file" || ok "diff: regenerated bookkeeping alone (no authored row) is still left out"

# a worktree whose path has a space (the old default branch name feat/<folder> was invalid for it)
bash "$KIT" worktree add "../wt sp" >/dev/null 2>"$TMP/add-sp.err" || fail "add 'wt sp' (a path with a space): $(cat "$TMP/add-sp.err")"
echo "A = 7" > "$TMP/wt sp/src/a.py"; echo "<!-- sp -->" >> "$TMP/wt sp/.agents/CHECKLIST.md"
patch="$(bash "$KIT" worktree diff "../wt sp" 2>/dev/null)"
printf '%s\n' "$patch" | grep -qF "diff --git a/src/a.py " && ! printf '%s\n' "$patch" | grep -qF "CHECKLIST.md" \
  && ok "a worktree path with a space: added, and its diff leaves the bookkeeping out" || fail "space path: $(printf '%s\n' "$patch" | grep '^diff --git')"
git -C "$TMP/m" worktree remove --force "$TMP/wt sp" >/dev/null 2>&1

# a worktree whose ONLY dirt is bookkeeping (a hook rewrote it): remove still refuses (not weakened) and names the way out,
# which must not be a command the git guard blocks (`git checkout -- <file>`, `switch -c`)
cd "$TMP/m" || exit 1
bash "$KIT" worktree add ../wt-k >/dev/null 2>&1 || fail "add wt-k"
echo "<!-- k -->" >> "$TMP/wt-k/.agents/CHECKLIST.md"
bash "$KIT" worktree remove ../wt-k >"$TMP/rm-k.out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q "with-checklist" "$TMP/rm-k.out" && ! grep -qE "checkout --|switch -c" "$TMP/rm-k.out" \
  && ok "remove: bookkeeping-only dirt is still refused; the hint names --with-checklist, no command the git guard blocks" \
  || { fail "remove of a bookkeeping-only worktree (rc=$rc)"; cat "$TMP/rm-k.out"; }
bash "$KIT" worktree diff ../wt-k --with-checklist 2>/dev/null | git apply --3way >/dev/null 2>&1
bash "$KIT" worktree remove ../wt-k >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && ok "remove: allowed once --with-checklist brought the bookkeeping into main" || fail "remove after --with-checklist (rc=$rc)"

# the checklist NOT tracked (git-ignored or not): a worktree that wrote it on request still does not ship it
make_repo "$TMP/u" 0 untracked
cd "$TMP/u" && bash "$KIT" worktree add ../wt-u >/dev/null 2>&1 || fail "add wt-u"
echo "A = 2" > "$TMP/wt-u/src/a.py"
gate "$TMP/wt-u" --checklist >/dev/null
[ -f "$TMP/wt-u/.agents/regression_status.json" ] || fail "fixture: the untracked checklist was not written"
patch="$(bash "$KIT" worktree diff ../wt-u 2>/dev/null)"
printf '%s\n' "$patch" | grep -qF "diff --git a/src/a.py " && ! printf '%s\n' "$patch" | grep -qE 'diff --git a/\.agents/(CHECKLIST\.md|regression_status\.json) ' \
  && ok "diff: an UNTRACKED checklist file is left out too" || fail "untracked checklist in the diff: $(printf '%s\n' "$patch" | grep '^diff --git')"

# the list worktree.py leaves out follows what regression_checklist.py writes (a new file there must not start conflicting again)
missing="$(python3 - "$DEVKIT_DIR" <<'PY' 2>&1
import sys
sys.path.insert(0, sys.argv[1] + "/scripts/git"); sys.path.insert(0, sys.argv[1] + "/bin")
import worktree as w, regression_checklist as rc
need = {str(rc.STATUS_FILE), str(rc.VIEW_FILE), str(rc.OLD_VIEW_FILE), str(rc.ARCHIVE_FILE)}
print(" ".join(sorted(need - set(w.BOOKKEEPING))), end="")
PY
)"
[ -z "$missing" ] && ok "worktree.py BOOKKEEPING covers every file regression_checklist.py writes" || fail "BOOKKEEPING misses: $missing"
bash "$KIT" worktree diff ../wt-u --bogus >/dev/null 2>&1; [ $? = 2 ] && ok "diff: an unknown option is a usage error (exit 2)" || fail "diff accepted an unknown option"

# a MAIN checkout is never taken for a linked worktree: not through GIT_DIR in the environment, not through a planted .git/commondir
python3 - "$DEVKIT_DIR/bin" "$TMP" >"$TMP/linked.out" 2>&1 <<'PY'
import os, subprocess, sys
sys.path.insert(0, sys.argv[1])
import regression_checklist as rc
T = sys.argv[2]
env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
def sh(cwd, *c):
    return subprocess.run(list(c), cwd=cwd, capture_output=True, text=True, env=env, check=True)
main = os.path.join(T, "m")
res = []
def check(name, want):
    got = rc.in_linked_worktree(main if name[0] != "L" else os.path.join(T, "wt-lk"))
    res.append((name, got == want, got))
sh(main, "git", "worktree", "add", "-q", "--detach", os.path.join(T, "wt-lk"))
check("main checkout", False); check("L linked worktree", True)
os.environ["GIT_DIR"] = os.path.join(main, ".git", "worktrees", "wt-lk")
check("main checkout with GIT_DIR pointing at a linked worktree's git dir", False)
os.environ["GIT_COMMON_DIR"] = T
check("main checkout with GIT_DIR and GIT_COMMON_DIR exported", False)
for k in ("GIT_DIR", "GIT_COMMON_DIR"): os.environ.pop(k, None)
other = os.path.join(T, "other-clone"); sh(T, "git", "clone", "-q", main, other)
open(os.path.join(main, ".git", "commondir"), "w").write(os.path.join(other, ".git") + "\n")
check("main checkout whose .git/commondir was pointed at another clone", False)
os.remove(os.path.join(main, ".git", "commondir"))
for name, good, got in res:
    print(("PASS " if good else "FAIL ") + "in_linked_worktree: " + name + ("" if good else " -> " + str(got)))
sys.exit(0 if all(g for _, g, _ in res) else 1)
PY
while IFS= read -r l; do case "$l" in PASS*) ok "${l#PASS }" ;; FAIL*) fail "${l#FAIL }" ;; *) echo "$l" ;; esac; done < "$TMP/linked.out"
git -C "$TMP/m" worktree remove --force "$TMP/wt-lk" >/dev/null 2>&1

if [ "$FAILS" -ne 0 ]; then echo "worktree checklist: $FAILS FAILED"; exit 1; fi
echo "worktree checklist: all checks passed"
