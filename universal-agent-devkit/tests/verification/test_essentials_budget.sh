#!/usr/bin/env bash
# rules/essentials.md is written in full into the AGENTS.md of every host project and loaded every session.
# 02/11/2026 the owner asked for rules/essentials.md under 200 lines (it was 220); the cut moved mechanics
# (gate cache, load slots, proof waiver paths) to core-rules.md. Bytes are capped too, so re-wrapping long
# lines cannot pass for a cut. A ratchet: lower the numbers when the file shrinks; raise them only to restore
# an obligation the cut dropped (Antigravity audit T0208 found nine, 157→161 lines).
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
ESS="$DK/rules/essentials.md"
MAX_LINES=161
MAX_BYTES=14350
fail() { echo "✖ $1" >&2; exit 1; }

[ -f "$ESS" ] || fail "missing $ESS"
lines="$(wc -l < "$ESS" | tr -d ' ')"
bytes="$(tr -d '\r' < "$ESS" | wc -c | tr -d ' ')"   # LF bytes: a CRLF checkout must not read red
[ "$lines" -le "$MAX_LINES" ] || fail "rules/essentials.md has $lines lines (budget $MAX_LINES)"
[ "$bytes" -le "$MAX_BYTES" ] || fail "rules/essentials.md has $bytes bytes (budget $MAX_BYTES)"
echo "✅ test_essentials_budget: rules/essentials.md $lines lines, $bytes bytes (budget $MAX_LINES / $MAX_BYTES)"
