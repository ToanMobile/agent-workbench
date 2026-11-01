# Four-way review — the only code review that passes (31/10/2026)

> User: "Bất cứ review nào 3 agent review là ai và 3 nó phải cùng thống nhất kết quả thì mới gọi là pass." — widened the same
> day to FOUR equal reviewers: Claude Code on Opus, Antigravity, Grok and Alibaba OCR. All four must PASS, unanimously.

**Current mode (user, 01/11/2026 09:15):** reviews run REDUCED 3-way — Claude Code (Opus) + Antigravity + OCR, unanimous 3/3 —
with `REVIEW_SKIP_REVIEWERS=grok` (Grok is back after 02/11; never skip `ocr`). The merge gate takes that run only with
`--accept-reduced-review grok` on a PR that is not machine-gated; the Stop hook never passes on a reduced PASS (see the last section).

## Who reviews (all four required, equal votes)
| Reviewer | How it runs | Vote |
|---|---|---|
| **Claude Code — Opus** | `claude -p --model opus`, read-only (Read/Grep/Glob + read-only git) | its JSON `verdict`; the model that answered (result `modelUsage`) must be Opus |
| **Antigravity** | `mcp-servers/antigravity-pm-mcp/bin/pm-review-audit.js` (pm_task_create → pm_dispatch kind=audit, `--model` pinned) | `audit-agent.json` verdict for this HEAD |
| **Grok** | `grok --prompt-file … --output-format json -m grok-4.7 --sandbox read-only --tools read_file,grep,list_dir` — no shell: `run_terminal_cmd`, edits, web and subagents are disallowed | its JSON `verdict`; `modelUsage` must show the pinned model |
| **Alibaba OpenCodeReview** | `bin/ocr-review --strict` — OCR's own LLM (full LLM mode); the delegation spec never counts | pass iff the run completed and no critical/high comment |

Plus, never optional: `registry` (bin/known_patterns.py — a known bug pattern on an added line is a P0 recurring bug) and, at depth
**deep** (≥ 50 changed lines or an auth / payment / schema / migration / secret path): a Claude Opus **security** reviewer and the
Claude Opus **verifier** (tries to refute every P0/P1).

Models: `REVIEW_CLAUDE_MODEL` (default `opus`; a non-Opus value is refused), `REVIEW_GROK_MODEL` (default `grok-4.7`) and
`REVIEW_AGY_MODEL` (default `gemini-4-argon-high`); each is part of the code hash, and the Stop hook and the merge gate drop them. The
model that really answered is recorded in each envelope (`model`, `models`), in `summary.md` and in `review_outcomes.jsonl`;
Claude not on Opus (or not reported), Grok not on its pinned model (or not reported) = that reviewer FAILED.

## Run it
```
bash .agents/devkit/bin/review-fanout.sh --base origin/<base>      # in the DevKit repo: universal-agent-devkit/bin/review-fanout.sh
```
The 4 reviewers run in parallel, each with its own timeout. Results: `<git-common-dir>/review-fanout/<code-hash>/summary.md|json`
(one verdict, deduped findings with consensus marks, inline comments). The same code is never reviewed twice (cache by code hash).
The Stop hook `hooks/review_gate.sh` runs the same thing (`--base merge-base`: merge-base(HEAD, origin/<base>), the base the merge
gate asks about, so both hash one code state) and blocks until it PASSES. It starts review-fanout with none of the session's
overrides: `REVIEW_SKIP_REVIEWERS`, `REVIEW_*_BIN`, `REVIEW_AGY_CLI`, `ANTIGRAVITY_PM_AGY`, `REVIEW_*_MODEL`, `REVIEW_DEEP_LINES`,
`REVIEW_MAX_*` and `REVIEW_REGRESSION_STATUS` are dropped — the Stop gate always judges the default 4-way review.

## PASS only when ALL hold (bin/review-merge.py)
1. Claude Code (Opus), Antigravity, Grok and OCR (and registry; security + verifier when deep) each produced a result, status `ok`,
   verdict `pass`, on the required model. Missing, failed, timed out, errored, unavailable, out of credit, wrong model, or a `fail`
   vote → **FAIL**. No fail-open, no fallback, no release after N blocks.
2. No blocking finding: a P0/P1 whose file:line + verbatim snippet is really in the code (cite-check, every reviewer) and that the
   verifier did not refute. A refuted one is downgraded to P3 and logged. A `detect` hit of a known pattern is never refutable.
3. Cost is no condition: tokens / USD are logged in `summary.json` (`usage`) and `summary.md`, never a FAIL (user 31/10/2026:
   no cost limit on the review).
4. Every accepted P0/P1 of an earlier run — an OPEN row `BUG-REV-<id>` in the regression checklist — is fixed **with a linked
   regression test that passed**: `regression_checklist.py bug-link BUG-REV-<id> <test>` then `post-fix-gate.py --run-tests`.
   Not a bug after all: `regression_checklist.py drop BUG-REV-<id> --refuted-by <run dir>`, only with a sealed run of THIS
   project (`<git-common-dir>/review-fanout/<code hash>/`, meta.repo this repo or one of its worktrees) whose verifier refuted
   that finding (it stays in review_outcomes.jsonl). The rows are read from `.agents/regression_status.json`, or — B2 of #742 —
   from `REVIEW_REGRESSION_STATUS=<absolute file outside the repo>` when a trusted caller (the merge gate's `--review-status-file`
   flag, never an inherited environment variable) sets it; its bytes are part of the code hash and a FAIL records its rows there.

