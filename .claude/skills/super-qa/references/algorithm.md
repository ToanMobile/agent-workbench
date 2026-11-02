# Super QA — Algorithm, one iteration, bug-handling rule

> Moved out of `SKILL.md` (Claude Code cuts a SKILL.md above 20000 characters, #545). Text is unchanged; `SKILL.md` points here.

## Algorithm

### 1. Determine iteration count
- If user provides arg (e.g. `/super-qa 5`), use that count.
- If `--resume`, start at `max(existing iteration-*.md) + 1`.
- Default: **10 iterations, sequential**. (Concurrency is unsafe — workers
  share `queue.md`. To run parallel work, branch and run a second
  orchestrator.)

Report once: `🐛 Super QA starting — N iterations`.

### 2. For each iteration N (sequential)

**2a. Pre-flight**
- `next_n = max(existing iteration-*.md numbers in docs/super-qa/iter/) + 1`. If none exist, start at 1.
- Confirm working tree is clean (`git status` has no staged/unstaged tracked
  changes — untracked files are OK). If dirty → halt and notify.
- Verify `docs/super-qa/queue.md` exists. If not, refuse to dispatch
  and report — the queue is hand-seeded once via this skill's setup
  (or already by the commit that introduced the skill).

**2b. Launch the iteration worker**

Launch one sub-agent (Agent tool) in the repo root, no worktree, with
prompt = `references/iteration-preamble.md` + a per-iteration footer (iter
num, base SHA, mandatory final-commit format) and `SUPER_QA_FORENSICS=1`.
When it returns, classify the iteration:
- `0` iter complete — a `🧪 [test] super-qa: iter N` commit is on the current branch.
- `2` worker failed — it errored and left no done or WIP marker.
- `3` no done-commit — it finished but no `🧪 [test] super-qa: iter N` commit exists.
- `4` HUMAN GATE — its output contains `HUMAN GATE TRIPPED:`.
- `5` WIP-CHECKPOINT — it hit its budget mid-fix and left a `🚧 [wip] super-qa:` commit;
  the next iter picks it up.

Report: `🔍 Iter N launched`.

**2c. Wait, then advance**

On status 0:
- Read the close-out commit subject to extract `(X bugs, Y items)`.
- Report: `✅ Iter N done — X bugs, Y items processed`.
- Loop to next iteration.

On status 2 / 3 / 4 / 5:
- Report the worker's last output (its final 50 lines).
- Halt the loop (unless `--continue-on-error` was passed).
- Exit 4 (HUMAN GATE) is mandatory halt regardless — see "critical paths"
  below.
- Exit 5 (WIP) is **not** halt; the next iter's regression phase finds the
  red spec and finishes the fix. Continue.

### 3. Termination check (after every iter)

Stop when **any** of:

- Queue has no `[ ]` items left — natural completion.
- User-supplied iteration count `N` is reached (the `N` in `/super-qa N`).
- A halt gate fires (HUMAN GATE, dirty tree, worker status 2/3/4).
- User interrupts.

**Notification trigger (NOT a stop):** after 3 consecutive iters with zero
bugs found, report a summary like *"diminishing returns: 3 iters, 0
bugs, N items still in queue — continuing"*. The loop continues until the
queue actually drains (or `N` is reached). The user can interrupt manually
if they accept the diminishing returns.

Rationale: zero bugs in recent iters does not prove the unexplored remainder
of the queue is clean. The only way to know is to keep going. The previous
"3 zero-bug iters" auto-halt was budget pragmatism dressed up as completeness.

Coverage % is reported every iter as a progress indicator, never a gate.

### 4. Final report

After termination (or on halt):
- Aggregate: total iters, items moved from `[ ]` → `[x]` / `[b]` / `[!]`,
  total bugs found, total fixed, queue size now.
- Report a summary linking to all `docs/super-qa/iter/iteration-*.md`
  and the current `docs/super-qa/report/QA-REPORT.md`.

## One iteration, in plain English

The worker (per iter N) runs three phases:

**Phase 1 — Regression.** `npx playwright test e2e/paths/` against
everything. Any red spec? Apply the retry policy (re-run once in isolation).
Real reds get filed as bugs in `iteration-N.md`, fixed via TDD, re-run until
green. This is the "verify what we already have" step.

**Phase 2 — Explore.** Until the budget is hit (default: 5 cells popped
OR 30 min wall-clock):
1. Pop the top `[ ]` item from `queue.md`.
2. Classify via the URL-pattern heuristic in `docs/super-qa/page-types.md`.
3. Write a spec at `e2e/paths/<slug>.spec.ts` using the test recipe for that type.
4. Run it.
   - **Green** → mark `[x]`. Walk the rendered page; push newly-discovered
     children (links / buttons / dialogs / tabs — see preamble for the
     verbatim "what counts as a child" rule) to the back of the queue. Cap
     children pushed per page at **10**.
   - **Red** → file the bug to `iteration-N.md`. **Mark `[b]`. Do NOT push
     children.** Try to fix via TDD if budget allows; otherwise leave for
     next iter. After fix, re-mark `[ ]` so a future iter expands the
     subtree.

**Phase 3 — Report.** Write `docs/super-qa/iter/iteration-N.md` (bugs
found, items processed, queue size before/after, coverage snapshot). Run
`npm run qa:report:render`. Commit:
`🧪 [test] super-qa: iter N (X bugs, Y items, Z PRs opened)` (writing-standard.md § 1).

## The bug-handling rule (non-blocking)

> When a spec goes red, the worker logs the bug, marks the item `[b]`, **stops
> expanding into that subtree**, and continues with the rest of the iter's
> batch. Other siblings in the queue still get tested.

A bug on `/customers/:id` shouldn't block exploration of `/orders` or
`/dashboard`. Maximum coverage per iter; one bug never halts the loop.

Fix can happen:
- **Same iter** — if budget allows, the worker runs TDD on the bug after
  the explore phase.
- **Next iter** — if budget exhausted, the bug sits in `iteration-N.md` and
  Phase 1 of iter N+1 finds the red spec and finishes the fix.
- **Manually by human** — fix it whenever; the loop picks it up on the next
  regression pass.

After fix, the `[b]` item gets re-marked `[ ]` and a future iter processes
it (and pushes its children).
