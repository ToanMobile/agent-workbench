# Ticket format

Canonical copy of the super-board ticket format, from `writing-standard.md` § 3. Onboard writes
it into the target's `docs/agents/issue-tracker.md` under `## Ticket format` (the file
`/to-tickets` reads); the AGENTS.md block only links there, so there is one copy to keep current.

```markdown
## Problem
<1–3 sentences: what is wrong or missing, from the user's side. No implementation plan.>

## Context
- **Where:** <page>, `<route>`
  - a. <step>
  - b. <step>
- **Who:** <who sees it>

![<page> · desktop](https://github.com/<owner>/<repo>/raw/<sha>/<path>.png)

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
| Title | `<emoji> [<kind>] <scope>: <what>` · ≤ 70 chars · no ticket number · e.g. `🐛 [bug] receipts: spinner never stops over 10 MB` |
| Context | lettered steps under Where, ONE per line · NEVER arrows · screenshot embedded for UI, NEVER linked |
| Bugs | add `## Evidence`: the folded 12-row table (writing-standard.md § 3) · a missing row says `n/a — why` |
| Acceptance Criteria | 2–5 `- [ ]` lines · each checkable · NEVER "works well", "is fast" |
| Risk | 🟢 Low · 🟡 Medium · 🔴 High + one line |
| Blocked by | `- #N — why` bullets, or a bare `- None.` · NEVER "None — but #N first" |
| Labels | `money`, `auth`, `schema` route the merge to a human (merge_policy) · `schema` = destructive only (DROP/TRUNCATE/RENAME); additive migrations need no label |
| Human-only step | a `needs-you: <command>` line in the PR body → 🙋 Blocked until done |
| Real device | label `needs-device` when the card's QA needs a real phone (OOM, FPS, memory, sensors) · while `adb devices` lists none (emulators and denylisted serials do not count) the board holds it in Ready (with `qa`) or QA and lists it under status "Waiting on you" · a phone plugged in releases it |
| Ticket only a person can do | `## Cần người` as the first section (`🙋 Cần bạn: <exactly what> · xong thì <next>`) + label `needs-you` + the same comment · createTask `--needs-you "<what>"` does all three |
| Size | one card = one PR · unset `auto_max_lines` is 0, so do not split for line count · a positive cap is opt-in and only then a bigger diff waits for a human · two unstarted cards that share a file fold into the lower number (AC copied verbatim) |

For recurring PR fixes, keep these sections. Context names the permitting shared boundary
and prior failing input/action; Evidence cites the prior PRs/findings. Fix names the intended
prevention, not an implementation plan. An AC requires the retained behavioral witness:
old failure for the reported reason, corrected pass and behavior-preserving refactor survival.
See [correction prevention](../../super-collect/references/correction-prevention.md).

When an unsettled design triggers [design preflight](design-preflight.md), keep the
approved choice and short rationale in Context, or link its applicable spec/ADR there.
Keep the same sections. Lint saves only the exact issue edit the user approves.
