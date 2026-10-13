# Plan C+D — không ai sửa trong main, một bộ gộp tuần tự (chưa duyệt, chưa code)

Ngày 13/10/2026. Người dùng yêu cầu lập plan để làm sau. Trạng thái: **bản nháp chờ duyệt (Gate 1, `AGENTS.md` §5.1)**: chạm hook, khoá phiên và luật cô lập (Gate 2), nên không code trước khi người dùng duyệt.

## 1. Vấn đề, có số đo (13/10)

Ba phiên cùng mở trên `agent-workbench` (`d1df0d47`, `cd6390a4`, `c01ac57e`) và ngồi đợi nhau:

- **Chờ do chính sách ở 2 chỗ, không do git.** `bin/session_lock.py` coi `agent-kit worktree finish|automerge` là ghi vào main (regex `GATE`, dòng 74); `hooks/worktree_merge_gate.sh` (dòng ~297–301) không gộp khi main có người giữ. `worktree.py automerge` đã tự từ chối khi trùng file sửa dở.
- **Chỉ trùng 1 file** trong commit 6 file đang chờ (`CHANGELOG.md`, do mục Đợt 31 của phiên khác).
- **Gate chậm và không ổn định:** 171 s, 507 s, 572 s, 884 s, một lần chạm 900 s; `test_worktree_merge_gate_owner.sh` đỏ ở cả 4 lần gate gần nhất. Load máy 195–344 khi 3 phiên cùng chạy.
- **Worktree mồ côi:** 7 thư mục `GeelyEx2-*`, 142–218 MB mỗi cái (gốc: cờ `uchg`, đã sửa ở Đợt 30). Đĩa `/Volumes/Data` đang 92–93 % đầy, còn ~11 GiB.

Gốc chung: **có một checkout chính mà người ta vừa sửa vừa dùng làm nơi gộp**, nên luôn có "người giữ main".

## 2. Đích

- **C. Không ai sửa trong main.** Main chỉ là nơi gộp. Mỗi phiên làm trong worktree riêng của phiên đó.
- **D. Một bộ gộp tuần tự.** Mỗi lần một worktree: gộp main vào worktree (xử lý conflict ở đó), kiểm bằng gate nhẹ, rồi `ff-only` vào main. Hàng đợi dùng khoá `MAIN_LOCK` đã có trong `_automerge_locked`.
- Kết quả mong muốn: hết "đợi người giữ main", HEAD main không bị phiên nào giữ nên không nhảy dưới chân ai, mỗi phiên tự gộp xong mà không cần người dùng gõ.

## 3. Thiết kế (bản lười: dùng lại cái đã có)

| # | Việc | Cách làm | Đã có sẵn |
|---|---|---|---|
| C1 | **Tạo worktree lười, theo phiên** | Lần ghi đầu tiên vào main của một phiên bị chặn, và hook tự chạy `agent-kit worktree add ../<repo>-<sid8>` rồi báo đường dẫn để phiên làm tiếp trong đó. Phiên chỉ đọc không tạo gì. Một phiên một worktree, tái dùng cho mọi việc của phiên. | `session_lock.py` đã chặn ghi và đã trỏ sang worktree; `worktree add` đã có; `worktree_guard` đã hiểu phiên đang ở trong worktree |
| C2 | **Main chỉ-gộp** | Ghi vào main chỉ cho (a) bộ gộp `finish`, (b) người dùng bằng công tắc `allow-shared`. Không còn khái niệm "người giữ main". | khoá phiên, `allow-shared` |
| D1 | **Bộ gộp** | Bỏ nhánh "main không rảnh thì không gộp" trong hook và bỏ `finish|automerge` khỏi `GATE`. Giữ `git merge --ff-only` và `MAIN_LOCK`. Trùng file sửa dở thì giữ lại, báo đúng tên file. | `_automerge_locked`, `MAIN_LOCK` |
| D2 | **Gate nhẹ khi gộp, full một lần** | Gộp chỉ cần gate test bị ảnh hưởng của worktree exit 0. `--full` chạy một lần ở cuối (phiên cuối hoặc nightly), theo đúng luật hiện có của DevKit; **không bỏ gate nào**. | `--run-tests`, chế độ impacted, `--force-full` |
| D3 | **File nóng không conflict** | `.gitattributes`: `CHANGELOG.md merge=union`, `.agents/instincts.md merge=union`. File bookkeeping của gate (`CHECKLIST.md`, `regression_status.json`, `instincts-index.md`) đã bị loại khỏi diff của worktree. | `BOOKKEEPING` trong `worktree.py` |
| D4 | **Dọn sạch** | Stop gộp rồi xoá worktree (đã có), kèm sửa `uchg` của Đợt 30 nên không còn mồ côi. Cộng một lệnh `worktree status` liệt kê cả thư mục mồ côi (hiện không ai thấy chúng). | `cmd_remove`, `worktree status` |

