# QA #1160 v1 (PR #1172, head 4de4b0cc)

- 4 test mới (closed_duplicate, diff_too_large, red_on_base_null_matrix, scratch_config_node_modules): XANH trên head (rc=0 cả 4).
- Cùng 4 test trên bản `origin/main` cũ (git archive, thư mục tạm): ĐỎ (rc=1, 1, 1, 2).
- 8 test `test_github_read*.sh` có sẵn: XANH (rc=0).
- `diff` 3 file bin với OfficeReader main (github-read.py) và GeelyEx2 main (verify-flags.sh, scratch-config.sh): rỗng.
- Cổng: `post-fix-gate.py --run-tests --scoped --brief --json | super-board-qa-exit2.sh` in `pass`, rc=0.
- Không sửa test có sẵn. Log thô ở /tmp/qa-agent-workbench-1160-*.log.
