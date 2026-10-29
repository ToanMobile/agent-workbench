---
name: super-qa
description: >-
  Super QA canonical workflow for functional bug-bash, evidence capture, and fix-ready issue filing.
  Crawls routes from `docs/super-qa/queue.md` with Playwright, records screenshots/logs/HARs, files
  product-readable issues with clear type/priority/area labels, and continues until traversal is
  complete or only human-gated blockers remain. Crawling is always browser-driven, but the regression
  test it leaves behind is written at whichever layer the defect actually lives — unit or integration
  in Vitest, e2e in Playwright only when the browser is the thing that broke. Use when the user says
  "run super-qa", "QA review", "bug bash", "verify and fix", or invokes `/super-qa`.
---


**For a board worker, before writes or worktree creation:** follow [skill readiness](../super-board/references/skills-readiness.md).
Resolve this lane for the actual host, load the report's files/fallbacks, halt
on missing requirements and recheck each conditional helper before use.

# super-qa — BFS Route-Crawler that Builds the Spec Suite

## Auth bootstrap — auto-discover, never ask

Before iter 1, resolve a test login. **Never ask the user; discover or create.** Order:

1. **Cached creds** at `.claude/settings.local.json` `.e2e.user` / `.e2e.pass` — use them as-is.
2. **Env-file fallback** — read in order: `.env.production.local`, `.env.local`, `.env`. Pull `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`. If both present, auto-create `e2e-test@<owner-domain>` (owner from `git config user.email` domain, fallback `erictech.ca`) via:
   ```bash
   curl -sS -X POST "$SUPABASE_URL/auth/v1/admin/users" \
     -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
     -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
     -H "Content-Type: application/json" \
     -d "{\"email\":\"$E2E_USER\",\"password\":\"$E2E_PASS\",\"email_confirm\":true,\"user_metadata\":{\"role\":\"e2e-test\",\"created_by\":\"super-qa-bootstrap\"}}"
   ```
   Generate a 24-char random password (`openssl rand -base64 24 | tr -d '/+=' | cut -c1-24`). Save to `.claude/settings.local.json` `.e2e` so the next run skips bootstrap. Verify by logging in (`POST /auth/v1/token?grant_type=password` returns access_token).
3. **Unauth-only fallback** — if neither cached creds nor env-file admin key exist, log "no admin key — restricting to public routes" and proceed with `/login`, `/signup`, `/forgot-password` only. Do NOT halt.

The bootstrap is **non-interactive**. If the curl returns an existing-user error (`User already registered`), reset the password via the same admin endpoint and continue. Save creds either way.

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

## Algorithm overview

You are the orchestrator. Your job: drive a BFS crawl of the target app
that **builds `e2e/paths/` into a comprehensive Playwright suite** while
fixing any bugs it stumbles on. Each iteration is a fresh worker — a sub-agent you launch in this
session with the Agent tool — that does ONE iter and exits. There is no
worktree: the worker commits directly to the active branch (default `main`).
This pack ships no headless dispatcher for this loop.

## Autonomous mode — NO AskUserQuestion mid-loop

`/super-qa` is invoked by an operator who walks away (often overnight). The loop must run end-to-end without the
orchestrator pausing on `AskUserQuestion`.

**Decide-and-proceed, don't ask, on these classes of issue:**

- Harness script bugs (parser errors, broken xargs, missing
  `chmod +x`, stale lock files). Fix locally, commit as `🐛 [fix] super-qa: <what>`
  (writing-standard.md § 1), then continue.
- Missing env auto-loads, leftover MCP zombies, log-dir creation.
- Lint / formatting nits introduced by the worker that block its own commit.
- Choosing between equivalent dispatch modes (sequential vs sequential —
  parallel is unsafe, never picked).

**Still halt on these (real forks):**

- Critical-path HUMAN GATE (worker status 4) — production money flow
  red >2 iters. Mandatory halt per skill contract.
- Worker status 2 / 3 with an error that isn't a script bug
  (e.g. Anthropic API down, a production 503, auth credential rejected).
- Working tree dirty with changes the orchestrator didn't make (could be
  user's in-flight work).
- Anything that would delete or rewrite history (`git reset --hard`,
  force-push, branch deletion).

