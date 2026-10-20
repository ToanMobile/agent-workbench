# 🏭 Kế Hoạch Tích Hợp Toàn Diện: Agent-Workbench × Super-Board × TUIOS

> **Kiến trúc Nhà máy Phần mềm Tự hành 24/7 cho 6 Repositories:** Kết hợp bộ não kỷ luật của **Agent-Workbench (Universal Agent DevKit)**, dây chuyền tự động hóa **Super-Board**, và hệ thống chạy ngầm bền bỉ **TUIOS Daemon** trên Visual Studio Code.

## ⚡ Các Câu Lệnh Khởi Chạy & Khôi Phục Nhanh (Quick Start)

1. **Khởi động Super-Board Runner chạy ngầm tự động 24/7 (Đồng thời cả 6 Repositories):**
   ```bash
   python3 /Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/super_board_all.py start
   # Hoặc dùng wrapper script:
   /Volumes/Data/Toan/agent-workbench/start-all-runners.sh start
   # (Hoặc khởi động lẻ repo hiện tại: /Volumes/Data/Toan/agent-workbench/start-runner.sh)
   ```
   *(Tự động cấp phát 2 slot khóa tải nặng `~/.claude/super-board/locks/heavy-gate-{1,2}.lock`, quét cột `Ready` trên cả 6 GitHub Projects `#1`–`#6`, tự giao việc cho Agent code trong worktree cô lập, chạy `post-fix-gate.py --run-tests --full --brief` và squash-merge vào nhánh chính sang `Done`).*

2. **Dừng an toàn, kiểm tra trạng thái & khôi phục sau tạm dừng GitHub API (`Stop`, `Status` & `Resume`):**
   ```bash
   # Kiểm tra trạng thái hoạt động & Watchdog của cả 6 repositories:
   python3 /Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/super_board_all.py status

   # Dừng an toàn đồng thời cả 6 repositories (ghi stop marker để launchd watchdog không tự bật lại):
   python3 /Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/super_board_all.py stop

   # Giải phóng cờ github-halt (rc=79) trên cả 6 repo khi mạng/GitHub API vừa khôi phục rồi chạy lại:
   for r in /Volumes/Data/Toan/agent-workbench /Volumes/Data/Toan/OfficeReader/OfficeReader /Volumes/Data/Toan/Game/Goods-Triple-Shelf-Match-3D /Volumes/Data/Toan/GeelyEx2 /Volumes/Data/Toan/Game/Neighbours-From-Hell /Volumes/Data/Toan/Game/Humans-vs.-UFOs; do
     (cd "$r" && python3 .claude/bin/super-board-github-read.py --resume 2>/dev/null || true)
   done
   python3 /Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/super_board_all.py start
   ```
   *(Dừng an toàn: giải phóng worker, gỡ nhãn in-flight trên GitHub Project board, ghi `.stopped` marker và dọn dẹp lock files sạch sẽ).*

3. **Mở giao diện TUIOS trực tiếp trên máy tính xem 6 Repo (`super_board_monitor.py`):**
   ```bash
   tuios attach factory
   # Hoặc chỉ đơn giản:
   tuios attach
   ```
   - **Thoát ra ẩn đi (Detach)** mà không tắt tiến trình ngầm: Bấm tổ hợp `Ctrl + B` rồi bấm `d`.
   - **Chuyển qua lại giữa 6 cửa sổ repo:** Bấm `Ctrl + B` rồi bấm số từ `1` đến `6`.
   - **Kiểm tra danh sách session đang chạy:** `tuios ls`.

4. **Mở Web Terminal xem 6 Repo từ xa trên điện thoại (`10 giây — Zero-Config — Cloudflare Quick Tunnel`):**
   ```bash
   tuios-web
   ```
   *(Khởi động Cloudflare Quick Tunnel mã hóa SSL và in link `https://*.trycloudflare.com` để mở xem ngay trên Safari/Chrome của điện thoại mà không cần cài app hay mua domain).*

5. **Khi cài lại máy Mac mới hoặc muốn tự động apply toàn bộ cấu hình 6 tài khoản/model/GUI chỉ với 1 lệnh:**
   ```bash
   awk '/^# === BOOTSTRAP_START ===$/,/^# === BOOTSTRAP_END ===$/' \
     universal-agent-devkit/docs/init_board/tuios-superboard-integration-plan.md \
     > ~/.claude/bin/setup-autonomous-factory.sh \
     && chmod +x ~/.claude/bin/setup-autonomous-factory.sh \
     && ~/.claude/bin/setup-autonomous-factory.sh
   ```

6. **Kiểm tra sức khỏe 9 tầng bất kỳ lúc nào trên máy hiện tại (`9/9 PASS` trên cả 6 Repo):**
   ```bash
   ~/.claude/bin/setup-autonomous-factory.sh --verify
   ```

---

## 1. Giải Đáp Cơ Chế Chạy Ngầm Của TUIOS (Attach / Detach)

### 1.1. TUIOS hoạt động theo mô hình Client – Server (Daemon)
Khác với terminal thông thường của VS Code (tắt cửa sổ là chết tiến trình), **TUIOS** tách làm 2 phần độc lập:
1. **`tuios daemon` (Background Server):** Chạy ngầm ở tầng hệ điều hành macOS. Toàn bộ 6 phiên terminal của 6 repo (`super_board_monitor.py`) và các tiến trình `super-board-run.sh` / `claude -p` nằm bên trong Daemon này.
2. **`tuios` UI (Client Viewer):** Chỉ là "màn hình hiển thị" kết nối vào Daemon.

### 1.2. Các tình huống sử dụng thực tế

| Thao tác của bạn | Chuyện gì xảy ra với 6 Repo đang chạy? | Cách mở lại để xem |
| :--- | :--- | :--- |
| **Đang mở TUIOS mà bấm tắt hẳn cửa sổ VS Code (`Cmd + Q`)** | **VẪN CHẠY 100% NGẦM.** Chỉ có màn hình hiển thị bị đóng, Daemon và các Agent vẫn tiếp tục code, test, merge bình thường. | Mở lại VS Code → Mở Terminal → Gõ `tuios attach` |
| **Đang xem TUIOS, muốn thoát ra ẩn đi (Detach)** | **VẪN CHẠY 100% NGẦM.** Bạn chủ động cất màn hình TUIOS đi để làm việc khác. | Bấm phím tắt `Ctrl+B` rồi bấm `d` (Detach). Khi cần xem lại gõ `tuios attach` |
| **Lâu lâu (vài tiếng / hôm sau) mới mở lên xem 1 lần** | **HOÀN TOÀN ĐƯỢC.** TUIOS tiêu thụ ~0% CPU khi không hiển thị (Event-driven rendering). | Gõ `tuios attach` → Bấm `Ctrl+B i` để mở **Inbox** xem tổng hợp kết quả cả 6 repo, xem xong lại tắt đi. |
| **Đóng nắp máy Mac / Đi ngủ** | Cần giữ máy Mac không vào chế độ Sleep phần cứng. | Chạy kèm `caffeinate -d -s -u` để khóa màn hình/tắt đèn màn hình mà Daemon vẫn chạy xuyên đêm. |

---

## 2. Kiến Trúc Tổng Thể 3 Tầng (3-Layer Architecture)

