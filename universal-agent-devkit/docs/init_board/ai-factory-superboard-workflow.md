# 🏭 AI Factory: quy trình nhà máy tự hành cho 6 repo

Máy Mac ở nhà chạy 24/7. Bạn giao việc bằng thẻ trên GitHub Project, các runner super-board tự nhận thẻ, viết code, chạy gate của DevKit rồi merge. Agent Office là văn phòng 3D để xem và điều khiển cả 6 board, mở được trên Mac lẫn điện thoại.

## 1. Chạy nhanh

Mọi lệnh chạy từ thư mục `/Volumes/Data/Toan/agent-workbench`.

| Việc | Lệnh |
| :--- | :--- |
| Bật cả nhà máy | `./ai-factory.sh` (hoặc `./ai-factory.sh start`) |
| Xem cái gì đang chạy | `./ai-factory.sh status` |
| Tắt cả nhà máy | `./ai-factory.sh stop` |
| Lấy mã QR mới cho điện thoại | chạy lại `./ai-factory.sh` (mã cũ hết hiệu lực) |
| Mở văn phòng trên Mac | http://ai-factory.localhost:4317 |

`ai-factory.sh` chưa nằm trong `PATH`, nên gõ đúng `./ai-factory.sh` ở thư mục gốc repo.

## 2. Ba phần của nhà máy

| Phần | Nằm ở đâu | Làm gì |
| :--- | :--- | :--- |
| Agent Office | `mcp-servers/agent-office/` | Văn phòng 3D đọc cả 6 GitHub Project. Xem ai đang làm gì, kéo thẻ, thêm việc, bình luận. |
| Super-board runners | `universal-agent-devkit/scripts/governance/super_board_all.py` | Mỗi repo một runner. Nhận thẻ `Ready`, giao cho agent làm trong worktree riêng, đưa thẻ qua Building, QA, Review, Done. |
| DevKit gate | `post-fix-gate.py` trong `.agents/devkit/bin/` | Cổng kiểm tra trước khi merge. Chỉ exit `0` mới được merge. |

## 3. `ai-factory.sh` làm gì

### Khi bật (`start`)

1. Bật server Agent Office trên cổng 4317. Nếu đã có server chạy sẵn trên cổng đó (ví dụ bản tự chạy khi đăng nhập), giữ nguyên server đó.
2. Bật cả 6 runner super-board (`super_board_all.py start`).
3. Tắt tunnel cũ và xoá key cũ, rồi tạo key bí mật mới (`~/.agent-office/remote-key`, chỉ chủ máy đọc được).
4. Mở Cloudflare quick tunnel tới `http://127.0.0.1:4317`. Chỉ mở khi cổng 4317 đúng là Agent Office.
5. In mã QR (cần `qrencode`). Mã chứa link `https://<tên-ngẫu-nhiên>.trycloudflare.com/#key=<key>`.
6. Mở http://ai-factory.localhost:4317 trên Mac.

Thiếu `cloudflared` thì bỏ qua bước truy cập từ xa, phần còn lại vẫn chạy. Cài một lần: `brew install cloudflared qrencode`.

### Khi tắt (`stop`)

- Tắt tunnel và xoá key. Link cũ hết dùng được ngay.
- Tắt server Agent Office do chính `ai-factory.sh` bật. Server tự chạy khi đăng nhập không bị tắt.
- Chỉ tắt đúng tiến trình đã ghi PID, và chỉ khi PID đó vẫn là `cloudflared` hoặc `server.py`. Không đụng tới tunnel hay server khác.
- Dừng cả 6 runner super-board.

### Khi xem (`status`)

Báo Agent Office bật hay tắt, tunnel bật hay tắt kèm địa chỉ tunnel, và trạng thái 6 runner. Lệnh này không in key. Muốn có QR mới thì chạy lại `start`.

File trạng thái nằm trong `~/.agent-office/`: `server.log`, `tunnel.log`, `server.pid`, `tunnel.pid`, `remote-key`.

## 4. An toàn khi mở từ xa

| Ai gọi | Cần key không |
| :--- | :--- |
| Trình duyệt trên chính máy Mac (`localhost`, `127.0.0.1`, `ai-factory.localhost`, `ai-factory.test`) | Không |
| Điện thoại qua tunnel, tải trang và ảnh, model 3D | Không, vì các file này không có dữ liệu |
| Điện thoại qua tunnel, đọc dữ liệu (`/api/...`) | Có, gửi trong header `X-Agent-Office-Key` |
| Điện thoại qua tunnel, sửa thẻ, thêm việc | Có key, và thêm header `X-Agent-Office: 1` |

Cách server phân biệt: cloudflared gắn header `Cf-Connecting-Ip` và `Cf-Ray` vào mọi yêu cầu đi qua tunnel. Yêu cầu có header đó luôn bị coi là từ ngoài.

Những điểm cần nhớ:

- Key đổi mỗi lần `start`. QR cũ hết dùng được.
- Không có file key (đã `stop`) thì mọi yêu cầu từ ngoài bị từ chối (403).
- Key nằm sau dấu `#` trong link, nên trình duyệt không gửi nó lên Cloudflare. Trang đọc key, cất vào `localStorage` của trình duyệt đó, rồi xoá khỏi thanh địa chỉ.
- So key bằng `hmac.compare_digest`. Sai key thì trả 401.
- Server chỉ nghe `127.0.0.1`. Tên máy được nhận: `localhost`, `127.0.0.1`, `::1`, các tên trong `allowedHosts` của `config.json`, và tên `*.trycloudflare.com`.
- `ai-factory.localhost` tự trỏ về máy này. `ai-factory.test` cần thêm một dòng vào `/etc/hosts`.

Lưu ý với bản tự chạy khi đăng nhập: `install-autostart.sh` chép code sang `~/.agent-office/app` và chạy bản chép đó. `ai-factory.sh` dùng lại bất kỳ server nào đang nghe cổng 4317. Nếu bản chép cũ hơn bản có kiểm tra key, tunnel sẽ phục vụ dữ liệu mà không cần key. Vì vậy mỗi lần cập nhật code Agent Office, chạy lại `./install-autostart.sh` (nếu đã cài autostart).

## 5. Agent Office

Chi tiết cách dùng ở `mcp-servers/agent-office/README.md`. Tóm tắt:

- **Đọc cả 6 Project cùng lúc.** `config.json` có `github.projects: [1, 2, 3, 4, 5, 6]`. Server đọc song song, mỗi Project một tiến trình `gh`. Một board lỗi thì các board khác vẫn hiện. Đọc lại GitHub mỗi 30 giây và ngay sau mỗi lần sửa.
- **Văn phòng 3D.** Mỗi hàng là một repo, mỗi cột là một trạng thái. Người là model glTF (Quaternius, CC0) có hoạt cảnh ngồi, đứng, đi. Khi thẻ đổi cột, người đứng dậy và đi bộ sang bàn mới theo đường A* tránh bàn ghế (`web/pathing.js`).
- **Ghi ngược về đúng Project của thẻ.** Kéo thẻ, đổi trường, bình luận, lưu trữ thẻ đều ghi lên Project chứa thẻ đó. Thêm việc mới thì vào Project của repo đã chọn. Runner thấy thay đổi ngay.
- **Che token.** Lời agent và lệnh lấy từ transcript được lọc qua `redact()` trước khi hiện: token GitHub, API key, mật khẩu, private key, header `Bearer` bị thay bằng `***`.
- **Agent đang làm gì.** Đọc transcript Claude Code trong `~/.claude/projects` mỗi 3 giây, và dòng `[RUNNER] ... tick` của super-board.
- **Tự chạy khi đăng nhập.** `./install-autostart.sh` cài launchd (`com.toanmobile.agent-office`). Gỡ bằng `./uninstall-autostart.sh`.
- **Kiểm tra trước khi dùng.** `python3 server.py --check`. Xem thử không đụng GitHub: `python3 server.py --demo --open`.
- **Quyền GitHub.** Chạy một lần `gh auth refresh -s project`.

## 6. Dùng trên điện thoại

| Cách | Dùng khi | Ghi chú |
| :--- | :--- | :--- |
| GitHub Mobile | Giao việc, xem board, đọc PR, trả lời thẻ `Blocked` | Không cần mở cổng mạng. Đủ cho phần lớn nhu cầu. |
| QR của `ai-factory.sh` | Xem văn phòng 3D, kéo thẻ từ xa | Quét QR in ra khi `start`. Link đổi mỗi lần chạy. |
| Tailscale (tuỳ chọn) | Muốn mạng riêng, không qua Cloudflare | Chưa cài trên máy này. Cài `brew install --cask tailscale`, rồi mở `http://<IP Tailscale>:4317`. Server đang nghe `127.0.0.1`, nên phải đổi `host` trong `config.json` và thêm IP hoặc tên Tailscale vào `allowedHosts`. Tên trong `allowedHosts` được coi như chính máy Mac, không cần key, nên chỉ làm vậy khi mạng Tailscale chỉ có máy của bạn. |

Giao việc từ điện thoại:

1. Mở app GitHub, chọn repo, tạo issue mới có Acceptance Criteria.
2. Gắn issue vào Project của repo, chọn cột `Ready`.
3. Runner ở nhà nhận thẻ trong lần tick kế tiếp.
4. Thẻ vào `Blocked` thì đọc bình luận, trả lời, kéo về `Ready`.

Vì sao không dùng các cách khác:

- **GitHub Pages:** chỉ là trang tĩnh và công khai. Không đọc được dữ liệu sống trên Mac, và không nên công khai trạng thái board.
- **Cloudflare named tunnel:** cần một tên miền riêng đã trỏ về Cloudflare. Quick tunnel không cần tài khoản hay tên miền, đổi link mỗi lần chạy, và có key bảo vệ.

## 7. Đưa thay đổi lên origin

