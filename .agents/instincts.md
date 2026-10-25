# Instincts & Failure Memory — Repository Lessons Learned

> **Quy định Vận hành cho AI Agent:**
> Tệp này ghi nhận lại các "bẫy mã nguồn" (traps), sai lầm trong quá khứ hoặc lỗi hồi quy từng xảy ra trên codebase này.
> Trước khi sửa code hoặc đề xuất giải pháp, AI Agent BẮT BUỘC phải đọc lướt qua các bẫy dưới đây để **tuyệt đối không đi vào vết xe đổ**.
> Khi gặp một lỗi mới hoặc bài học kinh nghiệm sâu sắc, AI Agent phải tự giác cập nhật thêm một mục vào tệp này.

---

## 1. Bẫy Thường Gặp & Bài Học Kinh Nghiệm (Active Instincts)

### [INSTINCT-001] Tránh Mất Mát Mã Nguồn Do Placeholder Lười Biếng
- **Hiện tượng lỗi:** Khi chỉnh sửa file dài, agent tự động phát sinh `// ... existing code ...` hoặc `# keep existing logic`, làm bay màu các hàm xung quanh khi lưu file.
- **Nguyên nhân gốc rễ:** Model cố gắng tối ưu token đầu ra nên bỏ qua đoạn giữa.
- **Quy tắc bắt buộc:** Luôn thay thế trọn vẹn khối mã liền mạch, kiểm tra độ dài file và git diff trước khi xác nhận hoàn tất.
- **Kiểm tra tự động:** `grep -En "// \.\.\.|\/\* \.\.\.|\# \.\.\." <modified_files>` phải trả về 0 kết quả.

---

### [INSTINCT-002] Chống Đúp Request & Spam Thao Tác (Button Double-Click)
- **Hiện tượng lỗi:** Người dùng click nhanh hoặc mạng lag làm gọi API/workflow 2 lần liên tiếp, dẫn tới trùng lặp dữ liệu hoặc lỗi race condition.
- **Nguyên nhân gốc rễ:** Thiếu debounce / disable trạng thái nút bấm ngay tại millisecond đầu tiên.
- **Quy tắc bắt buộc:** Mọi nút bấm kích hoạt xử lý bất đồng bộ hoặc gọi API đều phải có biến `isLoading` / `isSubmitting` để disable nút và hiển thị indicator ngay lập tức.

---

### [INSTINCT-003] Không Tái Phát Minh Bánh Xe (Don't Reinvent The Wheel)
- **Hiện tượng lỗi:** Tạo mới `DateUtils`, `StringHelper` hay `HttpWrapper` trong khi dự án đã có sẵn module tương tự ở thư mục chung.
- **Nguyên nhân gốc rễ:** Không tìm kiếm codebase trước khi bắt tay vào code.
- **Quy tắc bắt buộc:** Luôn chạy `grep_search` hoặc graph search các từ khóa liên quan trong project để tái sử dụng tiện ích nội bộ có sẵn.

---

### [INSTINCT-004] Bảo Vệ Bí Mật Môi Trường & Dữ Liệu Nhạy Cảm
- **Hiện tượng lỗi:** Hardcode API key, password, private key hoặc token test vào mã nguồn hoặc file test.
- **Nguyên nhân gốc rễ:** Tiện tay khi debug hoặc viết test nhanh.
- **Quy tắc bắt buộc:** Luôn đọc qua biến môi trường (`process.env`, `System.getenv`) hoặc file cấu hình nằm trong `.gitignore`. Che / mask dữ liệu nhạy cảm trước khi chụp ảnh báo cáo.

---

### [INSTINCT-005] Vùng Chạm Giao Diện Dưới Chuẩn Tiếp Cận (< 48dp)
- **Hiện tượng lỗi:** Nút bấm quá nhỏ hoặc quá sát nhau khiến người dùng khó tương tác trên màn hình cảm ứng hoặc web di động.
- **Nguyên nhân gốc rễ:** Chỉ căn chỉnh theo mắt nhìn trên màn hình desktop độ phân giải cao.
- **Quy tắc bắt buộc:** Mọi phần tử click/tap phải đảm bảo kích thước tối thiểu $\ge 48\times 48\text{dp}$ ($\ge 44\times 44\text{px}$ trên Web). Khoảng cách tối thiểu giữa 2 nút liền kề $\ge 8\text{dp}$.

---

### [INSTINCT-006] Chặn Luồng Chính (Main Thread) & Bẫy Hiệu Năng $O(N^2)$
- **Hiện tượng lỗi:** Ứng dụng bị đơ (ANR trên Android, lag/freeze UI trên Web/Desktop), giật khung hình khi cuộn danh sách lớn, hoặc rò rỉ bộ nhớ (OOM).
- **Nguyên nhân gốc rễ:** Thực hiện I/O (đọc file, DB, network) trên UI Thread, lồng vòng lặp $O(N^2)$ trên mảng động thay vì dùng HashMap/Set, hoặc quên đóng FileStream/Cursor/Listener.
- **Quy tắc bắt buộc:** 
  1. 100% I/O và tính toán nặng phải offload sang background coroutine / worker.
  2. Bắt buộc tra cứu $O(1)$ qua Map/Set khi join/filter 2 tập dữ liệu.
  3. Bắt buộc dùng `use` / `try-with-resources` để đóng 100% tài nguyên stream/connection.

---

### [INSTINCT-007] Nuốt Lỗi Âm Thầm (Empty Catch Block / Silent Exception)
- **Hiện tượng lỗi:** Ứng dụng chạy sai luồng dữ liệu, nút bấm không phản hồi nhưng không hề có thông báo hay crash log ("Ghost Bug").
- **Nguyên nhân gốc rễ:** Dùng `catch (e) {}` hoặc `except: pass` để "chữa cháy" cho qua unit test mà không xử lý hoặc log lỗi.
- **Quy tắc bắt buộc:** Nghiêm cấm khối catch rỗng. Bắt buộc ghi log lỗi kèm ngữ cảnh (Contextual Error Logging) hoặc hiển thị UI Error Boundary.

---

### [INSTINCT-008] Treo Vô Hạn Do Thiếu Timeout & Trùng Lặp Giao Dịch
- **Hiện tượng lỗi:** Ứng dụng quay vòng tròn loading vĩnh viễn khi mạng rớt; hoặc người dùng bị trừ tiền / tạo 2 đơn hàng khi mạng chập chờn.
- **Nguyên nhân gốc rễ:** Không set Timeout cho HTTP client; thiếu Idempotency-Key trên các request POST/PUT nhạy cảm.
- **Quy tắc bắt buộc:** 100% request mạng phải có timeout (Connect $\le 10\text{s}$, Read $\le 15\text{s}$). Mọi mutation request nhạy cảm phải gửi kèm header `Idempotency-Key`.

---

### [INSTINCT-009] In Log Thô (console.log / println) & Lộ Thông Tin Nhạy Cảm (PII)
- **Hiện tượng lỗi:** Log tràn ngập console production làm nghẽn I/O; lộ mật khẩu, access token, OTP hoặc số định danh trong Crashlytics / hệ thống log.
- **Nguyên nhân gốc rễ:** Thói quen debug bằng `console.log` / `println` thay vì Structured Logger; in thẳng toàn bộ payload request.
- **Quy tắc bắt buộc:** Nghiêm cấm log chuỗi thô trên production; bắt buộc dùng Structured Logger có log level; 100% dữ liệu nhạy cảm/Token phải được mask trước khi log.

---

### [INSTINCT-010] Sập Ứng Dụng Do Nâng Cấp Schema CSDL Thiếu Migration
- **Hiện tượng lỗi:** Người dùng cập nhật app lên bản mới thì bị văng ngay khi mở app (`Room cannot verify data integrity`).
- **Nguyên nhân gốc rễ:** Sửa đổi cấu trúc Entity/Table nhưng quên viết Migration Script hoặc dùng `fallbackToDestructiveMigration` làm mất sạch dữ liệu.
- **Quy tắc bắt buộc:** Mọi thay đổi schema CSDL phải có migration script và có bài test kiểm tra nâng cấp từ bản cũ lên bản mới.

---

## 2. Nhật Ký Bẫy Mã Nguồn Bổ Sung (Dành cho Dev / Agent thêm mới)

<!--
Mẫu ghi nhận:
### [INSTINCT-XXX] <Tên bẫy / Tình huống>
- **Ngày phát hiện:** YYYY-MM-DD
- **Hiện tượng lỗi:** <Mô tả lỗi hoặc hồi quy>
- **Nguyên nhân:** <Tại sao lại xảy ra>
- **Quy tắc phòng ngừa:** <Cách làm đúng từ nay về sau>
- **Lệnh kiểm tra:** <Câu lệnh kiểm tra tự động nếu có>
-->

---

