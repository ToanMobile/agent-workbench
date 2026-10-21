#!/usr/bin/env bash
# Regression test (issue #17): on macOS there is no /proc, so holder_pid() never skipped a short-lived sh parent, and
# is_pid_alive() answered True for a pid the OS had handed to another process (PermissionError / plain reuse).
# The lock now records pid_start (`ps -o lstart=`); a start that differs from the live process means the pid was recycled.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# 1. pid_start exists and is stable for a live process, None for a missing one.
out=$(python3 - "$DEVKIT_DIR/bin" <<'PY' 2>&1
import os, sys
sys.path.insert(0, sys.argv[1])
import session_lock as sl
a = sl.pid_start(os.getpid()); b = sl.pid_start(os.getpid())
assert a and a == b, (a, b)
assert sl.pid_start(2**22 - 3) is None
print("ok")
PY
); [ "$out" = ok ] && ok "pid_start: stable for a live pid, None for a missing one" || fail "pid_start: $out"

# 2. a live pid whose recorded start differs was recycled: dead. Same start: alive. No start recorded: old behaviour.
out=$(python3 - "$DEVKIT_DIR/bin" <<'PY' 2>&1
import os, sys
sys.path.insert(0, sys.argv[1])
import session_lock as sl
me = os.getpid(); real = sl.pid_start(me)
assert sl.is_pid_alive(me, real) is True
assert sl.is_pid_alive(me, "Thu Jan  1 00:00:00 1970") is False
assert sl.is_pid_alive(me) is True
print("ok")
PY
); [ "$out" = ok ] && ok "is_pid_alive: a changed start time reads as a recycled pid" || fail "is_pid_alive: $out"

# 3. a registered session stores pid_start, and a tampered one is pruned as dead.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git -C "$TMP" init -q . 
out=$(python3 - "$DEVKIT_DIR/bin" "$TMP" <<'PY' 2>&1
import json, os, sys, glob
sys.path.insert(0, sys.argv[1])
import session_lock as sl
cwd = sys.argv[2]
sl.register_session(cwd, "S1", pid=os.getpid())
f = glob.glob(os.path.join(cwd, ".git", "devkit-sessions", "S1.json"))[0]
d = json.load(open(f)); assert d.get("pid_start") == sl.pid_start(os.getpid()), d
d["pid_start"] = "Thu Jan  1 00:00:00 1970"; json.dump(d, open(f, "w"))
active, _, _ = sl.get_active_sessions(cwd)
assert not any(s.get("session_id") == "S1" for s in active), active
print("ok")
PY
); [ "$out" = ok ] && ok "register_session records pid_start; recycled pid is pruned" || fail "register/prune: $out"

# 4. holder_pid skips a forked /bin/sh parent without /proc (macOS): the grandparent is returned.
out=$(python3 - "$DEVKIT_DIR/bin" <<'PY' 2>&1
import os, subprocess, sys
sys.path.insert(0, sys.argv[1])
code = "import sys; sys.path.insert(0, %r); import session_lock as sl; print(sl.holder_pid())" % sys.argv[1]
# 'x; true' keeps sh alive as a forking parent of python
r = subprocess.run(["/bin/sh", "-c", 'python3 -c "$C"; true'], env=dict(os.environ, C=code), capture_output=True, text=True)
got = int(r.stdout.strip())
assert got == os.getpid(), (got, os.getpid(), r.stderr)
print("ok")
PY
); [ "$out" = ok ] && ok "holder_pid skips a forked sh parent without /proc" || fail "holder_pid: $out"

# 5. pid_start must not depend on the reader's TZ: `ps -o lstart=` prints local time, so a start written under one TZ and
# read under another read as a "recycled" pid and a live session looked dead (QA v4, AC2).
out=$(python3 - "$DEVKIT_DIR/bin" <<'PY' 2>&1
import os, subprocess, sys
sys.path.insert(0, sys.argv[1])
probe = "import sys; sys.path.insert(0, %r); import session_lock as sl; print(sl.pid_start(int(sys.argv[1])) or '')" % sys.argv[1]
target = subprocess.Popen(["sleep", "30"])
try:
    def read(tz):
        r = subprocess.run([sys.executable, "-c", probe, str(target.pid)], env=dict(os.environ, TZ=tz), capture_output=True, text=True)
        return r.stdout.strip()
    a, b = read("UTC"), read("Asia/Tokyo")
    assert a and a == b, (a, b)
    alive = subprocess.run([sys.executable, "-c", "import sys; sys.path.insert(0, %r); import session_lock as sl; print(sl.is_pid_alive(int(sys.argv[1]), sys.argv[2]))" % sys.argv[1], str(target.pid), a],
                           env=dict(os.environ, TZ="Asia/Tokyo"), capture_output=True, text=True).stdout.strip()
    assert alive == "True", alive
finally:
    target.kill(); target.wait()
print("ok")
PY
); [ "$out" = ok ] && ok "pid_start is the same under any TZ; a live pid is not read as recycled" || fail "pid_start TZ: $out"

[ "$FAILS" -eq 0 ] && echo "✅ test_session_lock_pid_start: all passed" || { echo "❌ test_session_lock_pid_start: $FAILS failed"; exit 1; }
