# QA v4 — issue #969, PR #1113 @ 3282d375

- Lệnh: `bash tests/super-board/test_merge_gate_gradle_env.sh` → exit 0, PASS (kết quả cuối: không nhân đôi cờ daemon, không Gradle thì env nguyên vẹn, timeout 900, không --no-daemon).
- `bash -n .claude/bin/super-board-merge-gate.sh` → exit 0.
- origin/main là tổ tiên của head → exit 0.
- Gate: `post-fix-gate.py --run-tests --scoped --brief --json | super-board-qa-exit2.sh` → `pass` (exit 0).
- Không thay đổi code từ v3; không UI, không ảnh.
- Chưa làm: gỡ overlay GeelyEx2 (cần sync kit, ngoài PR).
