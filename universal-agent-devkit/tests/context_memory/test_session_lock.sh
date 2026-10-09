#!/usr/bin/env bash
# Regression test (GeelyEx2 2026-09-29, owner: "một phiên một lúc trên thư mục này"): two Claude sessions worked in one
# checkout. The full gate of one ran 9 times; twice it passed but wrote no receipt because the OTHER session changed
# files mid-run, and push_gate then blocked the push. hooks/session_lock.sh: one agent session per checkout (per git
# dir — a linked worktree is its own checkout). The holder works; another live session is read-only: its
# Edit/Write/MultiEdit/NotebookEdit and its git-write / post-fix-gate Bash calls are blocked, reads and builds pass.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/session_lock.sh"
export DEVKIT_SCRATCH_CLEANUP=0   # these cases run the real session hooks: never prune the real /tmp/claude-<uid> (review 2026-10-09)
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
REPO="$TMP/repo"
mkdir -p "$REPO/src" && git -C "$REPO" init -q . && echo x > "$REPO/src/A.kt"
git -C "$REPO" -c user.email=t@t -c user.name=t add -A >/dev/null && git -C "$REPO" -c user.email=t@t -c user.name=t commit -qm init
mkdir -p "$TMP/plain"

# hook <session> <event> <tool> <cwd> [bash command]
hook() {
  python3 - "$@" <<'PY' > "$TMP/in.json"
import json, sys
sid, ev, tool, cwd = sys.argv[1:5]
d = {"session_id": sid, "hook_event_name": ev, "cwd": cwd}
if tool:
    d["tool_name"] = tool
    d["tool_input"] = {"command": sys.argv[5]} if tool == "Bash" else {"file_path": cwd + "/src/A.kt"}
print(json.dumps(d))
PY
  CLAUDE_PROJECT_DIR="$4" bash "$HOOK" < "$TMP/in.json" > "$TMP/out" 2> "$TMP/err"
}

hook A PreToolUse Edit "$REPO"; [ $? = 0 ] && ok "first session edits: takes the checkout" || fail "first edit blocked: $(cat "$TMP/err")"
hook B PreToolUse Edit "$REPO"; rc=$?
[ "$rc" = 2 ] && grep -q "A" "$TMP/err" && ok "a second live session's Edit is blocked, naming the holder" \
  || fail "second session edit not blocked (rc=$rc): $(cat "$TMP/err")"
hook B PreToolUse Write "$REPO"; [ $? = 2 ] && ok "  … Write too" || fail "second session Write passed"
hook B PreToolUse Bash "$REPO" "ls -la src && git status --short"; [ $? = 0 ] && ok "  … reads (ls, git status) pass" || fail "read-only Bash blocked"
hook B PreToolUse Bash "$REPO" "cd CarConnect && ./gradlew :app:testDebugUnitTest"; [ $? = 0 ] && ok "  … builds/tests pass" || fail "build blocked"
hook B PreToolUse Bash "$REPO" 'git commit -m x -- src/A.kt'; [ $? = 2 ] && ok "  … git commit blocked" || fail "second session commit passed"
hook B PreToolUse Bash "$REPO" 'git push origin main'; [ $? = 2 ] && ok "  … git push blocked" || fail "second session push passed"
hook B PreToolUse Bash "$REPO" 'python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full'; [ $? = 2 ] && ok "  … post-fix-gate blocked" || fail "second session gate passed"
hook B PreToolUse Bash "$REPO" 'echo hi > src/A.kt'; [ $? = 2 ] && ok "  … shell redirect into the checkout blocked" || fail "second session redirect passed"
hook A PreToolUse Edit "$REPO"; [ $? = 0 ] && ok "the holder keeps working" || fail "holder blocked"
hook B SessionStart "" "$REPO"; rc=$?
[ "$rc" = 0 ] && grep -q "A" "$TMP/out" && ok "SessionStart of a second session warns (no block) and names the holder" \
  || fail "SessionStart warning missing (rc=$rc): $(cat "$TMP/out")"

