# QA #249 v1 (không có UI, không có ảnh)
- `bash tests/super-board/test_runner_claim_loop.sh` → exit 0, toàn bộ pass (có case #249: BASH_DEFAULT/MAX_TIMEOUT_MS >= 3600000).
- Đột biến: xoá dòng `export BASH_*_TIMEOUT_MS` → case #249 ĐỎ (`unset/unset`); khôi phục → XANH.
- `post-fix-gate.py --run-tests --full --diff origin/main --brief` sau khi merge origin/main → exit 0, 55/55.
- Lần gate đầu (exit 1) do nhánh chậm 3 commit so với main; đã merge main, không xung đột.
- AC3 (log 1 ngày sau không còn "timed out after 10m") chỉ đo được sau deploy.
