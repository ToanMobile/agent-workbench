---
name: create-task
description: "Tự động tạo task chuẩn Super-Board (Problem, Context, Fix, AC, Risk) và đẩy trực tiếp lên cột Backlog của GitHub Project Board #1 (https://github.com/users/ToanMobile/projects/1/views/2). Kích hoạt khi gõ /createTask, /create-task, hoặc khi người dùng yêu cầu 'tạo task', 'đẩy lên backlog'."
---

# Create Task & Push to Backlog (Super-Board)

Skill này giúp tự động hóa việc khởi tạo task theo đúng quy chuẩn **Super-Board** ([`docs/agents/issue-tracker.md`](file:///Volumes/Data/Toan/agent-workbench/docs/agents/issue-tracker.md)) và đẩy trực tiếp lên cột **Backlog** của [GitHub Project #1](https://github.com/users/ToanMobile/projects/1/views/2).

---

## 🎯 Quy Chuẩn Định Dạng Bắt Buộc (Super-Board Standard)

Mỗi Task tạo ra BẮT BUỘC phải tuân thủ cấu trúc sau:
1. **Title:** `<emoji> [<kind>] <scope>: <what>` (dưới 70 ký tự, không chứa số issue):
   - 🐛 `[bug]` cho các lỗi, crash, sai logic.
   - ✨ `[feature]` cho tính năng mới.
   - 🔧 `[chore]` / 📝 `[docs]` / 🧪 `[test]` được map vào label `feature`.
   - 🔍 `[qa]` cho các task kiểm thử chất lượng.
2. **Body:**
   - `## Problem`: 1–3 câu mô tả lỗi/thiếu sót từ góc nhìn người dùng/hệ thống.
   - `## Context`: Bắt buộc chia bước có chữ cái đầu dòng (`a.`, `b.`), tuyệt đối KHÔNG dùng mũi tên `->`.
   - `## Fix`: Giải pháp kỹ thuật 1–3 dòng.
   - `## Acceptance Criteria`: 2–5 dòng checkable `- [ ]`, tuyệt đối không ghi chung chung "chạy ổn".
   - `## Risk`: 🟢 **Low** / 🟡 **Medium** / 🔴 **High** + 1 dòng giải thích.
   - `## Blocked by`: `- #N — why` hoặc một dòng `- None.`.

---

## 🛠️ Công Cụ Thực Thi

Công cụ cốt lõi được đặt tại:
[`universal-agent-devkit/scripts/governance/create_task.py`](file:///Volumes/Data/Toan/agent-workbench/universal-agent-devkit/scripts/governance/create_task.py)

### 1. Tạo từ mô tả nhanh của người dùng
Khi người dùng gõ `/createTask <nội dung>`:
```bash
python3 universal-agent-devkit/scripts/governance/create_task.py "$ARGUMENTS"
```
Agent có thể tự làm giàu nội dung thành đầy đủ 6 phần (Problem, Context, Fix, AC, Risk, Blocked by) rồi gọi:
```bash
python3 universal-agent-devkit/scripts/governance/create_task.py \
  --title "🐛 [bug] <scope>: <what>" \
  --problem "<nội dung problem>" \
  --fix "<nội dung fix>" \
  --ac "- [ ] AC 1\n- [ ] AC 2" \
  --risk "🟢 **Low** · <mô tả>"
```

### 1b. Thẻ chỉ người làm được (máy thật, playtest, store, secret, quyết định)
Thêm `--needs-you "<ĐÚNG việc người phải làm>"` (và `--needs-you-next "<xong thì làm gì>"`, mặc định
"gỡ nhãn needs-you rồi kéo thẻ về Ready"). Script thêm mục `## Cần người` lên đầu body, rồi gọi
`.claude/bin/super-board-needs-you.py mark` của repo: nhãn `needs-you` (hiện ngay trên thẻ) + một comment
`🙋 Cần bạn: … · xong thì …`. Không truyền cờ mà MỌI dòng AC khớp cụm "chỉ người làm được" (thiết bị thật, playtest,
Play Console, IARC, đặt secret, chốt thiết kế…) thì tự đánh dấu bằng dòng AC đầu tiên; AC trộn (lane còn phần code)
chỉ in gợi ý, QA/Review đánh dấu khi thẻ dừng ở bước của người; `--no-needs-you` tắt việc này. Thẻ tự đánh
dấu có bước sau mặc định "dán bằng chứng vào issue rồi đóng issue" (không còn việc cho lane).
Repo chưa có helper: vẫn gắn nhãn lúc tạo issue và in cảnh báo. Đánh dấu thất bại: issue đã tạo, exit 3.
```bash
python3 universal-agent-devkit/scripts/governance/create_task.py \
  --title "🧪 [test] viewer: kiểm DOCX 20 MB trên máy thật" --problem "..." \
  --ac "- [ ] Mở DOCX 20 MB trên thiết bị thật không crash" \
  --needs-you "Cắm Pixel 7 thật, mở file DOCX 20 MB, chụp màn hình kết quả vào issue"
```

### 2. Đẩy một ticket có sẵn từ file backlog
Khi người dùng muốn đẩy ticket số N từ file [`docs/super-board/backlog-tickets.md`](file:///Volumes/Data/Toan/agent-workbench/docs/super-board/backlog-tickets.md):
```bash
python3 universal-agent-devkit/scripts/governance/create_task.py \
  --from-file docs/super-board/backlog-tickets.md \
  --ticket <N>
```

### 3. Đẩy hàng loạt tickets
```bash
python3 docs/super-board/push-to-github-board.py --apply --ticket 1..5
```

---

## 📋 Sau Khi Tạo Thành Công
1. Trả về link GitHub Issue vừa tạo.
2. Xác nhận card đã nằm trên cột **Backlog** tại:
   👉 [https://github.com/users/ToanMobile/projects/1/views/2](https://github.com/users/ToanMobile/projects/1/views/2)
