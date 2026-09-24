# Plan V3 — Living Regression Checklist (tự động tối đa, chất lượng trên hết)

> Chủ: người dùng là senior "siêu lười": agent + hook làm hết, người chỉ duyệt việc không đảo ngược
> được. Luật tối thượng: **một bước tự động có thể tạo PASS giả hoặc che một lỗ hổng thì lùi về
> nhắc, không đoán.**
> Phạm vi: DevKit (`universal-agent-devkit`) + 3 dự án cài symlink: GeelyEx2 (automotive),
> OfficeReader (android), Goods-Triple-Shelf-Match-3D (game). Chỉ Claude + Gemini (không Codex/Cursor).

## 0. Đã có — không làm lại

- `.agents/regression_status.json` là dữ liệu gốc (máy ghi); view Markdown sinh lại từ đó.
- PASS/FAIL chỉ đến từ `postfix-gate --run-tests` / Stop regression gate chạy test thật; mỗi lần chạy
  lưu `duration`, `exit_code`, `commit` (`+dirty`).
- `agent-kit bugs import|add|link|drop`; trạng thái OPEN / NEEDS_TEST / NOT_IN_MATRIX / NOT_RUN /
  REPORTED; prompt tả bug → dòng REPORTED; Stop nhắc link test ĐỎ→XANH 1 lần; SessionStart hiện số đếm.
- Ma trận `.agents/regression_matrix.active.json` (file đổi → suite phải chạy); gate chỉ tin ma trận đã commit.
- Stop gate kiểm "đã fix" cần cặp ĐỎ→XANH trong phiên; `review_gate` chặn dừng khi code đổi chưa review.

## 1. Nguyên tắc bất biến

1. **Không PASS nếu không chạy thật.** Chữ ký: `Test | Thời gian | ExitCode | Commit | Log`. Không lệnh nào đánh PASS tay.
2. **Một nguồn sự thật.** JSON = dữ liệu; `CHECKLIST.md` = màn hình sinh lại, không sửa tay;
   `INBOX.md` = của người dùng, **agent không ghi một byte nào vào đó**.
3. **Mỗi "agent phải…" có hook/gate ép**; không ép được thì ghi rõ "tự giác".
4. **Bảo vệ hồi quy không bao giờ tắt ngầm**: archive chỉ ẩn; FLAKY không phải PASS; test chưa
   chứng minh ĐỎ không phải PASS.
5. **Không spam** (rule FinOS): đang code → test đích danh; Stop → suite bị ảnh hưởng; full suite →
   job đêm local. Không bắn backend dồn dập, retry chỉ cho test local.

## 2. File

| File | Ai ghi | Nội dung |
|---|---|---|
| `.agents/regression_status.json` | máy (qua khoá file) | REQ / BUG / TEST, kết quả, chữ ký, lịch sử, trạng thái inbox theo hash |
| `.agents/CHECKLIST.md` | máy, sinh lại | Dashboard; thay `regression_checklist.md` (mọi chỗ đọc file cũ đổi theo trong cùng thay đổi) |
| `.agents/INBOX.md` | **người dùng** | `- [ ] …`, `@làm` để giao làm luôn |
| `.agents/archive/BUG_ARCHIVE.md` | máy, sinh lại | Bug ổn định — chỉ view |
| `.agents/evidence/<test-id>/<ngày-giờ>.log` | gate | Log từng lần chạy; giữ 10 log gần nhất/test, trần dung lượng; `agent-kit clean` KHÔNG xoá |

## 3. Trạng thái

