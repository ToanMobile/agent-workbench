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
