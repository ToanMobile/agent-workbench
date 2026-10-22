# QA #252 v1 — giới hạn WIP runner (không có UI, không ảnh)

Nhánh issue-252-wip-limit @ merge origin/main (e23921c2, #253), matrix gộp thêm-cuối.

| AC | Chứng cứ | Kết quả |
|---|---|---|
| 1. QA+Review chờ ≥ ngưỡng → không giao build, log lý do | test_runner_wip_limit.sh mục 2-3 (12>=12 giữ, 11 giao, k=1 ngưỡng 6, log "WIP 12 >= 12") | ✅ |
| 2. Số gate ≥ trần → không giao worker mới | mục 4-5 (build giữ ở 3>=3; worker QA thêm giữ ở 4>=3, log lý do; worker đầu vẫn chạy) | ✅ |
| 3. Gate --full exit 0 | post-fix-gate --run-tests --full --diff origin/main: PASS 55/55, exit 0 | ✅ |

Test: test_runner_wip_limit / build_workers / lane_workers / preflight_swept đều exit 0.
Mutant (đều bị test bắt đỏ, đã khôi phục, không commit): `-ge`→`-gt` ở WIP (3 ✖), bỏ gates_at_cap ở lane (2 ✖), bỏ gates_at_cap ở build (2 ✖).
Ảnh: không cần — script bash của runner, không lên màn hình.
