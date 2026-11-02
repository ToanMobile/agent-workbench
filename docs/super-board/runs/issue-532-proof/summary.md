# Bằng chứng #532 — stale_rerun giết nhóm suite con khi INT/TERM

Base: `origin/main` @ 7fda00d1 (đã gồm PR #550, merge fb59d91).
Lệnh: `bash universal-agent-devkit/tests/verification/test_stale_rerun.sh` → exit 0 (✅ all passed)

- AC1 ✔ SIGINT vào stale_rerun giết suite con (không còn PID sau khi cha thoát)
- AC2 ✔ SIGTERM vào stale_rerun giết suite con (không còn PID sau khi cha thoát)
- AC3 ✔ quá giờ vẫn SIGKILL → TIMEOUT

Mã: `_execute` trong `stale_rerun.py` bắt INT/TERM → `_kill_group` (SIGKILL nhóm) → `SystemExit(128+signum)`;
đường quá giờ vẫn gọi `_kill_group` như cũ.
