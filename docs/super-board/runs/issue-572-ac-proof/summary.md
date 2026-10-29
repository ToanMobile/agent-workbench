# Proof #572 — tlimit.py kẹt vĩnh viễn khi SIGINT/TERM tới lúc Popen giữ `_waitpid_lock`

PR #580 đã sửa (`56ca38e3`). PR này chỉ chứng minh lại các AC trên `origin/main` @ `56ca38e3`. Không đổi code.

## ĐỎ → XANH
Lệnh: `bash universal-agent-devkit/tests/gates/test_tlimit_waitlock.sh`
- ĐỎ: `TLIMIT=<tlimit.py của 46559061, trước sửa>` → exit 1, `FAIL (3)`:
  - `✖ SIGINT in wait lock: tlimit still alive 10s after SIGINT (deadlock)`
  - `✖ SIGTERM in wait lock: tlimit still alive 10s after SIGTERM (deadlock)`
  - `✖ SIGINT, child ignores TERM: tlimit still alive 8s after SIGINT (deadlock)`
- XANH: cùng lệnh, `tlimit.py` trên main → exit 0, `PASS`:
  - `✔ SIGINT in wait lock: exit 130 in 0s` · `✔ ...grandchild stopped`
  - `✔ SIGTERM in wait lock: exit 143 in 0s` · `✔ ...grandchild stopped`
  - `✔ SIGINT, child ignores TERM: exit 130 in 2s` · `✔ ...grandchild stopped`

## Ba test gọi tlimit.py (chạy trên main)
- `tests/gates/test_tlimit_signal.sh` → `PASS`
- `tests/gates/test_gate_stop_reuse_race.sh` → `all checks passed`
- `tests/gates/test_gate_readonly_receipt_race.sh` → `all checks passed`
