# QA #22 · v1 · ❌ không đạt

- PR #39 · head `98b6239` · base `22f5c75` (origin/main)
- AC không có giao diện (MCP server): không chụp màn hình, bằng chứng là log test.
- Kiểm tra lỗ hổng test: một sub-agent chỉ đọc (chỉ có AC + diff), chạy probe + mutation trong bộ nhớ; kết quả gộp vào đây.

## Kết quả theo AC

| AC | Kết quả | Bằng chứng |
|---|---|---|
| AC1 — worker `git commit` khi `commitPolicy: forbid` bị gate từ chối | ✅ đạt | 10 test `#22` ĐỎ trên `22f5c75` (`main-22f5c75-gate-tests-RED.log`), XANH trên `98b6239` (`branch-98b6239-gate-tests.log` 26/26) · cả bộ 307/307 (`branch-98b6239-full-suite.log`) |
| AC2 — sửa file `forbiddenPaths` dù commit hay không đều bị chặn nghiệm thu | ❌ không đạt | `probe-ac2-undeclared.log`: 4/5 kịch bản `accept()` THÀNH CÔNG |

## AC2 — tái hiện

Chạy: `WT=<gốc mcp-servers/antigravity-pm-mcp> node --test probe-ac2-undeclared.mjs`

Chung cho mọi kịch bản:

- a. Task có `forbiddenPaths: ['gradle/libs.versions.toml']`, đủ bằng chứng PM (plan duyệt, giao implement, audit, review, test xanh, ảnh)
- b. Worker sửa `src/Kinh.kt`, `src/test/KinhTest.kt`
- c. Gọi `gateCtx`, `gate`, `accept` như `pm_accept` (`src/tools.js:1163-1179` chỉ xét `gate().ok`; cảnh báo không chặn)

| # | Kịch bản | commitPolicy | gate.ok | accept() | Ghi chú |
|---|---|---|---|---|---|
| A1 | sửa file CẤM, KHÔNG khai, chưa commit | forbid (mặc định) | true | thành công | chỉ cảnh báo "File CAM … KHONG khai" |
| A2 | như A1, có commit | forbid | false | bị từ chối | chặn nhờ luật commitPolicy; luật forbiddenPaths vẫn chỉ cảnh báo |
| A3 | như A1 | allow | true | thành công | chỉ cảnh báo |
| A4 | như A2 | allow | true | thành công | chỉ cảnh báo |
| D1 | `git mv` file CẤM sang `gradle/x.toml`, chưa commit, khai CẢ tên cũ | forbid | true | thành công | KHÔNG cảnh báo gì: `changedFiles` mất tên cũ |

Nguyên nhân:

- A1, A3, A4: `fileCamDungTheoTask` → `chiaTheoTask` (`src/policy.js:254-286`) chỉ đưa vào `chan` file task khai (`files_changed`) hoặc thuộc `scopeFiles`; file CẤM không khai rơi vào `canhBao` (`src/tasks.js:671-673`). Issue #22 mục Fix yêu cầu đối chiếu `task.baselineDirty` lúc giao việc — bản này chưa làm.
- D1: `gitSnapshot` (`src/worktree.js:73`) bỏ tên CŨ của mục rename trong `git status -z`.
- Test `#22 AC2` của Builder (`tests/gate.test.js:304`) XANH sẵn trên `22f5c75`: nó khai file CẤM trong `files_changed`, nên không chạm nhánh "không khai".
- Thiết kế cũ ghim "file CẤM không khai = chỉ cảnh báo" ở `tests/cam-dung-theo-task.test.js:26` (phiên khác / auto-commit trên cây dùng chung). Ảnh chụp `baselineDirty` giữ được ý đó: file đã bẩn TRƯỚC lúc giao vẫn cảnh báo, file đổi SAU lúc giao thì chặn.

## Sửa đúng trông thế nào

- A1–A4: cả 4 tổ hợp (forbid/allow × commit/không) từ chối nghiệm thu với dòng chặn `CAM sua … gradle/libs.versions.toml` do CHÍNH luật forbiddenPaths sinh ra (không nhờ luật commitPolicy). File CẤM đã bẩn trước lúc giao implement vẫn chỉ cảnh báo.
- D1: rename / `git mv` file CẤM (chưa commit) bị chặn; tên cũ phải vào danh sách soi file CẤM.
- Đưa probe A1–A4 + D1 vào `tests/gate.test.js`, ĐỎ trước khi sửa.

## Lỗ hổng khác (sub-agent, không chặn riêng — sửa cùng vòng nếu gọn)

| Mức | Lỗ hổng | Bằng chứng |
|---|---|---|
| High | commit `git mv` file CẤM, chỉ khai tên MỚI, `commitPolicy: allow` → nghiệm thu được, chỉ cảnh báo | probe của sub-agent (d2u) |
| High | `forbiddenPaths` nhập dạng Unicode NFD trong khi git trả NFC → không chặn, không cảnh báo (`src/policy.js:242-244`) | probe của sub-agent (f3) |
| Medium | `git commit --allow-empty`, hoặc commit rồi `git revert` → `ok=true` dưới forbid: luật so cây file (`src/worktree.js:44`), không đếm commit, dù comment `src/policy.js:260` nói "MỌI commit đều chặn" | probe của sub-agent |
| Medium | task tạo trước bản này (bản chụp không có `commitPolicy`): agent sửa cấu hình sống thành `allow` rồi commit → nghiệm thu được (`src/config.js:264`) | probe của sub-agent (h) |
| Medium | mutant sống: bỏ `ghiMocGiao(cfg, task)` khỏi `pm_dispatch` (`src/tools.js:672`) → 307/307 vẫn xanh | mutation của sub-agent |
| Medium | không test nào đi qua `pm_accept` / `accept()` bị từ chối cho AC1, AC2 | ledger của sub-agent |
| Low | mutant sống: bỏ kiểm SHA (`src/worktree.js:120`), `khaiCommit` trả nguyên đầu vào (`src/policy.js:277`), bỏ `d.truncated` (`src/worktree.js:45`), bỏ lọc thư mục trạng thái (`src/worktree.js:47`) | mutation của sub-agent |
| Low | commit rồi `git reset --soft HEAD~1` → `ok=true`; nhãn thông báo in `commit g..HEAD` khi task cũ không có commit gốc (`src/tasks.js:680`) | probe của sub-agent |

root-cause-hash: cc68b0b69cd3
