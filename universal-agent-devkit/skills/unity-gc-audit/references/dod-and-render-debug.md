# Data-Oriented Design (từ EnTT) và gỡ lỗi render (RenderDoc)

Phạm vi: chỉ profile `game`. Phần RenderDoc cho Vulkan/GLES chỉ tham khảo chéo được khi ứng dụng Android tự viết renderer; ứng dụng Compose thông thường dùng công cụ của skill `android-real-device-qa`.

Nguồn: `skypjack/entt` (README + wiki), `baldurk/renderdoc` (README + renderdoc.org/docs, tài liệu Unity RenderDocIntegration), `ellisonleao/magictools`. Mục "[Dịch]" là suy diễn của DevKit sang Unity C#, không phải lời của nguồn. EnTT không công bố số benchmark: không trích số.

## 1. Cơ chế EnTT đáng học
- Mỗi loại component có một pool sparse-set riêng; tính năng đắt (reactive, group, ổn định con trỏ) là tuỳ chọn "dùng mới trả tiền".
- `entt::entity` bọc `uint32_t`; huỷ entity tăng version nên handle cũ không còn `valid()`; `null`/`tombstone` luôn không hợp lệ.
- Xoá component là swap-and-pop: giữ pool liền kề nhưng làm tham chiếu cũ mất hiệu lực (trừ khi bật `in_place_delete`).
- Kiểu rỗng (tag) chỉ lưu tư cách thành viên, không tốn dữ liệu. View một loại duyệt thẳng mảng đóng gói; view nhiều loại duyệt pool nhỏ nhất rồi kiểm các pool còn lại.
- Group sở hữu đầy đủ giữ các component liền kề và cùng thứ tự: nhanh nhất; group không sở hữu tốn thêm bộ nhớ, wiki khuyên tránh nếu được.
- Khi đang duyệt: tạo mới an toàn, xoá/gỡ component của chính entity hiện tại an toàn, động vào component của entity khác là hành vi không xác định. Cách xử lý wiki nêu: gom lại rồi xử lý sau vòng lặp, hoặc gắn tag rồi dọn ở pass thứ hai.
- Registry/view/group không thread-safe; tập component rời nhau có thể chạy ở các thread khác nhau.
- Signal phải ngắt kết nối trước khi listener chết (`scoped_connection` tự ngắt); dispatcher `trigger` là tức thì (thứ tự không đảm bảo), `enqueue` + `update()` là trì hoãn.

## 2. [Dịch] Quy tắc Unity C# di động
1. Dữ liệu nóng là struct blittable trong mảng/`NativeArray`/`IComponentData`; không tham chiếu managed, không `class` per-entity, không LINQ/boxing trong vòng lặp. Kiểm: grep/analyzer cấm `class`-field trong component data.
2. Không cấp phát mỗi frame: Profiler `GC.Alloc == 0` trong test PlayMode ~300 frame.
3. Handle là (index, version): kiểm `Exists`/version trước khi dùng, không cache index qua frame. Test: dùng-sau-khi-huỷ trả false, không trả dữ liệu cũ.
4. Thay đổi cấu trúc đi qua `EntityCommandBuffer` cuối frame, không gọi `EntityManager.*` cấu trúc trong vòng query. Huỷ = gắn tag, system dọn ở pass sau (test: số entity ở frame N+1).
5. Tag là component kích thước 0 / enableable thay cho `bool` field khi dùng để lọc query.
6. Truy vấn bắt đầu từ component hiếm nhất; field đọc cùng nhau đặt cùng struct/archetype.
7. Job khai read-only/read-write; hai job ghi cùng loại component không chạy song song khi thiếu dependency.
8. Event: một điểm flush mỗi frame; mỗi subscribe có unsubscribe lúc teardown (test: số listener về 0 sau khi unload scene).
9. Chỉ chuyển sang DOD khi Profiler chỉ ra hot path; giữ OOP cho phần còn lại (Lazy Senior).

## 3. RenderDoc — phạm vi hỗ trợ (README)
- Có: Vulkan (Windows/Linux/Android), OpenGL ES 2.0–3.2 (Windows/Linux/Android), OpenGL 3.2–4.6 Core (Windows/Linux), D3D11/D3D12 (Windows).
- KHÔNG có Metal. Trên iOS dùng Xcode GPU Frame Capture; ghi rõ công cụ đã dùng thay vì tuyên bố có capture RenderDoc.
- Lưu ý: capture Vulkan không mang qua hãng GPU khác; replay có thể không tái hiện lỗi phụ thuộc driver/timing.

## 4. Quy trình triage lỗi render
1. Xác nhận API được hỗ trợ (mục 3).
2. Android: Development Build, `adb devices` thấy máy, tắt tích hợp ADB của Android Studio, chọn thiết bị ở remote-context (góc dưới trái), Browse gói app, tăng Max Connection Timeout nếu app khởi động chậm, launch rồi capture frame lỗi. Trỏ Android SDK path của RenderDoc vào SDK của Unity để tránh lệch phiên bản ADB.
3. Lỗi chỉ ở Editor: chuột phải tab Game/Scene → Load RenderDoc (lưu việc trước, vì thiết bị đồ hoạ bị nạp lại), bấm nút capture để chụp frame kế tiếp. D3D11: thêm `#pragma enable_debug_symbols` khi cần debug shader, gỡ trước release.
4. Event Browser: lọc theo action, mở các marker, bisect EID tới khi lỗi xuất hiện lần đầu ở Texture Viewer.
5. Texture Viewer trên render target: kiểm kênh RGBA, dải giá trị/Autofit (khung đen, HDR), overlay NaN/Inf/-ve.
6. Chọn pixel sai → Pixel History: dòng đỏ là fragment thất bại một phép thử, xanh là đã ghi; so sánh output shader từng fragment.
7. Overlay trên draw nghi ngờ: Wireframe, Depth/Stencil Test, Backface Cull, Viewport/Scissor, Highlight Drawcall.
8. Pipeline State tại EID đó: binding rỗng (đỏ), sai mip/format cast, render target, stage shader. Xuất HTML hai EID tốt/xấu để so sánh.
9. Mesh Viewer: so VS Input với VS Output để tìm vị trí suy biến.
10. Debug shader chỉ có với D3D11/D3D12/Vulkan (không GLES); Vulkan cần `NonSemantic.Shader.DebugInfo.100` để xem mã nguồn; có "Run to NaN/Inf". Với GLES chỉ kiểm constant và output.
11. Góc hiệu năng: overlay Quad Overdraw (Pass), Triangle Size, cột GPU Duration của Event Browser; đối chiếu ngân sách DrawCalls ở `game-rules.md` §4.
12. Bằng chứng bàn giao: capture (`.rdc`, không đặt trong `Assets/`) hoặc ảnh chụp kèm EID, toạ độ pixel và kết quả Pixel History; chụp lại sau khi sửa để so sánh.

## 5. magictools (đã đọc, không rút ra rule riêng)
List không có mục profiling/debug, không có Unity trong mục engine và không công bố tiêu chí duyệt; công cụ ngoài vẫn chọn theo thang Lazy Senior (core §4) và ghi giấy phép như `DESIGN.md` §7.
