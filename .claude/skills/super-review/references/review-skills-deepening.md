# Super Review — Skill dependencies, Deepening opportunities

> Moved out of `SKILL.md` (Claude Code cuts a SKILL.md above 20000 characters, #545). Text is unchanged; `SKILL.md` points here.

## Skill dependencies

The reviewer loads three skills, all scoped to the diff:

- `mattpocock-skills:code-review` — the two-axis review. **Standards** (does the diff
  follow this repo's documented standards, plus the Fowler smell baseline) and **Spec**
  (does it implement the originating issue's acceptance criteria). Always pass the fixed
  point explicitly — `git merge-base HEAD origin/<base>` — so it never stops to ask for
  one. A Spec-axis finding that contradicts the AC is a Blocker, not a nit.
- `mattpocock-skills:codebase-design` — the deep-module vocabulary used in step 2 and in
  every deepening opportunity written below. It is vocabulary, not a workflow: no report,
  no prompts, nothing to wait on.
- `ponytail:ponytail-review` — the Over-engineering pass in step 3, on the merge-base
  diff. Optional plugin: when it is not installed, use the inline ladder in step 3.
  Its findings are Should fix at most; it never decides merge-or-bounce.

**Never load inside the lane:** `mattpocock-skills:improve-codebase-architecture`. It
scans the whole codebase rather than the diff, writes a Tailwind/Mermaid HTML report and
shells out to `open`, then asks the user which candidate to explore and hands off to
`grilling`. Every one of those is fatal to an unattended reviewer. It is a
you-at-the-keyboard tool — run it yourself against the cards this lane files.

## Deepening opportunities

Architecture taste is real, and it is not a merge gate. The reviewer's job is
merge-or-bounce; a shallow module in an otherwise-correct diff is a **future ticket**,
not a reason to hold a green PR hostage.

```
  diff is correct + tests green + threads clean
            │
            ├─→ merge protocol                       ← the gate
            │
            └─→ shape friction noticed in the diff
                      │
                      └─→ super-review-file-refactor.sh
                              label: refactor · column: Backlog
                              → you run improve-codebase-architecture
                                against it later, at a desk
```

File one when the diff leaves a module whose **interface is nearly as complex as its
implementation**, puts a **seam** somewhere a caller has to work around, or spreads
behaviour across call sites so a future fix has no **locality**. Use the
`codebase-design` glossary terms exactly — a card that says "this feels messy" is a card
nobody can action.

Do **not** file one for: style, naming a future refactor might rename anyway, anything an
existing ADR in `docs/adr/` already settled, or a shape the issue's acceptance criteria
explicitly asked for. The script dedupes by fingerprint, so re-reviewing a bounced card
will not stack duplicates.
