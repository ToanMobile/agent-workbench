## Super Board

Board: Backlog · Ready · Building · QA · Review · Blocked · Done. Labels route: `qa` skips Building · `bug`, `feature`, none → built first.

| When | Use | NEVER |
|---|---|---|
| Set up / repair the board | `/super-board onboard` | DON'T hand-edit config mid-run |
| Check tickets before a run | `/super-board lint` | NEVER run with AC-less tickets |
| Drain the board | `/super-board run` | NEVER build, test or merge from the orchestrator |
| Board state / halt | `/super-board status` · `/super-board stop` | |
| Build one ticket | `/super-build` | NEVER build outside the card's worktree |
| QA a branch, or a live URL alone | `/super-qa` · `/super-qa <url>` | NEVER mark QA pass without evidence |
| Review a PR, merge | `/super-review` | NEVER `gh pr merge` direct — merge gate only |
| File bugs from Sentry, PostHog, PRs | `/super-collect` | DON'T file without a verifier pass |
| UI polish | `/ui-refine-loop` (human runs it) | board NEVER runs it |
| Diagram / explainer page | `/visual` | |
| Commit, pull, push this branch | `/git-sync` | NEVER force push or rebase shared history |

| Rule | Value |
|---|---|
| Config | `.claude/super-board/configs/<slug>.json` |
| Isolation | 1 card · 1 worktree · 1 branch |
| Merge | auto for normal changes · money, auth, destructive schema (DROP/TRUNCATE/RENAME) → human · PR > 400 changed lines → human |
| Migrations | additive → robot migrates allowed DBs only · live DB ALWAYS → 🙋 needs you |
| Blocked card | block-template comment · last line `blocked-by:` · 🙋 = needs you |
| Secrets | NEVER read `.env`; key names via `.claude/bin/super-board-env-check.sh` |

## Writing (super-board)

| Thing | Format → `.claude/skills/super-board/references/writing-standard.md` |
|---|---|
| Commit, PR title | `<emoji> [type] scope: subject` + short bullets · ✨ feat 🐛 fix 🔧 chore ♻️ refactor 🧪 test 📝 docs |
| PR body | blocks: status · Problem · Solution · AC + proof · history · Before\|After · Risk — `super-board-pr-body.sh` |
| Ticket | Problem · Context · Fix · AC · Risk · Blocked by → `docs/agents/issue-tracker.md` |
| Comment | `[role] [label] status` · Did · ✅ Done · ❌ Not done · Next · ≤ 8 lines |
| PR author notes | file + critical inline review comments: Purpose · What changed · Why it matters → `pr-author-notes.md` |

- NEVER chain steps with arrows. One step per line, lettered under Where.
- NEVER link screenshots. Embed a raw URL pinned to a sha.
- DON'T repeat file lists in status comments. DON'T write "Not verified" or "Next" in a PR body.

<!-- universal-agent-devkit-workflow:start -->
## Universal Agent DevKit Mandatory Pipeline & Real-Time 7-Column UI Sync (Zero Duplication)

Every worker running in a Universal Agent DevKit repository MUST execute the DevKit pipeline in a single worktree while updating the GitHub Project UI column in real-time (`super-board-card.sh --config <cfg> move <N> <Column>`) so all columns (`Backlog`, `Ready`, `Building`, `QA`, `Review`, `Blocked`, `Done`) reflect live progress without spawning duplicate test/review workers:

1. **Column `Building` — 5D Context, Codebase Graph & Paired TDD (`context-enricher` + `codebase-memory` + `tdd-workflow` / `fixbugs`):**
   - Move card `Ready -> Building`: `.claude/bin/super-board-card.sh --config <cfg> move <N> Building`.
   - Read `AGENTS.md`, `.agents/context/profile-rules.md`, `.agents/context/rules-index.md`, `.agents/instincts.md` and query `codebase-memory-mcp` (`search_graph`, `trace_path`, `get_code_snippet`, `check_index_coverage`).
   - Run the failing test at the real boundary (**RED**) before editing production code, then implement with Engineering & Zero-Slop Guardrails (**GREEN**).
   - **Surviving Mutant & Anti-Tautology Guard:** If a new test passes on its first run (`First-run Green`), mutate the guarded production line once to confirm **RED**, then restore **GREEN**; never assert on a test's own mock or copy the implementation formula into `expected`.
2. **Column `QA` — DevKit Post-Fix Gate & Visual Proof (`qc` + `verification-before-completion`):**
   - Move card `Building -> QA`: `.claude/bin/super-board-card.sh --config <cfg> move <N> QA`.
   - Execute `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief` (must exit `0`) and capture screenshot proof via `python3 .agents/devkit/bin/proof-capture.py` when app/UI source changes.
   - **Non-Blank, Terminal-State & A/B Perf Guards:** UI proof requires rendered data/empty-state + `0` `console.error`/`pageerror`/uncaught exceptions + `0` background `5xx`/`401`/`403`; async/queue/upload/eSign flows must verify terminal state + persisted destination record (Toast/HTTP 200 alone is never PASS); performance claims require alternating `AB, BA` (>= 5 pairs after warmup).
   - Push branch, open/update PR, and post `[builder] [report]` + `[qa] [report] ✅` with gate output and embedded proof screenshot.
3. **Column `Review` & `Done` — Smart Fast-Track vs Cross-Review (`open-code-review` + `deep-module-design`):**
   - Move card `QA -> Review`: `.claude/bin/super-board-card.sh --config <cfg> move <N> Review`.
   - **Adversarial Review Discipline:** Apply **Blind-First Pass** (read AC + raw `git diff` and form 2–4 failure hypotheses before reading Builder summary), **Review Remembers** (on rework rounds, grade prior `R1..Rn` findings `fixed`/`not fixed` first), and **Taste Never Blocks** (`Over-engineering`/`Deepening opportunity` is `Should fix`, never blocks a test-green diff).
   - **Small/Medium Task (`< 3` files, `<= 200` LOC net diff, no `auth`/`payment`/`migration`/`security`):** Run `open-code-review` self-audit, post `[reviewer] [report] ✅ merge-ready (DevKit Fast-Track)` + the 4-item Acceptance Report (`core-rules §1.3`), run `gh pr ready <PR>` + `.claude/bin/super-board-merge-gate.sh`, and move card `Review -> Done` (`column='Done'`) — unless the gate printed `ac-open: #N` (merged with AC still unproven: the card stays open in Ready, never Done).
   - **Large/High-Risk Task (`>= 2` modules, `>= 3` files, `> 200` LOC net diff, or `auth`/`payment`/`migration`/`security`):** Leave card in `Review` (`column='Review'`) so the independent Reviewer lane (2nd agent / Antigravity `audit`) performs cross-review before merging to `Done`.
<!-- universal-agent-devkit-workflow:end -->
