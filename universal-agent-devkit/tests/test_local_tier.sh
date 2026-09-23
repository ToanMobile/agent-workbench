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

if [ "$FAILS" -ne 0 ]; then
  echo "local tier: $FAILS FAILED"; exit 1
fi
echo "local tier: all checks passed"
