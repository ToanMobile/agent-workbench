#!/usr/bin/env bash
# Regression (DevKit speed 1d): `agent-kit worktree remove` (scripts/git/worktree.py) on a DETACHED worktree, the default of
# `worktree add` since the one-branch rule. Nothing it holds may be dropped silently, and nothing may be stuck for ever:
#   - commits that are in main neither by content nor as the same patch: refused, the refusal names the sha and the way out
#   - cherry-picked / rebased / squashed into main: allowed, also after main edited the same files (patch-id, merge-tree)
#   - a commit that only the worktree's own HEAD REFLOG still names (checkout --detach HEAD~1, reset): refused, listed
#     (a removal deletes that reflog, the commit is then lost at the next gc); an amend predecessor and a commit whose
#     content is in main do not count; a rebase or bisect in progress holds the removal
#   - two worktrees edited the same file, both brought back: the first one still goes (three-way merge adds nothing to main)
#   - a commit that also touched the checklist bookkeeping files (worktree diff leaves them out): not stuck on them
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

# ── remove: the commits of a DETACHED worktree are never dropped silently ───────────────────────────────────────────
# refused while they are in main neither by content nor as the same patch; allowed once cherry-picked / rebased there
# (also when main has since edited the same files), or when main holds the same bytes (squash); the refusal says how to get out
R="$TMP/rm"; mkdir -p "$R" && G "$R" init -q -b main . && cd "$R" || exit 1
for f in f g h k l m n; do printf '1\n2\n3\n4\n5\n' > "$R/$f.txt"; done
G "$R" add -A && G "$R" commit -qm init
wt() { bash "$KIT" worktree add "../rm-$1" >/dev/null 2>&1 || fail "add rm-$1"; }
wcommit() { G "$TMP/rm-$1" add -A && G "$TMP/rm-$1" commit -qm "$2"; }   # wcommit <name> <message>
rm_wt() { bash "$KIT" worktree remove "../rm-$1" >"$TMP/rm-$1.out" 2>&1; return $?; }
wt a; echo "a-end" >> "$TMP/rm-a/f.txt"; wcommit a "a"; SHA_A="$(G "$TMP/rm-a" rev-parse HEAD)"
rm_wt a; rc=$?
[ "$rc" = 1 ] && [ -d "$TMP/rm-a" ] && grep -q "UNREACHABLE" "$TMP/rm-a.out" && grep -q "${SHA_A:0:12}" "$TMP/rm-a.out" && grep -q "worktree remove --force" "$TMP/rm-a.out" \
  && G "$R" cat-file -e "$SHA_A" && ok "remove: a commit that is not in main is refused; the message names its sha and the user's way out (git worktree remove --force)" \
  || { fail "remove of an unintegrated detached commit (rc=$rc)"; cat "$TMP/rm-a.out"; }

wt b; echo "b-end" >> "$TMP/rm-b/g.txt"; wcommit b "b"; G "$R" cherry-pick "$(G "$TMP/rm-b" rev-parse HEAD)" >/dev/null 2>&1
rm_wt b; rc=$?; [ "$rc" = 0 ] && [ ! -d "$TMP/rm-b" ] && ok "remove: cherry-picked into main (same bytes) -> allowed" || fail "cherry-picked, same bytes (rc=$rc): $(cat "$TMP/rm-b.out")"

wt c; echo "c-end" >> "$TMP/rm-c/h.txt"; wcommit c "c"
printf 'main-top\n' | cat - "$R/h.txt" > "$TMP/h.new" && cp "$TMP/h.new" "$R/h.txt" && G "$R" commit -qam "main edits h.txt" && G "$R" cherry-pick "$(G "$TMP/rm-c" rev-parse HEAD)" >/dev/null 2>&1
rm_wt c; rc=$?; [ "$rc" = 0 ] && [ ! -d "$TMP/rm-c" ] && ok "remove: cherry-picked into main after main edited the same file (other bytes, same patch) -> allowed" || fail "cherry-picked with drift (rc=$rc): $(cat "$TMP/rm-c.out")"

