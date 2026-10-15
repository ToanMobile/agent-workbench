---
name: devkit-audit
description: Dùng khi chạy /devkit-audit hoặc khi người dùng muốn audit, review và tối ưu chất lượng, hiệu suất của chính DevKit trên các repo đã cài (chạy hằng ngày). Bỏ qua khi chỉ sửa bug của app trong một repo (dùng fixbugs) hoặc review diff của app (dùng qa-review / open-code-review).
---

# DevKit Audit hằng ngày (đo → audit → review → tối ưu → bàn giao)

Mục tiêu: đưa chính DevKit tới **100/100** theo `skills/devkit-audit/references/rubric.md`. **Ưu tiên số một: hook Stop** (số lần chặn thật, thời gian chạy lặp). Mỗi ngày đo lại, chỉ sửa cái đo được, mỗi sửa có test ĐỎ→XANH. **Mặc định dùng thêm `/giao`**: Antigravity phản biện kế hoạch và audit diff. Chạy tự động từ đầu đến cuối; chỉ hỏi người dùng việc chỉ họ quyết: xoá dữ liệu, force-push, sửa file luật, quyền dữ liệu mới.

## 7 pha (lệnh và bẫy: `skills/devkit-audit/references/procedure.md`; bài học: `references/lessons.md`; ứng viên sẵn: `references/backlog.md`)

0. **Chuẩn bị**: đọc note bàn giao mới nhất và mục Unreleased của `CHANGELOG.md`; tìm repo đã cài; kiểm khoá checkout và đĩa.
1. **Đo**: `skills/devkit-audit/scripts/devkit_metrics.py --json` cho 4 repo white list (đường dẫn ở `procedure.md` pha 0), so với dòng trend hôm trước.
2. **Audit chỉ đọc**: một agent mỗi repo, một agent guard, một agent tốc độ (`references/agent-briefs.md`). Tự kiểm lại mọi claim; gắn nhãn "tự xác nhận" hoặc "agent báo".
3. **Chọn và lên kế hoạch**: hook Stop trước, rồi phút tiết kiệm đã đo ÷ rủi ro; tối đa 3 mục; chưa có số đo thì đo trước. Qua `/giao`: `pm_task_create`, `pm_plan`, `pm_dispatch kind=plan_review`; tự kiểm từng phát hiện, rồi sửa kế hoạch.
4. **Sửa**: trong bản sao `cp -Rc` của kit; test ĐỎ trước, XANH sau; cài từng file bằng file tạm rồi `mv`.
5. **Review độc lập**: agent ngữ cảnh mới, OpenCodeReview (`bin/ocr-review`: tự review khi có khoá LLM, không thì spec delegation giao cho một reviewer ngữ cảnh mới khác) và `pm_dispatch kind=audit` cùng đọc toàn diff, thử phá. Sửa mọi lỗi thật, rồi review lại phần vừa sửa.
6. **Cổng và bàn giao**: gate `--full` exit 0 ở mọi repo white list đã đụng, đăng ký bug và RED-proof, commit đúng file của mình, push, cập nhật note bàn giao, dòng trend và `agent-kit learn`; cuối pha, `nightly.py run <repo>` một lần cho mỗi repo rảnh (`session_lock.py --status` exit 0 là điều kiện cần, chưa đủ: nó coi phiên đang rảnh ở prompt là rảnh; phép kiểm khoá chặt hơn nằm trong `nightly.py`, in `skip: <lý do>` khi có phiên giữ checkout; phiên mở giữa lúc một suite đang chạy là phần dư đã biết; không cài job đêm) để dọn hàng RED-proof chờ.
7. **Báo cáo**: 3 dòng đầu, 4 mục nghiệm thu, điểm /100 kèm mục bị trừ.

## Luật cứng

- Audit chỉ đọc (ngoại lệ duy nhất: `nightly.py run` ở bước 7 pha 6: nó ghi `.agents/regression_status.json` và `.agents/CHECKLIST.md` đã commit của repo rảnh như một lượt gate và để chúng chưa commit cho commit kế tiếp của repo đó; `red_proof.py` trong lượt ấy chạy `git worktree add --detach` trong chính repo đó, một worktree sandbox dùng một lần, tự gỡ khi xong). Antigravity chỉ phản biện và audit, không implement (từng viết lại hàm và để file rác). Audit không tự tạo worktree hay nhánh mới (trừ sandbox của red_proof nói trên). Không đụng repo đang do phiên khác giữ khoá. Xoá dữ liệu thật thì hỏi một lần bằng AskUserQuestion; mọi bước khác tự làm, không đưa lệnh `!`.
- Nhanh hơn chỉ bằng cách bỏ việc thừa, không giảm kiểm tra nào; có số đo trước và sau từ script, có công tắc tắt.
- Mọi mục rubric đã đạt, không hồi quy: dừng, báo 100/100.
- Chỉ tính bằng chứng tạo sau lần sửa cuối của lượt này.
