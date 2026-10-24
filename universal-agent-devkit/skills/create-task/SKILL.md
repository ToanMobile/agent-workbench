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

## 🧺 Gom Việc: Ít Thẻ Nhất Có Thể (BẮT BUỘC)

Mỗi thẻ là một PR, một merge-gate và một lần `post-fix-gate --full`; nhiều thẻ nhỏ làm gate chạy đè nhau và máy quá tải
(23/10: load 112 trên 12 lõi). Vì vậy **gom, đừng tách**:
- Việc mới cùng loại (`bug` / `feature` / `qa`) **tự nhập vào thẻ Backlog đang có**: script chọn thẻ trùng đường dẫn file nhiều
  nhất (hòa thì thẻ mới nhất), thêm dòng AC vào mục `## Acceptance Criteria` của thẻ đó và Problem/Fix vào mục `## Gộp thêm: <tiêu đề>`.
  Agent không cần tự chọn thẻ, không cần gọi `--merge-into`.
- Nhiều việc nhỏ trong cùng một lượt: tạo **một** thẻ có nhiều dòng AC, không gọi script mỗi việc một lần.
- Việc phát hiện giữa chừng mà không gấp: nhập vào thẻ Backlog đang có (bằng chính lệnh tạo thẻ), không mở thẻ lẻ.
- Sửa một lỗi gốc cho nhiều chỗ, hay một nhóm suite/test cùng nguyên nhân: **một thẻ, nhiều commit**, không một thẻ mỗi chỗ.
- Mở thẻ riêng chỉ khi có lý do thật và nói rõ bằng `--new-card "<lý do>"`: việc độc lập cần PR riêng, khác repo (`--repo`),
  hoặc thẻ Backlog hiện có đã đủ 6 việc gộp (`MAX_BATCH`, vì PR > 400 dòng đổi phải người duyệt). Thẻ cần người (`--needs-you`),
  khác loại với mọi thẻ Backlog, `--from-file` và Backlog trống thì script tự tạo thẻ mới. Không đọc được board thì tạo thẻ mới và cảnh báo.
- Rủi ro 🟢 và 🟡 đều gom; chỉ việc 🔴 High, hoặc có `--blocked-by`, mới thành thẻ riêng (24/10: trước đây chỉ 🟢 gom, mà gần
  như mọi thẻ ghi 🟡 nên cơ chế gom không bao giờ chạy).
- Thẻ đã ở Building / QA / Review / Done không nhận thêm việc: việc mới nhập vào thẻ Backlog khác hoặc mở thẻ mới.
- **Chỉ gom cùng chủ đề** (T0054, 24/10): thẻ nhận gom phải cùng scope cụ thể trong tiêu đề (`🐛 [fix] gate: …`; scope chung
  chung `task`/`misc`/`general`/`chore` không tính) hoặc trùng ít nhất một đường dẫn file; tổng mục AC sau gom ≤ 8 (`MAX_AC`).
  Script tự áp; khác chủ đề thì ra thẻ mới. (#344 cache gate bị gom vào #319 "bằng chứng test" rồi kẹt; #315 ôm 10+ AC, builder
  làm một phần rồi đóng cả thẻ.)
- **Gom tay (orchestrator gộp thẻ có sẵn) phải chép AC NGUYÊN VĂN** vào mục `## Acceptance Criteria` của thẻ nhận (giống
  `merge_body`), rồi mới đóng thẻ nguồn kèm link. Cấm dòng AC kiểu "AC của thẻ #X đạt (xem thẻ đó)": AC ở thẻ khác là AC không
  ai đếm (merge gate có đọc #X để đếm, nhưng builder vẫn dễ bỏ sót). Cấm gom phần còn lại của một thẻ vào thẻ khác chủ đề.

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

Thẻ được gom vào thẻ có sẵn thì script in `🧺 Đã gom ... vào thẻ Backlog #N` và không tạo issue; trả link thẻ #N cho người dùng.
Thêm `--new-card "<lý do>"` để mở thẻ riêng (xem mục Gom Việc).

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

### 1c. Thẻ về repo khác: luôn chỉ repo đích
Mặc định thẻ nằm ở repo của checkout đang đứng (theo `git origin`) và đi vào board của repo đó. Thẻ có việc ở repo
khác (Goods, NFH, GeelyEx2, OfficeReader) phải đi với `--repo`, để issue và card nằm ở đúng repo và đúng board:
```bash
python3 universal-agent-devkit/scripts/governance/create_task.py --repo ToanMobile/GeelyEx2 \
  --title "🔧 [chore] GeelyEx2: merge PR #82" --problem "..." --ac "- [ ] PR #82 merged"
```
Tiêu đề hoặc body nhắc tên repo khác mà thiếu `--repo` thì script thoát exit 64 và chưa tạo gì. Việc chạm hai repo:
tạo một thẻ mỗi repo. Thẻ thật sự về repo đang đứng, chỉ lấy repo kia làm ví dụ: thêm `--here`.
Chế độ `--from-file` (mục 2) không bị kiểm: ticket thuộc backlog của chính checkout đang đứng.

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
