# QA v7 #1102 — PR #1173 @ d326c0f7 (rebuild-5, sửa R8)
- RED: chạy test mới trên hook cũ (9810c071) trong bản xuất tạm: 7 ca R8 ĐỎ (rc 0, muốn rc 2): /bin/ln, ./ln, glob ?, glob *, brace, tilde, `done` làm đối số. Hook mới (d326c0f7): rc 0, tất cả XANH
- test_session_lock_trunk_for_loop_1102.sh, test_runner_agy_cwd_1102.sh, test_lane_worktree_kit.sh, test_qa_detached_worktree.sh rc 0
- 9 test session_lock cũ (test_session_lock, file_writes, grok_shell, trunk, target_repo, issue427, round3_427, backlog427, resolve) rc 0
- Probe thêm bằng hook thật: `env ln`, `command ln`, `./` và `../` trong đích, `>>`, `tee`, `cp`, `${t}`, ghi vào main sau/trong vòng, dạng nhiều dòng đều rc 2; ca đối chứng /tmp và thư mục ngoài main rc 0
- Gate scoped: exit 2, phân loại `review` (hồi quy 10/10, lớp tĩnh sạch); lý do duy nhất: 2 test cũ bị sửa (test_lane_worktree_kit.sh, test_qa_detached_worktree.sh) và SKILL.md cần agent khác (không phải Antigravity) duyệt chéo
- Phát hiện ngoài phạm vi (đã có sẵn, không do #1102): `link <file trong main> <đích ngoài>; echo x > <đích>` (hardlink) trả rc 0 cả khi KHÔNG có for-loop, vì `_MAKES_PATH` không có `link`. Ghi nhận cho Review, không chặn thẻ
- Chưa làm: SessionStart một dòng (tuỳ chọn)
