# Universal Agent DevKit — Test Suite Architecture

Thư mục `tests/` chứa toàn bộ 90 bài kiểm thử hồi quy tĩnh và thực thi (Executable Regression Tests) của DevKit.

> **Quy ước kiến trúc (Architectural Invariant):**
> Mỗi test nằm đúng MỘT cấp thư mục theo phân vùng bên dưới: `tests/<phân vùng>/test_*.sh`
> (`gates/`, `installer/`, `context_memory/`, `worktree_git/`, `verification/`). Không để `test_*.sh` phẳng trong `tests/`.
> 1. Gốc DevKit trong mỗi test: `DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"` (một `/..` thêm so với trước).
> 2. `run_impacted.sh` và `agent-kit test` duyệt glob `tests/*/test_*.sh`; `test_repo_consistency.sh` (R9) giữ cho cấu trúc,
>    các glob đó và regex của `test_evidence_gate.sh` luôn khớp nhau — một glob còn trỏ `tests/test_*.sh` sẽ khớp 0 file và đạt im lặng.
> 3. Tránh vượt ngưỡng timeout 900 giây (15 phút) của Post-Fix Gate (`post-fix-gate.py`).
> Thêm test mới: đặt vào đúng phân vùng, rồi chạy `bash tests/verification/test_repo_consistency.sh`.
---

## 5 Phân Vùng Nghiệp Vụ (Domain Test Groups)

### 1. Gates & Proofs (`gates/`)
Bảo vệ tính toàn vẹn của cổng kiểm thử sau khi sửa code, bằng chứng thực thi, và ngăn chặn commit khi chưa nghiệm thu:
- `test_postfix_gate.sh`: Kiểm thử 8 tầng kiểm soát của `post-fix-gate.py` (exit 0/1/2/3).
- `test_proof_gate.sh`: Kiểm thử cổng chặn ảnh nghiệm thu và hash cây mã nguồn (`tree_fp.py`).
- `test_proof_capture.sh` & `test_proof_capture_screen.sh`: Tự động khởi động emulator/AVD và chụp ảnh màn hình nghiệm thu.
- `test_repeat_proof.sh`: Chống gian lận tái sử dụng ảnh chụp cũ hoặc trùng byte sha256.
- `test_push_gate.sh` & `test_push_gate_hook.sh`: Cổng chặn lệnh `git push` khi chưa chạy full test gate.
- `test_regression_gate_hook.sh`: Hook kiểm tra ma trận hồi quy trước khi kết thúc lượt làm việc.
- `test_foreign_repo_gate.sh`: Ngăn chặn agent can thiệp hoặc chạy script trên repo bên ngoài chưa được cấp quyền.
- `test_gate_cache_key.sh` & `test_gate_cache_record.sh`: Quản lý bộ nhớ đệm cache kết quả test gate.
- `test_gate_fixes.sh`, `test_gate_friction.sh`, `test_gate_full_stale.sh`, `test_gate_reasons.sh`, `test_gate_receipt.sh`, `test_gate_since_new_test.sh`, `test_gate_since_test_edit.sh`: Các quy tắc kiểm tra ma trận lý do chặn/cho phép của gate.
- `test_gate_matrix_rename.sh`: Đổi tên file test mà ma trận nhắc tới: gate theo dõi rename do chính git ghi nhận, không để sửa ma trận lách test.
- `test_multi_session_gate.sh`: Cơ chế khóa phiên đa tác nhân và phát hiện xung đột phiên song song.
- `test_worktree_merge_gate.sh`: Cổng kiểm tra tính an toàn trước khi sáp nhập worktree sandbox vào main.

### 2. Installer, CLI & Profiles (`installer/`)
Quản lý cài đặt, gỡ bỏ, cập nhật DevKit và cấu hình các domain profiles:
- `test_install_cli.sh`, `test_install_idempotency.sh`, `test_install_safety.sh`: Cài đặt DevKit an toàn, tính lũy đẳng không ghi đè cấu hình người dùng.
- `test_quick_install.sh` & `test_uninstall.sh`: Thử nghiệm kịch bản cài nhanh và gỡ sạch sẽ.
- `test_reinit_keeps_setup.sh`: Re-init không làm mất các file thiết lập hiện hữu.
- `test_agent_config.sh`: Kiểm thử lệnh `agent-kit profile` nạp quy tắc theo từng profile mà không làm bẩn repo.
- `test_agent_health.sh`: Kiểm thử lệnh chẩn đoán `agent-kit health` và tự sửa chữa tính nhất quán.
- `test_platform_rules.sh`: Xác thực quy tắc cho 6 nền tảng (Android, iOS, Game Unity, Automotive, Web, Universal).
- `test_i18n_profiles.sh`: Đa ngôn ngữ (Anh/Việt) cho luật và thông báo.

