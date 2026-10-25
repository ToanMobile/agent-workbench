#!/usr/bin/env bash
# hooks/worktree_merge_gate.sh, a worktree that is removed while the Stop is deciding about it (2026-10-09, macOS; the flake of
# tests/gates/test_worktree_merge_gate_owner.sh section 7: "second Stop held" in 2 of 3 full-gate runs and 1 of 4 runs under load).
# A background merge of the previous Stop (worktree.py automerge) merges the worktree and then deletes its folder. A Stop that took
# its inventory in between saw "merged, still there — remove it", and by the time it chose what to merge the folder was gone, so
# the row matched nothing: it stayed in the list and HELD the Stop on a worktree that no longer existed ("đã gộp xong — XOÁ:
# agent-kit worktree remove <path>" for a path that is not there). A worktree that is gone is what the gate wants: it passes.
# The race is made deterministic with a `git` shim on PATH that deletes the worktree folder right after the inventory's
# `git -C <worktree> … status`.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/worktree_merge_gate.sh"; LOCKPY="$DEVKIT_DIR/bin/session_lock.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
REAL_GIT="$(command -v git)"; export REAL_GIT

P="$TMP/proj"; mkdir -p "$P" && G "$P" init -q -b main . && printf '1\n' > "$P/a.txt" && G "$P" add a.txt && G "$P" commit -qm init
TRA="$TMP/tra.jsonl"
python3 -c 'import json,datetime;print(json.dumps({"type":"user","timestamp":datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z"),"message":{"content":"go"}}))' > "$TRA"
sleep 1.2
mention() { python3 -c 'import json,sys;print(json.dumps({"type":"assistant","message":{"content":[{"type":"tool_use","id":"t","name":"Bash","input":{"command":sys.argv[1]}}]}}))' "git worktree add -b $1 $2" >> "$TRA"; }
# Under load (#419: 35-70 parallel gates) the hook's 9 s merge budget runs out and the merge goes to the background ("đang tự gộp ở nền"),
# whose result is for the NEXT Stop. The case waits for that result: it asks again (at most 12 times, ~1 s apart) while the note is there.
# No assertion is loosened: the final Stop's rc/output is what each case checks, and a worktree really not in main is still held.
stop() {
  local n=0
  while :; do
    printf '{"session_id":"%s","hook_event_name":"Stop","transcript_path":"%s"}' "$1" "$2" | CLAUDE_PROJECT_DIR="$P" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"
    local rc=$?
    grep -q "ở nền" "$TMP/out" "$TMP/err" 2>/dev/null && [ "$n" -lt 12 ] || return $rc
    n=$((n + 1)); sleep 1
  done
}
live() { python3 -I "$LOCKPY" --register --session "$1" --pid "$$" "$P"; }

# The worktree is already merged into main (clean, nothing ahead): the Stop would remove it
WT="$TMP/wt-feat1"
mention feat1 "$WT"; G "$P" worktree add -q -b feat1 "$WT" && echo n > "$WT/n.txt" && G "$WT" add n.txt && G "$WT" commit -qm feat1 && G "$P" merge -q --ff-only feat1
live A
mkdir -p "$TMP/shim"
cat > "$TMP/shim/git" <<'SH'
#!/bin/sh
# git, then (once) delete the worktree folder when the call was `git -C <that folder> … status …`
"$REAL_GIT" "$@"; rc=$?
if [ "$1" = "-C" ] && [ "$2" = "$VANISH_DIR" ] && [ ! -e "$VANISH_MARK" ]; then
  for a in "$@"; do
    if [ "$a" = status ]; then : > "$VANISH_MARK"; rm -rf "$VANISH_DIR"; break; fi
  done
fi
exit $rc
SH
chmod +x "$TMP/shim/git"
VANISH_DIR="$(cd "$WT" && pwd -P)"; VANISH_MARK="$TMP/vanished"; export VANISH_DIR VANISH_MARK

PATH="$TMP/shim:$PATH" stop A "$TRA"; rc=$?
[ -e "$VANISH_MARK" ] && ok "setup: the folder vanished right after the inventory's git status" || fail "setup: the shim never saw the status call (the inventory changed?)"
[ ! -d "$WT" ] || fail "setup: the worktree folder is still there"
[ "$rc" = 0 ] && ok "a worktree removed while the Stop decides does not hold it" || fail "held (rc=$rc) over a worktree that is gone: $(cat "$TMP/err")"
grep -q "wt-feat1" "$TMP/err" && fail "the hold text names the vanished worktree: $(cat "$TMP/err")" || ok "  … and nothing names the vanished worktree"

