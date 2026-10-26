#!/usr/bin/env bash
# Regression (OfficeReader 2026-10-08, user: "it creates a worktree and leaves it there"; "is there an automatic merge yet? I sit here
# making you run it 20 times and it is still not merged"; "just merge, and if there is a conflict fix it, safely"). The Stop gate only
# TOLD the agent to run diff | git apply, commit, remove: a worktree `worktree add` did not make (EnterWorktree, a subagent's) was
# refused by diff / remove outright, a patch onto a dirty shared main failed, and nothing ever finished the job.
# `agent-kit worktree finish <path>` (and `automerge`, the same with one JSON line) merges it by itself, from the main checkout:
#   - uncommitted work is REFUSED (#366: never auto-committed as `wip`); main is merged INTO the worktree (a conflict is resolved there, in a folder
#     nobody else touches); main only FAST-FORWARDS (another session's dirty / staged files are never touched); then the removal
#   1 committed work, main unchanged            2 uncommitted edit + new file: refused, then committed by hand   3 main moved on: merge commit
#   4 main holds another session's dirty + staged files: they survive untouched
#   5 conflict: exit 3, main untouched, markers in the worktree; resolving it and running again finishes the job
#   6 main has uncommitted edits on a file the worktree changed: nothing moves, exit 1; after the edit is committed it goes through
#   7 a worktree git made on its own (no devkit state, with harness files)   8 uncommitted work: refused, no commit hook runs   9 refusals: busy, detached main,
#   not a worktree, a live lock (from inside the worktree: no refusal since K4)    10 the JSON line of `automerge`
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
trap 'kill "${HOLD_PID:-}" 2>/dev/null; rm -rf "$TMP"' EXIT
hold() {   # hold <lock file>: a live process holds its flock, as a merge that is running does, until release
  rm -f "$TMP/held"
  python3 -I -c 'import fcntl,sys,time; f=open(sys.argv[1],"a"); fcntl.flock(f, fcntl.LOCK_EX); open(sys.argv[2],"w").close(); time.sleep(120)' "$1" "$TMP/held" &
  HOLD_PID=$!; for _ in $(seq 1 100); do [ -f "$TMP/held" ] && return 0; sleep 0.05; done
  fail "hold: the background holder never took the lock on $1"; release; return 1
}
release() { kill "$HOLD_PID" 2>/dev/null; wait "$HOLD_PID" 2>/dev/null; HOLD_PID=""; }
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

P="$TMP/main"; mkdir -p "$P" && G "$P" init -q -b main . && cd "$P" || exit 1
for f in a b c d f; do printf '1\n2\n3\n4\n5\n' > "$P/$f.txt"; done
G "$P" add -A && G "$P" commit -qm init
wt() { bash "$KIT" worktree add "../am-$1" --no-init >/dev/null 2>&1 || fail "add am-$1"; }
fin() { (cd "$P" && bash "$KIT" worktree finish "$@" >"$TMP/out" 2>&1); return $?; }
listed() { G "$P" worktree list | grep -q "$1"; }
wcom() { G "$TMP/am-$1" add -A -- "${@:3}" && G "$TMP/am-$1" commit -qm "$2"; }   # wcom <name> <message> [paths]: commit by hand (finish never does, #366)
clean_main() { [ -z "$(G "$P" status --porcelain --untracked-files=no)" ]; }

# 1: committed work, main did not move -> a pure fast-forward
wt a; sed -i.bak '5s/.*/A5/' "$TMP/am-a/a.txt" && rm "$TMP/am-a/a.txt.bak"; G "$TMP/am-a" commit -qam "a5"; WH="$(G "$TMP/am-a" rev-parse HEAD)"
fin ../am-a; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/am-a" ] && ! listed am-a && [ "$(G "$P" rev-parse HEAD)" = "$WH" ] && grep -q "^A5$" "$P/a.txt" && clean_main \
  && ok "1: committed work: main fast-forwards to it, the worktree is gone, main's tree is clean" || fail "1: (rc=$rc): $(cat "$TMP/out")"

