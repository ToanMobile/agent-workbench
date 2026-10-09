#!/usr/bin/env bash
# Regression test (audit 2026-10-09) for bin/session_lock.py:
#  D1 two sessions whose first write hooks start together were BOTH allowed (19 of 20 runs): read-decide-write was not
#     atomic. An exclusive flock on a sidecar file now covers it; a write that cannot get it in time is blocked.
#  D5 a `>` inside quotes or a data heredoc was read as a redirect: `grep -n "a > b" f`, `git log --format='%h -> %s'`,
#     `python3 -c "print(1>0)"` were blocked (exit 2) for a second live session. Real redirects into the checkout still are.
#  D6 a JSON-array payload and a non-numeric heartbeat (lock or registry) crashed the hook and --status with a traceback
#     (exit 1: the write went ahead). Now: a payload that is not an object is a no-op (exit 0, like unparsable JSON); a
#     heartbeat that is not a number counts as missing, i.e. stale (as before for a lock with no heartbeat).
#  D7 the git dir is found without spawning git for plain layouts: same answer as git for a main checkout, a subdirectory,
#     a linked worktree, a submodule, a non-repo, GIT_DIR in the environment.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/session_lock.sh"
SL="$DEVKIT_DIR/bin/session_lock.py"
export DEVKIT_SCRATCH_CLEANUP=0   # these cases run the real session hooks: never prune the real /tmp/claude-<uid>
TMP="$(mktemp -d)"
HOLD_PID=""
trap '[ -n "$HOLD_PID" ] && kill "$HOLD_PID" 2>/dev/null; rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
newrepo() {   # newrepo <dir>
  mkdir -p "$1/src" && git -C "$1" init -q . && git -C "$1" config user.email t@t && git -C "$1" config user.name t \
    && git -C "$1" config commit.gpgsign false && echo x > "$1/src/A.kt" && git -C "$1" add -A && git -C "$1" commit -qm init
}
REPO="$TMP/repo"; newrepo "$REPO"
GDIR="$REPO/.git"

# payload <file> <session> <tool> [bash command]   (PreToolUse; Edit targets src/A.kt)
payload() {
  python3 - "$@" "$REPO" <<'PY'
import json, sys
args = sys.argv[1:]
out, sid, tool, repo = args[0], args[1], args[2], args[-1]
d = {"session_id": sid, "hook_event_name": "PreToolUse", "cwd": repo, "tool_name": tool,
     "tool_input": {"command": args[3]} if tool == "Bash" else {"file_path": repo + "/src/A.kt"}}
open(out, "w").write(json.dumps(d))
PY
}
run_hook() {   # run_hook <payload file> : rc, stderr in $TMP/err
  CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" < "$1" > "$TMP/out" 2> "$TMP/err"
}
reset_lock() { rm -f "$GDIR/devkit-session.lock"; rm -rf "$GDIR/devkit-sessions"; }

# ── D1: two first writes at the same moment ──────────────────────────────────────────────────────────────────────────
both=0; one=0; rounds=8
for i in $(seq 1 $rounds); do
  reset_lock
  payload "$TMP/a$i.json" "A$i" Edit; payload "$TMP/b$i.json" "B$i" Edit
  CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" < "$TMP/a$i.json" > /dev/null 2> "$TMP/a$i.err" & pa=$!
  CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" < "$TMP/b$i.json" > /dev/null 2> "$TMP/b$i.err" & pb=$!
  wait "$pa"; ra=$?; wait "$pb"; rb=$?
  if [ "$ra" = 0 ] && [ "$rb" = 0 ]; then both=$((both + 1)); fi
  if { [ "$ra" = 0 ] && [ "$rb" = 2 ]; } || { [ "$ra" = 2 ] && [ "$rb" = 0 ]; }; then one=$((one + 1)); fi
done
[ "$both" = 0 ] && [ "$one" = "$rounds" ] && ok "D1: two simultaneous first writes: exactly one session gets the checkout ($one/$rounds rounds)" \
  || fail "D1: simultaneous first writes: both allowed in $both of $rounds rounds, exactly one in $one"

# D1: a write that cannot get the guard in time is blocked (fail closed); a read still passes
reset_lock
python3 - "$GDIR" "$TMP/held" <<'PY' &
import fcntl, os, sys, time
fd = os.open(os.path.join(sys.argv[1], "devkit-session.guard"), os.O_RDWR | os.O_CREAT, 0o600)
fcntl.flock(fd, fcntl.LOCK_EX)
open(sys.argv[2], "w").write("1")
time.sleep(8)
PY
HOLD_PID=$!
for _ in $(seq 1 100); do [ -s "$TMP/held" ] && break; sleep 0.05; done
payload "$TMP/w.json" W Edit; payload "$TMP/r.json" R Bash "ls src"
CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" < "$TMP/w.json" > /dev/null 2> "$TMP/w.err" & pw=$!
CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" < "$TMP/r.json" > /dev/null 2> "$TMP/r.err" & pr=$!
wait "$pw"; rw=$?; wait "$pr"; rr=$?
kill "$HOLD_PID" 2>/dev/null; wait "$HOLD_PID" 2>/dev/null; HOLD_PID=""
[ "$rw" = 2 ] && grep -q "devkit-session.guard" "$TMP/w.err" && ok "D1: guard held elsewhere: a write is blocked and the message names the guard file" \
  || fail "D1: write with the guard held: rc=$rw (want 2) $(head -c 300 "$TMP/w.err")"
