# QA #451 v1 (PR #512)
- AC1: `bash tests/super-board/test_size_exclude_evidence.sh` → exit 0, mọi ca ✔ (config fixture auto_max_lines 400).
- AC2: bỏ `docs/super-board/runs/**/*` khỏi size_exclude → exit 1, 2 ca ✖ (evidence bị tính vào cỡ PR, manifest bị tính). Đã khôi phục config, cây sạch.
- Test-gap: diff chỉ 1 file test; không có mã app đổi. Ảnh: không cần (không UI).
