#!/usr/bin/env bash
# Regression test: tests/impact_map.txt — the tests run_impacted.sh adds for a changed file that they exercise
# WITHOUT naming it (run_impacted.sh otherwise selects a test only when its text mentions the changed file's
# name). 2026-10-03: a change to scripts/context/enrich_context.py selected 3 of 101 tests and left out
# hooks/tests/test_prompt_dedupe.sh and hooks/tests/hook_contract_test.sh, which found two regressions the gate's
# own selection would have let through (INSTINCT-022 and INSTINCT-026 had both warned).
# bash 3.2 compatible.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
. "$DEVKIT_DIR/tests/lib/clean_git_env.sh"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
MAP="$DEVKIT_DIR/tests/impact_map.txt"

[ -f "$MAP" ] && ok "tests/impact_map.txt exists" || { fail "tests/impact_map.txt is missing"; echo "❌ test_impact_map: $FAILS failed"; exit 1; }
# every mapped test exists, every line has a glob and at least one test
bad=0; n=0
while read -r glob rest; do
  case "$glob" in ''|'#'*) continue ;; esac
  n=$((n + 1))
  [ -n "$rest" ] || { fail "map line '$glob' lists no test"; bad=1; continue; }
  for t in $rest; do [ -f "$DEVKIT_DIR/$t" ] || { fail "map line '$glob' names a test that does not exist: $t"; bad=1; }; done
done < "$MAP"
[ "$bad" = 0 ] && [ "$n" -gt 0 ] && ok "all $n map lines name tests that exist" || fail "map has problems ($n lines)"

# run_impacted --list with a simulated change selects the mapped tests (and runs nothing)
# DEVKIT_GATE_DONE (set by post-fix-gate for the tests it already ran) would drop e.g. hook_contract_test.sh from the list
# when this test itself runs inside the gate: the selection under test is the unfiltered one.
sel() { (cd "$DEVKIT_DIR" && env -u DEVKIT_GATE_DONE DEVKIT_IMPACT_TEST_CHANGED="$1" bash tests/run_impacted.sh --list 2>/dev/null); }
out="$(sel scripts/context/enrich_context.py)"
for t in hooks/tests/test_prompt_dedupe.sh hooks/tests/hook_contract_test.sh tests/context_memory/test_prompt_context.sh; do
  printf '%s\n' "$out" | grep -qx "$t" && ok "enrich_context.py change selects $t" || fail "enrich_context.py change does not select $t"
done
out="$(sel bin/post-fix-gate.py)"
printf '%s\n' "$out" | grep -qx "tests/gates/test_gate_friction.sh" && ok "post-fix-gate.py change selects test_gate_friction.sh" || fail "post-fix-gate.py change does not select test_gate_friction.sh"
out="$(sel skills/ui-ux-pro-max/data/stacks/unity-ugui.csv)"
printf '%s\n' "$out" | grep -qx "tests/verification/test_ui_ux_pro_max_data.sh" && ok "a ui-ux-pro-max data change selects its data test" || fail "ui-ux-pro-max change does not select test_ui_ux_pro_max_data.sh"
# 2026-10-05: bin/install.sh runs adapters/setup_*.sh and sources scripts/git/backup_conflict.sh, and no test names them: a change to an
# adapter selected repo consistency only, one to backup_conflict.sh missed the four install tests that catch a mutation of it.
for f in adapters/setup_claude.sh adapters/setup_codex.sh adapters/setup_cursor.sh adapters/setup_gemini.sh scripts/git/backup_conflict.sh; do
  out="$(sel "$f")"; miss=""
  for t in tests/installer/test_install_idempotency.sh tests/installer/test_install_safety.sh tests/installer/test_platform_rules.sh tests/installer/test_uninstall.sh; do
    printf '%s\n' "$out" | grep -qx "$t" || miss="$miss $t"
  done
  [ -z "$miss" ] && ok "$f change selects the install tests" || fail "$f change does not select:$miss"
