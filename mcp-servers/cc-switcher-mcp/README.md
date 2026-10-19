# CC Switcher MCP (`cc-switcher-mcp`)

MCP Server và Auto-Switcher Daemon trên macOS dành cho 6 profile đã cấu hình sẵn trong **CC Switch**, tích hợp **Anti-Ban Guard** (nghỉ an toàn 15 phút giữa các tài khoản Claude, đóng băng 5 giờ khi chạm giới hạn `429`) và điều khiển 2 chiều từ điện thoại qua **Telegram Bot**.

## Danh sách 6 Profile hỗ trợ

1. `finos` — `1. FinOS — toan.huynh@finos.asia (5x Team)` (`~/.claude-finos`)
2. `finos_team` — `2. FinOS Team — linhnt@finos.asia (5x Team)` (`~/.claude-finos_team`)
3. `max` — `3. Personal 5x Max — toan.huynh@finos.asia` (`~/.claude-max`)
4. `antigravity` — `4. Antigravity Ultra — phathuy.vetgo@gmail.com (Gemini 4 Argon High)`
5. `antigravity_pro` — `5. Antigravity Pro — alex.1993.dev@gmail.com (Gemini 4 Argon High)`
6. `grok` — `6. Grok CLI — grok-4.7 (xhigh)`

## Các MCP Tools cung cấp

- `switcher_status`: Xem trạng thái thực tế của 6 profile, thời gian Cooldown chống ban và thống kê token/chi phí từ `~/.cc-switch/cc-switch.db`.
- `switcher_switch`: Chuyển sang một profile cụ thể (`1..6` hoặc ID) kèm kiểm tra Cooldown và thông báo Telegram.
- `switcher_rotate`: Tự động xoay sang profile khả dụng tiếp theo.
- `switcher_report_limit`: Đánh dấu tài khoản hiện tại dính `429`, tự động đóng băng 5 giờ (`18000s`), xoay sang tài khoản kế tiếp và bắn cảnh báo về điện thoại.
- `switcher_configure_policy`: Điều chỉnh thời gian nghỉ chống ban (`claudeCooldownMinutes`, `rateLimitFreezeMinutes`).
- `switcher_telegram_setup`: Lưu Token và Chat ID Telegram vào `~/.cc-switch/telegram.env` (quyền `0600`, không bao giờ lưu vào Git).

## Điều khiển từ điện thoại qua Telegram

Khi chạy chế độ Daemon (`node bin/cc-switcher-mcp.js --daemon`), bạn có thể nhắn trực tiếp vào Bot Telegram trên điện thoại:

- `/status`: Xem danh sách 6 profile, tài khoản đang active và lượng token/chi phí đã dùng.
- `/switch <1..6>`: Đổi sang tài khoản chỉ định từ xa.
- `/rotate`: Tự động chuyển sang tài khoản an toàn kế tiếp.
- `/limit`: Báo tài khoản hiện tại hết quota (đóng băng 5h + chuyển tài khoản).
- `/cooldown 15`: Đặt khoảng nghỉ chống ban 15 phút giữa các tài khoản Claude.
