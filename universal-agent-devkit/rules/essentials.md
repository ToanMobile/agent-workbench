# DevKit Essentials — always loaded

The non-negotiable part of the Universal Agent DevKit, kept short so it loads in every
session. Paths are relative to the project root; `.agents/devkit/` is the DevKit itself.
Read on demand: master rules `.agents/devkit/AGENTS.md` · engineering standards
`.agents/devkit/rules/core-rules.md` · skills `.agents/skills/<name>/SKILL.md` · project
rules `.agents/local/rules/` (index loaded below; the prompt hook names the section that
matches a request — open it before editing that area) · traps `.agents/instincts.md`.

## Priority
1. The user's instruction in this task.
2. Project rules in `.agents/local/rules/` that the project marks as immutable
   (bất biến, MUST, cấm). They win over a generic DevKit rule. Say which project rule
   you followed.
3. These essentials and the master rules for anything those project rules do not cover.
4. Existing code patterns and tests.

## Before the first edit (pre-code gate)
Fill all five, or collect evidence first: (1) target + authority (verified error, necessity,
or user instruction); (2) the real source you will touch, read now — never a stale memory;
(3) every consumer of a signature/public API/shared object you change, tests included;
(4) the failure mechanism and how you will PROVE the change alters observable behaviour,
decided before editing; (5) what stays unverified. ≥2 modules, ≥3 files, >200 LOC or a risky
flow (crash, parsing, auth, navigation, lifecycle, security, module boundary): review the
plan before code; approval boundaries (auth, billing, destructive migration, global
architecture, commit/push/release, rule/hook files) need the user's go-ahead.

## Non-negotiables
- **No fabrication**: no invented paths, APIs, line numbers, metrics, versions, root causes,
  test results or past actions. Say "checking X" instead of a provisional conclusion.
- **Paired executable oracle for every bug fix** (no waiver): run a test at the real failure
  boundary and see it RED before changing production code, the same test GREEN after.
  A compile is proof only when the defect is a compile failure.
- **Evidence per claim**: a structural fact → fresh source; a metric/version → a tool
  measurement; "fixed/works" → discriminating before/after evidence; "X is unaffected" → a
  search scaled to the risk; a hypothesis is labelled as one; unknown is said.
- **Anti-loop**: two failed fixes for one root cause → stop, drop the hypothesis, change approach.
- **Protect working code**: touch it only for a real error, a real necessity, or an explicit
  instruction. Surgical diffs; no drive-by refactors, formatting sweeps or placeholder code
  (`// ... existing code ...`); keep public signatures backward compatible.
- **Git**: commit, push or open a PR only when the user asks. Never commit secrets
  (`.env`, keystores, `local.properties`, `google-services.json`, tokens); mask them in proof.
- **Done means verified**: run the post-fix gate (`postfix-gate --run-tests`, exit 0 only) and
  a fresh-context review before calling work finished; the Stop hooks enforce this.

## Engineering musts (details: `.agents/devkit/rules/core-rules.md`)
- No O(N²) on dynamic data where a map/set does; no allocations in hot loops.
- No I/O, network, DB or heavy parsing on the main/UI thread.
- Every stream/cursor/connection closed (`use`/try-with-resources/`finally`); listeners,
  observers, timers and scopes released with their lifecycle; no static UI/Context refs.
- No empty `catch`/`except: pass`; log with context or rethrow.
- Explicit network timeouts (connect ≤10 s, read ≤15 s); retry only idempotent calls, with
  backoff + jitter; an idempotency key on payment/order writes.
- No raw `console.log`/`println`/`printStackTrace` in production; structured logs with PII
  masked (tokens, passwords, OTP, IDs, card and phone numbers).
- Every schema change ships a migration and a migration test; never a destructive drop in LIVE.
- UI: tokens from `DESIGN.md`, touch targets ≥48 dp (≥44 px web), immediate feedback, and
  expensive actions disabled/debounced ≥1000 ms after the first tap.

## Working style
- Pick skills from context yourself; never ask the user to type a slash command.
- Answer in the user's language (Vietnamese when they write Vietnamese); identifiers,
  commands, paths and commit subjects stay English.
- Reports open with three lines: status (XONG / CHƯA XONG / CHỜ DUYỆT), what the user gets,
  next step; stay short; UI/device work carries a screenshot, CLI/backend work real output.
- Long session or a big refactor ahead: checkpoint and compact instead of filling the window.
- Traps from past bugs arrive with each request (`.agents/instincts.md`); read the named entry.
