#!/usr/bin/env bash
# Regression test: scripts/context_sync.py writes the DevKit essentials IN FULL between the
# devkit-essentials markers of the project's AGENTS.md. Antigravity reads AGENTS.md as plain
# text and expands no `@` import (measured 2026-09-25), so an import alone never reached it.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SYNC="$DEVKIT_DIR/scripts/context_sync.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

P="$TMP/proj"; mkdir -p "$P/.agents"
{ echo "# My project"; echo "Own text stays."; echo "<!-- universal-agent-devkit:start -->";
  cat "$DEVKIT_DIR/templates/agents_injection_block.md"; echo "<!-- universal-agent-devkit:end -->"; echo "Tail text stays."; } > "$P/AGENTS.md"
first_rule="$(grep -m1 '^## Lazy senior' "$DEVKIT_DIR/rules/essentials.md")"

python3 "$SYNC" "$P" --quiet
sec="$(sed -n '/devkit-essentials:start/,/devkit-essentials:end/p' "$P/AGENTS.md")"
printf '%s' "$sec" | grep -qF "$first_rule" && printf '%s' "$sec" | grep -qF "## Every prompt" \
  && ok "essentials written in full between the markers" || fail "section: $(printf '%s' "$sec" | head -3 | tr '\n' '|')"
grep -q '^Own text stays.$' "$P/AGENTS.md" && grep -q '^Tail text stays.$' "$P/AGENTS.md" \
  && ok "text outside the markers kept" || fail "own text lost"
[ "$(grep -c 'devkit-essentials:start' "$P/AGENTS.md")" = 1 ] && ok "one section, not duplicated" || fail "markers duplicated"

cp "$P/AGENTS.md" "$TMP/before"; python3 "$SYNC" "$P" --quiet
cmp -s "$TMP/before" "$P/AGENTS.md" && ok "second run changes nothing" || fail "not idempotent"
python3 "$SYNC" "$P" --check --quiet && ok "--check clean after sync" || fail "--check reports stale after sync"

python3 - "$P/AGENTS.md" <<'PY'
import sys; p = sys.argv[1]; s = open(p).read(); open(p, "w").write(s.replace("## Every prompt", "## Every prompt (edited by hand)"))
PY
out="$(python3 "$SYNC" "$P" --check)"; rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q "AGENTS.md" && ok "--check names a hand-edited section" || fail "--check missed the edit (rc=$rc: $out)"
python3 "$SYNC" "$P" --quiet; ! grep -q "edited by hand" "$P/AGENTS.md" && ok "sync restores the section" || fail "hand edit survived"

Q="$TMP/nomark"; mkdir -p "$Q/.agents"; printf '# Plain\nno DevKit block\n' > "$Q/AGENTS.md"
python3 "$SYNC" "$Q" --quiet; [ "$(cat "$Q/AGENTS.md")" = "$(printf '# Plain\nno DevKit block')" ] \
  && ok "AGENTS.md without markers untouched" || fail "unmarked AGENTS.md changed"

if [ "$FAILS" -ne 0 ]; then echo "context_sync: $FAILS FAILED"; exit 1; fi
echo "context_sync: all checks passed"
