# Thẻ #571 — bằng chứng AC (PR #587 đã merge: 849799ed)

Test: `bash universal-agent-devkit/tests/gates/test_worktree_merge_gate_open_pr.sh`

## XANH trên origin/main @ 3bc66f3f (hook đã sửa) — rc 0
- ✔ nhánh đã publish có PR mở: Stop không bị giữ, ghi chú nêu #569
- ✔ nhánh đã publish không có PR mở: vẫn chặn như cũ
- ✔ gh lỗi: vẫn chặn (fail closed)
- ✔ gh treo: vẫn chặn (fail closed)
- ✔ PR mở + worktree bẩn: vẫn chặn
- ✔ PR mở + commit chưa push: vẫn chặn
- ✔ 5 worktree + gh treo: vẫn chặn (ngân sách chung, không vượt báo động)

## ĐỎ với hook trước sửa (849799ed^) — rc 1
- ✖ open PR held the Stop (rc 2) — đúng ca AC1
- 6 ca còn lại ✔ (chúng mô tả hành vi chặn giữ nguyên)

Cách chạy ĐỎ: chép hook cũ (`git show 849799ed^:universal-agent-devkit/hooks/worktree_merge_gate.sh`)
vào bộ kit tạm (symlink phần còn lại), trỏ biến HOOK của test vào đó.
