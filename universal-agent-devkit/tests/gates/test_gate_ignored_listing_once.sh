#!/usr/bin/env bash
# bin/post-fix-gate.py, the list of git-ignored local config files (2026-10-13, /devkit-audit plan item 5, overhead): one
# `git ls-files --others --ignored` walk costs 1.5 s warm and 3.8 s cold in OfficeReader (measured), and one --full run asked it up
# to 5 times (snapshot_local_configs twice, local_state_sha three times: the receipt check, the receipt, the reuse key). The list
# is now read once per run for each set of pathspecs; the files' CONTENT is still hashed at every call, so an edited .env changes
# the receipt key exactly as before. A config file created or deleted DURING the run is missed by the cached list: the next run
# reads a fresh list, sees a different key and runs the suites again (more runs, never a wrong reuse).
# Switch: DEVKIT_GATE_LISTING_CACHE=0 restores one walk per call.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="${GATE_PY:-$DEVKIT_DIR/bin/post-fix-gate.py}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
REALGIT="$(command -v git)"
mkdir -p "$TMP/bin"
cat > "$TMP/bin/git" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$TMP/git.log"
exec "$REALGIT" "\$@"
EOF
chmod +x "$TMP/bin/git"

P="$TMP/p"; mkdir -p "$P/src" && cd "$P" || exit 1
git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
printf 'def f():\n    return 1\n' > src/mod.py
printf '.env\nlocal.properties\n' > .gitignore
cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}
JSON
git add -A && git commit -qm init
printf 'KEY=one\n' > .env
printf 'sdk.dir=/x\n' > local.properties
printf 'def f():\n    return 2\n' > src/mod.py

gate() {
  : > "$TMP/git.log"
  OUT="$(PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$PWD" POSTFIX_GATE_FORCE_FULL=1 python3 "$GATE" --matrix "$PWD/matrix.json" \
         --lang en --json "$@" 2>&1)"; RC=$?
  JSON="$(printf '%s\n' "$OUT" | grep '^{' | tail -1)"
}
j() { printf '%s' "$JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1" 2>/dev/null; }
walks() { grep -c -- '--ignored' "$TMP/git.log"; }

gate --run-tests --full
n1="$(walks)"
[ "$RC" = 0 ] && ok "first --full run PASS (exit 0)" || bad "first run exit $RC"
[ "$n1" -le 2 ] && ok "first run walks the ignored files $n1 time(s) (one per pathspec set)" || bad "first run walks the ignored files $n1 times (want <= 2)"
gate --run-tests --full
n2="$(walks)"
[ "$RC" = 0 ] && [ "$(j 'd["regression_tests"][0].get("mode")')" = cached ] && ok "same content: the receipt is reused" \
  || bad "no reuse on unchanged content (exit $RC, mode $(j 'd["regression_tests"][0].get("mode")'))"
[ "$n2" -le 2 ] && ok "a reusing run walks the ignored files $n2 time(s)" || bad "a reusing run walks the ignored files $n2 times (want <= 2)"
printf 'KEY=two\n' > .env
gate --run-tests --full
[ "$RC" = 0 ] && [ "$(j 'd["regression_tests"][0].get("mode")')" != cached ] && ok "an edited .env changes the key: the suites run again" \
  || bad "edited .env reused the old receipt (exit $RC, mode $(j 'd["regression_tests"][0].get("mode")'))"
DEVKIT_GATE_LISTING_CACHE=0 gate --run-tests --full
n3="$(walks)"
[ "$n3" -gt 2 ] && ok "DEVKIT_GATE_LISTING_CACHE=0: one walk per call again ($n3)" || bad "switch off still walks only $n3 times"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
