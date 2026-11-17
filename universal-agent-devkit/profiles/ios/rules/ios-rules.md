# 🍏 iOS Native Mobile Engineering Standards & Rules (Swift / SwiftUI)

Quy chuẩn kỹ thuật bắt buộc dành cho AI Agent khi phát triển, tối ưu và sửa lỗi ứng dụng iOS (Swift 6, SwiftUI, Swift Concurrency, XCTest).

---

## 1. Quản Trị Bộ Nhớ & Triệt Tiêu Vòng Lặp Tham Chiếu ARC (Zero Retain Cycles)

1. **Bắt buộc `[weak self]` trong Escaping Closures:**
   - Mọi closure bất đồng bộ, callback mạng (URLSession / Alamofire), Combine pipeline, hoặc completion handler dài hạn **BẮT BUỘC** phải sử dụng capture list `[weak self]` để tránh giữ chặt reference cycle:
     ```swift
     // CHUẨN MỰC:
     viewModel.fetchData { [weak self] result in
         guard let self else { return }
         self.updateUI(with: result)
     }
     ```
   - Tuyệt đối cấm capture strong `self` bên trong closures của NotificationCenter, Timer publisher hoặc async Task sống lâu.
2. **Delegate References Phải Là `weak var`:**
   - Mọi protocol delegate bắt buộc phải kế thừa `AnyObject` và khai báo dưới dạng `weak var delegate: MyDelegate?`.
3. **Giải Phóng Bộ Nhớ Hình Ảnh & Tài Nguyên Nặng:**
   - Bắt buộc kiểm tra và giải phóng UIImage / CGImage lớn khi view biến mất (`viewDidDisappear` hoặc `onDisappear`).
   - Sử dụng `autoreleasepool { ... }` khi xử lý hàng loạt tệp hoặc ảnh trong vòng lặp lớn.

---

## 2. Quản Trị Luồng & Swift Concurrency (@MainActor & Data Race Safety)

1. **Bảo Vệ Giao Diện Trên `@MainActor`:**
   - Mọi lớp ViewModel gắn với UI (hoặc `@Observable` class), hàm cập nhật trạng thái hiển thị, và navigation coordinator bắt buộc phải được gắn nhãn `@MainActor`:
     ```swift
     @MainActor
     @Observable
     final class OrderDetailViewModel {
         var state: ViewState = .idle
         // ...
     }
     ```
2. **Triệt Tiêu Data Race (Swift 6 Concurrency):**
   - Không chia sẻ đối tượng mutable reference type giữa các Task không cùng Actor.
   - Các class chia sẻ đa luồng phải là `actor` hoặc cấu trúc bất biến `struct` tuân thủ `Sendable`.
3. **Structured Concurrency & Hủy Bỏ Tác Vụ (Cancellation):**
   - Ưu tiên sử dụng `async/await` và `withTaskGroup` thay vì callback lồng nhau.
   - Luôn kiểm tra `Task.isCancelled` trong các vòng lặp tính toán nặng hoặc tải dữ liệu để dừng ngay khi người dùng rời màn hình.

---

## 3. Tối Ưu Hóa Hiệu Năng SwiftUI & Tránh Redraw Thừa (Frame Budget 120 FPS)

1. **Ngăn Ngừa Redraw Toàn Bộ View Hierarchy:**
   - Tránh lưu trữ trạng thái khổng lồ trong một biến `@State` duy nhất khiến toàn bộ `body` phải tính toán lại mỗi khi một trường nhỏ thay đổi.
   - Áp dụng macro `@Observable` (iOS 17+) để SwiftUI tự động track chính xác từng thuộc tính riêng lẻ, chỉ vẽ lại đúng View con phụ thuộc.
2. **Giữ Cho `body` Thuần Túy (Pure Computation):**
   - Tuyệt đối **KHÔNG** thực hiện đọc ghi tệp (Disk I/O), tính toán thuật toán nặng $O(N^2)$, hoặc khởi tạo đối tượng phức tạp bên trong `var body: some View`.
   - Mọi phép định dạng ngày tháng (`DateFormatter`) hoặc số tiền (`NumberFormatter`) phải được cache tái sử dụng ở ViewModel / singleton, không khởi tạo mới trong `body`.