## 4. Điều kiện tiên quyết (làm trước, độc lập với C+D)

1. **Sửa race của `worktree_merge_gate`**: hàng "gate error" cho thư mục vừa biến mất phải tính là đã xong, không phải đang giữ (`hooks/worktree_merge_gate.sh`, bộ lọc `vanished` bỏ qua hàng có `reason`). Nên chạy `inventory` riêng cho từng worktree để một thư mục mất không làm hỏng cả danh sách. Không có bước này, gate đỏ ngẫu nhiên làm mọi so sánh hiệu quả vô nghĩa.
2. **Gộp các commit đang chờ**: `aaf9805` ở `agent-workbench-dot30b` (xem `handoff-2026-10-13-gom-3-phien-chay-full-mot-lan.md`) phải vào main trước khi đổi luật.
3. **Đo cơ sở** (hiện chưa có số): thời gian `worktree add` kèm cài DevKit, thời gian `finish`, thời gian đợi khoá, dung lượng mỗi worktree. Ghi vào log gate để so trước và sau.

## 5. Lộ trình

| Pha | Việc | Kiểm chứng (ĐỎ→XANH) | Dừng nếu |
|---|---|---|---|
| 0 | Mục 4: sửa race, đo cơ sở | test race tất định (chèn lỗi cho `inventory`), số đo cơ sở có trong log | race vẫn đỏ sau sửa |
| 1 | **D1+D3+D4** trong một repo thử (`agent-workbench`) | 2 phiên cùng repo không ai đợi; trùng file thì giữ lại và báo tên file; hai worktree gộp cùng lúc nối đuôi nhau | HEAD main nhảy làm gate phiên khác hỏng hơn mức chấp nhận |
| 2 | **C1+C2** (tạo worktree lười + main chỉ-gộp) | ghi vào main bị chặn và có worktree sẵn; phiên chỉ đọc không tạo worktree; công tắc tắt hẳn (`WORKTREE_TRUNK_MODE=0`) | một phiên bị kẹt không ghi được ở đâu cả |
| 3 | Lan sang `GeelyEx2`, `OfficeReader` | mỗi repo một vòng đo cơ sở trước và sau | đĩa còn dưới ngưỡng (xem rủi ro) |
| 4 | Cập nhật `AGENTS.md` §7.1, `rules/essentials.md`, thông báo của `session_lock.py`, `CHANGELOG.md` | test văn bản (các test hint đã có) | — |

## 5.1 Test phải có (viết trước, thấy ĐỎ)

1. Hai phiên cùng repo, không phiên nào đợi (`test_worktree_merge_gate_owner.sh` case 4/4b viết lại: gộp khi không trùng, giữ khi trùng).
2. Ghi vào main từ phiên không phải bộ gộp thì bị chặn kèm worktree tạo sẵn (sửa `test_session_lock_target_repo.sh` dòng 253 và thêm case).
3. Phiên chỉ đọc không tạo worktree.
4. Hai worktree gộp đồng thời: tuần tự, không trộn index.
5. `CHANGELOG.md` hai phiên cùng thêm mục: gộp sạch, giữ cả hai.
6. Stop gộp và xoá worktree; thư mục `uchg` vẫn xoá được (`test_worktree_immutable_copy.sh` đã có).
7. Công tắc tắt trả về hành vi cũ.

