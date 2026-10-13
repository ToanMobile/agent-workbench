# DevKit — tối ưu & cải tiến workflow (nguồn duy nhất)

> Gộp ngày 13/10/2026 theo yêu cầu người dùng: mọi kế hoạch tối ưu / cải tiến workflow của DevKit nằm trong file này; issues và bugs nằm riêng ở [`issues-bugs.md`](issues-bugs.md). Trước đó là 7 file rải ở `docs/plans/` (cộng một bản sao trùng ở `docs/PLAN-C+D-trunk-integrator.md`).
>
> Chữ của từng plan được giữ nguyên. Chỉ có ba loại thay đổi: tiêu đề hạ cấp (tên file cũ nằm trong tiêu đề mục để `grep` ra), con trỏ giữa các file cũ trỏ sang mục mới (đánh dấu *trỏ lại khi gộp*), và các hàng bug của hai bảng theo dõi chuyển sang `issues-bugs.md` (giữ nguyên số `#`). Lịch sử từng file cũ: `git log --follow -- universal-agent-devkit/docs/plans/<tên cũ>`; riêng `goal-100-2026-10-13.md` chưa từng được commit nên bản gốc chỉ còn ở đây.

## Cách dùng

1. Kế hoạch mới, cập nhật trạng thái, kết quả đo: viết vào file này (Phần I). Làm xong hẳn thì chuyển xuống Phần II. Không tạo file plan thứ hai trong `docs/` (yêu cầu người dùng 13/10: tránh phân mảnh).
2. Vấn đề, bug, việc dọn dẹp đang mở: `issues-bugs.md`. Bug hồi quy có test vẫn do `agent-kit bugs` và gate ghi ở `.agents/CHECKLIST.md`; hai file này không thay thế nó.
3. Nhiều phiên cùng làm một mục: ghi `ĐANG LÀM: phiên <id>` vào cột Trạng thái trước khi bắt đầu (bảng ở mục I.1).
4. Trạng thái trong chỉ mục dưới đây trích từ chính file gốc hoặc nêu rõ nguồn đối chiếu; chỗ chưa đối chiếu ghi là "chưa đối chiếu", không đoán.

## Chỉ mục

| Mục | Nội dung | File gốc | Trạng thái |
|---|---|---|---|
| I.1 | Mục tiêu DevKit 100/100: việc còn lại (Đợt 31 OCR, Giai đoạn C, chiều 5 ngữ cảnh, giai đoạn D…) | `goal-100-2026-10-13.md` | Việc 1 (Đợt 31): code xong, chưa commit/push, chưa chạy gate `--full`; 2 và 4: dở (patch nháp); 5: chờ người dùng quyết; 6, 7: chưa làm; 8: chờ duyệt; 9: xong. Theo bảng gốc, cập nhật 13/10 15:40 |
| I.2 | Plan C+D: không ai sửa trong main, một bộ gộp tuần tự | `trunk-integrator-no-shared-main.md` | Bản nháp chờ duyệt (Gate 1), chưa code. Điều kiện tiên quyết số 2 (gộp `aaf9805`) xong 13/10 theo I.1 việc 8 |
| I.3 | Đề xuất bắt các bug agent không thấy (P1–P10) | `catch-bugs-agents-cannot-see.md` | File gốc: "PROPOSAL — nothing here is implemented" (07/10). CHANGELOG Đợt 6a–6d (08/10) ghi đã làm một phần: xem ghi chú đầu mục |
| II.A | DevKit chạy nhanh: nghiên cứu 04/10 và kế hoạch 3 đợt | `devkit-speed.md` | CHANGELOG có Đợt 0 (04/10), Đợt 1a (05/10, mục 3b), Đợt 4 (07/10, mục 1c); phần còn lại chưa đối chiếu |
| II.B | Living Regression Checklist V3 | `regression-checklist-v3.md` | Phụ lục B: P0–P9 xong 24/09/2026; người dùng quyết không cài job đêm |
| II.C | UI context injection Zero-Slop | `ui-context-injection-zero-slop.md` | Thực thi ngày 03/10/2026 (mục "Audit và thực thi"); hai điểm chờ người quyết nằm ở `issues-bugs.md` A.4 |

## Phần I — Đang mở / chờ duyệt


### I.1 Mục tiêu DevKit 100/100 — việc còn lại (cập nhật 2026-10-13 15:40) *(trước đây: `docs/plans/goal-100-2026-10-13.md`)*

Mục tiêu người dùng đặt 12/10: "làm cho tới khi devkit đạt 100/100", chấm theo `skills/devkit-audit/references/rubric.md`.
Điểm trung thực gần nhất ~70 (sau Đợt 23; các chiều ≈ [6,5,6,10,3,5,10,10,8,8]). Chấm lại sau khi Đợt 31 lên origin.

**Trước khi nhận việc:** `python3 .agents/devkit/bin/session_lock.py --status` (bị giữ → tự làm trong worktree riêng, luật 12/10);
nhiều phiên cùng làm mục tiêu này — ghi `ĐANG LÀM: phiên <id>` vào cột Trạng thái của bảng dưới trước khi bắt đầu, để phiên khác bỏ qua.

#### Trạng thái

| # | Việc | Trạng thái | Ở đâu |
|---|---|---|---|
| 1 | **Đợt 31** — OpenCodeReview làm reviewer thứ hai của `/devkit-audit`; `review_gate` tự chạy OCR (delegation khi chặn, công tắc `REVIEW_GATE_OCR=full`); che bí mật trong checklist; `regression_gate` không bỏ qua Stop khi payload thiếu `session_id` / `DEVKIT_ALLOW_SHARED_CHECKOUT=1`; sửa 16 phát hiện của lượt OCR tự review | **CODE XONG + TEST XANH, CHƯA COMMIT, CHƯA PUSH, CHƯA CHẠY GATE `--full`** | cây làm việc của main (HEAD `fbfbf42`) + sao lưu `.agents/local/memory/dot31-backup-2026-10-13/` |
| 2 | **Giai đoạn C của plan A–D** (KHÁC "Plan C+D" ở việc 8) — một bộ chuẩn hoá lệnh shell dùng chung cho `hardware_safety_gate.sh` và `block-dangerous-git.sh` (gỡ đệ quy `sh -c` / `adb shell` / `su -c` / `ssh` / `eval` / `xargs`, chuẩn hoá đường dẫn, brace expansion; shadow 1 ngày rồi bật chặn) — bỏ trần 89 | dở: patch nháp + replay 7 ngày, agent dừng vì hạn mức | `.agents/local/memory/wip-2026-10-13/guardc/` |
| 4 | **Chiều 5 ngữ cảnh** (≤40 KB nạp mỗi phiên) — tách luật profile automotive (người dùng duyệt 13/10 ~10:50: mọi dòng MUST / an toàn xe vẫn luôn nạp, chỉ hướng dẫn dài chuyển sang nạp khi cần); KiB đo 13/10: Neighbours 35.1 (đạt), Office 47.9, Goods 47.3, Geely 55.2 | dở: patch nháp kit + 3 repo, agent dừng vì hạn mức | `.agents/local/memory/wip-2026-10-13/ctx5/` |
| 5 | Phần còn thiếu của chiều 5 sau việc 4 là essentials nhúng sẵn 19.5 KB/repo: chỉ rút essentials hoặc nâng mốc 40 KB mới đủ | **chờ người dùng quyết** | — |
| 6 | Giai đoạn D — nightly `red_proof.py --pending` mỗi repo, đưa dòng "đang chờ" ≤2 % rồi đo lại cửa sổ 24 h | chưa làm | — |
| 7 | Replay Stop chặn nhầm trên transcript thật cho `proof_gate` / `review_gate` (đọc trường `report=` / `image=` mới) | chưa làm | — |
| 8 | **Plan C+D — trunk integrator** (mục I.2 bên dưới *(trỏ lại khi gộp)*, phiên d1df0d47): không ai sửa trong main, mỗi phiên một worktree, một bộ gộp tuần tự | **chờ người dùng duyệt (Gate 1 + Gate 2)** — không code trước khi duyệt; điều kiện tiên quyết số 2 của nó (gộp `aaf9805` từ `agent-workbench-dot30b`) XONG 13/10 15:3x (`d5ef026`) | — |
| 9 | Gộp worktree còn sót: workbench `dot30b` (`d5ef026`), `sprite-forge` (`fbfbf42`, vendor Sprite Forge + patch billing của DevKit, gate impacted PASS), `agent-workbench-plan` (`d7fc075`) | **XONG 13/10** — chưa push; `GeelyEx2-mcpfix` và `Goods-…-mcp` chờ phiên giữ repo nhả khoá (mục 7 của `2026-10-13-mcp-5-repo-va-coverage-map.md`) | — |

*(Việc 3 và 10 của bảng gốc là bug: nằm ở `issues-bugs.md` mục A.1, giữ nguyên số `#`. Việc 3 ghi "gộp vào việc 2", tức Giai đoạn C ở bảng trên.)*

#### Việc 1 — hoàn tất Đợt 31 (theo thứ tự)

Bằng chứng đã có: 17 ca ĐỎ → XANH cho 16 phát hiện OCR (`test_review_gate_ocr.sh` 18 kiểm, `test_review_gate_ocr_full.sh` 14,
`test_ocr_review_helper.sh` 14, `test_bug_secret_redaction.sh` 12, `test_regression_gate_held_by_other.sh` 13); 77 test liên quan exit 0;
delegation đo ở 5 repo 0.3–0.8 s, cây git không đổi; `/scan` kết luận (tồn đọng: che khoá theo mẫu, report giả tự tạo, `ocr` lấy từ PATH).

1. **Gate:** `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests` khi load1 < ~60.
   - `--auto-approve-tests`: hai test cũ bị sửa — `tests/gates/test_regression_gate_held_by_other.sh` (của Đợt 31, chặt hơn) và
     `tests/worktree_git/test_worktree_immutable_copy.sh` (của phiên d1df0d47, chạy PASS).
   - `test_budgets.sh` đỏ khi máy quá tải; HEAD đỏ y hệt (đo A/B 13/10) — không phải do Đợt 31.
   - Đừng kill script đang chờ khi gate con của nó đã chạy: 13/10 một gate mồ côi chạy tiếp trong lúc sửa file → không ghi biên nhận.
2. **Commit đúng file của Đợt 31** (tất cả dưới `universal-agent-devkit/` trừ hai file `.agents/`), `git add` từng file rồi `git commit`
   KHÔNG kèm pathspec — mục CHANGELOG Đợt 31 đã nằm sẵn trong index; CHANGELOG ở cây làm việc còn chữ Đợt 30 chưa commit của phiên d1df0d47,
   **không bao giờ `git add` CHANGELOG từ cây làm việc**:
   - `AGENTS.md`, `bin/regression_checklist.py`, `bin/ocr-review`, `hooks/regression_gate.sh`, `hooks/review_gate.sh`,
     `scripts/context/enrich_context.py`, `skills/devkit-audit/SKILL.md`, `skills/devkit-audit/references/procedure.md`,
     `skills/devkit-audit/references/rubric.md`, `skills/open-code-review/SKILL.md`, `tests/gates/test_regression_gate_held_by_other.sh`,
     `tests/gates/test_review_gate_ocr.sh`, `tests/gates/test_review_gate_ocr_full.sh`, `tests/installer/test_ocr_review_helper.sh`,
     `tests/verification/test_bug_secret_redaction.sh`, `tests/lib/test_durations.txt` *(đã sửa khi gộp 13/10: `docs/plans/goal-100-2026-10-13.md` không còn; nội dung của nó nằm ở file này, commit riêng, KHÔNG đưa vào commit Đợt 31)*;
   - `.agents/CHECKLIST.md`, `.agents/regression_status.json` (bug đã đăng ký: `BUG-20261013-bug-capture-copied-a-pasted-secret`,
     `BUG-20261013-regression-gate-held-skip-ignored-writers`, `BUG-20261013-opencodereview-never-ran-ocr-review-exit`).
   - KHÔNG đưa vào: `tests/verification/test_agent_kit_test_order.sh` (chưa rõ chủ), `Screenshot 2026-10-13 at 13.15.58.png`.
     `.agents/instincts-index.md` là mục lục sinh lại cho INSTINCT-038 (đã khớp `instincts.md` sau khi gộp `dot30b`): commit kèm được.
   - 15:40: bản dở cũ của d1df0d47 (`worktree.py`, `worktree_sandbox.py`, test immutable-copy, `instincts.md`, chữ Đợt 30) đã rời main —
     bản mới hơn của chúng vào main qua `dot30b` (`d5ef026`); bản cũ nằm trong `stash@{0}` (kèm mục CHANGELOG Đợt 31 cũ), dữ liệu gate của
     `dot30b` trong `stash@{1}`. Xoá hai stash này sau khi Đợt 31 đã commit.
3. `git show --stat HEAD` (pre-commit có thể stage thêm); `git fetch`; `git log --oneline origin/main..HEAD` (15:40: main đi trước origin
   16 commit chưa push — dashboard, mcpfix, plan MCP, `dot30b`, Sprite Forge và các merge tự động); origin đã đi → `git pull --no-rebase --no-edit`,
   gate lại, rồi push.
