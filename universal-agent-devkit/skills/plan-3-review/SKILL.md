---
name: plan-3-review
description: Dùng khi User yêu cầu "plan-3-review" hoặc "3 bên duyệt plan". Bỏ qua task đơn giản hoặc vừa theo AGENTS.md, và khi chỉ cần grill-plan hoặc cross-review 2 bên.
---

# Plan qua 3 review

## 1. Viết plan có bằng chứng

File tạm: mục tiêu; nguyên nhân (kèm `file:dòng` hoặc lệnh, chưa kiểm ghi "giả thuyết"); file sửa, người gọi; test RED→GREEN; rollback; điều chưa kiểm.

## 2. Ba bên phản biện song song

Brief: đường dẫn plan, kiểm từng khẳng định trên nguồn, chỉ đọc, trả `P0..P3 + file:dòng + sai gì` và `PASS`/`FAIL`.

| Bên | Plan | Diff |
|---|---|---|
| Claude sạch | Agent `subagent_type: Plan` + brief, không kèm kết luận tác giả | Như plan, brief ghi `base..head` |
| Antigravity | `pm_task_create`, `pm_plan`, `pm_dispatch kind=plan_review` (server dựng prompt); `plan-review.json`: `ok`=PASS, `co_van_de`=FAIL, blocker/major/minor=P0/P1/P2 | `pm_dispatch kind=audit`; `audit-agent.json`: `pass`/`fail` |
| Grok | `~/.grok/bin/grok -m grok-4.7 --permission-mode plan --prompt-file <brief>` | `pm_dispatch kind=audit agent=grok`; phát hiện ở `Log grok`. Không có task: lệnh cột Plan, brief `base..head` |

- Diff: Antigravity trước, đọc báo cáo rồi mới giao Grok (cùng ghi `audit-agent.json`; gate đọc lượt cuối); chỉ nhận khi `reviewer` đúng bên, `auditedHead`=HEAD.
- PASS kèm P0..P2 tính FAIL.
- Limit, lỗi công cụ, quá 15 phút (Grok audit: theo hạn tool), kết quả không rõ: thử lại 1 lần, rồi bỏ bên đó, ghi lý do (3→2→1). Phát hiện đã có vẫn qua mục 3.
- Hết bên: làm tiếp, bàn giao CHƯA XONG.

## 3. Đối chiếu

- Tự kiểm mọi phát hiện trên nguồn. Đúng: sửa, cả P0..P3, không đẩy Backlog.
- Sai: ghi bằng chứng bác bỏ, gửi bên đó vòng sau.
- Hai bên trái nhau: chạy lệnh hoặc test phân xử.

## 4. Lặp có giới hạn

- Vòng sau chỉ gửi phần đổi cho bên còn FAIL hoặc có phần đã kiểm bị đổi (`focus=delta` chỉ cho `plan_review`; `pm_plan` ghi lại huỷ phản biện cũ).
- Đạt: mỗi bên còn chạy PASS, phần đã kiểm không đổi; hoặc FAIL chỉ vì phát hiện đã bác, không phản chứng mới.
- Plan và diff mỗi phần tối đa 3 vòng. Phát hiện lặp 2 vòng: đổi cách.
- Hết vòng, chưa bác được: P0/P1 chọn phương án an toàn hơn, làm tiếp; P2/P3 ghi báo cáo. Diff còn P0/P1: CHƯA XONG.
- Chỉ hỏi User theo danh sách ở `AGENTS.md` gốc, mục Working style.

## 5. Làm và kiểm lại

1. Làm đúng plan: test đỏ, sửa tối thiểu, cùng test xanh; chỉ chạy test scope.
2. Lệch hành vi đã chốt: sửa plan, một bên phản biện delta (tính vào 3 vòng). Lệch khác: ghi báo cáo.
3. Gate theo `AGENTS.md` gốc, "Every prompt" bước 3.
4. Commit, 3 bên kiểm diff tại HEAD, lặp theo mục 4. Có sửa: kiểm delta, chạy lại gate.
5. Báo cáo bảng mỗi vòng: bên, kết quả, phát hiện đúng/bác, bên bỏ kèm lý do.
