# QA #837 v6 — head 11e582f0 (chỉ rebase, chưa sửa code) — FAIL

- `test_guard_remote_ref_forge.sh`: rc=0 (OK). `test_guard_shell_norm.sh`: rc=0 (ALL PASS).
- Dò tay qua hook thật (`guard_shell_norm_lib.sh check 2 git ...`), mong rc 2, thực tế rc 0:
  - `git 2>/dev/null update-ref refs/remotes/origin/main HEAD`
  - `git >/dev/null remote set-head origin feat`
  - `git -C . 2>/dev/null update-ref refs/remotes/origin/main HEAD`
- Đã chặn đúng (rc 2): `symbolic-ref ... head`, `... ORIG_HEAD`, `update-ref -m git refs/remotes/...`.
- Kết luận: blocker 1 của audit T0369 (`analyse_simple` chưa `drop_redirects`) còn nguyên; AC1 chưa đạt vì redirect đặt trước subcommand vẫn ghi được refs/remotes/*.
- Cần sửa: chuẩn hoá args (bỏ redirect) một lần trước khi tìm subcommand; thêm 3 ca trên vào test_guard_remote_ref_forge.sh.
