# QA #836 v1 — PR #1089 (head 7425ee4e + merge origin/main b8fe3cce)

| Lệnh | Kết quả |
|---|---|
| `bash universal-agent-devkit/tests/gates/test_gate_since_renamed_weakened.sh` (gate của PR) | exit 0, 3/3 ✔ |
| cùng test, `bin/post-fix-gate.py` lấy từ origin/main | ĐỎ exit 1: `flagged=no want yes` (2 ca kiểm soát vẫn ✔) |
| `test_gate_renamed_test_edit.sh` | exit 0 |
| `test_gate_since_test_edit.sh` | exit 0 |
| `test_gate_since_new_test.sh` | exit 0 |
| `test_gate_since_trunk_merge.sh` | không tồn tại trên origin/main (PR #834 đã đóng) — không chạy được |
| `post-fix-gate.py --run-tests --scoped --brief` | REJECT 3/4: chỉ `REG-AUTO-CC-SWITCHER-MCP-01` FAIL, `core-touched` post-fix-gate.py |

REG-AUTO-CC-SWITCHER-MCP-01: `cd mcp-servers/cc-switcher-mcp && npm test` → 133 pass / 1 fail
(`van ban trang thai: token het han chi cach mo claude…`, `/claude/` không khớp).
PR không đụng `mcp-servers/` (`git diff origin/main -- mcp-servers/cc-switcher-mcp` rỗng) và test đỏ y hệt
trên mã của origin/main: nó đọc trạng thái tài khoản cục bộ ⇒ đỏ trên base, không thuộc PR này.
