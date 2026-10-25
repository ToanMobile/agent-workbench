# #319 · QA vòng 1 (nhánh issue-319-ac-proof, 7c815a92, đã gộp origin/main: up to date)

## XANH — chạy lại độc lập trên cây QA (rc=0 cả 6)
- universal-agent-devkit/tests/gates/test_gate_auto_tree_receipt.sh (5 ca)
- universal-agent-devkit/tests/gates/test_gate_diff_merge_base.sh (3 ca)
- universal-agent-devkit/tests/verification/test_evidence_runners.sh
- tests/super-board/test_codex_wave_workers.sh (3 ca ac-open)
- tests/super-board/test_merge_gate_ac_check.sh (ca K,F,L,M,N…)
- tests/super-board/test_runner_reconcile_ac_open.sh

## ĐỎ — QA tự đột biến (`git show 4c7a3246^:<file>`), rồi trả bản HEAD (cây sạch)
- post-fix-gate.py trước #388 → test_gate_auto_tree_receipt rc=1 "no receipt … after a clean --full PASS"
- post-fix-gate.py trước #388 → test_gate_diff_merge_base rc=1
- super-board-merge-gate.sh trước #388 → test_merge_gate_ac_check rc=1, ĐỎ ca L, M, N ("3 FAILED")

## Gate
`post-fix-gate.py --run-tests --full --diff origin/main --brief` → exit 0, 110/110, 90 s (cache).

## Chưa chứng minh
AC "[gate] Đo trên một PR thật: chỉ một lần --full": cần dòng "verify skipped" của merge gate trên PR này; QA không tự giả lập.
Thẻ giữ `ac-open` cho tới khi merge gate in dòng đó.
