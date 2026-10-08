#!/usr/bin/env bash
# Regression (OfficeReader 2026-10-08, user: "it creates a worktree and leaves it there"; "is there an automatic merge yet? I sit here
# making you run it 20 times and it is still not merged"; "just merge, and if there is a conflict fix it, safely"). The Stop gate only
# TOLD the agent to run diff | git apply, commit, remove: a worktree `worktree add` did not make (EnterWorktree, a subagent's) was
# refused by diff / remove outright, a patch onto a dirty shared main failed, and nothing ever finished the job.
# `agent-kit worktree finish <path>` (and `automerge`, the same with one JSON line) merges it by itself, from the main checkout:
#   - uncommitted work is committed IN the worktree; main is merged INTO the worktree (a conflict is resolved there, in a folder
#     nobody else touches); main only FAST-FORWARDS (another session's dirty / staged files are never touched); then the removal
#   1 committed work, main unchanged            2 uncommitted edit + new file          3 main moved on: merge commit
#   4 main holds another session's dirty + staged files: they survive untouched
#   5 conflict: exit 3, main untouched, markers in the worktree; resolving it and running again finishes the job
#   6 main has uncommitted edits on a file the worktree changed: nothing moves, exit 1; after the edit is committed it goes through
#   7 a worktree git made on its own (no devkit state, with harness files)   8 a refused pre-commit hook   9 refusals: busy, detached main,
#   wrong place, not a worktree, a live lock    10 the JSON line of `automerge`
# Independent review 2026-10-08 (each was a real defect of the first version):
#   11 work under .claude/ in an adopted worktree is WORK (agent memory, agent definitions), never "setup"   12 an unreadable state file
#   is refused, not adopted   13 the main checkout on another branch (release/...): refused   14 a secret-looking local file is never
#   committed automatically   15 untracked bookkeeping files do not strand the removal
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${WM_KIT:-$DEVKIT_DIR/bin/agent-kit}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

P="$TMP/main"; mkdir -p "$P" && G "$P" init -q -b main . && cd "$P" || exit 1
for f in a b c d f; do printf '1\n2\n3\n4\n5\n' > "$P/$f.txt"; done
G "$P" add -A && G "$P" commit -qm init
wt() { bash "$KIT" worktree add "../am-$1" --no-init >/dev/null 2>&1 || fail "add am-$1"; }
fin() { (cd "$P" && bash "$KIT" worktree finish "$@" >"$TMP/out" 2>&1); return $?; }
listed() { G "$P" worktree list | grep -q "$1"; }
clean_main() { [ -z "$(G "$P" status --porcelain --untracked-files=no)" ]; }

# 1: committed work, main did not move -> a pure fast-forward
wt a; sed -i.bak '5s/.*/A5/' "$TMP/am-a/a.txt" && rm "$TMP/am-a/a.txt.bak"; G "$TMP/am-a" commit -qam "a5"; WH="$(G "$TMP/am-a" rev-parse HEAD)"
fin ../am-a; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/am-a" ] && ! listed am-a && [ "$(G "$P" rev-parse HEAD)" = "$WH" ] && grep -q "^A5$" "$P/a.txt" && clean_main \
  && ok "1: committed work: main fast-forwards to it, the worktree is gone, main's tree is clean" || fail "1: (rc=$rc): $(cat "$TMP/out")"

# 2: uncommitted work (an edit and a new file)
wt b; printf '1\n2\n3\n4\nB5\n' > "$TMP/am-b/b.txt"; echo n > "$TMP/am-b/n.txt"
fin ../am-b; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/am-b" ] && grep -q "^B5$" "$P/b.txt" && [ -f "$P/n.txt" ] && G "$P" log -1 --format=%s | grep -q "wip(am-b)" && clean_main \
  && ok "2: uncommitted edit + new file: committed in the worktree, merged, removed" || fail "2: (rc=$rc): $(cat "$TMP/out")"

