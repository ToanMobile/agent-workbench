# QA v9 — #1342 @ 92a160c2
- test_evidence_readonly_turn.sh: exit 0 (ALL OK)
- test_evidence_gate_linear.sh: exit 0; test_platform_rules.sh: exit 0
- Probe 26 dạng ghi/chuyển hướng (>&1o, >& o, >|o, 3>o, &>o, >/dev/null >o, <>o, ...): 26/26 bị chặn (rc 2)
- post-fix-gate --run-tests --scoped qua super-board-qa-exit2.sh: pass (exit 0)
