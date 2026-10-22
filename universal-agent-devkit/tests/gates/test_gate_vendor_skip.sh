#!/usr/bin/env bash
# Regression (agent-office, 22/10): third-party code under a vendor/ directory (a minified three.min.js) was rejected by the
# post-fix gate for an empty catch block and console.log, so it could not be committed. The four content audits (anti-laziness,
# performance antipatterns, resilience, logging) skip a `vendor` directory; the secret scan does NOT.
#   1. try{}catch(e){} + console.log in x/web/vendor/lib.min.js passes the gate
#   2. the same content under src/ is still rejected
#   3. a secret-looking literal under vendor/ is still rejected
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
R="$TMP/repo"
TOKEN="sk_live_$(python3 -c 'print("e" * 24, end="")')"
JS='function f(){try{g()}catch(e){}console.log("x");}'

make_repo() {
  rm -rf "$R" && mkdir -p "$R/src" && cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt
  git add -A && git commit -qm init
}
run_gate() { OUT="$(CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --lang en --run-tests --allow-no-tests 2>&1)"; RC=$?; }

make_repo
mkdir -p mcp-servers/x/web/vendor && printf '%s\n' "$JS" > mcp-servers/x/web/vendor/lib.min.js
run_gate
[ "$RC" = 0 ] && ok "1: empty catch + console.log under vendor/ passes" || { bad "1: vendor/ file rejected (exit $RC)"; printf '%s\n' "$OUT" | tail -8; }

make_repo
mkdir -p mcp-servers/x/web/src && printf '%s\n' "$JS" > mcp-servers/x/web/src/lib.js
run_gate
[ "$RC" = 1 ] && ok "2: the same content under src/ is still rejected" || { bad "2: src/ file accepted (exit $RC)"; printf '%s\n' "$OUT" | tail -8; }

make_repo
mkdir -p mcp-servers/x/web/vendor && printf 'const c = "%s";\n' "$TOKEN" > mcp-servers/x/web/vendor/key.js
run_gate
[ "$RC" = 1 ] && ok "3: a secret under vendor/ is still rejected" || { bad "3: vendor/ secret accepted (exit $RC)"; printf '%s\n' "$OUT" | tail -8; }

[ "$FAILS" = 0 ] && { echo "OK"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
