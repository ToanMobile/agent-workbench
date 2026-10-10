# Backlog đòn bẩy (cập nhật mỗi lần chạy: xoá mục đã xong, ghi số đo mới)

Cập nhật 2026-10-10. Nguồn: các agent nghiên cứu chỉ đọc của ngày 10/10 và `devkit_metrics.py`. "đo" = số đo thật (lệnh trong báo cáo gốc), "ước" = tính từ số đo, "giả thuyết" = chưa kiểm. Máy lúc đo có load cao, thời gian tường có thể gấp 3-5 lần lúc rảnh.

## Hook Stop trước (rubric mục 3 và 4)

Kết luận nghiên cứu: **không xây cache mới** (cache theo fingerprint cho cả kết quả, theo từng suite, hoặc bỏ cổng khi lượt không đổi file): mô phỏng trên log thật cho lợi ít, trả sai ở một phần lượt chạy lại (kết quả khác vì BUSY và file ngoài fingerprint), và bỏ cổng làm yếu bàn giao. Phần lớn lãng phí đã hết sau Dot 7a (08/10) và Dot 11 (09/10 12:07): Office 100 trên 110 lượt lặp exit 2 xảy ra trước Dot 7a, 0 sau Dot 11. Còn lại là **cứng hoá cache chặn sẵn có** của `hooks/regression_gate.sh`:

| Điểm yếu (đo, đọc code) | Sửa tối thiểu |
|---|---|
| Không lưu kết quả chặn khi `touched` hoặc `busy` khác rỗng; `busy` gộp UNTESTED do `untested_exit` (vĩnh viễn trên máy này) với BUSY thật, nên một vòng FAIL + suite không chạy được chạy lại đủ ~7,5 s mỗi lần thay vì 0,7 s | Chỉ coi BUSY và BUDGET là "không lưu"; `touched` chỉ không lưu khi không có suite FAIL |
| Khoá chặn thiếu `_local_sha` (cấu hình cục bộ ngoài fingerprint) và không có TTL; sửa file bị ignore rồi Stop vẫn trả FAIL cũ (nghiêng nghiêm, không tạo PASS giả) | Khoá `reuse_key|_local_sha|stat(gate,hook)`; TTL 1800 s (`REGRESSION_GATE_REPEAT_TTL_S`, 0 là tắt), giữ thời điểm của lần chạy thật |
| `attempts[fp]` chỉ tăng sau khi suite đã chạy, nên vòng dừng ở lần chặn thứ 3 | Tăng khi tái dùng |

Ràng buộc an toàn: chỉ lưu FAIL/UNVERIFIED, không bao giờ PASS, UNTESTED, BUSY, BUDGET, flaky, infra; vô hiệu khi receipt đầy đủ đổi hoặc bị xoá, khi `approved_tests.json`/`approved_hashes.json` đổi, khi transcript có câu duyệt mới. Thông điệp phải nói là kết quả đã lưu, từ lúc nào, và cách chạy lại ngay. Test ĐỎ trước (7 ca): FAIL + `untested_exit` lần 2 phải được tái dùng; sửa file ignored phải chạy lại; touched kèm FAIL tái dùng và câu duyệt mới làm chạy lại; touched-only vẫn exit 0 kèm nhắc; TTL hết hạn và thời điểm không bị làm mới; receipt PASS hoặc bị xoá thì chạy lại; BUSY/BUDGET/flaky/infra không lưu. Mô phỏng (cận trên): GeelyEx2 sau Dot 11 tiết kiệm khoảng 60 trên 120 phút hook trong 22 giờ; Office và workbench khoảng 0. Rủi ro còn lại (giả thuyết): FAIL thoáng qua, thiết bị hoặc mạng đổi bị ghim tối đa 30 phút (TTL, công tắc, và hạn mức attempts vẫn thả ở lần 3 giới hạn nó). Nâng lên cache theo từng suite khi tổng phút lặp khác phiên cộng lượt "reused" trong log vượt khoảng 30 phút mỗi ngày.