| Trạng thái | Nghĩa | Vào % an toàn |
|---|---|---|
| ✅ PASS | lần chạy thật gần nhất xanh, code canh chưa đổi, test đã chứng minh ĐỎ | tử số |
| 🟡 CẦN CHẠY LẠI | từng PASS, file test canh đã đổi sau commit lần chạy | mẫu số |
| ⏳ CHƯA CHẠY | link test xong, chưa chạy lại sau link | mẫu số |
| ⏳ CHƯA CHỨNG MINH ĐỎ | test xanh nhưng chưa từng thấy đỏ trên code lỗi (Unity/Gradle lớn chờ job đêm) | mẫu số |
| ❌ FAIL / TIMEOUT | đỏ | mẫu số |
| 🔁 FLAKY | đỏ rồi xanh khi chạy lại cùng code | mẫu số + tự tạo BUG flaky |
| 🚫 TEST VÔ HIỆU | vẫn xanh khi bỏ phần fix → không bảo vệ gì | mẫu số, chặn |
| ⚠️ CẦN TEST | REQ/BUG chưa có test, hoặc test gate không chạy | mẫu số |
| 🐞 CHƯA SỬA | bug xác nhận, chưa fix | mẫu số |
| 🟡 REPORTED | prompt tả bug, chưa xác nhận | **không tính** |
| 💤 TỰ ĐÓNG | REPORTED 14 ngày không ai đụng (khôi phục được) | không tính |

% an toàn = PASS ÷ (REQ + BUG + TEST đã xác nhận); HUD ghi rõ mẫu số.

**CẦN CHẠY LẠI**: mỗi test — `git diff --name-only <commit lần chạy>` + thay đổi chưa commit, khớp
`watch_files`; commit `+dirty` → so thêm mtime file với thời điểm chạy. Tính khi render, SessionStart,
Stop; mỗi commit khác nhau một `git diff`.

## 4. Tự động hoá & rào chất lượng

| # | Việc | Tự động | Rào |
|---|---|---|---|
| 1 | Chuyển phase | tự chạy tiếp, báo cáo 1 lần cuối | chỉ dừng cho quyết định thật (mục 6) |
| 2 | Link bug ↔ test | Stop tự link khi: test được viết/sửa trong phiên **và** lần đỏ đầu tiên trước lần sửa source đầu tiên **và** là cặp duy nhất | thiếu 1 điều kiện → chỉ nhắc |
| 3 | REPORTED rác | 14 ngày không đụng → 💤 TỰ ĐÓNG | không xoá |
| 4 | Inbox | hook so hash từng dòng `- [ ]`, mục mới vào ngữ cảnh 1 lần, ghi thành REQ; `@làm` hoặc gõ "làm inbox" → làm trọn: tiêu chí → test ĐỎ → code → XANH | không tự làm việc chưa được bật |
| 5 | Tiêu chí nghiệm thu REQ | sinh bằng `qa-review` **trước khi code**, khoá hash (sửa phải ghi lý do) | review độc lập so tiêu chí với **nguyên văn prompt**, không với code; REQ PASS chỉ khi mọi tiêu chí có test xanh |
| 6 | UNCOVERED / ngoài matrix | tự link theo quy ước tên (`Foo.kt`↔`FooTest.kt`) khi suite matrix chạy nó; không có suite → soạn sẵn bản vá matrix | bản vá matrix gom vào lần duyệt commit |
| 7 | CẦN CHẠY LẠI | SessionStart chạy nền suite **nhẹ** (không Gradle/Unity), ≤ 2 phút | snapshot file lúc chạy; file đổi giữa chừng → bỏ kết quả |
| 8 | Full suite | job đêm **local** (launchd), 1 luồng, ngoài giờ | không cloud (không có Unity/SDK/thiết bị/secret) |
| 9 | Biết khi đỏ | thông báo macOS chỉ khi dòng **chuyển** sang đỏ, 1 câu + link log; xanh → im lặng | có log làm bằng chứng |
| 10 | Flaky | đỏ → chạy lại 1 lần (chỉ test local); đỏ→xanh → 🔁 FLAKY | không bao giờ nuốt đỏ |
| 11 | Chứng minh ĐỎ | test mới: tạm bỏ phần fix trong worktree, chạy lại → phải đỏ. Python/Go/JS/JVM nhỏ: ngay lúc Stop; Unity/Gradle lớn: job đêm | vẫn xanh → 🚫 TEST VÔ HIỆU, chặn |
| 12 | Backlog bug không test | "làm backlog": theo P0→P2, mỗi bug 1 test; bug cũ chứng minh ĐỎ bằng **revert commit fix ghi trong evidence** trong worktree (đỏ trên code cũ, xanh trên code nay) | không có commit fix → CHƯA CHỨNG MINH ĐỎ |
| 13 | Bằng chứng commit/PR | tự đính dòng tổng kết test + link log; % tụt → agent tự ghi lý do vào commit message | chỉ kết quả thật |
| 14 | Link DevKit mất sau merge | **Đã có từ session DevKit-core:** `scripts/relink_check.py` chạy từ git hook post-merge / post-checkout / post-rewrite (sống sót cả khi hook Claude mất link — SessionStart thì không), chỉ tạo lại link thiếu | không chạy installer, không đụng file tracked |
| 15 | Archive | bug sửa + PASS mới + ≥ 30 ngày **và** ≥ 30 commit → chỉ view archive | đỏ/stale → tự về vùng cảnh báo |

