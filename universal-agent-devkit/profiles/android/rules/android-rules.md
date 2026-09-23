# Android Mobile Engineering Rules

> Luật chung cho mọi app Android (Kotlin / Jetpack Compose / Gradle nhiều module). Tên class, module,
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
- Mọi tính năng hoàn thành bắt buộc phải có ảnh chụp màn hình xác minh trạng thái **THÀNH CÔNG (PASS / Success State)**.
- Soát git diff trước khi báo cáo Tech Lead / Reviewer.
- Bằng chứng test là số đếm trong `<module>/build/test-results/**/TEST-*.xml` (unit) hoặc `<module>/build/outputs/androidTest-results/**/TEST-*.xml` (instrumented): `tests > 0`, `failures = 0`, `errors = 0`, nêu rõ `skipped`; XML phải mới hơn lần sửa cuối. `UP-TO-DATE`, `NO-SOURCE`, `No tests found` = **chưa chạy**, không phải PASS.
- JVM unit test xanh KHÔNG chứng minh hành vi phụ thuộc nền tảng (XML parser, Charset, `File.renameTo` qua FUSE/SAF, font/line-break, R8, Room trên SQLite thật): cần instrumented test hoặc chạy trên máy.

## 5. Gradle nhiều module, `build-logic` & Version Catalog
- Cấu hình dùng chung (compileSdk/minSdk, Kotlin/JVM target, Compose, lint, test options) nằm trong **convention plugin** ở `build-logic/`; module chỉ áp plugin + khai báo phần riêng. Không copy khối `android { … }` vào từng module.
- Version và coordinate thư viện chỉ ở `gradle/libs.versions.toml`; không hardcode version trong `build.gradle.kts` của module.
- Sửa `build-logic/`, `libs.versions.toml`, `gradle.properties` hay root `build.gradle.kts` = đổi build của MỌI module → compile lại mọi module bị ảnh hưởng **kèm test source set**: `./gradlew :<m>:compileDebugKotlin :<m>:compileDebugUnitTestKotlin`. `assembleDebug`/`compileDebugKotlin` KHÔNG compile `src/test` — đổi chữ ký có thể vỡ test mà build vẫn xanh.
- Biến thể test theo `testBuildType`: module đặt `testBuildType = "release"` chỉ có `testReleaseUnitTest` — root `./gradlew testDebugUnitTest` bỏ qua module đó. Xác định task thật bằng `./gradlew :<m>:tasks --all | grep UnitTest` trước khi tin một lệnh test.
- Ranh giới module là hợp đồng: module thư viện dùng chung không phụ thuộc ngược lên `app`/feature; feature không import trực tiếp feature khác (đi qua navigation/interface ở core). Đổi ranh giới = hỏi trước.
- Giữ tương thích configuration cache: không đọc file/env/`System.getProperty` lúc configuration mà không qua `providers.*`.
- Nâng AGP/Kotlin/Compose compiler/KSP: nâng theo bảng tương thích chính thức, cùng một thay đổi, rồi build + test toàn bộ.

## 6. Jetpack Compose — Stability & Recomposition
- `@Immutable` = bất biến sâu thật sự; `@Stable` = mọi thay đổi quan sát được đều báo cho Compose. Không gắn annotation để "làm im" compiler report.
- File **stability configuration** (`stabilityConfigurationFiles`) chỉ liệt kê kiểu **thực tế bất biến trong cách dự án dùng**. Kiểu mutable (`java.util.Date`, `PointF`, `RectF`, `Rect`, mảng, collection mutable) nếu được khai stable thì **cấm mutate instance sau khi đã truyền vào composable** — Compose sẽ bỏ qua recomposition và UI hiển thị giá trị cũ. Luôn tạo instance mới khi giá trị đổi.
- Collection trong UI state: `kotlinx.collections.immutable` (`ImmutableList`/`PersistentList`) hoặc wrapper `@Immutable`; không để `MutableList` trong state.
- Đọc state ở owner hẹp nhất; lambda/callback ổn định (method reference hoặc `remember`); `LazyColumn`/`LazyVerticalGrid` có `key` theo identity ổn định và `contentType`.
- Không cấp phát/sort/format nặng trong composition hoặc draw loop; tính trước ở state holder.
- Chứng minh vấn đề và kết quả bằng Compose compiler reports/metrics, Layout Inspector (recomposition counts) hoặc Macrobenchmark/Perfetto trên cùng kịch bản trước/sau. Compile xanh không chứng minh giảm recomposition.
- Thu thập Flow trong UI bằng `collectAsStateWithLifecycle()`, không `collectAsState()` cho luồng tốn tài nguyên.

