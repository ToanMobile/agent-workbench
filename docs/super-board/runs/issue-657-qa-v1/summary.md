# QA #657 v1 — procTag ps timeout

- RED (base agentapi.js, ca "ps cham 2 s"): FAIL, spawnSync ps-slow.sh ETIMEDOUT sau 1504 ms.
- GREEN (nhánh): node --test tests/proctag-timeout.test.js 3/3 pass.
- npm test (mcp-servers/antigravity-pm-mcp): exit 0, 324 pass / 0 fail.
- ps hỏng (/nonexistent/ps) vẫn ném: agy-round2.test.js các ca 256/447/765 pass.
- Trần ps dưới khoá: ca "so lan hoi ps bi chan tren" pass.
- AC4 (lượt --full đêm kế tiếp PASS) chưa kiểm được ở QA; chờ gate-full đêm.
