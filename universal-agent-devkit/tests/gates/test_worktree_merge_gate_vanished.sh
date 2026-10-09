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

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_merge_gate_vanished: all passed" || { echo "❌ test_worktree_merge_gate_vanished: $FAILS failed"; exit 1; }
