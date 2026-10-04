#!/usr/bin/env bash
# Regression (workflow audit 2026-10-04): pushing a release TAG of a commit the remote already has was
# blocked ("lần gate PASS gần nhất … không nằm trong lịch sử của v1.2.4"): the guard wants every push to
# contain the commit the last full gate passed, which an old tag never does — though such a push uploads
# nothing. Allowed now ONLY for plain tag pushes whose commits are all on the remote already.
# Everything else keeps the gate: a tag of an unpushed commit, a tag next to a branch, any forced or
# deleting push, a name that is both a branch and a tag, and a remote that is not a configured name.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${HOOK:-$DEVKIT_DIR/hooks/block-dangerous-git.sh}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
hook() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$TMP/repo" \
  | CLAUDE_PROJECT_DIR="$TMP/repo" bash "$HOOK" >/dev/null 2>&1; }
expect() { hook "$2"; local rc=$?; [ "$rc" = "$3" ] && echo "✔ $1 (exit $rc)" || { echo "✖ $1: exit $rc, expected $3"; FAILS=$((FAILS + 1)); }; }

git init -q --bare "$TMP/remote.git"
mkdir -p "$TMP/repo/src" "$TMP/repo/.agents" && cd "$TMP/repo" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t && git remote add origin "$TMP/remote.git"
echo "fun ok() = 1" > src/Core.kt
printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}\n' \
  > .agents/regression_matrix.active.json
git add -A && git commit -qm c1 && echo "fun ok() = 2" > src/Core.kt && git commit -qam c2
git push -q -u origin main 2>/dev/null                    # c1, c2 are on the remote; no gate run at all in this repo
git tag v1 HEAD~1 && git tag -a v2a -m "annotated" HEAD
echo "fun ok() = 3" > src/Core.kt && git commit -qam c3   # local only
git tag v3 HEAD
git branch side HEAD~1 && git tag side HEAD~1             # one name that is both a branch and a tag
git tag rel HEAD~1 && git push -q origin HEAD~2:refs/heads/rel   # tag "rel" (pushed commit) vs a REMOTE branch rel
git tag ORIG_HEAD HEAD && git rev-parse HEAD~1 > .git/ORIG_HEAD   # a tag named like a pseudoref, on the unpushed commit
git tag treetag "$(git rev-parse 'HEAD^{tree}')"                  # a tag of a TREE
git clone -q "$TMP/remote.git" "$TMP/other" 2>/dev/null           # another repository

expect "tag of a pushed commit (lightweight)" "git push origin v1" 0
expect "tag of a pushed commit (annotated)" "git push origin v2a" 0
expect "refs/tags/ form" "git push origin refs/tags/v1" 0
expect "v1:refs/tags/v1 form" "git push origin v1:refs/tags/v1" 0
expect "two such tags at once" "git push origin v1 v2a" 0
expect "cd + tag push" "cd $TMP/repo && git push origin v1" 0
expect "tag of an UNPUSHED commit stays gated" "git push origin v3" 2
expect "a tag together with an ungated branch stays gated" "git push origin v1 main" 2
expect "tag of a pushed commit + a tag of an unpushed one" "git push origin v1 v3" 2
expect "git push --force stays gated" "git push --force origin v1" 2
expect "git push -f stays gated" "git push -f origin v1" 2
expect "+tag stays gated" "git push origin +v1" 2
expect "--force-with-lease stays gated" "git push --force-with-lease origin v1" 2
expect "--delete stays gated" "git push origin --delete v1" 2
expect ":tag (delete) stays gated" "git push origin :v1" 2
expect "a name that is both a branch and a tag stays gated" "git push origin side" 2
expect "a remote given as a URL (not a configured name) stays gated" "git push $TMP/remote.git v1" 2
expect "a plain branch push is untouched (no receipt → blocked)" "git push origin main" 2
# found by the clean-context review (2026-10-04): each of these bypassed the first version
expect "X:X where the remote has a BRANCH X would move that branch" "git push origin rel:rel" 2
expect "…but the tag alone is a tag push" "git push origin rel" 0
expect "a tag named ORIG_HEAD resolves to the pseudoref, not the tag" "git push origin ORIG_HEAD" 2
expect "--git-dir points the check at another repository" "git --git-dir=$TMP/other/.git push origin v1" 2
expect "GIT_DIR points the check at another repository" "GIT_DIR=$TMP/other/.git git push origin v1" 2
git update-ref refs/remotes/origin/zz "$(git rev-parse HEAD)"
expect "a forged refs/remotes/origin/* does not make an unpushed commit look pushed" "git push origin v3" 2
git update-ref -d refs/remotes/origin/zz
expect "a tag of a tree next to a good tag rides along unchecked: stays gated" "git push origin v1 treetag" 2
git remote add dead /nonexistent/remote.git
expect "a remote that cannot be reached: no attestation, stays gated" "git push dead v1" 2

[ "$FAILS" -eq 0 ] && echo "push gate tags: all checks passed" || { echo "push gate tags: $FAILS FAILED"; exit 1; }
