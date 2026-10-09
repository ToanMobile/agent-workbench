# Audit DevKit 2026-10-09 — chạy tiếp ở local (macOS): kết quả

## Trạng thái

| Nơi | Commit | Nội dung | Đã kiểm chứng |
|---|---|---|---|
| `main` | `4425001` | Đợt 1–3 làm trên Linux cloud | trên Linux: 158/158 test bị ảnh hưởng |
| `main` | `94f388c` | macOS: so sánh đường dẫn theo inode (APFS), test camelCase, race worktree biến mất, guard `bash -c "$(…)"` / `>(sh)` / `find !`/`-o` | gate `--full` exit 0 |
| `main` | `430fb87` | `review_timing_guard` đọc payload qua fd 3, `DEVKIT_IMPACTED_SINCE` | gate `--full` exit 0 |
| `main` | `63f9561` | runner thiếu `set -e`, phạm vi `describe` JS, docstring/comment cuối dòng, project từ `cwd` payload (7 hook), đường tắt `churn_guard` | gate `--full` exit 0 (6/6), `run_impacted.sh` 112/112 |
| `main` | `6e6642b` | lý do từ chối của automerge, sửa theo audit Antigravity T0024 | gate `--full` exit 0 (3/3), `run_impacted.sh` 52/52 |

## Bước 1–2 — kiểm chứng trên macOS (bash 3.2, APFS) — xong
- 6 test của đợt 3: PASS ngay (hook contract 687/687).
- `run_impacted.sh --all` (177 test, 377 s): 175 xanh, **2 đỏ thật**, sửa gốc:
  - `test_session_lock.sh` (case-only cwd): `realpath` giữ nguyên hoa/thường, APFS không phân biệt ⇒ đường dẫn viết khác hoa/thường bị coi là NGOÀI checkout đang khoá. `_inside` / `_same_dir` so theo inode ở 4 chỗ. ĐỎ 3 → XANH.
  - `test_hook_camelcase_payload.sh`: bash 3.2 cắt đối số `"$(cmd "{\"a\":…}")"` tại dấu nháy thoát ⇒ 2 hook chạy trên rác. Payload dựng bằng phép gán; assertion giữ nguyên.
- 1 lỗi **chập chờn** của gate (`test_worktree_merge_gate_owner.sh` mục 7, đỏ 2/3 lần gate): lỗi sản xuất thật — merge nền của Stop trước xoá worktree đúng lúc Stop này đang quyết định, dòng đó ở lại danh sách giữ. `worktree_merge_gate.sh` bỏ dòng có thư mục đã biến mất. Test tất định mới (shim `git`): ĐỎ 2 → XANH.
- `test_guards_orphans.sh` đỏ chỉ do luật runner mới: fixture thêm `set -e`, assertion giữ nguyên.

## Bước 3 — gate `--full` — exit 0
Dòng rác `REG-01 echo FULL_TEST_EXECUTED` đã tự biến khỏi `CHECKLIST.md` và `regression_status.json` (kiểm: 0 khớp ở cả hai).

## Bước 4 — RED-proof các dòng bug cũ
Công cụ: `scripts/testing/red_proof.py`; không sửa JSON tay. Hai phát hiện về chính công cụ:
- Sandbox không có upstream ⇒ `run_impacted.sh` tính commit của 6 giờ qua là "đã đổi" ⇒ mỗi bằng chứng 15+ phút chưa xong. Thêm `DEVKIT_IMPACTED_SINCE` (`0` = tắt cửa sổ); đặt khi chạy bằng chứng: 1–10 phút.
- `.sh` không nằm trong `SOURCE_EXT` của `red_proof.py`, và code đã chuyển chỗ/viết lại nên `git revert` xung đột: các bằng chứng dùng `--patch` (bản vá đưa bug trở lại, lưu ở `.agents/local/red-patches/`, đã commit).
- `tests/impact_map.txt` thiếu `enrich_context.py → test_bug_capture.sh`: gate không chạy test bảo vệ bộ lọc ROLE_OPENING, và bằng chứng của bug đó ra VACUOUS giả. Đã thêm (có test).

Kết quả (nguồn sự thật: cột RED-proof trong `.agents/CHECKLIST.md`): **29 PROVEN / 1 INCONCLUSIVE / 2 chưa chạy** trong 32 dòng bug. Trong 19 dòng "⏳ chưa chứng minh ĐỎ" ban đầu: **17 PROVEN**. Còn lại, kèm lý do:
- `BUG-20260929-audit-review-nguyen-nhan-tai-sao-cac-ses` — INCONCLUSIVE: hai commit sửa (`3d53c7c`, `a49bc13`) là tối ưu hiệu năng rải ở `post-fix-gate.py` / `regression_gate.sh` đã viết lại; bản vá đưa lại chỉ làm đỏ test khác, không làm đỏ `test_regression_gate_hook.sh` (không nêu tên test). Không tìm được cách đưa bug trở lại mà test bảo vệ đỏ ⇒ để nguyên.
- `BUG-20261002-agent-kit-health-run-tests-scores-96-100` — chưa chạy: bản sửa nằm ở `tests/run_impacted.sh` (file test: công cụ cấm vá) và `bin/agent-kit` (không đuôi, đã viết lại thành pool song song).
- `BUG-20261009-run-impacted-recent-commits-in-sandbox` — chưa chạy: bản sửa chính là `tests/run_impacted.sh` (file test).

