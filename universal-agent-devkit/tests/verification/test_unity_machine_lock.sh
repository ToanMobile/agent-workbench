#!/usr/bin/env bash
# One Unity batchmode on the machine: nice -n 15, -job-worker-count 4, and a second
# process does not exec the Editor while UNITY_BATCH_LOCK is held.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BATCH="$DEVKIT_DIR/profiles/game/scripts/unity-batch.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

BIN="$TMP/bin"
mkdir -p "$BIN"
ARGV="$TMP/nice.argv"
EDITOR_LOG="$TMP/editor.log"

cat > "$BIN/nice" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$ARGV_LOG"
if [ "${1:-}" = "-n" ]; then shift 2; fi
exec "$@"
SH
cat > "$BIN/Unity" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$EDITOR_LOG"
: > "$STARTED"
[ -n "${FAKE_SLEEP:-}" ] && sleep "$FAKE_SLEEP"
log=""
while [ $# -gt 0 ]; do
  case "$1" in -logFile) log="$2"; shift ;; esac
  shift
done
[ -n "$log" ] && echo "fake unity" > "$log"
exit 0
SH
chmod +x "$BIN/nice" "$BIN/Unity"

PROJ="$TMP/proj"
mkdir -p "$PROJ/Assets" "$PROJ/ProjectSettings"
printf 'm_EditorVersion: 6000.0.1f1\n' > "$PROJ/ProjectSettings/ProjectVersion.txt"
printf 'PlayerSettings:\n  companyName: DevKitTest\n  productName: LockProbe\n' > "$PROJ/ProjectSettings/ProjectSettings.asset"

: > "$ARGV"
: > "$EDITOR_LOG"
LOCK="$TMP/unity-batch.lock"

env PATH="$BIN:$PATH" ARGV_LOG="$ARGV" EDITOR_LOG="$EDITOR_LOG" STARTED="$TMP/started1" \
  FAKE_SLEEP=3 UNITY_KEEP_PREFS=1 UNITY_PATH="$BIN/Unity" UNITY_PROJECT="$PROJ" \
  UNITY_BATCH_OUT="$TMP/out1" UNITY_BATCH_LOCK="$LOCK" UNITY_TIMEOUT=30 \
  bash "$BATCH" compile >"$TMP/first.out" 2>&1 &
FIRST=$!

i=0
while [ ! -f "$TMP/started1" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
if [ -f "$TMP/started1" ]; then
  ok "first editor started under the machine lock"
else
  fail "first editor did not start: $(tail -20 "$TMP/first.out")"
fi

env PATH="$BIN:$PATH" ARGV_LOG="$ARGV" EDITOR_LOG="$EDITOR_LOG" STARTED="$TMP/started2" \
  FAKE_SLEEP=0 UNITY_KEEP_PREFS=1 UNITY_PATH="$BIN/Unity" UNITY_PROJECT="$PROJ" \
  UNITY_BATCH_OUT="$TMP/out2" UNITY_BATCH_LOCK="$LOCK" UNITY_TIMEOUT=30 \
  bash "$BATCH" compile >"$TMP/second.out" 2>&1 &
SECOND=$!

sleep 0.4
if [ ! -f "$TMP/started2" ]; then
  ok "second process does not exec the editor while the machine lock is held"
else
  fail "second editor ran while the first still held the lock"
fi
python3 - "$LOCK" <<'PY'
import fcntl, os, sys
fd = os.open(sys.argv[1], os.O_RDWR | os.O_CREAT, 0o600)
try:
    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
except OSError:
    sys.exit(0)
else:
    sys.exit(1)
finally:
    os.close(fd)
PY
if [ "$?" -eq 0 ]; then
  ok "machine lock is held (non-blocking acquire fails)"
else
  fail "machine lock was not held"
fi

wait "$FIRST" || true
i=0
while [ ! -f "$TMP/started2" ] && [ "$i" -lt 80 ]; do sleep 0.1; i=$((i + 1)); done
wait "$SECOND" || true
if [ -f "$TMP/started2" ]; then
  ok "second editor runs after the machine lock is released"
else
  fail "second editor never ran: $(tail -20 "$TMP/second.out")"
fi
if grep -q -- '-n' "$ARGV" && grep -q -- '15' "$ARGV"; then
  ok "launched argv includes nice -n 15"
else
  fail "nice -n 15 missing: $(cat "$ARGV")"
fi
if grep -q -- '-job-worker-count 4' "$EDITOR_LOG"; then
  ok "editor argv includes -job-worker-count 4"
else
  fail "job-worker-count missing: $(cat "$EDITOR_LOG")"
fi

[ "$FAILS" -eq 0 ] && echo "test_unity_machine_lock: PASS" || { echo "test_unity_machine_lock: FAIL ($FAILS)"; exit 1; }
