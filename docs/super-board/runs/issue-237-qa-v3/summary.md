# QA #237 v3 — PR #244 @ 51d0571c (sau reviewer vòng 2: R5, R7)

Nhánh đã up to date với origin/main (merge --no-edit: Already up to date). Không còn thread `[qa]`/`[builder]` chưa giải quyết.

| Lệnh | Exit | Kết quả |
|---|---|---|
| bash tests/super-board/test_worker_death_record.sh | 0 | ALL PASS (A–K) |
| bash tests/super-board/test_runner_build_workers.sh | 0 | all passed |
| bash tests/super-board/test_runner_lane_workers.sh | 0 | không có dòng ✖ |
| bash tests/super-board/test_runner_lanes.sh | 0 | không có dòng ✖ |
| post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main (dòng của merge gate) | 0 | PASS, hồi quy 61/61 |

Mutation (khôi phục sau mỗi lần, cây sạch):
- Bỏ `exit=143` khỏi bỏ-qua-comment (R7) → K ĐỎ ("143 commented"); khôi phục → XANH.
- Đổi `gh_checkpoint` + `gh issue comment || true` về `gh_write_once` (R5) → J ĐỎ (runner exit 79); khôi phục → XANH.

Chưa kiểm: worker `claude -p` stream-json thật đầu cuối.
