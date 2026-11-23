# claude-verify seal — Reviewer steps (#1328)

Moved out of `SKILL.md` (size limit < 20000 characters, `tests/verification/test_skill_size.sh`). Walk these steps on the
merge-queue-on path when the cross-review is claude-verify.

1. Your session writes the review as JSON
   `{head, base: merge-base(origin/<base>, head), findings: [{id, severity: important|nit|pre-existing, file, line, snippet, class}], reviewed_at}`
   (every finding cites a line the PR added at head; `pre-existing` may cite any line of a changed file).
2. Run `python3 .agents/devkit/bin/claude_verify.py seal --repo <review worktree> --head <sha40> --report <file> --branch <PR branch>`:
   - exit 0 prints `task_id=CV…` (verdict pass);
   - exit 4 = an `important` finding (no approval: route the fix);
   - exit 2 = refused (report, branch or session; fix it or take the Antigravity path);
   - exit 3 = cannot check (git/kit error, or seal mode on without the owner's claude-verify signer): `blocked-by: agent`.
3. On exit 0 post `approved-head:<sha40>` with
   `approved-by: {"reviewer":"claude-verify","builder":"<builder lane id>","task_id":"CV…","gate_receipt":"<impacted task receipt id>"}`.

The seal needs your session in the card's reviewer ledger and not in its builder ledger; the runner records both before the workers
start. A manual session outside the board takes the Antigravity path or the owner's approval. The `workflow` backend records no session
ledger, so its reviews take the Antigravity path. A valid claude-verify pass seal also approves edited/deleted existing tests covered by its `base..head` diff (matching head/tree, `base == merge-base(trunk, head)`, reviewer != builder, valid Ed25519 signature when seal mode is on).
