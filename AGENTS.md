# agent-workbench

<!-- universal-agent-devkit:start -->
# Universal Agent DevKit
Loaded at every session start. Claude Code and Gemini CLI expand the `@` lines. Antigravity, Grok, Codex and Cursor read this same file as plain text: open each path after the @ before any work. Grok has no separate directory.
- DevKit essentials (always apply): written out in full at the end of the DevKit block in `AGENTS.md`, so an agent that expands no `@` import (Antigravity, measured 2026-09-25) has them too.
- Domain profile rules: @.agents/context/profile-rules.md
- Project rules index (`.agents/local/rules/`): @.agents/context/rules-index.md

A device serial in `.adb-denylist`, or forbidden by a project rule, is never captured.

<!-- devkit-essentials:start — generated from the DevKit's rules/essentials.md by scripts/context_sync.py; do not edit -->
# DevKit Essentials — always loaded

Loaded in every session; paths are relative to the project root, `.agents/devkit/` is the DevKit.
Read on demand: master rules `.agents/devkit/AGENTS.md` · standards `.agents/devkit/rules/core-rules.md`
(§19: gate, proof and Git mechanics) · skills `.agents/skills/<name>/SKILL.md` · project rules
`.agents/local/rules/` (index below; open the section the prompt hook names before editing that
area) · traps `.agents/instincts.md`.

## Priority
1. The user's instruction in this task.
2. Project rules in `.agents/local/rules/` marked immutable (bất biến, MUST, cấm): they win over
   a generic DevKit rule; say which project rule you followed.
3. These essentials and the master rules. 4. Existing code patterns and tests.

## Before the first edit (pre-code gate)
Fill all five or collect evidence first: (1) target + authority (verified error, necessity, user
instruction); (2) the real source, read now; (3) every consumer of a signature/public API/shared
object you change, tests included; (4) the failure mechanism and how you will PROVE the change
alters observable behaviour; (5) what stays unverified.
- ≥2 modules, ≥3 files, >200 LOC net diff or a risky flow (crash, parsing, auth, navigation, lifecycle,
  security, module boundary): review the plan before code; only the "ask the user" list under
  Working style needs the user's go-ahead. **Claude ↔ Antigravity cross-review, large tasks only**: the
  same size thresholds, or auth, payment, database migration, production Crashlytics triage, core
  architecture: `antigravity-pm` `plan_review` / `pm_plan` before code; after the gate exits 0, an
  independent Antigravity `audit` (or the `/giao` flow) of the whole diff and code safety, judged by the 7 golden
  standards (core-rules §18 lists them and the /100 scoring); the bilateral review record is
  required for large tasks only.
- Simple or medium task (local bug fix, UI tweak, test update, script fix, 1–2 file logic): the agent
  that was called, Claude or Antigravity, does it A to Z and verifies it itself (paired test RED→GREEN,
  gate exit 0), with no second-agent review. Trivia: choose, ask no one.

## Lazy senior: build less, never check less
Once the change is understood, stop at the first rung that holds: (1) does it need to exist?
(2) reuse the codebase; (3) stdlib; (4) native platform; (5) an installed dependency; (6) one line;
(7) only then the minimum that works. No abstraction, config or file nobody asked for; deletion over
addition; fix a bug once in the shared function; a complex request ships the lazy version and names
the full one in one line; a known-ceiling shortcut carries `ponytail: <ceiling>, <when to upgrade>`.
Never cut: trust-boundary validation, data-loss handling, security, accessibility, hardware
calibration, the paired oracle and the gate (core-rules §4).

## Non-negotiables
- **No fabrication**: no invented paths, APIs, line numbers, metrics, versions, root causes, test
  results or past actions. Say "checking X" instead of a provisional conclusion.
- **Paired executable oracle for every bug fix** (no waiver): a test at the real failure boundary,
  RED before the production change, the same test GREEN after. A compile proves only a compile failure.
- **Evidence per claim**: structural fact → fresh source; metric/version → a tool measurement;
  "fixed/works" → discriminating before/after evidence; "X is unaffected" → a search scaled to the
  risk; a hypothesis is labelled as one; unknown is said.
- **Anti-loop**: two failed fixes for one root cause → stop, drop the hypothesis, change approach.
- **Protect working code**: touch it only for a real error, a real necessity or an explicit
  instruction. Surgical diffs; no drive-by refactors, formatting sweeps or placeholder code
  (`// ... existing code ...`); keep public signatures backward compatible.
- **Git — commit and push yourself** (a project or user rule that forbids it wins: stop and wait
  for the order). A finished task
  is committed and pushed without asking, only your own paths (`git commit -m … -- <paths>`, never
  `git add -A`/`commit -a`). Before a push: `git fetch`, `git pull --ff-only` (or `--no-rebase
  --no-edit` when both moved; check the exit code; a conflict → skill conflict, ask only for a
  business decision), re-run the step 3 gate after any pull or merge, then `git push origin <branch>`,
  never `<sha>:<branch>`. Every commit and push needs the latest gate on that content at exit 0, or
  exit 2 whose only reason is an edited test an Antigravity audit passed; a trunk-push repo moves
  main only through `agent-kit integrate`. Never commit secrets (`.env`, keystores,
  `local.properties`, `google-services.json`, tokens); mask them in proof.