3. **Độ Rộng Vùng Chạm & Chống Spam Nút Bấm:**
   - Nút bấm phải có vùng chạm tối thiểu $\ge 44\times 44\text{pt}$ (chuẩn Apple Human Interface Guidelines).
   - Nút bấm kích hoạt giao dịch / thanh toán / ký số bắt buộc phải có biến `isLoading` để disable ngay lập tức sau cú chạm đầu tiên (`.disabled(isLoading)`).

---

## 4. Kỷ Luật Kiểm Thử XCTest & Đo Đạc Rò Rỉ Bộ Nhớ

1. **Paired Executable Oracle Bắt Buộc (XCTest):**
   - Viết bài test thất bại (**RED**) mô phỏng chính xác lỗi logic hoặc crash trước khi sửa code:
     ```bash
     xcodebuild test -scheme AppTests -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:AppTests/OrderTests/testDiscountCalculation_RED
     ```
   - Sửa code tối giản và chạy lại đúng bài test đó để xác nhận thành công (**GREEN**).
2. **Kiểm Tra Rò Rỉ Bộ Nhớ Bằng `leaks` CLI:**
   - Chạy lệnh kiểm tra rò rỉ bộ nhớ trên binary test:
     ```bash
     leaks -atExit -- ./build/Build/Products/Debug-iphonesimulator/App.app/App
     ```
   - Đảm bảo 0 memory leaks, 0 retain cycles được báo cáo.

## 5. SwiftUI UI & Apple HIG (Anti-Slop)
- **Safe Area & Insets**: Nút CTA dính đáy dùng `.safeAreaInset(edge: .bottom)` để đẩy nội dung; tuyệt đối không dùng `.ignoresSafeArea()` tràn lan gây lẹm chữ vào tai thỏ/Dynamic Island.
- **Bàn phím & Navigation**: Bàn phím không được che khuất input (SwiftUI tự xử lý nếu dùng đúng form/scroll view). Sheet nên dùng `.presentationDetents([.medium, .large])` (iOS 16+) để người dùng dễ vuốt đóng.
- **Mandatory 4 trạng thái**: Mọi màn hình phải có đủ 4 trạng thái thiết kế: Loading (dùng skeleton/redacted thay vì spinner), Empty (kèm CTA), Error (kèm Thử lại), Populated.
- **Zero-Slop & Vùng chạm**: Hit area $\ge 44\times 44\text{pt}$ (xem lại §3). Cấm thiết kế rập khuôn: Card lồng Card, dùng `Color.gray` trần, gradient tím-indigo mặc định, và câu chào sáo rỗng "Welcome back 👋".
- Quy trình chuẩn: Sử dụng skill `taste-mobile-app` kết hợp `impeccable` (`skills/impeccable/reference/ios.md`) để định hướng thẩm mỹ Apple HIG, phân cấp typography và kiểm tra UI/UX chống slop.

---

## 6. Quy tắc chung (từ universal, áp cho app iOS)

> Nhãn số liệu trong §7–§10: mỗi con số mang một trong hai nhãn: **nguồn** (tên tài liệu, phải kiểm lại theo bản hiện hành trước khi dùng làm cổng chặn) hoặc **"mặc định đề xuất của dự án, cần đo trên máy thật"**. Không có số đo từ **máy thật** (cùng model, build Release, sạc và nhiệt ổn định) thì không được tuyên bố "đã tối ưu"; Simulator chỉ để dev nhanh và so sánh tương đối, không làm bằng chứng hiệu năng.

