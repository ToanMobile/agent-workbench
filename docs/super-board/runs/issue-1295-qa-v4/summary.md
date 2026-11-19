# QA v4 — issue #1295 / PR #1297 (head 1e833b76, mã không đổi so với v3)

Lý do chạy lại: merge gate preflight ac-check từng từ chối vì khối sb:ac trống; Builder đã điền lại (rebuild-1).

- origin/main (3236abe9) đã là tổ tiên của head: merge main = "Already up to date".
- test_runner_self_reload_catchup_ff.sh (A/B/C/D/E): exit 0
- test_runner_self_reload.sh: exit 0
- test_runner_self_reload_absorbed.sh: exit 0
- test_runner_self_reload_absorbed_ff.sh: exit 0
- Không sửa test cũ. Security: diff chỉ là bash runner, không eval/curl/secret.
- Gate scoped: xem comment [qa] [report].
