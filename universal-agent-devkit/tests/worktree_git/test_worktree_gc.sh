#!/usr/bin/env bash
# `agent-kit worktree gc` (W1 step 1, docs/workflow-improvements.md I.0 R5b; 2026-10-13: 8 orphan GeelyEx2-* folders, 1.25 GB, were
# left for the user because hardware_safety_gate rightly blocks an agent's `rm -rf` outside the project). gc deletes a folder only when
# every file in it is provably not unique: a symlink, noise (.DS_Store), DevKit bookkeeping, the same bytes as main's file at that path,
# a blob the repo already holds (a committed version), or an ignored build output that is not a secret. Candidates: registered
# worktrees already integrated, `<repo>-*` siblings whose `.git` pointer dangles into THIS repo, and `<repo>-*` siblings with no `.git`
# that hold bookkeeping only. A secret that exists only there, a unique file, a live session's worktree, or work not in main: kept,
# named in one line. --dry-run deletes nothing.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WT="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"; trap 'chflags -R nouchg "$TMP" 2>/dev/null; chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

R="$TMP/main"; mkdir -p "$R" && G "$R" init -q -b main .
printf 'local.properties\nbuild/\nconfig/\n*.sqlite\n.idea/\n.agents/local/\n*.jks\n' > "$R/.gitignore"
export WORKTREE_GC_MIN_AGE_S=0   # every folder here is minutes old; the age guard has its own case below
echo base > "$R/app.txt" && echo v1 > "$R/lib.txt" && G "$R" add -A && G "$R" commit -qm base
mkdir -p "$R/config" && echo '{"a":1}' > "$R/config/app.json" && G "$R" add -f config/app.json && G "$R" commit -qm "tracked file under an ignored dir"
mkdir -p "$R/.agents" && echo '{"items":{}}' > "$R/.agents/regression_status.json" && G "$R" add .agents/regression_status.json && G "$R" commit -qm status
echo v2 > "$R/lib.txt" && G "$R" commit -qam v2          # lib.txt "v1" is now an OLD committed blob
G "$R" branch feat && G "$R" worktree add -q "$TMP/feat-co" feat && mkdir -p "$TMP/feat-co/build" && echo kept > "$TMP/feat-co/build/keep.txt" \
  && G "$TMP/feat-co" add -f build/keep.txt && G "$TMP/feat-co" commit -qm "feat force-tracks build/keep.txt" && G "$R" worktree remove "$TMP/feat-co"
echo "sdk.dir=/same" > "$R/local.properties"             # main's own local config (ignored)
dangle() {   # dangle <name>: a worktree whose admin dir is gone, so its .git pointer dangles (the GeelyEx2 orphans)
  G "$R" worktree add -q --detach "$TMP/$1" && rm -rf "$R/.git/worktrees/$1"
}

