#!/usr/bin/env bash
# 2026-11-12 RUNAWAY: with the merge queue on, the reviewer posted `edited-tests:` in the approval comment. That line pins the
# approval to the head, so every main move made the train answer gate-exit-2 ("edited-test review is stale"), the card went back
# through Build, QA and Review, main moved again, and no card reached Done in 240 cycles. The PM audit record (no comment line)
# survives main moving, so the queue-on rule must tell the reviewer NOT to post the line.
#  D1 super-review/SKILL.md queue-on step says NO `edited-tests:` line.
#  D2 run.md Reviewer queue-on step says NO `edited-tests:` line.
#  D3 the queue-off paths (merge gate) still post `edited-tests:` (the gate reads the comment there).
cd "$(dirname "$0")/../.." || exit 1
SKILL=.claude/skills/super-review/SKILL.md
RUN=.claude/skills/super-board/references/run.md
fails=0
ok()   { echo "ok   $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

grep -q 'and NO `edited-tests:` line (queue on only)' "$SKILL" \
  && ok "D1: SKILL.md queue-on says no edited-tests line" || fail "D1: SKILL.md queue-on step still tells the reviewer to post edited-tests"
grep -q 'and NO `edited-tests:` line (queue on only' "$RUN" \
  && ok "D2: run.md queue-on says no edited-tests line" || fail "D2: run.md queue-on step still tells the reviewer to post edited-tests"
grep -q 'post `approved-head` plus `approved-by` plus `edited-tests:` as its own comment' "$SKILL" \
  && ok "D3: SKILL.md queue-off still posts edited-tests" || fail "D3: queue-off edited-tests instruction lost"

[ "$fails" -eq 0 ]