# 3: main moved on (an unrelated commit): main is merged INTO the worktree, then main fast-forwards
wt c; printf 'new\n' > "$TMP/am-c/c-new.txt"; G "$TMP/am-c" add -A && G "$TMP/am-c" commit -qm "c-new"
printf '1\n2\n3\n4\nC5\n' > "$P/c.txt"; G "$P" commit -qam "main moves on"
fin ../am-c; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/am-c" ] && [ -f "$P/c-new.txt" ] && grep -q "^C5$" "$P/c.txt" && [ -n "$(G "$P" rev-list --merges -1 HEAD)" ] && clean_main \
  && ok "3: main moved on: both changes are in main (a merge commit), the worktree is gone" || fail "3: (rc=$rc): $(cat "$TMP/out")"

# 4: main holds ANOTHER SESSION's uncommitted edit and a staged new file: both survive
wt d; printf 'dd\n' > "$TMP/am-d/d-new.txt"; G "$TMP/am-d" add -A && G "$TMP/am-d" commit -qm "d-new"
printf 'other session edit\n' >> "$P/b.txt"; echo staged > "$P/s.txt"; G "$P" add s.txt
fin ../am-d; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/am-d" ] && [ -f "$P/d-new.txt" ] && grep -q "other session edit" "$P/b.txt" && G "$P" diff --cached --name-only | grep -q "^s.txt$" \
  && ok "4: another session's dirty file and staged file survive untouched" || fail "4: (rc=$rc): $(cat "$TMP/out") / $(G "$P" status --short)"
G "$P" reset -q s.txt; rm -f "$P/s.txt"; printf '1\n2\n3\n4\nB5\n' > "$P/b.txt"   # back to the committed b.txt

# 5: a real conflict: same line changed on both sides
wt e; printf '1\n2\nE3\n4\nA5\n' > "$TMP/am-e/a.txt"; G "$TMP/am-e" commit -qam "e3"
printf '1\n2\nM3\n4\nA5\n' > "$P/a.txt"; G "$P" commit -qam "m3"; HEAD5="$(G "$P" rev-parse HEAD)"
fin ../am-e; rc=$?
[ "$rc" = 3 ] && [ -d "$TMP/am-e" ] && grep -q "a.txt" "$TMP/out" && grep -q "Resolve it NOW" "$TMP/out" && ok "5: a conflict: exit 3, the files are named, the way out is stated" || fail "5: conflict (rc=$rc): $(cat "$TMP/out")"
[ "$(G "$P" rev-parse HEAD)" = "$HEAD5" ] && grep -q "^M3$" "$P/a.txt" && ! grep -q "<<<<" "$P/a.txt" && clean_main && ok "  … main was not touched (no markers, same HEAD)" || fail "  … main changed during a conflict"
grep -q "<<<<<<<" "$TMP/am-e/a.txt" && [ -f "$(G "$TMP/am-e" rev-parse --absolute-git-dir)/MERGE_HEAD" ] && ok "  … the conflict is open in the worktree, where it can be resolved" || fail "  … no open merge in the worktree"
printf '1\n2\nE3+M3\n4\nA5\n' > "$TMP/am-e/a.txt"; G "$TMP/am-e" add a.txt      # the agent resolves it and stops
fin ../am-e; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/am-e" ] && grep -q "^E3+M3$" "$P/a.txt" && clean_main && ok "  … once resolved and staged, running it again concludes the merge, fast-forwards main and removes the worktree" || fail "  … after resolving (rc=$rc): $(cat "$TMP/out")"

# 6: main has an UNCOMMITTED edit on a file the worktree changed -> nothing moves
wt f; printf '1\n2\n3\n4\nF5\n' > "$TMP/am-f/f.txt"; G "$TMP/am-f" commit -qam "f5"
printf 'F1\n2\n3\n4\n5\n' > "$P/f.txt"; HEAD6="$(G "$P" rev-parse HEAD)"
fin ../am-f; rc=$?
[ "$rc" = 1 ] && [ -d "$TMP/am-f" ] && [ "$(G "$P" rev-parse HEAD)" = "$HEAD6" ] && grep -q "^F1$" "$P/f.txt" && grep -q "UNCOMMITTED" "$TMP/out" \
  && ok "6: main's uncommitted edit on the same file: exit 1, nothing moved, the edit survives" || fail "6: (rc=$rc): $(cat "$TMP/out")"
