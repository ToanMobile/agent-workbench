#!/usr/bin/env bash
# Regression (agent-workbench #221): two branches that each append a different rule to the tail of
# .agents/regression_matrix.active.json conflicted on the last lines, so the second PR to merge went CONFLICTING
# (PR #217 vs #219, 22/10). The union merge driver `scripts/git/matrix_merge_driver.py` joins them.
#   1. two branches append different rules: merge is clean, both rules present after the base rules, in merge order
#   2. the merged matrix is still append-only against the base: the gate's matrix_additions() trusts it
#   3. both branches append the SAME rule (same id, same content): kept once
#   4. both branches append the same test id with a different command: merge FAILS (exit != 0) naming the id, never merges silently
#   5. a non-additive edit (both branches change the same existing rule) falls back to the text merge, which conflicts
#   7. merging origin/main INTO a PR branch keeps the matrix append-only against origin/main (what the gate compares), main's rules first
#   6. githooks.sh install registers the driver and .gitattributes routes the matrix file to it
#   8. the registered driver runs in a linked worktree with no .agents/devkit (the merge gate's scratch, #282)
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DRIVER="$DEVKIT_DIR/scripts/git/matrix_merge_driver.py"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
M=".agents/regression_matrix.active.json"
R=""

rule() { # $1 id $2 command
  printf '{"watch_files": ["x/%s"], "mandatory_regression_tests": [{"id": "%s", "name": "n", "command": "%s"}]}' "$1" "$1" "$2"
}
write_matrix() { # $@ = rule JSON objects
  python3 - "$@" <<'PY'
import json, sys
m = {"version": 1, "project": "t", "rules": [json.loads(a) for a in sys.argv[1:]]}
open(".agents/regression_matrix.active.json", "w", encoding="utf-8").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
PY
}
make_repo() { # a fresh repo per case; the trap removes them all
  R="$(mktemp -d "$TMP/repo.XXXXXX")" && mkdir -p "$R/.agents" && cd "$R" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t
  echo "$M merge=devkit-matrix" > .gitattributes
  git config merge.devkit-matrix.driver "python3 $DRIVER %O %A %B %P"
  write_matrix "$(rule BASE-1 true)"
  git add -A && git commit -qm base
}
branch_add() { # $1 branch, rest = rules appended to the base rules
  local b="$1"; shift
  git checkout -q -b "$b" main
  write_matrix "$(rule BASE-1 true)" "$@"
  git commit -qam "$b"
}
ids() { python3 -c 'import json;print(" ".join(t["id"] for r in json.load(open(".agents/regression_matrix.active.json"))["rules"] for t in r["mandatory_regression_tests"]))'; }

# 1 + 2
make_repo
branch_add a "$(rule A-1 true)"; branch_add b "$(rule B-1 true)"
git checkout -q a
if git merge --no-edit b >/dev/null 2>&1; then ok "1: two different appended rules merge clean"; else bad "1: merge conflicted"; fi
[ "$(ids)" = "BASE-1 A-1 B-1" ] && ok "1: both rules present, base first" || bad "1: ids are '$(ids)'"
python3 - "$GATE" "$R" <<'PY' && ok "2: gate trusts the merged matrix as append-only" || bad "2: matrix_additions rejected the merge"
import importlib.util, json, subprocess, sys
spec = importlib.util.spec_from_file_location("g", sys.argv[1]); g = importlib.util.module_from_spec(spec); spec.loader.exec_module(g)
base = json.loads(subprocess.check_output(["git", "-C", sys.argv[2], "show", "main:.agents/regression_matrix.active.json"]))
cur = json.load(open(sys.argv[2] + "/.agents/regression_matrix.active.json"))
sys.exit(0 if g.matrix_additions(base, cur) == ["A-1", "B-1"] else 1)
PY

# 3
make_repo
branch_add a "$(rule S-1 true)"; branch_add b "$(rule S-1 true)"
git checkout -q a
git merge --no-edit b >/dev/null 2>&1 && [ "$(ids)" = "BASE-1 S-1" ] && ok "3: identical rule on both sides kept once" || bad "3: '$(ids)'"

# 4
make_repo
branch_add a "$(rule D-1 'echo a')"; branch_add b "$(rule D-1 'echo b')"
git checkout -q a
OUT="$(git merge --no-edit b 2>&1)"; RC=$?
[ $RC -ne 0 ] && echo "$OUT" | grep -q "D-1" && ok "4: same id, different command fails and names the id" || bad "4: rc=$RC out=$OUT"
git merge --abort >/dev/null 2>&1

