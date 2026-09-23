# Game (Unity 6 / C# / URP Mobile & Blender) — Engineering Rules

> Áp dụng cho dự án Unity 6 (C#, URP, Unity Test Framework), đặc biệt game mobile casual/puzzle dọc.
> Ngân sách/ngưỡng cụ thể của một dự án (fps, draw call, MB, tỉ lệ màn hình, số màn) ghi ở `.agents/local/rules/` của dự án đó — file này là mặc định chung.
> Script trong profile chạy được từ gốc dự án qua `.agents/active-profile/scripts/…` và `.agents/active-profile/hooks/…`.

## 1. Kiểm soát Bộ nhớ & Rò rỉ Event (C# / MonoBehaviour)
- Bắt buộc hủy đăng ký (unsubscribe `-=`) mọi C# `Action`, `event`, `UnityEvent` listener thêm bằng code trong `OnDisable()` hoặc `OnDestroy()` (đối xứng với nơi đăng ký: `OnEnable`↔`OnDisable`, `Awake/Start`↔`OnDestroy`).
- Singleton kiểu `public static X Instance`: `OnDestroy()` phải đặt `if (Instance == this) Instance = null;`. Thiếu dòng này, sau khi reload scene `Instance` là object đã Destroy ("fake-null": `Instance != null` bằng toán tử Unity là false nhưng `?.` của C# vẫn gọi vào) → `MissingReferenceException`, và bản mới tự hủy vì tưởng đã có instance.
- `?.` / `??` bỏ qua toán tử `==` của `UnityEngine.Object` → không dùng chúng với tham chiếu MonoBehaviour/GameObject có thể đã Destroy; dùng `if (x != null)` hoặc `if (x)`.
- Khi tắt Domain Reload (Enter Play Mode Options), field `static` và event tĩnh giữ giá trị giữa các lần Play → reset trong hàm `[RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]`.
- Object `DontDestroyOnLoad` không bị hủy khi unload scene: test và luồng "chơi lại" phải tự dọn hoặc tái sử dụng chúng.

## 2. Hot Path Không Cấp Phát (Zero-GC) & Object Pooling
- CẤM tạo rác bộ nhớ (GC allocations) trong các hàm chạy theo frame: `Update()`, `FixedUpdate()`, `LateUpdate()`, coroutine lặp, callback input kéo-thả.
  - Cấm `new List<>()`, `LINQ` (`.Where()`, `.Select()`), boxing, closure/lambda bắt biến, cộng chuỗi, `string.Format` trong vòng lặp frame.
  - Dùng non-alloc physics APIs: `Physics.RaycastNonAlloc()`, `Physics.OverlapSphereNonAlloc()` với buffer cấp sẵn.
  - Cache `GetComponent<T>()`, `Camera.main`, `WaitForSeconds` trong `Awake()`/field; text động của TextMeshPro cập nhật bằng `SetText(format, value)` và chỉ khi giá trị đổi.
- Vật thể sinh/hủy liên tục (item, hiệu ứng, popup số, particle) dùng pool (`UnityEngine.Pool.ObjectPool<T>` hoặc pool riêng): không `Instantiate`/`Destroy` mỗi lần ghép/nổ. Pool phải reset trạng thái (tween, parent, scale, alpha, raycastTarget) khi trả về.
- Tween (DOTween…) gắn `SetTarget`/`SetLink` với GameObject sở hữu và kill khi object bị hủy/trả pool; số tween active sau khi xong màn phải về 0 (đo được bằng test).
- Đo GC bằng Profiler/`Recorder` (`GC.Alloc`) trên thiết bị thật. Trong Editor batchmode luôn có nền cấp phát của chính Editor (vài KB/frame) → ngưỡng trong test Editor phải là **tương đối** (không tăng theo màn/theo thời gian), không phải "0 byte".
- Kiểm tra nhanh bằng linter regex: `python3 <DevKit>/scripts/lint_unity_gc.py Assets/` (có thể báo sót/nhầm — không thay Profiler).

## 3. Rendering URP Mobile & Ngân Sách Khung Hình
- Mặc định: 60 fps → khung hình p95 ≤ 16,7 ms trên máy tầm trung; DrawCalls/Batches ≤ 100–150/frame trong gameplay (ghi ngưỡng thật của dự án vào rules riêng). Số đo trong Editor chỉ là chỉ báo — nghiệm thu trên máy thật.
- URP asset cho mobile: SRP Batcher bật; tắt HDR/MSAA/post-processing không dùng tới; không bật tính năng renderer không cần (Depth/Opaque Texture) cho game 2D/uGUI.
- Đổi thuộc tính visual lúc runtime qua `MaterialPropertyBlock` hoặc `sharedMaterial` có chủ đích; `Renderer.material` clone material mỗi lần gọi (rò rỉ, phá batching).
- Custom render pass trên URP 17 (Unity 6) viết theo RenderGraph API; không dùng API `Execute`/`CommandBuffer` cũ đã bị đánh dấu Compatibility Mode.
- UI: tách Canvas động (điểm, bộ đếm, thanh no) khỏi Canvas tĩnh để thay đổi text không rebuild cả canvas; tắt `raycastTarget` cho Image/Text trang trí; sprite UI gom vào Sprite Atlas.
- Texture: nén theo nền tảng (ASTC cho iOS/Android hiện đại), tắt Read/Write nếu không đọc pixel bằng code, kích thước bội số của 4 (block compression); texture 3D có mipmap ưu tiên lũy thừa của 2. Dùng Texture import preset/AssetPostprocessor để không phụ thuộc trí nhớ người import.
- Texture Atlasing và GPU Instancing cho vật thể lặp lại.

## 4. Tiêu chuẩn Mô hình 3D Blender
- Mesh xuất cho game: topology quad sạch, cấm non-manifold edges, cấm normal đảo; áp scale/rotation trước khi export (Unity dùng Y-up, 1 unit = 1 m).
- Xuất `.fbx` hoặc `.gltf`; asset ≥ 5 000 tris cần LOD0/LOD1/LOD2.
- Render sprite từ Blender (pipeline 2D dựng từ 3D): cố định camera/ánh sáng/độ phân giải trong script (`bpy`) để render lại được y hệt; nền trong suốt; đặt tên file ổn định để GUID trong Unity không đổi khi render lại.

## 5. Kỷ luật Asset Database & `.meta`
- CẤM TUYỆT ĐỐI tạo tài liệu, ghi chú, file tạm (`.md`, `.txt` ghi chú, `.tmp`, `.bak`, `.log`, `.orig`) bên trong `Assets/`. Tài liệu ở `docs/`, `design/`, `production/`; file nháp của agent ở ngoài repo (scratchpad) — kể cả file `.cs` thử compile: một `.cs` lạc trong `Assets/` làm vỡ biên dịch của mọi lần chạy Unity sau đó.
- Mỗi asset đi cùng `.meta` của nó: thêm/xóa/đổi tên/di chuyển phải làm cả hai (tốt nhất trong Editor). Xóa `.meta` khi asset còn → Unity sinh GUID mới → mọi tham chiếu scene/prefab tới asset đó gãy im lặng.
- Không sửa tay GUID/fileID trong YAML. Project Settings → Editor: Asset Serialization = Force Text, Version Control = Visible Meta Files.
- Scene/prefab là YAML dễ xung đột: mỗi thay đổi scene/prefab đi một commit riêng; cấu hình `UnityYAMLMerge` làm merge tool; ưu tiên tách UI/hệ thống thành prefab thay vì sửa scene lớn.
- Scene do code dựng (builder/generator) mà vẫn commit: coi là **đầu ra**, không sửa tay; nếu script test dựng lại và lưu scene mỗi lần chạy thì diff của scene sau khi chạy test là nhiễu, không phải thay đổi của task.
- Rác Unity Test Framework để lại sau lần chạy PlayMode bị crash (`Assets/InitTestScene*.unity`) và thư mục do công cụ ghi vào `Assets/Temp/` phải dọn trước khi commit.
- Hook tự động: `.claude/hooks/validate-assets.sh` (PostToolUse Edit|Write, chặn file tài liệu trong `Assets/`); chạy tay/ma trận: `bash .agents/active-profile/hooks/validate-assets.sh < /dev/null` (kiểm cả cặp `.meta`).

## 6. Kiến trúc Assembly (`.asmdef`)
- Tối thiểu 4 assembly: `<Game>.Runtime` · `<Game>.Editor` (`includePlatforms: ["Editor"]`) · `<Game>.Tests.EditMode` (`includePlatforms: ["Editor"]`, `defineConstraints: ["UNITY_INCLUDE_TESTS"]`, tham chiếu `nunit.framework.dll`) · `<Game>.Tests.PlayMode`.
- Chiều phụ thuộc một hướng: Tests → Editor → Runtime. Runtime KHÔNG tham chiếu Editor; code dùng `UnityEditor` trong Runtime phải bọc `#if UNITY_EDITOR` (không thì build player vỡ dù Editor vẫn chạy).
- Test cần chạm `internal` → `[assembly: InternalsVisibleTo("<Game>.Tests.EditMode")]`, không dùng reflection vào tên private (vỡ âm thầm khi đổi tên).
- Đổi `.asmdef` = biên dịch lại mọi assembly phụ thuộc → luôn chạy compile check sau khi sửa.

## 7. Kỷ luật Test: EditMode vs PlayMode
- **EditMode** cho logic thuần: luật chơi, solver, level generator, kinh tế/điểm, lưu/đọc save, parser dữ liệu. Tách logic khỏi MonoBehaviour để test được ở đây (nhanh, không cần scene).
- **PlayMode** cho vòng đời MonoBehaviour, coroutine, tween, load scene, input mô phỏng, layout UI thật.
- Tất định: random có seed (`System.Random(seed)` hoặc `Unity.Mathematics.Random`), in seed trong thông báo lỗi; không dùng trạng thái toàn cục `UnityEngine.Random` trong logic cần tái lập.
- Không chạm dữ liệu thật của người dùng: CẤM `PlayerPrefs.DeleteAll()` / ghi `persistentDataPath` thật trong test — tiêm (inject) store giả. Trên macOS, Editor dùng `unity.<company>.<product>.plist`, bản build Standalone dùng `com.<company>.<product>.plist` (Unity 6) → test `DeleteAll` xoá prefs của Editor (playtest trong Editor mất tiến trình); đừng suy ra hai file là một, đọc đúng file trước khi kết luận save bị xoá.
- Không assert theo đồng hồ sát ngưỡng (`WaitForSeconds(0.3f)` rồi kiểm tra thứ vừa tween 0,3 s): chờ theo điều kiện có timeout (`yield return new WaitUntil(...)` + đếm frame tối đa).
- `Screen.width/height` trong batchmode không phải kích thước máy (dự án tham chiếu đo được 640×480): test layout phải tự đặt độ phân giải/GameView hoặc tính theo `RectTransform`/`CanvasScaler`.
- Test đặt trong namespace; mọi object `DontDestroyOnLoad` tạo trong test được hủy ở `TearDown`/`UnityTearDown`.
- Mỗi bug fix có test hồi quy ĐỎ→XANH (`AGENTS.md` §6). Check tự động in số đo kèm PASS/FAIL; khi check FAIL thì sửa code, không nới ngưỡng.

## 8. Chạy Unity Batchmode — Lệnh & Bẫy Exit Code
Lệnh chuẩn (script profile đã xử lý các bẫy bên dưới):
```bash
bash .agents/active-profile/scripts/unity-batch.sh compile                 # -batchmode -quit -nographics
bash .agents/active-profile/scripts/unity-batch.sh editmode [--filter X]   # -runTests -testPlatform EditMode -testResults <xml>
bash .agents/active-profile/scripts/unity-batch.sh playmode [--category X]  # -runTests -testPlatform PlayMode (không -quit)
bash .agents/active-profile/scripts/unity-batch.sh execute Ns.Class.Method # -executeMethod, method tự gọi EditorApplication.Exit(code)
```
Nếu dự án đã có script riêng (`scripts/unity-compile-check.sh`, `scripts/unity-test.sh`…) thì dùng script của dự án.
- Unity có thể **thoát 0 dù log có `error CS…`** → luôn quét log (`-logFile`) tìm `error CS` / `Shader error in`.
- `-runTests` tự thoát khi chạy xong; thêm `-quit` làm Editor thoát trước khi test chạy.
- Chạy 0 test cũng thoát 0 (sai filter/category, assembly test không biên dịch) → kết quả không có `<test-case>` = FAIL.
- File kết quả là **NUnit 3 XML**, không phải JUnit: đọc bằng parser XML (`test-case/@result`), không đưa cho công cụ đọc JUnit.
- Mỗi project chỉ một Editor: có `Temp/UnityLockfile` + tiến trình Unity trên cùng đường dẫn → không chạy batchmode (đóng Editor, hoặc chờ phiên khác xong). Kiểm `pgrep -fl Unity` trước MỌI lệnh Unity, kể cả khi mình không mở Editor — một phiên/agent khác có thể đang dùng.
- Luôn có watchdog timeout và kill cả tiến trình; Editor có lúc treo lúc thoát sau "Test run completed" → bị kill → để lại `Temp/UnityLockfile` cũ: xác nhận không còn tiến trình rồi mới xóa.
- `-nographics` nhanh hơn nhưng không có GPU: đọc pixel, chụp GameView, test phụ thuộc render sẽ sai/đen — không dùng cho PlayMode cần hình.
- Lệnh chạy lâu (build Android/IL2CPP 15–30 phút) chạy nền có timeout riêng; không để chung timeout với test.
- Android build qua batchmode: Unity 6000.6 không đọc được output `sdkmanager` của Android cmdline-tools ≥ 23 → trỏ Unity vào SDK có cmdline-tools 16.0 (shim) hoặc bản Unity đi kèm; Player Settings "Active Input Handling = Both" gây cảnh báo build Android — chọn một hệ input và ghi ADR.

## 9. Sinh Màn Chơi Tất Định & Kiểm Chứng Solver
- Generator nhận seed, cùng seed → cùng màn (test so sánh 2 lần sinh). Không phụ thuộc thứ tự `Dictionary`/`HashSet` khi sinh.
- Có validator độc lập cho mỗi màn (đủ bộ 3, không bế tắc ngay từ đầu, ràng buộc thiết kế) chạy trong EditMode cho TOÀN BỘ danh sách màn.
- Solver có baseline đã commit (kết quả giải được/par theo từng màn); mọi thay đổi solver/generator/luật chạy lại baseline và giải thích mọi thay đổi số liệu.
- Unit test solver là chưa đủ: chạy bot chơi thật trong Play Mode giải N màn — `bash .agents/active-profile/scripts/unity-bot-marathon.sh 1-100` (ưu tiên `scripts/unity-bot-marathon.sh` của dự án; hợp đồng: bot in `[BOT-SUMMARY] won=W/T deadlocks=D`, PASS khi W = T và D = 0; không có Editor/bot → UNTESTED, không phải PASS).
- Trong game: kiểm bế tắc sau mỗi nước (không còn nước hợp lệ) và luôn có lối ra (gợi ý / hoàn tác / ô đệm) — không để người chơi kẹt im lặng. Bot tự chơi không được "đứng yên im lặng": đếm số lần bỏ lượt liên tiếp và fail kèm log.

## 10. Chạm, Kéo-Thả, Safe Area & Bố Cục Dọc
- Khóa hướng dọc trong Player Settings (Default Orientation = Portrait), không chỉ bằng code lúc chạy.
- `CanvasScaler` = Scale With Screen Size (tham chiếu dọc, ví dụ 1080×1920), `matchWidthOrHeight` chọn có chủ đích; nội dung tương tác nằm trong container áp `Screen.safeArea` (cập nhật lại khi safe area/độ phân giải đổi).
- Kiểm bố cục trên ma trận tỉ lệ tối thiểu: 16:9, 19.5:9 (notch/Dynamic Island), 20:9 (Android dài) + 4:3 nếu hỗ trợ iPad, cho mọi trạng thái UI chính (HUD và từng modal). Cấm: chữ tràn, phần tử tương tác chồng nhau, nằm dưới notch/home indicator, ra ngoài màn hình.
- Tọa độ UI: tính bằng `RectTransform` (`anchoredPosition`, `RectTransformUtility.ScreenPointToLocalPointInRectangle`), không cộng offset world (`Vector3.down * 100`) — kết quả khác nhau giữa Canvas Overlay và Screen Space - Camera, và giữa desktop/mobile.
- Kéo-thả: chỉ theo một `pointerId`; bỏ qua ngón thứ hai. Khóa input (theo ô/ngăn hoặc toàn bàn) khi item đang bay, đang nổ ghép, đang tween; hủy kéo khi pause/mất focus. Ngưỡng kéo (`EventSystem.pixelDragThreshold`) quy đổi theo dp (`Screen.dpi`).
- Vùng chạm ≥ 44 pt / 48 dp, nút quan trọng trong vùng ngón cái (nửa dưới màn hình dọc).

## 11. Addressables & Tài nguyên Tải Động
- Mỗi `LoadAssetAsync`/`InstantiateAsync` có `Release`/`ReleaseInstance` tương ứng (giữ handle); quên release = rò rỉ bộ nhớ theo màn.
- Không để cùng một asset vừa trong `Resources/` vừa trong nhóm Addressables (bị nhân đôi trong build). `Resources/` chỉ cho vài cấu hình nhỏ khởi động.
- Build nội dung Addressables trước build player (CI chạy cả hai); test chế độ "Use Existing Build" trước khi phát hành.

## 12. Quảng cáo, IAP, Consent — An Toàn Tích Hợp
- Tầng `PlatformServices` (Mock / Live) cho ads, IAP, analytics, notification: Editor và test luôn dùng Mock; không test nào gọi SDK thật.
- Chỉ thưởng rewarded ad trong callback "đã xem xong" của SDK; nút xem quảng cáo khóa ngay lần bấm đầu cho tới khi có kết quả. Mọi handler "xem QC để nhận X" phải có caller thật (kiểm bằng grep/test) — nút hiện mà không nối là lỗi.
- Không chen interstitial vào khoảnh khắc thưởng (cảnh thắng, lên cấp) hoặc khi người chơi đang thao tác; có giới hạn tần suất.
- IAP: xử lý giao dịch idempotent theo transaction ID, xử lý trạng thái pending, có Restore Purchases (iOS bắt buộc), xác nhận (confirm) chỉ sau khi đã cấp hàng.
- Consent (UMP/GDPR) và ATT (iOS) trước khi khởi tạo SDK quảng cáo/analytics; khai báo đúng nhóm tuổi. Không commit key/ad unit ID thật; ID test chỉ ở cấu hình dev.

## 13. Dữ liệu Lưu & Tiến Trình
- Save có số phiên bản; khóa thiếu → giá trị mặc định hợp lệ; nâng cấp từ bản save cũ có test.
- Hoàn thành màn idempotent: chơi lại màn cũ không cộng lại thưởng lần đầu, không kéo con trỏ tiến độ lùi lại.
- Ghi save khi `OnApplicationPause(true)`/`OnApplicationFocus(false)` và ở mốc (hết màn), không ghi mỗi frame.

## 14. Unity 6 API Drift (tri thức model có thể cũ)
- Tra tài liệu phiên bản đúng (context7 / tài liệu engine-reference của dự án) trước khi dùng API; không đoán chữ ký hàm.
- `Object.FindObjectsByType<T>(FindObjectsSortMode.None)` / `FindAnyObjectByType<T>()` thay `FindObjectsOfType<T>()` / `FindObjectOfType<T>()`.
- `Rigidbody.linearVelocity` / `linearDamping` thay `velocity` / `drag` (Unity 6).
- URP 17: RenderGraph cho renderer feature (§3).

## 15. Bằng Chứng Hình Ảnh (Visual Proof)
- Thay đổi hình ảnh/UI/game feel chỉ nghiệm thu bằng ảnh chụp Game View ở độ phân giải mục tiêu (ví dụ 1080×1920), chụp **sau** khi trạng thái cần chứng minh xuất hiện (giữa màn, sau thao tác) — không tin exit code, không tin số check.
- Ảnh phải khác ảnh nền (baseline): ảnh "màn 1 lúc bắt đầu" lặp lại qua nhiều task là ảnh cũ, không phải bằng chứng. Mở và nhìn từng ảnh; đối chiếu dữ liệu màn.
- Lỗi hình ảnh cần bắt: material hồng/magenta (shader lỗi), UI lệch/che, sprite fallback/placeholder, text tràn.

## 16. Tài liệu Thiết kế Game (GDD) — Checklist Review
*(Chắt lọc từ quy chuẩn thiết kế của Claude Code Game Studios, MIT License © 2026 Donchitos.)*
- Mỗi cơ chế một tài liệu, đủ 8 phần: Overview · Player Fantasy · Detailed Rules · Formulas · Edge Cases · Dependencies · Tuning Knobs · Acceptance Criteria.
- Công thức có định nghĩa biến, khoảng giá trị và ví dụ tính; edge case nói rõ chuyện gì xảy ra (không "xử lý khéo").
- Phụ thuộc hai chiều (A phụ thuộc B thì tài liệu B nhắc A); tuning knob có khoảng an toàn và ảnh hưởng tới gameplay.
- Acceptance criteria kiểm chứng được pass/fail; giá trị cân bằng dẫn nguồn công thức/lý do. Không "cảm giác phải hay".
- Giá trị gameplay nằm trong dữ liệu (ScriptableObject/JSON), không hardcode trong C#; đổi luật thì sửa GDD/ADR trong cùng thay đổi.
