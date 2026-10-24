# Agent Office

Xưởng 3D thay cho board GitHub Project của ToanMobile (project 1, view 2). Mỗi hàng là một repo, mỗi cột là một trạng thái trên board. Agent ngồi ở bàn của cột mình đang làm, thẻ đang làm nằm trên bàn, bóng thoại cho biết agent vừa nói gì hoặc vừa chạy lệnh nào. Mọi thao tác sửa đều ghi thẳng lên GitHub Project, nên runner super-board thấy ngay.

## Cài và chạy

```bash
cd /Volumes/Data/Toan/agent-workbench/mcp-servers
unzip ~/Downloads/agent-office.zip
cd agent-office
gh auth refresh -s project      # một lần: cho gh quyền đọc và sửa Project
python3 server.py --open        # mở http://127.0.0.1:4317
```

Trước khi dùng thật, chạy `python3 server.py --check`. Lệnh này kiểm tra gh, quyền project, Project và các cột của nó, transcript Claude Code, đường dẫn từng repo và log runner, rồi báo chỗ nào còn thiếu.

Muốn xem thử trước mà không đụng tới GitHub: `python3 server.py --demo --open`. Ở chế độ demo, mọi sửa đổi chỉ nằm trong bộ nhớ.

## Tự chạy khi đăng nhập

```bash
./install-autostart.sh      # macOS tự bật server mỗi lần đăng nhập, tự chạy lại nếu bị tắt
./uninstall-autostart.sh    # gỡ
```

Log nằm ở `~/.agent-office/server.log`. Sau khi cài, chỉ cần mở http://127.0.0.1:4317. Nếu đổi `config.json`, chạy lại `./install-autostart.sh` để server đọc cấu hình mới.

Chỉ cần Python 3.8+ có sẵn trên macOS và GitHub CLI (`gh`). Three.js đi kèm trong `web/vendor`, nên chạy được cả khi không có mạng (lúc đó dùng font hệ thống).

## Dùng thay board GitHub

- **Chuyển cột:** kéo thẻ trong xưởng 3D sang cột khác, hoặc kéo trong "Dạng bảng", hoặc bấm vào thẻ rồi chọn cột ở bảng chi tiết.
- **Thêm việc:** nút "Thêm việc" tạo issue mới trong repo đã chọn, gắn vào Project ở cột bạn chọn. Chọn "Bản nháp" thì chỉ tạo thẻ nháp trên Project.
- **Các trường khác:** đổi ngay trong bảng chi tiết của thẻ, ví dụ Priority hay Size (mọi trường dạng chọn của Project).
- **Bình luận lên issue:** gõ trong bảng chi tiết, agent đọc được ở lần nhận thẻ sau.
- **Lưu trữ thẻ khỏi Project:** issue gốc trên repo vẫn còn.
- **Dạng bảng:** kanban 2D, lọc theo repo, tìm theo số hoặc tên.

Đồng bộ hai chiều: server đọc lại Project mỗi 30 giây và ngay sau mỗi lần bạn sửa. Thay đổi do runner hoặc do người khác làm trên GitHub sẽ hiện lại trong vòng 30 giây.

## Đọc tình trạng

- **Nhãn repo bên trái mỗi hàng:**
  - Xanh lá: "Đang làm", kèm số agent và các thẻ.
  - Cam: "Chờ việc", runner vẫn chạy nhưng chưa có thẻ.
  - Repo đã dừng hoặc không có runner thì không có nhãn: cả hàng tối lại, thẻ chuyển xám, trên sàn ghi "<tên repo>: runner đang dừng". Nhãn hiện lại khi runner chờ bạn. Mở repo đó bằng "Danh sách repo" (phím R).
  - Đỏ: "Mất tín hiệu", quá 5 phút không có tick.
- **Agent đang làm** có vòng sáng xanh dưới chân và bóng thoại viền xanh. Bấm vào bóng thoại để xem chi tiết.
- **Khi phóng to vào một hàng:** bàn trống ghi "Build rảnh", agent đang nghỉ ghi "Nghỉ, 12 phút".

## Khi nhiều agent cùng làm một cột

Mỗi ô (một repo × một cột) dựng tối đa 3 bàn cỡ thường. Từ 4 agent trở lên, bàn xếp thành lưới 3 x 3 nhỏ hơn (tối đa 9, phần dư hiện "+N agent nữa"). Thay vì từng bóng thoại, ô có một bảng tóm tắt, ví dụ "9 agent đang làm ở Building" kèm 3 việc đầu. Bấm vào bảng để xem đủ từng agent đang làm gì. Khung "Ai đang làm gì" cũng tự chia nhóm theo repo khi đông.

