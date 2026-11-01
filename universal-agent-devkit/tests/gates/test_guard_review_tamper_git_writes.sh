#!/usr/bin/env bash
# hooks/guard-review-tamper.py, review finding 28b85d96f4 (#742 review REDUCED at 14108864): bash_hits dropped the ("git", dir)
# results of shell_writes, so a git command that rewrites the working tree from a ref or a patch went through:
#   git checkout REF -- .claude/settings.json universal-agent-devkit/hooks/review_gate.sh   (old fail-open gate, no guard registration)
#   git restore --source REF <hooks file>,  git apply / git am of a patch that edits hooks/ or bin/review*
# Denied now: a checkout / restore / reset / rm / mv / clean / stash operand that is protected, a folder holding the machinery
# (`.`, `universal-agent-devkit`) or a glob / pathspec magic; an apply / am whose patch (any file named on the line: operand, `<`,
# `cat f |`, the source of a `cp`) edits a protected path in its ---/+++/rename/copy headers, C-quoted ones included.
# Still allowed: commit / add (they leave the tree alone), patches of ordinary files, read-only git, a patch from a producer the
# guard cannot read (`agent-kit worktree diff … | git apply`: residual, same class as a script file that hides the names).
# Cases first drafted by r23b (01/11); r23 finished the fix.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_ALLOW_GATE_EDIT
DK="$(cd "$(dirname "$0")/../.." && pwd)"
G="$DK/hooks/guard-review-tamper.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
judge() {   # judge <command> [cwd] -> deny|allow
  python3 - "$G" "$1" "${2:-$TMP}" <<'PY'
import json, subprocess, sys
g, cmd, cwd = sys.argv[1:4]
p = subprocess.run([sys.executable, g], input=json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}, "cwd": cwd}),
                   capture_output=True, text=True, timeout=20)
print("deny" if '"deny"' in p.stdout else "allow")
PY
}
expect() { got="$(judge "$2" "${3:-$TMP}")"; [ "$got" = "$1" ] && ok "$1: ${2:0:110}" || fail "${2:0:140}: expected $1, got $got"; }
patch_of() {   # patch_of <file> <path in the patch>: a minimal unified diff that edits that path
  printf 'diff --git a/%s b/%s\nindex 1111111..2222222 100644\n--- a/%s\n+++ b/%s\n@@ -1 +1 @@\n-exit 2\n+exit 0\n' "$2" "$2" "$2" "$2" > "$1"
}
patch_of "$TMP/hook.diff"  universal-agent-devkit/hooks/review_gate.sh
patch_of "$TMP/bin.diff"   universal-agent-devkit/bin/review-merge.py
patch_of "$TMP/ci.diff"    .github/workflows/pr-review.yml
patch_of "$TMP/ok.diff"    src/app.py
{ printf 'From 0000 Mon Sep 17 00:00:00 2001\nSubject: [PATCH] x\n\n---\n'; cat "$TMP/hook.diff"; } > "$TMP/hook.mbox"
printf 'diff --git a/x.sh b/universal-agent-devkit/hooks/x.sh\nsimilarity index 100%%\nrename from x.sh\nrename to universal-agent-devkit/hooks/x.sh\n' > "$TMP/rename.diff"
printf 'diff --git "a/universal-agent-devkit/\\150ooks/review_gate.sh" "b/universal-agent-devkit/\\150ooks/review_gate.sh"\n--- "a/universal-agent-devkit/\\150ooks/review_gate.sh"\n+++ "b/universal-agent-devkit/\\150ooks/review_gate.sh"\n@@ -1 +1 @@\n-a\n+b\n' > "$TMP/quoted.diff"
mkdir -p "$TMP/sub" "$TMP/repo/universal-agent-devkit/hooks" "$TMP/repo/src" "$TMP/repo/.claude"
cp "$TMP/hook.diff" "$TMP/sub/p.diff"
: > "$TMP/repo/.claude/settings.json"