# control: a worktree that is still there and has work main lacks is still held/merged as before
sleep 1.2
WT2="$TMP/wt-feat2"; mention feat2 "$WT2"; G "$P" worktree add -q -b feat2 "$WT2" && echo m > "$WT2/m.txt" && G "$WT2" add m.txt && G "$WT2" commit -qm feat2
stop A "$TRA"; rc=$?
[ "$rc" = 0 ] && [ ! -d "$WT2" ] && [ -f "$P/m.txt" ] && ok "control: a worktree with work main lacks is still merged and removed by the Stop" || fail "control: (rc=$rc): $(cat "$TMP/err") $(cat "$TMP/out")"

# Two merges of ONE worktree overlap (2026-10-13, red in 3 of the last 10 full gates: test_worktree_merge_gate_owner.sh section 7,
# "second Stop held … wt-feat4 [feat4]: ✖ worktree: git rev-parse --absolute-git-dir: fatal: cannot change to …"). The background
# merge of the previous Stop brings the worktree into main and removes it (folder AND registration) just after this Stop's own
# `worktree.py automerge` of the same worktree started: that run dies on the missing folder, its failure became a hold, and the Stop
# was held on work that is already in main. The shim plays the other merge at this run's first `git -C <worktree> symbolic-ref`
# (automerge only; the inventory never calls it): fast-forward main to the branch, delete the folder, prune the registration.
sleep 1.2
WT3="$TMP/wt-feat3"; mention feat3 "$WT3"; G "$P" worktree add -q -b feat3 "$WT3" && echo o > "$WT3/o.txt" && G "$WT3" add o.txt && G "$WT3" commit -qm feat3
WT4="$TMP/wt-feat4"; mention feat4 "$WT4"; G "$P" worktree add -q -b feat4 "$WT4" && echo q > "$WT4/q.txt" && G "$WT4" add q.txt && G "$WT4" commit -qm feat4
cat > "$TMP/shim/git" <<'SH'
#!/bin/sh
# once, at automerge's first `git -C <that worktree> symbolic-ref`: the other merge lands the branch and removes the worktree first
if [ "$1" = "-C" ] && [ "$2" = "$VANISH_DIR" ] && [ "$3" = symbolic-ref ] && [ ! -e "$VANISH_MARK.tried" ]; then
  : > "$VANISH_MARK.tried"
  # the mark proves the OTHER merge really landed it (review 13/10: a mark set first let the case pass on this Stop's own merge)
  "$REAL_GIT" -C "$VANISH_MAIN" merge -q --ff-only "$VANISH_BRANCH" && rm -rf "$VANISH_DIR" && "$REAL_GIT" -C "$VANISH_MAIN" worktree prune \
    && : > "$VANISH_MARK"
fi
exec "$REAL_GIT" "$@"
SH
chmod +x "$TMP/shim/git"
VANISH_DIR="$(cd "$WT3" && pwd -P)"; VANISH_MARK="$TMP/vanished2"; VANISH_MAIN="$P"; VANISH_BRANCH=feat3
export VANISH_DIR VANISH_MARK VANISH_MAIN VANISH_BRANCH
PATH="$TMP/shim:$PATH" stop A "$TRA"; rc=$?
[ -e "$VANISH_MARK" ] && [ ! -d "$WT3" ] && [ -f "$P/o.txt" ] && ok "setup: the other merge landed feat3 and removed its worktree while this Stop's merge ran" \
  || fail "setup: the shim never fired or the other merge failed (mark=$([ -e "$VANISH_MARK" ] && echo y || echo n))"
[ "$rc" = 0 ] && ok "a worktree another merge just landed and removed does not hold the Stop" || fail "held (rc=$rc) over work already in main: $(cat "$TMP/err")"
grep -q "wt-feat3" "$TMP/err" && fail "  … the hold text names the removed worktree: $(cat "$TMP/err")" || ok "  … and nothing names the removed worktree"
[ ! -d "$WT4" ] && [ -f "$P/q.txt" ] && ok "  … the other worktree with work main lacks was merged and removed as usual" || fail "  … the other worktree was not brought back: $(cat "$TMP/err") $(cat "$TMP/out")"

