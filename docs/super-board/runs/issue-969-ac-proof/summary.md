# Bằng chứng AC — issue #969 (PR chứng minh sau PR #1113, merge 3a995cb7)

Gate kit trên origin/main đã chứa phần ghim Gradle (PR #1113). PR này không đổi code, chỉ ghi bằng chứng cho từng AC.

- AC2 — REG-GATE-118 chạy trên gate kit:
  oracle nguyên văn của GeelyEx2 (`tests/scripts/test_merge_gate_gradle_home.py`) chép sang cây tạm cùng `.claude/bin/super-board-merge-gate.sh` của kit, chạy
  `python3 test_merge_gate_gradle_home.py` → exit 0, `PASS: merge gate ghim GRADLE_USER_HOME + daemon, timeout vẫn 900`.
- AC3 — repo khác không đổi:
  `bash tests/super-board/test_merge_gate_gradle_env.sh` → exit 0, PASS, gồm ca "không Gradle: môi trường nguyên vẹn" và "timeout mặc định vẫn 900".
- AC1 — gỡ overlay GeelyEx2: CHƯA chứng minh. Gate cục bộ của GeelyEx2 vẫn mang `GRADLE_USER_HOME` và `-Dorg.gradle.daemon=true` (dòng 1441, 1443); việc gỡ cần sync kit sang repo GeelyEx2, nằm ngoài repo này.
