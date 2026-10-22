# QA v2 — #229 runner tự nạp lại code (PR #241)

- Nhánh: issue-229-runner-self-reload, đã gộp origin/main mới nhất (merge sạch, không xung đột).
- `bash tests/super-board/test_runner_self_reload.sh` → exit 0, 10/10 PASS.
- Đột biến: bỏ guard `ACTIVE_WORKERS` trong `self_reload_tick` → test ĐỎ (`✖ busy: exec=1`, exit 1); khôi phục → XANH (exit 0).
- `post-fix-gate.py --run-tests --full --diff origin/main --brief` → exit 0, hồi quy 58/58 (REG-SB-SELF-RELOAD-01 nối cuối ma trận).
- AC1 ✅ test RED→GREEN, rule cuối ma trận · AC2 ✅ qua test mô phỏng tick (chưa kiểm trên runner thật) · AC3 ✅ main lệch → notify một lần, không exec · AC4 ✅ gate exit 0, PR +170 dòng (<400).
