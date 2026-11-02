# DevKit audit 2026-10-28

HEAD workbench: `8ff7ee9b`. Kit: `universal-agent-devkit`. Mười agent chỉ đọc, rồi lượt gộp đọc lại nguồn của từng dòng P1/P2 trong bảng. Không commit, không tạo issue, không chạy gate, không chạy suite. `git status` của kit lúc đo là sạch. Một gate khác đang giữ `test_run.lock` (PID 47611, `post-fix-gate.py --run-tests`), nên lượt này không chạy gate.

## 1. Kết luận

Workflow chưa hoàn hảo: `worktree finish` vẫn đưa commit vào main local khi gate không exit 0, installer super-board vẫn ghi đè file kit qua symlink, và guard không nhận tên lệnh viết bằng ANSI-C `$''`.

Origin không mở bằng `git push` thẳng. `agent-kit integrate` vẫn đòi `--full` exit 0 rồi `push_gate` mới push.

## 2. Bảng phát hiện

Dấu ✓ là dòng lượt gộp đã đọc lại. Không có dấu là agent đo và lượt gộp chưa mở lại file đó.

| ID | Mức | Mảng | Phát hiện | Bằng chứng | Issue | Đề xuất |
|---|---|---|---|---|---|---|
| A1 | P1 | Gate / merge | `worktree finish` coi là qua khi không có suite `FAIL`/`TIMEOUT` và không cờ `busy`/`budget_exhausted`. Exit 1 (tĩnh đỏ, suite vẫn PASS), exit 4 nhãn `SLOT`, và exit 2 (test đã sửa chưa duyệt) đều `return None, False` rồi fast-forward main local. | ✓ `universal-agent-devkit/scripts/git/worktree.py:3261-3283`, gọi tại `:4027`. Exit 1 tại `bin/post-fix-gate.py:7435-7437`. `SLOT` là `UNTESTED` tại `:6847-6852` và exit 4 tại `:7479-7484`. JSON có `exit_code` (`:7730-7731`) nhưng `_merge_gate` không đọc. | Exit 2 là #486 đang mở. Exit 1 và `SLOT` chưa có issue. | Chỉ nhận exit 0, hoặc exit 3 (không có gì để kiểm). Thiếu JSON thì từ chối. `SLOT` phải vào `_gate_refusal`. |
| A2 | P1 | Cài đặt | `copy_file` vẫn `cp` khi đích không cùng file nguồn. Dest là symlink vào kit thì `cp` ghi đè kit. Vòng `hooks/*.py` áp cho mọi hook Python của pack, không chỉ `guard-protected-push.py`. | ✓ `/Users/alex/.local/share/super-board/install.sh:142-146` và `:183-186`. `-ef` chỉ bỏ qua khi dest chính là file pack. | Vẫn đúng #462. Anh em cùng hàm: `guard-secrets.py`. | Nếu dest là symlink thì bỏ qua và thoát lỗi. Cấm cài pack lên 4 repo symlink trước khi vá. |
| A3 | P1 | Guard | `$'\x67it' reset --hard` và `$'\x72m' -rf /` thoát 0. Lexer giữ nguyên `\xNN`, nên tên không còn là `git`/`rm` và mọi luật phía sau không chạy. Lệnh trần cùng nội dung bị chặn (exit 2). | ✓ `hooks/shell_norm.py:377-384` (`ansi_c_to_single` để nguyên escape) và `:413`. Agent 6 chạy hook stdin: hai payload ANSI-C exit 0; `git reset --hard` và `rm -rf /` exit 2. 20 payload, không lệnh phá thật. | Mới. | Giải `\xHH`, `\nnn`, `\uHHHH` trong `$''` trước khi so tên chương trình. |
| A4 | P2 | Gate / merge | Main không có file ma trận trên đĩa thì `finish` bỏ gate, kể cả repo đã cài DevKit. Xoá file ở working tree (blob vẫn trong commit) cũng tắt gate. | ✓ `worktree.py:3218-3226` (`os.path.isfile`) và `:4027` (`if matrix else (None, False)`). | #482 chỉ vá `push_gate` (`bin/push_gate.py:289-293`). Không phải hồi quy của bản đã đóng. | Có `.agents/devkit` mà không đọc được ma trận từ `HEAD` thì `finish` blocked. |
| A5 | P2 | Gate | Suite `keyed_full` quá giờ bị đổi thành `UNTESTED` và bị loại khỏi `tests_untested`. Không còn FAIL thì `--full` rơi vào nhánh PASS exit 0, chữ "ĐỦ ĐIỀU KIỆN NGHIỆM THU". Comment trong file gọi đây là chủ đích. | ✓ `post-fix-gate.py:7354-7361`, `:7370-7379`, `:7512-7513`. | Mới. Không trùng #363 (KNOWN-RED đòi bằng chứng trên base). | Đừng ghi exit 0 khi `stale_skipped` còn suite quá giờ. Exit 4, không biên nhận bàn giao. |
| A6 | P2 | Super-board | Thẻ Blocked mà `## Blocked by` không phải gạch `- #N` thì sweep không thả. #499 vẫn OPEN. Blocker #459 đã CLOSED. Body là một dòng `#459 (PR #491)`, không có bullet. | ✓ `super-board-deps.sh:121-123`. ✓ body #499. Agent 2: runner chỉ `log`, không comment, `super-board-run.sh:2142-2151`, log `docs/super-board/runs/2026-10-28-agent-workbench.md:1263`. | Mới (thẻ là #499, chưa có issue cho parser). | Sửa body #499 thành `- #459`, hoặc parser nhận `#N` không bullet và comment khi không đọc được. |
| A7 | P2 | Super-board | Nhánh `resume` chuyển Blocked → Review và không gọi `unmark`. `needs-you` còn. Trong `super-board-run.sh` không có chữ `unmark`. Trailer `--- decision ---` không có parser trong `.claude/**/*.py` và `.claude/**/*.sh` (agent 9). | ✓ `super-board-run.sh:2211-2229`. ✓ `rg unmark` trên file đó: 0. Luật bảo unmark nằm ở `references/run.md` (agent 2). | Mới. | `unmark` trong nhánh resume trước khi đổi cột. Parser trailer hoặc comment quyết định trước khi hỏi lại. |
| A8 | P2 | Super-board | Việc agent làm được vẫn tới người. `blocked-by: -` thành `human_gated` và không đi qua exit 64. `one_line` chỉ soi `--action`, và một từ trong `GENUINE_HUMAN_RE` (ví dụ `firebase`) tắt cả denylist. Denylist không có "split the card", "worktree finish", "Xcode Simulator". | ✓ `super-board-needs-you.py:49-94` và `:140-155`. ✓ `super-board-deps.sh:138-140` và `:170-171`. | Mới. | Chặn theo ý, cả `--action` và `--next`. `GENUINE_HUMAN_RE` không được tắt cả câu. Reclaim/no-op không ghi `blocked-by: -`. |
| A9 | P2 | Super-board | Worker build còn PID thì không có trần giờ ở cột Building. Tick đủ 5 worker bỏ cổng RUNAWAY. | Agent 10 đọc `super-board-run.sh:835-839`, `:2835-2839`, `:1940`, `:2001`. Watchdog chỉ đổi chữ, `super-board-watchdog.sh:385-390`. Lượt gộp chưa đọc lại các dòng này. | #464 đã đóng cho halt daemon. Lỗ tick rẻ và trần Building chưa có issue. | Trần im lặng cho build/QA. Tick rẻ vẫn đếm không-tiến-triển. |
| A10 | P2 | Super-board | Codex đặt `SB_MERGE_QUEUE=0`, và gate coi `0` là tắt hàng đợi dù config bật. Một lượt merge lẻ không làm canary đỏ. Không nhãn `ac-open` thì queue kéo Done, không đọc checkbox AC. | ✓ `super-board-codex-lane.sh:205`. ✓ `super-board-merge-gate.sh:165-174`. ✓ `super-board-merge-queue.sh:259-267`. Canary một lượt: agent 10 đọc `batch_canary.py:171-184`. | #471 đóng cho trường hợp ≥2 PR. Cửa một PR và Codex chưa có issue. | Lane Codex của board đã bật hàng không được đặt `SB_MERGE_QUEUE=0`. Done chỉ khi đã đọc checkbox, hoặc còn `ac-open`. |
| A11 | P2 | 5 repo | Merge queue và `verify-cmd --mark` chỉ thấy ở Idle-Plaza-3D và OfficeReader. HVU, Goods, Geely thiếu `super-board-verify-cmd.sh`, `super-board-merge-queue.sh`, `super-board-merge-train.sh`. | Agent 3 đọc config và `cmp` kích thước script. Lượt gộp không `cmp` lại. | Vẫn đúng #460, #441, #499. | Port sau khi vá A2. Không chạy `install.sh` hiện tại. |
| A12 | P2 | 5 repo | Cả 5 `.agents/devkit` trỏ đúng kit. Hook runtime của HVU, IP3, Goods, OfficeReader cùng inode kit. Geely `guard-protected-push.py` là file thường, `samefile` với kit là false. Goods/HVU: index và cây làm việc lệch kiểu (`git status` ra `T`) theo agent 3. | ✓ `readlink` + `os.path.samefile` lượt gộp, HEAD `8ff7ee9b`. Sha index Goods: agent 3. | Hệ quả #462. Chưa có issue riêng cho kiểu file trong index. | Đừng `git checkout` file `T` (sẽ thay symlink bằng blob pack cũ). Geely đổi file thường thành symlink sau A2. |
| A13 | P2 | Guard | `rm -rf $(echo /)` thoát 0 ở `guard-delete-outside.py`. `rm -rf /` trần bị chặn. Docstring của hook đã ghi giới hạn command substitution. | Agent 3, 18 payload trên hook mà settings HVU trỏ. Lượt gộp chưa đọc `expand()`. | Mới, nếu muốn đóng giới hạn đã ghi trong docstring. | Từ chối đích `rm` có `$(` hoặc backtick. |
| A14 | P3 | Stop | Gate crash hoặc exit lạ: Stop ghi `fail-open: gate crashed` rồi `sys.exit(0)`. Không đẩy main. | ✓ `hooks/regression_gate.sh:907-914`. | Mới, mức thấp. Comment ghi đây là chủ đích từ 2026-09-26. | Crash thì exit 2 của hook, không ghi `pass_fp`. |
| A15 | P3 | Stop | Cây git sạch thì Stop thoát 0 trước khi tính hash `.env` / `local.properties`. `git status` không hiện file ignore. | ✓ `regression_gate.sh:283-290`. Hash ignore nằm sau, khoảng `:575`. | Nghi ngờ về mức hại. Push trunk vẫn qua `push_gate`. | Nếu `.env` đổi so với lần PASS, đừng skip. |