DEVKIT_ALLOW_SHARED_CHECKOUT=1 hook B PreToolUse Edit "$REPO"; [ $? = 0 ] && ok "DEVKIT_ALLOW_SHARED_CHECKOUT=1 lets it through" || fail "override ignored"
grep -q "B" "$REPO/.git/devkit-session.log" 2>/dev/null && ok "  … and the override is logged" || fail "override not logged"

DEVKIT_SESSION_LOCK_STALE_S=0 hook B PreToolUse Edit "$REPO"; [ $? = 0 ] && ok "a stale lock (no heartbeat) is taken over" || fail "stale lock kept blocking"
hook A PreToolUse Edit "$REPO"; [ $? = 2 ] && ok "  … after which the old holder is the read-only one" || fail "old holder still writes"
hook B SessionEnd "" "$REPO"; [ $? = 0 ] || fail "SessionEnd failed"
hook A PreToolUse Edit "$REPO"; [ $? = 0 ] && ok "SessionEnd of the holder frees the checkout" || fail "lock not released on SessionEnd"

git -C "$REPO" worktree add -q "$TMP/wt" -b wt >/dev/null 2>&1
hook C PreToolUse Edit "$TMP/wt"; [ $? = 0 ] && ok "a linked worktree is its own checkout" || fail "worktree blocked by main lock"
hook D PreToolUse Edit "$TMP/plain"; [ $? = 0 ] && ok "not a git repo: not its business" || fail "plain dir blocked"

# --status (2026-09-29): Antigravity has no hook API, so it cannot be blocked — it asks. Read-only:
# exit 3 while another live session holds the checkout, 0 when free / stale / its own / not a repo.
LOCKF="$REPO/.git/devkit-session.lock"
before="$(cat "$LOCKF" 2>/dev/null)"
st() { python3 "$DEVKIT_DIR/bin/session_lock.py" --status "$@" > "$TMP/st.out" 2>&1; }
st "$REPO"; rc=$?
[ "$rc" = 3 ] && grep -q "A" "$TMP/st.out" && ok "--status: held by a live session → exit 3, names the holder" || fail "--status held: rc=$rc $(cat "$TMP/st.out")"
( cd "$REPO/src" && python3 "$DEVKIT_DIR/bin/session_lock.py" --status > /dev/null 2>&1 ); rc=$?
[ "$rc" = 3 ] && ok "--status with no dir checks the current directory's checkout" || fail "--status cwd: rc=$rc"
st --session A "$REPO"; [ $? = 0 ] && ok "--status --session <holder> → exit 0 (its own lock)" || fail "--status own: $(cat "$TMP/st.out")"
DEVKIT_SESSION_LOCK_STALE_S=0 st "$REPO"; [ $? = 0 ] && ok "--status: a stale lock → exit 0 (free)" || fail "--status stale: $(cat "$TMP/st.out")"
st "$TMP/plain"; [ $? = 0 ] && ok "--status: not a git repo → exit 0" || fail "--status plain: $(cat "$TMP/st.out")"
[ "$(cat "$LOCKF" 2>/dev/null)" = "$before" ] && ok "--status is read-only (lock file unchanged)" || fail "--status wrote the lock"
st "$TMP/wt"; rc=$?
[ "$rc" = 3 ] && grep -q "phiên C" "$TMP/st.out" && ! grep -q "phiên A" "$TMP/st.out" \
  && ok "--status: a linked worktree reports its own holder (C), not the main checkout's (A)" || fail "--status worktree: rc=$rc $(cat "$TMP/st.out")"

