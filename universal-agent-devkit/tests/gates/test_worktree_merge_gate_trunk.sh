#!/usr/bin/env bash
# W1 R1 v6 (docs/workflow-improvements.md I.0) - hooks/worktree_merge_gate.sh in trunk mode (`git config devkit.trunkMode true`):
#   1 the session's OWN worktree (its EnterWorktree record), committed and idle: merged into main with --keep at Stop (main fast-forwards,
#     the worktree stays for the session), the Stop is not held
#   2 the same with uncommitted work: nothing merged, a note, never a hold (the session is alive and works on)
#   3 trunk mode off: the old rule (the worktree the session is in is owed, held once it leaves): main untouched
#   4 the record of a session that is gone: adopted - merged through the gate, removed, its record pruned
#   5 a worktree another LIVE session owns (its state names it from `worktree add --session`): not merged, even when this session's
#     transcript names it and it was made after this session started (the old "made here" rule took it)
#   6 /clear and /resume (same process, new session id, still in the worktree): the dead id's record becomes the new id's, nothing adopted
#   7 a lock on main left by another live session: no reason not to merge in trunk mode (main has no holder there)
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export DEVKIT_LANG=en GIT_CONFIG_GLOBAL=/dev/null WORKTREE_AUTO_MERGE_WAIT_S=9
unset WORKTREE_TRUNK_MODE WORKTREE_MAX
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/worktree_merge_gate.sh"; WTPY="$DEVKIT_DIR/scripts/git/worktree.py"; SL="$DEVKIT_DIR/bin/session_lock.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
repo() {   # repo <name>: a main checkout in trunk mode
  local m="$TMP/$1"; mkdir -p "$m" && G "$m" init -q -b main && printf '.claude/audit-gate/\n/.claude/worktrees/\n' > "$m/.gitignore" \
    && echo a > "$m/a.txt" && G "$m" add -A && G "$m" commit -qm i && G "$m" config devkit.trunkMode true
}
wtadd() {   # wtadd <main> <name> <session>: a session worktree made like the WorktreeCreate hook makes it
  (cd "$1" && python3 -I "$WTPY" add "$1/.claude/worktrees/$2" --session="$3" --no-init >/dev/null 2>&1) || fail "setup: add $2"
}
commit_in() { echo "$3" > "$1/.claude/worktrees/$2/$3.txt" && G "$1/.claude/worktrees/$2" add "$3.txt" && G "$1/.claude/worktrees/$2" commit -qm "$3"; }
record() { mkdir -p "$1/.claude/audit-gate/session_worktree" && printf '%s\n' "$1/.claude/worktrees/$3" > "$1/.claude/audit-gate/session_worktree/$2"; }
transcript() {   # transcript <file> [path a Bash 'worktree add' named]: a session started a minute ago
  python3 -c 'import json,sys,time,datetime; f,p=sys.argv[1],sys.argv[2]
ts=datetime.datetime.fromtimestamp(time.time()-60, datetime.timezone.utc).isoformat().replace("+00:00","Z")
with open(f,"w") as o:
    o.write(json.dumps({"type":"user","timestamp":ts,"message":{"role":"user","content":"go"}})+"\n")
    if p: o.write(json.dumps({"type":"assistant","timestamp":ts,"message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"agent-kit worktree add "+p}}]}})+"\n")' "$1" "${2:-}"
}
stop() {   # stop <main> <session> <cwd> <transcript> [env...]: the hook's exit code; stdout in $TMP/out, stderr in $TMP/err
  local m="$1" s="$2" c="$3" t="$4"; shift 4
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"Stop","session_id":sys.argv[1],"cwd":sys.argv[2],"transcript_path":sys.argv[3]}))' "$s" "$c" "$t" \
    | env CLAUDE_PROJECT_DIR="$m" "$@" bash "$HOOK" > "$TMP/out" 2> "$TMP/err"
}