## 7. Baseline Profiles & Startup
- Sinh profile bằng module `androidx.baselineprofile` + Macrobenchmark trên build release-like (minified), cho các hành trình quan trọng thật (khởi động, mở màn hình chính, cuộn danh sách).
- Không sửa tay file `baseline-prof.txt` sinh ra; sinh lại sau thay đổi lớn về startup/navigation.
- Kiểm tra profile thực sự được đóng gói (artifact trong APK/AAB, `ProfileInstaller`) — "generate thành công" không phải bằng chứng runtime.
- Đo trước/sau cùng giao thức (cùng loại máy, `CompilationMode`, số vòng lặp). Ngưỡng cải thiện lấy từ baseline đo được, không lấy số mẫu.
- Selector trong generator/benchmark dựa trên semantics/resource-id/state, không `sleep` cố định hay toạ độ cứng.

## 8. R8 / ProGuard Keep Rules
- Release luôn `isMinifyEnabled = true` + `isShrinkResources = true`; **chạy thử bản release đã minify trên máy** trước khi phát hành — debug build không bao giờ lộ lỗi R8.
- Keep rule hẹp, có lý do: code gọi qua reflection, JNI (`native` method + class/field mà C/C++ truy cập), serialization (Kotlin Serialization/Gson/Moshi), enum `values()/valueOf()`, class nạp theo tên (`Class.forName`, ServiceLoader, `META-INF/services`). Cấm `-keep class ** { *; }`; `-dontwarn` phải kèm lý do.
- R8 có thể **repackage** class về package khác: `SomeClass::class.java.getResourceAsStream("file.txt")` (đường dẫn TƯƠNG ĐỐI theo package của class) trả `null` ở release dù resource vẫn nằm trong APK. Dùng `classLoader.getResourceAsStream("full/path/file.txt")` (tuyệt đối, không `/` đầu) hoặc keep package của class đó.
- Module thư viện ship keep rule qua `consumerProguardFiles`, không bắt app đoán.
- Lưu `mapping.txt` mỗi bản release và upload cho Crashlytics/Play để deobfuscate stack trace.
- Oracle cho lỗi chỉ xảy ra khi minify: test trên bản release, hoặc test JVM mô phỏng việc đổi tên/dời package (ví dụ remap class bằng ASM) — không kết luận từ debug build.

## 9. Storage Access Framework & `content://` URI
- URI từ SAF/`ACTION_VIEW`/`ACTION_SEND` là `content://`: **không suy ra file path** (`uri.path`, `_data`, `/storage/emulated/0/...`). Đọc/ghi bằng `ContentResolver.openInputStream/openOutputStream/openFileDescriptor` + `use {}`.
- Tên hiển thị/kích thước lấy từ `OpenableColumns.DISPLAY_NAME`/`SIZE` (có thể null/0 — xử lý); không lấy segment cuối của URI làm tên file.
- `takePersistableUriPermission` chỉ áp dụng cho grant từ `ACTION_OPEN_DOCUMENT`/`ACTION_OPEN_DOCUMENT_TREE`/`CREATE_DOCUMENT` có flag persistable; số grant lưu được có giới hạn — giải phóng grant không còn dùng.
- `SecurityException` (grant bị thu hồi), `FileNotFoundException` (file đã xoá/di chuyển), provider trả `null` là tình huống **dự kiến** — hiển thị UI phù hợp, không coi là crash/không đẩy lên Crashlytics như lỗi.
- Mode của `openFileDescriptor`/`openOutputStream`: `"w"` có thể KHÔNG truncate trên một số provider — dùng `"wt"` khi ghi đè toàn bộ; ghi an toàn = ghi file tạm rồi thay thế, không để file hỏng một nửa khi lỗi/huỷ.
- Mọi truy vấn provider/`DocumentFile` chạy ngoài main thread (§3). Quét cây thư mục lớn: giới hạn độ sâu/đồng thời, huỷ được, không BFS song song không giới hạn.
- Đọc `Intent` extra theo API mới (`getParcelableExtra(key, Uri::class.java)` từ API 33, `IntentCompat` cho bản cũ); kiểm tra MIME/kích thước trước khi mở.
- Không log/analytics URI, đường dẫn hay tên file thật (§12).

