# Mobile Engineering Rules (Android + iOS)

> Luật chung cho mọi app mobile: Android (Kotlin / Jetpack Compose / Gradle nhiều module) ở §1–§16, iOS (Swift / SwiftUI) ở §17,
> quy tắc chung từ universal ở §18, rồi ba mục nâng chuẩn: hiệu năng §19, chất lượng §20, UI/UX & Accessibility §21.
> Luật Android: Tên class, module,
> ngưỡng số cụ thể của từng dự án nằm ở `.agents/local/rules/` của dự án đó, không ở đây.
> Mọi hành vi thư viện/SDK nêu dưới đây phải verify lại theo **đúng version dự án đang pin** (docs chính
> thức / source SDK đã cài) trước khi dùng làm căn cứ sửa code.

## 1. Solo-Dev & Chống Spam Thao Tác (Debounce/Disabled)
- Mọi nút kích hoạt thao tác quan trọng, xác nhận giao dịch hoặc gọi API bắt buộc phải:
  1. **Disable ngay lập tức** sau cú click đầu tiên.
  2. Hiển thị trạng thái Loading hoặc Spinner.
  3. Áp dụng debounce tối thiểu $1000\text{ms}$ để tránh double click hoặc spam job queue.

## 2. Bảo mật Mobile & Tuyệt đối Cấm lộ Bí mật
- Tuyệt đối không hardcode API key, auth token, mật khẩu kiểm thử hoặc cookie trần trong code.
- Cấu hình qua `.env` hoặc `local.properties` (đã vào `.gitignore`).
- Mọi `PendingIntent` bắt buộc phải khai báo cờ rõ ràng: `PendingIntent.FLAG_IMMUTABLE` (hoặc `FLAG_MUTABLE` nếu thực sự cần thiết kèm giải trình).
- Component chỉ `exported="true"` khi thật sự nhận Intent từ app khác; mọi Intent/URI/extra đi vào đều là input không tin cậy — validate trước khi dùng. Không truyền dữ liệu nhạy cảm qua Intent extras.
- Chia sẻ file ra ngoài bằng `FileProvider` (`content://` + `FLAG_GRANT_READ_URI_PERMISSION`), không bao giờ `file://`.
- XML parser (SAX/DOM/XmlPullParser) đọc file người dùng phải chặn DOCTYPE/external entity (XXE). Parser của Android (Expat/KXml) KHÁC Xerces của JVM: `setFeature`/`setProperty` có thể ném `SAXNotRecognizedException` — gọi best-effort trong `try` RIÊNG, không chung `try` với `parse()`, và chặn entity bằng `EntityResolver` trả input rỗng.

## 3. Quản trị Hiệu năng & UI Thread (Chống ANR)
- CẤM chạy tác vụ I/O, truy vấn Room/SQLite hoặc tính toán mã hóa trên UI Main Thread.
- Sử dụng Kotlin Coroutines với `Dispatchers.IO` hoặc `Dispatchers.Default`.
- Quản lý kích thước Bitmap, tái chế bộ nhớ tránh OutOfMemory (OOM) — chi tiết ở §11.
- "I/O" gồm cả những lời gọi trông vô hại: `ContentResolver.query/openInputStream/openFileDescriptor`, `DocumentFile.listFiles()`/`findFile()`, `SharedPreferences.commit()`, `File.exists()/length()` trên thư mục lớn, lần truy cập đầu tiên của SDK khởi tạo lười (Firebase, HTTP client, DB builder), IPC/Binder đồng bộ.
- Không `runBlocking` trên main; không `System.gc()`/`Runtime.gc()` ở bất kỳ đâu trên main (đặc biệt trong `dispose`/`onDestroy`) — đó là GC đồng bộ, gây ANR.
- Main thread không được chờ một lock mà thread nền đang giữ trong lúc làm I/O/parse (lock contention = ANR dù main "không làm I/O"). Tách lock theo tài nguyên, hoặc chuyển cả đoạn cần lock ra thread nền.
- Text cực lớn: không nhồi nhiều trăm KB vào MỘT `TextView`/`BasicTextField`/`Text` — chi phí line-break (minikin/`DynamicLayout`) tăng siêu tuyến tính theo độ dài dòng. Gate theo **số ký tự** (không chỉ số dòng) rồi chuyển sang hiển thị phân trang/ảo hoá (LazyColumn/RecyclerView theo chunk).
- Inject `CoroutineDispatcher` (không hardcode `Dispatchers.IO` trong class cần test) để test thay bằng `StandardTestDispatcher`. Bật `StrictMode` (thread + VM policy) ở debug build.
- Hàm `suspend` phải main-safe: tự `withContext(...)` bên trong, caller không phải nhớ.

## 4. Nghiệm thu & Chụp ảnh Minh chứng (Acceptance Gate)
- Mọi prompt, trước khi mở đầu bằng XONG, bắt buộc có ảnh chụp màn hình xác minh trạng thái **THÀNH CÔNG (PASS / Success State)** theo `rules/essentials.md` mục "Every prompt". Chụp bằng `python3 .agents/devkit/bin/proof-capture.py`: serial khai báo chỉ dùng khi `adb devices` báo `device` và không nằm trong denylist. Không có máy thì lệnh tự mở AVD (`proof.providers.<name>.avd`, hoặc máy ảo điện thoại duy nhất), đợi boot, rồi ghi `reports/proof-<yyyyMMdd-HHmmss>.png`. Không screencap địa chỉ chết, không đổi sang điện thoại đang cắm. PNG > 8 KB, mtime trong lượt này.
- Soát git diff trước khi báo cáo Tech Lead / Reviewer.
- Bằng chứng test là số đếm trong `<module>/build/test-results/**/TEST-*.xml` (unit) hoặc `<module>/build/outputs/androidTest-results/**/TEST-*.xml` (instrumented): `tests > 0`, `failures = 0`, `errors = 0`, nêu rõ `skipped`; XML phải mới hơn lần sửa cuối. `UP-TO-DATE`, `NO-SOURCE`, `No tests found` = **chưa chạy**, không phải PASS.
- JVM unit test xanh KHÔNG chứng minh hành vi phụ thuộc nền tảng (XML parser, Charset, `File.renameTo` qua FUSE/SAF, font/line-break, R8, Room trên SQLite thật): cần instrumented test hoặc chạy trên máy.