# the finding's three cases
expect deny 'git checkout f54dcefd -- .claude/settings.json universal-agent-devkit/hooks/review_gate.sh'
expect deny 'git restore --source f54dcefd universal-agent-devkit/hooks/review_gate.sh'
expect deny "git apply $TMP/hook.diff"
# the same family: other subcommands, -C, options, chains, a nested shell
expect deny 'git restore -s HEAD~3 -- .claude/settings.local.json'
expect deny 'git -C /repo checkout HEAD~1 -- universal-agent-devkit/bin/review-merge.py'
expect deny 'git reset f54dcefd -- universal-agent-devkit/hooks/guard-review-tamper.py'
expect deny 'git rm -q universal-agent-devkit/hooks/guard-review-tamper.py'
expect deny 'git mv universal-agent-devkit/hooks/review_gate.sh /tmp/x.sh'
expect deny 'git clean -fdx .github/workflows'
expect deny 'git stash push -m wip -- .claude/settings.json'
expect deny 'git fetch origin && git checkout origin/old -- .github/workflows/pr-review.yml'
expect deny "bash -c 'git checkout f54dcefd -- universal-agent-devkit/hooks/review_gate.sh'"
expect deny 'cd universal-agent-devkit/hooks && git checkout f54dcefd -- review_gate.sh' "$TMP/repo"
# a folder that holds the machinery, a glob, pathspec magic
expect deny 'git checkout f54dcefd -- .' "$TMP/repo"
expect deny 'git restore --source f54dcefd universal-agent-devkit' "$TMP/repo"
expect deny 'git reset f54dcefd -- . && git checkout -- .' "$TMP/repo"
expect deny 'git clean -fdx' "$TMP/repo"
expect deny "git checkout f54dcefd -- '*.sh'" "$TMP/repo"
expect deny 'git checkout f54dcefd -- :/' "$TMP/repo"
# patches
expect deny "git apply --3way $TMP/bin.diff"
expect deny "git apply -p1 --whitespace=fix $TMP/ci.diff"
expect deny "git am $TMP/hook.mbox"
expect deny "git apply $TMP/rename.diff"
expect deny "git apply $TMP/quoted.diff"
expect deny 'cd sub && git apply p.diff'
expect deny "git apply --directory=universal-agent-devkit/hooks $TMP/ok.diff"
expect deny "git apply --stat --apply $TMP/hook.diff"
expect deny "cat $TMP/hook.diff | git apply"
expect deny "git apply < $TMP/hook.diff"
expect deny "cp $TMP/hook.diff $TMP/ok2.diff && git apply $TMP/ok2.diff"
cp "$TMP/ok.diff" "$TMP/swap.diff"
expect deny "cp $TMP/hook.diff $TMP/swap.diff && git apply $TMP/swap.diff"
# ghi đè thư mục cha .git/.claude/.github bằng cp/mv/rsync/rm (8ec050fad4: cp -R /tmp/review-fanout <common>/.git/)
expect deny 'cp -R /tmp/rf .git/'
expect deny 'rsync -a /tmp/rf/ /repo/.git'
expect deny 'rm -rf .claude'
# still allowed
expect allow 'mkdir -p .claude/worktrees/wt1'
expect allow "git apply $TMP/ok.diff"
expect allow "git apply --check $TMP/hook.diff"
expect allow "git apply --stat $TMP/hook.diff"
expect allow 'git am --abort'
expect allow 'agent-kit worktree diff ../wt | git apply --3way'
expect allow 'git checkout -- src/app.py'
expect allow 'git restore src/app.py'
expect allow 'git checkout f54dcefd -- src' "$TMP/repo"
expect allow 'git checkout --detach f54dcefd'
expect allow 'git checkout -b feature/x'
expect allow 'git stash pop'
expect allow 'git stash push -u -m r23-wip'
expect allow 'git merge --no-edit origin/main'
expect allow 'git pull --no-rebase --no-edit'
expect allow 'git commit -m "fix universal-agent-devkit/hooks/guard-review-tamper.py" -- universal-agent-devkit/hooks/guard-review-tamper.py'
expect allow 'git add universal-agent-devkit/hooks/guard-review-tamper.py'
expect allow 'git log --oneline -- universal-agent-devkit/hooks/ .claude/settings.json'
expect allow 'git diff HEAD -- .claude/settings.json universal-agent-devkit/hooks/review_gate.sh'
expect allow 'git show f54dcefd:universal-agent-devkit/hooks/review_gate.sh'
[ "$FAILS" = 0 ] && { echo "guard review tamper git writes: all checks passed"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
