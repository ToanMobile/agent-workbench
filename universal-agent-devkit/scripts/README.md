# Universal Agent DevKit Scripts

Toàn bộ 44 công cụ thực thi của **Universal Agent DevKit** được cấu trúc mạch lạc thành **6 nhóm nghiệp vụ chuyên biệt**:

```
scripts/
├── context/       # 5 công cụ: Làm giàu ngữ cảnh, phân tích prompt, bẫy lỗi & rules
├── linters/       # 4 công cụ: Phân tích AST, kiểm tra rò rỉ bộ nhớ, GC, recomposition
├── testing/       # 5 công cụ: Paired Executable Oracle (RED->GREEN), test runner & proof
├── git/           # 6 công cụ: Git hooks, an toàn branch, worktree & parallel sandbox
├── governance/    # 18 công cụ: Quản trị vòng đời DevKit, sync context, i18n & ma trận test
└── audits/        # 6 công cụ: Bộ kiểm toán độc lập 50 agents, chaos test & zero-regression
```

---

## 1. `context/` — Ngữ cảnh & Phân tích Ý định
- [`agent_hooks.py`](context/agent_hooks.py): Cấu hình hook gates cho Claude, Codex, Gemini CLI, Cursor.
- [`enrich_context.py`](context/enrich_context.py): Phân tích ý định prompt, nạp NFRs, tra cứu bẫy lỗi (`instincts`), và gán skill phù hợp.
- [`hardware_boundaries.py`](context/hardware_boundaries.py): Phát hiện và bảo vệ ranh giới phần cứng / ngoại vi đặc thù.
- [`rule_context.py`](context/rule_context.py): Ánh xạ câu prompt tới các phần quy tắc tương ứng trong `.agents/local/rules/`.
- [`rules_index.py`](context/rules_index.py): Tạo chỉ mục quy tắc dự án dạng bảng `sed -n` tối ưu nạp vào context.

## 2. `linters/` — Phân tích Tĩnh AST
- [`assertion_lint.py`](linters/assertion_lint.py): Kiểm tra tính hợp lệ của assertion trong các file test.
- [`hardware_source_lint.py`](linters/hardware_source_lint.py): Kiểm tra các mẫu mã nguồn tương tác phần cứng, CAN bus, ngoại vi.
- [`lint_compose_stability.py`](linters/lint_compose_stability.py): Kiểm tra tính ổn định recomposition trong Jetpack Compose.
- [`lint_unity_gc.py`](linters/lint_unity_gc.py): Phát hiện GC allocation trong vòng lặp game (`Update`, `FixedUpdate`, Coroutines).

## 3. `testing/` — Kiểm thử & Nghiệm thu
- [`capture_3d_proof.py`](testing/capture_3d_proof.py): Chụp ảnh nghiệm thu mô hình 3D Blender / baked sprites.
- [`proof_phash.py`](testing/proof_phash.py): So sánh perceptual hash (pHash) của ảnh chụp bằng chứng nghiệm thu.
- [`red_proof.py`](testing/red_proof.py): Kiểm chứng Paired Executable Oracle (bắt buộc test ĐỎ trên mã nguồn lỗi).
- [`run_unity_tests.py`](testing/run_unity_tests.py): Chạy Unity NUnit tests độc lập không phụ thuộc UI.
- [`stale_rerun.py`](testing/stale_rerun.py): Chạy lại các ca kiểm thử bị ảnh hưởng hoặc quá hạn.

## 4. `git/` — Quản trị Git & Sandbox
- [`backup_conflict.sh`](git/backup_conflict.sh): Bảo vệ file cấu hình và tài nguyên cục bộ khi cập nhật DevKit (cơ chế `*_old`).
- [`git-commit-msg.sh`](git/git-commit-msg.sh): Kiểm tra định dạng commit message và bắt buộc ghi nhận Bug ID / No-Guard.
- [`git-pre-commit.sh`](git/git-pre-commit.sh): Chạy kiểm tra tĩnh post-fix gate trước khi commit.
- [`githooks.sh`](git/githooks.sh): Quản lý cài đặt / gỡ bỏ các git hooks chuẩn của DevKit.
- [`worktree.py`](git/worktree.py): Quản trị worktree độc lập cho các phiên agent song song.
- [`worktree_sandbox.py`](git/worktree_sandbox.py): Quản trị APFS Copy-on-Write sandbox siêu tốc (<100ms, 0-byte đĩa ban đầu).