[ "$rr" = 0 ] && ok "D1: guard held elsewhere: a read (ls) still passes" || fail "D1: read with the guard held: rc=$rr $(head -c 300 "$TMP/r.err")"
[ ! -e "$GDIR/devkit-session.lock" ] && ok "D1: … and neither took the lock without the guard" || fail "D1: a lock was written without the guard: $(cat "$GDIR/devkit-session.lock")"

# ── D5: quotes and heredocs are text; real redirects into the checkout stay blocked ──────────────────────────────────
reset_lock
payload "$TMP/hold.json" A Edit; run_hook "$TMP/hold.json" || fail "D5 setup: A could not take the checkout ($(cat "$TMP/err"))"
b_rc() { payload "$TMP/b.json" B Bash "$1"; run_hook "$TMP/b.json"; echo $?; }
nl='
'
for cmd in 'grep -n "a > b" src/A.kt' "git log --format='%h -> %s'" 'python3 -c "print(1>0)"' \
           "cat <<EOF${nl}a > b${nl}EOF" "python3 - <<'EOF'${nl}print(1 > 0)${nl}EOF" 'echo "x" > "/tmp/x y"' \
           'echo \> src/A.kt' 'ls 2>&1 >/dev/null'; do
  rc="$(b_rc "$cmd")"
  [ "$rc" = 0 ] && ok "D5: read-only while A holds: $(printf '%s' "$cmd" | tr '\n' ' ')" \
    || fail "D5: read-only command blocked (rc=$rc): $(printf '%s' "$cmd" | tr '\n' ' ') — $(head -c 200 "$TMP/err")"
done
for cmd in 'echo hi > src/A.kt' 'echo hi >"src/A.kt"' 'echo "a > b" > src/A.kt' "printf x >> 'src/A.kt'" \
           'echo x 2>&1 > src/A.kt' '(echo x > src/A.kt)' 'y=$(echo z > src/A.kt)' "bash <<'EOF'${nl}echo x > src/A.kt${nl}EOF" \
           "echo x > \"$REPO/src/A.kt\"" 'echo x &>src/A.kt'; do
  rc="$(b_rc "$cmd")"
  [ "$rc" = 2 ] && ok "D5: still blocked: $(printf '%s' "$cmd" | tr '\n' ' ')" \
    || fail "D5: a redirect into the checkout passed (rc=$rc): $(printf '%s' "$cmd" | tr '\n' ' ')"
done

# ── D6: malformed payloads and garbled heartbeats never crash ────────────────────────────────────────────────────────
for p in '[1, 2]' 'null' '"text"' '7' '{"session_id":"B","hook_event_name":"PreToolUse","cwd":"'"$REPO"'","tool_name":"Bash","tool_input":"ls"}' \
         '{"session_id":"B","hook_event_name":"PreToolUse","cwd":"'"$REPO"'","tool_name":"Bash","tool_input":["ls"]}'; do
  printf '%s' "$p" > "$TMP/m.json"; run_hook "$TMP/m.json"; rc=$?
  [ "$rc" = 0 ] && ! grep -q Traceback "$TMP/err" && ok "D6: payload $(printf '%s' "$p" | head -c 60): no-op, exit 0" \
    || fail "D6: payload $(printf '%s' "$p" | head -c 60): rc=$rc $(tail -n 2 "$TMP/err")"
done
reset_lock
python3 - "$GDIR" <<'PY'
import json, os, sys
g = sys.argv[1]
json.dump({"session_id": "A", "started": "noon", "heartbeat": "abc", "cwd": "/x", "pid": os.getppid(), "gitdir": g},
          open(os.path.join(g, "devkit-session.lock"), "w"))
PY
python3 "$SL" --status "$REPO" > "$TMP/st" 2>&1; rc=$?
[ "$rc" = 0 ] && ! grep -q Traceback "$TMP/st" && ok "D6: --status with a non-numeric heartbeat: stale → free (exit 0), no traceback" \
  || fail "D6: --status garbled heartbeat: rc=$rc $(tail -n 2 "$TMP/st")"
payload "$TMP/g.json" B Edit; run_hook "$TMP/g.json"; rc=$?
[ "$rc" = 0 ] && ! grep -q Traceback "$TMP/err" && grep -q '"session_id": "B"' "$GDIR/devkit-session.lock" \
  && ok "D6: hook with a non-numeric heartbeat: stale → B takes the checkout, no traceback" \
  || fail "D6: hook garbled heartbeat: rc=$rc $(tail -n 2 "$TMP/err")"