4. Antigravity `audit` (task > 200 dòng) qua `/giao`; RED-proof các bug trên; báo cáo nghiệm thu 4 mục.
5. Báo người dùng: công tắc `REVIEW_GATE_OCR=full` đã sẵn — đặt `"REVIEW_GATE_OCR": "full"` trong `env` của `~/.claude/settings.json`;
   mỗi lượt trừ credit LLM. `review_gate` sẽ đòi một review context sạch cho các sửa sau 13:50 (lượt OCR tự review chạy trước các sửa cuối).

**Khôi phục nếu một merge/pull vào main làm mất file:** ở gốc repo `tar -xf .agents/local/memory/dot31-backup-2026-10-13/files.tar`, rồi
`git apply --3way .agents/local/memory/dot31-backup-2026-10-13/staged-changelog.patch` (mục CHANGELOG Đợt 31 vào index và cây làm việc;
patch dựng trên `5ff3c68` nên sẽ xung đột ở đầu "Unreleased": giữ Đợt 31, Sprite Forge và Đợt 30 bản MỚI, bỏ Đợt 30 bản cũ trong patch, `git add`).

#### Việc 2 — Giai đoạn C: điểm bắt đầu
`guardc/guard.patch` (1010 dòng: `hooks/hardware_safety_gate.sh`, `hooks/block-dangerous-git.sh`, test mới `tests/gates/test_guard_shell_norm.sh`)
viết trên kit cũ hơn HEAD hiện tại — áp bằng `git apply --3way`, kiểm lại từng hunk. `shadow_report.txt`: replay 7 ngày, 20 897 lệnh Bash khác nhau
ở 5 repo; hardware gate chặn thêm 1 lệnh (0→2), git guard chặn thêm 1 (0→2), không lệnh nào bị nới (2→0) — xem 2 lệnh đó là chặn đúng hay nhầm
trước khi bật. Cần `/giao` plan_review + audit (task lớn, luồng bảo mật). Thêm việc 3 vào cùng bộ chuẩn hoá.

#### Việc 4 — chiều 5: điểm bắt đầu
`ctx5/kit.patch` (5 file kit) và `GeelyEx2.patch`, `Goods.patch`, `OfficeReader.patch`; `baseline_status.txt` là `git status` các repo lúc agent bắt đầu
(GeelyEx2 có sẵn việc dở của người dùng — chỉ đụng file của patch). Viết lại trên HEAD hiện tại; test bắt buộc: mọi dòng MUST / cấm / bất biến
vẫn nằm trong file luôn nạp (như Đợt 28 với android/game). Repo đang bị phiên khác giữ → worktree riêng.

#### Đã kiểm và BỎ (không phải lỗi)
- `worktree_merge_gate` giữ Stop khi main do một phiên khác còn sống giữ: có chủ ý và có test (`tests/gates/test_worktree_merge_gate_owner.sh`
  ca 4/4b) — buộc phiên chờ người giữ rảnh rồi tự gộp (luật người dùng 12/10), trần 3 lần.

### I.2 Plan C+D — không ai sửa trong main, một bộ gộp tuần tự (chưa duyệt, chưa code) *(trước đây: `docs/plans/trunk-integrator-no-shared-main.md`)*

Ngày 13/10/2026. Người dùng yêu cầu lập plan để làm sau. Trạng thái: **bản nháp chờ duyệt (Gate 1, `AGENTS.md` §5.1)**: chạm hook, khoá phiên và luật cô lập (Gate 2), nên không code trước khi người dùng duyệt.

#### 1. Vấn đề, có số đo (13/10)

Ba phiên cùng mở trên `agent-workbench` (`d1df0d47`, `cd6390a4`, `c01ac57e`) và ngồi đợi nhau:

- **Chờ do chính sách ở 2 chỗ, không do git.** `bin/session_lock.py` coi `agent-kit worktree finish|automerge` là ghi vào main (regex `GATE`, dòng 74); `hooks/worktree_merge_gate.sh` (dòng ~297–301) không gộp khi main có người giữ. `worktree.py automerge` đã tự từ chối khi trùng file sửa dở.
- **Chỉ trùng 1 file** trong commit 6 file đang chờ (`CHANGELOG.md`, do mục Đợt 31 của phiên khác).
- **Gate chậm và không ổn định:** 171 s, 507 s, 572 s, 884 s, một lần chạm 900 s; `test_worktree_merge_gate_owner.sh` đỏ ở cả 4 lần gate gần nhất. Load máy 195–344 khi 3 phiên cùng chạy.
- **Worktree mồ côi:** 7 thư mục `GeelyEx2-*`, 142–218 MB mỗi cái (gốc: cờ `uchg`, đã sửa ở Đợt 30). Đĩa `/Volumes/Data` đang 92–93 % đầy, còn ~11 GiB.

Gốc chung: **có một checkout chính mà người ta vừa sửa vừa dùng làm nơi gộp**, nên luôn có "người giữ main".

#### 2. Đích

- **C. Không ai sửa trong main.** Main chỉ là nơi gộp. Mỗi phiên làm trong worktree riêng của phiên đó.
- **D. Một bộ gộp tuần tự.** Mỗi lần một worktree: gộp main vào worktree (xử lý conflict ở đó), kiểm bằng gate nhẹ, rồi `ff-only` vào main. Hàng đợi dùng khoá `MAIN_LOCK` đã có trong `_automerge_locked`.
- Kết quả mong muốn: hết "đợi người giữ main", HEAD main không bị phiên nào giữ nên không nhảy dưới chân ai, mỗi phiên tự gộp xong mà không cần người dùng gõ.

#### 3. Thiết kế (bản lười: dùng lại cái đã có)

| # | Việc | Cách làm | Đã có sẵn |
|---|---|---|---|
| C1 | **Tạo worktree lười, theo phiên** | Lần ghi đầu tiên vào main của một phiên bị chặn, và hook tự chạy `agent-kit worktree add ../<repo>-<sid8>` rồi báo đường dẫn để phiên làm tiếp trong đó. Phiên chỉ đọc không tạo gì. Một phiên một worktree, tái dùng cho mọi việc của phiên. | `session_lock.py` đã chặn ghi và đã trỏ sang worktree; `worktree add` đã có; `worktree_guard` đã hiểu phiên đang ở trong worktree |
| C2 | **Main chỉ-gộp** | Ghi vào main chỉ cho (a) bộ gộp `finish`, (b) người dùng bằng công tắc `allow-shared`. Không còn khái niệm "người giữ main". | khoá phiên, `allow-shared` |
| D1 | **Bộ gộp** | Bỏ nhánh "main không rảnh thì không gộp" trong hook và bỏ `finish|automerge` khỏi `GATE`. Giữ `git merge --ff-only` và `MAIN_LOCK`. Trùng file sửa dở thì giữ lại, báo đúng tên file. | `_automerge_locked`, `MAIN_LOCK` |
| D2 | **Gate nhẹ khi gộp, full một lần** | Gộp chỉ cần gate test bị ảnh hưởng của worktree exit 0. `--full` chạy một lần ở cuối (phiên cuối hoặc nightly), theo đúng luật hiện có của DevKit; **không bỏ gate nào**. | `--run-tests`, chế độ impacted, `--force-full` |
| D3 | **File nóng không conflict** | `.gitattributes`: `CHANGELOG.md merge=union`, `.agents/instincts.md merge=union`. File bookkeeping của gate (`CHECKLIST.md`, `regression_status.json`, `instincts-index.md`) đã bị loại khỏi diff của worktree. | `BOOKKEEPING` trong `worktree.py` |
| D4 | **Dọn sạch** | Stop gộp rồi xoá worktree (đã có), kèm sửa `uchg` của Đợt 30 nên không còn mồ côi. Cộng một lệnh `worktree status` liệt kê cả thư mục mồ côi (hiện không ai thấy chúng). | `cmd_remove`, `worktree status` |

#### 4. Điều kiện tiên quyết (làm trước, độc lập với C+D)

1. **Sửa race của `worktree_merge_gate`**: hàng "gate error" cho thư mục vừa biến mất phải tính là đã xong, không phải đang giữ (`hooks/worktree_merge_gate.sh`, bộ lọc `vanished` bỏ qua hàng có `reason`). Nên chạy `inventory` riêng cho từng worktree để một thư mục mất không làm hỏng cả danh sách. Không có bước này, gate đỏ ngẫu nhiên làm mọi so sánh hiệu quả vô nghĩa.
2. **Gộp các commit đang chờ**: `aaf9805` ở `agent-workbench-dot30b` (xem `handoff-2026-10-13-gom-3-phien-chay-full-mot-lan.md`) phải vào main trước khi đổi luật.
3. **Đo cơ sở** (hiện chưa có số): thời gian `worktree add` kèm cài DevKit, thời gian `finish`, thời gian đợi khoá, dung lượng mỗi worktree. Ghi vào log gate để so trước và sau.

#### 5. Lộ trình

| Pha | Việc | Kiểm chứng (ĐỎ→XANH) | Dừng nếu |
|---|---|---|---|
| 0 | Mục 4: sửa race, đo cơ sở | test race tất định (chèn lỗi cho `inventory`), số đo cơ sở có trong log | race vẫn đỏ sau sửa |
| 1 | **D1+D3+D4** trong một repo thử (`agent-workbench`) | 2 phiên cùng repo không ai đợi; trùng file thì giữ lại và báo tên file; hai worktree gộp cùng lúc nối đuôi nhau | HEAD main nhảy làm gate phiên khác hỏng hơn mức chấp nhận |
| 2 | **C1+C2** (tạo worktree lười + main chỉ-gộp) | ghi vào main bị chặn và có worktree sẵn; phiên chỉ đọc không tạo worktree; công tắc tắt hẳn (`WORKTREE_TRUNK_MODE=0`) | một phiên bị kẹt không ghi được ở đâu cả |
| 3 | Lan sang `GeelyEx2`, `OfficeReader` | mỗi repo một vòng đo cơ sở trước và sau | đĩa còn dưới ngưỡng (xem rủi ro) |
| 4 | Cập nhật `AGENTS.md` §7.1, `rules/essentials.md`, thông báo của `session_lock.py`, `CHANGELOG.md` | test văn bản (các test hint đã có) | — |

#### 5.1 Test phải có (viết trước, thấy ĐỎ)

1. Hai phiên cùng repo, không phiên nào đợi (`test_worktree_merge_gate_owner.sh` case 4/4b viết lại: gộp khi không trùng, giữ khi trùng).
2. Ghi vào main từ phiên không phải bộ gộp thì bị chặn kèm worktree tạo sẵn (sửa `test_session_lock_target_repo.sh` dòng 253 và thêm case).
3. Phiên chỉ đọc không tạo worktree.
4. Hai worktree gộp đồng thời: tuần tự, không trộn index.
5. `CHANGELOG.md` hai phiên cùng thêm mục: gộp sạch, giữ cả hai.
6. Stop gộp và xoá worktree; thư mục `uchg` vẫn xoá được (`test_worktree_immutable_copy.sh` đã có).
7. Công tắc tắt trả về hành vi cũ.

#### 6. Rủi ro và điều chưa biết

- **Đĩa:** mỗi worktree là một bản checkout đầy đủ (17 MB cho `agent-workbench`, nhưng 142–218 MB cho GeelyEx2). Nhiều phiên × nhiều repo ăn nhanh vào 11 GiB còn lại. **Chưa tính được số phiên tối đa**; cần số đo ở pha 0.
- **Repo Unity (Goods, Neighbours-From-Hell):** thư mục `Library` rất lớn nên một worktree mỗi phiên có thể không khả thi. **Giả định chưa kiểm:** loại hai repo này khỏi C, chỉ áp D1 (gộp không đợi) cho chúng.
- **Thói quen làm việc:** nếu bạn mở IDE vào checkout chính để sửa tay thì đó là phiên ghi vào main. Cần quyết: người dùng được miễn (như `allow-shared`) hay cũng đi qua worktree.
- **Thiết bị adb:** một thiết bị phục vụ một worktree tại một thời điểm (luật hiện có), nên nhiều worktree song song vẫn phải chạy thiết bị tuần tự.
- **Memory:** note ghi trong worktree nằm ở thư mục riêng và được chép sang main khi `finish` (đã có), nhưng chưa kiểm khi nhiều worktree cùng ghi một `MEMORY.md`.
- **Hook cài đặt:** các sửa hook phải cài đúng cách; ghi chú cũ trong memory cho biết chế độ tự động có lúc chặn việc cài hook, nên có thể cần bạn xác nhận ở đúng bước đó.
- **Nới luật cô lập phiên:** D1 làm HEAD main nhảy khi phiên khác đang làm; phiên đó có thể phải chạy lại gate một lần. Sửa dở của họ không bao giờ bị ghi đè (git từ chối trên file trùng).
- **Ước lượng công sức: chưa đo.** Không đưa số ngày cho đến khi có số đo cơ sở ở pha 0.

#### 7. Cần người dùng quyết trước khi code

1. **Duyệt hướng C+D** (Gate 1) và nới luật cô lập phiên cho D1 (Gate 2, đụng `session_lock.py` và `worktree_merge_gate.sh`).
2. **Phạm vi repo:** chỉ 3 repo không phải Unity ở pha 1–3, đúng không?
3. **Người dùng có miễn trừ** khi sửa tay trong checkout chính không?
4. **Có chấp nhận `--full` chỉ chạy một lần ở cuối** (đúng luật DevKit hiện có) thay vì mỗi phiên?

