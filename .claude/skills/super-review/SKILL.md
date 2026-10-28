---
name: super-review
description: Reviewer lane of the super-board pipeline and standalone PR/branch readiness review — forms its own hypotheses before reading the builder's summary, remembers prior findings and re-checks each with file:line proof, runs an adversarial truth-check on non-trivial diffs, and classes every finding (Gap, Bug, Verification miss, Scope drift, Over-engineering via `ponytail:ponytail-review`). Merges only through `super-board-merge-gate.sh`, pinned to the reviewed head SHA, and routes other fixes to Super Build or Super QA via the board. Use when the user says "Super Review", "review this branch", "review loop", "make sure this is merge-ready", "PR review", or asks for code, architecture, security, QA evidence, or release-readiness judgment.
---


**For a board worker, before writes or worktree creation:** follow [skill readiness](../super-board/references/skills-readiness.md).
Resolve this lane for the actual host, load the report's files/fallbacks, halt
on missing requirements and recheck each conditional helper before use.

# Super Review — PR/code readiness reviewer

**Super Review** is the super-board reviewer. It checks whether a branch or PR is safe to merge, records actionable findings, and routes fixes to the right Super workflow.

Super Review should be conservative with claims: only say **merge-ready** when review evidence is clean and verification has passed. If evidence is missing, say what is unverified.

## When to use

Use this skill for:

- PR or branch review before merge.
- Code, architecture, security, data-model, or migration judgment.
- Release-readiness checks after Super Build, Super QA, or a human's `/ui-refine-loop` pass.
- The Review lane of a `super-board run`.
- A final pass that needs risks, blockers, and human gates summarized.

Do **not** use this as the primary implementation workflow. Route fixes to:

- **Super Build** for feature/task implementation from GitHub Project `Ready` issues.
- **Super QA** for functional bugs, broken behavior, failing Playwright paths, or missing QA coverage.
- Visual fidelity, layout, screenshots, wireframes, or design-system drift: file a UI ticket; a human can run `/ui-refine-loop`. The board never triggers it.

## Inputs

Accept any of these inputs:

- current branch or local diff;
- GitHub PR number or URL;
- commit range;
- user-provided file list;
- QA report, screenshots, or super-board wave report;
- release goal / done definition;
- `prior_report` — the previous review's findings on this PR (see "Review remembers"). Empty on a first review.

If the input is ambiguous, default to reviewing the current branch against its upstream/base branch. Ask only when the base branch, PR, or target scope materially changes the result.

## Review flow

The full step list is in [references/review-flow.md](references/review-flow.md). Read it before you start a review.

## Output format · Review Loop behavior · Review remembers

The report layout, the loop rules and the prior-findings memory are in [references/review-output.md](references/review-output.md). Read it before you write a report or review a second round.

## Common pitfalls

- Calling a branch **fixed** or **merge-ready** before tests or evidence prove it.
- Treating UI success or HTTP 200 as enough evidence for background jobs, uploads, or imports.
- Mixing reviewer findings with broad refactors.
- Creating duplicate GitHub issues without checking whether the finding is already tracked.
- Letting Super Review become another alias for Super Build; keep review authority separate from implementation authority.
- Re-reviewing a bounced card from scratch and ignoring `prior_report` — that is how a finding gets "resolved" without a fix and slips through.

## Done condition

Super Review is done when one of these is true:

- no blocking findings remain and the branch/PR has enough verification evidence to call it merge-ready;
- all unresolved findings are explicitly human-gated;
- required evidence cannot be collected because tooling/service access is unavailable, and the output clearly marks the result as unverified.


## Skill dependencies · Deepening opportunities

Both are in [references/review-skills-deepening.md](references/review-skills-deepening.md).

## super-board integration

When invoked by super-board (env `SUPER_BOARD_RUN=1` or invocation contains "super-board run"):

### State protocol
- Read from issue + PR comments + PR review threads.
- **GitHub budget** — every "move card" is `.claude/bin/super-board-card.sh --config <cfg> move <N> <Status>` (1 GraphQL point; `gh project item-list` / `field-list` cost ~100–200). Comments, labels and PR reads go over REST; [rate-limit-etiquette.md](../super-board/references/rate-limit-etiquette.md) → "Price list" has the calls.
- Respect handed-down worktree at `.claude/worktrees/issue-<N>-review/` and branch `issue-<N>-<slug>`.