## 3. Top 5, theo thứ tự

1. A1. `finish` chỉ nhận exit 0 hoặc exit 3. Gộp luôn #486.
2. A2. Vá `copy_file` trước mọi lần cài super-board. #462 đang mở, và lỗ ăn sang `guard-secrets.py`.
3. A3. Giải ANSI-C trong tên lệnh của `shell_norm.py`.
4. A5. Suite `keyed_full` quá giờ không được thành PASS exit 0.
5. A7 cùng A8, rồi A6. `unmark` khi resume, siết denylist, sửa body #499 hoặc parser. A9 và A10 làm ngay sau nhóm này nếu board vẫn đang chạy.

## 4. Điểm đã tốt

Đừng nới các chốt này.

- Push trunk trực tiếp bị từ chối. Thiếu ma trận khi đã có `.agents/devkit` cũng bị từ chối. ✓ `push_gate.py:289-293` và `:300-301`. #482 còn đóng trên `push_gate`.
- `agent-kit integrate` là `exec python3`. ✓ `bin/agent-kit:287-291`. #480 còn đóng.
- Integrate chạy `--full` trong scratch và đây là lượt full của điểm gộp. ✓ `scripts/git/integrate.py:270-279`.
- Stop gỡ `POSTFIX_GATE_FULL` khỏi env. ✓ `hooks/regression_gate.sh:802-804`. #487 còn khớp. `CI` và `POSTFIX_GATE_FORCE_FULL` vẫn truyền xuống, đúng comment #472.
- `integrate` không push khi `--full` không exit 0. Hai agent đọc `integrate.py:374-389`. Lượt gộp chưa mở lại dòng push.
- Pre-commit không gọi `--full`. Agent 1 đọc `scripts/git-pre-commit.sh:7-13`.
- Retry flaky không đổi FAIL thành PASS khi lần đầu đã có dòng lỗi test. Agent 4 và agent 8 đọc `post-fix-gate.py:6936-6942`.
- BUSY / BUDGET / SLOT không xoá biên nhận cũ, và không được `accepted`. Agent 4 đọc `:7425-7427` và `:7732`. `_merge_gate` vẫn từ chối `busy` và `budget_exhausted` (`worktree.py:3272-3277`).
- Khoá `test_run.lock` của PID chết không bị coi là gate sống. Agent 8 đọc `post-fix-gate.py:4632-4647`. #442 và #488 không thấy cơ chế cũ trên HEAD.
- `ac-open` không bị queue kéo Done. ✓ `super-board-merge-queue.sh:259-261`. Verify đỏ đi Ready, không Done (`:270-276`).
- Năm repo đều symlink `.agents/devkit` về cùng một kit. Bốn repo app dùng hook kit qua cùng inode, trừ Geely `guard-protected-push.py` (A12). Sửa kit lan ngay ra bốn repo đó.
- Workbench không có file kit dirty lúc đo. Một lỗ trong kit chưa commit thì chưa lan. Một lỗ đã commit, hoặc một `cp` xuyên symlink, lan ngay.
- Exit 64 của `needs-you` chạy trước lệnh `gh`. ✓ `super-board-needs-you.py:316` nằm sau `one_line` ở `:148-154`. Bộ câu trong `tests/super-board/test_needs_you_autonomous_guard.sh` vẫn bị chặn nếu khớp regex.

