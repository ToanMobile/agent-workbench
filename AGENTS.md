# agent-workbench

Monorepo công cụ nội bộ cho hệ sinh thái AutoAgentFactory (AAF):

- `mcp-servers/agent-office/` — **AAF Studio** (`:4317` local Mac, `:4318` Telegram Mini App HMAC), `aaf_hub.py`, `aaf_supervisor.py`, `aaf_telegram_bot.py`, và bảng `/cc-switcher`.
- `mcp-servers/cc-switcher-mcp/` — CLI & MCP điều phối pool tài khoản Claude / Antigravity.
- `mcp-servers/play-store-mcp/` — MCP tương tác Google Play Developer API.
- `ai-factory.sh` — Script khởi chạy nhanh AAF Studio & tunnel điện thoại.

## Quy chuẩn làm việc
- Chạy test `agent-office`: `cd mcp-servers/agent-office && python3 -m unittest discover -s tests`
- Chạy test `cc-switcher-mcp`: `cd mcp-servers/cc-switcher-mcp && npm test`
- Không commit/push khi chưa có yêu cầu tường minh; không commit bí mật (`.env`, token, keystore, `telegram.env`).
- Không nuốt lỗi âm thầm (`except: pass` / `catch {}`); mọi tính năng/sửa lỗi đều có test ĐỎ → XANH.