#### 8. Việc còn lại (cập nhật cuối ngày 13/10, đo lúc ~14:00)

##### 8.1 Phải làm trước, độc lập với C+D
| # | Việc | Trạng thái đo được | Hành động |
|---|---|---|---|
| 1 | **Gộp worktree `agent-workbench-dot30b` vào main** | `aaf9805` (sửa theo review Đợt 30) và `204750d` (plan này) CHƯA vào main; `e4a16f3`, `33259ef` đã vào main và đã push | Khi phiên `c01ac57e` nhả khoá: khôi phục các bản cũ của chính mình ở main (`worktree.py`, `worktree_sandbox.py`, `test_worktree_immutable_copy.sh`, `.agents/instincts.md`; riêng `CHANGELOG.md` giữ cả mục Đợt 31), chạy `agent-kit worktree finish /Volumes/Data/Toan/agent-workbench-dot30b`, gate `--full --force-full --timeout 2400` exit 0, rồi `git pull --ff-only`/`--no-rebase` (kiểm exit code) và `git push origin main` |
| 7 | **Việc dở của hai phiên kia** | `cd6390a4`: chưa chạy `claude mcp list` cho 5 repo sau khi gộp; `c01ac57e`: Đợt 31 OCR (`REVIEW_GATE_OCR=full`, `hooks/review_gate.sh`, `bin/ocr-review`, 4 test mới) chưa commit — xem mục I.1 *(trỏ lại khi gộp)* | Hoàn tất trong phiên đó hoặc phiên mới theo bản bàn giao `handoff-2026-10-13-gom-3-phien-chay-full-mot-lan.md` |

*(Hàng #2 đến #6 của bảng gốc: gate chưa có biên nhận, race `worktree_merge_gate`, xoá hoặc kiểm thư mục và worktree sót. Chúng là issue/bug nên nằm ở `issues-bugs.md` mục A.2, giữ nguyên số `#`; thứ tự đề nghị ở 8.3 vẫn nói về các số đó.)*

##### 8.2 Khoá chính sách (đang chờ người dùng)
Việc nới chính sách khoá cho D1 (xoá `finish|automerge` khỏi regex `GATE` trong `bin/session_lock.py`; bỏ nhánh "main không rảnh thì không gộp" trong `hooks/worktree_merge_gate.sh`; sửa test `test_worktree_merge_gate_owner.sh` case 4/4b và `test_session_lock_target_repo.sh` dòng 253; cập nhật `AGENTS.md` §7.1) **bị hệ thống tự động từ chối ngày 13/10** (nhãn "Security Weaken"). Chưa có thay đổi nào được ghi. Cần người dùng: một câu xác nhận trong chat (agent thử lại), hoặc thêm rule `Edit` cho các đường dẫn trên trong settings.

##### 8.3 Thứ tự đề nghị sau khi duyệt
1. Mục 8.1 #1–#3 (gộp, gate, sửa race) → có biên nhận sạch.
2. Pha 0 của mục 5 (đo cơ sở: thời gian `worktree add` kèm cài DevKit, `finish`, thời gian đợi khoá, dung lượng mỗi worktree).
3. Pha 1 (D1+D3+D4) trên `agent-workbench`, rồi pha 2–4 theo mục 5.
4. Dọn 8.1 #4–#6 song song, không chặn.

##### 8.4 Chưa đo / chưa kiểm
- Thời gian tiết kiệm của C+D (chưa có số đo cơ sở); công sức triển khai.
- C với repo Unity (Library lớn) và với nhiều thiết bị adb.
- Có xảy ra `HEAD` nhảy làm hỏng gate phiên khác ở mức nào (pha 1 sẽ đo).

### I.3 Proposal — catch the bugs an agent cannot see (state-matrix, device-first, wiring pins) *(trước đây: `docs/plans/catch-bugs-agents-cannot-see.md`)*

> **Trạng thái bổ sung khi gộp (13/10):** file gốc ghi "PROPOSAL — nothing here is implemented" (07/10). CHANGELOG sau đó có Đợt 6a–6d (08/10) nêu nguồn là plan này: 6c = P1 (bằng chứng TRƯỚC khi sửa), 6d = mẫu P2/P3 cho android, 6b = hook biên dịch test nhường khoá của cổng và nhớ duyệt sửa test theo nội dung (đúng nội dung P5 và P8), 6a theo "nhóm S a và d" (lint test chỉ-kiểm-tồn-tại, bài học đi từ dự án lên kit, gần với P10). P4, P6, P7, P9: chưa đối chiếu. Phần gốc bên dưới giữ nguyên.


Source: OfficeReader session of 2026-10-07 (profile `android`). Written by the agent at the user's request
("gửi qua devkit để nó bổ sung kiểu này để bắt bug, chạy test kiểm tra tốt hơn").
Status: PROPOSAL — nothing here is implemented; every item names how to prove it works.

#### 1. What happened (evidence, not opinion)

Four user-visible defects shipped through green unit tests, a full post-fix gate (exit 0, 7/7 regression
groups) and a first code review. Each was found by something else:

| Defect | Why tests and gate were green | What found it |
|---|---|---|
| PDF "Translate" got 1-2 words: the END selection handle of a short word (~60 px) sat inside the 80 px radius of the START handle, which was tested first | The selection logic lives in an Android `View` over native PDFium: zero tests. The translate tests used a fake engine and a fixed string. | The user, on a phone; then `adb input swipe` + the sheet showing the source text "a" |
| Page pill ~75 dp above the bottom dock (`windowInsetsPadding(navigationBars)` applied inside an area the Scaffold had already padded) | Robolectric Compose runs with insets = 0, so a doubled inset is invisible | The user, on a phone; then `ui-query` bounds (210 px → 30 px) |
| Same pill drawn over a spreadsheet's own 44 dp tab strip | Nothing models the viewer's own bottom chrome | The agent's own device screenshot of an XLSX, after the user said "display is ugly" |
| Landscape + 3-button nav: pill under the side navigation bar; `.xlsb` has tabs on top, not bottom | State combination never enumerated | A fresh-context reviewer reading the code state by state |

Common cause: the agent reasons from code and trusts green checks. Bugs that come from real geometry or from
combinations of states are outside both. The only things that caught them were (a) a real device, (b) a person
or reviewer who enumerated states.

#### 2. Proposals

Each item: change, then how to prove it.

**P1 — Device-first reproduction for UI / gesture prompts.**
When the prompt classifier says UI_INTERACTION or a bug is reported about something the user sees or touches,
the first plan step is a reproduction on a device (before reading code), and the handover must carry a *before*
and an *after* artefact (screenshot or `ui-query` bounds by test tag). `proof_gate.sh` today checks only the
*after* PNG. Proof: a bug-fix reply with only an after PNG is refused with "BEFORE evidence missing".

**P2 — A "state matrix" step before a layout/overlay change is called done.**
Skill + reviewer lens that forces a table: document types × orientation × navigation mode (gesture / 3-button) ×
bars hidden × edit strips × TTS player × font scale 200 % × RTL × display cutout, one line of outcome per cell.
Add the lens to `principal-code-reviewer` and `council-*` prompts. Proof: replay today's four defects through
the lens; each must surface as a table cell marked "overlaps" or "unchecked".

**P3 — Overlap-invariant test template for Compose (profile `android`).**
A helper that renders a screen under injected `WindowInsets`, orientation and font scale, collects the bounds of
all interactive overlays by test tag, and asserts: no two intersect, each >= 48 dp, none under a system bar.
Proof: the helper, run on OfficeReader's reader screen at commit `7ee3d230a^`, fails on the doubled inset.

**P4 — Wiring pins when logic is extracted from an Android View.**
The vacuity gate correctly called a pure-helper test empty (reverting the view left it green). Make the next
step automatic: when a new `internal object` is created next to a `View` file and a test targets only the
object, generate a source-text pin test that asserts the view still calls it (and no longer contains the old
branch). Proof: reverting the view's call site turns the pin red.

**P5 — Do not let Stop hooks run Gradle while a gate run holds it.**
`testsourceset_gate.sh` compiled `:app` while `post-fix-gate.py` was running; the result was AAPT "resource
string/app_name not found" — a false P0. Serialise on the gate's lock, or report BUSY like `regression_gate.sh`
does. Proof: start a gate, trigger Stop; no AAPT error, hook reports BUSY.

**P6 — Commit-closure check at edit time, not at commit time.**
My edit lived in an *untracked* file produced by another session's refactor. Nothing said so until a reviewer
noticed that the file could not be committed alone and HEAD still held the old block. Add a check: for every
changed path, warn when it is untracked, or when HEAD's version of the same symbol is elsewhere; offer
`git archive HEAD` + overlay of the paths to be committed and compile that. Proof: the scenario above is flagged
the moment the file is edited.

**P7 — Scope `regression_invariants` to what is committed.**
It scanned another session's untracked test and blocked an unrelated commit (`?: return@collect` in a collector
lambda, which is also a false positive of the `TEST_EARLY_RETURN` rule). Scan staged + modified-tracked paths;
treat untracked foreign files as warnings. Proof: the commit goes through with that file present.

**P8 — Remember test-edit approvals by content hash.**
The same 7-15 edited tests were re-listed on every Stop (more than ten times in one session) after the user had
approved them twice. Store the approval (path + content hash) and honour it in `regression_gate.sh`; re-ask only
when the hash changes. Proof: approve once, stop twice, no second prompt; edit the file, prompt again.

**P9 — Telemetry rule for user-supplied selections (profile `android`).**
Features that act on a user selection should log a size bucket (never the content). A feature whose requests
are almost all 1-2 words is a signal no test gives. Proof: lint/rule text added; sample event name + bucket
scheme documented next to the PII rule.

**P10 — Upstream generic traps.**
`agent-kit learn` writes only to the project's `instincts.md`. When the trap is not project-specific
(overlapping touch targets must be nearest-wins; no `windowInsetsPadding` inside an area already padded by the
Scaffold), offer to copy it to the profile's instincts. Proof: the two traps from this session appear in
`profiles/android` after the command.

#### 3. Suggested order

P1 + P2 (process, cheap, would have prevented most of today) → P3 + P4 (tests that outlive the session) →
P5 + P6 + P7 + P8 (friction that cost the most time this session) → P9 + P10.

#### 4. Not claimed

No item here has been tried in this repo. P3's claim that Robolectric inserts zero insets is observed, not
measured for every API level. The OfficeReader fixes referenced are commit `7ee3d230a` (selection) and an
uncommitted working-tree change (pill, overlay stack).

## Phần II — Đã làm (giữ để biết vì sao và cách đo)

### II.A DevKit chạy nhanh: nghiên cứu 04/10/2026 và kế hoạch 3 đợt *(trước đây: `docs/plans/devkit-speed.md`)*

> **Trạng thái bổ sung khi gộp (13/10):** file gốc đánh dấu 1c "CODE XONG 07/10". CHANGELOG có Đợt 0 (04/10, "plan `docs/plans/devkit-speed.md`"), Đợt 1a (05/10, mục 3b) và Đợt 4 (07/10, mục 1c). Các mục còn lại chưa đối chiếu. Các lỗi tồn đọng nêu trong plan này được liệt kê ở `issues-bugs.md` A.4.


Ba agent chỉ-đọc đã đo trên 4 repo (workbench, GeelyEx2, OfficeReader, Goods); số quét ảnh đã được kiểm lại độc lập. Máy: M4 Pro, 12 lõi (8 hiệu năng), 24 GB RAM. Nguyên tắc cứng: gate và hook là cổng an toàn, chỉ làm CÙNG kiểm tra ít lần hơn, song song, hoặc cache đúng khóa (INSTINCT-017); không nới kiểm tra nào.