### Two card types
- **Built card (`feature`, `bug`, no label):** review the diff (code + tests).
- **`qa` card:** review the QA report quality and any test diff; there is no product-code diff.

### Lifecycle (Reviewer)
See `.claude/skills/super-board/references/run.md` → Reviewer. Summary of the sub-steps:

1. Worktree from current state of `issue-<N>-<slug>`, made by the DevKit and detached (the Reviewer commits nothing, and a branch
   another lane's leftover worktree still holds cannot be checked out twice): `git fetch origin`, then
   `agent-kit worktree add .claude/worktrees/issue-<N>-review --lane=review --base=origin/issue-<N>-<slug>` (no `agent-kit` on PATH:
   `python3 .agents/devkit/scripts/git/worktree.py add` with the same arguments). It links the DevKit, copies the git-ignored config and
   hooks, clones a Unity Library copy-on-write, takes no WORKTREE_MAX slot and marks the checkout the board's. Exit 4 = under the disk
   floor: stop with its message, card and claims unchanged. Never a plain `git worktree add` or EnterWorktree (agent-workbench#93).
   Clean up with `agent-kit worktree remove <path>` (no agent-kit on PATH: `python3 .agents/devkit/scripts/git/worktree.py remove`; a
   plain `git worktree remove` refuses the DevKit set-up every lane worktree carries).
2. **Gate 1 — thread scan.** Read threads and replies. [PR author notes](../super-board/references/pr-author-notes.md)
   alone are explanations, not findings or approval. Human questions or change requests
   in those threads still follow the normal review/blocking flow; the marker exempts no
   replies. Never auto-resolve them or bypass GitHub's conversation-resolution requirements.
   If ANY unresolved finding:
   - `[builder]` open → comment, move card Review → Ready.
   - `[qa]` open → comment, move card Review → QA.
   - Both open → bounce to whichever is older.
   - Clean up worktree, exit.
3. Read PR + spot-check Tester evidence + read CLAUDE.md / AGENTS.md.
   **3b. Prior-report check** — load `prior_report` (see "Review remembers"); if present, round 1 checks each prior finding; any `not fixed` → re-open its thread, bounce by prefix, post the report, exit.
4. Review code + tests.
5. **Reviewer-side test rerun (always — closes Tester self-verification gap):**
   - Bring the review worktree to the PR head: `git fetch origin && git checkout --detach origin/issue-<N>-<slug>`.
   - Re-run the EXACT command from Tester's PR `Local tests:` line.
   - Exception: the DevKit gate is never rerun here — never rerun post-fix-gate --full; read from QA's report the impacted `post-fix-gate.py --run-tests` exit 0 (its task receipt) for this exact head SHA. The merge point (the merge queue's train; queue off, the merge gate's `--force-full`) verifies the merged tree (run.md → Merge protocol).
   - Green → continue. Red → open new `[qa]`-prefixed thread quoting failure, move card Review → QA with `loop:rebuild-N`, exit.
   - If QA includes `Runtime checks:`, follow
     [optional runtime verification](../super-qa/references/runtime-verification.md):
     rerun the same scenario/config and pinned versions into new review evidence,
     check hashes/revisions and performance AC budgets. Never infer a speed win
     from exit 0 or an inconclusive result. Runtime checks supplement local tests.
6. **Adversarial mode** (per `config.truth_gate` — `off` / `non-trivial` / `always`, default `non-trivial`): see section below.
7. Decide per finding. First apply the Over-engineering rule to every finding collected —
   yours, `ponytail:ponytail-review`'s and the truth-check sub-agents': Over-engineering is
   Should fix, never Blocker, and never on its own a reason to bounce or block. Then:
   - **Deepening opportunity** → `.claude/bin/super-review-file-refactor.sh`, then keep going. It is not a finding for merge purposes and never bounces a card.
   - **No findings (Over-engineering aside) + threads clean + truth ≥ threshold + tests green** → run the **merge protocol** (below). Never move a card to Done any other way.
   - **Over-engineering only** (from `ponytail:ponytail-review`, see super-review step 3) → list it in the report, open no thread, and carry on to the merge decision; it never bounces a card alone. When the card bounces for another finding anyway, open a `[builder]` thread for each Over-engineering finding too, so the rebuild trims it.
   - **Code-side new finding** → new `[builder]`-prefixed thread, move card Review → Ready (`loop:rebuild-N`).
   - **Test-side new finding** → new `[qa]`-prefixed thread, move card Review → QA (`loop:rebuild-N`).
   - **Blocker finding (destructive schema, contract, money, auth, live-DB migration) or rebuild cap hit** → full §4 Block template, move card Review → Blocked; a block a person must clear also runs `super-board-needs-you.py mark` (block-template.md → "A person must act"). A *clean* PR that merely touches money, auth or schema is not a finding: run the merge protocol, and the gate's `merge_policy` hands it to a human (exit 7 → 🙋 Blocked).
8. Write the Reviewer report (marker `<!-- super-review:report -->`, ids on every finding) — edit the existing report comment in place, post a new one only on the first review. It is the next re-review's `prior_report`.
9. Clean up worktree.

### Merge protocol — Done means merged

Builder opens PRs as **drafts**, and GitHub never auto-merges a draft. Skipping the
`gh pr ready` step is why a six-hour run landed zero commits on `main` while producing
two complete builds. In order, no shortcuts:

1. `gh pr ready <PR>` — idempotent, safe on an already-ready PR.
   **Inside the board with the merge queue on** (config `merge_queue.enabled` or `SB_MERGE_QUEUE=1`, AND `worker_backend: "claude-p"`
   without `--codex`, whose runner drains the queue every tick): never call the merge gate (it refuses a direct call, exit 13). Post `approved-head:<sha40>` on the PR as its own comment, add
   the label `merge-queue`, comment on the issue `[reviewer] [report] ✅ merge-ready · queued PR #<P> @ <sha7>`, write
   the report (`merge-ready`) and leave the card in **Review**: the queue merges it in one train (run.md → Merge
   protocol). Queue off inside the board (`SB_MERGE_QUEUE=0`, not enabled, or the workflow backend (default) / `--codex`,
   where nothing drains the queue — even when the config enables it): step 2 as below.
2. Merge through the gate, pinned to the head you reviewed (`merge_policy.default: "human"`
   sends every merge to exit 7 below; a cross-review marker or a human `done` approves it):
   record `gh pr view <PR> --json headRefOid` when review passes, then
   `super-board-merge-gate.sh --config <cfg> --pr <PR> --expect-head <sha> --subject "<PR title>"
   --body-file <msg.md>` (it merges with `--match-head-commit`; the message is the PR title plus the
   commit bullets and `Closes #N` — writing-standard.md § 1). Add `--standalone` only when `/super-review` runs on its
   own, outside the board — never inside a board lane: there the runner sets `SB_BOARD_WORKER=1` and, with the queue on,
   the gate refuses `--standalone` (exit 13). Exit 6 = the head moved after review → your evidence is void;
   leave the card in **Review** with a `[reviewer]` comment naming both shas.
   The gate owns the merge decision (config `merge_policy`, `migrations`):
   - **Exit 9 — verification-readiness.** Halt the run; preserve card, approval, claims, and worktree. Configure `verify_commands` with the owning project's real checks — or, when the gate says the scratch tree has no `post-fix-gate.py`, repair the main checkout's DevKit install — and restart explicitly. No bounce to Build, rebase retry, approval request, or bare merge.
   - **Exit 2 / 5 — stale branch or real conflict.** Rebase pass (run.md → "The rebase pass").
   - **Exit 11 — verify red, branch NOT behind the base.** A rebase changes nothing: open a `[builder]` thread quoting the gate's "verify failed (exit N: …)" line, move Review → Ready with `loop:rebuild-N`.
   - **Exit 7 — a human merges.** `merge_policy` matched (money / auth / schema label,
     path or added-line keyword; a diff over `auto_max_lines`, default 400 — "big PR — please
     review"; `default: "human"`). `schema` means destructive only (DROP / TRUNCATE / RENAME);
     an additive migration follows `migrations.allowed_envs`, and a live DB is always human.
     Card → **Blocked** with the 🙋 template: `Why blocked` quotes the gate's
     `human-gate:` lines; `To unblock` = review PR #<P> and merge it yourself, OR comment
     `done` to approve (the next wave re-runs the gate, which merges). Mark the card:
     `super-board-needs-you.py mark --repo <owner/name> --issue <N> --action "Review PR #<P>" --next "comment đúng một chữ done trên issue để duyệt (hoặc tự merge PR #<P>)"`.
   - **Exit 8 — 🙋 needs you.** Migrations for a database outside
     `migrations.allowed_envs`, an allowed migrate command that failed, or a declared
     human-only step. Card → **Blocked** with the 🙋 template
     (`block-template.md` → "🙋 Needs you"), the gate's `needs-you:` commands copied
     verbatim into `To unblock`, `blocked-by: -`, and mark the card with
     `super-board-needs-you.py mark --repo <owner/name> --issue <N> --action "<the commands, shortened to 500
     characters: the full ones are in the Block comment>" --next "comment đúng một chữ done trên issue để duyệt (hoặc tự merge PR #<P>)"`. After the human
     comments `done` after the current pinned request, the next wave verifies their
     permission and the head, then moves it to Review. Re-run the gate; labels do not
     authorize it. For exits 7 and 8, copy `approval-request:` into the canonical
     issue block and link it from the PR (no duplicate request); see block-template.md.
   - **Cross-review replaces `done` (#605).** When the gate `--full` is green and your
     cross-review is complete (you are not the builder), post on the issue that holds the
     request, last (after the Block comment and its request), as its own comment with nothing
     else, besides `approved-head:<sha40>`:
     `cross-review-approved: {"repo":"<owner/name>","pr":<P>,"head":"<sha40>","scope":"<request scope>","reviewer":"<you>","builder":"<builder>","task_id":"<id>","gate_receipt":"<receipt sha/id>"}`
     (repo/pr/head/scope copied from the request). `super-board-approval.py` accepts it in place
     of `done`, except when the plan has `schema` or `delete-protected` (a deleted
     `merge_policy.protected_paths` file) or any `needs-you:` step: those still need a human `done`.
   - The rule in one line: the robot migrates the databases it was allowed to test its
     work; live databases, money, auth and destructive schema changes wait for a person.
3. **Confirm the merge landed** — never trust the merge command's exit code:
   **Exit 79 — required GitHub evidence unavailable:** stop the current run. Leave
   the card, approval, claims, and worktree intact. Report the local halt reason;
   do not classify missing data as safe, bounce it to Build, or post a new approval
   request. Explicit recovery is in run-workflow.md → Required GitHub evidence.

   `gh pr view <PR> --json state,mergeCommit` must report `MERGED` plus a commit sha,
   and that sha must be an ancestor of the base branch
   (`git merge-base --is-ancestor <sha> origin/<base>`).
4. Only then: close the issue, move card Review → **Done**, post the ✅ comment citing
   the merge commit sha. Exception (T0054): the gate printed `ac-open: #N` — the PR merged with AC lines still
   unproven, so the gate kept the issue open with label `ac-open` and moved the card to Ready. Do NOT close it or
   move it to Done (card.sh refuses exit 5); post the merged comment and stop.
5. Merge refused (failing checks, conflicts, branch protection) → card Review →
   **Blocked** with the §4 Block template naming the blocker. Never leave it in Review;
   a card left in Review gets re-picked and re-reviewed indefinitely.

**Invariant:** a card in `Done` has its code on the base branch. The run loop's
landed-work halt gate reads `Done` as its definition of progress, so a card marked Done
without a confirmed merge makes a runaway look like a healthy run.

### Prefix discipline
- Every new review thread Reviewer writes MUST start with its owner lane — `[builder]`, `[qa]`, or `[reviewer]` — then a label: `[blocker]`, `[issue]`, `[suggestion]`, `[nit]`, `[question]`, `[praise]` (writing-standard.md § 4). Older PRs may carry `[QA]` / `[review]`; read them as `[qa]` / `[reviewer]`.
- Unprefixed **top-level** human PR comments → treat as 🧑 Block reason. Move card Review → Blocked with the full §4 template.
- Inline human review-thread replies → context only, no Block.

### `super-truth` is folded into super-review
The standalone `super-truth` skill is removed (spec §10 item 8.9). The adversarial pattern is now built in — see next section.

## Adversarial mode (folded from super-truth)

The fixed truth-check sub-agent brief, which the Reviewer uses verbatim, and the rules for its findings are in [references/adversarial-mode.md](references/adversarial-mode.md). Never write your own brief.

### Block/Skip exits use the §4 mandatory template
Same rule as super-build/super-qa.
