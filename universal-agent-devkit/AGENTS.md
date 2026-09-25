# AGENTS.md — Master Rules & Universal Multi-Agent Architecture

Shared baseline and **Single Source of Truth (SSOT)** for 5 core AI coding platforms: **Claude Code (Anthropic)**, **OpenAI Codex / ChatGPT Canvas**, **Antigravity (Google / Gemini)**, **Cursor IDE**, and **Grok (xAI)**.

---

## 1. Project Architecture & Modularization

**Project Type:** Modular Architecture & Clean Engineering Practices.
Every repository adopting this framework follows Clean Architecture, Unidirectional Data Flow, strict separation of concerns, and testability.

### 1.1 Architecture Baseline
- **Core Layer:** Shared primitives, domain models, utility abstractions, dispatchers, analytics, test rules.
- **Feature Layer:** Isolated feature modules/packages, UI components, ViewModels/StateHolders.
- **Infrastructure / Data Layer:** Storage, database, network clients, external integrations.
- **Engine / Libs Layer:** Performance-critical algorithms, parsers, low-level bindings.

---

## 2. Slash Commands & Skills Router

Skills live in `skills/` (source of truth); `.agents/skills/` and `commands/` link to them, and the DevKit plugin loads them directly:

| Slash Command / Alias | Canonical Skill Path | Description / Trigger | Primary Scope |
|---|---|---|---|
| `/qc`, `/check` | [qc](skills/qc/SKILL.md) | Detect the build tool, run tests/lint; Metalava & translation gates on Android/Gradle | Test / Build Gates |
| `/deploy`, `/build` | [deploy](skills/deploy/SKILL.md) | Android/Gradle only: APK/AAB builds, ProGuard/R8, signing, release checks | Build / Deploy |
| `/fixbugs`, `/fix` | [fixbugs](skills/fixbugs/SKILL.md) | Standard bug-fixing with Paired Executable Oracle (RED→GREEN) & Crashlytics/ANR triage | Repro / Fix / Verification |
| `/plan` | [spec-driven-development](skills/spec-driven-development/SKILL.md) | Spec-driven plan for changes ≥3 files or ≥2 modules | Spec / Plan / Tasks |
| `/scan` | [security-checklist](skills/security-checklist/SKILL.md) | Security audit: Input validation, URI/Permissions, Secrets, Auth | Security Gate |
| `/tdd` | [tdd-workflow](skills/tdd-workflow/SKILL.md) | TDD Workflow: Write failing RED test before implementation logic | Test-First |
| `/verify`, `/done` | [verification-before-completion](skills/verification-before-completion/SKILL.md) | Verification gate before declaring task completion | Verification Gate |
| `/conflict` | [merge-conflict-resolver](skills/merge-conflict-resolver/SKILL.md) | Resolve Git merge / rebase / cherry-pick / stash conflicts | Git 3-way merge |
| `/handoff` | [session-handoff](skills/session-handoff/SKILL.md) | Transfer work-in-progress context across sessions | Session Handoff |
| `/graph`, `/codebase-memory` | [codebase-memory](skills/codebase-memory/SKILL.md) | Explore codebase, trace call flow, blast radius, AST knowledge graph & Cypher | Codebase Navigation & Graph |
| `/plan-tests`, `/qa-review` | [qa-review](skills/qa-review/SKILL.md) | Audit diff before PR, acceptance criteria, test scenario matrix | Code / PR Review |
| `/review-code`, `/ocr`, `/open-code-review` | [open-code-review](skills/open-code-review/SKILL.md) | Alibaba OpenCodeReview: Deterministic line resolver, file bundling, code audit | Automated Diff Review |
| `/visual`, `/qa-visual` | [qa-visual](skills/qa-visual/SKILL.md) | Automated screenshot capture and DOM layout audit | Visual UI QA |
| `/audit-gate`, `/postfix-gate` | [audit-gate](commands/audit-gate.md) | Post-fix static diff gate (secrets, placeholders, dependencies, perf, swallowed errors, raw logs) + matrix regression tests | Post-Fix Gate |

**QA ladder:** `/plan-tests` → `/review-code` → `/check` → `/done` + `/audit-gate`. Deprecated stubs (removed in 1.2.0): `/review` → `/plan-tests`, `/qa` & `/test` → `/check`, `/bugs` & `/crashlytics` → `/fix`.

---

## 3. Role & Language

