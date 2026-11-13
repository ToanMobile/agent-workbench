#!/usr/bin/env bash
# tests/lib/job_pool.py (#976): _take() raises OSError when a later <dir>/tok.<k> cannot be opened; the free tok.<i> it already holds must
# be closed on that path too (it leaked: the slot stayed locked until exec/exit). tok.1 is a directory here, so os.open of it fails while
# tok.0 was already taken as the free one: after the OSError no fd _take() opened is still open.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/pool/tok.1"
out="$(python3 - "$DEVKIT_DIR/tests/lib" "$TMP/pool" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1])
import job_pool

def open_fds():
    return {int(n) for n in os.listdir("/dev/fd") if n.isdigit() and _alive(int(n))}

def _alive(fd):
    try:
        os.fstat(fd)
        return True
    except OSError:
        return False

before = open_fds()
try:
    job_pool._take(sys.argv[2], 2, False)
    print("no OSError raised")
    sys.exit(1)
except OSError as exc:
    leaked = sorted(open_fds() - before)
print("leaked=" + ",".join(map(str, leaked)) if leaked else "clean")
sys.exit(1 if leaked else 0)
PY
)"; rc=$?
if [ "$rc" = 0 ]; then echo "ok: _take() closes every fd it opened when a later tok file cannot be opened"; echo "ALL PASS"; exit 0; fi
echo "✖ _take() OSError path: $out (exit $rc)"; exit 1
