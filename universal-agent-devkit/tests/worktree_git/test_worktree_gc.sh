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
printf 'local.properties\nbuild/\n' > "$R/.gitignore"
echo base > "$R/app.txt" && echo v1 > "$R/lib.txt" && G "$R" add -A && G "$R" commit -qm base
echo v2 > "$R/lib.txt" && G "$R" commit -qam v2          # lib.txt "v1" is now an OLD committed blob
echo "sdk.dir=/same" > "$R/local.properties"             # main's own local config (ignored)
dangle() {   # dangle <name>: a worktree whose admin dir is gone, so its .git pointer dangles (the GeelyEx2 orphans)
  G "$R" worktree add -q --detach "$TMP/$1" && rm -rf "$R/.git/worktrees/$1"
}

# 1 a registered worktree that holds nothing beyond main: removed
G "$R" worktree add -q --detach "$TMP/main-merged"
# 2 a registered worktree with a commit main lacks: kept
G "$R" worktree add -q --detach "$TMP/main-ahead" && echo x > "$TMP/main-ahead/x.txt" && G "$TMP/main-ahead" add x.txt && G "$TMP/main-ahead" commit -qm x
# 3 a dangling orphan: only committed content (an old blob), main's identical local config, a build output, noise, a link: deleted
dangle main-orphan-clean
echo v1 > "$TMP/main-orphan-clean/lib.txt"; cp "$R/local.properties" "$TMP/main-orphan-clean/"
mkdir -p "$TMP/main-orphan-clean/build/out" && echo bin > "$TMP/main-orphan-clean/build/out/app.bin"
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
# 7 not ours: a sibling with another prefix, and a <repo>-* folder without .git holding a person's file
mkdir -p "$TMP/other-thing" && echo keep > "$TMP/other-thing/f.txt"
mkdir -p "$TMP/main-notes" && echo "my notes" > "$TMP/main-notes/todo.txt"
# 8 a full copy with its own .git DIRECTORY (a person's clone or backup): never ours
mkdir -p "$TMP/main-backup" && cp -R "$R/.git" "$TMP/main-backup/.git" && cp "$R/app.txt" "$TMP/main-backup/"
# 9 a memory note written in a dangling orphan and not in main: kept
dangle main-orphan-memory; mkdir -p "$TMP/main-orphan-memory/.agents/local/memory/claude-auto" && echo note > "$TMP/main-orphan-memory/.agents/local/memory/claude-auto/n.md"

exists() { [ -e "$TMP/$1" ]; }
cd "$R" || exit 1
python3 "$WT" gc --dry-run > "$TMP/dry.out" 2>&1; rc=$?
[ "$rc" = 0 ] && ok "gc --dry-run exits 0" || fail "gc --dry-run rc=$rc: $(cat "$TMP/dry.out")"
for d in main-merged main-orphan-clean main-gate-orphan; do exists "$d" || fail "--dry-run deleted $d"; done
grep -q "main-orphan-clean" "$TMP/dry.out" && ok "--dry-run lists what it would delete and deletes nothing" || fail "--dry-run lists nothing: $(cat "$TMP/dry.out")"

python3 "$WT" gc > "$TMP/gc.out" 2>&1; rc=$?
[ "$rc" = 0 ] && ok "gc exits 0" || fail "gc rc=$rc: $(cat "$TMP/gc.out")"
for d in main-merged main-orphan-clean main-gate-orphan; do
  exists "$d" && fail "$d should be deleted: $(cat "$TMP/gc.out")" || ok "deleted: $d"
done
for d in main-ahead main-orphan-unique main-orphan-secret other-thing main-notes main-backup main-orphan-memory; do
  exists "$d" && ok "kept: $d" || fail "$d was deleted (it holds something unique or is not ours)"
done
grep -q "main-orphan-unique.*notes.md" "$TMP/gc.out" && ok "the kept orphan names its unique file" || fail "no reason for main-orphan-unique: $(cat "$TMP/gc.out")"
grep -q "main-orphan-secret.*local.properties" "$TMP/gc.out" && ok "the kept orphan names its secret" || fail "no reason for main-orphan-secret: $(cat "$TMP/gc.out")"
[ -f "$R/local.properties" ] && [ "$(cat "$R/local.properties")" = "sdk.dir=/same" ] && ok "main's own local config is untouched" || fail "main's local.properties changed"
G "$R" worktree list --porcelain | grep -q "main-merged" && fail "main-merged is still registered" || ok "the removed worktree is no longer registered"
[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_gc: all passed" || { echo "❌ test_worktree_gc: $FAILS failed"; exit 1; }
