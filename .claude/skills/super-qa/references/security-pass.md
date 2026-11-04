# Super QA — Security pass (every PR with code)

QA's one security check, ported from upstream super-board 3.3.0. It runs on every PR that changes code,
not only on security labels. It reads the diff; `.claude/hooks/security_gate.sh` stays a separate per-session
check that a review ran after an attack-surface edit.

1. Skip the pass only when every file in the PR diff is docs (`*.md`), a test, or a binary asset (images,
   audio, video, fonts, 3D models). Scenes, prefabs, scripts, configs and workflows are code and still get the
   pass; one such file in a mixed diff runs it. Say `pr-security-review: skipped (no code in diff)` on the
   `Did:` line. A `qa` card with no PR yet says `pr-security-review: no diff`.
2. Otherwise load `pr-security-review` and follow it on the PR's diff against its base branch
   (`gh pr view <PR> --json baseRefName`). It runs in this lane, not in a sub-agent: it launches its own
   finding and false-positive sub-tasks.
3. Each finding it keeps is a QA failure, filed the normal way: one `❌ Not done` line
   (`security: <category> — <one line> · <file:line>`), one `[builder]` PR thread on that line, then the
   **Fail** exit (QA → Ready, `loop:rebuild-N`). A finding outside the card's scope is filed with
   `super-qa-file-bug.sh` (`source:qa`, priority high) and still fails the card while the PR adds the hole.
4. A finding you can show is wrong goes on the `✅ Done` line with the proof.
5. No findings → `pr-security-review: 0 findings` on the `Did:` line.
6. Skill missing → Block the card with the block-template comment and `super-board-needs-you.py mark` (a person
   installs the skill; `setup fix` does it for a pack install). Never pass a code PR unchecked. The runner's
   skills-ready check normally stops before this point (exit 10).

The Review lane does not run this pass. For a deep audit of the whole repo, mention `security-audit`
(standalone, if installed); never run it from the lane.
