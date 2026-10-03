# agent-workbench

<!-- universal-agent-devkit:start -->
# Universal Agent DevKit
Loaded at every session start. Claude Code and Gemini CLI expand the `@` lines. Antigravity, Grok, Codex and Cursor read this same file as plain text: open each path after the @ before any work. Grok has no separate directory.
- DevKit essentials (always apply): written out in full at the end of the DevKit block in `AGENTS.md`, so an agent that expands no `@` import (Antigravity, measured 2026-09-25) has them too.
- Domain profile rules: @.agents/context/profile-rules.md
- Project rules index (`.agents/local/rules/`): @.agents/context/rules-index.md

On demand — everything agent-related lives in `.agents/`: master rules `.agents/devkit/AGENTS.md` · engineering standards `.agents/devkit/rules/core-rules.md` · skills `.agents/skills/` · traps from past bugs `.agents/instincts.md` · profile `.agents/active-profile.json`.
Post-fix gate: `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief` — only exit `0` counts as PASS. A turn that changes app source on a profile with a screen also attaches a real proof PNG from this turn before the reply may open with XONG. Standing text: the top of this file and the essentials below ("Every prompt"). A serial in `.adb-denylist`, or forbidden by a project rule, is never captured.

<!-- devkit-essentials:start — generated from the DevKit's rules/essentials.md by scripts/context_sync.py; do not edit -->
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
- **Claude ↔ Antigravity cross-review (chỉ dành cho task lớn & rủi ro cao)**: Cơ chế phản biện
  song phương Claude ↔ Antigravity (qua `antigravity-pm` `plan_review` / `pm_plan` trước khi code
  và `audit` sau khi xong) CHỈ ÁP DỤNG cho các task lớn: chạm ≥2 modules, ≥3 files, >200 LOC net diff,
  hoặc luồng rủi ro cao (auth, payment, database migration, production crashlytics triage, thay đổi
  kiến trúc cốt lõi) theo 7 tiêu chuẩn vàng:
  (1) *Chính xác phẫu thuật:* diff tối thiểu, Zero Blast Radius, không làm xước mô xung quanh.
  (2) *Tất định & Tự kiểm chứng:* paired test RED → GREEN, bịt kín mọi failure mode.
  (3) *Hiển nhiên & Tối giản:* không múa code phức tạp, on-call đọc hiểu cơ chế trong 10 giây.
  (4) *Kỷ luật tài nguyên:* không nghẽn UI, không O(N²), dọn sạch stream/listener/leak.
  (5) *Thấu suốt vận hành:* log có cấu trúc, không nuốt ngoại lệ, khoanh vùng lỗi trong 5 phút.
  (6) *Phòng thủ ranh giới:* zero-trust, validate biên nghiêm ngặt, không lộ secret/PII.
  (7) *Dễ tiêu hủy & Tiến hóa:* module khép kín, sẵn sàng xóa sạch, tương thích ngược.
  Đối với TASK ĐƠN GIẢN / TRUNG BÌNH (bug fix cục bộ, tinh chỉnh UI, cập nhật test, sửa script,
  logic 1-2 file): gọi agent nào (Claude hoặc Antigravity) thì agent đó TỰ LÀM LUÔN TỪ A-Z cho
  nhanh, tự kiểm chứng (paired test RED→GREEN, gate exit 0), KHÔNG CẦN gọi agent thứ 2 review để
  tránh lãng phí thời gian và token.