G "$P" commit -qam "main commits its f edit"
fin ../am-f; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/am-f" ] && grep -q "^F1$" "$P/f.txt" && grep -q "^F5$" "$P/f.txt" && ok "  … after main commits it, the same command goes through (both edits in f.txt)" || fail "  … retry (rc=$rc): $(cat "$TMP/out")"

# 7: a worktree git made by itself: no devkit state, and harness files in it
mkdir -p "$P/.claude" && echo '{}' > "$P/.claude/settings.local.json"      # main's own local settings (untracked); a worktree copy of it is SETUP
G "$P" worktree add -q --detach "$TMP/am-raw" && mkdir -p "$TMP/am-raw/.claude" && echo '{}' > "$TMP/am-raw/.claude/settings.local.json" && echo raw > "$TMP/am-raw/raw.txt"
fin ../am-raw; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/am-raw" ] && [ -f "$P/raw.txt" ] && [ -z "$(G "$P" ls-files .claude/settings.local.json)" ] \
  && ok "7: a worktree 'worktree add' did not make is adopted: merged and removed, the setup file (same bytes as main's) is not carried" || fail "7: (rc=$rc): $(cat "$TMP/out")"

# 8: the repo's pre-commit hook refuses the worktree's commit: held, nothing lost, goes through once fixed
mkdir -p "$P/.git/hooks" && printf '#!/bin/sh\necho "pre-commit says no" >&2\nexit 1\n' > "$P/.git/hooks/pre-commit" && chmod +x "$P/.git/hooks/pre-commit"
wt h; echo h > "$TMP/am-h/h.txt"
fin ../am-h; rc=$?
[ "$rc" = 1 ] && [ -d "$TMP/am-h" ] && [ -f "$TMP/am-h/h.txt" ] && grep -q "pre-commit says no" "$TMP/out" && ok "8: a refused commit holds it (exit 1), the work is still in the worktree, the reason is shown" || fail "8: (rc=$rc): $(cat "$TMP/out")"
rm -f "$P/.git/hooks/pre-commit"
fin ../am-h; rc=$?; [ "$rc" = 0 ] && [ ! -d "$TMP/am-h" ] && [ -f "$P/h.txt" ] && ok "  … and once the hook allows it, it goes through" || fail "  … retry after the hook (rc=$rc): $(cat "$TMP/out")"

# 9: refusals
wt i; touch "$(G "$TMP/am-i" rev-parse --absolute-git-dir)/BISECT_LOG"
fin ../am-i; rc=$?; [ "$rc" = 1 ] && [ -d "$TMP/am-i" ] && grep -q "bisect" "$TMP/out" && ok "9: a bisect in progress: refused" || fail "9: busy (rc=$rc): $(cat "$TMP/out")"
rm -f "$(G "$TMP/am-i" rev-parse --absolute-git-dir)/BISECT_LOG"
G "$P" checkout -q --detach; fin ../am-i; rc=$?; [ "$rc" = 1 ] && grep -q "detached HEAD" "$TMP/out" && ok "  … main on a detached HEAD: refused" || fail "  … detached main (rc=$rc): $(cat "$TMP/out")"
G "$P" checkout -q main
(cd "$TMP/am-i" && bash "$KIT" worktree finish . >"$TMP/out" 2>&1); rc=$?; [ "$rc" = 1 ] && grep -q "MAIN checkout" "$TMP/out" && [ -d "$TMP/am-i" ] && ok "  … from inside the worktree: refused" || fail "  … inside (rc=$rc): $(cat "$TMP/out")"
fin ../nope; rc=$?; [ "$rc" = 1 ] && grep -q "not a registered worktree" "$TMP/out" && ok "  … a path that is not a worktree: refused" || fail "  … not a worktree (rc=$rc): $(cat "$TMP/out")"
fin; rc=$?; [ "$rc" != 0 ] && grep -q "usage" "$TMP/out" && ok "  … no argument: usage" || fail "  … usage missing"
LOCKF="$(G "$TMP/am-i" rev-parse --absolute-git-dir)/devkit-automerge.lock"
python3 -c 'import json,sys,time;json.dump({"pid":int(sys.argv[2]),"at":time.time()},open(sys.argv[1],"w"))' "$LOCKF" "$$"
fin ../am-i; rc=$?; [ "$rc" = 1 ] && grep -q "another automatic merge" "$TMP/out" && ok "  … another live automatic merge of the same worktree: refused" || fail "  … live lock (rc=$rc): $(cat "$TMP/out")"
python3 -c 'import json,sys,time;json.dump({"pid":2**22+4242,"at":time.time()},open(sys.argv[1],"w"))' "$LOCKF"
echo i > "$TMP/am-i/i.txt"
fin ../am-i; rc=$?; [ "$rc" = 0 ] && [ ! -d "$TMP/am-i" ] && ok "  … a lock whose process is gone is taken over" || fail "  … stale lock (rc=$rc): $(cat "$TMP/out")"

# 10: the machine form
wt j; echo j > "$TMP/am-j/j.txt"
J="$(cd "$P" && bash "$KIT" worktree automerge ../am-j 2>/dev/null | tail -1)"; rc=$?
python3 -c 'import json,sys;d=json.loads(sys.argv[1]);sys.exit(0 if d["status"]=="merged" and d["path"].endswith("am-j") else 1)' "$J" && [ ! -d "$TMP/am-j" ] && ok "10: automerge prints one JSON line {status: merged, path, message}" || fail "10: automerge output: $J"

# 11: tracked file edited and a new note under .claude/ in an adopted worktree: that is the agent's WORK
mkdir -p "$P/.claude/agents" && echo "agent v1" > "$P/.claude/agents/x.md" && G "$P" add .claude/agents/x.md && G "$P" commit -qm "an agent definition"
G "$P" worktree add -q --detach "$TMP/am-agent"; echo "agent v2" > "$TMP/am-agent/.claude/agents/x.md"; mkdir -p "$TMP/am-agent/.claude/agent-memory/r" && echo "a lesson" > "$TMP/am-agent/.claude/agent-memory/r/new.md"
fin ../am-agent; rc=$?
[ "$rc" = 0 ] && grep -q "agent v2" "$P/.claude/agents/x.md" && [ -f "$P/.claude/agent-memory/r/new.md" ] && [ -n "$(G "$P" ls-files .claude/agent-memory/r/new.md)" ] \
  && ok "11: an edited agent definition and a new agent-memory note under .claude/ reach main (committed), nothing silently dropped" || fail "11: (rc=$rc): $(cat "$TMP/out") / $(G "$P" status --short)"

# 12: a state file that is there but unreadable: refused before anything is committed or merged
wt k; echo '{corrupt' > "$(G "$TMP/am-k" rev-parse --absolute-git-dir)/devkit-worktree.json"; echo k > "$TMP/am-k/k.txt"
HEAD12="$(G "$P" rev-parse HEAD)"; WHEAD12="$(G "$TMP/am-k" rev-parse HEAD)"
fin ../am-k; rc=$?
[ "$rc" = 1 ] && [ "$(G "$P" rev-parse HEAD)" = "$HEAD12" ] && [ "$(G "$TMP/am-k" rev-parse HEAD)" = "$WHEAD12" ] && [ -f "$TMP/am-k/k.txt" ] \
  && ok "12: an unreadable state file: exit 1, no commit in the worktree, nothing in main" || fail "12: (rc=$rc): $(cat "$TMP/out")"

# 13: the main checkout is on ANOTHER branch (a release branch): the worktree is not merged into it
G "$P" branch release HEAD~1; G "$P" switch -q release; RELEASE="$(G "$P" rev-parse release)"
wt m; echo m > "$TMP/am-m/m.txt"; G "$TMP/am-m" add m.txt; G "$TMP/am-m" commit -qm m
fin ../am-m; rc=$?
[ "$rc" = 1 ] && [ -d "$TMP/am-m" ] && [ "$(G "$P" rev-parse release)" = "$RELEASE" ] && grep -q "release" "$TMP/out" \
  && ok "13: main checkout on 'release': refused, the branch did not move" || fail "13: (rc=$rc): $(cat "$TMP/out")"
G "$P" switch -q main
fin ../am-m; rc=$?; [ "$rc" = 0 ] && [ ! -d "$TMP/am-m" ] && ok "  … back on main, the same command merges it" || fail "  … back on main (rc=$rc): $(cat "$TMP/out")"

# 14: a secret-looking local file (not git-ignored) is never committed on its own
wt n; echo "AWS_SECRET_ACCESS_KEY=abc" > "$TMP/am-n/.env.local"; echo feat > "$TMP/am-n/feature.txt"
HEAD14="$(G "$P" rev-parse HEAD)"; WHEAD14="$(G "$TMP/am-n" rev-parse HEAD)"
fin ../am-n; rc=$?
[ "$rc" = 1 ] && grep -q ".env.local" "$TMP/out" && [ "$(G "$P" rev-parse HEAD)" = "$HEAD14" ] && [ "$(G "$TMP/am-n" rev-parse HEAD)" = "$WHEAD14" ] && [ -f "$TMP/am-n/.env.local" ] \
  && ok "14: a .env.local in the worktree: exit 1, named, nothing committed anywhere" || fail "14: (rc=$rc): $(cat "$TMP/out")"
rm -f "$TMP/am-n/.env.local"
fin ../am-n; rc=$?; [ "$rc" = 0 ] && [ -f "$P/feature.txt" ] && ok "  … without it the rest goes through" || fail "  … after removing it (rc=$rc): $(cat "$TMP/out")"

# 15: untracked bookkeeping files (regenerated by the gate and hooks) are dropped, they do not strand the removal
wt o; mkdir -p "$TMP/am-o/.agents" && echo "# generated" > "$TMP/am-o/.agents/CHECKLIST.md" && echo real > "$TMP/am-o/real.txt"
fin ../am-o; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/am-o" ] && [ -f "$P/real.txt" ] && [ -z "$(G "$P" ls-files .agents/CHECKLIST.md)" ] && ok "15: untracked generated bookkeeping does not strand the removal, and is not carried" || fail "15: (rc=$rc): $(cat "$TMP/out")"

# 10b: a second merge of the same worktree while one runs is "running", not an error
wt p; echo p > "$TMP/am-p/p.txt"; python3 -c 'import json,sys,time;json.dump({"pid":int(sys.argv[2]),"at":time.time()},open(sys.argv[1],"w"))' "$(G "$TMP/am-p" rev-parse --absolute-git-dir)/devkit-automerge.lock" "$$"
JP="$(cd "$P" && bash "$KIT" worktree automerge ../am-p 2>/dev/null | tail -1)"
python3 -c 'import json,sys;d=json.loads(sys.argv[1]);sys.exit(0 if d["status"]=="blocked" and d.get("running") is True else 1)' "$JP" && ok "10b: a live merge of the same worktree is reported as running (JSON running: true)" || fail "10b: $JP"

# round 2 #2: a worktree on a PUBLISHED branch (has a remote ref) is never merged automatically
git init -q --bare "$TMP/origin.git" && G "$P" remote add origin "$TMP/origin.git" && G "$P" push -q origin main 2>/dev/null
G "$P" branch rel1 && G "$P" push -q origin rel1 2>/dev/null
G "$P" worktree add -q "$TMP/am-rel" rel1; echo r > "$TMP/am-rel/rel-only.txt"; REL1="$(G "$P" rev-parse rel1)"; HEAD17="$(G "$P" rev-parse HEAD)"
fin ../am-rel; rc=$?
[ "$rc" = 1 ] && grep -qi "published" "$TMP/out" && [ "$(G "$P" rev-parse rel1)" = "$REL1" ] && [ "$(G "$P" rev-parse HEAD)" = "$HEAD17" ] && [ -d "$TMP/am-rel" ] \
  && ok "16: a worktree on a published branch (remote ref): refused, the branch and main did not move" || fail "16: (rc=$rc): $(cat "$TMP/out")"
G "$P" worktree remove --force "$TMP/am-rel" 2>/dev/null

# round 2 #3: notes in the worktree's own (git-ignored) agent memory are copied into main's before the removal
echo ".agents/local/memory/" >> "$P/.gitignore"; G "$P" add .gitignore; G "$P" commit -qm "ignore agent memory"
wt q; mkdir -p "$TMP/am-q/.agents/local/memory/claude-auto" && echo "a lesson" > "$TMP/am-q/.agents/local/memory/claude-auto/lesson.md" && echo qq > "$TMP/am-q/q.txt"
fin ../am-q; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/am-q" ] && [ "$(cat "$P/.agents/local/memory/claude-auto/lesson.md" 2>/dev/null)" = "a lesson" ] \
  && ok "17: the worktree's own memory note is saved into main's before it goes" || fail "17: (rc=$rc): $(cat "$TMP/out")"

# round 2 #5: the secret-looking list is the gate's, plus the common extras; a template (.env.example) is not a secret
for secret in id_ecdsa .netrc serviceAccountKey.json AuthKey_ABC.p8 id_dsa; do
  wt s; echo "x" > "$TMP/am-s/$secret"; echo f > "$TMP/am-s/other.txt"; HS="$(G "$P" rev-parse HEAD)"
  fin ../am-s; rc=$?
  [ "$rc" = 1 ] && grep -q "$secret" "$TMP/out" && [ "$(G "$P" rev-parse HEAD)" = "$HS" ] && ok "18: $secret is never committed automatically" || fail "18: $secret (rc=$rc): $(cat "$TMP/out")"
  rm -f "$TMP/am-s/$secret"; fin ../am-s >/dev/null 2>&1
done
wt t; echo "KEY=" > "$TMP/am-t/.env.example"; fin ../am-t; rc=$?
[ "$rc" = 0 ] && [ -n "$(G "$P" ls-files .env.example)" ] && ok "  … a .env.example template is not a secret" || fail "  … template (rc=$rc): $(cat "$TMP/out")"

# round 2 #1: several automatic merges AT ONCE (a Stop with many subagent worktrees) must not corrupt main's index
for round in 1 2; do
  pids=()
  for n in 0 1 2 3; do G "$P" worktree add -q --detach "$TMP/am-par$round$n"; echo "p" > "$TMP/am-par$round$n/par$round$n.txt"; done
  for n in 0 1 2 3; do ( cd "$P" && exec bash "$KIT" worktree automerge "../am-par$round$n" >"$TMP/par$round$n.out" 2>&1 ) & pids+=($!); done
  for p in "${pids[@]}"; do wait "$p"; done
  all=1; for n in 0 1 2 3; do [ -f "$P/par$round$n.txt" ] && [ -n "$(G "$P" ls-files "par$round$n.txt")" ] && [ ! -d "$TMP/am-par$round$n" ] || all=0; done
  clean=1; [ -z "$(G "$P" diff --cached --name-only)" ] && [ -z "$(G "$P" status --porcelain --untracked-files=no)" ] && [ -z "$(G "$P" ls-files --others --exclude-standard | grep '^par')" ] || clean=0
  [ "$all" = 1 ] && [ "$clean" = 1 ] && ok "19.$round: four automatic merges at once: all landed, main's index and tree are clean" || fail "19.$round: (all=$all clean=$clean) $(G "$P" status --short | head -8) / $(cat "$TMP"/par${round}*.out | cut -c1-200)"
done

[ "$FAILS" -eq 0 ] && echo "worktree automerge: all checks passed" || { echo "worktree automerge: $FAILS FAILED"; exit 1; }
