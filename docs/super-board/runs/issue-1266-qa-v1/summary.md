# QA #1266 (PR #1272) @ 5c7f5938 — head đã chứa origin/main
Lệnh: bash tests/super-board/test_<tên>.sh cho 14 test (3 test đỏ + 11 test ghim skill)
Kết quả: 14/14 rc=0 (tự chạy)
- risk_door_blast: super-review/SKILL.md 19944 < 20000
- qa_exit2_edited_test: run.md, worker-preamble, bản sinh khớp
- queue_approval_no_edited_tests_line: D4, D5, D6 ok
Nguyên nhân mất chuỗi D5: commit 2b5d3825 (#1242)
Đối chiếu luật: mục "When to use" của super-review chuyển nguyên văn sang references/when-to-use.md, không bỏ luật nào.
