# Đề xuất cưỡng chế (bài học đã có nhưng vẫn tái phạm) — retro 2026-10-26

## 1. "Đã fix" nhưng vẫn lỗi — B_FIX_CHUA_KIEM (15 lần / 11 phiên, 08-14→10-17)
Đã có: automotive AUTO-05, GeelyEx2 INSTINCT-086 (09-04), INSTINCT-132 (09-05), luật RED→GREEN của devkit.
Vẫn tái phạm: 09-25, 10-06, 10-07, 10-08, 10-15, 10-17; 6/15 lần nằm ở Antigravity, nơi hook Claude không chạy.
- Chuyển gate vào git hook không phụ thuộc agent (pre-commit/pre-push qua core.hooksPath) để Antigravity cũng bị chặn.
- Hook UserPromptSubmit: tin nhắn khớp `vẫn bị|lại bị|đã báo|vẫn chưa|vẫn còn` → tạo mục REOPEN. Stop bị chặn cho tới khi có test RED→GREEN trên đúng đường người dùng nói (version/app).
- Stop gate: chặn chữ "XONG/đã fix" nếu báo cáo còn "cần anh thử", "chưa đo", hoặc không ghi nơi đo (xe / máy thật / emulator).

## 2. Hỏi/chờ duyệt — E_HOI_CHO_DAY_VIEC (8 phiên, 09-25→10-13)
Đã có: GeelyEx2 INSTINCT-041 (09-13→09-19), nhưng vẫn tái phạm ở 09-25 (#52) và ở các project khác.
- Ask-gate trong Stop hook: lượt kết bằng câu hỏi hoặc "CHỜ DUYỆT" mà không thuộc nhóm được phép (xoá dữ liệu quan trọng, secrets, billing, publish production, phần cứng nguy hiểm) → chặn một lần với lời nhắn "làm theo khuyến nghị của bạn".

## 3. Gate chậm / chạy lặp — G_CHAM_LAP (11 phiên, 09-29→10-26)
Đã có: agent-workbench 017 (09-29), 018 (09-30), 051 (10-18), 066 (10-25), đều là bug cache; người dùng vẫn than tới 10-25 và 10-26.
- Thêm tầng gate doc-only: diff chỉ `*.md`/`docs/` → chỉ lint doc.
- Dùng lại biên nhận gate theo tree hash: tree không đổi thì không chạy lại.
- Ghi thời gian từng gate và cảnh báo khi vượt ngân sách.

## 4. Worktree/branch rác — L_WORKTREE_RAC (2 phiên, 10-13→10-20)
Đã có: GeelyEx2 INSTINCT-156 (10-01), agent-workbench INSTINCT-047 (10-17).
- Thêm `worktree gc` vào SessionEnd/finish (người dùng đã cho phép ở #352): gỡ worktree sạch có branch đã merge vào origin/main, xoá `git branch --merged origin/main` (trừ main/trunk), rồi in phần còn sót.

## 5. Từ signals (hook có rồi nhưng thói quen vẫn lặp)
- Trunk mode: 1863 lần bị chặn. Tự tạo worktree khi có lệnh ghi đầu tiên (hoặc SessionStart in sẵn lệnh vào worktree) thay vì chỉ chặn.
- Hook thiếu file: 1040 lỗi `python3 "$CLAUDE_PROJECT_DIR"/… can't open file`, liên quan agent-workbench 052 (file DevKit bị ignore nên vắng trong worktree). Gọi hook qua launcher có fallback về checkout chính, kèm health-check ở SessionStart.
- Khoá phiên (H, 4 phiên): `agent-kit worktree finish`/merge không được cần khoá của checkout chính. Đây là luật devkit, không có instinct nào.
- antigravity-pm: 39 lỗi sai thứ tự gọi (gần goods-027). Tool nên trả về lời gọi đúng tiếp theo, hoặc tự chạy bước tiên quyết.
- Đề xuất mới: lint trích dẫn cho tài liệu gửi khách (A_BIA). Mọi tên thư viện phải grep được trong file build, mọi con số phải có nguồn.
- Đề xuất mới: tự tạm dừng board khi load average vượt ngưỡng (I_QUA_TAI).