1. **Solo-Dev & Git Security (BẮT BUỘC):** tự commit/push khi xong theo DevKit essentials (`AGENTS.md`, mục Git). Cấm commit bí mật: tệp môi trường chứa khoá, token, mật khẩu, certificate `.p12`, provisioning profile, `GoogleService-Info.plist` thật, API key; nạp qua `.xcconfig` ngoài Git, biến môi trường CI hoặc secret manager. Dữ liệu nhạy cảm của người dùng lưu trong Keychain, không `UserDefaults`, không log. Soát `git diff` trước khi báo xong.
2. **Paired Executable Oracle:** mỗi bug fix có test RED chạy thấy FAIL trước khi sửa code production, rồi cùng test đó GREEN (lệnh `xcodebuild test -only-testing:` ở §4). Cấm xoá/nới assertion, cấm `XCTAssertTrue(true)`, cấm mock lỏng để ép xanh. Compile xanh chỉ chứng minh compile.
3. **Chống spam và bất đồng bộ:** thao tác tốn kém (gọi API, giao dịch, ký số, kích hoạt workflow) phải có trạng thái loading, disable ngay lần chạm đầu và debounce ≥ 1000 ms (nguồn: DevKit essentials, `AGENTS.md`, mục Engineering musts). Mạng: connect ≤ 10 s, read ≤ 15 s (`URLSessionConfiguration.timeoutIntervalForRequest`), chỉ retry thao tác idempotent, có backoff + jitter, idempotency key cho ghi thanh toán/đơn hàng (cùng nguồn).
4. **Bằng chứng nghiệm thu:** tính năng chỉ xong khi có bằng chứng trạng thái THÀNH CÔNG chạy thật: số test `> 0` và 0 failure trong kết quả `xcodebuild`, và với UI là ảnh chụp trạng thái thành công từ **máy thật** (tem thời gian của lượt chạy hiện tại). Không có thiết bị thì ghi `UNTESTED`/CHƯA XÁC MINH, tuyệt đối không giả PASS.
5. **Clean Architecture & Dependency Rule:** `Domain` (entity, value object, use case) không import `SwiftUI`/`UIKit`/`CoreData`/SDK bên thứ ba; phụ thuộc chỉ trỏ từ ngoài vào trong; `View` không chứa nghiệp vụ, ViewModel gọi use case qua protocol (port ở ranh giới thật: mạng, lưu trữ, Keychain), không tạo port cho mọi thứ.
6. **Bảo mật nền tảng:** App Transport Security bật, không `NSAllowsArbitraryLoads` ở Release; validate URL scheme/universal link và tham số nhận vào; `WKWebView` tắt JavaScript/truy cập file trừ khi đã verify yêu cầu, allowlist origin; không đưa PII, token, đường dẫn đầy đủ vào log hay telemetry.

---

## 7. Hiệu năng iOS — Ngân sách đo được

### 7.1 Bảng ngân sách

| Chỉ số | Ngân sách | Nguồn / trạng thái | Cách đo |
|---|---|---|---|
| Khởi động nguội đến frame đầu | 400 ms | mặc định đề xuất của dự án, cần đo trên máy thật | Instruments mẫu "App Launch"; `XCTApplicationLaunchMetric`; MetricKit `MXAppLaunchMetric` |
| Khung hình 60 Hz | 16,6 ms/khung (1000 ms ÷ 60) | Phép tính từ tần số quét | Instruments "Animation Hitches"; `XCTHitchMetric` |
| Khung hình 120 Hz (ProMotion) | 8,3 ms/khung (1000 ms ÷ 120) | Phép tính từ tần số quét | Như trên, trên máy có màn ProMotion |
| Hitch time ratio | Dưới 5 ms mỗi giây là "tốt" | Apple WWDC "Eliminate animation hitches" / Xcode Organizer; kiểm lại tài liệu hiện hành | `XCTHitchMetric`; MetricKit `MXAnimationMetric` |
| Hang (main thread không phản hồi) | Không bị chặn quá 250 ms | Apple, tài liệu "Understand hangs in your app" | Instruments "Hangs"; MetricKit `MXHangDiagnostic`; Xcode Organizer |
| Jank | Không quá 5% khung chậm, tốc độ khung giữ ≥ 58 FPS (60 Hz) hoặc ≥ 115 FPS (120 Hz) | Ngưỡng của council `07-performance-anr` trong kit (kiểm lại cho từng app) | Instruments "Animation Hitches" trong kịch bản cuộn chuẩn |
| Bộ nhớ / rò rỉ | Sau 10 vòng vào–ra một màn hình, bộ nhớ không tăng đều và không còn instance `UIViewController`/ViewModel cũ | mặc định đề xuất của dự án, cần đo trên máy thật | Instruments "Leaks" + "Allocations" (Mark Generation), `leaks -atExit` (§4), `XCTMemoryMetric`, Debug Memory Graph |
| Năng lượng / nhiệt | `ProcessInfo.thermalState` không vượt `.fair` trong kịch bản chuẩn của app, không giữ CPU/GPS/radio ngoài thời gian cần | mặc định đề xuất của dự án, cần đo trên máy thật | Instruments "Energy Log"; `ProcessInfo.thermalState`; MetricKit `MXCPUMetric`, `MXLocationActivityMetric` |
| Mạng | Connect ≤ 10 s, read ≤ 15 s, retry idempotent + backoff + jitter | DevKit essentials (`AGENTS.md`) | Network Link Conditioner, `URLProtocol` giả lập |

### 7.2 Luật bắt buộc đi kèm

