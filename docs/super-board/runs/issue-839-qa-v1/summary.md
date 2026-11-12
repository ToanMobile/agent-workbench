# QA #839 — PR #1093, head f9031b1b (đã gộp origin/main, "Already up to date")

| Lệnh | Kết quả |
|---|---|
| `bash universal-agent-devkit/tests/gates/test_gate_since_trunk_merge.sh` | exit 0, 31 ca xanh (ca 1, 2, 11 exit 0; ca 13 exit 1 + lazy-placeholder) |
| `test_gate_since_new_test.sh` | exit 0 |
| `test_gate_since_test_edit.sh` | exit 0 |
| RED: cùng test, `universal-agent-devkit` của `origin/main` (scratch `git archive`) | exit 1, "13 FAILED" |
| `post-fix-gate.py --run-tests --scoped --brief` | exit 1, 3/4: chỉ `REG-AUTO-CC-SWITCHER-MCP-01` đỏ |

`REG-AUTO-CC-SWITCHER-MCP-01` (`mcp-servers/cc-switcher-mcp`, "token het han chi cach mo claude"):
đọc trạng thái tài khoản thật. PR không đổi file nào ở đó (diff: `post-fix-gate.py` và
`test_gate_since_trunk_merge.sh`). Chạy lại trên `git archive origin/main` của thư mục đó:
đỏ y hệt ⇒ đỏ trên base, không thuộc PR này.
Gate chạm gate-core (`core-touched`): cần audit chéo Antigravity trước merge.
