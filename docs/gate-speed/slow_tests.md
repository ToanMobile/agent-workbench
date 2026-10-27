# Test chậm của DevKit: số đo 27/10 và đề xuất tách

Số đo: chạy từng test một lần, lần lượt, từ kit của worktree `gate-speed-prep` (`bash universal-agent-devkit/<test>`), máy 12 core, ngày
2026-10-27 lúc 14:27–15:10. Tải 1 phút lúc đó từ 12 đến 35 (gấp 1–3 lần số core), vì các phiên khác chạy cùng và gate impacted của chính
worktree này chạy song song với 8 test sau. Mỗi test chỉ đo một lần nên số đo nhiễu. Cột "ghi" lấy từ `tests/lib/test_durations.txt`
(đo 04/10 với 4 job, file này chỉ để xếp thứ tự).

| test | ghi (s) | đo (s) | load1 đầu → cuối | rc |
|---|---:|---:|---|---|
| tests/context_memory/test_local_tier.sh | 71 | **635.0** | 18.7 → 35.4 | 0 |
| tests/installer/test_install_idempotency.sh | 61 | **346.8** | 34.6 → 13.9 | 0 |
| tests/installer/test_install_cli.sh | 77 | **314.5** | 13.1 → 13.1 | 0 |
| tests/gates/test_gate_stop_reuse_race.sh | 100 | **183.7** | 27.5 → 32.7 | 0 |
| tests/gates/test_proof_capture_lock.sh | 100 | 112.4 | 22.1 → 27.5 | 0 |
| tests/gates/test_gate_budget_resume.sh | 90 | 97.7 | 28.6 → 12.3 | 0 |
| tests/gates/test_evidence_false_blocks.sh | 77 | 66.6 | 13.1 → 30.0 | 0 |
| tests/worktree_git/test_worktree_trunk_merge.sh | 75 | 51.6 | 30.0 → 18.7 | 0 |
| tests/worktree_git/test_trunk_main_pending_writers.sh | 70 | 42.9 | 35.4 → 34.6 | 0 |
| tests/gates/test_postfix_gate.sh | 82 | 41.3 | 12.3 → 13.1 | 0 |
| tests/gates/test_unity_proof.sh | **150** | 6.2 | 23.1 → 22.1 | 0 |

## Kết luận

1. **Test "dài nhất 150 s" không còn dài.** `test_unity_proof.sh` hết 6,2 s: ca Unity treo bị giết sau `--timeout 2`, và `sleep 30` của
   Unity giả không bao giờ chạy hết. Số 150 trong `test_durations.txt` đã lỗi thời. Cần đo lại cả file này, vì run_impacted xếp thứ tự
   chạy theo nó.
2. **Đuôi dài thật là nhóm cài đặt.** `test_local_tier` (635 s), `test_install_idempotency` (347 s) và `test_install_cli` (315 s) chạy
   `bin/install.sh` hoặc `agent-kit` vào repo tạm, và nay chậm gấp 4–9 lần số ghi. `commands/*`, `adapters/*` và
   `scripts/git/backup_conflict.sh` trong `impact_map.txt` kéo cả ba vào lượt impacted, nên đổi một file lệnh là gate tốn hơn 20 phút.
   Giả thuyết (chưa kiểm): mỗi lần cài nay làm nhiều việc hơn hồi 04/10 (thêm hook, relink skill, git init, chép kit). Các test này có
   `sleep` tổng cộng gần 0 s, nên thời gian không nằm ở chỗ chờ.
3. `test_gate_stop_reuse_race.sh` (184 s) chạy tuần tự khoảng 30 kịch bản. Mỗi kịch bản gọi một gate thật có `tl 240`: K1 gồm
   4 hàng × 4 cách, K2 gồm 6, K6 gồm 4.
4. `test_proof_capture_lock.sh` (112 s) đã có sẵn `LOCK_TEST_ONLY` để chọn ca theo id.

## Đề xuất tách (chưa làm)

| test | cách tách | lợi dự kiến |
|---|---|---|
| test_local_tier, test_install_idempotency, test_install_cli | Bước 1: đo từng lần gọi `install.sh` (bọc `time`, hoặc trace `bash -x` có mốc thời gian) để tìm bước chậm, sửa ở `install.sh` thay vì sửa test. Bước 2: dùng chung MỘT lần cài cho các ca chỉ đọc kết quả cài (dựng một repo cài sẵn rồi `cp -c` cho mỗi ca, APFS clone); chỉ ca kiểm việc cài lại / gỡ cài mới gọi `install.sh`. Bước 3: tách `test_local_tier` thành 2–3 file theo nhóm ca (cài mới, cập nhật kit, sửa của team) để run_impacted chạy song song. | ~1300 s nối tiếp xuống còn vài phút; đây là mục lớn nhất |
| test_gate_stop_reuse_race | Tách 3 file theo nhóm K1 / K2 / K6 (mỗi file một vòng `for`), hoặc chạy các nhóm trong subshell nền rồi gộp kết quả theo mẫu `grp_*` của `test_postfix_gate.sh` (file đó đã tự song song hoá: 41 s đo so với 82 s ghi). | 184 s → ~70 s tường |
| test_proof_capture_lock | 2–3 file bọc mỏng, mỗi file gọi file gốc với `LOCK_TEST_ONLY=<nhóm id>`; impact_map trỏ `bin/proof-capture.py` tới cả nhóm. | 112 s → ~40–60 s tường |
| test_gate_budget_resume | Đọc lại trước khi tách: 4 lần gọi gate thật, `GATE_TOTAL_BUDGET_S` nhỏ. Có thể tách 2 file. | ~98 s → ~50 s |
| test_unity_proof | Không tách; sửa số trong `test_durations.txt`. | — |

Mọi lần tách giữ nguyên assertion. Mỗi file mới thêm một dòng vào `test_durations.txt`, và dòng `impact_map.txt` trỏ tới file cũ phải đổi
sang các file mới (đổi trong lượt không bị chặn bởi worktree `devkit-relink-prune`).

## Chưa kiểm

- Nguyên nhân nhóm cài đặt chậm gấp 4–9 lần: mới là giả thuyết, chưa trace.
- Mỗi test đo một lần dưới tải 12–35; không lặp nên không có trung vị, và không đo khi máy yên.
- Các test 45–60 s trong `test_durations.txt` chưa đo.
