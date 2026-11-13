#!/usr/bin/env bash
# #1127 AC1: importing enrich_context compiled ~60 module-level regexes (~30 ms CPU of the 110 ms prompt-hook budget on a
# cold macOS runner). They must compile on first use, so an import compiles only the stdlib's own few, and a lazy regex still
# answers like a compiled one.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="${DEVKIT_DIR_UNDER_TEST:-$(cd "$(dirname "$0")/../.." && pwd)}"
python3 -I - "$DEVKIT_DIR/scripts/context" <<'PY'
import re, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import re._compiler as C
n = [0]; real = C.compile
def spy(*a, **k):
    n[0] += 1; return real(*a, **k)
C.compile = spy
re.purge()
import enrich_context as E
fails = 0
if n[0] > 20:
    fails += 1; print(f"✖ import compiled {n[0]} regexes (limit 20; stdlib imports compile a few of their own)")
else:
    print(f"✔ import compiled {n[0]} regexes")
m = E.FENCE_RE.search("a ```x``` b")
if not m or m.group(0) != "```x```" or E.FENCE_RE.sub("", "a ```x``` b") != "a  b":
    fails += 1; print("✖ lazy regex answers differently")
else:
    print("✔ lazy regex search/sub work")
sys.exit(1 if fails else 0)
PY
