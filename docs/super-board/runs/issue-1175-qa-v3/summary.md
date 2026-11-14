# QA #1175 v3 — head c09c774a (đã chứa origin/main d12d1afe)

| Lệnh | Kết quả |
|---|---|
| `bash tests/super-board/test_github_read_malformed_halt.sh` với script của main | rc=1 (ĐỎ) |
| cùng test với script của PR | rc=0 (XANH) |
| `bash tests/super-board/test_github_read_foreign_halt.sh` | rc=0 (XANH) |
| `bash tests/super-board/test_github_read.sh` | rc=0 (XANH) |
| `post-fix-gate.py --run-tests --scoped --brief --json` qua `super-board-qa-exit2.sh` | xem report |

AC1 ✅ ĐỎ→XANH · AC2 ✅ fail-closed giữ nguyên · AC3 ⏳ đo sau merge (orchestrator, luật 20).
Log thô giữ ngoài nhánh: /tmp/qa-agent-workbench-1175-*.log