### [INSTINCT-011] Luật bắt buộc chỉ nằm trong file đọc khi cần thì agent bỏ qua
- **Ngày phát hiện:** 2026-09-25
- **Hiện tượng lỗi:** Luật bắt buộc chỉ nằm trong file đọc khi cần thì agent bỏ qua
- **Nguyên nhân:** Báo cáo nghiệm thu 4 mục chỉ ở core-rules §1.3 (on-demand), essentials luôn nạp không nhắc và không hook nào kiểm — một lượt push bàn giao thiếu nó mà không gì chặn (2026-09-25); thang lười cũng từng như vậy
- **Quy tắc phòng ngừa & Cách fix:** Luật áp cho mọi lượt phải có bản tóm tắt trong rules/essentials.md VÀ một hook/gate ép khi có thể; khi thêm luật BẮT BUỘC vào core-rules, grep essentials xem đã có chưa

---

### [INSTINCT-012] Sửa hook DevKit tại chỗ làm hỏng mọi phiên đang chạy
- **Ngày phát hiện:** 2026-09-25
- **Hiện tượng lỗi:** Sửa hook DevKit tại chỗ làm hỏng mọi phiên đang chạy
- **Nguyên nhân:** Hook trong .claude/hooks là symlink vào checkout DevKit, được đọc trực tiếp ở mỗi Stop của mọi phiên và mọi project; ghi đè bằng open('w') cắt rỗng file trước khi ghi, một Stop chạy đúng lúc đó đọc file dở và lỗi cú pháp (2026-09-25)
- **Quy tắc phòng ngừa & Cách fix:** Sửa file hook/gate của DevKit bằng ghi file tạm rồi os.replace (nguyên tử), giữ quyền thực thi; chạy bash -n và hook với một input mẫu trên FILE TẠM, chỉ os.replace khi cả hai đạt — không phải sau khi đã thay
- **Tái phát 2026-09-26:** ghi nguyên tử nhưng kiểm SAU khi thay: một dấu nháy đơn ("body's") trong python của `python3 -c '…'` làm block-dangerous-git.sh lỗi cú pháp, exit 2 chặn MỌI lệnh Bash ở mọi project 1–2 phút (phiên GeelyEx2 báo). Trong khối `-c '…'` không viết `'`, dùng `\x27`

---

### [INSTINCT-013] Nhận cờ CLI bằng regex 'có chữ X trong từ' cho lọt giá trị dính cờ
- **Ngày phát hiện:** 2026-09-26
- **Hiện tượng lỗi:** Nhận cờ CLI bằng regex 'có chữ X trong từ' cho lọt giá trị dính cờ
- **Nguyên nhân:** hardware_safety_gate xét '^-[A-Za-z]*[dcgtL]' là cờ dump nên -vtime, -bcrash (vẫn stream) được cho qua; từ 'logcat' ở bất kỳ vị trí nào bị coi là lệnh nên 'pkill logcat' bị chặn nhầm (review 2026-09-26)
- **Quy tắc phòng ngừa & Cách fix:** Cờ cho qua phải khớp NGUYÊN từ (^-[dcg]+$, ^-t\d*$); lệnh xét theo vị trí lệnh (chỉ nohup/setsid/timeout N đứng trước); mỗi luật mới có ca âm với giá trị dính cờ và ca tên lệnh làm đối số

---

