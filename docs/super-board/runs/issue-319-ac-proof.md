# #319 · bằng chứng AC cho PR #388 (đã merge, acc8d7e7)

PR #388 đã merge code của thẻ nhưng merge gate giữ thẻ ở `ac-open` vì chưa có bằng chứng từng dòng AC.
PR này không đổi code: nó chạy lại từng test trên `origin/main` (d8f06fd2) và đột biến file production về trước #388
(`git show 4c7a3246^:<file>`), để thấy ĐỎ, rồi trả lại bản HEAD (cây sạch).

## GREEN trên origin/main

| Test | Kết quả |
|---|---|
| `universal-agent-devkit/tests/gates/test_gate_auto_tree_receipt.sh` | rc=0, 5 ca |
| `universal-agent-devkit/tests/gates/test_gate_diff_merge_base.sh` | rc=0, 3 ca |
| `universal-agent-devkit/tests/verification/test_evidence_runners.sh` | rc=0 |
| `tests/super-board/test_codex_wave_workers.sh` | rc=0 |
| `tests/super-board/test_merge_gate_ac_check.sh` | rc=0, ca A..N |
| `tests/super-board/test_runner_reconcile_ac_open.sh` | rc=0, 7 ca |

## ĐỎ khi bỏ bản sửa

| Đột biến | Test | Kết quả |
|---|---|---|
| `post-fix-gate.py` về trước #388 | `test_gate_auto_tree_receipt.sh` | rc=1 `no receipt … after a clean --full PASS` |
| `post-fix-gate.py` về trước #388 | `test_gate_diff_merge_base.sh` | rc=1, 1 ca ĐỎ |
| `hooks/test_evidence_gate.sh` về trước #388 | `test_evidence_runners.sh` | rc=1 |
| `super-board-merge-gate.sh` về trước #388 | `test_merge_gate_ac_check.sh` | rc=1, ĐỎ ca L (pr_title lỗi), M (bỏ tick lúc verify), N (body nén lúc verify) |
| `super-board-codex-wave.sh:269` điều kiện `re.search(ac-open: #N)` thành `True` | `test_codex_wave_workers.sh` | ĐỎ ca "thiếu dòng" và "sai số thẻ" |
| cùng dòng thành `False` | `test_codex_wave_workers.sh` | ĐỎ ca "ac-open: #12 → advanced" |
| `super-board-run.sh` về trước #388 | `test_runner_reconcile_ac_open.sh`, `test_codex_wave_workers.sh` | vẫn XANH (ca ac-open của wave nằm ở `codex-wave.sh`, không ở `run.sh`; reconcile chỉ cần giữ XANH) |

## run.md

`run.md:387` (bước 4c) không còn `--record` bằng tay; `post-fix-gate.py --full --diff origin/<base>` exit 0 trên cây sạch tự ghi biên nhận qua `super-board-verify-cmd.sh --mark`.