## 5. Gradle nhiều module, `build-logic` & Version Catalog
<!-- on-demand: §5 Gradle, build-logic, Version Catalog, testBuildType -->
- Cấu hình dùng chung (compileSdk/minSdk, Kotlin/JVM target, Compose, lint, test options) nằm trong **convention plugin** ở `build-logic/`; module chỉ áp plugin + khai báo phần riêng. Không copy khối `android { … }` vào từng module.
- Version và coordinate thư viện chỉ ở `gradle/libs.versions.toml`; không hardcode version trong `build.gradle.kts` của module.
- Sửa `build-logic/`, `libs.versions.toml`, `gradle.properties` hay root `build.gradle.kts` = đổi build của MỌI module → compile lại mọi module bị ảnh hưởng **kèm test source set**: `./gradlew :<m>:compileDebugKotlin :<m>:compileDebugUnitTestKotlin`. `assembleDebug`/`compileDebugKotlin` KHÔNG compile `src/test` — đổi chữ ký có thể vỡ test mà build vẫn xanh.
- Biến thể test theo `testBuildType`: module đặt `testBuildType = "release"` chỉ có `testReleaseUnitTest` — root `./gradlew testDebugUnitTest` bỏ qua module đó. Xác định task thật bằng `./gradlew :<m>:tasks --all | grep UnitTest` trước khi tin một lệnh test.
<!-- /on-demand -->
- Ranh giới module là hợp đồng: module thư viện dùng chung không phụ thuộc ngược lên `app`/feature; feature không import trực tiếp feature khác (đi qua navigation/interface ở core). Đổi ranh giới = hỏi trước.
- Giữ tương thích configuration cache: không đọc file/env/`System.getProperty` lúc configuration mà không qua `providers.*`.
- Nâng AGP/Kotlin/Compose compiler/KSP: nâng theo bảng tương thích chính thức, cùng một thay đổi, rồi build + test toàn bộ.

## 6. Jetpack Compose — Stability & Recomposition
- `@Immutable` = bất biến sâu thật sự; `@Stable` = mọi thay đổi quan sát được đều báo cho Compose. Không gắn annotation để "làm im" compiler report.
- File **stability configuration** (`stabilityConfigurationFiles`) chỉ liệt kê kiểu **thực tế bất biến trong cách dự án dùng**. Kiểu mutable (`java.util.Date`, `PointF`, `RectF`, `Rect`, mảng, collection mutable) nếu được khai stable thì **cấm mutate instance sau khi đã truyền vào composable** — Compose sẽ bỏ qua recomposition và UI hiển thị giá trị cũ. Luôn tạo instance mới khi giá trị đổi.
<!-- on-demand: §6 Compose: state owner, collection, LazyColumn key, compiler reports -->
- Collection trong UI state: `kotlinx.collections.immutable` (`ImmutableList`/`PersistentList`) hoặc wrapper `@Immutable`; không để `MutableList` trong state.
- Đọc state ở owner hẹp nhất; lambda/callback ổn định (method reference hoặc `remember`); `LazyColumn`/`LazyVerticalGrid` có `key` theo identity ổn định và `contentType`.
- Không cấp phát/sort/format nặng trong composition hoặc draw loop; tính trước ở state holder.
- Chứng minh vấn đề và kết quả bằng Compose compiler reports/metrics, Layout Inspector (recomposition counts) hoặc Macrobenchmark/Perfetto trên cùng kịch bản trước/sau. Compile xanh không chứng minh giảm recomposition.
- Thu thập Flow trong UI bằng `collectAsStateWithLifecycle()`, không `collectAsState()` cho luồng tốn tài nguyên.
<!-- /on-demand -->

## 7. Baseline Profiles & Startup
<!-- on-demand: §7 Baseline Profiles, Macrobenchmark, startup -->
- Sinh profile bằng module `androidx.baselineprofile` + Macrobenchmark trên build release-like (minified), cho các hành trình quan trọng thật (khởi động, mở màn hình chính, cuộn danh sách).
- Không sửa tay file `baseline-prof.txt` sinh ra; sinh lại sau thay đổi lớn về startup/navigation.
- Kiểm tra profile thực sự được đóng gói (artifact trong APK/AAB, `ProfileInstaller`) — "generate thành công" không phải bằng chứng runtime.
- Đo trước/sau cùng giao thức (cùng loại máy, `CompilationMode`, số vòng lặp). Ngưỡng cải thiện lấy từ baseline đo được, không lấy số mẫu.
- Selector trong generator/benchmark dựa trên semantics/resource-id/state, không `sleep` cố định hay toạ độ cứng.
<!-- /on-demand -->

## 8. R8 / ProGuard Keep Rules
- Release luôn `isMinifyEnabled = true` + `isShrinkResources = true`; **chạy thử bản release đã minify trên máy** trước khi phát hành — debug build không bao giờ lộ lỗi R8.
- Keep rule hẹp, có lý do: code gọi qua reflection, JNI (`native` method + class/field mà C/C++ truy cập), serialization (Kotlin Serialization/Gson/Moshi), enum `values()/valueOf()`, class nạp theo tên (`Class.forName`, ServiceLoader, `META-INF/services`). Cấm `-keep class ** { *; }`; `-dontwarn` phải kèm lý do.
<!-- on-demand: §8 R8 / ProGuard: repackage, consumerProguardFiles, mapping.txt -->
- R8 có thể **repackage** class về package khác: `SomeClass::class.java.getResourceAsStream("file.txt")` (đường dẫn TƯƠNG ĐỐI theo package của class) trả `null` ở release dù resource vẫn nằm trong APK. Dùng `classLoader.getResourceAsStream("full/path/file.txt")` (tuyệt đối, không `/` đầu) hoặc keep package của class đó.
- Module thư viện ship keep rule qua `consumerProguardFiles`, không bắt app đoán.
- Lưu `mapping.txt` mỗi bản release và upload cho Crashlytics/Play để deobfuscate stack trace.
- Oracle cho lỗi chỉ xảy ra khi minify: test trên bản release, hoặc test JVM mô phỏng việc đổi tên/dời package (ví dụ remap class bằng ASM) — không kết luận từ debug build.
<!-- /on-demand -->

## 9. Storage Access Framework & `content://` URI
<!-- on-demand: §9 SAF, content:// URI, OpenableColumns, persistable permission -->
- URI từ SAF/`ACTION_VIEW`/`ACTION_SEND` là `content://`: **không suy ra file path** (`uri.path`, `_data`, `/storage/emulated/0/...`). Đọc/ghi bằng `ContentResolver.openInputStream/openOutputStream/openFileDescriptor` + `use {}`.
- Tên hiển thị/kích thước lấy từ `OpenableColumns.DISPLAY_NAME`/`SIZE` (có thể null/0 — xử lý); không lấy segment cuối của URI làm tên file.
- `takePersistableUriPermission` chỉ áp dụng cho grant từ `ACTION_OPEN_DOCUMENT`/`ACTION_OPEN_DOCUMENT_TREE`/`CREATE_DOCUMENT` có flag persistable; số grant lưu được có giới hạn — giải phóng grant không còn dùng.
- `SecurityException` (grant bị thu hồi), `FileNotFoundException` (file đã xoá/di chuyển), provider trả `null` là tình huống **dự kiến** — hiển thị UI phù hợp, không coi là crash/không đẩy lên Crashlytics như lỗi.
- Mode của `openFileDescriptor`/`openOutputStream`: `"w"` có thể KHÔNG truncate trên một số provider — dùng `"wt"` khi ghi đè toàn bộ; ghi an toàn = ghi file tạm rồi thay thế, không để file hỏng một nửa khi lỗi/huỷ.
- Mọi truy vấn provider/`DocumentFile` chạy ngoài main thread (§3). Quét cây thư mục lớn: giới hạn độ sâu/đồng thời, huỷ được, không BFS song song không giới hạn.
- Đọc `Intent` extra theo API mới (`getParcelableExtra(key, Uri::class.java)` từ API 33, `IntentCompat` cho bản cũ); kiểm tra MIME/kích thước trước khi mở.
- Không log/analytics URI, đường dẫn hay tên file thật (§12).
<!-- /on-demand -->

