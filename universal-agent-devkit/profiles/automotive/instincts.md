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

## 2. Bẫy Đặc Thù Automotive / IVI (đúc kết từ đo đạc trên đầu xe thật)

### [INSTINCT-AUTO-01] Remount / Ghi `/system` Trên Đầu Xe Có dm-verity
- **Hiện tượng lỗi:** Sau `adb remount` hoặc push file vào `/system/priv-app`, đầu xe báo "device corrupt" và màn hình không boot được.
- **Nguyên nhân gốc rễ:** ROM IVI bật dm-verity; mọi thay đổi phân vùng hệ thống làm hỏng chuỗi xác minh khi khởi động.
- **Quy tắc bắt buộc:** Chỉ cài bằng `adb install` / `pm install`, cấu hình bằng `settings`, `pm`, `cmd`. Ai đề xuất remount — từ chối. Không bypass `hardware_safety_gate.sh`.
- **Kiểm tra tự động:** `grep -rnE "remount|disable-verity|mount -o rw|/system/priv-app" scripts/ docs/` — mọi kết quả phải là cảnh báo/cấm, không phải lệnh chạy.

---

### [INSTINCT-AUTO-02] Ghi Thuộc Tính VHAL Dạng Toggle Khi Chưa Đọc Được Trạng Thái
- **Hiện tượng lỗi:** Lệnh "bật" một chức năng (ví dụ tuần hoàn gió) lúc bật lúc tắt, lật qua lại theo mỗi lần gửi.
- **Nguyên nhân gốc rễ:** Property là công tắc đảo; guard "đã đúng thì không ghi" đọc trạng thái trước khi `CarPropertyManager` kết nối xong → `null` → luôn ghi → đảo ngược trạng thái đang đúng.
- **Quy tắc bắt buộc:** Nối guard sau khi `Car` đã kết nối; đọc trả `null`/lỗi thì KHÔNG ghi và báo "không đọc được". Test phải phủ ca đọc `null`.
- **Kiểm tra tự động:** Unit test giả lập property đọc `null` ⇒ khẳng định không có lệnh `setProperty` nào được phát ra.

---

### [INSTINCT-AUTO-03] Coi Giá Trị ECU Lúc Xe Thức Là Lựa Chọn Của Người Dùng
- **Hiện tượng lỗi:** Chế độ lái / mức phanh tái sinh / âm cảnh báo tự về mặc định sau khi mở lại đầu xe; cấu hình người dùng đã lưu bị ghi đè.
- **Nguyên nhân gốc rễ:** Luồng đồng bộ đọc giá trị mặc định ECU ngay lúc boot rồi lưu đè vào storage; cổng "vừa khởi động" dựa trên mốc thời gian không reset qua reboot.
- **Quy tắc bắt buộc:** Giá trị lúc boot chỉ là trạng thái phần cứng, không phải ý chí người dùng. Chỉ lưu khi người dùng thao tác; restore có cổng đánh lửa đúng nghĩa. Mọi thay đổi `*Restore*`/`*Policy*` phải tra lịch sử (`git log -S`) và nhật ký bug trước.
- **Kiểm tra tự động:** Test mô phỏng chuỗi boot → ECU trả mặc định → khẳng định cấu hình đã lưu không đổi.

---

### [INSTINCT-AUTO-04] Câu Nói Trong Cabin Biến Thành Lệnh Phần Cứng
- **Hiện tượng lỗi:** Xe tự chạy lệnh (khởi động lại hệ thống, mở khoá cửa, chia màn hình) khi người trong xe chỉ nói chuyện hoặc loa đang phát nội dung.
- **Nguyên nhân gốc rễ:** Bộ "snap"/so khớp gần đúng kéo chữ méo hoặc câu cụt về lệnh gần nhất; wake word trùng từ đời thường.
- **Quy tắc bắt buộc:** "Im còn hơn làm sai": thiếu neo ý định hoặc tham số thì hỏi lại/im; lệnh an toàn cần xác nhận khi xe chạy; mỗi thay đổi parser phải chạy lại toàn bộ kho câu thật và so ảnh chụp hành vi trước/sau.
- **Kiểm tra tự động:** Bộ test "must_reject" (tiếng cabin, câu cụt, ảo giác) = 0 lệnh phát ra.