## 5. `governance/` — Quản trị & Đồng bộ DevKit
- [`build_inputs.py`](governance/build_inputs.py): Định nghĩa các input build cần thiết cho sandbox testing.
- [`claude_memory.py`](governance/claude_memory.py): Quản lý bộ nhớ lâu dài và đồng bộ dự án cho Claude.
- [`context_sync.py`](governance/context_sync.py): Đồng bộ các quy tắc, profile, và essentials vào `.agents/context/`.
- [`devkit_clean.py`](governance/devkit_clean.py): Dọn dẹp logs, cache cũ và artifacts tạm thời.
- [`devkit_i18n.py`](governance/devkit_i18n.py): Xử lý đa ngôn ngữ (tiếng Việt / English) cho DevKit.
- [`devkit_uninstall.py`](governance/devkit_uninstall.py): Gỡ bỏ an toàn DevKit khỏi dự án mà không ảnh hưởng mã nguồn chính.
- [`fold_agent_file.py`](governance/fold_agent_file.py): Gấp gọn và chuyển đổi nội dung tệp agent cũ vào `AGENTS.md`.
- [`i18n.sh`](governance/i18n.sh): Script trợ giúp ngôn ngữ hiển thị trong Shell scripts.
- [`index_memory.py`](governance/index_memory.py): Đánh chỉ mục bài học kinh nghiệm (`instincts`).
- [`matrix_detect.py`](governance/matrix_detect.py): Tự động nhận diện build tool và sinh ma trận kiểm thử hồi quy.
- [`memory_stats.py`](governance/memory_stats.py): Thống kê tần suất truy vết bẫy lỗi và quy tắc từ transcripts.
- [`merge_json.py`](governance/merge_json.py): Hợp nhất an toàn cấu hình JSON (settings, hooks, configs).
- [`merge_markdown.py`](governance/merge_markdown.py): Hợp nhất nội dung Markdown có gắn block đánh dấu DevKit.
- [`nightly.py`](governance/nightly.py): Bộ lập lịch kiểm thử định kỳ và chạy lại các test nặng.
- [`profile_skills.py`](governance/profile_skills.py): Lọc và xác thực danh sách skill hợp lệ theo profile.
- [`relink_check.py`](governance/relink_check.py): Tự động phục hồi các symlink bị mất sau git checkout/merge.
- [`sync_commands.sh`](governance/sync_commands.sh): Đồng bộ hóa slash commands và aliases.
- [`token_cost_tracker.py`](governance/token_cost_tracker.py): Giám sát và theo dõi chi phí token theo phiên làm việc.

## 6. `audits/` — Bộ Kiểm toán Độc lập
- [`adversarial_chaos_test_10_agents.py`](audits/adversarial_chaos_test_10_agents.py): Chaos test tấn công đối kháng 10 kịch bản giả mạo kết quả test / receipt.
- [`audit_agent_perfection_50_agents.py`](audits/audit_agent_perfection_50_agents.py): Kiểm toán 50 tiêu chí hoàn thiện Agent theo 10 hội đồng thẩm định.
- [`audit_production_lifecycle_50_agents.py`](audits/audit_production_lifecycle_50_agents.py): Kiểm toán vòng đời sản phẩm, tài nguyên, coroutines và leak memory.
- [`audit_test_suite_50_agents.py`](audits/audit_test_suite_50_agents.py): Kiểm toán độ tin cậy và phân vùng kiểm thử (Paired Executable Oracle).
- [`audit_workflows_rules_skills_50_agents.py`](audits/audit_workflows_rules_skills_50_agents.py): Kiểm toán toàn vẹn quy tắc, profile isolation, và YAML frontmatter.
- [`audit_zero_regression_10_agents.py`](audits/audit_zero_regression_10_agents.py): Kiểm toán cơ chế chặn lỗi hồi quy (zero-regression gate).
