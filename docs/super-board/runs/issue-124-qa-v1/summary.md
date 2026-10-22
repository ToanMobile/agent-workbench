# QA #124 v1 — github-read ghi stdout bằng UTF-8 bytes

Nhánh `issue-124-github-read-stdout-utf8` @ `41c56628` (UI: không có thay đổi giao diện, không chụp ảnh).

| Lệnh | Kết quả |
|---|---|
| `bash tests/super-board/test_github_read_utf8_stdout.sh` | rc 0, 4/4 đạt |
| `bash tests/super-board/test_upstream_66_67.sh` | PASS |
| `bash tests/super-board/test_merge_policy_odd_newlines.sh` | PASS |
| `post-fix-gate.py --run-tests --full --diff origin/main --brief` | exit 0, 40/40 hồi quy |

Đối chứng ĐỎ (đột biến): chạy test mới với bản `github-read` của origin/main → rc 1, 3 lỗi:
- U+2028: `rc=64 'latin-1' codec can't encode character ' '`
- NEL: output không khớp byte
- NEL: `DROP TABLE lọt` (merge-policy ra `human: []`)
Khôi phục bản sửa → XANH 4/4.

Test gaps (not written): Medium/Low — đường `--kind json` chỉ ASCII (json.dumps mặc định ensure_ascii), stderr vẫn theo locale (chỉ thông báo, không vào policy).
