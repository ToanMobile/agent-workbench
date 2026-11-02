# Super QA — Page-type taxonomy and Critical paths (HUMAN GATE)

> Moved out of `SKILL.md` (Claude Code cuts a SKILL.md above 20000 characters, #545). Text is unchanged; `SKILL.md` points here.

## Page-type taxonomy

Classification gives the worker a test recipe per kind of place. See
`docs/super-qa/page-types.md` for the canonical list:

```
list-page       form-page       settings-page
detail-page     dashboard-page  modal/drawer
public-page     import-flow     wizard
                                settings-tab
```

Classification order: URL-pattern heuristic first (cheap default) → AI
override if the heuristic looks wrong → hand-curated override in
`page-types.md` if the user wants to lock something in.

## Critical paths (HUMAN GATE)

`docs/super-qa/critical-paths.md` is a hand-curated list of
money-flow specs that MUST always be green (login, create order, take
payment, run cutoff snapshot, send driver email). The user maintains it;
the skill never auto-edits it.

If any critical-path spec has been red for **>2 consecutive iters**, the
the iteration ends with status **4 (HUMAN GATE)**. The loop halts. A human investigates.
This protects production-critical flows from being silently broken by
in-flight queue items.
