# QA #836 v1 — PR #1089 (head 7425ee4e + merge origin/main)

| Lệnh | Kết quả |
|---|---|
| `bash universal-agent-devkit/tests/gates/test_gate_since_renamed_weakened.sh` (gate của PR) | exit 0, 3/3 ✔ |
| cùng test, `post-fix-gate.py` lấy từ origin/main | ĐỎ: `flagged=no want yes, exit 0 want 2` (2 ca kiểm soát vẫn ✔) |
| `test_gate_renamed_test_edit.sh` | exit 0 |
| `test_gate_since_test_edit.sh` | exit 0 |
| `test_gate_since_new_test.sh` | exit 0 |
| `test_gate_since_trunk_merge.sh` | không tồn tại trên origin/main (PR #834 đã đóng) — không chạy được |
| `post-fix-gate.py --run-tests --scoped --brief --json` | exit 1: chỉ `REG-AUTO-CC-SWITCHER-MCP-01` FAIL; `REG-DK-ALL-KIT-01` PASS |

REG-AUTO-CC-SWITCHER-MCP-01: `cd mcp-servers/cc-switcher-mcp && npm test`, 133 pass / 1 fail
(`van ban trang thai: token het han chi cach mo claude…`, `/claude/` không khớp). PR không đụng
`mcp-servers/`, file giống hệt origin/main; test phụ thuộc trạng thái tài khoản cục bộ ⇒ đỏ trên base, không thuộc PR này.