# 1 own worktree, committed, idle: merged with --keep, not held
repo a; wtadd "$TMP/a" s1 s1; commit_in "$TMP/a" s1 one; record "$TMP/a" s1 s1; transcript "$TMP/t1.jsonl"
stop "$TMP/a" s1 "$TMP/a/.claude/worktrees/s1" "$TMP/t1.jsonl"; rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/a/one.txt" ] && [ -d "$TMP/a/.claude/worktrees/s1" ] && grep -q "gộp worktree phiên" "$TMP/out" \
  && ok "own worktree, committed: merged into main with --keep (it stays), Stop not held" || fail "own merge (rc $rc): out=$(head -c 300 "$TMP/out") err=$(head -c 300 "$TMP/err")"

# 2 uncommitted work: a note, no merge, no hold
commit_in "$TMP/a" s1 two; echo dirty > "$TMP/a/.claude/worktrees/s1/dirty.txt"
stop "$TMP/a" s1 "$TMP/a/.claude/worktrees/s1" "$TMP/t1.jsonl"; rc=$?
[ "$rc" = 0 ] && [ ! -f "$TMP/a/two.txt" ] && grep -q "chưa commit" "$TMP/out" && ok "  … uncommitted work in it: nothing merged, a note, not held" || fail "dirty own (rc $rc): $(head -c 300 "$TMP/out")"
rm -f "$TMP/a/.claude/worktrees/s1/dirty.txt"

# 3 trunk mode off: the old rule - the worktree the session is in is not merged by its own Stop
repo b; G "$TMP/b" config devkit.trunkMode false; wtadd "$TMP/b" s1 s1; commit_in "$TMP/b" s1 one; record "$TMP/b" s1 s1
stop "$TMP/b" s1 "$TMP/b/.claude/worktrees/s1" "$TMP/t1.jsonl"; rc=$?
[ "$rc" = 0 ] && [ ! -f "$TMP/b/one.txt" ] && ok "trunk mode off: as before (the worktree the session is in is not merged by its Stop)" || fail "trunk off (rc $rc)"

# 4 a gone session's record: adopted (merged, removed), record pruned
repo c; wtadd "$TMP/c" s9 s9; commit_in "$TMP/c" s9 nine; record "$TMP/c" s9 s9
stop "$TMP/c" s1 "$TMP/c" "$TMP/t1.jsonl"; rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/c/nine.txt" ] && [ ! -d "$TMP/c/.claude/worktrees/s9" ] && [ ! -e "$TMP/c/.claude/audit-gate/session_worktree/s9" ] \
  && ok "a gone session's worktree: adopted - merged into main, removed, its record pruned" || fail "adoption (rc $rc): out=$(head -c 300 "$TMP/out") err=$(head -c 300 "$TMP/err")"

# 5 another LIVE session's worktree (owner in its state): left alone, even named in this transcript and made after this session started
repo d; wtadd "$TMP/d" s5 s5; commit_in "$TMP/d" s5 five
python3 -I "$SL" --register --session s5 --pid $$ "$TMP/d" >/dev/null 2>&1
transcript "$TMP/t5.jsonl" "$TMP/d/.claude/worktrees/s5"
stop "$TMP/d" s1 "$TMP/d" "$TMP/t5.jsonl"; rc=$?
[ "$rc" = 0 ] && [ ! -f "$TMP/d/five.txt" ] && [ -d "$TMP/d/.claude/worktrees/s5" ] && ok "another live session's worktree: not merged, not removed, Stop not held" || fail "a live owner's worktree was taken or held on (rc $rc)"

