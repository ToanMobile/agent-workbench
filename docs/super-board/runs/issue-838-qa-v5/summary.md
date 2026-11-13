# QA #838 · vòng 5 · PR #1092

Head kiểm: `17caefd3` (đã chứa origin/main, `merge-base --is-ancestor` = 0).

| Mục | Kết quả |
|---|---|
| AC1 `test_gate_since_landed_base.sh` (gỡ assertion main ⇒ exit 2, liệt kê test) | PASS |
| AC2 control gộp thuần exit 0 + `test_gate_since_trunk_merge.sh` | PASS |
| #842 `test_outcome_report_labels.sh` | PASS |
| Hồi quy: `test_gate_since_test_edit`, `test_gate_since_new_test`, `test_gate_renamed_test_edit`, `test_outcome_table_rows` | PASS |
| Gate scoped `--run-tests --scoped --brief --json` ⇒ `qa-exit2` | `pass` (exit 0) |
| Biên nhận task (head `17caefd3`) | `6d49f4cbc139db7ccd477a26` |
| Bảo mật (diff 2 file DevKit + 2 test) | Không thấy lỗ hổng: lệnh git dùng danh sách đối số, không qua shell |

Không có ảnh (không phải UI).
