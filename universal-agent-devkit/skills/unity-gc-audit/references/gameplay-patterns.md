# Mẫu thiết kế gameplay (Unity) — tham chiếu nạp khi cần

Phạm vi: chỉ profile `game` (skill `unity-gc-audit` bị loại khỏi mọi profile ứng dụng và đầu xe). Công việc ứng dụng không đọc file này.

Tóm lược bằng lời của DevKit từ các nguồn dưới đây; rule ngắn nằm ở `profiles/game/rules/game-rules.md` §7. Ngưỡng ghi "DevKit" là quy ước của kit, không trích từ nguồn.

Nguồn đã đọc:
- `munificent/game-programming-patterns` (Bob Nystrom, 19 chương trong `book/`).
- Họ repo Unity của `adammyhre` (chỉ tham khảo tên và README, chưa đọc sâu; chưa có rule nào dựa trực tiếp vào đó): URL `adammyhre/Unity-Design-Patterns` trong yêu cầu gốc trả 404 (kiểm 2026-10-12). Repo có thật cùng tác giả: Unity-Service-Locator (scope GameObject/Scene/Global), Unity-Event-Bus (`EventBus<T>` tĩnh), Unity-Audio-Pooling, Unity-Hierarchical-StateMachine, Unity-Improved-Timers, Unity-Dependency-Injection-Lite, Unity-Behaviour-Trees.
- `roboryantron/Unite2017` (mã mẫu của bài nói Ryan Hipple) và `DanielEverland/ScriptableObject-Architecture` (thư viện dựng theo bài nói). URL `Ryan-Hipp/ScriptableObject-Architecture` trong yêu cầu gốc trả 404.

## Bảng chọn nhanh: dấu hiệu → mẫu → bẫy

| Dấu hiệu trong code | Mẫu | Bẫy chính |
|:---|:---|:---|
| Nhiều `if/else` theo cờ bool trạng thái | State (FSM; pushdown cho lớp chồng; hierarchical cho AI phức tạp) | FSM bị giới hạn; AI phức tạp cần phân cấp hoặc behavior tree |
| Input gắn cứng vào hành động; cần undo/replay | Command (`Execute` + `Undo`) | Undo cần thao tác thứ hai; state bắt trong command phải nhìn thấy được |
| Nhiều hệ thống cần biết một sự kiện | Observer / Event Bus | Quên huỷ đăng ký → UI chết vẫn nhận sự kiện (lapsed listener); khó theo dõi luồng khi đọc code |
| Cần gửi thông điệp nhưng xử lý muộn hơn | Event Queue | Queue chung là global; world đã đổi lúc xử lý; vòng phản hồi nếu gửi trong handler |
| Cần một dịch vụ toàn cục (audio, save) | Truyền tham chiếu; Service Locator khi bắt buộc | Phụ thuộc ẩn tới runtime; lookup có thể hỏng (dùng null-service); Singleton gộp "một instance" với "truy cập toàn cục" |
| Quá nhiều object cùng loại | Flyweight / Type Object (SO) | Con trỏ gián tiếp có thể cache-miss: đo trước; phải tự nối instance với type hợp lệ |
| Lớp chạm nhiều miền (input, vật lý, hiển thị) | Component | Thêm wiring và gián tiếp; đừng over-engineer |
| Lớp cha phình thành "nồi hầm" | Tách Subclass Sandbox thành component | Brittle base class |
| Tạo/huỷ liên tục cùng kích thước | Object Pool | Chọn cỡ pool; chính sách khi cạn (chặn, bỏ qua, huỷ cũ nhất, nở thêm); xoá tham chiếu khi trả pool |
| Giá trị dẫn xuất tính lại thường xuyên | Dirty Flag | Phải đặt cờ ở MỌI đường ghi dữ liệu gốc; công việc dồn có thể thành khựng |
| Đọc trạng thái giữa lúc đang cập nhật tuần tự | Double Buffer | Swap phải nguyên tử và rẻ; tốn gấp đôi bộ nhớ; buffer chứa dữ liệu cách 2 frame |
| Truy vấn "gần đây" O(N²) | Spatial Partition (lưới phẳng → quadtree) | Vô nghĩa khi N nhỏ; object di chuyển phải xếp lại ô |
| Hành vi cần nằm trong dữ liệu, sandbox | Bytecode/VM | Chậm hơn native, ngôn ngữ nhỏ phình to, cần tool soạn thảo: chỉ dùng khi thật cần |

## Game Loop và cập nhật theo frame
- Vòng cơ bản: cộng `elapsed` vào `lag`; trong khi `lag >= step` thì `update()` và trừ; `render(lag/step)` nội suy phần dư. Bước cố định cho mô phỏng, biến thiên cho render.
- Bước phải lớn hơn thời gian một `update()` trên máy yếu nhất, nếu không sẽ không bao giờ bắt kịp; giới hạn số vòng bù (DevKit: ≤ 5 mỗi frame).
- Time step biến thiên làm vật lý/mạng không tất định; Update Method khó với logic cần lưu trạng thái giữa các frame; thêm/xoá object khi đang duyệt là nguy hiểm.
- Di động: đặt `Application.targetFrameRate` (30 hoặc 60) để tiết kiệm pin, không busy-wait.

## Data Locality (liên quan Zero-GC)
- Chỉ tối ưu bố cục dữ liệu sau khi Profiler chứng minh cache miss. Mảng liền kề theo thứ tự xử lý; tách dữ liệu nóng/lạnh (hot/cold). Tác giả gọi đây là "black art", vì vậy phải đo trước/sau.

## ScriptableObject Architecture (Hipple, Unite 2017)
- Thành phần trong mã mẫu: `FloatVariable` (Value/SetValue/ApplyChange), `FloatReference` (hằng số hoặc biến SO), `GameEvent` (`Raise` duyệt listener ngược; lý do "để listener tự huỷ đăng ký giữa chừng" là suy luận của DevKit), `GameEventListener` (đăng ký `OnEnable`, huỷ `OnDisable`, gọi `UnityEvent`), `RuntimeSet<T>` (danh sách không trùng, thay `Find`/singleton).
- Thư viện của DanielEverland bổ sung: biến có clamp, sự kiện có kiểu, collection, công cụ debug sự kiện bằng stack trace.
- Hệ quả thiết kế: scene/prefab nói chuyện qua asset SO nên không còn phụ thuộc vòng giữa scene; prefab kéo vào scene rỗng vẫn chạy.
- Bẫy thấy trong mã nguồn: biến read-only chỉ cảnh báo rồi bỏ qua `Set`; `Raise` chỉ bắn khi giá trị đổi; `OnValidate` có thể set lại giá trị; ví dụ `ResetHP` phải đặt tay, nếu không SO giữ giá trị cũ.
- CHƯA XÁC MINH trong nguồn: hành vi SO giữ giá trị giữa các lần Play trong Editor và khi tắt Domain Reload → rule của DevKit buộc reset lúc bắt đầu phiên và có test với Domain Reload tắt.
- Quy ước DevKit: mỗi biến SO có đúng một nơi ghi; SO không phải save data.

## Kiểm tra bằng máy (gợi ý, chạy được trong CI)
- Cặp đăng ký/huỷ: mỗi file có `+=`/`Register`/`AddListener` phải có `-=`/`Unregister`/`RemoveListener` tương ứng (`grep` theo file).
- Cấm `FindObjectOfType` trong prefab runtime; cấm lookup Service Locator trong `Update`.
- Test từng đường ghi dữ liệu gốc đặt được dirty flag; test xếp lại ô khi object di chuyển với Spatial Partition.