## 10. Hilt / Dependency Injection
- Ưu tiên constructor injection (`@Inject constructor`) + `@Binds` cho interface; `@Provides` chỉ cho kiểu không sở hữu.
- Scope đúng vòng đời: `@Singleton` cho client/DB/repository dùng chung; không `@Singleton` cho state theo người dùng/tài liệu, không giữ object nặng theo tài liệu (renderer, parser session) ở scope rộng.
- Không inject/giữ `Activity`/`Fragment`/`View` trong object sống lâu hơn nó; cần Context ở tầng dưới thì `@ApplicationContext`.
- ViewModel: `@HiltViewModel` + `SavedStateHandle` cho tham số điều hướng/khôi phục process death. Worker: `@HiltWorker` + `HiltWorkerFactory`.
- Test: `@HiltAndroidTest` + `@TestInstallIn`/`@UninstallModules` thay module; không sửa graph production cho test.
- Đổi binding dùng chung = đổi hành vi mọi consumer → liệt kê consumer (graph/grep, gồm `src/test`, `src/androidTest`) trước khi sửa.

## 11. Room — Schema & Migration
- `exportSchema = true`, thư mục schema được commit; mọi lần tăng `version` phải có `Migration`/`AutoMigration` **và** test bằng `MigrationTestHelper` (tạo DB ở version N-1 với dữ liệu thật, migrate, kiểm tra dữ liệu còn nguyên).
- Cấm `fallbackToDestructiveMigration()` ở release (mất dữ liệu người dùng); nếu buộc phải dùng thì chỉ `fallbackToDestructiveMigrationFrom(...)` các version cụ thể, có duyệt.
- **Bẫy `@Insert(onConflict = REPLACE)` + `ForeignKey(onDelete = CASCADE)`**: REPLACE thực chất là DELETE + INSERT → xoá sạch bản ghi con qua CASCADE. Cập nhật bản ghi cha có con thì dùng `@Upsert`/`@Update` (update tại chỗ). Có test: upsert cha → con còn nguyên.
- Nhiều thao tác phụ thuộc nhau: `@Transaction` / `withTransaction`; transaction ngắn, không I/O mạng bên trong.
- Truy vấn trả `Flow` hoặc là `suspend`; không `allowMainThreadQueries()` ngoài test.
- Index cho cột lọc/sắp xếp thường xuyên; danh sách lớn phân trang (Paging 3), không load toàn bộ bảng lên UI.

## 12. Analytics, Crashlytics & PII
- Không gửi PII vào analytics/Crashlytics (event param, custom key, log, message của exception): tên file, đường dẫn, URI, nội dung tài liệu, email, token, ID thiết bị thô. ID cần thiết thì hash; đường dẫn → chỉ gửi loại/nhóm (extension đã chuẩn hoá, bucket kích thước).
- Tên event và giá trị param là **hằng số ít cardinality**: không ghép tên event động, không dùng **chuỗi UI đã dịch** hay message exception làm giá trị (một lỗi sẽ vỡ thành hàng chục giá trị theo ngôn ngữ). Tách "message cho người dùng" khỏi "error key cho analytics" ngay tại nguồn.
- Tôn trọng giới hạn của nền tảng analytics (độ dài tên event/param, số param, số user property) — verify theo docs hiện hành, có test cho schema.
- Consent trước khi thu thập (Consent Mode / UMP); trạng thái `analytics_storage` không suy ra từ quyền quảng cáo.
- Crashlytics non-fatal: lọc `CancellationException` (coroutine huỷ hợp lệ) và lỗi dự kiến (mất mạng, file bị xoá, quyền bị thu hồi, người dùng huỷ) tại **helper trung tâm**, không rải ở call site. Lọc theo kiểu exception, không theo prefix chuỗi của lớp wrapper.
- Kiểm chứng event bằng DebugView/`adb shell setprop debug.firebase.analytics.app <pkg>` trên build có cấu hình giống release; dashboard trễ/không thấy ≠ event không gửi.