# 1 a registered DevKit worktree (its devkit-worktree.json) that holds nothing beyond main: KEPT. Registered worktrees belong to the Stop
#   gate (worktree_merge_gate) and `worktree remove`, never to gc (review 3: removing them opened two more data-loss holes)
(cd "$R" && python3 "$WT" add "$TMP/main-merged" --no-init >/dev/null 2>&1) || fail "setup: worktree add main-merged"
mkdir -p "$TMP/main-merged/build" && echo bin > "$TMP/main-merged/build/out.bin"   # an ignored build output does not keep it
# 2 a registered worktree with a commit main lacks: kept
G "$R" worktree add -q --detach "$TMP/main-ahead" && echo x > "$TMP/main-ahead/x.txt" && G "$TMP/main-ahead" add x.txt && G "$TMP/main-ahead" commit -qm x
# 3 a dangling orphan: only committed content (an old blob), main's identical local config, a build output, noise, a link: deleted
dangle main-orphan-clean
echo v1 > "$TMP/main-orphan-clean/lib.txt"; cp "$R/local.properties" "$TMP/main-orphan-clean/"
mkdir -p "$TMP/main-orphan-clean/build/out" && echo bin > "$TMP/main-orphan-clean/build/out/app.bin"
echo png > "$TMP/main-orphan-clean/build/out/ảnh.png"   # a non-ASCII build output: git quotes such names unless core.quotePath=false
: > "$TMP/main-orphan-clean/.DS_Store"; ln -s "$R" "$TMP/main-orphan-clean/link-to-main"
chflags uchg "$TMP/main-orphan-clean/app.txt" 2>/dev/null   # a locked copy (INSTINCT-038) must not strand it
# 4 a dangling orphan with a file never committed: kept
dangle main-orphan-unique; echo "work only here" > "$TMP/main-orphan-unique/notes.md"
# 5 no .git at all, bookkeeping only (what a gate wrote after its worktree was removed): deleted
mkdir -p "$TMP/main-gate-orphan/.claude/audit-gate" "$TMP/main-gate-orphan/.agents/evidence/REG-1" "$TMP/main-gate-orphan/.agents/regression_journal" "$TMP/main-gate-orphan/__pycache__"
: > "$TMP/main-gate-orphan/.claude/audit-gate/test_run.lock"; echo log > "$TMP/main-gate-orphan/.agents/evidence/REG-1/a.log"
echo '{}' > "$TMP/main-gate-orphan/.agents/regression_journal/journal.jsonl"; : > "$TMP/main-gate-orphan/.DS_Store"
# 6 a secret that exists only there (the Neighbours keystore case): kept, and said so
dangle main-orphan-secret; echo "sdk.dir=/different" > "$TMP/main-orphan-secret/local.properties"
# 7 not ours: a sibling with another prefix, and a <repo>-* folder without .git holding a person's file, nothing, or only links
mkdir -p "$TMP/other-thing" && echo keep > "$TMP/other-thing/f.txt"
mkdir -p "$TMP/main-notes" && echo "my notes" > "$TMP/main-notes/todo.txt"
mkdir -p "$TMP/main-empty/sub" "$TMP/main-links" && ln -s "$R" "$TMP/main-links/to-main"
# 8 a full copy with its own .git DIRECTORY (a person's clone or backup): never ours
mkdir -p "$TMP/main-backup" && cp -R "$R/.git" "$TMP/main-backup/.git" && cp "$R/app.txt" "$TMP/main-backup/"
# 10 a new file under a build-folder name that git does NOT ignore here (out/): work, kept; and a secret named in another case: kept
dangle main-orphan-outdir; mkdir -p "$TMP/main-orphan-outdir/out" && echo "not ignored" > "$TMP/main-orphan-outdir/out/new.txt"
dangle main-orphan-casesecret; echo key > "$TMP/main-orphan-casesecret/Release.JKS"
# --- review 4: each of these must be KEPT ---
# .antigravity-pm/ holds people's briefs, plans and scripts, not only machine logs
dangle main-orphan-pm; mkdir -p "$TMP/main-orphan-pm/.antigravity-pm/tasks/T1" && echo "plan only here" > "$TMP/main-orphan-pm/.antigravity-pm/tasks/T1/plan.md"
mkdir -p "$TMP/main-np/.antigravity-pm" && echo "print(1)" > "$TMP/main-np/.antigravity-pm/tool.py"
# a name ending in CR next to its committed twin: hash-object --stdin-paths drops the CR and hashes the twin
dangle main-orphan-cr; echo v1 > "$TMP/main-orphan-cr/lib.txt"; echo "unique" > "$TMP/main-orphan-cr/lib.txt"$'\r'
# DevKit bookkeeping next to a person's empty folder: not a leftover
mkdir -p "$TMP/main-gate-mixed/.claude/audit-gate" "$TMP/main-gate-mixed/my-project/src" && : > "$TMP/main-gate-mixed/.claude/audit-gate/test_run.lock"
# a service-account key under build/ is no build output
dangle main-orphan-sakey; mkdir -p "$TMP/main-orphan-sakey/build" && echo '{"type":"service_account"}' > "$TMP/main-orphan-sakey/build/service-account.json"
# 9 a memory note written in a dangling orphan and not in main: kept
dangle main-orphan-memory; mkdir -p "$TMP/main-orphan-memory/.agents/local/memory/claude-auto" && echo note > "$TMP/main-orphan-memory/.agents/local/memory/claude-auto/n.md"

# --- review of d5ec03e: each of these must be KEPT ---
# B a commit made on the orphan's detached HEAD: its blob is in the object DB but no ref holds it any more
G "$R" worktree add -q --detach "$TMP/main-orphan-detcommit" && echo "work only here" > "$TMP/main-orphan-detcommit/work.txt" \
  && G "$TMP/main-orphan-detcommit" add work.txt && G "$TMP/main-orphan-detcommit" commit -qm w && rm -rf "$R/.git/worktrees/main-orphan-detcommit"
# C a file only staged (git add) before the admin dir went
G "$R" worktree add -q --detach "$TMP/main-orphan-staged" && echo "staged only" > "$TMP/main-orphan-staged/st.txt" \
  && G "$TMP/main-orphan-staged" add st.txt && rm -rf "$R/.git/worktrees/main-orphan-staged"
