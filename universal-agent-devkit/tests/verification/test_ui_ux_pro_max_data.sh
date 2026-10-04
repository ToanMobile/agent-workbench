#!/usr/bin/env bash
# Regression test: the ui-ux-pro-max skill's own checks — validate_data.py (CSV shape, official hosts, catalog
# counts) and its unittest suite — run in the gate. They were red at HEAD for days (a stale catalog count, a High
# row without an official URL, a threshold test bound to a growing file) because no matrix rule ran them; the
# impact map (tests/impact_map.txt) now selects this test whenever skills/ui-ux-pro-max/* changes.
# bash 3.2 compatible.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
. "$DEVKIT_DIR/tests/lib/clean_git_env.sh"
SK="$DEVKIT_DIR/skills/ui-ux-pro-max/scripts"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

( cd "$SK" && python3 validate_data.py ) > "$TMP/validate.log" 2>&1 && ok "validate_data.py: $(tail -1 "$TMP/validate.log")" \
  || { fail "validate_data.py failed"; sed 's/^/    /' "$TMP/validate.log" | head -12; }
( cd "$SK" && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_*.py' ) > "$TMP/unit.log" 2>&1 \
  && ok "skill unittests: $(grep -E '^Ran ' "$TMP/unit.log") — $(tail -1 "$TMP/unit.log")" \
  || { fail "skill unittests failed"; grep -E '^(FAIL|ERROR):|^Ran |^FAILED' "$TMP/unit.log" | head -8 | sed 's/^/    /'; }

[ "$FAILS" -eq 0 ] && echo "✅ test_ui_ux_pro_max_data: all passed" || { echo "❌ test_ui_ux_pro_max_data: $FAILS failed"; exit 1; }
