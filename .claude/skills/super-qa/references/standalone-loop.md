# super-qa — standalone loop reference

Moved verbatim from SKILL.md (#1420). Read it before a standalone `/super-qa` run; a board Tester needs only
"Auth bootstrap", when an AC test needs a logged-in user.

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
It triggers a "diminishing returns" report and keeps exploring the queue.

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