# 2: uncommitted work (an edit and a new file)
wt b; printf '1\n2\n3\n4\nB5\n' > "$TMP/am-b/b.txt"; echo n > "$TMP/am-b/n.txt"
HEAD2="$(G "$P" rev-parse HEAD)"; WHEAD2="$(G "$TMP/am-b" rev-parse HEAD)"
fin ../am-b; rc=$?
[ "$rc" = 1 ] && [ -d "$TMP/am-b" ] && grep -q "b.txt" "$TMP/out" && grep -q "n.txt" "$TMP/out" && [ "$(G "$P" rev-parse HEAD)" = "$HEAD2" ] && [ "$(G "$TMP/am-b" rev-parse HEAD)" = "$WHEAD2" ] \
  && [ -f "$TMP/am-b/n.txt" ] && ! G "$TMP/am-b" log --format=%s | grep -q "^wip" \
  && ok "2: uncommitted edit + new file: refused (exit 1), both files named, no wip commit, nothing moved" || fail "2: refusal (rc=$rc): $(cat "$TMP/out")"
wcom b "b5 and n"
fin ../am-b; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/am-b" ] && grep -q "^B5$" "$P/b.txt" && [ -f "$P/n.txt" ] && clean_main \
  && ok "  … once committed by hand: merged, removed" || fail "  … after the commit (rc=$rc): $(cat "$TMP/out")"

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
G "$TMP/am-raw" add raw.txt && G "$TMP/am-raw" commit -qm raw   # by hand: only the work, never the setup file
fin ../am-raw; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/am-raw" ] && [ -f "$P/raw.txt" ] && [ -z "$(G "$P" ls-files .claude/settings.local.json)" ] \
  && ok "7: a worktree 'worktree add' did not make is adopted: merged and removed, the setup file (same bytes as main's) is not carried" || fail "7: (rc=$rc): $(cat "$TMP/out")"

# 8: uncommitted work: finish refuses and runs no commit hook of its own (#366); committed by hand, it goes through
mkdir -p "$P/.git/hooks" && printf '#!/bin/sh\necho "pre-commit says no" >&2\nexit 1\n' > "$P/.git/hooks/pre-commit" && chmod +x "$P/.git/hooks/pre-commit"
wt h; echo h > "$TMP/am-h/h.txt"
fin ../am-h; rc=$?
[ "$rc" = 1 ] && [ -d "$TMP/am-h" ] && [ -f "$TMP/am-h/h.txt" ] && grep -q "h.txt" "$TMP/out" && ! grep -q "pre-commit says no" "$TMP/out" && ok "8: uncommitted work holds it (exit 1), the file is named, the work is still in the worktree, no commit was tried" || fail "8: (rc=$rc): $(cat "$TMP/out")"
rm -f "$P/.git/hooks/pre-commit"
wcom h h
fin ../am-h; rc=$?; [ "$rc" = 0 ] && [ ! -d "$TMP/am-h" ] && [ -f "$P/h.txt" ] && ok "  … committed by hand, it goes through" || fail "  … retry after the commit (rc=$rc): $(cat "$TMP/out")"

# 9: refusals
wt i; touch "$(G "$TMP/am-i" rev-parse --absolute-git-dir)/BISECT_LOG"
fin ../am-i; rc=$?; [ "$rc" = 1 ] && [ -d "$TMP/am-i" ] && grep -q "bisect" "$TMP/out" && ok "9: a bisect in progress: refused" || fail "9: busy (rc=$rc): $(cat "$TMP/out")"
rm -f "$(G "$TMP/am-i" rev-parse --absolute-git-dir)/BISECT_LOG"
G "$P" checkout -q --detach; fin ../am-i; rc=$?; [ "$rc" = 1 ] && grep -q "detached HEAD" "$TMP/out" && ok "  … main on a detached HEAD: refused" || fail "  … detached main (rc=$rc): $(cat "$TMP/out")"
G "$P" checkout -q main
# K4 (17/10): từ trong worktree không còn bị từ chối, finish tự dùng main checkout (--keep: am-i còn cần cho các ca khoá bên dưới;
# ca gộp và gỡ thật: tests/worktree_git/test_worktree_finish_inside.sh)
(cd "$TMP/am-i" && bash "$KIT" worktree finish . --keep >"$TMP/out" 2>&1); rc=$?; [ "$rc" = 0 ] && ! grep -q "MAIN checkout" "$TMP/out" && [ -d "$TMP/am-i" ] && ok "  … from inside the worktree: runs from the main checkout by itself (--keep: kept)" || fail "  … inside (rc=$rc): $(cat "$TMP/out")"
fin ../nope; rc=$?; [ "$rc" = 1 ] && grep -q "not a registered worktree" "$TMP/out" && ok "  … a path that is not a worktree: refused" || fail "  … not a worktree (rc=$rc): $(cat "$TMP/out")"
fin; rc=$?; [ "$rc" != 0 ] && grep -q "usage" "$TMP/out" && ok "  … no argument: usage" || fail "  … usage missing"
LOCKF="$(G "$TMP/am-i" rev-parse --absolute-git-dir)/devkit-automerge.lock"
if hold "$LOCKF"; then   # a holder that never took the lock is a failure already (hold says so): the checks below would prove nothing
  fin ../am-i; rc=$?; [ "$rc" = 1 ] && grep -q "another automatic merge" "$TMP/out" && ok "  … another live automatic merge of the same worktree: refused" || fail "  … live lock (rc=$rc): $(cat "$TMP/out")"
  release
fi
if hold "$LOCKF"; then
  kill -9 "$HOLD_PID"; wait "$HOLD_PID" 2>/dev/null; HOLD_PID=""   # the merge was killed: no clean-up ran
  echo i > "$TMP/am-i/i.txt"; wcom i i
  fin ../am-i; rc=$?; [ "$rc" = 0 ] && [ ! -d "$TMP/am-i" ] && ok "  … the lock of a merge that was killed is free at once" || fail "  … killed holder's lock (rc=$rc): $(cat "$TMP/out")"
fi

# 10: the machine form
wt j; echo j > "$TMP/am-j/j.txt"; wcom j j
J="$(cd "$P" && bash "$KIT" worktree automerge ../am-j 2>/dev/null | tail -1)"; rc=$?
python3 -c 'import json,sys;d=json.loads(sys.argv[1]);sys.exit(0 if d["status"]=="merged" and d["path"].endswith("am-j") else 1)' "$J" && [ ! -d "$TMP/am-j" ] && ok "10: automerge prints one JSON line {status: merged, path, message}" || fail "10: automerge output: $J"

# 11: tracked file edited and a new note under .claude/ in an adopted worktree: that is the agent's WORK
mkdir -p "$P/.claude/agents" && echo "agent v1" > "$P/.claude/agents/x.md" && G "$P" add .claude/agents/x.md && G "$P" commit -qm "an agent definition"
G "$P" worktree add -q --detach "$TMP/am-agent"; echo "agent v2" > "$TMP/am-agent/.claude/agents/x.md"; mkdir -p "$TMP/am-agent/.claude/agent-memory/r" && echo "a lesson" > "$TMP/am-agent/.claude/agent-memory/r/new.md"
fin ../am-agent; rc=$?   # FIRST uncommitted: the oracle that .claude/ files are WORK (not setup) — finish refuses and names both (#366)
[ "$rc" = 1 ] && [ -d "$TMP/am-agent" ] && grep -q ".claude/agents/x.md" "$TMP/out" && grep -q ".claude/agent-memory/r/new.md" "$TMP/out" \
  && ok "11: uncommitted agent definition and agent-memory note under .claude/ are WORK: refused, both named" || fail "11: .claude/ work not refused/named (rc=$rc): $(cat "$TMP/out")"
G "$TMP/am-agent" add .claude/agents/x.md .claude/agent-memory/r/new.md && G "$TMP/am-agent" commit -qm "agent work"   # by hand: the work, not the setup
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
rm -f "$TMP/am-n/.env.local"; wcom n feat
fin ../am-n; rc=$?; [ "$rc" = 0 ] && [ -f "$P/feature.txt" ] && ok "  … without it the rest goes through" || fail "  … after removing it (rc=$rc): $(cat "$TMP/out")"

# 15: untracked bookkeeping files (regenerated by the gate and hooks) are dropped, they do not strand the removal
wt o; mkdir -p "$TMP/am-o/.agents" && echo "# generated" > "$TMP/am-o/.agents/CHECKLIST.md" && echo real > "$TMP/am-o/real.txt"; wcom o real real.txt
fin ../am-o; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/am-o" ] && [ -f "$P/real.txt" ] && [ -z "$(G "$P" ls-files .agents/CHECKLIST.md)" ] && ok "15: untracked generated bookkeeping does not strand the removal, and is not carried" || fail "15: (rc=$rc): $(cat "$TMP/out")"

# 10b: a second merge of the same worktree while one runs is "running", not an error
wt p; echo p > "$TMP/am-p/p.txt"
if hold "$(G "$TMP/am-p" rev-parse --absolute-git-dir)/devkit-automerge.lock"; then
  JP="$(cd "$P" && bash "$KIT" worktree automerge ../am-p 2>/dev/null | tail -1)"
  release
  python3 -c 'import json,sys;d=json.loads(sys.argv[1]);sys.exit(0 if d["status"]=="blocked" and d.get("running") is True else 1)' "$JP" && ok "10b: a live merge of the same worktree is reported as running (JSON running: true)" || fail "10b: $JP"
fi

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
wt q; mkdir -p "$TMP/am-q/.agents/local/memory/claude-auto" && echo "a lesson" > "$TMP/am-q/.agents/local/memory/claude-auto/lesson.md" && echo qq > "$TMP/am-q/q.txt"; wcom q qq q.txt
fin ../am-q; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/am-q" ] && [ "$(cat "$P/.agents/local/memory/claude-auto/lesson.md" 2>/dev/null)" = "a lesson" ] \
  && ok "17: the worktree's own memory note is saved into main's before it goes" || fail "17: (rc=$rc): $(cat "$TMP/out")"
# 17b (OCR r2, 26/10): not only claude-auto - every git-ignored file under .agents/local/ only the worktree holds (a red-patch, a stage note)
#     is carried into main before the removal; a file main already holds with OTHER bytes (the MEMORY.md index both edited) lands next to it
#     as <name>.from-<worktree>, main's own copy untouched. Before: the red-patch went with the folder (now the blocker `remove` shares would
#     keep the worktree instead, so finish carries them first).
# 17c: a destination main does NOT ignore (the worktree ignores it through its own core.excludesFile): nothing copied, the worktree kept
G "$P" config extensions.worktreeConfig true
wt r3; mkdir -p "$TMP/am-r3/.agents/local/stage"; echo "stage only here" > "$TMP/am-r3/.agents/local/stage/H.md"
printf '.agents/local/stage/\n' > "$TMP/r3-excl"; G "$TMP/am-r3" config --worktree core.excludesFile "$TMP/r3-excl"
echo r3 > "$TMP/am-r3/r3.txt"; wcom r3 r3 r3.txt
fin ../am-r3; rc=$?
[ "$rc" = 1 ] && [ -f "$TMP/am-r3/.agents/local/stage/H.md" ] && [ ! -e "$P/.agents/local/stage/H.md" ] && grep -q "\.agents/local/stage/H.md" "$TMP/out" \
  && ok "17c: a .agents/local/ file main would not ignore is not copied; the worktree is kept, naming it" || fail "17c: (rc=$rc): $(cat "$TMP/out")"
G "$P" worktree remove --force "$TMP/am-r3" 2>/dev/null; G "$P" config --unset extensions.worktreeConfig
echo ".agents/local/" >> "$P/.gitignore"; G "$P" add .gitignore; G "$P" commit -qm "ignore .agents/local"
echo "main index" > "$P/.agents/local/memory/claude-auto/MEMORY.md"
wt r2; mkdir -p "$TMP/am-r2/.agents/local/red-patches" "$TMP/am-r2/.agents/local/memory/claude-auto"
echo "diff --git a/x b/x" > "$TMP/am-r2/.agents/local/red-patches/BUG-9.patch"; echo "worktree index" > "$TMP/am-r2/.agents/local/memory/claude-auto/MEMORY.md"
echo r2 > "$TMP/am-r2/r2.txt"; wcom r2 r2 r2.txt
fin ../am-r2; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/am-r2" ] && [ "$(cat "$P/.agents/local/red-patches/BUG-9.patch" 2>/dev/null)" = "diff --git a/x b/x" ] \
  && [ "$(cat "$P/.agents/local/memory/claude-auto/MEMORY.md.from-am-r2" 2>/dev/null)" = "worktree index" ] \
  && [ "$(cat "$P/.agents/local/memory/claude-auto/MEMORY.md")" = "main index" ] \
  && ok "17b: finish carries every .agents/local/ file only the worktree holds (red-patch; MEMORY.md main has too -> MEMORY.md.from-am-r2), then removes it" \
  || fail "17b: (rc=$rc, exists=$([ -d "$TMP/am-r2" ] && echo y || echo n)): $(cat "$TMP/out")"
# 17d (OCR r3 W2, 26/10): a worktree NAME used before: main already holds MEMORY.md.from-am-x (an earlier session's carried index, other
#     bytes): finish puts this one at MEMORY.md.from-am-x.2 (created O_EXCL), never over the earlier copy. 17e: the same bytes already at
#     .from-<name>: nothing copied, the worktree goes.
echo "EARLIER carried copy" > "$P/.agents/local/memory/claude-auto/MEMORY.md.from-am-x"
wt x; mkdir -p "$TMP/am-x/.agents/local/memory/claude-auto"; echo "this worktree's index" > "$TMP/am-x/.agents/local/memory/claude-auto/MEMORY.md"
echo x > "$TMP/am-x/x.txt"; wcom x x x.txt
fin ../am-x; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/am-x" ] && [ "$(cat "$P/.agents/local/memory/claude-auto/MEMORY.md.from-am-x")" = "EARLIER carried copy" ] \
  && [ "$(cat "$P/.agents/local/memory/claude-auto/MEMORY.md.from-am-x.2" 2>/dev/null)" = "this worktree's index" ] && [ "$(cat "$P/.agents/local/memory/claude-auto/MEMORY.md")" = "main index" ] \
  && ok "17d: an earlier .from-am-x copy is never overwritten; this one lands at .from-am-x.2" \
  || fail "17d: (rc=$rc) .from-am-x='$(cat "$P/.agents/local/memory/claude-auto/MEMORY.md.from-am-x")': $(cat "$TMP/out")"
echo "same as carried" > "$P/.agents/local/memory/claude-auto/MEMORY.md.from-am-z"
wt z; mkdir -p "$TMP/am-z/.agents/local/memory/claude-auto"; echo "same as carried" > "$TMP/am-z/.agents/local/memory/claude-auto/MEMORY.md"
echo z > "$TMP/am-z/z.txt"; wcom z z z.txt
fin ../am-z; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/am-z" ] && [ ! -e "$P/.agents/local/memory/claude-auto/MEMORY.md.from-am-z.2" ] \
  && ok "17e: the same bytes already at .from-am-z: nothing copied, the worktree goes" || fail "17e: (rc=$rc): $(cat "$TMP/out")"
# 17f (OCR r3 W1): a git repo nested under .agents/local/ (a repo-copy stage) is listed by git as ONE folder entry ("…/kit-copy/"): it was
#     skipped as "not a file" and removed with the worktree. finish copies no folder: blocked, naming it; nothing touched
wt y; mkdir -p "$TMP/am-y/.agents/local/stage/kit-copy"; G "$TMP/am-y/.agents/local/stage/kit-copy" init -q .
echo "staged work awaiting the user" > "$TMP/am-y/.agents/local/stage/kit-copy/HANDOFF.md"; echo y > "$TMP/am-y/y.txt"; wcom y y y.txt
fin ../am-y; rc=$?
[ "$rc" = 1 ] && [ -f "$TMP/am-y/.agents/local/stage/kit-copy/HANDOFF.md" ] && grep -q "\.agents/local/stage/kit-copy/" "$TMP/out" \
  && [ ! -e "$P/.agents/local/stage/kit-copy" ] && ok "17f: a nested git repo under .agents/local/ blocks finish, named; nothing copied or removed" \
  || fail "17f: (rc=$rc, stage there: $([ -f "$TMP/am-y/.agents/local/stage/kit-copy/HANDOFF.md" ] && echo y || echo NO)): $(cat "$TMP/out")"
rm -rf "$TMP/am-y/.agents/local/stage"; G "$P" worktree remove --force "$TMP/am-y" 2>/dev/null

# round 2 #5: the secret-looking list is the gate's, plus the common extras; a template (.env.example) is not a secret
for secret in id_ecdsa .netrc serviceAccountKey.json AuthKey_ABC.p8 id_dsa; do
  wt s; echo "x" > "$TMP/am-s/$secret"; echo f > "$TMP/am-s/other.txt"; HS="$(G "$P" rev-parse HEAD)"
  fin ../am-s; rc=$?
  [ "$rc" = 1 ] && grep -q "$secret" "$TMP/out" && [ "$(G "$P" rev-parse HEAD)" = "$HS" ] && ok "18: $secret is never committed automatically" || fail "18: $secret (rc=$rc): $(cat "$TMP/out")"
  rm -f "$TMP/am-s/$secret"; wcom s other other.txt; fin ../am-s >/dev/null 2>&1
done
wt t; echo "KEY=" > "$TMP/am-t/.env.example"; fin ../am-t; rc=$?
[ "$rc" = 1 ] && ! grep -q "never committed automatically" "$TMP/out" && ok "  … a .env.example template is not called a secret (only plain uncommitted work)" || fail "  … template flagged as a secret (rc=$rc): $(cat "$TMP/out")"
wcom t tmpl; fin ../am-t; rc=$?
[ "$rc" = 0 ] && [ -n "$(G "$P" ls-files .env.example)" ] && ok "  … committed by hand, the template goes through" || fail "  … template (rc=$rc): $(cat "$TMP/out")"

# round 2 #1: several automatic merges AT ONCE (a Stop with many subagent worktrees) must not corrupt main's index
for round in 1 2; do
  pids=()
  for n in 0 1 2 3; do G "$P" worktree add -q --detach "$TMP/am-par$round$n"; echo "p" > "$TMP/am-par$round$n/par$round$n.txt"; G "$TMP/am-par$round$n" add -A && G "$TMP/am-par$round$n" commit -qm "par$round$n"; done
  for n in 0 1 2 3; do ( cd "$P" && exec bash "$KIT" worktree automerge "../am-par$round$n" >"$TMP/par$round$n.out" 2>&1 ) & pids+=($!); done
  for p in "${pids[@]}"; do wait "$p"; done
  all=1; for n in 0 1 2 3; do [ -f "$P/par$round$n.txt" ] && [ -n "$(G "$P" ls-files "par$round$n.txt")" ] && [ ! -d "$TMP/am-par$round$n" ] || all=0; done
  clean=1; [ -z "$(G "$P" diff --cached --name-only)" ] && [ -z "$(G "$P" status --porcelain --untracked-files=no)" ] && [ -z "$(G "$P" ls-files --others --exclude-standard | grep '^par')" ] || clean=0
  [ "$all" = 1 ] && [ "$clean" = 1 ] && ok "19.$round: four automatic merges at once: all landed, main's index and tree are clean" || fail "19.$round: (all=$all clean=$clean) $(G "$P" status --short | head -8) / $(cat "$TMP"/par${round}*.out | cut -c1-200)"
done

# R3 review P2-6 (14/10): the merge of main INTO a worktree rewrites its files, so a test run of that tree must not have them change under it. The
# run holds <worktree>/.claude/audit-gate/test_run.lock: while it does, the merge-in is skipped (never waited for, not an error: "running", the next Stop merges),
# and when it does not, the merge-in itself holds that lock (a post-merge hook probes it from inside the merge).
wt u; echo u > "$TMP/am-u/u.txt"; G "$TMP/am-u" add -A && G "$TMP/am-u" commit -qm "u"
echo m > "$P/u-main.txt"; G "$P" add u-main.txt && G "$P" commit -qm "main moves on (u)"   # main is ahead: the worktree needs the merge-in
UH="$(G "$TMP/am-u" rev-parse HEAD)"; MH="$(G "$P" rev-parse HEAD)"; UL="$TMP/am-u/.claude/audit-gate/test_run.lock"
mkdir -p "$TMP/am-u/.claude/audit-gate" && printf '*\n' > "$TMP/am-u/.claude/audit-gate/.gitignore"   # as the gates leave it: state is no work to commit
if hold "$UL"; then
  t0=$SECONDS; JU="$(cd "$P" && bash "$KIT" worktree automerge ../am-u --keep 2>/dev/null | tail -1)"; t1=$SECONDS; release
  python3 -c 'import json,sys;d=json.loads(sys.argv[1]);sys.exit(0 if d["status"]=="blocked" and d.get("running") is True and "test run" in d["message"] else 1)' "$JU" \
    && [ "$(G "$TMP/am-u" rev-parse HEAD)" = "$UH" ] && [ "$(G "$P" rev-parse HEAD)" = "$MH" ] && [ $((t1 - t0)) -lt 20 ] \
    && ok "20: a test run holds the worktree: main is not merged into it, nothing moves, no waiting (JSON running, said why)" \
    || fail "20: held by a test run: $JU / worktree HEAD $(G "$TMP/am-u" rev-parse --short HEAD) was $(echo "$UH" | cut -c1-7) / $((t1 - t0))s"
fi
printf '#!/bin/sh\npython3 -I -c '"'"'import fcntl,os,sys\nfd = os.open(sys.argv[1], os.O_RDONLY)\ntry:\n    fcntl.flock(fd, fcntl.LOCK_SH | fcntl.LOCK_NB); print("free")\nexcept OSError:\n    print("held")'"'"' "%s" >> "%s"\n' "$UL" "$TMP/probe" > "$P/.git/hooks/post-merge"
chmod +x "$P/.git/hooks/post-merge"; rm -f "$TMP/probe"
fin ../am-u --keep; rc=$?
[ "$rc" = 0 ] && [ -f "$P/u.txt" ] && [ "$(head -1 "$TMP/probe" 2>/dev/null)" = held ] && ok "20b: no test run: merged, and the merge-in held the worktree's test_run.lock (probed from inside it)" \
  || fail "20b: (rc=$rc) probe: $(tr '\n' ' ' < "$TMP/probe" 2>/dev/null): $(cat "$TMP/out")"
rm -f "$P/.git/hooks/post-merge"

[ "$FAILS" -eq 0 ] && echo "worktree automerge: all checks passed" || { echo "worktree automerge: $FAILS FAILED"; exit 1; }