#### 1. Số đo
Mỗi lần gate/Stop trong repo app (Geely / Office / Goods):
- Quét ảnh proof (run_proof_block): 121 s (171 PNG) / 97 s (170) / 135 s (157), chạy cả khi chỉ sửa tài liệu; 0,6-0,9 s/ảnh bằng Python thuần (đã tự kiểm). Tổng trong 8-12 ngày: Geely 8,0 giờ (510 lượt gate), Office 4,9 giờ (462), Goods 1,0 giờ (82).
- Quét ảnh chỉ phục vụ cảnh báo mức warn (giống nhau); hash tham chiếu vẫn tính dù không có ảnh mới (bin/post-fix-gate.py ~2679-2683, gọi ~3887; scripts/testing/proof_phash.py 27-59, 116-131). Pillow: 14,6 ms/ảnh thay 729 ms, bit giống hệt 42/42 mẫu.
- local_state_sha gọi 2 lần/lượt full: 2,1 / 3,6 / 0,25 s. Lớp tĩnh+checklist 0,7-2,4 s.
- Hook Stop chờ khóa test 120 s rồi trả "bận" (hooks/regression_gate.sh:507; CLI 900 s): 73 lần trong ~8 ngày (Geely 24, Office 10, Goods 6, workbench 33), tối thiểu 2,4 giờ, kết quả UNTESTED không cache.
- Suite chạy tuần tự (post-fix-gate.py:3663-3796, một Popen ở 3730). Tổng trung vị / suite dài nhất: Geely 356/156 s, Office 571/194, workbench 597/189, Goods 281/210 (trần tăng tốc 2,3x/2,9x/3,2x/1,3x). Chỉ 2/46 suite Geely có impacted_command; 393/404 log Geely là full.
- Hoãn --full khi có phiên khác (exit 5, post-fix-gate.py:3542-3560, 4010-4021) rồi --force-full chạy lại cả bộ vì tái dùng là tất-cả-hoặc-không trên một biên nhận (3608-3625). Tần suất chưa log.
- Game REG-GAME-03: bản impacted 300-311 s chậm hơn bản full 210 s.
Bộ test kit (agent-kit test = tests/run_impacted.sh --all): 109 test, tổng 20,5 phút tuần tự, trung vị 2,9 s, 65/109 dưới 5 s, 14 test chậm nhất = 13,1 phút (64%): test_proof_gate 137 s, test_postfix_gate 82, test_install_cli 77, test_local_tier 71, test_install_idempotency 61. DEVKIT_TEST_JOBS mặc định 4 (dòng 67) trên máy 12 lõi, danh sách theo thứ tự bảng chữ cái. ĐO CƠ SỞ (máy yên, 04/10): `run_impacted.sh --all` = **301 s** cho 102 test, tất cả qua = ≈288 s giai đoạn song song + ≈13 s cho hai test chạy riêng (test_budgets 3 s, test_session_context 10 s); test dài nhất test_proof_gate một mình 137 s. Tổng thời gian các test ≈1230 s / 4 luồng ≈ 307 s: hiện bị giới hạn bởi SỐ LUỒNG, chưa phải bởi đuôi. Trần với 10 luồng ≈ max(137 s, ≈123 s) + 13 s ≈ 165-170 s. (Con số '14,1 phút' ở bản đầu của kế hoạch là của bộ chạy theo lô do phiên nghiên cứu tự dựng, không phải của script thật: đã sửa.) Một phần test chậm là ngủ/đợi (ước 59 s trong 138 s của test_proof_gate).
Mỗi lượt chat (hook): hook cùng sự kiện chạy SONG SONG (thời gian = hook chậm nhất). DevKit ≈ 1,7-1,8 s/lượt (≈ 610 tiến trình, ≈ 90 lần khởi động python). PreToolUse Bash nhóm ≈ 62-65 ms; session_lock.sh chậm nhất 56 ms (2 python + 2 git, thật sự cần ≈ 10 ms); đường nhanh của block-dangerous-git/hardware_safety_gate chỉ phủ 6-11% lệnh thật (52k lệnh phát lại). Stop: 6 hook ≈ 201 ms (transcript 88 MB: 331 ms); proof_gate quét cả transcript trước khi thoát sớm (đọc ngược 0,3 ms thay 42 ms); security_gate 194 ms; churn_guard readlines() toàn transcript mỗi Edit; worktree_guard `tail|grep` nguội 2,25 s ở 88 MB (python 10 ms). SessionStart 4,4 s, trong đó git ls-remote qua ssh 3,6 s (ControlPersist: 0,6 s), chạy cả khi resume/clear/compact. Hook bên thứ ba codebase-memory-mcp hook-augment (trong ~/.claude/settings.json của người dùng, KHÔNG phải DevKit) ≈ 1,3 s mỗi grep/rg/git grep/Grep/Glob/Read, chỉ có output 2-9% lần Read. Hook set sys.dont_write_bytecode nên sau mỗi lần sửa kit chúng biên dịch lại mỗi lần chạy (+17 ms cho regression_checklist). GeelyEx2 có hook riêng rebuild-dist.sh thêm 5-23 s/Stop.
Chạy nhiều agent: mỗi agent một worktree riêng ĐÃ song song được (khóa test, đăng ký phiên, biên nhận theo thư mục git; hai commit song song xong 0,04 s; cp -Rc 13,4k file 1,86 s/12 MB so với cp -R 4,21 s/530 MB; agent-kit worktree add 8,4 s). Nghẽn nằm TRONG một checkout: phiên thứ hai chỉ-đọc (bin/session_lock.py:454-475); hoãn exit 5; một khóa test cho cả dự án (post-fix-gate.py:2772-2808); biên nhận 1 file/thư mục git nên cùng nội dung ở 3 worktree vẫn chạy lại (tree_fp.py:27, post-fix-gate.py:648,714); regression_status.json/CHECKLIST.md (có track ở workbench/Geely/Goods) xung đột khi gộp (post-fix-gate.py:4050, scripts/git/worktree.py:372); proof-capture.py không có khóa thiết bị; RAM: Gradle -Xmx8g/-Xmx4g nên chỉ vừa 2-3 gate nặng cùng lúc. Thiếu: hook WorktreeCreate/SubagentStart/Stop; cmd_add (worktree.py:202) không clone Library của Unity; worktree_sandbox.py:161 chỉ clone node_modules; worktree ghi memory vào thư mục rỗng cục bộ; .sandboxes/ chỉ được ignore ở workbench. LƯU Ý thêm (phiên nghiên cứu vừa gặp): hook session_lock.sh chặn cả Write vào scratchpad NGOÀI checkout khi phiên khác giữ khóa. Cho Write ngoài checkout đi qua là NỚI một cổng nên KHÔNG nằm trong Đợt 0: xem câu hỏi 3.6.

#### 2. Kế hoạch và quyền sở hữu file
Đợt 0 (độc lập, chạy song song, vài giờ):
- 0a Quét ảnh: chỉ hash tham chiếu khi có ảnh mới; cache hash theo sha256 trong .git/postfix-gate/ (ghi nguyên tử); đường nhanh Pillow (đọc IHDR như `_png_luma`: chỉ bit 8, không interlace, color 0/2/6, còn lại None như cũ; lấy đúng 72 điểm mẫu rồi áp công thức độ sáng CỦA KIT `(r*3+g*6+b)//10`, KHÔNG dùng `convert("L")` 299/587/114), lùi về Python thuần khi có ngoại lệ. Sở hữu: bin/post-fix-gate.py (run_proof_block), scripts/testing/proof_phash.py. Chứng minh: dựng ORACLE `{đường dẫn: [sha256, dhash]}` bằng mã CŨ trên mọi ảnh thật (reports/, .claude/audit-gate/, .agents/evidence/ của 4 repo) TRƯỚC khi sửa; sau khi sửa 4 chế độ (cache lạnh, cache ấm, Pillow, ép Python thuần) đều giống oracle từng bit; test dhash cũ (test_gate_fixes.sh) xanh; test ghép đôi cùng finding + khẳng định thời gian; byte-identical và zero-byte vẫn chặn.
- 0b Hook chờ khóa 120 s → 45 s (số chọn sau khi đo log: 73 BUSY/8 ngày, các lần chờ thật 33,8-41,4 s vẫn chạy được test); thăm dò biên nhận/khóa CHƯA làm (đợt 1). Sở hữu: hooks/regression_gate.sh. Chứng minh: ĐO TRƯỚC từ log thật bao nhiêu lượt Stop chờ khóa 15-120 s rồi vẫn chạy được test (hạ chờ sẽ biến chúng thành UNTESTED) rồi mới chọn số; mở rộng test_regression_gate_hook.sh: khóa bị giữ → BUSY (exit 4, không cache, không PASS) trong ≤ 20 s; XONG vẫn cần biên nhận full.
- 0c Test kit song song theo số lõi (mặc định ≈ min(lõi-2,10), DEVKIT_TEST_JOBS vẫn ghi đè) và test dài chạy trước (file thời lượng, lùi về thứ tự cũ). Sở hữu: tests/run_impacted.sh. Chứng minh: cùng tập test, cùng exit, cùng thứ tự output; test đo thời gian (test_budgets, test_session_context) vẫn chạy riêng; đo --all trước/sau (301 s → mục tiêu ≈ 170 s, gần 1,8 lần; thứ tự dài-trước chỉ có tác dụng khi số luồng ≥ ~8).
- 0d SessionStart: git ls-remote chạy nền hoặc chỉ khi source=startup; ghi chú ControlPersist cho ~/.ssh/config (KHÔNG tự sửa file đó). Sở hữu: hooks/session_context.sh. Chứng minh: test remote trần: báo ahead/behind không đổi khi fetch xong; không mạng thì không chờ.
- 1a-1 (độc lập, làm cùng đợt) proof_gate.sh + devkit_harness.turn_start đọc ngược theo khối (KHÔNG giới hạn pushed_in_turn: đổi nó là đổi quyết định); vá luôn lỗi fail-open có từ trước khi chưa biết mốc đầu lượt (NameError tp/time trong heredoc làm hook thoát 0 = cho qua; mốc = entry user thật cuối cùng, bỏ isMeta của Stop-hook/ảnh/skill/notification, receipt hỏng thì chặn); GIỮ NGUYÊN mọi tên/chữ ký công khai (7 file khác import devkit_harness.py). Sở hữu: hooks/proof_gate.sh, hooks/devkit_harness.py. Chứng minh: kết quả cũ = mới trên mọi transcript thật và tại các điểm cắt ngẫu nhiên.
- 1a-2 (độc lập) CHỈ TỐI ƯU, quyết định y hệt: worktree_guard.sh thay `tail|grep` nguội bằng tìm byte python (`python3 -I -S`, vì `-c` nạp module trong cwd của repo). ĐÃ BỎ khỏi đợt này: session_lock.sh bản nhanh bằng bash (reviewer tìm ra 2 lệch nới lỏng: `.git` lồng nhau git từ chối, key trùng trong payload; chỉ tiết kiệm ≈ 40 ms ở hook chạy song song, không nằm trên đường găng) và biên dịch trước .pyc (lợi ≈ 19 ms). Sở hữu: hooks/worktree_guard.sh. Chứng minh: bảng tương đương cũ/mới theo từng trạng thái khóa (exit code + stdout + stderr từng byte).
Đợt 1 (sau khi 0a gộp; một người sở hữu post-fix-gate.py theo thứ tự 1b → 1c → 1d):
- 1b Cache PASS theo từng suite, dùng ĐÚNG khóa của biên nhận: tree_fp + matrix_sha + local_sha + RESULT_FORMAT + id suite + hash lệnh; loại DEVICE_SUITE; đặt ở <git-common-dir>/postfix-gate/by-fp/<fp>.json; ghi từ lượt Stop của suite chế độ full; đọc ở post-fix-gate.py ~3608 và ~648. full_pass.json vẫn theo từng worktree vì push_gate.py đọc nó. Chứng minh: sau một lượt bị hoãn, --force-full chạy 0 suite; test ĐỎ: khóa khác nhau không bao giờ dùng chung PASS.
- 1c [CODE XONG 07/10, Đợt 4 (CHANGELOG): cờ `parallel_safe` đọc từ ma trận base-ref, mặc định tuần tự] parallel_safe theo từng suite trong ma trận (mặc định tuần tự; vacuity_revert độc quyền; Gradle/Unity tuần tự) ở post-fix-gate.py:3663. Ứng viên đã đo: workbench 479 → ~340 s (≈200 s nếu gồm ALL-01), suite script Geely chạy chồng lên CAR-01, chuỗi QA-CONTRACTS của Office bằng xargs -P (ước tính).
- 1d Nhận worktree-riêng-cho-mỗi-agent: gate trong worktree liên kết dùng --no-checklist; worktree diff bỏ file checklist có track (worktree.py:372, post-fix-gate.py ~4050); bỏ hoãn exit 5 khi phiên kia ở worktree KHÁC (giữ khi cùng một checkout); autoMemoryDirectory của worktree trỏ về claude-auto/ của main; thêm --detach cho cmd_add (luật 1 nhánh).
- Lặt vặt: local_state_sha tính một lần/lượt (2-7 s); base_text qua git cat-file --batch (1045-1052); đồng bộ ba danh sách loại trừ (tree_fp.EXCLUDE, devkit_harness.OWN, danh sách own của regression_gate.sh:189; instincts-index.md bị ghi lại lúc SessionStart mà không nằm trong EXCLUDE); security_gate tăng dần (offset cache kiểm kích thước+inode+hash, lùi về quét đầy đủ; tập cờ giống hệt tại các điểm cắt ngẫu nhiên của mọi transcript thật) và churn_guard đọc đuôi.
Đợt 2 (lớn hơn; HỎI người dùng trước khi làm từng mục): bể slot theo tài nguyên (gốc Gradle, dự án Unity, serial thiết bị; mẫu scripts/testing/red_proof.py:247 proof_slot); agent-kit worktree land (rebase, gate MỘT lần, fast-forward, gỡ worktree); khóa thiết bị cho bin/proof-capture.py; clone Library (cp -c, red_proof.py:317 furnish) trong cmd_add; daemon unix socket cho cổng Pre Bash/Edit (62 → ~25 ms/lượt, rủi ro cao: fail-closed, mã cũ, truyền env); async:true CHỈ cho hook ghi sổ (bash_write_ledger PostToolUse, read_ledger), tuyệt đối không cho cổng.

