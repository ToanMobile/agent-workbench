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
stop() { printf '{"session_id":"%s","hook_event_name":"Stop","transcript_path":"%s"}' "$1" "$2" | CLAUDE_PROJECT_DIR="$P" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
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
if [ "$1" = "-C" ] && [ "$2" = "$VANISH_DIR" ] && [ "$3" = symbolic-ref ] && [ ! -e "$VANISH_MARK" ]; then
  : > "$VANISH_MARK"
  "$REAL_GIT" -C "$VANISH_MAIN" merge -q --ff-only "$VANISH_BRANCH" && rm -rf "$VANISH_DIR" && "$REAL_GIT" -C "$VANISH_MAIN" worktree prune
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

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_merge_gate_vanished: all passed" || { echo "❌ test_worktree_merge_gate_vanished: $FAILS failed"; exit 1; }
