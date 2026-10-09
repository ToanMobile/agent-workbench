# agent-workbench

Monorepo gom các công cụ MCP / agent của ToanMobile. Mỗi thư mục là một dự án độc lập, giữ nguyên lịch sử git
(nhập bằng `git subtree`), có README, test và tài liệu riêng.

| Thư mục | Là gì | Ngôn ngữ |
| --- | --- | --- |
| [`mcp-servers/play-store-mcp/`](mcp-servers/play-store-mcp/) | MCP server làm việc với Google Play Console (APK, release, review…) | Python (uv) |
| [`mcp-servers/antigravity-pm-mcp/`](mcp-servers/antigravity-pm-mcp/) | Claude Code làm PM điều phối Google Antigravity: giao task, phản biện plan, audit/review, cổng nghiệm thu cưỡng chế | Node ESM |
| [`universal-agent-devkit/`](universal-agent-devkit/) | Bộ chuẩn hóa kỹ thuật & chất lượng Zero-Defect: 28 skills, 8 domain profiles (Android, iOS, Web, Backend, Automotive, Game, Voice, Universal), bảo vệ xung đột X_old, Post-Fix Gate cho 4 nền tảng AI Agent (Claude Code, OpenAI Codex, Antigravity, Cursor) | Shell + Python + Node |

## Lịch sử

- Repo GitHub này trước là `play-store-mcp` (đổi tên thành `agent-workbench` ngày 14/09/2026); toàn bộ lịch sử cũ nằm dưới `play-store-mcp/` (nay được gom gọn vào `mcp-servers/play-store-mcp/`).
- `antigravity-pm-mcp` và `universal-agent-devkit` được nhập ngày 14/09/2026 bằng `git subtree add`, giữ nguyên commit gốc.

## Làm việc với từng dự án

```bash
cd agent-workbench/mcp-servers/antigravity-pm-mcp && npm install && npm test
cd agent-workbench/mcp-servers/play-store-mcp && uv sync && uv run pytest
```

DevKit cho chính repo này (hook, skill và lệnh của Claude Code / Gemini CLI): chạy **từ gốc repo**, một lần sau
mỗi lần clone — `.claude/hooks/` là link của riêng máy này nên bị gitignore, thiếu nó thì mọi guard và gate DevKit
đều tắt (SessionStart sẽ in đúng một dòng nhắc lệnh này):

```bash
cd agent-workbench && bash universal-agent-devkit/bin/agent-kit init . -y -a claude,gemini
python3 universal-agent-devkit/bin/agent-health.py -t .   # kiểm tra: PASS
```

Lệnh này không sửa file nào đã track; nó chỉ thêm link máy-cục-bộ (đã gitignore / `.git/info/exclude`) và
`.claude/settings.local.json` (cá nhân, không commit). Đừng dùng `make init` trong `universal-agent-devkit/`: nó cài
DevKit vào chính thư mục kit (sửa / xoá file đã track của kit) và không tạo `.claude/hooks/` ở gốc repo.

Workflow GitHub Actions của `play-store-mcp` nằm ở `play-store-mcp/.github/workflows/` — GitHub chỉ chạy workflow ở
`.github/workflows/` gốc repo, nên muốn CI chạy lại phải kéo lên gốc và sửa `working-directory`.