#### 3. Việc cần người dùng quyết (agent KHÔNG tự làm; hỏi bằng AskUserQuestion)
1. Hook codebase-memory-mcp hook-augment trong ~/.claude/settings.json (cấu hình của người dùng): bỏ hoặc thu hẹp (chỉ Read/Grep lớn)? Tiết kiệm 3-4 s/lượt.
2. covered_by trong ma trận Geely (bỏ chạy lại 9 lớp REG-CAR-VOICE đã nằm trong testDebugUnitTest của REG-CAR-01; 42-54 s): đổi lược đồ ma trận.
3. Game REG-GAME-03: quay về lệnh full khi thời lượng impacted ghi nhận > full (_recorded_seconds, ~3092-3114); có thể bỏ kiểm tra vacuity của suite đó.
4. Daemon cho cổng Pre-tool, và async cho hook ghi sổ.
5. .gitignore của ba repo app (.sandboxes/): sửa từng repo.
6. session_lock.sh có nên cho Write/Edit vào đường dẫn NGOÀI checkout đi qua khi phiên khác giữ khóa? (hiện chặn cả scratchpad; cho qua là nới cổng).
7. Lớp lỗi có từ trước, ở MỌI hook: `python3 -c` / heredoc chạy với cwd là repo nên module trong repo (mmap.py, re.py...) che thư viện chuẩn (session_context.sh:31, regression_gate.sh:79,94, proof_gate.sh:56, worktree_guard.sh khối quyết định...). Cách chữa `python3 -I`; đợt 0 chỉ tránh thêm chỗ mới.
8. Lớp lỗi có từ trước: `open()` chặn trên state agent ghi được nên một FIFO treo gate/hook (post-fix-gate.py: cached_full_pass ~L659, acquire_test_run_lock ~L2817, đọc ảnh ~L2691, last_report ~L4100, last_output ~L4199; proof_gate.sh ~L250/254/268; push_gate.py ~L249). Đợt 0 chỉ vá chỗ mới (cache băm ảnh).

#### 3b. Nghiên cứu thêm sau Đợt 0 (04/10, đo trên máy dùng chung, chưa cài gì)
Cổng ở ba repo app (log 24/09-03/10): suite chỉ chiếm 28/31/40 % thời gian Stop (Geely/Office/Goods); phần còn lại là quét ảnh (0a), kiểm tĩnh, chờ khóa (0b). BUSY thật 24/10/6 lượt (139-357 s); exit 5 = 0 trong 488 lần gọi CLI nên BỎ mục "bỏ hoãn exit 5" khỏi 1d. `_recorded_seconds` (~3092) chỉ có một nơi gọi là pre-commit; đường Stop/--full dùng `plan_test_run` (~2464): mục 3.3 nhắm nhầm hàm.
Xếp theo lợi / rủi ro (rủi ro = đổi quyết định PASS/FAIL):
- Sửa thứ tự `cached_full_pass`: tính `tree_fp` (0,25 s) trước `local_state_sha` (3,8-6,4 s ở Geely/Office); cùng điều kiện AND, chỉ đổi thứ tự: ≈ 4-5 s mỗi lần gate có biên nhận khớp. Rủi ro không. Cỡ S.
- Pre-commit: 58-60 trong 72 commit DevKit rơi vào ngưỡng kill 60 s (≈ 7 phút/ngày). Ước lượng thời gian từ `run_impacted --list` + file thời lượng TRƯỚC khi chạy, bỏ qua (untested) suite > 30 s: verdict y hệt vì suite bị kill vốn không có verdict. Cỡ S/M, ở post-fix-gate.py.
- `agent-kit test` ≠ `run_impacted.sh --all`: nó chạy TUẦN TỰ trước pool hook_contract 42,8 s + or_ported 13,6 s + `node --test` 22,6 s ≈ 79 s. Cho chạy song song với pool, in đúng thứ tự: cỡ S, bin/agent-kit.
- test_proof_gate: 14 nhóm kịch bản chạy đồng thời và commit lùi ngày thay `sleep 1.1` (43 s): 139,8 → 19,0 s, 55/55 ca, 6 đột biến cho tập hỏng giống bản cũ. Cỡ M (sửa test có sẵn: auto-approve-tests).
- session_lock.sh: nằm TRÊN đường găng của PreBash (nhóm hook 67,8 ms với nó, 43,8 ms không có). Chỉ nên thay `python3 realpath $0` bằng vòng readlink trong bash (-18 ms/lệnh Bash; 0,19-0,31 s/lượt ở repo app; 112 ca bảng tương đương 0 lệch). KHÔNG làm bản nhanh bằng regex (2 lệch nới lỏng).
- Hook Stop `testsourceset_gate` ở repo app: 200/493 lượt Stop nặng (trung vị 3,1 s, tổng 1 giờ/8 ngày ở OfficeReader), 77-79 % không có Edit/Write từ lượt trước; cache theo tree-fingerprint đã có nhưng trượt nhiều (vì sao: chưa biết). Việc đầu tiên là GHI log lý do trượt (S, không đổi quyết định).
- Không đáng làm: cache PASS theo từng suite (≈ 2,5 phút/ngày ở Geely, Goods 0 vì toàn Unity; phơi nhiễm PASS-rồi-FAIL 5/576, 3/14, 6/125 là cận trên); bỏ retry flaky; chồng kiểm tĩnh; khởi động Gradle; mở rộng đường nhanh của hai cổng Bash (chỉ phủ 7-9 % lệnh thật).
- Cần người dùng: hook `hook-augment` của codebase-memory trong ~/.claude/settings.json tốn 1,35-1,4 s mỗi lần Read và ≈ 1,3 s trên ~11 % lệnh Bash (đo ở mục 3.1: lớn hơn mọi mục trên cộng lại); `covered_by` CAR-VOICE trong CAR-01 (820 s/10 ngày); dùng lại kết quả Unity (≈ 8 phút/ngày, rủi ro cao nhất).
- Lỗ hổng bảo mật tìm thấy khi nghiên cứu (đã giao vá): file `json.py`/`shlex.py` ở thư mục làm việc của hook làm hook thoát 0/1 thay vì chặn: vô hiệu hóa hardware_safety_gate.sh và block-dangerous-git.sh; và `cd $VAR; cd /tmp; rm -rf <ngoài project>` làm hardware_safety_gate crash TypeError (exit 1 = không chặn).
- Phát hiện phụ: tests/verification/test_run_impacted.sh dùng `pgrep -f test_slow_` toàn máy (hai bản chạy chồng nhau làm hỏng 3 check); 6 test trong hooks/tests/ (~45 s) không nằm trong --all, agent-kit test hay ma trận; impact_map thiếu `adapters/*` và `scripts/git/backup_conflict.sh` (các test cài đặt không được chọn khi file đó đổi).

#### 4. Đo sau mỗi đợt
- Bộ test kit: time bash universal-agent-devkit/tests/run_impacted.sh --all (cơ sở: 301 s, đo 04/10 trên máy yên).
- Quét ảnh: bấm giờ run_proof_block hoặc dhash trên reports/proof-*.png của Geely/Office/Goods (cơ sở 97-135 s/lượt).
- Gate trên thay đổi chỉ tài liệu, mỗi repo app: thời gian Stop hook từ lúc bắt đầu đến kết quả (cơ sở ≈ 120-135 s).
- Số kết quả BUSY và exit 5 mỗi ngày (cơ sở 73 BUSY / 8 ngày; exit 5 chưa log: thêm log trước).
- Thời gian từ "xong việc" đến "đã gộp" của một agent chạy trong worktree riêng.

#### 5. Chưa đo được
Tần suất --full bị hoãn (exit 5 không log); chạy lại cùng cây; thời lượng chạy lại vacuity; tăng tốc song song thật; thời gian hook Pre/PostToolUse thật (Claude Code chỉ ghi durationMs cho hook Stop hoặc hook có output); hit-rate cache Gradle trong worktree lạnh; thời gian clone Library (ước ≈ 6 s); hành vi Antigravity trên đường dẫn worktree; foreign_repo_gate.sh với worktree.

### II.B Plan V3 — Living Regression Checklist (tự động tối đa, chất lượng trên hết) *(trước đây: `docs/plans/regression-checklist-v3.md`)*


> Chủ: người dùng là senior "siêu lười": agent + hook làm hết, người chỉ duyệt việc không đảo ngược
> được. Luật tối thượng: **một bước tự động có thể tạo PASS giả hoặc che một lỗ hổng thì lùi về
> nhắc, không đoán.**
> Phạm vi: DevKit (`universal-agent-devkit`) + 3 dự án cài symlink: GeelyEx2 (automotive),
> OfficeReader (android), Goods-Triple-Shelf-Match-3D (game). Chỉ Claude + Gemini (không Codex/Cursor).

#### 0. Đã có — không làm lại

- `.agents/regression_status.json` là dữ liệu gốc (máy ghi); view Markdown sinh lại từ đó.
- PASS/FAIL chỉ đến từ `postfix-gate --run-tests` / Stop regression gate chạy test thật; mỗi lần chạy
  lưu `duration`, `exit_code`, `commit` (`+dirty`).
- `agent-kit bugs import|add|link|drop`; trạng thái OPEN / NEEDS_TEST / NOT_IN_MATRIX / NOT_RUN /
  REPORTED; prompt tả bug → dòng REPORTED; Stop nhắc link test ĐỎ→XANH 1 lần; SessionStart hiện số đếm.
- Ma trận `.agents/regression_matrix.active.json` (file đổi → suite phải chạy); gate chỉ tin ma trận đã commit.
- Stop gate kiểm "đã fix" cần cặp ĐỎ→XANH trong phiên; `review_gate` chặn dừng khi code đổi chưa review.

#### 1. Nguyên tắc bất biến

1. **Không PASS nếu không chạy thật.** Chữ ký: `Test | Thời gian | ExitCode | Commit | Log`. Không lệnh nào đánh PASS tay.
2. **Một nguồn sự thật.** JSON = dữ liệu; `CHECKLIST.md` = màn hình sinh lại, không sửa tay;
   `INBOX.md` = của người dùng, **agent không ghi một byte nào vào đó**.
3. **Mỗi "agent phải…" có hook/gate ép**; không ép được thì ghi rõ "tự giác".
4. **Bảo vệ hồi quy không bao giờ tắt ngầm**: archive chỉ ẩn; FLAKY không phải PASS; test chưa
   chứng minh ĐỎ không phải PASS.
5. **Không spam** (rule FinOS): đang code → test đích danh; Stop → suite bị ảnh hưởng; full suite →
   job đêm local. Không bắn backend dồn dập, retry chỉ cho test local.

#### 2. File

| File | Ai ghi | Nội dung |
|---|---|---|
| `.agents/regression_status.json` | máy (qua khoá file) | REQ / BUG / TEST, kết quả, chữ ký, lịch sử, trạng thái inbox theo hash |
| `.agents/CHECKLIST.md` | máy, sinh lại | Dashboard; thay `regression_checklist.md` (mọi chỗ đọc file cũ đổi theo trong cùng thay đổi) |
| `.agents/INBOX.md` | **người dùng** | `- [ ] …`, `@làm` để giao làm luôn |
| `.agents/archive/BUG_ARCHIVE.md` | máy, sinh lại | Bug ổn định — chỉ view |
| `.agents/evidence/<test-id>/<ngày-giờ>.log` | gate | Log từng lần chạy; giữ 10 log gần nhất/test, trần dung lượng; `agent-kit clean` KHÔNG xoá |

#### 3. Trạng thái

| Trạng thái | Nghĩa | Vào % an toàn |
|---|---|---|
| ✅ PASS | lần chạy thật gần nhất xanh, code canh chưa đổi, test đã chứng minh ĐỎ | tử số |
| 🟡 CẦN CHẠY LẠI | từng PASS, file test canh đã đổi sau commit lần chạy | mẫu số |
| ⏳ CHƯA CHẠY | link test xong, chưa chạy lại sau link | mẫu số |
| ⏳ CHƯA CHỨNG MINH ĐỎ | test xanh nhưng chưa từng thấy đỏ trên code lỗi (Unity/Gradle lớn chờ job đêm) | mẫu số |
| ❌ FAIL / TIMEOUT | đỏ | mẫu số |
| 🔁 FLAKY | đỏ rồi xanh khi chạy lại cùng code | mẫu số + tự tạo BUG flaky |
| 🚫 TEST VÔ HIỆU | vẫn xanh khi bỏ phần fix → không bảo vệ gì | mẫu số, chặn |
| ⚠️ CẦN TEST | REQ/BUG chưa có test, hoặc test gate không chạy | mẫu số |
| 🐞 CHƯA SỬA | bug xác nhận, chưa fix | mẫu số |
| 🟡 REPORTED | prompt tả bug, chưa xác nhận | **không tính** |
| 💤 TỰ ĐÓNG | REPORTED 14 ngày không ai đụng (khôi phục được) | không tính |

% an toàn = PASS ÷ (REQ + BUG + TEST đã xác nhận); HUD ghi rõ mẫu số.

**CẦN CHẠY LẠI**: mỗi test — `git diff --name-only <commit lần chạy>` + thay đổi chưa commit, khớp
`watch_files`; commit `+dirty` → so thêm mtime file với thời điểm chạy. Tính khi render, SessionStart,
Stop; mỗi commit khác nhau một `git diff`.

#### 4. Tự động hoá & rào chất lượng

