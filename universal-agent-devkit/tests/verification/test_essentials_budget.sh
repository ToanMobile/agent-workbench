#!/usr/bin/env bash
# rules/essentials.md is written in full into the AGENTS.md of every host project and loaded every session.
# 02/11/2026 the owner asked for the always-on rules under 200 lines in every repo; the cut moved mechanics
# (gate cache, load slots, proof waiver paths) to core-rules.md. Bytes are capped too, so re-wrapping long
# lines cannot pass for a cut. A ratchet: lower the numbers when the file shrinks, never raise them.
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
ESS="$DK/rules/essentials.md"
MAX_LINES=157
MAX_BYTES=13700
fail() { echo "✖ $1" >&2; exit 1; }

[ -f "$ESS" ] || fail "missing $ESS"
lines="$(wc -l < "$ESS" | tr -d ' ')"
bytes="$(wc -c < "$ESS" | tr -d ' ')"
[ "$lines" -le "$MAX_LINES" ] || fail "rules/essentials.md has $lines lines (budget $MAX_LINES)"
[ "$bytes" -le "$MAX_BYTES" ] || fail "rules/essentials.md has $bytes bytes (budget $MAX_BYTES)"
echo "✅ test_essentials_budget: rules/essentials.md $lines lines, $bytes bytes (budget $MAX_LINES / $MAX_BYTES)"
