#!/usr/bin/env bash
# Regression test: `worktree.py status` lists EVERY worktree and flags the ones holding work that is not in
# the main line, so bringing one worktree back never silently forgets the others (2026-09-30: work done in
# one worktree was lost when another was gathered; nothing told the user the earlier ones existed).
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WT="$DEVKIT_DIR/scripts/worktree.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/main"
mkdir -p "$R" && cd "$R" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
echo base > app.txt && git add app.txt && git commit -q -m base

git worktree add -q -b a-dirty "$TMP/wt-a" >/dev/null 2>&1
echo "uncommitted feature" >> "$TMP/wt-a/app.txt"
git worktree add -q -b b-ahead "$TMP/wt-b" >/dev/null 2>&1
( cd "$TMP/wt-b" && echo b > b.txt && git add b.txt && git commit -q -m "feat: b" )
git worktree add -q --detach "$TMP/wt-c" >/dev/null 2>&1
( cd "$TMP/wt-c" && echo c > c.txt && git add c.txt && git commit -q -m "feat: c (detached, no branch)" )
git worktree add -q -b d-clean "$TMP/wt-d" >/dev/null 2>&1
git worktree add -q -b e-untracked "$TMP/wt-e" >/dev/null 2>&1
echo "new file never added" > "$TMP/wt-e/new_feature.py"

# f: a worktree whose git link is broken must never read as clean
git worktree add -q -b f-broken "$TMP/wt-f" >/dev/null 2>&1
echo "edit" >> "$TMP/wt-f/app.txt"; rm -f "$TMP/wt-f/.git"
# g: based on a branch that is ahead of main but adds nothing of its own: the upstream commits are not its work
git branch upstream && git worktree add -q -b upstream-tmp "$TMP/wt-up" >/dev/null 2>&1
( cd "$TMP/wt-up" && for i in 1 2 3; do echo "u$i" > "u$i.txt"; git add "u$i.txt"; git commit -q -m "upstream $i"; done && git branch -f upstream HEAD )
git worktree add -q -b g-from-upstream "$TMP/wt-g" upstream >/dev/null 2>&1
# h: a corrupt state file in ONE worktree must not break the report for the others
git worktree add -q -b h-state "$TMP/wt-h" >/dev/null 2>&1
echo '{}' > "$(git -C "$TMP/wt-h" rev-parse --absolute-git-dir)/devkit-worktree.json"

# stk: stacked on b-ahead (whose commit is nowhere in main)
git worktree add -q -b stk-on-b "$TMP/wt-stk" b-ahead >/dev/null 2>&1
# r: branch that was pushed (a remote-tracking ref equals HEAD) but never merged into main
git worktree add -q -b r-pushed "$TMP/wt-r" >/dev/null 2>&1
( cd "$TMP/wt-r" && echo r > r.txt && git add r.txt && git commit -q -m "feat: r" )
git update-ref refs/remotes/origin/r-pushed "$(git -C "$TMP/wt-r" rev-parse HEAD)"
# q: its work was brought back the documented way (same content committed in main), the branch was not merged
git worktree add -q -b q-patched "$TMP/wt-q" >/dev/null 2>&1
( cd "$TMP/wt-q" && echo q > q.txt && git add q.txt && git commit -q -m "feat: q" )
cp "$TMP/wt-q/q.txt" "$R/q.txt" && git add q.txt && git commit -q -m "feat: q (applied from the worktree patch)"
# rn: a rename whose new name already exists in main but whose old file still exists there is NOT integrated
git worktree add -q -b rn-rename "$TMP/wt-rn" >/dev/null 2>&1
( cd "$TMP/wt-rn" && git mv app.txt app-renamed.txt && git commit -q -m "refactor: rename" )
cp "$R/app.txt" "$R/app-renamed.txt" && git add app-renamed.txt && git commit -q -m "add the new name only"
# lit: a file named like a pathspec magic (":app.txt") must not match another path
git worktree add -q -b lit-magic "$TMP/wt-lit" >/dev/null 2>&1
( cd "$TMP/wt-lit" && echo lit > ":app.txt" && git add -- "./:app.txt" && git commit -q -m "feat: odd name" ) || fail "could not commit the odd-named file"
# tag: a detached worktree whose commit a TAG holds is unintegrated but not UNREACHABLE
git worktree add -q --detach "$TMP/wt-tag" >/dev/null 2>&1
( cd "$TMP/wt-tag" && echo t > t.txt && git add t.txt && git commit -q -m "feat: t" && git tag keep-t )
# a broken ref must not make the report fail open: detached wt-c still has to read UNREACHABLE
mkdir -p "$R/.git/refs/remotes/origin" && echo "1111111111111111111111111111111111111111" > "$R/.git/refs/remotes/origin/broken"

