# QA v4 — issue #1273, PR #1279, head 3fe852d6
origin/main là tổ tiên của head (merge-base --is-ancestor exit 0).
- bash tests/super-board/test_risk_door_blast.sh: exit 0 (super-review/SKILL.md 19983 < 20000)
- bash tests/super-board/test_qa_exit2_edited_test.sh: exit 0
- post-fix-gate --run-tests --scoped: xem dòng kết quả trong comment [qa] [report]
Chưa kiểm: lượt gate-full đêm kế tiếp; suite agent-kit test thuộc #1275.
