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

### [INSTINCT-AND-12] ViewModel Lộ MutableStateFlow Hoặc Để Lỗi Rơi Khỏi viewModelScope
- **Hiện tượng lỗi:** UI sửa state trực tiếp; một lỗi của luồng dữ liệu làm crash hoặc làm UI kẹt Loading vĩnh viễn; test ViewModel lệch vì dispatcher thật.
- **Nguyên nhân gốc rễ:** `MutableStateFlow` public, không `.catch` thành state, không inject dispatcher/Main test (nguồn: android/architecture-samples — UDF, `MainCoroutineRule`).
- **Quy tắc bắt buộc:** Mutable private, lộ `StateFlow<UiState>` bất biến qua `stateIn`; lỗi thành state; test ViewModel dùng `MainCoroutineRule` và fake repository (xem `mobile-rules.md` §16).
- **Kiểm tra tự động:** grep `val .*: MutableStateFlow` không `private` trong ViewModel = 0; test repository ném lỗi → `UiState` chứa lỗi, không crash.

---

### [INSTINCT-AND-13] Vùng Chạm Chồng Nhau Chọn Theo Thứ Tự Duyệt, Không Theo Khoảng Cách Gần Nhất
- **Hiện tượng lỗi:** Hai vùng chạm nằm trong bán kính bắt của nhau thì luôn thắng cùng một vùng, bất kể ngón tay chạm gần vùng nào. Ví dụ: chọn chữ trong PDF, handle cuối của một từ ngắn (~60 px) nằm trong bán kính 80 px của handle đầu; handle đầu được kiểm tra trước nên kéo handle cuối lại kéo handle đầu, và "Dịch" chỉ nhận 1–2 từ. Unit test xanh vì logic nằm trong `View` trên PDFium gốc, test dịch dùng engine giả và chuỗi cố định.
- **Nguyên nhân gốc rễ:** Hit-test dạng `if (hit(a)) … else if (hit(b)) …` (hoặc `firstOrNull { it.contains(point) }`): vùng nào đứng trước trong danh sách thắng khi chồng nhau.
- **Quy tắc bắt buộc:** Khi nhiều vùng cùng chứa điểm chạm, chọn vùng có khoảng cách tới điểm chạm xuống (down) nhỏ nhất (nearest-wins), hoà thì theo quy tắc phụ cố định (ví dụ vùng đang được chọn); tuyệt đối không dựa vào thứ tự kiểm tra. Cố định đích kéo từ lúc ACTION_DOWN tới ACTION_UP. Test: hai vùng gần hơn bán kính bắt, chạm sát vùng thứ hai ⇒ vùng thứ hai thắng; đảo thứ tự danh sách không đổi kết quả.
- **Kiểm tra tự động:** `grep -rnE "firstOrNull \{[^}]*(contains|hit|isNear)" --include=*.kt .` và đọc từng chuỗi `if (hit…) … else if (hit…)` trong `onTouchEvent`/`pointerInput`; chỉ rõ cả thứ tự kiểm tra lẫn bán kính bắt trong test.
- **Nguồn:** OfficeReader 07/10/2026 (bẫy không riêng một dự án nên được đưa lên profile android, để mọi app Android nhận nó).

---

### [INSTINCT-AND-14] `windowInsetsPadding` Bên Trong Vùng Mà Scaffold Đã Đệm Inset Rồi
- **Hiện tượng lỗi:** Nút/pill nổi ở đáy màn hình cao hơn đáy thật ~75 dp: bounds đo trên máy là 210 px thay vì 30 px. Robolectric Compose chạy với inset = 0 nên test xanh.
- **Nguyên nhân gốc rễ:** Nội dung đã nhận `innerPadding` của `Scaffold` (đã gồm thanh điều hướng), rồi một con lại gọi `Modifier.windowInsetsPadding(WindowInsets.navigationBars)` / `navigationBarsPadding()` / `systemBarsPadding()` cho cùng cạnh: inset bị đệm hai lần.
- **Quy tắc bắt buộc:** Một cạnh chỉ được đệm inset đúng một lần. Nội dung nằm dưới `innerPadding` thì dùng `innerPadding`, không thêm `windowInsetsPadding` cho cạnh đó; con nào tự xử lý inset thì cha phải `Modifier.consumeWindowInsets(innerPadding)` trước. Đo bằng bounds thật (`ui-query` / `dump-view-hierarchy.sh`) trên máy hoặc test dựng inset có chủ đích (`compose-overlap-invariants`), không suy từ code; ma trận trạng thái (cử chỉ / 3 nút × hướng) theo `mobile-rules.md` §15.
- **Kiểm tra tự động:** `grep -rnE "windowInsetsPadding|navigationBarsPadding|systemBarsPadding|safeDrawingPadding" --include=*.kt .` rồi đối chiếu từng chỗ nằm trong content lambda của `Scaffold` có dùng `innerPadding`.
- **Nguồn:** OfficeReader 07/10/2026 (bẫy không riêng một dự án nên được đưa lên profile android, để mọi app Android nhận nó).

