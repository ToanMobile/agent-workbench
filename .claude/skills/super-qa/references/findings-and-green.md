# Super QA — Findings as GitHub Issues, and what counts as green

> Moved out of `SKILL.md` (Claude Code cuts a SKILL.md above 20000 characters, #545). Text is unchanged; `SKILL.md` points here.

## Findings land in clear GitHub Issues, NOT in markdown

Every `[b]` cell triggers the worker to call `.claude/bin/super-qa-file-bug.sh`.
The resulting Project card must be readable from the board without opening it.
Do **not** use legacy `[VFL]`, `verify-fix`, or `severity:P*` wording in new issue titles.

**Title format:**

```text
<emoji> <Type> <route?> — <short action/result>
```

Examples:

```text
🐛 Bug /imports — CSV upload fails after submit
🎨 UX /settings/users — Add user button is a no-op
🧪 Tests /orders — missing coverage for failed payment state
📝 Docs /delivery — SPEC section missing for dispatch flow
```

**Priority labels use plain words:**

- `priority:high` — urgent, release-blocking, data-loss, security/auth, money, or critical feature broken.
- `priority:medium` — important feature degraded, important edge case, a11y/i18n issue, or user confusion that should be fixed soon.
- `priority:low` — polish, cosmetic, copy, documentation, testability, or cleanup.

**Required labels:**

- Type: `bug`, `feature`, `ux`, `tests`, `docs`, or `tech-debt`.
- Source: `source:qa`.
- Priority: `priority:high`, `priority:medium`, or `priority:low`.
- Area: `area:<product-area>` when known (`area:settings`, `area:imports`, `area:admin-shell`, etc.).
- QA category when relevant: `qa:functional`, `qa:visual`, `qa:network`, `qa:console`, `qa:i18n`, `qa:a11y`, `qa:data`, `qa:testability`.
- Suggested skill owner when helpful: `skill:super-build`, `skill:super-qa`, `skill:ui-refine-loop`, or `skill:super-review`. `skill:ui-refine-loop` marks a UI ticket for a human to run `/ui-refine-loop` on; the board never triggers it.

The script adds the issue to the resolved `Super Ultimate QA` project and moves it into the `Bug` column (override with `SUPER_QA_TARGET_OPTION_NAME`) so a human (or `/super-build` with `BUILD_LOOP_SOURCE_COLUMN=Bug`) can pick it up immediately. The repo's standalone feature project is not touched by this flow.

The `iteration-N.md` Section 3 is the per-iter audit (with `gh_issue: <N>` back-references); the GH issue is the durable tracker. The fix-commit message includes `(closes #<N>)` so the issue auto-closes on merge.

**Triage all loop-filed findings:**
```bash
gh issue list -l source:qa --state open
```

This is a carved exception to the project rule "ask before `gh issue create`": the loop is autonomous and unattended, so it is authorized to auto-file — but ONLY with the clear `source:qa` label and the evidence template below.

### Required issue body template

Every auto-filed finding must give a future headless Claude/Super Build session enough context to fix it without re-discovering the bug from scratch:

```markdown
## Summary
<one sentence: what is wrong and where>

## Repro steps
1. <exact login/route/action>
2. <next action>
3. <observed failure>

## Expected behavior
<what should happen, citing SPEC.md, DESIGN.md, or product intent when possible>

## Actual behavior
<what happened instead>

## Evidence
- Screenshot: <embedded image or repo/raw path>
- Console: <0 errors or paste relevant lines / path to console.log>
- Network: <failed requests or path to network.json/HAR>
- Page errors: <0 errors or path to pageerrors.log>
- Spec: `<e2e/paths/...spec.ts>`

## Suggested fix path
- Suggested owner: `super-build` | `super-qa` | `super-review` | `ui-refine-loop` (UI ticket — a human can run `/ui-refine-loop`; the board never triggers it)
- Suggested skills: `mattpocock-skills:diagnosing-bugs`, `mattpocock-skills:tdd`, `verification-before-completion`
- Notes for implementer: <first suspected file/function, if known>

## Acceptance criteria
- [ ] <user-visible behavior fixed>
- [ ] <Playwright/regression coverage added or updated>
- [ ] <Super QA rerun passes this route>
```

If a screenshot/network/console artifact does not exist, explicitly write `not captured` and explain why. Do not leave evidence ambiguous.

### Filing guardrails

`super-qa-file-bug.sh` validates issue bodies before filing. It must reject weak tickets that are missing required sections or still contain placeholders like `TBD`, `<...>`, or `TODO:`. Do not bypass this with `SUPER_QA_ALLOW_WEAK_BODY=1` during normal autonomous runs. `--check-body` runs only these checks and exits (0, or the refusal code) without calling `gh`; super-collect's dry run uses it.

Every filed issue must include:

- `## Board summary` near the top for quick project-card context.
- A hidden `super-qa-meta` block with route, spec, iteration, area, category, priority, type, and `fingerprint`.
- A deterministic fingerprint. Use a meaningful key when known, such as `settings-users|add-user|no-op`; otherwise the script derives one from kind/route/category/title.

Dedupe policy: before creating a new issue, the script searches open `source:qa` issues for the fingerprint. If a match exists, it comments with the new evidence and returns the existing issue number instead of creating a duplicate Ready card.

## What counts as "green" — non-blank guards + forensics

A 200 response with a blank body is a bug, not a green test. Every spec
under `e2e/paths/` enforces:

- **No console errors** (`level === 'error'` only)
- **No uncaught page errors** (`page.on('pageerror', ...)`)
- **No 5xx network responses** during the run
- **No 401/403** on auth-required pages
- **Type-specific non-blank guard** (e.g., list-page: ≥1 row OR
  empty-state element; dashboard: ≥1 widget with non-`—` data) — see
  `docs/super-qa/page-types.md` "Non-blank guard" column

If any of those fire → cell is `[b]` → bug filed.

**DevKit repo** (it has `.agents/devkit/bin/post-fix-gate.py`): a QA pass also needs, on the branch
head QA tested after `git merge --no-edit origin/<base>`, the target tests green and
`python3 .agents/devkit/bin/post-fix-gate.py --run-tests --brief` (impacted, not `--full`: the merge point runs
that once on the merged tree) at exit 0, which writes the task receipt; and, when app/UI source changed on a
profile with a screen, a fresh `python3 .agents/devkit/bin/proof-capture.py` PNG. This holds when `/super-qa`
runs on its own, outside the board's worker preamble. Paste the gate's last line, the head SHA and the PNG into
the `[qa] [report]`; any other exit is not green, except an edited-test exit 2 (the gate's only reason is an
existing test the branch changed, #605): not a fail and not a block: list the edited tests in the report and hand
the card to Review, whose Antigravity audit cross-reviews them.

Per-spec forensics captured by `e2e/lib/report-fixture.ts`:

| Artifact | Path |
|----------|------|
| Screenshot per `report.step()` | `docs/super-qa/report/<slug>/tc-N/<locale>/*.jpg` |
| Console errors | `docs/super-qa/report/<slug>/tc-N/<locale>/console.log` |
| Page errors | `docs/super-qa/report/<slug>/tc-N/<locale>/pageerrors.log` |
| Network HAR | `docs/super-qa/report/<slug>/tc-N/<locale>/network.har` |
| Network summary | `docs/super-qa/report/<slug>/tc-N/<locale>/network.json` |
| Sentry probe | `docs/super-qa/report/<slug>/tc-N/sentry-events.json` |

The fixture (`e2e/lib/report-fixture.ts`) **already captures** console
errors, page errors, failed requests, network summary, and Sentry events,
plus HAR via `recordHar`. Disk writes are gated behind
`SUPER_QA_FORENSICS=1`; set it in every worker's environment. Fixture
exposes everything via `report.forensics.*` (e.g.
`report.forensics.consoleErrors`).
