# MCP của 5 repo và dashboard coverage-map: việc còn lại

Cập nhật 2026-10-13. Phiên làm việc đã dừng giữa chừng vì các checkout bị phiên khác giữ và gate hết giờ. File này liệt kê đúng những gì chưa xong, theo thứ tự nên làm.

## 1. Tập MCP yêu cầu cho từng repo (người dùng chốt 13/10)

| Repo | Phải chạy | Không được thêm |
|---|---|---|
| agent-workbench | codebase-memory-mcp, context7, agentmemory | replicant-mcp, play-store |
| GeelyEx2 | codebase-memory-mcp, context7, agentmemory, replicant-mcp | play-store |
| OfficeReader | đủ 5 (thêm replicant-mcp, play-store) | |
| Goods | đủ 5 (cần thêm agentmemory, play-store, replicant-mcp) | |
| Neighbours-From-Hell | đủ 5 (cần thêm play-store, replicant-mcp) | |

`ocr` (Open Code Review) là CLI, không phải MCP. Nó chạy được ở cả 5 repo (`ocr` v1.12.13).
Bảng này cũng nằm trong `universal-agent-devkit/dashboard/collect_rows.py` (`REQUIRED_MCPS`). Đổi yêu cầu thì đổi ở đó rồi chạy lại collector.

## 2. Trạng thái từng repo (đo 13/10 bằng `claude mcp list`, cấu hình `~/.claude-max`)

| Repo | `.mcp.json` | Còn thiếu |
|---|---|---|
| agent-workbench | đúng (3 server), đã vào `main` | không |
| OfficeReader | đủ 7 server, kết nối được | không |
| GeelyEx2 | còn khai báo play-store do nhầm | gỡ play-store (việc 3.1), bật play-store không cần |
| Neighbours-From-Hell | đủ 5 server, đã vào `master` | xem việc 3.3 |
| Goods | thiếu replicant-mcp, play-store chạy bằng `uvx` | việc 3.2 |

Lưu ý khi đọc kết quả: trạng thái duyệt MCP gắn với từng thư mục cấu hình Claude. Với `~/.claude` thì cả 5 repo đều ra "Pending approval". Cách chắc nhất là mở `claude` trong từng repo rồi chạy `/mcp`.

## 3. Việc còn lại

### 3.1 GeelyEx2: gỡ play-store khỏi `.mcp.json`
- Worktree `/Volumes/Data/Toan/GeelyEx2-mcpfix` đã xóa key `play-store` khỏi `.mcp.json`, chưa commit. Gate chạy hai lần đều REJECT vì `REG-CAR-01` (~2000 test JVM của CarConnect) hết giờ; lớp kiểm tĩnh đạt. Đây là thay đổi một khối JSON, không chạm mã mà test kiểm.
- Làm: commit `.mcp.json` trong worktree, `agent-kit worktree finish`, rồi chạy gate một mình khi máy rảnh.

### 3.2 Goods: thêm replicant-mcp, đổi play-store sang binary `.venv`, bật lại MCP
- Worktree `/Volumes/Data/Toan/Game/Goods-Triple-Shelf-Match-3D-mcp` (commit `4405395`) đã làm phần `.mcp.json`: thêm `replicant-mcp`, đổi `play-store` từ `uvx` sang `/Volumes/Data/Toan/agent-workbench/mcp-servers/play-store-mcp/.venv/bin/play-store-mcp` (uvx chạy hơn 40 giây vẫn chưa trả lời, có thể vượt thời gian chờ MCP). Gate của nó đã PASS (4/4). Chưa gộp vì phiên `e26856b2` giữ repo.
- Làm: `agent-kit worktree finish ../Goods-Triple-Shelf-Match-3D-mcp` khi khóa nhả.
- Sau đó sửa `Goods/.claude/settings.local.json` (file gitignore, ngoài worktree): bỏ `agentmemory` và `play-store` khỏi `disabledMcpjsonServers`, thêm `agentmemory`, `play-store`, `replicant-mcp` vào `enabledMcpjsonServers`.
- play-store của Goods đã trỏ `GOOGLE_APPLICATION_CREDENTIALS` vào file trong `keystore/` và bật read-only. Không đọc hay commit file đó.

