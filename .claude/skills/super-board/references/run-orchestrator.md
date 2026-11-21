# super-board run — orchestrator-only sections

Moved verbatim from [run.md](run.md) (#1420). The orchestrator and the legacy `claude-p` runner read this file;
a lane worker follows run.md → its lane lifecycle (run.md → "Lane read map").

## Preconditions (verified before any worker dispatches)

| Check | Action on fail |
|---|---|
| Usable verification commands | Run `python3 .claude/bin/super-board-verification-ready.py --config <config>`. Exit 9 halts setup before dispatch: configure the owning project's checks, then restart explicitly. |
| Active config exists | Halt: "Run `super-board onboard` first." |
| Project + required columns exist | Halt: "Project / columns missing. Run `super-board onboard` to repair." |
| `gh auth` valid with required scopes | Halt: "Re-auth: `gh auth refresh -s project,read:project,repo`." |
| `pre-flight.md` all items `[✓]` | Halt: "Pre-flight incomplete — fix these: [list]." |
| No issues missing ACs in active columns | Halt: "N issues need clarification. Run `super-board lint`." |
| Clean git working tree on base branch | Halt: "Working tree dirty. Stash or commit before running." |
| Legacy worktrees | If `.worktrees/issue-*` exists, halt before dispatch. Stop its worker, inspect/preserve edits, then `git worktree move` it to the matching `.claude/worktrees/` path. Never delete it as part of an upgrade. |
| Stale worktree scan | Scan only `.claude/worktrees/issue-<N>` and `issue-<N>-build/qa/review`. If its named branch is gone, use `agent-kit worktree remove` (never `--force`; a plain `git worktree remove` refuses the DevKit set-up every lane worktree carries). Keep detached, dirty, locked, unregistered, or unrelated folders; log failures for inspection. A missing board label alone is not permission to delete work. |
| Production-merge guard | If `base_branch == "main"` AND `human_approves_merge == false` AND `merge_policy.default != "human"` AND `merge_policy.allow_auto_on_production != true` AND production-detection signals fire (see onboard → base branch), halt with: `🛡 Refusing to start: would auto-merge to production main. Set merge_policy.default: "human", switch base_branch to staging, or re-run super-board onboard to opt in explicitly.` |
| Orphan-worker scan (added 2026-05-22 after #381 worker storm) | `pgrep -f 'claude -p .*super-board run'` must return zero. If any super-board worker is already alive from a prior crashed run, halt with: `🛑 ${N} super-board workers already running. Stop them first: pkill -f 'claude -p .*super-board run'`. The dispatcher must never run while orphan workers exist — they will collide on assignee claims and produce duplicate PRs. |
| Database reach | Run every `migrations.checks[env]` for an env in `allowed_envs` (read-only, e.g. `supabase migration list --db-url …`). On failure halt with its error: "Migrate URL for <env> does not connect — fix it before a wave builds work the gate cannot land." |
| GraphQL rate-limit guard | Before each tick, `sb_gh_guard_check` (super-board-gh-guard.sh — it reads GraphQL's own `rateLimit`, because `gh api rate_limit` misreports the GraphQL bucket). If GraphQL remaining < 200, sleep until reset. Prevents the runner from dying mid-loop when the user has burned quota in another tool. |

## Dispatch allocation model — one worker per lane, not per backlog

`super-board run` allocates headless Claude capacity by **lane**, not by how many cards are stacked in one column.

- **Max concurrency:** 3 workers total — at most one Builder, one Tester, and one Reviewer at the same time.
- **Never dispatch multiple workers from the same column just because that column has a backlog.** If all cards are in `Ready`, the runner dispatches exactly one worker for the top card — a Builder, or a Tester when the card is labelled `qa` — until it exits.
- **Mixed-column example:** if `Ready`, `QA`, and `Review` each contain cards and all lanes are idle, the runner dispatches three workers: one Builder from `Ready`, one Tester from `QA`, and one Reviewer from `Review`.
- **Downstream-first priority:** when multiple lanes are available, dispatch Review before QA before Ready/Build, so finished work gets closed before new build work starts.
- **Lane idle gate:** a lane is eligible only when its prior worker process has exited. The runner must track lane PIDs or an equivalent lane lease; GitHub issue assignees are per-card mutexes, not lane-capacity controls.

This means a board with 30 cards in `Ready` and zero elsewhere does **not** start 3 Builder sessions. It starts one Builder. As that Builder moves its card to `QA` and exits, the next tick can start one new Builder for the next `Ready` card and one Tester for the first `QA` card, because those are different lanes.

## Per-tick logic (~30s cadence)

```
1. Refresh project items + column counts via gh api
2. Re-validate preconditions (auth, pre-flight, columns)
3. Downstream-first dispatch by lane capacity:
   ├─ Review has cards + Reviewer idle → dispatch top of Review
   ├─ QA has cards + Tester idle       → dispatch top of QA
   └─ Ready has cards → top card labelled `qa` + Tester idle → Tester;
                         otherwise Builder idle → Builder

   Allocation rule: at most ONE worker per lane at a time.
   Max concurrency = 3 total workers (Builder + Tester + Reviewer),
   but never 3 Builders from a Ready backlog. GitHub issue assignees prevent two workers claiming the same card;
   the runner still must track lane idleness separately to prevent multiple
   same-lane workers.
4. Wait for any lane to finish OR 30s timeout
5. Re-read project state (lane may have moved a card)
6. Loop until done conditions met
```

## Done conditions

The loop exits cleanly when:
- All active-pipeline columns are empty; OR
- Only Blocked/Done cards remain, or cards waiting for a person or a real device (Backlog is not part of a run); OR
- A halt gate fires.

## Run manifest

```
docs/super-board/runs/<YYYY-MM-DD>-<slug>.md
```

Records: config used, columns, target, per-card history (claim → completion → next column with evidence links), halt gates, final counts, per-lane wall-clock, resume command.

## Notification cadence

- **Start** — project, initial column counts, link to live status: `super-board status`.
- **Per card completion** — `✅ Tester → #41 passed all checks → Review`.
- **Per Block** — short headline + reason tag (`⛔ #19 blocked → 🔐 missing OPENAI_API_KEY`) + link to the full §4 template comment on the issue.
- **Every 10 dispatches** — brief column-count snapshot.
- **Block-rate alert** — when Blocked count exceeds `config.block_rate_alert_pct` of initial Ready: ping with breakdown ("11/30 Ready cards blocked: 🔐×6, 💳×3, ❓×2 — see project board"). One-shot per run (does not re-fire).
- **Final** — end column counts, total moved to Done, blockers (with reason-tag breakdown), total wall-clock.