## 10. Hilt / Dependency Injection
<!-- on-demand: §10 Hilt: scope, ViewModel, Worker, test, binding dùng chung -->
- Ưu tiên constructor injection (`@Inject constructor`) + `@Binds` cho interface; `@Provides` chỉ cho kiểu không sở hữu.
- Scope đúng vòng đời: `@Singleton` cho client/DB/repository dùng chung; không `@Singleton` cho state theo người dùng/tài liệu, không giữ object nặng theo tài liệu (renderer, parser session) ở scope rộng.
- Không inject/giữ `Activity`/`Fragment`/`View` trong object sống lâu hơn nó; cần Context ở tầng dưới thì `@ApplicationContext`.
- ViewModel: `@HiltViewModel` + `SavedStateHandle` cho tham số điều hướng/khôi phục process death. Worker: `@HiltWorker` + `HiltWorkerFactory`.
- Test: `@HiltAndroidTest` + `@TestInstallIn`/`@UninstallModules` thay module; không sửa graph production cho test.
- Đổi binding dùng chung = đổi hành vi mọi consumer → liệt kê consumer (graph/grep, gồm `src/test`, `src/androidTest`) trước khi sửa.
<!-- /on-demand -->

## 11. Room — Schema & Migration
- `exportSchema = true`, thư mục schema được commit; mọi lần tăng `version` phải có `Migration`/`AutoMigration` **và** test bằng `MigrationTestHelper` (tạo DB ở version N-1 với dữ liệu thật, migrate, kiểm tra dữ liệu còn nguyên).
- Cấm `fallbackToDestructiveMigration()` ở release (mất dữ liệu người dùng); nếu buộc phải dùng thì chỉ `fallbackToDestructiveMigrationFrom(...)` các version cụ thể, có duyệt.
<!-- on-demand: §11 Room: REPLACE + CASCADE, transaction, Flow, index, Paging -->
- **Bẫy `@Insert(onConflict = REPLACE)` + `ForeignKey(onDelete = CASCADE)`**: REPLACE thực chất là DELETE + INSERT → xoá sạch bản ghi con qua CASCADE. Cập nhật bản ghi cha có con thì dùng `@Upsert`/`@Update` (update tại chỗ). Có test: upsert cha → con còn nguyên.
- Nhiều thao tác phụ thuộc nhau: `@Transaction` / `withTransaction`; transaction ngắn, không I/O mạng bên trong.
- Truy vấn trả `Flow` hoặc là `suspend`; không `allowMainThreadQueries()` ngoài test.
- Index cho cột lọc/sắp xếp thường xuyên; danh sách lớn phân trang (Paging 3), không load toàn bộ bảng lên UI.
<!-- /on-demand -->

## 12. Analytics, Crashlytics & PII
- Không gửi PII vào analytics/Crashlytics (event param, custom key, log, message của exception): tên file, đường dẫn, URI, nội dung tài liệu, email, token, ID thiết bị thô. ID cần thiết thì hash; đường dẫn → chỉ gửi loại/nhóm (extension đã chuẩn hoá, bucket kích thước). Tính năng chạy trên lựa chọn của người dùng (dịch, sao chép, tìm, chia sẻ phần bôi đen): chỉ gửi kích thước, không bao giờ gửi nội dung hay độ dài chính xác (lược đồ bucket: mục §12 bên dưới).
<!-- on-demand: §12 Analytics, Crashlytics: log, cardinality, consent, non-fatal; selection_action, size_bucket -->
- **Tính năng chạy trên lựa chọn của người dùng** (selected text; luật không gửi nội dung ở dòng PII phía trên): event hằng số `selection_action`; param `feature` (hằng số: `translate`, `copy`, `search`, `share`), `size_bucket` và `doc_type` (extension đã chuẩn hoá). `size_bucket` (số words hoặc số ký tự của vùng chọn) chọn theo **hệ chữ** của vùng chọn, không theo việc có dấu cách hay không: hệ chữ ngăn từ bằng dấu cách (Latin, Kirin, Hy Lạp, Ả Rập, Do Thái, Devanagari, Hàn) đếm từ — `w1`, `w2`, `w3_5`, `w6_20`, `w21_100`, `w101_plus`, và một từ Latin dài vẫn là `w1`; hệ chữ viết liền không ngăn từ (Hán, Hiragana, Katakana, Thái, Lào, Khmer, Myanmar) đếm ký tự — `c1_2`, `c3_10`, `c11_100`, `c101_plus`. Vùng chọn trộn hai nhóm: theo nhóm chiếm nhiều ký tự chữ hơn, bằng nhau thì đếm ký tự.
- Đọc phân phối `size_bucket` sau mỗi bản phát hành: tính năng mà gần như mọi request rơi vào `w1`/`w2` là tín hiệu lỗi chọn vùng (OfficeReader 07/10: "Dịch" trong PDF nhận 1–2 từ vì handle cuối của từ ngắn thua handle đầu; không test nào thấy, bucket thấy ngay). Có kiểm thử hàm gom bucket ở các ranh giới (đếm từ: 1, 2, 3, 5, 6, 20, 21, 100, 101; đếm ký tự: 1, 2, 3, 10, 11, 100, 101), cả đầu vào Latin, Hán/Thái và trộn, và kiểm thử param của event không chứa văn bản thô.
- Tên event và giá trị param là **hằng số ít cardinality**: không ghép tên event động, không dùng **chuỗi UI đã dịch** hay message exception làm giá trị (một lỗi sẽ vỡ thành hàng chục giá trị theo ngôn ngữ). Tách "message cho người dùng" khỏi "error key cho analytics" ngay tại nguồn.
- Tôn trọng giới hạn của nền tảng analytics (độ dài tên event/param, số param, số user property) — verify theo docs hiện hành, có test cho schema.
- Consent trước khi thu thập (Consent Mode / UMP); trạng thái `analytics_storage` không suy ra từ quyền quảng cáo.
- Crashlytics non-fatal: lọc `CancellationException` (coroutine huỷ hợp lệ) và lỗi dự kiến (mất mạng, file bị xoá, quyền bị thu hồi, người dùng huỷ) tại **helper trung tâm**, không rải ở call site. Lọc theo kiểu exception, không theo prefix chuỗi của lớp wrapper.
- Kiểm chứng event bằng DebugView/`adb shell setprop debug.firebase.analytics.app <pkg>` trên build có cấu hình giống release; dashboard trễ/không thấy ≠ event không gửi.
<!-- /on-demand -->

