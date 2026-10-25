#!/usr/bin/env bash
# writing-standard.md §5: the managed AGENTS.md block (references/agents-md-block.md) is ≤ 40 lines. It is loaded into
# every session of every board repo. 2026-10-25: 62 lines, 21 of them the "DevKit Mandatory Pipeline" that board
# workers already read from super-build/references/worker-preamble.md (and run.md) — the same text, loaded twice.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SB="$ROOT/.claude/skills"
BLOCK="$SB/super-board/references/agents-md-block.md"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

n=$(wc -l < "$BLOCK" | tr -d ' ')
if [ "$n" -le 40 ]; then ok "agents-md-block.md is $n lines (≤ 40)"; else fail "agents-md-block.md is $n lines (> 40, writing-standard §5)"; fi

# The pipeline text leaves the block, not the workers: the preamble every builder reads still carries it.
if grep -q "universal-agent-devkit-workflow:start" "$BLOCK"; then fail "the DevKit pipeline is still in the managed block"
else ok "the DevKit pipeline is not in the managed block"; fi
if grep -q "Mandatory Pipeline" "$SB/super-build/references/worker-preamble.md"; then ok "worker-preamble.md still carries the pipeline"
else fail "worker-preamble.md lost the pipeline"; fi
# Wave lanes read only their own run.md section; Tester and Reviewer sit after the pipeline, so the section every lane
# reads must point at it (before this cut they got it from AGENTS.md).
RUN_MD="${RUN_MD:-$SB/super-board/references/run.md}"
if awk '/^### Running the gate and the merge gate \(every lane\)/{f=1;next} /^#/{f=0} f' "$RUN_MD" | grep -q "Mandatory"; then
  ok "run.md: the every-lane section points every lane at the pipeline"
else fail "run.md: the every-lane section does not point Tester/Reviewer lanes at the pipeline"; fi

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
