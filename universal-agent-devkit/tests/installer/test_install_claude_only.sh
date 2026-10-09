#!/usr/bin/env bash
# test_install_claude_only.sh — B3 (audit 2026-10-09): `install.sh -a claude` (`--agents=claude`)
# must give a project agent-health passes, and whose AGENTS.md names only folders that exist.
# It used to FAIL health for ever: .agents/skills/* was placed by setup_gemini.sh alone, so the
# "Every DevKit command and skill" check failed, re-running init as the message advised changed
# nothing, and AGENTS.md pointed the agent at .agents/skills/ that did not exist.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export DEVKIT_LANG=en

DEVKIT="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-claude-only.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
strip() { sed 's/\x1b\[[0-9;]*m//g'; }

P="$TMP/proj"
mkdir -p "$P" && (cd "$P" && git init -q && git config user.email t@t && git config user.name t \
  && git config commit.gpgsign false && echo x > a && git add a && git commit -qm init)

bash "$DEVKIT/bin/install.sh" -t "$P" -y -p universal --agents=claude --no-githooks > "$TMP/i1.out" 2>&1 \
  && ok "claude-only install exit 0" || { fail "claude-only install failed"; tail -5 "$TMP/i1.out"; }
[ ! -e "$P/.gemini" ] && [ ! -e "$P/mcp_config.json" ] && [ ! -e "$P/.codex" ] && [ ! -e "$P/.cursor" ] \
  && ok "nothing of the other agents is written" || fail "claude-only install wrote another agent's files"
n="$(find "$P/.agents/skills" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | xargs)"
[ "$n" -gt 0 ] && [ -f "$P/.agents/skills/qc/SKILL.md" ] \
  && ok "the profile's skills are in .agents/skills ($n), as AGENTS.md says" || fail ".agents/skills missing after a claude-only install ($n entries)"
grep -q '\.agents/skills/' "$P/AGENTS.md" && ok "(AGENTS.md does name .agents/skills/)" || fail "AGENTS.md no longer names .agents/skills/ — update this test"

python3 "$DEVKIT/bin/agent-health.py" -t "$P" > "$TMP/h1.out" 2>&1; rc=$?
if [ "$rc" = 0 ]; then ok "agent-health passes on a claude-only install"
else fail "agent-health exit $rc on a claude-only install:"; strip < "$TMP/h1.out" | grep -E "✖|Result|Kết quả" | head -5; fi

# Re-init with no -a keeps the agents already set up (claude): still healthy, still no Gemini files.
bash "$DEVKIT/bin/install.sh" -t "$P" -y > "$TMP/i2.out" 2>&1 || { fail "re-init failed"; tail -5 "$TMP/i2.out"; }
grep -q "keeping the agents already set up: claude" "$TMP/i2.out" && ok "re-init keeps the claude-only setup" || fail "re-init did not keep claude-only"
python3 "$DEVKIT/bin/agent-health.py" -t "$P" > "$TMP/h2.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$P/.gemini" ] && ok "re-init: agent-health still passes, no Gemini files" \
  || { fail "re-init: health exit $rc"; strip < "$TMP/h2.out" | grep -E "✖" | head -5; }

# Uninstall takes the skill links away again.
bash "$DEVKIT/bin/agent-kit" uninstall "$P" --apply > "$TMP/u.out" 2>&1
[ ! -e "$P/.agents/skills" ] && ok "uninstall removes .agents/skills" || fail "uninstall left .agents/skills: $(ls "$P/.agents/skills" | head -3)"

if [ "$FAILS" -ne 0 ]; then echo "claude-only install: $FAILS FAILED"; exit 1; fi
echo "claude-only install: all checks passed"
