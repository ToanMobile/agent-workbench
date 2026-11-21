#!/usr/bin/env bash
# Profile filter of DevKit slash commands (owner 2026-11-21): a hand-written command that names a skill in its
# frontmatter (`skill: <name>`) follows that skill's profile filter at install and in health; backend never gets
# unity-test, taste-mobile-app or ui-ux-pro-max; create-task and createTask resolve to one skill (one listing row).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u

SRC_DEVKIT="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cmd-profile-filter.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

DK="$TMP/dk"
mkdir -p "$DK"
(cd "$SRC_DEVKIT" && tar --exclude=./node_modules --exclude=./.git -cf - .) | (cd "$DK" && tar -xf -)
notty() { python3 -c 'import os,subprocess,sys; sys.exit(subprocess.call(sys.argv[1:], stdin=subprocess.DEVNULL, preexec_fn=os.setsid))' "$@"; }

# 1. create-task and createTask are links to the one create-task skill
for c in create-task createTask; do
  t="$(cd "$DK/commands" && python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$c.md")"
  [ -L "$DK/commands/$c.md" ] && [ "$t" = "$DK/skills/create-task/SKILL.md" ] \
    && ok "1 commands/$c.md -> skills/create-task/SKILL.md" || fail "1 commands/$c.md is not a link to the create-task skill (got $t)"
done

# 2. unit: the command filter maps a hand-written command through its frontmatter skill
. "$DK/scripts/git/backup_conflict.sh"
DEVKIT_SKILLS_ALLOWED="$(python3 "$DK/scripts/governance/profile_skills.py" backend | tr '\n' ' ')"
devkit_command_allowed "$DK/commands/unity-test.md" && fail "2 backend allows commands/unity-test.md" || ok "2 backend filters commands/unity-test.md"
devkit_command_allowed "$DK/commands/gen-prompt.md" && ok "2 backend keeps commands/gen-prompt.md (no skill: line)" || fail "2 backend dropped gen-prompt.md"
DEVKIT_SKILLS_ALLOWED="$(python3 "$DK/scripts/governance/profile_skills.py" game | tr '\n' ' ')"
devkit_command_allowed "$DK/commands/unity-test.md" && ok "2 game allows commands/unity-test.md" || fail "2 game filters commands/unity-test.md"
unset DEVKIT_SKILLS_ALLOWED

# 3. a real install: backend lacks the three commands and health does not ask for them; game keeps unity-test
for prof in backend game; do
  P="$TMP/p_$prof"; mkdir -p "$P"; git -C "$P" init -q
  notty bash "$DK/bin/agent-kit" init "$P" -a claude -p "$prof" -y >"$TMP/init_$prof.out" 2>&1 || { fail "3 init -p $prof rc!=0"; tail -5 "$TMP/init_$prof.out"; continue; }
  if [ "$prof" = backend ]; then
    left=""
    for c in unity-test taste-mobile-app ui-ux-pro-max; do [ -e "$P/.claude/commands/$c.md" ] && left="$left $c"; done
    [ -z "$left" ] && ok "3 backend install has no unity-test/taste-mobile-app/ui-ux-pro-max command" || fail "3 backend install still has:$left"
    [ -e "$P/.claude/commands/createTask.md" ] && [ -e "$P/.claude/commands/create-task.md" ] \
      && ok "3 backend keeps /createTask and /create-task" || fail "3 backend lost /createTask or /create-task"
    python3 "$DK/bin/agent-health.py" "$P" >"$TMP/health.out" 2>&1
    grep -q "unity-test.md" "$TMP/health.out" && fail "3 health on backend asks for unity-test.md" || ok "3 health on backend does not ask for unity-test.md"
    # 4. SessionStart / git-hook relink must not put the filtered command back
    python3 "$DK/scripts/governance/relink_check.py" "$P" --quiet --links-only >/dev/null 2>&1
    [ -e "$P/.claude/commands/unity-test.md" ] && fail "4 relink_check re-linked unity-test.md on backend" || ok "4 relink_check leaves unity-test.md out on backend"
  else
    [ -e "$P/.claude/commands/unity-test.md" ] && ok "3 game install keeps /unity-test" || fail "3 game install lost /unity-test"
  fi
done

[ "$FAILS" = 0 ] && { echo "PASS test_command_profile_filter"; exit 0; } || { echo "FAIL test_command_profile_filter ($FAILS)"; exit 1; }