# Never pass on LOST work (plan_review T0035 r1, blocker): the folder and its registration disappear the same way, but nothing landed
# the branch in main (an rm -rf + prune from outside). A gone worktree is "done" only when its HEAD is in main: here it must still hold.
sleep 1.2
WT5="$TMP/wt-feat5"; mention feat5 "$WT5"; G "$P" worktree add -q -b feat5 "$WT5" && echo r > "$WT5/r.txt" && G "$WT5" add r.txt && G "$WT5" commit -qm feat5
cat > "$TMP/shim/git" <<'SH'
#!/bin/sh
# once, at automerge's first `git -C <that worktree> symbolic-ref`: the folder and its registration go WITHOUT landing the branch
if [ "$1" = "-C" ] && [ "$2" = "$VANISH_DIR" ] && [ "$3" = symbolic-ref ] && [ ! -e "$VANISH_MARK" ]; then
  : > "$VANISH_MARK"
  rm -rf "$VANISH_DIR" && "$REAL_GIT" -C "$VANISH_MAIN" worktree prune
fi
exec "$REAL_GIT" "$@"
SH
chmod +x "$TMP/shim/git"
VANISH_DIR="$(cd "$WT5" && pwd -P)"; VANISH_MARK="$TMP/vanished3"; export VANISH_DIR VANISH_MARK
PATH="$TMP/shim:$PATH" stop A "$TRA"; rc=$?
[ -e "$VANISH_MARK" ] && [ ! -d "$WT5" ] && [ ! -f "$P/r.txt" ] && ok "setup: feat5's folder and registration went, its commit never reached main" \
  || fail "setup: the shim never fired or main got r.txt (mark=$([ -e "$VANISH_MARK" ] && echo y || echo n))"
[ "$rc" = 2 ] && ok "a gone worktree whose HEAD is NOT in main still holds the Stop (no silent loss)" || fail "passed (rc=$rc) although feat5's work never reached main"
grep -q "wt-feat5" "$TMP/err" && ok "  … and the hold names it" || fail "  … the hold does not name feat5: $(cat "$TMP/err")"

# The vanished filter itself (plan_review T0035 r2, blocker): case 1 drops a row whose folder is gone after the inventory. That is right
# for an integrated worktree, but a worktree whose commit is NOT in main and whose folder disappears (rm -rf from outside) was dropped
# the same way: the Stop passed and the work was never asked for again. A gone row passes only when its branch tip is in main.
sleep 1.2
WT6="$TMP/wt-feat6"; mention feat6 "$WT6"; G "$P" worktree add -q -b feat6 "$WT6" && echo s > "$WT6/s.txt" && G "$WT6" add s.txt && G "$WT6" commit -qm feat6
cat > "$TMP/shim/git" <<'SH'
#!/bin/sh
# git, then (once) delete the worktree folder when the call was `git -C <that folder> … status …` (the inventory has just read it)
"$REAL_GIT" "$@"; rc=$?
if [ "$1" = "-C" ] && [ "$2" = "$VANISH_DIR" ] && [ ! -e "$VANISH_MARK" ]; then
  for a in "$@"; do
    if [ "$a" = status ]; then : > "$VANISH_MARK"; rm -rf "$VANISH_DIR"; break; fi
  done
fi
exit $rc
SH
chmod +x "$TMP/shim/git"
VANISH_DIR="$(cd "$WT6" && pwd -P)"; VANISH_MARK="$TMP/vanished4"; export VANISH_DIR VANISH_MARK
PATH="$TMP/shim:$PATH" stop A "$TRA"; rc=$?
[ -e "$VANISH_MARK" ] && [ ! -d "$WT6" ] && [ ! -f "$P/s.txt" ] && ok "setup: feat6's folder went right after the inventory read it; its commit is not in main" \
  || fail "setup: the shim never fired or main got s.txt (mark=$([ -e "$VANISH_MARK" ] && echo y || echo n))"