OUT="$(python3 "$WT" status 2>&1)"; RC=$?
line() { printf '%s\n' "$OUT" | grep -F "/$1  [" | head -1; }   # the path then two spaces: wt-r must not match wt-rn
for n in a b c e; do
  line "wt-$n" | grep -q "UNINTEGRATED" && ok "wt-$n is flagged UNINTEGRATED" || fail "wt-$n not flagged: $(line "wt-$n")"
done
line "wt-d" | grep -q "^clean " && ok "clean wt-d is listed as clean" || fail "wt-d not listed as clean: $(line "wt-d")"
line "wt-f" | grep -q "UNINTEGRATED" && ok "wt-f (unreadable status) is flagged, not read as clean" || fail "unreadable wt-f read as: $(line "wt-f")"
line "wt-up" | grep -q "UNINTEGRATED" && ok "wt-up (3 commits held only by a side branch) is flagged: not in the main line" || fail "wt-up read as: $(line "wt-up")"
line "wt-g" | grep -q "UNINTEGRATED" && ok "wt-g (based on a branch that is not in the main line) is flagged" || fail "wt-g read as: $(line "wt-g")"
line "wt-stk" | grep -q "UNINTEGRATED" && ok "a worktree stacked on another branch is flagged" || fail "stacked wt-stk read as: $(line "wt-stk")"
line "wt-q" | grep -q "^clean " && ok "wt-q whose patch was brought back into main reads clean" || fail "wt-q (patch applied in main) read as: $(line "wt-q")"
line "wt-rn" | grep -q "UNINTEGRATED" && ok "a rename whose deletion is not in main is flagged" || fail "wt-rn read as: $(line "wt-rn")"
line "wt-lit" | grep -q "UNINTEGRATED.*dirty=0 ahead=1" && ok "a pathspec-magic file name counts as one unintegrated commit, not clean" || fail "wt-lit read as: $(line "wt-lit")"
line "wt-r" | grep -q "UNINTEGRATED" && ok "a pushed branch (remote ref equal to HEAD) that is not in main is still flagged" || fail "pushed wt-r read as: $(line "wt-r")"
printf '%s' "$OUT" | grep -q "Traceback" && fail "status crashed on a corrupt state file: $OUT" || ok "a corrupt state file in one worktree does not break status"
line "wt-c" | grep -q "UNREACHABLE" && ok "detached wt-c is marked UNREACHABLE (its commit is on no branch)" || fail "detached commit not marked unreachable"
[ "$RC" = 0 ] && ok "status exits 0 by default" || fail "status exit $RC"
python3 "$WT" status --strict >/dev/null 2>&1; [ "$?" = 1 ] && ok "status --strict exits 1 while work is unintegrated" || fail "--strict did not exit 1"

# with the broken ref repaired, a tag holding the detached commit means it is NOT unreachable
rm -f "$R/.git/refs/remotes/origin/broken"
OUT="$(python3 "$WT" status 2>&1)"
line "wt-tag" | grep -q "UNREACHABLE" && fail "tag-held wt-tag wrongly UNREACHABLE: $(line "wt-tag")" || ok "a commit held by a tag is not UNREACHABLE"
line "wt-tag" | grep -q "UNINTEGRATED" && ok "  … but it is still unintegrated" || fail "wt-tag read as: $(line "wt-tag")"
line "wt-c" | grep -q "UNREACHABLE" && ok "wt-c (no ref holds it) stays UNREACHABLE" || fail "wt-c lost its UNREACHABLE flag"

# remove: a detached worktree whose commits no branch holds must be refused (they would be lost)
RM_OUT="$(python3 "$WT" remove "$TMP/wt-c" 2>&1)"
[ -d "$TMP/wt-c" ] && printf '%s' "$RM_OUT" | grep -q "UNREACHABLE" && ok "remove refuses a detached worktree with unreachable commits and says why" || fail "remove did not name the unreachable commits: $RM_OUT"

if [ $FAILS -gt 0 ]; then echo "FAILED: $FAILS errors"; exit 1; fi
echo "ALL TESTS PASSED"
