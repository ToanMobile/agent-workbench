#!/usr/bin/env bash
# Regression test: a DevKit command the kit removed leaves a dangling `.claude/commands/<name>.md` link in every installed repo
# (1.2.0 dropped review/qa/test/bugs/crashlytics: OfficeReader, Goods, Humans, Idle health 90-93 with 5 dangling links, 26/10).
# Only `agent-kit init` removed them, and auto mode refuses init in a main checkout with local changes. relink_check now prunes
# a link that is dangling AND points into this DevKit (absolute or through the .agents/devkit alias); anything else — a dangling
# link pointing elsewhere, a regular file, a live link — stays. SessionStart runs it, so a session heals the repo by itself.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en DEVKIT_INCIDENT=0
unset DEVKIT_RELINK
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
KIT="$(cd "$DEVKIT_DIR" && pwd -P)"
P="$TMP/p"; mkdir -p "$P" && cd "$P" && git init -q -b main . && git config user.email t@t && git config user.name t
echo x > a && git add a && git commit -qm init
bash "$DEVKIT_DIR/bin/install.sh" -t "$P" -a claude -p android -y >/dev/null 2>&1
[ -d "$P/.claude/commands" ] && [ -d "$P/.agents/context" ] || { echo "✖ install did not set up the project"; exit 1; }

plant() {   # the leftovers of 1.2.0 plus things that must stay
  ln -sfn "$KIT/commands/zz-removed-a.md" "$P/.claude/commands/zz-removed-a.md"                 # dangling, absolute into the kit
  ln -sfn "$P/.agents/devkit/commands/zz-removed-b.md" "$P/.claude/commands/zz-removed-b.md"    # dangling, through the alias
  ln -sfn "$TMP/elsewhere/mine.md" "$P/.claude/commands/zz-mine.md"                             # dangling, not the kit's: keep
  printf 'my own command\n' > "$P/.claude/commands/zz-own.md"                                    # regular file: keep
}
check() {   # $1 label
  [ ! -e "$P/.claude/commands/zz-removed-a.md" ] && [ ! -L "$P/.claude/commands/zz-removed-a.md" ] \
    && [ ! -L "$P/.claude/commands/zz-removed-b.md" ] \
    && ok "$1: the 2 dangling links into the kit are pruned" \
    || fail "$1: dangling kit links left: $(ls -l "$P/.claude/commands" | grep zz-removed | tr '\n' ' ')"
  [ -L "$P/.claude/commands/zz-mine.md" ] && [ -f "$P/.claude/commands/zz-own.md" ] \
    && ok "$1: a dangling link outside the kit and a regular file stay" \
    || fail "$1: removed something that is not the kit's: $(ls "$P/.claude/commands" | grep zz | tr '\n' ' ')"
  [ -L "$P/.claude/commands/qc.md" ] && [ -e "$P/.claude/commands/qc.md" ] \
    && ok "$1: live kit links stay" || fail "$1: a live kit link was removed"
}

plant
python3 "$DEVKIT_DIR/scripts/governance/relink_check.py" "$P" --quiet
check "relink_check"
grep -q "pruned 2" "$P/.claude/audit-gate/relink.log" 2>/dev/null \
  && ok "relink_check logs the pruned links" || fail "no prune line in relink.log: $(tail -2 "$P/.claude/audit-gate/relink.log" 2>/dev/null)"
[ -z "$(git -C "$P" status --porcelain --untracked-files=no)" ] && ok "the prune changes no tracked file" \
  || fail "tracked changes: $(git -C "$P" status --porcelain --untracked-files=no | head -3)"

# SessionStart heals a repo with no git operation and no `agent-kit init`.
rm -f "$P/.claude/commands/zz-mine.md" "$P/.claude/commands/zz-own.md"
plant
printf '{"session_id":"relink-prune-test","source":"startup"}' | CLAUDE_PROJECT_DIR="$P" bash "$DEVKIT_DIR/hooks/session_context.sh" >/dev/null 2>&1
check "SessionStart"

# A linked worktree is left alone, as for the restore (its links are the main checkout's business).
W="$TMP/w"; git -C "$P" worktree add -q --detach "$W" 2>/dev/null
mkdir -p "$W/.claude/commands" "$W/.agents/context"; cp "$P/.agents/active-profile.json" "$W/.agents/" 2>/dev/null
ln -sfn "$KIT/commands/zz-removed-w.md" "$W/.claude/commands/zz-removed-w.md"
python3 "$DEVKIT_DIR/scripts/governance/relink_check.py" "$W" --quiet
[ -L "$W/.claude/commands/zz-removed-w.md" ] && ok "linked worktree: nothing pruned" || fail "pruned in a linked worktree"

# A link directory that is itself a symlink into the kit (`.claude/commands -> <kit>/commands`) lists the KIT's own files:
# its dangling, git-tracked links must not be pruned (OCR review 26/10: the kit lost commands/old.md and .agents/skills/old).
for variant in commands skills; do
  K="$TMP/fk-$variant/kit"; mkdir -p "$K/profiles" "$K/commands" "$K/skills/keep" "$K/.agents/skills" "$K/scripts/governance" "$K/rules"
  echo r > "$K/rules/essentials.md"; echo k > "$K/skills/keep/SKILL.md"
  cp "$DEVKIT_DIR/scripts/governance/relink_check.py" "$K/scripts/governance/relink_check.py"; : > "$K/scripts/governance/context_sync.py"
  ln -s ../skills/old/SKILL.md "$K/commands/old.md"; ln -s ../../skills/old "$K/.agents/skills/old"
  git -C "$K" init -q -b main && git -C "$K" add -A && git -C "$K" -c user.email=t@t -c user.name=t commit -qm kit
  FP="$TMP/fk-$variant/p"; mkdir -p "$FP/.claude" "$FP/.agents/context"; git -C "$FP" init -q -b main
  echo '{}' > "$FP/.agents/active-profile.json"; ln -s "$K" "$FP/.agents/devkit"
  if [ "$variant" = commands ]; then ln -s "$K/commands" "$FP/.claude/commands"; mkdir -p "$FP/.agents/skills"
  else mkdir -p "$FP/.claude/commands"; ln -s "$K/.agents/skills" "$FP/.agents/skills"; fi
  python3 "$K/scripts/governance/relink_check.py" "$FP" --quiet --links-only
  [ -z "$(git -C "$K" status --porcelain)" ] && ok "$variant dir is a symlink into the kit: the kit's tracked links stay" \
    || fail "$variant dir symlinked into the kit: kit changed: $(git -C "$K" status --porcelain | tr '\n' ' ')"
done
# A project inside the kit (a self-install) prunes nothing: every kit link would look like a DevKit link.
K="$TMP/fk-self/kit"; mkdir -p "$K/profiles" "$K/scripts/governance" "$K/rules" "$K/.claude/commands" "$K/.agents/context"
echo r > "$K/rules/essentials.md"; cp "$DEVKIT_DIR/scripts/governance/relink_check.py" "$K/scripts/governance/"; : > "$K/scripts/governance/context_sync.py"
echo '{}' > "$K/.agents/active-profile.json"; ln -s ../../skills/gone/SKILL.md "$K/.claude/commands/gone.md"
git -C "$K" init -q -b main && git -C "$K" add -A && git -C "$K" -c user.email=t@t -c user.name=t commit -qm kit
python3 "$K/scripts/governance/relink_check.py" "$K" --quiet --links-only
[ -z "$(git -C "$K" status --porcelain)" ] && ok "project inside the kit (self-install): nothing pruned" \
  || fail "self-install: kit changed: $(git -C "$K" status --porcelain | tr '\n' ' ')"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