[ "$rc" = 2 ] && ok "a vanished worktree whose branch is NOT in main still holds the Stop" || fail "passed (rc=$rc) although feat6's work never reached main"
grep -q "feat6" "$TMP/err" && ok "  … and the hold names it" || fail "  … the hold does not name feat6: $(cat "$TMP/err")"

# Fresh-context review 13/10 (two silent passes of the first fix). One shim for the rest: at automerge's first
# `git -C <worktree> symbolic-ref`, run $VANISH_PRE in the worktree (if set), then delete the folder and prune the registration.
cat > "$TMP/shim/git" <<'SH'
#!/bin/sh
if [ "$1" = "-C" ] && [ "$2" = "$VANISH_DIR" ] && [ "$3" = symbolic-ref ] && [ ! -e "$VANISH_MARK" ]; then
  : > "$VANISH_MARK"
  [ -n "${VANISH_PRE:-}" ] && (cd "$VANISH_DIR" && sh -c "$VANISH_PRE")
  rm -rf "$VANISH_DIR" && "$REAL_GIT" -C "$VANISH_MAIN" worktree prune
fi
exec "$REAL_GIT" "$@"
SH
chmod +x "$TMP/shim/git"

# 5: a commit only a reflog still names. A detached worktree made commit X, then went back to main's commit: HEAD is in main,
# X is in the worktree's HEAD reflog only. Removed from outside while its merge runs: X must not pass in silence.
sleep 1.2
WT7="$TMP/wt-reflog"; mention reflog "$WT7"; G "$P" worktree add -q --detach "$WT7" && echo x > "$WT7/x.txt" && G "$WT7" add x.txt \
  && G "$WT7" commit -qm only-in-reflog && G "$WT7" checkout -q --detach HEAD~1
VANISH_DIR="$(cd "$WT7" && pwd -P)"; VANISH_MARK="$TMP/vanished5"; VANISH_PRE=""; export VANISH_DIR VANISH_MARK VANISH_PRE
PATH="$TMP/shim:$PATH" stop A "$TRA"; rc=$?
[ -e "$VANISH_MARK" ] && [ ! -d "$WT7" ] && ok "setup: the reflog-only worktree went while its merge ran" || fail "setup: the shim never fired for the reflog-only worktree"
[ "$rc" = 2 ] && ok "5: a commit only its reflog named still holds the Stop" || fail "5: passed (rc=$rc) although commit X was only in the worktree's reflog"

# 6: the branch was rewound before the folder went (reset --hard to main): commit B is not in main, the tip now is. Must hold.
sleep 1.2
WT8="$TMP/wt-feat8"; mention feat8 "$WT8"; G "$P" worktree add -q -b feat8 "$WT8" && echo b > "$WT8/b.txt" && G "$WT8" add b.txt && G "$WT8" commit -qm feat8
VANISH_DIR="$(cd "$WT8" && pwd -P)"; VANISH_MARK="$TMP/vanished6"; VANISH_PRE="git reset -q --hard $(G "$P" rev-parse HEAD)"; export VANISH_DIR VANISH_MARK VANISH_PRE
PATH="$TMP/shim:$PATH" stop A "$TRA"; rc=$?
[ -e "$VANISH_MARK" ] && [ ! -d "$WT8" ] && [ ! -f "$P/b.txt" ] && ok "setup: feat8 was rewound to main, then removed" || fail "setup: the rewind case did not set up"
[ "$rc" = 2 ] && ok "6: a rewound branch whose commit B never reached main still holds the Stop" || fail "6: passed (rc=$rc) although B never reached main"

# 7 (kills a mutant that drops gone() from landed()): the merge is REFUSED while the folder is still there and its base is in main
# (only uncommitted work; the pre-commit hook rejects the commit). The worktree exists and holds work: the Stop must hold.
sleep 1.2
WT9="$TMP/wt-feat9"; mention feat9 "$WT9"; G "$P" worktree add -q -b feat9 "$WT9" && echo u > "$WT9/u.txt"
mkdir -p "$P/.git/hooks" && printf '#!/bin/sh\nexit 1\n' > "$P/.git/hooks/pre-commit" && chmod +x "$P/.git/hooks/pre-commit"
stop A "$TRA"; rc=$?
rm -f "$P/.git/hooks/pre-commit"
[ -d "$WT9" ] && [ "$rc" = 2 ] && ok "7: a refused merge of a worktree that is still there holds the Stop" || fail "7: (rc=$rc, exists=$([ -d "$WT9" ] && echo y || echo n)): $(cat "$TMP/err")"
rm -rf "$WT9"; G "$P" worktree prune; G "$P" branch -q -D feat9 2>/dev/null

