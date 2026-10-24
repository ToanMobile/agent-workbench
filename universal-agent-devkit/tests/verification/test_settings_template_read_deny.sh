#!/usr/bin/env bash
# Regression test (issue #139): the settings templates must not deny Read on the APK build output,
# because headless QA workers list and install the debug APK from app/build/outputs/apk (Claude Code
# applies a Read deny to the paths inside a Bash command, so `ls app/build/outputs/apk/debug` was refused).
# Bulky or sensitive artefacts stay denied: build/intermediates, build/tmp, *.aab, *.hprof.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REPO_DIR="$(cd "$DEVKIT_DIR/.." && pwd)"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

check() {
  local label="$1" file="$2"
  if [ ! -f "$file" ]; then fail "$label: $file missing"; return; fi
  python3 - "$file" <<'PY' && ok "$label" || fail "$label"
import json, sys
deny = json.load(open(sys.argv[1]))["permissions"]["deny"]
bad = [r for r in ("Read(**/build/**)", "Read(**/*.apk)") if r in deny]
assert not bad, f"blocks the APK output: {bad}"
need = ["Read(**/build/intermediates/**)", "Read(**/build/tmp/**)", "Read(**/*.aab)", "Read(**/*.hprof)"]
missing = [r for r in need if r not in deny]
assert not missing, f"lost the bulky-artefact denies: {missing}"
PY
}

check "template claude_settings.json" "$DEVKIT_DIR/templates/claude_settings.json"
check "devkit .claude/settings.json" "$DEVKIT_DIR/.claude/settings.json"
if [ -f "$REPO_DIR/.claude/settings.json" ] && [ "$REPO_DIR" != "$DEVKIT_DIR" ]; then
  check "repo .claude/settings.json" "$REPO_DIR/.claude/settings.json"
fi

[ "$FAILS" -eq 0 ]
