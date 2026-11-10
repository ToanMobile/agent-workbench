# QA #837 v3 — head 8a9c2a8c (rebuild sau audit T0308)

- Lệnh: `bash universal-agent-devkit/tests/gates/test_guard_remote_ref_forge.sh`
- Hook cũ (origin/main): rc=1, 20 ca ✖ (ĐỎ). Hook PR: rc=0 `OK` (XANH).
- `test_guard_shell_norm.sh`: ALL PASS.
- 3 blocker audit đã đóng: lệnh đọc `symbolic-ref ... 2>/dev/null` rc 0; bypass `-m`/`-d`/`--del`/`--d`/symref trung gian rc 2;
  `set-head -a --no-auto`, `-a -d`, `--auto --delete` rc 2; `--au`/`--aut`/`--auto`/`-a` rc 0.
- Dò thêm tay: `symbolic-ref HEAD refs/remotes/...`, `--recurse`/`--no-recurse` ghi refs/remotes rc 2; fetch, pull rc 0.
- Ngoài AC (đã ghi): `git branch -r -d`, `git remote remove|rename`, `git push .`/`fetch .` ghi refs/remotes.
