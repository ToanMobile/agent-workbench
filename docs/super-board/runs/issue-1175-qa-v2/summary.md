# QA #1175 v2 — head 0aa827c3 + main 8fa63472 (merge 722176ca)

| Lệnh | Kết quả |
|---|---|
| `bash tests/super-board/test_github_read_malformed_halt.sh` với script của main | rc=1 (ĐỎ, FAIL 12) |
| cùng test với script của PR | rc=0 (XANH) |
| `bash tests/super-board/test_github_read_foreign_halt.sh` | rc=0 (XANH) |
| `post-fix-gate.py --run-tests --scoped --brief --json` qua `super-board-qa-exit2.sh` | `pass` (rc=0) |

AC1 ✅ ĐỎ→XANH · AC2 ✅ fail-closed giữ nguyên · AC3 ⏳ chỉ đo được sau merge.
Log thô giữ ngoài nhánh: /tmp/qa-agent-workbench-1175-*.log
