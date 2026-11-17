#!/usr/bin/env bash
# #1235: the Reviewer's edited-test audit must use the review worktree as project and call pm_dispatch kind=audit WITHOUT `message`
# (with `message` or a project not at the PR head the PM records no scope and the merge gate ignores the audit).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
for f in .claude/skills/super-review/SKILL.md .claude/skills/super-board/references/run.md; do
  p="$ROOT/$f"
  if grep -q 'pm_task_create` (project = config `repo.path`)' "$p"; then fail "$f still says project = config repo.path for the audit"; else ok "$f: no project = config repo.path"; fi
  grep -q 'issue-<N>-review' "$p" && grep -q 'WITHOUT `message`' "$p" && grep -q 'Pham vi:' "$p" && grep -q 'Khong ghi pham vi' "$p" \
    && ok "$f: review worktree, no message, Pham vi: check" || fail "$f: missing review-worktree / WITHOUT message / Pham vi: wording"
done
echo
[ "$FAILS" -eq 0 ] && { echo "test_super_review_audit_scope_1235: PASS"; exit 0; } || { echo "test_super_review_audit_scope_1235: FAIL ($FAILS)"; exit 1; }
