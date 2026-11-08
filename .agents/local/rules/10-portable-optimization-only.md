# Chỉ Tối Ưu Phần Port Được Sang 5 Repo App (Portable Optimization Only)

Lệnh chủ repo (01/11/2026, nguyên văn): "chỉ tối ưu cho phần port đc 5 repo tối ưu cho nó thì ko làm cho tôi".
5 repo app: GeelyEx2, OfficeReader, Goods-Triple-Shelf-Match-3D, Humans-vs.-UFOs, Idle-Plaza-3D.
Mục tiêu (chủ repo, 01/11): "tăng chất lượng 5 repo cũng như nâng auto lên 100%". Việc DevKit chỉ có giá trị khi tăng chất lượng app hoặc tăng % thẻ app tự chạy hết, tức từ Ready tới Done mà không cần người đụng tay (đo 18/10–01/11: khoảng 25%).

## 1. Phạm vi (BẤT BIẾN)
- **Chỉ làm tối ưu mà 5 repo app nhận được khi đồng bộ kit**: tốc độ gate/merge gate chạy trong app, tài nguyên máy dùng chung (slot, số test song song), luồng board/merge/review mà app dùng, giảm chỗ app phải làm tay.
- **CẤM làm tối ưu chỉ có lợi cho nội bộ agent-workbench**: test riêng của kit (`tests/gates`, shard REG-DK-*), công cụ đo/thông báo/dashboard của kit, tiện ích điều phối chỉ chạy ở workbench. Thẻ loại này đóng "not planned" hoặc để Hoãn, không mở lane.
- **Ngoại lệ 1, lỗi nghiêm trọng ở kit** (mất dữ liệu hay commit, main hỏng hoặc lệch origin, merge/push hỏng hẳn làm luồng tự động dừng, lỗ bảo mật, gate báo xanh sai). Đây là sửa lỗi, không phải tối ưu; vẫn làm ngay.
- **Ngoại lệ 2, việc DevKit thật sự quan trọng** (lệnh chủ repo 01/11, nguyên văn: "nếu nó thật sự quan trọng thật sự cần cho dev kit thì vẫn đưa vô được"). Ngoài ngoại lệ 1, việc thuộc loại CẤM ở dòng trên chỉ được làm khi đạt ít nhất một mức sau, đo trên dữ liệu thật (PR đã merge, log board, log gate), không ước lượng:
  - a. Gỡ một tín hiệu đụng tay lặp lại ở board workbench (thẻ Blocked/🙋, merge gate đỏ oan hoặc TIMEOUT do chậm hay chập chờn làm board dừng), gặp từ 2 lần trong 7 ngày gần nhất, kèm số thẻ/PR làm bằng chứng. Merge/push hỏng hẳn thuộc ngoại lệ 1, làm ngay từ lần đầu.
  - b. Tiết kiệm giờ máy lớn: giảm ít nhất 10% tổng số test gate chọn chạy hoặc tổng thời gian gate trên các PR đã merge vào main agent-workbench 14 ngày gần nhất (máy chạy chung với 5 repo app): số test đo bằng cách chạy lại bước chọn test của gate trên các PR đó, thời gian đo từ log gate của các PR đó; không tính phần giảm do xoá hay nới test.
  - c. Là điều kiện bắt buộc của một việc port sang app đã nhận (ghi số thẻ app đó).
- Dù đạt mức nào, lợi ích vẫn phải lớn hơn công làm, review và rủi ro chạm file lõi. Không đạt mức nào thì xử lý như việc nội bộ thường ở dòng trên: để Hoãn, hoặc đóng "not planned" khi chủ repo không giữ.

## 2. Kiểm trước khi nhận thẻ tối ưu
- Thẻ, PR hoặc plan tối ưu phải ghi một dòng `Port: <repo app nào nhận, qua file kit nào>`. Việc theo ngoại lệ 2 ghi `Kit: <mức a/b/c>, <số đo hoặc số thẻ, kèm nguồn>` thay cho `Port:`. Không ghi được một trong hai dòng thì không làm.
- Việc `Port:`: lợi ích ở app phải lớn hơn công port (mỗi thay đổi kit tốn 5 PR đồng bộ). Lợi ích nhỏ hoặc không đo được thì Hoãn.
- Tốc độ không phải là tự động: ghi rõ thẻ gỡ được tín hiệu đụng tay nào (ở app với `Port:`, ở board workbench với `Kit:` mức a), hoặc ghi "chỉ tiết kiệm giờ máy".

## 3. Thẻ mới
- **Không đẩy lỗi vào Backlog** (lệnh chủ repo 06/11, nguyên văn: "vụ p0,p1 thì làm còn các p2,p3 v.v.. Thì đưa vô backlog remove rule này cho tôi đi để nó xử lý hết ko đưa backlog"): mọi lỗi hoặc phát hiện review (P0, P1, P2, P3) gặp khi đang làm thì sửa luôn trong cùng task/PR, kèm oracle và gate; không hạ cấp thành thẻ Backlog, không chỉ ghi vào PR. Bug thật nằm ngoài task đang làm (repo khác, luồng khác) thì vẫn tạo thẻ để board xử lý, không bỏ qua.

## 4. Tự sửa cấu hình hỏng, không hỏi (lệnh chủ repo 01/11: "tự sửa config cho mọi quyền mục đích auto 100%")
- Cấu hình repo/kit bị hỏng làm luồng tự động đứng (`.git/config` như `core.bare`/`core.worktree`, `.git/info/exclude`, config super-board, `.antigravity-pm.json`, hook kit lệch bản kit): agent tự trả về trạng thái tốt đã biết (bản trước khi hỏng, bản của kit, hoặc patch đã đo), không hỏi người dùng. Ghi lại bản cũ, lệnh đã chạy và cách kiểm vào RESULT của phiên.
- Trước khi sửa, đọc file đích và sao lưu bản đang có ra `.agents/local/` hoặc scratch. Sau khi sửa, chạy lệnh kiểm (`git status`, `agent-kit parity`, `agent-health.py -t`) và ghi kết quả.
- Không nằm trong mục này: quyền của chính agent (allow/deny trong `.claude/settings*.json`, chế độ permission, auto mode), nới hoặc tắt hook bảo vệ, secret. Người dùng tự cấp quyền; agent chỉ soạn sẵn danh sách quyền cần thêm, kèm lý do.
