---
name: parallel-lanes
description: "Dùng khi một việc được chia cho từ hai agent/lane trở lên chạy song song (fixer, reviewer, lane test, đợt merge): xếp lane đường găng và lane nặng chạy trước, giới hạn số lane theo CPU còn trống, brief sẵn các bẫy lặp lại, mỗi lane một worktree, review theo mức rủi ro nhưng không bỏ vòng nào, một gate full cho cả đợt. Lệnh: `agent-kit lanes plan|slots|record`."
---

# Parallel Lanes (nhiều agent, xong sớm nhất mà không bớt chất lượng)

Nhanh ở đây đến từ **xếp lịch**, không đến từ bỏ một vòng review hay verify (người dùng, 15/10: "chất lượng DevKit là ưu tiên cao nhất"). Đợt 15/10 mất nhiều giờ vì lane rủi ro nhất bắt đầu sau các lane nhỏ và bảy agent cùng chạy test đẩy load lên 37.

## 1. Lập kế hoạch đợt
1. Viết `lanes.json` (một list): `id`, `est_min` (bỏ trống thì lấy trung vị các lane cùng `kind` đã ghi, mặc định 30), `kind`, `deps` (lane phải xong trước), `risk` (`high` cho hook/guard/gate/code giết tiến trình), `files` (file lane sẽ sửa).
2. `agent-kit lanes slots` — số lane chạy cùng lúc máy này chịu được ngay bây giờ (CPU trống chia 4, từ 1 đến 6). Đang có agent chạy suite thì con số đã trừ phần đó; không mở thêm lane vượt số này.
3. `agent-kit lanes plan lanes.json` — thứ tự bắt đầu: lane có đường dài nhất tới cuối đợt (ước lượng của nó cộng chuỗi lane chờ nó) chạy trước, lane `high` thắng khi hoà; thời gian cả đợt so với xếp theo thứ tự nhập; thứ tự merge; cảnh báo hai lane sửa cùng một file (chỉ một lane sở hữu file đó, lane kia chờ hoặc đổi phạm vi).
4. Khởi động theo thứ tự đó; một lane xong thì mở lane kế trong hàng, không đợi cả nhóm.

## 2. Brief mỗi lane (đưa sẵn các bẫy lặp lại để vòng review đầu tìm ít hơn)
- Mỗi test mới phải qua mutation: sửa một dòng logic, test phải đỏ (test rỗng đã gặp ở 4 lane: `if (!c) return;`, pin không thể fail, grep ở bất kỳ đâu trong file).
- Mỗi dòng "nguy hiểm phải bị chặn" có dòng đối chứng vô hại cùng hình dạng.
- Nghi ngờ thì đóng (fail closed): không cắt, không bỏ qua phần mà thứ gì đó còn có thể chạy.
- Pid/định danh kiểm lại dưới khoá, ngay trước khi giết.
- Test không phụ thuộc máy chủ: tên host `Mac` làm git mất identity; wrapper `#!/bin/sh` mới tạo có thể mất >1,5 s ở lần chạy đầu.
- Test mới cần exec bit + một dòng trong `tests/lib/test_durations.txt`.
- Không trích đường dẫn tài liệu sắp xoá (`docs/issues-bugs.md`, `docs/workflow-improvements.md`).
- Mỗi lane làm trong worktree riêng (`agent-kit worktree add`, hoặc EnterWorktree trong trunk mode); không ai ghi vào main.

## 3. Review theo rủi ro, lặp tới khi sạch
- Hook, guard, gate, code giết tiến trình hoặc tái dùng kết quả: `principal-code-reviewer` + `ocr-review` chạy SONG SONG trên cùng diff, sửa cả hai báo cáo một lượt.
- Verify = reviewer GỐC chạy lại chính probe/mutant của họ (SendMessage giữ nguyên ngữ cảnh), không gọi cặp reviewer mới. Còn P0/P1 thì sửa tiếp và verify lại; không merge lane còn lỗ fail-open đã biết, không "chốt tạm" để đỡ tốn giờ.
- Lane chỉ có văn bản, luật, test hoặc script có fixture: một reviewer cộng test và mutant của lane.
- Đừng nhờ reviewer liệt kê cách vượt guard bằng văn xuôi (classifier an toàn đã chặn một agent): dùng OCR, so verdict cũ–mới, corpus đơn điệu và mutation.

## 4. Gate và merge
- Mỗi lane chạy gate impacted (`--since <base>`) trong worktree của nó.
- Merge theo thứ tự `lanes plan` đưa ra; xung đột chỉ ở file hợp nhất bằng union (`tests/impact_map.txt`, `tests/lib/test_durations.txt`, checklist).
- Một gate full cho kết quả đã merge (`post-fix-gate.py --run-tests --full --diff origin/<nhánh>`), trên máy yên: không chạy khi từ 5 agent đang chạy test (`agent-kit lanes slots` cho 1 là dấu hiệu máy đang quá tải).
- Xong lane thì `agent-kit lanes record <id> <số phút thật> --kind <loại>` để lần sau ước lượng sát hơn.
