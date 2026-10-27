# QA #489 v1 (PR #507, head c5e8ec9c + merge origin/main)

- tests/super-board/test_worker_wrap_term.sh: 3 lượt rc=0, "all passed".
- tests/super-board/test_runner_merge_queue.sh: 3 lượt rc=0, 5 s mỗi lượt, 54 ✔ / 0 ✖ (không đổi so với trước).
- RED trên wrapper base (origin/main): "wrapper still alive 6 s after TERM", rc=1. GREEN trên nhánh.
- Không còn sleep 301 do test để lại (các worker-wrap còn thấy thuộc phiên board khác).
- post-fix-gate --run-tests --brief (impacted): PASS 3/3, biên nhận task đã ghi.
- AC1 (tái hiện, ≥3 lượt): đạt, máy rảnh không treo; builder ghi 4/40, 9/40 treo khi ép tải.
- AC2 (<120 s, không tiến trình sót, 3 lượt): đạt (5 s).
- AC3 (số assertion không giảm): đạt (54, file test không đổi).
- Chưa kiểm: worker claude thật (chỉ stub), stress dưới tải do QA không chạy lại.
