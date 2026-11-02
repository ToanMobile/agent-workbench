---
name: parallel-lanes
description: "Dùng khi một việc được chia cho từ hai agent/lane trở lên chạy song song (fixer, reviewer, lane test, đợt merge): xếp lane đường găng và lane nặng chạy trước, giới hạn số lane theo CPU còn trống, brief sẵn các bẫy lặp lại, mỗi lane một worktree, review theo mức rủi ro nhưng không bỏ vòng nào, một gate full cho cả đợt ở điểm gộp (integrate / merge gate / merge train). Lệnh: `agent-kit lanes plan|slots|record`."
---

# Parallel Lanes (nhiều agent, xong sớm nhất mà không bớt chất lượng)

Nhanh ở đây đến từ **xếp lịch**, không đến từ bỏ một vòng review hay verify (người dùng, 15/10: "chất lượng DevKit là ưu tiên cao nhất"). Đợt 15/10 mất nhiều giờ vì lane rủi ro nhất bắt đầu sau các lane nhỏ và bảy agent cùng chạy test đẩy load lên 37.

## 1. Lập kế hoạch đợt
1. Viết `lanes.json` (một list): `id`, `est_min` (bỏ trống thì lấy trung vị các lane cùng `kind` đã ghi, mặc định 30), `kind`, `deps` (lane phải xong trước), `risk` (`high` cho hook/guard/gate/code giết tiến trình), `files` (đường dẫn lane sẽ sửa, tính từ gốc repo; một thư mục tính là mọi file trong nó). Để `lanes.json` NGOÀI repo (thư mục scratch của phiên): file nằm trong worktree bị auto-merge quét vào main.
2. `agent-kit lanes slots` — số lane chạy cùng lúc máy này chịu được ngay bây giờ (CPU trống chia 4, từ 1 đến 4 = 3-4 agent chạy suite cùng lúc). Đó là TỔNG số lane chạy cùng lúc, không phải số lane thêm: trừ các lane đang chạy rồi mới mở. Load trung bình 1 phút đi chậm hơn các lane vừa mở, nên đọc lại `slots` trước khi mở lane kế. `agent-kit worktree add` không giới hạn số worktree (#607), chỉ chặn khi đĩa dưới sàn.
3. `agent-kit lanes plan lanes.json` — thứ tự bắt đầu: lane có đường dài nhất tới cuối đợt (ước lượng của nó cộng chuỗi lane chờ nó) chạy trước, lane `high` thắng khi hoà; thời gian cả đợt so với xếp theo thứ tự nhập (đây là heuristic: khi thứ tự nhập ngắn hơn thì plan dùng thứ tự nhập và nói rõ); thứ tự merge. Hai lane khai cùng một file (thư mục tính cho mọi file trong nó; file hợp nhất bằng union thì không) KHÔNG BAO GIỜ chạy cùng lúc: lane bắt đầu được muộn hơn (theo chuỗi `deps`) chờ lane kia, dòng `SERIAL` (JSON: `serialized`) nói rõ; mở worktree của lane chờ CHỈ SAU KHI lane kia đã gộp vào trunk (`worktree finish` / merge gate), không thì nó vẫn sửa trên file cũ và vẫn xung đột; khi file đó là phần chính của cả hai thì gộp thành một lane (18/10: nhiều agent cùng sửa một file là chỗ chậm thật).
4. Khởi động theo thứ tự đó, mọi lane được chạy ngay trong MỘT tin nhắn: cùng repo thì Agent tool `isolation: "worktree"`, repo khác thì một phiên riêng (Claude Desktop chỉ mở phiên ở repo khác trong lượt có lời người dùng: mở ngay lượt đó); phần chỉ đọc thì Agent song song không worktree. Một lane xong thì mở lane kế trong hàng, không đợi cả nhóm. Lane được giao không tách tiếp.

**Tự kích hoạt [hook]:** `prompt_context.sh` (UserPromptSubmit, `enrich_context.py` `parallel_split`, chỉ regex, ~0,01 ms) chèn một dòng `- Song song (<lý do>)` khi yêu cầu chia được: nhiều repo ("4 repo", "tất cả repo"), một hành động trên nhiều issue/thẻ ("làm 3 thẻ", "issue #12, #15"), lời yêu cầu rõ ("nhiều agent", "song song giúp", "in parallel"), từ 2 mục danh sách (đánh số hoặc gạch đầu dòng) mở đầu bằng động từ hành động. Câu hỏi, việc chỉ nhắc một file, các bước tái hiện lỗi, chữ trong khối ```, từ chỉ là chủ đề ("lỗi khi nhiều agent cùng ghi"), chit-chat và prompt của agent thì im lặng. Thấy dòng đó thì chia ngay, không đợi người dùng nhắc. Lỗi mới tìm thấy giữa đợt (người dùng 18/10): cực quan trọng (mất dữ liệu hay commit, main hỏng hoặc lệch origin, merge/push hỏng làm luồng tự động dừng, lỗ bảo mật, gate báo xanh sai) thì làm ngay; còn lại (chậm, thêm bước tay, thông báo sai, tối ưu) không sửa, tạo thẻ Backlog bằng skill `createTask` rồi ghi số issue vào báo cáo cuối. Test: `tests/context_memory/test_parallel_hint.sh`.

## 2. Brief mỗi lane (đưa sẵn các bẫy lặp lại để vòng review đầu tìm ít hơn)
- Mỗi test mới phải qua mutation: sửa một dòng logic, test phải đỏ (test rỗng đã gặp ở 4 lane: `if (!c) return;`, pin không thể fail, grep ở bất kỳ đâu trong file).
- Mỗi dòng "nguy hiểm phải bị chặn" có dòng đối chứng vô hại cùng hình dạng.
- Nghi ngờ thì đóng (fail closed): không cắt, không bỏ qua phần mà thứ gì đó còn có thể chạy.
- Pid/định danh kiểm lại dưới khoá, ngay trước khi giết.
- Test không phụ thuộc máy chủ: tên host `Mac` làm git mất identity; wrapper `#!/bin/sh` mới tạo có thể mất >1,5 s ở lần chạy đầu.
- Test mới cần exec bit + một dòng trong `tests/lib/test_durations.txt`.
- Không trích đường dẫn tài liệu đã báo là sắp xoá.
- Mỗi lane làm trong worktree riêng (`agent-kit worktree add`, hoặc EnterWorktree trong trunk mode); không ai ghi vào main.

## 3. Review theo rủi ro, lặp tới khi sạch
- Hook, guard, gate, code giết tiến trình hoặc tái dùng kết quả: `principal-code-reviewer` + `ocr-review` chạy SONG SONG trên cùng diff, sửa cả hai báo cáo một lượt.
- Verify = reviewer GỐC chạy lại chính probe/mutant của họ (SendMessage giữ nguyên ngữ cảnh), không gọi cặp reviewer mới. Còn P0/P1 thì sửa tiếp và verify lại; không merge lane còn lỗ fail-open đã biết, không "chốt tạm" để đỡ tốn giờ.
- Lane chỉ có văn bản, luật, test hoặc script có fixture: một reviewer cộng test và mutant của lane, và `python3 .agents/devkit/bin/ocr-review --from <base> --to <commit>` (hook `review_gate.sh` đòi một lượt OCR sau lần sửa code cuối khi máy có `ocr`).
- Đừng nhờ reviewer liệt kê cách vượt guard bằng văn xuôi (classifier an toàn đã chặn một agent): dùng OCR, so verdict cũ–mới, corpus đơn điệu và mutation.

## 4. Gate và merge
- Mỗi lane chạy gate impacted (`--since <base>`) trong worktree của nó.
- Merge theo thứ tự `lanes plan` đưa ra; xung đột chỉ ở file hợp nhất bằng union (`tests/impact_map.txt`, `tests/lib/test_durations.txt`, checklist).
- Lane không chạy `--full`. Một gate cho cả đợt ở điểm gộp: `agent-kit integrate` (repo trunk-push), merge gate hoặc merge train (repo PR) chạy `--scoped` trong worktree tạm của chúng (tự leo `--full` khi đụng file lõi); `--full` đêm do skill `gate-full` chạy lúc 00:00; không gọi tay `post-fix-gate.py --full` trong lane hay checkout chính. Điểm gộp chạy trên máy yên: kiểm `uptime` trước (load trên số core là quá tải, test chập chờn và gate dễ quá 900 s), không chạy khi từ 5 agent đang chạy test.
- Xong lane thì `agent-kit lanes record <id> <số phút thật> --kind <loại>` để lần sau ước lượng sát hơn (file lịch sử nằm trong git dir chung `<git-common-dir>/devkit/lane_times.jsonl`: mọi worktree dùng chung, không bao giờ vào commit).
