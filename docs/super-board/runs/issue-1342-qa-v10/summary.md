# QA v10 — #1342 @ e86f37bb (đã gộp origin/main, Already up to date)
- test_evidence_readonly_turn.sh → exit 0 (ALL OK)
- test_evidence_gate_linear.sh → exit 0
- test_platform_rules.sh → exit 0
- AC1–AC3: review-output.md có `## Convergence` (dòng 88), review-flow.md có lớp Pre-existing, run.md có dòng Convergence.
- AC4: super-review/SKILL.md không đổi so với main, 19850 ký tự < 20000.
- AC8: CHECKLIST `REPORTED 0`; instincts.md 106 mục, instincts-index 105 dòng (1 dòng mẫu INSTINCT-XXX).
- R8: probe 30 lệnh git qua `_read_segment`. Các dạng ghi/tạo nhánh/chạy chương trình đều bị chặn (bare word sau `branch`, -m/-D/-c/-u, remote add/set-url/prune/show, worktree add, --output/--out, -O, --no-index, --textconv). Các dạng đọc (-vv, --show-current, remote -v, worktree list, status, log, rev-parse, describe, blame, check-ignore) vẫn qua.
