#!/usr/bin/env bash
# Regression (DevKit speed, review of 0a): tree_fingerprint() copied the real index with shutil.copyfile, so the
# throw-away index got a NEW mtime. git's "racily clean" rule (an index entry whose mtime is not older than the
# index file's own mtime is re-hashed instead of trusted) then no longer applied: an edit of the SAME SIZE made in the
# SAME SECOND as the last index write was not seen, and the fingerprint of the MODIFIED tree equalled the fingerprint
# of the unmodified one until a `git status` refreshed the real index. A full-gate receipt of the old code then
# matched changed code. shutil.copy2 keeps the index mtime, so git re-hashes those entries.
# Needs a real same-second edit: up to 8 attempts, each ~1.3 s; none aligned = the test says so and fails (never a silent pass).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

out="$(PYTHONDONTWRITEBYTECODE=1 python3 - "$DEVKIT_DIR/bin" "$TMP" <<'PY'
import os, subprocess, sys, time
sys.path.insert(0, sys.argv[1]); import tree_fp
tmp = sys.argv[2]
env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
G = lambda d, *a: subprocess.run(["git", "-c", "user.email=t@t", "-c", "user.name=t", "-C", d, *a], capture_output=True, text=True, env=env)
aligned = 0
for i in range(8):
    d = os.path.join(tmp, "r%d" % i); os.makedirs(d + "/src")
    G(d, "init", "-q", "-b", "main")
    p = d + "/src/Core.kt"; open(p, "w").write("fun ok() = 1\n")
    G(d, "add", "-A"); G(d, "commit", "-q", "-m", "c")                  # the real index is written now
    idx_sec = int(os.stat(d + "/.git/index").st_mtime)
    fp_clean = tree_fp.tree_fingerprint(d)                              # the unmodified committed tree
    open(p, "w").write("fun ok() = 2\n")                                # same size
    if int(os.stat(p).st_mtime) != idx_sec:
        continue                                                        # crossed a second boundary: not a racy edit, retry
    aligned += 1
    time.sleep(1.2)                                                     # the fingerprint is taken later than that second
    before = tree_fp.tree_fingerprint(d)
    G(d, "status", "-s")                                                # a normal refresh of the REAL index
    after = tree_fp.tree_fingerprint(d)
    print("ALIGNED", "SEEN" if before != fp_clean else "MISSED", "STABLE" if before == after else "DRIFT")
    break
print("aligned=%d" % aligned)
PY
)"
case "$out" in *"aligned=0"*) bad "no attempt put the edit in the same second as the index write (8 tries): the test could not run" ;; esac
case "$out" in *ALIGNED*SEEN*) ok "a same-size edit in the same second as the index write changes the fingerprint (not mistaken for the unmodified tree)" ;; *ALIGNED*MISSED*) bad "the fingerprint of the MODIFIED tree equals the unmodified tree's: the edit was missed" ;; esac
case "$out" in *ALIGNED*STABLE*) ok "the fingerprint is the same before and after a git status refresh of the real index" ;; *ALIGNED*DRIFT*) bad "the fingerprint changed after a git status refresh with unchanged content" ;; esac

echo
[ "$FAILS" -eq 0 ] && echo "tree_fp racy index: all checks passed" || { echo "tree_fp racy index: $FAILS FAILED"; exit 1; }
