---
name: new-receipt-kind-checklist
description: When a diff adds a new gate receipt kind or test-selection mode (scoped, task…), diff its write/drop rules against full_pass.json's, and compare its selection with run_impacted --list
metadata:
  type: project
---
A new receipt kind that push_gate / proof_gate accept "like the full receipt" tends to copy the doors but not the writer's rules.
Found 2026-10-29 reviewing #644 (scoped_pass.json): the scoped receipt skipped four rules the full one has —
precise-key hits written as PASS (full turns them UNTESTED/KEYED, P0-A); dropped only on exit 1/FAIL (full drops on any contradicting
exit, e.g. 2); PARTIAL_MODES / impacted / resource suites not excluded (full needs `not impacted_run`); no check that the receipt's diff
base covers the pushed range (task receipt has `merge-base --is-ancestor base task_mb`).

**Why:** each gap is a false green at the push/merge door; tests written for the new kind build receipts by hand and never hit them.
**How to apply:** for any new receipt kind, grep the full receipt's write call (`receipt_tests`, `partial`, `impacted_run`) and drop paths
(`_tree_store(... None)`), and list which ones the new kind inherits. For a new test selector, compare it with the old one cheaply:
`DEVKIT_IMPACT_TEST_CHANGED=<kit-rel path> bash tests/run_impacted.sh --list` (runs nothing) against the new selector's output over a
sampled set of files per extension (scratch .py probe; docs/data files were where #644's graph missed tests).
