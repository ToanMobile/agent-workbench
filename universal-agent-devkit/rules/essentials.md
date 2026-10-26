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
decided before editing; (5) what stays unverified.
- ≥2 modules, ≥3 files, >200 LOC net diff or a risky flow (crash, parsing, auth, navigation, lifecycle,
  security, module boundary): review the plan before code; only the "ask the user" list under
  Working style needs the user's go-ahead. **Claude ↔ Antigravity cross-review, large tasks only**: the
  same size thresholds, or auth, payment, database migration, production Crashlytics triage, core
  architecture: `antigravity-pm` `plan_review` / `pm_plan` before code; after the gate exits 0, an
  independent Antigravity `audit` (or the `/giao` flow) of the whole diff and code safety. Judge it by
  the 7 golden standards (surgical, deterministic, boring, resource hygiene, operability, zero-trust
  boundary, deletable; core-rules §18 has them and the /100 scoring); the bilateral review record is
  required for large tasks only.
- Simple or medium task (local bug fix, UI tweak, test update, script fix, 1–2 file logic): the agent
  that was called, Claude or Antigravity, does it A to Z and verifies it itself (paired test RED→GREEN,
  gate exit 0), with no second-agent review. Trivia: choose, ask no one.

## Lazy senior: build less, never check less
Once the change is understood (read the code, trace the flow, grep every caller), stop at
the first rung that holds: (1) does it need to exist? (2) already in this codebase → reuse;
(3) stdlib; (4) native platform feature; (5) an installed dependency; (6) one line;
(7) only then the minimum that works. No abstraction, config or file nobody asked for;
deletion over addition. A bug is fixed once in the shared function, not per caller. A
complex request: ship the lazy version and name the full one in one line. A deliberate
shortcut with a known ceiling carries `ponytail: <ceiling>, <when to upgrade>`. Never cut:
trust-boundary validation, data-loss handling, security, accessibility, hardware
calibration, the paired oracle and the gate below. Details: core-rules §4.

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
- **Git — commit and push yourself** (unless a project rule in `.agents/local/rules/` or a user rule forbids it — that rule wins, then stop and wait for the order): a finished task (task receipt of step 3, proof when
  required, the acceptance report) is committed and pushed without asking: commit your own
  paths, `git fetch`; origin moved → `git pull --no-rebase --no-edit` (check its exit code;
  a conflict → skill conflict, ask only for a business decision) and, after any pull, merge
  or conflict fix, re-run the gate on what will be pushed: on a PR branch `post-fix-gate.py --run-tests`
  (its task receipt), on main `post-fix-gate.py --run-tests --full --diff origin/<branch>` (a push of
  main is a merge point). Every commit and every push needs the latest gate on that content at
  exit 0 — or exit 2 whose only reason is an edited test an Antigravity `audit` passed, with
  `Test-approved-by: antigravity <task-id>` in `git log origin/<branch>..HEAD`. Anything else: no commit,
  no push.
  Never commit secrets
  (`.env`, keystores, `local.properties`, `google-services.json`, tokens); mask them in proof.
  A checkout another session shares: commit only your own paths (`git commit -m … -- <paths>`),
  never `git add -A`/`commit -a`, which sweep in the other session's work.
- **One developer, one branch**: work on the current branch. No new branch, worktree or
  remote branch unless the user asks for it (then prefix the git command with
  `DEVKIT_ALLOW_BRANCH=1`); the one pre-authorized exception is the held-checkout worktree
  below. Before a push, bring origin into the local branch with its own
  command (`git pull --ff-only`, or `--no-rebase` when both moved; check its exit code),
  then `git push origin <branch>` — never `<sha>:<branch>` that the local branch does not
  hold. The git guard blocks the rest; session start names drift and leftovers (AGENTS.md §7.1).
