# QA #1228 · PR #1229 · head 1dc03d6 (round 1)

| AC | Kết quả | Bằng chứng |
|---|---|---|
| 1. `worktree add` không từ chối từ 5 GiB | ✅ | `DISK_MIN_GIB` mặc định 5.0; `test_worktree_cache_prune.sh` "tỉa rồi vẫn dưới sàn: exit 4" xanh (rc=0); `add` của chính QA tạo được worktree khi đĩa 15 GiB |
| 2. Test mới ĐỎ code cũ, XANH code mới | ✅ | code cũ (origin/main worktree.py): rc=1 `default floor=15.0, want 5.0`; code PR: rc=0 |
| 3. cache_prune xanh với ghim mới; 25/25 không đổi | ✅ | rc=0, dòng "mặc định: cảnh báo 25, sàn 5, tỉa 25 GiB" |

Security pass: diff chỉ đổi một hằng số + test, không có bề mặt tấn công. Không finding.

Gate `post-fix-gate --scoped`: exit 2, lớp tĩnh đạt; lý do duy nhất là test có sẵn bị sửa cần duyệt chéo.
Lưu ý: verdict audit của T0550 ghi "audit-agent.json 98/100" nhưng task ở `awaiting_dispatch`, không có file audit-agent.json
=> chưa có audit Antigravity thật; Reviewer cần chạy audit thật (pm_dispatch kind=audit) trước khi merge.
