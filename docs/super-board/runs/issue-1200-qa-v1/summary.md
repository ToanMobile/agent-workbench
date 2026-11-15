# QA #1200 v1 (PR #1204, head 1dc7d01)
- test_edited_approval_survives_base_move.sh: exit 0, H1-H5 xanh (ALL OK)
- Trước sửa (3 script lấy từ origin/main): exit 1, H1 và H2 ĐỎ, H3-H5 xanh (2 FAILED)
- test_merge_gate_pm_edited_base_moved.sh: exit 0, ALL OK (G3 bỏ, chuyển sang H3/H4)
- post-fix-gate --run-tests --scoped: qa-exit2 = review (test cũ bị sửa, chờ duyệt chéo)
- main đã gộp vào QA worktree: Already up to date
- Security pass: diff shell, python -I, argv không nội suy shell; path tuyệt đối/".." bị từ chối; fail closed
