#!/usr/bin/env bash
# Regression test: the project tier (.agents/local). DevKit is the core: a project item
# sharing a DevKit name moves to .agents/local/<kind>/, the DevKit item is installed,
# project items with a free name are linked in, and re-installing — also after the
# DevKit itself was updated — never rewrites the project tier.
set -u

SRC_DEVKIT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en
unset CLAUDE_PROJECT_DIR TARGET_DIR

# A private DevKit copy, so the test can "update" it like `git pull` would.
DK="$TMP/dk"
mkdir -p "$DK"
(cd "$SRC_DEVKIT" && tar --exclude=./node_modules --exclude=./.git -cf - .) | (cd "$DK" && tar -xf -)
KIT="$DK/bin/agent-kit"

FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
install() { bash "$DK/bin/install.sh" -t "$1" -a all -p none -y "${@:2}" > "$TMP/out" 2>&1 || { fail "install exited non-zero"; cat "$TMP/out"; }; }
tree_sum() { (cd "$1" && find . -type f -o -type l | LC_ALL=C sort | while IFS= read -r f; do
  if [ -L "$f" ]; then echo "L $f $(readlink "$f")"; else echo "F $f $(cksum < "$f")"; fi; done) | cksum; }
count_old() { find "$1" -maxdepth 4 \( -name "*_old" -o -name "*_old.*" -o -name "*_old_*" \) | wc -l | xargs; }

# ------------------------------------------------------------------ symlink mode
P="$TMP/p"; mkdir -p "$P/.claude/commands" "$P/.agents/skills/qc" "$P/.agents/local/skills/my-skill"
(cd "$P" && git init -q)
echo "my fix" > "$P/.claude/commands/fix.md"             # same name as a DevKit command
echo "mine" > "$P/.claude/commands/mine.md"              # the project's own name
echo "my qc" > "$P/.agents/skills/qc/SKILL.md"           # same name as a DevKit skill
printf -- '---\nname: my-skill\ndescription: team skill\n---\n' > "$P/.agents/local/skills/my-skill/SKILL.md"

install "$P"
[ -L "$P/.claude/commands/fix.md" ] && [ "$(cat "$P/.agents/local/commands/fix.md")" = "my fix" ] \
  && ok "same-name command: DevKit installed, the project's moved to .agents/local/commands/" || fail "fix.md not moved to the project tier"
[ "$(cat "$P/.agents/local/skills/qc/SKILL.md" 2>/dev/null)" = "my qc" ] && [ -L "$P/.agents/skills/qc" ] \
  && ok "same-name skill: DevKit installed, the project's moved to .agents/local/skills/" || fail "qc not moved to the project tier"
[ -f "$P/.claude/commands/mine.md" ] && [ ! -L "$P/.claude/commands/mine.md" ] \
  && ok "a project command with its own name stays where it is" || fail "mine.md was touched"
[ "$(readlink "$P/.agents/skills/my-skill")" = "../../.agents/local/skills/my-skill" ] && [ -f "$P/.agents/skills/my-skill/SKILL.md" ] \
  && ok "project-tier skill with a free name is linked in (relative link)" || fail "my-skill not linked: $(readlink "$P/.agents/skills/my-skill")"
[ "$(count_old "$P")" = 0 ] && ok "no *_old created" || fail "*_old created: $(find "$P" -maxdepth 4 -name '*_old*')"
[ ! -e "$P/.claude/commands_old" ] && [ ! -e "$P/.agents/skills_old" ] && ok "no commands_old/ or skills_old/" || fail "old-style backup dirs created"
(cd "$P" && ! git check-ignore -q .agents/local/commands/fix.md) && ok ".agents/local is not git-ignored (meant to be committed)" \
  || fail ".agents/local is ignored by .gitignore"

before="$(tree_sum "$P/.agents/local")"
install "$P"
[ "$(tree_sum "$P/.agents/local")" = "$before" ] && ok "re-install leaves the project tier byte-identical" || fail "re-install changed .agents/local"

# The DevKit is updated (git pull): a skill changes, and a new DevKit skill takes the
# name of a project-tier skill that was active until now.
echo "<!-- devkit v2 -->" >> "$DK/skills/fixbugs/SKILL.md"
mkdir -p "$DK/skills/my-skill" && printf -- '---\nname: my-skill\ndescription: devkit v2 skill\n---\n' > "$DK/skills/my-skill/SKILL.md"
install "$P"
grep -q "devkit v2" "$P/.agents/skills/fixbugs/SKILL.md" && ok "after a DevKit update, re-install delivers the new version" || fail "update not delivered"
[ -L "$P/.agents/skills/my-skill" ] && grep -q "devkit v2 skill" "$P/.agents/skills/my-skill/SKILL.md" \
  && ok "a new DevKit skill wins over the project-tier skill of that name" || fail "DevKit did not take over my-skill"
