# Automotive & IVI Specific Engineering Rules

> Áp dụng cho app chạy trên đầu xe (Android Automotive OS / IVI dựng trên AOSP cũ như Flyme Auto, ECARX — thường Android 9 / SDK 28), app điện thoại đi kèm (companion), và tool desktop quản trị qua ADB.
> Tên file trong các ví dụ (`MediaKeyProxyService.kt`, `CarAudioService.kt`…) là minh hoạ — tra đúng tên lớp tương ứng trong dự án.

## 1. Cô lập Luồng Dùng chung (Shared Flow Isolation)
- CẤM sửa trực tiếp logic mặc định trong các luồng dùng chung (ví dụ `MediaKeyProxyService.kt`, `GoogleMapsNavigator.kt`, `CarAudioService.kt`).
- Khi sửa lỗi cho app cụ thể (VD: YouTube, Google Maps split-screen), bắt buộc bọc trong:
  ```kotlin
  if (isTargetPackage(packageName, TARGET_PACKAGE)) {
      // Logic riêng cho target app
  } else {
      // Luồng mặc định cho ứng dụng bên thứ 3 (Media, Radio, Navigation) giữ nguyên 100%
      super.handleEvent(event)
  }
  ```

## 2. Bảo tồn Rào chắn Phần cứng Bất biến
- CẤM xóa bỏ hoặc sửa đổi các điều kiện kiểm tra:
  - `Build.VERSION.SDK_INT <= 28`
  - `Build.MANUFACTURER.contains("GenericAutomotiveIVI")`
  - IVI Head-Unit & CAN hardware quirks
  - Timeout trễ CAN bus đã đo đạc trên phần cứng thật.
- Guard đã đo trên xe chỉ được đổi khi có **số đo mới trên xe thật** chứng minh kết luận cũ sai; ghi số đo đó vào nhật ký bug của dự án cùng bản vá.

## 3. Quản lý Sự kiện & Tranh chấp Âm thanh
- Bắt buộc Debounce phím vô lăng $\ge 80\text{ms}$.
- Xử lý Audio Focus tranh chấp giữa Navigation và Media Player; trả focus (`abandonAudioFocus`) ở mọi nhánh thoát, kể cả nhánh lỗi.
- Đảm bảo Touch Target trên màn hình IVI $\ge 48\times 48\text{dp}$ (sàn cứng); điều khiển dùng khi đang lái nên lớn hơn — xem `DESIGN.md` §6.
- Phím vô lăng có thể đi qua **VHAL** chứ không qua `KeyEvent`: đo đường đi thật (log callback vô điều kiện) trước khi viết handler; mã hoá giá trị trong callback có thể khác giá trị `dumpsys` in ra.

## 4. System App, Chữ ký & Phân vùng Hệ thống
- App cần `android:sharedUserId="android.uid.system"` phải ký bằng **platform key** của ROM; không tự ý xoá `sharedUserId`/quyền hệ thống trong `AndroidManifest.xml` — mất nó là mất quyền điều khiển xe, không báo lỗi lúc build.
- Đổi `sharedUserId` giữa hai bản cài = UID khác nhau → phải gỡ bản cũ trước; ghi rõ trong tài liệu cài đặt.
- 🚫 **CẤM remount / ghi `/system`, `/vendor`, `/product`** (`adb remount`, `mount -o rw`, `adb disable-verity`, push vào `/system/priv-app`): đầu xe bật **dm-verity** — vi phạm = "device corrupt", màn xe không boot. Cài app chỉ qua `adb install` / `pm install` thường; cấu hình qua `settings put`, `pm`, `cmd`. Hook `hardware_safety_gate.sh` chặn các lệnh này — không bypass.
- Lệnh runtime (`am stack`, `am start --windowing-mode`, freeform) không ghi phân vùng nên không gây boot loop, nhưng có thể làm SystemUI/SurfaceFlinger (thậm chí `system_server`) khởi động lại — coi là thao tác rủi ro, không chạy khi xe đang lái.
- `pm install` từ app uid system bị SELinux chặn đọc file trong app data → APK tạm đặt ở vùng `pm` đọc được (vd `/data/local/tmp/`), kiểm quyền file trước khi cài.

## 5. VHAL / CarPropertyManager
- Mọi đọc/ghi thuộc tính xe đi qua **một cửa chung** (hub/binding của dự án) — không gọi `CarPropertyManager` rải rác trong UI/ViewModel.
- **Không chặn luồng**: cấm `Thread.sleep`/`runBlocking` trên luồng callback VHAL hoặc Main; ghi lặp dùng retry có lịch (backoff) trên dispatcher nền.
- **Đọc trạng thái trước khi ghi thuộc tính dạng toggle**: nhiều property là công tắc đảo (ghi = đổi trạng thái). Guard "đã đúng thì không ghi" phải chạy **sau khi `Car`/`CarPropertyManager` đã kết nối**; đọc trả `null` ⇒ KHÔNG ghi (đọc null mà vẫn ghi = xung toggle ngược).
- `Car.createCar(...)`: giữ đường fallback đã được chứng minh chạy trên ROM thật; đổi signature/cách kết nối là thay đổi rủi ro cao, phải đo trên xe.
- Giá trị ECU mặc định lúc xe thức (chế độ lái, mức tái sinh, âm cảnh báo…) **không phải ý chí người dùng** — không auto-sync đè cấu hình người dùng đã lưu bằng giá trị lúc boot. Cổng "vừa khởi động" không được dùng `elapsedRealtime` lưu qua reboot.
- Property đọc-được ≠ ghi-được: danh mục ID đã verify (đọc/ghi/status) là dữ liệu đo — tra trước khi đoán từ dump. Kiểm quyền `android.car.permission.*` tương ứng trước khi dùng.
- ID property VHAL không phải bí mật và có thể cần giữ nguyên qua R8 (reflection/AIDL) — kiểm keep rules khi bật obfuscation.

