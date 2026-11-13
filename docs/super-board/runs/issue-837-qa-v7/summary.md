# QA #837 v7 (PR #1090, head 89feab82)

- Lệnh: `bash universal-agent-devkit/tests/gates/test_guard_remote_ref_forge.sh`
  - hook cũ (origin/main, qua GG_HOOK): rc=1, 38 dòng ✖ (ĐỎ)
  - hook PR: rc=0, `OK` (XANH)
- `test_guard_shell_norm.sh`: rc=0, ALL PASS
- Dò tay qua hook thật, rc 2 đúng: `git 2>/dev/null update-ref refs/remotes/...`, `git >/dev/null remote set-head origin feat`, `git -C . 2>/dev/null update-ref ...`, `-c`, `env git`, `--git-dir`, `update-ref -d`, `--stdin`
- Dò tay rc 0 đúng: fetch, pull, `remote set-head origin --auto`, `symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null`, `git 2>/dev/null fetch/rev-parse`
- Lỗ ngoài AC (Medium, không viết test): `git 2>&1 update-ref refs/remotes/origin/main HEAD` rc 0 (fd-dup giữa dòng, shell_norm.join_fd_dup dùng chung; cũng lọt với reset --hard cũ); `git push . HEAD:refs/remotes/origin/main` và `git fetch . HEAD:refs/remotes/origin/main` rc 0.
