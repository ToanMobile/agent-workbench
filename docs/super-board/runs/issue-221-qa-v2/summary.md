# QA #221 v2 — merge driver ma trận hồi quy (rebuild 1)

- `bash universal-agent-devkit/tests/gates/test_matrix_merge_driver.sh` → exit 0, 9 kiểm tra (gồm test 7 so với origin/main).
- Đột biến (tắt bước đặt rule của main lên trước) → test 7 ĐỎ (FAIL 2); khôi phục file → XANH.
- Gộp thật origin/main (2 commit mới) qua driver: không conflict, 49 rule, 48 rule đầu giống hệt main (chỉ-thêm), 53 id test không trùng.
- Gate `post-fix-gate.py --run-tests --full --diff origin/main` → exit 0, 53/53 (lần 2 exit 4 UNTESTED do file đổi giữa lúc chạy, chạy lại exit 0).
- Lưu ý: chưa cài driver ở main (`agent-kit githooks install`) thì gộp không qua driver vẫn conflict như cũ.
