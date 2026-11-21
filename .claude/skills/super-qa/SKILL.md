---
name: super-qa
description: >-
  Super QA canonical workflow for functional bug-bash, evidence capture, and fix-ready issue filing.
  Use when the user says "run super-qa", "QA review", "bug bash", "verify and fix", or invokes `/super-qa`.
---


**For a board worker, before writes or worktree creation:** follow [skill readiness](../super-board/references/skills-readiness.md).
Resolve this lane for the actual host, load the report's files/fallbacks, halt
on missing requirements and recheck each conditional helper before use.

# super-qa — BFS Route-Crawler that Builds the Spec Suite

Super QA crawls routes from `docs/super-qa/queue.md` with Playwright, records screenshots/logs/HARs,
files product-readable issues with clear type/priority/area labels, and continues until traversal is
complete or only human-gated blockers remain. Crawling is always browser-driven, but the regression
test it leaves behind is written at whichever layer the defect actually lives — unit or integration
in Vitest, e2e in Playwright only when the browser is the thing that broke.

## Standalone loop (/super-qa outside the board)

The standalone BFS loop's sections are in [references/standalone-loop.md](references/standalone-loop.md): Auth bootstrap —
auto-discover, never ask · Algorithm overview · Autonomous mode — NO AskUserQuestion mid-loop · The queue is the curation
surface · Recovery / re-entry · Stop conditions · Invocation patterns · Companion skill. Read it all before a standalone
`/super-qa` run. A board Tester opens only "Auth bootstrap", when an AC test needs a logged-in user.

- Never ask the user for a test login: discover or create one (Auth bootstrap).
- No AskUserQuestion mid-loop: decide and proceed; halt only on the real forks listed there.

## QA loop state board — GitHub Project as the state store

State for the QA↔Build loop lives in a GitHub Project named **`Super Ultimate QA`** (auto-discovered by title at the user/org level). It has six Status columns:

| Column   | Meaning                                              |
|----------|------------------------------------------------------|
| Queue    | Work the next iteration will pick up                 |
| Testing  | Feature currently being explored or verified         |
| Done     | Spec passing, no action needed                       |
| Bug      | Failing spec; Super Build picks these up next        |
| Flaky    | Only passes on retry; quarantine + investigate       |
| Skip     | Out of scope; documented and parked                  |

This board is the durable, machine-readable state for the loop. `docs/super-qa/queue.md` remains the BFS route seed and audit log, but **all actionable findings land on the project board** so the build lane can pick them up without parsing markdown.

### Project resolution

Resolution order (used by `.claude/bin/super-qa-file-bug.sh` and the orchestrator):

1. If `SUPER_QA_PROJECT_TITLE` is set, query `gh project list --owner $SUPER_QA_PROJECT_OWNER --format json` and pick the project whose title matches (case-insensitive).
2. Otherwise default to title `Super Ultimate QA`.
3. Owner defaults to `$(gh repo view --json owner -q .owner.login)` or `SUPER_QA_PROJECT_OWNER` if set.

If no matching project exists, the loop halts with a one-line error and instructs the operator to create one. Do not silently fall back to the repo's primary project — column semantics differ.

### Filing semantics

When the worker finds a red spec, it calls `.claude/bin/super-qa-file-bug.sh`. The script:

- Creates the issue with `source:qa` label and full evidence body.
- Adds the issue to the resolved **Super Ultimate QA** project.
- Sets the Status field to `Bug` (override with `SUPER_QA_TARGET_OPTION_NAME`).

A `Flaky` retry-only finding goes to `Flaky`; out-of-scope routes go to `Skip`. The same issue may also live on a repo-level project for normal triage — Status on the QA project is the loop state; status elsewhere is independent.

## Findings land in clear GitHub Issues · What counts as "green"

The issue body template, the filing guardrails and the non-blank guards with forensics are in [references/findings-and-green.md](references/findings-and-green.md). Read it before you file a finding or call a route green.

## Algorithm · One iteration, in plain English · The bug-handling rule

Iteration count, the per-iteration steps, the termination check, the final report and the non-blocking bug rule are in [references/algorithm.md](references/algorithm.md). Read it before you start the standalone loop.

## Page-type taxonomy · Critical paths (HUMAN GATE)

Both are in [references/page-types-critical-paths.md](references/page-types-critical-paths.md). A critical path (auth, payment, destructive action) is never exercised without the human gate there.

## Multi-step user journeys · Test-gap check (after build) · Skill dependencies