grep -q "team skill" "$P/.agents/local/skills/my-skill/SKILL.md" && [ "$(cat "$P/.agents/local/commands/fix.md")" = "my fix" ] \
  && ok "the project tier is untouched by the update" || fail "project tier changed by the update"
bash "$KIT" list-old "$P" | grep -q "skills/my-skill: shadowed" && ok "list-old reports the shadowed project skill" \
  || fail "list-old does not report my-skill as shadowed"
rm -rf "$DK/skills/my-skill"

# Uninstall + restore-old give the project back; the team's own tier item stays.
bash "$KIT" uninstall "$P" --apply >/dev/null 2>&1
bash "$KIT" restore-old "$P" --apply >/dev/null 2>&1
[ "$(cat "$P/.claude/commands/fix.md")" = "my fix" ] && [ "$(cat "$P/.agents/skills/qc/SKILL.md")" = "my qc" ] \
  && ok "uninstall + restore-old put the moved items back" || fail "restore from the project tier failed"
[ -f "$P/.agents/local/skills/my-skill/SKILL.md" ] && [ ! -e "$P/.agents/local/commands" ] \
  && [ -z "$(find "$P/.agents/local" -name .devkit_backups.log)" ] \
  && ok "the team's own item stays, consumed backups and ledgers are cleaned" || fail "project tier not cleaned: $(find "$P/.agents/local")"

# A project whose tier is only DevKit backups ends up exactly as before.
R="$TMP/r"; mkdir -p "$R/.claude/commands"; (cd "$R" && git init -q)
echo "my fix" > "$R/.claude/commands/fix.md"
install "$R"
[ -f "$R/.agents/local/README.md" ] && ok "a new project tier gets a README" || fail "no README in .agents/local"
bash "$KIT" uninstall "$R" --apply >/dev/null 2>&1
bash "$KIT" restore-old "$R" --apply >/dev/null 2>&1
[ "$(cat "$R/.claude/commands/fix.md")" = "my fix" ] && [ ! -e "$R/.agents" ] \
  && ok "round trip leaves no .agents/ behind" || fail "leftovers: $(find "$R/.agents" 2>/dev/null)"

# A tier created by an older DevKit carries the older README text: still recognised as
# the DevKit's, so the round trip still leaves nothing behind.
R1="$TMP/r1"; mkdir -p "$R1/.claude/commands"; (cd "$R1" && git init -q)
echo "my fix" > "$R1/.claude/commands/fix.md"
install "$R1"
(source "$DK/scripts/backup_conflict.sh" && _devkit_local_readme v1) > "$R1/.agents/local/README.md"
grep -q "are reference only, never linked\.$" "$R1/.agents/local/README.md" || fail "v1 README fixture is not the old text"
bash "$KIT" uninstall "$R1" --apply >/dev/null 2>&1
bash "$KIT" restore-old "$R1" --apply >/dev/null 2>&1
[ ! -e "$R1/.agents" ] && ok "an untouched README from an older DevKit is cleaned too" \
  || fail "old README left behind: $(find "$R1/.agents" 2>/dev/null)"

# The project's own AGENTS.md (kept, DevKit block injected) lists the project-tier rules too.
A="$TMP/a"; mkdir -p "$A/rules"; (cd "$A" && git init -q)
echo "TEAM RULE" > "$A/rules/team.md"
echo "# Team agents" > "$A/AGENTS.md"
install "$A"
grep -qx -- "- @.agents/local/rules/team.md" "$A/AGENTS.md" && grep -q "# Team agents" "$A/AGENTS.md" \
  && ok "the project's own AGENTS.md gets the same imports in its DevKit block" || { fail "AGENTS.md block has no project rules"; cat "$A/AGENTS.md"; }

# ------------------------------------------------------------------ root rules/ skills/ commands/
# Agent material moves to the project tier; a source-code dir stays and gets the DevKit
# items placed inside — either way every DevKit path (rules/core-rules.md, …) resolves.
S="$TMP/s"; mkdir -p "$S/rules" "$S/skills/billing" "$S/commands"; (cd "$S" && git init -q)
echo "TEAM RULE" > "$S/rules/team.md"
echo "my core rules" > "$S/rules/core-rules.md"
echo "old team rule" > "$S/rules/team_20260101_101010.md"
printf -- '---\nname: billing\ndescription: b\n---\n' > "$S/skills/billing/SKILL.md"
echo "module.exports = 1" > "$S/commands/build.js"
echo "my fix" > "$S/commands/fix.md"
snap() { (cd "$1" && find rules skills commands -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
  [ -f "$f" ] && echo "$f $(cksum < "$f")" || echo "$f"; done); }
