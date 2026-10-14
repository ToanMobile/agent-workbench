#!/usr/bin/env bash
# docs/issues-bugs.md A.2 #3 (trunk-integrator-no-shared-main.md §8.1): a commit made in a worktree and then left (`commit`, then
# `checkout --detach HEAD~1`) is named by nothing but the worktree's own HEAD reflog. scripts/git/worktree.py _inventory read that reflog
# only while the folder existed (`reflog = … if os.path.isdir(path) else []`): a folder deleted from outside (rm -rf, no prune) BEFORE the
# inventory read it gave reflog [] and the commit passed as integrated — `worktree status` said clean and the Stop gate passed; the next
# `git worktree prune` + gc loses it. git keeps that reflog in the worktree's admin dir (<common>/worktrees/<id>/logs/HEAD) until a prune:
# it is read from there now, never turned into "cannot say" (tests/gates/test_worktree_merge_gate_vanished.sh case 1 relies on []).
#   1 `worktree status`: the reflog-only commit of a deleted folder is UNINTEGRATED / UNREACHABLE (was: clean)
#   2 control: a deleted folder whose reflog names nothing main lacks stays clean
#   3 a worktree on a BRANCH (detach, commit, back to the branch), folder deleted: held too
#   4 its admin reflog replaced by a FIFO: "cannot say" (held), and nothing hangs
#   5 Stop hook: the folder vanishes WHILE the inventory reads it (after the hook's own live check): held, named (was: passed)
#   6 Stop hook: the folder was deleted BEFORE the Stop (hooks/worktree_merge_gate.sh gone_folder_reason): held, the commit named (was: passed)
#   7 Stop hook control: the same with nothing only the reflog names passes (no hold on a deleted, integrated worktree)
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WTPY="$DEVKIT_DIR/scripts/git/worktree.py"
HOOK="$DEVKIT_DIR/hooks/worktree_merge_gate.sh"; LOCKPY="$DEVKIT_DIR/bin/session_lock.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
REAL_GIT="$(command -v git)"; export REAL_GIT

P="$TMP/proj"; mkdir -p "$P" && G "$P" init -q -b main . && printf '1\n' > "$P/a.txt" && G "$P" add a.txt && G "$P" commit -qm init
status() { (cd "$P" && python3 "$WTPY" status --strict) >"$TMP/st.out" 2>&1; }
row() { grep -F "$1" "$TMP/st.out"; }
reflog_only() {   # reflog_only <dir>: a detached worktree with commit X that only its HEAD reflog names (HEAD back on main's commit)
  G "$P" worktree add -q --detach "$1" && echo x > "$1/x-$(basename "$1").txt" && G "$1" add -A && G "$1" commit -qm "only-in-reflog $(basename "$1")" \
    && G "$1" rev-parse HEAD > "$TMP/$(basename "$1").sha" && G "$1" checkout -q --detach HEAD~1
}

# 1: the reflog-only commit of a folder deleted from outside
W1="$TMP/wt-gone"; reflog_only "$W1"; W1R="$(cd "$W1" && pwd -P)"
status; [ $? = 1 ] && row "$W1R" | grep -q "UNINTEGRATED" && ok "setup: with its folder, the reflog-only worktree is UNINTEGRATED" \
  || fail "setup: the reflog-only worktree is not held while its folder exists: $(cat "$TMP/st.out")"
rm -rf "$W1"
status; rc=$?
[ "$rc" = 1 ] && row "$W1R" | grep -q "UNINTEGRATED" && row "$W1R" | grep -q "UNREACHABLE" \
  && ok "1: folder deleted (no prune): its reflog-only commit is still UNINTEGRATED / UNREACHABLE" \
  || fail "1: a deleted folder's reflog-only commit passes as integrated (rc=$rc): $(cat "$TMP/st.out")"
G "$P" worktree prune

# 2: control: a deleted folder with nothing but main's own commit in its reflog is clean — a real answer, not "cannot say"
W2="$TMP/wt-plain"; G "$P" worktree add -q --detach "$W2"; W2R="$(cd "$W2" && pwd -P)"; rm -rf "$W2"
status; rc=$?
[ "$rc" = 0 ] && row "$W2R" | grep -q "^clean" && ok "2: a deleted folder whose reflog names nothing main lacks stays clean" \
  || fail "2: (rc=$rc): $(cat "$TMP/st.out")"
G "$P" worktree prune

# 3: a worktree on a branch: detach, commit, back to the branch (its tip is main's commit), folder deleted
W3="$TMP/wt-branch"; G "$P" worktree add -q -b feat3 "$W3" && G "$W3" checkout -q --detach && echo b > "$W3/b.txt" && G "$W3" add b.txt \
  && G "$W3" commit -qm "detached on a branch worktree" && G "$W3" checkout -q feat3; W3R="$(cd "$W3" && pwd -P)"; rm -rf "$W3"
status; rc=$?
[ "$rc" = 1 ] && row "$W3R" | grep -q "UNINTEGRATED" && ok "3: a branch worktree's reflog-only commit is held after its folder went" \
  || fail "3: (rc=$rc): $(cat "$TMP/st.out")"
G "$P" worktree prune; G "$P" branch -q -D feat3 2>/dev/null

