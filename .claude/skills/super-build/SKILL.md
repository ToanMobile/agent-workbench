---
name: super-build
description: Builder lane of the super-board pipeline — takes a `Ready` GitHub Project card into its own per-issue git worktree, makes the smallest safe change test-first (TDD, `ponytail` simplest-first, official docs first for third-party APIs, upgrades and auth/billing), opens a draft PR and hands it to QA and Review through the board; it never merges — merges go through the Reviewer's merge gate. Inside `super-board run` it runs as a lane agent in the in-session wave workflow (`workflows/super-board-wave.js`, no worker cap unless `max_workers` is set); standalone headless `claude -p` dispatch is legacy opt-in. Use when the user says "Super Build", "run the build loop", "/super-build", or invokes the skill.
---

# Super Build — Builder lane and legacy headless GitHub-Project executor

Inside `super-board run`, Super Build is the Builder lane: a lane agent in the in-session wave workflow (`workflows/super-board-wave.js`) that follows "super-board integration" below. Run on its own, `/super-build` is the **legacy headless path (opt-in)**: you are the orchestrator, the source of truth is the **`Ready` column of the configured GitHub Project board**, and your job is to dispatch every issue in `Ready` (in board order) as a headless `claude -p` worker in its own git worktree, open a PR for each finished branch, and move its card to `QA` so the Tester and Reviewer take it from there. Super Build never merges — merging happens only through the Reviewer's merge gate (`.claude/bin/super-board-merge-gate.sh`).

**Curation contract:** the human moves cards into `Ready` when they should be worked. The loop never reads `Backlog`, `In Progress`, or `Done` cards. If `Ready` is empty, the loop reports "queue empty" and exits cleanly — no error.

**This skill is single-purpose: EXECUTE curated GitHub Project `Ready` issues.** It is INDEPENDENT of `/super-qa` / **Super QA** (the autonomous bug-bash loop that hardens shipped code). They share no state unless a `super-board run` sequences them through the board. Run **Super Build** to make forward progress on the issue queue; run **Super QA** to bug-bash the existing codebase. They CAN run concurrently in different orchestrator sessions, but expect merge conflicts if both touch the same files.

## Role boundary

Super Build is the canonical builder. Do not use a separate `build-feature` workflow. If the user wants a one-off feature, first create or curate a GitHub issue/card with clear acceptance criteria, move it to `Ready`, then let Super Build execute it.

Super Build may implement, test, commit, push, open PRs, and move project cards to `QA`. It never merges or moves cards to `Done` — the Reviewer does that through the merge gate. One exception to closing: when every AC is already met on the base branch (checked with a command, output pasted in an issue comment), it closes the issue with no PR (`run.md` → Builder step 3c, "already met") and the runner's reconcile moves the card to Done. Never on a card labelled `ac-open` (T0054: a PR of it merged with AC still unproven): the runner reopens a closed `ac-open` issue, so closing it loops — open a proof PR instead whose `sb:ac` block lists EVERY AC line (earlier proven ones kept `[x]` citing their PR, the rest proven now, e.g. a measurement taken on main); its merge gate removes the label. It should not invent new product scope beyond the issue body. If the issue needs product/design/security judgment, apply the human-gate or WIP-partial path instead of guessing.

**GitHub budget** — every "move card" is `.claude/bin/super-board-card.sh --config <cfg> move <N> <Status>` (1 GraphQL point; `gh project item-list` / `field-list` cost ~100–200). Comments, labels and PR reads go over REST; [rate-limit-etiquette.md](../super-board/references/rate-limit-etiquette.md) → "Price list" has the calls.

## Configuration and Algorithm (legacy standalone mode)

The opt-in headless `claude -p` path: Configuration, Algorithm steps 0–5 (pre-flight, read the Ready column, skill resolution before locks, labels, dispatch wave, wait and reconcile, final report) are in [references/legacy-standalone.md](references/legacy-standalone.md). Inside `super-board run` skip it and follow "super-board integration" below.

## Issue contract

Every Ready issue should be executable without live clarification. Preferred issue body shape:

```markdown
## Goal
<one-sentence outcome>

## Acceptance Criteria
- [ ] <observable behavior or artifact>
- [ ] <test/verification expectation>

## Notes / Constraints
- Depends on: #123, #456
- Skills: mattpocock-skills:tdd, verification-before-completion
- Human gates: <deploy, destructive DB action, product decision, etc.>
```

Super Build treats acceptance criteria as the completion contract. Workers must not edit checkboxes to make the issue look complete. If the issue is too vague to execute, mark it with `super-board-needs-you.py mark` (the question as the action) instead of guessing.

## Constraints

- **Worker cap:** `max_workers` from the config when set, otherwise 3 on this legacy path (resource throttle). The workflow backend has no cap unless `max_workers` is set.
- **Never auto-touch issues with the `needs-you` (or legacy `human-gated`) label** (production cutover, secrets, irreversible ops, real devices, store accounts, decisions).
- **Never modify code in the main worktree** while workers are running. Only run `gh` commands and push/PR operations.
- **Conflicts** between concurrent workers' branches are not resolved here — they surface at the merge gate, and the card comes back to the Builder for a rebuild. Don't auto-resolve.
- **Report cadence** (to the user, in the session): 1 message at start, 1 per dispatch wave, 1 per completion (success/fail), 1 final summary. Don't spam.
- **Workers MUST use the right skills.** The worker preamble enforces: workers parse the `Skills:` line from the issue body if present; otherwise they route on the issue's **type label** (`bug` → `diagnosing-bugs`+`tdd`, `feature` → `implement`+`tdd`+`codebase-design`, `refactor`/`tech-debt` → `codebase-design`+`tdd`, `docs` → skip `tdd`), always adding `ponytail:ponytail` (simplest solution first, before any code; inline fallback when the plugin is absent), `verification-before-completion` and a `code-review` pass on their own diff. Test mechanics are picked by the localisation ladder, never by label. Decision points walk the decision ladder — acceptance criteria → repo precedent → smallest blast radius → human gate — and stop at the first rung that answers the question. No panel, no vote; `mattpocock-skills:grilling` is forbidden inside a worker (it waits on a user who is not there) and lives in `super-board lint` instead. `mattpocock-skills:code-review` runs once against the worker's own diff before the final commit. See `references/decision-policy.md` for the skill map, the ladder, the human gates, and the `--- decision ---` commit trailer.

## Worker preamble

The preamble at `references/worker-preamble.md` is the worker contract: decision policy, HUMAN GATE handling, the per-issue 14-gate contract, and final-commit format. The dispatcher prepends it to every worker prompt. See that file for the verbatim text.

## Recovery / re-entry

If the user invokes `/super-build` after a partial run:
- Re-read `gh issue list`. Issues already closed are skipped automatically.
- If legacy `.worktrees/issue-N` exists, stop and inspect it before dispatch. Preserve edits and use `git worktree move` to the matching `.claude/worktrees/issue-N` path; never delete the old folder to make a fresh dispatch fit.
- If `.claude/worktrees/issue-N` exists for an N that's still open: a previous worker was interrupted. Default: notify the user and ask before auto-resuming (a re-dispatch overwrites the previous attempt's branch).
- If the `loop:in-progress` label is set on issue N but no worktree exists: stale lock from a crashed orchestrator. Remove the label and treat as ready.

## Stop conditions

- Selected GitHub Project `Ready` queue is empty, or all remaining Ready cards are blocked / `needs-you` / `loop:halted`.
- Any worker fails (dispatcher exit 2 or 3).
- HUMAN GATE TRIPPED (dispatcher exit 4).
- Push or PR creation fails.
- User interrupts.

**Not a stop condition:** WIP-PARTIAL (dispatcher exit 5). The orchestrator opens a partial PR, leaves the issue open with `needs-you`, and continues dispatching the next issue in the wave. WIP-PARTIAL is intentional, bounded work.

## Invocation patterns

- `Super Build` / `/super-build` → process all GitHub Project `Ready` issues in board order
- `/super-build --only N` → execute only issue #N (smoke-test mode, ignores `loop:in-progress` label on that issue if you set `FORCE=1`)
- `/super-build --dry-run` → print the dispatch plan (issues, order, parallelism waves) without invoking workers, without setting labels, without commenting