1. **Đo trước, sửa sau, đo lại:** mọi PR "tối ưu" nêu số trước/sau, cùng máy, cùng build Release, cùng trạng thái nhiệt, có đường dẫn trace (`.trace`) hoặc kết quả `xcresult`. Không có số = không có tuyên bố. Thắng hiệu năng cần đo xen kẽ A/B rồi B/A, tối thiểu 5 cặp sau warmup, so median và dải; dải lớn hơn 20% median hoặc hai dải chồng lấp thì kết luận `inconclusive` (nguồn: skill `verification-before-completion` trong kit). Không kết luận từ một lần chạy.
2. **Máy thật:** bằng chứng hiệu năng từ thiết bị thật, build Release, và một máy ProMotion nếu app hỗ trợ; ghi model máy và phiên bản iOS vào báo cáo. Simulator không đại diện CPU, GPU, nhiệt, bộ nhớ thật.
3. **Khởi động:** chỉ làm việc cần cho frame đầu trong `application(_:didFinishLaunchingWithOptions:)`/`App.init`; khởi tạo SDK, analytics, cache khác dời sau frame đầu (`Task` ưu tiên thấp hoặc sau khi giao diện hiện). Không I/O đồng bộ, parse lớn, khởi tạo `static let` nặng ở đường khởi động; giảm số framework động khi có thể.
4. **Hitch và khung hình:** mỗi màn hình có danh sách hoặc animation phải có kết quả đo hitch ở 60 Hz và, nếu máy hỗ trợ, ở 120 Hz. Danh sách động dùng `List` hoặc `LazyVStack`/`LazyHStack` với identity ổn định (`id` bền, không dùng `index` làm id khi dữ liệu đổi), không bọc danh sách dài trong `VStack` thường. Đọc thuộc tính ViewModel đúng nơi cần để `@Observable` chỉ vẽ lại View con liên quan; khi nghi redraw thừa dùng `Self._printChanges()` ở debug để tìm nguyên nhân. Không đổi tần số quét chỉ để qua cổng.
5. **Hang và main thread:** I/O, mạng, mã hoá, parse JSON lớn, giải mã ảnh, truy vấn CoreData/SwiftData nặng không chạy trên main thread; chuyển sang `actor`/`Task` nền (§2) rồi quay về `@MainActor` để cập nhật giao diện. Bật Main Thread Checker (scheme Run) trong debug và coi vi phạm là lỗi. Cấm `DispatchQueue.main.sync` gọi từ main và cấm khoá đồng bộ trên main.
6. **Swift Concurrency:** không `Task.detached` khi `Task` kế thừa actor là đủ; huỷ `Task` khi rời màn hình (`.task` modifier tự huỷ); không chặn thread của cooperative pool bằng `DispatchSemaphore`/`sleep`; bật `-strict-concurrency=complete` và coi cảnh báo concurrency mới là lỗi (§8).
7. **Bộ nhớ và ảnh:** giải mã ảnh theo kích thước hiển thị bằng ImageIO (`CGImageSourceCreateThumbnailAtIndex`) thay vì nạp ảnh gốc; ảnh/tệp lớn xử lý theo luồng, trong `autoreleasepool` (§1). Phản ứng `UIApplication.didReceiveMemoryWarningNotification` bằng cách xả cache. Sau 10 vòng vào–ra (bảng 7.1) không còn instance cũ; đối tượng sống lâu (singleton, cache) có giới hạn kích thước (`NSCache` với `countLimit`/`totalCostLimit`).
8. **Năng lượng và nhiệt:** quan sát `ProcessInfo.thermalState` và `isLowPowerModeEnabled`; khi `.serious` trở lên hoặc Low Power Mode thì giảm tần suất làm việc nền, ngừng animation không cần, hạ chất lượng xử lý. Dừng quét vị trí độ chính xác cao, huỷ `Timer`/`CADisplayLink`/sensor khi vào background; việc nền dùng `BGTaskScheduler`, không giữ background task quá hạn.
9. **Quan sát production:** đăng ký `MXMetricManager` (gói `MXMetricPayload`, `MXDiagnosticPayload`) để nhận khởi động, hitch, hang, CPU, ghi đĩa, crash; đo đoạn quan trọng bằng `OSSignposter`/`os_signpost` để hiện trong Instruments và `XCTOSSignpostMetric`. Log bằng `os.Logger` với `privacy` đúng (mặc định coi tham số động là private), không PII, nhãn metric có số giá trị hữu hạn (skill `observability-instrumentation`).
10. **Hồi quy hiệu năng là hồi quy chức năng:** thêm test hiệu năng bằng `measure(metrics:options:)` với `XCTClockMetric`, `XCTCPUMetric`, `XCTMemoryMetric`, `XCTStorageMetric`, `XCTApplicationLaunchMetric` hoặc `XCTHitchMetric`; đặt baseline theo máy/CI cố định của dự án; số đo vượt baseline đã chốt chặn merge như test đỏ. Chạy trên máy thật cố định model, sạc đủ, nhiệt ổn định, tắt cập nhật nền.

