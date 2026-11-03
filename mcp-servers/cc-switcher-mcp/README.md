# CC Switcher MCP (`cc-switcher-mcp`)

MCP Server và Auto-Switcher Daemon trên macOS dành cho 7 profile đã cấu hình sẵn trong **CC Switch**, tích hợp **Anti-Ban Guard** (nghỉ an toàn 15 phút giữa các tài khoản Claude, đóng băng 5 giờ khi chạm giới hạn `429`) và bảng điều khiển trên web `/cc-switcher` (Telegram chỉ còn gửi cảnh báo).

## Danh sách 6 Profile hỗ trợ

1. `finos` — `1. FinOS — toan.huynh@finos.asia (5x Team)` (`~/.claude-finos`)
2. `finos_team` — `2. FinOS Team — linhnt@finos.asia (5x Team)` (`~/.claude-finos_team`)
3. `max` — `3. Personal 5x Max — toan.huynh@finos.asia` (`~/.claude-max`)
4. `antigravity` — `4. Antigravity Ultra — phathuy.vetgo@gmail.com (Gemini 4 Argon High)`
5. `antigravity_pro` — `5. Antigravity Pro — alex.1993.dev@gmail.com (Gemini 4 Argon High)`
6. `grok` — `6. Grok CLI — grok-4.7 (xhigh)`

### Antigravity nhiều profile

`agy` không có biến chọn thư mục cấu hình, chỉ tách tài khoản qua `HOME`. Chỉ `agy` gõ trong zsh tương tác dùng khoá `agyAccount`; `switchProfile` trả `HOME` trong `env`; `antigravity-pm-mcp` (`/giao`) chưa đọc `agyAccount`. Mỗi profile AGY có HOME riêng (`~/.agy-antigravity_ultra`, `~/.agy-antigravity_pro`; trong đó chỉ `.gemini` là thật, còn lại là symlink về HOME thật). Hàm `agy()` trong `~/.zshrc` đọc khoá `agyAccount` trong `.claude/settings.local.json` của repo (khoá riêng, không đụng `account` của Claude) rồi đặt `HOME`. `agy-profile <tên>` ghi khoá đó và dựng thư mục; lần đầu phải đăng nhập tài khoản trong thư mục mới. `agy` lưu tài khoản trong Keychain (service `gemini`) và Keychain đi theo `HOME`, nên mỗi profile có `Library` thật với `Keychains/login.keychain-db` riêng (mật khẩu trống) và `Preferences` riêng; các mục khác của `Library` là symlink. Profile dựng bản cũ (Library symlink) được đổi tự động; cần đăng nhập lại. `.gemini` của profile bắt đầu RỖNG: MCP server, skill, `GEMINI.md` và trusted folders trong `~/.gemini` thật không tự có, phải cài lại hoặc symlink từng mục (trừ file token tài khoản).

## Các MCP Tools cung cấp

- `switcher_status`: Xem trạng thái thực tế của 7 profile, thời gian Cooldown chống ban và thống kê token/chi phí từ `~/.cc-switch/cc-switch.db`.
- `switcher_switch`: Chuyển sang một profile cụ thể (`1..7` hoặc ID) kèm kiểm tra Cooldown và thông báo Telegram.
- `switcher_rotate`: Tự động xoay sang profile khả dụng tiếp theo.
- `switcher_report_limit`: Đánh dấu tài khoản hiện tại dính `429`, tự động đóng băng 5 giờ (`18000s`), xoay sang tài khoản kế tiếp và bắn cảnh báo về điện thoại.
- `switcher_configure_policy`: Điều chỉnh thời gian nghỉ chống ban (`claudeCooldownMinutes`, `rateLimitFreezeMinutes`).
- `switcher_telegram_setup`: Lưu Token và Chat ID Telegram vào `~/.cc-switch/telegram.env` (quyền `0600`, không bao giờ lưu vào Git).

## Bảng điều khiển trên web (thay cho Telegram)

Bảng điều khiển nằm ở **http://ai-factory.localhost:4317/cc-switcher** (trang của Agent Office, nút "CC Switcher" trong Xưởng agent). Chỉ mở trên chính máy Mac: qua tunnel điện thoại, kể cả có key, trang trả 403.

