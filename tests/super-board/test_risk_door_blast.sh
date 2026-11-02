#!/usr/bin/env bash
# #549: the Risk block names Door (one-way / two-way) and Blast radius (who is hit + how to undo),
# in the writing standard and in every lane doc; every SKILL.md stays under 20000 UTF-8 bytes.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SK="$ROOT/.claude/skills"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

for f in super-board/references/writing-standard.md super-board/references/run.md \
         super-build/SKILL.md super-qa/references/iteration-preamble.md super-review/SKILL.md; do
  p="$SK/$f"
  if grep -q "Door" "$p" && grep -q "Blast radius" "$p"; then ok "$f names Door and Blast radius"
  else fail "$f lacks Door and/or Blast radius"; fi
done

# The standard shows the exact line shape every lane copies.
if grep -qE '^\*\*Door\*\* · (one-way|two-way)|Door: (one-way|two-way)' "$SK/super-board/references/writing-standard.md"; then
  ok "writing-standard.md shows a Door line with one-way/two-way"
else fail "writing-standard.md has no Door: one-way|two-way line"; fi

for s in "$SK"/*/SKILL.md; do
  n=$(wc -c < "$s" | tr -d ' ')
  if [ "$n" -lt 20000 ]; then ok "$(basename "$(dirname "$s")")/SKILL.md $n < 20000"
  else fail "$(basename "$(dirname "$s")")/SKILL.md $n ≥ 20000"; fi
done

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