### 3. Context, Memory & AI Governance (`context_memory/`)
Đồng bộ ngữ cảnh phiên làm việc, bộ nhớ tác nhân và chống lặp vòng lặp suy luận:
- `test_session_context.sh` & `test_session_authorship.sh`: Nạp context tự động vào đầu prompt cho Claude/Antigravity/Gemini.
- `test_session_lock.sh`: Cơ chế chiếm giữ và giải phóng khóa phiên làm việc (Session Lock).
- `test_prompt_context.sh`: Kiểm thử inject bẫy mã nguồn lịch sử (instincts) và rules vào prompt.
- `test_context_sync.sh`: Đồng bộ file `AGENTS.md` và `rules-index.md`.
- `test_memory_stats.sh`: Thống kê dung lượng và dọn dẹp bộ nhớ đồ thị tri thức.
- `test_injection_block.sh`: Phát hiện và ngăn chặn tấn công Prompt Injection trong input/output.
- `test_token_cost_tracker.sh`: Giám sát và cảnh báo tiêu hao token.
- `test_anti_loop_disclosure.sh` & `test_anti_loop_ownership.sh`: Chặn vòng lặp sửa lỗi mù quáng (Anti-Loop heuristic).
- `test_learn.sh`: Tự động trích xuất bài học và ghi nhận vào `.agents/instincts.md`.
- `test_completion.sh` & `test_local_tier.sh`: Cơ chế tiered verification (Scout -> Verify -> Auditor).
- `test_budgets.sh`: Giới hạn tài nguyên và thời gian thực thi của tác nhân.

### 4. Worktree & Git Hygiene (`worktree_git/`)
Bảo vệ nhánh Git, cách ly thử nghiệm sandbox và quản lý hook git:
- `test_worktree.sh`, `test_worktree_sandbox.sh`, `test_worktree_status.sh`: Tạo sandbox bản sao CoW (<100ms) trên APFS, chạy thử và tự động dọn dẹp.
- `test_githooks.sh`: Quản lý pre-commit, commit-msg hook tích hợp với DevKit.
- `test_commit_hygiene.sh`: Chuẩn hóa message commit (Conventional Commits tiếng Việt, cấm lộ secret).
- `test_clean.sh`: Dọn rác file tạm, cache build.
- `test_restore_old.sh` & `test_x_old_conflict_isolation.sh`: Cách ly các file backup `.X_old` không làm sai lệch build.
- `test_relink.sh` & `test_auto_link.sh`: Quản lý liên kết tương đối giữa các công cụ và cấu hình.

### 5. Verification, Bug Oracle & Consistency (`verification/`)
Quy trình Paired Test Oracle (RED -> GREEN), phát hiện hồi quy và kiểm tra chất lượng mã nguồn:
- `test_red_proof.sh` & `test_red_proof_hash.sh`: Bắt buộc phải có bài test ĐỎ trước khi sửa lỗi và XANH sau khi sửa.
- `test_vacuity_since.sh`: Phát hiện test vô nghĩa (vacuous test / pass ảo không thực sự kiểm tra lỗi).
- `test_stale.sh`, `test_stale_deleted.sh`, `test_stale_rerun.sh`: Phát hiện và dọn dẹp các bằng chứng kiểm thử đã quá hạn (stale).
- `test_bug_capture.sh`, `test_bug_import.sh`, `test_bug_own_tests.sh`, `test_bug_unlink.sh`: Vòng đời ghi nhận, liên kết và quản lý mã lỗi (`agent-kit bugs`).
- `test_checklist_journal.sh`, `test_checklist_view.sh`, `test_regression_checklist.sh`: Tự động cập nhật checklist kiểm thử hồi quy (`CHECKLIST.md`).
- `test_flaky.sh`: Phát hiện bài test chập chờn (flaky test).
- `test_evidence_log.sh`, `test_evidence_unity.sh`, `test_run_unity_tests.sh`, `test_unity_batch.sh`: Bằng chứng kiểm thử tự động cho game Unity.
- `test_runner_quoted.sh`: An toàn shell quoting cho các lệnh test runner.
- `test_legacy_lint_and_red_gradle.sh`: Tương thích ngược với Gradle test runner.
- `test_lint_scripts.sh`: Linter kiểm tra toàn bộ script trong DevKit.
- `test_testsourceset.sh`: Nhận diện test source sets trong các ngôn ngữ khác nhau.
- `test_matrix_detect.sh`: Tự động nhận diện module và test runner (Gradle, npm, pytest, go, cargo, Unity, mcp-servers).
- `test_merge_json.sh`: Trộn cấu hình JSON an toàn không làm mất trường dữ liệu của người dùng.
- `test_run_impacted.sh` & `test_impacted_tests.sh`: Thuật toán xác định chính xác các bài test chịu ảnh hưởng bởi diff.
- `test_repo_consistency.sh`: Kiểm tra toàn diện 19 tiêu chí nhất quán tĩnh của repo.
- `test_mark_stale_speed.sh`: Tối ưu hóa tốc độ đánh dấu bằng chứng lỗi thời.
- `test_backlog.sh` & `test_inbox_req.sh`: Quản lý yêu cầu tồn đọng và hàng đợi xử lý.
- `test_agent_bridge.sh` & `test_adb_safe_exec.sh`: Cầu nối giao tiếp an toàn giữa các agent và thực thi ADB.
