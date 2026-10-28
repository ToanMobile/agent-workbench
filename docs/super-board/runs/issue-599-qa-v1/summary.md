# QA #599 v1
- Lệnh: `bash tests/super-board/test_runner_mq_restart.sh` trên main (đã merge origin/main): exit 0, 8/8 ✔.
- AC1 (ĐỎ khi không đọc .mq.pid): đột biến bỏ khối đọc `.mq.pid` trong merge_queue_due, 3 ✖ (runner #2/#3 bật bộ gom thứ hai, calls=2/3).
- AC2 (.mq.rc runner cũ, 79/9): đột biến bỏ nhánh đọc `.mq.rc`, 3 ✖ (rc 79 trả 0, calls=1).
- Đột biến chỉ là bản sao tạm của runner, đã xoá; không sửa code runner.