- **Default Communication Language:** User-facing replies are in the **user's language** (Vietnamese when they write Vietnamese, English otherwise), concise, and evidence-backed — the same rule as `rules/essentials.md` "Working style".
- **Language Switch Option (Vietnamese / Multilingual):** When `--lang=vi` is configured, or whenever the user communicates or requests in **Vietnamese** (or another language), the agent seamlessly responds in that preferred language.
- Code identifiers, commands, file paths, and commit subjects ALWAYS stay in **English**.
- **TASK COMPLETION CARD:** After every progress update, checkpoint, reviewer finding, or failed investigation path, automatically continue the remaining work until the full assigned scope reaches a valid terminal state. Progress updates are not final responses; never prompt the user to type `continue`.

---

## 4. Priority

1. User instruction in the current task.
2. This `AGENTS.md` (Master Rules & Universal Multi-Agent Architecture).
3. Project contracts, commands, and memory — including the project tier rules in `.agents/local/rules/` (the project's own rules, moved there by the DevKit installer). Read them before editing code. They add project and domain rules on top of this file; where one contradicts §6 or `rules/core-rules.md`, the DevKit rule wins and the conflict is reported to the user.
4. Existing code patterns and tests.

---

## 5. Pre-Code Gate (Run before the first Edit/Write)

Five boxes. If any cannot be filled, you are **NOT** allowed to write code yet — collect evidence or escalate as a labeled hypothesis:

1. **Target + authority** — what you change and which authority covers it (a: verified error, b: necessity, c: user-instructed).
2. **Real source read** for the exact area you touch — read the file directly, never trust stale cache.
3. **Consumer list** if you touch a signature, base-class member, public API, or shared object — **including tests**.
4. **Failure mechanism + how you will prove the fix changes observable behavior** — decided BEFORE editing.
5. **Residual** — what will stay unverified, and why.

Risky flow (crash fix, parsing, auth, navigation, lifecycle, security/privacy, module boundary, 2+ modules): boxes 1–5 must be reviewed BEFORE code is written.

### 5.1 Plan Convergence & Human Gates
**Review the PLAN to convergence before writing code. Code is the LAST step, not the first.**
Required order: plan → reviewer approves the *plan* → gaps found → revise plan and review AGAIN → no gaps left → **GATE 1: User approves the plan** → **write the RED test FIRST** → only then code → green + review on diff → **GATE 2 (Narrow Scope)**.

- **Gate 1:** Applies to work crossing planning threshold (≥2 modules, ≥3 files, >200 LOC net diff, or risky flow) or approval boundary.
- **Gate 2 (Strict Narrow Scope):** Applies ONLY when touching:
  (a) Approval boundary (auth policy, billing, destructive migrations, global architecture);
  (b) Attack surface narrowly defined by security gates;
  (c) Irreversible external action (commit/push/PR, release/publish, deleting shared device/server state);
  (d) Meta-tooling or rule files (`AGENTS.md`, `rules/`, `hooks/`, the project's own QA scripts).
  Inside this scope, Gate 2 is a full STOP. Outside this scope, issue the verdict and carry on.

---

## 6. Non-Negotiable Rules

- **No fabrication:** Do not invent file paths, APIs, line numbers, metrics, dates, versions, root causes, test results, or past actions.
- **Verify BEFORE speaking:** Do not state conclusions or diagnoses before evidence is collected — say "checking X" instead of provisional claims.
- **PAIRED EXECUTABLE ORACLE (bắt buộc cho mọi bug fix — không có waiver / mandatory with no waiver):** Trước khi sửa bất kỳ dòng code production nào, phải thực thi một oracle ở failure boundary thật và quan sát RED; sau khi sửa, thực thi lại cùng oracle và quan sát GREEN. Compile chỉ hợp lệ khi chính acceptance là lỗi compile/build failure.
- **Discriminating Evidence:** Root cause requires discriminating evidence (pass/fail contrast), not mere source-reasoning.
- **Statement Decision Table:**
  - **C1:** Structural fact from source → Fresh source/graph output.
  - **C2:** Version/metric/hash/docs → Tool measurement or official doc.
  - **C3:** Consequence/runtime/fix works → Discriminating evidence cited inline.
  - **C4:** Negative/scope claim ("X unaffected") → Broad search scaled to claim risk.
  - **C5:** Past action / fix outcome → Exit-0 tool call + before/after repro.
  - **C6:** Preference/trade-off → Labeled suggestion with verified reasons.
  - **C7:** Hypothesis → Labeled hypothesis + discriminating test needed.
  - **C8:** Future estimate → Labeled "unverified estimate".
  - **C9:** Unknown / data missing → Explicit statement of missing data/tool.
- **Anti-Loop:** After 2 failed fixes for the same root cause, STOP and abandon the failing hypothesis; change approach.
- **Protection of Working Code:** Working code is protected. Touch only with: (a) real evidence of error, (b) unavoidable necessity for the task, or (c) explicit user instruction.
- **Surgical Changes:** No drive-by refactoring, formatting sweeps, or gratuitous abstractions.

---

## 7. Multi-Agent Integration Guide

In an installed project, `AGENTS.md` is the project's **only** instruction file (no `CLAUDE.md`, no `GEMINI.md`): the project's own text plus the DevKit block, which loads three generated real files from `.agents/context/` — `essentials.md` (`rules/essentials.md`), `profile-rules.md` (the profile's `RULES.md`) and `rules-index.md` (one line per section of `.agents/local/rules/`). They are copies, not links: an `@` import whose real path is outside the project is not loaded. Everything agent-related lives in `.agents/`; this DevKit is `.agents/devkit/`, so a path in this file such as `rules/core-rules.md` or `skills/qc/SKILL.md` is `.agents/devkit/rules/core-rules.md` there (skills are also at `.agents/skills/<name>/`). What is **enforced by hooks** (runs without the model choosing to) differs per platform:

| Platform | Reads the rules | Enforced by hooks |
|---|---|---|
| **Claude Code** | `AGENTS.md` (read because the project has no `CLAUDE.md`; its `@` lines expand), `.claude/commands`, `.claude/agents` | All DevKit hooks (`.claude/settings.json`): session/prompt context, git, device (Bash and the `replicant-mcp` MCP tools) and destructive-`rm` guards, the worktree guard (`worktree_guard.sh`: an agent that works in a git worktree cannot write into the main checkout, §7.1), read-before-edit, regression tests, test/“fixed” evidence, fresh-context review, secrets, XONG needs this turn's full-gate exit 0 and, for app source on a profile with a screen, a proof image; XONG and any turn that ran `git push` need the 4-item acceptance report |
| **OpenAI Codex** | `AGENTS.md` as plain text (no `@` expansion): its DevKit block lists the rule files to open | `.codex/hooks.json` via `hooks/agent_bridge.sh`: session/prompt context, git, device & `rm` guards on shell commands, regression tests on Stop |
| **Gemini CLI** | `AGENTS.md` through `context.fileName` in `.gemini/settings.json` (its `@` lines expand), `.agents/skills`; symlink mode adds the DevKit folder to `context.includeDirectories` so `.agents/devkit/` can be read on demand | `.gemini/settings.json` via the bridge: same set as Codex |
| **Cursor** | `AGENTS.md` + the always-applied rule `.cursor/rules/universal-agent-devkit.mdc` (`@`-includes the core, profile and project rules) | `.cursor/hooks.json` via the bridge: session context, git, device & `rm` guards, regression tests on stop |
| **Grok** | The same `AGENTS.md` as every other agent. No Grok adapter and no `.grok/` directory | No DevKit files of its own. It runs the Claude hooks from `.claude/settings.json` (and sees the skills and commands installed for the other agents), but it discards UserPromptSubmit output and its transcript is not Claude's. The hooks detect it (`hooks/devkit_harness.py`: camelCase payload, `GROK_HOOK_EVENT`, its `updates.jsonl` transcript) and never trap it: the prompt hook records no `REPORTED` bug row; `testsourceset_gate.sh` and `regression_gate.sh` compile/test once per unchanged tree per session, block at most 3 times per session (`TESTSOURCESET_GATE_MAX_SESSION_BLOCKS`, `REGRESSION_GATE_MAX_SESSION_BLOCKS`; a pass resets it) and then let it stop with a `systemMessage` that says the gate is still not green; its session-end Stop runs nothing. The same session cap applies to any Stop without a usable Claude transcript (bridged agents too) |
| **Antigravity** | `AGENTS.md` and `GEMINI.md` as plain text — no `@` import is expanded (measured 2026-09-25), so the DevKit block carries the essentials in full; `.agents/skills` | none (no hook API) — rules only |

Every platform also gets the git **pre-commit** gate (`agent-kit githooks install`, installed by `agent-kit init` in git projects). Hooks that read Claude's transcript (review, test evidence, claims) exist only on Claude Code.
- **Living regression checklist — automatic parts and their off switches** (`=0` turns one off; `.agents/CHECKLIST.md`, `docs/plans/regression-checklist-v3.md`):

  | Switch | What it does | Hook / tool |
  |---|---|---|
  | `BUG_CAPTURE` | bug prompt → `REPORTED` row (under every agent; not agent/harness prompts by their content: "You are …" openings, tool/JSON schemas, long instruction blocks) | UserPromptSubmit |
  | `INBOX_WATCH` | new `.agents/INBOX.md` lines → context, once each | UserPromptSubmit |
  | `BUG_LINK_REMINDER` | hold Stop once when this session's bug/REQ has no test | Stop (`test_evidence_gate.sh`) |
  | `AUTO_LINK` | link bug ↔ test on one-to-one RED→GREEN evidence (🤖) | Stop |
  | `RED_PROOF` | sandbox RED-proof of this session's bugs/REQs (background) | Stop, `scripts/red_proof.py` |
  | `FLAKY_RETRY` | re-run a failing suite once: a test failed then passed → 🔁 FLAKY (still FAIL); the build broke with no test failing then passed → PASS flagged `infra_retry` | `post-fix-gate`, nightly, stale re-run |
  | `INFRA_RETRY` | a run that lost its results store (Gradle `EOFException` / `results.bin`) is infrastructure: re-run once whatever its length, never marked 🔁 FLAKY | `post-fix-gate` |
  | `TEST_RUN_LOCK_WAIT_S` (seconds, default 900) | how long a test run waits for `.claude/audit-gate/test_run.lock`, the per-project lock the gate, stale re-run and nightly hold so two runs never share one build dir; past it the run reports the lock, never runs side by side | `post-fix-gate`, `scripts/stale_rerun.py`, nightly |
  | `STALE_RERUN` | re-run light STALE suites in the background | SessionStart, `scripts/stale_rerun.py` |
  | `EVIDENCE_KEEP` | logs kept per test (default 10) | `post-fix-gate` |
  | `NIGHTLY_NOTIFY` | notification when a row turns red | `scripts/nightly.py` |
- **Synchronization:** Run `./bin/agent-kit sync` anytime skills, commands, or hooks are updated.

### 7.1 Parallel Agents — One Git Worktree per Agent

Two agents editing one working tree overwrite each other's files, mix their diffs in `git status` and break each other's builds mid-run. When two or more agents change code at the same time, each gets its own worktree and branch.

- **Create:** `agent-kit worktree add ../<repo>-<task> [<feat|fix>/<task>]` from the main checkout does the whole set-up below in one step (branch default `feat/<folder>`), then open the agent in that directory. Claude Code can instead start the subagent with `isolation: "worktree"` (Agent tool) or switch the session with `EnterWorktree`; the harness creates the worktree and removes it when nothing changed, and the set-up below is then yours to do. Keep worktrees outside the repo, so the repo's build, lint and search never scan them and no `.gitignore` entry is needed.
- **Set up before the first build** — a new worktree holds tracked files only:
  - Untracked local config (`local.properties`, `.env`, `google-services.json`, `keystore.properties`) is missing: copy it from the main checkout, never commit it (`rules/core-rules.md` §1).
  - A symlink-mode DevKit install is untracked as well, so `.claude/`, `rules/`, `skills/` are missing: run `agent-kit init` inside the worktree. Its files are untracked there (and `.gitignore` gains the DevKit block when the project has not committed it) — keep them out of what you bring back.
  - The git pre-commit gate is shared by every worktree of the repo; nothing to install.
- **Worktree guard** (`hooks/worktree_guard.sh`, Claude Code, PreToolUse on Bash and Edit|Write|MultiEdit|NotebookEdit): once a session or subagent has a worktree, a write into the main checkout of the same repo is blocked (exit 2) — an Edit there, a redirection, a `cp`/`mv`/`rm`/`sed -i`/`dd of=` target, a git write (`commit`, `checkout`, `stash push/pop`, …) or a build tool run there. Reads of the main checkout, `git stash list`, `python3 -c …` and copies to `host:` pass, and so do `.claude/agent-memory/`, `.claude/audit-gate/` and `.agents/local/memory/`, which exist only in the main checkout. A worktree is declared by `DEVKIT_WORKTREE=<path>`, by the harness (`isolation: "worktree"`: the subagent's `worktreePath`, or its transcript's first `cwd`), or by the session having STARTED in a worktree (the first `cwd` of its transcript) — never by a later `cd`: the leader may look into a worktree, then edit, `git merge` or `git apply` in the main checkout. A subagent whose prompt only names a worktree made by `agent-kit worktree add` gets a warning, not a block. Off: `WORKTREE_GUARD=0` (logged in `.claude/audit-gate/worktree_guard.log`).
- **One device, one agent:** a physical device or emulator serves one worktree at a time. Run device work one worktree after another, each with `adb-safe-exec.sh -s <SERIAL>`.
- **Accept a worktree only on its own gate run:** `cd <worktree> && CLAUDE_PROJECT_DIR="$PWD" python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full` → exit `0`, plus the proof PNG when `rules/essentials.md` ("Every prompt", step 4) requires one. The gate reads `CLAUDE_PROJECT_DIR` before the git root; left pointing at the main checkout, it audits the main checkout instead.
- **No automatic merge:** the leader reviews each worktree's diff like any other change (§5, §6), then brings it back. Without an explicit request to commit (`rules/core-rules.md` §1), bring it as a patch — in the main checkout: `agent-kit worktree diff <worktree> | git apply --3way` (new and deleted files and the branch's commits included, the DevKit set-up left out; `git add -A` would carry the DevKit files, which already exist in the main checkout, and the apply fails). When the user asked for commits, merge the branch instead. Conflicts go through `/conflict` (`merge-conflict-resolver`); commit and push stay behind Gate 2 (§5.1 c).
- **Clean up:** `agent-kit worktree remove <path>` removes a worktree made by `worktree add` once every uncommitted change in it is also in the main checkout (the branch and its commits stay). Otherwise `git worktree remove <path>` for a worktree with no changes left. One that still holds changes, and its unmerged branch, need `git worktree remove --force` / `git branch -D`, which the git guard blocks: once its changes are safely in the main checkout, ask the user to run them.

---

## 8. Universal Zero-Regression & Autonomous Intent Router

Synthesizing the foundational methodologies of `obra/superpowers` (Anti-Rationalization, Rulings-not-stalls, strict TDD), `alirezarezvani/claude-skills` (Surgical Scoping, Context-First), and `alibaba/open-code-review` (Deterministic Line Resolution, Zero-Noise Review):

### 8.1 Autonomous Pipeline (Zero-Effort for Developer)
Whenever the user asks to fix a bug, refactor code, or change behavior in a complex codebase, the agent MUST automatically execute this multi-phase loop without requiring manual skill invocation:

1. **Anti-Rationalization Gate:** STOP any thought of "this is a trivial fix" or "I don't need tests". Every change to shared flows, central dispatchers, base classes, or middleware carries high regression risk.
2. **Blast Radius & Call-Site Audit:**
   - Automatically inspect 100% of inbound callers using AST / MCP graph (`trace_path`) or grep BEFORE modifying shared functions.
   - Map all dependent components across modules, listeners, and background services.
3. **Surgical Scope (Zero Collateral Damage):**
   - If an issue occurs on a specific target client, tenant, platform, or app, isolate the fix strictly inside that condition (e.g., Strategy pattern, adapter, or `if (isTargetScope(...))`).
   - Leave default shared logic for other consumers 100% untouched.
   - This is for behaviour that must differ per target. A defect every caller hits is fixed once, at the shared root (`rules/essentials.md` "Lazy senior"); do not copy a guard into each target branch.
4. **Preserve Immutable Platform & Legacy Guards:**
   - Never delete or relax legacy `if (...)` conditions established for OS versions, platform quirks, or historical edge-case fixes.
5. **Two-Way Regression Verification:**
   - Execute the targeted test for the fix (RED → GREEN).
   - Re-run the existing module test suite to verify all existing tests remain 100% GREEN. Never alter existing assertions to mask regressions.
6. **Deterministic Review with OpenCodeReview (`ocr`):**
   - If the `ocr` CLI is installed (the DevKit does not install it), run `ocr review` or `ocr delegate preview` on the diff; otherwise use the `open-code-review` skill or a `principal-code-reviewer` subagent. On Claude Code the Stop hook `review_gate.sh` requires one of these after the last code edit.

> **Modular Domain Profiles:**
> Domain-specific and project-specific rules (such as Automotive Hardware, FlymeAuto, or CAN Bus specifics) are kept isolated in `profiles/` (e.g. `profiles/automotive/`) to keep the DevKit core 100% universal and domain-agnostic.
>
> | Profile | Domain | Skills left out (`exclude_skills`) |
> |---|---|---|
> | `android` | Compose, Coroutines, Vitals | — |
> | `automotive` | AAOS, CAN, Vehicle HAL | `unity-gc-audit` |
> | `ios` | Swift 6, SwiftUI | Android/Unity skills |
> | `web` | TypeScript, React/Next.js | Android/Unity skills |
> | `backend` | API services (Python/Go/Rust/Node) | Android/Unity skills + `qa-visual` |
> | `game` | Unity 6, Zero-GC | Android skills |
> | `voice-assistant` | edge audio AI | `compose-recomp-audit`, `unity-gc-audit` |
> | `universal` | anything else | Android/Unity skills |
>
> Switch with `agent-kit profile <id>`; the active one is linked at `.agents/active-profile`.

### 8.2 Routing Matrix — which skill for which task (the agent picks from context)
The agent MUST trigger these skills from context by itself and NEVER ask the user to type a slash command (rule and skill chains: `rules/core-rules.md` §16). Choosing a skill is the model's job — no hook forces it. What hooks DO force is listed in §7 and marked **[hook]** below.

| Giai Đoạn Vòng Đời | Kỹ Năng Tự Động Kích Hoạt | Ngữ Cảnh / Tình Huống Kỹ Thuật Tự Động Kích Hoạt | Hành Động Tự Động Của Agent |
|---|---|---|---|
| **0. Gateway & Context** | `context-enricher` | **MỌI YÊU CẦU ĐẦU VÀO / PROMPT NGẮN CỦA USER** | **[hook]** `prompt_context.sh` (UserPromptSubmit) tự chèn: loại việc, yêu cầu ngầm định (debounce ≥ 1000ms, a11y ≥ 48dp, main thread, PII), bẫy instincts khớp kèm số dòng, và luật paired RED→GREEN khi sửa bug; prompt tả bug được tự ghi thành dòng REPORTED trong regression checklist (`agent-kit bugs add/link/drop`); `session_context.sh` (SessionStart) nạp mục lục instincts + trạng thái checklist. Agent vẫn tự dò AST/Graph. |
| **0. Gateway & Context** | `session-handoff` | Phiên làm việc dài, context window > 50%, trước refactor lớn | Tự động tóm tắt tiến độ (checkpoint), dọn sạch ngữ cảnh thừa, chống suy thoái năng lực suy luận. |
| **1. Discovery & Arch** | `codebase-memory` | Khám phá dự án, tìm symbol, hàm, route, truy vết blast radius, Cypher | **SSOT ĐỒ THỊ:** Tự động resolve symbol, trace inbound/outbound callers, truy vấn Cypher, hoặc fallback Read/Grep an toàn. |
| **1. Discovery & Arch** | `spec-driven-development` | Tính năng mới phức tạp chạm $\ge 2$ module, $\ge 3$ files hoặc > 200 LOC | Tự động soạn thảo spec kỹ thuật, phân tích assumptions và edge cases trước khi code. |
| **1. Discovery & Arch** | `grill-plan` | Kế hoạch có rủi ro kiến trúc cao, thay đổi shared flow | Tự động phản biện đối lập, stress-test kế hoạch, tìm lỗ hổng kiến trúc trước khi code. |
| **1. Discovery & Arch** | `documentation-and-adrs` | Quyết định kiến trúc, chọn pattern/thư viện, đổi data model | Tự động tạo hồ sơ ADR (Architecture Decision Record) lưu trữ rationale và trade-offs. |
| **1. Discovery & Arch** | `deep-module-design` | Thiết kế interface, seam kiểm thử, phân tách trừu tượng | Tự động đánh giá interface sâu, tính đóng gói, Dependency Inversion (DIP) và mockability. |
| **2. Dual-Agent Orchestration** | `giao` | Tác vụ code phức tạp khi Claude Code đóng vai Leader PM | Tự động kích hoạt quy trình 7 giai đoạn: Task ➔ Plan ➔ Review ➔ Implement ➔ Audit ➔ Test ➔ Proof ➔ Accept. |
| **3. Implementation & TDD** | `fixbugs` | Sửa mọi loại lỗi / bug, Crashlytics, stack trace, ANR traces.txt | **PAIRED ORACLE & INCIDENT TRIAGE:** Bóc tách stack trace, phân loại failure mechanism, bắt buộc Paired Oracle (RED ➔ GREEN). |
| **3. Implementation & TDD** | `tdd-workflow` | Viết logic nghiệp vụ mới có thể kiểm thử (testable) | Tự động viết unit/integration test trước khi viết code logic (RED-first). |
| **3. Implementation & TDD** | `incremental-implementation` | Thay đổi nhiều file hoặc task khó kiểm chứng trong 1 bước | Tự động chia nhỏ thành các bước phẫu thuật tăng dần, kiểm chứng liên tục từng bước. |
| **3. Implementation & TDD** | `deprecation-migration` | Sunset API cũ, xóa code cũ, di trú schema CSDL | Tự động rà soát callers, lập kế hoạch di trú 3 pha (Soft ➔ Hard ➔ Sunset), bảo toàn tương thích. |
| **3. Implementation & TDD** | `security-checklist` | Thay đổi Intent, URI, auth, permissions, WebView, secret | Tự động rà soát bề mặt tấn công, nguyên tắc quyền tối thiểu, che giấu credential trần. |
| **3. Implementation & TDD** | `observability-instrumentation` | Thêm log, metric, trace, chẩn đoán lỗi thiếu dữ liệu | Tự động chuẩn hóa structured logging, phân cấp DEBUG/INFO/ERROR, mask 100% PII. |
| **3. Implementation & TDD** | `writing-skills` | Tạo mới hoặc chuẩn hóa Skill / Rules cho Agent | Tự động tuân thủ cấu trúc YAML frontmatter, mô tả ngữ cảnh kích hoạt và quy chuẩn kebab-case. |
| **4. Device & Visual QA** | `android-real-device-qa` | Kiểm thử Android trên thiết bị thật / máy ảo emulator | Tự động đo FPS SurfaceFlinger, dump view hierarchy XML, triage ANR logcat, tombstone native crash, quét DEX. |
| **4. Device & Visual QA** | `compose-recomp-audit` | Tối ưu Compose 120 FPS, loại bỏ Recomposition thừa | Tự động audit tính ổn định tham số (@Stable/@Immutable), derivedStateOf, deferred state reads, LazyColumn keying. |
| **4. Device & Visual QA** | `unity-gc-audit` | Triệt tiêu GC Alloc trong Unity 6, hướng tới Zero-GC Update loop | Tự động quét LINQ/boxing trong frame loops, NonAlloc physics APIs, cache coroutines, chống rò rỉ C# events khi đổi Scene. |
| **4. Device & Visual QA** | `qa-visual` | Kiểm tra giao diện, audit layout, chống vỡ màn hình | Tự động audit tràn khung, lệch align, touch target >= 48dp, upload screenshot lên R2. |
| **4. Device & Visual QA** | `qa-review` | Chuẩn bị trước khi tạo PR / bàn giao Tech Lead | Tự động chất vấn diff, tạo acceptance criteria kiểm chứng được và dựng ma trận test scenario. |
| **5. Acceptance & Delivery** | `merge-conflict-resolver` | Xung đột git khi merge, rebase, cherry-pick | Tự động phân tích AST và ngữ cảnh để giải quyết xung đột mà không làm mất mát logic. |
| **5. Acceptance & Delivery** | `qc` | Chạy bộ kiểm thử tự động, lint check, unit test | Phát hiện build tool rồi chạy test runner tương ứng; Translation gate và Metalava API check cho Android/Gradle. |
| **5. Acceptance & Delivery** | `open-code-review` | Soát mã nguồn tự động trước khi bàn giao | Tự động chạy phân tích hunk tất định (Alibaba OCR), quét rò rỉ bộ nhớ và code lười biếng. |
| **5. Acceptance & Delivery** | `verification-before-completion` | Trước khi tuyên bố Xong / Pass / Hoàn tất | Chạy `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full` (exit 0) và gắn PNG nghiệm thu của chính lượt đó trừ khi thay đổi chắc chắn không lên màn hình (profile backend lúc đầu lượt, hoặc mọi thứ đổi từ HEAD đầu lượt chỉ là test / Markdown ở gốc / thư mục tooling ở gốc — danh sách đủ ở `rules/essentials.md` bước 4: chỉ cần cổng). Luật đứng: `rules/essentials.md` mục "Every prompt". **[hook]** Khi có ma trận (`.agents/regression_matrix.active.json`), Stop hook `regression_gate.sh` tự chạy cổng; `test_evidence_gate.sh` chặn "đã fix" không có cặp test ĐỎ→XANH trong phiên. Hook không chụp ảnh; **[hook]** `proof_gate.sh` (chỉ Claude Code) chặn câu trả lời mở bằng XONG khi lượt đó thiếu cổng `--full` exit 0 trên code hiện tại hoặc thiếu `reports/proof-*.png` thật chụp trong lượt. |
| **5. Acceptance & Delivery** | `deploy` | Đóng gói APK/AAB, kiểm tra signing, xuất bản release (chỉ Android/Gradle) | Tự động kiểm tra chứng chỉ ký (signing key), version bump và sẵn sàng phát hành. |


### 8.3 The 10 Review Councils
The DevKit provides 10 council subagent prompts in `agents/councils/` (5 focus areas each); a profile's `active_councils` selects the ones that apply:
- **Council 1 — Subsystem & Shared Flow Isolation (5 Agents):** Shared flow surgical isolation, legacy platform guards preservation, shared resource & session arbitration, hardware event & interrupt throttling, multi-window & responsive boundary.
- **Council 2 — Architecture & Blast Radius (5 Agents):** AST inbound caller tracing, circular dependency detection, clean layered architecture, API contract breaking, dead code zombie scanning.
- **Council 3 — Zero-Defect & TDD (5 Agents):** Paired executable oracle enforcement, regression matrix orchestration, assertion integrity, flaky test hunting, mutation coverage.
- **Council 4 — Deterministic Code Review (Alibaba OCR) (5 Agents):** Hunk position resolver (`resolver.go`), semantic file bundling, zero-noise precision filtering, suggested diff verification, delegation bridge.
- **Council 5 — Security & Vulnerabilities (5 Agents):** Raw secret/credential leak hunting, IPC/Intent security, data exfiltration detection, OWASP Mobile & API Top 10, tamper defense.
- **Council 6 — Game Engine & 3D Assets (Unity & Blender) (5 Agents):** Mono GC memory leaks, draw call batching & UI canvas, scene hierarchy integrity, Blender poly count & mesh topology, game asset memory budget.
- **Council 7 — Performance, ANR & Thermal (5 Agents):** Main thread blocking (>16ms/ANR), frame drop jank, battery drain & thermal throttling, bitmap OOM prevention, Binder transaction limits (1MB).
- **Council 8 — Tiered Memory Governance (L0-L3) (5 Agents):** Session trace harvesting, recurrence pattern promotion, on-demand domain context routing, master rulebook bloat control, anti-rationalization policing.
- **Council 9 — Solo Dev & Operational Process (5 Agents):** Anti-spam click & debounce verification, mandatory acceptance screenshot with PASS badge, audit trail logging, DEMO vs LIVE isolation, fail-closed receipt signing.
- **Council 10 — Standards Compliance & Delivery (5 Agents):** Bidirectional requirement traceability, protocol & data stream integrity, accessibility & UX visual safety, offline resilience & fault tolerance, Tech Lead handover formatting.

### 8.4 Engineering Excellence & Failure Prevention
- **`DESIGN.md`, touch targets, instant feedback:** `rules/core-rules.md` §6.
- **Instincts & Failure Memory (`.agents/instincts.md`):** Traps, anti-patterns and past regressions. **[hook]** Surfaced automatically — the map at session start, the matching entries on each request; recorded with `agent-kit learn` or `postfix-gate --record-lesson`. It lowers repeats; it cannot guarantee none.
- **Lazy Senior Dev Principle (7-rung ladder: YAGNI → reuse → stdlib → native → installed dep → one line → minimum; `ponytail:` debt markers; never cut validation, security, a11y or the oracle):** always-on summary in `rules/essentials.md`, details `rules/core-rules.md` §4. **[gate]** post-fix gate warns (never blocks) on a newly added dependency and on a `ponytail:` marker with no upgrade trigger.
- **Anti-Laziness & File Integrity (no `// ... existing code ...` placeholders, backward compatibility):** `rules/core-rules.md` §5.
- **Compiler AST Self-Healing:** Parse compiler diagnostic logs to extract exact `file:line:col`, error codes, and caller blast radius to fix build issues methodically.

Health Diagnostic Command (configuration only; add `--run-tests` to run the suites):
```bash
agent-kit health
```