## Xem thẻ theo cột

Bấm vào một cột ở góc phải trên (ví dụ "Blocked 39") hoặc nhãn cột dưới xưởng để xem toàn bộ thẻ của cột đó, nhóm theo repo, kèm agent đang làm và lý do chặn. Bấm vào thẻ để xem chi tiết.

## Ai đang làm gì

Khung bên trái (phím W) liệt kê từng agent: lane, số thẻ, repo, tên việc và việc đang làm bằng lời thường, ví dụ "Đang sửa worktree.py" hay "Đang chạy test test_worktree_checklist.sh". Bóng thoại trên đầu agent trong xưởng cũng hiện đủ 3 dòng đó. Bấm vào một dòng để camera bay tới agent.

## Nhắn agent

Bảng chi tiết của một agent hoặc một thẻ có ô **Nhắn agent**. Lệnh gõ ở đây đi tới worker super-board như một tin nhắn mới trong Claude Code.

- **Agent đang chạy:** server ghi lệnh vào `~/.agent-office/inbox/<session id>/`. Sau bước (tool call) đang chạy, hook `inbox_hook.py` trao lệnh cho agent, thường trong vài giây; bước dài như chạy test thì chờ bước đó xong. Agent đọc xong thì ô hiện "Agent đã đọc".
- **Agent đã dừng:** server chạy `claude --resume <session id>` với đúng tài khoản (`config_dir`), thư mục và model của lần giao, log ở `~/.agent-office/resume/`. Không resume khi phiên còn tiến trình, khi thẻ còn worker khác của runner, hay khi đang có một resume khác của phiên đó.
- **Chỉ phiên worker:** đích phải là phiên chính của một lần giao trong log worker `docs/super-board/runs/*-workers/` (7 ngày gần nhất), không phải phiên Claude Code mở tay hay subagent.
- **Cần runner mới:** chỉ worker do runner có hàm `agent_office_args` bật (và đã chạy `install-autostart.sh` để có `~/.agent-office/app/inbox_hook.py`) mới có hộp thư. Worker cũ đang chạy thì chờ nó dừng rồi gửi để resume.

Lệnh gửi tới worker là chạy code tuỳ ý trên máy (worker chạy `--dangerously-skip-permissions`), nên:

- Từ điện thoại (qua tunnel), server không gửi ngay mà bắn mã 6 số lên thông báo macOS; nhập đúng mã trong 2 phút mới gửi, sai 3 lần thì huỷ, tối đa 5 lệnh chờ mã. Chọn cách này vì key nằm trong link QR (có thể lộ qua lịch sử, ảnh chụp), còn mã chỉ hiện trên Mac là yếu tố thứ hai không nằm trong link, và không cần thêm màn đặt PIN. Giới hạn: phải ở gần Mac để đọc mã.
- Tối đa 6 lệnh mỗi phút (điện thoại và Mac đếm riêng), 4000 ký tự mỗi lệnh. Mỗi lệnh ghi vào "Vừa xảy ra" (`events.jsonl`) với token và mật khẩu đã che.
- Lệnh tới agent mang một nonce mà chỉ runner và server biết; chữ giả trong issue, comment hay trang web không có nonce nên agent bỏ qua. Code mà chính worker chạy vẫn đọc được nonce: nonce chặn chữ tĩnh, không chặn code chạy dưới cùng tài khoản.

## Cảnh báo và lý do chặn

- **Vừa xảy ra** (phím E): nhật ký sự kiện. Server ghi vào `~/.agent-office/events.jsonl`, nên vẫn còn khi tải lại trang và ghi cả lúc trang đóng. Gồm agent bắt đầu hoặc dừng, repo mất tín hiệu, runner chờ bạn, thẻ chuyển cột, bị chặn hoặc xong. Tab trình duyệt hiện số sự kiện chưa xem.
- **Thông báo macOS:** server tự gửi khi runner chờ bạn, một repo dừng hoặc mất tín hiệu, hay một thẻ bị chặn, kể cả khi không mở trang. Tắt bằng `"macNotify": false` trong `config.json`.
- **Lý do bị chặn:** thẻ ở cột Blocked hiện bình luận mới nhất trên GitHub, nơi agent ghi lý do chặn. Dạng bảng lọc được "Bị chặn" và "Bị chặn, chưa rõ lý do".

## Kiểu bàn làm việc