## Companion skill

`/super-qa` / **Super QA** is the autonomous bug-bash iteration loop. It is **independent of this skill** unless a `super-board run` sequences them through the board. Run **Super Build** for forward progress on Ready issues; run **Super QA** to harden the existing codebase by hunting bugs.

## super-board integration

When invoked by super-board (env `SUPER_BOARD_RUN=1` set by the runner, or invocation contains "super-board run"), follow these rules instead of the standalone defaults:

### State protocol
- Read context from: issue body + ALL issue comments + linked PR description + PR comments + PR review threads. NEVER from local state files for inter-lane coordination.
- Work only in the worktree path super-board names (`.claude/worktrees/issue-<N>-build/`), created with the DevKit (Lifecycle step 1). Never a plain `git worktree add` or EnterWorktree.
- Respect the single branch super-board hands you (`issue-<N>-<slug>`). Don't create alternate branches.

### Lifecycle (Builder, first pass)
Follow spec `.claude/skills/super-board/references/run.md` → Builder (first pass). Summary:
1. Worktree with the DevKit, after `git fetch origin`: `agent-kit worktree add .claude/worktrees/issue-<N>-build issue-<N>-<slug> --lane=build --base=origin/<config.base_branch>`
   (no `agent-kit` on PATH: `python3 .agents/devkit/scripts/git/worktree.py add` with the same arguments). It links the DevKit, copies the
   git-ignored config and hooks, clones a Unity Library copy-on-write and reuses the build worktree a stopped
   run left at that path. Exit 4 = under the disk floor: stop with its message, card and claims unchanged. Never a plain `git worktree add`.
2. Branch `issue-<N>-<slug>` from `config.base_branch` (step 1 makes it; an existing one, local or only on origin, is checked out as it is).
3. Docs check (section below) — if the ticket touches a third-party surface, an upgrade, or auth/billing, read the current official docs first.
4. Implement the smallest safe change that covers the ACs. Unset `auto_max_lines` is 0 (section below).
5. Commit + push (always).
6. Open **draft PR** with the PR description template from `run.md` — title in commit-subject format, every marker block filled, `Docs:` bullets in Solution, Risk with `Door:` (one-way/two-way) and `Blast radius:` lines (writing-standard.md § 2).
7. Follow [PR author notes](../super-board/references/pr-author-notes.md), then post the `[builder] [report]` PR comment + the short issue comment with the PR URL (writing-standard.md § 4).
8. Move card Ready/Building → QA.

### Keep each PR small (only when the board set a positive cap)
Unset `merge_policy.auto_max_lines` is 0: there is no line-count cap. Build the card's ACs as one
PR. A positive `auto_max_lines` is opt-in (additions + deletions; lockfiles, generated files,
snapshots and migration SQL do not count — see `merge_policy.size_exclude`). A PR over that positive
cap is never auto-merged: the merge gate parks it in Blocked 🙋 "big PR — please review".

When the cap is a positive number, check `git diff --shortstat origin/<base>...HEAD` (minus excluded
files) before each push. If the change grows past that cap mid-build, **stop — do not push on**.
Commit and push what you have on the branch, leave the PR as a draft, and post a PR comment
proposing the split: the vertical slices (each thin end to end, under the cap, with its own ACs),
which slice this PR keeps, and `/to-tickets` as the way to file the rest. Then move the card to
Blocked with `❓` ("too big — split proposed in PR #<P>", `block-template.md`). Never pad past the
cap to "finish" the ticket. When the cap is 0, do not stop or split for line count.

### Lifecycle (Builder, rebuild)
Triggered when card returns to Ready/Building with `loop:rebuild-N` label.
1. Read PR review threads on this branch's PR; filter `[builder]` prefix.
2. For each unresolved `[builder]` thread: read file:line + suggested fix → apply → resolve thread via:
   ```bash
   gh api graphql -f query='mutation($threadId:ID!){resolveReviewThread(input:{threadId:$threadId}){thread{isResolved}}}' -f threadId="<thread-id>"
   ```