---

## 1b. Bẫy iOS / Swift (từ profile ios)
### [INSTINCT-IOS-01] Bẫy Rò Rỉ Bộ Nhớ Vòng Lặp Tham Chiếu (Retain Cycle In Closures)
- **Hiện tượng lỗi:** Người dùng mở màn hình chi tiết rồi back ra nhiều lần, bộ nhớ RAM tăng liên tục từ 100MB lên 500MB+ dẫn tới crash OOM (Out Of Memory) hoặc thông báo terminate từ hệ điều hành.
- **Nguyên nhân gốc rễ:** Capture strong `self` trong escaping closures của Network call, Combine sink, NotificationCenter hoặc Timer, làm ViewController / ViewModel không bao giờ được dealloc.
- **Quy tắc bắt buộc:** 
  1. Mọi escaping closure có truy cập thuộc tính của lớp phải dùng `[weak self]` và kiểm tra `guard let self else { return }`.
  2. Mọi delegate protocol phải là `weak var delegate: MyDelegate?`.

---

### [INSTINCT-IOS-02] Bẫy Cập Nhật Giao Diện Ngoài `@MainActor` (Data Race Crash)
- **Hiện tượng lỗi:** Ứng dụng thi thoảng bị crash bí ẩn với lỗi `EXC_BAD_INSTRUCTION` hoặc `Main Thread Checker: UI API called on a background thread` khi cập nhật label hoặc show alert.
- **Nguyên nhân gốc rễ:** Nhận kết quả từ background task hoặc URLSession dataTask rồi gán trực tiếp vào biến state của UI mà không điều phối về Main Thread.
- **Quy tắc bắt buộc:** 
  1. Toàn bộ ViewModel liên kết với SwiftUI View phải được khai báo `@MainActor`.
  2. Bật cờ Strict Concurrency Checking (`-strict-concurrency=complete`) trong build settings của Xcode để bắt lỗi data race ngay lúc compile.

---

### [INSTINCT-IOS-03] Bẫy Tính Toán Nặng Trong SwiftUI `body` Gây Tụt Frame 120 FPS
- **Hiện tượng lỗi:** Màn hình cuộn bị khựng giật (Drop frame xuống 30–45 FPS trên màn hình ProMotion 120Hz).
- **Nguyên nhân gốc rễ:** Khởi tạo `DateFormatter()`, `NumberFormatter()`, gọi hàm sort mảng lớn hoặc đọc UserDefaults trực tiếp bên trong `var body: some View`. Vì SwiftUI gọi lại `body` liên tục mỗi khi state thay đổi, các phép toán này lặp lại hàng trăm lần.
- **Quy tắc bắt buộc:** 
  1. Thuộc tính `body` chỉ chứa khai báo View thuần túy.
  2. Toàn bộ logic định dạng và xử lý dữ liệu phải được tiền xử lý và cache trong ViewModel.

---

### [INSTINCT-IOS-04] Bẫy Xung Đột Luồng CoreData / SwiftData (Concurrency Violation)
- **Hiện tượng lỗi:** Sập app bất ngờ với lỗi `CoreData: Concurrency violation` hoặc `EXC_BAD_ACCESS` khi ghi dữ liệu nền.
- **Nguyên nhân gốc rễ:** Dùng `NSManagedObject` hoặc `ModelContext` tạo từ Main Thread trên background thread mà không gọi `performBackgroundTask` hoặc background context riêng.
- **Quy tắc bắt buộc:** Mỗi thread hoặc background task phải có context riêng biệt; chỉ truyền `NSManagedObjectID` hoặc PersistentIdentifier giữa các luồng.

---

### [INSTINCT-IOS-05] Vùng Chạm Dưới Chuẩn Apple HIG (< 44pt) & Chống Spam Chạm
- **Hiện tượng lỗi:** Nút bấm quá nhỏ, người dùng bấm trượt hoặc bấm 2 lần liên tiếp gây trùng đơn hàng.
- **Nguyên nhân gốc rễ:** Frame nút bấm nhỏ hơn $44\times 44\text{pt}$, không có debounce.
- **Quy tắc bắt buộc:**
  1. Áp dụng `.frame(minWidth: 44, minHeight: 44)` hoặc `.contentShape(Rectangle())` mở rộng vùng chạm.
  2. Khóa tức thì trạng thái nút với `.disabled(isSubmitting)` sau cú chạm đầu tiên.

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