wt d; echo "d1" >> "$TMP/rm-d/k.txt"; wcommit d "d1"; echo "d2" >> "$TMP/rm-d/l.txt"; wcommit d "d2"
D1="$(G "$TMP/rm-d" rev-parse HEAD~1)"; D2="$(G "$TMP/rm-d" rev-parse HEAD)"
printf 'main-top\n' | cat - "$R/k.txt" > "$TMP/k.new" && cp "$TMP/k.new" "$R/k.txt" && G "$R" commit -qam "main edits k.txt" && G "$R" cherry-pick "$D1" "$D2" >/dev/null 2>&1
rm_wt d; rc=$?; [ "$rc" = 0 ] && [ ! -d "$TMP/rm-d" ] && ok "remove: two commits rebased (cherry-picked) onto a drifted main -> allowed" || fail "rebased with drift (rc=$rc): $(cat "$TMP/rm-d.out")"

wt e; echo "e1" >> "$TMP/rm-e/m.txt"; wcommit e "e1"; echo "e2" >> "$TMP/rm-e/m.txt"; wcommit e "e2"
cp "$TMP/rm-e/m.txt" "$R/m.txt" && G "$R" commit -qam "squash of e1+e2"
rm_wt e; rc=$?; [ "$rc" = 0 ] && [ ! -d "$TMP/rm-e" ] && ok "remove: squashed into main (same bytes) -> allowed" || fail "squash, same bytes (rc=$rc): $(cat "$TMP/rm-e.out")"

wt f; echo "f1" >> "$TMP/rm-f/n.txt"; wcommit f "f1"; echo "f2" >> "$TMP/rm-f/n.txt"; wcommit f "f2"; SHA_F="$(G "$TMP/rm-f" rev-parse HEAD)"
printf 'main-top\n' | cat - "$R/n.txt" > "$TMP/n.new" && cp "$TMP/n.new" "$R/n.txt" && G "$R" commit -qam "main edits n.txt"
printf 'f1\nf2\n' >> "$R/n.txt" && G "$R" commit -qam "squash of f1+f2, with main's own edit around it"
rm_wt f; rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/rm-f" ] && ok "remove: a squash merged with main's own edits around it (other bytes, other patch ids) -> allowed (a three-way merge adds nothing to main)" \
  || { fail "squash with drift (rc=$rc)"; cat "$TMP/rm-f.out"; }

# ── a commit only the worktree's reflog names (the reviewer's repro): commit, `checkout --detach HEAD~1`, remove ───────
wt g; echo "g1" >> "$TMP/rm-g/f.txt"; wcommit g "g1"; SHA_G="$(G "$TMP/rm-g" rev-parse HEAD)"
G "$TMP/rm-g" checkout -q --detach HEAD~1
rm_wt g; rc=$?
[ "$rc" = 1 ] && [ -d "$TMP/rm-g" ] && grep -q "${SHA_G:0:12}" "$TMP/rm-g.out" && grep -qi "reflog" "$TMP/rm-g.out" && grep -q "rescue/" "$TMP/rm-g.out" \
  && ok "remove: a commit only the worktree reflog still names is refused, listed, with the rescue branch command" \
  || { fail "reflog-only commit (rc=$rc)"; cat "$TMP/rm-g.out"; }
G "$R" branch rescue/g "$SHA_G"
rm_wt g; rc=$?; [ "$rc" = 0 ] && [ ! -d "$TMP/rm-g" ] && G "$R" cat-file -e "$SHA_G" && ok "remove: once a branch holds the commit (rescue), the worktree can go" || fail "after rescue (rc=$rc): $(cat "$TMP/rm-g.out")"

wt h; echo "h1" >> "$TMP/rm-h/g.txt"; wcommit h "h1"; echo "h-typo" >> "$TMP/rm-h/g.txt"; G "$TMP/rm-h" add -A; G "$TMP/rm-h" commit -q --amend -m "h1 amended"
cp "$TMP/rm-h/g.txt" "$R/g.txt" && G "$R" commit -qam "h brought back"
rm_wt h; rc=$?; [ "$rc" = 0 ] && [ ! -d "$TMP/rm-h" ] && ok "remove: an amended commit's predecessor does not hold the removal once the final work is in main" || fail "amend predecessor (rc=$rc): $(cat "$TMP/rm-h.out")"

