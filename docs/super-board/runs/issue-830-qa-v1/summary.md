# QA #830 (PR #1076) v1 — PASS
- Head: e9443e6e (đã merge origin/main f74556aa, đã up to date)
- Test mới `tests/gates/test_hardware_issue830.sh`: GREEN rc 0 trên head; RED rc 1 (8 dòng fail) trên hook cũ f74556aa.
- 13 test hook liên quan (shell_norm, monotonic, empty_serial, issue427, rm_*, backlog427, round3_427, data_local_tmp, find_*, cwd_unknown, unglob_quoted): rc 0 cả 13.
- `post-fix-gate --run-tests --scoped`: exit 0, qa-exit2 = pass.
- Security pass: diff 2 file, không có eval/exec/subprocess/IO mới.
- Ảnh: không cần (hook dòng lệnh).