## 13. Bitmap, PDF & File Lớn — Bộ nhớ
- Giải mã ảnh theo kích thước hiển thị: `BitmapFactory.Options.inSampleSize` (đọc `inJustDecodeBounds` trước) hoặc `ImageDecoder.setTargetSize`; thư viện ảnh (Coil/Glide) phải có `size(...)`. Không decode ảnh gốc 12–50 MP vào `ARGB_8888`.
- Trang PDF: render theo viewport/zoom, tile cho zoom cao; bitmap cache bị chặn (`LruCache` tính theo byte, dựa `ActivityManager.memoryClass`); giải phóng khi trang ra khỏi màn hình.
- `android.graphics.pdf.PdfRenderer`: chỉ MỘT page mở tại một thời điểm (đóng page trước khi mở page khác), không thread-safe → tuần tự hoá mọi truy cập; renderer **sở hữu** `ParcelFileDescriptor` truyền vào và tự đóng nó — đừng đóng PFD lần hai hay giữ PFD riêng. Verify quyền sở hữu tài nguyên theo source SDK đã resolve trước khi thiết kế wrapper cleanup.
- File văn phòng/XML lớn: parse streaming (SAX/StAX/event API), không DOM toàn bộ; đặt ngân sách bộ nhớ và từ chối/hiển thị lỗi thân thiện khi vượt, thay vì để OOM.
- `OutOfMemoryError` là `Error`, **không** bị `catch (e: Exception)` bắt; vùng cần phục hồi phải bắt riêng và giải phóng tài nguyên; `android:largeHeap` không phải là cách sửa.
- Tài nguyên native/stream/cursor/renderer đóng ở MỌI nhánh (thành công, lỗi, huỷ coroutine, dispose muộn sau khi màn hình đã đóng); callback đến sau dispose phải no-op an toàn.
- Không giữ tham chiếu tĩnh tới `Activity`/`Context`/`View` (kể cả trong singleton của thư viện render) — rò rỉ cả cây view và bitmap.
- Đo bằng dữ liệu thật: fixture lớn/hỏng/mã hoá, Memory Profiler/LeakCanary/heap dump; không đẩy HPROF lên dịch vụ ngoài khi chưa được duyệt.

## 14. Vòng đời, Process Death & Công việc nền
- State cần sống qua process death đi vào `SavedStateHandle`/`rememberSaveable`; kiểm tra bằng "Don't keep activities" hoặc `adb shell am kill`.
- Coroutine gắn scope có vòng đời (`viewModelScope`, `lifecycleScope` + `repeatOnLifecycle`); cấm `GlobalScope`; khi bắt `Exception` trong coroutine phải ném lại `CancellationException`.
- Việc nền dài/định kỳ: `WorkManager` (constraints, backoff); `BroadcastReceiver.onReceive` chỉ việc nhanh hoặc `goAsync()` rồi `finish()` trong `finally`; Foreground Service khai báo `foregroundServiceType` đúng (Android 14+).
- App Widget (Glance/RemoteViews): PendingIntent/layout cũ có thể sống qua lần cập nhật app — xử lý `ACTION_MY_PACKAGE_REPLACED` để render lại mọi widget.

## 15. Accessibility & UI Compose
- Touch target ≥ 48×48dp (`Modifier.minimumInteractiveComponentSize()`); text dùng `sp` và chịu được font scale 200%; tương phản ≥ 4.5:1.
- Icon có ý nghĩa có `contentDescription` (chuỗi resource); icon trang trí `contentDescription = null`; icon chỉ hướng dùng `Icons.AutoMirrored.*` và layout dùng start/end cho RTL.
- Màu/khoảng cách/typography lấy từ theme/design-system (`MaterialTheme.colorScheme`, token của dự án), không `Color(0x…)`/số dp rải rác; chuỗi hiển thị qua `stringResource`.