### 3.3 Neighbours-From-Hell và GeelyEx2: bật MCP trong `settings.local.json`
- Neighbours-From-Hell: `enabledMcpjsonServers` cần có `replicant-mcp` và `play-store` (hiện chỉ có 3 server nền).
- GeelyEx2: không cần bật play-store (không yêu cầu).
- Hai file này gitignore và nằm trong checkout đang do phiên khác giữ, nên chưa sửa. Sửa khi khóa nhả, hoặc từ chính phiên của repo đó.

### 3.4 Xác nhận kết nối
- Sau 3.1 đến 3.3, chạy `claude mcp list` trong từng repo (cả với `~/.claude` lẫn cấu hình bạn thực dùng) và ghi kết quả. Hiện mới có bằng chứng "server khởi động và trả lời"; chưa có ai gọi thử một công cụ.
- play-store ở workbench, Geely, Neighbours-From-Hell không có credentials thật: chỉ khởi động được, chưa dùng được thao tác Google Play.

### 3.5 Push
- Chưa push repo nào. Neighbours-From-Hell không có remote. Với mỗi repo: gate `--full` exit 0 trên nội dung sẽ push, `git pull` nếu origin đã đổi, rồi `git push origin <nhánh>`.

## 4. Dashboard coverage-map

Nguồn: `universal-agent-devkit/dashboard/` (`collect_rows.py`, `workflow-map.page.html`, `dash_shim.js`, `render_smoke.js`, `checks.json`, `workflow-map.html`).
Mở thẳng `workflow-map.html` trong trình duyệt. Bản artifact (riêng tư): https://claude.ai/artifact/9jipizCiyhWsTv6QL3goZE.

Còn lại:
- Làm mới dữ liệu sau khi 3.1 và 3.2 vào `main`: `python3 universal-agent-devkit/dashboard/collect_rows.py` (ghi lại `checks.json` và `workflow-map.html`), commit, rồi tải `checks.json` lên artifact và cập nhật tài liệu `datasets/checks`.
- Chạy `node universal-agent-devkit/dashboard/render_smoke.js` sau mỗi lần sửa trang (không cần trình duyệt).
- Chưa bấm thử trong trình duyệt thật: giao diện mới chỉ được xem qua bản dựng tĩnh (Quick Look). Brave headless treo, Chrome không có trên máy.
- Quy trình trên trang (8 công đoạn, thành phần của từng công đoạn) được định nghĩa tay trong `PHASES`/`FLOW` của `collect_rows.py`, dựa theo AGENTS.md ("Every prompt") và các hook Stop. Nhãn tiếng Việt cho hook và skill (`HOOK_VI`, `SKILL_VI`) tôi dịch từ tên, từ phần đầu file hook và từ thông báo hook, chưa đối chiếu từng file. Khi kit đổi hook, cập nhật các bảng này.
- Snapshot chỉ phản ánh lúc chạy collector; chưa có bước tự làm mới.

## 5. Quyết định cần người dùng

- **ocr không được hook nào chạy.** Skill `open-code-review` và CLI `ocr` có ở cả 5 repo, nhưng chỉ chạy khi agent tự chọn; `review_gate.sh` chỉ chấp nhận skill đó làm bằng chứng review, `enrich_context.py` chỉ gợi ý khi prompt thuộc loại review. Nếu muốn review bằng ocr không bị bỏ sót, cần quyết định có thêm một hook chạy `ocr delegate preview` ở bước Review hay không. Hiện chưa làm.
- **Gate của kit chạy sát giới hạn 900 giây.** `REG-DK-ALL-01` (cả bộ test kit) và `REG-CAR-01` (Geely) hết giờ khi máy tải, làm REJECT cả những thay đổi chỉ động vào JSON. Đã kiểm chứng ngày 13/10: ngay cả một diff chỉ có một file markdown (chính file kế hoạch này) cũng bị `REG-DK-ALL-01` hết giờ ở 900,15 giây, trong khi các test khác của cùng lần gate đều đạt. Vậy nguyên nhân là bộ test kit chạy quá giới hạn của gate, không phải do nội dung thay đổi. Cần quyết định có nới giới hạn, tách bộ test, hay chạy gate theo hàng đợi. Chưa đổi gì.
- **Commit tự động "wip".** Khi phiên kết thúc mà worktree còn thay đổi, DevKit tự gộp chúng vào `main` dưới dạng commit `wip(...)` không qua gate (đã xảy ra với `4de90cb` dashboard và `9a41b19` mcpfix). Nội dung vẫn đúng nhưng chưa có gate PASS cho chúng.