**Cả chuỗi hook Stop** (nghiên cứu 10/10 đo trên bản ghi `stop_hook_summary` trong transcript: 1401 lần Stop, 37 phiên, 4 repo; nguồn chuẩn hơn log hook): 9 hook DevKit chạy SONG SONG nên thời gian tường là hook chậm nhất, không phải tổng; thứ tự hook vô nghĩa (ý "đổi thứ tự" của Antigravity bị bác bằng số đo này). Sau Dot 11: 213 lần Stop trong 22 giờ, 74 phút tường (`regression_gate` 60, `testsourceset_gate` 10,5); 7 hook nhẹ chỉ 1,6% (đường tới hạn p50 0,36 s, p90 1,5 s). Lý do mỗi lần Stop: 27% hết lượt người dùng, 35% re-Stop sau chặn của DevKit, 31% đánh thức nền, 7% sau chặn của `/goal`; trung vị 28 Stop và 12 lượt model thêm mỗi phiên; lượt sau chặn là 28% số lần gọi model. Chặn: 47% đến ngay sau một chặn khác; `proof_gate` ở lượt có push: 41 trong 79 lần chặn (52%) báo cáo 4 mục đã có SAU push ở reply trước trong cùng lượt, tránh được hoàn toàn. Số đo bằng log của `devkit_metrics.py` từng sai (đã sửa): log ghi nhiều dòng mỗi Stop nên số Stop phồng gấp 1,8 lần, và đếm cả dòng hook thả.

Thứ tự việc (RED trước, công tắc tắt, hồi quy một commit):
1. `hooks/proof_gate.sh`: nhận báo cáo 4 mục ở BẤT KỲ reply nào sau lần push trong lượt. RED: push, reply có 4 mục, reply kế không có thì exit 0; báo cáo chỉ trước push, hoặc thiếu một mục, thì exit 2. Đòn bẩy lớn nhất, giảm số lượt model thừa.
2. `hooks/regression_gate.sh`: bảng "điểm yếu" ở trên, cộng digest duyệt test (`approved_tests.json` và số lần AskUserQuestion) trong khoá tái dùng, cộng `flock` và gộp khi ghi `regression_gate.state.json` (đọc rồi ghi sau nhiều phút, hai phiên sống có thể ghi đè nhau: tương quan, chưa chứng minh).
3. `hooks/testsourceset_gate.sh`: bỏ qua lượt dở dang (reply "CHƯA XONG" kèm file đổi): 8 trong 15 phút sau Dot 11. Mở rộng Dot 11: hỏi người dùng.
4. Hồ sơ `test_evidence_gate` (transcript 32 MB mất 17 s, thực tế tối đa 23,5 s): cần lịch sử RED trước khi đụng.
Không làm: trần re-Stop và `review_gate` status_optional (làm yếu), đổi thứ tự hook, gộp thông điệp (chỉ giảm token, không giảm lượt). Chưa biết: vì sao `reuse_key` còn lệch ở một số lần chạy lại; transcript chỉ phủ khoảng 93% Stop.

## Guard (rubric mục 1)

Kết luận nghiên cứu 10/10: kiến trúc **(b) chuẩn hoá lệnh dùng chung, làm theo pha**; vá từng lỗ (a) không hội tụ (28 commit trong 17 ngày cho hai hook, hàm `drop_comments` trùng 32 dòng, hardware hook có 5 bộ tách lệnh). Prototype `hooks/devkit_shellnorm.py` (khoảng 480 dòng, compile 2,8 ms) giảm lọt từ 35 xuống 8 trên 106 payload (prototype mới port khoảng 60% logic hook, thiếu phần fail-closed của hook git cho feed/`<()`/`$()`). Chi phí đo: đường nhanh bash 3 ms CPU; đường Python 38-40 ms CPU (khởi động 20,6 + import 11,6 + compile 5-8). Thứ tự: (5) pha 0 đường nhanh (allow-list lệnh chỉ đọc, bớt khoảng 34% CPU mỗi lệnh), (6) preflight text→text (brace, `$'..'`, redirect đứng đầu), (1) hardware `-lc` và tham số wrapper (`sudo -u`, `timeout -s`), (2) git dry-run, `--cached`, cụm `-am`, (3) git `checkout <path>` không `--`, (4) hardware option trước động từ (`pnpm -r publish`, `terraform -chdir=x destroy`), (8) hardware chặn nhầm `rm` (`.venv`, `*.log`, `find -type d -empty -delete`), cuối cùng (7) tách mã khỏi dữ liệu (PATTERNS chỉ khớp văn bản có thể là mã: chặn nhầm 23 xuống 3). Mỗi pha chạy lại 18 test cũ ở bản sao. Bỏ qua vì agent không gõ: `gi{t..t}`, `git $'reset'`, `$ADB -s`, `env -S`. Giữ chặn: `find -mtime +30 -delete`. Còn đo được: tỉ lệ lệnh thật đi đường nhanh (ghi log mỗi quyết định đường Python rồi chia cho số dòng ledger).