| # | Việc | Tự động | Rào |
|---|---|---|---|
| 1 | Chuyển phase | tự chạy tiếp, báo cáo 1 lần cuối | chỉ dừng cho quyết định thật (mục 6) |
| 2 | Link bug ↔ test | Stop tự link khi: test được viết/sửa trong phiên **và** lần đỏ đầu tiên trước lần sửa source đầu tiên **và** là cặp duy nhất | thiếu 1 điều kiện → chỉ nhắc |
| 3 | REPORTED rác | 14 ngày không đụng → 💤 TỰ ĐÓNG | không xoá |
| 4 | Inbox | hook so hash từng dòng `- [ ]`, mục mới vào ngữ cảnh 1 lần, ghi thành REQ; `@làm` hoặc gõ "làm inbox" → làm trọn: tiêu chí → test ĐỎ → code → XANH | không tự làm việc chưa được bật |
| 5 | Tiêu chí nghiệm thu REQ | sinh bằng `qa-review` **trước khi code**, khoá hash (sửa phải ghi lý do) | review độc lập so tiêu chí với **nguyên văn prompt**, không với code; REQ PASS chỉ khi mọi tiêu chí có test xanh |
| 6 | UNCOVERED / ngoài matrix | tự link theo quy ước tên (`Foo.kt`↔`FooTest.kt`) khi suite matrix chạy nó; không có suite → soạn sẵn bản vá matrix | bản vá matrix gom vào lần duyệt commit |
| 7 | CẦN CHẠY LẠI | SessionStart chạy nền suite **nhẹ** (không Gradle/Unity), ≤ 2 phút | snapshot file lúc chạy; file đổi giữa chừng → bỏ kết quả |
| 8 | Full suite | job đêm **local** (launchd), 1 luồng, ngoài giờ | không cloud (không có Unity/SDK/thiết bị/secret) |
| 9 | Biết khi đỏ | thông báo macOS chỉ khi dòng **chuyển** sang đỏ, 1 câu + link log; xanh → im lặng | có log làm bằng chứng |
| 10 | Flaky | đỏ → chạy lại 1 lần (chỉ test local); đỏ→xanh → 🔁 FLAKY | không bao giờ nuốt đỏ |
| 11 | Chứng minh ĐỎ | test mới: tạm bỏ phần fix trong worktree, chạy lại → phải đỏ. Python/Go/JS/JVM nhỏ: ngay lúc Stop; Unity/Gradle lớn: job đêm | vẫn xanh → 🚫 TEST VÔ HIỆU, chặn |
| 12 | Backlog bug không test | "làm backlog": theo P0→P2, mỗi bug 1 test; bug cũ chứng minh ĐỎ bằng **revert commit fix ghi trong evidence** trong worktree (đỏ trên code cũ, xanh trên code nay) | không có commit fix → CHƯA CHỨNG MINH ĐỎ |
| 13 | Bằng chứng commit/PR | tự đính dòng tổng kết test + link log; % tụt → agent tự ghi lý do vào commit message | chỉ kết quả thật |
| 14 | Link DevKit mất sau merge | **Đã có từ session DevKit-core:** `scripts/relink_check.py` chạy từ git hook post-merge / post-checkout / post-rewrite (sống sót cả khi hook Claude mất link — SessionStart thì không), chỉ tạo lại link thiếu | không chạy installer, không đụng file tracked |
| 15 | Archive | bug sửa + PASS mới + ≥ 30 ngày **và** ≥ 30 commit → chỉ view archive | đỏ/stale → tự về vùng cảnh báo |

#### 5. Giao diện `CHECKLIST.md`

1. HUD 1 dòng: `An toàn 82% (41/50) · ❌ 1 · 🟡 3 · ⚠️ 5 · 🐞 2 · 🔁 0 · 🟡 REPORTED 2 · matrix chờ duyệt: không`.
2. 🚨 Vùng cảnh báo: FAIL, TEST VÔ HIỆU, FLAKY, CẦN CHẠY LẠI, CẦN TEST, CHƯA SỬA — mỗi dòng 1 câu "việc cần làm".
3. 📥 Hộp thư: mục inbox chưa xử lý / đã nhận → REQ-id (đọc từ JSON, link tới `INBOX.md`).
4. Phân hệ theo `component` của ma trận (tên nghiệp vụ trong ma trận); REQ + bug + test + chữ ký; phân hệ 100% PASS thu gọn `<details>`.
5. Sổ tay bug: Mã | Mô tả dễ hiểu | Test bảo vệ | Trạng thái | Bằng chứng.
6. 🟡 REPORTED (+ 💤 TỰ ĐÓNG thu gọn).
7. Chân trang: "Sinh tự động lúc …, không sửa tay" + số bug trong archive.

#### 6. Chỉ 3 việc cần người

1. **Commit / push** — không đảo ngược được; rule của người dùng.
2. **Tin ma trận đã đổi** — agent tự tin ma trận nó sửa = tự nới gate của chính nó; gom thành 1 lần duyệt cùng commit.
3. **Xoá bug người dùng đã xác nhận** — dữ liệu của họ.

#### 7. Ngân sách, công tắc, số đo

- Ngân sách (có test đo): hook prompt ≤ 100 ms; SessionStart ≤ 2 s (phần đồng bộ); phần kiểm của Stop (không tính chạy test) ≤ 5 s.
- Công tắc tắt riêng từng tính năng (env): `BUG_CAPTURE`, `BUG_LINK_REMINDER`, `AUTO_LINK`, `INBOX_WATCH`,
  `STALE_RERUN`, `RED_PROOF`, `FLAKY_RETRY`, `EVIDENCE_KEEP` — bảng trong AGENTS.md.
- Báo cáo tuần 1 dòng: số lần người phải động tay, tỷ lệ REPORTED bị drop (chỉnh bộ nhận diện bug),
  số FLAKY, số TEST VÔ HIỆU bị bắt.

#### 8. Lộ trình (mỗi phase: test ĐỎ→XANH trong `tests/*/test_*.sh`, `./bin/agent-kit test` rc 0)

| Phase | Nội dung | Nghiệm thu |
|---|---|---|
| P0 | Audit **chỉ đọc** 3 dự án: tính năng, test, độ phủ ma trận, bug không test, commit fix có trong evidence | Phụ lục A của file này (không hỏi, chạy tiếp) |
| P1 | 🟡 CẦN CHẠY LẠI | sửa file canh → PASS thành 🟡; chạy lại → PASS |
| P2 | `.agents/evidence/` + chữ ký có link log; clean không xoá; giữ 10 log | log đúng test, link đúng; log thứ 11 xoá log cũ nhất |
| P3 | Chứng minh ĐỎ (test mới, stack nhẹ lúc Stop) + 🚫 TEST VÔ HIỆU + ⏳ CHƯA CHỨNG MINH ĐỎ | test không phụ thuộc fix → chặn; test thật → PASS |
| P4 | Auto-link chặt (mục 4.2), 💤 TỰ ĐÓNG, 🔁 FLAKY | cặp mơ hồ → chỉ nhắc; đỏ→xanh cùng code → FLAKY |
| P5 | `INBOX.md` (agent không ghi) + REQ (`agent-kit req add/link`), tiêu chí khoá hash, review so với prompt | `INBOX.md` giữ nguyên từng byte; mục mới vào ngữ cảnh đúng 1 lần; REQ thiếu tiêu chí có test → CẦN TEST |
| P6 | Lệnh chữ "làm inbox" / "làm backlog" (hook nhận diện) + RED-proof bug cũ bằng revert commit fix | backlog chạy theo severity; không có commit fix → CHƯA CHỨNG MINH ĐỎ |
| P7 | Job đêm launchd local (full suite + RED-proof nặng) + thông báo khi chuyển đỏ + báo cáo tuần | xanh → không thông báo; chuyển đỏ → 1 thông báo có log |
| P8 | View `CHECKLIST.md` (mục 5), đổi mọi chỗ đọc `regression_checklist.md` | snapshot test; phân hệ 100% thu gọn; % đúng mẫu số |
| P9 | Khoá file trong post-fix-gate; SessionStart health tự re-init; test ngân sách; áp dụng 3 dự án, `agent-kit health` sạch | 2 session ghi cùng lúc không mất dòng; ngân sách đạt |

#### 9. Điều kiện bắt đầu & phối hợp

- Full suite DevKit **xanh trước** (lúc viết: đỏ ở `test_platform_rules.sh` do tái cấu trúc `.agents/`
  của session DevKit-core). Đỏ không do mình → không sửa file của session khác; nhắn session đó, làm
  P0 (chỉ đọc) trong lúc chờ.
- Trước khi sửa file dùng chung (`bin/post-fix-gate.py`, `bin/install.sh`, `bin/agent-health.py`,
  `AGENTS.md`), nhắn session DevKit-core (ListAgents) chốt quyền sở hữu file.
- Không commit/push khi người dùng chưa yêu cầu.

#### 10. Cấm

- Đánh PASS bằng niềm tin; sửa tay `CHECKLIST.md`; ghi bất cứ gì vào `INBOX.md`.
- Tạo checklist thứ hai song song; archive tắt test bảo vệ; coi FLAKY / chưa chứng minh ĐỎ là PASS.
- Tự link khi bằng chứng không rõ một-một; tự tin ma trận đã đổi.
- Luật đếm assertion (heuristic, báo sai nhiều — đã có RED-proof + review độc lập thay thế).
- Full suite sau mỗi sửa nhỏ; job đêm trên cloud.

#### Phụ lục A — Audit P0 (2026-09-24 10:45, chỉ đọc)

| | GeelyEx2 | OfficeReader | Goods-Triple |
|---|---|---|---|
| HEAD | d23430ea | cf51416b6 | 41a8404 |
| Ma trận | 9 rule / 14 suite | 9 rule / 9 suite | 3 rule / 4 suite |
| File test (theo mẫu đường dẫn) / nằm trong watch_files | 5746 / 3017 | 1053 / 656 | 152 / 152 |
| Suite đã có lần chạy thật | 5 (đều `+dirty`) | 1 (`+dirty`) | 4 (commit a2a8078, HEAD đã khác) |
| Bug | 167: PASS 83 · NOT_RUN 3 · NEEDS_TEST 67 · NOT_IN_MATRIX 7 · OPEN 7 | 57: NOT_RUN 57 | 35: NOT_RUN 26 · OPEN 9 |
| Bug không có test hồi quy | **74** (critical 8, P1 1, chưa phân loại 65) | 0 | 0 |
| …có commit fix tra được trong evidence (RED-proof bằng revert được) | 13 | – | – |
| INBOX.md / CHECKLIST.md / evidence/ | chưa có | chưa có | chưa có |

Kết luận cho các phase:
- **P1 đáng giá ngay**: mọi lần chạy đều `+dirty` hoặc ở commit cũ hơn HEAD → không lần PASS nào hiện
  được kiểm là còn mới; cần luật mtime cho `+dirty` (mục 3).
- **P6 backlog** tập trung ở GeelyEx2: 74 bug, ưu tiên 8 critical; chỉ 13 bug RED-proof được bằng
  revert commit fix → 61 bug còn lại sẽ ở "CHƯA CHỨNG MINH ĐỎ" tới khi có test viết mới thấy đỏ.
- **Tương thích ngược**: dòng cũ (bug import, `tests`, `linked_ts`, `last`) giữ nguyên; V3 chỉ thêm
  trường. Post-fix-gate ghi `PASS_IMPACTED` (không thuộc RESULT_STATES) → không bao giờ thành PASS.
- Phân loại severity của GeelyEx2 thiếu ở 65/74 bug → backlog xếp chưa phân loại sau critical/P1.

#### Phụ lục B — Trạng thái thực hiện (2026-09-24, session agent-workbench-cd)

| Phase | Kết quả | Test (ĐỎ trước → XANH) |
|---|---|---|
| P0 | Phụ lục A | — (chỉ đọc) |
| P1 | STALE: git diff từ commit lần chạy + mtime; impacted-only sau PASS → STALE; SessionStart chạy nền suite nhẹ (`scripts/stale_rerun.py`) | `test_stale.sh` 12, `test_stale_rerun.sh` 9 |
| P2 | `.agents/evidence/<test>/<ts>.log` (10 log, git-ignored, clean không xoá), link từ dòng; khoá file trong post-fix-gate | `test_evidence_log.sh` 7 |
| P3 | `scripts/red_proof.py` (sandbox = git worktree: ĐỎ không fix / XANH có fix; revert 3-way; chép file build bị ignore, `.agents/local/red_proof.json`; chỉ chạy test của bug qua `impacted_command`; id lạ → exit 2; evidence nhiều commit → "mơ hồ"); UNPROVEN / VACUOUS / OUTDATED; Stop chạy nền + giữ Stop khi VACUOUS. Sửa theo pilot thật của agent-workbench-f6 | `test_red_proof.sh` 24 |
| P4 | Auto-link một-một (🤖), 💤 tự đóng REPORTED 14 ngày, 🔁 FLAKY (post-fix-gate chạy lại 1 lần) | `test_auto_link.sh` 9, `test_flaky.sh` 7 |
| P5 | REQ (`agent-kit req`), tiêu chí khoá hash, INBOX.md chỉ đọc, nhắc REQ cho prompt tính năng, nhắc Stop cho REQ | `test_inbox_req.sh` 23 |
| P6 | "làm backlog" / "làm inbox"; RED-proof bug cũ bằng revert commit fix trong evidence | `test_backlog.sh` 7 |
| P7 | `scripts/nightly.py` + `agent-kit nightly` (LaunchAgent local, thông báo khi chuyển đỏ, báo cáo tuần) | `test_nightly.sh` 16 |
| P8 | Dashboard `.agents/CHECKLIST.md` (link tên cũ), HUD %, vùng cảnh báo, phân hệ gập, sổ tay bug, archive | `test_checklist_view.sh` 12 |
| P9 | Ngân sách hook (prompt 67 ms, SessionStart 257 ms, Stop 56 ms trên checklist 180 dòng); bảng công tắc AGENTS.md; README/CHANGELOG; mục 14 do `relink_check.py` (DevKit-core) | `test_budgets.sh` 3 (canh ngân sách — không có pha ĐỎ) |
| Thêm (audit OR, G4/G5) | ANTI-LOOP: tiết lộ "mutation" theo từng testcase; chỉ tính lần chạy của phiên này (bash_write_ledger) | `test_anti_loop_disclosure.sh` 10, `test_anti_loop_ownership.sh` 8 |