`docs/super-qa/flows.md` and its template, the Test-gap check (after build) and the skill list are in [references/flows-test-gap.md](references/flows-test-gap.md).

## Coexistence with `/super-build` · Test target & safety rails · Files involved

All three are in [references/coexistence-safety-files.md](references/coexistence-safety-files.md). Read the safety rails before you point the crawler at a target.

## super-board integration

When invoked by super-board (env `SUPER_BOARD_RUN=1` or invocation contains "super-board run"):

- **GitHub budget** — every "move card" is `.claude/bin/super-board-card.sh --config <cfg> move <N> <Status>` (1 GraphQL point; `gh project item-list` / `field-list` cost ~100–200). Comments, labels and PR reads go over REST; [rate-limit-etiquette.md](../super-board/references/rate-limit-etiquette.md) → "Price list" has the calls.

### State protocol (same as super-build)
- Read from issue + PR comments + PR review threads.
- Respect handed-down worktree + branch.
- After pushing tests, evidence or fixes to a PR, refresh [PR author notes](../super-board/references/pr-author-notes.md) before the handoff. Keep file summaries current and explain critical changed sections on the PR.

### Card types
- **Built card (`feature`, `bug`, no label):** worktree at `.claude/worktrees/issue-<N>-qa/` detached at `origin/<PR branch>`. The build worktree keeps the branch.
- **`qa` card (skipped Building):** move it Ready → QA yourself, create `issue-<N>-<slug>` from the base branch, test what is already there (run.md → "qa cards").
- **A live URL with no repo** is not a board card: `/super-qa <url>` runs standalone.