# 8 (Antigravity T0035 round 4, blocker): the folder is deleted BEFORE the Stop runs (rm -rf from outside, no prune). The hook's live
# set kept only folders that exist, so the worktree was skipped, dropped from the debt and the Stop passed with its commit not in main.
sleep 1.2
WT10="$TMP/wt-feat10"; mention feat10 "$WT10"; G "$P" worktree add -q -b feat10 "$WT10" && echo t > "$WT10/t.txt" && G "$WT10" add t.txt && G "$WT10" commit -qm feat10
rm -rf "$WT10"
stop A "$TRA"; rc=$?
[ "$rc" = 2 ] && ok "8: a worktree whose folder was deleted before the Stop, its commit not in main, holds the Stop" || fail "8: passed (rc=$rc) although feat10 never reached main"
grep -q "feat10" "$TMP/err" && ok "  … and the hold names it" || fail "  … the hold does not name feat10: $(cat "$TMP/err")"
grep -q "$(G "$P" rev-parse --short=10 feat10)" "$TMP/err" && ok "  … and the commit to bring back" || fail "  … the hold does not give the commit: $(cat "$TMP/err")"
grep -q "git worktree prune" "$TMP/err" && grep -qv "ĐỪNG" "$TMP/err" && ! grep -q "ĐỪNG.*prune\|prune.*ĐỪNG" "$TMP/err" \
  && fail "  … the hold advises git worktree prune (for a detached worktree it drops the reflog that names the commit)" || ok "  … and never advises prune"
grep -q "không kiểm tra được\|KHÔNG chạy được" "$TMP/err" && fail "  … the hold calls a checked worktree 'could not be checked'" || ok "  … and does not call it a gate failure"
G "$P" worktree prune; G "$P" branch -q -D feat10 2>/dev/null

# 8b: the same, but its work is in main (merged earlier): nothing to bring back, the Stop passes and names nothing
sleep 1.2
WT11="$TMP/wt-feat11"; mention feat11 "$WT11"; G "$P" worktree add -q -b feat11 "$WT11" && echo v > "$WT11/v.txt" && G "$WT11" add v.txt && G "$WT11" commit -qm feat11 \
  && G "$P" merge -q --ff-only feat11
rm -rf "$WT11"
stop A "$TRA"; rc=$?
[ "$rc" = 0 ] && ok "8b: a deleted worktree whose work is in main does not hold the Stop" || fail "8b: held (rc=$rc) over work already in main: $(cat "$TMP/err")"
grep -q "prune" "$TMP/err" && fail "  … a hold advised git worktree prune" || ok "  … and nothing advises prune"
G "$P" worktree prune

# 8c (review of step 0): the work came back as the same patch, not the same commit — a detached worktree brought back with
# `diff | git apply` + a commit in main (the documented way), then its folder deleted. Nothing is lost: no hold.
sleep 1.2
WT12="$TMP/wt-det12"; mention det12 "$WT12"; G "$P" worktree add -q --detach "$WT12" && echo w > "$WT12/w.txt" && G "$WT12" add w.txt && G "$WT12" commit -qm det12 \
  && G "$WT12" diff HEAD~1 HEAD | G "$P" apply && G "$P" add w.txt && G "$P" commit -qm "det12 brought back"
rm -rf "$WT12"
stop A "$TRA"; rc=$?
[ "$rc" = 0 ] && ok "8c: a deleted worktree whose commit came back as the same patch does not hold the Stop" || fail "8c: held (rc=$rc) although its patch is in main: $(cat "$TMP/err")"
G "$P" worktree prune

# 8d (review of step 0): another LIVE session owns the deleted worktree: a bystander neither holds on it nor takes it over
sleep 1.2
WT13="$TMP/wt-feat13"; mention feat13 "$WT13"; G "$P" worktree add -q -b feat13 "$WT13" && echo y > "$WT13/y.txt" && G "$WT13" add y.txt && G "$WT13" commit -qm feat13
python3 -c 'import json,os,sys; p=sys.argv[1]; d=json.load(open(p)) if os.path.exists(p) else {}; d.setdefault("owners",{})[os.path.realpath(sys.argv[2])]="OWNER"; d.setdefault("owed",[]).append(os.path.realpath(sys.argv[2])); json.dump(d,open(p,"w"))' \
  "$P/.claude/audit-gate/worktree_merge_gate.state" "$WT13"