## 13. Bitmap, PDF & File Lớn — Bộ nhớ
<!-- on-demand: §13 Bitmap, PdfRenderer, file lớn, OOM, tài nguyên native -->
- Giải mã ảnh theo kích thước hiển thị: `BitmapFactory.Options.inSampleSize` (đọc `inJustDecodeBounds` trước) hoặc `ImageDecoder.setTargetSize`; thư viện ảnh (Coil/Glide) phải có `size(...)`. Không decode ảnh gốc 12–50 MP vào `ARGB_8888`.
- Trang PDF: render theo viewport/zoom, tile cho zoom cao; bitmap cache bị chặn (`LruCache` tính theo byte, dựa `ActivityManager.memoryClass`); giải phóng khi trang ra khỏi màn hình.
- `android.graphics.pdf.PdfRenderer`: chỉ MỘT page mở tại một thời điểm (đóng page trước khi mở page khác), không thread-safe → tuần tự hoá mọi truy cập; renderer **sở hữu** `ParcelFileDescriptor` truyền vào và tự đóng nó — đừng đóng PFD lần hai hay giữ PFD riêng. Verify quyền sở hữu tài nguyên theo source SDK đã resolve trước khi thiết kế wrapper cleanup.
- File văn phòng/XML lớn: parse streaming (SAX/StAX/event API), không DOM toàn bộ; đặt ngân sách bộ nhớ và từ chối/hiển thị lỗi thân thiện khi vượt, thay vì để OOM.
- `OutOfMemoryError` là `Error`, **không** bị `catch (e: Exception)` bắt; vùng cần phục hồi phải bắt riêng và giải phóng tài nguyên; `android:largeHeap` không phải là cách sửa.
- Tài nguyên native/stream/cursor/renderer đóng ở MỌI nhánh (thành công, lỗi, huỷ coroutine, dispose muộn sau khi màn hình đã đóng); callback đến sau dispose phải no-op an toàn.
- Không giữ tham chiếu tĩnh tới `Activity`/`Context`/`View` (kể cả trong singleton của thư viện render) — rò rỉ cả cây view và bitmap.
- Đo bằng dữ liệu thật: fixture lớn/hỏng/mã hoá, Memory Profiler/LeakCanary/heap dump; không đẩy HPROF lên dịch vụ ngoài khi chưa được duyệt.
<!-- /on-demand -->

## 14. Vòng đời, Process Death & Công việc nền
- State cần sống qua process death đi vào `SavedStateHandle`/`rememberSaveable`; kiểm tra bằng "Don't keep activities" hoặc `adb shell am kill`.
- Coroutine gắn scope có vòng đời (`viewModelScope`, `lifecycleScope` + `repeatOnLifecycle`); cấm `GlobalScope`; khi bắt `Exception` trong coroutine phải ném lại `CancellationException`.
- Việc nền dài/định kỳ: `WorkManager` (constraints, backoff); `BroadcastReceiver.onReceive` chỉ việc nhanh hoặc `goAsync()` rồi `finish()` trong `finally`; Foreground Service khai báo `foregroundServiceType` đúng (Android 14+).
- App Widget (Glance/RemoteViews): PendingIntent/layout cũ có thể sống qua lần cập nhật app — xử lý `ACTION_MY_PACKAGE_REPLACED` để render lại mọi widget.

## 15. Accessibility & UI Compose
- Touch target ≥ 48×48dp (`Modifier.minimumInteractiveComponentSize()`); text dùng `sp` và chịu được font scale 200%; tương phản ≥ 4.5:1.
- Icon có ý nghĩa có `contentDescription` (chuỗi resource); icon trang trí `contentDescription = null`; icon chỉ hướng dùng `Icons.AutoMirrored.*` và layout dùng start/end cho RTL.
- Màu/khoảng cách/typography lấy từ theme/design-system (`MaterialTheme.colorScheme`, token của dự án), không `Color(0x…)`/số dp rải rác; chuỗi hiển thị qua `stringResource`.
- Zero-Slop (chống giao diện phèn): cấm `Card { Card { … } }` lồng nhau (dùng whitespace + divider mảnh); cấm icon tile (ô vuông bo góc nhạt chứa icon) đặt trên heading; cấm `Color.Gray` / `#808080` trần và gradient tím-xanh mặc định (neutral pha 3–5% tông chủ đạo, ví dụ `MaterialTheme.colorScheme.onSurfaceVariant`); spacing 4–8dp trong nhóm / 12–16dp nội dung / 24–32dp giữa section, không 16dp cho mọi thứ. Dữ liệu chi tiết: skill `ui-ux-pro-max` (stack `jetpack-compose`, nhóm `VisualSlop`).
- **Edge-to-edge & Insets**: Bắt buộc `enableEdgeToEdge()` (targetSdk 35 trên Android 15). Nội dung dùng `WindowInsets` / `Modifier.safeDrawingPadding()`. Form/CTA ở đáy phải có `Modifier.imePadding()` để không bị bàn phím che.
- **Mandatory 4 trạng thái**: Mọi màn hình/luồng phải có 4 trạng thái: Loading (skeleton bám layout, không spinner), Empty (kèm CTA), Error (kèm Thử lại), Populated. Cấm câu chào sáo rỗng "Welcome back 👋". Quy trình chuẩn: dùng skill `taste-mobile-app` kết hợp `impeccable` (`skills/impeccable/reference/android.md`) để rà soát nhịp điệu bố cục, phân cấp thị giác và chống slop M3.
- **Hit area và kích thước nhìn:** Icon nhìn thấy có thể 24–32dp; hit area bắt buộc ≥ 48×48dp. Hai vùng tương tác cách nhau ≥ 8dp.
- **Thumb zone:** Primary CTA (Ký, Xác nhận, Tiếp tục) nằm trong 40% nửa dưới màn hình.
- **Frame budget 16.6ms:** Cấm `Column` + `verticalScroll` cho danh sách động. Dùng `LazyColumn`/`LazyRow` với stable key. Tính toán nặng trong Composable đi qua `remember` hoặc `derivedStateOf`.
- **Kiểm chứng bất biến chồng lấn/Insets:** Khi đổi layout/overlay/inset/cử chỉ có nhiều vùng chạm/chrome đáy-cạnh ⇒ thêm/cập nhật test bảng cấu hình bằng helper `compose-overlap-invariants` + ma trận trạng thái (hướng × kiểu điều hướng cử chỉ/3 nút × inset status/nav/cutout × font scale × RTL và các trạng thái riêng của màn hình (ví dụ thanh công cụ ẩn/hiện, trình phát nổi), mỗi ô một dòng kết quả). Không dùng snapshot toạ độ tuyệt đối trừ khi thật sự cần.

