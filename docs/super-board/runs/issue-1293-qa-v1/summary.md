# QA #1293 (PR #1294) — v1

Đầu PR a0d452d4, đã gộp origin/main (Already up to date).

| AC | Kết quả |
|---|---|
| 1. matrix_problem null = sạch | test_merge_gate_red_on_base_null_matrix.sh: ĐỎ trên script của main (exit 1, Ca 1 thất bại), XANH trên PR (exit 0) |
| 2. scratch có node_modules | test_scratch_config_node_modules.sh: ĐỎ trên main (exit 2, node_modules bị thay), XANH trên PR (exit 0) |
| 3. test cũ còn xanh | red_on_base, red_on_base_kit_tests, verify_flags, scratch_config, scratch_clean, scratch_agents_clean, ff, verified_tree: 8/8 exit 0 |

Cách tạo ĐỎ: ghi đè 2 script bằng bản origin/main, chạy 2 test mới, rồi khôi phục bản PR (cây sạch).
Ảnh: không cần, chỉ đổi script runner và test.
