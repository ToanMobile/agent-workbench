# Mốc đo A — gate DevKit, 2026-10-29 07:27 → 2026-10-30 07:40

Plan ổn định DevKit, thẻ #686 (Pha 1). Đo bằng `universal-agent-devkit/scripts/governance/stabilize_metrics.py` trên bản sao
`runs.jsonl` ở main `46b553fa` (465 dòng; bản sao nằm ngoài repo tại `.claude/audit-gate/stabilize/baseline-A-20261030.jsonl`, 1,1 MB, không commit).
Kiểm kê workflow đi kèm: `docs/audit/workflow-inventory-20261030.md`.

Lệnh đo mốc A và lệnh chạy lại cho mốc B:

```
python3 universal-agent-devkit/scripts/governance/stabilize_metrics.py <runs.jsonl> --repo-prefix agent-workbench \
    [--since <epoch|ISO>] [--until <epoch|ISO>] [--sampler-csv <ngày>.csv] [--json]
```

`--repo-prefix` suy repo từ vị trí của FILE (git common dir của thư mục chứa file), không từ tên `project` của dòng, vì `project` chỉ là tên thư mục
làm việc (`issue-NNN-build`, `scoped-gate`, `.merge-scratch-*`… không chứa tên repo). File nằm trong repo `agent-workbench` thì mọi dòng được giữ,
chỉ loại `ocr-*` (mốc A: 23 dòng của `ocr-605`; `meta.dropped_projects` liệt kê phần bị loại).

Số liệu dưới đây tính lại bằng script sau vòng sửa review (B9: `suites` chỉ liệt kê suite đã chạy hoặc không PASS; con số chính của `rerun_on_red`
chỉ sau lượt exit 1; `false_red_pct` định nghĩa lại). Bản trước của tài liệu này có `suites_per_run` trừ `suites_reused` hai lần và `false_red_pct` quá thấp.

## 1. Bảng số

Cột "Cả mốc A" là cả 465 dòng trừ `ocr-*` (442 lượt). Cột "Cửa sổ handoff" cắt đúng 29/10 17:51 → 30/10 07:03 để đối chiếu số đã biết.

| Chỉ số | Cả mốc A (442 lượt) | Cửa sổ handoff (280 lượt) | Số trong handoff |
|---|---|---|---|
| `rerun_on_red` (chỉ sau lượt exit 1) | 51 lượt / 10,76 h | 34 lượt / 6,36 h | 48 lượt / 8,5 h |
| — theo nguồn | cli 37 / 8,11 h; hook 14 / 2,65 h | cli 22 / 3,73 h; hook 12 / 2,63 h | |
| chạy lại sau exit 2/3 (gate chặn, báo riêng) | 44 lượt / 4,96 h: edited_test 43 / 4,63 h; matrix 1 / 0,33 h | 12 lượt / 1,52 h: edited_test 11 / 1,19 h; matrix 1 / 0,33 h | |
| `busy_pct` (trường `busy` true) | 36,2 % (160/442) | 39,6 % (111/280) | 111/280 |
| `busy_pct` theo exit 4 | 27,4 % (121/442) | 36,4 % (102/280) | |
| `machine_hours` (tổng `total_wall_s`) | 71,90 h | 41,18 h | |
| — lượt full nặng (≥ 40 suite) | 37,27 h (152 lượt) = 51,8 % | 32,50 h (143 lượt) = 78,9 % | |
| `false_red_pct` | 11,9 % (16/135 FAIL) | 7,6 % (7/92 FAIL) | |
| `merge_gate_s`, mọi lượt `merge_point` | median 944,2; p90 1444,4 (n = 19) | median 895,4; p90 1311,8 (n = 14) | median 909; p90 1316 |
| `merge_gate_s`, chỉ lượt PASS | median 1063,2; p90 1341,4 (n = 8) | median 909,0; p90 1202,4 (n = 5) | |
| `scoped_escalated_pct` | 92,1 % (152/165) | 94,9 % (149/157) | |
| `suites_per_run` (suite chạy thật) | median 38,0; p90 51,0 (n = 263) | median 47,0; p90 51,0 (n = 169) | |
| `load_median` | không có CSV sampler cho 29/10 | 48,74 (n = 1: CSV chỉ bắt đầu 30/10 07:01) | |
| `load_median`, 30/10 07:01 → 07:40 | 24,3 (p90 46,3; n = 71 mẫu) | | |

Đọc nhanh: hơn nửa giờ máy (51,8 %) nằm ở lượt full nặng; 92 % lượt `--scoped` bị leo lên full vì khớp lõi; hơn một phần ba lượt gate dính khoá bận;
16 trong 135 lượt FAIL (11,9 %) là đỏ giả: suite đỏ chạy lại và xanh trên cùng nội dung (cùng `fp`); chạy lại cùng fp sau exit 1 tốn 10,76 h, và thêm
4,96 h chạy lại sau lượt gate chặn exit 2/3, gần như toàn `edited_test` (quy trình duyệt test, không phải đỏ).

## 2. Định nghĩa

Đầy đủ trong docstring đầu `stabilize_metrics.py`. Tóm tắt:

