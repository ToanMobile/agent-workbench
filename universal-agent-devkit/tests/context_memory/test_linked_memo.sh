#!/usr/bin/env bash
# #1127: enrich_context._linked() ran regression_checklist.skip_bookkeeping (several git subprocesses) up to 3x per prompt.
# One process, one project root: it must ask once.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
python3 -I - "$DEVKIT_DIR/scripts/context" <<'PY'
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import enrich_context as E
class RC:
    calls = 0
    @staticmethod
    def skip_bookkeeping(_p):
        RC.calls += 1
        return True
res = [E._linked(RC, "/x") for _ in range(3)] + [E._linked(RC, "/y")]
ok = res == [True] * 4 and RC.calls == 2
print("✔ skip_bookkeeping asked once per root" if ok else f"✖ calls={RC.calls} res={res}")
sys.exit(0 if ok else 1)
PY