---

## 8. Chất lượng — Cổng kiểm chứng

1. **Paired oracle RED→GREEN:** mỗi bug fix có đúng một test ở ranh giới lỗi thật; thấy RED trước khi sửa production, sửa tối giản, chạy lại đúng test đó thấy GREEN; giữ lệnh và exit code (lệnh ở §4). Test đã sửa cần agent khác duyệt theo luật DevKit. Logic trích ra object mới cần test nối View ↔ ViewModel/object (test tích hợp ở biên thật).
2. **Ma trận hồi quy:** `regression_matrix.json` chỉ giữ mục có lệnh test thật, chạy được (scheme XCTest hoặc `swift test` của dự án); không thêm mục "cho đủ". File trong `watch_files` đổi thì chạy đúng test của component tương ứng; đổi `Package.swift`, cấu hình build chung thì chạy cả test target.
3. **Lint và format:** `swiftlint --strict` và `swiftformat --lint .` chạy ở CI, vi phạm mới là đỏ; baseline chỉ để ghi nợ cũ, không thêm để qua cổng. Bật `SWIFT_STRICT_CONCURRENCY = complete` (`-strict-concurrency=complete`, §2) và coi cảnh báo concurrency mới là lỗi.
4. **Framework test:** Swift Testing (`@Test`, `#expect`, `#require`, parameterized) cho unit/logic mới; XCTest cho UI test (XCUITest) và test hiệu năng (`measure`, `XCTMetric`), vì Swift Testing không thay được hai loại này. Hai framework có thể sống chung trong một target. Test hành vi quan sát được, không khoá hàm private hay thứ tự gọi ngẫu nhiên.
5. **Kim tự tháp test:** nhiều unit test nhanh ở đáy (Domain, ViewModel, không UI), ít hơn integration (`URLProtocol` giả, store in-memory), ít nhất là UI/E2E trên máy thật (XCUITest). Tỷ lệ tham khảo 70/20/10 (Google Testing Blog, "Just Say No to More End-to-End Tests"); với dự án này tỷ lệ thật là mặc định đề xuất của dự án, cần đo trên máy thật và dữ liệu CI (thời gian chạy và số lỗi bắt được mỗi tầng). Fake viết tay ưu tiên hơn mock; test không phụ thuộc thứ tự, giờ hệ thống, mạng thật; dùng `Clock`/`Date` được inject.
6. **Chọn bằng chứng nhỏ nhất đủ chứng minh:** logic/Domain thì unit test; ViewModel `@MainActor` thì unit test với `async` test; luồng bất đồng bộ/huỷ thì test với `AsyncStream`/continuation tất định, không `sleep`; biên mạng/lưu trữ thì integration; hiển thị, vùng chạm và a11y thì XCUITest + `app.performAccessibilityAudit()`; vòng đời, quyền, tệp, hiệu năng thì chạy trên máy thật. Compile, mock-only test, lint không chứng minh runtime/thiết bị/bảo mật/hiệu năng.
7. **Surviving Mutant Guard và chống tautology:** test mới chạy xanh ngay lần đầu thì làm hỏng thử đúng dòng production được bảo vệ (đảo `>` thành `>=`, đổi hằng số), thấy RED rồi hoàn nguyên thấy GREEN (không commit bản hỏng). Cấm `expected` tính lại bằng công thức của hàm đang test, cấm assert trên giá trị của chính mock do test dựng.
8. **Crash-free:** mỗi phát hành đối chiếu Xcode Organizer và Crashlytics với bản trước; crash mới kèm test tái hiện (mục 1). Mục tiêu nội bộ crash-free sessions ≥ 99,5% và crash-free users ≥ 99% là mặc định đề xuất của dự án, cần đo trên máy thật và dữ liệu Organizer/Crashlytics của dự án. Lỗi dự kiến (mất mạng, `CancellationError`, tệp bị xoá) không đẩy lên như lỗi.
9. **Kiểm soát flaky:** test flaky là lỗi chất lượng: không `sleep` cố định, không toạ độ cứng, không phụ thuộc thứ tự; dùng `XCTestExpectation`/`await` có điều kiện, `waitForExistence(timeout:)`. Test mới hoặc vừa sửa chạy lặp (`xcodebuild test -test-iterations 20 -run-tests-until-failure`; số lần 20 là mặc định đề xuất của dự án, cần đo trên máy thật và CI của dự án, số thật theo kế hoạch đo) và phải xanh mọi lần; một lần đỏ thì sửa nguyên nhân, không che bằng retry. `-retry-tests-on-failure` ở CI chỉ để phát hiện và gắn nhãn flaky, không để làm xanh.
10. **Bằng chứng kết quả:** đọc kết quả thật của `xcodebuild` (`Executed N tests, with 0 failures`, hoặc `xcresult`): `N > 0` và 0 failure; "no tests" hoặc kết quả cache cũ không phải PASS. Nghiệm thu UI: ảnh trạng thái thành công từ máy thật, build Release; không chạy được thì `UNTESTED`.
11. **Cổng chung:** `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --scoped --brief` exit 0 trước khi báo xong; sắp tuyên bố "xong/fixed/PASS" thì chạy skill `verification-before-completion`.

