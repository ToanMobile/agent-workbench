# QA #115 v1 — watchdog + runner, 5 điểm sau PR #114
Head thử: 055b09ae (base origin/main). Không có UI → không có ảnh (ảnh: không cần, thay đổi chỉ là script shell/python).
- `bash tests/super-board/test_runner_watchdog.sh` → exit 0, "all passed" (gồm 4 ca mới: stop không stop.sh riêng, NO_PROGRESS=abc, guard không rg, safe_path)
- `bash tests/super-board/test_watchdog_lock_atomic.sh` → PASS (8 check cùng khoá cũ, đúng 1 giữ khoá)
- RED trên watchdog cũ (origin/main): 7/8 lần ĐỎ ("2 of 8 checks hold the check lock"); bản mới 0/8 ĐỎ
- `post-fix-gate.py --run-tests --full --brief --diff origin/main --auto-approve-tests` → exit 0, hồi quy 42/42
- Test đã có bị sửa: test_runner_watchdog.sh chỉ thêm dòng (tự duyệt)
Khoảng trống (Medium, không chặn): test khoá nguyên tử dựa vào đua thời gian nên bản cũ ĐỎ 7/8 chứ không 8/8.
