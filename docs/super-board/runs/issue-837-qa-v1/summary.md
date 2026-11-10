# QA #837 / PR #1090 (v1)
- Base: origin/main đã merge vào đầu PR, sạch.
- AC1 ĐỎ: hook cũ (origin/main) chạy tests/gates/test_guard_remote_ref_forge.sh → 12 ca ✖. XANH: hook của PR → OK, rc=0.
- AC2: fetch, pull, `remote set-head --auto/-a`, lệnh đọc ref (rev-parse, log, symbolic-ref) → rc 0 (không bị chặn).
- Gate: post-fix-gate --run-tests --scoped qua super-board-qa-exit2.sh → `review` (tests/impact_map.txt, file test đã có, bị sửa).
- Ngoài phạm vi (có từ trước, PR không thêm): `git push . HEAD:refs/remotes/origin/main` và `git fetch . HEAD:refs/remotes/origin/main` vẫn rc 0 qua hook.
- Chạy lại 10/11: RED 12 ca ✖ (hook cũ, rc=1) → GREEN rc=0 (hook PR). Gate scoped sau merge origin/main: `review` (sửa test đã có: impact_map.txt, test_durations.txt).