## 16. Kiến trúc tầng & Kiểm thử (nguồn: android/architecture-samples)
- Tầng UI (Screen + ViewModel) → Repository (interface) → data source (Room cục bộ + network). Tầng domain chỉ thêm khi logic được dùng lại ở nhiều nơi (nhánh `main` của sample không có).
- ViewModel giữ `MutableStateFlow` ở dạng private và lộ một `StateFlow<UiState>` qua `stateIn(viewModelScope, <chính sách chia sẻ, ví dụ SharingStarted.WhileSubscribed(timeout)>, initial)` (sample dùng helper riêng `WhileUiSubscribed`). `UiState` là `data class` bất biến; UI gửi sự kiện bằng hàm của ViewModel; thông báo một lần là state và được xoá bằng hàm "đã hiển thị".
<!-- on-demand: §16 Kiến trúc tầng: StateFlow, Repository, fake, package theo feature; extract/trích (wiring_pin) -->
- Lỗi của luồng dữ liệu thành state (`.catch` → `Async.Error`/`userMessage`), không để lọt ra khỏi `viewModelScope`.
- Repository: đọc trả `Flow` từ Room (nguồn sự thật), ghi local rồi mới đồng bộ network; ánh xạ entity/DTO ↔ model ngoài bằng hàm riêng, không lộ entity Room lên UI. Dispatcher và application scope inject bằng qualifier (`@IoDispatcher`, `@DefaultDispatcher`, `@ApplicationScope`).
- Test: fake viết tay trong module dùng chung (`FakeRepository`/`FakeDao`/`FakeNetworkDataSource`) ưu tiên hơn mock repository; `MainCoroutineRule` set/reset `Dispatchers.Main` bằng test dispatcher; mỗi `@Module` có `@TestInstallIn(replaces = …)` đối ứng; test Room dùng DB in-memory (§10, §11).
- Package theo feature (`tasks/`, `taskdetail/`, …), mỗi feature có Screen + ViewModel và test phản chiếu cấu trúc đó. Chi tiết: `skills/deep-module-design/references/architecture-android.md`.
- Trích logic ra khỏi một `View` vào `internal object` mới: test của object không chứng minh `View` còn gọi nó (revert call site của `View`, test object vẫn xanh; vacuity gate gọi test đó là rỗng). Sau khi trích, chạy `python3 .agents/devkit/scripts/linters/wiring_pin.py scan` (trong DevKit: `scripts/linters/`): nó tìm `internal object` mới (cùng file hoặc nằm cạnh một file `View`) mà không test nào nhắc tới cả `View` lẫn object đó (test chỉ nhắc `View`, hay pin của object khác trong cùng `View`, không tính), và in sẵn một pin test dạng source-text cho từng cặp (View, object): View vẫn gọi `Object.`, không còn các dòng nhánh cũ. Lưu pin vào đường dẫn nó gợi ý, chạy đúng lệnh `wiring_pin.py verify <pin.kt> --root <module>` nó in (từ gốc repo) thấy xanh, rồi revert call site thử: phải đỏ. `UNWIRED` = không View nào gọi object (nhắc trong comment, KDoc hay chuỗi ký tự không tính). `UNPINNABLE` = không dòng bị xoá nào đủ làm mốc: tự viết assertion "code cũ không còn" bằng tay, vì pin chỉ có nửa "còn gọi" thì không chứng minh gì. `verify` thoát 2 với pin chứa `view.contains(` mà nó không đọc được (pin bị formatter bẻ dòng thì vẫn đọc được). Pin chỉ thấy chuỗi ký tự, không thấy call nằm trong nhánh không bao giờ chạy: test hành vi thật vẫn cần khi có thể dựng được `View`.
<!-- /on-demand -->


## 17. iOS — Swift / SwiftUI / Swift Concurrency / XCTest (từ profile ios)
Quy chuẩn kỹ thuật bắt buộc dành cho AI Agent khi phát triển, tối ưu và sửa lỗi ứng dụng iOS (Swift 6, SwiftUI, Swift Concurrency, XCTest).

---

### 17.1. Quản Trị Bộ Nhớ & Triệt Tiêu Vòng Lặp Tham Chiếu ARC (Zero Retain Cycles)

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

### 17.2. Quản Trị Luồng & Swift Concurrency (@MainActor & Data Race Safety)

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

### 17.3. Tối Ưu Hóa Hiệu Năng SwiftUI & Tránh Redraw Thừa (Frame Budget 120 FPS)

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

### 17.4. Kỷ Luật Kiểm Thử XCTest & Đo Đạc Rò Rỉ Bộ Nhớ

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

### 17.5. SwiftUI UI & Apple HIG (Anti-Slop)
- **Safe Area & Insets**: Nút CTA dính đáy dùng `.safeAreaInset(edge: .bottom)` để đẩy nội dung; tuyệt đối không dùng `.ignoresSafeArea()` tràn lan gây lẹm chữ vào tai thỏ/Dynamic Island.
- **Bàn phím & Navigation**: Bàn phím không được che khuất input (SwiftUI tự xử lý nếu dùng đúng form/scroll view). Sheet nên dùng `.presentationDetents([.medium, .large])` (iOS 16+) để người dùng dễ vuốt đóng.
- **Mandatory 4 trạng thái**: Mọi màn hình phải có đủ 4 trạng thái thiết kế: Loading (dùng skeleton/redacted thay vì spinner), Empty (kèm CTA), Error (kèm Thử lại), Populated.
- **Zero-Slop & Vùng chạm**: Hit area $\ge 44\times 44\text{pt}$ (xem lại §17.3). Cấm thiết kế rập khuôn: Card lồng Card, dùng `Color.gray` trần, gradient tím-indigo mặc định, và câu chào sáo rỗng "Welcome back 👋".
- Quy trình chuẩn: Sử dụng skill `taste-mobile-app` kết hợp `impeccable` (`skills/impeccable/reference/ios.md`) để định hướng thẩm mỹ Apple HIG, phân cấp typography và kiểm tra UI/UX chống slop.


## 18. Quy tắc chung (từ universal)
### 18.1. Solo-Dev & Git Security (BẮT BUỘC)
- Tự commit/push khi xong và danh sách việc phải hỏi người dùng trước: DevKit essentials trong `AGENTS.md`, mục Git và Working style.
- Tuyệt đối KHÔNG commit bí mật / credentials: `.env`, keys, token, mật khẩu, cookies.
- Mọi tài khoản hoặc cấu hình nhạy cảm phải nạp qua biến môi trường hoặc file cấu hình cục bộ (`.gitignore`).
- Soát kỹ `git diff` trước khi báo cáo hoàn thành.

### 18.2. Paired Executable Oracle & Zero-Defect TDD
- Khi sửa lỗi (bug-fixing) hoặc phát triển tính năng mới:
  1. **RED:** Viết bài test tái hiện lỗi trước, chạy test xác nhận THẤT BẠI.
  2. **GREEN:** Sửa code tối giản để bài test chuyển sang THÀNH CÔNG.
  3. Cấm mock lỏng lẻo (`assert True`), cấm xóa hoặc đổi assertion của test để pass gian lận.

### 18.3. Chống Spam & Quản trị Bất đồng bộ (Debounce / Rate Limit)
- Các thao tác gọi API tốn kém, xác nhận giao dịch hoặc kích hoạt workflow bắt buộc có Debounce / Loading state.
- Không spam request liên tục làm quá tải backend, job queue hoặc làm nghẽn dịch vụ thông báo.

### 18.4. Bằng chứng Nghiệm thu (Acceptance Gate)
- Tính năng chỉ được xem là hoàn tất khi có bằng chứng xác minh trạng thái **THÀNH CÔNG (PASS / Success State)**:
  - Thông báo thành công (toast/modal), trạng thái nghiệp vụ hoàn tất.
  - Báo cáo kiểm thử hoặc screenshot kết quả thực tế.

### 18.5. Clean Architecture & The Dependency Rule
- **Tách biệt phân tầng (Separation of Concerns):**
  - `Domain`: Chứa Entities, Value Objects và Use Cases thuần túy, độc lập tuyệt đối với UI và CSDL.
  - `Adapters`: Controllers, Presenters, Gateways chuyển đổi dữ liệu.
  - `Frameworks & Drivers`: UI, Web/Desktop runtime, Database, Third-party SDKs.