done
# git-commit-msg.sh is the body of the commit-msg hook: only test_commit_hygiene makes commits through it (a mutant that turns the rule off
# leaves test_githooks green and turns test_commit_hygiene red), and it names the hook, not the script.
out="$(sel scripts/git/git-commit-msg.sh)"
printf '%s\n' "$out" | grep -qx "tests/worktree_git/test_commit_hygiene.sh" && ok "git-commit-msg.sh change selects test_commit_hygiene.sh" || fail "git-commit-msg.sh change does not select test_commit_hygiene.sh"
# 21/10 (#31): scripts/governance/fold_agent_file.py (CLAUDE.md folded into AGENTS.md at install) and devkit_i18n.py (the i18n of installed
# files) are named by no test; the install and i18n tests exercise them through bin/install.sh.
out="$(sel scripts/governance/fold_agent_file.py)"
printf '%s\n' "$out" | grep -qx "tests/installer/test_uninstall.sh" && ok "fold_agent_file.py change selects test_uninstall.sh" || fail "fold_agent_file.py change does not select test_uninstall.sh"
out="$(sel scripts/governance/devkit_i18n.py)"
printf '%s\n' "$out" | grep -qx "tests/installer/test_i18n_profiles.sh" && ok "devkit_i18n.py change selects test_i18n_profiles.sh" || fail "devkit_i18n.py change does not select test_i18n_profiles.sh"
out="$(sel LICENSE)"
printf '%s\n' "$out" | grep -qx "hooks/tests/test_prompt_dedupe.sh" && fail "an unrelated change selects a mapped test" || ok "an unrelated change selects nothing from the map"
# 25/10 (audit B6): the stem (name without extension) of a changed file is matched as a word only for a CODE file (.sh .py .bash .mjs
# .js): a test reaches a script through a command ("$KIT githooks install" → scripts/git/githooks.sh). For a doc the stem is a common
# word: commands/test.md selected 273 tests through "test", commands/fix.md 202 through "fix". A doc's real readers sit in the map.
out="$(sel commands/fix.md)"; n="$(printf '%s\n' "$out" | grep -c .)"
[ "$n" -le 20 ] && ok "commands/fix.md selects $n tests (≤ 20: a doc's stem is no word match)" || fail "commands/fix.md selects $n tests (> 20: its stem 'fix' matched as a word)"
CMD_TESTS="tests/installer/test_install_cli.sh tests/installer/test_install_idempotency.sh tests/installer/test_install_safety.sh tests/installer/test_install_alias.sh tests/installer/test_install_user_data.sh tests/installer/test_uninstall.sh tests/installer/test_i18n_profiles.sh tests/context_memory/test_local_tier.sh tests/worktree_git/test_restore_old.sh tests/worktree_git/test_x_old_conflict_isolation.sh"
for f in commands/fix.md .claude/commands/review.md; do
  out="$(sel "$f")"; miss=""
  for t in $CMD_TESTS; do printf '%s\n' "$out" | grep -qx "$t" || miss="$miss $t"; done
  [ -z "$miss" ] && ok "$f selects the tests that read the kit's commands/" || fail "$f does not select:$miss"
done
out="$(sel scripts/git/githooks.sh)"
for t in tests/worktree_git/test_githooks.sh tests/worktree_git/test_commit_hygiene.sh; do
  printf '%s\n' "$out" | grep -qx "$t" && ok "githooks.sh (code) still selects $t" || fail "githooks.sh does not select $t (test_commit_hygiene names only the stem: \$KIT githooks install)"
done
# the doc readers that only the stem used to reach: install / profile / health / uninstall read them (and the two the audit named)
chk_doc() { # <file> <test>...
  local f="$1" o miss=""; shift; o="$(sel "$f")"
  for t in "$@"; do printf '%s\n' "$o" | grep -qx "$t" || miss="$miss $t"; done
  [ -z "$miss" ] && ok "$f selects its readers" || fail "$f does not select:$miss"
}
chk_doc hooks/hooks.json tests/installer/test_prompt_hook_missing.sh tests/installer/test_agent_health.sh tests/gates/test_guard_secrets.sh tests/installer/test_uninstall.sh
chk_doc AGENTS.md tests/worktree_git/test_worktree.sh
chk_doc rules/core-rules.md tests/gates/test_postfix_gate.sh tests/gates/test_proof_gate.sh tests/gates/test_proof_gate_report_after_push.sh
chk_doc rules/essentials.md tests/installer/test_platform_rules.sh tests/context_memory/test_profile_split.sh
chk_doc profiles/web/profile.json tests/installer/test_install_cli.sh tests/verification/test_matrix_detect.sh tests/worktree_git/test_relink_skills.sh
chk_doc profiles/game/regression_matrix.json tests/installer/test_agent_config.sh tests/installer/test_uninstall.sh
chk_doc templates/regression_matrix.json tests/installer/test_agent_health.sh tests/installer/test_uninstall.sh

[ "$FAILS" -eq 0 ] && echo "✅ test_impact_map: all passed" || { echo "❌ test_impact_map: $FAILS failed"; exit 1; }