## 6. Giao thức Companion (Xe ↔ Điện thoại ↔ Desktop)
- DTO giao thức (status / command / response) sống ở **đúng một module dùng chung**; hai phía import từ đó. Cấm định nghĩa lại DTO ở app.
- Tên lệnh là **hằng** trong module dùng chung, không chuỗi trần ở hai đầu.
- Đổi/thêm/xoá field hoặc lệnh = **breaking change**: sửa cùng lúc spec giao thức + server (xe) + mọi client; thêm test tuần tự hoá ở cả hai phía.
- NDJSON = đúng **1 object/dòng**, không dòng rỗng thừa; mọi transport (TCP, Bluetooth SPP…) chia chung một lớp xử lý lệnh — không viết logic riêng theo transport.
- Mọi socket: timeout tường minh, đóng socket ở mọi nhánh lỗi (kể cả auth fail), xác thực trước khi nhận lệnh điều khiển. Test auth trên emulator phải nối qua IP thật của emulator — kết nối localhost có thể được miễn trừ.

## 7. Điều khiển xe bằng giọng nói — "Im còn hơn làm sai"
- Câu nghe không chắc chắn (tiếng cabin, câu cụt, snap/gần đúng, ảo giác STT) **không bao giờ** được biến thành lệnh phần cứng. Thiếu tham số ⇒ hỏi lại hoặc im, không đoán.
- Lệnh ảnh hưởng an toàn (kính, cửa/khoá, chế độ lái, phanh tái sinh, khởi động lại hệ thống) phải qua cổng ý định + **xác nhận khi xe đang chạy** trên đường giọng nói.
- Đo chất lượng bằng dữ liệu thật ngoài đường (mẫu số = toàn bộ lượt, kể cả lượt lỗi); cấm loại mẫu, đổi nhãn hay hạ ngưỡng để đẹp số.
- Mọi câu xe trả lời bằng giọng phải có clip/TTS thật và test phủ.

## 8. Bằng chứng trên Xe thật > Máy ảo
- Máy ảo xanh **không phải** bằng chứng cho hành vi phụ thuộc ROM, VHAL, âm thanh, mic, đa cửa sổ, độ trễ CPU. Sửa stub/mock của máy ảo để test xanh là giấu lỗi.
- Báo cáo ghi rõ đo ở đâu (máy bàn / máy ảo / xe thật); chưa đo trên xe ⇒ ghi **CHƯA ĐO TRÊN XE**, không suy ra.
- Bug đo trên xe: một lượt đạt không phải bằng chứng. Chỉ PASS khi có lần **chạy lặp sau bản sửa** — ≥3 lượt đạt, 0 lượt hỏng (lượt "không đo được" vì adb rớt không tính). Đánh dấu `agent-kit bugs add … --on-car`, nộp kết quả `agent-kit bugs repeat <ID> <ket-qua.json>`; thiếu thì checklist ghi `NEEDS_CAR`.
- Máy ảo dùng nguồn dữ liệu mô phỏng; xe thật chỉ dùng VHAL thật — cấm nút/cờ giả lập dữ liệu xe lộ ra UI người dùng.
- Luôn ghim `adb -s <serial>`; thiết bị cá nhân khai trong `.adb-denylist` (dự án) hoặc `~/.config/universal-agent-devkit/adb-denylist` (máy). `adb` trần có thể nhắm nhầm máy.
- Đừng đoán nguyên nhân crash: `adb logcat -d -b crash`, `dumpsys dropbox`, tombstone — log thắng suy luận. `pm list packages <x>` lọc chuỗi con, so khớp đúng `package:<x>`.
- Log đo trên xe ghi **ngay trên xe**, không stream về máy tính: ADB Wi-Fi rớt là `adb logcat` (không `-d/-c/-g/-t`) chết theo, mất log đúng lúc cần. Chụp một lần: `adb shell "logcat -d > /data/local/tmp/x.txt"` rồi `adb pull`; ghi suốt phép đo: `adb shell "nohup logcat -f /data/local/tmp/x.txt &"` rồi `adb pull`. `hardware_safety_gate` chặn dạng stream trên profile này.

## 9. Bản Phát hành & Hardening
- Bản public: R8 bật (minify + optimize), strip log, không `-dontobfuscate`, không keep toàn bộ `class **`; ký khoá thật (system app = platform key; app điện thoại = keystore riêng); giữ `mapping.txt` riêng, không đẩy public.
- Cổng kiểm hardening / tài liệu / ý định giọng nói của dự án là **cổng chặn** — không bypass, không chạy bản cài lên xe từ build debug ngoài quy trình (versionCode thấp hơn bản release có thể bị cơ chế cập nhật đè).
- Tài liệu nói sai là lỗi: con trỏ file, tên lớp, số phiên bản trong doc phải khớp mã nguồn.

## 10. ROM IVI thiếu API/màn hình chuẩn
- Intent tới màn hình hệ thống (tối ưu pin, cài đặt con…) có thể không tồn tại → `ActivityNotFoundException`. Kiểm bằng `resolveActivity`/`cmd package query-activities` và có nhánh dự phòng.
- Implicit broadcast receiver, PIP touch handler, divider chia màn hình, freezer tiến trình… có thể thiếu hoặc lỗi ở tầng ROM: xác nhận trên xe thật, bọc fallback + watchdog, ghi telemetry cho đường mới (mỗi đường một "vân tay" lọc được lỗi).
- Chỉ dùng API ≤ SDK của ROM hoặc có guard `Build.VERSION.SDK_INT`.
