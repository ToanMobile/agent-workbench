---
name: grill-plan
description: Dùng khi User yêu cầu grill/phản biện plan, plan còn ambiguity blocking hoặc thay đổi kiến trúc rủi ro cao cần stress-test trước code. Bỏ qua khi task đã rõ hoặc User muốn thực thi ngay.
---

# Grill Plan (Adversarial Plan Stress-Testing)

## Tách Rời FACT Khỏi DECISION

- **FACT:** Tự động điều tra từ codebase/graph, tuyệt đối KHÔNG hỏi User những gì đọc được từ code.
- **LOCAL DECISION:** Reversible, trong phạm vi cho phép → Tự chọn phương án tối ưu chất lượng và ghi nhận trade-off.
- **BLOCKING DECISION:** Chỉ hỏi khi bằng chứng kỹ thuật không thể phân định và ảnh hưởng lớn tới kiến trúc hoặc dữ liệu sản xuất, hoặc lựa chọn đổi đáng kể user-visible behavior/data/release outcome, hoặc cần authority theo `AGENTS.md`.

## Quy Trình Phản Biện & Stress-Test

1. **Lập cây quyết định thật:** Bóc tách toàn bộ giả định ngầm của bản kế hoạch.
2. **Resolve fact trước:** Tra cứu codebase, đo đạc dữ liệu, loại bỏ các giả định sai.
3. **Phản biện tối đa 3 câu hỏi blocking mỗi turn:** Mỗi câu nêu rõ bằng chứng (evidence), đánh đổi (trade-off) và phương án đề xuất cụ thể. Dùng question tool khi có, nếu không hỏi plain text; không hỏi lại quyết định đã chốt.
4. **Batch tiếp theo chỉ khi có blocker mới:** Chỉ mở batch tiếp theo nếu câu trả lời làm lộ blocker mới.
5. **Không hỏi kéo dài vô nghĩa:** Sau khi gỡ bỏ blocker, bàn giao `/plan` tự tiếp tục; chỉ dừng ở plan nếu User yêu cầu plan-only.

Không có approval gate mặc định. Cùng blocker lặp hai vòng thì áp anti-loop và báo điều còn thiếu; không bịa câu hỏi để kéo dài.

Output cuối gồm decision tự chốt, authority decision từ User, assumptions còn lại và tác động tới spec/plan/tasks.
