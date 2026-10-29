# Super Review — Review flow

> Moved out of `SKILL.md` (Claude Code cuts a SKILL.md above 20000 characters, #545). Text is unchanged; `SKILL.md` points here.

## Review flow

1. **Establish scope**
   - Identify branch, base branch, PR, changed files, and user goal.
   - Check working tree status before reviewing.
   - If there are unrelated dirty files, stop and ask before touching them.
   - Load `prior_report`. If one exists, run round 1 of "Review remembers" before step 2.

2. **Inspect changes — your own pass first**
   - **Before reading the builder's account** (PR description summary, `[builder] [report]` comment, Tester
     handoff), read the issue's acceptance criteria and the raw diff, and write down 2–4
     hypotheses: what must be true for this to be right, and where it would most likely
     break. Reading their summary first anchors you on their framing; the point of a
     reviewer is a second, independent solver.
   - Then read their claims and check each one against the code and test output, the same
     way you check your own hypotheses. A claim is a lead, not evidence.
   - Read the diff and the affected modules.
   - Load `mattpocock-skills:codebase-design` and read the diff through its vocabulary
     — **module**, **interface**, **depth**, **seam**, **adapter**, **leverage**,
     **locality**. Ask the shape question the diff raises: does this land behind a
     small interface, or does it widen one? Apply the deletion test to anything the
     diff adds that looks shallow.
   - Scope is the diff, **never the whole codebase**. A hot spot three modules away
     is not this PR's problem.
   - Check app-specific conventions from the nearest `CLAUDE.md` / `AGENTS.md`, especially:
     - `clock.now()` instead of `new Date()`;
     - services own business logic, repositories own data access;
     - job handlers own outer transactions;
     - money uses `numeric(12,2)`;
     - calendar days use `date`, not `timestamptz`;
     - structured `AppError({ error_code, context })`;
     - jsonb writes are Zod-validated.
   - **DevKit repo** (it has `.agents/devkit/bin/post-fix-gate.py`): the reviewed head needs a
     `post-fix-gate.py --run-tests --scoped --brief` exit 0 (its scoped receipt) on that exact SHA — read it from QA's
     report and never rerun post-fix-gate --full yourself: the merge point (the merge queue's train; queue off,
     the merge gate) verifies the merged tree once with `--scoped`, which escalates to `--full` on a core file. A review run on its own, outside the board,
     runs the impacted gate itself when QA left no result for this SHA; its merge goes through the merge gate
     with `--standalone`, which runs the full verify (Merge protocol step 2) — only outside the board, never
     inside a board lane.
     It also needs an `.agents/devkit/bin/ocr-review` pass on the diff. Missing either is a
     **Verification miss**, also when `/super-review` runs on its own, outside the board.

3. **Classify findings** — every finding gets a **class** (what kind of problem) and a
   **severity** (does it block). Class:
   - **Gap** — an acceptance criterion or requested behaviour is missing or incomplete.
   - **Bug** — the code likely fails or regresses behaviour.
   - **Verification miss** — the code may be right, but the evidence does not prove it
     (missing test, test asserts the wrong thing, skipped rerun).
   - **Scope drift** — the diff changes something the issue did not ask for, or skips a
     stated constraint.
   - **Over-engineering** — the diff works but builds more than the AC needs: a new
     dependency, abstraction, config or file where the codebase, stdlib, a native feature
     or one line already covered it. Find these with `ponytail:ponytail-review` on the
     merge-base diff (`git merge-base HEAD origin/<base>`); plugin not installed → ask the
     ponytail ladder of each addition yourself: needed at all? already in the codebase?
     stdlib? native? an installed dep? one line? Always **Should fix**, routed to
     Super Build — it **never blocks a merge on its own**. A simplification that would
     cut validation, security, data-loss protection or accessibility is not a finding.
   - **No issue** — you checked a hypothesis or claim and it holds. Not a finding: list it
     on the report's `✅ Done` line with the file:line or command that showed it. Saying what is
     right stops the next round re-litigating it.

   Severity:
   - **Blocker:** correctness, data loss, security, auth, migrations, money, customer-visible broken behavior, or failing required tests.
   - **Should fix:** maintainability, missing tests, risky edge cases, accessibility, i18n, observability, or design drift that is clearly in scope.
   - **Nit / optional:** style or cleanup that does not block merge.
   - **Deepening opportunity:** the diff is correct but leaves a shallow module, a
     seam in the wrong place, or behaviour spread across call sites. **This never
     blocks a merge.** A green PR does not get held for architecture taste — file it
     and merge. See "Deepening opportunities" below.
   - **Human gate:** product/design/ops decision that cannot be safely guessed.

4. **Route fixes**
   - If a blocker is an implementation task, hand it to **Super Build**.
   - If a blocker is a functional regression, hand it to **Super QA**.
   - If a blocker is visual/design fidelity, file a UI ticket; a human can run `/ui-refine-loop` (the board never triggers it).
   - If it is a deepening opportunity, file it with `.claude/bin/super-review-file-refactor.sh` and carry on to the merge decision. Do not open a PR thread for it; do not bounce the card.
     `--title` is the bare problem: the filer adds the `♻️ [refactor] <scope>:` prefix, so never pass one.
     The `--body-file` uses the ticket format (writing-standard.md § 3): `## Problem`,
     `## Context` (`- **Where:**` the module and files), `## Fix` — the filer refuses a body
     without them. **Write real acceptance criteria too.** A card that carries an
     `## Acceptance Criteria` checklist is filed straight into `Ready` and the next wave builds it;
     one without lands in the holding column and waits for `super-board lint`. That is the whole
     difference between a finding that gets fixed this week and a note nobody grades. Two or three
     checkable lines is enough — what must be true when this is done, in terms a test can assert.
     The filer appends `## Risk` and `## Blocked by` for you when you have not written them.
   - If the user explicitly authorizes Super Review to fix, make the smallest safe patch, verify it, and clearly report that review also changed code.

5. **Verify evidence**
   - Run the smallest meaningful verification for the touched area.
   - Prefer targeted tests first; run broader suites when the change crosses boundaries.
   - For upload/import flows, do not call it complete from UI success or HTTP 200 alone; verify jobs reach terminal state and destination records are saved.
   - If verification is skipped, state why and mark merge-readiness as unverified.

6. **Report**
   - Lead with the final status: `merge-ready`, `blocked`, `human-gated`, or `unverified`.
   - Include findings grouped by severity.
   - Include verification commands and results.
   - Include which Super workflow should own each fix.
