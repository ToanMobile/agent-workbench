# QA #1350 v3 — PR #1360 @ fd2723b6

Base: origin/main đã merge (Already up to date).

| Lệnh | Exit | Kết quả |
|---|---|---|
| bash tests/super-board/test_runner_read_recover_sites_1350.sh | 0 | 17 ca xanh (A-K2, G) |
| bash tests/super-board/test_runner_mq_restart.sh | 0 | all passed |
| bash tests/super-board/test_runner_watchdog.sh | 0 | all passed |

Ca K1/K2 (set_card_status, audit major :459) xanh: tạm thời thì nhả rồi ghi, dai dẳng thì exit 79.
RED của K1/K2 do builder báo (tự chạy trên base); QA không chạy lại RED (hook chặn khôi phục file).
Chưa làm: AC4 (chạy thật sau merge + sync kit).