python3 - "$GDIR" <<'PY'
import json, os, sys, time
g = sys.argv[1]
json.dump({"session_id": "P", "started": time.time(), "heartbeat": time.time(), "cwd": "/x", "pid": 2 ** 70, "gitdir": g},
          open(os.path.join(g, "devkit-session.lock"), "w"))
PY
python3 "$SL" --status "$REPO" > "$TMP/st" 2>&1; rc=$?
[ "$rc" = 3 ] && ! grep -q Traceback "$TMP/st" && ok "D6: --status with a pid past the OS range: unknown pid, fresh heartbeat → held (exit 3), no traceback" \
  || fail "D6: --status huge pid: rc=$rc $(tail -n 2 "$TMP/st")"
mkdir -p "$GDIR/devkit-sessions"
printf '{"session_id":"C","heartbeat":"zz","pid":%s,"status":"working","gitdir":"%s"}' "$$" "$GDIR" > "$GDIR/devkit-sessions/C.json"
payload "$TMP/c.json" C Bash "ls"; run_hook "$TMP/c.json"; rc=$?
[ "$rc" = 0 ] && ! grep -q Traceback "$TMP/err" && ok "D6: registry entry with a non-numeric heartbeat: hook does not crash" \
  || fail "D6: registry garbled heartbeat: rc=$rc $(tail -n 2 "$TMP/err")"
printf '{"session_id":"D","heartbeat":"zz","pid":%s,"status":"working","gitdir":"%s"}' "$$" "$GDIR" > "$GDIR/devkit-sessions/D.json"
python3 "$SL" --check-last-active --session B "$REPO" > "$TMP/cl" 2>&1; rc=$?
{ [ "$rc" = 0 ] || [ "$rc" = 1 ]; } && ! grep -q Traceback "$TMP/cl" && ok "D6: --check-last-active with a garbled registry entry: no traceback (rc=$rc)" \
  || fail "D6: --check-last-active garbled: rc=$rc $(tail -n 2 "$TMP/cl")"

# ── D7: git dir without spawning git — same answer as git ─────────────────────────────────────────────────────────────
SUB="$TMP/sub"; newrepo "$SUB"
git -C "$REPO" -c protocol.file.allow=always submodule add -q "$SUB" mods/sub >/dev/null 2>&1
git -C "$REPO" worktree add -q "$TMP/wt" -b wt >/dev/null 2>&1
mkdir -p "$TMP/plain" "$REPO/src/deep"
python3 - "$DEVKIT_DIR/bin" "$REPO" "$TMP" <<'PY'
import os, subprocess, sys
sys.path.insert(0, sys.argv[1])
import session_lock as sl
repo, tmp = sys.argv[2], sys.argv[3]
fails = 0
def git_says(d, *args):
    r = subprocess.run(["git", "-C", d, "rev-parse", *args], capture_output=True, text=True)
    return r.stdout.strip().splitlines() if r.returncode == 0 else None
def real(p):
    return os.path.realpath(p) if p else p
for d in (repo, repo + "/src/deep", tmp + "/wt", repo + "/mods/sub", tmp + "/plain", repo + "/.git", tmp + "/missing"):
    want = git_says(d, "--absolute-git-dir", "--show-toplevel")
    got = sl.git_dir(d)
    want_gd = (real(want[0]), real(want[1])) if want and len(want) >= 2 else (None, None)
    wantc = git_says(d, "--git-common-dir", "--show-toplevel") if want else None
    gotc = sl.git_common_dir(d)
    want_c = (real(os.path.join(d, wantc[0])), real(wantc[1])) if wantc and len(wantc) >= 2 else (None, None)
    same = (real(got[0]), real(got[1])) == want_gd and (real(gotc[0]), real(gotc[1])) == want_c
    print(("✔" if same else "✖") + f" D7: git dir of {os.path.relpath(d, tmp)} matches git ({got[0] and os.path.relpath(real(got[0]), real(tmp))})"
          + ("" if same else f": got {got} / {gotc}, git says {want_gd} / {want_c}"))
    fails += not same
os.environ["GIT_DIR"] = repo + "/.git"
got = sl.git_dir(tmp + "/plain")
same = got[0] is not None and real(got[0]) == real(repo + "/.git")
print(("✔" if same else "✖") + " D7: GIT_DIR in the environment is honoured (falls back to git)" + ("" if same else f": {got}"))
fails += not same
sys.exit(1 if fails else 0)
PY
[ $? = 0 ] || FAILS=$((FAILS + 1))

[ "$FAILS" -eq 0 ] && echo "✅ test_session_lock_robust: all passed" || { echo "❌ test_session_lock_robust: $FAILS failed"; exit 1; }
