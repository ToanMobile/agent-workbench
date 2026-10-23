# QA #254 v2 — head d711fdd (sau rebase)
- Test mới `tests/super-board/test_builder_already_met_and_model_tier.sh`: RED 8/8 trên file của origin/main, GREEN 8/8 (exit 0) trên nhánh.
- Gate `post-fix-gate.py --run-tests --full --diff origin/main`: exit 0, hồi quy 54/54, lớp tĩnh đạt.
- AC1 (lối ra already-met): kiểm văn bản run.md + SKILL.md, chưa chạy builder thật.
- AC2 (--model theo model_tier): kiểm bằng hàm thật `claude_model_for_tier`, cả 2 lời gọi claude -p đều mang --model.
- AC3: gate --full exit 0.
