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

### [INSTINCT-G01] Bẫy Lệch Chuẩn API Unity 6 (Unity 6.6 API Drift)
- **Hiện tượng lỗi:** Sinh code dùng API cũ bị deprecated trong Unity 6 (như `FindObjectsOfType<T>()`, `Renderer.material` gây clone material rò rỉ, CommandBuffer thô thay vì RenderGraph).
- **Nguyên nhân gốc rễ:** Dữ liệu huấn luyện của LLM bị cutoff trước Unity 6.6.
- **Quy tắc bắt buộc:** 
  1. Dùng `Object.FindObjectsByType<T>(FindObjectsSortMode.None)` thay vì `FindObjectsOfType<T>()`.
  2. Dùng `Renderer.sharedMaterial` hoặc MaterialPropertyBlock khi đổi thuộc tính visual trong runtime, tránh gọi `.material` gây sinh clone instance làm rò rỉ VRAM.
  3. Tuân thủ chuẩn RenderGraph API khi viết custom render passes trên Universal Render Pipeline (URP).

---

### [INSTINCT-G02] Bẫy `Time.timeScale = 0` Khiến Menu Pause Bị Treo Đơ
- **Hiện tượng lỗi:** Mở Pause Menu hoặc Game Over Dialog bằng `Time.timeScale = 0;`, nhưng các hiệu ứng tween UI (DOTween / LeanTween) hoặc Coroutine mở popup bị đứng hình bất động, người dùng không thể bấm resume.
- **Nguyên nhân gốc rễ:** Tween và Coroutine mặc định chạy theo game time bị đóng băng khi `timeScale = 0`.
- **Quy tắc bắt buộc:** 
  1. Mọi tween UI chạy trong popup/pause menu bắt buộc phải set `.SetUpdate(true)` (Unscaled Time).
  2. Mọi Coroutine chạy trong UI pause bắt buộc dùng `yield return new WaitForSecondsRealtime(...)` thay vì `WaitForSeconds(...)`.

---

### [INSTINCT-G03] Bẫy Animator Controller Rỗng & State Không Có Clip
- **Hiện tượng lỗi:** Gọi `animator.Play("Attack")` hoặc `animator.SetTrigger(...)` nhưng Animator Controller bị gán rỗng (null runtimeAnimatorController) hoặc State không gắn Animation Clip, sinh NullReferenceException hoặc đơ frame nhân vật.
- **Nguyên nhân gốc rễ:** Prefab cấu hình dang dở hoặc thay đổi runtime mà không null-check controller.
- **Quy tắc bắt buộc:** Kiểm tra `animator != null && animator.runtimeAnimatorController != null && animator.isActiveAndEnabled` trước khi kích hoạt trigger/state.

---

### [INSTINCT-G04] Bẫy Canvas Rebuild & Tụt FPS Do Trộn Dynamic Với Static UI
- **Hiện tượng lỗi:** Game bị tụt FPS từ 60/120 xuống 30–40 FPS trên mobile mỗi khi Text hiển thị điểm số, máu (HP), hoặc đồng hồ đếm ngược cập nhật giá trị.
- **Nguyên nhân gốc rễ:** Đặt Text động chung một Canvas với Background tĩnh hoặc hàng trăm Icon tĩnh. Khi Text thay đổi, Unity đánh dấu cả Canvas là dirty và rebuild toàn bộ Vertex Buffer của Canvas đó.
- **Quy tắc bắt buộc:** Bắt buộc phân tách UI thành các Sub-Canvas độc lập: Canvas tĩnh (Background, khung viền không đổi) và Canvas động (Text điểm số, thanh máu, coin count).

---

### [INSTINCT-G05] Bẫy Cấp Phát Bộ Nhớ Heap Trong Frame Loop (Physics NonAlloc)
- **Hiện tượng lỗi:** Game chơi sau 2–3 phút bị giật khựng (Spike lag 50–100ms) lặp đi lặp lại do Garbage Collector thu gom rác thế hệ Gen 0.
- **Nguyên nhân gốc rễ:** Dùng `Physics.RaycastAll`, `Physics.OverlapSphere`, hoặc `GetComponent<T>()` bên trong `Update()`, `FixedUpdate()`, mỗi frame cấp phát một mảng `Collider[]` hoặc đối tượng mới trên Heap.
- **Quy tắc bắt buộc:** 
  1. Bắt buộc dùng `Physics.RaycastNonAlloc` và `Physics.OverlapSphereNonAlloc` với mảng đệm tĩnh/thành viên (preallocated buffer).
  2. Cache toàn bộ Component references trong `Awake()` / `Start()`.
  3. Tuyệt đối cấm dùng từ khóa `new ` (List, Dictionary, Object) trong `Update()`.

