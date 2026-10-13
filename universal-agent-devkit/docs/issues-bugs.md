# DevKit — issues & bugs (nguồn duy nhất)

> Gộp ngày 13/10/2026 theo yêu cầu người dùng: một file cho issues, bugs và việc dọn dẹp đang mở; kế hoạch tối ưu / cải tiến workflow nằm riêng ở [`workflow-improvements.md`](workflow-improvements.md). Các hàng ở Phần A tách từ hai bảng theo dõi (mục tiêu 100/100, Plan C+D §8.1), giữ nguyên chữ và số `#` gốc. Phần B là báo cáo audit 09/10, giữ nguyên.

## Cách dùng

1. Vấn đề hoặc bug mới của DevKit chưa có test: thêm một hàng ở Phần A, ghi bằng chứng (lệnh, số đo, đường dẫn) và nguồn. Xong thì chuyển sang Phần B kèm commit và cặp test ĐỎ→XANH.
2. Bug có test hồi quy: `agent-kit bugs add/link`; `.agents/CHECKLIST.md` là nguồn trạng thái PASS/FAIL. Không ghi PASS/FAIL ở đây.
3. "Chưa kiểm lại" nghĩa là dòng đó trích từ một plan cũ và chưa ai chạy lại ngày 13/10.

## Chỉ mục

| Mục | Nội dung | Nguồn | Trạng thái |
|---|---|---|---|
| A.1 | `session_lock` bỏ lọt `cp`/`mv`/`rm`/`tee`/`sed -i` (việc 3); thư mục mồ côi do gate ghi sau khi worktree bị gỡ (việc 10) | `goal-100-2026-10-13.md` | Kiểm lại 13/10 17:00: cả hai vẫn mở; việc 10 lặp lại lúc 16:36. Lịch làm: `workflow-improvements.md` I.0 W3, W1 (R5a) |
| A.2 | Gate chưa có biên nhận cho `aaf9805`/`204750d`; race `worktree_merge_gate`; dọn thư mục và worktree sót | `trunk-integrator-no-shared-main.md` §8.1 #2–#6 | Kiểm lại 13/10 tối: #2, #3, #6 còn mở; #4, #5 đã đóng và đã bỏ khỏi bảng → I.0 W0, W1 |
| A.3 | Worktree ở Goods chưa gộp | `goal-100-2026-10-13.md` | Kiểm lại 13/10 tối: Goods vẫn vậy; phần GeelyEx2 đã đóng và đã bỏ → I.0 W1 (R5b gc) |
| A.4 | Tồn đọng ghi trong plan / báo cáo đã làm; con trỏ cũ tới `docs/plans/*` còn sót | các plan II.A, II.C và audit B.1 | Kiểm lại 13/10 tối: 6 hàng đã đóng đã bỏ; 5 hàng còn mở, 3 hàng chưa kiểm được (xem đầu mục) |
| B.1 | Audit DevKit 2026-10-09: kết quả | `audit-2026-10-09-followup.md` | Báo cáo đã đóng |

## Phần A — Đang mở


### A.1 Từ bảng mục tiêu 100/100 (việc 3 và 10)

| # | Việc | Trạng thái | Ở đâu |
|---|---|---|---|
| 3 | **Lỗ của `session_lock`** — `bash_collides` (`bin/session_lock.py` ~dòng 956) chỉ coi git write, lệnh chạy gate và redirect `>` là ghi; `cp`/`mv`/`rm`/`tee`/`sed -i`/`touch`/python ghi file vào checkout đang bị giữ đều lọt (13/10 11:03 đã xảy ra) | chưa làm — gộp vào việc 2 (kiểm lại 13/10 17:00: `bin/session_lock.py:956-971` không đổi từ `892125a`) → `workflow-improvements.md` I.0 W3 | `worktree_guard.sh` đã có bộ quét đích ghi, nhúng trong heredoc `python3 -I <<'PY'` (dòng 165–574; bộ quét lệnh Bash ở dòng 423–544): đưa nó vào bộ chuẩn hoá chung, đừng viết bộ thứ hai |
| 10 | **Lỗi kit: thư mục mồ côi do gate ghi sau khi worktree bị gỡ** — 13/10 hai lần (`agent-workbench-dashboard` 12:57, `agent-workbench-sprite-forge` 15:30): một `post-fix-gate` đang chạy trong worktree, `worktree finish/remove` gỡ worktree, gate kết thúc và ghi `.agents/evidence`, `regression_journal`, `CHECKLIST.md`, `.claude/audit-gate/*.lock` vào đường dẫn cũ → thư mục không có `.git`, git không thấy, không guard nào liệt kê. Sửa: `finish`/`remove` chờ hoặc từ chối khi khoá `test_run.lock` của worktree đang bị giữ, và/hoặc gate không tạo lại gốc project đã biến mất (kiểm `.git` trước khi ghi); `worktree status` liệt kê thư mục `<repo>-*` không còn đăng ký. Test ĐỎ trước. | chưa làm (đã xoá tay hai thư mục). **Kiểm lại 13/10 17:00: vẫn mở và lặp lại lúc 16:36** — `GeelyEx2-push-1013d` (không đăng ký, không `.git`, chỉ `.agents/` và `.claude/audit-gate/*.lock`; `regression_journal` ghi do `post-fix-gate.py` pid 31401). `worktree.py` không nhắc `test_run.lock`; `post-fix-gate.py:1038` `os.makedirs` và `:3420` `state.mkdir(parents=True)` ghi mà không kiểm `.git` → `workflow-improvements.md` I.0 W1 (R5a) | `scripts/git/worktree.py`, `bin/post-fix-gate.py` |