## 5. Issue đề xuất

Chưa tạo. Chọn số rồi bảo tạo.

1. `worktree finish`: từ chối mọi exit khác 0 và 3, gồm exit 1 tĩnh và exit 4 `SLOT`. Nhắc #486 cho exit 2, không mở issue thứ hai cho cùng một `return`.
2. `finish` fail-closed khi có `.agents/devkit` mà ma trận không đọc được từ `HEAD`.
3. `shell_norm`: giải ANSI-C `$''` trước khi so tên lệnh. Test `$'\x67it'` và `$'\x72m'`.
4. Giữ #462, mở rộng AC: mọi `hooks/*.py`, gồm `guard-secrets.py`. Không tạo issue mới.
5. Biên nhận `--full` không được exit 0 khi còn suite `keyed_full` quá giờ trong `stale_skipped`.
6. Sweep: `## Blocked by` nhận `#N` không bullet, hoặc comment lên thẻ khi không parse được. Sửa body #499 là việc riêng, không cần issue nếu chỉ sửa một dòng.
7. Resume gọi `unmark`. Parser cho trailer quyết định, hoặc cấm hỏi lại khi comment `done` đã mới hơn request.
8. `needs-you`: denylist theo ý, áp vào `--next`, `GENUINE_HUMAN_RE` không tắt cả câu. Reclaim và no-op không dùng `blocked-by: -`.
9. Trần im lặng cho Building/QA, và tick đủ worker vẫn đếm RUNAWAY.
10. Codex của board đã bật merge queue không đặt `SB_MERGE_QUEUE=0`. Canary đỏ từ một lần merge lẻ sau `enabled_at`. Done không đọc được checkbox thì không kéo Done.
11. `guard-delete-outside`: từ chối đích `rm` có `$(` hoặc backtick.
12. Index Goods/HVU: bỏ kiểu file lẫn (blob pack trong index, symlink ở working tree). Làm sau mục 4.