## 6. Rủi ro và điều chưa biết

- **Đĩa:** mỗi worktree là một bản checkout đầy đủ (17 MB cho `agent-workbench`, nhưng 142–218 MB cho GeelyEx2). Nhiều phiên × nhiều repo ăn nhanh vào 11 GiB còn lại. **Chưa tính được số phiên tối đa**; cần số đo ở pha 0.
- **Repo Unity (Goods, Neighbours-From-Hell):** thư mục `Library` rất lớn nên một worktree mỗi phiên có thể không khả thi. **Giả định chưa kiểm:** loại hai repo này khỏi C, chỉ áp D1 (gộp không đợi) cho chúng.
- **Thói quen làm việc:** nếu bạn mở IDE vào checkout chính để sửa tay thì đó là phiên ghi vào main. Cần quyết: người dùng được miễn (như `allow-shared`) hay cũng đi qua worktree.
- **Thiết bị adb:** một thiết bị phục vụ một worktree tại một thời điểm (luật hiện có), nên nhiều worktree song song vẫn phải chạy thiết bị tuần tự.
- **Memory:** note ghi trong worktree nằm ở thư mục riêng và được chép sang main khi `finish` (đã có), nhưng chưa kiểm khi nhiều worktree cùng ghi một `MEMORY.md`.
- **Hook cài đặt:** các sửa hook phải cài đúng cách; ghi chú cũ trong memory cho biết chế độ tự động có lúc chặn việc cài hook, nên có thể cần bạn xác nhận ở đúng bước đó.
- **Nới luật cô lập phiên:** D1 làm HEAD main nhảy khi phiên khác đang làm; phiên đó có thể phải chạy lại gate một lần. Sửa dở của họ không bao giờ bị ghi đè (git từ chối trên file trùng).
- **Ước lượng công sức: chưa đo.** Không đưa số ngày cho đến khi có số đo cơ sở ở pha 0.

## 7. Cần người dùng quyết trước khi code

1. **Duyệt hướng C+D** (Gate 1) và nới luật cô lập phiên cho D1 (Gate 2, đụng `session_lock.py` và `worktree_merge_gate.sh`).
2. **Phạm vi repo:** chỉ 3 repo không phải Unity ở pha 1–3, đúng không?
3. **Người dùng có miễn trừ** khi sửa tay trong checkout chính không?
4. **Có chấp nhận `--full` chỉ chạy một lần ở cuối** (đúng luật DevKit hiện có) thay vì mỗi phiên?

## 8. Việc còn lại (cập nhật cuối ngày 13/10, đo lúc ~14:00)

