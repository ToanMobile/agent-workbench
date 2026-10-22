# QA #251 v2 — head 54e73808 (đã chứa origin/main)

Lệnh: `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief --diff origin/main`
Kết quả: exit 0, hồi quy 57/57, lớp tĩnh đạt.

Test bash của PR (cây sạch): `test_merge_gate_red_on_base.sh` (25 ca), `test_verify_cmd_same_as_gate.sh`,
cùng 16 test `test_merge_gate_*` / `test_merge_train` liên quan: đều PASS.

Mutation (khôi phục sau mỗi lần, cây sạch):
- R1: tắt `gate_masked_conditions_clean` (merge-gate.sh:707) → test ĐỎ. Bắt được.
- R2: tắt kiểm `post-fix-gate.py` (merge-gate.sh:706) → test vẫn xanh (mutant sống sót, xác nhận 2 lần).
  Lý do khả dĩ: wrapper vẫn bị R1 chặn (không có dòng `--json`). Vẫn fail-closed → Medium.

Test gaps (không viết, không chặn):
- Ca R2 chưa độc lập với R1: thêm ca wrapper có JSON sạch giả để chỉ R2 chặn.
- So suite theo id, chưa theo từng ca; lệnh chạy lại trên base không giữ lock/heartbeat (#146) — builder đã ghi là giới hạn biết trước.
