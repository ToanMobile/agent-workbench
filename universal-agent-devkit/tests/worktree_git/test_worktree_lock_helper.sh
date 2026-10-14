#!/usr/bin/env bash
# scripts/git/worktree.py _lock_file: the one lock of `worktree add` (the cap), automerge (one merge per worktree) and MAIN_LOCK (one
# fast-forward of main at a time). Review 14/10 of W1 R5c: the O_EXCL lock FILE it was let two waiters that both saw a dead holder's file
# take it over together (each unlinked the other's fresh file), and a file deleted between the failed create and the read made a waiter
# give up at once. A lock must never be held twice, whatever a killed holder left behind, and must free itself when its holder dies.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'kill "${HOLDER:-}" 2>/dev/null; rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
cat > "$TMP/take.py" <<'PY'
import os, sys, time
sys.path.insert(0, sys.argv[1])
import worktree as w
lock_path, tokens, tag = sys.argv[2], sys.argv[3], sys.argv[4]
h = w._lock_file(lock_path, wait=20.0)
if h is None:
    sys.exit(3)
os.mkdir(os.path.join(tokens, tag))
n = len(os.listdir(tokens))          # holders at this moment, this one included
with open(os.path.join(tokens, "..", "max." + tag), "w") as f:
    f.write(str(n) + "\n")
time.sleep(0.02)
os.rmdir(os.path.join(tokens, tag))
if isinstance(h, str):               # the O_EXCL version returned its path (released by unlinking it); a handle is closed
    os.unlink(h)
else:
    h.close()
PY

# 1 a lock file a killed holder left behind (dead pid) and twelve waiters at once: never two holders, every waiter gets it (30 runs)
bad=0
for k in $(seq 1 30); do
  d="$TMP/r$k"; mkdir -p "$d/tok"; printf '{"pid": 999999, "at": %s}\n' "$(date +%s)" > "$d/x.lock"
  for i in $(seq 1 12); do (python3 -I "$TMP/take.py" "$DEVKIT_DIR/scripts/git" "$d/x.lock" "$d/tok" "t$i"; echo $? > "$d/rc.$i") & done
  wait
  m="$(cat "$d"/max.* 2>/dev/null | sort -n | tail -1)"; got="$(grep -lx 0 "$d"/rc.* 2>/dev/null | wc -l | tr -d ' ')"
  { [ "${m:-0}" = 1 ] && [ "$got" = 12 ]; } || bad=$((bad + 1))
done
[ "$bad" = 0 ] && ok "a dead holder's lock file + 12 waiters: one holder at a time, all 12 served (30 runs)" || fail "$bad of 30 runs had two holders at once or a waiter that gave up"

# 2 a live holder: wait=0 gets None at once; once the holder is killed (no clean-up at all) the lock is free right away
python3 -I -c 'import sys,time; sys.path.insert(0, sys.argv[1]); import worktree as w; h = w._lock_file(sys.argv[2]); open(sys.argv[3], "w").close(); time.sleep(60)' \
  "$DEVKIT_DIR/scripts/git" "$TMP/live.lock" "$TMP/held" &
