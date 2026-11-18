# #1273 QA v6 — PR #1289 (chỉ thêm docs bằng chứng)

Base: origin/main @ 7fb2e5a3 đã là tổ tiên của head (merge: Already up to date).

- `bash tests/super-board/test_risk_door_blast.sh` → exit 0 (REG-SB-RISK-DOOR-BLAST-549-01; super-review/SKILL.md 19983 < 20000) (tự chạy)
- `bash tests/super-board/test_qa_exit2_edited_test.sh` → exit 0 (REG-SB-QA-EXIT2-643-01) (tự chạy)
- Khối sb:ac của PR có đủ 4 dòng AC; AC1, AC3 tick kèm PR #1279; AC2, AC4 để trống kèm lý do.

Chưa kiểm: lượt `gate_full.py run` đêm kế tiếp (AC2, AC4); suite `agent-kit test` thuộc #1275.