# Idle holder (user, 2026-10-09: "phiên đó ngừng chạy thì là ok rồi chứ sao bắt phải /exit"): a session that finished its
# turn and waits at the prompt is a live process, so the pid check kept its lock for the whole 600 s heartbeat window and the
# user had to /exit it. Claude Code's Notification `idle_prompt` (~60 s after the turn ended, no typing, no background agent)
# marks the holder idle; an idle lock is free for another session. Not Stop: Stop hooks run in parallel, the end-of-turn gate
# among them, and a blocked Stop means the turn goes on.
R2="$TMP/repo2"
mkdir -p "$R2/src" && git -C "$R2" init -q . && echo x > "$R2/src/A.kt"
git -C "$R2" -c user.email=t@t -c user.name=t add -A >/dev/null && git -C "$R2" -c user.email=t@t -c user.name=t commit -qm init
notify() {   # notify <session> <cwd> <notification_type>
  python3 -c 'import json,sys; print(json.dumps({"session_id": sys.argv[1], "hook_event_name": "Notification", "cwd": sys.argv[2],
    "notification_type": sys.argv[3], "message": "Claude is waiting for your input"}))' "$@" > "$TMP/in.json"
  CLAUDE_PROJECT_DIR="$2" bash "$HOOK" < "$TMP/in.json" > "$TMP/out" 2> "$TMP/err"
}
last() { python3 "$DEVKIT_DIR/bin/session_lock.py" --check-last-active --session "$1" "$R2" > /dev/null 2>&1; }
hook A SessionStart "" "$R2"; hook B SessionStart "" "$R2"
hook A PreToolUse Edit "$R2"; [ $? = 0 ] || fail "idle setup: A could not take repo2"
last B; [ $? = 1 ] && ok "idle: a working holder counts as another active session (gate defers --full)" || fail "working A not counted active"
notify A "$R2" permission_prompt; [ $? = 0 ] || fail "Notification hook failed"
hook B PreToolUse Edit "$R2"; [ $? = 2 ] && ok "idle: a permission prompt is not idle — lock kept" || fail "permission_prompt freed the lock"
notify B "$R2" idle_prompt
hook B PreToolUse Edit "$R2"; [ $? = 2 ] && ok "idle: a NON-holder going idle frees nothing" || fail "B's own idle freed A's lock"
GATE_STATE="$R2/.claude/audit-gate"; mkdir -p "$GATE_STATE"
python3 -c 'import fcntl,sys,time; f=open(sys.argv[1],"a"); fcntl.flock(f, fcntl.LOCK_EX); open(sys.argv[2],"w").close(); time.sleep(30)' \
  "$GATE_STATE/test_run.lock" "$TMP/flock.ready" & FL=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -f "$TMP/flock.ready" ] && break; python3 -c 'import time; time.sleep(0.1)'; done
notify A "$R2" idle_prompt
hook B PreToolUse Edit "$R2"; [ $? = 2 ] && ok "idle: not marked while an end-of-turn test run holds test_run.lock" || fail "idle marked during a gate run"
kill "$FL" 2>/dev/null; wait "$FL" 2>/dev/null
notify A "$R2" idle_prompt
st "$R2"; [ $? = 0 ] && ok "idle: --status reports an idle holder's checkout as free" || fail "--status idle: $(cat "$TMP/st.out")"
last B; [ $? = 0 ] && ok "idle: an idle session is not an active sibling (the gate may run --full)" || fail "idle A still counted active"
hook A PreToolUse Edit "$R2"; [ $? = 0 ] && ok "idle: the holder's next tool call resumes it" || fail "idle holder blocked on its own lock"
hook B PreToolUse Edit "$R2"; [ $? = 2 ] && ok "  … and the lock is held again (idle cleared despite the 30 s heartbeat throttle)" || fail "resumed holder's lock still idle"
last B; [ $? = 1 ] && ok "  … and it is an active sibling again" || fail "resumed A not counted active"
notify A "$R2" idle_prompt
hook B PreToolUse Bash "$R2" "ls src"; n0="$(grep -c "B nhận khoá của A" "$R2/.git/devkit-session.log" 2>/dev/null)"
[ "${n0:-0}" = 0 ] && ok "idle: a read-only call on an idle lock takes nothing and logs no takeover" || fail "phantom takeover logged ($n0)"
hook B PreToolUse Edit "$R2"; [ $? = 0 ] && ok "idle: another session's write takes an idle holder's checkout" || fail "idle lock still blocks: $(cat "$TMP/err")"
grep -q "B nhận khoá của A" "$R2/.git/devkit-session.log" 2>/dev/null && ok "  … logged" || fail "idle takeover not logged"
hook A PreToolUse Edit "$R2"; [ $? = 2 ] && ok "  … after which the old holder is the read-only one" || fail "old idle holder still writes"
notify B "$R2" idle_prompt
holder() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["session_id"])' "$R2/.git/devkit-session.lock"; }
hook C SessionStart "" "$R2"
! grep -q "CHỈ ĐỌC" "$TMP/out" && [ "$(holder)" = B ] \
  && ok "idle: a new session over an idle lock gets no read-only warning and takes nothing before it writes" || fail "SessionStart over idle: holder=$(holder) $(cat "$TMP/out")"