# A main TRACKS config/app.json under an ignored dir: the orphan's own edit of it is work, not an ignored file
dangle main-orphan-trackedignored; echo '{"a":2}' > "$TMP/main-orphan-trackedignored/config/app.json"
# D ignored is not rebuildable: a database, an IDE workspace, a handoff note under .agents/local/
dangle main-orphan-ignoreddata; echo db > "$TMP/main-orphan-ignoreddata/data.sqlite"
mkdir -p "$TMP/main-orphan-ignoreddata/.idea" "$TMP/main-orphan-ignoreddata/.agents/local"; echo ws > "$TMP/main-orphan-ignoreddata/.idea/workspace.xml"
echo "handoff" > "$TMP/main-orphan-ignoreddata/.agents/local/handoff.md"
# I authored checklist rows in regression_status.json (people's bug/REQ rows) that main lacks
dangle main-orphan-status; echo '{"items":{"BUG-1":{"kind":"bug","title":"only here"}}}' > "$TMP/main-orphan-status/.agents/regression_status.json"
# review: a worktree a PERSON made (no devkit-worktree.json), clean: never removed by gc
G "$R" worktree add -q --detach "$TMP/main-review"
# H a DevKit worktree whose session is alive but idle (waiting for the user): not removed
(cd "$R" && python3 "$WT" add "$TMP/main-idle" --no-init >/dev/null 2>&1) || fail "setup: worktree add main-idle"
python3 -c 'import json,sys,time; json.dump({"session_id":"S","pid":int(sys.argv[2]),"heartbeat":time.time(),"idle_since":time.time()},open(sys.argv[1],"w"))' \
  "$R/.git/worktrees/main-idle/devkit-session.lock" "$$"
# F a DevKit worktree, integrated, but holding a memory note main lacks
(cd "$R" && python3 "$WT" add "$TMP/main-memnote" --no-init >/dev/null 2>&1) || fail "setup: worktree add main-memnote"
mkdir -p "$TMP/main-memnote/.agents/local/memory/claude-auto" && echo note > "$TMP/main-memnote/.agents/local/memory/claude-auto/x.md"
# --- review 2: each of these must be KEPT ---
# P1 a REGISTERED DevKit worktree, integrated, no live session, with ignored files only it has: `remove --force` would delete them
(cd "$R" && python3 "$WT" add "$TMP/main-regignored" --no-init >/dev/null 2>&1) || fail "setup: worktree add main-regignored"
mkdir -p "$TMP/main-regignored/.agents/local" && echo handoff > "$TMP/main-regignored/.agents/local/handoff.md"
echo db > "$TMP/main-regignored/app.sqlite"; echo key > "$TMP/main-regignored/release.jks"
# P2 an orphan's own edit of build/keep.txt, which branch feat TRACKS (main does not): not a build output
dangle main-orphan-forcetracked; mkdir -p "$TMP/main-orphan-forcetracked/build" && echo "edited" > "$TMP/main-orphan-forcetracked/build/keep.txt"

exists() { [ -e "$TMP/$1" ]; }
cd "$R" || exit 1
python3 "$WT" gc --dry-run > "$TMP/dry.out" 2>&1; rc=$?
[ "$rc" = 0 ] && ok "gc --dry-run exits 0" || fail "gc --dry-run rc=$rc: $(cat "$TMP/dry.out")"
for d in main-merged main-orphan-clean main-gate-orphan; do exists "$d" || fail "--dry-run deleted $d"; done
grep -q "main-orphan-clean" "$TMP/dry.out" && ok "--dry-run lists what it would delete and deletes nothing" || fail "--dry-run lists nothing: $(cat "$TMP/dry.out")"

python3 "$WT" gc > "$TMP/gc.out" 2>&1; rc=$?; [ "$rc" = 0 ] || tail -5 "$TMP/gc.out" >&2
[ "$rc" = 0 ] && ok "gc exits 0" || fail "gc rc=$rc: $(cat "$TMP/gc.out")"
for d in main-orphan-clean main-gate-orphan; do
  exists "$d" && fail "$d should be deleted: $(cat "$TMP/gc.out")" || ok "deleted: $d"
done
for d in main-merged main-empty main-links main-ahead main-orphan-unique main-orphan-secret other-thing main-notes main-backup main-orphan-memory \
         main-orphan-detcommit main-orphan-staged main-orphan-trackedignored main-orphan-ignoreddata main-orphan-status \
         main-review main-idle main-memnote main-regignored main-orphan-forcetracked main-orphan-outdir main-orphan-casesecret \
         main-orphan-pm main-np main-orphan-cr main-gate-mixed main-orphan-sakey; do
  exists "$d" && ok "kept: $d" || fail "$d was deleted (it holds something unique or is not ours)"
