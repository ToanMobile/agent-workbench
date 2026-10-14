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
record() {   # record <main> <session> <worktree name> [pid]: a session's record as the PostToolUse hook writes it (line 2: the claude pid)
  mkdir -p "$1/.claude/audit-gate/session_worktree" && { printf '%s\n' "$1/.claude/worktrees/$3"; [ -z "${4:-}" ] || printf 'pid %s\n' "$4"; } > "$1/.claude/audit-gate/session_worktree/$2"
}
DEAD=2147483646   # a pid no process has
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
repo c; wtadd "$TMP/c" s9 s9; commit_in "$TMP/c" s9 nine; record "$TMP/c" s9 s9 "$DEAD"
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
repo e; wtadd "$TMP/e" s0 s0; record "$TMP/e" s0 s0 $$   # the same claude process ($$) under the old id; the new id is registered by SessionStart with that pid
python3 -I "$SL" --register --session s1b --pid $$ "$TMP/e" >/dev/null 2>&1
stop "$TMP/e" s1b "$TMP/e/.claude/worktrees/s0" "$TMP/t1.jsonl"; rc=$?
[ "$rc" = 0 ] && [ -d "$TMP/e/.claude/worktrees/s0" ] && [ "$(head -1 "$TMP/e/.claude/audit-gate/session_worktree/s1b" 2>/dev/null)" = "$TMP/e/.claude/worktrees/s0" ] \
  && [ "$(sed -n 2p "$TMP/e/.claude/audit-gate/session_worktree/s1b" 2>/dev/null)" = "pid $$" ] \
  && [ ! -e "$TMP/e/.claude/audit-gate/session_worktree/s0" ] && ok "/clear: the record follows the session to its new id, the worktree is kept" || fail "reown (rc $rc): $(ls "$TMP/e/.claude/audit-gate/session_worktree" 2>&1)"

# 7 a live other session's lock on main: no reason to skip the merge in trunk mode
repo f; wtadd "$TMP/f" s1 s1; commit_in "$TMP/f" s1 seven; record "$TMP/f" s1 s1
python3 -c 'import json,os,sys,time; json.dump({"session_id":"other","started":time.time(),"heartbeat":time.time(),"cwd":sys.argv[1],"pid":os.getppid()}, open(sys.argv[2],"w"))' \
  "$TMP/f" "$(G "$TMP/f" rev-parse --absolute-git-dir)/devkit-session.lock"
stop "$TMP/f" s1 "$TMP/f/.claude/worktrees/s1" "$TMP/t1.jsonl"; rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/f/seven.txt" ] && ok "a lock on main from another live session: trunk mode merges anyway" || fail "main lock blocked the trunk merge (rc $rc): $(head -c 300 "$TMP/out")"

# 8 a gone session's worktree whose folder was removed from outside while git still lists it, its commit not in main: held, record kept
repo g; wtadd "$TMP/g" s8 s8; commit_in "$TMP/g" s8 eight; record "$TMP/g" s8 s8 "$DEAD"; rm -rf "$TMP/g/.claude/worktrees/s8"
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

# 10 a LIVE session idle at its prompt (its pid answers, its heartbeat is 40 min old): liveness is the pid, never the heartbeat - its
#    worktree is not adopted (merged and removed under it); once the pid is gone the same record is adopted (R3 review 14/10, P1-1)
repo i; wtadd "$TMP/i" s7 s7; commit_in "$TMP/i" s7 seven; record "$TMP/i" s7 s7
python3 -I "$SL" --register --session s7 --pid $$ "$TMP/i" >/dev/null 2>&1
REG="$(G "$TMP/i" rev-parse --absolute-git-dir)/devkit-sessions/s7.json"
python3 -c 'import json,sys,time; d=json.load(open(sys.argv[1])); d["heartbeat"]=time.time()-2400; json.dump(d,open(sys.argv[1],"w"))' "$REG"
stop "$TMP/i" s1 "$TMP/i" "$TMP/t1.jsonl"; rc=$?
[ "$rc" = 0 ] && [ ! -f "$TMP/i/seven.txt" ] && [ -d "$TMP/i/.claude/worktrees/s7" ] && [ -e "$TMP/i/.claude/audit-gate/session_worktree/s7" ] \
  && ok "a live session idle for 40 min (pid answers): its worktree and record are left alone" || fail "adopted a live idle session's worktree (rc $rc): out=$(head -c 300 "$TMP/out")"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["pid"]=2147483646; json.dump(d,open(sys.argv[1],"w"))' "$REG"
