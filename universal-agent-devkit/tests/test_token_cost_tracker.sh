#!/usr/bin/env bash
# Regression test: token_cost_tracker.py pricing calculations and transcript parsing
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$DEVKIT_DIR/scripts/token_cost_tracker.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# Test 1: Help command runs cleanly
python3 "$SCRIPT" --help >/dev/null 2>&1
if [ $? -eq 0 ]; then
  ok "token_cost_tracker.py --help returns exit 0"
else
  fail "token_cost_tracker.py --help failed"
fi

# Test 2: Direct calculation in JSON mode
JSON_OUT=$(python3 "$SCRIPT" --model claude-3-7-sonnet --input 1000000 --output 100000 --cache-read 500000 --json)
if echo "$JSON_OUT" | grep -q '"total": 4.65'; then
  ok "Token cost calculation matches expected math"
else
  fail "Calculation error: $JSON_OUT"
fi

# Test 3: Markdown report formatting
MD_OUT=$(python3 "$SCRIPT" --model claude-3-7-sonnet --input 100000 --output 1000)
if echo "$MD_OUT" | grep -q "Thống kê Chi phí Token"; then
  ok "Markdown table report formatted properly"
else
  fail "Markdown formatting error"
fi

# Test 4: Parse mock transcript file
TRANSCRIPT="$TMP/transcript.jsonl"
cat <<'EOF' > "$TRANSCRIPT"
{"message":{"model":"claude-3-7-sonnet","usage":{"input_tokens":50000,"output_tokens":2000,"cache_read_input_tokens":10000,"cache_creation_input_tokens":5000}}}
{"message":{"model":"claude-3-7-sonnet","usage":{"input_tokens":25000,"output_tokens":1000,"cache_read_input_tokens":5000,"cache_creation_input_tokens":0}}}
EOF

PARSE_OUT=$(python3 "$SCRIPT" --transcript "$TRANSCRIPT" --json)
if echo "$PARSE_OUT" | grep -q '"total": 98000'; then
  ok "Transcript JSONL parsing aggregates all turns accurately"
else
  fail "Transcript parsing aggregation error: $PARSE_OUT"
fi

# Test 5: streamed records of ONE message id (cumulative usage) count once, last record wins
DUP="$TMP/dup.jsonl"
cat <<'EOF2' > "$DUP"
{"message":{"id":"msg_1","model":"claude-3-7-sonnet","usage":{"input_tokens":100,"output_tokens":1}}}
{"message":{"id":"msg_1","model":"claude-3-7-sonnet","usage":{"input_tokens":100,"output_tokens":50}}}
{"message":{"id":"msg_2","model":"claude-3-7-sonnet","usage":{"input_tokens":10,"output_tokens":5}}}
EOF2
DUP_OUT=$(python3 "$SCRIPT" --transcript "$DUP" --json)
if echo "$DUP_OUT" | grep -q '"input": 110,' && echo "$DUP_OUT" | grep -q '"output": 55,'; then
  ok "duplicate message ids are counted once (last usage wins)"
else
  fail "duplicate message ids double-counted: $DUP_OUT"
fi

# Test 6: the most specific model name wins (gpt-4o-mini must not be priced as gpt-4o)
MINI_OUT=$(python3 "$SCRIPT" --model gpt-4o-mini --input 1000000 --json)
if echo "$MINI_OUT" | grep -q '"total": 0.15'; then
  ok "gpt-4o-mini priced as gpt-4o-mini"
else
  fail "gpt-4o-mini mispriced: $MINI_OUT"
fi

# Test 7: an unknown model is priced at the default tier but says so on stderr
UNK_ERR=$(python3 "$SCRIPT" --model totally-unknown-model --input 1000 --json 2>&1 >/dev/null)
if echo "$UNK_ERR" | grep -qi "unknown model"; then
  ok "unknown model warns instead of silently using the default tier"
else
  fail "no warning for an unknown model"
fi

if [ $FAILS -gt 0 ]; then
  echo "FAILED: $FAILS errors"
  exit 1
fi
echo "ALL TESTS PASSED"
exit 0