### [INSTINCT-014] Gate nhận lệnh shell chỉ ở đầu đoạn và coi mọi file lạ là code
- **Ngày phát hiện:** 2026-09-27
- **Hiện tượng lỗi:** Gate nhận lệnh shell chỉ ở đầu đoạn và coi mọi file lạ là code
- **Nguyên nhân:** hardware_safety_gate chỉ nhận adb đứng đầu đoạn lệnh nên 'then adb -s &lt;máy denylist> reboot' lọt; security_gate coi redirect ra scratchpad và '>' trong code Python là ghi vào repo; post-fix-gate coi ảnh proof và config agent là code cần test — 22+ lần chặn nhầm trong 1 ngày (2026-09-27)
- **Quy tắc phòng ngừa & Cách fix:** Gate phân tích lệnh shell phải bỏ qua từ khoá ghép (if/then/do/else/{/() trước khi xét vị trí lệnh; chỉ tính ghi khi đích nằm trong repo; file do agent tự sinh (reports/proof-*.png, .antigravity-pm.json, .adb-denylist, memory) không cần test; mỗi luật nới có ca âm đối kháng (biến gán lại, for/read, repo khác) viết trước

---

### [INSTINCT-015] Hai chỗ trong DevKit phân loại cùng một thứ khác nhau
- **Ngày phát hiện:** 2026-09-28
- **Hiện tượng lỗi:** Hai chỗ trong DevKit phân loại cùng một thứ khác nhau
- **Nguyên nhân:** needs_no_test (post-fix-gate) không coi *.log là tài liệu dù tree_fp đã coi; RUNNER_FAIL_RX không đọc failures="N" của JUnit XML dù gate XML đọc được; proof_gate coi git push trong repo nháp là bàn giao — agent GeelyEx2 bị chặn nhầm và một lần chạy đỏ bị tính là xanh (2026-09-28)
- **Quy tắc phòng ngừa & Cách fix:** Khi thêm/đổi luật phân loại (file không cần test, dấu hiệu đỏ, lệnh bàn giao) ở một gate, grep mọi gate khác có luật cùng loại và dùng chung một hàm/regex; mỗi dạng output thật agent hay in (log redirect, XML tóm tắt) phải có ca test ĐỎ và XANH

---

### [INSTINCT-016] Cài DevKit từ bản stage cũ ghi đè commit của phiên khác
- **Ngày phát hiện:** 2026-09-28
- **Hiện tượng lỗi:** Cài DevKit từ bản stage cũ ghi đè commit của phiên khác
- **Nguyên nhân:** Stage chép từ bản đang chạy lúc bắt đầu việc; một phiên khác commit vào cùng file sau đó; install_atomic ghi đè cả file bằng bản stage nên mất hunk của commit 7e2ea43 (2 lần, 2026-09-28)
- **Quy tắc phòng ngừa & Cách fix:** Trước khi cài một file: so bản đang chạy với HEAD và với bản gốc của stage; nếu HEAD đã đổi thì gộp 3 chiều (git merge-file) hoặc sửa tại chỗ bằng thay đúng đoạn (đọc từ đĩa, ghi file tạm + os.replace); không bao giờ ghi đè cả file bằng bản trong bộ nhớ; sau khi cài kiểm git diff HEAD không có dòng xoá lạ

---

### [INSTINCT-017] Khoá cache dựng sai làm dùng nhầm hoặc không bao giờ dùng lại kết quả test
- **Ngày phát hiện:** 2026-09-29
- **Hiện tượng lỗi:** Khoá cache dựng sai làm dùng nhầm hoặc không bao giờ dùng lại kết quả test
- **Nguyên nhân:** testsourceset_gate băm scope bằng shasum (máy thiếu shasum → mọi scope chung 1 khoá, PASS của lib dùng cho lib2); regression_gate so fingerprint devkit_harness (20 hex) với receipt tree_fp (24 hex) nên đoạn đi tắt chết; post-fix-gate chỉ kiểm cache TRƯỚC khi chờ khoá test nên lượt chờ chạy lại toàn bộ suite (2026-09-29)
- **Quy tắc phòng ngừa & Cách fix:** Khoá cache chỉ dựng bằng python3 hashlib/cùng một hàm fingerprint (bin/tree_fp) ở mọi nơi đọc và ghi; không tính được khoá thì không dùng cache; kiểm lại cache sau khi chờ khoá; mỗi khoá có ca test ĐỎ cho 'khoá khác nhau phải không dùng chung PASS'

---

### [INSTINCT-018] Kết quả 'không chạy được trên máy này' làm kẹt mốc đã kiểm nên mọi lượt Stop chạy lại cả dải commit
- **Ngày phát hiện:** 2026-09-30
- **Hiện tượng lỗi:** Kết quả 'không chạy được trên máy này' làm kẹt mốc đã kiểm nên mọi lượt Stop chạy lại cả dải commit
- **Nguyên nhân:** regression_gate.sh chỉ dời verified_head khi gate exit 0/3; suite REG-QC-05 (test trên xe thật, untested_exit) làm mọi lượt ra exit 4 nên mốc kẹt ở b747…, mỗi Stop GeelyEx2 chạy lại toàn bộ suite cho dải --since ngày càng dài (4-5 phút, 16 lần); --full exit 4 còn xoá receipt nên cache không bao giờ dùng lại (2026-09-29)
- **Quy tắc phòng ngừa & Cách fix:** Mọi trạng thái kết thúc hợp lệ của gate (PASS, UNTESTED theo untested_exit) phải dời mốc đã kiểm và được nhớ theo khoá gồm nội dung cây; chỉ BUSY/FAIL mới không dời; mỗi trạng thái có test 'Stop lần 2 cùng nội dung không chạy lại gate'

---

### [INSTINCT-019] Đo thời gian hook bằng đồng hồ tường mà không trừ lúc máy ngủ
- **Ngày phát hiện:** 2026-09-30
- **Hiện tượng lỗi:** Đo thời gian hook bằng đồng hồ tường mà không trừ lúc máy ngủ
- **Nguyên nhân:** durationMs của stop_hook_summary tính cả lúc laptop ngủ: một lượt Stop 420 s ở GeelyEx2 thật ra là 417 s máy ngủ (pmset: Sleep 07:01:52, 417 secs, pin 4%), một lượt 2698 s ở OfficeReader cũng vậy; audit ban đầu quy nhầm cho review_gate và thổi số trung bình lên (2026-09-30)
- **Quy tắc phòng ngừa & Cách fix:** Audit tốc độ phải trừ các khoảng Sleep lấy từ 'pmset -g log' (dòng Sleep có '&lt;N> secs'; không ghép Sleep với dòng 'Wake Requests') khỏi khoảng [kết thúc − thời lượng, kết thúc] của từng lượt; mọi hook cùng lượt bằng nhau ~X giây là dấu hiệu máy ngủ, không phải hook chậm

---

### [INSTINCT-020] Dọn/kiểm kê worktree đọc lỗi git thành 'sạch' và cho file mới lọt allowlist theo tiền tố
- **Ngày phát hiện:** 2026-09-30
- **Hiện tượng lỗi:** Dọn/kiểm kê worktree đọc lỗi git thành 'sạch' và cho file mới lọt allowlist theo tiền tố
- **Nguyên nhân:** sandbox cleanup và worktree status bỏ qua returncode của git status/rev-list (stdout rỗng = sạch), dùng --untracked-files=no, allowlist theo tiền tố thư mục, đo ahead bằng 'trừ mọi ref khác'; việc ở worktree này bị xoá khi gom worktree khác
- **Quy tắc phòng ngừa & Cách fix:** kiểm kê fail-closed: rc≠0 hoặc None = chưa gộp; file mới chưa add là việc thật (-uall, so byte với bản nguồn mới coi là bỏ được); đo 'chưa gộp' bằng main_head..head, đo 'sẽ mất' riêng bằng ref; chạy agent-kit worktree status trước khi gộp hoặc xoá bất kỳ worktree nào

---

### [INSTINCT-021] Nguồn tự dò mới giành quyền cấu hình đã khai
- **Ngày phát hiện:** 2026-09-30
- **Hiện tượng lỗi:** Nguồn tự dò mới giành quyền cấu hình đã khai
- **Nguyên nhân:** proof-capture thêm nhánh 'có iOS Simulator Booted thì chụp simulator' nhưng chỉ coi provider có serial là đã khai; provider chỉ khai avd (và 2 simulator Booted) bị đẩy sang simctl/fail, đổi hành vi adb đang chạy (review 7de08da, 2026-09-30)
- **Quy tắc phòng ngừa & Cách fix:** Thêm một nguồn tự dò (thiết bị, file, env) thì liệt kê MỌI trường cấu hình người dùng có thể khai (serial, avd, udid, type…) — trường nào có mặt thì nó thắng; tự dò chỉ quyết khi không khai gì và kết quả đúng 1 ứng viên, còn lại rơi về đường cũ. Viết test 'đã khai X + nguồn tự dò có mặt → vẫn đường cũ' cho từng trường.

---

### [INSTINCT-022] Gắn skill vào intent rộng làm đổi dòng 'Skill phù hợp' và đẩy skill khác khỏi top 5
- **Ngày phát hiện:** 2026-10-01
- **Hiện tượng lỗi:** Gắn skill vào intent rộng làm đổi dòng 'Skill phù hợp' và đẩy skill khác khỏi top 5
- **Nguyên nhân:** enrich_context khử trùng lặp theo cả dòng và cắt skills[:5]; thêm skill vào nhánh UI_INTERACTION khiến prompt bug 'xoay màn hình' có dòng skill khác (test_prompt_dedupe đỏ) và đẩy android-real-device-qa/qa-visual ra
- **Quy tắc phòng ngừa & Cách fix:** Skill chuyên biệt có nhánh từ khoá riêng, hẹp; sau khi sửa enrich_context chạy cả tests/context_memory/test_prompt_context.sh và hooks/tests/test_prompt_dedupe.sh (run_impacted không tự chạy test dedupe)

---

### [INSTINCT-023] Swift Concurrency / MainActor Isolation & Task Cancellation Leak
- **Ngày phát hiện:** 2026-10-02
- **Hiện tượng lỗi:** UI SwiftUI giật lag hoặc crash runtime "Publishing changes from background threads is not allowed"; hoặc Task chạy ngầm tiếp tục fetch network/tiêu thụ pin sau khi View đã bị dismiss.
- **Nguyên nhân:** Cập nhật `@Published` / `@Observable` state từ background async task mà không cô lập `@MainActor`; tạo `Task { ... }` không giữ reference hoặc không handle `Task.isCancelled` khi view lifecycle kết thúc (`.onDisappear`).
- **Quy tắc phòng ngừa & Cách fix:** Mọi ViewModel/State binding cập nhật UI bắt buộc gắn `@MainActor`; background async task dài hạn phải kiểm tra `try Task.checkCancellation()`; dùng `.task { ... }` modifier gắn liền với vòng đời View thay vì `onAppear { Task { ... } }`.

---

### [INSTINCT-024] Android StateFlow Lifecycle Collection & Main Thread Blocking trong Jetpack Compose
- **Ngày phát hiện:** 2026-10-02
- **Hiện tượng lỗi:** App tiêu hao pin/bộ nhớ ngầm ngay cả khi user đã minimize app ra background; hoặc ANR 5s khi composable render.
- **Nguyên nhân:** Dùng `flow.collectAsState()` trong Jetpack Compose thay vì `collectAsStateWithLifecycle()`, khiến Flow upstream tiếp tục emit dữ liệu khi app ở `Lifecycle.State.STOPPED`; thực hiện JSON parsing / Database fetch trực tiếp trong Composable function.
- **Quy tắc phòng ngừa & Cách fix:** Bắt buộc dùng `collectAsStateWithLifecycle()` cho mọi StateFlow trong Compose; 100% logic tính toán nặng/IO phải bọc trong `LaunchedEffect(key) { withContext(Dispatchers.IO) { ... } }` hoặc đưa vào ViewModel.


---

### [INSTINCT-025] Chia nhóm thư mục làm hỏng đường dẫn mà grep chuỗi literal không bắt hết, và hook nuốt lỗi bằng 2>/dev/null che mất
- **Ngày phát hiện:** 2026-10-02
- **Hiện tượng lỗi:** Sau khi chia scripts/ thành 6 nhóm, 13 test gọi script ở đường dẫn cũ và hook session_context.sh âm thầm bỏ qua toàn bộ khối checklist/STALE ở đầu phiên
- **Nguyên nhân:** Cổng chỉ chạy các test nhắc tên file đổi nên 13 test hỏng không bao giờ được chạy; session_context.sh suy ra bin/ bằng dirname(dirname(index_memory.py)) và ghép stale_rerun.py cạnh index_memory.py, mà hai file nay ở hai thư mục khác nhau; khối Python chạy dưới 2>/dev/null nên import lỗi không để lại dấu vết (2026-10-02)
- **Quy tắc phòng ngừa & Cách fix:** Sau khi di chuyển file: (1) lấy danh sách chính thức bằng git show --name-status -M rồi grep cả đường dẫn cũ LẪN các phép ghép đường dẫn (dirname(...)/x.py, os.path.dirname lồng nhau, sys.path.insert), không chỉ chuỗi scripts/x.py; (2) chạy MỌI script test trước và sau, so sánh từng script về mã thoát và số ca đạt, không dựa vào lựa chọn test tác động của cổng; (3) hook chạy Python dưới 2>/dev/null phải có test khẳng định ĐẦU RA chứa khối mong đợi

---

### [INSTINCT-026] Thêm khối ngữ cảnh luôn bật vào hook prompt: dedupe theo dòng, bẫy UI chen slot, từ khoá UI mơ hồ và hợp đồng chit-chat im lặng
- **Ngày phát hiện:** 2026-10-03
- **Hiện tượng lỗi:** Cửa UI của enrich_context (mandate Zero-Slop nhiều dòng + intent UI bật theo profile) qua audit và review có 5 lỗ: mandate dính dòng NFR bị gửi lại hoặc mồ côi gạch đầu dòng; INTENT_TERMS làm bẫy click/48dp chen lên trước bẫy của prompt DOCX; hook_contract_test 'chit-chat adds nothing' đỏ trên fixture profile web; từ UI mới (screen, panel, dialog, theme, font, view, card, compose) bắt nhầm sql view, compose.yaml, Grafana panel, Dialogflow; agent bridge không dedupe nên Gemini nhận mandate ở mọi prompt
- **Nguyên nhân:** dedupe_session bỏ lặp từng dòng theo tiền tố ONCE_PER_SESSION; INTENT_TERMS và ngưỡng shown_refs coi mọi intent là bằng chứng về prompt; mentions() coi từ từ 4 ký tự trở lên là tiền tố; hooks/agent_bridge.sh nhánh prompt từng không chuyển session_id; run_impacted chọn test theo tên file nên một lần sửa enrich_context.py không kéo hook_contract_test.sh (chỉ nêu prompt_context) vào gate (2026-10-03)
- **Quy tắc phòng ngừa & Cách fix:** Dòng mới trong compact() muốn gửi một lần mỗi phiên phải bắt đầu bằng tiền tố trong ONCE_PER_SESSION, khối nhiều dòng thì mỗi dòng một tiền tố; intent không do từ UI tương tác bật (chỉ profile, hoặc chỉ từ kiểu dáng / thẩm mỹ) không nạp INTENT_TERMS; intent chỉ do profile còn ghi vào dossier['profile_intents'] để không hạ ngưỡng shown_refs; từ khoá UI mơ hồ đi qua UI_WHOLE_WORDS, nghĩa backend vào NON_TECHNICAL_PHRASES, mỗi cụm có ca âm ở test_prompt_context mục 1b, và cụm chứa từ định tuyến (compose) phải có ranh giới từ vì 'compose up' nuốt cả 'recompose up'; nhánh prompt của hooks/agent_bridge.sh phải chuyển session_id / conversation_id (đã sửa 2026-10-04), không thì Gemini/Codex/Cursor không dedupe và khối luôn bật tốn ở mọi prompt; sau khi sửa enrich_context.py cả ba test test_prompt_context, test_prompt_dedupe, hook_contract_test nay do run_impacted tự chọn qua tests/impact_map.txt (từ 2026-10-04); ai thêm file đọc qua script khác nhớ thêm dòng vào bảng
- **Lệnh kiểm tra:** `bash universal-agent-devkit/tests/context_memory/test_prompt_context.sh && bash universal-agent-devkit/hooks/tests/test_prompt_dedupe.sh && bash universal-agent-devkit/hooks/tests/hook_contract_test.sh > /dev/null`

---

### [INSTINCT-027] Lối tắt của cổng tin trạng thái agent ghi được và tái dùng bộ phân loại của việc khác
- **Ngày phát hiện:** 2026-10-04
- **Hiện tượng lỗi:** 4 sửa workflow (đẩy tag cũ, gate tài liệu/đầu ra, bắt bug, health) qua test của chính chúng nhưng reviewer ngữ cảnh sạch tìm 6 lỗ P2: X:X đẩy tag lên nhánh remote trùng tên, tên tag trần resolve thành pseudoref ORIG_HEAD, --git-dir/GIT_DIR làm hook kiểm sai repo, refs/remotes/* do agent ghi làm commit chưa push trông như đã push, needs_no_test tắt chốt test-bị-sửa cho .log/golden/code dưới reports/, regex loại trừ làm mất báo lỗi thật (bị cũ, bị hết hạn, lỗi thời gian)
- **Nguyên nhân:** Lối tắt viết quanh ca thật và test chỉ có ca thật cộng đối chứng dễ: tin bằng chứng cục bộ agent ghi được (refs/remotes, rev-parse DWIM) thay vì nguồn chứng thực (ls-remote); dùng lại needs_no_test cho việc khác (file có phải test không) nên miễn rộng hơn ý định; ngoại lệ regex viết từ ví dụ một câu
- **Quy tắc phòng ngừa & Cách fix:** Lối tắt trong cổng: miễn trừ hẹp theo ca thật, không tái dùng bộ phân loại của việc khác; đối chiếu với nguồn chứng thực (git ls-remote), truyền tên ref đầy đủ (refs/tags/…), tắt lối tắt khi lệnh đổi repo (--git-dir, GIT_DIR) hoặc có spec không phải commit; mỗi ngoại lệ regex kèm ca dương tính cùng chữ khác nghĩa. Chạy reviewer ngữ cảnh sạch với lệnh tìm cách vượt TRƯỚC khi cài; dò cả cờ làm bỏ qua cả khối kiểm (--all, --tags)
- **Lệnh kiểm tra:** `bash universal-agent-devkit/tests/gates/test_push_gate_tags.sh && bash universal-agent-devkit/tests/gates/test_gate_nontest_docs.sh && bash universal-agent-devkit/tests/verification/test_bug_capture.sh && bash universal-agent-devkit/tests/verification/test_health_githook_chain.sh`
- **Nguồn:** audit workflow DevKit 04/10 (review ngữ cảnh sạch)

---

### [INSTINCT-028] Nới nhánh bỏ qua gate biến lỗ phân loại cũ thành fail-open
- **Ngày phát hiện:** 2026-10-09
- **Hiện tượng lỗi:** Nới nhánh bỏ qua gate biến lỗ phân loại cũ thành fail-open
- **Nguyên nhân:** 2026-10-09 Dot 11: regression_gate cho lượt không dòng trạng thái được bỏ qua test nếu OUTCOME không thấy claim; OUTCOME phân biệt hoa/thường nên 'Đã fix…', 'Fixed', 'Done.', 'Xong:' bị coi là làm dở và bỏ qua test — trước đó lỗ này vô hại vì chỉ áp cho câu CHƯA XONG. Cùng ngày: nhả khoá ở Stop sẽ đua với gate cuối lượt vì các hook Stop chạy SONG SONG (docs Claude Code).
- **Quy tắc phòng ngừa & Cách fix:** Khi mở rộng điều kiện SKIP của một gate: liệt kê mọi câu bàn giao thật (mọi kiểu hoa/thường, dòng trạng thái ở dòng sau, tiếng Anh/Việt) thành ca test phải bị chặn, chạy ĐỎ trên bộ phân loại hiện tại trước khi nới; từ khoá claim không phân biệt hoa/thường, chỉ XONG/PASS viết hoa. Tín hiệu 'phiên rảnh' dùng Notification idle_prompt, không dùng Stop.

---

### [INSTINCT-029] Test bảo vệ không được sandbox RED-proof chọn nên bằng chứng ra VACUOUS giả
- **Ngày phát hiện:** 2026-10-09
- **Hiện tượng lỗi:** Test bảo vệ không được sandbox RED-proof chọn nên bằng chứng ra VACUOUS giả
- **Nguyên nhân:** run_impacted.sh chỉ chọn test có nhắc TÊN file đổi; test_bug_capture.sh chạm enrich_context.py qua prompt_context.sh nên không bao giờ được chọn: gate không chạy nó và RED-proof (sandbox không có upstream, cửa sổ 6 giờ) kết luận test không bắt bug (2026-10-09)
- **Quy tắc phòng ngừa & Cách fix:** Trước khi tin VACUOUS/INCONCLUSIVE chạy run_impacted.sh --list với file bị đưa bug trở lại; thiếu test bảo vệ thì thêm dòng vào tests/impact_map.txt (kèm test). Đặt DEVKIT_IMPACTED_SINCE=0 khi chứng minh trong sandbox

---

### [INSTINCT-030] bash 3.2 cắt đối số "$(cmd "{\"a\":…}")" tại dấu nháy thoát
- **Ngày phát hiện:** 2026-10-09
- **Hiện tượng lỗi:** bash 3.2 cắt đối số "$(cmd "{\"a\":…}")" tại dấu nháy thoát
- **Nguyên nhân:** Trên macOS /bin/bash 3.2 một từ dạng "$(f x "…\"…\"…")" làm đối số lệnh bị tách ở dấu nháy thoát; hook chạy trên payload rác và test camelCase khẳng định sai rc (2026-10-09), Linux bash 5 không lỗi
- **Quy tắc phòng ngừa & Cách fix:** Dựng chuỗi có \" trong phép gán (v="$(cmd …)") rồi truyền "$v"; kiểm test bash bằng /bin/bash trên macOS, không chỉ bash 5

---

### [INSTINCT-031] Hook lexer: shlex hides what follows a hash, and the one-line fix opens a new hole
- **Ngày phát hiện:** 2026-10-10
- **Hiện tượng lỗi:** Hook lexer: shlex hides what follows a hash, and the one-line fix opens a new hole
- **Nguyên nhân:** shlex.shlex has commenters='#' by default, so everything after a '#' token never reached the judge (a comment line, or a#b, followed by a destructive command passed with rc 0) in block-dangerous-git.sh and hardware_safety_gate.sh. Setting commenters='' alone looked enough but a quote inside a REAL comment then makes shlex raise ValueError, the git hook falls back to its raw regex and loses its branch rules, and harmless commands with a trailing comment start to be blocked. Also: the Python of these hooks sits in a bash single-quoted python3 -c string, so one literal single quote in new code (even in a docstring) breaks the hook for every session.
- **Quy tắc phòng ngừa & Cách fix:** Cut real comments first (drop_comments: a # at the start of a word, outside quotes, up to the newline, BEFORE backslash-newline is joined), then set commenters=''. Test a comment with an apostrophe, a comment ending in a backslash, a#b and $'..' next to each command, in both directions (blocked and allowed). Write new hook Python with \x27, never a literal single quote. Edit live hooks as temp file + mv after testing in a cp -Rc clone of the kit.

---

### [INSTINCT-032] Stop hook that accepts a report from any earlier transcript line: the hook's own feedback holds the skeleton, and an odd line crashes it into a pass
- **Ngày phát hiện:** 2026-10-10
- **Hiện tượng lỗi:** Stop hook that accepts a report from any earlier transcript line: the hook's own feedback holds the skeleton, and an odd line crashes it into a pass
- **Nguyên nhân:** proof_gate report-after-push (10/10): a text pre-filter let every later line with the word text reach code that assumed a message object; Python in the hook exits 1 and the wrapper turns exit 1 into exit 0, so one odd line after a push let a reply with no report through. The Stop hook feedback itself (a user-role isMeta line) carries the 4-item skeleton, so without the assistant-role check the second Stop after a block passed. Both found only by a fresh-context review and a mutation run (mutant M6 survived until a case for the feedback line existed).
- **Quy tắc phòng ngừa & Cách fix:** A hook that reads a transcript line to accept something checks role, isSidechain, block type and shape before matching text; every hook test turns a Traceback in stderr into a failure (a crash is a pass); run mutants of each guard and add the case for every survivor.

---

### [INSTINCT-033] A gate that skips unfinished turns must remember what it skipped
- **Ngày phát hiện:** 2026-10-10
- **Hiện tượng lỗi:** A gate that skips unfinished turns must remember what it skipped
- **Nguyên nhân:** testsourceset_gate (backlog #3, 10/10) skipped the compile on a reply that says CHUA XONG. The handover turn finds work through git (uncommitted files plus verified_head..HEAD), but regression_gate moves verified_head for every session of the checkout, so a commit made in a skipped turn could be declared verified by another session and nothing was left to compile at the handover. Found only by a fresh-context review that replayed the two turns (mutation testing did not find it: no test had two turns).
- **Quy tắc phòng ngừa & Cách fix:** Every skip rule keeps a per-session list of what it did not check and adds it to the next check that runs; test it with two turns (skip, then handover) and with the shared mark moved in between.

---

### [INSTINCT-034] A hook that ages a green run by the last source edit must only count edits that belong to the project
- **Ngày phát hiện:** 2026-10-10
- **Hiện tượng lỗi:** A hook that ages a green run by the last source edit must only count edits that belong to the project
- **Nguyên nhân:** test_evidence_gate (10/10) took every Edit/Write of a file with a source extension as the last code edit, including helper scripts in the scratchpad the harness tells agents to use: 62 of 171 real blocks followed such a write. The first fix (ignore temp-dir writes) broke CHECK 7 for sessions whose every source edit is a scratch one (the marker stayed unset, the RED->GREEN pair could never be seen): 7 of 59 real transcripts flipped from pass to block. Found by a fresh-context review replaying real transcripts, not by the unit tests.
- **Quy tắc phòng ngừa & Cách fix:** When a rule drops a class of events from a marker, give every consumer of that marker a fallback and replay real transcripts old vs new: only the intended ones may change.

---

### [INSTINCT-035] zsh and && chains in install steps
- **Ngày phát hiện:** 2026-10-12
- **Hiện tượng lỗi:** zsh and && chains in install steps
- **Nguyên nhân:** zsh does not word-split command substitutions, so git add $(... | tr) passed one argument; and a chain a && b; c && mv still ran mv after a failed a, installing a half-checked hook
- **Quy tắc phòng ngừa & Cách fix:** use xargs for lists in zsh; one && chain from check to mv; python comments inside hooks sh carry no apostrophe

---

### [INSTINCT-036] A new tests/*/test_*.sh needs a line in tests/lib/test_durations.txt, and the gate only shows it when that test is selected
- **Ngày phát hiện:** 2026-10-13
- **Hiện tượng lỗi:** A new tests/*/test_*.sh needs a line in tests/lib/test_durations.txt, and the gate only shows it when that test is selected
- **Nguyên nhân:** test_run_impacted_order.sh fails on any tests/*/test_*.sh missing from tests/lib/test_durations.txt; 30 tests from earlier Dots were already unlisted at HEAD, so the first gate whose impacted set included the order test (Dot 28, 13/10) went red on 31 tests, not on its own
- **Quy tắc phòng ngừa & Cách fix:** When adding a test file, add '&lt;seconds> &lt;path>' to tests/lib/test_durations.txt in the same commit; before a gate on a new test run bash tests/verification/test_run_impacted_order.sh directly (a number measured under load is fine: only the start order uses it)

---

### [INSTINCT-037] A MUST/CẤM regex lint cannot see obligations phrased without a keyword, so an on-demand split needs a hand review and pinned guardrails
- **Ngày phát hiện:** 2026-10-13
- **Hiện tượng lỗi:** A MUST/CẤM regex lint cannot see obligations phrased without a keyword, so an on-demand split needs a hand review and pinned guardrails
- **Nguyên nhân:** Dot 28 moved rule blocks to an on-demand file after a regex check for MUST/CẤM/BẮT BUỘC/bất biến; two independent reviewers then found obligations the regex missed (analytics PII, 'đổi ranh giới = hỏi trước', 'luôn DOKill(true)', 'không thêm Singleton mới')
- **Quy tắc phòng ngừa & Cách fix:** Cut a rule block only after reading each line for an obligation (phải, không, luôn, chỉ khi, hỏi trước) and pin the ones that must stay in the LOADED text as needles in tests/context_memory/test_profile_split.sh; a rule that applies to every turn belongs in the loaded file (INSTINCT-011)

---

### [INSTINCT-038] A copy that keeps the source's macOS user flags (uchg) cannot be deleted, and git drops the worktree registration anyway
- **Ngày phát hiện:** 2026-10-13
- **Hiện tượng lỗi:** Seven unregistered GeelyEx2-* folders (150-200 MB each) left after agent-kit worktree finish; the next session could not reuse the name and made -1013b, -1013c
- **Nguyên nhân:** worktree.py _copy used shutil.copy2, which copies BSD flags: the user's keystore (chflags uchg) became an undeletable copy; git 2.55 worktree remove --force errors on it but still deletes the worktree's admin dir, so the folder stays, no guard lists it, nothing can retry. Earlier memory blamed the sandbox: a wrong mechanism chosen from the symptom alone
- **Quy tắc phòng ngừa & Cách fix:** Copy secrets with shutil.copy (content+mode), never copy2, cp -p or cp -c (clonefile keeps the flags too; worktree_sandbox.py had it as well); for a whole directory copied with cp -c -R run `chflags -R nouchg,nouappnd` on the copy and give shutil.copytree copy_function=shutil.copy (its default is copy2); make the copy with os.umask(0o077) set, because shutil.copy creates the file with the umask's mode and fixes it afterwards (a keystore is group/other readable in between); a remove/cleanup asks git FIRST and clears user flags only after git has dropped the registration (a refused removal must leave the user's flags alone), then verifies the folder is gone (fail closed, exit non-zero, name the path and the user's how-to: git can no longer remove an unregistered folder); use lchflags, never chflags, so a swapped-in link is not followed; before blaming a sandbox for EPERM, ls -lO the file: the flag is the discriminating evidence

---

### [INSTINCT-039] A gate shortcut that treats 'the folder is gone' as 'done' without proving the work reached trunk
- **Ngày phát hiện:** 2026-10-13
- **Hiện tượng lỗi:** A gate shortcut that treats 'the folder is gone' as 'done' without proving the work reached trunk
- **Nguyên nhân:** worktree_merge_gate dropped any worktree whose folder vanished (09/10 vanished filter) and the first race fix also passed a failed automerge when folder+registration were gone; an rm -rf (+prune) of unmerged commits then passed the Stop silently; the real flake was two automerge runs of one worktree overlapping
- **Quy tắc phòng ngừa & Cách fix:** 'Gone' is never proof: pass a vanished/removed worktree only when its listed HEAD is an ancestor of main or its branch moved past it to a tip in main (work_in_main); every such shortcut gets a paired must-hold case (removed WITHOUT landing) next to the must-pass case

---

### [INSTINCT-040] A FIFO at any agent-writable path a hook or gate opens hangs it, and a Stop hook killed at its timeout lets the Stop through
- **Ngày phát hiện:** 2026-10-14
- **Hiện tượng lỗi:** A FIFO at any agent-writable path a hook or gate opens hangs it, and a Stop hook killed at its timeout lets the Stop through
- **Nguyên nhân:** open(), a bash > / >> redirect and exec 9>> block on a FIFO; 14/10: full_pass.json, proof cache, test_run.lock, every hook's .claude/audit-gate/.gitignore and its own log hung post-fix-gate and 5 Stop hooks; the first fix covered the gate files but not the hooks' own logs (found only by a second clean-context review)
- **Quy tắc phòng ngừa & Cách fix:** Open agent-writable state with O_NONBLOCK and require fstat S_ISREG (post-fix-gate _state_fd, proof_gate open_reg); in hooks drop FIFOs at the top of .claude/audit-gate/ BEFORE the .gitignore line and before any log/lock open; test by planting a FIFO at every path the hook opens, with a timeout, on HEAD first (RED)

---

### [INSTINCT-041] A worktree is adopted on proof of death, never on a stale heartbeat
- **Ngày phát hiện:** 2026-10-15
- **Hiện tượng lỗi:** A worktree is adopted on proof of death, never on a stale heartbeat
- **Nguyên nhân:** worktree_merge_gate adopted (auto-commit, merge, REMOVE) the worktree of a session whose heartbeat was older than 600 s; a live session idle at its prompt or in one long tool call has no fresh heartbeat. get_active_sessions also DELETED the registry entry of a live-pid/stale-heartbeat session, and SessionEnd deletes it for ended ones, so 'no entry' means nothing either.
- **Quy tắc phòng ngừa & Cách fix:** Adopt or reown only when every known pid is dead (record line 2, then the registry) or a pid-less record is older than 24 h; one helper (session_lock.info_alive) for every caller; a probe that calls get_active_sessions before the Stop belongs in the test (case 10b), not just a stale-heartbeat fixture.

---

### [INSTINCT-042] A helper worktree made with --no-init fails agent-kit health, and the Stop hook gates it at every Stop
- **Ngày phát hiện:** 2026-10-15
- **Hiện tượng lỗi:** A helper worktree made with --no-init fails agent-kit health, and the Stop hook gates it at every Stop
- **Nguyên nhân:** agent-kit worktree add --no-init leaves no .claude/hooks, commands or @-imports, so REG-WB-CONFIG-01 is RED on its merged result; the merge-gate hook then re-ran a heavy gate on it at the end of EVERY turn (9+ times), loading the machine and making the real gate time out (REG-DK-ALL-01 780 s vs ~330 s) and fail.
- **Quy tắc phòng ngừa & Cách fix:** Make helper worktrees WITH init; never leave an unmerged helper worktree standing across turns; land the integration worktree first, then remove the helpers (a tree identical to main is removable without --force). Wait for background gates inside the turn (a for-loop with sleep), not by ending turns.

---

### [INSTINCT-043] A test that disables the global git config relies on git's auto-detected identity, which needs a hostname with a domain: on a host named Mac a gate's own git merge fails with 'Committer identity unknown'
- **Ngày phát hiện:** 2026-10-15
- **Hiện tượng lỗi:** A test that disables the global git config relies on git's auto-detected identity, which needs a hostname with a domain: on a host named Mac a gate's own git merge fails with 'Committer identity unknown'
- **Nguyên nhân:** git builds an identity from user + hostname only when the hostname has a dot. tests/gates/test_worktree_merge_gate_trunk.sh sets GIT_CONFIG_GLOBAL=/dev/null and its fixture repos had no user.name/user.email, so the hook's own merge commit (main into a worktree) had none. macOS renames the host with the network (Alexs-MacBook-Pro.local -> Mac), so a green test went red twice with no code change (15/10).
- **Quy tắc phòng ngừa & Cách fix:** Give every fixture repo user.name and user.email in ITS config (worktrees share it); never count on auto-detect. When a test with GIT_CONFIG_GLOBAL=/dev/null fails with 'Committer identity unknown', it is this trap, not the code under test.
- **Lệnh kiểm tra:** `GIT_CONFIG_GLOBAL=/dev/null git var GIT_COMMITTER_IDENT`
- **Nguồn:** session 9559b4fd, Stop-hook regression gate REG-DK-ALL-01

---

### [INSTINCT-044] bash 3.2 ${var//x/} is quadratic and a PreToolUse guard killed at its timeout gives no verdict: a big command can pass both command guards just by being slow
- **Ngày phát hiện:** 2026-10-15
- **Hiện tượng lỗi:** bash 3.2 ${var//x/} is quadratic and a PreToolUse guard killed at its timeout gives no verdict: a big command can pass both command guards just by being slow
- **Nguyên nhân:** On macOS /bin/bash 3.2.57 the replacement ${c//\\/} in fast_allow of block-dangerous-git.sh and hardware_safety_gate.sh is O(n^2) on multi-line input: a 20 KB command took 14-18 s, the hardware gate's hook timeout is 10 s (the git guard sets none), and a hook that times out is no verdict (INSTINCT-040 records the same for a Stop hook). Pre-existing, found by a reviewer's timing probe (15/10).
- **Quy tắc phòng ngừa & Cách fix:** Bound every guard by input size: a linear tool (tr -d) above ~256 characters, a SIGALRM watchdog that REFUSES with a reason before the hook timeout, and a test with 20 KB and 200 KB commands including a dangerous line hidden after 20 KB of harmless text that must still be blocked.
- **Lệnh kiểm tra:** `time a 20 KB multi-line command through the hook under /bin/bash 3.2 (tool-call JSON on stdin)`
- **Nguồn:** session 9559b4fd, principal-code-reviewer timing probe of the shell_norm lane

---

### [INSTINCT-045] A guard that cuts heredoc bodies as data with a scanner that is not the shell hides live commands: three review rounds kept finding new fail-open forms
- **Ngày phát hiện:** 2026-10-15
- **Hiện tượng lỗi:** A guard that cuts heredoc bodies as data with a scanner that is not the shell hides live commands: three review rounds kept finding new fail-open forms
- **Nguyên nhân:** shell_norm.py decided which heredoc bodies are data with its own lexer. Wherever the lexer disagrees with the shell the body is cut but RUNS: ${x//&lt;&lt;EOF}, $[1&lt;&lt;EOF], (true)#&lt;&lt;EOF, $'\\eOF' delimiters, a quoted $( ) argument of git -c alias.x, a runner registered before the write (trap, git config core.fsmonitor, git bisect run). Each fix closed one form and the next review found another; 1440 monotonic rows did not contain these shapes (15/10).
- **Quy tắc phòng ngừa & Cách fix:** Cut a body only under a structural precondition: the whole command uses only constructs the scanner models, the delimiter is a plain word, and the body is the last statement or the value of a known message option of a known consumer; any doubt keeps the text in the scan (fail closed). Every guard change needs a monotonic corpus (old blocks implies new blocks) with a harmless control per row, mutation-checked, before any review.
- **Lệnh kiểm tra:** `bash universal-agent-devkit/tests/gates/test_guard_shell_norm_monotonic.sh (on the lane branch until it is merged)`
- **Nguồn:** session 9559b4fd, OCR + principal review of lane aa3f350b (guard shell_norm)

---

### [INSTINCT-046] Công tắc môi trường của runner/worker lọt vào suite test của gate
- **Ngày phát hiện:** 2026-10-16
- **Hiện tượng lỗi:** Công tắc môi trường của runner/worker lọt vào suite test của gate
- **Nguyên nhân:** super-board-run.sh export DEVKIT_ALLOW_BRANCH=1 cho worker, worker tự đặt POSTFIX_GATE_FORCE_FULL=1; suite_env() của post-fix-gate giữ nguyên chúng nên REG-DK-HOOK-01 (checkout -b want=2 got=0) và test_busy_keeps_receipt đỏ trong merge-gate verify, thẻ đã review bị đẩy sang Blocked
- **Quy tắc phòng ngừa & Cách fix:** Biến là công tắc của MỘT lần chạy gate/hook (DEVKIT_ALLOW_BRANCH, POSTFIX_GATE_FORCE_FULL, WORKTREE_MERGE_GATE…) phải nằm trong danh sách drop của suite_env() và unset trong tests/lib/clean_git_env.sh; thêm công tắc mới thì thêm vào cả hai và vào test_suite_env.sh

---

### [INSTINCT-047] Squash merge làm main local lệch origin, và symlink kit chặn gỡ worktree
- **Ngày phát hiện:** 2026-10-17
- **Hiện tượng lỗi:** Squash merge làm main local lệch origin, và symlink kit chặn gỡ worktree
- **Nguyên nhân:** merge gate dùng gh pr merge --squash nên origin có commit mới cùng nội dung khác sha, trong khi trunk mode đã đưa chính các commit PR vào main local: ff-only thất bại mãi và mỗi PR người dùng phải đồng bộ tay; agent-kit heal/init tạo symlink .agents/hooks/* trỏ vào kit của main nên worktree remove thấy 'thay đổi main chưa có' và giữ worktree
- **Quy tắc phòng ngừa & Cách fix:** sau squash, base local chỉ dời về origin/<base> bằng `reset --keep` khi CÂY hai bên giống hệt; còn commit riêng chưa đẩy hoặc main đang dở merge thì để nguyên và cảnh báo. KHÔNG merge non-ff trong main (luật main chỉ ff) và KHÔNG `merge --abort` vô điều kiện (nó huỷ merge + phần giải tay của phiên khác). Symlink UNTRACKED trỏ vào universal-agent-devkit/ hoặc .agents/devkit/ của main là trạng thái cài, bỏ ở `changes_since` (một chỗ cho diff/status/finish/remove); file đã theo dõi bị thay bằng link vẫn là việc. Test: tests/super-board/test_merge_gate_squash_sync.sh, universal-agent-devkit/tests/worktree_git/test_worktree_remove_kit_links.sh

---

### [INSTINCT-048] Hook Stop của phiên cha tự gộp worktree của agent con đang chạy
- **Ngày phát hiện:** 2026-10-17
- **Hiện tượng lỗi:** Hook Stop của phiên cha tự gộp worktree của agent con đang chạy
- **Nguyên nhân:** worktree_merge_gate.sh xem mọi worktree agent-* do phiên sở hữu là đã xong, nên gộp cả việc dở của subagent nền (K10, 17/10: wip a07752b)
- **Quy tắc phòng ngừa & Cách fix:** Trước khi automerge, xét thông báo harness cuối cùng của subagent (đang chờ việc nền / chưa báo / SendMessage = còn sống) và bỏ qua; chỉ gộp khi có bằng chứng nó đã dừng

---

### [INSTINCT-049] Gỡ một lần git từ chối có thể lộ ra việc ghi đè file bị ignore
- **Ngày phát hiện:** 2026-10-18
- **Hiện tượng lỗi:** Gỡ một lần git từ chối có thể lộ ra việc ghi đè file bị ignore
- **Nguyên nhân:** merge --ff-only và reset --keep mặc định ghi đè file bị git ignore ở đường dẫn target thêm; một file dở chặn ff đã vô tình giữ file đó, nên stage bản trùng byte rồi thử lại (K13) làm mất cấu hình cục bộ
- **Quy tắc phòng ngừa & Cách fix:** Mọi đường thử lại ff/reset trong merge gate: --no-overwrite-ignore cho ff, chốt va chạm file ignore (trùng/cha/con, casefold, NFC) trước reset --keep; kiểm index bằng --ita-visible-in-index; test cả trường hợp main sạch

---

### [INSTINCT-050] Gate tin lệnh do chính thay đổi thêm vào: lệnh đó chạy trước suite base thì vô hiệu được suite base
- **Ngày phát hiện:** 2026-10-18
- **Hiện tượng lỗi:** PR chỉ THÊM rule vào ma trận hồi quy, test của rule mới XANH, gate exit 0 dù suite base phải ĐỎ
- **Nguyên nhân:** post-fix-gate tin ma trận chỉ-thêm (PR #63) và chạy test thêm theo thứ tự rule: rule chèn đầu chạy trước suite base, ghi đè script base, hoặc đẩy script vào DEVKIT_GATE_DONE / ran_cmds / đích covered_by để runner base bỏ qua (universal-agent-devkit/bin/post-fix-gate.py)
- **Quy tắc phòng ngừa & Cách fix:** Lệnh do thay đổi đưa vào chỉ chạy SAU mọi suite base và STALE, tuần tự, không ghi vào trạng thái dùng chung (DEVKIT_GATE_DONE, ran_cmds), không lấp id/covered_by của base; chỉ PASS đã thực chạy mới tính
- **Lệnh kiểm tra:** `bash universal-agent-devkit/tests/gates/test_gate_matrix_additive.sh`

---

### [INSTINCT-051] Khoá dùng lại kết quả test băm cả file mà chính suite ghi lại thì không bao giờ khớp giữa hai checkout
- **Ngày phát hiện:** 2026-10-18
- **Hiện tượng lỗi:** Khoá dùng lại kết quả test băm cả file mà chính suite ghi lại thì không bao giờ khớp giữa hai checkout
- **Nguyên nhân:** local_state_sha của post-fix-gate băm build input do task Test build lại (APK overlay GeelyEx2, byte khác mỗi lượt) và config trong cache build (Unity Library/**/local.properties): scratch của merge gate có cây trùng nhưng local_sha khác, suite nặng chạy lại ở mọi PR (18/10)
- **Quy tắc phòng ngừa & Cách fix:** Khoá dùng lại chỉ gồm INPUT: bỏ file trong cache build và file suite tự ghi lại trong lượt (đo trước/sau suite, ghi vào biên nhận), nhưng không bao giờ bỏ config/khoá thật (LOCAL_CONFIG, DEFAULT_INPUTS) — tool sửa tại chỗ vẫn là đổi input; có ca đối chứng input thật khác thì không dùng lại

---

### [INSTINCT-052] Worktree do công cụ tự tạo thiếu phần cài DevKit bị ignore, và bài thử pass trên đường khác đường chạy thật
- **Ngày phát hiện:** 2026-10-19
- **Hiện tượng lỗi:** Worktree do công cụ tự tạo thiếu phần cài DevKit bị ignore, và bài thử pass trên đường khác đường chạy thật
- **Nguyên nhân:** Merge gate chỉ tìm install.sh ở '.', tức worktree Reviewer do lane tạo bằng worktree add trần, nơi .agents/devkit (bị ignore) không có: scratch thiếu post-fix-gate.py, mọi PR đã review đỏ ở verify, 47 thẻ Blocked ở 5 board (19/10). Lane còn chép link tương đối .agents/active-profile của main y nguyên vào worktree sâu hơn nên link gãy (exit 127). Bài thử 20 phiên ngày 17/10 pass vì đi EnterWorktree (hook cài DevKit) và chạy merge gate từ main checkout, không đi qua lane + PR + merge gate từ worktree Reviewer.
- **Quy tắc phòng ngừa & Cách fix:** Mọi script tìm DevKit hay state bị ignore phải tìm cả ở main checkout (dòng đầu danh sách worktree), không chỉ ở '.'; thiếu thì dừng với lỗi môi trường (exit 9), không quy cho PR. Bài thử nghiệm thu phải đi đúng đường production (lane tạo worktree, PR, merge gate chạy từ worktree Reviewer). Test: tests/super-board/test_merge_gate_devkit_from_main.sh, universal-agent-devkit/tests/worktree_git/test_heal_active_profile.sh.

---

### [INSTINCT-053] Halt vì lỗi đọc tạm thời không ai tự gỡ: máy ngủ dậy làm chết mọi board hàng giờ
- **Ngày phát hiện:** 2026-10-20
- **Hiện tượng lỗi:** Halt vì lỗi đọc tạm thời không ai tự gỡ: máy ngủ dậy làm chết mọi board hàng giờ
- **Nguyên nhân:** super-board-github-read.py halt sau 3 lần đọc lỗi trong vài giây (mạng chưa lên sau khi máy thức), watchdog coi halt rc=79 là dừng có chủ đích nên không bao giờ khởi động lại
- **Quy tắc phòng ngừa & Cách fix:** Mọi trạng thái dừng do lỗi tạm thời (mạng, quota, đọc) phải có đường tự phục hồi có giới hạn thời gian (replay chỉ đọc rồi restart); chỉ thao tác ghi chưa rõ kết quả mới chờ người. Trạng thái sống/chết phải hiện ra ngoài (mô tả Project, field card) kèm giờ cập nhật

---

### [INSTINCT-054] Guard đường dẫn chạy SAU bước phá huỷ, hoặc leo tổ tiên theo chuỗi để lọt '..'
- **Ngày phát hiện:** 2026-10-20
- **Hiện tượng lỗi:** Guard đường dẫn chạy SAU bước phá huỷ, hoặc leo tổ tiên theo chuỗi để lọt '..'
- **Nguyên nhân:** restore-old kiểm cha-symlink sau rm/mkdir (đã xoá file DevKit trước khi SKIP), bước leo tổ tiên theo chuỗi coi 'nope/../..' là trong dự án, phía backup của ledger chỉ kiểm tiền tố
- **Quy tắc phòng ngừa & Cách fix:** Kiểm tra chỉ-đọc trước mọi rm/mkdir/mv và ở cả dry-run; từ chối đoạn '.'/'..' trên CẢ đường dẫn (cả đoạn cuối); áp cùng kiểm tra cho nguồn lẫn đích của mv
- **Lệnh kiểm tra:** `bash universal-agent-devkit/tests/worktree_git/test_restore_old.sh`

---

### [INSTINCT-055] Chạy gate dưới nohup làm test SIGHUP đỏ giả
- **Ngày phát hiện:** 2026-10-20
- **Hiện tượng lỗi:** Chạy gate dưới nohup làm test SIGHUP đỏ giả
- **Nguyên nhân:** nohup đặt SIGHUP = SIG_IGN cho mọi tiến trình con; gate lồng trong test_gate_robustness.sh A9 không nhận SIGHUP nên sống quá 10 s (đo 20/10: HEAD và P1 đỏ y hệt dưới nohup, xanh khi không nohup)
- **Quy tắc phòng ngừa & Cách fix:** Không bọc gate/test bằng nohup; chạy nền bằng run_in_background của harness. Thấy A9 SIGHUP đỏ mà TERM/INT xanh: kiểm SIGHUP có bị ignore từ tiến trình cha không trước khi nghi code
- **Lệnh kiểm tra:** `python3 -c 'import signal; print(signal.getsignal(signal.SIGHUP))'`

---

### [INSTINCT-056] killpg bị macOS từ chối (EPERM) làm gate chết khi suite quá giờ, biên nhận cũ ở lại thành xanh giả
- **Ngày phát hiện:** 2026-10-20
- **Hiện tượng lỗi:** killpg bị macOS từ chối (EPERM) làm gate chết khi suite quá giờ, biên nhận cũ ở lại thành xanh giả
- **Nguyên nhân:** macOS từ chối signal cho process group còn zombie; run_in_group chỉ bắt ProcessLookupError nên PermissionError làm gate crash giữa chừng, write_full_pass_receipt(exit 1) không chạy, lượt --full sau dùng lại PASS trước lúc treo
- **Quy tắc phòng ngừa & Cách fix:** Mọi killpg trong DevKit bắt cả PermissionError và lùi về proc.send_signal; lần communicate cuối có trần (cháu có thể giữ ống output). Test: tests/gates/test_gate_robustness.sh A12/A12b/A13
- **Lệnh kiểm tra:** `grep -n 'os.killpg' universal-agent-devkit/bin/*.py universal-agent-devkit/scripts/*/*.py`

---

### [INSTINCT-057] Test super-board chạy trong worktree dùng heavy_slot của main checkout, không phải bản đang sửa
- **Ngày phát hiện:** 2026-10-21
- **Hiện tượng lỗi:** Test super-board chạy trong worktree dùng heavy_slot của main checkout, không phải bản đang sửa
- **Nguyên nhân:** .claude/bin/super-board-heavy-slot.py tìm bin/heavy_slot.py ở main worktree TRƯỚC (main_wt/universal-agent-devkit), nên test gọi wrapper (test_tests_skip_machine_slots.sh, test_heavy_slot.sh) trong worktree chạy code CŨ của main: P1 bỏ 2 slot mà REG-SB-TEST-SLOT-ISO-01 vẫn XANH ở worktree, ĐỎ ngay khi main được fast-forward (21/10)
- **Quy tắc phòng ngừa & Cách fix:** Sửa universal-agent-devkit/bin/heavy_slot.py thì chạy lại các test gọi .claude/bin/super-board-heavy-slot.py SAU khi main có code mới (sau worktree finish), trước khi push
- **Lệnh kiểm tra:** `grep -rlE 'super-board-heavy-slot.py|SLOT_BIN' tests/`

---

### [INSTINCT-058] Một lần đọc GitHub hỏng tạm thời dưới set -e giết runner, watchdog crash-loop rồi bỏ cuộc
- **Ngày phát hiện:** 2026-10-22
- **Hiện tượng lỗi:** Một lần đọc GitHub hỏng tạm thời dưới set -e giết runner, watchdog crash-loop rồi bỏ cuộc
- **Nguyên nhân:** super-board-run.sh chạy set -euo pipefail; fetch_project_items/gh_rate_guard gọi trần trong vòng lặp nên một lần card.sh exit 69 (đọc board lệch số sau khi máy khởi động lại) làm runner chết; watchdog khởi động lại 5 lần, lần nào cũng chết ở lần đọc đầu, rồi bỏ cuộc (22/10 22:05-22:15, #256)
- **Quy tắc phòng ngừa & Cách fix:** Mọi lệnh đọc mạng trong vòng lặp daemon chạy set -e phải đi qua wrapper: đọc lại có backoff+jitter, hỏng hết lượt thì bỏ tick, có trần số tick bỏ liên tiếp rồi mới thoát; mã halt có chủ đích vẫn dừng. Hàm gọi trong ngữ cảnh || mất errexit nên phải tự kiểm payload. Đổi tên biến bằng sed toàn file shell lớn dễ trúng hàm khác: sửa theo dòng/hàm cụ thể

### [INSTINCT-059] Memo hoa trang thai repo trong mot tien trinh pha hop dong thu muc bi go giua luot va lam mu test cu
- **Ngày phát hiện:** 2026-10-22
- **Hiện tượng lỗi:** Memo hoa trang thai repo trong mot tien trinh pha hop dong thu muc bi go giua luot va lam mu test cu
- **Nguyên nhân:** Memo hoa cau tra loi dia chi thu muc quan tri ca tien trinh nen khi worktree bi go giua luot gate van dung duong dan cu va tao lai thu muc quan tri (test_gate_project_removed_midrun do); cache in_linked_worktree lam ca commondir bi trong doc cau tra loi cu nen mutant van xanh. Hai loi chi lo khi reviewer chay test co san tren diff; test RED moi cua minh van xanh.
- **Quy tắc phòng ngừa & Cách fix:** Chi memo hoa cau tra loi tinh va kiem lai thu muc con ton tai (os.path.isdir) truoc khi dung; khong cache trong ham ma test hien co doi bo cuc giua hai lan goi; chay lai test gate va worktree ke can cung mot mutant truoc khi tin test RED sang GREEN cua chinh minh.

---

### [INSTINCT-060] Model 3D cache cũ sau khi dựng lại
- **Ngày phát hiện:** 2026-10-23
- **Hiện tượng lỗi:** Model 3D cache cũ sau khi dựng lại
- **Nguyên nhân:** server trả web/models/*.glb với Cache-Control max-age 1 ngày dưới URL cố định; dựng lại GLB cùng tên thì trình duyệt vẫn dùng bản cũ, nhìn như sửa không có tác dụng
- **Quy tắc phòng ngừa & Cách fix:** URL tài nguyên tĩnh được cache lâu phải mang dấu vân tay nội dung (tên+kích thước+mtime_ns hoặc hash) do server điền vào trang; kiểm thay đổi hình ảnh bằng chính renderer cuối (three.js trong trang), không bằng ảnh render của công cụ dựng

---

### [INSTINCT-061] Biến gán kèm lệnh source (VAR=1 . file) chỉ sống trong lúc source
- **Ngày phát hiện:** 2026-10-23
- **Hiện tượng lỗi:** Biến gán kèm lệnh source (VAR=1 . file) chỉ sống trong lúc source
- **Nguyên nhân:** Test gọi SB_LIB_ONLY=1 . super-board-run.sh; bash giữ phép gán đứng trước builtin '.' chỉ trong lúc source, nên hàm gọi về sau không thấy SB_LIB_ONLY và test đếm slot worker thật trong ~/.claude/super-board-slots (23/10: merge-train bị giữ 3/3 running)
- **Quy tắc phòng ngừa & Cách fix:** Cần biết lib mode ở thời điểm gọi hàm thì chốt nó bằng một dòng top-level chạy lúc source (SB_SLOT_LIB_MODE="${SB_LIB_ONLY:-0}"); test lib mode bằng một HOME giả có slot sống và kiểm đột biến

---

### [INSTINCT-062] Mở file người dùng ghi được bằng open() không kiểm loại file
- **Ngày phát hiện:** 2026-10-24
- **Hiện tượng lỗi:** Mở file người dùng ghi được bằng open() không kiểm loại file
- **Nguyên nhân:** suite_cache._read_text/_file_digest mở FIFO bằng open() nên chờ mãi; test_gate_robustness treo, REG-DK-ALL-01 TIMEOUT ở mọi giới hạn kể cả máy rảnh. Nới timeout không chữa được; watchdog thì coi halted rc=79 mất file halt là dừng có chủ đích nên board nằm im 5,5 giờ
- **Quy tắc phòng ngừa & Cách fix:** Mọi chỗ đọc file trong gate/cache kiểm os.path.isfile (hoặc mở O_NONBLOCK) trước; timeout vô hạn dù máy rảnh nghĩa là treo, dùng PYTHONFAULTHANDLER=1 + kill -ABRT lấy stack thay vì tăng giới hạn; rc=79 của runner không bao giờ là dừng có chủ đích

---

### [INSTINCT-063] KNOWN-RED chỉ nhận FAIL và guard che message commit mở cửa
- **Ngày phát hiện:** 2026-10-24
- **Hiện tượng lỗi:** KNOWN-RED chỉ nhận FAIL và guard che message commit mở cửa
- **Nguyên nhân:** gate coi TIMEOUT là lỗi của thay đổi dù base cũng TIMEOUT; guard secrets xoá trắng cả -m và heredoc nên lệnh con trong message lọt
- **Quy tắc phòng ngừa & Cách fix:** bằng chứng base phải ghi cả TIMEOUT dưới khoá cả cây, không dùng bản ghi của chính lượt này; guard chỉ che message khi không có lệnh con và heredoc có delimiter quote, lỗi parser thì xét nguyên lệnh

---

### [INSTINCT-064] Sweep bỏ sót thẻ bị gom/bỏ (NOT_PLANNED)
- **Ngày phát hiện:** 2026-10-25
- **Hiện tượng lỗi:** Sweep bỏ sót thẻ bị gom/bỏ (NOT_PLANNED)
- **Nguyên nhân:** post-merge-clean --sweep chỉ dọn thẻ có PR MERGED; thẻ đóng NOT_PLANNED/DUPLICATE khi gom vào thẻ khác không có PR merged nên PR mở, branch và worktree của nó ở lại mãi (24/10: 20 worktree, 31 branch khi chỉ 4 thẻ chạy)
- **Quy tắc phòng ngừa & Cách fix:** Mọi đường đóng thẻ (gom, bỏ, split) phải có bước dọn cùng đường: sweep xử lý CLOSED+NOT_PLANNED/DUPLICATE qua drop_card và kit prune-branch --dropped (chỉ xoá khi tip có trên origin); thêm trạng thái đóng mới thì thêm ca vào test_post_merge_dropped_cards.sh

---

### [INSTINCT-065] Test chạy không hạn giờ để lại tiến trình mồ côi hàng chục giờ
- **Ngày phát hiện:** 2026-10-25
- **Hiện tượng lỗi:** Test chạy không hạn giờ để lại tiến trình mồ côi hàng chục giờ
- **Nguyên nhân:** run_impacted.sh chạy từng test bằng bash trần; ca FIFO của test_gate_robustness kẹt trong open() của nhân, runner phía trên bị SIGKILL (pkill -9 của board) nên không trap nào dọn, hai post-fix-gate.py sống 18h giữ khoá/tải, gate khác báo BUSY; thêm: print ra stderr pipe đã chết ném BrokenPipe (Python bỏ qua SIGPIPE) và bỏ qua bước giết nhóm
- **Quy tắc phòng ngừa & Cách fix:** Mọi lệnh con có thể treo chạy qua tests/lib/run_bounded.py (hạn giờ + giết cả nhóm + watchdog khi helper bị SIGKILL + theo dõi caller); log trong đường dọn dẹp không bao giờ được ném lỗi (os.write + nuốt OSError, dọn trước log sau); test mới thêm ca vào test_run_bounded.sh
