#!/usr/bin/env bash
# App repos run a docs check (REG-DOCS-01) that fails on a backticked repo path that does not exist.
# The pr-security-review README cited the upstream file `.claude/commands/security-review.md` in backticks,
# which exists in no repo that receives the skill. Citing it as plain text keeps the credit and the check green.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
README="$ROOT/.claude/skills/pr-security-review/README.md"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

[ -f "$README" ] && ok "README exists" || { fail "README missing"; exit 1; }
dead=0
while IFS= read -r p; do
  [ -e "$ROOT/$p" ] || { dead=$((dead + 1)); echo "  dead backticked path: $p"; }
done < <(grep -o '`\.claude/[A-Za-z0-9_./-]*`' "$README" | tr -d '`' | sort -u)
[ "$dead" -eq 0 ] && ok "every backticked .claude/ path in the README exists here" || fail "$dead backticked .claude/ path(s) do not exist"
grep -q 'claude-code-security-review' "$README" && ok "upstream credit link kept" || fail "upstream credit link lost"
grep -q 'MIT' "$README" && ok "MIT credit kept" || fail "MIT credit lost"

[ "$FAILS" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$FAILS FAILED"; exit 1
