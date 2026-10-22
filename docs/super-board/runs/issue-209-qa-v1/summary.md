# QA #209 v1 — qa_workers / review_workers

Đầu nhánh được kiểm: a4bbdb6380 (PR #217).

| Lệnh | Exit | Kết quả |
|---|---|---|
| `bash tests/super-board/test_runner_lane_workers.sh` | 0 | all passed (qa 3 tester + thẻ 4 chờ, review 2, zombie extra, mặc định 1, tải cao giữ nguyên) |
| `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief --diff origin/main` | 0 | PASS, hồi quy 46/46, lớp tĩnh đạt |

Rà diff: `top_card_in_column` bỏ thẻ đang có lock (`issue_locked`) nên worker thêm không nhận trùng thẻ.
Ảnh: không cần, không có UI.
