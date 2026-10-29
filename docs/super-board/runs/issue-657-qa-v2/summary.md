# QA #657 v2 — PR #673 @ 5be8e1df (đã gộp origin/main c1b8e1cc)

- Lệnh: `cd mcp-servers/antigravity-pm-mcp && npm test` → exit 0, 325 pass / 0 fail.
- ĐỎ→XANH: `node --test tests/proctag-timeout.test.js` với agentapi.js của origin/main → 3 pass, 1 fail
  (`psTimeoutMs: so thuc bi cat ... 1500.5 !== 1500`); với agentapi.js của PR → 4 pass, 0 fail.
- AC1–AC3: ca ps chậm 2 s vẫn xanh (proctag-timeout.test.js), ps hỏng vẫn ném lỗi, ca trần ps dưới khoá pass (nằm trong 325/325).
- AC4: chỉ kiểm được ở lượt --full 00:00 kế tiếp trên main.
