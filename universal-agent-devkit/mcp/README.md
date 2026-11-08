# 🔌 MCP (Model Context Protocol) Integration Hub

Universal configuration and schemas for Model Context Protocol (MCP) servers used across **Claude Code**, **OpenAI Codex**, **Antigravity / Gemini**, **Cursor**, and **Grok**.

---

## 📋 MCP Servers Inventory

| Server Name | Command / Transport | Key Capabilities & Tools |
|---|---|---|
| **`codebase-memory-mcp`** | `codebase-memory-mcp` (stdio) | Knowledge Graph discovery, AST symbol navigation, call trace paths (`search_graph`, `trace_path`, `get_code_snippet`, `query_graph`). |
| **`context7`** | `npx -y @upstash/context7-mcp` | Tra cứu official documentation của thư viện bên thứ ba theo phiên bản chính xác (`resolve-library-id`, `query-docs`). |
| **`android-code-search`** | `npx -y cs-android-mcp` | Tìm kiếm mã nguồn và symbol trong Android Open Source Project (AOSP) (`search_android_code`, `suggest_symbols`). |
| **`android-skills`** | `npx -y android-skills-mcp` | Tra cứu kỹ năng phát triển Android chính thức (`list_skills`, `search_skills`, `get_skill`). |
| **`mobile-mcp`** | `npx -y @mobilenext/mobile-mcp@1.0.16` | Điều khiển Android/iOS (thay `replicant-mcp` 08/11/2026): liệt kê thiết bị, mở app, bấm theo `ref` của `mobile_list_elements_on_screen`, gõ, cuộn, chụp màn hình, đọc logcat (`mobile_list_available_devices`, `mobile_launch_app`, `mobile_list_elements_on_screen`, `mobile_click_on_screen_at_coordinates`, `mobile_batch_commands`). Emulator có id là TÊN AVD, máy thật là serial. Không chạy Gradle (dùng Bash). Guard thiết bị `hardware_safety_gate.sh` xét mọi tool `mcp__mobile-mcp__*`, kể cả từng bước trong `mobile_batch_commands`; 4 tool cloud bị chặn mặc định. Nếu bật `.adb-allowlist` / `ADB_ALLOW_SERIALS` phải ghi cả serial adb (`emulator-5554`) lẫn tên AVD / UDID Simulator mà mobile-mcp dùng; denylist phải ghi tên đúng như tool gọi thiết bị (ghi cả serial adb lẫn tên AVD / UDID Simulator, guard không tự đổi tên AVD thành serial); trong allowlist mỗi dòng (hoặc mỗi mục cách nhau `,` `;`) là MỘT tên, tên có dấu cách được giữ nguyên (`Pixel 7 API 34`), các từ của nó không tự được phép. Telemetry của hãng bị tắt bằng `MOBILEMCP_DISABLE_TELEMETRY=1` (không đặt cờ này, tên tool và mã máy băm được gửi lên PostHog). Không bật chung với MCP khác dùng uiautomator trên cùng một thiết bị (tiến trình `DeviceServer` giữ UiAutomation tới 30 phút). |
| **`play-store`** | Python stdio (`play-store-mcp`) | Quản lý Google Play Console, triển khai APK/AAB, track crash rate, ANR rate, review response, subscriptions, vitals summary (`deploy_app`, `get_crash_rate`, `get_reviews`, `get_vitals_summary`). |

---

## 🛠️ Setup Instructions per Agent

### 1. Claude Code
File cấu hình: `.mcp.json` tại root dự án hoặc `~/.claude/.mcp.json`.
```json
{
  "mcpServers": {
    "codebase-memory-mcp": { "command": "codebase-memory-mcp" },
    "context7": { "command": "npx", "args": ["-y", "@upstash/context7-mcp"] },
    "android-code-search": { "command": "npx", "args": ["-y", "cs-android-mcp"] },
    "mobile-mcp": { "command": "npx", "args": ["-y", "@mobilenext/mobile-mcp@1.0.16"], "env": { "ANDROID_HOME": "/Volumes/Data/AndroidSDK" } }
  }
}
```

### 2. Google Antigravity & Gemini CLI
File cấu hình: `mcp_config.json` tại root dự án hoặc `~/.gemini/config/mcp_config.json`.

### 3. Cursor & OpenAI Codex
Thêm cấu hình vào Settings -> MCP Servers hoặc copy từ `mcp/.mcp.json`.

### 4. Grok
Không có file MCP riêng. Grok dùng chung bộ đã cài cho các agent khác.

---

## 📂 Tool Schemas
Toàn bộ schemas định nghĩa chi tiết của 100+ MCP tools được lưu trữ tại thư mục `mcp/schemas/`.
