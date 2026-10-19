# QA #24 v1 (PR #131)
- AC1 renderReport dùng gateCtx: tests/report-lint-diff.test.js "#24 AC1" — XANH
- AC2 phanTichDiff giữ đường dẫn lib/web/db: "#24 AC2" — XANH
- Đột biến (src về origin/main): cả 2 test ĐỎ (pass 0, fail 2); khôi phục: XANH
- `npm test` (mcp-servers/antigravity-pm-mcp): 313/313 pass; `npm run lint` exit 0
- Gate: post-fix-gate --run-tests --full --force-full --diff origin/main: exit 0 (9/9 hồi quy)
- Gap Medium (không viết): tên file chứa " b/" hoặc đường dẫn có dấu nháy (diff --git "a/..") chưa được pin.
Không có AC giao diện: không chụp ảnh (cố ý).
