---
name: sandbox
description: "Điều phối Worktree Sandbox song song (APFS CoW, .worktreeinclude, tự động xóa sạch sau khi merge vào main). Dùng khi cần thử nghiệm nhiều phương án song song, A/B testing giữa các agent, hoặc gõ /sandbox."
---

# /sandbox — Parallel Worktree Sandbox Manager

Sử dụng lệnh này để tạo và điều phối các môi trường song song (Parallel Worktrees) với tốc độ tức thì qua APFS Copy-on-Write và **tự động xóa sổ sạch sẽ sau khi merge**.

## Cú pháp nhanh:

```bash
# 1. Tạo sandbox
python3 universal-agent-devkit/scripts/worktree_sandbox.py create <tên>

# 2. Xem danh sách
python3 universal-agent-devkit/scripts/worktree_sandbox.py list

# 3. So sánh 2 phương án
python3 universal-agent-devkit/scripts/worktree_sandbox.py compare <a > <b>

# 4. Merge giải pháp tốt nhất & TỰ ĐỘNG DỌN SẠCH RÁC
python3 universal-agent-devkit/scripts/worktree_sandbox.py merge-winner <tên>

# 5. Dọn dẹp thủ công
python3 universal-agent-devkit/scripts/worktree_sandbox.py cleanup --all
```
