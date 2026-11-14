# QA #1160 v2 — PR #1177, head a0364ffb (lượt rebuild #1)

- `bash tests/super-board/test_github_read*.sh` (10 file): exit 0 cả 10.
- RED: hai test mới (`closed_duplicate`, `diff_too_large`) exit 1 trên `super-board-github-read.py` của origin/main, exit 0 sau sửa.
- `git merge origin/main`: Already up to date.
- `post-fix-gate.py --run-tests --scoped --brief --json` qua `super-board-qa-exit2.sh`: `pass` (exit 0).
- CI `devkit-tests` ở lượt trước đỏ do `test_prompt_hook_gate_env` (CPU 154 ms > 150 trên runner), file không thuộc diff; lượt CI mới trên a0364ffb đang chạy.
- Test có sẵn không bị sửa. Ảnh: không cần.
