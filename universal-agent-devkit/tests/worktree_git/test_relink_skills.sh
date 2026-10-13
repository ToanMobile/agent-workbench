#!/usr/bin/env bash
# scripts/governance/relink_check.py, skills (2026-10-13, /devkit-audit item 6, health): a skill added to the DevKit after a
# project was installed never got its .agents/skills/<name> link (OfficeReader: agent-health 96/100, "a DevKit command/skill is
# missing: .agents/skills/devkit-audit"). relink_check, run by the post-merge / post-checkout / post-rewrite hooks, re-created
# missing hook and command links only. It now also links every DevKit skill the profile does not exclude, in a project whose
# install has .agents/skills/, and keeps the new link out of git (.git/info/exclude) unless an ignore rule already covers it.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en
unset DEVKIT_RELINK
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
P="$TMP/p"; mkdir -p "$P" && cd "$P" && git init -q -b main . && git config user.email t@t && git config user.name t \
  && git config commit.gpgsign false
echo x > a && git add a && git commit -qm init
bash "$DEVKIT_DIR/bin/install.sh" -t "$P" -a claude -p backend -y >/dev/null 2>&1
[ -L .agents/skills/devkit-audit ] || { fail "install did not link the devkit-audit skill (fixture)"; exit 1; }
before="$(git status --porcelain)"

# a skill the DevKit gained after this install: its link is not there
rm -f .agents/skills/devkit-audit
sed -i.bak '/devkit-audit/d' .git/info/exclude && rm -f .git/info/exclude.bak
python3 "$DEVKIT_DIR/scripts/governance/relink_check.py" "$P" --quiet
[ -L .agents/skills/devkit-audit ] && [ -f .agents/skills/devkit-audit/SKILL.md ] && ok "relink links the missing devkit-audit skill" \
  || fail "relink did not link the missing devkit-audit skill"
[ "$(git status --porcelain)" = "$before" ] && ok "the new link is kept out of git (status unchanged)" \
  || fail "the new link shows in git status: $(git status --porcelain | head -3 | tr '\n' ' ')"
# a skill the profile excludes is not linked
[ ! -e .agents/skills/qa-visual ] && ok "a skill the backend profile excludes (qa-visual) stays unlinked" || fail "excluded skill qa-visual was linked"
# a second run changes nothing and writes no second exclude line
python3 "$DEVKIT_DIR/scripts/governance/relink_check.py" "$P" --quiet
n="$(grep -c 'skills/devkit-audit' .git/info/exclude)"
[ "$n" -le 1 ] && ok "a second run adds no duplicate exclude line ($n)" || fail "exclude has $n devkit-audit lines"
# a project whose install has no .agents/skills/ gets none
rm -rf .agents/skills
python3 "$DEVKIT_DIR/scripts/governance/relink_check.py" "$P" --quiet
[ ! -e .agents/skills ] && ok "no .agents/skills/ in the install: relink creates none" || fail "relink created .agents/skills/"

[ "$FAILS" -eq 0 ] && echo "✅ test_relink_skills: all passed" || { echo "❌ test_relink_skills: $FAILS failed"; exit 1; }