- **One checkout, one session**: an agent with no hooks (Antigravity) runs `python3 .agents/devkit/bin/session_lock.py --status`
  before editing; exit 3 = another live session holds it → never edit there and never stop to ask the user (pre-authorized
  by the user, 2026-10-12: handle it yourself, stop only when the work is done): make your own detached worktree with
  `agent-kit worktree add ../<repo>-<task>`, work, run the gate and commit in it, then `agent-kit worktree finish <path>`
  (fast-forwards the trunk and removes the worktree; the Stop hook finishes it too). Main still held when you are done →
  wait for the holder to idle (about a minute after its turn) and finish then. Only a task that session dispatched to you
  (antigravity-pm, `/giao`: it is your PM and reviews your diff) is done in its checkout. Exit 5 = trunk mode (the default;
  `agent-kit worktree trunk off` turns it off): main is merge-only and nobody holds it — every session works in its own worktree (Claude Code: the
  tool EnterWorktree; others: `agent-kit worktree add`), and only `agent-kit worktree finish` moves main.
- **Done means verified**: run the post-fix gate
  (`python3 .agents/devkit/bin/post-fix-gate.py --run-tests --brief`, impacted, exit 0 only, on the
  current code; step 3) and attach a real proof PNG from this turn (when step 4 of "Every prompt" applies)
  before the reply may open with XONG. The Stop hooks enforce this where the host has them, but
  no hook takes the screenshot.

## Every prompt (standing law)
Applies to Claude Code, Gemini CLI, Antigravity, Codex, Cursor and Grok, to every turn that
changes a file. A turn that changes nothing (a question, a review, a plan) is answered
directly: no gate, no image, no status line. In a changing turn a missing step opens the
reply with CHƯA XONG and stops. Do not write XONG, PASS, đã fix, or đã xong without step 5.

1. Read `AGENTS.md` (its DevKit block carries these essentials), `.agents/context/profile-rules.md`,
   `.agents/context/rules-index.md`, and every `.agents/local/rules/` file the index names.
2. A code or bug prompt: run the failing oracle and see RED before editing production,
   then the same oracle GREEN after. Keep the command log and the exit code.