orig="$(snap "$S")"
install "$S"
[ -L "$S/rules" ] && grep -q "Core Engineering Rules" "$S/rules/core-rules.md" \
  && ok "root rules/ of agent material: DevKit rules installed (@rules/core-rules.md resolves)" || fail "DevKit rules/ not installed"
[ "$(cat "$S/.agents/local/rules/team.md")" = "TEAM RULE" ] && [ "$(cat "$S/.agents/local/rules/core-rules.md")" = "my core rules" ] \
  && ok "the project's rules are kept in .agents/local/rules/" || fail "project rules not kept"
# The moved rules must still reach the agents: listed as @-imports in the DevKit block.
grep -qx -- "- @.agents/local/rules/team.md" "$S/CLAUDE.md" && grep -qx -- "- @.agents/local/rules/core-rules.md" "$S/CLAUDE.md" \
  && ok "CLAUDE.md imports the project-tier rules" || { fail "CLAUDE.md does not import .agents/local/rules"; cat "$S/CLAUDE.md"; }
! grep -q "team_20260101_101010" "$S/CLAUDE.md" && ok "dated copies are not imported" || fail "a dated copy was imported"
[ "$(grep -c '@.agents/local/rules/' "$S/CLAUDE.md")" = 2 ] && ok "one import per rule file" || fail "wrong import count: $(grep -c '@.agents/local/rules/' "$S/CLAUDE.md")"
[ -L "$S/skills" ] && [ "$(readlink "$S/.agents/skills/billing")" = "../../.agents/local/skills/billing" ] \
  && ok "root skills/: DevKit installed, the project's skill moved and linked back" || fail "skills/ not handled"
[ -d "$S/commands" ] && [ ! -L "$S/commands" ] && [ "$(cat "$S/commands/build.js")" = "module.exports = 1" ] \
  && ok "root commands/ with source code stays in place" || fail "source-code commands/ was moved"
[ -L "$S/commands/fix.md" ] && [ -e "$S/commands/audit-gate.md" ] && [ "$(cat "$S/.agents/local/commands/fix.md")" = "my fix" ] \
  && ok "DevKit commands placed inside it; the same-named project file moved to the tier" || fail "commands/ not merged"
before="$(tree_sum "$S/.agents/local")"
install "$S"
[ "$(tree_sum "$S/.agents/local")" = "$before" ] && [ "$(count_old "$S")" = 0 ] \
  && ok "re-install: project tier unchanged, no *_old" || fail "re-install changed the tier or created *_old"
[ "$(grep -c '@.agents/local/rules/' "$S/CLAUDE.md")" = 2 ] && ok "re-install does not duplicate the imports" \
  || fail "imports duplicated on re-install: $(grep -c '@.agents/local/rules/' "$S/CLAUDE.md")"
bash "$KIT" uninstall "$S" --apply >/dev/null 2>&1
bash "$KIT" restore-old "$S" --apply >/dev/null 2>&1
[ "$(snap "$S")" = "$orig" ] && ok "uninstall + restore-old give rules/ skills/ commands/ back exactly" \
  || { fail "round trip differs"; diff <(echo "$orig") <(snap "$S"); }
[ ! -e "$S/.agents" ] && ok "no .agents/ left behind (dangling tier links removed)" || fail "leftovers: $(find "$S/.agents")"

# ------------------------------------------------------------------ copy mode
Q="$TMP/q"; mkdir -p "$Q"; (cd "$Q" && git init -q)
install "$Q" -m copy
echo "TEAM EDIT" >> "$Q/.agents/skills/fixbugs/SKILL.md"
echo "<!-- devkit v3 -->" >> "$DK/skills/fixbugs/SKILL.md"
install "$Q" -m copy
grep -q "devkit v3" "$Q/.agents/skills/fixbugs/SKILL.md" && ! grep -q "TEAM EDIT" "$Q/.agents/skills/fixbugs/SKILL.md" \
  && ok "copy mode: the edited DevKit skill is refreshed to the updated DevKit" || fail "copy mode: skill not refreshed"
grep -q "TEAM EDIT" "$Q/.agents/local/skills/fixbugs/SKILL.md" 2>/dev/null \
  && ok "copy mode: the team's edit is kept in .agents/local/skills/fixbugs/" || fail "copy mode: team edit lost"
[ "$(find "$Q/.agents/local/skills/fixbugs" -type f | wc -l | xargs)" = 1 ] \
  && ok "copy mode: only the edited file is kept" || fail "copy mode: kept more than the edit"
[ ! -L "$Q/.agents/skills/fixbugs" ] && ok "copy mode: shadowed edit is not linked over the DevKit skill" || fail "edit linked over DevKit"

