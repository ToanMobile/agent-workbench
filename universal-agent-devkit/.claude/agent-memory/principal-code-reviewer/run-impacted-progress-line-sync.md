---
name: run-impacted-progress-line-sync
description: A new run_impacted.sh stderr line that carries a test path can satisfy tests that wait on that path (test_run_impacted.sh killed-run case) too early
metadata:
  type: feedback
---
When a diff adds or changes a progress line in `tests/run_impacted.sh` (`· start` / `· done`, #427, #473), grep every
test that reads the runner's output for waits or counts on a bare test name. In 2026-10-28 (#473 review) the new
`· start <test>` line satisfied test_run_impacted.sh's wait `grep -q "test_fast_…"`, which was meant to wait for the
`· done` line, so the kill could land before `· done` (a probe with 0.5 s latency: HEAD PASS, diff FAIL).

**Why:** these tests sync on events, not clocks (#430). A line printed earlier with the same name turns the event
into a race that only fails under load.

**How to apply:** for each such wait or count, check that it is anchored to the line kind (`^· done …`, `^✔ `), and
check that the gate's `HANG_START_RE` / `HANG_DONE_RE` still match the runner's real printf. See [[load-view-written-back]] for another
case of a tool's output feeding back into a tracked consumer.