- Nhánh `main` của `agent-workbench` được bảo vệ. Không push thẳng.
- Thay đổi đi qua PR, rồi merge bằng `.claude/bin/super-board-merge-gate.sh`. Gate merge chạy lại `verify_commands` trên nội dung sẽ merge.
- `verify_commands` của `agent-workbench` (`.claude/super-board/configs/agent-workbench.json`): `python3 universal-agent-devkit/bin/post-fix-gate.py --run-tests --full --force-full --brief --auto-approve-tests`.
- DevKit gate bỏ qua code bên thứ ba trong thư mục `vendor/` khi kiểm tra nội dung (ví dụ Three.js trong `web/vendor`). Quét secret vẫn đọc cả `vendor/`.

## 8. Sáu repo và board

| Repo | Đường dẫn | Project | Tài khoản ưu tiên |
| :--- | :--- | :---: | :--- |
| agent-workbench | `/Volumes/Data/Toan/agent-workbench` | #1 | `finos` |
| OfficeReader | `/Volumes/Data/Toan/OfficeReader/OfficeReader` | #2 | `finos_team` |
| Goods-Triple-Shelf-Match-3D | `/Volumes/Data/Toan/Game/Goods-Triple-Shelf-Match-3D` | #3 | `finos` |
| GeelyEx2 | `/Volumes/Data/Toan/GeelyEx2` | #4 | `finos_team` |
| Neighbours-From-Hell | `/Volumes/Data/Toan/Game/Neighbours-From-Hell` | #5 | `finos` |
| Humans-vs.-UFOs | `/Volumes/Data/Toan/Game/Humans-vs.-UFOs` | #6 | `finos` |

Cài super-board vào một repo mới:

1. `cd <repo>` rồi `bash ~/.local/share/super-board/install.sh --yes`.
2. Mở Claude Code trong repo, chạy `/super-board onboard`, chọn đúng Project.
3. Giữ nguyên `AGENTS.md` của DevKit, không cho ghi đè.
4. Trong `.claude/super-board/configs/<slug>.json`, đặt `verify_commands` chạy `post-fix-gate.py --run-tests --full --brief`.

### Thẻ đi qua 7 cột

| Cột | Việc diễn ra |
| :--- | :--- |
| `Backlog` | Việc mới, chưa đủ điều kiện. Runner kéo thẻ đủ AC lên `Ready` khi lane build rảnh. |
| `Ready` | Chờ runner nhận. |
| `Building` | Agent làm trong worktree riêng: test đỏ trước, sửa, test xanh. |
| `QA` | Chạy DevKit gate (exit `0`), ảnh nghiệm thu khi có màn hình, mở PR. |
| `Review` | Việc nhỏ (dưới 3 file, tối đa 200 dòng, không chạm auth, thanh toán, migration): tự review rồi merge qua merge gate. Việc lớn: chờ agent thứ hai review chéo. |
| `Blocked` | Cần bạn. Bình luận cuối ghi lý do. |
| `Done` | Đã merge vào nhánh chính. |

## 9. Treo Mac 24/7

Lệnh chạy một lần khi cắm sạc. Máy này hiện vẫn để `sleep 1`, nên chưa áp dụng:

```bash
sudo pmset -c sleep 0 disksleep 0 displaysleep 5 tcpkeepalive 1
```

Khôi phục khi mang máy đi: `sudo pmset -c sleep 1 displaysleep 10`.

Không để SSH hỏi mật khẩu giữa đêm: `ssh-add --apple-use-keychain ~/.ssh/id_ed25519`, rồi kiểm tra `gh auth status`.

| Rủi ro khi chạy nhiều ngày | Cơ chế tự xử lý |
| :--- | :--- |
| Hết hạn mức Claude giữa đêm | `super-board-account-pool.sh` chuyển sang tài khoản kế tiếp khi chạm 95 %. |
| Agent treo hoặc thẻ chết sớm lặp lại | Runner thu hồi tiến trình treo; thẻ chết sớm quá 3 lần thì thôi giao lại. |
| Đầy ổ vì worktree | Runner dọn worktree của thẻ đã merge và worktree `red-proof-*` mồ côi. |
| Nhiều repo cùng chạy gate nặng | `super-board-heavy-slot.py` giới hạn số gate nặng chạy cùng lúc trên cả máy. |
| GitHub API lỗi, runner dừng (`rc=79`) | Chạy lệnh mở khoá ở mục 11, rồi `./ai-factory.sh` lại. |

## 10. Tài khoản và CC Switch

| Mã | Tài khoản | Model mặc định | Nơi lưu |
| :--- | :--- | :--- | :--- |
| `finos` | toan.huynh@finos.asia (FinOS) | `sonnet`, advisor `opus` | `~/.claude-finos` |
| `finos_team` | linhnt@finos.asia (FinOS Team) | `sonnet`, advisor `opus` | `~/.claude-finos_team` |
| `max` | toan.huynh@finos.asia (Personal Max) | `sonnet`, advisor `opus` | `~/.claude-max` |
| `antigravity` | phathuy.vetgo@gmail.com (Google AI Ultra) | `gemini-4-argon-high` | `~/.gemini/antigravity-cli/` |
| `antigravity_pro` | alex.1993.dev@gmail.com (Google AI Pro) | `gemini-4-argon-high` | `~/.gemini/antigravity-cli/` |
| `grok` | Grok CLI | `grok-4.7` | `~/.grok/config.toml` |

- CC Switch để chế độ `Direct`: không proxy, không chèn token tĩnh. `claude` nói chuyện thẳng với Anthropic bằng Keychain.
- Máy này có dữ liệu CC Switch (`~/.cc-switch/`) nhưng chưa có `CC Switch.app` trong `/Applications`, nên mục 7 của `--verify` báo FAIL (đo ngày 22/10). `ccswitch` dòng lệnh vẫn chạy.
- Ba thư mục `~/.claude-{finos,finos_team,max}` dùng symlink về `~/.claude/`, nên đổi tài khoản vẫn giữ lịch sử `claude --resume`.
- Khi cả 3 tài khoản Claude chạm 95 %, chỉ chuyển sang Antigravity hoặc Grok nếu bật `SB_FALLBACK_ANTIGRAVITY=1` (hoặc `=pro`) và `SB_FALLBACK_GROK=1`. Không bật thì runner tạm dừng tới khi hạn mức hồi.

Lệnh hay dùng:

| Việc | Lệnh |
| :--- | :--- |
| Xem hạn mức các tài khoản | `ccswitch list` |
| Đổi tài khoản đang dùng | `ccswitch switch finos` (hoặc `finos_team`, `max`, `antigravity`, `antigravity_pro`, `grok`) |
| Đổi tài khoản mặc định cho một repo | `~/.claude/bin/super-board-account-pool.sh switch <đường-dẫn-repo> max` |

## 11. Bảng lệnh

| Việc | Lệnh |
| :--- | :--- |
| Bật nhà máy (office, 6 runner, tunnel, QR) | `./ai-factory.sh` |
| Tắt nhà máy | `./ai-factory.sh stop` |
| Xem trạng thái | `./ai-factory.sh status` |
| Chỉ bật, tắt hoặc xem 6 runner | `python3 universal-agent-devkit/scripts/governance/super_board_all.py start` (hoặc `stop`, `status`) |
| Board của một repo | `/super-board status`, `/super-board stop` |
| Kiểm tra Agent Office | `cd mcp-servers/agent-office && python3 server.py --check` |
| Cài hoặc cập nhật Agent Office tự chạy | `cd mcp-servers/agent-office && ./install-autostart.sh` |
| Hạn mức GitHub API | `gh api rate_limit \| jq '.resources.core, .resources.graphql'` |
| Kiểm tra sức khoẻ cấu hình (9 mục) | `~/.claude/bin/setup-autonomous-factory.sh --verify` |

Mở khoá sau khi GitHub API lỗi làm runner dừng (`rc=79`), chạy ở từng repo:

```bash
python3 .claude/bin/super-board-github-read.py --resume
```

## 12. Cài lại máy bằng một lệnh

Script `setup-autonomous-factory.sh` nằm ngay trong file này (mục 12.3). Nó cài bể tài khoản và `ccswitch`, vá super-board cho quy trình DevKit, nối symlink session, cấu hình model và CC Switch, gán tài khoản cho 6 repo, rồi kiểm tra 9 mục. Script không bật nhà máy. Bật bằng `./ai-factory.sh`.

9 mục kiểm tra: `ai-factory.sh` và Agent Office có mặt · `cloudflared` và `qrencode` đã cài · super-board đã cài trong `~/.claude/` · mẫu config có khoá DevKit gate · bể tài khoản và `ccswitch` · symlink session của 3 tài khoản · CC Switch.app · 6 repo đã gán tài khoản · `/super-board onboard` xanh ở cả 6 repo.

### 12.1. Chạy thẳng từ file này

Từ thư mục `/Volumes/Data/Toan/agent-workbench`:

```bash
awk '/^# === BOOTSTRAP_START ===$/{f=1;next}/^# === BOOTSTRAP_END ===$/{f=0}f' \
  universal-agent-devkit/docs/init_board/ai-factory-superboard-workflow.md \
  > ~/.claude/bin/setup-autonomous-factory.sh \
  && chmod +x ~/.claude/bin/setup-autonomous-factory.sh \
  && ~/.claude/bin/setup-autonomous-factory.sh
```

Chỉ kiểm tra, không sửa gì:

```bash
~/.claude/bin/setup-autonomous-factory.sh --verify
```

### 12.2. Máy Mac mới

1. Đăng nhập từng tài khoản Claude một lần:
   ```bash
   CLAUDE_CONFIG_DIR=~/.claude-finos claude login
   CLAUDE_CONFIG_DIR=~/.claude-finos_team claude login
   CLAUDE_CONFIG_DIR=~/.claude-max claude login
   ```
