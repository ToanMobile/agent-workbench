# QA v2 — issue #729 (PR #1031, đầu 26c24f5d)

- Lệnh: `bash universal-agent-devkit/tests/gates/test_gate_manual_suite.sh` — exit 0, 6/6 XANH (ca 6 `--force-full` bỏ qua suite manual nay XANH; v1 ĐỎ).
- Gate: `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --scoped --brief --json | super-board-qa-exit2.sh` → `pass`.
- Đã merge origin/main (đã có trong đầu PR, "Already up to date").
- AC 1, 2, 4 (phần manual): đạt. AC gộp còn lại (verify theo diff, #803, #763, ruleset #746) PR ghi rõ chưa làm.
- Log thô: /tmp/qa-agent-workbench-729-manual-suite.log (không commit).