wt i; echo "i1" >> "$TMP/rm-i/k.txt"; wcommit i "i1"
printf 'main-top2\n' | cat - "$R/k.txt" > "$TMP/k2.new" && cp "$TMP/k2.new" "$R/k.txt" && G "$R" commit -qam "main edits k.txt again"   # other bytes in main
G "$R" cherry-pick "$(G "$TMP/rm-i" rev-parse HEAD)" >/dev/null 2>&1
G "$TMP/rm-i" checkout -q --detach HEAD~1
rm_wt i; rc=$?; [ "$rc" = 0 ] && ok "remove: a reflog-only commit whose change is in main (cherry-picked) does not hold it" || fail "reflog commit in main (rc=$rc): $(cat "$TMP/rm-i.out")"

wt j; G "$TMP/rm-j" bisect start >/dev/null 2>&1
rm_wt j; rc=$?; [ "$rc" = 1 ] && [ -d "$TMP/rm-j" ] && grep -qi "bisect" "$TMP/rm-j.out" && ok "remove: a bisect in progress holds the removal" || fail "bisect in progress (rc=$rc): $(cat "$TMP/rm-j.out")"
G "$TMP/rm-j" bisect reset >/dev/null 2>&1

# ── two worktrees edited the same file (different lines), both brought back: neither stays stuck ───────────────────
printf 'top\n1\n2\n3\n4\n5\nbottom\n' > "$R/s.txt" && G "$R" add -A && G "$R" commit -qm "s.txt"
wt p1; wt p2
sed -i.bak 's/^2$/2-A/' "$TMP/rm-p1/s.txt" && rm -f "$TMP/rm-p1/s.txt.bak"; wcommit p1 "A edits line 2"
sed -i.bak 's/^4$/4-B/' "$TMP/rm-p2/s.txt" && rm -f "$TMP/rm-p2/s.txt.bak"; wcommit p2 "B edits line 4"
for n in p1 p2; do
  bash "$KIT" worktree diff "../rm-$n" 2>/dev/null | git apply --3way >/dev/null 2>&1 && G "$R" add -A && G "$R" commit -qm "bring back $n" || fail "bring back $n"
done
rm_wt p1; rc=$?; [ "$rc" = 0 ] && [ ! -d "$TMP/rm-p1" ] && ok "remove: A and B edited the same file, both in main: A's commit adds nothing to main -> allowed" || fail "overlapping edits, A (rc=$rc): $(cat "$TMP/rm-p1.out")"
rm_wt p2; rc=$?; [ "$rc" = 0 ] && ok "remove: ... and B too" || fail "overlapping edits, B (rc=$rc): $(cat "$TMP/rm-p2.out")"

# ── a commit that also touched the checklist bookkeeping (diff leaves it out) is not stuck on it ───────────────────
mkdir -p "$R/.agents" && echo "# checklist" > "$R/.agents/CHECKLIST.md" && G "$R" add -A && G "$R" commit -qm "checklist"
wt C; echo "C-work" >> "$TMP/rm-C/h.txt"; echo "<!-- hook -->" >> "$TMP/rm-C/.agents/CHECKLIST.md"; wcommit C "work + bookkeeping"
bash "$KIT" worktree diff ../rm-C 2>/dev/null | git apply --3way >/dev/null 2>&1 && G "$R" add -A && G "$R" commit -qm "bring back C"
rm_wt C; rc=$?; [ "$rc" = 0 ] && [ ! -d "$TMP/rm-C" ] && ok "remove: the commit's checklist bookkeeping change (left out by diff) does not keep the worktree for ever" || fail "bookkeeping in the commit (rc=$rc): $(cat "$TMP/rm-C.out")"

