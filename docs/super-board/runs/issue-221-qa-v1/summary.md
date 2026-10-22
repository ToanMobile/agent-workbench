# QA #221 v1 — merge driver cho ma trận hồi quy

- `bash universal-agent-devkit/tests/gates/test_matrix_merge_driver.sh` → exit 0, 7/7 ✔ (PASS).
- Đột biến (bỏ phần rule của nhánh `theirs` khỏi kết quả gộp) → test 1 và 2 ĐỎ (FAIL 2); đã khôi phục file.
- Gộp thật `origin/main` vào nhánh với driver: tự gộp sạch, 49 id test không trùng, có REG-DK-MATRIX-MERGE-01.
- Trước khi PR vào main, `.agents/devkit` (symlink về main) chưa có driver nên gộp vẫn conflict như cũ; chỉ đúng sau khi PR merge.
- Gate trên nhánh cũ: REJECT 47/48 vì nhánh tụt sau main (file của main), diff PR chỉ 5 file +204/-0.