---

## 9. UI/UX & Accessibility — Cổng bắt buộc (token chi tiết: `DESIGN.md`)

1. **Apple HIG trước, tự vẽ sau:** dùng thành phần và hành vi chuẩn của nền tảng (tab bar 2–5 mục cho các khu vực, navigation stack cho phân cấp, sheet cho tác vụ khép kín, alert/confirmation dialog/context menu/swipe actions, Large Title ở màn cấp cao). Không tắt hoặc che cử chỉ vuốt cạnh trái để quay lại. Dùng SF Symbols, không trộn bộ icon web. Dùng thành phần hệ thống (`List` grouped/inset, `Form`, `Toggle`, `Picker`) cho màn dạng cài đặt, không dựng bản sao tự chế.
2. **Vùng chạm:** ≥ 44×44 pt (Apple HIG); icon nhìn thấy có thể nhỏ hơn, mở rộng bằng `.contentShape(Rectangle())` và `.frame(minWidth: 44, minHeight: 44)`. Hai vùng chạm cạnh nhau cách ≥ 8 pt (nguồn: skill `ui-ux-pro-max`, nhóm "Touch & Interaction"). CTA chính nằm nửa dưới màn hình, trong tầm ngón cái, hoặc dính đáy bằng `.safeAreaInset(edge: .bottom)` (§5).
3. **Dynamic Type:** dùng `Font.TextStyle` hệ thống (`.body`, `.headline`, `.caption`...) hoặc `Font.custom(_:size:relativeTo:)`, không cố định cỡ chữ theo point; kiểm tra tới các cỡ accessibility lớn nhất (`.dynamicTypeSize(...accessibility5)`); không cố định chiều cao khung chữ, cho phép xuống dòng; với bố cục ngang dùng `ViewThatFits` hoặc `@Environment(\.dynamicTypeSize)` để chuyển sang xếp dọc; số liệu dùng `@ScaledMetric`. Sàn cỡ chữ 11 pt, Body 17 pt (nguồn: `skills/impeccable/reference/ios.md` của kit; Apple HIG, Typography).
4. **VoiceOver:** mọi phần tử tương tác đọc được tên + vai trò + trạng thái: `accessibilityLabel`, `accessibilityValue`, `accessibilityHint` (chỉ khi cần), trait đúng (`.isButton`, `.isHeader`, `.isSelected`); nhóm phần tử bằng `accessibilityElement(children: .combine)`; ẩn phần trang trí bằng `accessibilityHidden(true)`; thứ tự đọc đúng thứ tự logic (`accessibilitySortPriority` khi cần); thông báo thay đổi động bằng `AccessibilityNotification`/`UIAccessibility.post`. Icon-only button luôn có `accessibilityLabel`. Duyệt tay bằng VoiceOver trên máy thật cho luồng chính; tự động bằng `app.performAccessibilityAudit()` trong XCUITest.
5. **Tương phản:** chữ thường ≥ 4,5:1, chữ lớn ≥ 3:1 (WCAG 2.x mức AA, tiêu chí 1.4.3); thành phần giao diện không phải chữ (icon, viền input) ≥ 3:1 (WCAG 1.4.11). Dùng màu ngữ nghĩa hệ thống để tự thích ứng với Dark Mode và Increased Contrast; không truyền thông tin chỉ bằng màu (`@Environment(\.accessibilityDifferentiateWithoutColor)`).
6. **Dark Mode:** là giao diện hạng nhất; mọi màn hình có bản tối từ token ngữ nghĩa (`Color(.systemBackground)`, `.primary`, Asset Catalog có Any/Dark), không đảo màu thủ công; kiểm tra ảnh và tương phản ở cả hai chế độ.
7. **Reduce Motion:** tôn trọng `accessibilityReduceMotion`/`@Environment(\.accessibilityReduceMotion)`: thay parallax và chuyển động lớn bằng crossfade; animation không chứa thông tin duy nhất; cũng xét Reduce Transparency và Bold Text.
8. **Bốn trạng thái:** Loading (skeleton/`redacted(reason: .placeholder)` bám layout, không spinner trơ), Empty (giải thích + CTA, ví dụ `ContentUnavailableView`), Error (thông điệp rõ + Thử lại), Populated (§5). Không để trạng thái thiếu.
9. **Haptic:** chỉ để xác nhận hành động hoặc báo lỗi: `UIImpactFeedbackGenerator`, `UISelectionFeedbackGenerator`, `UINotificationFeedbackGenerator` hoặc `.sensoryFeedback` (iOS 17+); không rung liên tục, không rung cho thao tác thường; hệ thống tự giảm khi người dùng tắt.
10. **Debounce ≥ 1000 ms** và disable ngay lần chạm đầu cho thao tác tốn kém (§3, §6).
11. **Safe area, bàn phím, hướng:** nội dung nằm trong safe area, không điều khiển dưới Dynamic Island/home indicator; bàn phím không che input; kiểm tra iPhone nhỏ nhất và lớn nhất được hỗ trợ, xoay ngang và iPad nếu là target.
12. **Zero-Slop:** không `Card` lồng `Card`, không ô icon đặt trên tiêu đề, không `Color.gray`/`#808080` trần, không gradient tím–xanh mặc định (neutral pha 3–5% tông chủ đạo), nhịp spacing 4–8 / 12–16 / 24–32 (không 16 cho mọi thứ; nguồn: DevKit essentials), không câu chào sáo rỗng "Welcome back"; mỗi màn hình một điểm neo thị giác. Dấu hiệu "bê từ web sang": thanh điều hướng tự chế, nút có hiệu ứng hover, back tự chế.
13. **Bằng chứng UI:** ảnh chụp từ **máy thật** (hoặc Simulator khi ghi rõ là Simulator) ở chế độ sáng và tối, cỡ chữ lớn, và một lượt VoiceOver cho màn hình mới. Chụp Simulator bằng `xcrun simctl io <UDID> screenshot <path>` và đổi giao diện bằng `xcrun simctl ui <UDID> appearance dark` (dùng UDID khi có nhiều máy ảo; nguồn: `skills/impeccable/reference/ios.md`). Thay đổi chỉ trong tooling/test/tài liệu không cần ảnh.