python3 -I "$LOCKPY" --register --session OWNER --pid "$$" "$P"
rm -rf "$WT13"
stop A "$TRA"; rc=$?
[ "$rc" = 0 ] && ok "8d: a deleted worktree another live session owns does not hold a bystander" || fail "8d: bystander held (rc=$rc): $(cat "$TMP/err")"
python3 -c 'import json,os,sys; d=json.load(open(sys.argv[1])); r=os.path.realpath(sys.argv[2]); sys.exit(0 if d.get("owners",{}).get(r)=="OWNER" and r in d.get("owed",[]) else 1)' \
  "$P/.claude/audit-gate/worktree_merge_gate.state" "$WT13" && ok "  … and its owner and its debt are kept (a later session still sees it)" \
  || fail "  … the bystander dropped the owner or the debt: $(cat "$P/.claude/audit-gate/worktree_merge_gate.state")"
G "$P" worktree prune; G "$P" branch -q -D feat13 2>/dev/null
python3 -I "$LOCKPY" --unregister --session OWNER "$P" >/dev/null 2>&1

# 8e (review of 8695853): a detached worktree with TWO commits brought back as ONE squashed diff (diff | git apply, one commit in
# main: the documented way), then its folder deleted. Its patch is in main as a whole: no hold.
sleep 1.2
WT14="$TMP/wt-det14"; mention det14 "$WT14"; G "$P" worktree add -q --detach "$WT14" && echo a > "$WT14/a14.txt" && G "$WT14" add a14.txt \
  && G "$WT14" commit -qm det14a && echo b > "$WT14/b14.txt" && G "$WT14" add b14.txt && G "$WT14" commit -qm det14b \
  && G "$WT14" diff HEAD~2 HEAD | G "$P" apply && G "$P" add a14.txt b14.txt && G "$P" commit -qm "det14 brought back squashed"
rm -rf "$WT14"
stop A "$TRA"; rc=$?
[ "$rc" = 0 ] && ok "8e: a deleted worktree whose two commits came back as one squashed diff does not hold the Stop" || fail "8e: held (rc=$rc): $(cat "$TMP/err")"
G "$P" worktree prune

# 8f (review of 8695853): the recorded owner is DEAD: the session that is held on the deleted worktree becomes its owner (so a third
# session leaves it to this live one), as a live worktree's debt is adopted
sleep 1.2
WT15="$TMP/wt-feat15"; mention feat15 "$WT15"; G "$P" worktree add -q -b feat15 "$WT15" && echo z > "$WT15/z.txt" && G "$WT15" add z.txt && G "$WT15" commit -qm feat15
python3 -c 'import json,os,sys; p=sys.argv[1]; d=json.load(open(p)) if os.path.exists(p) else {}; d.setdefault("owners",{})[os.path.realpath(sys.argv[2])]="DEADSESSION"; d.setdefault("owed",[]).append(os.path.realpath(sys.argv[2])); json.dump(d,open(p,"w"))' \
  "$P/.claude/audit-gate/worktree_merge_gate.state" "$WT15"
rm -rf "$WT15"
stop A "$TRA"; rc=$?
[ "$rc" = 2 ] && ok "8f: the deleted worktree of a dead owner holds the Stop" || fail "8f: rc=$rc: $(cat "$TMP/err")"
python3 -c 'import json,os,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("owners",{}).get(os.path.realpath(sys.argv[2]))=="A" else 1)' \
  "$P/.claude/audit-gate/worktree_merge_gate.state" "$WT15" && ok "  … and the held session becomes its owner" || fail "  … the dead owner was kept: $(cat "$P/.claude/audit-gate/worktree_merge_gate.state")"
G "$P" worktree prune; G "$P" branch -q -D feat15 2>/dev/null

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_merge_gate_vanished: all passed" || { echo "❌ test_worktree_merge_gate_vanished: $FAILS failed"; exit 1; }