# 6 /clear: a dead id's record naming the worktree the session is in becomes the new id's; nothing adopted
repo e; wtadd "$TMP/e" s0 s0; record "$TMP/e" s0 s0
stop "$TMP/e" s1b "$TMP/e/.claude/worktrees/s0" "$TMP/t1.jsonl"; rc=$?
[ "$rc" = 0 ] && [ -d "$TMP/e/.claude/worktrees/s0" ] && [ "$(cat "$TMP/e/.claude/audit-gate/session_worktree/s1b" 2>/dev/null)" = "$TMP/e/.claude/worktrees/s0" ] \
  && [ ! -e "$TMP/e/.claude/audit-gate/session_worktree/s0" ] && ok "/clear: the record follows the session to its new id, the worktree is kept" || fail "reown (rc $rc): $(ls "$TMP/e/.claude/audit-gate/session_worktree" 2>&1)"

# 7 a live other session's lock on main: no reason to skip the merge in trunk mode
repo f; wtadd "$TMP/f" s1 s1; commit_in "$TMP/f" s1 seven; record "$TMP/f" s1 s1
python3 -c 'import json,os,sys,time; json.dump({"session_id":"other","started":time.time(),"heartbeat":time.time(),"cwd":sys.argv[1],"pid":os.getppid()}, open(sys.argv[2],"w"))' \
  "$TMP/f" "$(G "$TMP/f" rev-parse --absolute-git-dir)/devkit-session.lock"
stop "$TMP/f" s1 "$TMP/f/.claude/worktrees/s1" "$TMP/t1.jsonl"; rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/f/seven.txt" ] && ok "a lock on main from another live session: trunk mode merges anyway" || fail "main lock blocked the trunk merge (rc $rc): $(head -c 300 "$TMP/out")"

# 8 a gone session's worktree whose folder was removed from outside while git still lists it, its commit not in main: held, record kept
repo g; wtadd "$TMP/g" s8 s8; commit_in "$TMP/g" s8 eight; record "$TMP/g" s8 s8; rm -rf "$TMP/g/.claude/worktrees/s8"
stop "$TMP/g" s1 "$TMP/g" "$TMP/t1.jsonl"; rc=$?
[ "$rc" = 2 ] && [ -e "$TMP/g/.claude/audit-gate/session_worktree/s8" ] && ok "a gone session's worktree removed from outside, commit not in main: Stop held, its record kept" \
  || fail "vanished dead worktree (rc $rc, record $( [ -e "$TMP/g/.claude/audit-gate/session_worktree/s8" ] && echo kept || echo pruned)): $(head -c 300 "$TMP/err")"

# 9 liveness cannot be told (bin/session_lock.py not importable): no record is adopted - it could be a live peer's worktree
FK="$TMP/kit"; mkdir -p "$FK/hooks" "$FK/bin" "$FK/profiles" && ln -s "$DEVKIT_DIR/scripts" "$FK/scripts"
for f in "$DEVKIT_DIR"/hooks/*; do ln -s "$f" "$FK/hooks/"; done; rm -f "$FK/hooks/worktree_merge_gate.sh" && cp "$HOOK" "$FK/hooks/"
for f in "$DEVKIT_DIR"/bin/*; do ln -s "$f" "$FK/bin/"; done; rm -f "$FK/bin/session_lock.py" && echo 'raise ImportError("broken on purpose")' > "$FK/bin/session_lock.py"
repo h; wtadd "$TMP/h" s9 s9; commit_in "$TMP/h" s9 nine; record "$TMP/h" s9 s9
python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"Stop","session_id":"s1","cwd":sys.argv[1],"transcript_path":sys.argv[2]}))' "$TMP/h" "$TMP/t1.jsonl" \
  | CLAUDE_PROJECT_DIR="$TMP/h" bash "$FK/hooks/worktree_merge_gate.sh" >/dev/null 2>&1
[ ! -f "$TMP/h/nine.txt" ] && [ -d "$TMP/h/.claude/worktrees/s9" ] && ok "session_lock not importable: no record adopted (liveness unknown), the worktree kept" || fail "adopted a record with liveness unknown"

echo
[ "$FAILS" -eq 0 ] && { echo "test_worktree_merge_gate_trunk: PASS"; exit 0; } || { echo "test_worktree_merge_gate_trunk: FAIL ($FAILS)"; exit 1; }
