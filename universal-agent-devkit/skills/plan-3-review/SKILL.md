---
name: plan-3-review
description: Dùng khi User yêu cầu lấy plan qua 3 review, "plan-3-review", "3 bên duyệt plan", hoặc khi task lớn/rủi ro cần phản biện plan nhiều vòng trước và sau khi code. Bỏ qua khi sửa cục bộ đã rõ nguyên nhân.
---

# Plan qua 3 review, kiểm lại nhiều vòng rồi mới làm

Failure mode: tác giả tin nguyên nhân chưa kiểm, code rồi mới biết sai gốc.

## 1. Viết plan có bằng chứng

Viết vào một file tạm của phiên (không commit), gồm:

- Mục tiêu và số đo đạt.
- Nguyên nhân: mỗi khẳng định kèm `file:dòng` hoặc lệnh và kết quả vừa chạy. Chưa kiểm thì ghi "giả thuyết".
- File sẽ sửa, người gọi bị ảnh hưởng, việc không làm.
- Test RED→GREEN ở đúng biên lỗi, cách rollback, điều còn chưa kiểm được.

## 2. Ba bên phản biện song song, cùng một brief

Brief: đường dẫn plan, yêu cầu tự kiểm từng khẳng định trên nguồn, tìm cách bác bỏ, chỉ đọc không sửa, trả `P0..P3 + file:dòng + sai gì` và `PASS` hoặc `FAIL`.

| Bên | Cách gọi |
|---|---|
| Claude bối cảnh sạch | Agent `subagent_type: Plan`, không truyền kết luận của tác giả |
| Antigravity | `pm_task_create`, `pm_plan`, `pm_dispatch kind=plan_review`, đọc `plan-review.json` |
| Grok | `~/.grok/bin/grok -m grok-4.7 --permission-mode plan --prompt-file <brief>` |

Bên nào dính limit, 429 hay lỗi công cụ: thử lại 1 lần, vẫn lỗi thì bỏ và ghi lý do (3→2→1). Tối thiểu 1 bên PASS thật; không có bên nào thì báo CHƯA XONG.

## 3. Đối chiếu và sửa plan

- Tự kiểm mọi phát hiện trên nguồn. Đúng: sửa plan. Sai: ghi lý do bác. Không im lặng bỏ qua.
- Hai bên trái nhau: chạy lệnh hoặc test để phân xử, không theo số đông.
- Sửa cả P0..P3 trong task này, không đẩy Backlog.

## 4. Lặp có giới hạn

- Vòng sau chỉ gửi phần đổi (`focus=delta` với Antigravity; `pm_plan` ghi lại làm huỷ phản biện cũ), và chỉ gửi bên còn FAIL hoặc bên có phần liên quan bị đổi.
- Đạt khi: mọi bên còn chạy PASS trên bản plan cuối, không còn phát hiện đúng chưa xử lý.
- Tối đa 3 vòng. Phát hiện lặp 2 vòng: đổi cách. Hết 3 vòng chưa đạt: dừng, báo phần tranh chấp; không code trên plan chưa đạt.
- Chỉ hỏi User việc thuộc danh sách hỏi ở `AGENTS.md`.

## 5. Làm và kiểm lại

1. Làm đúng plan: test đỏ trước, sửa tối thiểu, cùng test xanh.
2. Lệch plan: phản biện delta phần lệch trước khi làm tiếp.
3. Xong code: 3 bên kiểm diff tại head cuối, lặp theo mục 4.
4. Chạy gate một lần trên cây cuối theo `AGENTS.md` bước 3.

## 6. Báo cáo

Bảng mỗi vòng: bên, kết quả, số phát hiện đúng và bị bác, bên bị bỏ kèm lý do. Bên không chạy thì không ghi PASS.