# 4: the admin reflog replaced by a FIFO: never read as clean, never a hang
W4="$TMP/wt-fifo"; G "$P" worktree add -q --detach "$W4"; W4R="$(cd "$W4" && pwd -P)"; ADM4="$(G "$W4" rev-parse --absolute-git-dir)"; rm -rf "$W4"
rm -f "$ADM4/logs/HEAD" && mkfifo "$ADM4/logs/HEAD"
python3 -c 'import subprocess,sys
try:
    r = subprocess.run([sys.executable, sys.argv[1], "status"], cwd=sys.argv[2], capture_output=True, text=True, timeout=60)
    open(sys.argv[3], "w").write(r.stdout + r.stderr)
except subprocess.TimeoutExpired:
    open(sys.argv[3], "w").write("HUNG")' "$WTPY" "$P" "$TMP/st.out"
! grep -q HUNG "$TMP/st.out" && row "$W4R" | grep -q "UNINTEGRATED" && ok "4: an admin reflog that is a FIFO reads as 'cannot say' (held) and nothing hangs" \
  || fail "4: $(cat "$TMP/st.out")"
rm -f "$ADM4/logs/HEAD"; G "$P" worktree prune

# The Stop hook (hooks/worktree_merge_gate.sh), as in tests/gates/test_worktree_merge_gate_vanished.sh
TRA="$TMP/tra.jsonl"
python3 -c 'import json,datetime;print(json.dumps({"type":"user","timestamp":datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z"),"message":{"content":"go"}}))' > "$TRA"
sleep 1.2
mention() { python3 -c 'import json,sys;print(json.dumps({"type":"assistant","message":{"content":[{"type":"tool_use","id":"t","name":"Bash","input":{"command":sys.argv[1]}}]}}))' "git worktree add --detach $1" >> "$TRA"; }
stop() { printf '{"session_id":"%s","hook_event_name":"Stop","transcript_path":"%s"}' "$1" "$2" | CLAUDE_PROJECT_DIR="$P" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
python3 -I "$LOCKPY" --register --session A --pid "$$" "$P"

# 5: the folder vanishes right after the inventory's first git call on it (`rev-parse --git-path logs/HEAD`): the hook's live check saw it
mkdir -p "$TMP/shim"
cat > "$TMP/shim/git" <<'SH'
#!/bin/sh
"$REAL_GIT" "$@"; rc=$?
if [ "$1" = "-C" ] && [ "$2" = "$VANISH_DIR" ] && [ "$3" = rev-parse ] && [ "$4" = --git-path ] && [ ! -e "$VANISH_MARK" ]; then
  : > "$VANISH_MARK"; rm -rf "$VANISH_DIR"
fi
exit $rc
SH
chmod +x "$TMP/shim/git"
W5="$TMP/wt-race"; mention "$W5"; reflog_only "$W5"
VANISH_DIR="$(cd "$W5" && pwd -P)"; VANISH_MARK="$TMP/vanished5"; export VANISH_DIR VANISH_MARK
PATH="$TMP/shim:$PATH" stop A "$TRA"; rc=$?
[ -e "$VANISH_MARK" ] && [ ! -d "$W5" ] && ok "setup: the folder vanished while the inventory read it" || fail "setup: the shim never fired (the inventory changed?)"
[ "$rc" = 2 ] && ok "5: a folder that vanished while its reflog was read, a commit only that reflog names: the Stop is held" \
  || fail "5: passed (rc=$rc) although $(cut -c1-10 "$TMP/wt-race.sha") is named by its reflog only: $(cat "$TMP/err")"
grep -q "wt-race" "$TMP/err" && ok "  … and the hold names it" || fail "  … the hold does not name wt-race: $(cat "$TMP/err")"
G "$P" worktree prune

# 6: the folder was deleted BEFORE the Stop (the hook's own gone-folder path, not the inventory's live rows)
sleep 1.2
W6="$TMP/wt-before"; mention "$W6"; reflog_only "$W6"; rm -rf "$W6"
stop A "$TRA"; rc=$?
[ "$rc" = 2 ] && ok "6: a folder deleted before the Stop, a commit only its reflog names: the Stop is held" \
  || fail "6: passed (rc=$rc) although $(cut -c1-10 "$TMP/wt-before.sha") is named by its reflog only: $(cat "$TMP/err")"
grep -q "wt-before" "$TMP/err" && grep -q "$(cut -c1-10 "$TMP/wt-before.sha")" "$TMP/err" && ok "  … and the hold names it and the commit to keep" \
  || fail "  … the hold does not name wt-before and its commit: $(cat "$TMP/err")"
G "$P" worktree prune

# 7: control: deleted before the Stop, nothing only its reflog names (HEAD in main): no hold
sleep 1.2
W7="$TMP/wt-clean"; mention "$W7"; G "$P" worktree add -q --detach "$W7"; rm -rf "$W7"
stop A "$TRA"; rc=$?
[ "$rc" = 0 ] && ok "7: a deleted folder with nothing to bring back does not hold the Stop" || fail "7: held (rc=$rc): $(cat "$TMP/err")"
G "$P" worktree prune

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_reflog_gone_folder: all passed" || { echo "❌ test_worktree_reflog_gone_folder: $FAILS failed"; exit 1; }