- `rerun_on_red`: lượt chạy lại cùng `project` + `fp` + `mode` ngay sau một lượt exit 1. Lượt BUSY (exit 4) ở giữa trong suốt; lượt khác `fp` xen giữa làm đứt chuỗi;
  dòng không có `fp` bị bỏ. Chạy lại sau exit 2/3 báo riêng. Chưa có chỗ loại lượt "flaky": gate không ghi cờ đó vào `runs.jsonl`, nên không có nguồn để loại.
  Giờ máy = tổng `total_wall_s` của các lượt chạy lại.
- `busy_pct`: số chính là trường `busy` true; số phụ là exit 4.
- `machine_hours`: tổng `total_wall_s`. Full nặng = (`mode` full hoặc `force_full`) và ≥ 40 suite (`max(len(suites), len(ran_suites)) + suites_reused`), trừ lượt exit 4.
- `false_red_pct`: lượt FAIL là đỏ giả khi mọi suite đỏ của nó (trạng thái khác PASS và UNTESTED) nằm trong `suites`/`ran_suites` của một lượt exit 0 cùng `fp` về sau.
  Lượt xanh chỉ liệt kê suite đã chạy lại, nên không so cả tập suite. FAIL không ghi suite đỏ nào đếm riêng (`undetermined`; mốc A: 0).
- `merge_gate_s`: `total_wall_s` của lượt `merge_point` true; phân vị nội suy tuyến tính.
- `scoped_escalated_pct`: trong lượt `--scoped` (mode scoped hoặc `force_reason` chứa `--scoped`), phần có `force_reason` chứa `--scoped → full`.
- `suites_per_run`: `max(len(ran_suites), số suite trong suites có giây chạy)`. Suite dùng lại chỉ nằm trong `suites_reused` nên không trừ đi; bỏ lượt không chạy suite nào.
- `load_median`: trung vị cột `load1` trong CSV của `com.toanmobile.devkit.capacity.sampler`.

## 3. Đối chiếu với handoff

Cùng cửa sổ 29/10 17:51 → 30/10 07:03, lệnh `--repo-prefix agent-workbench`:

- Tổng lượt 280 và `busy` 111/280 khớp tuyệt đối. Handoff dùng trường `busy`; theo exit 4 chỉ còn 102.
- Merge gate median 909 s khớp số của riêng lượt PASS (n = 5). Gộp mọi lượt `merge_point` (kể cả đỏ) thì median 895,4. p90 handoff 1316 s so với
  1311,8 s (mọi lượt) của script: lệch nhỏ do cách tính phân vị (script nội suy tuyến tính, n chỉ 14).
- `rerun_on_red`: con số chính nay là 34 lượt / 6,36 h (chỉ sau exit 1), thấp hơn 48 lượt / 8,5 h của handoff. Chạy lại sau exit 2/3 là 12 lượt / 1,52 h; cộng cả hai
  là 46 lượt / 7,88 h, gần số handoff hơn (đây chính là con số của bản script trước, khi chưa tách exit 2). Chưa tái hiện được 48 chính xác vì không rõ định nghĩa gốc.
  Lệch còn lại nằm ở cách xử lý BUSY và `mode` (bỏ điều kiện cùng `mode` cho 51 lượt / 9,51 h khi cộng cả exit 2/3).
- `false_red_pct`: handoff không có số này. Bản script trước báo 9/135 (6,7 %) vì đòi cùng tập suite; định nghĩa đúng cho 16/135 (11,9 %).

## 4. Giới hạn của số liệu

- `runs.jsonl` **không có SHA commit**: hai lượt cùng `fp` ở hai worktree là cùng nội dung nhưng không biết là cùng commit hay chỉ cùng cây.
- Gate **bỏ dòng dài hơn 3000 byte**: các lượt full (≥ 50 suite) bị cắt `suites`/`ran_suites`/`changed_files` (cờ `*_cut`; 260 dòng `suites_cut`).
  Khi cắt, gate bỏ các mục PASS trước, nên `suites_per_run` của lượt full là cận dưới; `changed_files` bị cắt ở 50 phần tử.
- `false_red_pct` là xấp xỉ: "suite đỏ chạy lại và xanh cùng `fp`" gợi ý flaky hoặc hạ tầng, không chứng minh. Một suite xanh ở lượt sau cũng có thể do sửa môi trường (cùng nội dung code).
  Danh sách bị cắt có thể làm lượt xanh thiếu suite, nên đây là cận dưới.
- `project` là tên thư mục, không phải tên repo; `--repo-prefix` dựa vào vị trí file đầu vào. Một file chép ra ngoài mọi repo git (vd `/tmp`) quay về so tên
  `project` với tiền tố, và sẽ loại các worktree đặt tên khác.
- `busy` không phải exit 4: có 40 lượt `exit 2` mang `busy` true (chờ khoá rồi gate chặn vì lý do khác).
- Sampler chỉ có CSV từ 30/10 07:01 (không có file 2026-10-29), nên `load_median` của cả ngày mốc A chưa đo được; số ở trên là cửa sổ 39 phút cuối.
- `total_wall_s` của lượt BUSY gồm thời gian chờ khoá nên `machine_hours` không phải giờ CPU, và các lượt chạy song song cộng dồn (71,9 h giờ máy trong khoảng 24 h).
- Một mốc 24 giờ, một repo: chưa đủ để so sánh thống kê; dùng làm điểm tham chiếu cho mốc B sau Pha 1.