# 5
make_repo
git checkout -q -b a main && sed -i.bak 's/"command": "true"/"command": "echo a"/' "$M" && rm -f "$M.bak" && git commit -qam a
git checkout -q -b b main && sed -i.bak 's/"command": "true"/"command": "echo b"/' "$M" && rm -f "$M.bak" && git commit -qam b
git checkout -q a
git merge --no-edit b >/dev/null 2>&1 && bad "5: overlapping edit of an existing rule merged silently" || ok "5: non-additive overlap still conflicts"
git merge --abort >/dev/null 2>&1

# 7: QA v1 of #221 — the gate compares with origin/main, not with the merge-base
make_repo
branch_add a "$(rule A-1 true)"
git checkout -q main && write_matrix "$(rule BASE-1 true)" "$(rule M-1 true)" && git commit -qam main-adds
git update-ref refs/remotes/origin/main main
git checkout -q a
git merge --no-edit main >/dev/null 2>&1 && [ "$(ids)" = "BASE-1 M-1 A-1" ] && ok "7: main's rule first, the branch's after" || bad "7: '$(ids)'"
python3 - "$GATE" "$R" <<'PY' && ok "7: gate trusts the matrix as append-only against origin/main" || bad "7: matrix_additions vs origin/main rejected the merge"
import importlib.util, json, subprocess, sys
spec = importlib.util.spec_from_file_location("g", sys.argv[1]); g = importlib.util.module_from_spec(spec); spec.loader.exec_module(g)
base = json.loads(subprocess.check_output(["git", "-C", sys.argv[2], "show", "origin/main:.agents/regression_matrix.active.json"]))
cur = json.load(open(sys.argv[2] + "/.agents/regression_matrix.active.json"))
sys.exit(0 if g.matrix_additions(base, cur) == ["A-1"] else 1)
PY

# 6
H="$(mktemp -d "$TMP/hooks.XXXXXX")" && cd "$H" && git init -q . && git config user.email t@t && git config user.name t
bash "$DEVKIT_DIR/scripts/git/githooks.sh" install "$H" >/dev/null 2>&1
git config --get merge.devkit-matrix.driver | grep -q matrix_merge_driver.py && grep -q "regression_matrix.active.json merge=devkit-matrix" .gitattributes \
  && ok "6: githooks install registers the driver and the attribute" || bad "6: driver/attribute missing"

# 8 (#282): the driver githooks.sh registers must run in a checkout that has no .agents/devkit (the merge gate's
# .merge-scratch-* worktree: the kit symlink is untracked). A relative ".agents/devkit/…" command fails there and git
# falls back to the text merge, so two appended rules conflict.
# The main checkout has the kit (untracked symlink, as installed); the linked worktree the merge runs in does not.
mkdir -p "$H/.agents" && cd "$H" || exit 1
printf '.agents/devkit\n' > .gitignore
write_matrix "$(rule BASE-1 true)" && git add -A && { git commit -qm base >/dev/null 2>&1 || bad "8: setup commit base refused"; }
ln -s "$DEVKIT_DIR" "$H/.agents/devkit"
git branch a8; git branch b8
W="$TMP/scratch8" && git worktree add -q "$W" a8 && cd "$W" || exit 1
write_matrix "$(rule BASE-1 true)" "$(rule A-8 true)"; git commit -qam a8 >/dev/null 2>&1 || bad "8: setup commit a8 refused"
git checkout -q b8; write_matrix "$(rule BASE-1 true)" "$(rule B-8 true)"; git commit -qam b8 >/dev/null 2>&1 || bad "8: setup commit b8 refused"
git checkout -q a8
[ ! -e "$W/.agents/devkit" ] || bad "8: setup — .agents/devkit must not exist in the worktree"
if git merge --no-edit b8 >/dev/null 2>&1 && [ "$(ids)" = "BASE-1 A-8 B-8" ]; then
  ok "8: the installed driver merges appended rules in a worktree without .agents/devkit"
else
  bad "8: merge conflicted in a worktree without .agents/devkit (driver: $(git config --get merge.devkit-matrix.driver))"
fi
cd "$H" && git worktree remove --force "$W" >/dev/null 2>&1