## A verdict counts only when sealed, for this code and these reviewers
- review-merge.py seals `summary.json` with an HMAC (`bin/review_sign.py`, key `~/.config/agent-workbench/review.key`, outside
  every repo); an unsigned or edited summary is no verdict (`--status` says UNSIGNED).
- The seal is written only for a run's own summary in `<git-common-dir of meta.repo>/review-fanout/<code hash>/` (and `meta.common_dir`
  binds that git common dir into the sealed bytes); a summary in any other folder (`/tmp/review-fanout/<H>`) is never sealed, and a
  summary sealed in a throwaway git repo is never accepted in another repo's `review-fanout`.
- `--status` reads the summary once, checks the seal on those bytes, its `meta.code_hash` (this code state) and its
  `meta.runtime`: where claude, grok, ocr and node resolve (plus `REVIEW_AGY_CLI` / `ANTIGRAVITY_PM_AGY` when set and a raised
  `REVIEW_DEEP_LINES`). A PASS made by other reviewer executables than the asking environment runs is no verdict there
  (`NONE`, the review runs again); a FAIL stays a FAIL. The runtime is not part of the code hash, so a CLI self-update behind the
  same PATH entry keeps the verdict.

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
(summary.json `verdict: PASS`, or `PASS_REDUCED` when the merge gate carries the matching `--accept-reduced-review`); paste the
summary path into the Reviewer report. Merge policy stays autonomous (no human approval); the machine gates are this review +
`.github/workflows/pr-review.yml` (lint, typecheck, tests, semgrep, gitleaks, OCR).

## Whole-solution scan (`review-fanout.sh --full`)
`bash universal-agent-devkit/bin/review-fanout.sh --full --repo .` (`--list` shows the plan, no LLM) runs the same four reviewers
over every tracked source file, not a diff: the separate clones (mcp-servers/rea, mcp-servers/super-board), node_modules,
vendored / generated / build output, lockfiles, minified and binary files, data (.csv/.jsonl, .json > 1500 lines) and prose
(.md/.txt, docs/) are excluded. Files are chunked by module (≤ 6000 lines, `--chunk-lines`); Claude Opus, Antigravity and
Grok review each chunk, OCR reviews the whole selection once in a scratch copy, the registry checks every line, the Opus
verifier tries to refute each cited P0/P1. Product code goes before tests. No cost cap by default (cost is logged); `--max-usd`
/ `--max-tokens` (> 0) opt in to one, and once it is spent no further chunk starts and the report lists the skipped ones.
REPORT ONLY — nothing is fixed, no bug row is recorded.
Output: `<git-common-dir>/review-fanout/full-<head>-<ts>/full-summary.md|json` (per-reviewer, per-chunk status and model;
findings P0–P3 with state, consensus reviewers and file:line).

## Per-run override: a REDUCED run (user decision only)

The default is always the 4-way unanimous gate. When the user decides for a session that Grok and/or OCR cannot or should not
run (for example Grok out of credit, OCR quota reached), one run can be reduced:

```bash
REVIEW_SKIP_REVIEWERS=grok,ocr bin/review-fanout.sh            # or: bin/review-fanout.sh --skip grok,ocr
REVIEW_SKIP_REVIEWERS=grok,ocr bin/review-fanout.sh --full ...  # whole-solution scan, same override
```

- The skip is honoured only through a one-shot token that the same command line creates (`--skip`, or
  `REVIEW_SKIP_REVIEWERS` given to review-fanout itself): bound to the code hash, valid 6 h, logged in
  `<git-common-dir>/review-fanout/override.log`, consumed by the run.
- Only `grok` and `ocr` can be skipped. `claude` (pinned to Opus) and `antigravity` are always required; `--skip claude` or
  `--skip antigravity` is a usage error (exit 2). The registry, security reviewer and verifier still run as usual.
- Every remaining reviewer must still pass on the right model: missing, failed, timed out or a non-Opus Claude = FAIL.
- The summary is titled "REDUCED n-way review (<skipped> skipped by user override — not the default 4-way gate)" — today
  "REDUCED 3-way review (grok skipped …)" — lists
  each skipped reviewer as `SKIPPED … skipped by user override`, and summary.json / review_outcomes.jsonl carry
  `"reduced": true, "skipped_by_override": [...]`.
- The skip list is part of the code hash: a reduced PASS never answers the default 4-way `--status`, and `--status --skip <list>`
  reports it as `PASS_REDUCED` (exit 6), never `PASS`. The Stop hook drops the override, so a reduced run never passes a Stop;
  the merge gate takes it only with `--accept-reduced-review <list>` (exactly that skip list) on a PR that is not machine-gated.
- An agent never sets the override on its own; it is the user's call for a session.