stop "$TMP/i" s1 "$TMP/i" "$TMP/t1.jsonl"; rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/i/seven.txt" ] && [ ! -d "$TMP/i/.claude/worktrees/s7" ] \
  && ok "  … the same record once its pid is gone: adopted (merged, removed)" || fail "dead pid not adopted (rc $rc): out=$(head -c 300 "$TMP/out") err=$(head -c 300 "$TMP/err")"

# 10a adoption needs PROOF of death (session_lock.owner_gone): a missing registry entry is not one (SessionEnd deletes the entry of every ended
#     session, and a live session whose registration failed never had one) - the pid on the record is (OCR 13 / R1 review 14/10)
repo n1; wtadd "$TMP/n1" s3 s3; commit_in "$TMP/n1" s3 three; record "$TMP/n1" s3 s3
stop "$TMP/n1" s1 "$TMP/n1" "$TMP/t1.jsonl"; rc=$?
[ "$rc" = 0 ] && [ ! -f "$TMP/n1/three.txt" ] && [ -d "$TMP/n1/.claude/worktrees/s3" ] && grep -q "left alone" "$TMP/err" \
  && ok "no pid on the record, no registry entry, a fresh record: not adopted (nothing proves the owner gone), a note on stderr" \
  || fail "adopted on a missing registry entry (rc $rc): out=$(head -c 200 "$TMP/out") err=$(head -c 200 "$TMP/err")"
touch -t "$(date -v-25H +%Y%m%d%H%M 2>/dev/null || date -d '25 hours ago' +%Y%m%d%H%M)" "$TMP/n1/.claude/audit-gate/session_worktree/s3"
stop "$TMP/n1" s1 "$TMP/n1" "$TMP/t1.jsonl"; rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/n1/three.txt" ] && [ ! -d "$TMP/n1/.claude/worktrees/s3" ] \
  && ok "  … the same record 25 h old: adopted" || fail "an old pid-less record not adopted (rc $rc): out=$(head -c 200 "$TMP/out") err=$(head -c 200 "$TMP/err")"
repo n2; wtadd "$TMP/n2" s3 s3; commit_in "$TMP/n2" s3 three; record "$TMP/n2" s3 s3 $$   # a live session with no registry entry: its record's pid answers
stop "$TMP/n2" s1 "$TMP/n2" "$TMP/t1.jsonl"; rc=$?
[ "$rc" = 0 ] && [ ! -f "$TMP/n2/three.txt" ] && [ -d "$TMP/n2/.claude/worktrees/s3" ] \
  && ok "  … a live session with no registry entry (failed registration): its record's pid answers - not adopted" || fail "adopted a live unregistered session's worktree (rc $rc)"

