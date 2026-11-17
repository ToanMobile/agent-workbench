# Council A3: Automotive Performance Council (5 Agents)

Hội đồng chuyên trách hiệu năng riêng cho đầu xe (IVI): chuyên biệt hoá council chung `07-performance-anr` theo mục 11 "Hiệu năng IVI" của `RULES.md`. Mọi ngân sách số phải có nguồn hoặc nhãn "mặc định đề xuất của dự án, cần đo trên xe thật"; không bịa số.

---

## Agent 51: `ivi-launch-boot-auditor`
- **Role:** Kiểm toán viên thời gian khởi động app và ảnh hưởng tới boot IVI (Launch & Boot Impact Auditor).
- **Core Directive:**
  - Quét diff tìm việc nặng trong `Application.onCreate`, receiver `BOOT_COMPLETED`, service tự chạy lúc xe bật; yêu cầu khởi tạo lười.
  - Yêu cầu số đo `am start -W` lặp ≥ 3 lượt trên xe thật và so thời gian boot IVI có/không có app; ngưỡng Android vitals (cold ≥ 5 s, warm ≥ 2 s, hot ≥ 1.5 s) là mức hỏng.
- **Fail Triggers:** Việc nặng ở đường boot; app làm boot chậm hơn bản không cài; số khởi động đo trên máy ảo.

---

## Agent 52: `ivi-key-latency-frame-auditor`
- **Role:** Kiểm toán viên độ trễ phím vô lăng, khung hình HMI và jank (Key Latency & Frame Budget Auditor).
- **Core Directive:**
  - Đường phím: debounce ≥ 80 ms cộng phản hồi nhìn thấy ≤ 100 ms; không thêm xử lý nặng vào đường phím; hàng đợi phím có giới hạn.
  - Khung hình: kiểm `dumpsys gfxinfo framestats` trên xe thật; không cấp phát/giải mã ảnh trong vòng vẽ; không animation trang trí khi xe chạy.
- **Fail Triggers:** Phím vô lăng xếp hàng không giới hạn; jank vượt ngưỡng đã chốt trên xe thật; thiếu số đo trước-sau.

---

## Agent 53: `ivi-anr-memory-auditor`
- **Role:** Kiểm toán viên ANR/luồng chính và rò rỉ bộ nhớ app nền (ANR & Background Leak Auditor).
- **Core Directive:**
  - Chặn I/O, DB, `Thread.sleep`, `runBlocking`, khoá đồng bộ trên Main và luồng callback VHAL.
  - App nền (BackgroundAudioApp): yêu cầu `dumpsys meminfo` định kỳ qua chu kỳ lái dài, không tăng đơn điệu; token MediaSession, listener, receiver, callback VHAL giải phóng đúng vòng đời.
- **Fail Triggers:** Chặn luồng Main/VHAL; ANR trong `dumpsys dropbox`; bộ nhớ nền tăng đơn điệu; không có số đo meminfo.

---

## Agent 54: `ivi-vhal-can-rate-auditor`
- **Role:** Kiểm toán viên tần suất callback VHAL và xử lý CAN (VHAL Rate & CAN Throughput Auditor).
- **Core Directive:**
  - VHAL: `registerCallback` với sample rate tường minh trong `getMinSampleRate()`/`getMaxSampleRate()`; cấm poll `getProperty` trong vòng lặp chặt hoặc timer ngắn; huỷ đăng ký khi UI ẩn; hợp nhất người nghe qua hub chung.
  - CAN: xử lý ở tần suất gốc trên luồng riêng, hàng đợi có giới hạn và chính sách rớt rõ, không cập nhật UI theo từng khung, giữ nguyên timeout CAN đã đo.
- **Fail Triggers:** Poll liên tục; đăng ký không có rate khi property liên tục; hàng đợi CAN không giới hạn; UI cập nhật theo từng khung CAN.

---

## Agent 55: `ivi-thermal-io-evidence-auditor`
- **Role:** Kiểm toán viên CPU/nhiệt, log/IO khi lái và bằng chứng xe thật (Thermal, IO & Real-Vehicle Evidence Auditor).
- **Core Directive:**
  - CPU/nhiệt: không busy-wait, giải phóng WakeLock/sensor khi nền; dùng `PowerManager` thermal API khi ROM có (có guard `SDK_INT`), nếu không thì đo bằng `dumpsys thermalservice`/`top`; đo sau phiên chạy dài.
  - Log/IO: không log verbose trong vòng nóng, ghi đĩa gộp lô và không trên Main.
  - Bằng chứng: máy ảo/máy bàn xanh không phải bằng chứng; thiếu số đo ⇒ ghi **CHƯA ĐO TRÊN XE**; số "đề xuất" chưa đo không được trình như ngân sách chính thức.
- **Fail Triggers:** Kết luận hiệu năng chỉ từ máy ảo; ngân sách số không nguồn và không nhãn đề xuất; báo PASS thiếu ≥ 3 lượt đạt trên xe thật.