---

## 10. Bộ công cụ theo tình huống

> Tên dạng `skill:`, `agent:`, `council:` đều có thật trong kit. Các skill compose-recomp-audit và android-real-device-qa chỉ Android, không dùng cho iOS; tương đương iOS là Instruments, MetricKit, `xcodebuild test`. Agent `principal-code-reviewer` và `test-architect-seti` mô tả bằng ví dụ Kotlin/Android: dùng phương pháp của chúng (chọn lens theo rủi ro, bằng chứng tất định) với code Swift và lệnh iOS của profile này.

| Nhóm | Tình huống | Công cụ | Cho ra |
|---|---|---|---|
| UI/UX | Dựng màn hình/luồng mới hoặc làm lại giao diện rập khuôn | `skill:taste-mobile-app` | Quy trình 7 pha: dial Expression/Motion/Density (1–10), khoá `MOBILE-DESIGN.md` lấy token từ `DESIGN.md` trước dòng UI đầu tiên, 10 câu tự đánh giá cuối |
| UI/UX | Chọn bảng màu, font, style nút, micro-interaction, haptic | `skill:ui-ux-pro-max` | Quyết định thẩm mỹ theo stack SwiftUI, ưu tiên Accessibility và Touch trước |
| UI/UX | Thiết kế mới, critique, audit, polish màn native | `skill:impeccable` | Phê bình/audit/polish theo HIG (`skills/impeccable/reference/ios.md`), trích `DESIGN.md` |
| UI/UX | Kiểm giao diện trên máy thật: vùng chạm ≥ 44 pt, tràn khung, accessibility label, ảnh nghiệm thu thành công | `agent:real-device-ui-auditor` | Báo cáo cây accessibility, touch target, overflow, xác thực ảnh proof có tem thời gian |
| Hiệu năng | Main thread chậm/hang, jank, nóng máy/pin, OOM ảnh | `council:07-performance-anr` | Phán quyết hiệu năng theo ngân sách §7 (đo bằng Instruments/MetricKit) |
| Hiệu năng | Thêm hoặc audit log, metric, trace, Crashlytics | `skill:observability-instrumentation` | Điểm đo đủ chẩn đoán lỗi production, đã che PII |
| Chất lượng | Thêm/sửa logic testable, viết regression test | `skill:tdd-workflow` | Chu trình RED rồi GREEN an toàn, chọn bằng chứng nhỏ nhất |
| Chất lượng | Thiết kế/review test, chẩn flake, chọn bằng chứng tất định | `agent:test-architect-seti` | Kiến trúc test, findings P0–P3 và lệnh verify đích |
| Chất lượng | Chạy lint, test, QA gate | `skill:qc` | Tự nhận `xcodebuild`/`swift test` rồi chạy lint + test; số test thật |
| Chất lượng | Sắp tuyên bố xong/fixed/PASS, trước commit/PR, kiểm kết quả agent khác | `skill:verification-before-completion` | Bằng chứng chạy thật, RED/GREEN cùng oracle; thắng hiệu năng cần A/B |
| Chất lượng | Diff không tầm thường: crash, tệp, auth, navigation, lifecycle, nhiều file | `agent:principal-code-reviewer` | Phát hiện có bằng chứng, không tự sửa |
| Chất lượng | Review diff tự động trước commit/PR | `skill:open-code-review` | Nhận xét theo hunk |
| Phát hành/An toàn | Build Release, ký số, `CFBundleVersion` tăng đơn điệu, Privacy Manifest và khai báo quyền, tuân thủ App Store | `agent:mobile-release-auditor` | Kiểm gói phát hành, bí mật ký không lộ, version, store compliance |
| Phát hành/An toàn | Đổi URL scheme/universal link, tệp, quyền, `WKWebView`, auth, ATS/Keychain, trước release | `skill:security-checklist` | Danh mục kiểm bảo mật (bản viết cho Android: dùng mục tương đương ATS/Keychain của iOS) |

