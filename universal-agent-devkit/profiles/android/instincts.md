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

### [INSTINCT-AND-01] Room `@Insert(REPLACE)` Xoá Sạch Bản Ghi Con Qua `CASCADE`
- **Hiện tượng lỗi:** Bookmark/ghi chú/bản ghi con "tự biến mất" sau khi bản ghi cha được làm mới (quét lại thư mục, đồng bộ), dù không ai gọi delete.
- **Nguyên nhân gốc rễ:** `@Insert(onConflict = OnConflictStrategy.REPLACE)` là DELETE + INSERT; bảng con khai `ForeignKey(onDelete = CASCADE)` nên bị xoá theo.
- **Quy tắc bắt buộc:** Cập nhật bản ghi cha có con → `@Upsert` / `@Update` (update tại chỗ). Test: upsert cha cùng khoá → đếm bản ghi con không đổi.
- **Kiểm tra tự động:** `grep -rn "OnConflictStrategy.REPLACE" --include=*.kt .` rồi đối chiếu entity có bảng con `CASCADE`.

---

### [INSTINCT-AND-02] Thiết Lập XML Parser Ném Lỗi Trên Android Dù JVM Test Xanh (XXE hardening)
- **Hiện tượng lỗi:** Mọi lần đọc/ghi file OOXML/XML trên máy thật đều báo "file hỏng", unit test JVM vẫn xanh.
- **Nguyên nhân gốc rễ:** `SAXParserFactory.setFeature("http://apache.org/xml/features/...")` được Xerces (JVM) chấp nhận nhưng parser Expat của Android ném `SAXNotRecognizedException` (là `SAXException`); nằm chung `try` với `parse()` nên bị hiểu là "malformed".
- **Quy tắc bắt buộc:** `setFeature`/`setProperty` gọi best-effort trong `try` riêng; chặn external entity bằng `EntityResolver`/`resolveEntity` trả `InputSource` rỗng; hành vi phụ thuộc parser phải có instrumented test hoặc chạy trên máy.

---

### [INSTINCT-AND-03] R8 Dời Package Làm `getResourceAsStream` Tương Đối Trả `null` Ở Release
- **Hiện tượng lỗi:** Chỉ bản release crash `resource not found` / NPE khi nạp file tài nguyên đi kèm thư viện; debug chạy bình thường.
- **Nguyên nhân gốc rễ:** `Foo::class.java.getResourceAsStream("data.txt")` tra theo package của class; R8 repackage class sang package khác nên đường dẫn tương đối trỏ sai, trong khi resource vẫn ở chỗ cũ trong APK.
- **Quy tắc bắt buộc:** Dùng `classLoader.getResourceAsStream("đường/dẫn/tuyệt/đối/data.txt")` hoặc keep package; luôn chạy thử bản release đã minify trước phát hành.
- **Kiểm tra tự động:** `grep -rn "getResourceAsStream(\"[^/]" --include=*.kt --include=*.java .`

---

### [INSTINCT-AND-04] `System.gc()` Trong Dispose/Teardown Gây ANR
- **Hiện tượng lỗi:** ANR khi đóng màn hình/tài liệu; thread dump cho thấy main kẹt trong GC (`MarkCompact`/`RunPhases`).
- **Nguyên nhân gốc rễ:** Gọi `System.gc()` đồng bộ trên main trong `dispose()`/`onDestroy` trong khi thread nền còn cấp phát mạnh → pause kéo dài.
- **Quy tắc bắt buộc:** Không gọi `System.gc()`/`Runtime.getRuntime().gc()` trong code app; giải phóng tài nguyên bằng `close()`/`recycle()` tường minh.
- **Kiểm tra tự động:** `grep -rnE "System\.gc\(\)|Runtime\.getRuntime\(\)\.gc\(\)" --include=*.kt --include=*.java .`

---

### [INSTINCT-AND-05] Text Ít Dòng Nhưng Cực Dài Làm Treo `TextView`/`BasicTextField`
- **Hiện tượng lỗi:** ANR ở `TextView.onMeasure` → `DynamicLayout`/`minikin` khi mở file text/JSON/log minified.
- **Nguyên nhân gốc rễ:** Gate chọn "một view duy nhất vs hiển thị phân đoạn" chỉ theo số dòng; chi phí ngắt dòng tăng siêu tuyến tính theo độ dài một dòng.
- **Quy tắc bắt buộc:** Gate theo tổng số ký tự và độ dài dòng dài nhất, ngưỡng lấy từ đo đạc trên máy thật; vượt ngưỡng → hiển thị phân đoạn/ảo hoá, không đưa toàn bộ vào một view.

