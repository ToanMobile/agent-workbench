# QA #421 v1 — worktree remove: commit chỉ còn trong reflog, trunk đã có patch

Head: sau merge origin/main (15aaaf4a) vào nhánh issue-421-remove-reflog-squash.
Xung đột `cmd_remove` giải: giữ nhánh `merged`/`else` (_holder / _live_checkout_lock) của main + truyền `waived` của #421.

- test_worktree_remove_reflog_squash.sh (REG-DK-REMOVE-REFLOG-SQUASH-01): ALL PASS (r1–r5), exit 0
- Liền kề exit 0: remove, remove_late_holder, remove_safety, discard_squash, remove_branch, remove_origin_safe, remove_essentials_block
- post-fix-gate --run-tests --brief: exit 0, 13/13 (lần 1 REG-DK-ALL-01 TIMEOUT 900s do tải máy 102; chạy lại tải 20 → PASS)
- Ảnh: không cần — thay đổi backend/script, không lên màn hình.
- Test gaps (không viết): chuỗi squash sửa file có `merge=` driver (matrix, test_durations) vẫn UNREACHABLE (fail-closed) — ngoài AC, nên mở thẻ riêng.
