#!/usr/bin/env bash
# `agent-kit worktree gc` (W1 step 1, docs/workflow-improvements.md I.0 R5b; 2026-10-13: 8 orphan GeelyEx2-* folders, 1.25 GB, were
# left for the user because hardware_safety_gate rightly blocks an agent's `rm -rf` outside the project). gc deletes a folder only when
# every file in it is provably not unique: a symlink main has too (same path, same target) or a DevKit kit link (issue #12 / #40: any
# other symlink is work), noise (.DS_Store), DevKit bookkeeping, the same bytes as main's file at that path,
# the blob a kept commit holds AT THAT PATH (a committed version of that file), or an ignored build output that is not a secret
# (issue #12: a new path holding bytes committed elsewhere is work, not a committed version). Candidates: registered
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
# 3 a dangling orphan: only committed content (an old blob), main's identical local config, a build output, noise, a DevKit kit
#   link (into main's universal-agent-devkit/: install state, issue #12 / #40): deleted
dangle main-orphan-clean
echo v1 > "$TMP/main-orphan-clean/lib.txt"; cp "$R/local.properties" "$TMP/main-orphan-clean/"
mkdir -p "$TMP/main-orphan-clean/build/out" && echo bin > "$TMP/main-orphan-clean/build/out/app.bin"
echo png > "$TMP/main-orphan-clean/build/out/ảnh.png"   # a non-ASCII build output: git quotes such names unless core.quotePath=false
mkdir -p "$R/universal-agent-devkit/skills/x"   # thư mục rỗng: git không thấy, main không bẩn
: > "$TMP/main-orphan-clean/.DS_Store"; ln -s "$R/universal-agent-devkit/skills/x" "$TMP/main-orphan-clean/kit-skill-x"
chflags uchg "$TMP/main-orphan-clean/app.txt" 2>/dev/null   # a locked copy (INSTINCT-038) must not strand it
# 4 a dangling orphan with a file never committed: kept
dangle main-orphan-unique; echo "work only here" > "$TMP/main-orphan-unique/notes.md"
# 4b issue #12: a NEW path whose bytes some ref holds at ANOTHER path is uncommitted work too, kept: a copy of app.txt (a current
#    blob), and lib.txt's old "v1" under a new name (an old blob)
dangle main-orphan-copy; cp "$R/app.txt" "$TMP/main-orphan-copy/copy.txt"
dangle main-orphan-oldblob; mkdir -p "$TMP/main-orphan-oldblob/notes" && echo v1 > "$TMP/main-orphan-oldblob/notes/old.txt"
# 4c issue #12 (QA): an uncommitted edit of a TRACKED path that gives it another file's bytes (lib.txt := app.txt): work, kept
dangle main-orphan-trackedcopy; cp "$R/app.txt" "$TMP/main-orphan-trackedcopy/lib.txt"
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
# 10 a new file under a build-folder name that git does NOT ignore here (out/): work, kept; and a secret named in another case, only
#    the orphan has it: recognised as a secret, so (A.1b #12, tests/worktree_git/test_worktree_secret_carry.sh) copied into main, then deleted
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
         main-review main-idle main-memnote main-regignored main-orphan-forcetracked main-orphan-outdir \
         main-orphan-pm main-np main-orphan-cr main-gate-mixed main-orphan-sakey main-orphan-copy main-orphan-oldblob main-orphan-trackedcopy; do
  exists "$d" && ok "kept: $d" || fail "$d was deleted (it holds something unique or is not ours)"
done
grep -q "main-orphan-unique.*notes.md" "$TMP/gc.out" && ok "the kept orphan names its unique file" || fail "no reason for main-orphan-unique: $(cat "$TMP/gc.out")"
grep -q "main-orphan-secret.*local.properties" "$TMP/gc.out" && ok "the kept orphan names its secret" || fail "no reason for main-orphan-secret: $(cat "$TMP/gc.out")"
grep -q "main-orphan-copy.*copy.txt" "$TMP/gc.out" && grep -q "main-orphan-oldblob.*notes/old.txt" "$TMP/gc.out" \
  && ok "a new path holding bytes committed elsewhere is named as unique work (issue #12)" || fail "no reason for main-orphan-copy/oldblob: $(cat "$TMP/gc.out")"
grep -q "main-orphan-trackedcopy.*lib.txt" "$TMP/gc.out" && ok "a tracked path given another file's bytes is named as unique work (issue #12)" \
  || fail "no reason for main-orphan-trackedcopy: $(cat "$TMP/gc.out")"
