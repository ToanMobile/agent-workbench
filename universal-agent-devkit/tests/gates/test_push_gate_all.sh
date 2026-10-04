#!/usr/bin/env bash
# Regression (workflow audit 2026-10-04): `git push --all`, `--branches` and `--tags` were not gated AT ALL — the
# guard skipped its whole push block for those flags, so a commit no gate had passed went out (measured: exit 0 with an
# unpushed, ungated commit). Now:
#  --tags                every tag must point at a commit the remote itself already advertises (git ls-remote): it never
#                        uploads a new commit. Tags of unpushed commits, tags of trees, an unreachable remote → blocked.
#  --all / --branches    every local branch must have nothing new to send (its tip is already in the remote branch of
#                        the same name) or be covered by the gate receipt exactly like `git push origin <branch>`.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${HOOK:-$DEVKIT_DIR/hooks/block-dangerous-git.sh}"; GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
hook() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "${HCWD:-$TMP/repo}" \
  | CLAUDE_PROJECT_DIR="$TMP/repo" bash "$HOOK" >/dev/null 2>&1; }
expect() { hook "$2"; local rc=$?; [ "$rc" = "$3" ] && echo "✔ $1 (exit $rc)" || { echo "✖ $1: exit $rc, expected $3"; FAILS=$((FAILS + 1)); }; }
gate() { CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --run-tests --full --brief "$@" >/dev/null 2>&1; }

git init -q --bare "$TMP/remote.git"
mkdir -p "$TMP/repo/src" "$TMP/repo/.agents" && cd "$TMP/repo" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t && git remote add origin "$TMP/remote.git"
echo "fun ok() = 1" > src/Core.kt
printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}\n' \
  > .agents/regression_matrix.active.json
git add -A && git commit -qm c1 && echo "fun ok() = 2" > src/Core.kt && git commit -qam c2
git push -q -u origin main 2>/dev/null                    # c1, c2 are on the remote; the gate never ran
git tag v1 HEAD~1 && git tag -a v2a -m annotated HEAD
echo "fun ok() = 3" > src/Core.kt && git commit -qam c3   # local only, never gated
git tag v3 HEAD                                           # a tag of the unpushed commit

# ── --tags ────────────────────────────────────────────────────────────────────
expect "--tags with a tag of an UNPUSHED commit" "git push --tags origin" 2
expect "--tags after the remote name" "git push origin --tags" 2
expect "--tags with no remote named (default origin)" "git push --tags" 2
expect "--tags next to an ungated branch" "git push --tags origin main" 2
git tag -d v3 >/dev/null
expect "--tags when every tag is on the remote already" "git push --tags origin" 0
expect "…also without naming the remote" "git push --tags" 0
git tag treetag "$(git rev-parse 'HEAD^{tree}')"
expect "--tags with a tag of a TREE" "git push --tags origin" 2
git tag -d treetag >/dev/null
git update-ref refs/remotes/origin/zz "$(git rev-parse HEAD)"; git tag v3 HEAD
expect "a forged refs/remotes/origin/* does not make the unpushed commit look pushed" "git push --tags origin" 2
git update-ref -d refs/remotes/origin/zz; git tag -d v3 >/dev/null
git remote add dead /nonexistent/remote.git
expect "--tags to a remote that cannot be asked: no attestation" "git push --tags dead" 2

# ── --all / --branches ────────────────────────────────────────────────────────
expect "--all with an ungated commit on main" "git push --all origin" 2
expect "--all after the remote name" "git push origin --all" 2
expect "--all with no remote named" "git push --all" 2
expect "--branches with an ungated commit" "git push --branches origin" 2
git branch side HEAD~1
gate --diff origin/main
expect "--all: main is gated but a local branch (side) was never sent and the receipt is not in its history" "git push --all origin" 2
git branch -q -D side
expect "--all once the gate covers every branch" "git push --all origin" 0
expect "--branches once the gate covers every branch" "git push origin --branches" 0
echo "fun ok() = 4" > src/Core.kt && git commit -qam "after the gate"
expect "--all with a commit made after the gate" "git push --all origin" 2
expect "a plain branch push is still checked the same way" "git push origin main" 2