---

### [INSTINCT-AND-06] Chuỗi UI Đã Dịch / Tên File Lọt Vào Analytics
- **Hiện tượng lỗi:** Một lỗi hiển thị thành hàng chục giá trị `error_name` khác nhau theo ngôn ngữ; param analytics chứa tên file/đường dẫn thật của người dùng.
- **Nguyên nhân gốc rễ:** Callback lỗi chỉ truyền một `String` dùng cho cả dialog lẫn analytics; message được ghép path/tên file.
- **Quy tắc bắt buộc:** Tách `userMessage` (được dịch, được chứa chi tiết) khỏi `errorKey` (hằng số tiếng Anh, ít cardinality) ngay tại nguồn; chỉ `errorKey` đi vào analytics/Crashlytics; quét hết call site, kể cả đường đi qua module thư viện.

---

### [INSTINCT-AND-07] `CancellationException` Làm Nhiễu Crashlytics Non-fatal
- **Hiện tượng lỗi:** Dashboard đầy `JobCancellationException: Job was cancelled` không có stack hữu ích.
- **Nguyên nhân gốc rễ:** `catch (e: Exception) { crashlytics.recordException(e) }` bắt cả coroutine cancellation hợp lệ (người dùng rời màn hình, `withTimeout`).
- **Quy tắc bắt buộc:** Lọc `is CancellationException` tại helper ghi lỗi trung tâm (một chỗ cho mọi call site) và ném lại cancellation trong coroutine; lọc theo kiểu, không theo chuỗi message.

---

### [INSTINCT-AND-08] Khai Kiểu Mutable Là Stable Rồi Mutate Tại Chỗ (Compose)
- **Hiện tượng lỗi:** UI Compose không cập nhật (overlay/toạ độ/ngày giờ hiển thị giá trị cũ) dù state đã đổi.
- **Nguyên nhân gốc rễ:** `PointF`/`RectF`/`Rect`/`Date` được liệt kê trong stability configuration hoặc bọc trong `@Immutable`, nhưng code mutate cùng instance → Compose so sánh bằng nhau và bỏ qua recomposition.
- **Quy tắc bắt buộc:** Kiểu đã khai stable thì luôn tạo instance mới khi đổi giá trị; kiểm tra bằng compiler report + test UI trước/sau.

---

### [INSTINCT-AND-09] Coi `content://` URI Như File Path
- **Hiện tượng lỗi:** Mở/lưu tài liệu từ Drive/Downloads/app khác thất bại (`FileNotFoundException`, `EACCES`), tên file hiển thị là số hoặc `document:1234`.
- **Nguyên nhân gốc rễ:** Dùng `uri.path`/cột `_data`/segment cuối của URI như đường dẫn và tên file.
- **Quy tắc bắt buộc:** Đọc/ghi qua `ContentResolver` (stream/FD + `use`), tên và kích thước từ `OpenableColumns`; thu hồi quyền/xoá file là tình huống dự kiến có UI riêng.

---

### [INSTINCT-AND-10] Widget Crash Sau Khi Cập Nhật App (PendingIntent/Trampoline Cũ)
- **Hiện tượng lỗi:** Crash `InvisibleActionTrampolineActivity`/PendingIntent sai đích lặp lại trên máy vừa cập nhật app, dù đã sửa layout widget.
- **Nguyên nhân gốc rễ:** Layout/PendingIntent của bản cũ còn sống tới lần `onUpdate` kế tiếp; receiver không xử lý `ACTION_MY_PACKAGE_REPLACED`.
- **Quy tắc bắt buộc:** Mọi receiver widget xử lý `MY_PACKAGE_REPLACED` (manifest + `onReceive`, `goAsync()`) để render lại toàn bộ widget.

---

### [INSTINCT-AND-11] Build Xanh Nhưng Test Source Set Không Compile
- **Hiện tượng lỗi:** Đổi chữ ký hàm/constructor, `assembleDebug` xanh, CI/gate release đỏ vì `src/test` gọi chữ ký cũ.
- **Nguyên nhân gốc rễ:** `assembleDebug`/`compileDebugKotlin` không biên dịch test source set.
- **Quy tắc bắt buộc:** Sau khi đổi API dùng chung: `./gradlew :<m>:compileDebugKotlin :<m>:compileDebugUnitTestKotlin` cho mọi module bị ảnh hưởng; đọc số test từ `TEST-*.xml`, `UP-TO-DATE`/`No tests found` không phải PASS.

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
