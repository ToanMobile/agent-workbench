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

# 4b (review of the fix: tests/gates/test_worktree_merge_gate_owner.sh section 7 held a second Stop under load): a background merge
# REMOVES an integrated worktree while the inventory reads it — its folder and its admin dir's HEAD are already deleted, the reflog file
# is deleted too or not yet. Nothing is lost: it must read clean, never "cannot say" (`git log -g` needs that HEAD; the file does not)
mkdir -p "$TMP/shim"
cat > "$TMP/shim/git" <<'SH'
#!/bin/sh
"$REAL_GIT" "$@"; rc=$?
if [ "$1" = "-C" ] && [ "$2" = "$VANISH_DIR" ] && [ "$3" = rev-parse ] && [ "$4" = --git-path ] && [ ! -e "$VANISH_MARK" ]; then
  : > "$VANISH_MARK"; rm -rf "$VANISH_DIR"; rm -f "$VANISH_ADMIN/HEAD"; [ -n "${VANISH_REFLOG:-}" ] && rm -f "$VANISH_ADMIN/logs/HEAD"
fi
exit $rc
SH
chmod +x "$TMP/shim/git"
for variant in "" drop; do
  W4B="$TMP/wt-removing$variant"; G "$P" worktree add -q --detach "$W4B"
  VANISH_DIR="$(cd "$W4B" && pwd -P)"; VANISH_ADMIN="$(G "$W4B" rev-parse --absolute-git-dir)"; VANISH_MARK="$TMP/removing$variant"; VANISH_REFLOG="$variant"
  export VANISH_DIR VANISH_ADMIN VANISH_MARK VANISH_REFLOG
  (cd "$P" && PATH="$TMP/shim:$PATH" python3 "$WTPY" status --strict) >"$TMP/st.out" 2>&1; rc=$?
  [ -e "$VANISH_MARK" ] && [ "$rc" = 0 ] && row "$VANISH_DIR" | grep -q "^clean" \
    && ok "4b: an integrated worktree removed while the inventory reads it (reflog file ${variant:-kept}) reads clean, not 'cannot say'" \
    || fail "4b: (rc=$rc, shim fired=$([ -e "$VANISH_MARK" ] && echo y || echo n), reflog file ${variant:-kept}): $(cat "$TMP/st.out")"
  G "$P" worktree prune
done

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

# 8 (OpenCodeReview of the fix): several deleted folders in one Stop share ONE inventory (one ref-tip scan, one budget inside the hook's
# alarm), not one inventory each — the alarm's exit passes the Stop in silence
sleep 1.2
cat > "$TMP/shim/git" <<'SH'
#!/bin/sh
for a in "$@"; do [ "$a" = for-each-ref ] && echo x >> "$SCAN_LOG"; done
exec "$REAL_GIT" "$@"
SH
chmod +x "$TMP/shim/git"
W8A="$TMP/wt-two-a"; W8B="$TMP/wt-two-b"; mention "$W8A"; mention "$W8B"
G "$P" worktree add -q --detach "$W8A"; G "$P" worktree add -q --detach "$W8B"; rm -rf "$W8A" "$W8B"
SCAN_LOG="$TMP/scans"; : > "$SCAN_LOG"; export SCAN_LOG
PATH="$TMP/shim:$PATH" stop A "$TRA"; rc=$?
[ "$rc" = 0 ] && [ "$(wc -l < "$SCAN_LOG" | tr -d ' ')" = 1 ] && ok "8: two deleted folders, one Stop: one inventory (one ref scan), and it passes" \
  || fail "8: rc=$rc, ref scans=$(wc -l < "$SCAN_LOG" | tr -d ' '): $(cat "$TMP/err")"
G "$P" worktree prune

# 9 (OpenCodeReview of the fix): the inventory returns no row for a deleted folder git still lists (a listing it cannot tie to the path):
# that is "cannot say" (held), never "unregistered, nothing to lose" — only a fresh listing without it proves that
sleep 1.2
cat > "$TMP/shim/git" <<'SH'
#!/bin/sh
z=""; for a in "$@"; do [ "$a" = -z ] && z=1; done
if [ "$3" = worktree ] && [ "$4" = list ] && [ -n "$z" ]; then   # only the inventory's -z listing loses it; the hook's own listing keeps it
  "$REAL_GIT" "$@" | python3 -c 'import os,sys; h=b"worktree "+os.environ["HIDE_DIR"].encode(); sys.stdout.buffer.write(b"\0\0".join(r for r in sys.stdin.buffer.read().split(b"\0\0") if not r.startswith(h)))'
  exit 0
fi
exec "$REAL_GIT" "$@"
SH
chmod +x "$TMP/shim/git"
W9="$TMP/wt-unseen"; mention "$W9"; reflog_only "$W9"; HIDE_DIR="$(cd "$W9" && pwd -P)"; export HIDE_DIR; rm -rf "$W9"
PATH="$TMP/shim:$PATH" stop A "$TRA"; rc=$?
[ "$rc" = 2 ] && grep -q "wt-unseen" "$TMP/err" && ok "9: a deleted folder the inventory cannot see while git still lists it holds the Stop" \
  || fail "9: passed (rc=$rc) although $(cut -c1-10 "$TMP/wt-unseen.sha") is named by its reflog only: $(cat "$TMP/err")"