---

### [INSTINCT-AUTO-05] Máy Ảo Xanh Nhưng Xe Thật Chết
- **Hiện tượng lỗi:** Test và máy ảo đều xanh, nhưng tính năng chết trên xe nhiều ngày; có lần còn sửa stub `Car`/VHAL giả của máy ảo để máy ảo xanh lại.
- **Nguyên nhân gốc rễ:** Máy ảo không có ROM OEM, service của hãng, độ trễ CPU và hành vi mic/âm thanh thật; test được viết khoá chiều ngược của một bản vá đã đo.
- **Quy tắc bắt buộc:** Máy ảo xanh không phải bằng chứng cho hành vi phụ thuộc ROM/VHAL; cấm sửa mock để hợp thức hoá; cấm viết test khoá chiều ngược một mục "đã sửa" trong nhật ký bug. Báo cáo ghi rõ "CHƯA ĐO TRÊN XE".
- **Kiểm tra tự động:** Báo cáo nghiệm thu phải có dòng nơi đo (máy bàn / máy ảo / xe) cho từng hạng mục.

---

### [INSTINCT-AUTO-06] ROM IVI Thiếu Màn Hình / Handler Chuẩn Của Android
- **Hiện tượng lỗi:** App bên thứ ba văng khi mở (gọi màn "bỏ qua tối ưu pin" không tồn tại); cửa sổ PIP tạo được nhưng không chạm/đóng được; chia đôi màn hình làm NPE trong `DockedStackDividerController`, có ca kéo sập `system_server`.
- **Nguyên nhân gốc rễ:** ROM OEM gỡ hoặc làm hỏng thành phần SystemUI/Settings mà AOSP mặc định có.
- **Quy tắc bắt buộc:** Kiểm tồn tại (`resolveActivity`, `cmd package query-activities -a <action>`) trước khi gọi; đường đa cửa sổ phải có cổng năng lực cửa sổ + fallback + watchdog; không nới cổng đó cho "dễ dùng".
- **Kiểm tra tự động:** `adb -s <serial> shell cmd package query-activities -a <action>` trên xe thật trước khi phát hành tính năng dựa vào màn hình hệ thống.

---

### [INSTINCT-AUTO-07] Launcher / ROM Tự Dọn Tác Vụ Nền & Tắt Wi-Fi
- **Hiện tượng lỗi:** Nhạc nền dừng khoảng 30 giây sau khi app ra nền; Wi-Fi không tự nối lại sau khi tắt máy; receiver tự bật bị bỏ qua.
- **Nguyên nhân gốc rễ:** Launcher OEM xoá task nền theo lịch; ROM tắt Wi-Fi khi tắt máy; Android chặn implicit broadcast.
- **Quy tắc bắt buộc:** Đo hành vi thật (timestamp logcat) trước khi đổ lỗi app; dùng foreground service / explicit receiver / cơ chế khôi phục có điều kiện; ghi telemetry cho mỗi lần khôi phục.
- **Kiểm tra tự động:** Kịch bản thiết bị: đưa app ra nền, chờ ≥ 60 s, khẳng định phiên phát còn sống.

---

### [INSTINCT-AUTO-08] Micro "Chết" Vì Xe Khoá Mic Ở Tầng DSP
- **Hiện tượng lỗi:** Sau khi tắt/mở xe, mic trả PCM câm; watchdog dựng lại mic liên tục mà không hết.
- **Nguyên nhân gốc rễ:** Xe chuyển chế độ ngủ/ACC và gọi mute mic ở tầng âm thanh; app không hỏi trạng thái mute nên đổ lỗi engine.
- **Quy tắc bắt buộc:** Trước khi dựng lại pipeline, hỏi trạng thái mute (`AudioManager`/`CarAudioManager`); watchdog phải đo nội dung PCM (RMS), không chỉ "có callback"; mic chết không chứng minh bằng WAV cũ.
- **Kiểm tra tự động:** Telemetry lượt thu ghi RMS + trạng thái mute; lọc `level=warning` khi RMS≈0 và mute=false.

---