- ≥2 modules, ≥3 files, >200 LOC or a risky flow (crash, parsing, auth, navigation, lifecycle,
  security, module boundary): review the plan before code; only the "ask the user" list under
  Working style needs the user's go-ahead.

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
- **Git — commit and push yourself**: a finished task (gate `--full` exit 0, proof when
  required, the acceptance report) is committed and pushed without asking: commit your own
  paths, `git fetch`; origin moved → `git pull --no-rebase --no-edit` (check its exit code;
  a conflict → skill conflict, ask only for a business decision) and, after any pull, merge
  or conflict fix, re-run the gate on what will be pushed (`post-fix-gate.py --run-tests
  --full --diff origin/<branch>`). Every commit and every push needs the latest gate on that content at
  exit 0 — or exit 2 whose only reason is an edited test an Antigravity `audit` passed, with
  `Test-approved-by: antigravity <task-id>` in `git log origin/<branch>..HEAD`. Anything else: no commit,
  no push.
  Never commit secrets
  (`.env`, keystores, `local.properties`, `google-services.json`, tokens); mask them in proof.
  A checkout another session shares: commit only your own paths (`git commit -m … -- <paths>`),
  never `git add -A`/`commit -a`, which sweep in the other session's work.
- **One developer, one branch**: work on the current branch. No new branch, worktree or
  remote branch unless the user asks for it (then prefix the git command with
  `DEVKIT_ALLOW_BRANCH=1`). Before a push, bring origin into the local branch with its own
  command (`git pull --ff-only`, or `--no-rebase` when both moved; check its exit code),
  then `git push origin <branch>` — never `<sha>:<branch>` that the local branch does not
  hold. The git guard blocks the rest; session start names drift and leftovers (AGENTS.md §7.1).
- **One checkout, one session**: an agent with no hooks (Antigravity) runs `python3 .agents/devkit/bin/session_lock.py --status`
  before editing; exit 3 = another live session holds it → do not edit (wait, or ask for a worktree) unless
  that session dispatched this task to you (antigravity-pm, `/giao`: it is your PM and reviews your diff).
- **Done means verified**: run the post-fix gate
  (`python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief`, exit 0 only) and
  attach a real proof PNG from this turn (when step 4 of "Every prompt" applies) before the
  reply may open with XONG. Với task lớn (≥2 modules, ≥3 files, >200 LOC hoặc rủi ro cao), sau khi
  gate PASS (exit 0) gọi Antigravity audit / review check độc lập (qua `antigravity-pm` `audit` hoặc
  quy trình như `/giao`) để rà soát toàn bộ diff và an toàn mã nguồn. Với task đơn giản, agent tự hoàn
  tất và nghiệm thu ngay khi gate PASS (exit 0) mà không cần gọi thêm agent khác.
  Khi chạy nhiều agent / nhiều prompt song song: chỉ test đúng ca đang làm (`--run-tests --brief`).
  Cổng kiểm thử tự động kiểm tra toàn bộ sessions và chỉ kích hoạt kiểm tra toàn diện (`--full`)
  khi xác nhận đây là phiên cuối cùng duy nhất đang làm việc (tránh lock contention và chạy lặp).
  The Stop hooks enforce the gate on hosts that have them. They do not take the screenshot; on
  Claude Code `proof_gate.sh` refuses a reply opening with XONG unless this turn has a `--full`
  exit 0 on the current code and, for app source on a profile with a screen, names a fresh proof
  PNG.

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
   `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief`
   Exit 0 is required. Khi làm việc qua nhiều prompt hoặc nhiều agent, gate tự động tối ưu:
   chỉ chạy test ca đang làm (impacted mode) khi còn các phiên khác đang chạy, và chỉ chạy toàn diện
   `--full` khi đây là phiên cuối cùng duy nhất hoàn tất công việc. Một lượt hoãn/impacted in "CHƯA ĐỦ ĐIỀU KIỆN NGHIỆM THU", không ghi receipt và KHÔNG phải bằng chứng cho bước 5: phiên cuối chạy `--full`, hoặc thêm `--force-full` khi phải nghiệm thu ngay. Any other exit: paste the last
   30 log lines, fix, and repeat this step. A dry-run, `--help`, or a single Gradle test does not replace this command.
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
   a later turn that only touches tests is not asked again. `hooks/proof_gate.sh` applies the same rule (`bin/tree_fp.py`). From the
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
5. The reply may open with XONG only when this turn has exit 0 from step 3 and, when step 4
   applies, its PNG. Line 1: XONG or CHƯA XONG. Line 2: what the user gets. Line 3: gate
   exit code, then image path and serial, or "ảnh: không cần — <reason>".
   Every handover — an XONG, or any turn that runs `git push` — then carries the acceptance
   report (core-rules §1.3), 1–2 lines each: 1. Đã fix gì (lỗi, nguyên nhân gốc, RED→GREEN)
   · 2. Chặn bug cũ (test hồi quy / immutable_guards chạy lại PASS) · 3. Nguy cơ bug mới
   (caller, module liên đới đã rà) · 4. An toàn mã nguồn (secret, placeholder, OCR).
   Kèm điểm đánh giá chất lượng Agent trên thang 100 (ngưỡng $\ge 95/100$); biên bản phản
   biện song phương Claude ↔ Antigravity chỉ bắt buộc với task lớn.
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
  card or panel in panel, no icon tile above a heading, no bare `Color.Gray`/`#808080` or purple-blue gradient
  (tint neutrals 3–5 %), spacing 4–8 / 12–16 / 24–32 (never 16 everywhere); game: 9-slice bevel, pressed scale
  0.95 with a 2–4 px sink, never `LiberationSans SDF`.

