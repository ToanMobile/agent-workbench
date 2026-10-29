# QA v1 #572 — tlimit.py kẹt khi tín hiệu tới lúc giữ _waitpid_lock

Base: origin/main 56ca38e3 + PR #603 (chỉ docs). Tester chạy lại độc lập.

| AC | Lệnh | Kết quả |
|---|---|---|
| 1 ĐỎ SIGINT | `TLIMIT=<tlimit.py của 46559061> bash tests/gates/test_tlimit_waitlock.sh` | exit 1, FAIL (3): "tlimit still alive 10s after SIGINT (deadlock)" |
| 1 XANH SIGINT | `bash tests/gates/test_tlimit_waitlock.sh` (main) | exit 0, "exit 130 in 1s", "grandchild stopped" |
| 2 SIGTERM | cùng lệnh | "exit 143 in 1s", "grandchild stopped" |
| 3 trần giây | cùng lệnh | "SIGINT, child ignores TERM: exit 130 in 2s" (trần 5 s, tối đa 8 s) |
| 4 3 test caller | test_tlimit_signal / test_gate_stop_reuse_race / test_gate_readonly_receipt_race | PASS / all checks passed / all checks passed |

Cả 4 AC đạt. Không đổi code, chỉ thêm bằng chứng.
