---
name: worktree-sandbox
description: "Quản lý môi trường thử nghiệm song song (Parallel Worktree Sandboxes) trên macOS APFS: nhân bản CoW siêu tốc (<100ms, 0-byte đĩa), nạp .worktreeinclude, cách ly dependencies, so sánh diff trọng tài và tự động dọn dẹp sạch sẽ (auto-clear) ngay khi merge vào main để chống rác Git. Kích hoạt khi cần chạy A/B testing giữa các agent, thử nghiệm nhiều giải pháp song song, hoặc gõ /sandbox."
---

# Parallel APFS Worktree Sandbox

Kỹ năng điều phối môi trường phân nhánh song song cho nhiều AI Agent hoặc thử nghiệm nhiều giải pháp cạnh tranh mà không gây bẩn working directory chính và **tự động xóa sổ sạch sẽ sau khi merge**.

## 🚀 Cách Kích Hoạt

### 1. Dòng lệnh CLI trực tiếp:
```bash
# Tạo sandbox thử nghiệm
python3 universal-agent-devkit/scripts/worktree_sandbox.py create <name> [--base <branch>] [--port-offset 10]

# Liệt kê danh sách sandboxes đang chạy
python3 universal-agent-devkit/scripts/worktree_sandbox.py list

# So sánh diff giữa 2 sandboxes (A/B testing)
python3 universal-agent-devkit/scripts/worktree_sandbox.py compare <name_a> <name_b>

# Merge giải pháp thắng cuộc và TỰ ĐỘNG DỌN DẸP SẠCH TOÀN BỘ RÁC
python3 universal-agent-devkit/scripts/worktree_sandbox.py merge-winner <name> [--squash]

# Dọn dẹp thủ công toàn bộ bất kỳ lúc nào
python3 universal-agent-devkit/scripts/worktree_sandbox.py cleanup --all
```

### 2. Quy trình Trọng tài Tự động (Tournament Protocol):
1. **Khởi tạo 2 Sandbox**:
   - `worktree_sandbox.py create fix-approach-a --port-offset 10`
   - `worktree_sandbox.py create fix-approach-b --port-offset 20`
2. **Thực thi Song song**:
   - Agent 1 sửa trong `.sandboxes/fix-approach-a`.
   - Agent 2 sửa trong `.sandboxes/fix-approach-b`.
3. **Thẩm định & Chọn Winner**:
   - Chạy `post-fix-gate.py` trong từng sandbox.
   - Dùng `worktree_sandbox.py compare fix-approach-a fix-approach-b` để đối chiếu diff.
4. **Merge & Tự động Tiêu hủy**:
   - Chạy `worktree_sandbox.py merge-winner fix-approach-a`
   - Hệ thống tự động merge code vào nhánh chính, tự động gỡ bỏ worktree `fix-approach-a`, và prune `.git/worktrees/`. Sandbox khác (`fix-approach-b`) được GIỮ NGUYÊN; thêm `--clean-others` khi chắc chắn muốn xoá luôn các sandbox thua cuộc.
