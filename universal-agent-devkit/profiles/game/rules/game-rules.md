# Game (Unity 6 / C# / URP Mobile & Blender) — Engineering & Design Rules

> Áp dụng cho dự án Unity 6 (C#, URP, Unity Test Framework), đặc biệt game mobile casual/puzzle/arcade.
> Toàn bộ quy chuẩn được tổ chức thành **6 Nhóm Nghiệp Vụ Tinh Gọn** (chắt lọc từ thực tiễn sản xuất AAA-indie và Claude Code Game Studios © Donchitos).
> Script trong profile chạy được từ gốc dự án qua `.agents/active-profile/scripts/…` và `.agents/active-profile/hooks/…`.

## 1. Thiết Kế Game & Định Hướng Mỹ Thuật (GDD & Art Direction)
- **Tài liệu GDD 8 phần chuẩn mực:** Mỗi cơ chế bắt buộc có GDD khép kín đủ 8 phần: Overview · Player Fantasy · Detailed Rules (States/Transitions) · Formulas (có biến và ví dụ tính) · Edge Cases (xử lý tất định) · Dependencies (2 chiều) · Tuning Knobs (ngưỡng min/max an toàn) · Acceptance Criteria (kiểm chứng được bằng test). Mọi giá trị gameplay đặt trong `ScriptableObject`/JSON, tuyệt đối không hardcode trong mã C#.
- **Quy tắc phối màu 60-30-10:**
  - `60% Base / Nền:` Tone tối hoặc dịu (`#1A1A2E`, `#16213E`, `#F4F5F7`) chống mỏi mắt.
  - `30% Structure / Khung viền:` Bệ đỡ, panel, thanh điều hướng (`#C5A059`, `#8A9BA8`).
  - `10% Accent CTA / Điểm nhấn:` Nút chính Play/Claim, ngọc quý, cảnh báo (`#FFA000`, `#00E676`, `#FF1744`).
- **Từ điển màu ngữ nghĩa:** Vàng/Gold (tiền thưởng, CTA số 1), Đỏ/Crimson (nguy hiểm, máu tụt, hủy), Xanh lá/Emerald (hồi phục, an toàn, xác nhận), Xanh dương/Cyan (mana, khiên, info), Tím/Violet (vật phẩm hiếm/epic).
- **Ngữ pháp hình khối (Shape Language):** Tròn/Pill (thân thiện, an toàn, player, phần thưởng, bo góc $\ge 16\text{px}$); Vuông/Rect (ổn định, nền tảng, chướng ngại vật, lưới); Nhọn/Spike (nguy hiểm, kẻ thù, cạm bẫy). Phân cấp thị giác: Bàn chơi $\to$ Mục tiêu $\to$ Nút CTA chính.

## 2. Mỹ Thuật Kỹ Thuật, 3D Assets & Shaders (Technical Art & Rendering)
- **Pipeline 3D-to-2D Baked Sprites (Chống Phèn):** CẤM DÙNG 2D phẳng hoặc khối primitive thô cho coin, gem, rương, cúp. Dựng 3D beveled trong Blender (`bpy`) với ánh sáng Studio 3 điểm (Key Light ấm 45°, Fill Light lạnh 50%, Rim Light gắt nổi viền + AO), render headless ra PNG 512×512 alpha trong suốt, đóng gói vào SpriteAtlas (đẹp nổi khối 3D nhưng nhẹ DrawCall như 2D).
- **Tiêu chuẩn Mesh 3D:** Quad topology sạch, cấm non-manifold/đảo normal; freeze scale/rotation trước khi export (Unity Y-up, 1 unit = 1m); asset $\ge 5\,000$ tris bắt buộc có LOD0/LOD1/LOD2.
- **Shader & VFX Mobile URP:**
  - SRP Batcher: Mọi custom shader bắt buộc đóng gói uniforms vào CBUFFER `UnityPerMaterial`.
  - Độ chính xác: Dùng `half` (16-bit) cho màu sắc, UV, normal; chỉ dùng `float` (32-bit) cho worldPos, depth, matrix.
  - Triệt tiêu phân nhánh động: Cấm `if/else` trong fragment shader; dùng `lerp()`, `step()`, `smoothstep()`, `saturate()`.
  - Ngân sách VFX: Hạt one-shot $\le 30-50$ particles; bật Bounds-based Culling; pooling qua `ObjectPool<ParticleSystem>`.
- **URP Global Volume (Bắt buộc mọi Scene):** Tonemapping ACES (chống cháy trắng bệt màu); Bloom (Threshold 1.15, Scatter 0.7 làm rực ngọc/hiệu ứng); Vignette (0.22 gom thị giác); Color Adjustments (Contrast +12, Saturation +8 tạo độ tươi tắn).

## 3. Trải Nghiệm Người Dùng & Game Feel (UI/UX Production & Juice Engine)
- **Game Feel & "Juice" Đa Giác Quan:**
  - `Squash & Stretch:` Chạm nén $0.92\times$ Y ($0.08\text{s}$), buông bật nảy Overshoot $1.08\times$ với `Ease.OutBack` ($0.15\text{s}$). Luôn `transform.DOKill(true)` trước khi kích hoạt tween mới.
  - `Hit-Stop (Impact Freeze):` Dừng frame 3–5 frames ($50-80\text{ms}$) khi va chạm mạnh hoặc nổ combo tạo cảm giác lực có sức nặng.
  - `Trauma Camera Shake:` Rung chấn phi tuyến tính tính bằng $Trauma^2 \times \text{PerlinNoise}(t)$ với decay tuyến tính ($1.2/\text{s}$).
- **Feedback Hạt & Số Nổi:** Burst 15–25 hạt sparkles bay cánh cung hút vào HUD khi nhận thưởng; TextMeshPro Floating Numbers punch scale 1.25x trôi lên $+150\text{px}$ mờ dần $0.6\text{s}$ (tái sử dụng qua Object Pool).
- **Kiến trúc uGUI Canvas:** Tối thiểu 2 Canvas độc lập để khỏi rebuild mesh và re-batch cả cây: `Canvas_Static` (nền, frame cố định) và `Canvas_Dynamic` (thanh máu, số đổi liên tục). Kit giữ 3 tầng: `Canvas_Static_Background` (tắt raycaster), `Canvas_Dynamic_HUD` (chỉ rebuild text thay đổi), `Canvas_Modal_Overlay` (Dimmer 60% alpha, scale tween $0.8 \to 1.0$). Nút bấm dùng 9-sliced sprite có viền nổi (bevel highlight sáng hơn 20%, bóng đáy tối hơn 30%).
- **TextMeshPro Styling Tiêu Chuẩn:** Cấm text trần trụi. Bắt buộc dùng TMP SDF Material Preset có Drop Shadow Underlay (Offset Y = -0.5, Softness = 0.2), Outline 0.15 và gradient 4 điểm tạo chữ nổi bật trên nền game.
- **Decoupled Audio Event Bus:** Bắn sự kiện âm thanh qua `AudioEventBus.Raise()`; mọi âm thanh UI/gameplay (Pop, Clink, Whoosh, Thud) kèm **Pitch Jitter ngẫu nhiên ($0.95 - 1.05$)** chống mỏi tai.
- **Bố Cục Dọc & Vùng Ngón Cái (Thumb Zone):** Nút chính trong $40\%$ nửa dưới màn hình; `CanvasScaler` Scale With Screen Size (1080×1920); bọc tương tác trong `Screen.safeArea`; Touch Target $\ge 48\times 48\text{dp}$; Debounce $\ge 1000\text{ms}$ nút mua/nhận thưởng; đủ 4 trạng thái tương tác (Normal, Hover/Focus, Pressed, Disabled).
- **Zero-Slop cho UI game:** Cấm Panel lồng Panel (dùng khoảng trắng + divider mảnh); cấm icon tile trên heading; cấm xám trần `#808080` và gradient tím-xanh (neutral pha 3–5% tông chính); spacing 4–8 / 12–16 / 24–32, không 16 đều. Nút không phẳng kiểu web: 9-slice bevel, Pressed (tư thế đang giữ nút) scale 0.95 kèm lún 2–4px và trả lại khi nhả — squash 0.92× ở mục Squash & Stretch là tween lúc chạm, không phải tư thế giữ; cấm font mặc định `LiberationSans SDF` của TextMeshPro. Dữ liệu chi tiết: skill `ui-ux-pro-max` (stack `unity-ugui`, nhóm `VisualSlop`).

## 4. Kiến Trúc C# & Tối Ưu Hiệu Năng Bộ Nhớ (Zero-GC & Architecture)
- **Kiến trúc 4 Assembly (`.asmdef`):** `<Game>.Runtime`, `<Game>.Editor`, `<Game>.Tests.EditMode`, `<Game>.Tests.PlayMode`. Chiều phụ thuộc 1 hướng: Tests $\to$ Editor $\to$ Runtime. Runtime cấm dùng `UnityEditor` khi chưa bọc `#if UNITY_EDITOR`. Test chạm internal dùng `InternalsVisibleTo`.
- **Vòng Đời & Triệt Tiêu Rò Rỉ Event:** Unsubscribe đối xứng (`-=` trong `OnDisable`/`OnDestroy`); Singleton `Instance = null` trong `OnDestroy`; cấm `?.`/`??` với fake-null của `UnityEngine.Object` (dùng `if (x)`); reset field tĩnh trong `[RuntimeInitializeOnLoadMethod(SubsystemRegistration)]`.
- **Hot Path Zero-GC:** Cấm tuyệt đối `new`, nối chuỗi bằng `+`, LINQ, boxing và closure trong `Update()` và `FixedUpdate()` (cả coroutine lặp). Cache reference (component, `WaitForSeconds`, buffer) từ `Awake()` hoặc `Start()`. Dùng Physics `NonAlloc`; cập nhật TextMeshPro bằng `SetText(format, value)` chỉ khi đổi; kiểm tra nhanh bằng `lint_unity_gc.py`.
- **Object Pooling Toàn Diện:** Mọi entity sinh-diệt liên tục (đạn, particle, popup text, item, vfx) đi qua `UnityEngine.Pool.ObjectPool<T>`; reset trạng thái khi trả pool; kill tween (`SetLink`/`DOKill`) khi object bị hủy.
- **Quản Lý Tài Nguyên Addressables:** Luôn ghép đôi `LoadAssetAsync` với `Release`/`ReleaseInstance`; không để trùng asset giữa `Resources/` và Addressables; build Addressables trước build player.
- **Ngân Sách Khung Hình & DrawCalls:** 60 fps (p95 $\le 16.7\text{ms}$); DrawCalls gameplay $\le 100-150$ (UI DrawCalls $\le 15$); đổi visual runtime qua `MaterialPropertyBlock`; nén texture ASTC, tắt Read/Write nếu không đọc pixel bằng code.
- **Thermal và vòng đời khi app ẩn:** `Application.targetFrameRate = 60` (puzzle hoặc máy yếu: 30). `OnApplicationPause(true)` ngắt coroutine, dừng âm thanh và hạ tải GPU; khôi phục khi `OnApplicationPause(false)`.

## 5. Màn Chơi Tất Định, Level Solver & Kiểm Thử (Determinism & Testing)
- **Sinh Màn Chơi Tất Định:** Generator nhận seed cố định (cùng seed $\to$ cùng màn); Level Validator độc lập chạy EditMode quét toàn bộ màn trước khi phát hành; kiểm tra bế tắc sau mỗi nước và luôn có lối thoát (gợi ý/undo/ô đệm), không để người chơi kẹt im lặng.
- **Level Solver Baseline & Bot Marathon:** Baseline par commit vào Git; Bot tự chơi PlayMode `unity-bot-marathon.sh 1-100` bắt buộc đạt $W = T$ (Won = Total) và $D = 0$ (Deadlocks = 0).
- **Kỷ Luật Kiểm Thử EditMode vs PlayMode:**
  - EditMode: Logic thuần, luật chơi, solver, level generator, tính điểm, save/load ($< 0.1\text{s}$ không cần mở scene).
  - PlayMode: MonoBehaviour, coroutine, tween, input mô phỏng, layout UI.
  - Paired Executable Oracle (RED $\to$ GREEN): Mọi bug fix bắt buộc thấy test ĐỎ trước khi sửa mã, test XANH sau khi sửa.
- **Chạy Unity Batchmode An Toàn:** Quét log bắt `error CS`/`Shader error in` (Unity có thể thoát 0 dù log lỗi); kết quả phải có `<test-case>` trong NUnit 3 XML; kiểm tra `Temp/UnityLockfile` và PID tiến trình Unity trước khi chạy; `-nographics` không dùng cho test cần đọc pixel/render.
- **Dữ Liệu Lưu (Save/Load) Idempotent:** Versioned save schema; hoàn thành màn idempotent (không cộng trùng thưởng); ghi save ở pause/focus và mốc kết thúc màn; CẤM `PlayerPrefs.DeleteAll()` trong test (tiêm mock storage).

## 6. Quy Trình 4 Pha, Asset Database & Nghiệm Thu (4-Phase Protocol & Gate)
- **Quy Trình Kỹ Nghệ 4 Phase Tuần Tự:**
  1. *Phase 1 (Architecture & Assembly):* Định vị `asmdef`, dependency injection, cấm singleton bừa bãi.
  2. *Phase 2 (Deterministic TDD):* Viết test EditMode cho core logic trước khi chạm `MonoBehaviour`.
  3. *Phase 3 (Visual Polish & Juice UI):* Render 3D baked props từ Blender, thêm Squash & Stretch, URP Post-Processing, tối ưu DrawCalls $\le 15$.
  4. *Phase 4 (Profiling & Hot Path Zero-GC):* Quét `lint_unity_gc.py`, chuyển sang Physics `NonAlloc` và kích hoạt Object Pooling.
- **Kỷ Luật Asset Database & Tệp `.meta`:** CẤM TUYỆT ĐỐI file rác/tài liệu (`.md`, `.txt`, `.tmp`) bên trong `Assets/`; luôn thêm/xóa/đổi tên đồng bộ cả asset và `.meta`; dọn sạch rác `InitTestScene*.unity` và `Assets/Temp/` trước commit.
- **An Toàn Dịch Vụ Nền Tảng (Ads/IAP/Consent):** Tầng `PlatformServices` (Mock/Live) — Editor và test luôn dùng Mock; thưởng rewarded ad chỉ trong callback đã xem xong; IAP xử lý idempotent theo transaction ID; Consent UMP/ATT trước khởi tạo SDK; không commit secret/key thật.
- **Đồng Bộ API Unity 6:** Dùng API hiện đại (`FindObjectsByType`, `linearVelocity`, URP RenderGraph); tránh các API đã deprecated trong Unity 6.
- **Cổng Nghiệm Thu Bằng Chứng Thị Giác (Visual Proof Gate):** Chụp ảnh Game View thật độ phân giải mục tiêu (1080×1920) sau thao tác; ảnh phải khác baseline; bắt lỗi material hồng magenta, vỡ layout UI hoặc tràn text.