- **The Dependency Rule:** Mọi phụ thuộc mã nguồn chỉ được phép trỏ từ ngoài vào trong. Lớp Domain cốt lõi không bao giờ biết đến sự tồn tại của UI, database hay framework bên ngoài.

## 19. Hiệu năng — Ngân sách đo được (Android + iOS)

> Mọi con số dưới đây có MỘT trong hai nhãn: **nguồn nền tảng** (tên tài liệu) hoặc **"mặc định đề xuất của dự án, cần đo trên máy thật"**. Con số nguồn nền tảng vẫn phải kiểm lại theo tài liệu hiện hành trước khi dùng làm cổng chặn (ngưỡng Play/Apple có thể đổi). Không có số đo trên **máy thật** (cùng model, bản build release-like, sạc/nhiệt ổn định) thì không được tuyên bố "đã tối ưu"; emulator/simulator chỉ dùng để dev nhanh, không làm bằng chứng hiệu năng.

### 19.1 Bảng ngân sách

| Chỉ số | Ngân sách | Nguồn / trạng thái | Cách đo |
|---|---|---|---|
| Khởi động nguội Android | Dưới 5 s (từ 5 s trở lên bị Android vitals xếp "quá chậm") | Android vitals, tài liệu "App startup time". Mục tiêu nội bộ chặt hơn (do dự án đặt từ baseline đo được): mặc định đề xuất của dự án, cần đo trên máy thật | Macrobenchmark `StartupTimingMetric` (`timeToInitialDisplayMs`, `timeToFullDisplayMs`); `adb shell am start -W` |
| Khởi động ấm Android | Dưới 2 s | Android vitals, tài liệu "App startup time" | Macrobenchmark `StartupMode.WARM` |
| Khởi động nóng Android | Dưới 1,5 s | Android vitals, tài liệu "App startup time" | Macrobenchmark `StartupMode.HOT` |
| Khởi động iOS đến frame đầu | 400 ms | mặc định đề xuất của dự án, cần đo trên máy thật | Instruments mẫu "App Launch"; `XCTApplicationLaunchMetric`; MetricKit `MXAppLaunchMetric` |
| Khung hình 60 Hz | 16,6 ms/khung (1000 ms ÷ 60) | Phép tính từ tần số quét; Android coi khung vượt 16 ms là "slow frame" (tài liệu "Slow rendering") | `FrameTimingMetric` (`frameDurationCpuMs`, `frameOverrunMs`); Perfetto; `adb shell dumpsys gfxinfo <pkg> framestats` |
| Khung hình 120 Hz | 8,3 ms/khung (1000 ms ÷ 120) | Phép tính từ tần số quét | Như trên, trên máy có màn 120 Hz; iOS: Instruments "Animation Hitches" trên máy ProMotion |
| Khung đóng băng (frozen) Android | Không có khung nào trên 700 ms | Android vitals, tài liệu "Slow rendering" | Perfetto, `FrameTimingMetric` |
| Tỷ lệ jank | ≤ 1% khung chậm trong kịch bản cuộn chuẩn | mặc định đề xuất của dự án, cần đo trên máy thật (lấy baseline đo được rồi siết dần) | Macrobenchmark cuộn danh sách (≥ 10 vòng) |
| iOS hitch | Hitch time ratio < 5 ms mỗi giây là "tốt" | Apple WWDC "Eliminate animation hitches" / Xcode Organizer; kiểm lại tài liệu hiện hành | Instruments "Animation Hitches"; `XCTHitchMetric`; MetricKit `MXAnimationMetric` |
| iOS main thread hang | Main thread không bị chặn quá 250 ms | Apple, tài liệu "Understand hangs in your app" | Instruments "Hangs"; MetricKit `MXHangDiagnostic`; Xcode Organizer |
| ANR Android — input | 5 s | Android developers, "ANRs" | `anr-logcat-triage.sh` (scripts/qa), `/data/anr/traces`, Play Console ANR |
| ANR Android — broadcast | 10 s (broadcast foreground) | Android developers, "ANRs" | như trên |
| Tỷ lệ ANR / crash | Dưới ngưỡng "bad behavior" của Google Play (ANR người dùng cảm nhận được 0,47%, crash 1,09%) | Android vitals; kiểm lại con số hiện hành ở Play Console. Mục tiêu nội bộ chặt hơn: mặc định đề xuất của dự án, cần đo trên máy thật | Play Console Android vitals, Crashlytics, MetricKit/Organizer |
| Bộ nhớ / rò rỉ | Sau 10 vòng vào–ra một màn hình, heap không tăng đều (không có instance Activity/ViewModel/UIViewController cũ còn sống) | mặc định đề xuất của dự án, cần đo trên máy thật | LeakCanary, Memory Profiler/heap dump; iOS: Instruments "Leaks" + "Allocations", `leaks -atExit` (§17), `XCTMemoryMetric` |
| Bitmap OOM | Giải mã theo kích thước hiển thị (§13); không có `OutOfMemoryError` trên fixture ảnh/PDF lớn | Android developers, "Loading large bitmaps efficiently" | Heap dump + fixture lớn/hỏng |
| Binder transaction | Tổng dữ liệu một giao dịch Binder dưới 1 MB (bộ đệm chia sẻ cả tiến trình) | Android developers, `TransactionTooLargeException` | Không đẩy Bitmap/danh sách lớn qua Intent/Bundle/`savedInstanceState`; truyền URI/ID |
| Pin / wakelock | Không giữ wakelock thủ công ngoài thời gian cần thiết; việc nền qua WorkManager; tuân thủ Doze/App Standby | Android developers, "Doze and App Standby", "Excessive wake locks" (Android vitals) | `adb shell dumpsys batterystats`, Battery Historian, `adb shell dumpsys deviceidle force-idle`; iOS: Instruments "Energy Log", MetricKit `MXCPUMetric`/`MXDiskIOMetric` |
| Mạng — timeout | Connect ≤ 10 s, read ≤ 15 s, retry chỉ cho thao tác idempotent, có backoff + jitter | Luật DevKit essentials (`AGENTS.md`, mục Engineering musts) | Test với mạng chậm/ngắt (Network Link Conditioner, `adb shell cmd connectivity`/proxy giả lập) |

