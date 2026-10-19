# Issue tracker

Tickets live as GitHub issues on `ToanMobile/agent-workbench`, driven by the super-board project
board **Agent Workbench** (https://github.com/users/ToanMobile/projects/1).

| Item | Value |
|---|---|
| Columns | Backlog · Ready · Building · QA · Review · Blocked · Done |
| Type labels | `qa` (skips Building) · `bug` · `feature` (no label = feature) |
| Merge policy | robot merges normal changes; `money` / `auth` / destructive `schema` wait for a human |
| Verification | `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief` (exit 0 only) |

## Ticket format

```markdown
## Cần người          ← only when a step needs a person; omit otherwise
🙋 Cần bạn: <exactly what the person must do> · xong thì <what to do next>

## Problem
<1–3 sentences: what is wrong or missing, from the user's side. No implementation plan.>

## Context
- **Where:** <page>, `<route>`
  - a. <step>
  - b. <step>
- **Who:** <who sees it>

## Fix
<the intended change in 1–3 lines>

## Acceptance Criteria
- [ ] <checkable outcome a test can assert>
- [ ] <checkable outcome>

## Risk
🟢 **Low** · <one line>

## Blocked by
- #<N> — <why>          ← or exactly: - None.
```

| Rule | Value |
|---|---|
| Title | `<emoji> [<kind>] <scope>: <what>` · ≤ 70 chars · no ticket number |
| Context | lettered steps under Where, ONE per line · NEVER arrows |
| Bugs | add `## Evidence` with the 12-row table · a missing row says `n/a — why` |
| Acceptance Criteria | 2–5 `- [ ]` lines · each checkable · NEVER "works well", "is fast" |
| Risk | 🟢 Low · 🟡 Medium · 🔴 High + one line |
| Blocked by | `- #N — why` bullets, or a bare `- None.` |
| Human-only step | a `needs-you: <command>` line in the PR body → 🙋 Blocked until done |
| Needs a person | real device, playtest, store/legal account, owner-only secret, a decision → `## Cần người` first, label `needs-you` + one `🙋 Cần bạn` comment (`.claude/bin/super-board-needs-you.py mark`; createTask `--needs-you`) |
| Size | one card = one PR under 400 changed lines |