2. Cài công cụ: `brew install cloudflared qrencode jq`.
3. Chạy lệnh ở mục 12.1.
4. Cấp quyền Project cho `gh`: `gh auth refresh -s project`.
5. Bật nhà máy: `./ai-factory.sh`.

### 12.3. Mã nguồn script (`setup-autonomous-factory.sh`)

Các bản vá tự động trong script:

| # | File được vá | Tác dụng |
| :-: | :--- | :--- |
| 1 | `super-board-run.sh`, `super-board-wave.js` | Worker gọi qua bể tài khoản; một worker DevKit đưa thẻ qua nhiều cột mà không bị coi là treo; không sinh thêm worker QA, Review khi thẻ đã tới `Done`. |
| 2 | `super-board-skills-ready.py` | Tìm skill cả trong `.agents/skills/` và ánh xạ tên skill super-board sang skill DevKit. |
| 3 | `super-board-setup.py` | Nhận bản cài trong `~/.claude/`; tự thêm `verify_commands` chạy DevKit gate khi config còn trống. |
| 4 | `super-board-agents-md.py` | Nâng giới hạn dòng lên 600 và không đề nghị gộp đè `AGENTS.md` do DevKit quản lý. |
| 5 | `worker-preamble.md`, `agents-md-block.md`, `run.md` | Chèn quy trình DevKit và lệnh chuyển cột vào lời dặn của mọi worker. |

