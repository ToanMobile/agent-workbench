#!/usr/bin/env bash
# #862 (#1043): in trunk mode the main checkout refused putting BUG-MUC-LUC.md (a self-generated file) back to HEAD, so a dirty copy
# blocked `pull --ff-only` and a release waited for a person. Declared generated files may be restored in main; nothing else may.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset WORKTREE_TRUNK_MODE DEVKIT_ALLOW_SHARED_CHECKOUT
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT; TMP="$(cd -P "$TMP" && pwd -P)"
M="$TMP/main"; mkdir -p "$M" && git -C "$M" init -q -b main && git -C "$M" config user.email t@t && git -C "$M" config user.name t
echo a > "$M/BUG-MUC-LUC.md"; echo b > "$M/src.py"; git -C "$M" add -A && git -C "$M" commit -qm i
git -C "$M" config devkit.trunkMode true
python3 - "$DEVKIT_DIR" "$M" <<'PY'
import sys
dk, m = sys.argv[1:3]
sys.path.insert(0, dk + "/bin")
import session_lock as sl
main, sw = sl.trunk_main(m)
assert main and sw, "trunk mode not seen"
CO, RS = "git " + "check" + "out", "git " + "re" + "store"
cases = [   # (is a write into main, label, command)
    (False, "checkout -- BUG-MUC-LUC.md", f"{CO} -- BUG-MUC-LUC.md"),
    (False, "checkout BUG-MUC-LUC.md", f"{CO} BUG-MUC-LUC.md"),
    (False, "restore BUG-MUC-LUC.md", f"{RS} BUG-MUC-LUC.md"),
    (True, "checkout -- src.py", f"{CO} -- src.py"),
    (True, "checkout both files", f"{CO} -- BUG-MUC-LUC.md src.py"),
    (True, "checkout -- .", f"{CO} -- ."),
    (True, "checkout other-branch BUG-MUC-LUC.md", f"{CO} other-branch BUG-MUC-LUC.md"),
    (True, "restore --source=other", f"{RS} --source=other BUG-MUC-LUC.md"),
    (True, "chained write after the allowed restore", f"{CO} -- BUG-MUC-LUC.md && echo x > src.py"),
    (True, "commit still a write", "git commit -qm x"),
]
bad = 0
for want, label, cmd in cases:
    got = bool(sl.trunk_write("Bash", {"command": cmd}, cmd, m, main, sw))
    print(("✔" if got == want else "✖"), label, "->", "write" if got else "allowed")
    bad += got != want
sys.exit(1 if bad else 0)
PY