**Status updates instead of questions:** when you make an autonomous fix,
report it in the next status message — what was broken, what you committed
(with SHA), and a one-line revert path, in the session output.

After this loop has run for a while, `e2e/paths/` is the deliverable. CI runs
`npm run test:e2e` on every PR. **No AI involvement in steady-state
regression.** AI is only needed to extend the suite when new pages ship.

```
                AI loop (build phase)            CI (steady state)
               ─────────────────────             ──────────────────
/super-qa      →  e2e/paths/    →    npm run test:e2e on PR
(drains queue.md,        grows toward         catches regressions
 fixes bugs)             comprehensive        without any AI tokens
```

**This skill is INDEPENDENT of `/super-build`.** They share no state.
`super-build` executes new sessions from the GitHub Project board (forward
progress); `super-qa` hardens what already ships by exhaustively
walking the route tree.

## The queue is the curation surface

`docs/super-qa/queue.md` is a markdown checklist the loop reads from
and writes to. Four states per line:

- `[ ]` queued — will be popped next
- `[x]` green spec exists (links to the spec file + iter discovered)
- `[!]` skipped permanently (with reason)
- `[b]` bug found here, children NOT pushed; will be re-tried after fix
- `[?]` flaky — passed on retry, not a bug yet (see flaky policy below)

The queue is **append-only at the back** during normal exploration. The user
can hand-edit it to reorder (turn BFS into DFS for one branch, push something
to the front, etc.). The skill respects whatever the user wrote.

The seed is `client/src/routes.ts` — every static route becomes a `[ ]`
entry under "Level 0".

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

## Recovery / re-entry

- Default: starts a new batch numbered after the last `iteration-*.md`
  (e.g. if iters 1-5 exist, the next batch starts at 6).
- `--resume`: only run iters whose number is greater than `max(existing)`.
- A leftover `🚧 [wip] super-qa:` commit on the current branch (from a status-5 iteration)
  is OK — the next iter's regression phase finds the red spec and finishes
  the fix.

## Stop conditions

- Queue empty (no `[ ]` items left) — natural completion.
- Iteration count reached (the user-supplied `N`).
- Worker status 2 / 3 / 4 — halt and report.
- User interrupts.

**Note:** "3 consecutive zero-bug iters" is **no longer** a stop condition.
It triggers a "diminishing returns" report but the loop
continues exploring the rest of the queue. See "Termination check" above
for rationale.

## Invocation patterns

- `/super-qa` → 10 iters, sequential, default budget
- `/super-qa 5` → 5 iters
- `/super-qa --resume` → continue from `max(existing) + 1`
- `/super-qa --continue-on-error` → don't halt on a single iter failure

## Companion skill

`/super-build` executes pending issues from the GitHub Project board.
Independent of this skill — they share no state. Run `/super-build` to make
forward progress; run `/super-qa` to grow the spec suite + harden
shipped code.

## super-board integration

When invoked by super-board (env `SUPER_BOARD_RUN=1` or invocation contains "super-board run"):

- **GitHub budget** — every "move card" is `.claude/bin/super-board-card.sh --config <cfg> move <N> <Status>` (1 GraphQL point; `gh project item-list` / `field-list` cost ~100–200). Comments, labels and PR reads go over REST; [rate-limit-etiquette.md](../super-board/references/rate-limit-etiquette.md) → "Price list" has the calls.

### State protocol (same as super-build)
- Read from issue + PR comments + PR review threads.
- Respect handed-down worktree + branch.
- After pushing tests, evidence or fixes to a PR, refresh [PR author notes](../super-board/references/pr-author-notes.md) before the handoff. Keep file summaries current and explain critical changed sections on the PR.

### Card types
- **Built card (`feature`, `bug`, no label):** worktree at `.claude/worktrees/issue-<N>-qa/` checked out at Builder's branch tip.
- **`qa` card (skipped Building):** move it Ready → QA yourself, create `issue-<N>-<slug>` from the base branch, test what is already there (run.md → "qa cards").
- **A live URL with no repo** is not a board card: `/super-qa <url>` runs standalone.