3. From the repo root, once:
   `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --brief`
   Exit 0 is required. This impacted run (the tests the branch's change since the trunk reaches) writes the
   task receipt, the proof for step 5. A task never runs `--full`: only the merge point does (the merge queue
   or merge train of a PR repo, the push of main of a trunk-push repo). Any other exit: paste the last
   30 log lines, fix, and repeat this step. A dry-run, `--help`, or a single Gradle test does not replace this command.
   `--full` is cached-full: every cacheable light/cpu matrix suite is considered too; one whose content key (its inputs +
   environment, `bin/suite_cache.py`, shared by every worktree) already PASSed is reused, the rest run (an added suite that
   times out is named, outside the verdict). Gradle/Unity/device suites, `run_impacted.sh`, network commands and
   `"cache": false` keep the old selection; `--no-cache` runs them all. When the repo's last real full run is over 24 h old,
   a `--full` (not a merge gate) uses no content key (sentinel). A push of main needs that receipt of the pushed content
   (usually zero suites to run). Suites run by machine load (`bin/heavy_slot.py`): under a 1-minute load of 8 × cores
   (`bin/capacity.py`; `DEVKIT_SLOT_LOAD_MAX` / `DEVKIT_CAPACITY` override) they start at once, above it they
   wait up to 600 s and run anyway; only Unity and device suites hold an exclusive lock.
4. A proof image is blocking, same rank as exit 0, unless the change surely cannot show on a
   screen: the profile was backend when the turn started (committed, or an uncommitted profile
   file written before the turn), or every file changed since HEAD at
   the turn start (commits, merges, pulls included; new files too) is under a top-level
   `.agents/ .claude/ .gemini/ .github/ .githooks/ .codebase-memory/ docs/ reports/ scripts/
   bin/ tools/`, a top-level test folder (`tests/`, `*Tests/`), a `src/<test source set>/`, a
   `*.log` file anywhere, or is Markdown / LICENSE-type at the root (on a web profile `docs/`
   counts as the site). Then
   write "ảnh: không cần — <reason>" in line 3 and skip this step. Cite only this turn's
   proofs: every cited PNG is checked (stamp in its name from this turn, not a byte copy of
   another proof). A UI change committed in an earlier turn is that turn's proof to attach —
   a later turn that only touches tests is not asked again. For a UI or gesture bug, capture BEFORE evidence from the unfixed build (`reports/before-<yyyyMMdd-HHmmss>.png`) or write `before: không cần — <reason>`. `hooks/proof_gate.sh` applies the same rule (`bin/tree_fp.py`). From the
   repo root: `python3 .agents/devkit/bin/proof-capture.py`
   The command checks `adb devices` first. A declared serial is used only when its
   state is `device` and it is not on the denylist. If that serial is offline, or no
   allowed device is online, it starts the AVD in `.antigravity-pm.json`
   (`proof.providers.<name>.avd`). With no avd name it starts the phone AVD on an
   android profile, or the existing CarConnect AVD on an automotive profile, waits for
   `sys.boot_completed=1`, and writes `reports/proof-<yyyyMMdd-HHmmss>.png`.
   It does not screencap a dead address and does not substitute another plugged-in phone.
   - Install the build this turn produced on that serial and reach the success screen,
     then run the command again so the PNG shows that screen.
   - Put the PNG in the reply with the path and serial the command printed. Real PNG,
     larger than 8 KB, mtime in this turn. Bắt buộc hiển thị trực tiếp (inline, không lặp path):
     `![Ảnh nghiệm thu](reports/proof-<stamp>.png)`.
   - The command exits non-zero when it cannot open a device. Open with CHƯA XONG and
     paste that error. Do not draw, reuse an old image, or substitute a test XML.
5. The reply may open with XONG only when this turn has step 2 RED→GREEN (code or bug prompt), exit 0
   from step 3 (its task receipt), when step 4 applies its PNG, and the work handed to the merge point: PR
   opened, worktree finished or main pushed. Line 1: XONG, CHƯA XONG or CHỜ DUYỆT (English: DONE / NOT DONE /
   AWAITING APPROVAL). Line 2: what the user gets. Line 3: gate exit code, then image path and
   serial, or "ảnh: không cần — <reason>"; then the next step. Stay short.
   Every handover — an XONG, or any turn that runs `git push` — then carries the acceptance
   report (core-rules §1.3), 1–2 lines each: 1. Đã fix gì (lỗi, nguyên nhân gốc, RED→GREEN)
   · 2. Chặn bug cũ (test hồi quy / immutable_guards chạy lại PASS) · 3. Nguy cơ bug mới
   (caller, module liên đới đã rà) · 4. An toàn mã nguồn (secret, placeholder, OCR).
   Kèm điểm đánh giá chất lượng Agent trên thang 100 (ngưỡng $\ge 95/100$, core-rules §18).
   `proof_gate.sh` refuses the reply without all four.
   A change of Markdown (`.md/.rst/.adoc`) or LICENSE-type files only needs no regression
   test: the gate passes it.

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
  expensive actions disabled/debounced ≥1000 ms after the first tap. Editing a UI file (`*.kt`/`*.java`/`*.xml`,
  `*.swift`, `*.dart`, `*.tsx`/`*.jsx`/`*.vue`/`*.css`, `*.prefab`, `*UI*.cs`) also means Zero-Slop: no card in
  card or panel in panel, no icon tile above a heading, no bare Color.Gray (or any named grey constant)/`#808080` or purple-blue gradient
  (tint neutrals 3–5 %), spacing 4–8 / 12–16 / 24–32 (never 16 everywhere); game: 9-slice bevel, pressed scale
  0.95 with a 2–4 px sink, never `LiberationSans SDF`.

## Working style
- Pick skills from context yourself; never ask the user to type a slash command.
- Act, don't offer: an audit or review that finds a defect in this project fixes it in the
  same turn (oracle, gate, proof) unless the fix crosses an approval boundary. Never end a
  turn with a menu of steps this law already prescribes (tests, gate, fresh-context review,
  proof capture on an allowed device, re-running after another session's work) — do them.
- Never hand the work to the user (user, 2026-10-09: "tự xử lý luôn đi, tôi không đọc đâu"):
  no `!` command, no "run this", no checklist for the user. The agent itself runs the gate of
  every repo the change reaches, the fresh-context review and its fixes, the Antigravity audit
  when required, the kit install and host re-sync, commit and push. A step the permission
  system denies is never worked around: report CHƯA XONG with what was denied and why it is
  needed, everything else finished. Only the "ask the user" list below, a login only the user
  can type, and a switch the kit reserves for the user go to the user.
- Clean up what you create (user, 2026-10-09: 33 GB of scratch filled the disk): a repo copy,
  stage kit or fixture is deleted in the same turn its purpose is served, a copy as soon as it
  was pushed from. The session hooks remove the session's temp dir at SessionEnd and prune
  dead sessions' dirs (idle 7 days) at SessionStart (`.agents/devkit/scripts/governance/scratch_cleanup.py`).
  Anything that must outlive the session (a stage awaiting the user, a handoff) lives outside
  `/tmp/claude-<uid>`, e.g. in the repo's ignored `.agents/local/`.
- Decide, don't ask. Agent tự chủ tối đa: Khi thấy tốt hơn hoặc cần thiết thì TỰ AUTO DUYỆT
  (auto-approve) các thay đổi test và code sau khi kiểm chứng test PASS. Tuyệt đối KHÔNG hỏi
  phiền người dùng bằng AskUserQuestion "Duyệt / không duyệt" với các thay đổi code/test thông
  thường. Hỏi người dùng CHỈ KHI: force-push hoặc viết lại lịch sử đã chia sẻ; xoá file
  hoặc dữ liệu cực kỳ quan trọng mà không khôi phục được từ origin (dữ liệu người dùng thật,
  migration phá dữ liệu LIVE, nhánh/tag còn commit chưa có trên remote); việc cực kỳ nguy hiểm
  cần xác nhận (phát hành store / deploy production, đổi hoặc in secret đang dùng, thao tác
  billing/thanh toán, cấp quyền camera/location/danh bạ/PII, phá hợp đồng API công khai đã
  phát hành, làm yếu gate bảo mật khi lượt này chưa được yêu cầu). Commit, push fast-forward
  kể cả `main`, mở và merge PR thường, sửa test, sửa code: agent tự làm, không hỏi, không đưa
  lệnh `!`. Khi đúng việc phải hỏi: một lần AskUserQuestion (phương án khuyến nghị trước),
  rồi tự làm tiếp nếu được duyệt.
- An edited existing test: Agent tự thẩm định và tự auto-duyệt (auto-approve, cờ `--auto-approve-tests`
  hoặc một dòng riêng `AUTO-APPROVE: <đường dẫn test>` trong câu trả lời — câu văn xuôi không được tính) khi thấy thay đổi là tốt hơn, cần thiết, hợp lý và test
  chạy PASS; tuyệt đối KHÔNG hỏi phiền người dùng bằng AskUserQuestion.
- **Language**: code comments, acceptance reports, handovers, PR notes and commit messages are English by default;
  with `"lang": "vi"` (`.agents/active-profile.json` or a project rule) comments, reports and commit messages
  are Vietnamese; replies match the user's language; identifiers, commands and paths stay English (core-rules §2.3).
- Long session or a big refactor ahead: checkpoint and compact instead of filling the window.
- Traps from past bugs arrive with each request (`.agents/instincts.md`); read the named entry.