# 10a2 reown only where liveness is known and trunk mode is on (OCR 5): with session_lock not importable (it reads everyone as dead) or trunk mode
#      off, the record of a session whose worktree the new session happens to stand in is not taken
mkkit() {   # mkkit <dir>: a kit copy whose hooks / bin / scripts are the real ones, with its own copy of the gate (it finds its kit from its path)
  mkdir -p "$1/hooks" "$1/bin" "$1/profiles" && ln -s "$DEVKIT_DIR/scripts" "$1/scripts"
  for f in "$DEVKIT_DIR"/hooks/*; do ln -s "$f" "$1/hooks/"; done; rm -f "$1/hooks/worktree_merge_gate.sh" && cp "$HOOK" "$1/hooks/"
  for f in "$DEVKIT_DIR"/bin/*; do ln -s "$f" "$1/bin/"; done
}
gate_in() {   # gate_in <kit> <main> <session> <cwd>: one Stop of that session through that kit's copy of the gate
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"Stop","session_id":sys.argv[1],"cwd":sys.argv[2],"transcript_path":sys.argv[3]}))' "$3" "$4" "$TMP/t1.jsonl" \
    | CLAUDE_PROJECT_DIR="$2" bash "$1/hooks/worktree_merge_gate.sh" > "$TMP/out" 2> "$TMP/err"
}
mkkit "$TMP/kit5"; rm -f "$TMP/kit5/bin/session_lock.py" && echo 'raise ImportError("broken on purpose")' > "$TMP/kit5/bin/session_lock.py"
repo o1; wtadd "$TMP/o1" s0 s0; record "$TMP/o1" s0 s0 "$DEAD"
gate_in "$TMP/kit5" "$TMP/o1" s1b "$TMP/o1/.claude/worktrees/s0"
[ -e "$TMP/o1/.claude/audit-gate/session_worktree/s0" ] && [ ! -e "$TMP/o1/.claude/audit-gate/session_worktree/s1b" ] \
  && ok "session_lock not importable: reown does not move another session's record to the session standing in its worktree" || fail "reown ran with liveness unknown: $(ls "$TMP/o1/.claude/audit-gate/session_worktree")"
repo o2; G "$TMP/o2" config devkit.trunkMode false; wtadd "$TMP/o2" s0 s0; record "$TMP/o2" s0 s0 "$DEAD"
stop "$TMP/o2" s1b "$TMP/o2/.claude/worktrees/s0" "$TMP/t1.jsonl"
[ -e "$TMP/o2/.claude/audit-gate/session_worktree/s0" ] && [ ! -e "$TMP/o2/.claude/audit-gate/session_worktree/s1b" ] \
  && ok "  … trunk mode off: the gate moves no record either" || fail "reown ran outside trunk mode: $(ls "$TMP/o2/.claude/audit-gate/session_worktree")"

# 10a3 a failure inside the trunk block leaves the legacy rules a debt list untouched (OCR 6): the dead session's worktree was added to `owed`
#      first, and when a later step raised, the legacy rules adopted and removed it. Here session_worktree.registered() raises.
mkkit "$TMP/kit6"; rm -f "$TMP/kit6/hooks/session_worktree.py" && cp "$DEVKIT_DIR/hooks/session_worktree.py" "$TMP/kit6/hooks/"
printf '\ndef registered(main, wt):\n    raise RuntimeError("boom")\n' >> "$TMP/kit6/hooks/session_worktree.py"
repo p1; wtadd "$TMP/p1" s9 s9; commit_in "$TMP/p1" s9 nine; record "$TMP/p1" s9 s9 "$DEAD"
wtadd "$TMP/p1" s8 s8; record "$TMP/p1" s8 s8 "$DEAD"; rm -rf "$TMP/p1/.claude/worktrees/s8"   # a second dead record whose folder is gone: registered() runs for it
gate_in "$TMP/kit6" "$TMP/p1" s1 "$TMP/p1"; rc=$?
[ ! -f "$TMP/p1/nine.txt" ] && [ -d "$TMP/p1/.claude/worktrees/s9" ] \
  && ok "the trunk block fails half way: the dead session's worktree is not adopted by the legacy rules" || fail "legacy rules adopted a worktree after the trunk block failed (merged: $( [ -f "$TMP/p1/nine.txt" ] && echo yes || echo no)): err=$(head -c 200 "$TMP/err")"

# 10b the same live idle session, after ANOTHER session's get_active_sessions ran (post-fix-gate --full, --check-last-active): that call used to
#     DELETE the registry entry of a live pid with a heartbeat older than 600 s, and the next Stop adopted the worktree - committed the wip in it,
#     merged it into main and removed it, under the live session (R1 review 14/10). The entry stays; the worktree stays.
repo k; wtadd "$TMP/k" s7 s7; commit_in "$TMP/k" s7 seven; echo wip > "$TMP/k/.claude/worktrees/s7/wip.txt"; record "$TMP/k" s7 s7
python3 -I "$SL" --register --session s7 --pid $$ "$TMP/k" >/dev/null 2>&1
REG="$(G "$TMP/k" rev-parse --absolute-git-dir)/devkit-sessions/s7.json"
python3 -c 'import json,sys,time; d=json.load(open(sys.argv[1])); d["heartbeat"]=time.time()-2400; json.dump(d,open(sys.argv[1],"w"))' "$REG"
python3 -I "$SL" --check-last-active --session s1 "$TMP/k" >/dev/null 2>&1
stop "$TMP/k" s1 "$TMP/k" "$TMP/t1.jsonl"; rc=$?
[ -f "$REG" ] && [ "$rc" = 0 ] && [ -d "$TMP/k/.claude/worktrees/s7" ] && [ ! -f "$TMP/k/seven.txt" ] && [ ! -f "$TMP/k/wip.txt" ] \
  && ok "a live idle session's registry entry survives another session's get_active_sessions: its worktree is not merged, committed or removed" \
  || fail "live session's worktree taken after get_active_sessions (rc $rc, registry $( [ -f "$REG" ] && echo kept || echo DELETED), worktree $( [ -d "$TMP/k/.claude/worktrees/s7" ] && echo kept || echo REMOVED), wip in main: $( [ -f "$TMP/k/wip.txt" ] && echo yes || echo no))"
# … and the second fence: a worktree lock whose pid answers is held by that session whatever its heartbeat says (the gate acts ON its tree)
python3 -I -c 'import os,sys,time; sys.path.insert(0, sys.argv[1]); import session_lock as sl
lk={"session_id":"x","pid":os.getpid(),"heartbeat":time.time()-2400}
assert sl.is_free_for(lk,"me",time.time(),idle_frees=False), "default changed: a 40 min heartbeat no longer frees a live pid"
assert not sl.is_free_for(lk,"me",time.time(),idle_frees=False,live_pid_holds=True), "a live pid was not held"
assert sl.is_free_for(dict(lk,pid=2147483646),"me",time.time(),idle_frees=False,live_pid_holds=True), "a dead pid was not free"' "$DEVKIT_DIR/bin" \
  && ok "  … is_free_for(live_pid_holds): a live pid holds with a 40 min heartbeat, a dead pid is free, the default is unchanged" || fail "is_free_for live_pid_holds"

# 10c a test run holds the tree of an adoptable (dead) session's worktree: it is not merged and removed under the run (the candidate loop
#     did not look at test_run.lock); not a hold either - the next Stop, once the run is over, adopts it
repo l; wtadd "$TMP/l" s6 s6; commit_in "$TMP/l" s6 six; record "$TMP/l" s6 s6
python3 -I "$SL" --register --session s6 --pid 2147483646 "$TMP/l" >/dev/null 2>&1
mkdir -p "$TMP/l/.claude/worktrees/s6/.claude/audit-gate"; rm -f "$TMP/ready"
python3 -c 'import fcntl,os,sys,time; fd=os.open(sys.argv[1],os.O_RDWR|os.O_CREAT,0o600); fcntl.flock(fd,fcntl.LOCK_EX); open(sys.argv[2],"w").close(); time.sleep(60)' \
  "$TMP/l/.claude/worktrees/s6/.claude/audit-gate/test_run.lock" "$TMP/ready" & HOLDER=$!
for _ in $(seq 1 50); do [ -e "$TMP/ready" ] && break; sleep 0.1; done
stop "$TMP/l" s1 "$TMP/l" "$TMP/t1.jsonl"; rc=$?
kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null
[ "$rc" = 0 ] && [ ! -f "$TMP/l/six.txt" ] && [ -d "$TMP/l/.claude/worktrees/s6" ] \
  && ok "a test run holds an adoptable worktree: not merged or removed under the run, the Stop not held" || fail "worktree adopted under a running test (rc $rc, merged: $( [ -f "$TMP/l/six.txt" ] && echo yes || echo no)): out=$(head -c 300 "$TMP/out") err=$(head -c 300 "$TMP/err")"
stop "$TMP/l" s1 "$TMP/l" "$TMP/t1.jsonl"; rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/l/six.txt" ] && [ ! -d "$TMP/l/.claude/worktrees/s6" ] \
  && ok "  … the run over: the next Stop adopts it (merged, removed)" || fail "not adopted after the run (rc $rc): out=$(head -c 300 "$TMP/out") err=$(head -c 300 "$TMP/err")"

# 11 the gate's 13 s alarm passes the Stop SILENTLY (os._exit), so a hold still to be decided after merge_own went with it whenever merge_own was
#    started with the budget nearly spent (R3 review 14/10, P3d). Under 4 s left the own merge is not started: a note, the next Stop merges. The
#    kit copy below raises that 4 s threshold above the 13 s alarm, so merge_own always meets it with less than the threshold left, however fast the
#    runner (a 4 s alarm could go off before merge_own was reached on a slow one: fail_open, no output, a false failure - OCR 8); the real hook
#    (case 1: 13 s alarm, 4 s threshold) still merges.
FK="$TMP/kit11"; mkdir -p "$FK/hooks" "$FK/bin" "$FK/profiles" && ln -s "$DEVKIT_DIR/scripts" "$FK/scripts"
for f in "$DEVKIT_DIR"/hooks/*; do ln -s "$f" "$FK/hooks/"; done; rm -f "$FK/hooks/worktree_merge_gate.sh"
for f in "$DEVKIT_DIR"/bin/*; do ln -s "$f" "$FK/bin/"; done
sed 's/ITIMER_REAL)\[0\] < 4\.0:/ITIMER_REAL)[0] < 99.0:/' "$HOOK" > "$FK/hooks/worktree_merge_gate.sh"
grep -q 'ITIMER_REAL)\[0\] < 99\.0:' "$FK/hooks/worktree_merge_gate.sh" || fail "setup: the threshold of the kit copy was not patched"
repo j; wtadd "$TMP/j" s1 s1; commit_in "$TMP/j" s1 eleven; record "$TMP/j" s1 s1
REAL_HOOK="$HOOK"; HOOK="$FK/hooks/worktree_merge_gate.sh"
stop "$TMP/j" s1 "$TMP/j/.claude/worktrees/s1" "$TMP/t1.jsonl"; rc=$?; HOOK="$REAL_HOOK"
[ "$rc" = 0 ] && [ ! -f "$TMP/j/eleven.txt" ] && grep -q "hết thời gian" "$TMP/out" \
  && ok "alarm budget nearly spent: the own merge is not started (a note, not merged), the Stop is decided before the alarm" \
  || fail "own merge started with the budget spent (rc $rc, merged: $( [ -f "$TMP/j/eleven.txt" ] && echo yes || echo no)): out=$(head -c 300 "$TMP/out") err=$(head -c 300 "$TMP/err")"

# 12 the session's own worktree is dropped from `pending` and merged only when worktree.py imports and WORKTREE_AUTO_MERGE != 0: otherwise it was
#    neither merged nor reported - committed work stayed out of trunk with the Stop passing in silence (OCR 7). Now a note names the command.
repo q1; wtadd "$TMP/q1" s1 s1; commit_in "$TMP/q1" s1 twelve; record "$TMP/q1" s1 s1
stop "$TMP/q1" s1 "$TMP/q1/.claude/worktrees/s1" "$TMP/t1.jsonl" WORKTREE_AUTO_MERGE=0; rc=$?
[ "$rc" = 0 ] && [ ! -f "$TMP/q1/twelve.txt" ] && grep -q 'agent-kit worktree finish .*--keep' "$TMP/out" \
  && ok "own worktree committed, WORKTREE_AUTO_MERGE=0: not merged, a note names agent-kit worktree finish --keep" \
  || fail "auto-merge off, own commit not in main: no note (rc $rc): out=$(head -c 300 "$TMP/out") err=$(head -c 300 "$TMP/err")"
repo q2; wtadd "$TMP/q2" s1 s1; record "$TMP/q2" s1 s1   # nothing committed: nothing owed, so no note at every Stop
stop "$TMP/q2" s1 "$TMP/q2/.claude/worktrees/s1" "$TMP/t1.jsonl" WORKTREE_AUTO_MERGE=0; rc=$?
[ "$rc" = 0 ] && [ ! -s "$TMP/out" ] && ok "  … nothing committed in it: no note" || fail "a note for a worktree with nothing to merge (rc $rc): out=$(head -c 300 "$TMP/out")"
mkkit "$TMP/kit12"; rm -f "$TMP/kit12/scripts"; mkdir -p "$TMP/kit12/scripts/git"   # a kit whose worktree.py cannot be imported (its own copy of scripts/)
for f in "$DEVKIT_DIR"/scripts/*; do [ "$(basename "$f")" = git ] || ln -s "$f" "$TMP/kit12/scripts/"; done
for f in "$DEVKIT_DIR"/scripts/git/*; do ln -s "$f" "$TMP/kit12/scripts/git/"; done
rm -f "$TMP/kit12/scripts/git/worktree.py" && echo 'raise ImportError("broken on purpose")' > "$TMP/kit12/scripts/git/worktree.py"
repo q3; wtadd "$TMP/q3" s1 s1; commit_in "$TMP/q3" s1 twelve; record "$TMP/q3" s1 s1
gate_in "$TMP/kit12" "$TMP/q3" s1 "$TMP/q3/.claude/worktrees/s1"; rc=$?
[ "$rc" = 0 ] && [ ! -f "$TMP/q3/twelve.txt" ] && grep -q 'agent-kit worktree finish .*--keep' "$TMP/out" \
  && ok "  … worktree.py not importable: the same note" || fail "worktree.py not importable, own commit not in main: no note (rc $rc): out=$(head -c 300 "$TMP/out") err=$(head -c 300 "$TMP/err")"

# 13 the 13 s alarm going off INSIDE merge_own: its git calls (the HEAD read and the is-ancestor test, 5 s timeouts of their own) can outlast what is
#    left, and the alarm's os._exit(0) then passes the Stop in silence although a hold is due (second review 14/10, R4b). The alarm now unwinds
#    merge_own into a note and the hold survives. A git shim stalls exactly those two calls for 4 s each; the kit copy's alarm is 7 s, so it
#    goes off during the second one (the entry check, 4 s left, still passes: the first call starts with about 6 s).
FK="$TMP/kit13"; mkkit "$FK"; sed 's/signal\.alarm(13)/signal.alarm(7)/' "$HOOK" > "$FK/hooks/worktree_merge_gate.sh"
grep -q 'signal\.alarm(7)' "$FK/hooks/worktree_merge_gate.sh" || fail "setup: the alarm of the kit copy was not patched"
repo r1; wtadd "$TMP/r1" s1 s1; commit_in "$TMP/r1" s1 own; record "$TMP/r1" s1 s1
wtadd "$TMP/r1" s8 s8; commit_in "$TMP/r1" s8 eight; record "$TMP/r1" s8 s8 "$DEAD"; rm -rf "$TMP/r1/.claude/worktrees/s8"   # a dead session's vanished worktree: a hold that needs no merge
SHIM="$TMP/shim13"; mkdir -p "$SHIM"; OWNSHA="$(G "$TMP/r1/.claude/worktrees/s1" rev-parse HEAD)"
printf '#!/bin/bash\ncase "$*" in\n  "-C %s rev-parse HEAD"|"-C %s merge-base --is-ancestor %s HEAD") sleep 4;;\nesac\nexec "%s" "$@"\n' \
  "$TMP/r1/.claude/worktrees/s1" "$TMP/r1" "$OWNSHA" "$(command -v git)" > "$SHIM/git"; chmod +x "$SHIM/git"
PATH="$SHIM:$PATH" gate_in "$FK" "$TMP/r1" s1 "$TMP/r1/.claude/worktrees/s1"; rc=$?
[ "$rc" = 2 ] && grep -q "$TMP/r1/.claude/worktrees/s8" "$TMP/err" && grep -q "hết thời gian của cổng giữa lúc gộp" "$TMP/err" && [ ! -f "$TMP/r1/own.txt" ] \
  && ok "the alarm goes off inside merge_own: the own merge gives up with a note, the hold that was due still holds (rc 2)" \
  || fail "the alarm inside merge_own lost the hold (rc $rc, merged: $( [ -f "$TMP/r1/own.txt" ] && echo yes || echo no)): out=$(head -c 300 "$TMP/out") err=$(head -c 300 "$TMP/err")"

# 14 the session owns a committed worktree AND owes another one that holds the Stop (OCR 14): the own merge still runs and its note is in the hold
#    text on stderr. The other worktree (x, made by this session) conflicts with a later commit on main - one that merged cleanly would not hold -
#    so the gate's automerge cannot land it. Then the two hold paths where the own merge does NOT run: its budget spent, auto-merge off.
mkhold() {   # mkhold <name>: a main checkout with the own worktree s1 (committed) and x, whose commit conflicts with main's; x is named in $TMP/t14-<name>.jsonl
  repo "$1"; wtadd "$TMP/$1" s1 s1; commit_in "$TMP/$1" s1 own; record "$TMP/$1" s1 s1
  wtadd "$TMP/$1" x s1; echo wt > "$TMP/$1/.claude/worktrees/x/a.txt"; G "$TMP/$1/.claude/worktrees/x" commit -qam x
  echo main > "$TMP/$1/a.txt"; G "$TMP/$1" commit -qam m; transcript "$TMP/t14-$1.jsonl" "$TMP/$1/.claude/worktrees/x"
}
mkhold u1
stop "$TMP/u1" s1 "$TMP/u1/.claude/worktrees/s1" "$TMP/t14-u1.jsonl"; rc=$?
[ "$rc" = 2 ] && [ -f "$TMP/u1/own.txt" ] && [ "$(cat "$TMP/u1/a.txt")" = main ] && grep -q "đã gộp worktree phiên vào main" "$TMP/err" && grep -q "worktrees/x" "$TMP/err" \
  && ok "own worktree merged AND another held: rc 2, the own-merge note in the hold text, main got the own commit and not the conflicting one" \
  || fail "own merge + another hold (rc $rc, own in main: $( [ -f "$TMP/u1/own.txt" ] && echo yes || echo no)): err=$(head -c 500 "$TMP/err")"
mkhold u2; REAL_HOOK="$HOOK"; HOOK="$TMP/kit11/hooks/worktree_merge_gate.sh"   # kit11: the threshold above the alarm, so merge_own meets it with the budget spent
stop "$TMP/u2" s1 "$TMP/u2/.claude/worktrees/s1" "$TMP/t14-u2.jsonl"; rc=$?; HOOK="$REAL_HOOK"
[ "$rc" = 2 ] && [ ! -f "$TMP/u2/own.txt" ] && grep -q "hết thời gian" "$TMP/err" && grep -q "worktrees/x" "$TMP/err" \
  && ok "  … the own merge skipped, its budget spent: still rc 2, the budget note in the hold text, main without the own commit" \
  || fail "budget spent with another hold (rc $rc, own in main: $( [ -f "$TMP/u2/own.txt" ] && echo yes || echo no)): err=$(head -c 500 "$TMP/err")"
mkhold u3
stop "$TMP/u3" s1 "$TMP/u3/.claude/worktrees/s1" "$TMP/t14-u3.jsonl" WORKTREE_AUTO_MERGE=0; rc=$?
[ "$rc" = 2 ] && [ ! -f "$TMP/u3/own.txt" ] && grep -qF "agent-kit worktree finish $TMP/u3/.claude/worktrees/s1 --keep" "$TMP/err" && grep -q "worktrees/x" "$TMP/err" \
  && ok "  … WORKTREE_AUTO_MERGE=0: still rc 2, the note names agent-kit worktree finish --keep for the own worktree, main without the own commit" \
  || fail "auto-merge off with another hold (rc $rc, own in main: $( [ -f "$TMP/u3/own.txt" ] && echo yes || echo no)): err=$(head -c 500 "$TMP/err")"
# 14b the hold cap (3 holds on one list, then the Stop passes with a systemMessage) must not drop the own-worktree note either (OCR2 4): the failed
#     merge, the conflict and the WORKTREE_AUTO_MERGE=0 hint went silent exactly when the session stops for good
mkhold u4
for i in 1 2 3; do
  stop "$TMP/u4" s1 "$TMP/u4/.claude/worktrees/s1" "$TMP/t14-u4.jsonl" WORKTREE_AUTO_MERGE=0; rc=$?; [ "$rc" = 2 ] || fail "u4 hold $i of 3 (rc $rc): $(head -c 300 "$TMP/err")"
done
stop "$TMP/u4" s1 "$TMP/u4/.claude/worktrees/s1" "$TMP/t14-u4.jsonl" WORKTREE_AUTO_MERGE=0; rc=$?
[ "$rc" = 0 ] && grep -q "systemMessage" "$TMP/out" && grep -qF "worktrees/x" "$TMP/out" && grep -qF "agent-kit worktree finish $TMP/u4/.claude/worktrees/s1 --keep" "$TMP/out" \
  && ok "  … the hold cap reached: the Stop passes, and the systemMessage still carries the own-worktree note (finish --keep)" \
  || fail "cap-path message without the own-worktree note (rc $rc): out=$(head -c 600 "$TMP/out") err=$(head -c 200 "$TMP/err")"

# 15 session_lock not importable and a worktree whose state names ANOTHER session (OCR2 20): "that session may be alive" was assumed for every
#    such worktree, also one this repo already owes - legacy mode then dropped it and passed the Stop in silence with the work unintegrated,
#    against the gate's own rule (no session_lock: MORE worktrees count as ours, held and capped). Trunk mode, which merges and removes on
#    proof of death, keeps its hands off it.
owed_state() {   # owed_state <main> <worktree name>: the debt an earlier Stop saved (this worktree owed, no owner recorded)
  mkdir -p "$1/.claude/audit-gate" && python3 -c 'import json,os,sys; json.dump({"owed":[os.path.realpath(sys.argv[2])],"owners":{},"sessions":{}}, open(sys.argv[1],"w"))' \
    "$1/.claude/audit-gate/worktree_merge_gate.state" "$1/.claude/worktrees/$2"
}
repo w1; G "$TMP/w1" config devkit.trunkMode false; wtadd "$TMP/w1" s9 s9; commit_in "$TMP/w1" s9 nine; owed_state "$TMP/w1" s9
gate_in "$TMP/kit5" "$TMP/w1" s1 "$TMP/w1"; rc=$?
[ "$rc" = 2 ] && grep -q "worktrees/s9" "$TMP/err" && [ -d "$TMP/w1/.claude/worktrees/s9" ] \
  && ok "no session_lock, trunk mode off: an owed worktree whose state names another session still holds the Stop" \
  || fail "owed worktree of another session dropped without session_lock (rc $rc): out=$(head -c 300 "$TMP/out") err=$(head -c 300 "$TMP/err")"
repo w2; wtadd "$TMP/w2" s9 s9; commit_in "$TMP/w2" s9 nine; owed_state "$TMP/w2" s9
gate_in "$TMP/kit5" "$TMP/w2" s1 "$TMP/w2"; rc=$?
[ "$rc" = 0 ] && [ ! -f "$TMP/w2/nine.txt" ] && [ -d "$TMP/w2/.claude/worktrees/s9" ] \
  && ok "  … trunk mode on: hands off (no proof of death), nothing merged, nothing held" || fail "trunk mode took another session's worktree without session_lock (rc $rc): err=$(head -c 300 "$TMP/err")"

echo
[ "$FAILS" -eq 0 ] && { echo "test_worktree_merge_gate_trunk: PASS"; exit 0; } || { echo "test_worktree_merge_gate_trunk: FAIL ($FAILS)"; exit 1; }