## 5. Giao diện `CHECKLIST.md`

1. HUD 1 dòng: `An toàn 82% (41/50) · ❌ 1 · 🟡 3 · ⚠️ 5 · 🐞 2 · 🔁 0 · 🟡 REPORTED 2 · matrix chờ duyệt: không`.
2. 🚨 Vùng cảnh báo: FAIL, TEST VÔ HIỆU, FLAKY, CẦN CHẠY LẠI, CẦN TEST, CHƯA SỬA — mỗi dòng 1 câu "việc cần làm".
3. 📥 Hộp thư: mục inbox chưa xử lý / đã nhận → REQ-id (đọc từ JSON, link tới `INBOX.md`).
4. Phân hệ theo `component` của ma trận (tên nghiệp vụ trong ma trận); REQ + bug + test + chữ ký; phân hệ 100% PASS thu gọn `<details>`.
5. Sổ tay bug: Mã | Mô tả dễ hiểu | Test bảo vệ | Trạng thái | Bằng chứng.
6. 🟡 REPORTED (+ 💤 TỰ ĐÓNG thu gọn).
7. Chân trang: "Sinh tự động lúc …, không sửa tay" + số bug trong archive.

## 6. Chỉ 3 việc cần người

1. **Commit / push** — không đảo ngược được; rule của người dùng.
2. **Tin ma trận đã đổi** — agent tự tin ma trận nó sửa = tự nới gate của chính nó; gom thành 1 lần duyệt cùng commit.
3. **Xoá bug người dùng đã xác nhận** — dữ liệu của họ.

## 7. Ngân sách, công tắc, số đo

- Ngân sách (có test đo): hook prompt ≤ 100 ms; SessionStart ≤ 2 s (phần đồng bộ); phần kiểm của Stop (không tính chạy test) ≤ 5 s.
- Công tắc tắt riêng từng tính năng (env): `BUG_CAPTURE`, `BUG_LINK_REMINDER`, `AUTO_LINK`, `INBOX_WATCH`,
  `STALE_RERUN`, `RED_PROOF`, `FLAKY_RETRY`, `EVIDENCE_KEEP` — bảng trong AGENTS.md.
- Báo cáo tuần 1 dòng: số lần người phải động tay, tỷ lệ REPORTED bị drop (chỉnh bộ nhận diện bug),
  số FLAKY, số TEST VÔ HIỆU bị bắt.

## 8. Lộ trình (mỗi phase: test ĐỎ→XANH trong `tests/test_*.sh`, `./bin/agent-kit test` rc 0)