- **One developer, one branch**: work on the current branch; no new branch, worktree or remote
  branch unless the user asks (then prefix the git command with `DEVKIT_ALLOW_BRANCH=1`), except the
  pre-authorized worktree below. The git guard blocks the rest.
- **One checkout, one session**: an agent with no hooks (Antigravity) runs
  `python3 .agents/devkit/bin/session_lock.py --status` before editing. Exit 3 = another live session
  holds it: never edit there and never stop to ask (pre-authorized by the user, 2026-10-12): run
  `agent-kit worktree add ../<repo>-<task>`, gate and commit there, then `agent-kit worktree finish <path>`
  (main still held → finish once the holder idles). A task that session dispatched to you (`/giao`)
  is done in its checkout. Exit 5 = trunk mode (default): main is merge-only, every session works
  in its own worktree (Claude Code: EnterWorktree) and only `agent-kit worktree finish` moves main.
- **Done means verified**: step 3 at exit 0 on the current code and, when step 4 applies, this
  turn's proof PNG before XONG; Stop hooks enforce it where they exist, but no hook takes the screenshot.

## Every prompt (standing law)
Applies to Claude Code, Gemini CLI, Antigravity, Codex, Cursor and Grok, to every turn that changes
a file. A turn that changes nothing (a question, a review, a plan) is answered directly: no gate,
no image, no status line. In a changing turn a missing step opens the reply with CHƯA XONG and
stops. Do not write XONG, PASS, đã fix or đã xong without step 5.

1. Read `AGENTS.md`, `.agents/context/profile-rules.md`, `.agents/context/rules-index.md` and every
   `.agents/local/rules/` file the index names.
2. A code or bug prompt: run the failing oracle and see RED before editing production, then the
   same oracle GREEN after. Keep the command log and the exit code.
3. From the repo root, once: `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --scoped --brief`.
   Exit 0 is required; this scoped run writes the task receipt, the proof for step 5 (build, QA, review,
   merge queue and `agent-kit integrate` run the same). Nobody runs `--full` by hand for a task: the
   `gate-full` skill runs it nightly. Any other exit: paste the last 30 log lines, fix, repeat; a
   dry-run, `--help` or a single Gradle test does not replace it. Details: core-rules §19.
4. A proof image blocks like exit 0, unless the change surely cannot show on a screen: a backend
   profile, or every changed file is tooling, tests, docs or logs (exact list: core-rules §19;
   `hooks/proof_gate.sh` applies it). Then write "ảnh: không cần — <reason>" in line 3 and skip this
   step. Otherwise run `python3 .agents/devkit/bin/proof-capture.py` from the repo root (it picks an
   allowed online device or boots the profile's AVD and writes `reports/proof-<yyyyMMdd-HHmmss>.png`),
   install this turn's build on that serial, reach the success screen, run it again and embed the PNG inline
   with its serial: `![Ảnh nghiệm thu](reports/proof-<stamp>.png)`. Never draw, reuse an old image
   or substitute a test XML; no device → CHƯA XONG with the command's error. A UI or gesture bug
   also needs BEFORE evidence from the unfixed build (`reports/before-<stamp>.png`) or `before: không cần — <reason>`.
5. The reply may open with XONG only when this turn has step 2 RED→GREEN (code or bug prompt), exit 0
   from step 3 (its task receipt), the step 4 PNG when it applies, and the work handed to the merge
   point: PR opened, worktree finished or main pushed. Line 1: XONG, CHƯA XONG or CHỜ DUYỆT (English:
   DONE / NOT DONE / AWAITING APPROVAL). Line 2: what the user gets. Line 3: gate exit code, then
   image path and serial, or "ảnh: không cần — <reason>"; then the next step. Stay short.
   Every handover (an XONG, or any turn that runs `git push`) carries the acceptance report
   (core-rules §1.3), 1–2 lines each: 1. Đã fix gì (lỗi, nguyên nhân gốc, RED→GREEN) · 2. Chặn bug
   cũ (test hồi quy / immutable_guards chạy lại PASS) · 3. Nguy cơ bug mới (caller, module liên đới
   đã rà) · 4. An toàn mã nguồn (secret, placeholder, OCR); kèm điểm chất lượng Agent trên thang 100
   (ngưỡng ≥ 95/100, core-rules §18). `proof_gate.sh` refuses the reply without all four.
   A Markdown or LICENSE-type-only change needs no regression test: the gate passes it.

## Engineering musts (details: `.agents/devkit/rules/core-rules.md` §6, §8–14)
- No O(N²) where a map/set does, no allocations in hot loops, no I/O/network/DB/heavy parsing on
  the main/UI thread; every stream, cursor, connection, listener, timer and scope released with
  its lifecycle; no static UI/Context refs.
- No empty `catch`/`except: pass`; no raw `console.log`/`println`/`printStackTrace` in production;
  structured logs with PII masked. Network: connect ≤10 s, read ≤15 s, retry only idempotent calls
  with backoff + jitter, idempotency key on payment/order writes. Every schema change ships a
  migration and its test; never a destructive drop in LIVE.
- UI: `DESIGN.md` tokens, touch targets ≥48 dp (≥44 px web), immediate feedback, expensive actions
  debounced ≥1000 ms. UI files (core-rules §19) follow Zero-Slop: no card in card or panel in panel, no icon tile above
  a heading, no bare grey/`#808080`, no purple-blue gradient (tint neutrals 3–5 %),
  spacing 4–8 / 12–16 / 24–32 (never 16 everywhere); game:
  9-slice bevel, pressed scale 0.95 with a 2–4 px sink, never `LiberationSans SDF`.

## Working style
- Pick skills from context yourself; never ask the user to type a slash command.
- Act, don't offer: a defect an audit or review finds here is fixed in the same turn (oracle, gate,
  proof) unless the fix needs the ask list; never end a turn with a menu of prescribed steps: do them.
