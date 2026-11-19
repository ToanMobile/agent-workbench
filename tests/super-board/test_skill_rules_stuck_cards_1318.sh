#!/usr/bin/env bash
# #1318/#1319: các câu luật mà runner dựa vào phải nằm trong skill/run.md (ghim chữ, để một lần sửa văn bản không làm mất luật).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
has() { grep -qF -- "$2" "$1" && ok "$3" || fail "$3 (missing in ${1#$ROOT/}: $2)"; }

B="$ROOT/.claude/skills/super-build/SKILL.md"
R="$ROOT/.claude/skills/super-review/SKILL.md"
M="$ROOT/.claude/skills/super-board/references/run.md"

has "$B" "**Before ending the turn (#1318):** push any local commit that is not on \`origin\`" "super-build: push local commits before ending the turn"
has "$B" "the last command of the turn exactly one \`move\` of the card" "super-build: the last command is one move"
has "$R" "A missing rebase is not a bounce: it does not count toward \`rebuild_cap\`" "super-review: missing rebase is not a bounce, not counted in rebuild_cap"
has "$R" "a card that already hit the cap still goes Review → Ready \`loop:rebase\`" "super-review: capped card still goes Ready loop:rebase"
has "$M" "A missing rebase is not a bounce: it does not count toward \`rebuild_cap\`" "run.md reviewer step: missing rebase is not a bounce"
has "$M" "A \`loop:rebase\` pass does not count toward \`rebuild_cap\` (#1319)" "run.md rebase pass: loop:rebase not counted in rebuild_cap"

[ "$FAILS" -eq 0 ] && { echo "PASS test_skill_rules_stuck_cards_1318"; exit 0; }
echo "FAIL test_skill_rules_stuck_cards_1318 ($FAILS)"; exit 1
