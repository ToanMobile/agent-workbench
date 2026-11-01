#!/usr/bin/env bash
# hooks/guard-review-tamper.py, review finding ac772c846b (#742 review REDUCED at 14108864): the `review_sign.py verify` exemption
# was an unanchored search, so `python3 -c '…load_key…' # review_sign.py verify` (or any chain after a real verify) drove the
# signer. Only a line that is exactly one `python3 [-I] <path>/review_sign.py verify <file>` is exempt.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_ALLOW_GATE_EDIT
DK="$(cd "$(dirname "$0")/../.." && pwd)"
G="$DK/hooks/guard-review-tamper.py"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
judge() {   # judge <command> -> deny|allow
  python3 - "$G" "$1" <<'PY'
import json, subprocess, sys
g, cmd = sys.argv[1:3]
p = subprocess.run([sys.executable, g], input=json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}, "cwd": "/repo"}),
                   capture_output=True, text=True, timeout=20)
print("deny" if '"deny"' in p.stdout else "allow")
PY
}
expect() { got="$(judge "$2")"; [ "$got" = "$1" ] && ok "$1: ${2:0:110}" || fail "${2:0:140}: expected $1, got $got"; }
# the chained cases name neither bin/review* nor .git/review-fanout (a verify run from the bin dir), so only the exemption decides
V='python3 review_sign.py verify /tmp/rf/summary.json'
# the finding's own line: the verify words only in a comment
expect deny "python3 -c 'import sys; sys.path.insert(0, \"universal-agent-devkit/bin\"); import review_sign; print(review_sign.load_key(True).decode())' # review_sign.py verify"
# a real verify with something chained, substituted, redirected or on a second line
expect deny "$V; python3 -c 'import review_sign; review_sign.sign(\"s.json\")'"
expect deny "$V && python3 -c 'from review_sign import load_key; print(load_key(True))'"
expect deny "$V || python3 -I -c 'import review_sign'"
expect deny "$V | python3 -c 'import review_sign'"
expect deny "$V & python3 -c 'import review_sign'"
expect deny "python3 review_sign.py verify \$(python3 -c 'import review_sign; review_sign.sign(\"s\")')"
expect deny "python3 review_sign.py verify \`python3 -c 'import review_sign'\`"
expect deny "$V > /tmp/out.txt"
expect deny "$(printf '%s\npython3 -c "import review_sign; review_sign.sign(1)"' "$V")"
expect deny "python3 -c 'import review_sign; review_sign.sign(\"s\")' review_sign.py verify x.json"
expect deny "python3 -m review_sign verify x.json"
expect deny "python3 universal-agent-devkit/bin/review_sign.py sign x.json"
expect deny "python3 review_sign.py sign /tmp/rf/summary.json"
expect deny "cd universal-agent-devkit/bin && $V"
# still allowed: exactly one verify call
expect allow "$V"
expect allow 'python3 universal-agent-devkit/bin/review_sign.py verify .git/review-fanout/H/summary.json'
expect allow "python3 -I universal-agent-devkit/bin/review_sign.py verify .git/review-fanout/H/summary.json"
expect allow "  /usr/bin/python3 /repo/universal-agent-devkit/bin/review_sign.py verify /repo/.git/review-fanout/H/summary.json  "
[ "$FAILS" = 0 ] && { echo "guard review tamper verify-only: all checks passed"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
