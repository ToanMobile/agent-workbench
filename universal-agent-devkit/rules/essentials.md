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
- **Done means verified**: run the post-fix gate
  (`python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full`, exit 0 only) and
  attach a real proof PNG from this turn before the reply may open with XONG.
  The Stop hooks enforce the gate on hosts that have them. They do not take the screenshot;
  on Claude Code `proof_gate.sh` refuses a reply opening with XONG that names no fresh proof PNG.

## Every prompt (standing law)
Applies to Claude Code, Gemini CLI, Antigravity, Codex, Cursor and Grok. Do this in the
same turn, before answering. A missing step opens the reply with CHƯA XONG and stops.
Do not write XONG, PASS, đã fix, or đã xong without both items in step 5.

1. Read `AGENTS.md`, `.agents/context/essentials.md`, `.agents/context/profile-rules.md`,
   `.agents/context/rules-index.md`, and every `.agents/local/rules/` file the index names.
2. A code or bug prompt: run the failing oracle and see RED before editing production,
   then the same oracle GREEN after. Keep the command log and the exit code.
3. From the repo root, once:
   `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full`
   Exit 0 is required. Any other exit: paste the last 30 log lines, fix, and repeat this
   step. A dry-run, `--help`, or a single Gradle test does not replace this command.
4. A proof image is blocking, same rank as exit 0.
   - Serial: `.antigravity-pm.json` → `proof.providers.device.serial`.
   - Never capture a serial listed in `.adb-denylist` or forbidden by a project rule
     marked cấm / bất biến. An immutable project rule wins over this section.
   - Declared serial offline: CHƯA XONG. Do not switch to another device.
   - No declared serial and no denylist: use the one device in state `device` from
     `adb devices -l`, and name that serial.
   - No allowed device online: CHƯA XONG. Do not draw, reuse an old image, or substitute
     a test XML.
   - Install the build this turn produced, perform the task until the screen shows success.
   - `adb -s <SERIAL> exec-out screencap -p > reports/proof-<yyyyMMdd-HHmmss>.png`
   - Real PNG, larger than 8 KB, mtime newer than the start of the turn. Put the image
     in the reply with its path and serial.
5. The reply may open with XONG only when this turn has exit 0 from step 3 and the PNG
   from step 4. Line 1: XONG or CHƯA XONG. Line 2: what the user gets. Line 3: gate exit
   code, image path, serial.

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
  next step; stay short. XONG also requires the full-gate exit 0 and the proof PNG in
  "Every prompt".
- Long session or a big refactor ahead: checkpoint and compact instead of filling the window.
- Traps from past bugs arrive with each request (`.agents/instincts.md`); read the named entry.
