# QA #321 v2 — PR #342 head b164caf5 + origin/main (merge 6f51a40b)

- Gate: `post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests --diff origin/main` → exit 0, 91/91 (cùng lệnh merge gate, in bởi `super-board-verify-cmd.sh`).
- #305 `test_create_task_batch.sh` → "all passed" (nhóm 29-32 còn đủ sau rebase).
- #261 `tests/super-board/test_merge_policy_money_keywords.sh` → PASS (có đối chứng âm).
- #236 `super-board-approve-head.test.js` + `super-board-approve.test.js` → 7/7 PASS.
- ĐỎ→XANH: giữ kết quả v1 (ĐỎ với mã của main); head chỉ đổi do gộp main, không chạy lại ĐỎ.
- Khoảng trống (Medium, không chặn): #236 chưa có test "không lặp thông báo merge".
- Không có thay đổi giao diện nên không có ảnh. Log thô không commit.
