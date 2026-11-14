# QA #1175 v4 — head 722e6c84 (đã gồm origin/main d8452aa2)
- AC1: `bash tests/super-board/test_github_read_malformed_halt.sh` ĐỎ với script của main (rc=1, có dòng FAIL), XANH với script của PR (rc=0).
- AC2: `bash tests/super-board/test_github_read_foreign_halt.sh` XANH (PASS), lệnh đọc hợp lệ không nêu repo vẫn halt.
- Gate: `post-fix-gate.py --run-tests --scoped --brief --json` qua `super-board-qa-exit2.sh` = `pass` (rc=0), không sửa test cũ.
- AC3: đo sau merge (orchestrator đã đăng [decision] trên issue, merge gate #1181 nhận).