! exists main-orphan-casesecret && [ "$(cat "$R/Release.JKS" 2>/dev/null)" = key ] && [ -z "$(G "$R" status --porcelain -- Release.JKS)" ] \
  && grep -q "main-orphan-casesecret.*Release.JKS" "$TMP/gc.out" \
  && ok "  … a secret whatever the case of its name (Release.JKS), only the orphan's: copied into main (ignored there), named, then the orphan deleted" \
  || fail "main-orphan-casesecret: exists=$(exists main-orphan-casesecret && echo y || echo n) main has=$(cat "$R/Release.JKS" 2>&1): $(cat "$TMP/gc.out")"
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
dangle main-z-after; echo v1 > "$TMP/main-z-after/lib.txt"
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
# issue #12 review F1: a clean checkout of an OLD commit after main moved a file (git mv) and an empty file now lives elsewhere: rev-list
# names each blob once, under its newest path, so the (blob, path) pair is missed there; the history of the orphan's own paths holds
# both versions, so the leftover is deleted, not stranded
mkdir -p "$R/pkg" && echo "moved later" > "$R/mv-src.txt" && : > "$R/pkg/__init__.py" && G "$R" add mv-src.txt pkg/__init__.py && G "$R" commit -qm "add"
dangle main-orphan-moved
# issue #12 (QA): the same old checkout plus a COPY of the file main later moves: its history is asked in the same call, yet the
# copy's own path never held those bytes, so the copy is work and the folder is kept
dangle main-orphan-movedcopy; cp "$TMP/main-orphan-movedcopy/mv-src.txt" "$TMP/main-orphan-movedcopy/mv-copy.txt"
mkdir -p "$R/other" && : > "$R/other/__init__.py" && G "$R" mv mv-src.txt mv-dst.txt && G "$R" rm -q pkg/__init__.py && G "$R" add other/__init__.py \
  && G "$R" commit -qm "move, drop, add elsewhere"
# issue #12 Context a (QA): a NEW empty file (newpkg/__init__.py) while kept commits hold the empty blob at other paths: uncommitted work, kept
dangle main-orphan-empty; mkdir -p "$TMP/main-orphan-empty/newpkg" && : > "$TMP/main-orphan-empty/newpkg/__init__.py"
python3 "$WT" gc > "$TMP/gc7.out" 2>&1; rc=$?
[ "$rc" = 0 ] && ! exists main-orphan-moved && ok "a clean old checkout whose files main later moved or emptied elsewhere is deleted" \
  || fail "main-orphan-moved stranded (rc=$rc): $(cat "$TMP/gc7.out")"
exists main-orphan-empty && grep -q "main-orphan-empty.*newpkg/__init__.py" "$TMP/gc7.out" \
  && ok "a new empty file whose blob kept commits hold only at other paths is kept and named (issue #12)" \
  || fail "main-orphan-empty deleted or unnamed: $(cat "$TMP/gc7.out")"
exists main-orphan-movedcopy && grep -q "main-orphan-movedcopy.*mv-copy.txt" "$TMP/gc7.out" \
  && ok "a copy of a file whose own path history is asked in the same call is kept and named (issue #12)" \
  || fail "main-orphan-movedcopy deleted or unnamed: $(cat "$TMP/gc7.out")"
# issue #12 (#40): symlink trong orphan là việc riêng — trừ khi main có symlink cùng đường dẫn + cùng đích, hoặc là link kit DevKit
# tự cài (trỏ vào universal-agent-devkit/ / .agents/devkit/ của main); không đi theo link
ln -s /opt/tool "$R/tool-link"   # symlink chưa track của main
dangle main-orphan-newlink; mkdir -p "$TMP/main-orphan-newlink/src" && ln -s /x "$TMP/main-orphan-newlink/src/newlink"
mkdir -p "$TMP/elsewhere-dir"; dangle main-orphan-dirlink; ln -s "$TMP/elsewhere-dir" "$TMP/main-orphan-dirlink/dirlink"
dangle main-orphan-samelink; ln -s /opt/tool "$TMP/main-orphan-samelink/tool-link"
dangle main-orphan-otherlink; ln -s /opt/other "$TMP/main-orphan-otherlink/tool-link"   # cùng đường dẫn, KHÁC đích
dangle main-orphan-kitlink; mkdir -p "$TMP/main-orphan-kitlink/.agents/skills" \
  && ln -s "$R/universal-agent-devkit/skills/x" "$TMP/main-orphan-kitlink/.agents/skills/x" \
  && ln -s ../../universal-agent-devkit "$TMP/main-orphan-kitlink/.agents/devkit-rel"   # link tương đối, realpath ra ngoài main: việc riêng