## Đòn bẩy khác (xếp theo tiết kiệm đo ÷ rủi ro)

| # | Đòn bẩy | Tiết kiệm | Rủi ro | Chỗ sửa |
|---|---|---|---|---|
| 1 | Ghi vào `runs.jsonl` thời gian từng pha, luật khớp, `tests_touched`, `fp` và lý do exit: tiên quyết cho mọi mục khác | 0 (đo) | 0, nhưng bản ghi bị `push_gate.py` đối chiếu nên giữ nguyên các trường cũ | `post-fix-gate.py` `_log_gate_run` |
| 2 | Cache offset cho `split_user_approved`: mỗi lần có test cũ bị sửa chưa commit nó quét mọi transcript mới hơn bằng `re.search` từng dòng (đo 6,4 s với test 2 ngày, 13,2 s với 6 ngày; Office 9,2 trên 14,3 s) | Office ≈5, GeelyEx2 ≈2 phút/ngày (ước) | thấp-vừa: test cache == quét đủ | `post-fix-gate.py` `split_user_approved` |
| 3 | Guard lũ file lạ: kiểm NUL 8 KB trước khi đọc cả file, biên dịch trước glob (4000 file lạ làm gate 63,7 s: hygiene 24 s, `tree_fingerprint` hai lần 17 s, `mark_stale` 6,9 s) | chặn tái diễn sự cố đã tốn 472 phút ở GeelyEx2 | thấp | `post-fix-gate.py` hygiene, `mark_stale` |
| 4 | Gộp git trong `mark_stale` (27 lệnh) và biên dịch trước `local_state_sha` (320k `fnmatch`) | 3-6 phút/ngày/repo (ước) | thấp | `regression_checklist.py` |
| 5 | Repo: test `REG-TOOLS-07` của GeelyEx2 chạy 223 lần, 16,8 s mỗi lần vì 15 `sleep(1100)`; dùng đồng hồ giả | ≈12 phút/ngày | thấp, sửa test cũ cần duyệt | `tests/scripts/test-admin-force-update-behaviour.py` ở repo |
| 6 | Repo: `parallel_safe` cho suite Python độc lập (Geely, Office chưa đặt cờ nào) | tối đa 9,2 + 4,9 phút/ngày (thực tế ×0,6) | thấp nếu độc lập | ma trận của repo |
| 7 | Bỏ suite đã được `covered_by` khi suite phủ FAIL (REG-CAR-VOICE chạy lại sau 24 lần REG-CAR-01 FAIL) | 6,4 phút/ngày | vừa: mất chẩn đoán, verdict vẫn FAIL | vòng suite trong `post-fix-gate.py` |
| 8 | Ngữ cảnh: essentials 18,9 KB nạp ở cả 4 repo (mỗi phiên 32-76 KB tuỳ repo); cắt 25% essentials và để `profile-rules` của Office nạp theo nhu cầu; viết lại bước 1 "Every prompt" tiết kiệm ≈0 token đo được | ≈1,2k token mỗi lần nạp, ≈50k token/ngày (ước) | vừa: file luật, hỏi người dùng; cần A/B tuân thủ luật | `rules/essentials.md`, profile |

Không làm: daemon giữ cache (phức tạp, dễ hỏng); chọn Unity theo từng phần (cơ chế thật là cả luật chạy FULL khi một file không có test gọi tên, chọn từng phần làm yếu kiểm tra); mở rộng đuôi file Unity được "vouch" khi chưa đo trần tiết kiệm.