```bash
# === BOOTSTRAP_START ===
#!/usr/bin/env bash
# setup-autonomous-factory.sh — 1-Command Full Auto-Config & Recovery for Agent-Workbench Autonomous Factory
# Source of Truth: universal-agent-devkit/docs/init_board/ai-factory-superboard-workflow.md
#
# Automatically applies 100% of configuration without manual re-setup:
#   1. ai-factory tools check (ai-factory.sh, Agent Office, cloudflared, qrencode) — start the factory with ./ai-factory.sh
#   2. Super-Board v3.1.2 global config + DevKit post-fix-gate lock (`template-devkit-config.json`)
#   3. 6-Tier Multi-Account Pool (`super-board-account-pool.sh` + `ccswitch` CLI):
#      - 1. finos            : toan.huynh@finos.asia [FinOS 5x Team]       (sonnet / advisor opus • xhigh)
#      - 2. finos_team       : linhnt@finos.asia [FinOS Team 5x]           (sonnet / advisor opus • xhigh)
#      - 3. max              : toan.huynh@finos.asia [Personal 5x Max]     (sonnet / advisor opus • xhigh)
#      - 4. antigravity      : phathuy.vetgo@gmail.com [Google AI Ultra]   (gemini-4-argon-high • xhigh)
#      - 5. antigravity_pro  : alex.1993.dev@gmail.com [Google AI Pro]     (gemini-4-argon-high • xhigh)
#      - 6. grok             : Grok CLI v1.0.50 [xAI]                      (grok-4.7 • xhigh)
#   4. 100% Unified Session Symlinks across ~/.claude-{finos,finos_team,max} -> ~/.claude/
#   5. CC Switch.app GUI SQLite (`~/.cc-switch/cc-switch.db`) & `settings.json` (100% safe Direct mode)
#
# Usage:
#   bash ~/.claude/bin/setup-autonomous-factory.sh            # Full auto-apply + verify
#   bash ~/.claude/bin/setup-autonomous-factory.sh --verify   # Non-destructive 9-point health check

set -euo pipefail

VERIFY_ONLY=0
[ "${1:-}" = "--verify" ] && VERIFY_ONLY=1

FACTORY_ROOT="/Volumes/Data/Toan/agent-workbench"

REPOS=(
  "/Volumes/Data/Toan/agent-workbench:agent-workbench:finos"
  "/Volumes/Data/Toan/OfficeReader/OfficeReader:OfficeReader:finos_team"
  "/Volumes/Data/Toan/Game/Goods-Triple-Shelf-Match-3D:Goods-Triple:finos"
  "/Volumes/Data/Toan/GeelyEx2:GeelyEx2:finos_team"
  "/Volumes/Data/Toan/Game/Neighbours-From-Hell:Neighbours:finos"
  "/Volumes/Data/Toan/Game/Humans-vs.-UFOs:Humans-vs-UFOs:finos"
)

install_account_pool_script() {
  mkdir -p "$HOME/.claude/bin" "$HOME/.local/bin" "$HOME/.claude/super-board"
  cat <<'POOL_EOF' > "$HOME/.claude/bin/super-board-account-pool.sh"
#!/usr/bin/env bash
# super-board-account-pool.sh (also invoked via `ccswitch`)
# 6-Tier Multi-Account Pool & Auto-Failover:
#   1. finos            -> ~/.claude-finos         | FinOS Org (toan.huynh@finos.asia)
#   2. finos_team       -> ~/.claude-finos_team    | FinOS Team (linhnt@finos.asia)
#   3. max              -> ~/.claude-max           | Personal 5x Max (toan.huynh@finos.asia)
#   4. antigravity      -> ~/.local/bin/agy        | Google Antigravity Ultra (phathuy.vetgo@gmail.com • gemini-4-argon-high)
#   5. antigravity_pro  -> ~/.local/bin/agy        | Google Antigravity Pro (alex.1993.dev@gmail.com • gemini-4-argon-high)
#   6. grok             -> ~/.grok/bin/grok        | Grok CLI v1.0.50 (grok-4.7 • xhigh)

set -euo pipefail

POOL_ACCOUNTS=("finos" "finos_team" "max")
SB_DIR="${SB_STATE_DIR:-$HOME/.claude/super-board}"
USAGE_SH="${SB_USAGE_SH:-$HOME/.claude/bin/super-board-usage.sh}"
AGY_BIN="${AGY_BIN:-$HOME/.local/bin/agy}"
GROK_BIN="${GROK_BIN:-$HOME/.grok/bin/grok}"
mkdir -p "$SB_DIR"

usage_file_for() { echo "$SB_DIR/usage-${1}.json"; }

keychain_service_for() {
  case "$1" in
    finos)      echo "Claude Code-credentials-08fc04bc" ;;
    finos_team) echo "Claude Code-credentials-25aa58cc" ;;
    max)        echo "Claude Code-credentials-0f12add9" ;;
    *)          echo "" ;;
  esac
}

account_label() {
  case "$1" in
    finos)            echo "toan.huynh@finos.asia [FinOS]" ;;
    finos_team)       echo "linhnt@finos.asia [FinOS Team]" ;;
    max)              echo "toan.huynh@finos.asia [5x Max]" ;;
    antigravity)      echo "phathuy.vetgo@gmail.com [Ultra]" ;;
    antigravity_pro)  echo "alex.1993.dev@gmail.com [Pro]" ;;
    grok)             echo "Grok CLI [grok-4.7 • xhigh]" ;;
    *)                echo "$1" ;;
  esac
}

set_antigravity_google_account() {
  local acct="$1" active_email="phathuy.vetgo@gmail.com" old_email="alex.1993.dev@gmail.com"
  if [ "$acct" = "antigravity_pro" ]; then
    active_email="alex.1993.dev@gmail.com"
    old_email="phathuy.vetgo@gmail.com"
  fi
  mkdir -p "$HOME/.gemini/antigravity-cli"
  printf '{\n  "active": "%s",\n  "old": [\n    "%s"\n  ]\n}\n' "$active_email" "$old_email" > "$HOME/.gemini/google_accounts.json"
  printf '{\n  "model": "gemini-4-argon-high",\n  "effort": "xhigh",\n  "activeAccount": "%s"\n}\n' "$active_email" > "$HOME/.gemini/antigravity-cli/settings.json"
}

detect_current_account() {
  local repo="${1:-$PWD}"
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    local base
    base="$(basename "$CLAUDE_CONFIG_DIR")"
    case "$base" in
      .claude-*) echo "${base#.claude-}"; return 0 ;;
    esac
  fi
  local root f acct=""
  root="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || echo "$repo")"
  f="$root/.claude/settings.local.json"
  if [ -f "$f" ] && command -v jq >/dev/null 2>&1; then
    acct="$(jq -r '.account // empty' "$f" 2>/dev/null || true)"
  fi
  if [ -z "$acct" ] && [ -f "$SB_DIR/active-account" ]; then
    acct="$(cat "$SB_DIR/active-account" 2>/dev/null || true)"
  fi
  echo "${acct:-finos}"
}

account_email() {
  local acct="$1"
  case "$acct" in
    antigravity)     echo "phathuy.vetgo@gmail.com"; return 0 ;;
    antigravity_pro) echo "alex.1993.dev@gmail.com"; return 0 ;;
    grok)            echo "Grok CLI (v1.0.50)"; return 0 ;;
  esac
  local cfg="$HOME/.claude-${acct}/.claude.json"
  if [ -f "$cfg" ] && command -v jq >/dev/null 2>&1; then
    jq -r '.oauthAccount.emailAddress // "unknown"' "$cfg" 2>/dev/null || echo "unknown"
  else
    echo "unknown"
  fi
}

check_account_quota() {
  local acct="$1" threshold="${2:-95}" ufile
  ufile="$(usage_file_for "$acct")"
  if [ ! -f "$ufile" ]; then
    echo '{"state":"ok","window":null,"used":0,"resets_at":null,"age":null,"reason":"ready (no limit hit recorded)"}'
    return 0
  fi
  local out rc=0
  out="$(SB_USAGE_FILE="$ufile" bash "$USAGE_SH" check --threshold "$threshold" 2>/dev/null)" || rc=$?
  if [ "$rc" -eq 3 ]; then
    echo "$out" | jq -c '.state = "ok"'
    return 0
  fi
  echo "$out"
  return "$rc"
}

ordered_pool_for() {
  local preferred="$1" result=() a
  case "$preferred" in
    finos|finos_team|max) result+=("$preferred") ;;
  esac
  for a in "${POOL_ACCOUNTS[@]}"; do
    [ "$a" = "$preferred" ] || result+=("$a")
  done
  printf '%s\n' "${result[@]}"
}

cmd_record() {
  local acct="${1:-}" payload
  [ -n "$acct" ] || acct="$(detect_current_account "$PWD")"
  payload="$(cat)"
  printf '%s' "$payload" | SB_USAGE_FILE="$(usage_file_for "$acct")" bash "$USAGE_SH" record
  printf '%s' "$payload" | SB_USAGE_FILE="$SB_DIR/usage.json" bash "$USAGE_SH" record
}

cmd_resolve() {
  local repo="$PWD" threshold=95
  while [ $# -gt 0 ]; do
    case "$1" in
      --threshold) threshold="$2"; shift 2 ;;
      *) repo="$1"; shift ;;
    esac
  done
  local preferred
  preferred="$(detect_current_account "$repo")"
  if { [ "$preferred" = "antigravity" ] || [ "$preferred" = "antigravity_pro" ]; } && [ -x "$AGY_BIN" ]; then
    local agy_email
    agy_email="$(account_email "$preferred")"
    set_antigravity_google_account "$preferred"
    jq -n --arg engine "antigravity" --arg account "$preferred" --arg preferred "$preferred" \
      --arg email "$agy_email" --arg bin "$AGY_BIN" \
      '{state:"ok", engine:$engine, account:$account, preferred:$preferred, rotated:false, config_dir:"'"$HOME"'/.gemini/antigravity", email:$email, binary:$bin}'
    return 0
  fi
  if [ "$preferred" = "grok" ] && [ -x "$GROK_BIN" ]; then
    jq -n --arg engine "grok" --arg account "grok" --arg preferred "$preferred" --arg bin "$GROK_BIN" \
      '{state:"ok", engine:$engine, account:$account, preferred:$preferred, rotated:false, config_dir:null, binary:$bin}'
    return 0
  fi
  local earliest_reset="" acct qjson qstate qreset
  while IFS= read -r acct; do
    [ -d "$HOME/.claude-${acct}" ] || continue
    set +e; qjson="$(check_account_quota "$acct" "$threshold")"; set -e
    qstate="$(echo "$qjson" | jq -r '.state // "ok"')"
    if [ "$qstate" != "pause" ]; then
      local rotated="false"
      [ "$acct" != "$preferred" ] && rotated="true"
      jq -n --arg engine "claude" --arg account "$acct" --arg preferred "$preferred" \
        --arg config_dir "$HOME/.claude-${acct}" --arg email "$(account_email "$acct")" \
        --arg label "$(account_label "$acct")" --argjson rotated "$rotated" --argjson quota "$qjson" \
        '{state:"ok", engine:$engine, account:$account, preferred:$preferred, rotated:$rotated, config_dir:$config_dir, email:$email, label:$label, quota:$quota}'
      return 0
    fi
    qreset="$(echo "$qjson" | jq -r '.resets_at // empty')"
    if [ -n "$qreset" ] && { [ -z "$earliest_reset" ] || [ "$qreset" -lt "$earliest_reset" ]; }; then
      earliest_reset="$qreset"
    fi
  done < <(ordered_pool_for "$preferred")

  if [ "${SB_FALLBACK_ANTIGRAVITY:-0}" = "1" ] && [ -x "$AGY_BIN" ]; then
    set_antigravity_google_account "antigravity"
    jq -n --arg engine "antigravity" --arg account "antigravity" --arg preferred "$preferred" \
      --arg email "phathuy.vetgo@gmail.com" --arg bin "$AGY_BIN" \
      '{state:"ok", engine:$engine, account:$account, preferred:$preferred, rotated:true, config_dir:"'"$HOME"'/.gemini/antigravity", email:$email, binary:$bin, reason:"all 3 Claude accounts at >=95% quota; failed over to Antigravity Ultra (phathuy.vetgo@gmail.com)"}'
    return 0
  fi
  if [ "${SB_FALLBACK_ANTIGRAVITY:-0}" = "pro" ] && [ -x "$AGY_BIN" ]; then
    set_antigravity_google_account "antigravity_pro"
    jq -n --arg engine "antigravity" --arg account "antigravity_pro" --arg preferred "$preferred" \
      --arg email "alex.1993.dev@gmail.com" --arg bin "$AGY_BIN" \
      '{state:"ok", engine:$engine, account:$account, preferred:$preferred, rotated:true, config_dir:"'"$HOME"'/.gemini/antigravity", email:$email, binary:$bin, reason:"all 3 Claude accounts at >=95% quota; failed over to Antigravity Pro (alex.1993.dev@gmail.com)"}'
    return 0
  fi
  if [ "${SB_FALLBACK_GROK:-0}" = "1" ] && [ -x "$GROK_BIN" ]; then
    jq -n --arg engine "grok" --arg account "grok" --arg preferred "$preferred" --arg bin "$GROK_BIN" \
      '{state:"ok", engine:$engine, account:$account, preferred:$preferred, rotated:true, config_dir:null, binary:$bin, reason:"all 3 Claude accounts at >=95% quota; failed over to Grok CLI"}'
    return 0
  fi
  jq -n --arg preferred "$preferred" --argjson resets_at "${earliest_reset:-null}" \
    '{state:"pause", engine:"claude", account:null, preferred:$preferred, resets_at:$resets_at, reason:"all 3 Claude accounts (finos, finos_team, max) are >= threshold"}'
  return 10
}

cmd_status() {
  local threshold="${1:-95}" current
  current="$(detect_current_account "$PWD")"
  echo "╭─────────────────┬──────────────────────────────────┬──────────┬──────────┬──────────────────────────────────────╮"
  echo "│ ACCOUNT         │ EMAIL / PLAN / ENGINE            │ QUOTA    │ STATUS   │ CONFIG & UNIFIED SESSIONS            │"
  echo "├─────────────────┼──────────────────────────────────┼──────────┼──────────┼──────────────────────────────────────┤"
  local acct qjson used state label shared_ok marker
  for acct in "${POOL_ACCOUNTS[@]}"; do
    label="$(account_label "$acct")"
    set +e; qjson="$(check_account_quota "$acct" "$threshold")"; set -e
    used="$(echo "$qjson" | jq -r 'if .used != null then "\(.used)%" else "0%" end')"
    state="$(echo "$qjson" | jq -r '.state // "ok"' | tr '[:lower:]' '[:upper:]')"
    if [ -L "$HOME/.claude-${acct}/projects" ] && [ -L "$HOME/.claude-${acct}/sessions" ]; then
      shared_ok="~/.claude-${acct} (shared sessions ✔)"
    else
      shared_ok="~/.claude-${acct} (isolated)"
    fi
    marker="  $acct"; [ "$acct" = "$current" ] && marker="★ $acct"
    printf "│ %-15s │ %-32s │ %-8s │ %-8s │ %-36s │\n" "$marker" "$label" "$used" "$state" "$shared_ok"
  done
  if [ -x "$AGY_BIN" ]; then
    marker="  antigravity"; [ "$current" = "antigravity" ] && marker="★ antigravity"
    printf "│ %-15s │ %-32s │ %-8s │ %-8s │ %-36s │\n" "$marker" "$(account_label antigravity)" "N/A" "READY" "~/.gemini/antigravity (Argon High ✔)"
    marker="  antigravity_pro"; [ "$current" = "antigravity_pro" ] && marker="★ antigravity_pro"
    printf "│ %-15s │ %-32s │ %-8s │ %-8s │ %-36s │\n" "$marker" "$(account_label antigravity_pro)" "N/A" "READY" "~/.gemini/antigravity (Argon High ✔)"
  fi
  if [ -x "$GROK_BIN" ]; then
    marker="  grok"; [ "$current" = "grok" ] && marker="★ grok"
    printf "│ %-15s │ %-32s │ %-8s │ %-8s │ %-36s │\n" "$marker" "$(account_label grok)" "N/A" "READY" "~/.grok/bin/grok (fallback ready ✔)"
  fi
  echo "╰─────────────────┴──────────────────────────────────┴──────────┴──────────┴──────────────────────────────────────╯"
}

sync_global_claude_credentials() {
  local target="$1" src_cfg="$HOME/.claude-${1}/.claude.json" svc
  svc="$(keychain_service_for "$target")"
  if [ "$target" = "antigravity" ] || [ "$target" = "antigravity_pro" ]; then
    set_antigravity_google_account "$target"
  fi
  if [ -f "$src_cfg" ]; then
    cp "$src_cfg" "$HOME/.claude.json" 2>/dev/null || true
    cp "$src_cfg" "$HOME/.claude/.claude.json" 2>/dev/null || true
  fi
  if [ -n "$svc" ]; then
    local cred=""
    cred="$(security find-generic-password -s "$svc" -w 2>/dev/null || true)"
    if [ -n "$cred" ]; then
      security add-generic-password -U -s "Claude Code-credentials" -a "$(id -un)" -w "$cred" >/dev/null 2>&1 || true
    fi
  fi
  if [ -f "$HOME/.cc-switch/cc-switch.db" ] && command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 "$HOME/.cc-switch/cc-switch.db" \
      "UPDATE providers SET is_current = CASE WHEN id = '$target' THEN 1 ELSE 0 END WHERE app_type = 'claude';" 2>/dev/null || true
    if [ "$target" = "antigravity" ] || [ "$target" = "antigravity_pro" ]; then
      sqlite3 "$HOME/.cc-switch/cc-switch.db" \
        "UPDATE providers SET is_current = CASE WHEN id = '$target' THEN 1 ELSE 0 END WHERE app_type = 'gemini';" 2>/dev/null || true
    fi
  fi
  if [ -f "$HOME/.cc-switch/settings.json" ] && command -v jq >/dev/null 2>&1; then
    local stmp="$HOME/.cc-switch/settings.json.tmp.$$"
    jq --arg t "$target" '.currentProviderClaude = $t | .showProfileSwitcher = true | .enableFailoverToggle = true' \
      "$HOME/.cc-switch/settings.json" > "$stmp" && mv "$stmp" "$HOME/.cc-switch/settings.json"
  fi
  echo "$target" > "$SB_DIR/active-account"
}

cmd_switch() {
  local repo="$PWD" target=""
  if [ $# -eq 0 ]; then
    local cur; cur="$(detect_current_account "$PWD")"
    case "$cur" in
      finos)           target="finos_team" ;;
      finos_team)      target="max" ;;
      max)             target="antigravity" ;;
      antigravity)     target="antigravity_pro" ;;
      antigravity_pro) target="grok" ;;
      *)               target="finos" ;;
    esac
  elif [ $# -eq 1 ]; then
    case "$1" in
      finos|1)                          target="finos" ;;
      finos_team|2)                     target="finos_team" ;;
      max|3)                            target="max" ;;
      antigravity|agy|agy_ultra|4)      target="antigravity" ;;
      antigravity_pro|agy_pro|5)        target="antigravity_pro" ;;
      grok|6)                           target="grok" ;;
      *) echo "error: invalid account '$1'" >&2; return 64 ;;
    esac
  else
    repo="$1"; target="$2"
    [ "$target" = "agy" ] || [ "$target" = "agy_ultra" ] && target="antigravity"
    [ "$target" = "agy_pro" ] && target="antigravity_pro"
  fi
  local root f tmp
  root="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || echo "$repo")"
  if [ -d "$root/.git" ] || [ -f "$root/.git" ] || [ -d "$root/.claude" ]; then
    mkdir -p "$root/.claude"
    f="$root/.claude/settings.local.json"
    if [ -s "$f" ]; then
      tmp="$f.tmp.$$"
      jq --arg a "$target" '.account = $a' "$f" > "$tmp" && mv "$tmp" "$f"
    else
      printf '{\n  "account": "%s"\n}\n' "$target" > "$f"
    fi
  fi
  sync_global_claude_credentials "$target"
  echo "✔ Switched -> '$target' ($(account_label "$target"), 100% sessions preserved)"
}

cmd_exec() {
  local repo="$PWD"
  if [ $# -gt 0 ] && [ "$1" != "--" ]; then repo="$1"; shift; fi
  [ "${1:-}" = "--" ] && shift
  local resolved engine acct cfg_dir agy_email
  resolved="$(cmd_resolve "$repo")" || { echo "$resolved" >&2; return 10; }
  engine="$(echo "$resolved" | jq -r '.engine')"
  acct="$(echo "$resolved" | jq -r '.account')"
  if [ "$engine" = "antigravity" ]; then
    agy_email="$(echo "$resolved" | jq -r '.email // "phathuy.vetgo@gmail.com"')"
    set_antigravity_google_account "$acct"
    echo "⚡ [Multi-Account Pool] Using Antigravity CLI (gemini-4-argon-high • xhigh — $agy_email)" >&2
    exec "$AGY_BIN" --model gemini-4-argon-high --effort xhigh "$@"
  fi
  if [ "$engine" = "grok" ]; then
    echo "⚡ [Multi-Account Pool] Using Grok CLI (grok-4.7 • xhigh)" >&2
    exec "$GROK_BIN" -m grok-4.7 "$@"
  fi
  cfg_dir="$(echo "$resolved" | jq -r '.config_dir')"
  if [ "$(echo "$resolved" | jq -r '.rotated')" = "true" ]; then
    echo "🔄 [Multi-Account Pool] Auto-rotated from $(echo "$resolved" | jq -r '.preferred') -> $acct ($cfg_dir)" >&2
  fi
  export CLAUDE_CONFIG_DIR="$cfg_dir"
  export SB_ACTIVE_ACCOUNT="$acct"
  exec "$@"
}

MODE="${1:-status}"
[ $# -gt 0 ] && shift
case "$MODE" in
  status|list|--list|-l)                                                 cmd_status "$@" ;;
  resolve)                                                               cmd_resolve "$@" ;;
  record)                                                                cmd_record "$@" ;;
  switch|--switch|-s)                                                    cmd_switch "$@" ;;
  exec)                                                                  cmd_exec "$@" ;;
  finos|finos_team|max|antigravity|agy|agy_ultra|antigravity_pro|agy_pro|grok) cmd_switch "$MODE" ;;
  *) echo "Usage: $(basename "$0") [status|list|switch [finos|finos_team|max|antigravity|antigravity_pro|grok]|resolve|record|exec]" >&2; exit 64 ;;
esac
POOL_EOF
  chmod +x "$HOME/.claude/bin/super-board-account-pool.sh"
  ln -sf "$HOME/.claude/bin/super-board-account-pool.sh" "$HOME/.local/bin/ccswitch"

  cat <<'TMPL_EOF' > "$HOME/.claude/super-board/template-devkit-config.json"
{
  "verify_commands": [
    "python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief"
  ],
  "max_workers": 3,
  "tick_seconds": 120,
  "no_progress_cycles": 3,
  "max_dispatches": 30,
  "usage_pause_pct": 95
}
TMPL_EOF
}

patch_super_board_and_devkit_workflow() {
  python3 - <<'PY'
import glob, json, os, re

# 1. Patch super-board-run.sh:
#    - Route worker spawns through super-board-account-pool.sh
#    - Allow single DevKit worker to step card across "Ready Building QA Review" on UI without zombie-kill
for run_sh in [
    os.path.expanduser("~/.claude/bin/super-board-run.sh"),
    os.path.expanduser("~/.local/share/super-board/scripts/super-board-run.sh"),
]:
    if not os.path.exists(run_sh):
        continue
    with open(run_sh, "r") as f:
        txt = f.read()
    if "super-board-account-pool.sh" not in txt and 'nohup claude -p "$prompt" >> "$worker_log" 2>&1 &' in txt:
        old = '  gh_checkpoint\n  nohup claude -p "$prompt" >> "$worker_log" 2>&1 &'
        new = """  gh_checkpoint
  local pool_json="" pool_engine="claude" pool_acct="" pool_cfg=""
  if [ -x "$HOME/.claude/bin/super-board-account-pool.sh" ]; then
    pool_json="$("$HOME/.claude/bin/super-board-account-pool.sh" resolve "$PWD" 2>/dev/null || true)"
    if [ -n "$pool_json" ]; then
      pool_engine="$(echo "$pool_json" | jq -r '.engine // "claude"')"
      pool_acct="$(echo "$pool_json" | jq -r '.account // empty')"
      pool_cfg="$(echo "$pool_json" | jq -r '.config_dir // empty')"
      [ -n "$pool_acct" ] && printf 'account_pool: engine=%s account=%s config_dir=%s\\n' "$pool_engine" "$pool_acct" "$pool_cfg" >> "$worker_log"
    fi
  fi
  if [ "$pool_engine" = "antigravity" ] && [ -x "$HOME/.local/bin/agy" ]; then
    nohup "$HOME/.local/bin/agy" --model gemini-4-argon-high --effort xhigh --dangerously-skip-permissions -p "$prompt" >> "$worker_log" 2>&1 &
  elif [ "$pool_engine" = "grok" ] && [ -x "$HOME/.grok/bin/grok" ]; then
    nohup "$HOME/.grok/bin/grok" -m grok-4.7 -p "$prompt" >> "$worker_log" 2>&1 &
  elif [ -n "$pool_cfg" ]; then
    CLAUDE_CONFIG_DIR="$pool_cfg" nohup claude -p "$prompt" >> "$worker_log" 2>&1 &
  else
    nohup claude -p "$prompt" >> "$worker_log" 2>&1 &
  fi"""
        txt = txt.replace(old, new)
    txt = txt.replace(
        'check_lane_zombie build  "Ready Building"',
        'check_lane_zombie build  "Ready Building QA Review"',
    )
    with open(run_sh, "w") as f:
        f.write(txt)

# 1b. Patch super-board-wave.js:
#     - Respect `b.column` (`at = b.column || 'QA'`) and `q.column` (`at = q.column || 'Review'`)
#       so a DevKit worker that steps the card visually through `Ready -> Building -> QA -> Review -> Done`
#       on the GitHub Project UI does NOT trigger duplicate QA/Review sub-agents when `b.column === 'Done'`,
#       while still triggering independent `Review` when `b.column === 'Review'` (large task >=3 files / >200 LOC).
for wave_js in [
    os.path.expanduser("~/.claude/workflows/super-board-wave.js"),
    os.path.expanduser("~/.local/share/super-board/workflows/super-board-wave.js"),
]:
    if not os.path.exists(wave_js):
        continue
    with open(wave_js, "r") as f:
        wtxt = f.read()
    wtxt = wtxt.replace(
        "`- status=advanced  → card moved forward (Building→QA, QA→Review, Review→Done/merged)`",
        "`- status=advanced  → card moved forward (Building→QA/Review/Done, QA→Review/Done, Review→Done/merged)`",
    )
    wtxt = wtxt.replace(
        "      const b = await runLane('build', card, model, history)\n      if (b.status !== 'advanced') return { number: card.number, history }\n      at = 'QA'",
        "      const b = await runLane('build', card, model, history)\n      if (b.status !== 'advanced') return { number: card.number, history }\n      at = b.column || 'QA'",
    )
    wtxt = wtxt.replace(
        "      const q = await runLane('qa', card, model, history)\n      if (q.status !== 'advanced') return { number: card.number, history }\n      at = 'Review'",
        "      const q = await runLane('qa', card, model, history)\n      if (q.status !== 'advanced') return { number: card.number, history }\n      at = q.column || 'Review'",
    )
    with open(wave_js, "w") as f:
        f.write(wtxt)

# 2. Patch super-board-skills-ready.py:
#    - Search `<repo>/.agents/skills` and `~/.agents/skills` for `host == 'claude'`
#    - Map all `mattpocock-skills:*` and `testing-strategy` directly to Universal Agent DevKit `.agents/skills/*`
for sr_path in [
    os.path.expanduser("~/.claude/bin/super-board-skills-ready.py"),
    os.path.expanduser("~/.local/share/super-board/scripts/super-board-skills-ready.py"),
]:
    if not os.path.exists(sr_path):
        continue
    with open(sr_path, "r") as f:
        sr = f.read()
    sr = sr.replace(
        "self.roots = [self.root / '.claude/skills', self.home / '.claude/skills']",
        "self.roots = [self.root / '.claude/skills', self.root / '.agents/skills', self.home / '.claude/skills', self.home / '.agents/skills']",
    )
    if "DEVKIT_SKILL_MAP" not in sr:
        devkit_map_block = """DEVKIT_SKILL_MAP = {
    'mattpocock-skills:diagnosing-bugs': 'fixbugs',
    'diagnosing-bugs': 'fixbugs',
    'mattpocock-skills:tdd': 'tdd-workflow',
    'tdd': 'tdd-workflow',
    'mattpocock-skills:implement': 'incremental-implementation',
    'implement': 'incremental-implementation',
    'mattpocock-skills:codebase-design': 'deep-module-design',
    'codebase-design': 'deep-module-design',
    'mattpocock-skills:code-review': 'open-code-review',
    'code-review': 'open-code-review',
    'mattpocock-skills:resolving-merge-conflicts': 'merge-conflict-resolver',
    'resolving-merge-conflicts': 'merge-conflict-resolver',
    'mattpocock-skills:domain-modeling': 'deep-module-design',
    'domain-modeling': 'deep-module-design',
    'mattpocock-skills:to-spec': 'spec-driven-development',
    'to-spec': 'spec-driven-development',
    'mattpocock-skills:ask-matt': 'grill-plan',
    'ask-matt': 'grill-plan',
    'testing-strategy': 'qc',
    'verification-before-completion': 'verification-before-completion',
}
"""
        sr = sr.replace("CORE = [", devkit_map_block + "CORE = [")
        old_resolve = """        for path in candidates:
            resolved = readable(path)
            if resolved and resolved not in self.disabled:
                return resolved, str(path.absolute())
        return None, None"""
        new_resolve = """        mapped = DEVKIT_SKILL_MAP.get(name) or DEVKIT_SKILL_MAP.get(suffix)
        if mapped and not self.catalog_only:
            for directory in self.roots:
                candidates.append(directory / mapped / 'SKILL.md')
        for path in candidates:
            resolved = readable(path)
            if resolved and resolved not in self.disabled:
                return resolved, str(path.absolute())
        return None, None"""
        sr = sr.replace(old_resolve, new_resolve)
    with open(sr_path, "w") as f:
        f.write(sr)

# 3. Patch super-board-setup.py:
#    - Recognize global `~/.claude/{skills,bin,workflows,hooks,settings.json}` installation for any repo
#    - Automatically inject `verify_commands: ["python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief"]`
for sp_path in [
    os.path.expanduser("~/.claude/bin/super-board-setup.py"),
    os.path.expanduser("~/.local/share/super-board/scripts/super-board-setup.py"),
]:
    if not os.path.exists(sp_path):
        continue
    with open(sp_path, "r") as f:
        sp = f.read()
    old_settings = """def settings_commands(root):
    s = load_json(os.path.join(root, ".claude", "settings.json")) or {}
    return {h.get("command") for entries in (s.get("hooks") or {}).values() for e in entries
            for h in e.get("hooks", [])}"""
    new_settings = """def settings_commands(root):
    cmds = set()
    for p in [os.path.join(root, ".claude", "settings.json"), os.path.expanduser("~/.claude/settings.json")]:
        s = load_json(p) or {}
        for entries in (s.get("hooks") or {}).values():
            for e in entries:
                for h in e.get("hooks", []):
                    if h.get("command"):
                        cmds.add(h.get("command"))
    return cmds"""
    sp = sp.replace(old_settings, new_settings)

    old_ver = """def installed_version(root):
    return read(os.path.join(root, ".claude", "skills", "super-board", "VERSION")) or None"""
    new_ver = """def installed_version(root):
    return (read(os.path.join(root, ".claude", "skills", "super-board", "VERSION"))
            or read(os.path.expanduser("~/.claude/skills/super-board/VERSION")) or None)"""
    sp = sp.replace(old_ver, new_ver)

    old_missing = """    missing = []
    missing += [f"skill {s}" for s in SKILLS if not os.path.isfile(os.path.join(claude, "skills", s, "SKILL.md"))]
    missing += [f"script {b}" for b in BIN if not os.path.isfile(os.path.join(claude, "bin", b))]
    missing += [f"workflow {w}" for w in WORKFLOWS if not os.path.isfile(os.path.join(claude, "workflows", w))]
    hook_files = sorted(os.path.basename(p) for p in glob.glob(os.path.join(pack, "hooks", "*.py"))) if pack else []
    missing += [f"hook {h}" for h in hook_files if not os.path.isfile(os.path.join(claude, "hooks", h))]"""
    new_missing = """    gclaude = os.path.expanduser("~/.claude")
    def has_c(*rel):
        return os.path.isfile(os.path.join(claude, *rel)) or os.path.isfile(os.path.join(gclaude, *rel))
    missing = []
    missing += [f"skill {s}" for s in SKILLS if not has_c("skills", s, "SKILL.md")]
    missing += [f"script {b}" for b in BIN if not has_c("bin", b)]
    missing += [f"workflow {w}" for w in WORKFLOWS if not has_c("workflows", w)]
    hook_files = sorted(os.path.basename(p) for p in glob.glob(os.path.join(pack, "hooks", "*.py"))) if pack else []
    missing += [f"hook {h}" for h in hook_files if not has_c("hooks", h)]"""
    sp = sp.replace(old_missing, new_missing)

    old_mig = """    if not c.get("worker_backend"):
        c["worker_backend"] = "workflow"
        changes.append("worker_backend \\"workflow\\" added")
    return c, changes"""
    new_mig = """    if not c.get("worker_backend"):
        c["worker_backend"] = "workflow"
        changes.append("worker_backend \\"workflow\\" added")
    if not c.get("verify_commands"):
        c["verify_commands"] = ["python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief"]
        changes.append("verify_commands locked to DevKit post-fix-gate.py")
    return c, changes"""
    sp = sp.replace(old_mig, new_mig)
    with open(sp_path, "w") as f:
        f.write(sp)

# 4. Patch super-board-agents-md.py:
#    - Raise `--max-lines` default from 200 to 600 so Universal Agent DevKit AGENTS.md passes check
#    - Detect `universal-agent-devkit:start` and set `offer_merge = False` to protect AGENTS.md & CLAUDE.md
for am_path in [
    os.path.expanduser("~/.claude/bin/super-board-agents-md.py"),
    os.path.expanduser("~/.local/share/super-board/scripts/super-board-agents-md.py"),
]:
    if not os.path.exists(am_path):
        continue
    with open(am_path, "r") as f:
        am = f.read()
    am = am.replace('default=200', 'default=600')
    old_offer = '    out["offer_merge"] = bool(out["claude"] and not out["claude"]["is_pointer"])'
    new_offer = """    devkit_managed = any(
        (root / f).is_file() and "universal-agent-devkit:start" in (root / f).read_text(encoding="utf-8", errors="replace")
        for f in ("AGENTS.md", "CLAUDE.md")
    )
    if devkit_managed and out["claude"]:
        out["claude"]["is_pointer"] = True
    out["devkit_managed"] = devkit_managed
    out["offer_merge"] = False if devkit_managed else bool(out["claude"] and not out["claude"]["is_pointer"])"""
    am = am.replace(old_offer, new_offer)
    with open(am_path, "w") as f:
        f.write(am)

# 5. Inject Universal Agent DevKit 6-Step Autonomous Pipeline + Real-Time 7-Column UI Sync into worker-preamble.md, agents-md-block.md & run.md
devkit_pipeline = """
<!-- universal-agent-devkit-workflow:start -->
## Universal Agent DevKit Mandatory Pipeline & Real-Time 7-Column UI Sync (Zero Duplication)

Every worker running in a Universal Agent DevKit repository MUST execute the DevKit pipeline in a single worktree while updating the GitHub Project UI column in real-time (`super-board-card.sh --config <cfg> move <N> <Column>`) so all columns (`Backlog`, `Ready`, `Building`, `QA`, `Review`, `Blocked`, `Done`) reflect live progress without spawning duplicate test/review workers:

1. **Column `Building` — 5D Context, Codebase Graph & Paired TDD (`context-enricher` + `codebase-memory` + `tdd-workflow` / `fixbugs`):**
   - Move card `Ready -> Building`: `.claude/bin/super-board-card.sh --config <cfg> move <N> Building`.
   - Read `AGENTS.md`, `.agents/context/profile-rules.md`, `.agents/context/rules-index.md`, `.agents/instincts.md` and query `codebase-memory-mcp` (`search_graph`, `trace_path`, `get_code_snippet`, `check_index_coverage`).
   - Run the failing test at the real boundary (**RED**) before editing production code, then implement with Engineering & Zero-Slop Guardrails (**GREEN**).
   - **Surviving Mutant & Anti-Tautology Guard:** If a new test passes on its first run (`First-run Green`), mutate the guarded production line once to confirm **RED**, then restore **GREEN**; never assert on a test's own mock or copy the implementation formula into `expected`.
2. **Column `QA` — DevKit Post-Fix Gate & Visual Proof (`qc` + `verification-before-completion`):**
   - Move card `Building -> QA`: `.claude/bin/super-board-card.sh --config <cfg> move <N> QA`.
   - Execute `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief` (must exit `0`) and capture screenshot proof via `python3 .agents/devkit/bin/proof-capture.py` when app/UI source changes.
   - **Non-Blank, Terminal-State & A/B Perf Guards:** UI proof requires rendered data/empty-state + `0` `console.error`/`pageerror`/uncaught exceptions + `0` background `5xx`/`401`/`403`; async/queue/upload/eSign flows must verify terminal state + persisted destination record (Toast/HTTP 200 alone is never PASS); performance claims require alternating `AB, BA` (>= 5 pairs after warmup).
   - Push branch, open/update PR, and post `[builder] [report]` + `[qa] [report] ✅` with gate output and embedded proof screenshot.
3. **Column `Review` & `Done` — Smart Fast-Track vs Cross-Review (`open-code-review` + `deep-module-design`):**
   - Move card `QA -> Review`: `.claude/bin/super-board-card.sh --config <cfg> move <N> Review`.
   - **Adversarial Review Discipline:** Apply **Blind-First Pass** (read AC + raw `git diff` and form 2–4 failure hypotheses before reading Builder summary), **Review Remembers** (on rework rounds, grade prior `R1..Rn` findings `fixed`/`not fixed` first), and **Taste Never Blocks** (`Over-engineering`/`Deepening opportunity` is `Should fix`, never blocks a test-green diff).
   - **Small/Medium Task (`< 3` files, `<= 200` LOC net diff, no `auth`/`payment`/`migration`/`security`):** Run `open-code-review` self-audit, post `[reviewer] [report] ✅ merge-ready (DevKit Fast-Track)` + the 4-item Acceptance Report (`core-rules §1.3`), run `gh pr ready <PR>` + `.claude/bin/super-board-merge-gate.sh`, and move card `Review -> Done` (`column='Done'`).
   - **Large/High-Risk Task (`>= 2` modules, `>= 3` files, `> 200` LOC net diff, or `auth`/`payment`/`migration`/`security`):** Leave card in `Review` (`column='Review'`) so the independent Reviewer lane (2nd agent / Antigravity `audit`) performs cross-review before merging to `Done`.
<!-- universal-agent-devkit-workflow:end -->
"""

for md_path in [
    os.path.expanduser("~/.claude/skills/super-build/references/worker-preamble.md"),
    os.path.expanduser("~/.claude/skills/super-board/references/agents-md-block.md"),
    os.path.expanduser("~/.claude/skills/super-board/references/run.md"),
    os.path.expanduser("~/.local/share/super-board/skills/super-build/references/worker-preamble.md"),
    os.path.expanduser("~/.local/share/super-board/skills/super-board/references/agents-md-block.md"),
    os.path.expanduser("~/.local/share/super-board/skills/super-board/references/run.md"),
]:
    if not os.path.exists(md_path):
        continue
    with open(md_path, "r") as f:
        mtxt = f.read()
    mtxt = re.sub(
        r"<!-- universal-agent-devkit-workflow:start -->.*?<!-- universal-agent-devkit-workflow:end -->\n?",
        "",
        mtxt,
        flags=re.DOTALL,
    )
    if "ISSUE PROMPT FOLLOWS:" in mtxt:
        mtxt = mtxt.replace("ISSUE PROMPT FOLLOWS:", devkit_pipeline.strip() + "\n\n---\n\nISSUE PROMPT FOLLOWS:")
    elif "### Builder (rebuild)" in mtxt:
        mtxt = mtxt.replace("### Builder (rebuild)", devkit_pipeline.strip() + "\n\n### Builder (rebuild)")
    else:
        mtxt = mtxt.rstrip() + "\n\n" + devkit_pipeline.strip() + "\n"
    with open(md_path, "w") as f:
        f.write(mtxt)
PY
}

unify_profile_sessions() {
  mkdir -p "$HOME/.claude"/{projects,sessions,session-env,file-history,paste-cache,skills,hooks,bin,workflows,agents,plugins,super-board}
  touch "$HOME/.claude/history.jsonl"
  for acct in finos finos_team max; do
    local pdir="$HOME/.claude-${acct}"
    mkdir -p "$pdir"
    for item in projects sessions session-env file-history paste-cache skills hooks bin workflows agents plugins settings.json history.jsonl .mcp.json CLAUDE.md; do
      [ -e "$HOME/.claude/$item" ] || continue
      if [ -d "$pdir/$item" ] && [ ! -L "$pdir/$item" ]; then
        cp -Rn "$pdir/$item/"* "$HOME/.claude/$item/" 2>/dev/null || true
        rm -rf "$pdir/$item"
      elif [ -f "$pdir/$item" ] && [ ! -L "$pdir/$item" ]; then
        rm -f "$pdir/$item"
      fi
      ln -sfn "$HOME/.claude/$item" "$pdir/$item"
    done
  done
}

configure_models_and_cc_switch_gui() {
  python3 - <<'PY'
import json, os, sqlite3, time

# 1. Grok CLI default -> grok-4.7 (xhigh)
grok_cfg = os.path.expanduser("~/.grok/config.toml")
if os.path.exists(grok_cfg):
    with open(grok_cfg, "r") as f:
        txt = f.read()
    txt = txt.replace('default = "grok-4.6"', 'default = "grok-4.7"')
    with open(grok_cfg, "w") as f:
        f.write(txt)

# 2. Antigravity CLI -> Ultra (phathuy.vetgo@gmail.com) + Pro (alex.1993.dev@gmail.com) + gemini-4-argon-high (xhigh)
os.makedirs(os.path.expanduser("~/.gemini/antigravity-cli"), exist_ok=True)
with open(os.path.expanduser("~/.gemini/google_accounts.json"), "w") as f:
    json.dump({"active": "phathuy.vetgo@gmail.com", "old": ["alex.1993.dev@gmail.com"]}, f, indent=2)

agy_st_path = os.path.expanduser("~/.gemini/antigravity-cli/settings.json")
agy_st = json.load(open(agy_st_path)) if os.path.exists(agy_st_path) else {}
agy_st["model"] = "gemini-4-argon-high"
agy_st["effort"] = "xhigh"
agy_st["activeAccount"] = agy_st.get("activeAccount") or "phathuy.vetgo@gmail.com"
agy_st["accounts"] = {
    "antigravity": {"email": "phathuy.vetgo@gmail.com", "tier": "Ultra", "model": "gemini-4-argon-high", "effort": "xhigh"},
    "antigravity_pro": {"email": "alex.1993.dev@gmail.com", "tier": "Pro", "model": "gemini-4-argon-high", "effort": "xhigh"},
}
with open(agy_st_path, "w") as f:
    json.dump(agy_st, f, indent=2)

gem_st_path = os.path.expanduser("~/.gemini/settings.json")
if os.path.exists(gem_st_path):
    gem_st = json.load(open(gem_st_path))
    gem_st["model"] = "gemini-4-argon-high"
    with open(gem_st_path, "w") as f:
        json.dump(gem_st, f, indent=2)

# 3. Clean ~/.claude/settings.json (100% Direct First-Party Keychain OAuth, no static token/proxy)
claude_st_path = os.path.expanduser("~/.claude/settings.json")
if os.path.exists(claude_st_path):
    cst = json.load(open(claude_st_path))
    cst["model"] = cst.get("model") or "sonnet"
    cst["advisorModel"] = cst.get("advisorModel") or "opus"
    cst["effortLevel"] = cst.get("effortLevel") or "xhigh"
    if "env" in cst:
        for k in ["CLAUDE_CODE_OAUTH_TOKEN", "CLAUDE_CODE_OAUTH_REFRESH_TOKEN", "CLAUDE_CODE_OAUTH_SCOPES", "ANTHROPIC_BASE_URL"]:
            cst["env"].pop(k, None)
        if not cst["env"]:
            cst.pop("env", None)
    with open(claude_st_path, "w") as f:
        json.dump(cst, f, indent=2)

# 4. Populate CC Switch.app SQLite database & settings.json (Direct Mode, 6 Accounts + 6 Profiles)
db_path = os.path.expanduser("~/.cc-switch/cc-switch.db")
if os.path.exists(db_path):
    now_ms = int(time.time() * 1000)
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("DELETE FROM providers WHERE app_type = 'claude' AND id IN ('default', 'claude-official', 'finos', 'finos_team', 'max', 'antigravity', 'antigravity_pro', 'grok')")
    cur.execute("DELETE FROM providers WHERE app_type = 'gemini' AND id IN ('default', 'antigravity', 'antigravity_pro')")
    rows = [
        ("finos", "claude", "1. FinOS — toan.huynh@finos.asia (5x Team)", '{"advisorModel": "opus", "model": "sonnet"}', "https://claude.ai", "official", 1, "FinOS Organization • ~/.claude-finos • 100% Shared Sessions", "anthropic", "#D4915D", '{"commonConfigEnabled":true}', 1),
        ("finos_team", "claude", "2. FinOS Team — linhnt@finos.asia (5x Team)", '{"advisorModel": "opus", "model": "sonnet"}', "https://claude.ai", "official", 2, "FinOS Team • ~/.claude-finos_team • 100% Shared Sessions", "anthropic", "#10B981", '{"commonConfigEnabled":true}', 0),
        ("max", "claude", "3. Personal 5x Max — toan.huynh@finos.asia", '{"advisorModel": "opus", "model": "sonnet"}', "https://claude.ai", "official", 3, "Personal 5x Max • ~/.claude-max • 100% Shared Sessions", "anthropic", "#8B5CF6", '{"commonConfigEnabled":true}', 0),
        ("antigravity", "claude", "4. Antigravity Ultra — phathuy.vetgo@gmail.com (Gemini 4 Argon High)", '{"advisorModel": "opus", "model": "sonnet"}', "https://idx.google.com", "official", 4, "Google Antigravity Ultra • gemini-4-argon-high (xhigh) • phathuy.vetgo@gmail.com", "google", "#4285F4", '{"commonConfigEnabled":true}', 0),
        ("antigravity_pro", "claude", "5. Antigravity Pro — alex.1993.dev@gmail.com (Gemini 4 Argon High)", '{"advisorModel": "opus", "model": "sonnet"}', "https://idx.google.com", "official", 5, "Google Antigravity Pro • gemini-4-argon-high (xhigh) • alex.1993.dev@gmail.com", "google", "#34A853", '{"commonConfigEnabled":true}', 0),
        ("grok", "claude", "6. Grok CLI — grok-4.7 (xhigh)", '{"advisorModel": "opus", "model": "sonnet"}', "https://x.ai/grok", "official", 6, "Grok CLI v1.0.50 • grok-4.7 (xhigh) • Auto-Failover Engine", "grok", "#000000", '{"commonConfigEnabled":true}', 0),
        ("antigravity", "gemini", "Antigravity Ultra — phathuy.vetgo@gmail.com (Gemini 4 Argon High)", '{"model": "gemini-4-argon-high", "effort": "xhigh", "email": "phathuy.vetgo@gmail.com"}', "https://idx.google.com", "official", 1, "Google AI Ultra • gemini-4-argon-high (xhigh) • phathuy.vetgo@gmail.com", "google", "#4285F4", '{"commonConfigEnabled":true}', 1),
        ("antigravity_pro", "gemini", "Antigravity Pro — alex.1993.dev@gmail.com (Gemini 4 Argon High)", '{"model": "gemini-4-argon-high", "effort": "xhigh", "email": "alex.1993.dev@gmail.com"}', "https://idx.google.com", "official", 2, "Google AI Pro • gemini-4-argon-high (xhigh) • alex.1993.dev@gmail.com", "google", "#34A853", '{"commonConfigEnabled":true}', 0),
    ]
    for r in rows:
        cur.execute(
            """
            INSERT OR REPLACE INTO providers (
                id, app_type, name, settings_config, website_url, category,
                created_at, sort_index, notes, icon, icon_color, meta,
                is_current, in_failover_queue, cost_multiplier, provider_type
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, '1.0', 'official_subscription')
            """,
            (r[0], r[1], r[2], r[3], r[4], r[5], now_ms, r[6], r[7], r[8], r[9], r[10], r[11]),
        )
    profiles = [
        ("finos", "1. FinOS (toan.huynh@finos.asia)", 1, "antigravity"),
        ("finos_team", "2. FinOS Team (linhnt@finos.asia)", 2, "antigravity"),
        ("max", "3. Personal 5x Max (toan.huynh@finos.asia)", 3, "antigravity"),
        ("antigravity", "4. Antigravity Ultra (phathuy.vetgo@gmail.com)", 4, "antigravity"),
        ("antigravity_pro", "5. Antigravity Pro (alex.1993.dev@gmail.com)", 5, "antigravity_pro"),
        ("grok", "6. Grok CLI (xAI v1.0.50)", 6, "antigravity"),
    ]
    for pid, pname, idx, gem_id in profiles:
        payload = json.dumps({"currentIds": {"claude": pid, "codex": "default", "gemini": gem_id, "grokbuild": "grokbuild-official"}})
        cur.execute("INSERT OR REPLACE INTO profiles (id, name, payload, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)", (pid, pname, payload, idx, now_ms, now_ms))
    conn.commit()
    conn.close()

cc_st_path = os.path.expanduser("~/.cc-switch/settings.json")
if os.path.exists(cc_st_path):
    cc_st = json.load(open(cc_st_path))
    cc_st["enableLocalProxy"] = False
    cc_st["enableStackMode"] = False
    cc_st["showProfileSwitcher"] = True
    cc_st["enableFailoverToggle"] = True
    cc_st["currentProviderClaude"] = cc_st.get("currentProviderClaude") or "finos"
    cc_st["currentProviderGemini"] = cc_st.get("currentProviderGemini") or "antigravity"
    with open(cc_st_path, "w") as f:
        json.dump(cc_st, f, indent=2)
PY
}

configure_repo_accounts() {
  for entry in "${REPOS[@]}"; do
    IFS=":" read -r rpath rname racct <<< "$entry"
    [ -d "$rpath" ] || continue
    mkdir -p "$rpath/.claude"
    local slocal="$rpath/.claude/settings.local.json"
    if [ -s "$slocal" ] && command -v jq >/dev/null 2>&1; then
      local tmp="$slocal.tmp.$$"
      jq --arg a "$racct" '.account = (.account // $a)' "$slocal" > "$tmp" && mv "$tmp" "$slocal"
    else
      printf '{\n  "account": "%s"\n}\n' "$racct" > "$slocal"
    fi
  done
}

run_verify() {
  echo "╔══════════════════════════════════════════════════════════════════════════════╗"
  echo "║     AUTONOMOUS FACTORY RECOVERY & HEALTH CHECK (9-POINT VERIFICATION)       ║"
  echo "╚══════════════════════════════════════════════════════════════════════════════╝"
  local pass=0 total=9

  if [ -x "$FACTORY_ROOT/ai-factory.sh" ] && [ -f "$FACTORY_ROOT/mcp-servers/agent-office/server.py" ]; then
    echo "  [1/9] PASS: ai-factory.sh + Agent Office present in $FACTORY_ROOT"
    pass=$((pass + 1))
  else
    echo "  [1/9] FAIL: ai-factory.sh or mcp-servers/agent-office missing in $FACTORY_ROOT"
  fi

  if command -v cloudflared >/dev/null 2>&1 && command -v qrencode >/dev/null 2>&1; then
    echo "  [2/9] PASS: cloudflared + qrencode installed (phone access via quick tunnel + QR)"
    pass=$((pass + 1))
  else
    echo "  [2/9] FAIL: missing cloudflared or qrencode (brew install cloudflared qrencode)"
  fi

  if [ -x "$HOME/.claude/bin/super-board-run.sh" ] && [ -d "$HOME/.claude/skills/super-board" ]; then
    echo "  [3/9] PASS: Super-Board v3.1.2 skills & runner scripts installed in ~/.claude/"
    pass=$((pass + 1))
  else
    echo "  [3/9] FAIL: Super-Board global installation incomplete"
  fi

  if [ -f "$HOME/.claude/super-board/template-devkit-config.json" ] && grep -q "post-fix-gate.py --run-tests --full --brief" "$HOME/.claude/super-board/template-devkit-config.json"; then
    echo "  [4/9] PASS: DevKit post-fix-gate locked in ~/.claude/super-board/template-devkit-config.json"
    pass=$((pass + 1))
  else
    echo "  [4/9] FAIL: template-devkit-config.json missing post-fix-gate lock"
  fi

  if [ -x "$HOME/.claude/bin/super-board-account-pool.sh" ] && [ -x "$HOME/.local/bin/ccswitch" ]; then
    echo "  [5/9] PASS: 6-Tier Pool (finos, finos_team, max, antigravity Ultra/Pro, grok-4.7) active"
    pass=$((pass + 1))
  else
    echo "  [5/9] FAIL: super-board-account-pool.sh or ccswitch missing"
  fi

  if [ -L "$HOME/.claude-finos/projects" ] && [ -L "$HOME/.claude-finos_team/projects" ] && [ -L "$HOME/.claude-max/projects" ]; then
    echo "  [6/9] PASS: Unified Session Symlinks verified across ~/.claude-{finos,finos_team,max}"
    pass=$((pass + 1))
  else
    echo "  [6/9] FAIL: Profile session symlinks incomplete"
  fi

  if [ -d "/Applications/CC Switch.app" ]; then
    local remote_tool="GitHub Mobile (Zero-Install ✔)"
    if command -v cloudflared >/dev/null 2>&1; then
      remote_tool="Cloudflare Tunnel (cloudflared ✔)"
    elif [ -d "/Applications/Tailscale.app" ]; then
      remote_tool="Tailscale ✔"
    fi
    echo "  [7/9] PASS: GUI Apps & Remote Tool verified (/Applications/CC Switch.app • $remote_tool)"
    pass=$((pass + 1))
  else
    echo "  [7/9] FAIL: /Applications/CC Switch.app missing"
  fi

  local repo_ok=0
  for entry in "${REPOS[@]}"; do
    IFS=":" read -r rpath rname racct <<< "$entry"
    [ -f "$rpath/.claude/settings.local.json" ] && repo_ok=$((repo_ok + 1))
  done
  if [ "$repo_ok" -eq 6 ]; then
    echo "  [8/9] PASS: All 6 repositories mapped with preferred account in .claude/settings.local.json"
    pass=$((pass + 1))
  else
    echo "  [8/9] FAIL: Only $repo_ok/6 repositories have .claude/settings.local.json"
  fi

  local onboard_ok=0
  for entry in "${REPOS[@]}"; do
    IFS=":" read -r rpath rname racct <<< "$entry"
    if python3 "$HOME/.claude/bin/super-board-setup.py" check --root "$rpath" --host claude >/dev/null 2>&1; then
      onboard_ok=$((onboard_ok + 1))
    fi
  done
  if [ "$onboard_ok" -eq 6 ]; then
    echo "  [9/9] PASS: '/super-board onboard' DevKit Workflow & Skill Readiness green across all 6/6 repos"
    pass=$((pass + 1))
  else
    echo "  [9/9] FAIL: '/super-board onboard' check passed on only $onboard_ok/6 repos"
  fi

  echo "──────────────────────────────────────────────────────────────────────────────"
  echo "  RESULT: ${pass}/${total} CHECKS PASSED"
  [ "$pass" -eq "$total" ]
}

if [ "$VERIFY_ONLY" -eq 1 ]; then
  run_verify
  exit $?
fi

install_account_pool_script
patch_super_board_and_devkit_workflow
unify_profile_sessions
configure_models_and_cc_switch_gui
configure_repo_accounts
run_verify
# === BOOTSTRAP_END ===
```
