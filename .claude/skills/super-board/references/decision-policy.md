# Ủy quyền thường trực của chủ: `[orchestrator] [decision]`

Nguồn: comment của Toan (chủ mọi thẻ) trên #516, 28/10. Đây là nguyên văn luật; bộ đọc
`.claude/bin/super-board-decision.py` là nơi DUY NHẤT quyết định một comment có phải quyết định hợp lệ.
(Không nhầm với `../../super-build/references/decision-policy.md`: đó là thang quyết định của worker khi code.)

Tôi (Toan, chủ mọi thẻ) ỦY QUYỀN THƯỜNG TRỰC: với blocker 🙋/❓ trên mọi repo super-board của tôi, bạn tự chọn hướng tốt nhất và
ghi quyết định, không chờ tôi duyệt tay. Chỉ hỏi tôi ở các trường hợp nằm trong DANH SÁCH DỪNG.

## Luật quyết định (theo thứ tự)

1. Code đã xong, gate xanh, AC còn mở chỉ vì thiếu mẫu đo/điều kiện môi trường, mà mẫu thay thế chứng minh đúng cơ chế → CHẤP NHẬN mẫu thay thế.
2. AC không còn tái hiện được (không có RED để làm oracle) → merge phần đã sửa, đóng thẻ, ghi "mở thẻ mới nếu đỏ lại, kèm log".
3. Thiếu công cụ/lệnh không tồn tại → dùng quy trình đã có tiền lệ (PR mẫu gần nhất).
4. Việc dính repo ngoài hoặc người khác → KHÔNG push ra ngoài; tách card: phần làm được trong repo tôi + bản patch/issue soạn sẵn cho upstream.
5. Thẻ ôm nhiều repo/phạm vi → tách mỗi repo một card, một PR.

Luôn chọn hướng an toàn, đảo ngược được, ít phạm vi nhất mà vẫn đóng được thẻ.

## Danh sách dừng (vẫn gắn needs-you)

- Cần người thật: lái xe, phần cứng, ELM327, thiết bị, tài khoản/thanh toán, đăng nhập.
- Xoá hoặc đổi AC về hành vi sản phẩm, đổi phạm vi tính năng.
- Mất dữ liệu, xoá file/nhánh của phiên khác, đụng thay đổi chưa commit của người khác.
- Bảo mật, secret, quyền push, nới hook/gate.
- Không có mẫu thay thế lẫn tiền lệ.

## Cách ghi

Mỗi quyết định: comment `[orchestrator] [decision]` gồm luật số mấy, lý do, bằng chứng, "Quyết định cuối, không hỏi lại", rồi gỡ
needs-you và chuyển cột đúng (Review/Ready/Done). Builder/QA/merge gate gặp `[decision]` thì coi AC đó đã xử lý, KHÔNG dựng lại blocker.

Luật cứng kèm theo: không `--no-verify`, không `--auto-approve-tests`, không push thẳng main (đi PR/integrate). Test sửa: liệt kê kèm
diff để chủ duyệt bằng AUTO-APPROVE. Gặp cùng chướng ngại 2 lần thì dừng và báo.

## Máy đọc thế nào (hợp lệ hay bỏ qua)

Dòng đầu (sau khi bỏ marker) là `[orchestrator] [decision]`, người đăng là chủ (authorAssociation OWNER hoặc `decision_policy.owner`), và:

| Điều kiện | Kết quả |
| --- | --- |
| mang `<!-- sb-decision:orchestrator -->` | hợp lệ |
| comment tay của chủ, KHÔNG có marker `<!-- … -->` nào | hợp lệ |
| header `[builder]` / `[qa]` / `[reviewer]`, hay marker lane khác (`sb-write`, `super-review:report`, `super-board:needs-you` …) không kèm marker orchestrator | bỏ qua: lane không tự quyết cho thẻ mình |

 Ai đọc nó:

- `super-board-deps.sh`: `needsYou` = nhãn `needs-you` hiện tại, hoặc comment 🙋 mà không có `[decision]` hợp lệ mới hơn.
- `super-board-needs-you.py mark`: có `[decision]` hợp lệ mới hơn comment needs-you gần nhất thì không gắn lại, trừ khi `--action`
  rơi vào danh sách dừng (lái xe, secret, quyền push, thanh toán, mất dữ liệu …).
- `super-board-qa-report.py` (merge gate): `[decision]` hợp lệ mới hơn report `[qa] [report]` mới nhất thì các mục `❌ Not done` của report đó không chặn merge.

Lùi: `decision_policy.enabled: false` trong config của board (schema: `config-schema.json`).
