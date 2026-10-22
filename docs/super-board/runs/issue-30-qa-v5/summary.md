# QA v5 — issue #30 (rebuild-4, head 9880df85)

Lệnh: `bash universal-agent-devkit/tests/verification/test_governance_cleanup_fold_intent.sh` → exit 0, ca (g) xanh.
`bash universal-agent-devkit/tests/installer/test_uninstall.sh` → exit 0, 24/24.

Đột biến R9 (bỏ tiền tố `folded-from:…:start` khỏi FOLD_RE, khôi phục bằng bản sao): test #30 đỏ 1 ca → khôi phục xanh.

AC1: bản sao thư mục audit-gate thật (`cp -Rp`, giữ mtime) 14244 KB → 3300 KB (du) sau
`devkit_clean --days=7 --apply --keep-state` (1291 mục); chạy lần 2: 0 mục, không đổi; 6 file *.state/*.json còn nguyên.
(Lưu ý đo: `cp -R` không giữ mtime nên mọi file thành "mới" và cho 8,3 MB — số đó không hợp lệ.)
AC2 + AC3: giữ nguyên, test xanh. R9 đạt: uninstall gỡ trọn cặp marker, không đưa marker vào file khôi phục.

Gate: `post-fix-gate --run-tests --full --diff origin/main` → exit 0, 42/42. Chưa chạy --apply trên thư mục thật.