- Never hand the work to the user (2026-10-09: "tự xử lý luôn đi, tôi không đọc đâu"): no `!`
  command, no "run this", no checklist. The agent runs the gate of every repo the change reaches,
  the reviews and their fixes, the kit install and host re-sync, commit and push. Only the "ask
  the user" list below, a login only the user can type and a switch the kit reserves go to the user.
- **Auto 100%** (chủ repo 2026-11-02: "tự auto toàn bộ ko cần người phải duyệt hay comment hay cho
  quyền"; quyền công cụ: câu cuối): không bước nào chờ người duyệt, comment, review hay merge; cần
  người duyệt thứ hai thì đó là agent khác (Antigravity audit, review lane). Agent TỰ AUTO DUYỆT
  thay đổi code khi test PASS, không hỏi "Duyệt / không duyệt". Commit, push fast-forward kể cả
  `main`, mở và merge PR thường, sửa test, sửa code: tự làm. Hỏi người dùng CHỈ KHI: force-push
  hoặc viết lại lịch sử đã chia sẻ; xoá file/dữ liệu cực kỳ quan trọng không khôi phục được từ
  origin (dữ liệu người dùng thật, migration phá dữ liệu LIVE, nhánh/tag còn commit chưa có trên
  remote); phát hành store / deploy production; đổi hoặc in secret đang dùng; billing/thanh toán;
  cấp quyền camera/location/danh bạ/PII; phá API công khai đã phát hành; làm yếu gate bảo mật chưa
  được yêu cầu. Khi đó: một AskUserQuestion (khuyến nghị trước) rồi tự làm tiếp nếu được duyệt.
  Quyền công cụ (allow/deny, permission mode) do người dùng cấp: agent không tự nới, không lách
  lệnh bị từ chối; ghi CHƯA XONG cho bước đó kèm quyền cần và lý do, làm hết phần còn lại.
- An edited existing test needs cross-approval by another agent: an Antigravity `/giao` audit that
  records it (`.claude/audit-gate/approved_tests.json`) or the trailer
  `Test-approved-by: antigravity <task-id>`, valid only when the antigravity-pm verdict records
  `auditedHead: <sha>` of the tree holding that exact test. The editor never approves its own test
  (`--auto-approve-tests` and `AUTO-APPROVE:` approve nothing); never ask the user.
- Clean up what you create (2026-10-09: 33 GB of scratch filled the disk): delete a repo copy, stage
  kit or fixture once served; what must outlive the session lives in the ignored `.agents/local/`.
- **Language**: code comments, acceptance reports, handovers, PR notes and commit messages are English by default;
  with `"lang": "vi"` (`.agents/active-profile.json` or a project rule) comments, reports and commit messages
  are Vietnamese; replies match the user's language; identifiers, commands and paths stay English (core-rules §2.3).
- Long session or a big refactor ahead: checkpoint and compact instead of filling the window.
- Traps from past bugs arrive with each request (`.agents/instincts.md`); read the named entry.
<!-- devkit-essentials:end -->
<!-- universal-agent-devkit:end -->

<!-- super-board:begin v3.1.2 (managed; edits inside are overwritten on upgrade) -->
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
| Merge | auto for normal changes · money, auth, destructive schema, deleting a protected file → human · line count is a human gate only when `auto_max_lines` is a positive number (unset default is 0) |
| Migrations | additive → robot migrates allowed DBs only · live DB → 🙋 `done` or cross-review marker |
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
<!-- super-board:end -->
