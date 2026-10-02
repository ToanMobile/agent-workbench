# DevKit AST Linters & Static Analysis

Bộ công cụ phân tích tĩnh AST và kiểm tra chất lượng mã nguồn chuyên sâu:

- `assertion_lint.py`: Kiểm tra tính hợp lệ của assertion trong các file test.
- `hardware_source_lint.py`: Kiểm tra các mẫu mã nguồn tương tác phần cứng, CAN bus, ngoại vi.
- `lint_compose_stability.py`: Kiểm tra tính ổn định recomposition trong Jetpack Compose.
- `lint_unity_gc.py`: Phát hiện GC allocation trong vòng lặp game (`Update`, `FixedUpdate`, Coroutines).