### Lifecycle (Tester, first pass)
See `.claude/skills/super-board/references/run.md` → Tester (first pass — repo-backed). Summary:
1. `git fetch origin`, then a detached worktree with the DevKit: `agent-kit worktree add .claude/worktrees/issue-<N>-qa --lane=qa --base=origin/<PR branch>`
   (no `agent-kit` on PATH: `python3 .agents/devkit/scripts/git/worktree.py add` with the same arguments). It does not check out the branch, so the
   build worktree keeps it — do not remove that worktree. Refresh with `git fetch origin` then `git -C .claude/worktrees/issue-<N>-qa checkout --detach origin/<PR branch>`.
   Push a QA evidence commit in two forms the DevKit hook accepts (it refuses a HEAD:<PR branch> refspec from a detached worktree). <sha> is the QA worktree HEAD sha: record it with git rev-parse HEAD right after you commit the evidence there and before any git switch. Find the worktree that holds the PR branch with git worktree list. A worktree holds it: fast-forward it there, git -C <build worktree> merge --ff-only <sha>, then git push origin <PR branch>. None holds it: in the QA worktree run git switch <PR branch> (checks out the local branch, or creates it from origin), then git merge --ff-only <sha>, then git push origin <PR branch>, each as its own command. If any command exits non-zero, or after the push git ls-remote origin <PR branch> is not <sha>: when the head moved (non-fast-forward rejection) go back to step 5b (#1302, never Block for it); any other failure: do not retry or force, Block the card naming it. Write test output to a LITERAL path (>/tmp/qa-<repo>-<N>-<file>.log, the repo name, issue number and test file name keep parallel QA runs apart), never a shell variable in a redirect target (the trunk-mode guard refuses it): run the test once per file or pipe the output instead of looping with a variable log name. A `qa` card with no PR branch yet creates `issue-<N>-<slug>` from the base (`--lane=qa --base=origin/<config.base_branch>` on the same path).
   The add links the DevKit, copies the git-ignored config and hooks, and clones a Unity Library copy-on-write. Exit 4 = under the disk floor: stop with its message, card and
   claims unchanged. Never a plain `git worktree add` or EnterWorktree (agent-workbench#93). Clean up the QA worktree with `agent-kit worktree remove <path>` (the branch stays; the build worktree stays until after the merge).
2. Read issue + PR + Builder's handoff.
3. Build issue-scoped test plan: ONE observable test per AC.
3a. Existing project verifier → follow [project-verifier.md](references/project-verifier.md)
for affected selection, host readiness, real assertions and fresh proof.
3b. Run the **Test-gap check** (above) against the Builder's diff; its High gaps join the plan.
3c. Run the **Security pass** ([security-pass.md](references/security-pass.md)) on the PR's diff. Any kept finding → Fail (step 7).
4. Run tests. Capture evidence to `docs/super-board/runs/issue-<N>-qa-v<N>/`. **For any UI-affecting issue, capture ≥1 screenshot per AC showing the exact state that AC describes (never a generic Home screen), and record the `adb devices` serial on Android runs** (`tester-verifiers-evidence.md`). Save as `ac1-<short-desc>.png`.
5. **Commit the evidence directory** (the test files you wrote were committed before the gate run, run.md 4c: the merge gate refuses a QA report whose sha has code or test commits after it), then push it as in step 1 (`git add docs/super-board/runs/issue-<N>-qa-v<N>/ && git commit`, then the step 1 push; if any command exits non-zero, or `git ls-remote origin <PR branch>` is not <sha> because the head moved, go back to step 5b (#1302: `super-board-qa-head.sh`, then `super-board-qa-sync.sh`), never Block for a moved head; any other failure: do not retry or force, Block the card). This is non-optional — without it, the inline image markdown in the issue comment won't render on GitHub. Keep it small: screenshots plus a `summary.md` of at most 40 lines, never raw runner output over 200 lines and never ANSI colour codes (run.md → Tester step 5, "Evidence stays small").
6. **Pass** → tick the PR's `ac` block with proof lines, write `visual` for UI, append a `history` row, rewrite `status` (`super-board-pr-body.sh`) → `[qa] [report] ✅` PR comment with results + evidence path → **issue comment with screenshot evidence** (see "Issue-comment evidence format" below) → move QA → Review. Clean up worktree.
7. **Fail** → leave failing ACs unchecked with the reason, append a `history` row, rewrite `status` → `[qa] [report] ❌` PR comment with per-AC expected/actual + repro file:line + evidence path + "what fixed should look like" → issue comment with the failure screenshots → increment rebuild counter → move QA → Ready (label `loop:rebuild-N`). Clean up worktree.

### Optional verifiers · Handoff comment · Issue-comment evidence format (REQUIRED, pass and fail)

The optional project feature verifier, the runtime performance and memory checks, the test command the pass-handoff PR comment must carry, and the issue-comment evidence format are in [references/tester-verifiers-evidence.md](references/tester-verifiers-evidence.md). The evidence format is required on every pass and every fail.

### Lifecycle (Tester, rebuild — when Reviewer bounced for [qa] thread fixes)
1. Read PR review threads; filter `[qa]` prefix.
2. For each unresolved `[qa]` thread: apply fix to test files → resolve thread via `gh api graphql resolveReviewThread`.
3. Re-run full test suite for the ticket.
4. Save evidence to `runs/issue-<N>-qa-v<N+1>/`.
5. Commit in the QA worktree, then push by the Tester push rule above (from the detached QA worktree a bare `git push` or `HEAD:<PR branch>` is refused). If any command exits non-zero, or `git ls-remote origin <PR branch>` is not <sha> because the head moved, go back to step 5b (#1302: `super-board-qa-head.sh`, then `super-board-qa-sync.sh`), never Block for a moved head; any other failure: do not retry or force, Block the card. Verify ALL `[qa]` threads resolved.
6. Update the PR's `ac`, `history`, `status` blocks; post `[qa] [report]` PR + issue comments (writing-standard.md § 4). Move QA → Review.

### Failure → `root-cause-hash:` line required
Hash lane = `qa`. Same input definition as super-build.

### Block/Skip exits use the §4 mandatory template
Same rule as super-build, including `super-board-needs-you.py mark` when a person must act
(a real device, a human judgement the AC asks for, a credential).

**Owner's standing decision.** A valid `[orchestrator] [decision]` comment on the card settles the AC or blocker it
names (what counts as valid: `.claude/skills/super-board/references/decision-policy.md` → "Máy đọc thế nào"; `.claude/bin/super-board-decision.py` is the only
judge): treat that AC as handled and do not raise the same blocker again. Never post `[decision]` yourself for the
card you work on, under any header: when a choice is needed, write the Block (block-template.md) and let the
orchestrator decide (run.md → "Owner's standing decision"). In your `[qa] [report]` list an AC settled that way
under ✅ with a link to the decision, never under ❌ Not done: the merge gate skips only the ❌ items of reports older
than the decision.

**Review-lane-only AC.** An AC only the Review lane can prove (independent review by a non-author) is never listed under `❌ Not done:`: the merge-gate `qa-report` check blocks every Not done item that names an AC, and only a newer `[decision]` clears it, so the card would loop to `rebuild_cap` (#1258 / PR #1292). Put it under `✅ Done:` as `ACn passed; independent review pending` and end the report with `Next: reviewer` (#1298).
