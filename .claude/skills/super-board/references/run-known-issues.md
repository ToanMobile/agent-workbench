# super-board run — known issues

Moved verbatim from [run.md](run.md) → "Worker self-check" (#1420): the incidents behind its checks and the
runner's zombie sweep. The rule they produced stays in run.md as a self-check item.

### Known issue — multi-attempt card moves (added 2026-05-22)

During the 2026-05-21 production run, several workers exited cleanly (process terminated, in-flight lock reaped) but **had not moved their card to the next column**. The dispatcher correctly re-dispatched (lane idle + card still in source column = re-fire) — but each retry burned a full lane cycle (~10 min) before the next worker tried again. The #382 Reviewer took **5 attempts × ~10 min = ~50 min** to move a card that the first attempt should have moved.

Suspected causes:
- Worker lost the response to a column move and exited "cleanly" without confirming its outcome. Preserve the unknown outcome and pause; do not claim success or blindly repeat the mutation.
- Worker's super-build/super-qa/super-review skill silently caught the move error and proceeded to assignee-release without surfacing the failure.

**Mitigation for now:** the dispatcher's `reap_finished_locks` + assignee sweep + re-dispatch keep the pipeline rolling, so this is a wall-clock issue, not a correctness issue. A worker that doesn't move the card will eventually have another worker do it.

**Required behavior:** check the shared halt record before a column move, attempt the mutation once, and preserve `move-mutation-result: ok|unknown|skipped` in the handoff. An uncertain outcome pauses the run for read-only reconciliation; it must never trigger blind replay.

### Known issue — lane-zombie workers (added 2026-05-24, auto-remediated)

**Symptom seen on fitbox-v4 first run:** a Tester worker successfully moved #81 QA → Review and the Reviewer subsequently merged it to Done — but the original Tester's `claude -p` process kept running for 30+ minutes afterward. The dispatcher's `lane_idle()` check uses `kill -0` on the lane PID and saw the zombie as "still busy," so the QA lane never re-dispatched. By the time it was noticed, the QA column had grown 1 → 2 → 3 cards with no Tester picking them up.

Different from the multi-attempt-move issue above: there the worker exited without moving the card; here the worker moved the card but didn't exit.

**Auto-remediation (now implemented in `super-board-run.sh` as anti-zombie control #7):**

Every tick — both cheap and expensive — `sweep_lane_zombies` runs `check_lane_zombie` for each lane. For each lane whose PID is alive AND whose claimed issue's current column is NOT in the lane's expected source set:

| Lane    | Expected source columns | Anything else means → |
|---------|-------------------------|-----------------------|
| build   | Ready, Building         | zombie                |
| qa      | QA                      | zombie                |
| review  | Review                  | zombie                |

On zombie detection: wait a grace period (`SB_ZOMBIE_GRACE`, default 60 s from first sighting) so the worker can print its final report and exit; after that `SIGTERM` + 1s + `SIGKILL` the PID, remove the inflight lock, idempotently sweep the assignee, clear the lane PID/issue vars, log `💀 zombie <lane> worker on #<N> (pid=<P>) — card moved to '<col>'; killing`. Uses the cached project items only — zero extra API calls per tick.

Trade-off: if someone (human or external tool) manually moves a card out of its source column while a worker is legitimately mid-work, the watchdog will kill that worker. Acceptable — manual board edits during an active run are an anti-pattern, and the worker would fail on its own column-move anyway.