*(Các việc #1, #2, #4 đến #9 của bảng gốc là cải tiến: nằm ở `workflow-improvements.md` mục I.1. Việc 3 ghi "gộp vào việc 2", tức Giai đoạn C ở đó.)*

### A.1b Mới 13/10 tối (review ngữ cảnh sạch sau `cd0fb04`) — làm TRƯỚC W1

| # | Việc | Bằng chứng | Sửa |
|---|---|---|---|
| 11 | **P1 bảo mật, có từ trước: gate tự duyệt test đã sửa từ tin nhắn KHÔNG phải của agent.** `bin/post-fix-gate.py` (~dòng 727) đọc `content` ở cấp ngoài cùng của MỌI record. Claude Code ghi record `type: "queue-operation"` có `content` ở cấp ngoài: tin nhắn từ phiên khác, `agent-message`, `task-notification`, prompt người dùng xếp hàng | Reviewer đo trên 2224 transcript thật: 83 record khớp từ khoá. Một record OfficeReader 03/10 ("…tôi không duyệt… bạn cần tự duyệt diff") được tính là DUYỆT; "đừng tự duyệt" trong transcript của phiên khác cũng DUYỆT | Chỉ đọc `content` cấp ngoài khi `type` là `PLANNER_RESPONSE` (Antigravity) hoặc `assistant` và không `isMeta`. Marker phân biệt hoa thường, payload tách token, so khớp CHÍNH XÁC đường dẫn hoặc basename (không khớp chuỗi con: `my_test_old.sh` từng duyệt cả `test_old.sh`). Dòng JSON bị cắt cụt thì bỏ, không rơi về dòng thô. Thiếu timestamp thì không duyệt. Test ĐỎ trước cho từng ca |

| 12 | **File bí mật sinh ra trong worktree không bao giờ về main.** `worktree add` chép LOCAL_CONFIG (`.env`, `*.jks`, `key.properties`…) từ main sang worktree, nhưng `finish`/`automerge` chỉ mang về file git theo dõi. File bị gitignore, đúng là loại file bí mật, nên kẹt lại trong worktree, và worktree không xoá được nếu không mất khoá | Neighbours: `Neighbours-From-Hell-keystore` tạo lúc 12/10 17:32:05; `keystore/key_store_neighbours.jks` + `key.properties` sinh lúc 17:32:23. Main chưa từng có keystore (không file nào, Unity chưa cấu hình keystore Android). Người dùng tưởng main có "keystore gốc" | `finish`/`automerge`/`gc`: file bí mật bị ignore mà CHỈ có trong worktree thì chép về đúng đường dẫn ở main (giữ quyền 600, thêm vào `.git/info/exclude` nếu `.gitignore` chưa chặn), so từng byte, rồi mới gỡ worktree. Bản giống main thì bỏ. Test ĐỎ trước. Ca Neighbours: người dùng duyệt chép rồi xoá (13/10 tối); đang chờ phiên `b63800b5` nhả khoá repo đó |

### A.2 Từ Plan C+D §8.1 (hàng #2 đến #6)

| # | Việc | Trạng thái đo được | Hành động |
|---|---|---|---|
| 2 | **Gate chưa có biên nhận cho `aaf9805` / `204750d`** | Lần đỏ gần nhất: `test_worktree_merge_gate_owner.sh` (race có sẵn); gate trên commit chỉ-Markdown vẫn TIMEOUT 900 s vì `REG-DK-ALL-01` chọn quá nhiều test | Chạy với `--timeout 2400`; điều tra vì sao commit docs kéo cả suite DevKit. **13/10 17:00:** không nối được với sha: `runs.jsonl` không ghi HEAD, và main không có `full_pass.json`. Gate `--full` gần nhất của main là 13:53, exit 2 UNTESTED (cả 4 suite PASS). Nguyên nhân đã đo ở đoạn dưới; trên main có thêm một nguyên nhân thứ hai: 17 commit chưa push → `--list` chọn 190/226 test → `workflow-improvements.md` I.0 W0 và W2a |
| 3 | **Sửa race `worktree_merge_gate`** | Đỏ ở cả 4 lần gate hôm nay; A/B song song: kit cũ 7/30, kit mới 18/30 lượt đỏ (có nhiễu: một số lượt kit mới chạy trong git worktree) — **chưa chứng minh Đợt 30 không làm xấu thêm**. Kiểm lại 13/10 17:00: `hooks/worktree_merge_gate.sh` không đổi từ `94f388c`; dòng 271–275 chạy một `inventory` cho mọi worktree, dòng 283 gắn `reason` "gate error" cho mọi hàng khi nó lỗi, và bộ lọc `vanished` ở dòng 287 bỏ qua hàng có `reason`. **13/10 ~18:15: ĐÃ SỬA, nhưng cơ chế thật khác.** Bước kiểm kê chịu được thư mục biến mất (shim tất định: không làm đỏ). Lỗi thật là hai lần `automerge` của MỘT worktree chạy chồng nhau: lần chạy nền của Stop trước đã gộp và gỡ worktree, lần của Stop sau chết vì thư mục đã mất, và lỗi đó thành giữ Stop. Sửa: `landed()` trong `hooks/worktree_merge_gate.sh` chỉ tính là xong khi thư mục và đăng ký đều đã mất, worktree có 0 file dở, và HEAD đã nằm trong main | Test ĐỎ→XANH: `tests/gates/test_worktree_merge_gate_vanished.sh` ca 2 (đã gộp → cho qua) và ca 3 (bị xoá mà chưa gộp → vẫn giữ Stop; Antigravity bắt được ở vòng phản biện 2), ca 5–7. **Còn mở (review 13/10, có từ trước):** thư mục mất TRƯỚC khi bước kiểm kê đọc reflog thì `worktree.py` (~dòng 982) trả `reflog = []`, nên commit chỉ còn trong reflog vẫn cho qua; hướng sửa: đọc reflog từ admin dir (`git --git-dir=<admin> log -g`), không đổi thành `None` (ca 1 sẽ bị giữ). **Còn mở (Antigravity T0035 vòng 4, lỗi chặn, có từ trước):** thư mục bị xoá TRƯỚC khi hook Stop chạy thì rơi khỏi `live` (`worktree_merge_gate.sh` ~197 lọc `os.path.isdir`, ~293 `continue`), bị xoá khỏi `owed`, và Stop thoát 0 dù commit chưa vào main. Antigravity đã chạy thử: rc 0. Nhánh có tên vẫn giữ commit; worktree detached thì commit chỉ còn trong reflog của admin dir. Sửa ở `workflow-improvements.md` I.0, bước 0 của W1 |
| 6 | **Worktree của phiên khác, KHÔNG xoá khi chưa rõ chủ** | Kiểm lại 13/10 tối: `Neighbours-From-Hell-keystore` (đăng ký) đứng ở `ec528ee`, đã nằm trong `master`; còn bẩn `.claude/settings.json`, `AGENTS.md` và thư mục `keystore/` chưa track (`key.properties`, `key_store_neighbours.jks`) — đây là BẢN DUY NHẤT của khoá ký (main không có `keystore/`), nên phải chép về main rồi mới xoá worktree (A.1b #12). Goods `-mcp` xem A.3. Worktree `GeelyEx2-push-*` của phiên Geely đang sống tạo rồi tự gỡ trong ngày, không ghi tên ở đây | `worktree gc` (I.0 W1 (R5b gc)) nhận nuôi khi phiên chủ đã chết. Khoá ký chỉ có trong worktree: chép về main (không commit) rồi xoá worktree |

*(Hàng #1 và #7 của bảng gốc, cùng 8.2 đến 8.4 và thứ tự đề nghị, nằm ở `workflow-improvements.md` mục I.2.)*

**Nguyên nhân đã đo cho hàng #2, thêm khi gộp (13/10, phiên gộp docs):** gate của một thay đổi chỉ-Markdown chạy 1064 s vì `tests/run_impacted.sh` (dòng ~34–38) khi không có upstream `@{u}` lấy mọi file của các commit trong 6 giờ qua làm "đã đổi". Worktree tách rời không có upstream, nên các commit trong ngày của phiên khác bị tính vào. Đo ở worktree `agent-workbench-docsplit` (18 commit trong 6 giờ): `run_impacted.sh --list` chọn **157 test** với môi trường mặc định và **11 test** với `DEVKIT_IMPACTED_SINCE=0` (11 test này đúng là các test nêu tên file đã đổi, cộng `test_repo_consistency`). Dưới tải máy 400–670 (Unity batch test của repo khác), 2 test (`test_session_fetch_source.sh`, `test_hook_python_isolation.sh`) đỏ trong lần chạy 157 test nhưng xanh khi chạy riêng. Cách chữa đề xuất, chưa làm vì sửa test runner/gate thuộc Gate 2 (d): tính cửa sổ từ `git merge-base` với trunk thay vì 6 giờ, hoặc tự đặt `DEVKIT_IMPACTED_SINCE=0` cho worktree liên kết tách rời không upstream. Kiểm: `--list` trong worktree phải bằng số test của chính diff.

### A.3 Ngoài phạm vi phiên này: worktree ở Goods (người dùng 13/10: "chỉ xử lý agent_workbench thôi")

Worktree Goods vẫn chưa gộp, chưa sửa, chưa xoá gì (danh sách gốc ở mục 7 của `2026-10-13-mcp-5-repo-va-coverage-map.md`).
Kiểm lại 13/10 tối: vẫn đăng ký, `4405395` chưa nằm trong `main` của Goods (`merge-base --is-ancestor` exit 1), cây còn đúng 7 đường dẫn bẩn như dưới đây. Cách bền: `workflow-improvements.md` I.0 W1 (R5b gc).

| Worktree | Commit | Main đang giữ bởi | Lưu ý trước khi `agent-kit worktree finish` |
|---|---|---|---|
| `/Volumes/Data/Toan/Game/Goods-Triple-Shelf-Match-3D-mcp` | `4405395` (chỉ đổi `.mcp.json`) | phiên `fb81febe` (đang làm) | **ĐỪNG `finish` khi cây còn bẩn**: `finish` tự commit `wip(...)` mọi thay đổi chưa commit rồi đưa vào main |

Cây làm việc của worktree Goods (kiểm 13/10 15:4x) có thay đổi KHÔNG thuộc việc `.mcp.json`:
- Unity tự sinh: xoá `Assets/Plugins/Demigiant/DOTween/DOTween.dll.mdb.meta` và `…/Editor/DOTweenEditor.dll.mdb.meta` (file `.mdb` bị
  gitignore nên không có trong worktree; main còn `.mdb`, xoá meta thì Unity tạo lại GUID mới), `Assets/UniversalRenderPipelineGlobalSettings.asset`
  bị ghi lại với `m_RuntimeSettings` rỗng (mất 15 mục);
- IDE: `.vscode/` và `Goods-Triple-Shelf-Match-3D-mcp.slnx` chưa track (main cũng có `.vscode/` chưa track, khác nội dung → `ff-only` có thể hỏng);
- `.claude/settings.json`, `AGENTS.md` bị sửa (nhiều khả năng do `agent-kit init` trong worktree) — xem diff trước, không đưa vào main nếu chỉ là bản cài DevKit.
Cách gộp sạch: trong worktree, `git stash push -u -m "<lý do>" -- <các đường dẫn trên>` (lấy lại được), kiểm `git diff main...HEAD` chỉ còn
`.mcp.json`, rồi `agent-kit worktree finish` từ main của Goods khi phiên giữ nhả khoá. **Gấp:** hook Stop (`worktree_merge_gate`) của phiên `fb81febe`
cũng tự gộp worktree này — nếu nó chạy trước khi dọn, các file trên vào main dưới dạng commit `wip(...)`: khi đó tách chúng ra bằng commit sửa lại, không
viết lại lịch sử.

### A.4 Tồn đọng nằm trong plan / báo cáo khác (trạng thái ghi tại thời điểm viết, chưa kiểm lại)

Mỗi hàng trích nguyên văn một đoạn ngắn từ nguồn ghi ở cột phải; đọc đoạn đó trong nguồn trước khi làm.

**Kiểm lại 13/10 17:00 (phiên d352c03b), cập nhật 13/10 tối:** 6 hàng đã đóng (`contract_facts` F2, `hook_contract_test.sh` cho `enrich_context.py`, `python3 -c` thiếu `-I`, `pgrep -f test_slow_`, `adapters/*` trong impact_map, file untracked của CarConnect) đã bỏ khỏi mục này. Còn lại:
- **Vẫn mở:**
  - regex `cwd` không đọc JSON thoát: 15 hook vẫn dùng `RX_CWD`, ví dụ `bash_write_ledger.sh:80`.
  - Gộp 3 suite Gradle của Geely: chưa làm. `REG-CAR-01` và `REG-SHARED-01` chạy cùng một lệnh (`REG-SHARED-01` nay có `covered_by: REG-CAR-01`); `REG-PHONE-01` và `REG-SHARED-02` cũng cùng lệnh, chưa có `covered_by`.
  - `hooks/tests/`: 5 trên 9 file không suite, lệnh hay test nào gọi tới (`git_guard_bypass`, `git_guard_nested`, `proof_gate_turn`, `reply_status`, `stop_repeat`).
  - Con trỏ `docs/plans/`: còn ở 12 file.
  - Ba dòng bug của audit 09/10: trong `.agents/CHECKLIST.md` cả ba là "⏳ chưa chứng minh ĐỎ".
- **Chưa kiểm được:** Gemini qua alias (cần một phiên Gemini thật); nhận nuôi worktree (3) — sẽ đóng ở `workflow-improvements.md` I.0 W1 (R5b gc); FIFO `open()`.
- **Là quyết định chính sách:** squash #22/#3; gradient tím-xanh.

| Trích nguyên văn | Nguồn |
|---|---|
| "Giới hạn đã biết (chưa đóng): regex lấy `cwd` của payload (9 hook cũ + 7 hook mới) không đọc JSON thoát (`é`, `\\`)" | Audit 09/10 (B.1), phần "Giới hạn đã biết" |
| "Gemini qua alias (`includeDirectories` dùng đường dẫn thật): **chưa kiểm** — cần một phiên Gemini thật." | Audit 09/10 (B.1), "Bước 6" |
| "`BUG-20260929-audit-review-nguyen-nhan-tai-sao-cac-ses` — INCONCLUSIVE" | Audit 09/10 (B.1), "Bước 4" |
| "`BUG-20261002-agent-kit-health-run-tests-scores-96-100` — chưa chạy" | Audit 09/10 (B.1), "Bước 4" |
| "`BUG-20261009-run-impacted-recent-commits-in-sandbox` — chưa chạy" | Audit 09/10 (B.1), "Bước 4" |
| "Lựa chọn "gộp 3 suite Gradle thành 1 lệnh" của người dùng **chưa thực hiện**" | Audit 09/10 (B.1), cùng mục |
| "(3) worktree chưa từng vào danh sách "nợ" của một phiên đã kết thúc không bao giờ được phiên sau nhận nuôi (chỉ liệt kê ở SessionStart) — chưa đổi." | Audit 09/10 (B.1), cùng mục |
| "**Cần chủ quy chuẩn xác nhận**: hàng #22 và #3 (có sẵn) vẫn mô tả squash giữ tới lúc nhả" | UI context injection (II.C), "Review ngữ cảnh sạch" #3 |
| "**Để nguyên, cần người quyết**: hai bên mâu thuẫn về chính sách, không phải lỗi mã" | UI context injection (II.C), "Review ngữ cảnh sạch" #7 (cấm gradient tím-xanh) |
| "Lớp lỗi có từ trước: `open()` chặn trên state agent ghi được nên một FIFO treo gate/hook" | DevKit chạy nhanh (II.A), mục 3 #8 |
| "6 test trong hooks/tests/ (~45 s) không nằm trong --all, agent-kit test hay ma trận" | DevKit chạy nhanh (II.A), mục 3b cuối (phần `adapters/*` của câu này đã đóng) |

**Con trỏ cũ tới `docs/plans/*` còn sót sau lần gộp 13/10** (tên file cũ nằm trong tiêu đề mục của hai file mới nên `grep` tìm ra):

- `universal-agent-devkit/AGENTS.md` §7, bảng "Living regression checklist" trỏ `docs/plans/regression-checklist-v3.md`. Đây là file luật (Gate 2 d) và đang sửa dở theo Đợt 31; sửa thành `docs/workflow-improvements.md` mục II.B sau khi Đợt 31 commit.
- Comment trong test và script: `tests/gates/test_review_timing_guard_big_payload.sh`, `test_gate_runner_no_errexit.sh`, `test_git_guard_shell_subst.sh`, `test_churn_guard_fast_path.sh`, `test_gate_js_describe_scope.sh`, `test_hardware_find_not_or.sh`, `test_comment_claim_docstring_trailing.sh`, `tests/verification/test_run_impacted_since.sh`, `tests/context_memory/test_prompt_context.sh`, `hooks/tests/hook_contract_test.sh`, `scripts/context/enrich_context.py`. Chỉ là chú thích; sửa comment test kéo theo duyệt "test đã sửa" nên để dành cho lần chạm các file đó.
- `CHANGELOG.md` (lịch sử: giữ nguyên) và `.agents/regression_status.json` (chuỗi evidence do máy ghi: không sửa tay).

## Phần B — Báo cáo đã đóng

### B.1 Audit DevKit 2026-10-09 — chạy tiếp ở local (macOS): kết quả *(trước đây: `docs/plans/audit-2026-10-09-followup.md`)*


#### Trạng thái

| Nơi | Commit | Nội dung | Đã kiểm chứng |
|---|---|---|---|
| `main` | `4425001` | Đợt 1–3 làm trên Linux cloud | trên Linux: 158/158 test bị ảnh hưởng |
| `main` | `94f388c` | macOS: so sánh đường dẫn theo inode (APFS), test camelCase, race worktree biến mất, guard `bash -c "$(…)"` / `>(sh)` / `find !`/`-o` | gate `--full` exit 0 |
| `main` | `430fb87` | `review_timing_guard` đọc payload qua fd 3, `DEVKIT_IMPACTED_SINCE` | gate `--full` exit 0 |
| `main` | `63f9561` | runner thiếu `set -e`, phạm vi `describe` JS, docstring/comment cuối dòng, project từ `cwd` payload (7 hook), đường tắt `churn_guard` | gate `--full` exit 0 (6/6), `run_impacted.sh` 112/112 |
| `main` | `6e6642b` | lý do từ chối của automerge, sửa theo audit Antigravity T0024 | gate `--full` exit 0 (3/3), `run_impacted.sh` 52/52 |

#### Bước 1–2 — kiểm chứng trên macOS (bash 3.2, APFS) — xong
- 6 test của đợt 3: PASS ngay (hook contract 687/687).
- `run_impacted.sh --all` (177 test, 377 s): 175 xanh, **2 đỏ thật**, sửa gốc:
  - `test_session_lock.sh` (case-only cwd): `realpath` giữ nguyên hoa/thường, APFS không phân biệt ⇒ đường dẫn viết khác hoa/thường bị coi là NGOÀI checkout đang khoá. `_inside` / `_same_dir` so theo inode ở 4 chỗ. ĐỎ 3 → XANH.
  - `test_hook_camelcase_payload.sh`: bash 3.2 cắt đối số `"$(cmd "{\"a\":…}")"` tại dấu nháy thoát ⇒ 2 hook chạy trên rác. Payload dựng bằng phép gán; assertion giữ nguyên.
- 1 lỗi **chập chờn** của gate (`test_worktree_merge_gate_owner.sh` mục 7, đỏ 2/3 lần gate): lỗi sản xuất thật — merge nền của Stop trước xoá worktree đúng lúc Stop này đang quyết định, dòng đó ở lại danh sách giữ. `worktree_merge_gate.sh` bỏ dòng có thư mục đã biến mất. Test tất định mới (shim `git`): ĐỎ 2 → XANH.
- `test_guards_orphans.sh` đỏ chỉ do luật runner mới: fixture thêm `set -e`, assertion giữ nguyên.

#### Bước 3 — gate `--full` — exit 0
Dòng rác `REG-01 echo FULL_TEST_EXECUTED` đã tự biến khỏi `CHECKLIST.md` và `regression_status.json` (kiểm: 0 khớp ở cả hai).

#### Bước 4 — RED-proof các dòng bug cũ
Công cụ: `scripts/testing/red_proof.py`; không sửa JSON tay. Hai phát hiện về chính công cụ:
- Sandbox không có upstream ⇒ `run_impacted.sh` tính commit của 6 giờ qua là "đã đổi" ⇒ mỗi bằng chứng 15+ phút chưa xong. Thêm `DEVKIT_IMPACTED_SINCE` (`0` = tắt cửa sổ); đặt khi chạy bằng chứng: 1–10 phút.
- `.sh` không nằm trong `SOURCE_EXT` của `red_proof.py`, và code đã chuyển chỗ/viết lại nên `git revert` xung đột: các bằng chứng dùng `--patch` (bản vá đưa bug trở lại, lưu ở `.agents/local/red-patches/`, đã commit).
- `tests/impact_map.txt` thiếu `enrich_context.py → test_bug_capture.sh`: gate không chạy test bảo vệ bộ lọc ROLE_OPENING, và bằng chứng của bug đó ra VACUOUS giả. Đã thêm (có test).

Kết quả (nguồn sự thật: cột RED-proof trong `.agents/CHECKLIST.md`): **29 PROVEN / 1 INCONCLUSIVE / 2 chưa chạy** trong 32 dòng bug. Trong 19 dòng "⏳ chưa chứng minh ĐỎ" ban đầu: **17 PROVEN**. Còn lại, kèm lý do:
- `BUG-20260929-audit-review-nguyen-nhan-tai-sao-cac-ses` — INCONCLUSIVE: hai commit sửa (`3d53c7c`, `a49bc13`) là tối ưu hiệu năng rải ở `post-fix-gate.py` / `regression_gate.sh` đã viết lại; bản vá đưa lại chỉ làm đỏ test khác, không làm đỏ `test_regression_gate_hook.sh` (không nêu tên test). Không tìm được cách đưa bug trở lại mà test bảo vệ đỏ ⇒ để nguyên.
- `BUG-20261002-agent-kit-health-run-tests-scores-96-100` — chưa chạy: bản sửa nằm ở `tests/run_impacted.sh` (file test: công cụ cấm vá) và `bin/agent-kit` (không đuôi, đã viết lại thành pool song song).
- `BUG-20261009-run-impacted-recent-commits-in-sandbox` — chưa chạy: bản sửa chính là `tests/run_impacted.sh` (file test).

#### Bước 5 — việc còn lại của Bước 3 (mục 2–4)
Quyết định chính sách do người dùng chọn qua câu hỏi: runner thiếu `set -e` ⇒ dòng nối thêm là sửa test (có); guard chỉ đóng ca ít báo động giả (`eval "$(…)"`, `source <(…)`, `bash script.sh`, `rm -r $VAR` giữ nguyên là giới hạn đã biết).

| Mục | Kết quả | Guard (đỏ → xanh) |
|---|---|---|
| `tee >(sh)`, `bash -c "$(…)"` | **xong** | `test_git_guard_shell_subst.sh` 9 → 0 |
| `find` có `!` / `-not` / `-o` | **xong** (+ sửa theo audit: nhóm bị phủ định) | `test_hardware_find_not_or.sh` 13 + 2 → 0 |
| `eval "$(…)"`, `source <(…)`, `bash script.sh`, `rm -r $VAR` | **không đóng (quyết định)** — phổ biến và hợp lệ (ssh-agent, brew shellenv, completions) | test hiện có khẳng định chúng được phép |
| `comment_claim_guard`: docstring Python, comment cuối dòng | **xong** | `test_comment_claim_docstring_trailing.sh` 10 → 0 |
| Đè test JS `it()` ở hai `describe` | **xong** (đếm theo đường `describe`; quét lỗi thì quay về đếm cả file) | `test_gate_js_describe_scope.sh` 4 → 0 |
| Runner thiếu `set -e` | **xong** (quyết định của người dùng) | `test_gate_runner_no_errexit.sh` 4 → 0 |
| `review_timing_guard` truyền payload qua env | **xong** (fd 3) | `test_review_timing_guard_big_payload.sh` 2 → 0 |
| Hook dò thư mục log theo cwd | **xong cho 7 hook làm rò `.claude/` ra cwd tiến trình**; 3 hook còn lại (`foreign_repo_gate`, `session_context`, `worktree_merge_gate`) đo ra không ghi gì ngoài project | `test_hook_log_dir.sh` 14 → 0 |
| `churn_guard` không có đường tắt | **xong** (`grep -c -F` 8 ms vs python 30 ms) | `test_churn_guard_fast_path.sh` 6 → 0 |
| `prompt_context` ~150 ms | **không đổi**: đo 160–240 ms/prompt; `enrich_context.py` 83 ms việc thật (biên dịch regex 20 ms, hai lần `git` 14 ms, import 28 ms) — không có phép tối ưu tất định đáng kể | — |
| Gate khởi động ~110 ms | **không đổi**: biên dịch 46 ms của 5,3 nghìn dòng; muốn bỏ phải tách file mà test nạp nó theo đường dẫn | — |

**Review ngữ cảnh sạch** (principal-code-reviewer trên 94f388c..6e6642b, bắt buộc bởi `review_gate`) tìm 6 điểm P3, đã sửa trong `fcf9fea`, mỗi điểm một ca đỏ → xanh: `find` nhóm dương chứa `-o` / đối số `-exec` bị từ chối nhầm (hồi quy của chính tôi) và toán tử `,`; chuỗi ba nháy gán mở docstring giả; `#!/bin/sh -e` không phải errexit; `bash -c ": ; $(…)"` lọt; `security_gate` mất luật fail-closed khi thiếu python3 ngoài cây git; registry phiên so git dir bằng chuỗi. Bảy dòng bug bị ảnh hưởng đã chứng minh ĐỎ lại (PROVEN).

Ba vòng review sau đó (chỉ commit sửa của vòng trước) tìm thêm 1 P2 + 3 P3, 2 P2 + 3 P3, rồi 2 P3 ở `b4ad8a9`; tất cả đã sửa, mỗi điểm một ca đỏ → xanh (vòng bốn: ĐỎ 7 trong `test_git_guard_shell_subst.sh` — một dấu ngoặc trong phép so sánh tắt kiểm tra phần còn lại của script `-c`, và thân `$( … )` thường bị coi là dữ liệu). Chi tiết và giới hạn đã chấp nhận (ngoặc trong nháy, `watch`/`ssh` trong `bash -c`) ở `CHANGELOG.md` "Đợt 13". Vòng 8 RED-proof: hai dòng `hardware-find-negated-or-unfiltered` và `git-guard-bash-c-subst-tee-shell` PROVEN lại sau các vòng sửa.

Giới hạn đã biết (chưa đóng): regex lấy `cwd` của payload (9 hook cũ + 7 hook mới) không đọc JSON thoát (`é`, `\\`); chỉ ảnh hưởng khi `CLAUDE_PROJECT_DIR` không đặt VÀ cwd tiến trình nằm ngoài cây git. Nâng cấp khi có harness gửi payload `ensure_ascii`: giải mã bằng python ở nhánh hiếm đó.

#### Bước 6 (mục 5 cũ) — kiểm chứng trên macOS
- Chạy thật lần đầu: xong (bước 1–3).
- `head_and_dirty` băm NỘI DUNG đích của symlink: **đã xác nhận** trên macOS (symlink trỏ lại sang file cùng nội dung ⇒ cùng sha; symlink treo ⇒ `None`). `push_gate.tested_fingerprint` đã bỏ qua so khớp chính xác khi có symlink trong `dirty` (ghi sẵn trong code), nên không đổi.
- Gemini qua alias (`includeDirectories` dùng đường dẫn thật): **chưa kiểm** — cần một phiên Gemini thật.

#### Việc người dùng hỏi thêm giữa chừng (Stop hook chạy lâu; worktree không merge/xoá)
- **Stop hook, GeelyEx2 hôm nay**: 28 lần gate ≈ 116 phút; 83 phút là Gradle. Nguyên nhân đo được: 11.229 file untracked dưới `CarConnect/app/src/test/resources` khớp glob của rule `REG-CAR-01` và không phải "mã nguồn bản đồ test hiểu được" ⇒ `select_impacted_tests` trả `ok=False` ⇒ **mỗi lượt Stop chạy ĐỦ lệnh Gradle** (214–300 s) thay vì 3 test thu hẹp (kiểm bằng cách gọi hàm với chỉ các file `.kt`: `ok=True, count=3`). Thêm ~60 s chi phí gate cho 11.267 file đổi. Commit hoặc ignore các file này là cách cắt nhiều nhất; gộp suite chỉ cắt phần nhỏ. Phiên GeelyEx2 đang tự gộp `REG-CAR-VOICE` vào `REG-CAR-01` (`covered_by`): cơ chế này chỉ bỏ VOICE khi `REG-CAR-01` đã chạy lệnh ĐẦY ĐỦ và PASS — ở lượt Stop điều đó đang xảy ra chính vì fallback nói trên. Hệ quả cần biết: khi 11k file được commit/ignore và `REG-CAR-01` chạy thu hẹp, VOICE (9 lớp, 140–270 s) KHÔNG còn được che và sẽ chạy riêng mỗi khi file voice đổi. Lựa chọn "gộp 3 suite Gradle thành 1 lệnh" của người dùng **chưa thực hiện**: `REG-CAR-VOICE` đã được phiên GeelyEx2 gộp bằng `covered_by` (commit–revert–commit trong giờ qua, tôi không sửa đè lên matrix đang bị sửa), `REG-CAR-01` và `REG-SHARED-01` dùng cùng lệnh đầy đủ và gate chạy mỗi lệnh một lần, và số đo cho thấy gộp thêm chỉ cắt phần nhỏ so với 11k file đang ép chạy đủ.
- **Worktree để lại**: ba nguyên nhân đo được ở GeelyEx2 — (1) phiên a792ad73 còn sống giữ main nên tự gộp bị hoãn (đúng luật: không gộp worktree của phiên đang chạy); (2) lần tự gộp `giao-tichhop-09-10` 19:03 bị pre-commit gate từ chối và thông báo cũ chỉ giữ 500 ký tự CUỐI của output gate (đoạn "0 phát hiện … REJECT"), mất lý do — **đã sửa** (`_refusal_text`, `test_worktree_automerge_reason.sh`); (3) worktree chưa từng vào danh sách "nợ" của một phiên đã kết thúc không bao giờ được phiên sau nhận nuôi (chỉ liệt kê ở SessionStart) — chưa đổi. Người dùng chọn để phiên GeelyEx2 tự gộp; không đụng vào worktree nào ở đó.