done
grep -q "main-orphan-unique.*notes.md" "$TMP/gc.out" && ok "the kept orphan names its unique file" || fail "no reason for main-orphan-unique: $(cat "$TMP/gc.out")"
grep -q "main-orphan-secret.*local.properties" "$TMP/gc.out" && ok "the kept orphan names its secret" || fail "no reason for main-orphan-secret: $(cat "$TMP/gc.out")"
grep -q "main-orphan-casesecret.*Release.JKS" "$TMP/gc.out" && ok "  … whatever the case of its name" || fail "no reason for main-orphan-casesecret: $(cat "$TMP/gc.out")"
# a pid this user may not signal (EPERM, pid 1) is a LIVE holder: the module's one _pid_alive (the automerge lock relies on it)
(cd "$DEVKIT_DIR/scripts/git" && python3 -I -c 'import sys; sys.path.insert(0, "."); import worktree as w; sys.exit(0 if w._pid_alive(1) else 1)') \
  && ok "_pid_alive: EPERM counts as alive" || fail "_pid_alive(1) reads as dead"
# a folder changed in the last WORKTREE_GC_MIN_AGE_S seconds may be a worktree add still being written: never touched
dangle main-orphan-young; echo v1 > "$TMP/main-orphan-young/lib.txt"
WORKTREE_GC_MIN_AGE_S=600 python3 "$WT" gc > "$TMP/gc3.out" 2>&1
exists main-orphan-young && ok "a folder younger than the age guard is left alone" || fail "gc deleted a folder made seconds ago"
# --log=<file>: each run that DELETED something appends a stamped record, written under the gc lock; a run that only kept or found
# nothing writes nothing (the record of a deletion is never pushed out by repeats)
dangle main-orphan-logged; echo v1 > "$TMP/main-orphan-logged/lib.txt"
python3 "$WT" gc --log="$TMP/gc.log" >/dev/null 2>&1
grep -q "^== " "$TMP/gc.log" 2>/dev/null && grep -q "main-orphan-logged" "$TMP/gc.log" && ok "--log records what it deleted, stamped" \
  || fail "no deletion record: $(cat "$TMP/gc.log" 2>&1)"
python3 "$WT" gc --log="$TMP/gc.log" >/dev/null 2>&1
[ "$(grep -c '^== ' "$TMP/gc.log" 2>/dev/null)" = 1 ] && ok "  … and a run that deletes nothing adds nothing" || fail "a no-delete run wrote a record: $(cat "$TMP/gc.log")"
# a sweep never dies midway (it would leave the folders after it, every session): a `.git` file that is not UTF-8, and a ref holding a
# path that is not UTF-8 (made with plumbing: APFS refuses such a name on disk)
mkdir -p "$TMP/main-a-badgit" && printf 'gitdir: \377\376\n' > "$TMP/main-a-badgit/.git"
blob=$(echo w | G "$R" hash-object -w --stdin); tree=$(printf '100644 blob %s\t\377.txt\n' "$blob" | G "$R" mktree)
G "$R" update-ref refs/heads/weird "$(G "$R" commit-tree "$tree" -m weird)"
dangle main-z-after; echo v1 > "$TMP/main-z-after/lib.txt"; echo "v1" > "$TMP/main-z-after/old.txt"
python3 "$WT" gc --log="$TMP/gc6.log" > "$TMP/gc6.out" 2>&1; rc=$?
[ "$rc" = 0 ] && ! exists main-z-after && exists main-a-badgit && grep -q "main-z-after" "$TMP/gc6.log" 2>/dev/null \
  && ok "an unreadable .git and a non-UTF-8 path in a ref: the sweep goes on, and records what it deleted" \
  || fail "the sweep died or stopped: rc=$rc $(tail -3 "$TMP/gc6.out")"
G "$R" update-ref -d refs/heads/weird
# one gc per repo: while another holds the lock, gc deletes nothing and prints nothing
dangle main-orphan-locked; echo v1 > "$TMP/main-orphan-locked/lib.txt"
python3 -I -c 'import fcntl,sys,time; f=open(sys.argv[1],"a"); fcntl.flock(f, fcntl.LOCK_EX); open(sys.argv[2],"w").close(); time.sleep(20)' \
  "$R/.git/devkit-gc.lock" "$TMP/locked" & LOCKER=$!
for _ in $(seq 1 50); do [ -e "$TMP/locked" ] && break; sleep 0.1; done
python3 "$WT" gc > "$TMP/gc4.out" 2>&1; rc=$?
kill "$LOCKER" 2>/dev/null; wait "$LOCKER" 2>/dev/null
[ "$rc" = 0 ] && [ ! -s "$TMP/gc4.out" ] && exists main-orphan-locked && ok "a second gc while one runs: silent no-op" || fail "second gc rc=$rc: $(cat "$TMP/gc4.out")"
[ -f "$R/local.properties" ] && [ "$(cat "$R/local.properties")" = "sdk.dir=/same" ] && ok "main's own local config is untouched" || fail "main's local.properties changed"
G "$R" worktree list --porcelain | grep -q "main-merged" && ok "a registered worktree stays registered: not gc's" || fail "gc unregistered main-merged"
[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_gc: all passed" || { echo "❌ test_worktree_gc: $FAILS failed"; exit 1; }
