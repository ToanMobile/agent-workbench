#!/usr/bin/env bash
# Regression test (fresh-context audit 2026-10-10, GeelyEx2) for bin/agent-health.py: the kit moved scripts/red_proof.py to scripts/testing/,
# GeelyEx2 kept a COMMITTED symlink scripts/red_proof.py -> ../.agents/devkit/scripts/red_proof.py that now points at nothing, and health still
# said 100/100 because its broken-link check looks only inside .claude/ and .agents/. A clone or CI breaks on such a link. Health now also
# warns about any tracked symlink (git mode 120000) whose target is missing, wherever it lies; a tracked link that resolves stays silent.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HEALTH="${HEALTH_UNDER_TEST:-$DEVKIT_DIR/bin/agent-health.py}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
strip() { sed 's/\x1b\[[0-9;]*m//g'; }

W="$TMP/proj"; mkdir -p "$W/scripts" && (cd "$W" && git init -q && git config user.email t@t && git config user.name t && echo x > a && git add a && git commit -qm i)
bash "$DEVKIT_DIR/bin/install.sh" -t "$W" -a claude -p backend -y --no-githooks >/dev/null 2>&1

health() { python3 "$HEALTH" -t "$W" 2>&1 | strip; }
WARN='a clone or CI breaks|clone hoặc CI sẽ hỏng'   # only the warning carries it; the passing line ("No tracked symlink points …") does not

out="$(health)"
echo "$out" | grep -qE "$WARN" && fail "a project with no tracked symlink was reported: $(echo "$out" | grep -E "$WARN")" || ok "no tracked symlink: nothing to report"

# a tracked link that resolves
echo real > "$W/scripts/real.py"
( cd "$W" && ln -s real.py scripts/good.py && git add scripts/real.py scripts/good.py && git commit -qm good )
out="$(health)"
echo "$out" | grep -q 'good.py' && fail "a tracked symlink that resolves was reported" || ok "a resolving tracked symlink is silent"

# a tracked link whose target is gone: the GeelyEx2 shape
( cd "$W" && ln -s ../.agents/devkit/scripts/red_proof_gone.py scripts/red_proof_gone.py && git add scripts/red_proof_gone.py && git commit -qm broken )
out="$(health)"
echo "$out" | grep -q 'scripts/red_proof_gone.py' && ok "a tracked symlink with a missing target is named" \
  || fail "broken tracked symlink not reported: $(echo "$out" | grep -E '⚠|✖' | head -5 | tr '\n' ' ')"
echo "$out" | grep -E "$WARN" | grep -q 'good.py' && fail "the resolving link was listed next to the broken one" || ok "only the broken link is listed"

[ "$FAILS" -eq 0 ] && echo "✅ test_agent_health_broken_tracked_link: all passed" || { echo "❌ test_agent_health_broken_tracked_link: $FAILS failed"; exit 1; }
