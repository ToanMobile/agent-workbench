# QA v4 — #31 (head 269d1811)

- Lệnh: `bash -n` + `bash <file>` cho 15 file `.sh` đổi trong PR (14 cũ + test_gate_sentinel.sh). Kết quả: 15/15 exit 0.
- R3: `DEVKIT_SLOT_PRIORITY=merge DEVKIT_SLOT_LOAD_WAIT_S=0 bash test_gate_sentinel.sh` → exit 0, "all passed" (biến rò không còn làm đỏ).
- R2 (index cả thư mục): `index_repository fast` trên `universal-agent-devkit/tests` → parse_unusable_count=0, nodes=5760, edges=13303; parse_partial=25 (ngoài phạm vi AC1 đã chốt = 12 file unusable).
- Ảnh: không cần (chỉ đổi test).
