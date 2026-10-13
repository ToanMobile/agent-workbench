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
