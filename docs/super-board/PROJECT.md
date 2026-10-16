# agent-workbench — project notes for super-board

**What it is.** Home of the Universal Agent DevKit (`universal-agent-devkit/`): hooks, gates, skills and
the `agent-kit` installer that other repos (GeelyEx2, OfficeReader, Goods, Neighbours-From-Hell) link to.
Profile: backend. Primary languages: Python and Bash.

**Where things live**
- `universal-agent-devkit/hooks/`, `bin/`, `scripts/`, `skills/`, `tests/` — the kit itself.
- `.agents/` — project rules, instincts, regression matrix and checklist; `AGENTS.md` is the source of truth.
- `.agents/local/memory/` — agent memory, git-ignored, never committed.

**Rules a builder must follow**
- Read `AGENTS.md` first: its DevKit block is non-negotiable (paired RED→GREEN test for every bug fix, gate exit 0, no `--no-verify`).
- A change to a hook or gate needs its test in `universal-agent-devkit/tests/` and an independent review (guard code failed open in 4 review rounds).
- Verification command: `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief` — only exit 0 is PASS.
- Trunk mode is on: work in a worktree, never edit the main checkout.
