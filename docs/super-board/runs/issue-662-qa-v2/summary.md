# #662 · QA v2 — gate_full chống trùng thẻ (head 7b5684b)

Kết quả: ĐẠT 4/4 AC sau sửa review vòng 1.
- tests/gates/test_gate_full_nightly.sh: exit 0 (b9, b9b, b10, b10b, b11, b12, b13 XANH).
- Mutation: đổi `by_id = bool(SUITE_ID.match(first))` thành `by_id = True` thì b13 ĐỎ ("agent-kit test" nuốt thẻ thường); khôi phục thì XANH.
- Gate scoped 153/155: REG-SB-SETUP-BIN-01 và REG-SB-MERGE-TRAIN-01 đỏ, cùng hai suite đã đỏ trên origin/main ở v1, không do PR.
