# QA v5 · issue #17 · PR #140

Lệnh: `bash universal-agent-devkit/tests/context_memory/test_session_lock*.sh` (10 suite) — exit 0 cả 10.
Gate: `post-fix-gate.py --run-tests --full --brief --diff origin/main` — exit 0, 41/41.

- AC1 PASS: `holder_pid` bỏ qua cha `sh` bằng `ps -o ppid=,comm=` khi không có /proc (test 4).
- AC2 PASS: `_ps` ghim `TZ=UTC LC_ALL=C`; `pid_start` giống nhau ở TZ UTC và Asia/Tokyo, PID sống không bị coi là tái cấp (test 5).
- Mutant: bỏ ghim TZ trong bản sao → test 5 ĐỎ (`16:49:05` ≠ `01:49:05`); bản thật XANH.