# 9 (#272 R2): the same test id on both sides with different content must leave git's conflict markers in the file
# (a `git add` right after the failed merge must not silently keep only ours' rule).
make_repo
branch_add a "$(rule D-1 'echo a')"; branch_add b "$(rule D-1 'echo b')"
git checkout -q a
git merge --no-edit b >/dev/null 2>&1
if grep -q '^<<<<<<<' "$M" && grep -q '^>>>>>>>' "$M"; then ok "9: duplicate id leaves conflict markers in the file"; else bad "9: no conflict markers after a duplicate id (the file is ours-only)"; fi
git merge --abort >/dev/null 2>&1

# 10 (#272 R3): a .gitattributes without a final newline still gets the attribute on its own line
H10="$(mktemp -d "$TMP/hooks10.XXXXXX")" && cd "$H10" && git init -q . && git config user.email t@t && git config user.name t
printf '*.txt text' > .gitattributes
bash "$DEVKIT_DIR/scripts/git/githooks.sh" install "$H10" >/dev/null 2>&1
grep -qxF '*.txt text' .gitattributes && grep -qxF "$M merge=devkit-matrix" .gitattributes \
  && ok "10: attribute appended on its own line after a file with no final newline" || bad "10: attribute glued to the last line: $(cat .gitattributes)"

# 11 (#272 R4): origin/main holds a matrix that is not an object (a JSON array): the driver must not crash
make_repo
branch_add a "$(rule A-1 true)"; branch_add b "$(rule B-1 true)"
git checkout -q main && printf '[]\n' > "$M" && git commit -qam weird && git update-ref refs/remotes/origin/main main
git checkout -q a
OUT="$(git merge --no-edit b 2>&1)"
echo "$OUT" | grep -q Traceback && bad "11: driver crashed on a non-object origin matrix" || ok "11: non-object origin matrix does not crash the driver"
git merge --abort >/dev/null 2>&1

# 12 (#272 R1): the command githooks.sh registers, run where no kit copy exists anywhere, falls back to git's own
# text merge instead of failing with "can't open file"
DRV12="$(git -C "$H" config --get merge.devkit-matrix.driver)"
make_repo
git config merge.devkit-matrix.driver "$DRV12"
branch_add a "$(rule A-1 true)"; branch_add b "$(rule B-1 true)"
git checkout -q a
OUT="$(git merge --no-edit b 2>&1)"
echo "$OUT" | grep -qi "can't open file" && bad "12: driver errored without a kit copy: $OUT" || ok "12: no kit copy: git's text merge runs instead of an error"
git merge --abort >/dev/null 2>&1

# 13 (#302): two branches that each append a different timing line to the tail of tests/lib/test_durations.txt merge clean and
# keep both; the root .gitattributes of THIS repo routes the file to git's built-in union driver
D="universal-agent-devkit/tests/lib/test_durations.txt"
ATTR_FILE="$DEVKIT_DIR/../.gitattributes"
make_repo
mkdir -p "$(dirname "$D")" && printf 'a 1\nb 2\n' > "$D"
if [ -f "$ATTR_FILE" ] && grep -qxF "$D merge=union" "$ATTR_FILE"; then echo "$D merge=union" >> .gitattributes; fi
git add -A && git commit -qm base
for br in x y; do git checkout -q -b $br main && printf '%s 9\n' "t-$br" >> "$D" && git commit -qam "add $br"; done
git checkout -q x
if git merge --no-edit y >/dev/null 2>&1 && grep -q '^t-x 9$' "$D" && grep -q '^t-y 9$' "$D" && ! grep -q '^<<<<<<<' "$D"; then
  ok "13: two appended timing lines merge clean, both kept"
else bad "13: test_durations.txt conflicts or loses a line (tracked attribute missing in the repo .gitattributes?)"; fi
git merge --abort >/dev/null 2>&1
# 13b: the very same line appended on both sides stays once
make_repo
mkdir -p "$(dirname "$D")" && printf 'a 1\n' > "$D"
if [ -f "$ATTR_FILE" ] && grep -qxF "$D merge=union" "$ATTR_FILE"; then echo "$D merge=union" >> .gitattributes; fi
git add -A && git commit -qm base
for br in x y; do git checkout -q -b $br main && printf 'same 5\n' >> "$D" && git commit -qam "add $br"; done
git checkout -q x
git merge --no-edit y >/dev/null 2>&1; [ "$(grep -c '^same 5$' "$D")" = 1 ] && ok "13b: a line added on both sides stays once" || bad "13b: duplicate line after merge: $(cat "$D")"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
