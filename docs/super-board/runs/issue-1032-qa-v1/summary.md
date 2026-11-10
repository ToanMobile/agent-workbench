# QA #1032 v1 — PR #1077 (head a0742a16)

Lệnh: `bash tests/super-board/test_runner_claim_loop.sh` — exit 0, "all passed".
- Test 6d: 5 assert XANH trên PR.
- Cùng test chạy với `super-board-run.sh` của origin/main: ĐỎ 4 assert (#80 qa-fail, #82 review→Ready, #83 build→QA, #84 build→Review); #81 (thẻ qa còn ở Ready) vẫn được đếm đúng.

Gate: `post-fix-gate.py --run-tests --scoped --brief --json` qua `super-board-qa-exit2.sh` → `pass` (merge origin/main: already up to date).
Security pass: diff chỉ là nhánh `case` trong runner, không có input không tin cậy, không secret.
Không có UI → không có ảnh.