### 8.1 Phải làm trước, độc lập với C+D
| # | Việc | Trạng thái đo được | Hành động |
|---|---|---|---|
| 1 | **Gộp worktree `agent-workbench-dot30b` vào main** | `aaf9805` (sửa theo review Đợt 30) và `204750d` (plan này) CHƯA vào main; `e4a16f3`, `33259ef` đã vào main và đã push | Khi phiên `c01ac57e` nhả khoá: khôi phục các bản cũ của chính mình ở main (`worktree.py`, `worktree_sandbox.py`, `test_worktree_immutable_copy.sh`, `.agents/instincts.md`; riêng `CHANGELOG.md` giữ cả mục Đợt 31), chạy `agent-kit worktree finish /Volumes/Data/Toan/agent-workbench-dot30b`, gate `--full --force-full --timeout 2400` exit 0, rồi `git pull --ff-only`/`--no-rebase` (kiểm exit code) và `git push origin main` |
| 2 | **Gate chưa có biên nhận cho `aaf9805` / `204750d`** | Lần đỏ gần nhất: `test_worktree_merge_gate_owner.sh` (race có sẵn); gate trên commit chỉ-Markdown vẫn TIMEOUT 900 s vì `REG-DK-ALL-01` chọn quá nhiều test | Chạy với `--timeout 2400`; điều tra vì sao commit docs kéo cả suite DevKit |
| 3 | **Sửa race `worktree_merge_gate`** | Đỏ ở cả 4 lần gate hôm nay; A/B song song: kit cũ 7/30, kit mới 18/30 lượt đỏ (có nhiễu: một số lượt kit mới chạy trong git worktree) — **chưa chứng minh Đợt 30 không làm xấu thêm** | Sửa hàng "gate error" cho thư mục vừa mất thành "đã xong"; chạy `inventory` riêng từng worktree; viết test tất định (chèn lỗi); đo lại A/B cùng điều kiện |
| 4 | **Xoá 7 thư mục `/Volumes/Data/Toan/GeelyEx2-{car-debug,cardbg,push-1013,push-1013b,push-1013c,regen-persist-sliders,xe-debug}`** | Đã gỡ cờ `uchg`, không có việc nào chỉ nằm trong đó (đối chiếu cây với lịch sử) | Người dùng gõ `! rm -rf …` (hook `hardware_safety_gate` chặn agent). Giải phóng ~1,2 GB |
| 5 | **Kiểm thư mục `/Volumes/Data/Toan/agent-workbench-dashboard`** | Còn thư mục `.agents` rỗng nghĩa, git không còn đăng ký | Đối chiếu nội dung với main rồi xoá |
| 6 | **Worktree của phiên khác, KHÔNG xoá khi chưa rõ chủ** | `agent-workbench-sprite-forge` (12 file sửa dở), `Neighbours-From-Hell-keystore` (3 file + thư mục `keystore/` chưa track), Goods `Goods-Triple-Shelf-Match-3D-mcp` (1 commit `4405395` chưa vào main, 7 file sửa dở của Unity) | Hỏi người dùng; Goods `-mcp`: `agent-kit worktree finish` từ checkout Goods sau khi xem 7 file sửa dở |
| 7 | **Việc dở của hai phiên kia** | `cd6390a4`: chưa chạy `claude mcp list` cho 5 repo sau khi gộp; `c01ac57e`: Đợt 31 OCR (`REVIEW_GATE_OCR=full`, `hooks/review_gate.sh`, `bin/ocr-review`, 4 test mới) chưa commit — xem `docs/plans/goal-100-2026-10-13.md` | Hoàn tất trong phiên đó hoặc phiên mới theo bản bàn giao `handoff-2026-10-13-gom-3-phien-chay-full-mot-lan.md` |

### 8.2 Khoá chính sách (đang chờ người dùng)
Việc nới chính sách khoá cho D1 (xoá `finish|automerge` khỏi regex `GATE` trong `bin/session_lock.py`; bỏ nhánh "main không rảnh thì không gộp" trong `hooks/worktree_merge_gate.sh`; sửa test `test_worktree_merge_gate_owner.sh` case 4/4b và `test_session_lock_target_repo.sh` dòng 253; cập nhật `AGENTS.md` §7.1) **bị hệ thống tự động từ chối ngày 13/10** (nhãn "Security Weaken"). Chưa có thay đổi nào được ghi. Cần người dùng: một câu xác nhận trong chat (agent thử lại), hoặc thêm rule `Edit` cho các đường dẫn trên trong settings.

### 8.3 Thứ tự đề nghị sau khi duyệt
1. Mục 8.1 #1–#3 (gộp, gate, sửa race) → có biên nhận sạch.
2. Pha 0 của mục 5 (đo cơ sở: thời gian `worktree add` kèm cài DevKit, `finish`, thời gian đợi khoá, dung lượng mỗi worktree).
3. Pha 1 (D1+D3+D4) trên `agent-workbench`, rồi pha 2–4 theo mục 5.
4. Dọn 8.1 #4–#6 song song, không chặn.

### 8.4 Chưa đo / chưa kiểm
- Thời gian tiết kiệm của C+D (chưa có số đo cơ sở); công sức triển khai.
- C với repo Unity (Library lớn) và với nhiều thiết bị adb.
- Có xảy ra `HEAD` nhảy làm hỏng gate phiên khác ở mức nào (pha 1 sẽ đo).