## 6. Dọn dẹp

- Thư mục rỗng `/Volumes/Data/Toan/agent-workbench-dashboard` (20 KB, đã gỡ khỏi `git worktree list`): hook chặn xóa đệ quy ngoài project. Người dùng xóa tay nếu muốn.
- Worktree `agent-workbench-dot30b` và `agent-workbench-sprite-forge` thuộc phiên khác, không đụng.
- Memory về bảng MCP theo repo chưa ghi vì `.agents/local/memory/` nằm trong checkout bị khóa. Nội dung nằm ở mục 1 của file này.

## 7. Đang kẹt khi đóng phiên (13/10, cuối phiên)

Ba worktree đã commit nhưng chưa vào nhánh chính, vì checkout của từng repo đang do một phiên khác giữ (`agent-kit worktree finish` bị chặn):

| Worktree | Commit | Repo giữ bởi phiên | Việc cần làm |
|---|---|---|---|
| `/Volumes/Data/Toan/agent-workbench-plan` | `2e3bd42` (file này) | `c01ac57e` | `agent-kit worktree finish /Volumes/Data/Toan/agent-workbench-plan` từ `/Volumes/Data/Toan/agent-workbench` |
| `/Volumes/Data/Toan/GeelyEx2-mcpfix` | `f0a2c39f2` (gỡ play-store) | `0b9c3540` | `agent-kit worktree finish ../GeelyEx2-mcpfix` từ `/Volumes/Data/Toan/GeelyEx2` |
| `/Volumes/Data/Toan/Game/Goods-Triple-Shelf-Match-3D-mcp` | `4405395` (replicant-mcp, play-store qua `.venv`) | `fb81febe` | `agent-kit worktree finish ../Goods-Triple-Shelf-Match-3D-mcp` từ `/Volumes/Data/Toan/Game/Goods-Triple-Shelf-Match-3D` |

Hook Stop của phiên giữ hoặc phiên sau cũng tự gộp chúng. Cần biết:
- Chưa commit nào trong ba commit này có gate `--full` exit 0. Gate của file này ra REJECT vì `REG-DK-ALL-01` hết giờ (900,15 giây) dù chỉ có một file markdown; gate của Geely hết giờ ở `REG-CAR-01`. Gate của Goods đã PASS (4/4) từ trước.
- Khi gộp tự động, DevKit có thể tạo commit `wip(...)` thay vì giữ nguyên các commit trên.
- Sau khi gộp, làm tiếp từ mục 3 (bật MCP trong `settings.local.json`, `claude mcp list`, push) và mục 4 (làm mới dữ liệu dashboard).

Các việc chưa làm hoặc chưa kiểm chứng tại thời điểm đóng phiên:
- Bật MCP trong `settings.local.json` ở Goods, Neighbours-From-Hell (mục 3.2 và 3.3).
- `claude mcp list` sau khi các thay đổi vào nhánh chính (mục 3.4).
- Push mọi repo (mục 3.5).
- Làm mới `checks.json` và `workflow-map.html` rồi cập nhật artifact (mục 4).
- Bấm thử `workflow-map.html` trong trình duyệt thật (mục 4).
- Hai quyết định ở mục 5 (hook chạy ocr; giới hạn 900 giây của gate).
- Thư mục rỗng `/Volumes/Data/Toan/agent-workbench-dashboard` cần xóa tay (mục 6).
