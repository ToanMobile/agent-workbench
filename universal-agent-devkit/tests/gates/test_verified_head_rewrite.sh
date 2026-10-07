#!/usr/bin/env bash
# Regression test: hooks/devkit_harness.verified_head() after the history was rewritten (git filter-repo).
# 2026-10-07 (GeelyEx2): the verified HEAD of 03/10 was no commit of the rewritten history, so the fallback was
# EMPTY_TREE; a tree is never an ancestor of HEAD, so EVERY Stop "reset" it again (55 times, one message each) and
# gated `--since EMPTY_TREE` = the whole repo (13287 files, ~10 min, always blocked, so the mark never advanced).
#   - the stored mark EMPTY_TREE must stay (no reset, no message, no state write on every Stop);
#   - a mark that filter-repo rewrote (.git/filter-repo/commit-map) goes to the commit it became: the same code that
#     was verified, so the range is the real one (49 commits), nothing verified is dropped and nothing is skipped.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

PY="${PYTHON:-python3}"
export TMP DEVKIT_DIR
cat > "$TMP/t.py" <<'PY'
import json, os, subprocess, sys
sys.path.insert(0, os.path.join(os.environ["DEVKIT_DIR"], "hooks"))
import devkit_harness as h

TMP = os.environ["TMP"]
ENV = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")

def git(repo, *a, check=True):
    r = subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True, env=ENV)
    if check and r.returncode:
        raise SystemExit("git %s failed: %s" % (" ".join(a), r.stderr))
    return r.stdout.strip()

def state_path(repo):
    return os.path.join(repo, h.GATE_STATE)

def seed(repo, vh):
    os.makedirs(os.path.dirname(state_path(repo)), exist_ok=True)
    with open(state_path(repo), "w") as f:
        json.dump({"verified_head": vh}, f)

def stored(repo):
    return json.load(open(state_path(repo)))["verified_head"]

def rewritten_repo(name):
    """Old history OLD (2 commits), then a NEW unrelated history with the same files: what filter-repo leaves."""
    repo = os.path.join(TMP, name)
    os.makedirs(repo)
    git(repo, "init", "-q", ".")
    for n in ("a", "b"):
        open(os.path.join(repo, n + ".txt"), "w").write(n)
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "old " + n)
    old = git(repo, "rev-parse", "HEAD")
    git(repo, "checkout", "-q", "--orphan", "rewritten")
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", "new a+b")
    new = git(repo, "rev-parse", "HEAD")
    open(os.path.join(repo, "c.txt"), "w").write("c")
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", "new c")
    head = git(repo, "rev-parse", "HEAD")
    return repo, old, new, head

def fr_map(repo, pairs):
    d = os.path.join(repo, ".git", "filter-repo")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "commit-map"), "w") as f:
        f.write("old                                      new\n")
        for o, n in pairs:
            f.write("%s %s\n" % (o, n))

res = []
def check(label, cond, detail=""):
    res.append(("✔ " if cond else "✖ ") + label + ("" if cond else "  [" + str(detail) + "]"))

# 1. no commit-map: the fallback EMPTY_TREE is reached once, then it is STABLE (no reset on every Stop)
repo, old, new, head = rewritten_repo("nomap")
seed(repo, old)
vh1, _h, why1 = h.verified_head(repo)
check("no commit-map: first call falls back to EMPTY_TREE and says why", vh1 == h.EMPTY_TREE and why1 == "rebase/reset", (vh1, why1))
vh2, _h, why2 = h.verified_head(repo)
check("EMPTY_TREE stored: the next Stop does not reset it again (no reset reason)", vh2 == h.EMPTY_TREE and why2 == "", (vh2, why2))
before = os.stat(state_path(repo)).st_mtime_ns
h.verified_head(repo)
check("EMPTY_TREE stored: no state rewrite on every Stop", os.stat(state_path(repo)).st_mtime_ns == before)

# 2. filter-repo commit-map: the mark moves to the commit it became, not to the whole repo
repo, old, new, head = rewritten_repo("mapped")
fr_map(repo, [(old, new)])
seed(repo, old)
vh1, _h, why1 = h.verified_head(repo)
check("commit-map: the verified commit is replaced by the one filter-repo made of it", vh1 == new and why1 == "rebase/reset", (vh1[:8], new[:8], why1))
check("commit-map: the new mark is stored", stored(repo) == new, stored(repo)[:8])
vh2, _h, why2 = h.verified_head(repo)
check("commit-map: the next Stop is stable (same mark, no reset)", vh2 == new and why2 == "", (vh2[:8], why2))
check("commit-map: the gated range is the commits after the mark, not the whole history",
      git(repo, "rev-list", "--count", vh2 + "..HEAD") == "1", git(repo, "rev-list", "--count", vh2 + "..HEAD"))

# 3. a commit-map line that does not lead into HEAD's history is not trusted
repo, old, new, head = rewritten_repo("foreign")
git(repo, "checkout", "-q", "--orphan", "other")
git(repo, "commit", "-qm", "unrelated", "--allow-empty")
other = git(repo, "rev-parse", "HEAD")
git(repo, "checkout", "-q", "rewritten")
fr_map(repo, [(old, other)])
seed(repo, old)
vh1, _h, why1 = h.verified_head(repo)
check("commit-map pointing outside HEAD's history: EMPTY_TREE, never that commit", vh1 == h.EMPTY_TREE, vh1[:8])

# 4. a pruned commit (all-zero new id) is not a mark
repo, old, new, head = rewritten_repo("pruned")
fr_map(repo, [(old, "0" * 40)])
seed(repo, old)
vh1, _h, why1 = h.verified_head(repo)
check("commit-map with a pruned commit (0000...): EMPTY_TREE", vh1 == h.EMPTY_TREE, vh1[:8])

# 5. unchanged behaviour: an ordinary reset inside ONE history still goes to the merge-base
repo = os.path.join(TMP, "plain")
os.makedirs(repo)
git(repo, "init", "-q", ".")
for n in ("a", "b", "c"):
    open(os.path.join(repo, n + ".txt"), "w").write(n)
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", n)
c3 = git(repo, "rev-parse", "HEAD")
c1 = git(repo, "rev-parse", "HEAD~2")
git(repo, "reset", "-q", "--hard", c1)
open(os.path.join(repo, "d.txt"), "w").write("d")
git(repo, "add", "-A")
git(repo, "commit", "-qm", "d")
seed(repo, c3)
vh1, _h, why1 = h.verified_head(repo)
check("ordinary reset: still the merge-base of the old mark and HEAD", vh1 == c1 and why1 == "rebase/reset", (vh1[:8], c1[:8], why1))

print("\n".join(res))
sys.exit(1 if any(r.startswith("✖") for r in res) else 0)
PY
out="$("$PY" -I "$TMP/t.py")"; rc=$?
printf '%s\n' "$out"
[ "$rc" = 0 ] && ok "verified_head survives a history rewrite" || bad "verified_head after a history rewrite (rc=$rc)"
[ "$FAILS" = 0 ] && exit 0 || exit 1
