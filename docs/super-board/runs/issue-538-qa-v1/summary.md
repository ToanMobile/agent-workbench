# QA #538 v1

- Lệnh: `bash tests/super-board/test_runner_claim_loop.sh` (nhánh + merge origin/main): exit 0, tất cả PASS, gồm 4d (#538) cả hai ca.
- RED: runner cũ của main + test 4d: ✖ "result followed by task_summary was counted as an early death (#538)" (1 failed).
- Gate: `post-fix-gate.py --run-tests --brief` exit 0, 31/31.
- Ghi chú: test M của test_worker_death_record.sh đỏ sẵn trên main (Builder đã nêu), không thuộc PR này.
