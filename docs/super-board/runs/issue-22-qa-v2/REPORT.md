# QA #22 · v2 · đạt (AC1, AC2)

- PR #39 · head `6a73935` · branch `issue-22-pm-mcp-commitpolicy-forbid-gate` · base `main`
- AC không có giao diện (MCP server): không chụp màn hình, bằng chứng là log test và kết quả mutation.
- Vòng này: card có nhãn `loop:rebuild-1`, chưa có thread `[qa]` nào mở; các thread còn lại là author-note của PR. Đây là lượt QA v2 cho head `6a73935` (vòng sửa AC2 sau v1).

## Kết quả theo AC

| AC | Kết quả | Bằng chứng |
|---|---|---|
| AC1 — worker `git commit` khi `commitPolicy: forbid` bị gate từ chối | ✅ đạt | `node --test tests/`: 310/310 PASS trên `6a73935`. Các test `#22 AC1` (forbid/allow, commit khi khai và không khai, đổi policy sau khi tạo task, commit cứu hộ của PM) đều xanh. |
| AC2 — sửa file `forbiddenPaths` dù commit hay không đều bị chặn nghiệm thu | ✅ đạt | Test `#22 AC2` (file CẤM đổi sau khi giao, không khai, sửa hoặc `git mv`, forbid/allow, có commit hay không) xanh. Mutation bên dưới chứng minh test phân biệt được. |

## Mutation (bằng chứng test phân biệt được)

Cách làm: sao chép `mcp-servers/antigravity-pm-mcp` sang thư mục scratch, mỗi lần gỡ một guard, chạy `node --test tests/gate.test.js tests/cam-dung-theo-task.test.js` (nền 34/34 PASS). Scratch được khôi phục và khớp với worktree.

| Mutant | Guard bị gỡ | Kết quả |
|---|---|---|
| M1 | `commitTheoTask` luôn trả `chan: []` (tắt chặn commit forbid) | RED, nhiều test `#22 AC1` đỏ |
| M2 | Bỏ `ctx.camSauGiao` khỏi `chanCam` (tắt chặn file CẤM đổi sau giao) | RED, 2 test (pass 32, fail 2) |
| M3 | Tắt khối kiểm `committedFiles` của forbid trong `gate()` | RED, nhiều test `#22 AC1` đỏ |
| M4 | Bỏ bước loại `baselineDirty` trong `pm_plan` | RED, 1 test (file CẤM đã bẩn trước khi giao => chỉ CẢNH BÁO) |

## Ghi chú

- Probe `probe-ac-pm-accept.mjs` của lượt trước bị loại khỏi cây: harness báo "promise pending" và không khẳng định gì. Phủ AC nằm trong bộ `tests/` (đường lệnh mà Reviewer chạy lại), đã kiểm bằng mutation ở trên.
- Log thô của lượt này (`v2-gate.log`, `v2-mutation.log`) bị `.gitignore` chặn, nên không dẫn link được; toàn bộ kết quả đã nằm trong báo cáo này.
- Lệnh gate chạy trên cây sạch trả exit 3 (không có gì để kiểm), vì vậy gate được chạy trên chính báo cáo này.
