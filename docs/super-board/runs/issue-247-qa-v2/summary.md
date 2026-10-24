# QA #247 vòng 2 (rebuild-1)
Head: gộp origin/main (e0ec6a41) vào 4cee7fae.
- test_gate_tree_store_reuse.sh: exit 0 (XANH; vòng 1 đã ĐỎ 5 ca trên gate của main)
- test_gate_sibling_receipt.sh: exit 0
- test_run_impacted_order.sh: exit 0 (R1 đã sửa: có dòng thời lượng)
- post-fix-gate --run-tests --full --brief: exit 0, 58/58
Chưa đo: AC thời gian QA→merge (cần số liệu sau merge). R3 (gọn from_store) là should-fix, không chặn.