## Bước 5 — việc còn lại của Bước 3 (mục 2–4)
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

Giới hạn đã biết (chưa đóng): regex lấy `cwd` của payload (9 hook cũ + 7 hook mới) không đọc JSON thoát (`é`, `\\`); chỉ ảnh hưởng khi `CLAUDE_PROJECT_DIR` không đặt VÀ cwd tiến trình nằm ngoài cây git. Nâng cấp khi có harness gửi payload `ensure_ascii`: giải mã bằng python ở nhánh hiếm đó.

## Bước 6 (mục 5 cũ) — kiểm chứng trên macOS
- Chạy thật lần đầu: xong (bước 1–3).
- `head_and_dirty` băm NỘI DUNG đích của symlink: **đã xác nhận** trên macOS (symlink trỏ lại sang file cùng nội dung ⇒ cùng sha; symlink treo ⇒ `None`). `push_gate.tested_fingerprint` đã bỏ qua so khớp chính xác khi có symlink trong `dirty` (ghi sẵn trong code), nên không đổi.
- Gemini qua alias (`includeDirectories` dùng đường dẫn thật): **chưa kiểm** — cần một phiên Gemini thật.

## Việc người dùng hỏi thêm giữa chừng (Stop hook chạy lâu; worktree không merge/xoá)
- **Stop hook, GeelyEx2 hôm nay**: 28 lần gate ≈ 116 phút; 83 phút là Gradle. Nguyên nhân đo được: 11.229 file untracked dưới `CarConnect/app/src/test/resources` khớp glob của rule `REG-CAR-01` và không phải "mã nguồn bản đồ test hiểu được" ⇒ `select_impacted_tests` trả `ok=False` ⇒ **mỗi lượt Stop chạy ĐỦ lệnh Gradle** (214–300 s) thay vì 3 test thu hẹp (kiểm bằng cách gọi hàm với chỉ các file `.kt`: `ok=True, count=3`). Thêm ~60 s chi phí gate cho 11.267 file đổi. Commit hoặc ignore các file này là cách cắt nhiều nhất; gộp suite chỉ cắt phần nhỏ. Phiên GeelyEx2 đang tự gộp `REG-CAR-VOICE` vào `REG-CAR-01` (`covered_by`): cơ chế này chỉ bỏ VOICE khi `REG-CAR-01` đã chạy lệnh ĐẦY ĐỦ và PASS — ở lượt Stop điều đó đang xảy ra chính vì fallback nói trên. Hệ quả cần biết: khi 11k file được commit/ignore và `REG-CAR-01` chạy thu hẹp, VOICE (9 lớp, 140–270 s) KHÔNG còn được che và sẽ chạy riêng mỗi khi file voice đổi. Lựa chọn "gộp 3 suite Gradle thành 1 lệnh" của người dùng **chưa thực hiện**: `REG-CAR-VOICE` đã được phiên GeelyEx2 gộp bằng `covered_by` (commit–revert–commit trong giờ qua, tôi không sửa đè lên matrix đang bị sửa), `REG-CAR-01` và `REG-SHARED-01` dùng cùng lệnh đầy đủ và gate chạy mỗi lệnh một lần, và số đo cho thấy gộp thêm chỉ cắt phần nhỏ so với 11k file đang ép chạy đủ.
- **Worktree để lại**: ba nguyên nhân đo được ở GeelyEx2 — (1) phiên a792ad73 còn sống giữ main nên tự gộp bị hoãn (đúng luật: không gộp worktree của phiên đang chạy); (2) lần tự gộp `giao-tichhop-09-10` 19:03 bị pre-commit gate từ chối và thông báo cũ chỉ giữ 500 ký tự CUỐI của output gate (đoạn "0 phát hiện … REJECT"), mất lý do — **đã sửa** (`_refusal_text`, `test_worktree_automerge_reason.sh`); (3) worktree chưa từng vào danh sách "nợ" của một phiên đã kết thúc không bao giờ được phiên sau nhận nuôi (chỉ liệt kê ở SessionStart) — chưa đổi. Người dùng chọn để phiên GeelyEx2 tự gộp; không đụng vào worktree nào ở đó.
