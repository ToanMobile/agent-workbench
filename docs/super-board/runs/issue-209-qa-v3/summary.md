# QA #209 v3 — qa_workers / review_workers

Đầu nhánh được kiểm: 1cf00f2428 (PR #217, MERGEABLE; main đi trước 1 commit #152, gộp sạch).

| Lệnh | Exit | Kết quả |
|---|---|---|
| `bash tests/super-board/test_runner_lane_workers.sh` | 0 | all passed (AC1-AC4 đều có test) |
| Mutant: bỏ vòng zombie `REVIEW_EXTRA` (dòng 907) | 1 | `✖ review zombie: 2 workers, #6 alive=y` (test bắt được), đã khôi phục |
| `post-fix-gate.py --run-tests --full --brief --diff <merge-base>` | 0 | PASS, hồi quy 48/48, lớp tĩnh đạt |

Ghi chú: `--diff origin/main` cho exit 2 vì nhánh còn thiếu commit #152 của main (test_merge_gate_load_wait.sh hiện như "bị sửa"); so với merge-base thì exit 0.
AC1 3 tester + thẻ 4 chờ · AC2 2 reviewer, merge.lock giữ nguyên · AC3 zombie extra bị giết · AC4 mặc định 1 · AC5 gate exit 0.
Ảnh: không cần, không có UI.