Không mở lại: #475, #480, #481, #482 (phần `push_gate`), #487, #488, #489, #442, #430, #434, #465, #470, #425. #450 và #473 vẫn mở và agent 8 thấy chưa là tổ tiên của `8ff7ee9b`. #451 và #454 vẫn đúng trên source test, không chạy lại ở lượt này. #230 vẫn mở: merge gate bỏ verify theo marker `verified-trees`, không theo fingerprint `tree_fp` (agent 7).

## Nghi ngờ, chưa đủ để vá

- `proof_gate` không so `local_sha` của biên nhận. Agent 5 đọc `proof_gate.sh:340-417`. Lượt gộp chưa đọc lại.
- `os._exit(0)` khi SIGALRM 13s trong `hooks/worktree_merge_gate.sh:60-66` là có thật (đã đọc). Chỉ nút Stop, và không gọi `save()` trên đường đó. Mức hại khi đang không giữ worktree: chưa chạy hook nên chưa xếp P2.
- Con `stale_rerun` không bắt INT/TERM. Agent 8. Chưa đọc lại.
- Help vẫn bảo chạy `--full` trước mọi bàn giao (`post-fix-gate.py:15-16`, `:5698`). Trùng #483, không phải lỗ mới.

## Việc lượt này không làm

Không chạy `post-fix-gate`, `finish`, `integrate`, installer, hay suite. Không sửa #499. Không xoá nhánh backup hay stash của Goods (agent 3 thấy `backup/wt-tmp.*` và stash `port187`). HVU lúc agent 3 đo đang bị session khác giữ (`session_lock` exit 3).
