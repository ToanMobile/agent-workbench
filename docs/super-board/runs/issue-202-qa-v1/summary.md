# QA #202 v1 — thứ tự Ready theo ưu tiên, lọc thẻ repo khác / Fix trùng

| Kiểm | Lệnh | Kết quả |
|---|---|---|
| Test PR | `bash tests/super-board/test_runner_ready_order.sh` | exit 0, 11/11 ✔ |
| ĐỎ trên base | cùng test với `super-board-run.sh` của origin/main | 8 ✖ (đã khôi phục file PR) |
| Runner lân cận | build_workers, claim_loop, lanes, reclaim_dead_build, watchdog, disk_gc_once | cả 6 exit 0 |
| Gate | `post-fix-gate.py --run-tests --full --brief --diff origin/main` | exit 0, hồi quy 46/46 |

AC1 bug cũ #188 trước feature mới #201 ✔ · AC2 priority label trước ✔ · AC3 repo/checkout khác → Blocked + block-template ✔ · AC4 Fix trùng #151 Ready → không giao, comment 1 lần ✔ · AC5 gate exit 0 ✔

Test gaps (không viết, Medium/Low): body chỉ trích dẫn repo khác bị chặn nhầm về Blocked (Builder đã nêu); thẻ Fix tham chiếu #N đã Done không bị chặn (đúng ý).
Không có ảnh: thay đổi chỉ ở script runner, không lên màn hình.
