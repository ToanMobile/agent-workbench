#!/usr/bin/env bash
# Regression test (audit 2026-10-09): Claude Code runs every hook as `/bin/sh -c 'bash "…/session_lock.sh"'`. On macOS /bin/sh is
# bash, which execs that last command, so the lock recorded the claude process (getppid). On Linux /bin/sh is dash: it forks bash and
# stays as a short-lived parent, the lock recorded THAT pid, it was dead at the next call and every other session read the checkout
# as free: a second live session's Edit passed and --status said free. The holder must be the long-lived process above the sh.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/session_lock.sh"
export DEVKIT_SCRATCH_CLEANUP=0   # never prune the real /tmp/claude-<uid> from a test
TMP="$(mktemp -d)"
A_PID=""
trap '[ -n "$A_PID" ] && kill "$A_PID" 2>/dev/null; rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
REPO="$TMP/repo"
mkdir -p "$REPO/src" && git -C "$REPO" init -q . && echo x > "$REPO/src/A.kt"
git -C "$REPO" -c user.email=t@t -c user.name=t add -A >/dev/null && git -C "$REPO" -c user.email=t@t -c user.name=t commit -qm init

# The way Claude Code runs a hook: a long-lived parent (here python, standing in for claude) -> /bin/sh -c 'bash "<hook>"'.
# Session A runs one Edit hook, writes its exit code, then stays alive like a session at work.
python3 - "$HOOK" "$REPO" "$TMP/a.rc" <<'PY' &
import json, os, subprocess, sys, time
hook, repo, rcf = sys.argv[1:4]
d = {"session_id": "A", "hook_event_name": "PreToolUse", "cwd": repo, "tool_name": "Edit",
     "tool_input": {"file_path": repo + "/src/A.kt"}}
r = subprocess.run(["/bin/sh", "-c", 'bash "$SL_HOOK"'], input=json.dumps(d), text=True, capture_output=True,
                   env=dict(os.environ, SL_HOOK=hook, CLAUDE_PROJECT_DIR=repo))
with open(rcf + ".tmp", "w") as f:
    f.write(str(r.returncode))
os.replace(rcf + ".tmp", rcf)
time.sleep(120)
PY
A_PID=$!
for _ in $(seq 1 200); do [ -s "$TMP/a.rc" ] && break; sleep 0.05; done
[ "$(cat "$TMP/a.rc" 2>/dev/null)" = 0 ] && ok "session A (hook under /bin/sh -c) takes the checkout" || fail "session A's Edit: rc=$(cat "$TMP/a.rc" 2>/dev/null)"

# hook_b <tool> : session B, also under /bin/sh -c, from this test (alive throughout)
hook_b() {
  printf '{"session_id":"B","hook_event_name":"PreToolUse","cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s/src/A.kt"}}' \
    "$REPO" "$REPO" > "$TMP/b.json"
  SL_HOOK="$HOOK" CLAUDE_PROJECT_DIR="$REPO" /bin/sh -c 'bash "$SL_HOOK"' < "$TMP/b.json" > "$TMP/b.out" 2> "$TMP/b.err"
}
hook_b; rc=$?
[ "$rc" = 2 ] && ok "a second live session's Edit is blocked while A is alive" \
  || fail "second session's Edit passed (rc=$rc): the lock holder pid was the short-lived /bin/sh, not session A"
python3 "$DEVKIT_DIR/bin/session_lock.py" --status --session B "$REPO" > "$TMP/st.out" 2>&1; rc=$?
[ "$rc" = 3 ] && ok "--status for B: held by live session A (exit 3)" || fail "--status for B: rc=$rc (want 3) $(cat "$TMP/st.out")"

kill "$A_PID" 2>/dev/null; wait "$A_PID" 2>/dev/null; A_PID=""
hook_b; rc=$?
[ "$rc" = 0 ] && ok "once session A's process is gone the checkout is free for B" \
  || fail "B still blocked after A ended (rc=$rc): $(cat "$TMP/b.err")"

[ "$FAILS" -eq 0 ] && echo "✅ test_session_lock_sh_parent: all passed" || { echo "❌ test_session_lock_sh_parent: $FAILS failed"; exit 1; }