### Cách nghiệm thu (chạy trước khi gọi một task là xong)

1. **Hiệu năng** (task chạm danh sách, animation, khởi động, ảnh, nền, bộ nhớ): đo Instruments hoặc `XCTMetric` trên máy thật bản Release trước và sau (§7.2 mục 1), giao `council:07-performance-anr` phán theo §7.1; thêm điểm đo với `skill:observability-instrumentation` nếu thiếu dữ liệu chẩn đoán.
2. **Chất lượng** (mọi task đổi logic): `skill:tdd-workflow` cho RED→GREEN, `skill:qc` cho lint + test (SwiftLint/SwiftFormat, `N > 0` test, 0 failure), `agent:test-architect-seti` khi có flake hoặc cần chọn bằng chứng; diff lớn/rủi ro thì `agent:principal-code-reviewer` và `skill:open-code-review`; đổi bề mặt bảo mật thì `skill:security-checklist`; trước release `agent:mobile-release-auditor`; cuối cùng `skill:verification-before-completion` rồi cổng `post-fix-gate.py` (§8 mục 11).
3. **UI/UX** (task đổi giao diện): `skill:taste-mobile-app` + `skill:impeccable` trước và sau khi dựng; `skill:ui-ux-pro-max` khi chọn màu/font/haptic; `agent:real-device-ui-auditor` cho vùng chạm ≥ 44 pt, accessibility và ảnh thành công từ máy thật (sáng/tối, cỡ chữ lớn, VoiceOver); các bước kiểm cơ học của `skill:taste-mobile-app` (không `Card` lồng, không `Color.gray`, không gradient tím) phải sạch.
4. Không có thiết bị thật: ghi `UNTESTED` cho phần cần máy thật, không gọi là xong hoàn toàn (§6 mục 4).
