# DevKit Governance, Sync & Management

Nhóm công cụ quản trị vòng đời, đồng bộ cấu hình và quản lý bộ nhớ:

- `build_inputs.py`: Định nghĩa các input build cần thiết cho sandbox testing.
- `claude_memory.py`: Quản lý bộ nhớ lâu dài và đồng bộ dự án cho Claude.
- `context_sync.py`: Đồng bộ các quy tắc, profile, và essentials vào `.agents/context/`.
- `devkit_clean.py`: Dọn dẹp logs, cache cũ và artifacts tạm thời.
- `devkit_i18n.py`: Xử lý đa ngôn ngữ (tiếng Việt / English) cho DevKit.
- `devkit_uninstall.py`: Gỡ bỏ an toàn DevKit khỏi dự án mà không ảnh hưởng mã nguồn chính.
- `fold_agent_file.py`: Gấp gọn và chuyển đổi nội dung tệp agent cũ vào `AGENTS.md`.
- `i18n.sh`: Script trợ giúp ngôn ngữ hiển thị trong Shell scripts.
- `index_memory.py`: Đánh chỉ mục bài học kinh nghiệm (`instincts`).
- `matrix_detect.py`: Tự động nhận diện build tool và sinh ma trận kiểm thử hồi quy.
- `memory_stats.py`: Thống kê tần suất truy vết bẫy lỗi và quy tắc từ transcripts.
- `merge_json.py`: Hợp nhất an toàn cấu hình JSON (settings, hooks, configs).
- `merge_markdown.py`: Hợp nhất nội dung Markdown có gắn block đánh dấu DevKit.
- `nightly.py`: Bộ lập lịch kiểm thử định kỳ và chạy lại các test nặng.
- `profile_skills.py`: Lọc và xác thực danh sách skill hợp lệ theo profile.
- `relink_check.py`: Tự động phục hồi các symlink bị mất sau git checkout/merge.
- `sync_commands.sh`: Đồng bộ hóa slash commands và aliases.
- `token_cost_tracker.py`: Giám sát và theo dõi chi phí token theo phiên làm việc.