python3 "$WT" gc > "$TMP/gc8.out" 2>&1; rc=$?
exists main-orphan-newlink && grep -q "main-orphan-newlink.*src/newlink" "$TMP/gc8.out" \
  && ok "an orphan with a new symlink main lacks is kept and names the link (#40)" || fail "main-orphan-newlink deleted or unnamed: $(cat "$TMP/gc8.out")"
exists main-orphan-dirlink && grep -q "main-orphan-dirlink.*dirlink" "$TMP/gc8.out" \
  && ok "an orphan with a new symlink to a directory is kept and names it, the link not followed (#40)" || fail "main-orphan-dirlink: $(cat "$TMP/gc8.out")"
exists main-orphan-otherlink && grep -q "main-orphan-otherlink.*tool-link" "$TMP/gc8.out" \
  && ok "a symlink at main's path but with another target is kept (#40)" || fail "main-orphan-otherlink: $(cat "$TMP/gc8.out")"
[ "$rc" = 0 ] && ! exists main-orphan-samelink && ok "an orphan whose symlink equals main's (same path, same target) is deleted (#40)" \
  || fail "main-orphan-samelink stranded (rc=$rc): $(cat "$TMP/gc8.out")"
exists main-orphan-kitlink && grep -q "main-orphan-kitlink.*devkit-rel" "$TMP/gc8.out" && ! grep -q "main-orphan-kitlink.*skills/x" "$TMP/gc8.out" \
  && ok "a kit link into main's kit is install state, a link resolving outside it is work (#40)" || fail "main-orphan-kitlink: $(cat "$TMP/gc8.out")"
[ -d "$TMP/elsewhere-dir" ] && [ -L "$R/tool-link" ] && ok "gc never followed a link into what it points to" || fail "a link target was deleted"
# issue #12 (#40): tuổi xét mọi file/thư mục vòng duyệt đi qua, không chỉ thư mục gốc + .git: file trong thư mục con vừa ghi lại → giữ
dangle main-orphan-young; dangle main-orphan-old
find "$TMP/main-orphan-young" "$TMP/main-orphan-old" -exec touch -h -t 202601010000 {} +
touch "$TMP/main-orphan-young/config/app.json"   # ghi lại (cùng nội dung): mtime mới, thư mục gốc + .git + config/ vẫn cũ
WORKTREE_GC_MIN_AGE_S=600 python3 "$WT" gc > "$TMP/gc9.out" 2>&1; rc=$?
exists main-orphan-young && grep -q "main-orphan-young.*config/app.json" "$TMP/gc9.out" \
  && ok "an orphan with a subfolder file written within WORKTREE_GC_MIN_AGE_S is kept and named, root and .git old (#40)" \
  || fail "main-orphan-young deleted or unnamed: $(cat "$TMP/gc9.out")"
[ "$rc" = 0 ] && ! exists main-orphan-old && ok "  … the same orphan with every file old is deleted (the age check keeps only what is new)" \
  || fail "main-orphan-old stranded (rc=$rc): $(cat "$TMP/gc9.out")"
# issue #327: a folder under main's own .claude/worktrees/ that git no longer registers is a leftover too (23/10: issue-249-qa kept 2509
# files, issue-123-review 624, neither with a `.git`, and gc only swept `<repo>-*` siblings). There the missing `.git` is judged like a
# dangling pointer: every file must be provably not unique. A registered worktree, a young folder and a unique file stay.
WD="$R/.claude/worktrees"; mkdir -p "$WD"
mkdir -p "$WD/orphan-nogit/build" && cp "$R/app.txt" "$WD/orphan-nogit/" && echo v1 > "$WD/orphan-nogit/lib.txt" && echo bin > "$WD/orphan-nogit/build/o.bin"   # same bytes as main, an old committed blob, a build output
mkdir -p "$WD/orphan-empty/sub/deeper"                                                        # nothing at all (the vibrant-meninsky case)
mkdir -p "$WD/leftover-unique" && echo "work only here" > "$WD/leftover-unique/notes.md"          # never committed: work
G "$R" worktree add -q --detach "$WD/registered" && rm -f "$WD/registered/.git"               # git still registers it (prunable, no `.git` left): never gc's
CASEVAR=0
if [ -d "$R/.CLAUDE" ]; then   # a case-insensitive volume: git may spell a registered path another way, the folder is the same inode
  G "$R" worktree add -q --detach "$R/.CLAUDE/worktrees/casevar" && rm -f "$WD/casevar/.git" && CASEVAR=1
