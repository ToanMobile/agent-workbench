#!/usr/bin/env bash
# Regression test (#515, from #462) for bin/agent-health.py: on 2026-10-24 a third-party installer wrote THROUGH the symlink
# .claude/hooks/guard-protected-push.py and put an old guard over the kit's own hooks/guard-protected-push.py; another file the kit tracks
# (scripts/testing/capture_3d_proof.py) was deleted. Health stayed green until `agent-kit integrate` broke. Health now compares the files
# the kit tracks with the kit's HEAD: one that differs or is gone is a red line naming the file and the restore command (printed, never run).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
strip() { sed 's/\x1b\[[0-9;]*m//g'; }

# A draft kit: the tracked files of this kit, committed in a repo of their own (HEAD = the clean state).
K="$TMP/kit"; mkdir -p "$K"
(cd "$DEVKIT_DIR" && git ls-files -z . | tar --null -T - -cf -) | tar -xf - -C "$K"
(cd "$K" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm kit)
W="$TMP/proj"; mkdir -p "$W" && (cd "$W" && git init -q && git config user.email t@t && git config user.name t && echo x > a && git add a && git commit -qm i)
bash "$K/bin/install.sh" -t "$W" -a claude -p backend -y --no-githooks >/dev/null 2>&1

health() { python3 "$K/bin/agent-health.py" -t "$W" 2>&1 | strip; }
RED='kit files? .*(differ from|khác HEAD)'   # only the failing line carries it
LINK="$W/.claude/hooks/guard-protected-push.py"

[ -L "$LINK" ] || fail "setup: $LINK is not a symlink into the draft kit"

out="$(health)"
echo "$out" | grep -qE "$RED" && fail "a clean kit was reported: $(echo "$out" | grep -E "$RED")" || ok "clean kit: nothing reported"

# the 2026-10-24 shape: an old file written through the symlink
echo '# old guard' > "$LINK"
out="$(health)"
echo "$out" | grep -E "$RED" | grep -q 'hooks/guard-protected-push.py' && ok "overwrite through a symlink is named" \
  || fail "overwrite through the symlink not reported: $(echo "$out" | grep -E '⚠|✖' | head -5 | tr '\n' ' ')"
echo "$out" | grep -E "$RED" | grep -q 'git -C .* checkout -- hooks/guard-protected-push.py' && ok "the restore command is printed" \
  || fail "no restore command for the overwritten file"
echo "$out" | grep -qE '✖.*(differ from|khác HEAD)' && ok "the line is red (✖), not a warning" || fail "the overwrite line is not red"
[ "$(cd "$K" && git diff HEAD --name-only | wc -l | tr -d ' ')" = 1 ] && ok "health did not restore anything" || fail "health changed the kit"
(cd "$K" && git checkout -q -- hooks/guard-protected-push.py)

# the 24/10 deletion
rm -f "$K/scripts/testing/capture_3d_proof.py"
out="$(health)"
echo "$out" | grep -E "$RED" | grep -q 'scripts/testing/capture_3d_proof.py' && ok "a deleted kit file is named" \
  || fail "deleted kit file not reported: $(echo "$out" | grep -E '⚠|✖' | head -5 | tr '\n' ' ')"
(cd "$K" && git checkout -q -- scripts/testing/capture_3d_proof.py)

out="$(health)"
echo "$out" | grep -qE "$RED" && fail "a restored kit is still reported" || ok "restored kit: nothing reported"

[ "$FAILS" -eq 0 ] && echo "✅ test_agent_health_kit_overwritten: all passed" || { echo "❌ test_agent_health_kit_overwritten: $FAILS failed"; exit 1; }