| Phase | Nội dung | Nghiệm thu |
|---|---|---|
| P0 | Audit **chỉ đọc** 3 dự án: tính năng, test, độ phủ ma trận, bug không test, commit fix có trong evidence | Phụ lục A của file này (không hỏi, chạy tiếp) |
| P1 | 🟡 CẦN CHẠY LẠI | sửa file canh → PASS thành 🟡; chạy lại → PASS |
| P2 | `.agents/evidence/` + chữ ký có link log; clean không xoá; giữ 10 log | log đúng test, link đúng; log thứ 11 xoá log cũ nhất |
| P3 | Chứng minh ĐỎ (test mới, stack nhẹ lúc Stop) + 🚫 TEST VÔ HIỆU + ⏳ CHƯA CHỨNG MINH ĐỎ | test không phụ thuộc fix → chặn; test thật → PASS |
| P4 | Auto-link chặt (mục 4.2), 💤 TỰ ĐÓNG, 🔁 FLAKY | cặp mơ hồ → chỉ nhắc; đỏ→xanh cùng code → FLAKY |
| P5 | `INBOX.md` (agent không ghi) + REQ (`agent-kit req add/link`), tiêu chí khoá hash, review so với prompt | `INBOX.md` giữ nguyên từng byte; mục mới vào ngữ cảnh đúng 1 lần; REQ thiếu tiêu chí có test → CẦN TEST |
| P6 | Lệnh chữ "làm inbox" / "làm backlog" (hook nhận diện) + RED-proof bug cũ bằng revert commit fix | backlog chạy theo severity; không có commit fix → CHƯA CHỨNG MINH ĐỎ |
| P7 | Job đêm launchd local (full suite + RED-proof nặng) + thông báo khi chuyển đỏ + báo cáo tuần | xanh → không thông báo; chuyển đỏ → 1 thông báo có log |
| P8 | View `CHECKLIST.md` (mục 5), đổi mọi chỗ đọc `regression_checklist.md` | snapshot test; phân hệ 100% thu gọn; % đúng mẫu số |
| P9 | Khoá file trong post-fix-gate; SessionStart health tự re-init; test ngân sách; áp dụng 3 dự án, `agent-kit health` sạch | 2 session ghi cùng lúc không mất dòng; ngân sách đạt |

## 9. Điều kiện bắt đầu & phối hợp

- Full suite DevKit **xanh trước** (lúc viết: đỏ ở `test_platform_rules.sh` do tái cấu trúc `.agents/`
  của session DevKit-core). Đỏ không do mình → không sửa file của session khác; nhắn session đó, làm
  P0 (chỉ đọc) trong lúc chờ.
- Trước khi sửa file dùng chung (`bin/post-fix-gate.py`, `bin/install.sh`, `bin/agent-health.py`,
  `AGENTS.md`), nhắn session DevKit-core (ListAgents) chốt quyền sở hữu file.
- Không commit/push khi người dùng chưa yêu cầu.

## 10. Cấm

- Đánh PASS bằng niềm tin; sửa tay `CHECKLIST.md`; ghi bất cứ gì vào `INBOX.md`.
- Tạo checklist thứ hai song song; archive tắt test bảo vệ; coi FLAKY / chưa chứng minh ĐỎ là PASS.
- Tự link khi bằng chứng không rõ một-một; tự tin ma trận đã đổi.
- Luật đếm assertion (heuristic, báo sai nhiều — đã có RED-proof + review độc lập thay thế).
- Full suite sau mỗi sửa nhỏ; job đêm trên cloud.

## Phụ lục A — Audit P0 (2026-09-24 10:45, chỉ đọc)

| | GeelyEx2 | OfficeReader | Goods-Triple |
|---|---|---|---|
| HEAD | d23430ea | cf51416b6 | 41a8404 |
| Ma trận | 9 rule / 14 suite | 9 rule / 9 suite | 3 rule / 4 suite |
| File test (theo mẫu đường dẫn) / nằm trong watch_files | 5746 / 3017 | 1053 / 656 | 152 / 152 |
| Suite đã có lần chạy thật | 5 (đều `+dirty`) | 1 (`+dirty`) | 4 (commit a2a8078, HEAD đã khác) |
| Bug | 167: PASS 83 · NOT_RUN 3 · NEEDS_TEST 67 · NOT_IN_MATRIX 7 · OPEN 7 | 57: NOT_RUN 57 | 35: NOT_RUN 26 · OPEN 9 |
| Bug không có test hồi quy | **74** (critical 8, P1 1, chưa phân loại 65) | 0 | 0 |
| …có commit fix tra được trong evidence (RED-proof bằng revert được) | 13 | – | – |
| INBOX.md / CHECKLIST.md / evidence/ | chưa có | chưa có | chưa có |

Kết luận cho các phase:
- **P1 đáng giá ngay**: mọi lần chạy đều `+dirty` hoặc ở commit cũ hơn HEAD → không lần PASS nào hiện
  được kiểm là còn mới; cần luật mtime cho `+dirty` (mục 3).