# ── found by the clean-context review (2026-10-04): each of these bypassed the first version ─────────────────
# Fixture of the review: main is covered by the gate receipt, the ungated work lives on a branch (side) and a tag (v4).
git reset -q --hard HEAD~1                                # drop "after the gate": main = the gated commit again
git checkout -q -b side && echo "fun ok() = 5" > src/Core.kt && git commit -qam c5 && git tag v4 HEAD && git checkout -q main
expect "baseline: main alone is covered, so a push of main passes" "git push origin main" 0
expect "baseline: the ungated branch alone is blocked" "git push origin side" 2
expect "abbreviated --tag" "git push --tag origin" 2
expect "abbreviated --ta" "git push --ta" 2
expect "abbreviated --al" "git push --al origin" 2
expect "abbreviated --branch" "git push --branch origin" 2
expect "abbreviated --b" "git push --b origin" 2
expect "refspec refs/tags/* sends v4" "git push origin 'refs/tags/*'" 2
expect "refspec refs/heads/* sends side" "git push origin 'refs/heads/*'" 2
expect "refspec refs/tags/*:refs/tags/*" "git push origin 'refs/tags/*:refs/tags/*'" 2
expect "a tree pushed as a tag" "git push origin 'side^{tree}:refs/tags/t'" 2
HCWD="$TMP/repo/.git" expect "cwd inside .git (rev-parse --show-toplevel fails there): the ungated branch" "git push origin side" 2
HCWD="$TMP/repo/.git" expect "cwd inside .git: --tags" "git push --tags origin" 2
expect "remote.<n>.push with a glob" "git config remote.origin.push 'refs/heads/*'" 2
expect "-c remote.<n>.push with a glob" "git -c remote.origin.push='refs/tags/*' push origin" 2
expect "push.default=matching sends every branch of the same name" "git config push.default matching" 2
expect "push.default=simple is fine" "git config push.default simple" 0
git clone -q --bare "$TMP/repo" "$TMP/fake.git" 2>/dev/null          # a server that already has every local commit
git remote add check "$TMP/fake.git"; git remote add pu "$TMP/fake.git"; git config remote.pu.pushurl "$TMP/remote.git"
expect "--recurse-submodules <mode> must not be read as the remote" "git push --tags --recurse-submodules check origin" 2
expect "pushurl differs from the fetch url: ls-remote asks the wrong server (--tags)" "git push --tags pu" 2
expect "the same for a plain tag push" "git push pu v4" 2
git clone -q "$TMP/remote.git" "$TMP/other" 2>/dev/null
expect "--git-dir=<other> points the check at another repository (--tags)" "git --git-dir=$TMP/other/.git push --tags origin" 2
expect "--git-dir=<other> with a plain branch push of the covered main" "git --git-dir=$TMP/other/.git push origin main" 2
expect "GIT_DIR=<other> with a plain branch push of the covered main" "GIT_DIR=$TMP/other/.git git push origin main" 2
expect "a commit message that merely MENTIONS --git-dir is not a retarget" "git commit -qm 'document --git-dir' --allow-empty" 0
# round 2 of the review: holes in the fixes themselves
expect "an unresolvable name next to a tag must not leave the tag shortcut on" 'b=side; git push origin v1 "$b"' 2
git remote add no "$TMP/fake.git"
expect "abbreviated --recurse <mode> must not be read as the remote" "git push --recurse no origin v4" 2
expect "abbreviated --recurse with --tags" "git push --tags --recurse no origin" 2
expect "quote-split export GIT_DIR does not hide the retarget" 'export GIT_""DIR='"$TMP"'/other/.git; git push origin main' 2
expect "quote-split --git-dir does not hide the retarget" 'git --git""-dir='"$TMP"'/other/.git push origin main' 2
expect "a commit message that mentions --git-dir, chained with a push of the covered main, is fine" "git commit -qm 'mention GIT_DIR and --git-dir' --allow-empty && git push origin main" 0
expect "-c remote.<n>.pushurl" "git -c remote.origin.pushurl=$TMP/remote.git push --tags origin" 2
expect "git config remote.<n>.pushurl" "git config remote.origin.pushurl $TMP/remote.git" 2
expect "-c url.<base>.pushInsteadOf" "git -c url.$TMP/remote.git.pushInsteadOf=$TMP/repo push origin v4" 2
expect "-c remote.pushDefault" "git -c remote.pushDefault=origin push --tags" 2
expect "-c branch.<b>.pushRemote" "git -c branch.main.pushRemote=origin push --tags" 2
expect "-c remote.<n>.push with a plain (non-glob) refspec" "git -c remote.origin.push=refs/heads/side push origin" 2
expect "git config remote.<n>.push with a tag refspec" "git config remote.origin.push refs/tags/v4" 2
expect "a dry run uploads nothing: never blocked" "git push --dry-run --tags origin" 0
expect "-n is a dry run too" "git push -n origin side" 0
git remote remove no
git tag -d v4 >/dev/null; git branch -q -D side
git config --unset remote.pu.pushurl; git remote remove pu; git remote remove check
sha="$(git rev-parse 'v1^{commit}')"
for i in $(seq 1 2500); do echo "create refs/tags/p$i $sha"; done | git update-ref --stdin
t0=$(date +%s); hook "git push --tags origin"; rc=$?; t1=$(date +%s)
[ "$rc" = 0 ] && [ $((t1 - t0)) -le 8 ] && echo "✔ 2500 tags, all on the remote: allowed in $((t1 - t0)) s (exit $rc)" \
  || { echo "✖ 2500 tags: exit $rc in $((t1 - t0)) s (want 0 within 8 s)"; FAILS=$((FAILS + 1)); }

git remote rename origin github >/dev/null 2>&1
expect "--tags with the default remote renamed (no origin): ask the real default remote" "git push --tags" 0
expect "--repo=<name> is the remote, not a refspec" "git push --tags --repo=github" 0
expect "--repo <name> with a tag refspec" "git push --repo github v1" 0
git remote rename github origin >/dev/null 2>&1
git branch -q old1 HEAD~1
expect "--all with a local branch the remote does not have: it would create a new branch" "git push --all origin" 2
git branch -q -D old1

[ "$FAILS" -eq 0 ] && echo "push gate --all/--tags: all checks passed" || { echo "push gate --all/--tags: $FAILS FAILED"; exit 1; }
