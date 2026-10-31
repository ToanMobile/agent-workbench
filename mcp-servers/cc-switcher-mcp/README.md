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

## Bảng điều khiển trên web (thay cho Telegram)

Bảng điều khiển nằm ở **http://ai-factory.localhost:4317/cc-switcher** (trang của Agent Office, nút "CC Switcher" trong Xưởng agent). Chỉ mở trên chính máy Mac: qua tunnel điện thoại, kể cả có key, trang trả 403.

- 6 tài khoản: % quota 5 giờ và 7 ngày, giờ reset (giờ VN) kèm thời gian còn lại, đóng băng 429, số repo đang gán, nguồn và tuổi số liệu quota.
- Chuyển tài khoản (có hộp xác nhận; đang trong cooldown hoặc đóng băng thì hỏi "Ép chuyển ngay"), xoay vòng, báo chạm 429, mở khóa 429 và cooldown, đặt thời gian nghỉ (15/5/0 phút hoặc số tùy chọn).
- Chia đều / đảo nhóm repo FinOS ↔ FinOS Team, lịch sử 50 lần chuyển gần nhất, sức khỏe (daemon, cảnh báo Telegram, cc-switch.db, lần đọc quota gần nhất).
- Trang gọi lại logic của gói này qua CLI JSON: `node bin/cc-switcher-mcp.js --panel-json [--refresh]` và `--panel-action <refresh|switch|rotate|limit|unfreeze|balance|cooldown>`. Không trả token hay chat id Telegram.

## Telegram: chỉ còn cảnh báo

Daemon (`node bin/cc-switcher-mcp.js --daemon`) vẫn gửi cảnh báo 429 / đổi tài khoản (văn bản, kèm link bảng điều khiển web) và giữ nút duyệt super-board. Bảng điều khiển, bàn phím ghim, danh sách lệnh (`/status`, `/menu`, `/switch`, `/rotate`, `/limit`, `/cooldown`, `/unfreeze`) đã gỡ: tin nhắn bất kỳ chỉ nhận lại link web, nút cũ trên tin nhắn cũ chỉ báo link rồi tự gỡ, daemon khởi động thì xóa danh sách lệnh cũ của bot.
