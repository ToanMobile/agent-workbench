#!/usr/bin/env bash
# Regression test: `agent-kit init .` with no -y/-p/-a (how an agent runs it, no tty) must keep what the
# project already has — its agents and its profile. 2026-09-30: GeelyEx2, OfficeReader and
# Goods-Triple each lost MCP entries / a hook / their profile and gained .codex/ + .cursor/.
set -u
DEVKIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
P="$(mktemp -d -t devkit-reinit-XXXXXX)"
trap 'rm -rf "$P"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

git -C "$P" init -q .
bash "$DEVKIT_ROOT/bin/install.sh" -t "$P" -y -p backend -a claude,gemini -m symlink >/dev/null 2>&1 || fail "first install exited non-zero"
profile_of() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("profile",""))' "$P/.agents/active-profile.json" 2>/dev/null; }
[ "$(profile_of)" = backend ] && ok "first install: profile backend" || fail "first install: profile is '$(profile_of)'"

# Exactly what `agent-kit init .` runs, with no controlling tty and stdin closed.
python3 - "$DEVKIT_ROOT" "$P" <<'PY'
import subprocess, sys
root, proj = sys.argv[1:3]
subprocess.run(["bash", f"{root}/bin/install.sh", f"--target={proj}", "--domain=auto", "--mode=symlink"],
               stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
PY

[ "$(profile_of)" = backend ] && ok "re-init keeps the profile (backend)" || fail "re-init changed the profile to '$(profile_of)'"
[ ! -e "$P/.codex" ] && ok "re-init does not add .codex/" || fail "re-init added .codex/"
[ ! -e "$P/.cursor" ] && ok "re-init does not add .cursor/" || fail "re-init added .cursor/"
grep -q ".claude/hooks/" "$P/.claude/settings.json" 2>/dev/null && ok "re-init keeps the claude hooks" || fail "claude hooks gone after re-init"

if [ $FAILS -gt 0 ]; then echo "FAILED: $FAILS errors"; exit 1; fi
echo "ALL TESTS PASSED"
