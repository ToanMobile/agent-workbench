# QA v2 · #1160 · PR #1172 @ b1afe912 (rebuild #1)

- Lệnh: `bash tests/super-board/<file>` cho 10 file test_github_read*.sh, 2 file test_scratch_config*.sh, test_merge_gate_red_on_base_null_matrix.sh → tất cả exit 0.
- `bash universal-agent-devkit/tests/worktree_git/test_agent_kit_integrate.sh` (I13 đỏ ở merge-queue) → ALL OK.
- Không sửa test có sẵn (diff chỉ thêm 4 test mới).
- github-read.py khớp OfficeReader main (0 dòng lệch); verify-flags.sh khớp GeelyEx2 main (0).
- scratch-config.sh lệch GeelyEx2 2 dòng: chỉ câu comment đổi để I13 xanh, logic giống.
- Ảnh: không cần (tooling).
