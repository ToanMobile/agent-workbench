# #1273 — bằng chứng trên origin/main @ 7fb2e5a3

Chạy trong worktree sạch tại origin/main (đã chứa PR #1279):

- `bash tests/super-board/test_risk_door_blast.sh` → exit 0 (REG-SB-RISK-DOOR-BLAST-549-01; super-review/SKILL.md 19983 < 20000) (tự chạy)
- `bash tests/super-board/test_qa_exit2_edited_test.sh` → exit 0 (REG-SB-QA-EXIT2-643-01) (tự chạy)

Chưa kiểm: lượt `gate_full.py run` đêm kế tiếp (mất ~300 phút, chỉ lịch đêm chạy); suite `agent-kit test` thuộc #1275.