- **P6 backlog** tập trung ở GeelyEx2: 74 bug, ưu tiên 8 critical; chỉ 13 bug RED-proof được bằng
  revert commit fix → 61 bug còn lại sẽ ở "CHƯA CHỨNG MINH ĐỎ" tới khi có test viết mới thấy đỏ.
- **Tương thích ngược**: dòng cũ (bug import, `tests`, `linked_ts`, `last`) giữ nguyên; V3 chỉ thêm
  trường. Post-fix-gate ghi `PASS_IMPACTED` (không thuộc RESULT_STATES) → không bao giờ thành PASS.
- Phân loại severity của GeelyEx2 thiếu ở 65/74 bug → backlog xếp chưa phân loại sau critical/P1.

## Phụ lục B — Trạng thái thực hiện (2026-09-24, session agent-workbench-cd)

| Phase | Kết quả | Test (ĐỎ trước → XANH) |
|---|---|---|
| P0 | Phụ lục A | — (chỉ đọc) |
| P1 | STALE: git diff từ commit lần chạy + mtime; impacted-only sau PASS → STALE; SessionStart chạy nền suite nhẹ (`scripts/stale_rerun.py`) | `test_stale.sh` 12, `test_stale_rerun.sh` 9 |
| P2 | `.agents/evidence/<test>/<ts>.log` (10 log, git-ignored, clean không xoá), link từ dòng; khoá file trong post-fix-gate | `test_evidence_log.sh` 7 |
| P3 | `scripts/red_proof.py` (sandbox = git worktree: ĐỎ không fix / XANH có fix; revert 3-way; chép file build bị ignore, `.agents/local/red_proof.json`; chỉ chạy test của bug qua `impacted_command`; id lạ → exit 2; evidence nhiều commit → "mơ hồ"); UNPROVEN / VACUOUS / OUTDATED; Stop chạy nền + giữ Stop khi VACUOUS. Sửa theo pilot thật của agent-workbench-f6 | `test_red_proof.sh` 24 |
| P4 | Auto-link một-một (🤖), 💤 tự đóng REPORTED 14 ngày, 🔁 FLAKY (post-fix-gate chạy lại 1 lần) | `test_auto_link.sh` 9, `test_flaky.sh` 7 |
| P5 | REQ (`agent-kit req`), tiêu chí khoá hash, INBOX.md chỉ đọc, nhắc REQ cho prompt tính năng, nhắc Stop cho REQ | `test_inbox_req.sh` 23 |
| P6 | "làm backlog" / "làm inbox"; RED-proof bug cũ bằng revert commit fix trong evidence | `test_backlog.sh` 7 |
| P7 | `scripts/nightly.py` + `agent-kit nightly` (LaunchAgent local, thông báo khi chuyển đỏ, báo cáo tuần) | `test_nightly.sh` 16 |
| P8 | Dashboard `.agents/CHECKLIST.md` (link tên cũ), HUD %, vùng cảnh báo, phân hệ gập, sổ tay bug, archive | `test_checklist_view.sh` 12 |
| P9 | Ngân sách hook (prompt 67 ms, SessionStart 257 ms, Stop 56 ms trên checklist 180 dòng); bảng công tắc AGENTS.md; README/CHANGELOG; mục 14 do `relink_check.py` (DevKit-core) | `test_budgets.sh` 3 (canh ngân sách — không có pha ĐỎ) |
| Thêm (audit OR, G4/G5) | ANTI-LOOP: tiết lộ "mutation" theo từng testcase; chỉ tính lần chạy của phiên này (bash_write_ledger) | `test_anti_loop_disclosure.sh` 10, `test_anti_loop_ownership.sh` 8 |

**Quyết định người dùng (2026-09-24, qua agent-workbench-f6):** KHÔNG cài job đêm / LaunchAgent cho 3 dự án. Hệ quả: suite nặng (Gradle/Unity) chỉ chạy khi gate chạy (`postfix-gate --run-tests --full`); RED-proof bug cũ trên suite nặng chạy tay: `python3 <devkit>/scripts/red_proof.py . --pending --heavy --wait`; không có báo cáo tuần. `agent-kit nightly` vẫn có sẵn nếu sau này muốn bật.
