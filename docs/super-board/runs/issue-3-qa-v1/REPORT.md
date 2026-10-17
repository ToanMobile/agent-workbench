# QA issue #3 — v1 (PR #34 @ ccb9bdc)

| Kiểm tra | Kết quả |
|---|---|
| `test_nightly.sh` trên nhánh | GREEN (ca trunk-mode: suite chạy, không skip) |
| `test_red_proof.sh` trên nhánh | GREEN (record revert không có trường `patch`) |
| Đột biến: trả `nightly.py` + `red_proof.py` về `origin/main` | RED cả hai: `trunk: skip: trunk mode: main chỉ nhận merge`; `revert mode leaked a patch field: .agents/local/red-patches/...patch` |
| Khôi phục code nhánh | cây sạch |

Nguyên nhân gốc AC2: `patch` là tham số của `prove()` (red_proof.py:569); dòng 673 gán lại nên `if patch:` (dòng 748) đúng và ghi trường `patch`.
Ghi chú: issue nhắc cờ `--detached` cho red_proof; diff không thêm — không thuộc AC, không chặn.
