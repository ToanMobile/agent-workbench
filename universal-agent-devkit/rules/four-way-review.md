# Four-way review — the only code review that passes (31/10/2026)

> User: "Bất cứ review nào 3 agent review là ai và 3 nó phải cùng thống nhất kết quả thì mới gọi là pass." — widened the same
> day to FOUR equal reviewers: Claude Code on Opus, Antigravity, Grok and Alibaba OCR. All four must PASS, unanimously.

## Who reviews (all four required, equal votes)
| Reviewer | How it runs | Vote |
|---|---|---|
| **Claude Code — Opus** | `claude -p --model opus`, read-only (Read/Grep/Glob + read-only git) | its JSON `verdict`; the model that answered (result `modelUsage`) must be Opus |
| **Antigravity** | `mcp-servers/antigravity-pm-mcp/bin/pm-review-audit.js` (pm_task_create → pm_dispatch kind=audit) | `audit-agent.json` verdict for this HEAD |
| **Grok** | `grok --prompt-file … --output-format json -m grok-4.7 --sandbox read-only --tools read_file,grep,list_dir,run_terminal_cmd` | its JSON `verdict`; `modelUsage` must show the pinned model |
| **Alibaba OpenCodeReview** | `bin/ocr-review --strict` — OCR's own LLM (full mode, `REVIEW_GATE_OCR=full`); the delegation spec never counts | pass iff the run completed and no critical/high comment |

Plus, never optional: `registry` (bin/known_patterns.py — a known bug pattern on an added line is a P0 recurring bug) and, at depth
**deep** (≥ 50 changed lines or an auth / payment / schema / migration / secret path): a Claude Opus **security** reviewer and the
Claude Opus **verifier** (tries to refute every P0/P1).

Models: `REVIEW_CLAUDE_MODEL` (default `opus`; a non-Opus value is refused) and `REVIEW_GROK_MODEL` (default `grok-4.7`). The
model that really answered is recorded in each envelope (`model`, `models`), in `summary.md` and in `review_outcomes.jsonl`;
Claude not on Opus (or not reported), Grok not on its pinned model (or not reported) = that reviewer FAILED.

## Run it
```
bash .agents/devkit/bin/review-fanout.sh --base origin/<base>      # in the DevKit repo: universal-agent-devkit/bin/review-fanout.sh
```
The 4 reviewers run in parallel, each with its own timeout. Results: `<git-common-dir>/review-fanout/<code-hash>/summary.md|json`
(one verdict, deduped findings with consensus marks, inline comments). The same code is never reviewed twice (cache by code hash).
The Stop hook `hooks/review_gate.sh` runs the same thing (`--base verified`) and blocks until it PASSES.

## PASS only when ALL hold (bin/review-merge.py)
1. Claude Code (Opus), Antigravity, Grok and OCR (and registry; security + verifier when deep) each produced a result, status `ok`,
   verdict `pass`, on the required model. Missing, failed, timed out, errored, unavailable, out of credit, wrong model, or a `fail`
   vote → **FAIL**. No fail-open, no fallback, no release after N blocks.
2. No blocking finding: a P0/P1 whose file:line + verbatim snippet is really in the code (cite-check, every reviewer) and that the
   verifier did not refute. A refuted one is downgraded to P3 and logged. A `detect` hit of a known pattern is never refutable.
3. Tokens / USD within `REVIEW_MAX_TOKENS` (3 000 000) / `REVIEW_MAX_USD` (15).
4. Every accepted P0/P1 of an earlier run — an OPEN row `BUG-REV-<id>` in the regression checklist — is fixed **with a linked
   regression test that passed**: `regression_checklist.py bug-link BUG-REV-<id> <test>` then `post-fix-gate.py --run-tests`.
   Not a bug after all: `regression_checklist.py drop BUG-REV-<id>` (it stays in review_outcomes.jsonl).

## Reviewer instructions (all four get the same)
- Read the callers, callees and tests of every changed symbol; findings stay scoped to the change.
- Known bug patterns of the repo (`.agents/instincts.md`) are in the prompt; a repeat is tagged `known_pattern` and is P0.
- Severity: P0 data loss / security / crash / wrong result on a main path / recurring bug · P1 real bug on a reachable path ·
  P2 should fix · P3 nit. Verdict pass only with no P0/P1.

## Never again: the anti-regression loop
- Fixed P0/P1 → regression test linked (rule 4 above blocks until then).
- A new bug class → `instincts.py add "<title>" --cause … --rule … --detect '<regex>' --detect-glob '*.py'`: every later review
  greps added lines for it (fanout and CI) and CI also runs it as a generated semgrep rule (`known_patterns.py semgrep`).
- Every run → `.claude/audit-gate/review_outcomes.jsonl` (verdict, reasons, each finding's state: blocking / refuted / uncited / advisory).

## Board / PR
`approved-head` and `cross-review-approved` are posted ONLY after `review-fanout.sh` printed PASS for that exact head
(summary.json `verdict: PASS`); paste the summary path into the Reviewer report. Merge policy stays autonomous (no human approval);
the machine gates are this review + `.github/workflows/pr-review.yml` (lint, typecheck, tests, semgrep, gitleaks, OCR).

## Whole-solution scan (`review-fanout.sh --full`)
`bash universal-agent-devkit/bin/review-fanout.sh --full --repo .` (`--list` shows the plan, no LLM) runs the same four reviewers
over every tracked source file, not a diff: the separate clones (mcp-servers/rea, mcp-servers/super-board), node_modules,
vendored / generated / build output, lockfiles, minified and binary files, data (.csv/.jsonl, .json > 1500 lines) and prose
(.md/.txt, docs/) are excluded. Files are chunked by module (≤ 6000 lines, `--chunk-lines`); Claude Opus, Antigravity and
Grok review each chunk, OCR reviews the whole selection once in a scratch copy, the registry checks every line, the Opus
verifier tries to refute each cited P0/P1. Product code goes before tests; once `--max-usd` (40) / `--max-tokens` (20 M) is
spent no further chunk starts and the report lists the skipped ones. REPORT ONLY — nothing is fixed, no bug row is recorded.
Output: `<git-common-dir>/review-fanout/full-<head>-<ts>/full-summary.md|json` (per-reviewer, per-chunk status and model;
findings P0–P3 with state, consensus reviewers and file:line).
