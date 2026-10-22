# QA #110 — merge train (v1)

Lệnh: `bash tests/super-board/test_merge_train.sh` → exit 0 (13 ca ✔, 0 ✖)
Gate: `post-fix-gate.py --run-tests --brief --diff origin/main` → exit 0, hồi quy 8/8

| AC | Bằng chứng |
|---|---|
| 3 PR cùng lúc: 1 lần verify, cả 3 merge | ca 1: verify=1, merged `1 2 3`, 3 file có trên origin/main |
| 1 PR đỏ: chia đôi tìm ra, 2 PR còn lại merge | ca 2: exit 11, `train-red: 5`, merged `4 6`, file `bad` không lên origin |
| 1 PR: chạy như hiện tại | ca 3: merge qua gate thường, verify=1, không có dòng train |
| gh giả, ĐỎ trước XANH sau | builder: script chưa có → đỏ; có script → xanh |

QA thêm:
- Khoảng trống High: biên nhận sai cây chưa được test. Thêm ca 4 (gate + `--train-receipt` sai cây → vẫn verify, verify=1).
- Đột biến `TRAIN_PROVED=1` trong gate: ca 3 và ca 4 đỏ (verify chạy 0 lần); khôi phục → xanh.
- PR #182 bị CONFLICTING với main ở `.agents/regression_matrix.active.json`: merge origin/main vào nhánh, giữ cả hai rule, đặt REG-SB-MERGE-TRAIN-01 ở cuối ma trận (gate chỉ tin ma trận thêm ở cuối).

Test gap chưa viết (Medium/Low): PR conflict trong chuỗi (exit 5); gate bị chặn giữa đợt khiến PR sau verify lại.