echo "SECOND EDIT" >> "$Q/.agents/skills/fixbugs/SKILL.md"
install "$Q" -m copy
grep -q "TEAM EDIT" "$Q/.agents/local/skills/fixbugs/SKILL.md" && ls -d "$Q/.agents/local/skills/fixbugs_"* >/dev/null 2>&1 \
  && grep -qs "SECOND EDIT" "$Q/.agents/local/skills/fixbugs_"*/SKILL.md \
  && ok "a later edit gets a dated folder; the earlier one is never overwritten" || fail "later edit clobbered or lost"
ls "$Q/.agents/skills" | grep -q "fixbugs_" && fail "dated copy linked as a skill" || ok "dated copies are never linked as skills"
[ "$(count_old "$Q")" = 0 ] && ok "copy mode: no *_old created" || fail "copy mode created *_old"

# ------------------------------------------------------------------ relative links keep their target
# .claude/commands/fix.md -> ../../.agents/skills/my-fix/SKILL.md moves one level deeper
# (.agents/local/commands/); its relative target must be rewritten, not left dangling.
R="$TMP/rlinks"; mkdir -p "$R/.claude/commands" "$R/.agents/skills/my-fix" "$R/rules/nested"
(cd "$R" && git init -q)
echo "# my fix skill" > "$R/.agents/skills/my-fix/SKILL.md"
ln -s ../../.agents/skills/my-fix/SKILL.md "$R/.claude/commands/fix.md"
echo "team rule" > "$R/rules/nested/team.md"; ln -s nested/team.md "$R/rules/team-link.md"   # link inside a moved dir
echo "outside" > "$R/NOTES.md"; ln -s ../NOTES.md "$R/rules/notes.md"                      # link out of a moved dir
install "$R"
[ "$(cat "$R/.agents/local/commands/fix.md" 2>/dev/null)" = "# my fix skill" ] \
  && ok "moved relative link (.claude/commands → .agents/local/commands) still resolves" || fail "moved link dangles: $(readlink "$R/.agents/local/commands/fix.md")"
[ "$(cat "$R/.agents/local/rules/team-link.md" 2>/dev/null)" = "team rule" ] && [ "$(cat "$R/.agents/local/rules/notes.md" 2>/dev/null)" = "outside" ] \
  && ok "links in a moved folder: inside ones kept, outside ones re-pointed" || fail "links in moved rules/ broken"

out="$(bash "$KIT" list-old "$R" 2>&1)"
printf '%s' "$out" | grep -q "rules/team-link.md: active (@-imported" && ok "list-old: an imported project rule is shown active, not 'reference'" \
  || fail "list-old rules label: $(printf '%s' "$out" | grep 'rules/' | head -2)"

# ------------------------------------------------------------------ project-tier skills reach Claude Code
mkdir -p "$R/.agents/local/skills/story-pipeline" "$R/.agents/local/skills/qc"
printf -- '---\nname: story-pipeline\ndescription: team skill\n---\n' > "$R/.agents/local/skills/story-pipeline/SKILL.md"
printf -- '---\nname: qc\ndescription: our qc\n---\n' > "$R/.agents/local/skills/qc/SKILL.md"
install "$R"
grep -q "team skill" "$R/.claude/commands/story-pipeline.md" 2>/dev/null \
  && ok "project-tier skill gets a /story-pipeline command linked to its SKILL.md" || fail "local skill not reachable as a command"
grep -q "our qc" "$R/.claude/commands/qc.md" 2>/dev/null && fail "a local skill replaced the DevKit /qc command" || ok "a DevKit command of the same name is kept"

# ------------------------------------------------------------------ only hook scripts in .claude/hooks
[ ! -e "$R/.claude/hooks/tests" ] && [ ! -e "$R/.claude/hooks/hooks.json" ] && [ -L "$R/.claude/hooks/precode_gate.sh" ] \
  && ok ".claude/hooks gets the hook scripts, not hooks/tests or hooks.json" || fail "non-hook entries linked into .claude/hooks"
DKP="$(cd "$DK" && pwd -P)"   # the installer links by the DevKit's physical path
ln -s "$DKP/hooks/tests" "$R/.claude/hooks/tests"; ln -s "$DKP/hooks/hooks.json" "$R/.claude/hooks/hooks.json"
echo "mine" > "$R/.claude/hooks/my_hook.sh"
install "$R"
[ ! -e "$R/.claude/hooks/tests" ] && [ ! -e "$R/.claude/hooks/hooks.json" ] && [ "$(cat "$R/.claude/hooks/my_hook.sh")" = "mine" ] \
  && ok "re-install removes the old tests/hooks.json links, keeps the project's own hook" || fail "stale hook links kept or own hook touched"

if [ "$FAILS" -ne 0 ]; then
  echo "local tier: $FAILS FAILED"; exit 1
fi
echo "local tier: all checks passed"