### 19.2 Luật bắt buộc đi kèm ngân sách
- **Đo trước, sửa sau, đo lại**: mọi PR "tối ưu" nêu số trước/sau, cùng máy, cùng giao thức (`CompilationMode`, số vòng, trạng thái nhiệt), có đường dẫn trace/báo cáo. Không có số = không có tuyên bố.
- **Máy thật**: bằng chứng hiệu năng phải từ thiết bị thật (Android: ít nhất một máy tầm thấp và một máy phổ thông của tệp người dùng; iOS: một máy ProMotion nếu app hỗ trợ). Số trên emulator/simulator chỉ để so sánh tương đối trong dev.
- **Macrobenchmark + Perfetto (Android)**: kịch bản khởi động nguội/ấm, cuộn danh sách chính và một hành trình quan trọng chạy trên build release-like (minified, `debuggable=false`, profileable); lưu trace Perfetto của lần chạy chậm nhất. Tối thiểu 10 vòng lặp (mặc định đề xuất của dự án, cần đo trên máy thật) và so median + p90.
- **Instruments + MetricKit (iOS)**: Time Profiler, Hangs, Animation Hitches, Allocations/Leaks trên máy thật, build Release; đăng ký `MXMetricManager` để nhận `MXMetricPayload`/`MXDiagnosticPayload` ở production.
- **Baseline Profile + R8 (Android)**: xem §7 và §8. Sau khi có profile phải đo lại khởi động và cuộn trên bản release; Google nêu baseline profile cải thiện tốc độ chạy mã từ lần đầu (Android developers, "Baseline Profiles"), mức cải thiện thật của app lấy từ số đo, không lấy từ tài liệu.
- **StrictMode (Android)**: debug build bật `ThreadPolicy` (disk read/write, network) và `VmPolicy` (leaked closable/registration objects, cleartext network) với `penaltyLog()`; CI/instrumented test coi vi phạm là lỗi. Xem §3.
- **Main thread (Android + iOS)**: I/O, mạng, parse nặng, mã hoá, truy vấn DB không chạy trên main thread (Android §3; iOS §17.2 và §17.3). Tải khởi động chỉ làm việc cần cho frame đầu; khởi tạo SDK còn lại dời sau frame đầu (App Startup/`Dispatchers.Default`; iOS: sau `didFinishLaunching`).
- **Khung hình**: mỗi màn hình có danh sách/animation phải có kết quả đo khung hình ở 60 Hz và, nếu máy hỗ trợ, ở 120 Hz; không đổi tần số quét chỉ để qua cổng.
- **Hồi quy hiệu năng là hồi quy chức năng**: số đo vượt ngưỡng đã chốt trong baseline của dự án chặn merge giống test đỏ (xem §20).
- Công cụ sẵn có trong kit: `scripts/qa/adb-fps-measure.sh` (đo khung hình qua `gfxinfo`), `scripts/qa/anr-logcat-triage.sh`, `scripts/qa/tombstone-triage.sh`, `scripts/qa/dump-view-hierarchy.sh`; council `07-performance-anr.md`.

## 20. Chất lượng — Cổng kiểm chứng (Android + iOS)

> Con số ở mục này mang nhãn **nguồn** hoặc **"mặc định đề xuất của dự án, cần đo trên máy thật"** (hoặc "cần đo trên dữ liệu của dự án" khi không liên quan thiết bị).

### 20.1 Paired oracle RED→GREEN
- Mỗi bug fix có đúng một test ở ranh giới lỗi thật: chạy thấy **RED** trước khi sửa code production, sửa tối giản, chạy lại đúng test đó thấy **GREEN**; giữ lệnh và exit code. Compile xanh chỉ chứng minh compile (§4).
- Android: JVM test (`./gradlew :<m>:testDebugUnitTest --tests <Class>`), hành vi phụ thuộc nền tảng cần instrumented test (§4). iOS: `xcodebuild test -only-testing:<Target>/<Class>/<test>` (§17.4).
- Cấm xoá/nới assertion, `assert True`, mock lỏng để ép xanh (§18). Test đã sửa cần agent khác duyệt theo luật DevKit.
- Với logic trích ra object mới: pin test nối View ↔ object (§16, `wiring_pin.py`).

### 20.2 Ma trận hồi quy
- `regression_matrix.json` của profile chỉ giữ mục có lệnh test **thật, chạy được** trong repo; mục không có test thật không được thêm "cho đủ". Dự án sinh ma trận từ test runner thật của mình (Gradle `testDebugUnitTest`, `assembleRelease`; iOS: scheme XCTest của dự án).
- File chia sẻ/watch_files đổi thì chạy đúng test của component tương ứng (TIA). Thay đổi build chung (`build-logic/`, `libs.versions.toml`) chạy test cả test source set (§5).

### 20.3 Lint và phân tích tĩnh
- Android: Android Lint (`./gradlew lintDebug`), ktlint (`ktlintCheck`), detekt (`detekt`) chạy ở CI, vi phạm mới = đỏ; baseline file chỉ để ghi nợ cũ, không thêm vào baseline để qua cổng.
- iOS: SwiftLint (`swiftlint --strict`), bật Strict Concurrency Checking (`-strict-concurrency=complete`, §17.2) và coi warning concurrency mới là lỗi.
- Cổng chung: `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --scoped --brief` exit 0.

### 20.4 Kim tự tháp test
- Nhiều unit test nhanh ở đáy (JVM/XCTest không UI), ít hơn integration (Room in-memory, Hilt test, `URLProtocol` giả), ít nhất là UI/E2E trên máy thật (Compose test, UI Automator, XCUITest). Tỷ lệ tham khảo 70/20/10 (Google Testing Blog, "Just Say No to More End-to-End Tests") — với dự án này là mặc định đề xuất của dự án, cần đo trên dữ liệu của dự án (tỷ lệ thật xem ở thời gian chạy và số lỗi bắt được mỗi tầng).
- Fake viết tay ưu tiên hơn mock repository (§16); test không phụ thuộc thứ tự, giờ hệ thống, mạng thật.

### 20.5 Crash-free và bằng chứng thiết bị thật
- Mục tiêu crash-free: không được vượt ngưỡng "bad behavior" của Google Play (crash 1,09% phiên người dùng cảm nhận được — Android vitals; kiểm lại con số hiện hành). Mục tiêu nội bộ crash-free sessions ≥ 99,5% và crash-free users ≥ 99% là mặc định đề xuất của dự án, cần đo trên dữ liệu Crashlytics/Organizer của dự án.
- Mỗi lần phát hành đối chiếu Crashlytics/Play Console/Xcode Organizer với bản trước; crash mới kèm test tái hiện (§20.1). Lỗi dự kiến (mất mạng, file bị xoá, huỷ coroutine) không đẩy lên như lỗi (§12).
- Nghiệm thu UI: ảnh chụp trạng thái THÀNH CÔNG từ **máy thật** (§4); bản release đã minify chạy thử trên máy (§8); iOS: bản Release trên thiết bị. Bằng chứng test là số đếm trong XML (`tests > 0`, `failures = 0`).

### 20.6 Kiểm soát flaky
- Test flaky là lỗi chất lượng: không `sleep` cố định, không toạ độ cứng, không phụ thuộc thứ tự; dùng idling/await có điều kiện và `StandardTestDispatcher` (§3, §7).
- Test mới hoặc test vừa sửa chạy lặp liên tiếp trước khi merge (ví dụ 20 lần; mặc định đề xuất của dự án, cần đo trên máy thật/CI của dự án) và phải xanh mọi lần; một lần đỏ ngẫu nhiên thì sửa nguyên nhân, không `@Ignore`/retry che.
- Retry tự động ở CI chỉ để phát hiện (ghi nhãn flaky và mở thẻ), không để làm xanh.
- Test hiệu năng chạy trên máy thật cố định model, sạc đủ, nhiệt ổn định, tắt cập nhật nền; ghi model và build vào báo cáo.

## 21. UI/UX & Accessibility — Cổng bắt buộc (chi tiết: `DESIGN.md`)

> Token màu, typography, spacing, chuyển động, trạng thái, dark mode, haptic: xem `DESIGN.md` của profile. Dưới đây là cổng kiểm tra ngắn cho mọi PR đổi giao diện (Android Compose/View và iOS SwiftUI/UIKit).

