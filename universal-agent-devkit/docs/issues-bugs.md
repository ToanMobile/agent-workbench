# DevKit — issues & bugs (nguồn duy nhất)

> Gộp ngày 13/10/2026 theo yêu cầu người dùng: một file cho issues, bugs và việc dọn dẹp đang mở; kế hoạch tối ưu / cải tiến workflow nằm riêng ở [`workflow-improvements.md`](workflow-improvements.md). Các hàng ở Phần A tách từ hai bảng theo dõi (mục tiêu 100/100, Plan C+D §8.1), giữ nguyên chữ và số `#` gốc. Phần B là báo cáo audit 09/10, giữ nguyên.

## Cách dùng

1. Vấn đề hoặc bug mới của DevKit chưa có test: thêm một hàng ở Phần A, ghi bằng chứng (lệnh, số đo, đường dẫn) và nguồn. Xong thì chuyển sang Phần B kèm commit và cặp test ĐỎ→XANH.
2. Bug có test hồi quy: `agent-kit bugs add/link`; `.agents/CHECKLIST.md` là nguồn trạng thái PASS/FAIL. Không ghi PASS/FAIL ở đây.
3. "Chưa kiểm lại" nghĩa là dòng đó trích từ một plan cũ và chưa ai chạy lại ngày 13/10.

## Chỉ mục

