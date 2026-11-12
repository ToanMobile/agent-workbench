#!/usr/bin/env bash
# #862: a red_proof whose proved file is git-IGNORED and absent (a red-patch a fresh worktree did not get) must keep its PROVEN
# status; a tracked/visible proved file that is gone or changed still drops to OUTDATED.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
P="$TMP/r"; mkdir -p "$P" && git -C "$P" init -q -b main . && echo a > "$P/t.sh" && echo ".agents/local/" > "$P/.git/info/exclude"
git -C "$P" add -A && git -C "$P" -c user.email=t@t -c user.name=t commit -qm init
python3 - "$DEVKIT_DIR" "$P" <<'PY'
import sys, hashlib
from pathlib import Path
sys.path.insert(0, sys.argv[1] + "/bin")
import regression_checklist as rc
proj = Path(sys.argv[2])
h = hashlib.sha1(b"x").hexdigest()[:16]
data = {"items": {
  "BUG-IGN": {"kind": "bug", "red_proof": {"status": "PROVEN", "files": {".agents/local/red-patches/BUG-IGN.patch": h}}},
  "BUG-VIS": {"kind": "bug", "red_proof": {"status": "PROVEN", "files": {"gone.sh": h}}},
}}
rc.mark_stale(data, proj)
a = data["items"]["BUG-IGN"]["red_proof"]["status"]; b = data["items"]["BUG-VIS"]["red_proof"]["status"]
print("ignored-missing:", a, "| visible-missing:", b)
sys.exit(0 if (a == "PROVEN" and b == "OUTDATED") else 1)
PY