Nút "Kiểu bàn" (phím D) có 5 mẫu: Gỗ sáng, Góc chữ L (hai màn hình), Bàn đứng, Buồng phát sáng, Bàn xưởng cơ khí. Trang nhớ mẫu đã chọn cho lần mở sau. Agent là người có tỉ lệ thật (ngồi gập gối hoặc đứng), áo theo màu lane, tay gõ phím khi đang làm.

## Thanh nút

Thanh dưới đáy có 5 nút chính: Ai đang làm gì, Toàn cảnh, Dạng bảng, Thêm việc, Vừa xảy ra. Nút "Khác" mở thêm Phóng to, Agent kế tiếp, Danh sách repo, Kiểu bàn, Ca đêm, Tải lại GitHub.

## Di chuyển trong xưởng

- **Cuộn chuột hoặc chụm hai ngón:** phóng to, thu nhỏ vào đúng chỗ con trỏ. Hai nút **+ / −** ở góc phải cũng làm được việc này.
- **Kéo chuột trái** (hoặc một ngón trên điện thoại): di chuyển trái phải, lên xuống. Kéo một thẻ việc thì vẫn là chuyển cột.
- **Vuốt ngang hoặc chéo trên trackpad, hoặc Shift + cuộn:** di chuyển sang ngang.
- **Chuột phải hoặc Shift + kéo:** xoay góc nhìn.
- **Phím mũi tên** để di chuyển, **+ / −** để phóng to, thu nhỏ.

## Phím tắt

W ai đang làm gì, F toàn cảnh, Z phóng to, B dạng bảng, A thêm việc, N agent kế tiếp, T ca ngày hoặc ca đêm, R danh sách repo, D chọn kiểu bàn, E xem "Vừa xảy ra", Esc đóng bảng chi tiết hoặc dạng bảng. Phím Tab đi qua các nút, rồi tới nhãn repo (repo đã dừng không có nhãn: dùng Danh sách repo) và bóng thoại của từng agent trong xưởng.

## Agent đang làm gì lấy từ đâu

- **Transcript Claude Code** trong `~/.claude/projects` (đọc mỗi 3 giây): lời agent, lệnh vừa chạy, thư mục, nhánh, token còn lại. Worktree tên `issue-87-review` được hiểu là lane Review đang làm #87.
- **Dòng `[RUNNER] ... tick`** của super-board: tìm trong transcript, trong manifest `docs/super-board/runs/*.md`, và trong `~/.agent-office/logs/*.log`. Nếu runner chỉ in ra terminal, thêm `2>&1 | tee -a ~/.agent-office/logs/<TênRepo>.log` vào lệnh chạy runner.

## config.json

| Khoá | Ý nghĩa |
|---|---|
| `github` | owner, loại (`user` hoặc `org`), số project, số view dùng để lấy thứ tự cột |
| `root` | thư mục chứa các repo |
| `repos`, `repoPaths` | danh sách repo luôn hiện; đường dẫn riêng khi thư mục không nằm ở `root/<tên>` |
| `claudeProjectsDir` | nơi Claude Code lưu transcript |
| `runnerLogGlobs` | file log runner (tên file chứa tên repo) |
| `activeMinutes` | bao lâu không có hoạt động thì coi agent là đang nghỉ |
| `githubSeconds`, `localSeconds` | chu kỳ đọc GitHub và đọc máy |
| `host`, `port` | nơi server lắng nghe (mặc định chỉ máy này) |

## An toàn

Server chỉ nghe `127.0.0.1`. Mọi yêu cầu ghi phải mang header riêng của trang, nên trang web khác mở trong trình duyệt không gửi thay được. Server dùng quyền của tài khoản `gh` đang đăng nhập.

"Từ chính Mac" (không cần key, không cần mã khi nhắn agent) nghĩa là kết nối tới từ loopback, Host nằm trong danh sách cho phép và không có header của tunnel. Nếu đổi `host` sang địa chỉ LAN rồi mở trang bằng IP LAN, kể cả ngay trên Mac, trang được coi như từ xa: cần key, và nhắn agent cần mã 6 số.

## Lỗi thường gặp

- **"Token gh thiếu quyền project":** chạy `gh auth refresh -s project`.
- **Trang chạy chậm khi board rất lớn:** mỗi ô trong xưởng chỉ dựng tối đa 6 thẻ, phần dư gom vào thẻ "+N việc nữa". Xem đủ danh sách trong "Dạng bảng".
- **Không thấy agent:** kiểm tra `claudeProjectsDir`, và kiểm tra `root` có khớp với đường dẫn repo trong transcript hay không.
- **Không thấy tick:** xem phần runner log ở trên.
- **Repo trên GitHub khác tên thư mục:** thêm vào `repoPaths`.
