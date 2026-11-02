# QA #476 v2 (PR #621, head fb6d5040)
- Lệnh: bash universal-agent-devkit/tests/gates/test_gate_shadow_map.sh → exit 0, 5/5 case ✔ (trace_map tự sinh, không đọc watch_files; shadow chỉ ghi log, ran_suites không đổi)
- RED: origin/main không có `trace_map` nên test ĐỎ trên base (v1).
- Gate scoped trên head: đỏ ở REG-DK-ALL-GATES-01 do 3 test: test_gate_git_batching (A13), test_gate_ignored_listing_once, test_gate_impacted_cache (h) — "no reuse on unchanged content".
- Baseline origin/main (c1b8e1cc): cả 3 test đỏ y hệt → đỏ có sẵn trên base, không do PR (diff chỉ thêm opt-in shadow). Cần thẻ riêng.
- AC1/AC2 đã tách sang #667; AC3 ✅.
- Chưa có biên nhận gate exit 0 cho head này; merge-queue verify cây đã merge.
