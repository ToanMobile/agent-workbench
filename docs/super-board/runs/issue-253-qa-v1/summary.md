# QA #253 v1
- `bash tests/super-board/test_runner_preflight_swept.sh` → exit 0, ALL PASS
- `python3 tests/super-board/test_blocked_by_open_only.py` → exit 0, 9 ca PASS
- RED: cùng test chạy trên code origin/main → 11 ca shell FAIL, thiếu super-board-blocked-by.py
- Gate: `post-fix-gate.py --run-tests --full --diff origin/main` → exit 0, 54/54 (đầu 1dea34ab, sau merge origin/main)
- Ảnh: không cần — không đụng UI