---

### [INSTINCT-G06] Unity Batchmode "Xanh Ảo": Exit 0 Dù Lỗi Biên Dịch Hoặc 0 Test Chạy
- **Hiện tượng lỗi:** Lệnh Unity batchmode trả exit 0 nên agent báo "compile sạch / test xanh", trong khi log có `error CS…` hoặc file kết quả không có test case nào (sai `-testFilter`, assembly test không biên dịch, thêm `-quit` cạnh `-runTests`).
- **Nguyên nhân gốc rễ:** Exit code của Editor không phản ánh lỗi biên dịch; `-runTests` chạy 0 test vẫn thoát 0; `-quit` làm Editor thoát trước khi test chạy.
- **Quy tắc bắt buộc:** Luôn quét `-logFile` tìm `error CS` / `Shader error in`; đọc XML NUnit 3 (không phải JUnit) và coi "0 `<test-case>`" là FAIL; không thêm `-quit` với `-runTests`. Dùng `.agents/active-profile/scripts/unity-batch.sh` hoặc script của dự án đã làm sẵn các bước này.
- **Kiểm tra tự động:** `grep -c "error CS" <log>` = 0 và `grep -c "<test-case" <results.xml>` > 0.

---

### [INSTINCT-G07] Hai Tiến Trình Unity Cùng Mở Một Project
- **Hiện tượng lỗi:** Batchmode chết khó hiểu, báo "project đang mở", hoặc phá trạng thái của phiên Editor/agent khác (xóa pipeline, ghi đè scene) khi chạy compile/test lúc người khác đang mở Editor.
- **Nguyên nhân gốc rễ:** Unity chỉ cho một Editor/project (`Temp/UnityLockfile`); nhiều agent/phiên song song không biết nhau. Lần chạy bị kill (timeout) để lại lockfile cũ.
- **Quy tắc bắt buộc:** Trước MỌI lệnh Unity: `pgrep -fl Unity` + kiểm `Temp/UnityLockfile`. Có tiến trình trên cùng project → dừng, báo người dùng. Lockfile mà không có tiến trình → lockfile cũ, xác nhận rồi mới xóa. Không bao giờ kill Editor của người khác.
- **Kiểm tra tự động:** `[ ! -f Temp/UnityLockfile ] && ! pgrep -f "Unity.*$(pwd)"`

---

### [INSTINCT-G08] Test Xóa Save Thật Của Người Chơi (`PlayerPrefs.DeleteAll`)
- **Hiện tượng lỗi:** Sau khi chạy test suite, bản game đang chơi trên máy dev mất tiến trình (về màn 1, mất xu); thao tác `defaults write` để mở khóa màn cũng "không có tác dụng".
- **Nguyên nhân gốc rễ:** Test gọi `PlayerPrefs.DeleteAll()`/ghi PlayerPrefs thật trong `SetUp`. Trên macOS, Editor ghi `~/Library/Preferences/unity.<company>.<product>.plist` và bản build Standalone ghi `com.<company>.<product>.plist` (Unity 6; Windows: hai khoá registry khác nhau) — `DeleteAll` trong test xoá prefs Editor đang dùng để playtest; save thật của người chơi nằm ở file của bản build, app đang mở ghi đè plist khi thoát.
- **Quy tắc bắt buộc:** Logic lưu trữ đi qua interface store để test tiêm store giả; cấm `PlayerPrefs.DeleteAll` trong test (thêm test guard quét thư mục Tests). Sửa plist/PlayerPrefs của bản build chỉ khi app đã đóng và đọc lại để xác nhận.
- **Kiểm tra tự động:** `grep -rln --include=*.cs "PlayerPrefs.DeleteAll" Assets | grep -i "/tests/"` = 0 kết quả.

---

### [INSTINCT-G09] Singleton "Fake-Null" Sau Khi Reload Scene
- **Hiện tượng lỗi:** Sau `SceneManager.LoadScene` (chơi lại, test load scene nhiều lần) hàng loạt `MissingReferenceException`; manager mới tự `Destroy` vì tưởng đã có instance; test PlayMode đỏ dây chuyền.
- **Nguyên nhân gốc rễ:** `OnDestroy()` không đặt `Instance = null`; `Instance?.Foo()` dùng null-check của C# nên vẫn gọi vào object Unity đã hủy.
- **Quy tắc bắt buộc:** Mọi singleton MonoBehaviour: `void OnDestroy() { if (Instance == this) Instance = null; }`; không dùng `?.`/`??` với `UnityEngine.Object`. Có test PlayMode load scene ≥ 2 lần.
- **Kiểm tra tự động:** Mỗi file có `static .* Instance` phải có `Instance = null` (grep đối chiếu).

