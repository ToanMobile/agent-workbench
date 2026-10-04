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

[ "$FAILS" -eq 0 ] && echo "✅ test_session_lock: all passed" || { echo "❌ test_session_lock: $FAILS failed"; exit 1; }