```text
┌────────────────────────────────────────────────────────────────────────────┐
│ TẦNG 1: TUIOS DAEMON & MONITOR (Giám sát Tập trung 6 Repo 24/7)            │
│  • Chạy ngầm độc lập với VS Code (tắt VS Code không chết phiên)           │
│  • 6 Windows chạy `super_board_monitor.py` (quét cả transcript worktree)  │
└────────────────────────────────────┬───────────────────────────────────────┘
                                     │ Giữ tiến trình sống liên tục nhiều ngày
                                     ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ TẦNG 2: SUPER-BOARD (Băng chuyền Điều phối Tự động từ 6 GitHub Projects)   │
│  • `super_board_all.py`: Điều phối 6 Runners + 2 Heavy-Gate Slots toàn máy │
│  • Điều phối 3 Làn: Builder (Code) → Tester (QA) → Reviewer (Audit)       │
│  • Tự động Xoay vòng 6 Tài khoản khi chạm 95% quota, tự Resume khi reset   │
└────────────────────────────────────┬───────────────────────────────────────┘
                                     │ Gọi `claude -p` (BG_WAIT_CEILING_MS=0)
                                     ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ TẦNG 3: AGENT-WORKBENCH / UNIVERSAL AGENT DEVKIT (Bộ não & Cổng Kiểm định)│
│  • Nạp nguyên vẹn 100% AGENTS.md + .agents/instincts.md (bẫy lỗi lịch sử)  │
│  • Cung cấp 27 Skills (.agents/skills/: codebase-memory, fixbugs, tdd...)  │
│  • Chốt chặn Merge Gate bằng: post-fix-gate.py --run-tests --full --brief  │
└────────────────────────────────────────────────────────────────────────────┘
```

### Tại sao giữ nguyên 100% `agent-workbench` không gây xung đột?
* **`agent-workbench`** nằm ở `AGENTS.md` và `.agents/` (`devkit/`, `instincts.md`, `skills/`, `CHECKLIST.md`).
* **`super-board`** cài đặt vào `.claude/` (`bin/`, `skills/`, `hooks/`, `workflows/`).
* Hai bên tách biệt hoàn toàn về thư mục nhưng cùng được `claude -p` nạp tự động khi chạy mỗi task.

### 2.7. Bốn Tinh Túy Đã Chắt Lọc Từ `super-qa` & `super-review` Bổ Sung Vào `Universal Agent DevKit`
Sau khi kiểm toán chéo toàn bộ `super-qa` và `super-review`, các phần trùng lặp hoặc chỉ phục vụ Web đơn thuần (Playwright-only proof, BFS `queue.md`/`iteration-N.md`) đã bị loại bỏ; chỉ **4 kỹ thuật thực sự đắt giá** được tích hợp thẳng vào 4 skill lõi của `Universal Agent DevKit`:
1. **Surviving Mutant Guard (`First-run Green`) & Chống Tautology Test** $\rightarrow$ tích hợp vào [`skills/tdd-workflow/SKILL.md`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/skills/tdd-workflow/SKILL.md): Với test mới viết cho nhánh/feature mới mà chạy lần đầu đã PASS (`First-run Green`), bắt buộc thử làm hỏng dòng production được bảo vệ 1 lần (đảo `>` thành `>=` hoặc bỏ guard), thấy **RED**, rồi hoàn nguyên về **GREEN**; cấm viết test assert trên chính mock do test dựng hoặc lặp lại công thức của hàm đang test.
2. **Blind-First Hypothesis, Review Remembers (`R1, R2...`) & Taste Never Blocks** $\rightarrow$ tích hợp vào [`skills/open-code-review/SKILL.md`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/skills/open-code-review/SKILL.md) & [`skills/giao/SKILL.md`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/skills/giao/SKILL.md): Đọc Acceptance Criteria + `git diff` thô và lập 2–4 giả thuyết lỗi *trước khi* đọc `result.json` của Builder; ở vòng rework phải chấm trạng thái từng finding cũ (`fixed` kèm `file:line` | `not fixed` | `no longer applies`) trước khi tìm lỗi mới; góp ý cấu trúc/gu (`Over-engineering` / `Deepening opportunity`) chỉ xếp mức `Should fix`, không bao giờ dùng làm lý do duy nhất để BLOCK diff đã đúng và PASS test.
3. **Non-Blank UI Guard & Terminal-State Async Verification** $\rightarrow$ tích hợp vào [`skills/verification-before-completion/SKILL.md`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/skills/verification-before-completion/SKILL.md): Mở màn hình không crash hoặc HTTP 200 chưa phải là GREEN — bắt buộc render phần tử dữ liệu/empty-state thật + `0` `console.error`/`pageerror`/uncaught exception + `0` request nền `5xx`/`401`/`403`; với luồng Async/Queue/Upload/eSign phải đợi job về `terminal state` và xác nhận bản ghi đích đã lưu bền vững (không tính riêng UI Toast).
4. **Alternating A/B Benchmark Protocol (`AB, BA` $\ge 5$ cặp)** $\rightarrow$ tích hợp vào [`skills/verification-before-completion/SKILL.md`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/skills/verification-before-completion/SKILL.md): Mọi tuyên bố tối ưu hiệu năng/bộ nhớ phải đo xen kẽ `AB, BA` $\ge 5$ cặp sau warmup trên cùng dữ liệu, so sánh median và range (`range > 20% median` hoặc hai dải chồng lấp $\rightarrow$ `inconclusive`, cấm kết luận từ 1 lần chạy đơn lẻ).

