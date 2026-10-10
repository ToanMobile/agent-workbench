---
name: devkit-audit
description: Dùng khi chạy /devkit-audit hoặc khi người dùng muốn audit, review và tối ưu chất lượng, hiệu suất của chính DevKit trên các repo đã cài (chạy hằng ngày). Bỏ qua khi chỉ sửa bug của app trong một repo (dùng fixbugs) hoặc review diff của app (dùng qa-review / open-code-review).
---

# DevKit Audit hằng ngày (đo → audit → review → tối ưu → bàn giao)

Mục tiêu: đưa chính DevKit tới **100/100** theo `skills/devkit-audit/references/rubric.md`. **Ưu tiên số một: hook Stop** (số lần chặn thật, thời gian chạy lặp). Mỗi ngày đo lại, chỉ sửa cái đo được, mỗi sửa có test ĐỎ→XANH. **Mặc định dùng thêm `/giao`**: Antigravity phản biện kế hoạch và audit diff. Chạy tự động từ đầu đến cuối; chỉ hỏi người dùng việc chỉ họ quyết: xoá dữ liệu, force-push, sửa file luật, quyền dữ liệu mới.

## 7 pha (lệnh và bẫy: `skills/devkit-audit/references/procedure.md`; bài học: `references/lessons.md`; ứng viên sẵn: `references/backlog.md`)

0. **Chuẩn bị**: đọc note bàn giao mới nhất và mục Unreleased của `CHANGELOG.md`; tìm repo đã cài; kiểm khoá checkout và đĩa.
1. **Đo**: `skills/devkit-audit/scripts/devkit_metrics.py --json` cho mọi repo, so với dòng trend hôm trước.
2. **Audit chỉ đọc**: một agent mỗi repo, một agent guard, một agent tốc độ (`references/agent-briefs.md`). Tự kiểm lại mọi claim; gắn nhãn "tự xác nhận" hoặc "agent báo".
3. **Chọn và lên kế hoạch**: hook Stop trước, rồi phút tiết kiệm đã đo ÷ rủi ro; tối đa 3 mục; chưa có số đo thì đo trước. Qua `/giao`: `pm_task_create`, `pm_plan`, `pm_dispatch kind=plan_review`; tự kiểm từng phát hiện, rồi sửa kế hoạch.
4. **Sửa**: trong bản sao `cp -Rc` của kit; test ĐỎ trước, XANH sau; cài từng file bằng file tạm rồi `mv`.
5. **Review độc lập**: agent ngữ cảnh mới và `pm_dispatch kind=audit` cùng đọc toàn diff, thử phá. Sửa mọi lỗi thật, rồi review lại phần vừa sửa.
6. **Cổng và bàn giao**: gate `--full` exit 0 ở mọi repo đã đụng, đăng ký bug và RED-proof, commit đúng file của mình, push, cập nhật note bàn giao, dòng trend và `agent-kit learn`.
7. **Báo cáo**: 3 dòng đầu, 4 mục nghiệm thu, điểm /100 kèm mục bị trừ.

## Luật cứng

- Audit chỉ đọc. Antigravity chỉ phản biện và audit, không implement (từng viết lại hàm và để file rác). Không worktree hay nhánh mới. Không đụng repo đang do phiên khác giữ khoá. Xoá dữ liệu thật thì hỏi một lần bằng AskUserQuestion; mọi bước khác tự làm, không đưa lệnh `!`.
- Nhanh hơn chỉ bằng cách bỏ việc thừa, không giảm kiểm tra nào; có số đo trước và sau từ script, có công tắc tắt.
- Mọi mục rubric đã đạt, không hồi quy: dừng, báo 100/100.
- Chỉ tính bằng chứng tạo sau lần sửa cuối của lượt này.
