# QA #209 v2 — qa_workers / review_workers

Đầu nhánh được kiểm: 95e4396188 (PR #217, sau khi đồng bộ lại với main).

| Lệnh | Exit | Kết quả |
|---|---|---|
| `bash tests/super-board/test_runner_lane_workers.sh` | 0 | all passed |
| Mutant: bỏ vòng `check_lane_zombie` cho `QA_EXTRA` | 1 | `✖ qa zombie: 3 workers, #2 pid alive=y` (test bắt được), đã khôi phục |
| `post-fix-gate.py --run-tests --full --brief --diff origin/main` | 0 | PASS, hồi quy 47/47, lớp tĩnh đạt |

AC1 3 tester + thẻ 4 chờ · AC2 2 reviewer, merge.lock giữ nguyên · AC3 zombie extra bị giết · AC4 mặc định 1 · AC5 gate exit 0.
Ảnh: không cần, không có UI.