---

### [INSTINCT-G10] Hiệu Ứng UI Tính Bằng Tọa Độ World
- **Hiện tượng lỗi:** Item kéo biến mất, sao/xu bay xuất phát ngoài màn hình, bàn tay hướng dẫn chỉ sai chỗ — chỉ trên desktop/web hoặc chỉ trên mobile.
- **Nguyên nhân gốc rễ:** Cộng offset world (`transform.position + Vector3.down * 100`) hoặc dùng `Camera.main` cho phần tử thuộc Canvas; đơn vị và gốc tọa độ khác nhau giữa Canvas Overlay và Screen Space - Camera, giữa độ phân giải.
- **Quy tắc bắt buộc:** Tween UI bằng `anchoredPosition` (`DOAnchorPos`), quy đổi điểm màn hình bằng `RectTransformUtility.ScreenPointToLocalPointInRectangle` với camera đúng của canvas; test PlayMode chạy cả hai chế độ canvas.

---

### [INSTINCT-G11] Race Input Khi Item Đang Bay / Đang Nổ
- **Hiện tượng lỗi:** Kéo món khác khi món trước còn đang bay → Undo làm mất món; kéo được món đang nổ ghép 3 → highlight kẹt, ô "đầy ma"; bấm gợi ý trong lúc kéo → gợi ý kẹt; ngón thứ hai phá thao tác kéo.
- **Nguyên nhân gốc rễ:** Snapshot/validate trạng thái chạy khi animation chưa kết thúc; không khóa input trong khoảng chuyển tiếp; không lọc `pointerId`.
- **Quy tắc bắt buộc:** Khóa input theo ô/bàn khi có item đang bay/nổ (`pendingFlights > 0`), item đang nổ `SetSelectable(false)` + tắt raycast; drag chỉ theo một `pointerId`; hủy kéo khi pause. Mỗi race có test PlayMode "spam tap trong lúc tween".

---

### [INSTINCT-G12] Check Tự Động Xanh Nhưng Màn Hình Sai
- **Hiện tượng lỗi:** Check UI 100% PASS (kích thước nút, safe area, overlap) trong khi người chơi thấy badge vô hình, icon bị che, text trống, sprite placeholder. Ảnh "nghiệm thu" qua nhiều task giống hệt nhau.
- **Nguyên nhân gốc rễ:** Check chỉ quét `Selectable`, không nhìn hình/đọc chữ; công cụ chụp ảnh chụp trạng thái cũ (màn 1 lúc bắt đầu) chứ không phải trạng thái vừa thay đổi.
- **Quy tắc bắt buộc:** Thay đổi hình ảnh phải có ảnh chụp đúng trạng thái sau thay đổi (giữa màn, sau thao tác), khác ảnh baseline, và phải mở ra nhìn. Test xanh ≠ tính năng hiện đúng. Khi một lỗi chỉ ảnh bắt được, thêm check tự động cho lớp lỗi đó.

---

### [INSTINCT-G13] File Nháp Của Agent Rơi Vào `Assets/` Hoặc Gốc Repo
- **Hiện tượng lỗi:** Lần chạy Unity sau đó lỗi biên dịch vì một `Test*.cs` nháp trong `Assets/`; `.meta` lạ xuất hiện; thư mục `Assets/Temp/` do công cụ chụp ảnh tạo ra (đường dẫn `save_path` tương đối được hiểu là trong `Assets/`); `patch.py`, `result.json`, `*.cs` lạc ở gốc repo.
- **Nguyên nhân gốc rễ:** Agent (kể cả agent chỉ-đọc/phản biện) tạo file thử compile ngay trong project; công cụ ghi file theo đường dẫn tương đối với `Assets/`.
- **Quy tắc bắt buộc:** File nháp chỉ ở scratchpad ngoài repo; `git status` sạch rác trước mỗi lần chạy Unity; công cụ ghi file phải nhận đường dẫn tuyệt đối ngoài `Assets/` hoặc dọn cả thư mục lẫn `.meta` ngay sau đó.
- **Kiểm tra tự động:** `bash .agents/active-profile/hooks/validate-assets.sh < /dev/null`

---

### [INSTINCT-G14] Script Test Dựng Lại Scene Mỗi Lần Chạy
- **Hiện tượng lỗi:** Sau khi chạy test, scene chính (`*.unity` hàng chục MB) hiện trong `git diff` dù task không đụng tới; task bị coi là "sửa file cấm"; merge scene xung đột.
- **Nguyên nhân gốc rễ:** Scene vừa là nguồn commit vừa là đầu ra của builder mà script test gọi và lưu lại.
- **Quy tắc bắt buộc:** Không đưa scene do builder sinh vào danh sách cấm của task chừng nào test còn dựng lại nó; không commit diff scene do test sinh như thay đổi của task; hướng lâu dài: scene tối giản + dựng lúc chạy, hoặc không commit đầu ra builder.