HOLDER=$!
for _ in $(seq 1 100); do [ -f "$TMP/held" ] && break; sleep 0.05; done
[ -f "$TMP/held" ] || fail "2 setup: the holder never took the lock (the checks below would prove nothing)"
probe() { python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import worktree as w; print("none" if w._lock_file(sys.argv[2], wait=float(sys.argv[3])) is None else "got")' "$DEVKIT_DIR/scripts/git" "$TMP/live.lock" "$1"; }
[ "$(probe 0)" = none ] && ok "a live holder: another taker gets None (wait 0)" || fail "the lock was taken while its holder lives"
kill -9 "$HOLDER"; wait "$HOLDER" 2>/dev/null; HOLDER=""
[ "$(probe 0)" = got ] && ok "  … the holder killed with no clean-up: the lock is free at once" || fail "a killed holder still holds the lock"

# 3 no fcntl (Windows Python): the caller runs unlocked and says so, never a traceback (OCR 14/10; cmd_gc already does this)
r="$(python3 -I -c 'import sys; sys.modules["fcntl"] = None; sys.path.insert(0, sys.argv[1]); import worktree as w; h = w._lock_file(sys.argv[2]); print("none" if h is None else "handle"); h.close()' "$DEVKIT_DIR/scripts/git" "$TMP/case3.lock" 2>"$TMP/nofcntl.err")"   # a lock name without "fcntl": the grep below must match the reason
[ "$r" = handle ] && grep -q "fcntl" "$TMP/nofcntl.err" && grep -qE "running unlocked|chạy không khoá" "$TMP/nofcntl.err" && ok "no fcntl module: an unlocked handle, and it says why" || fail "no fcntl: '$r' $(tail -1 "$TMP/nofcntl.err")"
# … nor the POSIX-only open flags (Windows Python has no os.O_NONBLOCK / os.O_NOFOLLOW): still that handle, never an AttributeError
r="$(python3 -I -c 'import os,sys; sys.modules["fcntl"] = None
for f in ("O_NONBLOCK", "O_NOFOLLOW", "O_CLOEXEC"):
    if hasattr(os, f): delattr(os, f)
sys.path.insert(0, sys.argv[1]); import worktree as w; h = w._lock_file(sys.argv[2]); print("none" if h is None else "handle"); h.close()' "$DEVKIT_DIR/scripts/git" "$TMP/noflags.lock" 2>"$TMP/noflags.err")"
[ "$r" = handle ] && ok "  … and without the POSIX-only open flags" || fail "no O_NONBLOCK/O_NOFOLLOW: '$r' $(tail -1 "$TMP/noflags.err")"

# 4 a FIFO or a folder planted at a lock path (review 14/10): an OSError at once, never a hang (open() of a FIFO waits for a reader)
mkfifo "$TMP/fifo.lock"; mkdir -p "$TMP/dir.lock"
for p in fifo.lock dir.lock; do
  r="$(python3 -I -c 'import signal,sys; signal.alarm(5); sys.path.insert(0, sys.argv[1]); import worktree as w
try:
    w._lock_file(sys.argv[2]); print("opened")
except OSError as e:
    print("oserror")' "$DEVKIT_DIR/scripts/git" "$TMP/$p" 2>/dev/null)"
  [ "$r" = oserror ] && ok "  … a $p planted at the lock path: OSError at once" || fail "$p at the lock path: '${r:-hung (alarm)}'"
done
# … and automerge, which the Stop hook reads one JSON line from, still prints that line (blocked) instead of a traceback
R="$TMP/repo"; mkdir -p "$R" && git -C "$R" init -q -b main . && echo a > "$R/a.txt" && git -C "$R" -c user.email=t@t -c user.name=t add -A \
  && git -C "$R" -c user.email=t@t -c user.name=t commit -qm a && git -C "$R" worktree add -q --detach "$TMP/repo-w" && echo b > "$TMP/repo-w/b.txt"
mkfifo "$(git -C "$TMP/repo-w" rev-parse --absolute-git-dir)/devkit-automerge.lock"
out="$(cd "$R" && python3 -I -c 'import subprocess,sys
try:
    r = subprocess.run(sys.argv[1:], capture_output=True, text=True, timeout=20); print(r.returncode); print(r.stdout.strip().splitlines()[-1] if r.stdout.strip() else "")
except subprocess.TimeoutExpired:
    print("TIMEOUT")' python3 "$DEVKIT_DIR/scripts/git/worktree.py" automerge "$TMP/repo-w")"
echo "$out" | head -1 | grep -qx 1 && echo "$out" | tail -1 | grep -q '"status": "blocked"' && echo "$out" | tail -1 | grep -qE "lỗi hệ thống tệp|filesystem error" && ok "automerge with a FIFO at its lock: one JSON line, blocked (exit 1)" \
  || fail "automerge with a FIFO at its lock: $(echo "$out" | tr '\n' ' ' | cut -c1-200)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_worktree_lock_helper: PASS"; exit 0; } || { echo "test_worktree_lock_helper: FAIL ($FAILS)"; exit 1; }