hook B PreToolUse Edit "$R2"; [ $? = 0 ] && ok "  … so the idle holder coming back still works (a session opened and never prompted never goes idle)" || fail "SessionStart stole an idle lock"
hook C PreToolUse Edit "$R2"; [ $? = 2 ] && ok "  … and the new session's write is then blocked by the working holder" || fail "C wrote over a working B"
# Audit T0021 (Antigravity): the idle hook read the lock at its start and wrote that dict back with idle_since — a take() by the
# holder resuming in between (fresh heartbeat, no idle mark) was overwritten and the WORKING holder marked idle. Now compare-then-write.
R3="$TMP/repo3"; mkdir -p "$R3" && git -C "$R3" init -q .
hook A SessionStart "" "$R3"; hook A PreToolUse Edit "$R3"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["heartbeat"]-=120; json.dump(d,open(p,"w"))' "$R3/.git/devkit-session.lock"
race="$(python3 -I - "$DEVKIT_DIR/bin" "$R3" <<'PY'
import io, json, os, sys, time
sys.path.insert(0, sys.argv[1])
import session_lock as sl
repo = sys.argv[2]
path = os.path.join(repo, ".git", sl.LOCK)
orig = sl.mark_idle_session
def racing(cwd, sid, **kw):   # the holder resumes while its idle hook runs: its PreToolUse take() lands right here
    orig(cwd, sid, **kw)
    sl.take(path, sl.read_lock(path), sid, cwd, time.time())
sl.mark_idle_session = racing
sys.stdin = io.StringIO(json.dumps({"session_id": "A", "hook_event_name": "Notification", "cwd": repo, "notification_type": "idle_prompt"}))
sl.main()
print("idle" if sl.read_lock(path).get("idle_since") else "working")
PY
)"
[ "$race" = working ] && ok "idle: a holder that resumed while its idle hook ran is not marked idle (compare-then-write)" || fail "race: resumed holder marked $race"
# Audit T0021 round 2: the same resume landing BEFORE the registry write (PreToolUse: heartbeat_session + take) left the lock working but
# the registry entry "idle" — the gate and session_authorship then treated a working session as gone. The registry write compares too.
R4="$TMP/repo4"; mkdir -p "$R4" && git -C "$R4" init -q .
hook A SessionStart "" "$R4"; hook A PreToolUse Edit "$R4"
python3 -c 'import json,sys
for p in sys.argv[1:]:
    d=json.load(open(p)); d["heartbeat"]-=120; json.dump(d,open(p,"w"))' "$R4/.git/devkit-session.lock" "$R4/.git/devkit-sessions/A.json"
race2="$(python3 -I - "$DEVKIT_DIR/bin" "$R4" <<'PY'
import io, json, os, sys, time
sys.path.insert(0, sys.argv[1])
import session_lock as sl
repo = sys.argv[2]
path = os.path.join(repo, ".git", sl.LOCK)
orig = sl.test_run_active
def resume_first(dirs):   # the holder resumes after the hook read its state, before any idle write: its PreToolUse runs here
    sl.heartbeat_session(repo, "A")
    sl.take(path, sl.read_lock(path), "A", repo, time.time())
    return orig(dirs)