- **Vùng chạm**: ≥ 48×48 dp (Android; Material/Android accessibility docs) và ≥ 44×44 pt (iOS; Apple HIG); hai vùng chạm cách nhau ≥ 8 dp.
- **Tương phản**: chữ thường ≥ 4,5:1, chữ lớn ≥ 3:1 (WCAG 2.x AA); thành phần không phải chữ (icon, viền input) ≥ 3:1 (WCAG 1.4.11).
- **Chữ co giãn**: Android `sp` chịu font scale 200%; iOS Dynamic Type gồm cả kích thước accessibility (`.dynamicTypeSize`, font hệ thống/`Font.TextStyle`); không cố định chiều cao khung chữ.
- **Screen reader**: TalkBack (`contentDescription`, `semantics`, thứ tự đọc, `Role`) và VoiceOver (`accessibilityLabel`, `accessibilityHint`, trait, `accessibilityElement`); phần tử tương tác phải đọc được tên + vai trò + trạng thái. Duyệt thủ công bằng TalkBack/VoiceOver trên máy thật cho luồng chính.
- **Dark mode**: mọi màn hình có bản tối từ token ngữ nghĩa, không đảo màu thủ công; kiểm tra ảnh/tương phản ở cả hai chế độ.
- **Reduced motion**: tôn trọng "giảm chuyển động" (Android `ANIMATOR_DURATION_SCALE`/`Settings.Global`; iOS `accessibilityReduceMotion`); animation không chứa thông tin duy nhất.
- **4 trạng thái** Loading/Empty/Error/Populated cho mọi màn hình (§15, §17.5); Error có Thử lại; Empty có CTA.
- **Debounce ≥ 1000 ms** và disable ngay lần chạm đầu cho thao tác tốn kém (§1, §17.3).
- **Haptic**: chỉ để xác nhận hành động hoặc báo lỗi, có thể tắt theo cài đặt hệ thống (xem `DESIGN.md`).
- **Material 3 (Android) và Apple HIG (iOS)**: dùng thành phần/hành vi chuẩn nền tảng trước khi tự vẽ; khác biệt có chủ đích giữa hai nền tảng (điều hướng, sheet, back) giữ đúng thói quen nền tảng.
- **Zero-Slop**: không `Card` lồng `Card`, không icon tile đặt trên heading, không `Color.Gray`/`#808080` trần, không gradient tím–xanh mặc định (neutral pha 3–5% tông chủ đạo), nhịp spacing 4–8 / 12–16 / 24–32 (không 16 cho mọi thứ), không câu chào sáo rỗng (§15, §17.5). Skill `taste-mobile-app`, `ui-ux-pro-max`, `impeccable`.
- **Bằng chứng**: ảnh chụp từ máy thật ở chế độ sáng và tối, font scale lớn, và một lượt TalkBack/VoiceOver cho màn hình mới; với thay đổi chỉ trong tooling/docs không cần ảnh.

## 22. Bộ công cụ theo tình huống

> Gọi đúng công cụ của kit đúng lúc; tên viết dạng `skill:`, `agent:`, `council:` đều có thật trong kit. Mục Android-only không áp cho iOS: tương đương iOS là Instruments (Time Profiler, Allocations, Leaks), MetricKit và `xcodebuild test`.

| Nhóm | Tình huống | Công cụ | Cho ra |
|---|---|---|---|
| UI/UX | Dựng màn hình/luồng mobile mới hoặc làm lại giao diện rập khuôn | `skill:taste-mobile-app` | Hướng thiết kế mobile (Compose, SwiftUI, Flutter, RN) tránh template mặc định |
| UI/UX | Chọn bảng màu, font, style nút, micro-interaction, haptic | `skill:ui-ux-pro-max` | Quyết định thẩm mỹ và juice cho UI Mobile/Game |
| UI/UX | Thiết kế mới, critique, audit, polish giao diện native iOS/Android | `skill:impeccable` | Phê bình/audit/polish và trích `DESIGN.md` |
| UI/UX | Có `qa.config.json`, cần chụp màn route × viewport, soi lệch layout (phần web/WebView) | `skill:qa-visual` | Ảnh các màn và danh sách lỗi bố cục đo trên DOM, đính vào PR |
| UI/UX | Kiểm giao diện trên máy thật: vùng chạm ≥ 48 dp, tràn khung, ảnh nghiệm thu màn thành công | `agent:real-device-ui-auditor` | Báo cáo accessibility tree, touch target, layout overflow, xác thực ảnh proof |
| Hiệu năng | Sửa Compose, State, ViewModel, LazyColumn/LazyRow hoặc thấy UI giật (Android-only) | `skill:compose-recomp-audit` | Soát recomposition thừa trong Compose |
| Hiệu năng | Đo FPS jank, chẩn ANR/crash logcat, audit UI hierarchy, quét DEX 64K trên máy Android thật/emulator (Android-only) | `skill:android-real-device-qa` | Số đo FPS, log ANR/crash, hierarchy qua adb |
| Hiệu năng | Main thread > 16 ms, ANR, nóng máy/pin, OOM bitmap, giới hạn Binder 1 MB (iOS dùng Instruments/MetricKit) | `council:07-performance-anr` | Phán quyết hiệu năng/ANR/thermal theo ngân sách §19 |
| Hiệu năng | Thêm hoặc audit log, metric, trace, Crashlytics/Firebase Performance | `skill:observability-instrumentation` | Điểm đo đủ để chẩn đoán lỗi production |
| Chất lượng | Thêm/sửa logic testable, viết regression test | `skill:tdd-workflow` | Chu trình RED rồi GREEN an toàn |
| Chất lượng | Thiết kế/review test, chẩn flake, chọn bằng chứng tất định cho hành vi Android rủi ro | `agent:test-architect-seti` | Kiến trúc test và bằng chứng tất định |
| Chất lượng | Chạy lint, unit test, QA gate | `skill:qc` | Tự nhận build tool (Gradle, xcodebuild, npm...) rồi chạy lint + test |
| Chất lượng | Sắp tuyên bố xong/fixed/PASS, trước commit/PR, hoặc kiểm kết quả agent khác | `skill:verification-before-completion` | Bằng chứng chạy thật trước khi nhận xong |
| Chất lượng | Diff không tầm thường: crash, file, auth, navigation, lifecycle, nhiều file (Kotlin/Java) | `agent:principal-code-reviewer` | Phát hiện có bằng chứng, không tự sửa |
| Chất lượng | Review diff tự động trước commit/PR | `skill:open-code-review` | Nhận xét theo hunk bằng OpenCodeReview |
| Chất lượng | Đổi ranh giới module, DI, API công khai, điều hướng, hoặc lifecycle/concurrency sâu (Android) | `agent:android-principal-architect` | Đánh giá kiến trúc và rủi ro migration |
| Phát hành/An toàn | Build release, ký keystore, ProGuard/R8, đồng bộ version đa nền tảng, tuân thủ store | `agent:mobile-release-auditor` | Kiểm gói phát hành, chữ ký, R8, version, store compliance |
| Phát hành/An toàn | Đổi Intent/URI/file, exported component, permission, WebView, auth, network security, trước release | `skill:security-checklist` | Danh mục kiểm bảo mật theo hạng mục |
