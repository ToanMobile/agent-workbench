# DevKit AST Linters & Static Analysis

Bộ công cụ phân tích tĩnh AST và kiểm tra chất lượng mã nguồn chuyên sâu:

- `assertion_lint.py`: Kiểm tra tính hợp lệ của assertion trong các file test.
- `hardware_source_lint.py`: Kiểm tra các mẫu mã nguồn tương tác phần cứng, CAN bus, ngoại vi.
- `lint_compose_stability.py`: Kiểm tra tính ổn định recomposition trong Jetpack Compose.
- `lint_unity_gc.py`: Phát hiện GC allocation trong vòng lặp game (`Update`, `FixedUpdate`, Coroutines).
- `wiring_pin.py`: Android — `scan` tìm `internal object` mới trích ra (cùng file hoặc cạnh một `View`) mà không test nào nhắc tới cả `View` lẫn object đó, và in pin test source-text cho từng cặp (View, object) (View còn gọi object, không còn nhánh cũ) kèm đúng lệnh `verify` chạy từ gốc repo; `UNPINNABLE` khi không dòng bị xoá nào đủ làm mốc; `verify` đọc lại pin và chấm nó trên source View, thoát 2 với pin nó không đọc hết được (regex, không phải parser Kotlin; không cần kotlinc).