fi
mkdir -p "$WD/fresh-empty"                                                                    # a scratch dir a gate made a moment ago, nothing in it yet
mkdir -p "$WD/orphan-young" && echo v1 > "$WD/orphan-young/lib.txt"
python3 "$WT" gc --dry-run > "$TMP/gc10d.out" 2>&1
grep -q "orphan-nogit" "$TMP/gc10d.out" && [ -e "$WD/orphan-nogit" ] && ok "--dry-run lists an unregistered .claude/worktrees folder and deletes nothing (#327)" \
  || fail "--dry-run did not list orphan-nogit: $(cat "$TMP/gc10d.out")"
find "$WD/orphan-nogit" "$WD/orphan-empty" "$WD/leftover-unique" "$WD/registered" -exec touch -h -t 202601010000 {} +   # old: only the age guard may tell them from the young two
[ "$CASEVAR" = 0 ] || find "$WD/casevar" -exec touch -h -t 202601010000 {} +
find "$WD/orphan-young" -exec touch -h {} +
WORKTREE_GC_MIN_AGE_S=600 python3 "$WT" gc > "$TMP/gc10y.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$WD/orphan-nogit" ] && [ ! -e "$WD/orphan-empty" ] \
  && ok "an unregistered .claude/worktrees folder with nothing unique (or nothing at all) is deleted once it is older than the age guard (#327)" \
  || fail "orphan-nogit / orphan-empty stranded (rc=$rc): $(cat "$TMP/gc10y.out")"
[ -e "$WD/orphan-young" ] && [ -e "$WD/fresh-empty" ] && ok "  … while one younger than the age guard is left alone, an empty one too (#327)" \
  || fail "orphan-young / fresh-empty was deleted: $(cat "$TMP/gc10y.out")"
[ "$CASEVAR" = 0 ] || { [ -e "$WD/casevar" ] && ok "  … a registered worktree git spells with another case is the same folder, not gc's (#327)" || fail "casevar deleted: $(cat "$TMP/gc10y.out")"; }
python3 "$WT" gc > "$TMP/gc10.out" 2>&1
[ -e "$WD/leftover-unique" ] && grep -q "leftover-unique.*notes.md" "$TMP/gc10.out" \
  && ok "  … one holding a file never committed is kept and names it (#327)" || fail "leftover-unique deleted or unnamed: $(cat "$TMP/gc10.out")"
[ -e "$WD/registered" ] && { [ "$CASEVAR" = 0 ] || [ -e "$WD/casevar" ]; } && G "$R" worktree list --porcelain | grep -q "$WD/registered" \
  && ok "  … a worktree git still registers under .claude/worktrees is not gc's (#327)" || fail "registered worktree touched: $(cat "$TMP/gc10.out")"
# issue #327 (b): a worktree locked `devkit-kept` by a session whose pid is dead stays locked for ever (only `remove` opened it): gc reports
# it (--dry-run) and opens it; a lock whose pid still answers is never touched
sleep 300 & LIVEPID=$!
DEADPID=$(python3 -c 'import os,subprocess; p=subprocess.Popen(["true"]); p.wait(); print(p.pid)')
G "$R" worktree add -q --detach "$TMP/kept-dead" && G "$R" worktree lock --reason "devkit-kept session=s1 pid=$DEADPID" "$TMP/kept-dead"
G "$R" worktree add -q --detach "$TMP/kept-live" && G "$R" worktree lock --reason "devkit-kept session=s2 pid=$LIVEPID" "$TMP/kept-live"
locked() { G "$R" worktree list --porcelain | awk -v p="/$(basename "$1")" '$1=="worktree"{c=(substr($2,length($2)-length(p)+1)==p)} c&&$1=="locked"{f=1} END{exit !f}'; }
python3 "$WT" gc --dry-run > "$TMP/gc11d.out" 2>&1
grep -q "kept-dead" "$TMP/gc11d.out" && locked "$TMP/kept-dead" && ! grep -q "kept-live" "$TMP/gc11d.out" \
  && ok "--dry-run names a devkit-kept lock of a dead pid and opens nothing (#327 b)" || fail "dry-run kept-lock report wrong: $(cat "$TMP/gc11d.out")"
python3 "$WT" gc > "$TMP/gc11.out" 2>&1
! locked "$TMP/kept-dead" && grep -q "kept-dead" "$TMP/gc11.out" && ok "gc opens and names a devkit-kept lock of a dead pid (#327 b)" \
  || fail "dead kept lock not opened: $(cat "$TMP/gc11.out")"
locked "$TMP/kept-live" && ok "  … a lock whose pid is alive is not touched (#327 b)" || fail "live kept lock was opened"
kill "$LIVEPID" 2>/dev/null
[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_gc: all passed" || { echo "❌ test_worktree_gc: $FAILS failed"; exit 1; }
