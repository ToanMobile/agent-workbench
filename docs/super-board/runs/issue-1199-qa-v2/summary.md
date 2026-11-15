# QA #1199 v2 (rebuild 1, body PR có sb:ac)
- Test: bash tests/super-board/test_qa_report_cross_repo_ac.sh -> exit 0, PASS 3/3
- Base ĐỎ ca 1: xem v1/summary.md (tự chạy, v1)
- Gate: post-fix-gate.py --run-tests --scoped --brief --json qua qa-exit2.sh: `pass`, sau merge origin/main
