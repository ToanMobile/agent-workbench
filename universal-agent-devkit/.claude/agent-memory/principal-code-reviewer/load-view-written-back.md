---
name: load-view-written-back
description: regression_checklist.load_view claims "never written back" but red_proof.keep_proof (record=True) and test_evidence_gate auto_link (non-linked) save() it — any new source merged into load_view leaks into tracked files
metadata:
  type: project
---

When a diff adds a data source to `regression_checklist.load_view` (overlay, pending store, ...), check every `load_view -> save()` caller:
`scripts/testing/red_proof.py keep_proof` (record=True: main, or DEVKIT_WORKTREE_CHECKLIST=1 as nightly sets) and the non-linked
branch of `auto_link` in `hooks/test_evidence_gate.sh`. Both write the whole view, so the new source's rows land in the tracked
checklist (probed 2026-10-25 on 8a1b4c95: `red_proof --pending` at trunk main flushed every pending row, main dirty).

**Why:** the docstring invariant is not enforced; only skip_bookkeeping kept load_view == load on the record path before.
**How to apply:** re-verify the caller list with `git grep -n "load_view"` before relying on this; probe with a scratch repo.
