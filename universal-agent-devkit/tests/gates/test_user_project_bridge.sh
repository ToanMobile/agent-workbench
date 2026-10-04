#!/usr/bin/env bash
# user_project_bridge.sh: a user-level hook runs the project bridge only when
# the checkout has one and does not already register that platform.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CMD="$DEVKIT_DIR/hooks/user_project_bridge.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# Not a git checkout: no-op, bridge is not required.
out="$(cd "$TMP" && bash "$CMD" codex stop regression_gate.sh </dev/null 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "outside git: exit 0, no output" || fail "outside git: rc=$rc out=$out"

repo="$TMP/repo"
mkdir -p "$repo/.agents/hooks" && git -C "$repo" init -q
cat > "$repo/.agents/hooks/agent_bridge.sh" <<'SH'
#!/bin/sh
printf 'called %s\n' "$*"
cat >/dev/null
SH
chmod +x "$repo/.agents/hooks/agent_bridge.sh"
out="$(cd "$repo" && printf 'payload' | bash "$CMD" codex stop regression_gate.sh 2>&1)"; rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'called codex stop regression_gate.sh' \
  && ok "project bridge runs when the platform has no hooks.json" \
  || fail "bridge call: rc=$rc out=$out"

mkdir -p "$repo/.codex"
printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"command":"bash .agents/hooks/agent_bridge.sh codex stop regression_gate.sh"}]}]}}' > "$repo/.codex/hooks.json"
out="$(cd "$repo" && printf 'payload' | bash "$CMD" codex stop regression_gate.sh 2>&1)"; rc=$?
[ "$rc" = 0 ] && ! printf '%s' "$out" | grep -q 'called ' \
  && ok "project hooks.json already names the bridge: user hook does not run it again" \
  || fail "double run: rc=$rc out=$out"

if [ "$FAILS" -ne 0 ]; then
  echo "user_project_bridge: $FAILS FAILED"; exit 1
fi
echo "user_project_bridge: all checks passed"