G "$P" worktree prune

# 10 (OpenCodeReview): a deleted worktree this session never made, named or owes (an old registration, another session's) is not
# inventoried for it: only the session's own deleted folders take the hook's time (each inventory row costs git calls inside its alarm)
sleep 1.2
cat > "$TMP/shim/git" <<'SH'
#!/bin/sh
for a in "$@"; do case "$a" in *"$FOREIGN_HEAD"*) echo x >> "$FOREIGN_LOG" ;; esac; done
exec "$REAL_GIT" "$@"
SH
chmod +x "$TMP/shim/git"
WF="$TMP/wt-foreign"; G "$P" worktree add -q --detach "$WF" && echo f > "$WF/f.txt" && G "$WF" add f.txt && G "$WF" commit -qm foreign   # never mentioned
FOREIGN_HEAD="$(G "$WF" rev-parse HEAD)"; FOREIGN_LOG="$TMP/foreign"; : > "$FOREIGN_LOG"; export FOREIGN_HEAD FOREIGN_LOG; rm -rf "$WF"
W10="$TMP/wt-mine"; mention "$W10"; G "$P" worktree add -q --detach "$W10"; rm -rf "$W10"
PATH="$TMP/shim:$PATH" stop A "$TRA"; rc=$?
[ "$rc" = 0 ] && [ ! -s "$FOREIGN_LOG" ] && ok "10: a deleted worktree the session does not own is never inventoried by its Stop" \
  || fail "10: rc=$rc, git calls naming the foreign HEAD: $(wc -l < "$FOREIGN_LOG" | tr -d ' '): $(cat "$TMP/err")"
G "$P" worktree prune

# 11 (OpenCodeReview A1): the deleted-folder inventory runs first and inside the same 13 s alarm as the main inventory of the session's live
# worktrees; with a stalled git it took everything up to alarm - 1.5 s, leaving the main inventory the 0.5 s floor and the alarm's silent
# pass (os._exit(0)) the rest. It gets a share now (at most half of what is left). The shim stalls the first ref scan (the deleted-folder
# inventory's: it runs first) and stamps the next git call of the hook: the gap is what that inventory took, measured against the alarm
# that was left when it began (13 s from the hook's start), so a slow runner shifts both sides. WORKTREE_AUTO_MERGE=0: no merge to wait for.
sleep 1.2
cat > "$TMP/shim/git" <<'SH'
#!/bin/sh
if [ ! -e "$STALL_DIR/stalled" ]; then
  case " $* " in *" for-each-ref "*) : > "$STALL_DIR/stalled"; exec sleep 100 ;; esac
elif [ ! -e "$STALL_DIR/after" ]; then : > "$STALL_DIR/after"; fi
exec "$REAL_GIT" "$@"
SH
chmod +x "$TMP/shim/git"
W11G="$TMP/wt-gone11"; W11L="$TMP/wt-live11"; mention "$W11G"; mention "$W11L"
G "$P" worktree add -q --detach "$W11G"; rm -rf "$W11G"
G "$P" worktree add -q --detach "$W11L" && echo l > "$W11L/l.txt" && G "$W11L" add l.txt && G "$W11L" commit -qm live11   # unintegrated: the main inventory's
STALL_DIR="$TMP/stall11"; mkdir -p "$STALL_DIR"; export STALL_DIR
T0="$(python3 -c 'import time; print(time.time())')"
PATH="$TMP/shim:$PATH" WORKTREE_AUTO_MERGE=0 stop A "$TRA"; rc=$?
python3 -I -c 'import os, sys
d, t0, rc = sys.argv[1], float(sys.argv[2]), int(sys.argv[3])
try:
    began, after = os.stat(d + "/stalled").st_mtime, os.stat(d + "/after").st_mtime
except OSError as e:
    print(f"the shim never saw both calls ({e})"); sys.exit(1)
left, took = 13 - (began - t0), after - began
print(f"it took {took:.1f} s of the {left:.1f} s left, rc {rc}")
sys.exit(0 if took <= 0.7 * left and rc == 2 else 1)' "$STALL_DIR" "$T0" "$rc" > "$TMP/share11"
[ $? = 0 ] && grep -q 'wt-live11.*ahead=1' "$TMP/err" && ok "11: a stalled deleted-folder inventory takes a share of the alarm, the main inventory keeps its time ($(cat "$TMP/share11"))" \
  || fail "11: $(cat "$TMP/share11"): $(head -c 400 "$TMP/err")"
G "$P" worktree prune

[ "$FAILS" -eq 0 ] && echo "✅ test_worktree_reflog_gone_folder: all passed" || { echo "❌ test_worktree_reflog_gone_folder: $FAILS failed"; exit 1; }
