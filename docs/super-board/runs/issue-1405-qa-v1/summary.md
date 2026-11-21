# QA v1 — #1405 / PR #1411 (`03af1e29`)

- Nhánh: `issue-1405-antigravity-pm-discover` · base: `main` (đã merge `origin/main`: Already up to date)
- Bảo mật (`pr-security-review`): 0 lỗ hổng mức High/Medium (confidence >= 8)
- Test-gap check: 0 High gap cần bổ sung (AC1/AC2 đã phủ đủ cả đường mới/cũ, security boundary, `agy` fallback, `unset` env ở wrapper)

## Kết quả chạy test
- `discover.test.js` trên `origin/main` (RED oracle): exit `1` · 2 pass, 3 fail (`AntigravityUnavailable` & `ANTIGRAVITY_AGENTAPI_EXE=agy`)
- `node --test mcp-servers/antigravity-pm-mcp/tests/discover.test.js`: exit `0` · 5/5 pass
- `bash tests/super-board/test_antigravity_probe_parity_1405.sh`: exit `0` · 5/5 pass
- `npm run lint && npm test` (toàn bộ `antigravity-pm-mcp`, bản sao tạm với `node_modules`): exit `0` · 380/380 pass, 0 fail, 0 skipped
- `bash tests/super-board/test_worker_wrap_term.sh`: exit `0` · 4/4 pass
- `bash tests/super-board/test_runner_review_antigravity_1390.sh`: exit `0` · PASS
- `bash tests/super-board/test_runner_review_antigravity_1390_qa_gaps.sh`: exit `0` · PASS
- `bash tests/super-board/test_reviewer_antigravity_audit_contract.sh`: exit `0` · PASS

## Nghiệm thu thật
- `node bin/antigravity-pm-mcp.js --doctor` (trên máy thật, IDE đang mở pid 78760): exit `0` · `Antigravity language server: noi duoc tai 127.0.0.1:63286 (nguon: cache)`
- Lượt review `agy` thật ở `GeelyEx2`: chưa nghiệm thu thật — chưa merge nên `main` chưa cập nhật `antigravity-pm-mcp` (cấu hình MCP đọc từ `/Volumes/Data/Toan/agent-workbench/mcp-servers/antigravity-pm-mcp/bin/antigravity-pm-mcp.js`); sẽ đo log worker review `GeelyEx2` sau khi PR vào `main`.

## Bằng chứng AC
- AC1: PASS (`discover.test.js`: RED trên `origin/main` exit `1`, GREEN trên PR exit `0` 5/5)
- AC2: PASS (`test_antigravity_probe_parity_1405.sh`: exit `0` 5/5)
- AC3: một phần (`--doctor` thật exit `0`; phần lượt review `agy` ở `GeelyEx2` chờ sau merge để thẻ giữ `ac-open`)