**Quyết định người dùng (2026-09-24, qua agent-workbench-f6):** KHÔNG cài job đêm / LaunchAgent cho 3 dự án. Hệ quả: suite nặng (Gradle/Unity) chỉ chạy khi gate chạy (`postfix-gate --run-tests --full`); RED-proof bug cũ trên suite nặng chạy tay: `python3 <devkit>/scripts/red_proof.py . --pending --heavy --wait`; không có báo cáo tuần. `agent-kit nightly` vẫn có sẵn nếu sau này muốn bật.

### II.C Plan — UI Context Injection Zero-Slop *(trước đây: `docs/plans/ui-context-injection-zero-slop.md`)*


Ngày: 2026-10-03. Đã audit với source thật và thực thi cùng ngày; các điểm lệch so với bản plan này nằm ở mục "Audit và thực thi" cuối file.

Bộ Zero-Slop chưa được gắn vào ngữ cảnh tự động. Prompt chạm UI và profile `android` / `game` / `ios` / `web` vẫn không bị buộc áp dụng chuẩn Impeccable. Phần chữ trong skill và một nửa bảng Compose đã có sẵn. Phần còn lại là lỗ hổng thật.

#### Đánh giá hiện trạng

| Hạng mục | Đã có | Còn thiếu |
|---|---|---|
| `enrich_context.py` | `UI_INTERACTION` khi có `nút`, `click`, `bấm`, `giao diện`, `ui`, `màn hình`, `layout`, `button`, `tap`. Kèm debounce, touch 48dp/44px, token `DESIGN.md`. | Không có `screen`, `card`, `panel`, `compose`, `ugui`, `canvas`, `theme`, `palette`, `view`, `widget`, `dialog`, `popup`, `animation`, `font`. Profile app không tự bật. Không inject đoạn ZERO-SLOP. |
| Cùng file, `VISUAL_DESIGN` | Đứng cuối, skill `ui-ux-pro-max` được thêm sau cùng. Game/Unity mới có NFR Anti-Phèn (juice, 60-30-10). | Hai intent không đi cùng nhau. Crash "xoay màn hình" cố ý không nạp skill thiết kế. |
| `compact()` | In NFR cụ thể (bỏ 3 NFR chung cuối) và 5 skill đầu. | Skill thứ 6 bị cắt khỏi dòng hook dù dossier vẫn có. |
| `rules/essentials.md` dòng 172 và `core-rules.md` §6 | Token `DESIGN.md`, touch, feedback, debounce. | Chưa nói Zero-Slop, chưa nêu đuôi file UI. |
| `android-rules.md` §15 | 48dp, font scale, contrast, cấm `Color(0x)` rải. | Chưa cấm card lồng card, icon tile, xám `#808080`, gradient tím-xanh, spacing đều 16dp. |
| `game-rules.md` §3 | Juice 0.92/1.08, 3 canvas, 9-slice, TMP, 48dp. | Chưa cấm panel lồng panel, icon tile, xám trần, spacing đều, nút phẳng, `LiberationSans SDF`, pressed scale 0.95 lún 2–4px. |
| `ui-ux-pro-max/SKILL.md` dòng 222 | Đủ 6 verb và 6 điều cấm. | Nhãn đang là `distill` … `polish`, chưa có dạng `/distill` … `/polish`. |
| `jetpack-compose.csv` dòng 53–57 | Cardocalypse, icon tile, tinted neutral, spacing 4–8 / 24–32, touch 48dp. | Chưa ghi dải nội dung 12–16dp và lệnh cấm gradient tím-xanh. |
| `unity-ugui.csv` (27 dòng) | 9-slice, TMP, touch, juice scale 0.92. | Chưa có hàng Zero-Slop. |

`compact()` giả định 3 NFR cuối là luật chung (chống placeholder, log, nuốt lỗi). Mandate phải được chèn trước 3 dòng đó thì hook mới in ra.

#### Cách làm

##### 1. `scripts/context/enrich_context.py`

Một cửa duy nhất, sau khi đã có `p_route` (đã gỡ `docker compose`, `thẩm mỹ viện`, `lựa chọn tối ưu`):

Bật khi `mentions(p_route, UI_KEYWORDS)` hoặc profile là `android`, `game`, `ios`, `web`.

Khi bật, mỗi thứ chỉ thêm một lần:

- Intent `UI_INTERACTION` và `VISUAL_DESIGN`.
- Ba NFR tương tác đang có (debounce, touch, token).
- Đúng khối chữ ZERO-SLOP bên dưới (6 gạch đầu dòng).
- `android-real-device-qa` chỉ khi profile là `android` và prompt đã khớp từ khóa UI. Profile một mình không kéo skill máy thật vào prompt thuần database.
- `ui-ux-pro-max` append cuối, sau `qa-visual`.

`UI_KEYWORDS`: `giao diện`, `màn hình`, `screen`, `nút`, `button`, `tap`, `click`, `layout`, `card`, `panel`, `hud`, `compose`, `ugui`, `canvas`, `theme`, `palette`, `widget`, `dialog`, `popup`, `popup túi đồ`, `animation`, `typography`, `font`, cộng `ui` và `bấm` để không thu hẹp luật cũ.

`view` khớp cả từ. `view` dài 4 ký tự nên matcher hiện tại coi là tiền tố và sẽ dính `ViewModel`. Prompt sửa ViewModel thuần không phải task vẽ UI.

`compose` chỉ xét trên `p_route`, nên `docker compose` không thành Jetpack Compose.

Khối `VISUAL_DESIGN` cũ giữ từ khóa thẩm mỹ (`phèn`, `typography`, `hud`, …). Cửa mới gom lại, không tạo intent trùng.

`compact()`: vẫn in tối đa 5 skill. Nếu `ui-ux-pro-max` bị rơi khỏi 5, in 4 skill đầu rồi skill này ở vị trí cuối. Nếu vị trí thứ 4 đang là `qa-visual`, `compose-recomp-audit` hoặc `unity-gc-audit` thì giữ skill đó và thay skill áp chót. `qa-visual` vẫn đứng ngay trước `ui-ux-pro-max`.

Hệ quả cố ý: mọi prompt trên profile app, kể cả câu không nói UI, đều tốn vài dòng ngữ cảnh. Đó là điều khoản "HOẶC khi active profile là android, game, ios, web".

Việc enrich nhìn prompt và profile, không nhìn file sắp sửa. Luật đuôi file nằm ở mục 2, để agent đọc khi đụng file. Lượt này không thêm Stop hook mới.

Khối NFR bắt buộc, nguyên văn:

```text
ZERO-SLOP UI MANDATE (Impeccable Standard):
• Cấm Cardocalypse: Cấm Card lồng Card (Compose/Flutter) và Panel lồng Panel (Unity). Dùng whitespace và subtle divider để làm phẳng layout.
• Cấm Icon Tile trên Heading: Không bọc icon vào ô vuông bo góc màu nhạt đặt trên tiêu đề.
• Cấm Màu xám trần & Gradient tím-xanh: Cấm Color.Gray trần (#808080); bắt buộc dùng Tinted Neutrals (pha 3-5% tông chủ đạo).
• Nhịp điệu Spacing: Cấm 16dp đều chằn chặn; 4-8dp cho item cùng nhóm, 12-16dp nội dung, 24-32dp phân cách section.
• Game UI Tactile Depth (Unity): Cấm nút phẳng lì kiểu web; bắt buộc có độ dày 3D (9-slice bevel), pressed state scale 0.95 lún 2-4px, cấm font mặc định LiberationSans SDF.
• Touch Target: Bắt buộc >= 48dp (Mobile) / >= 44px (Web) kèm immediate visual feedback (Ripple/Scale).
```

##### 2. Luật đứng

`rules/essentials.md`, bullet UI trong Engineering musts, và `rules/core-rules.md` §6, thêm cùng một ý:

Mọi sửa file giao diện (`*.kt` Compose, `*.xml` layout, `*.prefab`, `*UI*.cs`, `*.tsx`, `*.vue`, `*.css`) tuân thủ Zero-Slop và token `DESIGN.md`: cấm card/panel lồng nhau, cấm icon tile trên heading, cấm `Color.Gray` / `#808080` và gradient tím-xanh, spacing 4–8 / 12–16 / 24–32, game thì bevel 9-slice, pressed scale 0.95 lún 2–4px, cấm `LiberationSans SDF`, touch ≥ 48dp (mobile) / ≥ 44px (web) kèm ripple hoặc scale.

Sau đó chạy `scripts/governance/context_sync.py` để khối essentials trong `AGENTS.md` khớp file nguồn. Health đối chiếu bản sinh này.

##### 3. Data `ui-ux-pro-max`

`SKILL.md`: đổi 6 nhãn hiện có thành `/distill`, `/bolder`, `/quieter`, `/harden`, `/typeset`, `/polish`. Không thêm mục thứ hai.

`jetpack-compose.csv`: sửa hàng spacing 56 để có dải 12–16dp; thêm một hàng cấm gradient tím-xanh. Giữ số hàng cũ.

`unity-ugui.csv`: thêm hàng tiếp theo (từ 28), không đánh lại số 1–27:

- Cấm Panel lồng Panel; dùng khoảng trắng và divider.
- Cấm icon tile trên heading.
- Cấm xám `#808080` và gradient tím-xanh; neutral pha 3–5% tông chính.
- Spacing 4–8 / 12–16 / 24–32, cấm 16 đều.
- Nút có bevel 9-slice; pressed scale 0.95, lún 2–4px; cấm nút phẳng kiểu web.
- Cấm font `LiberationSans SDF`.

Đủ 13 cột, `Status=active`, `Applies To` và `Verified At` cùng kiểu hàng anh em. `validate_data.py` từ chối trùng cột `No`.

##### 4. Profile

`profiles/android/rules/android-rules.md` §15 và `profiles/game/rules/game-rules.md` §3: thêm đoạn Zero-Slop ngắn, cùng nội dung mục 2, phần game nhấn bevel / pressed / `LiberationSans SDF`. Không viết lại cả mục juice.

##### 5. Test

Sửa `tests/context_memory/test_prompt_context.sh`:

- `app crash khi xoay màn hình` phải ra `ui-ux-pro-max` và chữ `ZERO-SLOP`. Từ `màn hình` nằm trong danh sách mới; assertion cũ (cấm skill thiết kế) sẽ đỏ và được đổi theo spec.
- Prompt đúng chữ `sửa lại nút bấm trong màn hình inventory` ra skill `ui-ux-pro-max` và mandate.
- Profile `android`, `game`, `ios`, `web` với prompt không có từ UI (ví dụ sửa null trong repository) vẫn ra hai intent, skill và mandate.
- Giữ nguyên các ca âm: `ui` trong `build`, `hiệu ứng phụ`, `docker compose`, `thẩm mỹ viện`, `lựa chọn tối ưu`.
- `sửa lỗi hud bị vỡ layout`: `qa-visual` ngay trước `ui-ux-pro-max` trong 5 skill.
- Game + GC vẫn thấy `unity-gc-audit`. Android + recomposition vẫn thấy `compose-recomp-audit`.
- `ViewModel` không kéo `ui-ux-pro-max` trên profile `backend`.

Oracle: chạy suite này trước khi sửa `enrich_context.py` để thấy đỏ ở ca màn hình và ca inventory, rồi xanh sau khi sửa.

##### 6. Nghiệm thu và git

Từ gốc `agent-workbench`:

```bash
python3 universal-agent-devkit/scripts/context/enrich_context.py --compact "sửa lại nút bấm trong màn hình inventory"
bash universal-agent-devkit/bin/agent-kit health -t .
python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief --auto-approve-tests
```

Profile repo này là `backend`, nên lệnh compact kiểm đường từ khóa, không kiểm đường profile. Ca profile nằm trong suite.

Health 100/100 là điểm nối dây, không phải điểm hoàn thiện sản phẩm.

Ảnh: không cần. Chỉ đụng kit, profile backend, không có màn hình app.

Commit đúng path kit, subject tiếng Anh, trailer `No-Guard: host wiring, not a checklist bug`. Không stage `.agents/CHECKLIST.md`, `regression_status.json`, `instincts-index.md`. Không đụng checkout Geely, Office Reader, Goods đang khóa, không push `devkit/host-hooks`. Push `main` khi `origin/main` vẫn là cha của HEAD.

#### Ngoài phạm vi

Không thêm hook chặn theo đuôi file. Không đổi `bin/install.sh`, proof capture, hay bridge Cursor/Gemini/Codex. Không gọi Antigravity review: spec đã chốt, diff là luật và data, không đổi kiến trúc runtime.

#### Audit và thực thi (2026-10-03)

