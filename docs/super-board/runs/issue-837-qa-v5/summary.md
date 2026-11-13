# QA #837 v5 — head 94b13b6b (rebuild lần 3, chuẩn hoá args một lần)

- Lệnh: `bash universal-agent-devkit/tests/gates/test_guard_remote_ref_forge.sh`
- Hook cũ (origin/main): rc=1, 35 dòng ✖ (ĐỎ). Hook PR: rc=0 `OK` (XANH).
- `test_guard_shell_norm.sh`: rc=0 ALL PASS.
- Dò tay qua `block-dangerous-git.sh` (lỗ audit T0366): `symbolic-ref refs/remotes/origin/main HEAD`, `Refs/...`, `symbolic-ref > -q ...`,
  `remote 2>/dev/null set-head origin feat`, `set-head origin -- -a`, `update-ref refs/Remotes/...` rc 2;
  `remote -v set-head origin --auto`, `set-head origin --auto`, fetch, pull, `symbolic-ref -q --short ... 2>/dev/null`, đọc trong `python3 -c` rc 0.
- Ngoài AC (đã ghi): `branch -r -d`, `remote remove|rename`, `push .`/`fetch .`.
