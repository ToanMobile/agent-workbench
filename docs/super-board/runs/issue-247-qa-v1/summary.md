# QA #247 v1 — dùng lại biên nhận PASS theo cây

- Cây test: head PR gộp origin/main (a25eec4b), worktree issue-247-qa.
- `bash universal-agent-devkit/tests/gates/test_gate_tree_store_reuse.sh`: exit 0, XANH 10 nhóm ca.
- Cùng test với `post-fix-gate.py` của origin/main: ĐỎ 5 ca (1, 2, 2-tested_at, 7, 8).
- `bash universal-agent-devkit/tests/gates/test_gate_sibling_receipt.sh`: exit 0.
- `post-fix-gate.py --run-tests --full --brief --diff origin/main --auto-approve-tests`: exit 0, hồi quy 58/58, lớp tĩnh đạt.
- Test sửa: test_gate_sibling_receipt.sh (chỉ thêm xoá store theo cây ở setup), impact_map.txt; agent tự duyệt.
- Chưa đo được: AC "thời gian QA tới merge giảm" — cần số liệu vận hành sau merge.
- Log đầy đủ: $(git rev-parse --git-common-dir)/worktrees/issue-247-qa/postfix-gate/last_output.log
