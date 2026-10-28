# Super Build — Legacy standalone mode (Configuration and Algorithm)

> Moved out of `SKILL.md` (Claude Code cuts a SKILL.md above 20000 characters, #545). Text is unchanged; `SKILL.md` points here.

## Configuration

The orchestrator needs to know which project board to read.

### Standalone mode (legacy)

Reads `Ready` from the repo's feature project. Resolution order:

1. **`BUILD_LOOP_PROJECT`** env var — project number (e.g. `2`)
2. **`BUILD_LOOP_OWNER`** env var — project owner (e.g. `EricTechPro`)
3. **Auto-discovery fallback:** if env vars unset, run `gh project list --owner $(gh repo view --json owner -q .owner.login) --format json` and pick the project whose `title` matches the repo name, or the only open project if there's exactly one.

Surface: `🎯 Reading project: <owner>/<title> (#<n>), column "Ready"`.

## Algorithm

### 0. Pre-flight

Before reading the board:

- Confirm the main worktree is clean: `git status --porcelain` must be empty.
- Confirm `gh auth status` works and the repo remote points at the expected GitHub repo.
- Confirm `jq`, `git`, and `claude` are available.
- Resolve and print `BUILD_LOOP_OWNER` and `BUILD_LOOP_PROJECT`.
- Run `git fetch origin` and identify the base branch from the current checkout; do **not** assume `main`.

### 1. Read the source column

Source column is `Ready` (override with `BUILD_LOOP_SOURCE_COLUMN`):

```bash
SOURCE_COLUMN="${BUILD_LOOP_SOURCE_COLUMN:-Ready}"

.claude/bin/super-board-card.sh --owner "$BUILD_LOOP_OWNER" --number "$BUILD_LOOP_PROJECT" items \
  | jq --arg col "$SOURCE_COLUMN" '.items[] | select(.status == $col and .content.type == "Issue")'
```

`super-board-card.sh items` is the `gh project item-list` shape for ~1 GraphQL point per 100 cards (item-list spends 101) — without bodies.

For each Ready item:
- Capture `content.number` (issue #), `content.title` and `labels`; read the body over REST: `gh api repos/{owner}/{repo}/issues/<N> --jq .body`.
- **Skip** issues with the `loop:in-progress` label (in flight in another orchestrator) or `loop:halted` label (manually paused) or `needs-you` label (a step only a person can do), or the legacy `human-gated` label (merged into `needs-you` on 2026-10-19; `mark` migrates it, until then skip it too).
- Parse `body` for `Depends on: #N1, #N2` lines (case-insensitive). If any dep is still open AND not in the current Ready set, the issue is blocked — leave it for a future run.
- Parse `body` for an optional `Skills:` line (e.g. `Skills: mattpocock-skills:tdd, verification-before-completion`). If absent, the worker uses defaults from the preamble.

**Ordering:**
1. **Board order first** — `items` returns cards in the human's manual board order. Respect that. If the user wants Issue X before Issue Y, they drag X above Y on the board.
2. **Tiebreaker (rare):** within the same drag-position, sort by priority extracted from title regex `^\[?(P[1-4])\]?`: `P1` < `P2` < `P4` < `P3` < no priority. Then issue number ascending.

If `Ready` is empty: print `📭 Project board "Ready" column is empty — nothing to dispatch.` and exit 0. This is not an error; it means the human hasn't curated work yet.

### 1b. Resolve the selected worker skills before locks

Hydrate each selected issue through `super-board-github-read.py --kind issue --
issue view <N> --json number,title,body`. Save a JSON array with number, Ready
status, labels and literal body. Run `.claude/bin/super-board-skills-ready.py
--root <repo> --host claude --cards <cards.json> --lane build` before label
creation, stale-lock recovery, comments or dispatch. Exit 10 halts and names the
missing helpers. Preserve existing claims and worktrees. No automatic helper
installation during dispatch. The dispatcher and worker repeat this check.

### 2. Ensure required labels exist (idempotent)

Once per run, before first dispatch:
```bash
gh label create loop:in-progress --color FFA500 --description "Currently being worked on by /super-build" 2>/dev/null || true
gh label create loop:halted --color B60205 --description "Manually paused — /super-build will skip" 2>/dev/null || true
python3 .claude/bin/super-board-needs-you.py label --repo <owner/name>   # needs-you, one colour on every repo
```

### 3. Dispatch wave (worker cap)

Worker cap on this legacy path: `max_workers` from the super-board config when set, otherwise 3.

Report once per wave: `▶️ Super Build dispatching: Issues [#N1, #N2, #N3] (parallel)`

For each issue N in the ready set (up to the cap at a time):

a. **Lock the issue:**
```bash
gh issue edit N --add-label loop:in-progress
```

b. **Announce on the issue** (so a human reading the issue page knows it's being worked):
```bash
gh issue comment N --body "🤖 Dispatched by /super-build — worker spinning up in worktree \`.claude/worktrees/issue-N\` on branch \`loop/issue-N\`. Skills: <skills-line-from-body-or-defaults>."
```

c. **Dispatch:**
```bash
bash .claude/skills/super-build/scripts/super-build-dispatch.sh N
```
…via Bash with `run_in_background: true`. Capture each shell ID.

The dispatcher (this skill's `scripts/super-build-dispatch.sh`) handles:
- `agent-kit worktree add .claude/worktrees/issue-N loop/issue-N --lane=build --base=<base-branch>` — the DevKit's worktree (DevKit links, git-ignored config and hooks, a Unity Library cloned copy-on-write), never a plain `git worktree add` (agent-workbench#93); exit 4 = under the disk floor, nothing made
- `gh issue view N --json title,body,labels` to compose the worker prompt
- prepend `references/worker-preamble.md` + append working-directory footer
- `cd` into worktree and exec `claude -p --dangerously-skip-permissions --output-format stream-json --verbose --max-turns 250`
- verify the worker produced a `🔧 [chore] loop: close #N` commit on its branch
- exit 0 (success) / 2 (worker non-zero) / 3 (no done-commit) / 4 (HUMAN GATE TRIPPED)

**Base branch:** the orchestrator's currently-checked-out branch (e.g. `frontend-rebuild`). Pass via `BASE_BRANCH` env var to the dispatcher. Don't assume `main`.

### 4. Wait + reconcile

Poll BashOutput on each in-flight shell. As each finishes:

After creating either a complete or partial PR below, follow
[PR author notes](../../super-board/references/pr-author-notes.md) before reporting the
handoff complete. Add file summaries and critical inline notes on the PR, not in source.

**On dispatcher exit 0 (success):**
- `git -C .claude/worktrees/issue-N push -u origin loop/issue-N`
- `gh pr create --draft --base <base-branch> --head loop/issue-N --title "<emoji> [<type>] <scope>: <subject>" --body-file <body.md>` — title in commit-subject format, body = the marker-block template from `skills/super-board/references/run.md` (writing-standard.md § 2), `Closes #N` in the status card (plain text, never in backticks: GitHub does not link a code span), `Docs:` bullets in Solution
- `gh issue edit N --remove-label loop:in-progress`
- `gh issue comment N --body "[builder] [report] ✅ built · PR <URL>"` (Next line: `qa`)
- Move the project card to `QA`. The Tester and Reviewer take it from there; the issue closes when the Reviewer merges through the merge gate.
- Leave the worktree in place — the merge gate's clean-up (after the merge) or the board's sweep removes it once the work is on the base branch; the DevKit (`agent-kit worktree held` / `remove --merged` / `prune-branch`) decides what is safe to remove.
- Report: `✅ Super Build issue #N → PR <URL>, card in QA`
- Recompute ready set; if new issues are now unblocked, dispatch in the next wave (respecting the worker cap)

**On dispatcher exit 5 (intentional WIP-PARTIAL — open a partial PR, do NOT close):**
- `git -C .claude/worktrees/issue-N push -u origin loop/issue-N`
- `gh pr create --draft --base <base-branch> --head loop/issue-N --title "🚧 [wip] <scope>: <slice from worker's final message>"` — the status card says `Refs #N`, never `Closes`, so the merge does not close the issue.
- `gh issue edit N --remove-label loop:in-progress`, then `python3 .claude/bin/super-board-needs-you.py mark --repo <owner/name> --issue N --action "<what is left that only a person can decide or do>"`
- `gh issue comment N --body "[builder] [report] ⚠️ partial · PR <URL>\nDid: <slice>\n❌ Not done: <worker's reason for stopping>\nNext: Eric"` — the issue stays open with `needs-you` until the rest lands.
- Report: `🟡 Issue #N partial PR opened — issue stays open (needs-you)`
- **Continue dispatching the next issue in the wave.** A WIP-PARTIAL is NOT a halt. The worker did intentional, scoped work and the orchestrator advances.

**On dispatcher exit 2 or 3 (worker failed or no done-commit):**
- `gh issue edit N --remove-label loop:in-progress`
- `gh issue comment N --body "[builder] [report] ❌ failed · exit <X>\nDid: worker ran; worktree \`.claude/worktrees/issue-N\` kept\n❌ Not done: <one line from the log>\nNext: Eric\n\n<details><summary>log tail</summary>\n\n\`\`\`\n$(tail -50 .planning/super-build-logs/issue-N.log)\n\`\`\`\n</details>"`
- Report to the user with `tail -50` of `.planning/super-build-logs/issue-N.log`
- Do NOT open a PR; leave the worktree intact for human inspection
- Halt the loop

**On dispatcher exit 4 (HUMAN GATE TRIPPED):**
- `gh issue edit N --remove-label loop:in-progress`, then `python3 .claude/bin/super-board-needs-you.py mark --repo <owner/name> --issue N --action "<the human gate from the log, as a step>"`
- `gh issue comment N --body "🔴 HUMAN GATE TRIPPED — needs manual handling. See worktree \`.claude/worktrees/issue-N\`."`
- Report: `🔴 Issue #N tripped HUMAN GATE — needs manual handling`
- Halt the loop

### 5. Final report

When the selected GitHub Project `Ready` queue is empty, or only blocked cards remain: report a summary listing PRs opened this run (cards in `QA`), issues not built (`needs-you` / `loop:halted` / blocked dependencies), and any halts. Suggest: "Run `super-board run` to test, review and merge them."
