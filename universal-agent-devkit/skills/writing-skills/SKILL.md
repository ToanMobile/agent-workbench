---
name: writing-skills
description: Dùng khi tạo, sửa hoặc audit skill trong thư mục skills/ của dự án. Bỏ qua khi chỉ sử dụng skill hoặc sửa typo không đổi contract.
---

# Writing Skills (Chuẩn Hóa Kỹ Năng Cho Agent)

## Cấu Trúc Bắt Buộc Của Một Skill

Mỗi skill là một thư mục nằm trong `skills/<skill-name>/` chứa tệp `SKILL.md` mở đầu bằng YAML frontmatter chuẩn:

```markdown
---
name: <kebab-case-name>
description: Dùng khi <ngữ cảnh kích hoạt rõ ràng>. Bỏ qua khi <trường hợp không cần thiết>.
---
```

`disable-model-invocation: true` là hợp lệ và cần cho skill chỉ User được gọi như `session-handoff`. Không áp validator của Codex một cách máy móc lên Codex-only fields.

## Nguyên Tắc Soạn Thảo

1. **Trigger Ngắn Gọn & Chính Xác:** Trường `description` chỉ nêu rõ điều kiện kích hoạt và ranh giới loại trừ; không tóm tắt lại toàn bộ các bước thực hiện.
2. **Dung Lượng Tinh Gọn:** Giữ nội dung `SKILL.md` cô đọng dưới 500 từ. Trỏ tới các rules hoặc templates có sẵn thay vì sao chép trùng lặp.
3. **Một Mục Tiêu Cụ Thể:** Mỗi skill giải quyết một bài toán hoặc một failure mode rõ ràng.
4. **Không Thêu Dệt:** Không bịa đặt tham số công cụ hoặc đường dẫn tệp không tồn tại trong dự án.
5. **Không Tạo Skill Thừa:** Không tạo skill nếu command/rule đã đủ.
6. **Chọn Dạng Theo Failure:** Discipline failure: prohibition ngắn + consequence/evidence. Output-shape failure: recipe tích cực.
7. **Chỉ Dùng Fact Đã Verify:** Không thêm metric, threshold, API/tool field hoặc project fact chưa verify.

## Test Thay Đổi Behavior

1. Mô tả scenario skill phải đổi hành vi và failure/rationalization hiện tại.
2. Viết wording nhỏ nhất chặn failure; không bắt buộc spawn subagent nếu harness/policy không cho phép.
3. Chạy lại scenario hoặc audit fixture/command hiện có; kiểm bằng tay output quan trọng.
4. Rút bỏ phần không ảnh hưởng behavior.

## Checklist Kiểm Định (Skill Validation)

- [ ] YAML Frontmatter hợp lệ, trường `name` trùng khớp với tên thư mục.
- [ ] Mọi đường dẫn tham chiếu trong tệp đều tồn tại thật.
- [ ] Không chứa thông tin nhạy cảm, token, secret hoặc đường dẫn cục bộ cá nhân.
- [ ] Không mâu thuẫn với các quy tắc cốt lõi trong `rules/core-rules.md`.
- [ ] Mọi `@path`, wiki-link, command, rule, knowledge/memory path tồn tại.
- [ ] Markdown fence cân bằng.
- [ ] Skill không tự tạo approval gate.
- [ ] User-only skill giữ `disable-model-invocation: true`; autonomous skill không dùng field này ngoài ý định.
