#!/usr/bin/env bash
# Regression test: DevKit links removed by a git operation are restored by the
# post-merge / post-checkout hooks (the 2026-09-24 incident: a branch untracked the
# tracked absolute links, the fast-forward deleted them, every guard exited 127).
# The repair only re-creates links: no installer run, no tracked file or profile change,
# and nothing at all in a linked worktree, on a file checkout or in an un-migrated tree.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en
unset DEVKIT_RELINK
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
P="$TMP/p"; mkdir -p "$P" && cd "$P" && git init -q -b main . && git config user.email t@t && git config user.name t
echo x > a && git add a && git commit -qm init
bash "$DEVKIT_DIR/bin/install.sh" -t "$P" -a claude -p android -y >/dev/null 2>&1
H="$(git rev-parse --path-format=absolute --git-path hooks)"
[ -x "$H/post-merge" ] && [ -x "$H/post-checkout" ] && [ -x "$H/post-rewrite" ] && grep -q relink_check "$H/post-merge" \
  && ok "githooks install adds post-merge / post-checkout / post-rewrite link repair" || fail "relink hooks missing: $(ls "$H")"

git add -f .claude/hooks/precode_gate.sh .claude/commands/qc.md && git commit -qm "tracked links (the old mistake)"
git switch -q -c untrack && git rm -q --cached .claude/hooks/precode_gate.sh .claude/commands/qc.md && git commit -qm untrack
git switch -q main 2>/dev/null
rm -f "$P/.claude/audit-gate/relink.log"
prof_before="$(cksum < .agents/active-profile.json)"
git merge -q --ff-only untrack 2>/dev/null
[ -L .claude/hooks/precode_gate.sh ] && [ -L .claude/commands/qc.md ] && grep -q "restored 2/2" .claude/audit-gate/relink.log \
  && ok "fast-forward that deleted 2 DevKit links: post-merge restored them" || fail "links not restored: $(ls .claude/hooks | head -3); log=$(cat .claude/audit-gate/relink.log 2>/dev/null)"
[ -z "$(git status --porcelain --untracked-files=no)" ] && ok "the repair changes no tracked file" || fail "tracked changes: $(git status --porcelain --untracked-files=no | head -3)"
[ "$(cksum < .agents/active-profile.json)" = "$prof_before" ] && [ -L .agents/active-profile ] && head -1 .agents/active-profile/RULES.md | grep -qi android \
  && ok "the profile is unchanged (no installer run)" || fail "profile changed by the repair"

# A file checkout (post-checkout flag 0) is not a branch switch: nothing is repaired.
rm -f .claude/hooks/precode_gate.sh
git checkout -q -- a
[ ! -e .claude/hooks/precode_gate.sh ] && ok "file checkout (flag 0): skipped" || fail "file checkout re-created links"
bash "$H/post-checkout" "$(git rev-parse HEAD)" "$(git rev-parse HEAD)" 1 >/dev/null 2>&1
[ -L .claude/hooks/precode_gate.sh ] && ok "branch checkout (flag 1): link restored" || fail "branch checkout did not restore"

# An un-migrated tree (no .agents/context/: an older commit / pre-1.3 install) is left alone.
mv .agents/context "$TMP/ctx"; rm -f .claude/hooks/precode_gate.sh
bash "$H/post-checkout" "$(git rev-parse HEAD)" "$(git rev-parse HEAD)" 1 >/dev/null 2>&1
[ ! -e .claude/hooks/precode_gate.sh ] && ok "un-migrated tree (no .agents/context/): skipped" || fail "un-migrated tree was relinked"
mv "$TMP/ctx" .agents/context
bash "$H/post-checkout" "$(git rev-parse HEAD)" "$(git rev-parse HEAD)" 1 >/dev/null 2>&1

# A linked worktree is set up by `agent-kit worktree add`, never by the repair hook.
git worktree add -q "$TMP/wt" untrack 2>/dev/null
mkdir -p "$TMP/wt/.agents/context" "$TMP/wt/.claude" && cp .agents/active-profile.json "$TMP/wt/.agents/" && cp .claude/settings.json "$TMP/wt/.claude/"
(cd "$TMP/wt" && bash "$H/post-checkout" "$(git rev-parse HEAD)" "$(git rev-parse HEAD)" 1 >/dev/null 2>&1)
[ ! -e "$TMP/wt/.claude/hooks/precode_gate.sh" ] && [ ! -e "$TMP/wt/.agents/devkit" ] && ok "linked worktree: skipped" || fail "the hook relinked a worktree"
git worktree remove --force "$TMP/wt" 2>/dev/null

# The .agents/devkit link itself is restored.
rm -f .agents/devkit
bash "$H/post-merge" 0 >/dev/null 2>&1
[ -L .agents/devkit ] && [ -f .agents/devkit/rules/essentials.md ] && ok ".agents/devkit removed: restored" || fail ".agents/devkit not restored"

t0=$(python3 -c 'import time;print(time.time())'); bash "$H/post-checkout" "$(git rev-parse HEAD)" "$(git rev-parse HEAD)" 1 >/dev/null 2>&1; t1=$(python3 -c 'import time;print(time.time())')
python3 -c "import sys; sys.exit(0 if ($t1-$t0) < 1.0 else 1)" && ok "nothing missing: the hook is instant ($(python3 -c "print(round(($t1-$t0)*1000))") ms)" || fail "relink hook slow when nothing is missing"
bash "$DEVKIT_DIR/scripts/githooks.sh" uninstall "$P" >/dev/null 2>&1
[ ! -e "$H/post-merge" ] && ok "githooks uninstall removes the link-repair hooks" || fail "post-merge left after uninstall"
if [ "$FAILS" -ne 0 ]; then echo "relink: $FAILS FAILED"; exit 1; fi
echo "relink: all checks passed"
