# QA #1266 (PR #1272) @ d0113927 — head đã chứa origin/main
Lệnh: bash tests/super-board/test_<tên>.sh cho 14 test; post-fix-gate --run-tests --scoped
Kết quả: 14/14 rc=0, gate scoped exit 0 (qa-exit2: pass) (tự chạy)
- risk_door_blast: super-review/SKILL.md 19399 < 20000
- qa_exit2_edited_test, queue_approval_no_edited_tests_line (D4, D5, D6): ok
- Luật: mục "When to use" chuyển sang references/when-to-use.md, không bỏ luật (đối chiếu diff)
- Bảo mật: diff chỉ text hướng dẫn, không code, không có phát hiện