# ── a committed bug row (agent-kit bugs add) is WORK: the checklist file is bookkeeping, its authored rows are not ──────
( CLAUDE_PROJECT_DIR="$R" bash "$KIT" bugs add "seed row" --fixed >/dev/null 2>&1 ); G "$R" add -A && G "$R" commit -qm "checklist with a seed row"
wt q; ( cd "$TMP/rm-q" && CLAUDE_PROJECT_DIR="$TMP/rm-q" bash "$KIT" bugs add "bug found in the worktree" --fixed >/dev/null 2>&1 ); wcommit q "bug row"
SHA_Q="$(G "$TMP/rm-q" rev-parse HEAD)"
rm_wt q; rc=$?
[ "$rc" = 1 ] && [ -d "$TMP/rm-q" ] && G "$R" cat-file -e "$SHA_Q" && ok "remove: a commit whose only change is a new bug row is refused (the row exists nowhere else)" \
  || { fail "committed bug row dropped (rc=$rc)"; cat "$TMP/rm-q.out"; }
bash "$KIT" worktree diff ../rm-q 2>/dev/null | git apply --3way >/dev/null 2>&1 && G "$R" add -A && G "$R" commit -qm "bug row, brought back"
grep -q "bug found in the worktree" "$R/.agents/regression_status.json" || fail "the bug row did not reach main"
rm_wt q; rc=$?; [ "$rc" = 0 ] && [ ! -d "$TMP/rm-q" ] && ok "remove: ... allowed once the row is in main (diff | git apply, committed)" || fail "after bringing the bug row back (rc=$rc): $(cat "$TMP/rm-q.out")"

# ── the refusal names the rescue branch and the bookkeeping flag ────────────────────────────────────────────────────
grep -q "rescue/<name>" "$TMP/rm-a.out" && grep -q "with-checklist" "$TMP/rm-a.out" \
  && ok "remove: the refusal for commits not in main names the rescue branch command and diff --with-checklist" || fail "refusal wording: $(cat "$TMP/rm-a.out")"

# ── the checks that can only CLEAR a worktree have a time budget (a hook that runs out of time must not read "all clear") ──
wt u; echo "u1" >> "$TMP/rm-u/l.txt"; wcommit u "u1"
printf 'main-top3\n' | cat - "$R/l.txt" > "$TMP/l.new" && cp "$TMP/l.new" "$R/l.txt" && G "$R" commit -qam "main edits l.txt" && G "$R" cherry-pick "$(G "$TMP/rm-u" rev-parse HEAD)" >/dev/null 2>&1
ahead="$(cd "$R" && python3 - "$DEVKIT_DIR/scripts/git" "$TMP/rm-u" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import worktree as w
import os
row = lambda **kw: [r for r in w.inventory(os.getcwd(), **kw) if r["path"].endswith("rm-u")][0]["ahead"]
print(row(), row(budget=0.0))
PY
)"
[ "$ahead" = "0 1" ] && ok "inventory: with the default budget a cherry-picked commit clears (ahead 0); with no time left it stays unintegrated (ahead 1)" || fail "inventory budget: '$ahead' (expected '0 1')"
rm_wt u >/dev/null

# ── a PARENT commit with the same patch in main must not vouch for the valuable commit on top of it ───────────────────
wt v; echo "p" > "$TMP/rm-v/p.txt"; wcommit v "P (also cherry-picked into main)"; PV="$(G "$TMP/rm-v" rev-parse HEAD)"
echo "valuable" > "$TMP/rm-v/t.txt"; wcommit v "T (the valuable one)"; TV="$(G "$TMP/rm-v" rev-parse HEAD)"
echo "main goes on" > "$R/main-only.txt" && G "$R" add -A && G "$R" commit -qm "main goes on" && G "$R" cherry-pick "$PV" >/dev/null 2>&1
G "$TMP/rm-v" checkout -q --detach HEAD~2
rm_wt v; rc=$?
[ "$rc" = 1 ] && [ -d "$TMP/rm-v" ] && grep -q "${TV:0:7}" "$TMP/rm-v.out" && G "$R" cat-file -e "$TV" \
  && ok "remove: a reflog-only commit whose PARENT has the same patch in main is still refused (only its own patch id counts)" || { fail "parent patch vouched for the tip (rc=$rc)"; cat "$TMP/rm-v.out"; }