sl.test_run_active = resume_first
sys.stdin = io.StringIO(json.dumps({"session_id": "A", "hook_event_name": "Notification", "cwd": repo, "notification_type": "idle_prompt"}))
sl.main()
reg = json.load(open(os.path.join(repo, ".git", "devkit-sessions", "A.json")))
print(("idle" if sl.read_lock(path).get("idle_since") else "working") + "/" + str(reg.get("status")))
PY
)"
[ "$race2" = working/working ] && ok "  … and a resume before the registry write leaves lock AND registry working" || fail "race2: lock/registry = $race2"

# A copied checkout (2026-10-09: AGENTS.md §7.1 says integrate around another session's files in a `cp -Rc` copy) carries the
# original's lock file in its .git: the copy was "held" by the original's live holder for up to 600 s. A lock whose cwd is not
# inside this checkout belongs to the checkout it was copied from: not a holder here.
R5="$TMP/repo5"; mkdir -p "$R5/src" && git -C "$R5" init -q . && echo x > "$R5/src/A.kt"
hook A PreToolUse Edit "$R5"; [ $? = 0 ] || fail "copy setup: A could not take repo5"
cp -R "$R5" "$TMP/repo5-copy"
st "$TMP/repo5-copy"; [ $? = 0 ] && ok "copy: --status of a copied checkout says free (the copied lock is the original's)" || fail "--status copy: $(cat "$TMP/st.out")"
hook B PreToolUse Edit "$TMP/repo5-copy"; [ $? = 0 ] && ok "  … and a write there takes it" || fail "copied lock blocks the copy: $(cat "$TMP/err")"
hook B PreToolUse Edit "$R5"; [ $? = 2 ] && ok "  … while the original checkout stays held by its live holder" || fail "original lost its holder"
cp -R "$R5" "$TMP/repo5-copy2"
hook C PreToolUse Bash "$R2" "cd $TMP/repo5-copy2 && git commit -m x"; [ $? = 0 ] && ok "  … and a git write aimed at a copy from ANOTHER checkout is not judged by the copied lock" || fail "foreign copied lock blocks: $(cat "$TMP/err")"
# Review 2026-10-09 (P2): judged by the lock's cwd STRING, a holder whose cwd differs only in letter case (APFS is case-insensitive) read as
# "copied" and lost its live lock to the next writer. The lock records its git dir and is compared by inode (os.path.samefile).
R6="$TMP/repo6"; mkdir -p "$R6/src" && git -C "$R6" init -q . && echo x > "$R6/src/A.kt"
if [ -d "$TMP/REPO6" ]; then
  python3 -c 'import json,sys; print(json.dumps({"session_id": "A", "hook_event_name": "PreToolUse", "cwd": sys.argv[1], "tool_name": "Edit",
    "tool_input": {"file_path": sys.argv[2] + "/src/A.kt"}}))' "$TMP/REPO6" "$R6" > "$TMP/in.json"
  CLAUDE_PROJECT_DIR="$TMP/REPO6" bash "$HOOK" < "$TMP/in.json" > "$TMP/out" 2> "$TMP/err"
  [ -f "$R6/.git/devkit-session.lock" ] || fail "case setup: A (cwd in other letter case) took no lock"
  hook B PreToolUse Edit "$R6"; [ $? = 2 ] && ok "copy: a live holder whose cwd differs only in letter case still holds the checkout" || fail "case-only cwd difference freed a live holder"
else
  ok "copy: case-insensitive check skipped (case-sensitive filesystem)"
fi

[ "$FAILS" -eq 0 ] && echo "✅ test_session_lock: all passed" || { echo "❌ test_session_lock: $FAILS failed"; exit 1; }
