# Super QA — Multi-step flows, Test-gap check, Skill dependencies

> Moved out of `SKILL.md` (Claude Code cuts a SKILL.md above 20000 characters, #545). Text is unchanged; `SKILL.md` points here.

## Multi-step user journeys — `docs/super-qa/flows.md`

`critical-paths.md` is the *money-flow guard* (login, checkout, payment) —
small, hand-curated, mandatory human gate if red >2 iters. It is **not** a
coverage layer.

`docs/super-qa/flows.md` is a separate, broader hand-curated list of
*multi-step user journeys* the BFS crawler doesn't reliably exercise on its
own. Examples:

- create user → set role → user logs in → sees their assigned region
- import CSV → review preview → confirm import → verify rows in `/orders`
- create order → assign driver → driver email mock fires → order moves to dispatched

Each entry in `flows.md` is one line per flow with a slug. The worker
generates or updates `e2e/flows/<slug>.spec.ts` for each entry. Specs in
`e2e/flows/` run alongside `e2e/paths/` in Phase 1 regression — same fixture,
same forensics, same `[b]` rules apply. They are **not** pushed via BFS
expansion; they exist as hand-curated chains.

Flows take precedence over individual route specs when both exist for the
same endpoint — a green `e2e/paths/orders.spec.ts` doesn't override a red
`e2e/flows/create-order-end-to-end.spec.ts`.

The user maintains `flows.md`; the skill never auto-edits it. To add a new
flow, the user hand-edits the file; the next iter's Phase 1 picks up the
new slug and generates the spec from a flow recipe.

### `flows.md` template (the worker creates this on first encounter if missing)

```markdown
# super-qa multi-step user journeys

One line per flow. Format: `- slug — short description (route1 → route2 → ...)`

The worker generates / updates `e2e/flows/<slug>.spec.ts` per entry.
These run in Phase 1 regression alongside `e2e/paths/`.

## Flows

- onboard-user — create user, set role, user logs in, sees their region
  (/admin/users/new → /login → /dashboard)
- import-csv-end-to-end — import CSV, review preview, confirm, verify rows
  (/imports → /imports/preview → /orders)
```

## Test-gap check (after build)

Issue-scoped mode only (super-board Tester, or any run handed a finished diff). The
Builder's tests answer "does it do what I built?"; this answers "what breaks silently?".
Scope is the diff: `git diff --name-only $(git merge-base HEAD origin/<base>)...HEAD`.
On auth, money, data-loss or security changes, hand steps 1-3 to a read-only sub-agent
given only the ACs, the range and the changed-file list, so it is not anchored on the
Builder's reasoning.

1. **Ledger.** Every AC → the asserting `file:line` at unit, component and e2e, or `none`,
   or `n/a: <reason>`. Fill the unit column for all ACs first, then component, then e2e.
   A test that runs the code but asserts nothing about the AC is `none`.
2. **Edge cases.** For each changed input or branch, mark each class pinned (`file:line`),
   gap (exact witness value, never "consider edge cases") or n/a: boundaries (limit−1 /
   limit / limit+1; 0 vs null vs empty), money and dates (rounding, timezone shift, month
   end), input (unicode, very long, CSV injection), volume (0 / 1 / many, paging), auth
   (logged out, another user's id, wrong tier), error paths (every catch and rejected
   promise), idempotency and races (double-submit, replay), UI states (loading, empty,
   error, disabled), accessibility (role + accessible name, focus).
3. **Test the tests.** Flag a test that asserts on its own mock, recomputes the expected
   value with the code under test, or cannot fail. For high-risk logic, name the surviving
   mutant (`>` → `>=`, a dropped branch) no test would catch.
4. **Rank.** High: an AC with no test at any rung; any gap in auth/ownership, money,
   security or data loss. Medium: a partly covered branch, a surviving mutant, a missing
   loading/empty/error state. Low: cosmetic, copy, logging.
5. **Act.** Write every High gap now, red first, through `mattpocock-skills:tdd` (or
   `tdd-v2` where the repo has it), at the rung the localisation ladder picks. A new test
   that passes on its first run has not been seen to fail: break the guarded line, see
   red, restore it, see green; the mutation never reaches a commit. A High gap that needs
   app code changed to pass or to become testable is a **Fail**: bounce to Builder
   (QA → Ready) with the list (witness, expected, rung, target file). Medium and Low go
   in the handoff under `Test gaps (not written)` and never block.


## Skill dependencies

The worker (per `references/iteration-preamble.md`) must load and follow:

- `mattpocock-skills:ask-matt` (router — when the right flow is unclear)
- `mattpocock-skills:tdd` (the discipline layer — seams, red-green, assertion
  anti-patterns; does not change with the kind of test)
- `mattpocock-skills:diagnosing-bugs`
- `verification-before-completion` (no Matt Pocock equivalent — kept as-is)
- `testing-strategy` — coverage judgment per component type, and what to skip.
  Consult it for *what is worth testing*; it does not pick the layer. The
  localisation ladder in `references/iteration-preamble.md` picks the layer.
- `vitest` — mechanics for unit and integration tests in a TS/JS repo. 19
  references (`core-expect`, `features-mocking`, `features-coverage`,
  `core-hooks`, `advanced-vi`).
- `playwright-best-practices` — when writing or refactoring a spec. Reference
  its `core/locators.md` (data-testid first, `getByRole` fallback),
  `core/fixtures-hooks.md` (custom fixtures for auth, pre-test seeding, teardown),
  `core/test-data.md` (test data factories), and `core/page-object-model.md` (POM for
  reusable interactions). Keep specs reusable as the suite grows.
