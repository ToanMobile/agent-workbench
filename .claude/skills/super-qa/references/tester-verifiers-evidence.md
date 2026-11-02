# Super QA — Tester verifiers, handoff comment and evidence format

> Moved out of `SKILL.md` (Claude Code cuts a SKILL.md above 20000 characters, #545). Text is unchanged; `SKILL.md` points here.

### Optional project feature verifier

For an existing `.agents/skills/verify-<app>/` map, verifier creation during Onboard,
or source/selector upkeep, read [project-verifier.md](project-verifier.md).
Run relevant mapped features alongside issue AC checks; state missing/stale coverage
in the existing handoff. A map inspection or starter template proves no test pass.

### Optional runtime performance and memory checks

For runtime evidence requested by the issue, or a configured
`runtime_verification.config`, read [runtime-verification.md](runtime-verification.md).
Use the shared runner with a project-owned scenario and existing Playwright. Compare
pinned original/changed apps with matching data/environment, warmups and at least
five alternating samples each. Attach timing ranges, heap evidence, correctness
failures and verdict to the normal QA handoff under `Runtime checks:`. A noisy or
inconclusive result cannot prove a performance AC; do not replace correctness
checks or add profiling to unrelated issues.

### Pass-handoff PR comment MUST include the test command
Every Pass-handoff PR comment includes a `Local tests:` line with the EXACT command Reviewer will re-run as the self-verification gate:
```
Local tests:  npm test --run streaming
```
This is non-optional. Reviewer re-runs this command; red → bounce back to QA.

### Issue-comment evidence format (REQUIRED — both pass and fail)

The Tester's issue comment is the user's primary visibility into "is this actually fixed." A bare directory path is not sufficient — the user wants to *see* the proof on the issue page.

**The canonical template lives in `.claude/skills/super-board/references/run.md` → "Screenshot embed format" (right after Tester first pass).** Do not duplicate it here; both lanes (super-board Tester + standalone super-qa) follow that exact format. Summary of rules workers must obey:

- Capture screenshots at the standard viewports for UI ACs: **desktop 1920×1080, tablet 1024×768, mobile 375×667**.
- Commit the screenshots to the issue branch and push *before* writing the comment — inline image URLs won't render unless the file is on GitHub.
- Use the `https://github.com/<OWNER>/<REPO>/raw/<SHA>/...` URL form, `<SHA>` = the commit that added the screenshots, so images keep rendering after the branch is deleted on merge. Resolve `<OWNER>/<REPO>` from `git remote get-url origin`.
- Embed the same screenshots in BOTH the PR timeline comment AND the issue comment — the issue page is the user's primary view.
- Name the evidence folder once (`runs/issue-<N>-qa-v<V>/`) — no file lists.
- For non-visual ACs (API tests, migration SQL), skip the screenshot table but keep the evidence-path line. State the omission explicitly so the user knows it was intentional.
- If screenshot capture fails (no display, headless crash), document the reason and link alternative evidence (log file, HTTP trace) rather than silently dropping the requirement.
- Failure comments use the same format with broken-state screenshots (e.g., `before-fix-desktop.png`).
