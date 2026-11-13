#!/usr/bin/env bash
# Regression test (#1144): an agent the kit removed leaves a dangling `.claude/agents/<name>.md` link in every installed repo
# (#1057 dropped five agents: GeelyEx2 `agent-kit health` FAIL "Broken links", 13/11), and relink_check only pruned
# `.claude/commands`, `.agents/skills` and `.claude/hooks`. Same rule as for those: a link that dangles AND points into this
# DevKit (absolute or through the .agents/devkit alias) goes; a dangling link pointing elsewhere, a regular file, a live link
# and a live link to a directory (`councils`) stay.
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

mkdir -p "$P/.claude/agents" "$TMP/elsewhere"
LIVE_AGENT="$(ls "$KIT/agents"/*.md 2>/dev/null | head -1)"
[ -n "$LIVE_AGENT" ] || { echo "✖ the kit has no agent to link"; exit 1; }
ln -sfn "$LIVE_AGENT" "$P/.claude/agents/zz-live.md"                                       # live kit link: keep
ln -sfn "$KIT/agents/zz-removed-a.md" "$P/.claude/agents/zz-removed-a.md"                  # dangling, absolute into the kit
ln -sfn "$P/.agents/devkit/agents/zz-removed-b.md" "$P/.claude/agents/zz-removed-b.md"     # dangling, through the alias
ln -sfn "$TMP/elsewhere/mine.md" "$P/.claude/agents/zz-mine.md"                            # dangling, not the kit's: keep
printf 'my own agent\n' > "$P/.claude/agents/zz-own.md"                                     # regular file: keep

python3 "$DEVKIT_DIR/scripts/governance/relink_check.py" "$P" --quiet

[ ! -L "$P/.claude/agents/zz-removed-a.md" ] && [ ! -L "$P/.claude/agents/zz-removed-b.md" ] \
  && ok "the 2 dangling agent links into the kit are pruned" \
  || fail "dangling kit agent links left: $(ls -l "$P/.claude/agents" | grep zz-removed | tr '\n' ' ')"
[ -L "$P/.claude/agents/zz-mine.md" ] && [ -f "$P/.claude/agents/zz-own.md" ] \
  && ok "a dangling link outside the kit and a regular file stay" \
  || fail "removed something that is not the kit's: $(ls "$P/.claude/agents" | tr '\n' ' ')"
[ -L "$P/.claude/agents/zz-live.md" ] && [ -e "$P/.claude/agents/zz-live.md" ] \
  && ok "a live kit agent link stays" || fail "a live kit agent link was removed"
grep -q "pruned 2" "$P/.claude/audit-gate/relink.log" 2>/dev/null \
  && ok "relink_check logs the pruned links" || fail "no prune line in relink.log: $(tail -2 "$P/.claude/audit-gate/relink.log" 2>/dev/null)"

# A linked worktree is left alone (its links are the main checkout's business), as for the other link directories.
W="$TMP/w"; git -C "$P" worktree add -q --detach "$W" 2>/dev/null
mkdir -p "$W/.claude/agents" "$W/.agents/context"; cp "$P/.agents/active-profile.json" "$W/.agents/" 2>/dev/null
ln -sfn "$KIT/agents/zz-removed-w.md" "$W/.claude/agents/zz-removed-w.md"
python3 "$DEVKIT_DIR/scripts/governance/relink_check.py" "$W" --quiet
[ -L "$W/.claude/agents/zz-removed-w.md" ] && ok "linked worktree: nothing pruned" || fail "pruned in a linked worktree"

[ "$FAILS" -eq 0 ]