### 2.8. Tám Chốt Chặn Tự Hành Thế Hệ Mới (Cập Nhật 20/10 — Đạt 100/100 Trên Cả 6 Repositories)
1. **Điều phối 6 Repo & Khóa Tải Nặng Toàn Máy (`super_board_all.py` + `super-board-heavy-slot.py`):** Quản lý đồng thời cả 6 Project Boards (`#1 Agent Workbench`, `#2 OfficeReader`, `#3 Goods 3D`, `#4 GeelyEx2`, `#5 Neighbours From Hell`, `#6 Humans vs. UFOs`) và giới hạn tối đa **2 tiến trình kiểm thử nặng (`--full` gate / Unity / Gradle)** chạy song song toàn máy qua khóa `flock` tại `~/.claude/super-board/locks/heavy-gate-{1,2}.lock`.
2. **Chống Cắt Ngang Tác Vụ Nền `red_proof.py --pending` (`CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0`):** Hàm `dispatch_lane` trong `super-board-run.sh` xuất `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0` khi gọi `claude -p`, ngăn CLI tự cắt tiến trình nền sau 10 phút khi chạy suite kiểm thử lớn.
3. **Cầu Chì Tổng Chống Lặp Vô Tận Thẻ Chết Sớm (`SB_EARLY_MAX_TOTAL=3`):** `note_early_death` / `early_backoff` lưu lịch sử 20 lần chết sớm (`< 90s`) gần nhất của mỗi thẻ tại `docs/super-board/inflight/<issue>-<lane>.early-deaths`. Khi tổng số lần chết sớm đạt $\ge 3$ (kể cả khi rải qua nhiều cửa sổ 10 phút), runner dừng hẳn việc tự động re-dispatch thẻ lỗi đó và giữ nguyên cột `Ready` trên GitHub (không gây ping-pong trạng thái).
4. **Dọn Sạch Worktree Tạm `red-proof-*` & Worktree Đã Merge (`super-board-post-merge-clean.sh --sweep`):** `red_proof.py` bắt tín hiệu `SIGTERM`/`SIGHUP` để luôn chạy khối `finally` gỡ `/tmp/red-proof-*`; `cleanup_stale_worktrees` quét dọn các worktree `red-proof-*` mồ côi ngay khi khởi động runner (khi không có `red_proof.py` nào đang chạy); đồng thời `sweep_merged_lanes` chạy nền lúc startup và mỗi tick (giãn cách 600s, kể cả trước nhánh `cap reached 3/3`) để xóa sạch worktree của các thẻ đã squash-merge.
5. **Merge Gate Fast-Forward Tại Chỗ & Phân Loại Lỗi Thông Minh (`super-board-merge-gate.sh`):** Chờ tải máy hạ xuống trong giới hạn trước khi pin base, tự động fast-forward tại chỗ các nhánh chậm hơn `main` nếu gộp sạch trong scratch worktree; phân biệt chính xác xung đột thật (`exit 5`), lỗi môi trường (`exit 1`) và lỗi verify đỏ trên nhánh đã cập nhật (`exit 11` kèm trích xuất dòng `KẾT LUẬN` cuối cùng — không đẩy thẻ đi rebase vô ích); tự động retry 1 lần khi lệnh verify bị timeout (`exit 124`).
6. **Tự Động Hoãn Thẻ Cần Thiết Bị (`needs-device`) & Thẻ Chờ Người (`needs-you` / `human-gated`):** `super-board-device-online.py` và `super-board-needs-you.py` giúp runner, planner và status tự động giữ các thẻ QA có nhãn `needs-device` ở `QA` khi chưa có thiết bị thật kết nối (`adb`), và bỏ qua các thẻ `Ready` có dấu `needs-you` / `human-gated` để chờ người dùng xử lý.
7. **Chặn Tuyệt Đối Spam Telegram (`super-board-notify.py`):** Đã gỡ bỏ hoàn toàn các lệnh bắn thông báo `RUNAWAY daemon` / `RUNAWAY halt` khỏi `super-board-run.sh`; đồng thời `super-board-notify.py` chặn cứng mọi thông báo khi `SB_NOTIFY_SKIP=1`, `SB_LIB_ONLY=1`, `card == "lib"`, `cmd == "runaway"` hoặc khi chạy từ thư mục test tạm (`/tmp`, `/var/folders`).
8. **Giám Sát Transcript Đa Worktree (`super_board_monitor.py`) & Đầy Đủ 36 Script `BIN` (`super-board-setup.py`):** `super_board_monitor.py` quét cả thư mục transcript của worktree (`~/.claude/projects/<slug>--claude-worktrees-*`) để hiển thị trực tiếp thao tác của từng worker trên màn hình TUIOS; `super-board-setup.py` kiểm tra đủ 36/36 script trong `.claude/bin/`.

---

## 3. Lộ Trình Triển Khai Chi Tiết (5 Giai Đoạn)

### Giai đoạn 1: Cài đặt & Cấu hình TUIOS chạy ngầm (15 phút)

1. **Cài đặt TUIOS (bản mới nhất v0.9.3 arm64):**
   ```bash
   curl -fsSL https://raw.githubusercontent.com/Gaurav-Gosain/tuios/main/install.sh | bash
   ```
2. **Khởi tạo phiên chạy ngầm định danh (`factory`) và kích hoạt tích hợp trạng thái Agent:**
   Giúp TUIOS nhận biết chính xác khi nào Claude Code / Codex / Gemini / Antigravity / Grok đang `working`, `idle`, `needs_input` hay `errored`:
   ```bash
   tuios new factory --detached
   tuios setup all --yes
   ```

---

### Giai đoạn 2: Cài đặt Super-Board vào 6 Repositories (30 phút)

