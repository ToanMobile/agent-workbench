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

Mỗi NHÁNH là một PR, một merge-gate và một lượt gate (`post-fix-gate --scoped`, tự leo `--full` khi đụng file lõi); nhiều nhánh nhỏ làm gate chạy đè nhau và máy quá tải
(23/10: load 112 trên 12 lõi). Vì vậy **gom, đừng tách**: cùng chủ đề thì gom vào một thẻ (mục này), khác chủ đề thì vào một ĐỢT (mục 🚃 dưới).
- Việc mới cùng loại (`bug` / `feature` / `qa`) **tự nhập vào thẻ Backlog hoặc Ready chưa chạy** (Ready đã có PR mở head `issue-<số>-` là đã chạy, không nhận): script chọn thẻ trùng đường dẫn file nhiều
  nhất (hòa thì thẻ mới nhất), thêm dòng AC vào mục `## Acceptance Criteria` của thẻ đó và Problem/Fix vào mục `## Gộp thêm: <tiêu đề>`.
  Agent không cần tự chọn thẻ, không cần gọi `--merge-into`.
- Nhiều việc nhỏ trong cùng một lượt: tạo **một** thẻ có nhiều dòng AC, không gọi script mỗi việc một lần.
- Việc phát hiện giữa chừng mà không gấp: nhập vào thẻ chưa chạy (bằng chính lệnh tạo thẻ), không mở thẻ lẻ.
- Sửa một lỗi gốc cho nhiều chỗ, hay một nhóm suite/test cùng nguyên nhân: **một thẻ, nhiều commit**, không một thẻ mỗi chỗ.
- Mở thẻ riêng chỉ khi có lý do thật và nói rõ bằng `--new-card "<lý do>"`: việc độc lập cần PR riêng, khác repo (`--repo`).
  Thẻ không nhận thêm khi tổng dòng AC (cũ + mới) vượt trần `MAX_CARD_AC` (mặc định 12, đặt `SB_MAX_CARD_AC=<số>` để đổi; #369: thẻ gom phình tới build 7873 s). Không tách thẻ vì diff dài: không còn trần 400 dòng. Thẻ cần người (`--needs-you`),
  khác loại với mọi thẻ chưa chạy, `--from-file` và không có thẻ chưa chạy thì script tự tạo thẻ mới. Không đọc được board thì tạo thẻ mới và cảnh báo. Không đọc được PR mở thì không gom vào Ready, vẫn gom vào Backlog.
- Rủi ro 🟢 và 🟡 đều gom; chỉ việc 🔴 High, hoặc có `--blocked-by`, mới thành thẻ riêng (24/10: trước đây chỉ 🟢 gom, mà gần
  như mọi thẻ ghi 🟡 nên cơ chế gom không bao giờ chạy).
- Thẻ đã ở Building / QA / Review / Done, hoặc Ready đã có PR mở `issue-<số>-`, không nhận thêm việc: việc mới nhập vào thẻ chưa chạy khác hoặc mở thẻ mới.
- **Chỉ gom cùng chủ đề** (T0054, 24/10): thẻ nhận gom phải cùng scope cụ thể trong tiêu đề (`🐛 [fix] gate: …`; scope chung
  chung `task`/`misc`/`general`/`chore` không tính) hoặc trùng ít nhất một đường dẫn file; tổng mục AC sau gom không vượt `MAX_CARD_AC` (trên).
  Script tự áp; khác chủ đề thì ra thẻ mới. (#344 cache gate bị gom vào #319 "bằng chứng test" rồi kẹt; #315 ôm 10+ AC, builder
  làm một phần rồi đóng cả thẻ.)
- **Gom tay (orchestrator gộp thẻ có sẵn) phải chép AC NGUYÊN VĂN** vào mục `## Acceptance Criteria` của thẻ nhận (giống
  `merge_body`), rồi mới đóng thẻ nguồn kèm link. Cấm dòng AC kiểu "AC của thẻ #X đạt (xem thẻ đó)": AC ở thẻ khác là AC không
  ai đếm (merge gate có đọc #X để đếm, nhưng builder vẫn dễ bỏ sót). Cấm gom phần còn lại của một thẻ vào thẻ khác chủ đề.

---

## 🚃 Đợt: nhiều thẻ, một nhánh, một PR, một lần gate (#724)

Gom thẻ chỉ nhận việc cùng chủ đề (T0054), nên 5 việc khác scope từng là 5 nhánh, 5 gate, 5 merge gate. Đợt giữ thẻ RIÊNG (AC
riêng, đóng riêng) nhưng build chung:
- Việc không gom được (khác chủ đề, hoặc thẻ đủ trần AC) **tự vào đợt** của thẻ chưa chạy cùng loại, build được, không 🔴 High
  (thẻ trưởng; số lớn nhất trước; không nhận thẻ trưởng `ac-open`). Script chỉ ghi trên chính thẻ mới: `## Blocked by` =
  `- #<trưởng> — đợt: …` + marker `<!-- sb:batch-of #<trưởng> -->` + nhãn `waiting-on:#<trưởng>` (runner không giao thẻ Ready mang
  nhãn này; sweep gỡ nhãn khi thẻ trưởng đóng); in `🚃 Vào đợt #N`. Không sửa thẻ trưởng. Không tạo được nhãn thì thẻ đứng riêng.
- Trần đợt (#369): `SB_MAX_BATCH_CARDS` (mặc định 5 thẻ kể cả thẻ trưởng) và `SB_MAX_BATCH_AC` (mặc định 16 mục AC cộng mọi thẻ).
  Vượt thì thẻ mới đứng riêng và thành thẻ trưởng của đợt sau; gom cùng chủ đề vào thẻ trưởng cũng không được làm đợt vượt trần.
  Đợt chốt lúc tạo thẻ, không chờ gom (bài học #679).
- Vẫn riêng: 🔴 High, `--blocked-by`, `--needs-you`, `--new-card`, `--from-file`, nhãn ngoài bug/feature/qa, khác loại, repo chưa bật
  đợt (`PROJECT_REGISTRY[...]["batch"]`; hiện chỉ agent-workbench — merge gate repo khác chưa hiểu marker).
- **Builder thẻ trưởng** (người hay lane): `python3 .agents/devkit/scripts/governance/card_batch.py plan --lead <N>` in danh sách thẻ.
  Một worktree, một nhánh `issue-<N>-…`; mỗi thẻ một (vài) commit, subject kết thúc `(#m)`; PR body một dòng `Closes #x` cho MỖI
  thẻ (GitHub chỉ đóng thẻ đầu với `Closes #1, #2`), đặt NGOÀI khối `<!-- sb:status -->` (lane QA/Review ghi đè khối đó), ví dụ sau
  `<!-- /sb:risk -->`; khối sb:ac liệt kê AC của mọi thẻ, dòng của thành viên dạng `- [x] [#m] <AC>`
(`[#m]` sau ô tích, không trước gạch đầu dòng). Một lần
  gate scoped, một merge gate. Merge gate nhận Closes của thẻ mang marker đợt của nhánh và đếm AC của nó; còn dòng chưa tick thì
  KHÔNG thẻ nào trong đợt tự đóng (Refs cả đợt, thẻ trưởng `ac-open`).
- **Một thẻ bị chặn** (review, xung đột, AC không đạt): `card_batch.py split --lead <N> --card <M> --reason "<lý do>" --pr <P>`
  trong worktree của đợt: revert đúng commit `(#M)` (một chuỗi, xung đột thì abort cả chuỗi), thẻ M về `Blocked by - None.` và
  gỡ nhãn `waiting-on:#N` (thẻ riêng), PR bỏ `Closes #M` cùng dòng `[#M]` và các dòng `↳` của nó.
  Chạy lại gate một lần rồi push; phần còn lại merge. Revert xung đột: exit 5, cây như cũ.

Ví dụ 5 thẻ khác scope, cùng loại, ≤ 16 AC: trước 5 gate + 5 merge gate; giờ 1 gate + 1 merge gate (tách 1 thẻ: +1 gate lại).

---

## 🛠️ Công Cụ Thực Thi

Công cụ cốt lõi được đặt tại:
`.agents/devkit/scripts/governance/create_task.py`

### 1. Tạo từ mô tả nhanh của người dùng
Khi người dùng gõ `/createTask <nội dung>`:
```bash
python3 .agents/devkit/scripts/governance/create_task.py "$ARGUMENTS"
```
Agent có thể tự làm giàu nội dung thành đầy đủ 6 phần (Problem, Context, Fix, AC, Risk, Blocked by) rồi gọi:
```bash
python3 .agents/devkit/scripts/governance/create_task.py \
  --title "🐛 [bug] <scope>: <what>" \
  --problem "<nội dung problem>" \
  --fix "<nội dung fix>" \
  --ac "AC 1" --ac "AC 2" \
  --risk "🟢 **Low** · <mô tả>"
```

`--ac` lặp lại cho mỗi điều kiện; câu thường tự thành `- [ ] …` (pre-flight chỉ đếm dòng dạng danh sách). Đừng ghép nhiều AC bằng `\n` trong ngoặc kép: shell gửi nguyên chữ `\n` và ra một mục.

Thẻ được gom vào thẻ có sẵn thì script in `🧺 Đã gom ... vào thẻ chưa chạy #N` và không tạo issue; trả link thẻ #N cho người dùng.
Thẻ vào đợt thì script in `🚃 Vào đợt #N` rồi tạo issue như thường; trả link thẻ mới kèm "đợt #N".
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
python3 .agents/devkit/scripts/governance/create_task.py \
  --title "🧪 [test] viewer: kiểm DOCX 20 MB trên máy thật" --problem "..." \
  --ac "- [ ] Mở DOCX 20 MB trên thiết bị thật không crash" \
  --needs-you "Cắm Pixel 7 thật, mở file DOCX 20 MB, chụp màn hình kết quả vào issue"
```

### 1c. Thẻ về repo khác: luôn chỉ repo đích
Mặc định thẻ nằm ở repo của checkout đang đứng (theo `git origin`) và đi vào board của repo đó. Thẻ có việc ở repo
khác (Goods, Idle-Plaza-3D, GeelyEx2, OfficeReader, Humans-vs.-UFOs) phải đi với `--repo`, để issue và card nằm ở đúng repo và đúng board:
```bash
python3 .agents/devkit/scripts/governance/create_task.py --repo ToanMobile/GeelyEx2 \
  --title "🔧 [chore] GeelyEx2: merge PR #82" --problem "..." --ac "- [ ] PR #82 merged"
```
Tiêu đề hoặc body nhắc tên repo khác mà thiếu `--repo` thì script thoát exit 64 và chưa tạo gì. Việc chạm hai repo:
tạo một thẻ mỗi repo. Thẻ thật sự về repo đang đứng, chỉ lấy repo kia làm ví dụ: thêm `--here`.
Chế độ `--from-file` (mục 2) không bị kiểm: ticket thuộc backlog của chính checkout đang đứng.

### 2. Đẩy một ticket có sẵn từ file backlog
Khi người dùng muốn đẩy ticket số N từ file [`docs/super-board/backlog-tickets.md`](file:///Volumes/Data/Toan/agent-workbench/docs/super-board/backlog-tickets.md):
```bash
python3 .agents/devkit/scripts/governance/create_task.py \
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