### [INSTINCT-AUTO-09] Ghi Cấu Hình Quan Trọng Bằng `apply()` / Storage Nối Đuôi
- **Hiện tượng lỗi:** Cấu hình vừa lưu biến mất khi process bị kill hoặc xe tắt đột ngột; khoá đã "xoá" vẫn đọc ra giá trị cũ từ file.
- **Nguyên nhân gốc rễ:** `SharedPreferences.apply()` ghi bất đồng bộ; một số kho key-value ghi nối đuôi nên xoá khoá không xoá byte cũ.
- **Quy tắc bắt buộc:** Ghi hiếm mà mất là nghiêm trọng → `commit()` trên luồng nền; ghi thường xuyên → `apply()`. Xác minh ngữ nghĩa xoá của thư viện storage bằng test đọc lại sau khởi động lại.
- **Kiểm tra tự động:** `grep -rn "\.apply()" <module lưu cấu hình xe>` rà từng chỗ lưu cấu hình an toàn.

---

### [INSTINCT-AUTO-10] Hai Build Gradle Chạy Chồng Trong Cùng Cây Mã
- **Hiện tượng lỗi:** Test "flake": `EOFException`, file kết quả 0 byte, thư mục `test-results` biến mất giữa lượt.
- **Nguyên nhân gốc rễ:** Một build khác (agent khác, hook, IDE) chạy `--stop`/xoá `build/` cùng lúc.
- **Quy tắc bắt buộc:** Dùng khoá build của dự án (nếu có) hoặc chạy tuần tự; không retry mù test đỏ thật; mỗi agent song song dùng một worktree riêng (`AGENTS.md` §7.1).
- **Kiểm tra tự động:** `ps aux | grep -c "[G]radleDaemon"` trước khi chạy suite dài.

---

### [INSTINCT-AUTO-11] Test Gradle UP-TO-DATE Và Tên Test Có Dấu Cách
- **Hiện tượng lỗi:** Build xanh nhưng không in kết quả test nào; hoặc `androidTest` vỡ ở `dexBuilder` sau khi biên dịch đã xanh.
- **Nguyên nhân gốc rễ:** Gradle bỏ qua task test không đổi input; D8 cấm ký tự cách/không ASCII trong tên lớp sinh ra từ tên hàm backtick (DEX < 040).
- **Quy tắc bắt buộc:** Khi cần số liệu thật dùng `--rerun-tasks` (hoặc `clean<Task>`) và đọc XML `TEST-*.xml` của đúng lượt; tên hàm `androidTest` chỉ dùng ASCII + `_`.
- **Kiểm tra tự động:** `grep -rn 'fun `[^`]* [^`]*`' app/src/androidTest` phải rỗng.

---

### [INSTINCT-AUTO-12] `adb` Trần Nhắm Nhầm Thiết Bị Cá Nhân
- **Hiện tượng lỗi:** Script test gửi lệnh (kể cả chỉ-đọc như `getprop`) vào điện thoại cá nhân đang cắm cạnh máy test, rồi mới lọc.
- **Nguyên nhân gốc rễ:** `adb` không có `-s` nhắm vào thiết bị duy nhất đang kết nối; nhận diện thiết bị bằng cách hỏi nó là đã quá muộn.
- **Quy tắc bắt buộc:** Lọc serial theo TÊN trước (allowlist `emulator-*` / denylist), gửi lệnh sau; luôn `adb -s <serial>`; khai máy cấm trong `.adb-denylist` để `hardware_safety_gate.sh` chặn.
- **Kiểm tra tự động:** `grep -rnE "adb (shell|install|push|pull|logcat)" scripts/ | grep -v -- "-s "` phải rỗng.

---

## 3. Nhật Ký Bẫy Mã Nguồn Bổ Sung (Dành cho Dev / Agent thêm mới)

<!--
Mẫu ghi nhận:
### [INSTINCT-AUTO-XX] <Tên bẫy / Tình huống>
- **Ngày phát hiện:** YYYY-MM-DD
- **Hiện tượng lỗi:** <Mô tả lỗi hoặc hồi quy>
- **Nguyên nhân:** <Tại sao lại xảy ra>
- **Quy tắc phòng ngừa:** <Cách làm đúng từ nay về sau>
- **Lệnh kiểm tra:** <Câu lệnh kiểm tra tự động nếu có>
-->