3. Address any new failure feedback from Tester's latest ❌ comment.
4. Commit + push to same branch. Verify ALL `[builder]` threads are resolved before exit.
5. Refresh [PR author notes](../super-board/references/pr-author-notes.md), rewrite your PR body blocks (`super-board-pr-body.sh`), post `[builder] [report]` PR + issue comments. Move card Ready/Building → QA.

### Docs before outside-tool code (every ticket)
Before writing code, decide whether the ticket touches any of:
- a third-party API, SDK, library, CLI or cloud service (calling it, configuring it, adding it);
- a dependency or framework **upgrade**;
- **auth or billing** (OAuth/scopes, sessions, tokens, webhooks, payments, plans).

If yes, read the **current official docs** for the exact surface and version first — context7
when available, otherwise web search to the vendor's own docs, migration guide or changelog.
Check the installed version (`package.json` / lockfile, `npm view <pkg> version` for a new dep)
and read the docs for that major. Repo docs and existing call sites come first for how *this*
repo uses it; vendor docs settle what the tool does. Not Stack Overflow, not old blog posts,
not memory.

Cite what you read as `Docs:` bullets at the end of the PR body's Solution block (URL + the one
fact it settled). Docs unreachable → say so there and in the `[builder] [report]` comment, mark the
affected code `unverified against current docs`, and keep the change minimal. No outside tool
touched → `Docs: none needed — no third-party surface`.

### Failure → handoff comment must include `root-cause-hash:` line
On any failure-handoff comment, include:
```
root-cause-hash: <sha256 first 12 hex chars>
```
Hash inputs (joined with `|`): lane (`build`) | error class | first 3 unique normalized file:line frames. See `.claude/skills/super-board/references/run.md` → Root-cause hash.

### Never merge
Builder NEVER squash-merges. Reviewer owns merge.

### Too big → split, don't park (#253)
A card over the size cap that is agent-doable is split by the Builder, not blocked for a person: file each vertical slice with
`/createTask` (under the cap, own ACs, `Blocked by` the earlier slice), keep the first slice on this card, and say so in the
`[builder] [report]`. `super-board-needs-you.py mark` refuses "split the card" as a person's step, so a Block ❓ that only says
"too big" has no way out (#181 sat Blocked two ways on 22/10).

**No line cap → never split for size (24/10, user: "gom lại nhiều nhất có thể, đỡ chạy gate nhiều lần").** When the board's
`merge_policy.auto_max_lines` is `0`, a card with many deliverables or many AC items is built as ONE PR (its target tests +
one `post-fix-gate.py --run-tests --scoped`, never `--full` by hand: scoped never escalates (#741) and the nightly `gate-full` runs `--full`); never propose child cards, batches "≤ N items per PR" or a split to keep a diff small. Commit per deliverable inside the
one branch instead. Only a step no agent can do (a real device, real people, a credential) leaves the card, as a `qa` card.

**Batch (đợt, #724): other cards ride on this branch.** Before building, run
`python3 .agents/devkit/scripts/governance/card_batch.py plan --lead <N>`: open cards marked `<!-- sb:batch-of #N -->` are built here
too (they carry `waiting-on:#N` and Blocked by #N, so nobody builds them alone). One commit (or a few) per card, subject ending
`(#m)`; the PR body carries one `Closes #x` line per card, outside the `sb:status` block (QA and Review rewrite that block), and one sb:ac block listing every card's AC, member lines shaped
`- [x] [#m] <AC>`. One gate, one
merge gate. A member that blocks the rest (review, conflict, unmet AC): `card_batch.py split --lead <N> --card <M> --reason "…" --pr <P>`
reverts its commits and frees the card, then re-run the gate once and push.

### Block exits use the §4 mandatory template
When moving a card to Blocked (or dropping it: closed as not planned, Done, 🤷), populate the full template (its `blocked-by:` line from `super-board-blocked-by.py`, open issues only) from `.claude/skills/super-board/references/block-template.md`. A 1-line "needs creds" comment is a contract violation. When a person must act (🙋 🧑 🔐 🔑 💳 🎨 🛡, or ❓ waiting on a person's decision), also run `super-board-needs-you.py mark` in the same step (block-template.md → "A person must act").
