# Super Review — Output format, Review Loop behavior, Review remembers

> Moved out of `SKILL.md` (Claude Code cuts a SKILL.md above 20000 characters, #545). Text is unchanged; `SKILL.md` points here.

## Output format

The report follows writing-standard.md § 4: a comment header, ≤ 8 lines, then one findings
table. In a super-board run it is ONE PR comment, **edited in place** every round (see "Review
remembers"); R-ids never change.

```markdown
<!-- super-review:report -->
[reviewer] [report] <✅ merge-ready | ❌ bounced | 🛑 blocked | 🙋 human-gated | ⚠️ unverified> · round <N>
Did: <scope reviewed · base · verification command + result>
✅ Done: <prior findings fixed, hypotheses that held — each with file:line or command>
❌ Not done: <open findings by id, or what you could not verify and why>   (omit when nothing)
Next: <builder | qa | Eric | none>

| ID | Owner | Class | Where | Finding | Status |
|---|---|---|---|---|---|
| R1 | builder | Bug | `src/cart.py:12` | <finding> | ✅ fixed |
| R2 | builder | Bug | `src/cart.py:31` | <finding> | ❌ not fixed |
| R3 | qa | Verification miss | `tests/test_cart.py:8` | <finding> · blocker | open |
| R4 | builder | Over-engineering | `src/fmt.py:1` | <what it builds> → <smaller thing> · should fix, never blocks alone | open |
```

- Owner: `builder` (Super Build) · `qa` (Super QA) · `ui` (UI ticket; a human runs
  `/ui-refine-loop`) · `Eric` (human gate).
- Mark `blocker` or `should fix` in the Finding cell. Over-engineering is always `should fix`.
- Deepening opportunities filed with `super-review-file-refactor.sh` get a row with Status
  `filed #<issue>`.
- Human gates: the header says `🙋 human-gated` and `Next: Eric`; the decision goes in a row.

For short summaries (wave reports), keep it phone-friendly:

```markdown
[reviewer] [report] 🛑 blocked · PR #123
Did: `npm test -- --run imports` green
❌ Not done: R1 functional bug → qa · R2 schema decision → Eric
Next: qa
```

## Review Loop behavior

In a `super-board run` the loop runs through the board:

1. Super Review inspects branch/PR and writes findings.
2. Each actionable finding becomes a prefixed PR thread (`[builder]`, `[qa]`) and the card bounces to the owning lane — Super Build or Super QA; for visual polish, file a UI ticket; a human can run `/ui-refine-loop`.
3. The owning lane fixes and verifies its scope.
4. Super Review runs again against the updated branch, with its last report as `prior_report` — round 1 checks those findings before any fresh pass.
5. Stop only when no blocking review findings remain, or unresolved items are explicitly human-gated. A clean review merges through `.claude/bin/super-board-merge-gate.sh`, pinned to the head SHA it reviewed.

Super Review should not silently push fixes during the loop unless the user explicitly grants that authority.

## Review remembers

A re-review starts from the last one. Without it, a rebuilt card gets a fresh reviewer who
re-litigates settled points, misses that a finding was "resolved" without a fix, and can
bounce forever on a moving target.

**Lookup — one call, by marker.** Every report starts with `<!-- super-review:report -->`.
`prior_report` is the newest PR comment carrying it:

```bash
gh pr view <PR> --json comments \
  --jq '[.comments[] | select(.body | contains("<!-- super-review:report -->"))] | last | {url, body} // {}'
```

The number after `#issuecomment-` in `url` is the comment id. Write this round's report over it:
`gh api -X PATCH repos/<owner>/<repo>/issues/comments/<id> -F body=@report.md`. One report per
PR, edited in place, so the table carries every round's status.

Outside super-board (no PR), `prior_report` is whatever earlier review the caller hands you.

**No prior report** → first review. Behave exactly as before.

**Round 1 — check each prior finding before anything else.** Mark every one:

- `fixed` — cite the file:line that shows it.
- `not fixed` — still true of the code. A resolved thread is not evidence, and neither is
  the builder's reply saying it was fixed; read the code.
- `no longer applies` — the code it pointed at is gone, or the AC changed. Do not re-raise it.

Any `not fixed` (other than Over-engineering, which never bounces alone) → **bounce again**: set those rows to `❌ not fixed`, keeping their
original ids and owners. Skip the fresh pass; it would review code that is about to change.
All clear → round 2 is the normal fresh pass. New findings take ids after the highest one used.

## Convergence — every round is narrower than the last

A review loop that keeps finding something never ends: PR #1312 opened four new findings (R5–R8)
in round 2 and its card reached `loop:rebuild-4`; two of them (R6, R7) were more places of a
pattern round 1 had already reported once (R3, R2). These rules come from Anthropic's "Solving
code review" convergence fixes. No rule here adds a human step.

1. **Report the class, not the line (every round, round 1 above all).** Before you post a
   finding, ask whether it is one place of a pattern: an exit code a caller does not handle, a
   missing rate-limit or error check, an unescaped input, a test that cuts the function out with
   `sed`. If so, search the whole merge-base diff and the callers of what it changes for the
   other places, and write ONE finding: the class in the Finding cell, every place in `Where`, and
   the sentence `class: fix every place, also ones not listed`. A later round that finds another
   place of a class already reported adds it to that row; it is not a new finding.
2. **Pre-existing code is not this PR's finding.** A defect on lines the merge-base diff
   (`git diff origin/<base>...HEAD`) neither adds nor changes gets Class `Pre-existing`: no PR
   thread, never a bounce, never a block. A real bug is filed for the board
   (`.claude/bin/super-qa-file-bug.sh`, Status `filed #<issue>`); style or taste is dropped.
   It is the PR's own Bug, not Pre-existing, when the diff makes old code fail or reachable
   (a new exit code an old caller mishandles, a new caller of an unsafe function).
3. **From the second review on, the fresh pass reads only what changed.** Write the head you
   reviewed on the `Did:` line as `@ <sha>`. Next time, after the prior findings are all clear,
   review `git diff <that sha>..HEAD` (that sha is not an ancestor of HEAD, or the report has
   none: the merge-base diff, commits that only merge `origin/<base>` skipped). Raise a new
   finding only on those lines or on what they break. One exception: a Blocker for security,
   auth, money, data loss or a destructive migration anywhere in the merge-base diff is still
   raised; say in the row that round 1 missed it.
4. **A Nit never costs a round.** Nit / optional findings get a row, no thread, and never
   bounce a card, alone or together. If the card bounces for another finding, the builder may
   take them in the same push.
5. **Never post a finding twice.** A finding already in the table keeps its id and row; a new
   wording of it is not a new finding.

The audit, the test rerun and the merge gate still run on the whole PR head: narrowing the
reviewer's fresh pass removes none of them.
