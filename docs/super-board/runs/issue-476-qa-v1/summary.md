# QA #476 v1
- Lệnh: bash universal-agent-devkit/tests/gates/test_gate_shadow_map.sh → exit 0, 5/5 case ✔ (map REG-A có src/a.py+tests/t1.py; không lấy từ watch_files; shadow_select đúng; gate thật ghi shadow_skip, shadow_miss=[], ran_suites không đổi)
- RED: origin/main không có `trace_map` (grep = 0) nên test ĐỎ trên base.
- Gate: post-fix-gate.py --run-tests --brief → exit 0, 20/20 (sau merge origin/main, đã up to date)
- AC3 ✅ (map tự sinh). AC1, AC2 ❌ chưa chứng minh: shadow mặc định tắt, runs.jsonl chưa có lượt DEVKIT_SHADOW_MAP=1 thật.