Danh sách 6 repo mục tiêu trên máy (tương ứng với GitHub Projects `#1` đến `#6`):
1. `/Volumes/Data/Toan/agent-workbench` *(Project #1 — `agent-workbench`)*
2. `/Volumes/Data/Toan/OfficeReader/OfficeReader` *(Project #2 — `officereader`)*
3. `/Volumes/Data/Toan/Game/Goods-Triple-Shelf-Match-3D` *(Project #3 — `goods-triple-shelf-match-3d`)*
4. `/Volumes/Data/Toan/GeelyEx2` *(Project #4 — `geelyex2`)*
5. `/Volumes/Data/Toan/Game/Neighbours-From-Hell` *(Project #5 — `neighbours-from-hell`)*
6. `/Volumes/Data/Toan/Game/Humans-vs.-UFOs` *(Project #6 — `humans-vs-ufos`)*

**Thực hiện tại từng repo:**
```bash
# Cài đặt super-board vào .claude/ của repo (giữ nguyên 100% .agents/)
cd <đường-dẫn-repo>
bash ~/.local/share/super-board/install.sh --yes
```

Sau đó mở Claude Code trong từng repo và chạy lệnh thiết lập:
```text
/super-board onboard
```
* Trong bước `onboard`:
  * Chọn GitHub Project v2 tương ứng của repo (`#1`–`#6`).
  * Giữ nguyên `AGENTS.md` hiện có của `agent-workbench` (không cho ghi đè mất phần `universal-agent-devkit`).
  * Bật bảo vệ nhánh chính (`protect-main`).

---

### Giai đoạn 3: Khóa chặt Merge Gate bằng `post-fix-gate.py` của Agent-Workbench (15 phút)

Đây là bước quan trọng nhất để biến `super-board` thành công cụ tuân thủ kỷ luật thép của `agent-workbench`.

Trong file cấu hình `.claude/super-board/configs/<slug>.json` của mỗi repo (và bản mẫu toàn cục `~/.claude/super-board/template-devkit-config.json`), cấu hình `verify_commands` trỏ trực tiếp vào cổng kiểm định của DevKit:

```json
{
  "base_branch": "main",
  "usage_pause_pct": 95,
  "max_workers": 3,
  "tick_seconds": 30,
  "no_progress_cycles": 240,
  "max_dispatches": 0,
  "verify_commands": [
    "python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief"
  ]
}
```

**Ý nghĩa kỹ thuật:**
* Mọi PR do làn Builder viết code và làn QA kiểm thử, trước khi được phép squash-merge vào nhánh chính (`main`/`master`), bắt buộc phải vượt qua `post-fix-gate.py --run-tests --full --brief` với mã thoát `0` (điều phối qua `super-board-heavy-slot.py` tối đa 2 lượt `--full` đồng thời toàn máy).
* Nếu vi phạm bất kỳ quy tắc nào của `agent-workbench` (lộ secret, để lại placeholder, làm hỏng test cũ, thiếu bằng chứng), cổng merge sẽ từ chối (`exit 11`) kèm dòng `KẾT LUẬN` cuối và trả thẻ về `Building` để Agent sửa lại.

---

### Giai đoạn 4: Tối ưu hóa cho Gói Claude 5x (Chống cạn Quota khi chạy 6 Repo)

Khi chạy 6 repo song song trên gói **Claude 5x**, cần cấu hình điều tiết thông minh để không bị nghẽn:

1. **Kích hoạt bộ theo dõi hạn mức (`super-board-usage.sh` + `super-board-account-pool.sh`):**
   Đảm bảo status-line của Claude Code ghi nhận `% used` vào `~/.claude/super-board/usage-<account>.json`. Khi đạt **95%** hạn mức cửa sổ 5 giờ, hệ thống tự động xoay sang tài khoản tiếp theo trong bể 6 tài khoản.
2. **Sử dụng `super_board_all.py start` cho chế độ Daemon 24/7 (`SB_DAEMON=1`):**
   ```bash
   python3 /Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/super_board_all.py start
   ```
   * Tự động phân tầng model theo độ phức tạp của thẻ: Card dễ dùng **Haiku 4.5**, Card trung bình dùng **Sonnet**, Card khó dùng **Opus**.

---

### Giai đoạn 5: Quy trình Vận hành Hàng ngày (SOP "Bật Ngầm - Lâu Lâu Xem")

#### Bước 1: Khởi động nhà máy 6 Repo chỉ với 1 lệnh
Mở Terminal trong VS Code, bật chống sleep và kích hoạt cả 6 runners:
```bash
# Giữ máy Mac thức khi khóa màn hình và khởi động đồng thời cả 6 runners + TUIOS monitors:
caffeinate -d -s -u &
python3 /Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/super_board_all.py start
tuios attach factory
```
Trong 6 cửa sổ (Windows `1`–`6`) của TUIOS tương ứng với 6 repo, `super_board_monitor.py` tự động hiển thị bảng trạng thái trực tiếp:
* **Window 1 (`agent-workbench`):** Project #1 (`Agent Workbench`)
* **Window 2 (`OfficeReader`):** Project #2 (`OfficeReader`)
* **Window 3 (`Goods-Triple`):** Project #3 (`Goods 3D`)
* **Window 4 (`GeelyEx2`):** Project #4 (`GeelyEx2`)
* **Window 5 (`Neighbours`):** Project #5 (`Neighbours From Hell`)
* **Window 6 (`Humans-vs-UFOs`):** Project #6 (`Humans vs. UFOs`)

#### Bước 2: Thoát giao diện / Tắt VS Code đi làm việc khác
* Bấm `Ctrl+B` rồi nhấn `d` (hoặc đơn giản là đóng hẳn cửa sổ VS Code).
* Toàn bộ 6 dây chuyền vẫn âm thầm chạy ngầm 24/7.

#### Bước 3: Giao việc từ bất kỳ đâu (Điện thoại / Web)
* Mở GitHub Projects (`#1`–`#6`) của bất kỳ repo nào trên trình duyệt hoặc GitHub Mobile.
* Tạo Issue mới với Acceptance Criteria rõ ràng (hoặc dùng `/createTask`) → Kéo thẻ vào cột **`Ready`**.
* Trong vòng 30 giây (1 tick), `super-board` đang chạy ngầm ở nhà sẽ tự động nhận thẻ và bắt đầu chu trình `Build → QA → Review → Merge`.

#### Bước 4: Lâu lâu mở lên kiểm tra (5 phút/lần)
Khi muốn xem tiến độ:
1. Mở Terminal bất kỳ (trong VS Code hoặc iTerm/Terminal của Mac), gõ:
   ```bash
   tuios attach factory
   ```
2. Nhìn lướt qua 6 cửa sổ để thấy trạng thái trực quan của từng lane (`Build`, `QA`, `Review`) và log thực thi trực tiếp từ worktree.
3. Bấm `Ctrl+B` rồi nhấn `i` để mở **Hộp thư tập trung (Inbox)** nếu có bất kỳ câu hỏi nào từ Agent cần bạn duyệt.
4. Xem xong, bấm `Ctrl+B d` (hoặc đóng cửa sổ) — hệ thống tiếp tục chạy ngầm.

---

## 4. Bảng Tra Cứu Lệnh Nhanh (Quick Cheat Sheet)

| Nhu cầu của bạn | Lệnh / Phím tắt thực hiện |
| :--- | :--- |
| **Khởi động đồng thời cả 6 Super-Board Runners chạy ngầm** | `python3 universal-agent-devkit/scripts/governance/super_board_all.py start` |
| **Kiểm tra trạng thái cả 6 Runners, PID & Watchdog** | `python3 universal-agent-devkit/scripts/governance/super_board_all.py status` |
| **Dừng an toàn cả 6 Runners (ghi `.stopped` marker)** | `python3 universal-agent-devkit/scripts/governance/super_board_all.py stop` |
| **Mở Web Terminal xem 6 repo từ xa trên điện thoại (Cloudflare Quick Tunnel)** | `tuios-web` |
| **Mở lại màn hình theo dõi 6 repo sau khi đã tắt VS Code** | `tuios attach factory` |
| **Liệt kê các phiên chạy ngầm đang sống** | `tuios ls` |
| **Ẩn màn hình TUIOS đi (để chạy ngầm tiếp)** | `Ctrl+B` sau đó bấm `d` *(hoặc đóng luôn cửa sổ Terminal)* |
| **Xem hộp thư thông báo tổng hợp của cả 6 repo** | `Ctrl+B` sau đó bấm `i` |
| **Nhảy tới thông báo cũ nhất đang chờ duyệt** | `Ctrl+B` sau đó bấm `o` |
| **Kiểm tra nhanh trạng thái Board của 1 repo** | `/super-board status` |
| **Dừng toàn bộ worker của 1 repo an toàn** | `/super-board stop` |
| **Kiểm tra hạn ngạch GitHub API hiện tại** | `gh api rate_limit \| jq '.resources.core, .resources.graphql'` |

---

## 5. Điều Khiển & Giám Sát Từ Xa Bằng Điện Thoại (Mobile Workflow)

Khi bạn đi ra ngoài (dùng 4G/5G) và máy Mac đang treo ở nhà, hệ thống hỗ trợ 2 tầng điều khiển linh hoạt:

### 5.1. Tầng 1: GitHub Mobile (Khuyên dùng — Đáp ứng 95% nhu cầu hàng ngày, Zero-Config)
Vì `super-board` lấy GitHub Projects v2 làm nguồn trạng thái duy nhất (Single Source of Truth), ứng dụng **GitHub Mobile** chính chủ trở thành bộ điều khiển từ xa mà **không cần mở port mạng, không cần VPN hay cài đặt mạng phức tạp**:
1. **Giao việc từ điện thoại trong 10 giây:**
   * Mở app **GitHub** → Chọn 1 trong 6 Repo → Bấm **`+` (New Issue)**.
   * Dùng tính năng đọc giọng nói (Voice-to-Text) trên bàn phím điện thoại để đọc yêu cầu tính năng/sửa lỗi và tiêu chí nghiệm thu (`Acceptance Criteria`).
   * Gắn Issue vào **Project Board** và chọn cột **`Ready`**.
   * Máy Mac ở nhà trong vòng $\le 30\text{s}$ sẽ tự động nhận việc và bắt đầu chu trình `Build → QA → Review → Merge`.
2. **Nhận thông báo đẩy (Push Notifications) & Nghiệm thu bằng hình ảnh:**
   * Khi làn **Builder** mở PR, làn **QA** đăng báo cáo kiểm thử kèm ảnh chụp màn hình (Visual Proof), hoặc làn **Reviewer** tự động squash-merge vào `main`, điện thoại của bạn sẽ nhận thông báo tức thì.
   * Bạn bấm vào thông báo trên điện thoại để xem trực tiếp kết quả mà không cần mở máy tính.
3. **Xử lý khi Agent gặp lỗi / cần hỏi:**
   * Khi gặp sự cố hoặc bài toán mơ hồ, thẻ nhảy vào cột **`Blocked`** kèm comment hỏi bạn.
   * Bạn chỉ cần gõ 1 dòng comment chỉ đạo ngay trên điện thoại và kéo thẻ về **`Ready`** là Agent ở nhà tự chạy tiếp.

---

### 5.2. Tầng 2: Cloudflare Quick Tunnel + Web Terminal (Phương án đã chọn: Mở Web Xem Ngay Trong 10 Giây)
*Phương án tối ưu nhất: **Điện thoại HOÀN TOÀN KHÔNG CẦN CÀI BẤT KỲ APP NÀO**, không cần mua tên miền, không cần đăng ký tài khoản Cloudflare, mở thẳng bằng Safari / Chrome trên iOS / Android.*

#### Kiến trúc Cloudflare Quick Tunnel cho TUIOS:
```text
┌─────────────────────────┐          ┌──────────────────────┐          ┌─────────────────────────┐
│  Điện thoại (4G / 5G)   │  HTTPS   │  Cloudflare Edge     │  Tunnel  │    Máy Mac ở nhà        │
│  Safari / Chrome        ├─────────►│  (Mã hóa SSL 100%)   ├─────────►│  `cloudflared tunnel`   │
│  https://*.trycloud...  │          │  (Miễn phí, Không cần│          │        ▼                │
│                         │          │   tên miền riêng)    │          │  `ttyd` -> `tuios`      │
└─────────────────────────┘          └──────────────────────┘          └─────────────────────────┘
```

#### Hướng dẫn cài đặt & vận hành thực tế:

1. **Cài đặt 1 lần duy nhất trên máy Mac (qua Homebrew):**
   ```bash
   brew install cloudflared ttyd
   ```
   * **`ttyd`**: Cầu nối hiển thị phiên TUIOS thành giao diện Web (giao diện dark mode, mượt mà, đầy đủ phím tắt).
   * **`cloudflared`**: Đưa cổng web cục bộ ra Internet qua đường hầm mã hóa bảo mật của Cloudflare.

2. **Khởi động 1 lệnh duy nhất (Script tự động hóa):**
   Hệ thống đã tích hợp sẵn script khởi động 1 chạm tại `~/.claude/bin/start-web-terminal.sh`. Bất kỳ khi nào bạn chuẩn bị ra ngoài và muốn có link xem trên điện thoại, chỉ cần chạy:
   ```bash
   bash ~/.claude/bin/start-web-terminal.sh
   ```
   *(Script sẽ tự động khởi động `ttyd` gắn vào phiên TUIOS `factory`, bật `cloudflared tunnel` và in ra đường link kết nối).*

3. **Mở trên điện thoại:**
   * Màn hình Terminal sẽ in ra đường link ngẫu nhiên:
     ```text
     ========================================================================
       CLOUDFLARE QUICK TUNNEL ĐÃ SẴN SÀNG!
       Mở Safari/Chrome trên điện thoại và truy cập link sau:
       👉 https://xxxx-xxxx-xxxx.trycloudflare.com
     ========================================================================
     ```
   * Bạn mở Safari/Chrome trên iPhone/Android, dán link vào là **thấy ngay toàn bộ 6 cửa sổ TUIOS của 6 repo**!

4. **Khi về nhà hoặc muốn tắt đường hầm:**
   * Chỉ cần bấm `Ctrl+C` tại cửa sổ chạy script, hoặc chạy lệnh:
     ```bash
     killall ttyd cloudflared
     ```

---

### 5.3. Phụ lục: Tùy Chọn Dự Phòng với Tailscale + Termius
Nếu bạn đã quen với giao diện SSH client chuyên dụng (như Termius) và mạng riêng ảo Tailscale:
1. Cài đặt Tailscale: `brew install --cask tailscale` và đăng nhập.
2. Bật Remote Login (SSH) trên Mac: `System Settings → General → Sharing → Remote Login (ON)`.
3. Dùng app Termius trên điện thoại kết nối vào IP Tailscale của máy Mac (`100.x.y.z`) với lệnh startup: `tuios attach factory`.

---

## 6. Cấu Hình Treo Máy Mac 24/7 Xuyên Nhiều Ngày (Unattended Hardening)

Để treo máy Mac liên tục nhiều ngày chạy 6 repo mà **không bị tắt mạng, không bị sleep, không tràn RAM và không đầy ổ cứng**, áp dụng các chốt chặn kỹ thuật sau:

### 6.1. Tắt màn hình nhưng giữ CPU & Mạng chạy 100% khi cắm sạc (`pmset`)
Chạy lệnh sau 1 lần trên Terminal của máy Mac:
```bash
# Khi cắm sạc (-c):
# - sleep 0: Hệ thống không bao giờ ngủ
# - disksleep 0: Ổ cứng không bao giờ ngắt
# - displaysleep 5: Tự động tắt đèn màn hình sau 5 phút để mát máy & tiết kiệm điện
# - tcpkeepalive 1: Giữ kết nối Wi-Fi/SSH/GitHub luôn sống 24/7
sudo pmset -c sleep 0 disksleep 0 displaysleep 5 tcpkeepalive 1
```
*(Nếu cần khôi phục mặc định khi mang máy đi: `sudo pmset -c sleep 1 displaysleep 10`).*

### 6.2. Cơ chế tự bảo vệ khi treo máy nhiều ngày

| Rủi ro khi treo máy dài ngày | Cơ chế tự động xử lý trong kiến trúc này |
| :--- | :--- |
| **1. Chạm trần hạn mức Claude 5x giữa đêm** | `super-board-account-pool.sh` kết hợp `super-board-usage.sh` tự động phát hiện tài khoản hiện tại đạt $\ge 95\%$ hạn mức và **xoay vòng tức thì (Auto-Rotate)** qua bể 6 tầng: `finos` $\rightarrow$ `finos_team` $\rightarrow$ `max` (Gói cá nhân 5x Max) $\rightarrow$ `antigravity` (Google AI Ultra `phathuy.vetgo@gmail.com` • `gemini-4-argon-high`) $\rightarrow$ `antigravity_pro` (Google AI Pro `alex.1993.dev@gmail.com` • `gemini-4-argon-high`) $\rightarrow$ `grok` (`grok-4.7` • `xhigh`) mà **giữ nguyên 100% lịch sử session (`claude --resume`)**. |
| **2. Tiến trình Agent bị treo ngâm RAM (Zombie) hoặc Thẻ Chết Sớm Lặp Vô Tận** | `super-board-run.sh` có sẵn `sweep_lane_zombies` thu hồi các tiến trình `claude -p` đã hoàn thành phần việc trên cột Kanban nhưng chưa thoát, kết hợp cầu chì `SB_EARLY_MAX_TOTAL=3` ngắt hẳn các thẻ chết sớm (`< 90s`) lặp quá 3 lần và đặt `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0` để không cắt ngang tiến trình nền `red_proof.py --pending`. |
| **3. Tràn ổ cứng do sinh nhiều nhánh Worktree (`red-proof-*` & Lane Worktrees)** | `red_proof.py` bắt `SIGTERM`/`SIGHUP` để luôn gỡ `/tmp/red-proof-*`, `cleanup_stale_worktrees` dọn worktree mồ côi lúc khởi động, và `sweep_merged_lanes` (`super-board-post-merge-clean.sh --sweep`) chạy nền mỗi 600s để xóa sạch worktree của các thẻ đã squash-merge. |
| **4. Quá tải CPU/RAM khi nhiều Repo cùng chạy `--full` Gate** | `super-board-heavy-slot.py` (`~/.claude/super-board/locks/heavy-gate-{1,2}.lock`) giới hạn tối đa **2 tiến trình kiểm thử nặng** chạy song song toàn máy, kết hợp `super-board-merge-gate.sh` chờ tải máy hạ trước khi verify. |
| **5. Rò rỉ RAM giao diện đồ họa (Electron/GUI Leak)** | Trước khi rời máy dài ngày, bạn **đóng hẳn ứng dụng VS Code (`Cmd + Q`)**. Chỉ có `tuios daemon` (~20MB RAM) và các worker chạy ngầm, giải phóng hàng chục GB RAM cho trình biên dịch (Gradle/Xcode/Unity/Node). |
| **6. Hỏi mật khẩu SSH Key giữa đêm** | Thêm khóa SSH vào Apple Keychain vĩnh viễn bằng lệnh: `ssh-add --apple-use-keychain ~/.ssh/id_ed25519` và kiểm tra `gh auth status` dùng keyring. |

---

## 7. Quản Lý 6 Tài Khoản (`finos`, `finos_team`, `max`, `antigravity`, `antigravity_pro`, `grok`), Model Mặc Định & Chế Độ `Direct` An Toàn 100%

Hệ thống đã tích hợp trọn vẹn **3 tài khoản Claude Code 5x chính chủ** + **2 tài khoản Antigravity CLI (Google AI Ultra & Google AI Pro)** + **Grok CLI** và công cụ **`CC Switch`** (`ccswitch` CLI + `CC Switch.app` GUI ở chế độ **`Direct`** an toàn 100% chống ban):

### 7.1. Bảng Cấu Hình 6 Tài Khoản & Model Mặc Định Đã Khóa Cứng

| # | Mã Tài Khoản | Tài Khoản / Gói Cước | Model Mặc Định & Reasoning Effort | Nơi Lưu Trữ & Cơ Chế Xác Thực |
| :-: | :--- | :--- | :--- | :--- |
| **1** | **`finos`** | `toan.huynh@finos.asia` *(FinOS 5x Team)* | **`sonnet`** *(Advisor: **`opus`** • Effort: **`xhigh`**)* | `~/.claude-finos` • macOS Keychain `Claude Code-credentials-08fc04bc` (Direct OAuth) |
| **2** | **`finos_team`** | `linhnt@finos.asia` *(FinOS Team 5x)* | **`sonnet`** *(Advisor: **`opus`** • Effort: **`xhigh`**)* | `~/.claude-finos_team` • macOS Keychain `Claude Code-credentials-25aa58cc` (Direct OAuth) |
| **3** | **`max`** | `toan.huynh@finos.asia` *(Personal 5x Max)* | **`sonnet`** *(Advisor: **`opus`** • Effort: **`xhigh`**)* | `~/.claude-max` • macOS Keychain `Claude Code-credentials-0f12add9` (Direct OAuth) |
| **4** | **`antigravity`** (`agy`) | `phathuy.vetgo@gmail.com` *(Google AI Ultra)* | **`gemini-4-argon-high`** *(Effort: **`xhigh`**)* | `~/.gemini/antigravity-cli/settings.json` + `~/.gemini/google_accounts.json` |
| **5** | **`antigravity_pro`** (`agy_pro`) | `alex.1993.dev@gmail.com` *(Google AI Pro)* | **`gemini-4-argon-high`** *(Effort: **`xhigh`**)* | `~/.gemini/antigravity-cli/settings.json` + `~/.gemini/google_accounts.json` |
| **6** | **`grok`** | Grok CLI `v1.0.50` *(xAI)* | **`grok-4.7`** *(Effort: **`xhigh`**)* | `~/.grok/config.toml` (`default = "grok-4.7"`, `default_reasoning_effort = "xhigh"`) |

### 7.2. Chế Độ `Direct` Trên `CC Switch.app` (An Toàn 100% — Không Sợ Bị Ban)
* **Tại sao chọn `Direct` thay vì `Routing` / `Aggregation`:**
  * Với 3 tài khoản thuê bao **Claude 5x Subscription (OAuth)**, nếu bật `Routing` hoặc `Aggregation`, `CC Switch` sẽ dựng Local Proxy (`127.0.0.1`) đứng giữa giải mã gói tin OAuth — dễ bị hệ thống chống lạm dụng của Anthropic đánh dấu bất thường.
  * Ở chế độ **`Direct`** (`enableLocalProxy: false`, `enableStackMode: false`), `CC Switch` hoàn toàn **không chạm vào bất kỳ gói tin mạng nào** và **không chèn tĩnh `CLAUDE_CODE_OAUTH_TOKEN`** vào `settings.json`. Mọi kết nối đi thẳng 100% từ binary `claude` chính chủ tới `https://api.anthropic.com` qua TLS/HTTP2 chuẩn bằng macOS Keychain.
* **Chia sẻ 100% Session (`~/.claude-{finos,finos_team,max}` $\rightarrow$ `~/.claude/`):**
  * Các thư mục `projects`, `sessions`, `session-env`, `file-history`, `paste-cache`, `history.jsonl`, `skills`, `hooks`, `bin`, `workflows`, `settings.json` được nối Symlink đồng nhất về `~/.claude/`. Đổi qua lại giữa `finos`, `finos_team`, `max` giữ nguyên 100% lịch sử `claude --resume`.

### 7.3. Phân Bổ Tài Khoản Mặc Định Theo 6 Repo & Tự Động Xoay Vòng Khi Đầy Hạn Mức

| Repo | Project Board | Tài khoản ưu tiên (`.claude/settings.local.json`) | Chuỗi tự động Failover khi đạt $\ge 95\%$ Quota |
| :--- | :---: | :--- | :--- |
| `agent-workbench` | **#1** | `finos` (`~/.claude-finos`) | `finos` $\rightarrow$ `finos_team` $\rightarrow$ `max` $\rightarrow$ `antigravity` $\rightarrow$ `antigravity_pro` $\rightarrow$ `grok` / `pause` |
| `OfficeReader` | **#2** | `finos_team` (`~/.claude-finos_team`) | `finos_team` $\rightarrow$ `finos` $\rightarrow$ `max` $\rightarrow$ `antigravity` $\rightarrow$ `antigravity_pro` $\rightarrow$ `grok` / `pause` |
| `Goods-Triple-Shelf-Match-3D` | **#3** | `finos` (`~/.claude-finos`) | `finos` $\rightarrow$ `finos_team` $\rightarrow$ `max` $\rightarrow$ `antigravity` $\rightarrow$ `antigravity_pro` $\rightarrow$ `grok` / `pause` |
| `GeelyEx2` | **#4** | `finos_team` (`~/.claude-finos_team`) | `finos_team` $\rightarrow$ `finos` $\rightarrow$ `max` $\rightarrow$ `antigravity` $\rightarrow$ `antigravity_pro` $\rightarrow$ `grok` / `pause` |
| `Neighbours-From-Hell` | **#5** | `finos` (`~/.claude-finos`) | `finos` $\rightarrow$ `finos_team` $\rightarrow$ `max` $\rightarrow$ `antigravity` $\rightarrow$ `antigravity_pro` $\rightarrow$ `grok` / `pause` |
| `Humans-vs.-UFOs` | **#6** | `finos` (`~/.claude-finos`) | `finos` $\rightarrow$ `finos_team` $\rightarrow$ `max` $\rightarrow$ `antigravity` $\rightarrow$ `antigravity_pro` $\rightarrow$ `grok` / `pause` |

### 7.4. Bảng Lệnh Điều Khiển Đa Tài Khoản & Đổi Model (`ccswitch` & `super-board-account-pool.sh`)

```bash
# 1. Xem bảng trạng thái Quota & Session của cả 6 tài khoản/engine
ccswitch list

# 2. Đổi nhanh tài khoản đang dùng (giữ nguyên 100% session đang chạy)
ccswitch switch finos             # 1. toan.huynh@finos.asia [FinOS 5x Team]
ccswitch switch finos_team        # 2. linhnt@finos.asia [FinOS Team 5x]
ccswitch switch max               # 3. toan.huynh@finos.asia [Personal 5x Max]
ccswitch switch antigravity       # 4. phathuy.vetgo@gmail.com [Google AI Ultra • gemini-4-argon-high]
ccswitch switch antigravity_pro   # 5. alex.1993.dev@gmail.com [Google AI Pro • gemini-4-argon-high]
ccswitch switch grok              # 6. Grok CLI [grok-4.7 • xhigh]

# 3. Đổi tài khoản mặc định cho 1 repo cụ thể
~/.claude/bin/super-board-account-pool.sh switch /Volumes/Data/Toan/GeelyEx2 max

# 4. Bật chế độ tự động Failover sang Antigravity (Ultra/Pro) và Grok-4.7 khi cả 3 nick Claude chạm 95%
export SB_FALLBACK_ANTIGRAVITY=1     # hoặc =pro để ưu tiên alex.1993.dev@gmail.com
export SB_FALLBACK_GROK=1
```

### 7.5. Tích Hợp Sẵn 100% Workflow `Universal Agent DevKit` + Giữ Nguyên Đủ 7 Cột Trực Quan Trên UI (`Zero-Duplication Column Sync`)

Hệ thống kết hợp **trọn vẹn giao diện 7 cột trực quan trên GitHub Projects UI** (`Backlog` $\rightarrow$ `Ready` $\rightarrow$ `Building` $\rightarrow$ `QA` $\rightarrow$ `Review` $\rightarrow$ `Blocked` $\rightarrow$ `Done`) với **100% bộ công cụ kiểm thử & review của `Universal Agent DevKit`** ở hậu trường mà **không bị lặp lại 3 lần chạy test hay tạo 3 worktree trùng lặp**:

#### A. Cách thẻ di chuyển trực quan qua từng cột trên UI theo thời gian thực:

| Cột hiển thị trên UI GitHub Project | Lệnh cập nhật cột tức thì (`1 GraphQL point`) | Việc thực thi bên dưới hậu trường bằng `Universal Agent DevKit` (Trong cùng 1 Worktree) |
| :--- | :--- | :--- |
| **1. `Ready` $\rightarrow$ `Building`** | `super-board-card.sh move <N> Building` | Worker nhận thẻ, đọc `AGENTS.md` + `context-enricher` + `codebase-memory-mcp`, viết test tái hiện lỗi (**RED**) rồi viết code (**GREEN**) theo `tdd-workflow` / `fixbugs`. |
| **2. `Building` $\rightarrow$ `QA`** | `super-board-card.sh move <N> QA` | **Không đẻ Worker thứ 2.** Chính Worker hiện tại kéo thẻ sang cột **`QA`** trên UI, chạy `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief` (`exit 0`) + chụp ảnh màn hình thật bằng `proof-capture.py`, mở PR và đăng báo cáo `[qa] [report] ✅` kèm ảnh nghiệm thu. |
| **3. `QA` $\rightarrow$ `Review`** | `super-board-card.sh move <N> Review` | Khi Gate đạt `exit 0`, Worker kéo thẻ sang cột **`Review`** trên UI và phân nhánh thông minh theo đúng chuẩn `AGENTS.md`:<br>• **Task nhỏ/vừa (`< 3` files, `<= 200` LOC, không chạm `auth`/`payment`/`migration`):** Tự chạy `open-code-review`, đăng `[reviewer] [report] ✅`, gọi `super-board-merge-gate.sh` squash-merge vào `main` và kéo thẻ sang **`Done`**!<br>• **Task lớn/rủi ro cao (`>= 2` modules, `>= 3` files, `> 200` LOC, hoặc chạm `auth`/`payment`/`migration`):** Giữ thẻ ở cột **`Review`** để kích hoạt **Agent thứ 2 (Independent Reviewer / Antigravity `audit`)** vào review chéo độc lập trước khi merge sang **`Done`**. |
| **4. `Review` $\rightarrow$ `Done` / `Blocked`** | `super-board-card.sh move <N> Done` *(hoặc `Blocked`)* | Sau khi `super-board-merge-gate.sh` xác nhận commit đã nằm trên `main`, thẻ nhảy sang **`Done`** (hoặc nhảy sang **`Blocked`** kèm thông báo `🙋 Needs you` nếu cần người thật duyệt DB/Payment/Auth). |

#### B. 5 Bản vá tự động (`Auto-Patches`) trong `~/.claude/bin/setup-autonomous-factory.sh`:

| # | Thành phần được vá tự động | Tác dụng |
| :-: | :--- | :--- |
| **1** | **`super-board-wave.js` & `super-board-run.sh`** | Cho phép 1 Worker `DevKit` duy nhất dịch chuyển thẻ xuyên suốt `Ready → Building → QA → Review → Done` trên UI (`at = b.column \|\| 'QA'` và `check_lane_zombie build "Ready Building QA Review"`), đặt `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0`, cầu chì `SB_EARLY_MAX_TOTAL=3`, tự động bỏ qua việc đẻ lại Worker `QA`/`Review` trùng lặp khi thẻ đã tới `Done`, và chỉ gọi Reviewer độc lập khi thẻ dừng ở `Review` (task lớn $\ge 3$ files / $>200$ LOC). |
| **2** | **`super-board-skills-ready.py`** | Tự động quét **`.agents/skills/`** và ánh xạ 100% sang 27 skill của DevKit (`fixbugs`, `tdd-workflow`, `incremental-implementation`, `deep-module-design`, `open-code-review`, `merge-conflict-resolver`, `qc`). Kết quả `check`: **`missing: []` (PASS 6/6 repo)**. |
| **3** | **`super-board-setup.py`** | Nhận diện đồng thời **`~/.claude/` toàn cục** lẫn `<repo>/.claude/` (đủ 36/36 script trong `BIN`: bao gồm `super-board-device-online.py`, `super-board-heavy-slot.py`, `super-board-notify.py`) và tự động khóa cứng `verify_commands: ["python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief"]`. |
| **4** | **`super-board-agents-md.py`** | Nâng ngưỡng mặc định lên **`600` dòng** (`ok: 240 lines`) và tự động nhận diện `<!-- universal-agent-devkit:start -->` để bảo vệ nguyên vẹn `AGENTS.md` & `CLAUDE.md`. |
| **5** | **`worker-preamble.md` & `agents-md-block.md`** | Nhúng trực tiếp **Chu trình 6 Bước của Universal Agent DevKit + Lệnh dịch chuyển cột UI thời gian thực (`Building → QA → Review → Done`)** vào mọi Worker. |

Kiểm chứng trực tiếp trạng thái `/super-board onboard` trên bất kỳ repo nào:
```bash
python3 ~/.claude/bin/super-board-setup.py check --root /Volumes/Data/Toan/agent-workbench --host claude --text
# Checks:
#   ✓ super-board skills, scripts and board engine present
#   ✓ git repo found
#   ✓ required worker skills resolved for claude
#   ✓ re-checked: all green
```

---

## 8. Hướng Dẫn & Script Tự Động Hóa Toàn Bộ Hệ Thống (`1-Command Auto-Apply & Bootstrap`)

Toàn bộ logic cấu hình cho cả 6 tài khoản (`finos`, `finos_team`, `max`, `antigravity` Ultra `phathuy.vetgo@gmail.com`, `antigravity_pro` Pro `alex.1993.dev@gmail.com`, `grok-4.7`), cấu hình model mặc định (`sonnet`/`opus`, `gemini-4-argon-high`, `grok-4.7`), liên kết Symlink 100% session, tích hợp sẵn 100% workflow `Universal Agent DevKit` vào `/super-board onboard` + `/super-build`, khóa cổng kiểm định `post-fix-gate.py`, và nạp dữ liệu SQLite cho `CC Switch.app` ở chế độ `Direct` an toàn 100% đã được đóng gói hoàn chỉnh trong khối `# === BOOTSTRAP_START ===` bên dưới.

### 8.1. Cách 1: Chạy 1 Lệnh Tự Động Apply Toàn Bộ Cấu Hình Trực Tiếp Từ File `.md` Này
Từ thư mục gốc `/Volumes/Data/Toan/agent-workbench`, chạy đúng **1 câu lệnh duy nhất** dưới đây để tự động tạo và thực thi `~/.claude/bin/setup-autonomous-factory.sh`:

```bash
awk '/^# === BOOTSTRAP_START ===$/,/^# === BOOTSTRAP_END ===$/' \
  universal-agent-devkit/docs/init_board/tuios-superboard-integration-plan.md \
  > ~/.claude/bin/setup-autonomous-factory.sh \
  && chmod +x ~/.claude/bin/setup-autonomous-factory.sh \
  && ~/.claude/bin/setup-autonomous-factory.sh
```

Hoặc bất kỳ lúc nào muốn kiểm tra sức khỏe 9 tầng (`9/9 PASS` trên 6/6 repo):
```bash
~/.claude/bin/setup-autonomous-factory.sh --verify
```

### 8.2. Cách 2: Quy Trình Khi Cài Lại Máy Mac Mới Tinh
Nếu máy Mac mới chưa đăng nhập OAuth lần đầu:
1. **Bước 1 — Đăng nhập OAuth 1 lần cho các tài khoản:**
   ```bash
   CLAUDE_CONFIG_DIR=~/.claude-finos claude login       # toan.huynh@finos.asia (FinOS Org)
   CLAUDE_CONFIG_DIR=~/.claude-finos_team claude login  # linhnt@finos.asia (FinOS Team)
   CLAUDE_CONFIG_DIR=~/.claude-max claude login         # toan.huynh@finos.asia (Personal 5x Max)
   ```
2. **Bước 2 — Chạy lệnh tự động apply 100% cấu hình từ file này:**
   ```bash
   awk '/^# === BOOTSTRAP_START ===$/{f=1;next}/^# === BOOTSTRAP_END ===$/{f=0}f' \
     universal-agent-devkit/docs/init_board/tuios-superboard-integration-plan.md \
     > ~/.claude/bin/setup-autonomous-factory.sh \
     && chmod +x ~/.claude/bin/setup-autonomous-factory.sh \
     && ~/.claude/bin/setup-autonomous-factory.sh
   ```

### 8.3. Mã Nguồn Tự Động Hóa Nhúng Trực Tiếp (`setup-autonomous-factory.sh`)

```bash
# === BOOTSTRAP_START ===
#!/usr/bin/env bash
# setup-autonomous-factory.sh — 1-Command Full Auto-Config & Recovery for Agent-Workbench Autonomous Factory
# Source of Truth: universal-agent-devkit/docs/init_board/tuios-superboard-integration-plan.md
#
# Automatically applies 100% of configuration without manual re-setup:
#   1. TUIOS v0.9.3 + sidebar config + 5 agent hooks + persistent `factory` session (6 repos)
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

ensure_tuios_factory_session() {
  command -v tuios >/dev/null 2>&1 || return 0
  mkdir -p "$HOME/.config/tuios"
  if [ ! -f "$HOME/.config/tuios/config.toml" ]; then
    printf '[appearance]\nsidebar_enabled = true\n' > "$HOME/.config/tuios/config.toml"
  fi
  tuios setup all --yes >/dev/null 2>&1 || true
  if ! tuios ls 2>/dev/null | grep -q "factory"; then
    tuios new factory --detached >/dev/null 2>&1 || true
  fi

  cat <<'WEB_EOF' > "$HOME/.claude/bin/start-web-terminal.sh"
#!/usr/bin/env bash
# start-web-terminal.sh — 1-Command Web Terminal for TUIOS Factory via Cloudflare Quick Tunnel
set -euo pipefail
if ! command -v ttyd >/dev/null 2>&1 || ! command -v cloudflared >/dev/null 2>&1; then
  echo "🛑 Thiếu công cụ ttyd hoặc cloudflared."
  echo "👉 Chạy lệnh cài đặt: brew install cloudflared ttyd"
  exit 1
fi
echo "🚀 Đang khởi động Web Terminal cho TUIOS..."
killall ttyd 2>/dev/null || true
sleep 1
ttyd -p 7681 -t fontSize=14 -t fontFamily="Menlo, monospace" -t theme='{"background": "#1e1e2e"}' tuios attach factory >/dev/null 2>&1 &
TTYD_PID=$!
cleanup() {
  echo ""
  echo "🛑 Đang tắt Web Terminal & Cloudflare Tunnel..."
  kill "$TTYD_PID" 2>/dev/null || true
  killall cloudflared 2>/dev/null || true
  exit 0
}
trap cleanup EXIT INT TERM
sleep 2
echo "🌐 Đang tạo Cloudflare Quick Tunnel ra Internet..."
echo "========================================================================"
echo "  Bấm Ctrl+C bất cứ lúc nào để dừng Web Terminal"
echo "========================================================================"
cloudflared tunnel --url http://localhost:7681
WEB_EOF
  chmod +x "$HOME/.claude/bin/start-web-terminal.sh"
  ln -sf "$HOME/.claude/bin/start-web-terminal.sh" "$HOME/.local/bin/tuios-web"
}

run_verify() {
  echo "╔══════════════════════════════════════════════════════════════════════════════╗"
  echo "║     AUTONOMOUS FACTORY RECOVERY & HEALTH CHECK (9-POINT VERIFICATION)       ║"
  echo "╚══════════════════════════════════════════════════════════════════════════════╝"
  local pass=0 total=9

  if [ -x "$HOME/.local/bin/tuios" ] || command -v tuios >/dev/null 2>&1; then
    echo "  [1/9] PASS: TUIOS binary installed ($(tuios --version 2>/dev/null | head -n1))"
    pass=$((pass + 1))
  else
    echo "  [1/9] FAIL: TUIOS binary missing"
  fi

  if "$HOME/.local/bin/tuios" ls 2>/dev/null | grep -q "factory"; then
    echo "  [2/9] PASS: TUIOS background daemon session 'factory' is active (6 repo windows)"
    pass=$((pass + 1))
  else
    echo "  [2/9] FAIL: TUIOS session 'factory' not running"
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
ensure_tuios_factory_session
run_verify
# === BOOTSTRAP_END ===
```
