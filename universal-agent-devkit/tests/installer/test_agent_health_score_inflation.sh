#!/usr/bin/env bash
# Regression test (issue #21) for bin/agent-health.py: the score said 100/100 although `"hooks": {}` was empty
# (no hook registered, so no guard runs) and although the project had no pre-commit hook (the DevKit gate never sees a commit).
# Both must now cost points; a project that has both stays at the score it had.
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
score_of() { python3 "$HEALTH" -t "$1" 2>&1 | strip | grep -Eo '(Điểm|Score): [0-9]+/100' | grep -Eo '[0-9]+' | head -1; }

mk() {  # mk <dir> <install flags>
  mkdir -p "$1" && (cd "$1" && git init -q && git config user.email t@t && git config user.name t && echo x > a && git add a && git commit -qm i)
  bash "$DEVKIT_DIR/bin/install.sh" -t "$1" -a claude -p backend -y $2 >/dev/null 2>&1
}

mk "$TMP/with" ""
mk "$TMP/without" "--no-githooks"
base="$(score_of "$TMP/with")"; nohook="$(score_of "$TMP/without")"
[ -n "$base" ] && [ -n "$nohook" ] || { fail "no score read (with='$base' without='$nohook')"; exit 1; }

[ "$nohook" -lt "$base" ] && ok "missing pre-commit hook lowers the score ($base -> $nohook)" \
  || fail "missing pre-commit hook did not lower the score (with=$base without=$nohook)"

# empty hooks object in .claude/settings.json
python3 - "$TMP/with/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["hooks"] = {}
json.dump(d, open(p, "w"))
PY
empty="$(score_of "$TMP/with")"
[ "$empty" -lt "$base" ] && ok "empty \"hooks\": {} lowers the score ($base -> $empty)" \
  || fail "empty \"hooks\": {} did not lower the score (before=$base after=$empty)"

[ "$FAILS" -eq 0 ] && echo "✅ test_agent_health_score_inflation: all passed" || { echo "❌ test_agent_health_score_inflation: $FAILS failed"; exit 1; }
