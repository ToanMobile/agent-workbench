# QA #1160 · PR #1177 · v1 · head 1d514c06 (base = origin/main 8fa63472, đã chứa)

| AC | Lệnh | Kết quả |
|---|---|---|
| 1. Hai test mới ĐỎ trên main cũ, XANH sau sửa | `bash tests/super-board/test_github_read_closed_duplicate.sh`; `..._diff_too_large.sh` (script main cũ + test mới) | main cũ: exit 1 cả hai (`✖ rejects DUPLICATE`; `ReadHalted ... HTTP 406`). Head: exit 0 cả hai |
| 2. 8 test `test_github_read*.sh` có sẵn XANH | chạy từng file `tests/super-board/test_github_read*.sh` | 10/10 exit 0 (8 có sẵn + 2 mới) |
| 3. `diff` với OfficeReader origin/main rỗng | `diff .claude/bin/super-board-github-read.py <OfficeReader origin/main>` | rỗng, exit 0 |
| 4. drift: `super-board-github-read.py` không còn trong changed | `super-board-drift.py --source . --target <OfficeReader>` | không có trong `changed` (còn 8 file khác, không thuộc thẻ) |

Security pass: `local_pr_diff` gọi git bằng danh sách đối số, sha kiểm `[0-9a-f]{40}` trước khi vào lệnh git, timeout 60/120 s, lỗi trả CompletedProcess non-zero (không nuốt lỗi). Không phát hiện lỗ hổng.
Ảnh: không cần (công cụ CLI, không lên màn hình).
