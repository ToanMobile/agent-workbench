# #745 · chứng minh 3 AC trên origin/main d74d538e

Bản bump đã vào main qua PR #1080 (merge d74d538e). PR này chỉ thêm bằng chứng cho AC còn thiếu (T0054).

## AC1 · pin phiên bản trên main
- Lệnh: `git show origin/main:.mcp.json | grep context7-mcp` và `git show origin/main:mcp_config.json | grep -E "context7-mcp|agentmemory@"`
```
        "@upstash/context7-mcp@4.4.4"
        "@upstash/context7-mcp@4.4.4"
        "@agentmemory/agentmemory@0.9.31",
```

## AC2 · hai MCP server khởi động
- Bằng chứng QA ở PR #1080 (head 372fec49): `context7-mcp@4.4.4 --help` chạy được; `agentmemory@0.9.31 mcp` trả `initialize` OK (serverInfo 0.9.31).

## AC3 · stash 625d6d6d đã drop
- Lệnh: `git stash list | grep -c deps-context7-agentmemory`
- Kết quả: 0 (không còn mục nào theo message `deps-context7-agentmemory`).
- Commit `625d6d6d` vẫn tồn tại như object (`git cat-file -t 625d6d6d` = commit), có thể khôi phục nếu cần.