Mỗi khẳng định "hiện trạng" của plan được đối chiếu với source thật trước khi sửa; đã đúng gần hết. Phần dưới là những chỗ plan thiếu hoặc mâu thuẫn với source, và cách đã xử lý. Thứ tự thực thi: test đỏ trước (31 ca đỏ ở `test_prompt_context.sh`, 2 ở `test_prompt_dedupe.sh`), sửa mã trên bản sao rồi cài nguyên tử vào `enrich_context.py` (file này là hook đang chạy của mọi phiên: INSTINCT-012/016), xanh sau đó.

| # | Plan | Source thật | Xử lý |
|---|---|---|---|
| 1 | Mandate là một NFR nhiều dòng, chèn trước 3 NFR chung | `dedupe_session` bỏ lặp **từng dòng** (`ONCE_PER_SESSION`). Mandate dính vào dòng `Yêu cầu ngầm định` sẽ bị gửi lại mỗi khi tập NFR đổi; gạch đầu dòng đứng riêng không có tiền tố sẽ bị gửi lại mãi trong khi dòng tiêu đề bị bỏ (gạch mồ côi) | Giữ nguyên văn nhưng `compact()` in thành khối riêng (tiêu đề + 6 gạch); `ONCE_PER_SESSION` thêm `ZERO-SLOP UI MANDATE` và `• `. Mandate gửi một lần mỗi phiên, sau compaction gửi lại. Test: `hooks/tests/test_prompt_dedupe.sh` |
| 2 | Profile app bật UI cho mọi prompt | `INTENT_TERMS["UI_INTERACTION"]` (click, debounce, 48dp) cộng vào từ khóa khớp bẫy cho mọi intent, và `shown_refs` hạ ngưỡng 3→2 khi có intent. Bẫy 002/005 sẽ chiếm 2 trong 4 slot của prompt không nói UI, rồi dedupe giấu chúng | Intent chỉ do profile bật vào `dossier["profile_intents"]`: không nạp `INTENT_TERMS`, không hạ ngưỡng. Test: bẫy F48 vs F07 trên profile android, `shown_refs` |
| 3 | `view` khớp cả từ (nhưng không có trong danh sách), `card`/`compose` như từ khóa thường | `mentions()` coi từ ≥4 ký tự là tiền tố: `card` bắt `cardinality`/`cardholder`, `compose` bắt `composer` (PHP), `view` bắt `ViewModel` | Các từ mơ hồ (`view`, `card`, `compose`, và sau review `screen`, `panel`, `dialog`, `theme`, `font`) đi qua regex nguyên từ `UI_WHOLE_WORDS`; `NON_TECHNICAL_PHRASES` gỡ thêm nghĩa backend (`compose.yaml`, `sql view`, `Django views`, `Grafana panel`, `credit card`, `card number`, `dialog state`…); bỏ `popup túi đồ` (thừa vì đã có `popup`). Còn lại, ghi `ponytail:`: class CamelCase (`ScreenState`) ngoài profile app, `layout`/`click` như ở HEAD |
| 4 | `compact()`: "vị trí thứ 4 … thay skill áp chót" | Tự mâu thuẫn nếu đếm từ 1: vị trí 4 chính là áp chót | Lấy 5 skill đầu; nếu `ui-ux-pro-max` bị cắt thì nó thế chỗ skill cuối cùng không thuộc {`qa-visual`, `compose-recomp-audit`, `unity-gc-audit`}. Ca `Compose UI bị lag`, game + GC và hud trên android ghim hành vi này |
| 5 | `VISUAL_DESIGN` luôn bật theo cửa mới | Bốn NFR juice của game gắn với khối `VISUAL_DESIGN`: bật theo profile thì mọi prompt game mang thêm 4 dòng dài | Bốn dòng đó giữ theo từ khóa thẩm mỹ cũ |
| 6 | Data: sửa hàng 56, thêm một hàng | `validate_data.py` đã đỏ trước khi sửa: hàng 55 (High) trỏ `m3.material.io`, validator chỉ nhận `developer.android.com`; `catalog-summary.json` `stackGuidelines` lệch (đỏ cả ở HEAD). Plan không nhắc `catalog-summary.json` | Hàng 55 → trang Material 3 của developer.android.com (đã kiểm HTTP 200); `stackGuidelines` = 1310 (số hàng thật). `validate_data.py` exit 0. Test `test_threshold_exemption_is_declared_per_stack_not_by_row_count` đỏ sẵn ở HEAD, không liên quan, không đụng |
| 7 | Đuôi file: `*.kt *.xml *.prefab *UI*.cs *.tsx *.vue *.css` | Gate có `UI_EXTENSIONS` = `.kt .java .tsx .jsx .dart .vue .swift .xml`; profile `ios` thuộc phạm vi mà không có `.swift` | Luật đứng dùng hợp của hai danh sách |
| 8 | Commit "đúng path kit" | `context_sync.py` ghi lại khối essentials trong `AGENTS.md` gốc (file tracked); health đối chiếu nó | Commit cả `AGENTS.md` gốc |
| 9 | Chỉ đổi assertion `app crash khi xoay màn hình` | Hai test khác hết đúng theo spec mà gate của plan không chạy (chúng không nêu tên `enrich_context`): `test_prompt_dedupe.sh` ca "partly new" (prompt không có "màn hình" nay khác dòng skill), `hook_contract_test.sh` "chit-chat adds nothing" (fixture profile `web`) | Ca 1: prompt thứ ba thêm "màn hình" và từ khóa mạng. Ca 2: "im lặng" chỉ còn cho profile không phải app; profile app có ca riêng (đúng điều khoản "Hệ quả cố ý") |
| 10 | Nhãn `/distill` … `/polish` | Không có slash command nào được cài | Tiêu đề mục nói rõ đó là từ chỉ đạo viết trong prompt |

##### Review ngữ cảnh sạch (`principal-code-reviewer`, sau bản đầu)

Không blocker; 3 should-fix, 5 nit, đều có số đo. Xử lý:

| # | Phát hiện | Xử lý |
|---|---|---|
| 1 | `hooks/agent_bridge.sh` nhánh `prompt` không chuyển `session_id` nên Gemini/Codex/Cursor không dedupe: mandate (~1,1 KB) lặp ở mọi prompt trên profile app | Ban đầu để lại vì plan loại trừ bridge; sửa sau theo yêu cầu (04/10): nhánh `prompt` chuyển `session_id` / `conversation_id` như nhánh `stop`, test `test_agent_bridge.sh` (3 ca đỏ → xanh) |
| 2 | Từ UI mới bắt nhầm từ vựng backend (`sql view`, `Django views`, `compose.yaml`, `compose up`, `Grafana panel`, `screening`, `Dialogflow`, `theme_id`, `card` trong log thanh toán); replay prompt thật: cửa UI mở 3 → 5 lần | Sửa: 5 từ prefix thành nguyên từ, thêm cụm vào `NON_TECHNICAL_PHRASES`, 11 ca âm mới. Replay lại 319 prompt: HEAD 4, bản đầu 8, bản sửa 7; 3 lần tăng đều là văn bản dài (2 bản tóm tắt phiên tự sinh, 1 prompt vai trò dán vào) |
| 3 | 0.92 (squash lúc chạm) và 0.95 (pressed của mandate) cùng được tiêm cho một sự kiện | Giữ số của plan. Bản đầu gọi 0.92 là tween thoáng qua: sai, vì uGUI #22 giữ squash tới lúc nhả. Nay: tween squash kết thúc ở tư thế Pressed 0.95 + lún, trả lại khi nhả; sửa graphic con của nút (LayoutGroup điều khiển vị trí nút); ghi ở `game-rules.md`, uGUI #32 và dòng NFR juice. **Cần chủ quy chuẩn xác nhận**: hàng #22 và #3 (có sẵn) vẫn mô tả squash giữ tới lúc nhả |
| 4 | Prompt chỉ có từ thẩm mỹ (`bảng màu`, `phèn`) được skill nhưng không có mandate, trong khi `palette` mở cửa | Từ thẩm mỹ cũng mở cửa; điều kiện `VISUAL_DESIGN` rút gọn thành `ui_door` |
| 5 | `/distill …` ở đầu prompt bị hook bỏ qua (prompt bắt đầu bằng `/`) | Tiêu đề mục trong `SKILL.md` dặn viết giữa câu |
| 6 | `SKILL.md` ghi 3 trạng thái nút, thiếu Disabled | Sửa thành 4 trạng thái |
| 7 | Phạm vi cấm gradient tím-xanh lệch giữa mandate (tuyệt đối, nguyên văn plan) và data (chỉ bản template); `styles.csv` (Aurora UI, Vaporwave) lại gợi ý gradient xanh→tím | **Để nguyên, cần người quyết**: hai bên mâu thuẫn về chính sách, không phải lỗi mã |
| 8 | Test: ca game+GC không bắt được đột biến "thay skill cuối"; ca dedupe mandate chưa có trường hợp chỉ-do-profile; ca âm pass giả nếu helper crash | Thêm ca dedupe chỉ-do-profile và dấu `HELPER-CRASH` cho ca âm. Ca game+GC giữ nguyên: trên profile game `unity-gc-audit` luôn là skill thứ 4 nên không có input nào phân biệt được |

##### Review delta của `756c2e9` (cùng reviewer, sau bản sửa vòng 1)

Bản sửa vòng 1 gây 2 hồi quy; reviewer bắt cả hai bằng reproducer, đã sửa ở commit sau:

| # | Phát hiện | Xử lý |
|---|---|---|
| 1 | Từ thẩm mỹ mở cửa nên `UI_INTERACTION` thành intent thật và nạp lại bẫy click/debounce/48dp (F07 đứng đầu ở prompt `vfx`, `shading`, `đồ họa`), trái đúng luật INSTINCT-026 | Tách `ui_terms` (từ UI tương tác) khỏi `ui_words` (cộng từ thẩm mỹ): intent UI chỉ nạp bẫy khi có `ui_terms`; prompt thẩm mỹ vẫn có mandate. Ngưỡng bẫy yếu giữ như HEAD nhờ `VISUAL_DESIGN` |
| 2 | `compose(?:\.ya?ml\| up)` không có ranh giới từ nên ăn `recompose up to`, `Compose update/upgrade`: mất `compose-recomp-audit` và `PERFORMANCE` (hồi quy so với HEAD) | `(?<!\w)compose(?:\.ya?ml\|\s+up)(?!\w)` |
| 3 | Câu "0.92 chỉ là tween" sai so với uGUI #22 (squash giữ tới lúc nhả); làm theo cả hai thì tư thế giữ ra (1.05, 0.92), không bao giờ 0.95; sink bằng `anchoredPosition` của nút bị LayoutGroup ghi đè | Xem hàng 3 của bảng trên: đổi câu chữ, #32 áp lên graphic con. **Cần chủ quy chuẩn xác nhận** |
| 4 | Test không bắt hai hồi quy đầu | Thêm 12 ca (4 compose/PERFORMANCE, 8 từ thẩm mỹ không kéo F07), mutation J và K |
| 5 | Lệnh kiểm tra của INSTINCT-026 kết thúc bằng `\| tail -2` nên nuốt exit code | Bỏ `\| tail -2` |
| 6 | Header `hooks/prompt_context.sh` vẫn nói chit-chat không tốn context và chỉ kể 3 loại dòng dedupe | Sửa comment (4 dòng) qua cài nguyên tử: ghi ngoại lệ profile app và bridge |

Không lỗi theo reviewer: regex (mọi nhánh có nhóm, không backtracking: 1,8 MB ≤ 0,07 s), thứ tự intent/NFR/skill khi `aesthetic` lên trước (với prompt thẩm mỹ `UI_INTERACTION` chen ngay sau `BUG_FIX`; android + từ thẩm mỹ thêm `android-real-device-qa`), bash 3.2, CSV 13 cột, `validate_data.py`.

Mutation check (12 đột biến: bỏ loại intent-profile khỏi bẫy hoặc khỏi ngưỡng, mandate dính dòng NFR, bỏ tiền tố `ONCE_PER_SESSION`, skill line 5 đầu thuần, profile kéo `android-real-device-qa`, từ nguyên từ thành prefix, bỏ cụm backend, từ thẩm mỹ không mở cửa, NFR juice theo profile, từ thẩm mỹ nạp lại bẫy UI, `compose up` không ranh giới): cả 12 đều làm ít nhất một ca đỏ.

Kết quả đo (bản cuối): `test_prompt_context.sh` 118/118 (cả bash 3.2), `test_prompt_dedupe.sh` 30/30, `hook_contract_test.sh` 687 ok / 0 deviating, `validate_data.py` exit 0, health 100/100; replay 319 prompt đã gõ: cửa UI mở 4 lần ở HEAD, 7 lần nay (3 lần tăng là văn bản dài). Còn đỏ sẵn ở HEAD, không thuộc thay đổi này: `contract_facts_test.sh` F2 (`user_project_bridge.sh` thiếu header OPT-IN HELPER, từ commit `18f4591`) và `test_threshold_exemption…` nói trên.

Điểm cần biết: `tests/run_impacted.sh` chọn test theo tên file đổi; `hook_contract_test.sh` chỉ nêu `prompt_context` nên một lần sửa `enrich_context.py` thuần không kéo nó vào gate. Chưa sửa (ngoài phạm vi); nếu sửa tiếp `enrich_context.py`, chạy tay `bash universal-agent-devkit/hooks/tests/hook_contract_test.sh`.