# ── an EMPTY commit (only a message) is not 'the same patch' as any other empty commit in main ─────────────────────
wt w; G "$TMP/rm-w" commit -q --allow-empty -m "valuable note"; G "$TMP/rm-w" checkout -q --detach HEAD~1
G "$R" commit -q --allow-empty -m "an empty commit of main"
rm_wt w; rc=$?
[ "$rc" = 1 ] && [ -d "$TMP/rm-w" ] && ok "remove: a reflog-only EMPTY commit (a message) is refused although main has some empty commit" || { fail "empty reflog commit (rc=$rc)"; cat "$TMP/rm-w.out"; }
wt x; G "$TMP/rm-x" commit -q --allow-empty -m "head note"
rm_wt x; rc=$?
[ "$rc" = 1 ] && [ -d "$TMP/rm-x" ] && ok "remove: an EMPTY commit at the worktree's HEAD is refused although main has some empty commit" || { fail "empty head commit (rc=$rc)"; cat "$TMP/rm-x.out"; }

# ── a commit made inside a SUBMODULE of the worktree lives in the worktree's git dir: not silently deleted ────────────
L="$TMP/lib"; mkdir -p "$L" && G "$L" init -q -b main . && echo 1 > "$L/f" && G "$L" add -A && G "$L" commit -qm lib
G "$R" -c protocol.file.allow=always submodule add -q "$L" lib >/dev/null 2>&1 && G "$R" commit -qm "add the submodule"
wt s; G "$TMP/rm-s" -c protocol.file.allow=always submodule update -q --init >/dev/null 2>&1
echo "sub work" > "$TMP/rm-s/lib/f" && G "$TMP/rm-s/lib" commit -qam "sub work"; SUBSHA="$(G "$TMP/rm-s/lib" rev-parse --short=12 HEAD)"
rm_wt s; rc=$?
[ "$rc" = 1 ] && [ -d "$TMP/rm-s" ] && grep -qi "submodule" "$TMP/rm-s.out" && grep -q "$SUBSHA" "$TMP/rm-s.out" \
  && ok "remove: a commit made inside the worktree's submodule (on no remote ref) is refused, named" || { fail "submodule commit (rc=$rc)"; cat "$TMP/rm-s.out"; }
G "$TMP/rm-s/lib" push -q origin HEAD:refs/heads/sub-work >/dev/null 2>&1
# W1-f r6: a ref in the worktree's OWN module (what a push updates) is also what an agent can write by hand; the commit counts once the
# MAIN checkout's own copy of the submodule holds it on a remote-tracking ref (tests/worktree_git/test_worktree_remove_safety.sh)
rm_wt s; rc=$?; [ "$rc" = 1 ] && [ -d "$TMP/rm-s" ] && grep -q "fetch" "$TMP/rm-s.out" && ok "remove: pushed from the worktree but not yet fetched by the main checkout's copy -> still refused, says to fetch there" || fail "submodule pushed, not fetched (rc=$rc): $(cat "$TMP/rm-s.out")"
G "$R/lib" fetch -q origin >/dev/null 2>&1
rm_wt s; rc=$?; [ "$rc" = 1 ] && [ -d "$TMP/rm-s" ] && grep -q "not in the main checkout" "$TMP/rm-s.out" && ok "remove: ... and the worktree's moved submodule pointer (uncommitted in the superproject) is a change main does not hold yet" || fail "moved submodule pointer (rc=$rc): $(cat "$TMP/rm-s.out")"
G "$R/lib" checkout -q "$(G "$TMP/rm-s/lib" rev-parse HEAD)" && G "$R" add lib && G "$R" commit -qm "bring back the submodule pointer"
rm_wt s; rc=$?; [ "$rc" = 0 ] && [ ! -d "$TMP/rm-s" ] && ok "remove: once the submodule commit is on a remote ref of the main checkout's copy (pushed, then fetched there) and main records it, the worktree can go" || fail "submodule pushed, fetched, pointer committed (rc=$rc): $(cat "$TMP/rm-s.out")"