---

### [INSTINCT-G15] Ngưỡng Test Tuyệt Đối Cho Số Đo Dao Động (GC, Thời Gian)
- **Hiện tượng lỗi:** Test GC "≤ 8 byte chênh lệch" hoặc test chờ `WaitForSeconds` sát thời lượng tween đỏ ngẫu nhiên; mất nhiều vòng sửa vì test flaky chứ không phải code.
- **Nguyên nhân gốc rễ:** Editor batchmode có nền cấp phát riêng (vài KB/frame) dao động giữa các mẫu; thời gian thực trong batchmode không ổn định.
- **Quy tắc bắt buộc:** Ngưỡng tương đối (không tăng theo màn, ≤ x %), lấy min/median nhiều mẫu; chờ theo điều kiện có timeout thay vì theo giây; số đo tuyệt đối (0 B/frame, ms/frame) chỉ nghiệm thu trên máy thật.

---

### [INSTINCT-G16] Hoàn Thành Màn Không Idempotent
- **Hiện tượng lỗi:** Chơi lại màn cũ vẫn nhận đủ thưởng lần đầu (farm vô hạn) và con trỏ tiến độ bị kéo lùi; modal thắng hiển thị số xu khác số thực cộng vào ví.
- **Nguyên nhân gốc rễ:** `CompleteLevel` ghi đè `currentLevel = index + 1` và cộng thưởng không điều kiện; UI tự tính thưởng thay vì nhận giá trị từ logic.
- **Quy tắc bắt buộc:** Thưởng lần đầu chỉ khi lần đầu/khi tăng sao; `current = Max(current, index + 1)`; UI hiển thị giá trị do logic trả về. Test EditMode "chơi lại màn 1 khi đang ở màn 20".

---

### [INSTINCT-G17] Khôi Phục Trạng Thái Bắn Sự Kiện Gameplay
- **Hiện tượng lỗi:** Mở màn là xin quyền thông báo / phát hiệu ứng lớn lên / tự nổ bộ ba có sẵn hai lần — những việc lẽ ra chỉ xảy ra khi người chơi thao tác.
- **Nguyên nhân gốc rễ:** Đường nạp/khôi phục trạng thái (`SetStage(animate:false)`, `AddItem(instant)` lúc load màn) dùng chung code với đường gameplay nên vẫn bắn event/kiểm tra ghép.
- **Quy tắc bắt buộc:** Tách đường "khôi phục im lặng" không bắn event gameplay; event quan trọng (xin quyền, thưởng, analytics) chỉ nối vào đúng khoảnh khắc gameplay thật. Test: load màn 1 → số lần gọi dịch vụ mock = 0.

---

### [INSTINCT-G18] Tính Năng "Có Nút" Nhưng Chưa Nối / Hệ Thống Cũ Vẫn Chạy Ngầm
- **Hiện tượng lỗi:** Nút "xem quảng cáo cứu ván" hiện nhưng handler có 0 caller; sau khi đổi thiết kế, hệ thống bản cũ (sự kiện x2, chuỗi thắng, mascot…) vẫn chạy, log vẫn in, HUD hiển thị thông tin sai.
- **Nguyên nhân gốc rễ:** Tính năng đánh dấu xong theo UI chứ không theo luồng; builder/bootstrap vẫn `AddComponent` hệ thống cũ.
- **Quy tắc bắt buộc:** "Xong" = có caller thật + test luồng end-to-end; khi thay thiết kế, gỡ cả chỗ khởi tạo hệ thống cũ và kiểm `Player.log` một màn không còn tag log của hệ thống cũ.
- **Kiểm tra tự động:** grep tên handler (phải có caller ngoài test) và grep tag log cũ trong Player.log = 0.

---

### [INSTINCT-G19] Build Android Batchmode Của Unity 6 Vỡ Do Android SDK Mới
- **Hiện tượng lỗi:** Build Android batchmode dừng ở bước kiểm tra SDK (không đọc được output `sdkmanager`), hoặc log build đầy cảnh báo input.
- **Nguyên nhân gốc rễ:** Unity 6000.6 không parse được output của Android cmdline-tools ≥ 23; Player Settings "Active Input Handling = Both".
- **Quy tắc bắt buộc:** Trỏ Unity vào SDK (hoặc thư mục shim symlink) có cmdline-tools 16.0; chọn một hệ input (Input Manager cũ hoặc Input System) và ghi ADR; build Android chạy nền với timeout riêng (15–30 phút).

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
