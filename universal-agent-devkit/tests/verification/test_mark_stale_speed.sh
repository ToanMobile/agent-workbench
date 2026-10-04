#!/usr/bin/env bash
# Regression test: bin/regression_checklist.py mark_stale lists "changed since the run's commit"
# without one rename-detecting worktree `git diff <sha>` per distinct commit.
# 2026-09-28 (GeelyEx2): that diff took 0.57 s for one commit 2 800 files back (rename
# detection), 4-18 commits per call, mark_stale twice per post-fix-gate run. Now: one worktree
# diff against HEAD + one tree diff per commit, all --no-renames (_changed_since).
# Checked: the git calls (PATH wrapper) and the STALE verdict of every case the old code decided:
# committed change, dirty change, deleted file (clean / dirty run), untracked file, unknown
# commit, mtime rule, unchanged file. Documented over-reports (extra STALE, never a missed one):
# a file changed after the run and reverted in the worktree, the old path of a rename.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
REAL_GIT="$(command -v git)"

mkdir -p "$TMP/repo/src" "$TMP/bin" && cd "$TMP/repo" || exit 1
git init -q . && git config user.email t@t && git config user.name t
for f in a b c d keep r m; do echo "val $f = 1" > "src/$f.kt"; done
echo "val old = 1 // a file long enough for git to see its rename as a rename" > src/old.kt
git add -A && git commit -qm c1
C1="$(git rev-parse HEAD)"
echo "val a = 2" > src/a.kt                  # committed change
echo "val r = 2" > src/r.kt                  # committed, then reverted in the worktree
git mv src/old.kt src/new.kt                 # committed rename
git commit -qam c2
C2="$(git rev-parse HEAD)"
echo "val b = 2" > src/b.kt                  # dirty change
echo "val m = 2" > src/m.kt                  # dirty change made before the (future-dated) run
echo "val r = 1" > src/r.kt                  # back to the c1 content
rm src/c.kt                                  # deleted, uncommitted
echo "val u = 1" > src/u.kt                  # untracked

cat > "$TMP/bin/git" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMP/git_calls.log"
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$TMP/bin/git"

PATH="$TMP/bin:$PATH" python3 - "$DEVKIT_DIR/bin" "$TMP/repo" "$C1" "$C2" > "$TMP/result.txt" 2>&1 <<'PY'
import sys, time
sys.path.insert(0, sys.argv[1])
import regression_checklist as rc
project, c1, c2 = sys.argv[2], sys.argv[3], sys.argv[4]
future = time.time() + 1000
def test(watch, commit, ts=1, **last):
    return {"kind": "test", "watch_files": [watch], "last": {"status": "PASS", "commit": commit, "ts": ts, **last}}
data = {"items": {
    "committed": test("src/a.kt", c1),
    "committed-at-c2": test("src/a.kt", c2),
    "dirty": test("src/b.kt", c1),
    "dirty-at-c2": test("src/b.kt", c2),
    "deleted-clean-run": test("src/c.kt", c1),
    "deleted-before-dirty-run": test("src/c.kt", c1 + "+dirty", deleted=["src/c.kt"]),
    "deleted-dirty-run-no-record": test("src/c.kt", c1 + "+dirty"),
    "untracked": test("src/u.kt", c2),
    "unknown-commit": test("src/keep.kt", "0123456789abcdef0123456789abcdef01234567"),
    "mtime-before-run": test("src/m.kt", c2, ts=future),
    "unchanged": test("src/keep.kt", c1),
    "renamed-new-path": test("src/new.kt", c1),
    "renamed-old-path": test("src/old.kt", c1),
    "reverted": test("src/r.kt", c1),
}}
rc.mark_stale(data, project)
for tid, it in data["items"].items():
    print(tid, "STALE" if it.get("stale_since") else "ok", "|".join(it.get("stale_files") or []))
PY

verdict() { awk -v id="$1" '$1 == id {print $2}' "$TMP/result.txt"; }
expect() {  # id STALE|ok why
  if [ "$(verdict "$1")" = "$2" ]; then echo "✔ $1: $2 ($3)"
  else echo "✖ $1: expected $2, got '$(verdict "$1")' ($3)"; FAILS=$((FAILS + 1)); fi
}
expect committed STALE "a watched file committed after the run"
expect committed-at-c2 ok "the run's commit already had that change"
expect dirty STALE "an uncommitted edit"
expect dirty-at-c2 STALE "an uncommitted edit after a run at HEAD"
expect deleted-clean-run STALE "a file gone since a clean run"
expect deleted-before-dirty-run ok "already gone when the dirty run tested"
expect deleted-dirty-run-no-record ok "a dirty run without its deleted list: no hit (unchanged rule)"
expect untracked STALE "a new untracked watched file"
expect unknown-commit STALE "a run commit that no longer resolves"
grep -q "^unknown-commit STALE (commit 0123456789abcdef0123456789abcdef01234567 không còn trong repo)" "$TMP/result.txt" \
  && echo "✔ unknown-commit keeps its '(commit … không còn trong repo)' hit" \
  || { echo "✖ unknown-commit hit text changed: $(grep '^unknown-commit' "$TMP/result.txt")"; FAILS=$((FAILS + 1)); }
expect mtime-before-run ok "modified before the run (mtime rule)"
expect unchanged ok "nothing changed"
expect renamed-new-path STALE "the new path of a rename is never missed"
echo "  documented over-report, either verdict allowed: renamed-old-path=$(verdict renamed-old-path), reverted=$(verdict reverted)"

# The speed contract: one worktree diff (against HEAD), tree diffs per commit, no rename detection.
diffs="$(grep -E ' diff ' "$TMP/git_calls.log" | sed -E 's/.* diff /diff /')"
n_diff="$(printf '%s\n' "$diffs" | grep -c .)"
worktree="$(printf '%s\n' "$diffs" | awk '{n=0; for (i=2;i<=NF;i++) if ($i !~ /^-/) n++; if (n == 1) print}')"
n_wt="$(printf '%s\n' "$worktree" | grep -c .)"
renames="$(printf '%s\n' "$diffs" | grep -vc -e '--no-renames')"
if [ "$n_wt" -eq 1 ] && printf '%s\n' "$worktree" | grep -qE '(^| )HEAD$'; then
  echo "✔ one worktree git diff for $n_diff diff calls (against HEAD)"
else
  echo "✖ $n_wt worktree git diffs (one per commit):"; printf '    %s\n' "$worktree"; FAILS=$((FAILS + 1))
fi
if [ "$renames" -eq 0 ]; then
  echo "✔ every git diff of mark_stale runs with --no-renames"
else
  echo "✖ $renames git diff calls run rename detection"; FAILS=$((FAILS + 1))
fi

if [ "$FAILS" -ne 0 ]; then
  echo "--- mark_stale output"; cat "$TMP/result.txt"
  echo "mark_stale speed: $FAILS FAILED"; exit 1
fi
echo "mark_stale speed: all checks passed"
