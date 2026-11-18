# QA #1160 v3 — PR #1172, head 25453eda (sau khi gộp origin/main)

- `bash tests/super-board/test_github_read*.sh` (11 file) + `test_merge_gate_red_on_base_null_matrix.sh` + `test_scratch_config_node_modules.sh`: exit 0 cả 13.
- RED: hai test mới exit 1 và exit 2 trên `super-board-verify-flags.sh` / `super-board-scratch-config.sh` của origin/main; exit 0 sau sửa.
- `post-fix-gate.py --run-tests --scoped --brief`: PASS, hồi quy 3/3, biên nhận scoped đã ghi.
- Hai bản vá github-read đã vào main qua #1177; nhánh lấy bản main, diff so với main còn 4 file.
- Test có sẵn không bị sửa. Ảnh: không cần (script runner và test).
