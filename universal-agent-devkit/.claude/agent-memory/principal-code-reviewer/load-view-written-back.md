---
name: load-view-written-back
description: regression_checklist.load_view merges the untracked pending store; every load_view -> write path must write only its own rows (save_view_rows / pending_save_rows), never save() the whole view
metadata:
  type: project
---

`load_view` = tracked checklist + pending store (trunk-mode main). A caller that `save()`s the whole view flushes pending rows
into the tracked `.agents/regression_status.json` and main is dirty again (probed 2026-10-25 on 8a1b4c95: `red_proof --pending`
at trunk main flushed every pending row). Fixed in f0a5f842: `red_proof.keep_proof`, `test_evidence_gate` auto_link and
`enrich_context` now write through `save_view_rows` / `pending_save_rows` (only the rows they touched).

**Why:** the docstring invariant ("never written back") is not enforced by code; a new caller can reintroduce the flush.
**How to apply:** when a diff adds a `load_view` caller or a new source to it, `git grep -n "load_view\|save("` and check that no
path `save()`s the view; also check `_bug_command` / `migrate_pending` at trunk main (round-3 review found both writing tracked
files or restoring rows from HEAD). Probe with a scratch repo, not the real main.
