# QA #1199 v1
- Test: bash tests/super-board/test_qa_report_cross_repo_ac.sh
- Base (origin/main qa-report.py): ca 1 ĐỎ (FAILS=1), ca 2, 3 XANH
- Head PR #1203: 3/3 XANH, exit 0 (PASS)
- Gate: post-fix-gate.py --run-tests --scoped --brief --json qua qa-exit2.sh: `pass` (exit 0), sau merge origin/main (already up to date)
- Lưu ý: bản chép script base ra /tmp lỗi giả (thiếu super-board-decision.py), đã chạy lại cạnh file thật.