# ── ONE rule: worktree.removal_blockers() (scripts/git/worktree.py) is what `remove` obeys, and what `worktree land` calls ─────────
# per reason: the function lists it, and `remove` refuses with that very text (same exit code as ever); a clean worktree: [] and removable
blockers_first() {   # blockers_first <worktree name>: the number of reasons and the first line of the first one
  python3 - "$DEVKIT_DIR/scripts/git" "$R" "$TMP/rm-$1" "../rm-$1" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import worktree as w
import os
b = w.removal_blockers(os.path.realpath(sys.argv[2]), os.path.realpath(sys.argv[3]), shown=sys.argv[4])   # the path as `remove` sees it (cwd is a real path)
print(len(b), (b[0].splitlines() or [""])[0] if b else "")
PY
}
same_rule() {   # same_rule <name> <expected remove rc> <label>
  local out n first rc
  out="$(blockers_first "$1")"; n="${out%% *}"; first="${out#* }"
  bash "$KIT" worktree remove "../rm-$1" >"$TMP/rm-$1.tbl" 2>&1; rc=$?
  [ "$rc" = "$2" ] && [ "$n" -ge 1 ] && grep -qF "$first" "$TMP/rm-$1.tbl" \
    && ok "removal_blockers: $3 -> listed ($n), and remove refuses with the same text (exit $rc)" || { fail "removal_blockers vs remove: $3 (rc=$rc, n=$n, first='$first')"; cat "$TMP/rm-$1.tbl"; }
}
wt t1; G "$TMP/rm-t1" bisect start >/dev/null 2>&1; same_rule t1 1 "a bisect in progress"; G "$TMP/rm-t1" bisect reset >/dev/null 2>&1
wt t2; echo "t2" > "$TMP/rm-t2/t2.txt"; wcommit t2 "t2 not in main"; same_rule t2 1 "a commit that is not in main"
wt t3; echo "t3" > "$TMP/rm-t3/t3.txt"; wcommit t3 "t3"; G "$TMP/rm-t3" checkout -q --detach HEAD~1; same_rule t3 1 "a commit only the reflog names"
wt t4; G "$TMP/rm-t4" commit -q --allow-empty -m "t4 note"; same_rule t4 1 "an empty commit (a message)"
wt t5; echo "t5" > "$TMP/rm-t5/uncommitted.txt"; same_rule t5 1 "an uncommitted file main does not hold"
G "$R" -c protocol.file.allow=always submodule update -q --init >/dev/null 2>&1
wt t6; G "$TMP/rm-t6" -c protocol.file.allow=always submodule update -q --init >/dev/null 2>&1
echo "t6" > "$TMP/rm-t6/lib/f" && G "$TMP/rm-t6/lib" commit -qam "t6 sub work"; same_rule t6 1 "a submodule commit on no remote ref"
wt t7; ( cd "$TMP/rm-t7" && CLAUDE_PROJECT_DIR="$TMP/rm-t7" bash "$KIT" bugs add "t7 bug" --fixed >/dev/null 2>&1 ); wcommit t7 "t7 bug row"; same_rule t7 1 "a committed bug row"
G "$R" worktree add -q --detach "$TMP/rm-t8" >/dev/null 2>&1; same_rule t8 2 "a worktree not made by agent-kit worktree add"
wt t9; out9="$(blockers_first t9)"
[ "$out9" = "0 " ] && bash "$KIT" worktree remove ../rm-t9 >/dev/null 2>&1 && [ ! -d "$TMP/rm-t9" ] \
  && ok "removal_blockers: a clean worktree -> [] and remove removes it" || fail "clean worktree: '$out9'"

excs="$(python3 - "$DEVKIT_DIR/scripts/git" "$R" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import worktree as w
def boom(*a, **k): raise RuntimeError("git exploded")
w.inventory = boom
b = w.removal_blockers(sys.argv[2], sys.argv[2] + "-nowhere")
print(len(b), "cannot check" in (b[0] if b else ""))
PY
)"
[ "$excs" = "1 True" ] && ok "removal_blockers: a check that raises reads as a blocker (never as 'safe to remove')" || fail "exception in a check: '$excs'"

if [ "$FAILS" -ne 0 ]; then echo "worktree remove: $FAILS FAILED"; exit 1; fi
echo "worktree remove: all checks passed"
