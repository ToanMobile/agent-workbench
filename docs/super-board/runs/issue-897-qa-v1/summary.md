# QA #897 v1 (PR #1096, head 9e6a4a2f)

- `npm test` (mcp-servers/cc-switcher-mcp): exit 0, 139 pass / 0 fail.
- RED: `tests/residual-c2.test.js` chạy với src/ của origin/main (bản sao trong /tmp): exit 1, 0 pass / 5 fail (R1, R2, symlink, findKnownRepo, sendMessage).
- GREEN: cùng file trên head PR: 5/5 pass.
- Gate: `post-fix-gate.py --run-tests --scoped --brief --json` qua super-board-qa-exit2.sh: `pass`. Head đã chứa origin/main (0 commit sau).
- Test gaps (Medium, không viết): `--state-dir` thiếu giá trị, stdout xả trước exit, repoPath symlink trỏ về `/` hoặc home chưa có test riêng.