- 7 tài khoản: % quota 5 giờ và 7 ngày, giờ reset (giờ VN) kèm thời gian còn lại, đóng băng 429, số repo đang gán, nguồn và tuổi số liệu quota.
- Chuyển tài khoản (có hộp xác nhận; đang trong cooldown hoặc đóng băng thì hỏi "Ép chuyển ngay"), xoay vòng, báo chạm 429, mở khóa 429 và cooldown, đặt thời gian nghỉ (15/5/0 phút hoặc số tùy chọn).
- **Repo ↔ Tài khoản**: bảng mọi repo cc-switcher biết (tên, nhóm, đường dẫn, tài khoản gán, tài khoản đang dùng thực tế khi tài khoản gán chạm 429 hoặc repo chưa ghim, số git worktree, lần dùng Claude Code cuối và bằng tài khoản nào) và danh sách repo theo từng tài khoản. Đổi tài khoản của một repo ngay trong bảng (chọn → Lưu → xác nhận; ghi `account` vào `.claude/settings.local.json`, giống `claude-profile`), thêm repo Git mới hoặc gỡ repo (xóa khóa `account`). Danh sách repo thêm/gỡ lưu ở `~/.cc-switch/repos.json`.
- Chia đều / đảo nhóm repo FinOS ↔ FinOS Team, lịch sử 50 lần chuyển gần nhất, sức khỏe (daemon, cảnh báo Telegram, cc-switch.db, lần đọc quota gần nhất).
- Trang gọi lại logic của gói này qua CLI JSON: `node bin/cc-switcher-mcp.js --panel-json [--refresh]` và `--panel-action <refresh|switch|rotate|limit|unfreeze|balance|cooldown|repo_assign|repo_add|repo_remove>`. Không trả token hay chat id Telegram.

## Đổi id tài khoản (03/11/2026)

`finos` → `finos_toan`, `finos_team` → `finos_linh`, `max` → `finos_toan_max`, `antigravity` → `antigravity_ultra` (và thêm `finos_lua`). Id cũ vẫn được nhận ở mọi chỗ nhập (CLI `--switch`, API, ghim `account` cũ trong repo, state cũ); khi ghi luôn là id mới.

- **Thư mục đăng nhập KHÔNG đổi tên**: `~/.claude-finos`, `~/.claude-finos_team`, `~/.claude-max` giữ nguyên. Claude Code lưu token trong Keychain theo `sha256(đường dẫn CLAUDE_CONFIG_DIR)` (xem `fetchAnthropicProfileQuotaLive`), đổi tên thư mục là mất đăng nhập của cả 3 tài khoản.
- App CC Switch và `~/.cc-switch/cc-switch.db` giữ id cũ (`appProviderId`), cc-switcher tự đồng bộ đúng id đó.
- Migrate ghim `account` ở các repo và `switcher-state.json`: `node bin/cc-switcher-mcp.js --migrate-ids --dry-run` (chỉ in kế hoạch), bỏ `--dry-run` để ghi thật; chạy lại an toàn.
- Hàm `claude` trong `~/.zshrc` dựng `CLAUDE_CONFIG_DIR=$HOME/.claude-$account` từ ghim, nên sau khi migrate phải ánh xạ id mới về thư mục cũ, thêm trước dòng `print -u2 "⚡ [Claude CLI] Đang chạy với profile…`:

```zsh
case $account in finos_toan) account_dir=finos;; finos_linh) account_dir=finos_team;; finos_toan_max) account_dir=max;; *) account_dir=$account;; esac
# rồi dùng CLAUDE_CONFIG_DIR="$HOME/.claude-$account_dir" ở dòng chạy claude; khoá 429 vẫn tra theo "$account" (state đã đổi sang id mới)
```

## Telegram: chỉ còn cảnh báo

Daemon (`node bin/cc-switcher-mcp.js --daemon`) vẫn gửi cảnh báo 429 / đổi tài khoản (văn bản, kèm link bảng điều khiển web) và giữ nút duyệt super-board. Bảng điều khiển, bàn phím ghim, danh sách lệnh (`/status`, `/menu`, `/switch`, `/rotate`, `/limit`, `/cooldown`, `/unfreeze`) đã gỡ: tin nhắn bất kỳ chỉ nhận lại link web, nút cũ trên tin nhắn cũ chỉ báo link rồi tự gỡ, daemon khởi động thì xóa danh sách lệnh cũ của bot.
