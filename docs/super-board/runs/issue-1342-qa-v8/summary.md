# QA #1342 v8 — head d2117370

Lệnh: bash universal-agent-devkit/tests/{gates/test_evidence_readonly_turn,gates/test_evidence_gate_linear,installer/test_platform_rules,installer/test_install_alias,worktree_git/test_relink_alias,worktree_git/test_relink}.sh
Exit: cả 6 file = 0.
Gate: post-fix-gate.py --run-tests --scoped --brief --json qua super-board-qa-exit2.sh = `pass` (exit 0).
AC1–AC4: có `## Convergence`, lớp Pre-existing, dòng Convergence ở run.md; SKILL.md không đổi so với main, 19850 ký tự.
AC5–AC7: 4 alias đã gỡ, test alias/relink xanh; R6 (nháy, `\`, khai triển) bị chặn, ca đọc vẫn qua.
AC8: CHECKLIST không còn dòng REPORTED; instincts-index khớp (chỉ khác mẫu INSTINCT-XXX).
Log thô: /tmp/qa-agent-workbench-1342-*.log (ngoài nhánh).
