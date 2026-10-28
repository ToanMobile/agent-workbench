#!/usr/bin/env bash
# run_impacted.sh selects a test when its text names a changed file. 28/10 (#607): editing skills/parallel-lanes/SKILL.md
# selected every test that mentions "SKILL.md" (16 tests, ~189 s, none about parallel-lanes) because the match used the bare
# basename. A basename that several DevKit files share is matched with its parent folder ("parallel-lanes/SKILL.md"); a
# unique basename still matches alone, and tests/impact_map.txt still adds the declared readers (skills/*/SKILL.md ->
# test_skill_size.sh).
# bash 3.2 compatible.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
. "$DEVKIT_DIR/tests/lib/clean_git_env.sh"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
list() { DEVKIT_IMPACT_TEST_CHANGED="$1" bash "$DEVKIT_DIR/tests/run_impacted.sh" --list 2>/dev/null; }

sel="$(list skills/parallel-lanes/SKILL.md)"
printf '%s\n' "$sel" | grep -qx "tests/installer/test_i18n_profiles.sh" \
  && fail "an ambiguous basename (SKILL.md) still selects a test that only names another skill's SKILL.md" \
  || ok "skills/parallel-lanes/SKILL.md does not select tests that name only another skill's SKILL.md"
printf '%s\n' "$sel" | grep -qx "tests/verification/test_skill_size.sh" \
  && ok "  … the impact_map reader of skills/*/SKILL.md is still selected" || fail "impact_map reader test_skill_size.sh lost"
printf '%s\n' "$sel" | grep -qx "tests/verification/test_repo_consistency.sh" \
  && ok "  … repo consistency still runs" || fail "repo consistency dropped"

# OCR 29/10: tests read a skill's SKILL.md through variables (SKILL=…/skills/devkit-audit, "$d/SKILL.md")
printf '%s\n' "$(list skills/devkit-audit/SKILL.md)" | grep -qx "tests/verification/test_devkit_audit_nightly_step.sh" \
  && ok "skills/devkit-audit/SKILL.md selects test_devkit_audit_nightly_step.sh (reads it through a variable)" \
  || fail "skills/devkit-audit/SKILL.md lost test_devkit_audit_nightly_step.sh"
printf '%s\n' "$(list skills/tdd-workflow/SKILL.md)" | grep -qx "tests/verification/test_skill_eval.sh" \
  && ok "skills/tdd-workflow/SKILL.md selects test_skill_eval.sh" || fail "skills/tdd-workflow/SKILL.md lost test_skill_eval.sh"

sel="$(list skills/impeccable/SKILL.md)"
printf '%s\n' "$sel" | grep -qx "tests/verification/test_impeccable_skill.sh" \
  && ok "a test naming impeccable/SKILL.md is selected for it" || fail "impeccable/SKILL.md lost its own test"

# review 28/10: only SKILL.md narrows. profiles/game/DESIGN.md is read as "$GAME/DESIGN.md" by test_game_blender_default.sh and
# profiles/<p>/RULES.md through "profiles/%s/RULES.md": their bare names must keep selecting those tests.
printf '%s\n' "$(list profiles/game/DESIGN.md)" | grep -qx "tests/verification/test_game_blender_default.sh" \
  && ok "profiles/game/DESIGN.md still selects test_game_blender_default.sh (bare name kept)" || fail "profiles/game/DESIGN.md lost test_game_blender_default.sh"
printf '%s\n' "$(list profiles/backend/RULES.md)" | grep -qx "tests/context_memory/test_profile_split.sh" \
  && ok "profiles/backend/RULES.md still selects test_profile_split.sh" || fail "profiles/backend/RULES.md lost test_profile_split.sh"

sel="$(list scripts/git/worktree.py)"
printf '%s\n' "$sel" | grep -qx "tests/worktree_git/test_worktree_lane.sh" \
  && ok "a unique basename (worktree.py) still selects by name alone" || fail "unique basename worktree.py lost test_worktree_lane.sh"

echo
[ "$FAILS" -eq 0 ] && { echo "test_impacted_ambiguous_basename: PASS"; exit 0; } || { echo "test_impacted_ambiguous_basename: FAIL ($FAILS)"; exit 1; }