### Lifecycle (Tester, first pass)
See `.claude/skills/super-board/references/run.md` → Tester (first pass — repo-backed). Summary:
1. `git fetch origin`, then the worktree with the DevKit: `agent-kit worktree add .claude/worktrees/issue-<N>-qa issue-<N>-<slug> --lane=qa --base=origin/<config.base_branch>`
   (no `agent-kit` on PATH: `python3 .agents/devkit/scripts/git/worktree.py add` with the same arguments). It checks out the Builder's branch as
   it is (one only origin has from origin/<branch>; a `qa` card's new branch from the base), links the DevKit, copies the git-ignored config and
   hooks, clones a Unity Library copy-on-write. Exit 4 = under the disk floor: stop with its message, card and
   claims unchanged. Exit 1 naming a worktree that holds the branch (the Builder's leftover): `agent-kit worktree remove` that path
   (no agent-kit on PATH: `python3 .agents/devkit/scripts/git/worktree.py remove`; a plain `git worktree remove` refuses the DevKit set-up
   every lane worktree carries — 11 cards Blocked on 20/10 for it; refused with ✖ = it holds work: Block the card naming it), then add
   again. Never a plain `git worktree add` or EnterWorktree (agent-workbench#93). Clean up with `agent-kit worktree remove <path>`.
2. Read issue + PR + Builder's handoff.
3. Build issue-scoped test plan: ONE observable test per AC.
3a. Existing project verifier → follow [project-verifier.md](references/project-verifier.md)
for affected selection, host readiness, real assertions and fresh proof.
3b. Run the **Test-gap check** (above) against the Builder's diff; its High gaps join the plan.
4. Run tests. Capture evidence to `docs/super-board/runs/issue-<N>-qa-v<N>/`. **For any UI-affecting issue, capture at least one screenshot per AC** (Playwright `page.screenshot` or `browse --screenshot`). Save with descriptive names: `ac1-<short-desc>.png`, not `screenshot1.png`.
5. **Commit the evidence directory** to the issue branch alongside test files (`git add docs/super-board/runs/issue-<N>-qa-v<N>/ && git commit && git push`). This is non-optional — without it, the inline image markdown in the issue comment won't render on GitHub. Keep it small: screenshots plus a `summary.md` of at most 40 lines, never raw runner output over 200 lines and never ANSI colour codes (run.md → Tester step 5, "Evidence stays small").
6. **Pass** → tick the PR's `ac` block with proof lines, write `visual` for UI, append a `history` row, rewrite `status` (`super-board-pr-body.sh`) → `[qa] [report] ✅` PR comment with results + evidence path → **issue comment with screenshot evidence** (see "Issue-comment evidence format" below) → move QA → Review. Clean up worktree.
7. **Fail** → leave failing ACs unchecked with the reason, append a `history` row, rewrite `status` → `[qa] [report] ❌` PR comment with per-AC expected/actual + repro file:line + evidence path + "what fixed should look like" → issue comment with the failure screenshots → increment rebuild counter → move QA → Ready (label `loop:rebuild-N`). Clean up worktree.

### Optional verifiers · Handoff comment · Issue-comment evidence format (REQUIRED, pass and fail)

The optional project feature verifier, the runtime performance and memory checks, the test command the pass-handoff PR comment must carry, and the issue-comment evidence format are in [references/tester-verifiers-evidence.md](references/tester-verifiers-evidence.md). The evidence format is required on every pass and every fail.

### Lifecycle (Tester, rebuild — when Reviewer bounced for [qa] thread fixes)
1. Read PR review threads; filter `[qa]` prefix.
2. For each unresolved `[qa]` thread: apply fix to test files → resolve thread via `gh api graphql resolveReviewThread`.
3. Re-run full test suite for the ticket.
4. Save evidence to `runs/issue-<N>-qa-v<N+1>/`.
5. Commit + push. Verify ALL `[qa]` threads resolved.
6. Update the PR's `ac`, `history`, `status` blocks; post `[qa] [report]` PR + issue comments (writing-standard.md § 4). Move QA → Review.

### Failure → `root-cause-hash:` line required
Hash lane = `qa`. Same input definition as super-build.

### Block/Skip exits use the §4 mandatory template
Same rule as super-build, including `super-board-needs-you.py mark` when a person must act
(a real device, a human judgement the AC asks for, a credential).