| Mục | Nội dung | Nguồn | Trạng thái |
|---|---|---|---|
| A.1b | File bí mật sinh ra trong worktree không về main: phần sửa chung cho `finish`/`gc` (việc 12) | review 13/10 tối | Ca Neighbours xong 13/10; phần chung là W1 của phiên d352c03b |
| A.2 | Race `worktree_merge_gate`: lỗ con reflog đọc sau khi thư mục mất (#3) | `trunk-integrator-no-shared-main.md` §8.1 | W1 của phiên d352c03b |
| A.4 | Tồn đọng còn lại từ plan / audit cũ | các plan II.A, II.C và audit B.1 | Kiểm lại 14/10 (phiên d91dffdd): 2 việc mở, 1 chờ chủ xe duyệt, 2 quyết định chính sách, 1 không kiểm được |
| B.1 | Audit DevKit 2026-10-09: kết quả | `audit-2026-10-09-followup.md` | Báo cáo đã đóng |

## Phần A — Đang mở

**Đóng 14/10 (phiên d91dffdd, "fix hết") và đã bỏ khỏi file**, mỗi việc có test ĐỎ→XANH, bằng chứng trong commit:
A.1 #3 `session_lock` bỏ lọt `cp`/`mv`/`rm`/`tee`/`sed -i`/`touch` (`7a1c6de`, bộ quét chung `hooks/shell_writes.py`; lỗ còn lại ghi `ponytail` trong `_file_write_hits`);
A.1 #10 thư mục mồ côi (`338b2ca` R5a + `d5ec03e`/`b0ff762` gc, của phiên d352c03b);
A.1b #13 `review_gate` không thấy code sửa bằng Bash (`48aabca`);
A.2 #2 gate chọn quá nhiều test: worktree tách rời tính từ merge-base (`ff27ebb`), checkout có upstream dùng `git diff @{u}...HEAD` (`dfdb7ff`), main có biên nhận `--full` exit 0 ghi `head`;
A.3 worktree `-mcp` của Goods (7 đường dẫn nhiễu cất vào `stash@{0}` của Goods, gộp và push `5f43e73..58515a7`);
A.4 regex `cwd` không đọc JSON thoát ở 15 hook (`88d1512`), 5 file `hooks/tests` mồ côi (`1223e12`), con trỏ `docs/plans/` ở 11 file (`64ed509`), FIFO trên state agent ghi được: 15 chỗ đọc/ghi của `post-fix-gate`/`proof_gate`/`push_gate` (`e44764b`) dòng `.gitignore` của 15 hook (`02865cc`), và FIFO ở log / khoá của hook ở cấp đầu `.claude/audit-gate/` bị dọn trước lần mở đầu tiên (commit kế tiếp; principal-code-reviewer bắt `review_gate.log` … còn treo). Giới hạn còn lại, ghi `ponytail` trong `tests/gates/test_hook_gitignore_fifo.sh`: git tự đọc một `.gitignore` là FIFO trong thư mục nó duyệt; khe đua sau `isfile`; thư mục con của `.claude/audit-gate/`; `scripts/testing/stale_rerun.py:115` mở `test_run.lock` thường (không phải hook Stop); `session_lock.test_run_active` coi FIFO là đang chạy test (có từ trước).

### A.1b Mới 13/10 tối (review ngữ cảnh sạch sau `cd0fb04`)

| # | Việc | Bằng chứng | Sửa |
|---|---|---|---|
| 12 | **File bí mật sinh ra trong worktree không bao giờ về main.** `worktree add` chép LOCAL_CONFIG (`.env`, `*.jks`, `key.properties`…) từ main sang worktree, nhưng `finish`/`automerge` chỉ mang về file git theo dõi. File bị gitignore, đúng là loại file bí mật, nên kẹt lại trong worktree, và worktree không xoá được nếu không mất khoá | Neighbours: `Neighbours-From-Hell-keystore` tạo lúc 12/10 17:32:05; `keystore/key_store_neighbours.jks` + `key.properties` sinh lúc 17:32:23. Main chưa từng có keystore (không file nào, Unity chưa cấu hình keystore Android). Người dùng tưởng main có "keystore gốc" | `finish`/`automerge`/`gc`: file bí mật bị ignore mà CHỈ có trong worktree thì chép về đúng đường dẫn ở main (giữ quyền 600, thêm vào `.git/info/exclude` nếu `.gitignore` chưa chặn), so từng byte, rồi mới gỡ worktree. Bản giống main thì bỏ. Test ĐỎ trước. Ca Neighbours: ĐÃ XONG 13/10 ~20:50 — người dùng duyệt; `keystore/` chép về `Neighbours-From-Hell/keystore/` (700/600, `cmp` trùng từng byte, `keystore/` trong `.git/info/exclude`, `git status` không thấy), rồi `agent-kit worktree remove` gỡ worktree. Phần sửa chung cho `finish`/`gc` vẫn là việc của W1 (phiên d352c03b giữ `scripts/git/worktree.py`) |

### A.2 Từ Plan C+D §8.1

| # | Việc | Trạng thái đo được | Hành động |
|---|---|---|---|
| 3 | **Sửa race `worktree_merge_gate` — phần còn lại** | Race chính (hai lần `automerge` của một worktree chạy chồng nhau: Đợt 32, `42af92b`) và ca thư mục bị xoá TRƯỚC khi hook Stop chạy (Đợt 34, `8695853`, `tests/gates/test_worktree_merge_gate_vanished.sh` ca 8 ĐỎ→XANH) đã sửa, đã bỏ khỏi hàng này. **Còn mở (review 13/10, có từ trước; kiểm lại 14/10: `worktree.py` dòng 1089 trên main `1111bcd` vẫn `reflog = … if os.path.isdir(path) else []`):** thư mục mất TRƯỚC khi bước kiểm kê đọc reflog thì trả `reflog = []`, nên commit chỉ còn trong reflog vẫn cho qua | Đọc reflog từ admin dir (`git --git-dir=<admin> log -g`), không đổi thành `None` (ca 1 sẽ bị giữ). Test ĐỎ trước → `workflow-improvements.md` I.0 W1 (phiên d352c03b) |

*(Hàng #1 và #7 của bảng gốc, cùng 8.2 đến 8.4 và thứ tự đề nghị, nằm ở `workflow-improvements.md` mục I.2.)*

### A.4 Tồn đọng nằm trong plan / báo cáo khác

Mỗi hàng trích nguyên văn một đoạn ngắn từ nguồn ghi ở cột phải; đọc đoạn đó trong nguồn trước khi làm.

**Kiểm lại 14/10 (phiên d91dffdd):**
- **Vẫn mở:**
  - Ba dòng bug của audit 09/10 trong `.agents/CHECKLIST.md` vẫn "⏳ chưa chứng minh ĐỎ". Cả ba chỉ link tới suite `REG-DK-ALL-01`, không link file test nào, nên `red_proof.py` trả "không biết file test nào". Hai dòng (`BUG-20261002-agent-kit-health…`, `BUG-20261009-run-impacted…`) có bản sửa trong `tests/run_impacted.sh`, mà `red_proof.py` (`TEST_PATH`) coi mọi file dưới `tests/` là test nên từ chối red-patch. Hướng: khai runner là code sản xuất trong `.agents/local/red_proof.json` (khoá mới, ví dụ `"production"`), `agent-kit bugs link` tới `test_run_impacted.sh` / `test_run_impacted_since.sh`, viết red-patch, rồi `red_proof.py --pending`. `BUG-20260929-audit-review…` là yêu cầu audit hiệu năng, không có test tất định (revert `a49bc13` xung đột): `agent-kit bugs drop` hoặc giữ là chuyện quyết định.
  - Nhận nuôi worktree (3): W1 R5b của phiên d352c03b.
- **Chờ chủ xe duyệt:** gộp suite Gradle của Geely: `REG-SHARED-02` chạy đúng lệnh của `REG-PHONE-01` mà chưa có `covered_by: REG-PHONE-01` (`REG-SHARED-01` đã có `covered_by: REG-CAR-01`). Quy tắc chủ xe ở GeelyEx2: agent không tự sửa ma trận hồi quy (`265d25ce6` cũng đang chờ duyệt, chưa push).
- **Không kiểm được:** Gemini qua alias. Đo 14/10: Gemini CLI 0.59 trên máy này không đăng nhập được nữa (`IneligibleTierError`, `UNSUPPORTED_CLIENT`: Google ngừng hỗ trợ client này cho gói Gemini Code Assist cá nhân, bảo chuyển sang Antigravity), nên không có phiên Gemini thật nào để thử. Phần Gemini của DevKit ở 4 repo cũng không chạy được tới khi đổi gói / đăng nhập.
- **Là quyết định chính sách:** squash #22/#3; gradient tím-xanh.

| Trích nguyên văn | Nguồn |
|---|---|
| "Gemini qua alias (`includeDirectories` dùng đường dẫn thật): **chưa kiểm** — cần một phiên Gemini thật." | Audit 09/10 (B.1), "Bước 6" |
| "`BUG-20260929-audit-review-nguyen-nhan-tai-sao-cac-ses` — INCONCLUSIVE" | Audit 09/10 (B.1), "Bước 4" |
| "`BUG-20261002-agent-kit-health-run-tests-scores-96-100` — chưa chạy" | Audit 09/10 (B.1), "Bước 4" |
| "`BUG-20261009-run-impacted-recent-commits-in-sandbox` — chưa chạy" | Audit 09/10 (B.1), "Bước 4" |
| "Lựa chọn "gộp 3 suite Gradle thành 1 lệnh" của người dùng **chưa thực hiện**" | Audit 09/10 (B.1), cùng mục |
| "(3) worktree chưa từng vào danh sách "nợ" của một phiên đã kết thúc không bao giờ được phiên sau nhận nuôi (chỉ liệt kê ở SessionStart) — chưa đổi." | Audit 09/10 (B.1), cùng mục |
| "**Cần chủ quy chuẩn xác nhận**: hàng #22 và #3 (có sẵn) vẫn mô tả squash giữ tới lúc nhả" | UI context injection (II.C), "Review ngữ cảnh sạch" #3 |
| "**Để nguyên, cần người quyết**: hai bên mâu thuẫn về chính sách, không phải lỗi mã" | UI context injection (II.C), "Review ngữ cảnh sạch" #7 (cấm gradient tím-xanh) |

## Phần B — Báo cáo đã đóng

### B.1 Audit DevKit 2026-10-09 — chạy tiếp ở local (macOS): kết quả *(trước đây: `docs/plans/audit-2026-10-09-followup.md`)*


#### Trạng thái

| Nơi | Commit | Nội dung | Đã kiểm chứng |
|---|---|---|---|
| `main` | `4425001` | Đợt 1–3 làm trên Linux cloud | trên Linux: 158/158 test bị ảnh hưởng |
| `main` | `94f388c` | macOS: so sánh đường dẫn theo inode (APFS), test camelCase, race worktree biến mất, guard `bash -c "$(…)"` / `>(sh)` / `find !`/`-o` | gate `--full` exit 0 |
| `main` | `430fb87` | `review_timing_guard` đọc payload qua fd 3, `DEVKIT_IMPACTED_SINCE` | gate `--full` exit 0 |
| `main` | `63f9561` | runner thiếu `set -e`, phạm vi `describe` JS, docstring/comment cuối dòng, project từ `cwd` payload (7 hook), đường tắt `churn_guard` | gate `--full` exit 0 (6/6), `run_impacted.sh` 112/112 |
| `main` | `6e6642b` | lý do từ chối của automerge, sửa theo audit Antigravity T0024 | gate `--full` exit 0 (3/3), `run_impacted.sh` 52/52 |

#### Bước 1–2 — kiểm chứng trên macOS (bash 3.2, APFS) — xong
- 6 test của đợt 3: PASS ngay (hook contract 687/687).
- `run_impacted.sh --all` (177 test, 377 s): 175 xanh, **2 đỏ thật**, sửa gốc:
  - `test_session_lock.sh` (case-only cwd): `realpath` giữ nguyên hoa/thường, APFS không phân biệt ⇒ đường dẫn viết khác hoa/thường bị coi là NGOÀI checkout đang khoá. `_inside` / `_same_dir` so theo inode ở 4 chỗ. ĐỎ 3 → XANH.
  - `test_hook_camelcase_payload.sh`: bash 3.2 cắt đối số `"$(cmd "{\"a\":…}")"` tại dấu nháy thoát ⇒ 2 hook chạy trên rác. Payload dựng bằng phép gán; assertion giữ nguyên.
- 1 lỗi **chập chờn** của gate (`test_worktree_merge_gate_owner.sh` mục 7, đỏ 2/3 lần gate): lỗi sản xuất thật — merge nền của Stop trước xoá worktree đúng lúc Stop này đang quyết định, dòng đó ở lại danh sách giữ. `worktree_merge_gate.sh` bỏ dòng có thư mục đã biến mất. Test tất định mới (shim `git`): ĐỎ 2 → XANH.
- `test_guards_orphans.sh` đỏ chỉ do luật runner mới: fixture thêm `set -e`, assertion giữ nguyên.

#### Bước 3 — gate `--full` — exit 0
Dòng rác `REG-01 echo FULL_TEST_EXECUTED` đã tự biến khỏi `CHECKLIST.md` và `regression_status.json` (kiểm: 0 khớp ở cả hai).

#### Bước 4 — RED-proof các dòng bug cũ
Công cụ: `scripts/testing/red_proof.py`; không sửa JSON tay. Hai phát hiện về chính công cụ:
- Sandbox không có upstream ⇒ `run_impacted.sh` tính commit của 6 giờ qua là "đã đổi" ⇒ mỗi bằng chứng 15+ phút chưa xong. Thêm `DEVKIT_IMPACTED_SINCE` (`0` = tắt cửa sổ); đặt khi chạy bằng chứng: 1–10 phút.
- `.sh` không nằm trong `SOURCE_EXT` của `red_proof.py`, và code đã chuyển chỗ/viết lại nên `git revert` xung đột: các bằng chứng dùng `--patch` (bản vá đưa bug trở lại, lưu ở `.agents/local/red-patches/`, đã commit).
- `tests/impact_map.txt` thiếu `enrich_context.py → test_bug_capture.sh`: gate không chạy test bảo vệ bộ lọc ROLE_OPENING, và bằng chứng của bug đó ra VACUOUS giả. Đã thêm (có test).

Kết quả (nguồn sự thật: cột RED-proof trong `.agents/CHECKLIST.md`): **29 PROVEN / 1 INCONCLUSIVE / 2 chưa chạy** trong 32 dòng bug. Trong 19 dòng "⏳ chưa chứng minh ĐỎ" ban đầu: **17 PROVEN**. Còn lại, kèm lý do:
- `BUG-20260929-audit-review-nguyen-nhan-tai-sao-cac-ses` — INCONCLUSIVE: hai commit sửa (`3d53c7c`, `a49bc13`) là tối ưu hiệu năng rải ở `post-fix-gate.py` / `regression_gate.sh` đã viết lại; bản vá đưa lại chỉ làm đỏ test khác, không làm đỏ `test_regression_gate_hook.sh` (không nêu tên test). Không tìm được cách đưa bug trở lại mà test bảo vệ đỏ ⇒ để nguyên.
- `BUG-20261002-agent-kit-health-run-tests-scores-96-100` — chưa chạy: bản sửa nằm ở `tests/run_impacted.sh` (file test: công cụ cấm vá) và `bin/agent-kit` (không đuôi, đã viết lại thành pool song song).
- `BUG-20261009-run-impacted-recent-commits-in-sandbox` — chưa chạy: bản sửa chính là `tests/run_impacted.sh` (file test).

#### Bước 5 — việc còn lại của Bước 3 (mục 2–4)
Quyết định chính sách do người dùng chọn qua câu hỏi: runner thiếu `set -e` ⇒ dòng nối thêm là sửa test (có); guard chỉ đóng ca ít báo động giả (`eval "$(…)"`, `source <(…)`, `bash script.sh`, `rm -r $VAR` giữ nguyên là giới hạn đã biết).

| Mục | Kết quả | Guard (đỏ → xanh) |
|---|---|---|
| `tee >(sh)`, `bash -c "$(…)"` | **xong** | `test_git_guard_shell_subst.sh` 9 → 0 |
| `find` có `!` / `-not` / `-o` | **xong** (+ sửa theo audit: nhóm bị phủ định) | `test_hardware_find_not_or.sh` 13 + 2 → 0 |
| `eval "$(…)"`, `source <(…)`, `bash script.sh`, `rm -r $VAR` | **không đóng (quyết định)** — phổ biến và hợp lệ (ssh-agent, brew shellenv, completions) | test hiện có khẳng định chúng được phép |
| `comment_claim_guard`: docstring Python, comment cuối dòng | **xong** | `test_comment_claim_docstring_trailing.sh` 10 → 0 |
| Đè test JS `it()` ở hai `describe` | **xong** (đếm theo đường `describe`; quét lỗi thì quay về đếm cả file) | `test_gate_js_describe_scope.sh` 4 → 0 |
| Runner thiếu `set -e` | **xong** (quyết định của người dùng) | `test_gate_runner_no_errexit.sh` 4 → 0 |
| `review_timing_guard` truyền payload qua env | **xong** (fd 3) | `test_review_timing_guard_big_payload.sh` 2 → 0 |
| Hook dò thư mục log theo cwd | **xong cho 7 hook làm rò `.claude/` ra cwd tiến trình**; 3 hook còn lại (`foreign_repo_gate`, `session_context`, `worktree_merge_gate`) đo ra không ghi gì ngoài project | `test_hook_log_dir.sh` 14 → 0 |
| `churn_guard` không có đường tắt | **xong** (`grep -c -F` 8 ms vs python 30 ms) | `test_churn_guard_fast_path.sh` 6 → 0 |
| `prompt_context` ~150 ms | **không đổi**: đo 160–240 ms/prompt; `enrich_context.py` 83 ms việc thật (biên dịch regex 20 ms, hai lần `git` 14 ms, import 28 ms) — không có phép tối ưu tất định đáng kể | — |
| Gate khởi động ~110 ms | **không đổi**: biên dịch 46 ms của 5,3 nghìn dòng; muốn bỏ phải tách file mà test nạp nó theo đường dẫn | — |

**Review ngữ cảnh sạch** (principal-code-reviewer trên 94f388c..6e6642b, bắt buộc bởi `review_gate`) tìm 6 điểm P3, đã sửa trong `fcf9fea`, mỗi điểm một ca đỏ → xanh: `find` nhóm dương chứa `-o` / đối số `-exec` bị từ chối nhầm (hồi quy của chính tôi) và toán tử `,`; chuỗi ba nháy gán mở docstring giả; `#!/bin/sh -e` không phải errexit; `bash -c ": ; $(…)"` lọt; `security_gate` mất luật fail-closed khi thiếu python3 ngoài cây git; registry phiên so git dir bằng chuỗi. Bảy dòng bug bị ảnh hưởng đã chứng minh ĐỎ lại (PROVEN).

Ba vòng review sau đó (chỉ commit sửa của vòng trước) tìm thêm 1 P2 + 3 P3, 2 P2 + 3 P3, rồi 2 P3 ở `b4ad8a9`; tất cả đã sửa, mỗi điểm một ca đỏ → xanh (vòng bốn: ĐỎ 7 trong `test_git_guard_shell_subst.sh` — một dấu ngoặc trong phép so sánh tắt kiểm tra phần còn lại của script `-c`, và thân `$( … )` thường bị coi là dữ liệu). Chi tiết và giới hạn đã chấp nhận (ngoặc trong nháy, `watch`/`ssh` trong `bash -c`) ở `CHANGELOG.md` "Đợt 13". Vòng 8 RED-proof: hai dòng `hardware-find-negated-or-unfiltered` và `git-guard-bash-c-subst-tee-shell` PROVEN lại sau các vòng sửa.

Giới hạn đã biết (chưa đóng): regex lấy `cwd` của payload (9 hook cũ + 7 hook mới) không đọc JSON thoát (`é`, `\\`); chỉ ảnh hưởng khi `CLAUDE_PROJECT_DIR` không đặt VÀ cwd tiến trình nằm ngoài cây git. Nâng cấp khi có harness gửi payload `ensure_ascii`: giải mã bằng python ở nhánh hiếm đó.

#### Bước 6 (mục 5 cũ) — kiểm chứng trên macOS
- Chạy thật lần đầu: xong (bước 1–3).
- `head_and_dirty` băm NỘI DUNG đích của symlink: **đã xác nhận** trên macOS (symlink trỏ lại sang file cùng nội dung ⇒ cùng sha; symlink treo ⇒ `None`). `push_gate.tested_fingerprint` đã bỏ qua so khớp chính xác khi có symlink trong `dirty` (ghi sẵn trong code), nên không đổi.
- Gemini qua alias (`includeDirectories` dùng đường dẫn thật): **chưa kiểm** — cần một phiên Gemini thật.

#### Việc người dùng hỏi thêm giữa chừng (Stop hook chạy lâu; worktree không merge/xoá)
- **Stop hook, GeelyEx2 hôm nay**: 28 lần gate ≈ 116 phút; 83 phút là Gradle. Nguyên nhân đo được: 11.229 file untracked dưới `CarConnect/app/src/test/resources` khớp glob của rule `REG-CAR-01` và không phải "mã nguồn bản đồ test hiểu được" ⇒ `select_impacted_tests` trả `ok=False` ⇒ **mỗi lượt Stop chạy ĐỦ lệnh Gradle** (214–300 s) thay vì 3 test thu hẹp (kiểm bằng cách gọi hàm với chỉ các file `.kt`: `ok=True, count=3`). Thêm ~60 s chi phí gate cho 11.267 file đổi. Commit hoặc ignore các file này là cách cắt nhiều nhất; gộp suite chỉ cắt phần nhỏ. Phiên GeelyEx2 đang tự gộp `REG-CAR-VOICE` vào `REG-CAR-01` (`covered_by`): cơ chế này chỉ bỏ VOICE khi `REG-CAR-01` đã chạy lệnh ĐẦY ĐỦ và PASS — ở lượt Stop điều đó đang xảy ra chính vì fallback nói trên. Hệ quả cần biết: khi 11k file được commit/ignore và `REG-CAR-01` chạy thu hẹp, VOICE (9 lớp, 140–270 s) KHÔNG còn được che và sẽ chạy riêng mỗi khi file voice đổi. Lựa chọn "gộp 3 suite Gradle thành 1 lệnh" của người dùng **chưa thực hiện**: `REG-CAR-VOICE` đã được phiên GeelyEx2 gộp bằng `covered_by` (commit–revert–commit trong giờ qua, tôi không sửa đè lên matrix đang bị sửa), `REG-CAR-01` và `REG-SHARED-01` dùng cùng lệnh đầy đủ và gate chạy mỗi lệnh một lần, và số đo cho thấy gộp thêm chỉ cắt phần nhỏ so với 11k file đang ép chạy đủ.
- **Worktree để lại**: ba nguyên nhân đo được ở GeelyEx2 — (1) phiên a792ad73 còn sống giữ main nên tự gộp bị hoãn (đúng luật: không gộp worktree của phiên đang chạy); (2) lần tự gộp `giao-tichhop-09-10` 19:03 bị pre-commit gate từ chối và thông báo cũ chỉ giữ 500 ký tự CUỐI của output gate (đoạn "0 phát hiện … REJECT"), mất lý do — **đã sửa** (`_refusal_text`, `test_worktree_automerge_reason.sh`); (3) worktree chưa từng vào danh sách "nợ" của một phiên đã kết thúc không bao giờ được phiên sau nhận nuôi (chỉ liệt kê ở SessionStart) — chưa đổi. Người dùng chọn để phiên GeelyEx2 tự gộp; không đụng vào worktree nào ở đó.