## Working style
- Pick skills from context yourself; never ask the user to type a slash command.
- Act, don't offer: an audit or review that finds a defect in this project fixes it in the
  same turn (oracle, gate, proof) unless the fix crosses an approval boundary. Never end a
  turn with a menu of steps this law already prescribes (tests, gate, fresh-context review,
  proof capture on an allowed device, re-running after another session's work) — do them.
- Decide, don't ask. Agent tự chủ tối đa: Khi thấy tốt hơn hoặc cần thiết thì TỰ AUTO DUYỆT
  (auto-approve) các thay đổi test và code sau khi kiểm chứng test PASS. Tuyệt đối KHÔNG hỏi
  phiền người dùng bằng AskUserQuestion "Duyệt / không duyệt" với các thay đổi code/test thông
  thường. Hỏi người dùng CHỈ KHI: force-push hoặc viết lại lịch sử, xóa nhánh/tag, phát hành
  cho người dùng thật (store, production deploy), xóa dữ liệu người dùng thật hoặc migration phá
  hủy dữ liệu, auth/billing/secrets, phá vỡ hợp đồng public API, quyền truy cập dữ liệu cá nhân
  mới (camera, location, danh bạ, PII), làm yếu gate hoặc luật. Hỏi giữa lượt bằng AskUserQuestion
  (phương án khuyến nghị trước) và tiếp tục làm việc độc lập.
- Quyết định kiến trúc / kỹ thuật lớn: Task lớn (≥2 modules, ≥3 files, >200 LOC hoặc luồng rủi
  ro) trao đổi với Antigravity (`plan_review` / `audit`) để thống nhất giải pháp tối ưu. Task đơn
  giản: agent được gọi tự làm từ A-Z, không cần 2-agent review. Trivia: choose, ask no one.
- An edited existing test: Agent tự thẩm định và tự auto-duyệt (auto-approve, cờ `--auto-approve-tests`
  hoặc ghi nhận auto-duyệt trong lượt) khi thấy thay đổi là tốt hơn, cần thiết, hợp lý và test
  chạy PASS; tuyệt đối KHÔNG hỏi phiền người dùng bằng AskUserQuestion.
- Answer in the user's language (Vietnamese when they write Vietnamese); identifiers,
  commands, paths and commit subjects stay English.
- Reports open with three lines: status (XONG / CHƯA XONG / CHỜ DUYỆT), what the user gets,
  next step; stay short — a handover adds the 4-item report of "Every prompt" step 5. XONG also requires the full-gate exit 0 and, when it applies, the
  proof PNG in "Every prompt".
- Long session or a big refactor ahead: checkpoint and compact instead of filling the window.
- Traps from past bugs arrive with each request (`.agents/instincts.md`); read the named entry.
<!-- devkit-essentials:end -->
<!-- universal-agent-devkit:end -->
