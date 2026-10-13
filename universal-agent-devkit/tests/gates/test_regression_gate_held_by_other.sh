#!/usr/bin/env bash
# hooks/regression_gate.sh, a checkout held by ANOTHER live session (2026-10-13, /devkit-audit item 3, Stop false blocks): session
# 2836c3d3 held the workbench and worked TDD-style (a RED test in the tree), while this session — read-only there, no file changed —
# was blocked at five Stops (08:45 to 09:20) by that other session's in-progress diff: commits it had pushed earlier were
# "unverified" (verified_head only moves on a hook-run PASS), which turns off the work-in-progress skip, and the gate ran over the
# whole shared tree. A read-only session has nothing to hand over: it cannot write or push while the lock is held, and verified_head
# is shared, so the holder's next handover gates the same verified_head..HEAD range (it did, 09:39). The Stop of a session that does
# NOT hold the checkout, while another live and active session does, now runs nothing and says so in the log.
# Still gated: no lock, this session's own lock, a stale lock, an idle holder, a dead holder process.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${RG_HOOK:-$DEVKIT_DIR/hooks/regression_gate.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
REPO="$TMP/repo"
stop() { printf '{"session_id":"s-1","hook_event_name":"Stop"}' \
  | REGRESSION_GATE_MAX_SESSION_BLOCKS=99 CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }   # no session cap here
lock() {   # lock <session id> <heartbeat age s> <pid> [idle]
  python3 -c 'import json,sys,time; age=float(sys.argv[2]); d={"session_id":sys.argv[1],"started":time.time()-age-5,
"heartbeat":time.time()-age,"cwd":sys.argv[4],"pid":int(sys.argv[3]),"gitdir":sys.argv[4]+"/.git"}
if len(sys.argv)>5: d["idle_since"]=time.time()-1
json.dump(d,open(sys.argv[4]+"/.git/devkit-session.lock","w"))' "$1" "$2" "$3" "$REPO" ${4:+idle}
}
N=0
change() { N=$((N + 1)); echo "fun ok() = $N" > src/Core.kt; }

mkdir -p "$REPO/src" "$REPO/templates" && cd "$REPO" || exit 1
git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
echo "fun ok() = 0" > src/Core.kt
cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core flow","command":"sh result.sh"}]}]}
JSON
echo 'exit 1' > result.sh
git add -A && git commit -qm init

# control: a failing related suite blocks the Stop
change; stop; rc=$?
[ "$rc" = 2 ] && ok "no lock: the failing suite blocks (rc 2)" || fail "no lock: rc $rc (want 2)"

# the checkout is held by another live, active session: this read-only session runs nothing
change; lock other-session 1 $$; stop; rc=$?
[ "$rc" = 0 ] && ok "held by another live session: the Stop runs nothing (rc 0)" || fail "held by another live session: rc $rc (want 0)"
grep -q 'held by another live session' .claude/audit-gate/regression_gate.log \
  && ok "... and the log says why" || fail "no log line for the held-by-another skip"

# still gated
change; lock s-1 1 $$; stop; rc=$?
[ "$rc" = 2 ] && ok "this session holds the lock: still gated (rc 2)" || fail "own lock: rc $rc (want 2)"
change; lock other-session 7200 $$; stop; rc=$?
[ "$rc" = 2 ] && ok "a stale lock (2 h without heartbeat): still gated (rc 2)" || fail "stale lock: rc $rc (want 2)"
change; lock other-session 1 $$ idle; stop; rc=$?
[ "$rc" = 2 ] && ok "an idle holder (waits for the user): still gated (rc 2)" || fail "idle holder: rc $rc (want 2)"
change; lock other-session 1 999999; stop; rc=$?
[ "$rc" = 2 ] && ok "a dead holder process: still gated (rc 2)" || fail "dead holder: rc $rc (want 2)"
rm -f .git/devkit-session.lock
change; stop; rc=$?
[ "$rc" = 2 ] && ok "lock gone again: gated (rc 2)" || fail "after the lock: rc $rc (want 2)"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
