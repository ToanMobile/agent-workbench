# Super QA — Coexistence with super-build, Test target and safety rails, Files involved

> Moved out of `SKILL.md` (Claude Code cuts a SKILL.md above 20000 characters, #545). Text is unchanged; `SKILL.md` points here.

## Coexistence with `/super-build`

`super-qa-file-bug.sh` files bugs into the **Super Ultimate QA** project's `Bug` column. This is a separate board from `/super-build`'s standalone feature queue (`BUILD_LOOP_PROJECT`), so the two skills can run concurrently without column races:

- **Standalone `/super-build`** keeps reading `Ready` from its configured feature project. Untouched by `/super-qa`.
- **`Bug` cards reach a builder** when someone moves them to `Ready`, or when `/super-build` runs with `BUILD_LOOP_SOURCE_COLUMN=Bug` against this board. Builds go to `QA` as PRs; nothing moves to `Done` without the Reviewer's merge gate.

If you intentionally want a single board for both lanes, set `BUILD_LOOP_PROJECT=$SUPER_QA_PROJECT_NUMBER` and `BUILD_LOOP_SOURCE_COLUMN=Bug`. Don't do this by accident — the column semantics differ.

## Test target & safety rails

The default target is the app target configured by `BASE_URL`. Treat production URLs as production and prefer preview/staging for mutating flows.

Safety rails (enforced by the iteration preamble):
- Test user: configure via app env, for example `QA_BOT_EMAIL` / `QA_BOT_PASSWORD`.
- All written test data is prefixed `[TEST] ` so it's greppable.
- Sentry tag `source=super-qa` on errors.
- DB resets DISABLED (`RESET_DB=false`) — would wipe prod.
- Email sending mocked via `RESEND_API_KEY=mock_<anything>`. **Required:** run against a staging deploy (`NODE_ENV=staging`, `EMAIL_DRY_RUN=1`) — not prod. If no staging URL is configured, halt with `STATUS: halt (no-staging-env)`.
- Override the target via `BASE_URL=…` in the worker's environment.

## Files involved

```
.claude/skills/super-qa/
├─ SKILL.md                            ← orchestrator instructions (this file)
└─ references/
   └─ iteration-preamble.md            ← worker contract (verbatim prompt)

.claude/bin/super-qa-file-bug.sh       ← files a red spec onto the QA board

docs/super-qa/
├─ README.md                           ← operator's guide
├─ HANDOFF.md                          ← context handoff
├─ queue.md                            ← THE queue (loop reads/writes)
├─ page-types.md                       ← taxonomy + per-page overrides
├─ critical-paths.md                   ← hand-curated money-flow guard
└─ iter/
   ├─ iteration-1.md                   ← per-iter bug log + report
   └─ ...

e2e/paths/                             ← THE deliverable (one spec per place)

docs/super-qa/report/
└─ QA-REPORT.md                        ← regenerated every iter (existing)
```
