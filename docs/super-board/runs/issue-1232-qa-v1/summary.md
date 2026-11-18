# QA #1232 v1
- Lệnh: `bash tests/super-board/test_sweep_closed_no_merged_pr_1232.sh`
- XANH (head PR): exit 0, 9/9 ✔ (A dọn, B giữ file thật, C1-C4 không gỡ, D PR merged riêng vẫn dọn).
- ĐỎ (script cũ origin/main, CLEAN=...): exit 1, 4 ✖ (d0, A, B, D).
- Test hiện có không sửa: `test_post_merge_clean.sh` exit 0, `test_post_merge_clean_scratch.sh` exit 0.
- Log thô: /tmp/qa-agent-workbench-1232-*.log (không commit).
