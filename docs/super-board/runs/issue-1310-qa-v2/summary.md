# QA v2 · issue #1310 · PR #1313 · head da9a16d
Lệnh: bash tests/super-board/test_queue_ac_autofix_1310.sh → exit 0, 18 ✔ (A1 A1b A2 A3 A4 A5, B x4, B2 x2, B3 x2, B4 x3), 0 ✘
Gate: post-fix-gate.py --run-tests --scoped --brief --json → super-board-qa-exit2.sh in `pass` (exit 0)
RED trên main (v1): 5 FAILED (A1, A1b, B x3); A4/A5/B3/B4 mới: RED do builder báo (mutant B4), QA không tự chạy lại.
Lưu ý: fixture in "rm: ...merge-queue.trains: is a directory" (ồn, không ảnh hưởng kết quả).
Không UI, không ảnh. Log thô: /tmp/qa-agent-workbench-1310-autofix.log (không commit).
