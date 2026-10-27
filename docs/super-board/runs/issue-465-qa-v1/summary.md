# QA #465 v1 — PASS
- Lệnh: `bash tests/super-board/test_runner_claim_loop.sh`
- Nhánh fix (đã merge origin/main): exit 0, all passed (test 6c: 3 ✔)
- run.sh gốc origin/main: exit 1, 2 failed (ĐỎ), fix phân biệt được
- `post-fix-gate.py --run-tests --brief` (impacted): exit 0, 30/30 hồi quy
- Thẻ còn ở QA vẫn tính chết sớm (không nới quá mức)
