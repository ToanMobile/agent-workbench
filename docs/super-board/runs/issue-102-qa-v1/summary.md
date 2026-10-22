# QA v1 — issue #102 (PR #186)

Head đã test: cf699ffb (nhánh issue-102-merge-gate-flags-in-right-command)

| AC | Bằng chứng | Kết quả |
|---|---|---|
| `cd . && …post-fix-gate.py --run-tests && true` nhận --diff/--force-full | test_merge_gate_verify_flags.sh ca 1 | ✅ |
| `bash -c '… post-fix-gate.py --run-tests'` nhận đủ hai cờ bên trong chuỗi | ca 2 | ✅ |
| lệnh một lệnh như cũ (cờ ở cuối) | ca 3, ca 4 (đã có --force-full chỉ thêm --diff), ca 6 (token giả để nguyên) | ✅ |

Lệnh: `bash tests/super-board/test_merge_gate_verify_flags.sh` → thoát 0, 6/6 ✔
Test láng giềng (load_wait, readiness_tokens, timeout_retry, merge_call_failed, verify_log_outside) → đều thoát 0.

Đột biến (không commit): đổi nhánh chèn thành nối cờ vào cuối lệnh → 4/6 ca ĐỎ (ca 1, 2, 4, 5);
ca 3 và ca 6 vẫn xanh vì hành vi cũ của chúng không đổi. Khôi phục → 6/6 xanh.

DevKit gate: `post-fix-gate.py --run-tests --full --diff origin/main --brief --auto-approve-tests`
→ exit 0, hồi quy 44/44. Lần đầu exit 2 vì test_merge_gate_load_wait.sh (ca 16) bị sửa;
đã xem diff: chỉ đổi comment và chuỗi mong đợi theo định dạng lệnh mới, tự duyệt.

Ảnh: không cần — đổi script shell của merge gate, không có giao diện.

Test gaps (not written, Medium/Low):
- cả hai cờ đã có sẵn trong lệnh (không chèn gì): chưa có ca riêng.
- nhiều verify_commands trong một config: chưa có ca riêng (vòng lặp độc lập từng lệnh).
