# Danh Sách Đầu Việc Backlog Cho Agent Workbench (Super-Board)

> **Nguồn tổng hợp:** `universal-agent-devkit/docs/workflow-improvements.md` (tồn đọng đợt 15–16/10) và `universal-agent-devkit/docs/deep-code-audit-10-agents.md` (10 Slices kiểm toán 144 lỗi).
> **Chuẩn định dạng:** Tuân thủ 100% quy cách Super-Board tại [`docs/agents/issue-tracker.md`](file:///Volumes/Data/Toan/agent-workbench/docs/agents/issue-tracker.md).
> **Project Board đích:** [Agent Workbench Project #1](https://github.com/users/ToanMobile/projects/1) (`ToanMobile/agent-workbench`).

---

## 🚀 EPIC-01: Critical Operational Unblockers (Vá nghẽn vận hành hàng ngày)

### TICKET-01: 🐛 [bug] hooks: sửa quy chụp nhầm quyền tác giả trong review_gate

## Problem
Lệnh chỉ đọc (như git diff, grep, dotnet test) nhắc đến tên file dirty bị quy chụp là phiên hiện tại vừa sửa file, gây 43 lần auto-release và 10 lần chặn oan. Các câu trả lời hội thoại chưa xong cũng bị ép chạy review OCR.

## Context
- **Where:** `universal-agent-devkit/hooks/review_gate.sh`, line 601
  - a. Agent chạy lệnh kiểm tra `git diff src/foo.py`
  - b. Hàm `_names()` khớp chuỗi tên file và kích hoạt `session_touched.add()` oan
  - c. Cửa sổ lệnh mở `BASH_OPEN_MAX_S = 7200` giây (2 giờ) giữ trạng thái bẩn quá lâu
- **Who:** Mọi agent chạy trong linked worktree hoặc repo có file dirty từ phiên trước

## Fix
Đổi `_names(_bcmd, _rel, _base)` thành `_writes(_bcmd, _rel)` tại dòng 601 của `review_gate.sh`. Giảm `BASH_OPEN_MAX_S` xuống 300s. Thêm phân giải `session_worktree.py` cho `review_gate.sh` & `claim_check.sh`. Đổi `work_in_progress(d)` thành `status_optional=True`.

## Acceptance Criteria
- [ ] Lệnh `git diff <file_dirty>` không làm file đó bị thêm vào `session_touched`.
- [ ] Phản hồi giữa chừng không có từ khóa `XONG` không bị chặn bởi OCR review gate.
- [ ] Hook `review_gate.sh` và `claim_check.sh` đối chiếu đúng diff trong linked worktree thay vì main.

## Risk
🟢 **Low** · Thu hẹp điều kiện bắt dirty file, không ảnh hưởng logic audit chính.

## Blocked by
- None.

---

### TICKET-02: 🐛 [bug] governance: giải tỏa deadlock trunk mode trong nightly và shadowing red_proof

## Problem
Chạy `nightly.py` ban đêm bị kẹt cứng 100% do từ chối chạy trên `main` ở Trunk Mode (`exit 5`), trong khi linked worktree lại bị từ chối ghi sổ. Đồng thời `red_proof.py` ghi đè biến làm hỏng toàn bộ metadata của chế độ revert.

## Context
- **Where:** `scripts/governance/nightly.py`, `scripts/testing/red_proof.py`
  - a. `nightly.py` gọi `session_lock.py --status` trả về `exit 5` (Trunk Mode)
  - b. `checkout_busy()` coi `rc == 5` là bận và bỏ qua `red_proof.py --pending`
  - c. `red_proof.py` dòng 673 ghi đè biến `patch = git(...).stdout` làm trường patch lưu nội dung diff thay vì path
- **Who:** Tiến trình Nightly cron và hệ thống trả nợ kiểm thử RED-proof tự động

## Fix
Trong `nightly.py:checkout_busy()`, coi mã thoát `rc == 5` (Trunk Mode, không có phiên độc quyền) là rảnh (`return None`), chạy `red_proof.py` với cờ `--detached`. Đổi tên biến cục bộ dòng 673 trong `red_proof.py` thành `rev_diff`.

## Acceptance Criteria
- [ ] `nightly.py` thực thi thành công trên repo bật Trunk Mode mà không bị bỏ qua.
- [ ] `red_proof.py` ở chế độ revert lưu đúng metadata path không bị phình dữ liệu unified diff.

## Risk
🟡 **Medium** · Đụng chạm luồng điều phối cron ban đêm và công cụ kiểm chứng đỏ.

## Blocked by
- None.

---

### TICKET-03: 🐛 [bug] hooks: sửa test_evidence_gate từ chối gate-green và đếm nhầm commit test

## Problem
Check 7 (`paired_red_green`) của `test_evidence_gate.sh` từ chối kết quả `"gate-green"` do `post-fix-gate.py` sinh ra dù Check 2 đã công nhận, đồng thời việc commit/sửa file test bị tính nhầm là sửa production code làm mất hiệu lực oracle.

## Context
- **Where:** `universal-agent-devkit/hooks/test_evidence_gate.sh`, line 888, 1109, 1728
  - a. Check 2 cho phép `r[5] in ("green", "gate-green")`
  - b. Check 7 dòng 1728 chỉ kiểm tra cứng `r[5] == "green"`, từ chối kết quả gate
  - c. Dòng 1109 cập nhật `last_src_edit_idx` thiếu điều kiện `not is_test_path(fp)`
- **Who:** Lập trình viên chạy `post-fix-gate.py` hoàn thành test RED→GREEN

## Fix
Chấp nhận `r[5] in ("green", "gate-green")` tại dòng 1728 của `test_evidence_gate.sh`. Thêm kiểm tra `not is_test_path(fp)` trước khi cập nhật `last_src_edit_idx` tại dòng 1109 và 1115.

## Acceptance Criteria
- [ ] Chạy `post-fix-gate.py` sinh verdict `gate-green` được Check 7 công nhận đạt yêu cầu.
- [ ] Sửa hoặc commit file test sau khi chạy RED không làm vô hiệu hóa kết quả test trước đó.

## Risk
🟢 **Low** · Sửa điều kiện so khớp chuỗi trạng thái và loại trừ file test.

## Blocked by
- None.

---

### TICKET-04: ✨ [feature] gate: hỗ trợ push_gate nhận biên nhận full_pass từ linked worktree

## Problem
Ở Trunk Mode, nhánh `main` chỉ nhận merge nên không thể chạy gate trực tiếp. Khi push từ `main`, `push_gate.py` đòi biên nhận tại thư mục git của `main`, trong khi gate được chạy trong linked worktree và ghi biên nhận tại worktree đó.

## Context
- **Where:** `universal-agent-devkit/bin/push_gate.py`, line 472, 506
  - a. Agent chạy gate `--full` exit 0 trong worktree `../agent-workbench-task`
  - b. Agent merge vào `main` bằng `agent-kit worktree finish`
  - c. Push từ `main` bị `push_gate.py` từ chối vì thiếu `full_pass.json` tại `main`
- **Who:** Mọi phiên làm việc cần `git push origin main` sau khi hoàn tất task

## Fix
Cập nhật `push_gate.py` chấp nhận biên nhận `full_pass.json` từ linked worktree nếu commit HEAD của worktree khớp với commit chuẩn bị push từ main; hoặc cập nhật `worktree finish` tự động đồng bộ biên nhận về thư mục git chính.

## Acceptance Criteria
- [ ] Lệnh `git push origin main` vượt qua push gate thành công khi worktree trước đó đã pass gate exit 0.
- [ ] Có bài test tự động mô phỏng merge từ worktree và xác nhận push gate pass.

## Risk
🟡 **Medium** · Đụng chạm cổng kiểm soát git push của toàn bộ repository.

## Blocked by
- None.

---

### TICKET-05: ⚡ [perf] gate: tích hợp A15 gate speed và giải tỏa nghẽn khóa 45s tại stop hook

## Problem
Stop hook `regression_gate.sh` đặt thời gian chờ khóa 45 giây ngay cả khi mọi test suite đã được cache. Hiện tượng TOCTOU tái sinh `full_pass.json` cũ khi nhiều tiến trình chạy song song và receipt thiếu schema version.

## Context
- **Where:** `universal-agent-devkit/bin/post-fix-gate.py`, `hooks/regression_gate.sh`
  - a. Dòng 4855 của `post-fix-gate.py` tái sử dụng receipt trước khi lấy khóa
  - b. `regression_gate.sh` chờ khóa 45s kể cả khi `nothing_to_run == True`
  - c. Bản vá A15 trên worktree `agent-a89d86b8e80426e23` đã xử lý nhưng chưa gộp vào main
- **Who:** Mọi agent khi kết thúc lượt prompt gặp độ trễ lớn

## Fix
Hợp nhất các cải tiến từ worktree A15: kiểm tra cache trước khi chờ khóa trong `regression_gate.sh`, nâng cấp `SCHEMA_VERSION = 2`, bắt `RecursionError` khi đọc receipt và kiểm tra file tồn tại dưới khóa.

## Acceptance Criteria
- [ ] Stop hook phản hồi tức thì (<1s) khi các test suite đều có kết quả cache hợp lệ.
- [ ] Chạy 12 tiến trình gate đồng thời không sinh lỗi flaky trong `test_gate_run_log.sh`.

## Risk
🟡 **Medium** · Sửa logic đồng bộ đa tiến trình của gate trung tâm.

## Blocked by
- None.

---

## 🛡️ EPIC-02: Command Guard & Security Hardening (Khóa an toàn Parser & Chống Bypass)

### TICKET-06: 🔒 [bug] security: review độc lập vòng 6 và triệt tiêu bypass ANSI-C quote, newline, dollar-brace

## Problem
Bất đồng bộ giữa bộ lọc comment và parser shlex cho phép các payload chứa chuỗi `$'\''`, `\<newline>` trước `#`, hoặc `\${` vượt qua git guard và hardware safety gate với `exit 0` để thực thi `git reset --hard` hoặc `rm -rf`.

## Context
- **Where:** `universal-agent-devkit/hooks/block-dangerous-git.sh`, `hardware_safety_gate.sh`, `shell_norm.py`
  - a. Payload `echo $'\''; git reset --hard HEAD; echo \'` đi qua với exit 0
  - b. Nối dòng `\<newline>` trước `# '` làm lệch trạng thái nháy đơn
  - c. Ký tự `\${ # '` làm tăng biến đếm brace giả, nuốt lệnh nguy hiểm bên dưới
- **Who:** Hệ thống bảo vệ an toàn phần cứng và an toàn kho mã nguồn git

## Fix
Reviewer độc lập chạy lại driver kiểm thử 250 mẫu, `corpus5.py` và `crash5.py`. Chuẩn hóa token ANSI-C `$'\''` trước khi đưa vào `shlex`; gọi `fold_continuations()` trước `drop_comments()`; kiểm tra số lượng dấu escape `\` trước ký tự `${`.

## Acceptance Criteria
- [ ] PoC `echo $'\''; git reset --hard HEAD; echo \'` bị chặn (`exit 1/2`).
- [ ] PoC `echo $'\''; rm -rf /Users; echo \'` bị chặn (`exit 1/2`).
- [ ] PoC nối dòng `\<newline>` trước `#` bị chặn (`exit 1/2`).

## Risk
🔴 **High** · Liên quan trực tiếp đến rào chắn an toàn hệ thống, bắt buộc chạy paired test và review độc lập.

## Blocked by
- None.

---

### TICKET-07: 🔒 [bug] security: chặn bypass qua inline script cờ gộp và bổ sung solo_branch_rule

## Problem
Lệnh `inline_script_code()` chỉ bắt cờ rời `-c`, `-e`, bỏ lọt cờ gộp POSIX như `python3 -ISc "..."` hoặc `node --eval="..."`. Ngoài ra `git_in_literals` thiếu kiểm tra quy tắc nhánh đơn (`solo_branch_rule`).

## Context
- **Where:** `universal-agent-devkit/hooks/block-dangerous-git.sh`, `hardware_safety_gate.sh`
  - a. Lệnh `python3 -ISc "import os; os.system('git reset --hard')"` thoát kiểm tra
  - b. Lệnh `python3 -c "import subprocess; subprocess.run(['git','checkout','-b','x'])"` thoát kiểm tra nhánh đơn
- **Who:** Các script cố tình bọc lệnh git/rm nguy hiểm trong tiến trình con

## Fix
Trích xuất argument script cho cả cờ gộp POSIX và dạng `--flag=value`. Bổ sung gọi `solo_branch_rule` và `checkout_path_rule` bên trong `git_in_literals()`.

## Acceptance Criteria
- [ ] `python3 -ISc "import os; os.system('git reset --hard')"` bị chặn (`exit 1/2`).
- [ ] Lệnh tạo nhánh mới thông qua inline script bị chặn bởi quy tắc solo branch.

## Risk
🟡 **Medium** · Mở rộng phạm vi phân tích đối số CLI của các trình thông dịch.

## Blocked by
- None.

---

### TICKET-08: 🛡️ [bug] hooks: sửa fail-open trong worktree_guard khi shell_writes trả None

## Problem
`worktree_guard.sh` gọi `shell_writes.targets(cmd)` với `run_bodies=False` và khi kết quả là `None` (câu lệnh quá phức tạp), hook coi như danh sách rỗng (fail-open) và bỏ qua mọi đường dẫn chứa biến `$PWD`.

## Context
- **Where:** `universal-agent-devkit/hooks/worktree_guard.sh`, `hooks/shell_writes.py`
  - a. Khi gặp cú pháp shell phức tạp, `shell_writes.targets` trả `None`
  - b. `worktree_guard.sh` dòng 443 gán `targets = []` cho qua lệnh
- **Who:** Các câu lệnh ghi file dùng cú pháp lồng nhau trong worktree

## Fix
Bật `run_bodies=True` khi gọi `shell_writes.targets`. Khi `targets` trả `None`, áp dụng cơ chế fail-closed (từ chối hoặc chuyển sang phân tích tĩnh nghiêm ngặt). Nội suy biến `$PWD` trước khi đối chiếu ranh giới worktree.

## Acceptance Criteria
- [ ] Lệnh ghi file phức tạp không thể thoát ranh giới worktree bằng cách đánh lừa parser trả về `None`.
- [ ] Biến `$PWD` được giải mã thành đường dẫn tuyệt đối trước khi kiểm tra ranh giới.

## Risk
🟡 **Medium** · Có thể chặn nhầm nếu biểu thức shell không được parse đúng; cần test suite bao phủ.

## Blocked by
- None.

---

### TICKET-09: 🛡️ [bug] hooks: sửa chuẩn hóa đường dẫn tương đối trong precode_gate và foreign_repo_gate

## Problem
`precode_gate.sh` kiểm tra `os.path.exists()` trước khi chuẩn hóa `norm(path)` và bỏ sót key `notebook_path`. `foreign_repo_gate.sh` bỏ qua đường dẫn tương đối (`../repo-khac/file.py`) vì chỉ kiểm tra `isabs()`.

## Context
- **Where:** `universal-agent-devkit/hooks/precode_gate.sh`, `hooks/foreign_repo_gate.sh`
  - a. `precode_gate.sh` dòng 100 bỏ sót `notebook_path` ở fast-path bash
  - b. `foreign_repo_gate.sh` dòng 64 lập tức `sys.exit(0)` nếu đường dẫn không phải tuyệt đối
- **Who:** Các thao tác sửa file notebook hoặc truy cập file repo lân cận bằng relative path

## Fix
Dùng `target = norm(path)` cho `os.path.exists()` và bổ sung `notebook_path` trong `precode_gate.sh`. Dùng `os.path.abspath(os.path.join(cwd, fp))` trong `foreign_repo_gate.sh` để bắt đường dẫn tương đối ra ngoài repo.

## Acceptance Criteria
- [ ] Đường dẫn tương đối dạng `../other-repo/secret.txt` bị `foreign_repo_gate.sh` phát hiện và chặn.
- [ ] File Jupyter Notebook được `precode_gate.sh` kiểm tra đúng tiền điều kiện.

## Risk
🟢 **Low** · Sửa logic chuẩn hóa đường dẫn.

## Blocked by
- None.

---

### TICKET-10: ⚡ [perf] hooks: tối ưu quét tăng dần cho security_gate và đọc ngược trong churn_guard

## Problem
`security_gate.sh` quét lại toàn bộ file từ đầu mỗi lượt (chưa có offset cache). `churn_guard.sh` đọc toàn bộ transcript vào RAM qua `readlines()`.

## Context
- **Where:** `universal-agent-devkit/hooks/security_gate.sh`, `hooks/churn_guard.sh`
  - a. `security_gate.sh` không lưu offset (grep offset ra 0 khớp)
  - b. `churn_guard.sh` dòng 230 đọc trọn transcript gây tốn RAM khi phiên dài
- **Who:** Mọi phiên làm việc có transcript lớn hoặc repo có nhiều file mã nguồn

## Fix
Thêm offset cache (kích thước + inode + hash) cho `security_gate.sh`, lùi về quét đầy đủ khi phát hiện file bị thay đổi. Đổi `churn_guard.sh` sang đọc ngược theo từng khối buffer (chunked reverse reading).

## Acceptance Criteria
- [ ] Thời gian quét của `security_gate.sh` trên file lớn giảm $\ge 70\%$ ở các lượt kế tiếp.
- [ ] `churn_guard.sh` không chiếm dụng bộ nhớ lớn khi transcript đạt hàng chục MB.

## Risk
🟢 **Low** · Tối ưu hóa hiệu năng, có fallback quét toàn bộ an toàn.

## Blocked by
- None.

---

## 📦 EPIC-03: Worktree Isolation, Git & Session Lock (Bảo toàn dữ liệu & Phân lập Trunk Mode)

### TICKET-11: 💥 [bug] git: ngăn chặn worktree gc và worktree_sandbox xóa mất code chưa commit

## Problem
`worktree.py cmd_gc` xóa thẳng worktree nếu hash file trùng với bất kỳ blob nào trong lịch sử git toàn repo (`sha not in blobs` với `rev-list --objects --all`). `worktree_sandbox.py` xóa thư mục trước khi kiểm tra số lượng commit chưa merge (`ahead`).

## Context
- **Where:** `universal-agent-devkit/scripts/git/worktree.py`, `scripts/git/worktree_sandbox.py`
  - a. File mới tạo có nội dung rỗng hoặc khôi phục code cũ có blob trùng lịch sử git
  - b. `_gc_unique()` trả về `False` và gọi xóa thư mục mà không lưu patch
  - c. `cleanup_sandbox()` gọi `shutil.rmtree()` trước khi chạy `git rev-list`
- **Who:** Lập trình viên đang làm việc trong worktree hoặc sandbox có file chưa commit

## Fix
Trong `worktree.py cmd_gc`: tuyệt đối không xóa worktree nếu `git status --porcelain` khác rỗng (đối chiếu HEAD của chính worktree). Trong `cleanup_sandbox()`: kiểm tra status và `ahead == 0` an toàn trước khi xóa thư mục và nhánh.

## Acceptance Criteria
- [ ] Worktree có file uncommitted không bao giờ bị xóa mất dữ liệu bởi lệnh `agent-kit worktree gc`.
- [ ] Sandbox còn commit chưa merge vào main sẽ từ chối dọn dẹp và cảnh báo người dùng.

## Risk
🔴 **High** · Trực tiếp bảo vệ an toàn dữ liệu mã nguồn người dùng, không để mất code.

## Blocked by
- None.

---

### TICKET-12: 🔒 [bug] locks: bịt lỗ hổng bypass trunk mode từ worktree ghi vào main qua biến môi trường

## Problem
Trong `session_lock.py: _bash_trunk_write()`, khi lệnh ghi chứa ký tự `$` hoặc `` ` ``, hàm chỉ kiểm tra nếu đích ghi rơi vào main dựa trên thư mục hiện tại. Nếu agent đứng trong linked worktree, kiểm tra bị bỏ qua cho phép ghi đè thẳng vào main.

## Context
- **Where:** `universal-agent-devkit/bin/session_lock.py`, line 1522–1525
  - a. Agent trong linked worktree chạy: `MAIN=/path/to/main; echo evil > "$MAIN/src/foo.py"`
  - b. `_lands_in_main(here, main, sw)` trả `False` vì `here` là worktree
  - c. Vòng lặp `continue` bỏ qua kiểm tra, file trong `main` bị ghi đè trái phép
- **Who:** Các tiến trình làm việc trong worktree vô tình hoặc cố ý can thiệp vào main trunk

## Fix
Trước khi tách lệnh, phân tích các phép gán biến tĩnh `VAR=/path` để nội suy `$VAR`. Nếu đích bắt đầu bằng `$VAR` trỏ vào thư mục `main` hoặc biến chưa rõ nguồn gốc, áp dụng cơ chế fail-closed chặn ngay lập tức.

## Acceptance Criteria
- [ ] Lệnh `MAIN=/repo/main; echo test > "$MAIN/file"` chạy trong linked worktree bị chặn (`exit 1/2`).
- [ ] Nhánh `main` được bảo vệ bất khả xâm phạm ở chế độ Trunk Mode.

## Risk
🟡 **Medium** · Siết chặt phân tích cú pháp biến môi trường trong câu lệnh shell.

## Blocked by
- None.

---

### TICKET-13: 🔒 [bug] git: sửa automerge commit trước kiểm tra an toàn và race condition trong instincts

## Problem
`_automerge_locked()` chạy `git commit --no-edit` trước khi gọi `_commit_pending()`, vô hiệu hóa kiểm tra lộ secret và symlink độc hại. `instincts.py cmd_add` copy template bên ngoài khối `flock` làm mất bài học.

## Context
- **Where:** `universal-agent-devkit/scripts/git/worktree.py`, `bin/instincts.py`
  - a. `_automerge_locked()` dòng 2167 chạy thẳng `git commit` chốt mọi file staged
  - b. File staged chứa secret chưa qua bộ lọc `_secret_like` bị commit vào git
  - c. Hai tiến trình cùng gọi `instincts.py add` cắt cụt file template ngoài lock
- **Who:** Hệ thống tự động merge worktree và quản lý bài học kinh nghiệm tự động

## Fix
Chạy quét `_secret_like`, symlink và dọn bookkeeping trên các file staged trước khi chạy `git commit --no-edit` trong `worktree.py`. Đưa logic copy template trong `instincts.py` vào bên trong khối `flock(LOCK_EX)`.

## Acceptance Criteria
- [ ] File staged chứa secret mẫu bị chặn không cho phép automerge.
- [ ] Chạy đồng thời nhiều lệnh `instincts.py add` không bị mất dữ liệu hoặc hỏng file bài học.

## Risk
🟡 **Medium** · Đảm bảo an toàn bí mật mã nguồn khi tự động merge nhánh.

## Blocked by
- None.

---

### TICKET-14: 🛡️ [bug] git: chặn ghi đè symlink cha trong backup_conflict và cập nhật adapters

## Problem
`restore_old_backups()` trong `backup_conflict.sh` di chuyển file xuyên qua symlink cha trỏ vào `$DEVKIT_ROOT`, có thể ghi đè file gốc của DevKit. `setup_codex.sh` và `setup_cursor.sh` thiếu bước cài đặt skills.

## Context
- **Where:** `universal-agent-devkit/scripts/git/backup_conflict.sh`, `adapters/setup_*.sh`
  - a. Khôi phục backup gặp thư mục cha là symlink trỏ vào `$DEVKIT_ROOT`
  - b. Lệnh `mv` ghi đè trực tiếp lên file gốc của DevKit
  - c. Codex và Cursor thiếu `.agents/skills` sau khi chạy script setup adapter
- **Who:** Người dùng cài đặt hoặc khôi phục DevKit trên các IDE khác nhau

## Fix
Gọi `_backup_assert_safe_dir "$(dirname "$dst")" "$root"` trước khi di chuyển file trong `backup_conflict.sh`. Bổ sung gọi `devkit_place_skills` trong `setup_codex.sh` và `setup_cursor.sh`.

## Acceptance Criteria
- [ ] Khôi phục file sao lưu không ghi đè vào thư mục đích thông qua symlink.
- [ ] Cài đặt adapter cho Codex và Cursor tạo đầy đủ symlink skills trong `.agents/skills`.

## Risk
🟢 **Low** · Sửa script cài đặt và khôi phục sao lưu.

## Blocked by
- None.

---

### TICKET-15: 🔧 [chore] checklist: khôi phục regression_status bị rollback và ngăn gate ở main ghi sổ

## Problem
`regression_status.json` trên nhánh `main` bị rollback mất 9 mục kiểm thử; đồng thời lệnh gate chạy trên main vẫn tiếp tục ghi đè trạng thái dù main ở Trunk Mode chỉ nhận merge.

## Context
- **Where:** `universal-agent-devkit/bin/regression_checklist.py`, `bin/post-fix-gate.py`
  - a. Journal phát hiện rollback mất 9 mục ngày 16/10 00:26
  - b. Snapshot tốt `snapshots/20261016-002018-*.json` chưa được khôi phục
  - c. `post-fix-gate.py` ghi bookkeeping trực tiếp vào working tree của main
- **Who:** Bảng theo dõi hồi quy ma trận kiểm thử của toàn bộ repository

## Fix
Chạy `agent-kit checklist restore` khôi phục lại snapshot hợp lệ. Cập nhật `post-fix-gate.py`: khi phát hiện đang chạy trên nhánh `main` ở Trunk Mode, tự động bật cờ `skip_bookkeeping` không ghi đè file theo dõi.

## Acceptance Criteria
- [ ] Khôi phục đầy đủ 9 mục kiểm thử bị mất trong `regression_status.json`.
- [ ] Chạy test gate trên `main` không làm biến đổi trạng thái working tree git (`git status` sạch).

## Risk
🟢 **Low** · Khôi phục dữ liệu nhật ký và ngăn ghi đè trạng thái.

## Blocked by
- None.

---

### TICKET-16: 🍎 [bug] locks: hỗ trợ holder_pid trên macOS Darwin và chống PID recycling trong session_lock

## Problem
`holder_pid()` chỉ đọc `/proc/{pid}/stat` nên luôn trả về `None` trên macOS. `is_pid_alive()` trả `True` khi gặp `PermissionError` (PID đã bị hệ điều hành cấp lại cho daemon của root), gây nhận nhầm phiên còn sống.

## Context
- **Where:** `universal-agent-devkit/bin/session_lock.py`, `session_authorship.py`
  - a. Hệ điều hành macOS không có hệ thống tệp `/proc`
  - b. Kiểm tra lock session trên macOS luôn coi PID là rỗng hoặc bị treo
- **Who:** Người dùng phát triển trên máy Mac (Darwin)

## Fix
Lưu kèm thời điểm khởi tạo tiến trình `pid_start` (`ps -o lstart=`) vào lock file. Sử dụng `ps -o ppid=,comm=` làm cơ chế xác định tiến trình fallback trên macOS.

## Acceptance Criteria
- [ ] `session_lock.py` xác định chính xác PID phiên đang hoạt động trên hệ điều hành macOS.
- [ ] Không bị khóa nhầm khi PID cũ được cấp lại cho tiến trình hệ thống khác.

## Risk
🟢 **Low** · Bổ sung nhánh tương thích hệ điều hành Darwin.

## Blocked by
- None.

---

## 🧪 EPIC-04: Regression Checklist & RED-Proof Debt (Triệt tiêu nợ kiểm thử)

### TICKET-17: 🐛 [bug] checklist: sửa đụng độ băm _crit_hash nuốt toán tử toán học và 4 lỗi trạng thái

## Problem
`_crit_hash()` loại bỏ toàn bộ toán tử so sánh (`<`, `>`, `<=`, `==`), khiến hai tiêu chuẩn đối lập như `"Độ trễ < 300ms"` và `"Độ trễ > 300ms"` có cùng mã băm, làm gate giữ nguyên trạng thái `PASS` dù tiêu chuẩn bị đảo ngược. Dòng `retired` kẹt ở `STALE` vĩnh viễn.

## Context
- **Where:** `universal-agent-devkit/bin/regression_checklist.py`, line 756, 1871, 2616
  - a. `norm_title()` dùng regex `\w+` xóa sạch các ký tự toán tử
  - b. Tiêu chí kiểm thử bị đổi ngược logic nhưng checklist không phát hiện
  - c. Module kiểm thử cũ đã xóa nhưng các dòng checklist vẫn báo STALE
- **Who:** Hệ thống đánh giá tiêu chí nghiệm thu tự động

## Fix
Trong `_crit_hash()`, chuẩn hóa khoảng trắng nhưng giữ nguyên toàn bộ ký tự toán tử so sánh. Sửa điều kiện gán `retired = True` khi module không còn tồn tại; phân biệt đúng trạng thái `FLAKY` khi test pass ở lần thử lại.

## Acceptance Criteria
- [ ] Hai tiêu chuẩn kiểm thử đối lập dấu toán học sinh ra 2 mã băm khác nhau.
- [ ] Xóa module kiểm thử sẽ chuyển đúng trạng thái các dòng tương ứng sang retired, không kẹt STALE.

## Risk
🟡 **Medium** · Có thể làm thay đổi hash một số tiêu chuẩn hiện có; cần kiểm tra tương thích ngược.

## Blocked by
- None.

---

### TICKET-18: 🧪 [test] red-proof: trả nợ dứt điểm 65–81 ca kiểm thử chờ chứng minh ĐỎ

## Problem
Hiện có 65–81 hàng mang trạng thái "⏳ chưa chứng minh ĐỎ" trong `.agents/CHECKLIST.md` (tỷ lệ an toàn kiểm thử chỉ đạt 38%, trong khi mục tiêu chuẩn là $\le 2\%$).

## Context
- **Where:** `.agents/CHECKLIST.md`, `.agents/local/red_proof.json`, `scripts/testing/red_proof.py`
  - a. HUD báo 81/136 hàng đang ở trạng thái chờ
  - b. Bộ red-patches trong `.agents/local/red-patches/` đã sẵn sàng nhưng chưa được chạy tự động
  - c. Hàng audit hiệu năng `BUG-20260929...` không có test tất định cần được xử lý
- **Who:** Toàn bộ hệ thống đảm bảo chất lượng Paired Executable Oracle của dự án

## Fix
Chạy `python3 scripts/testing/red_proof.py --pending` trên từng repository với `DEVKIT_IMPACTED_SINCE=0`. Với các hàng audit hiệu năng không có test tất định, thống nhất drop hoặc gắn oracle phù hợp.

## Acceptance Criteria
- [ ] Số lượng hàng chưa chứng minh ĐỎ trên `.agents/CHECKLIST.md` giảm xuống $\le 2\%$.
- [ ] File `.agents/local/red_proof.json` được cập nhật đầy đủ mã băm xác nhận RED $\rightarrow$ GREEN.

## Risk
🟡 **Medium** · Cần chạy test trên cả 5 repo; cần đảm bảo môi trường test sạch sẽ.

## Blocked by
- `TICKET-02` (cần fix deadlock nightly và shadowing biến patch trước).

---

### TICKET-19: 🛡️ [bug] testing: gia cố an toàn thực thi trong red_proof (Quote shell, bẫy SIGTERM)

## Problem
`red_proof.py narrowed` nối chuỗi lệnh test không qua `shlex.quote()` và chặn nhầm lệnh chứa `${VAR}`. Khi nhận `SIGTERM`/`SIGINT`, script không dọn thư mục `/tmp/red-proof-*`, để lại tiến trình mồ côi.

## Context
- **Where:** `universal-agent-devkit/scripts/testing/red_proof.py`, line 310, 514, 617
  - a. Dòng 514 chặn mọi lệnh test có dấu `{`
  - b. Khi bị hủy giữa chừng, tiến trình con Gradle/pytest vẫn tiếp tục chạy ngầm
  - c. Đường dẫn tương đối với `--patch` bị lỗi khi chạy trên detached worktree
- **Who:** Các lượt chạy kiểm chứng ĐỎ tự động hoặc chạy qua CI/cron

## Fix
Dùng `shlex.quote(t)` khi nối chuỗi test; bọc xử lý tín hiệu `SIGTERM` để kích hoạt dọn dẹp worktree tạm và kill process group. Gọi `.resolve()` trên đường dẫn patch trước khi tạo worktree mới.

## Acceptance Criteria
- [ ] Hủy tiến trình bằng `Ctrl+C` không để lại thư mục rác trong `/tmp/red-proof-*`.
- [ ] Lệnh test chứa cú pháp `${ENV_VAR}` được thực thi an toàn và chính xác.

## Risk
🟢 **Low** · Cải thiện tính bền bỉ và dọn dẹp tài nguyên hệ thống.

## Blocked by
- None.

---

### TICKET-20: 📊 [bug] health: khắc phục agent-health báo điểm khống 100/100 khi cấu hình rỗng

## Problem
`agent-health.py` báo điểm sức khỏe tối đa 100/100 ngay cả khi `"hooks": {}` rỗng không có hook nào, thiếu file pre-commit hook hoặc `trust["problem"]` có lỗi.

## Context
- **Where:** `universal-agent-devkit/bin/agent-health.py`, line 218–318
  - a. Dòng 221 chỉ kiểm tra kiểu `dict` mà không kiểm tra độ dài dictionary hooks
  - b. Dòng 289 cho phép `git_hooks["pre_commit"] == "absent"` vẫn pass điểm tối đa
  - c. Dòng 305 truyền `True` cố định vào hàm chấm điểm cảnh báo
- **Who:** Báo cáo kiểm tra sức khỏe môi trường Agent trước khi làm việc

## Fix
Kiểm tra số lượng hook tối thiểu trong cấu hình; trừ điểm thích đáng khi thiếu git hooks bắt buộc hoặc `trust["problem"]` chứa cảnh báo lỗi.

## Acceptance Criteria
- [ ] Repository thiếu hook pre-commit không thể đạt điểm sức khỏe 100/100.
- [ ] Cấu hình hooks rỗng bị đánh giá không đạt chuẩn sức khỏe.

## Risk
🟢 **Low** · Sửa công thức tính điểm thẩm định sức khỏe.

## Blocked by
- None.

---

## 🤖 EPIC-05: Antigravity PM MCP Server Hardening (`mcp-servers/antigravity-pm-mcp`)

### TICKET-21: 🚨 [bug] pm-mcp: chặn bypass commitPolicy forbid và truyền changedFiles vào gate

## Problem
Hàm `gate()` bỏ quên kiểm tra `commitPolicy === 'forbid'`, và `gateCtx()` chỉ truyền `snap.wt` (file chưa commit) vào `soiThayDoi` và `lastChangeAtOf`. Nếu Worker tự ý chạy `git commit`, `snap.wt` rỗng `[]`, vô hiệu hóa 100% việc kiểm tra diff và forbiddenPaths!

## Context
- **Where:** `mcp-servers/antigravity-pm-mcp/src/policy.js`, `src/worktree.js`, `src/tasks.js`
  - a. Worker được giao task với `commitPolicy: 'forbid'`
  - b. Worker sửa file trái phép trong `forbiddenPaths` rồi chạy `git commit`
  - c. `snap.wt` trở thành `[]`, `gate()` duyệt pass và cho phép nghiệm thu task sai trái
- **Who:** Leader PM khi ủy quyền tác vụ cho Worker trong sandbox

## Fix
Thêm kiểm tra `commitPolicy === 'forbid' && snap.head !== task.baseHead` vào `gate()`. Truyền `changedFiles` (hợp nhất giữa `snap.wt` và `snap.sinceBase`) vào `soiThayDoi` và `lastChangeAtOf`. Đối chiếu thay đổi với snapshot `task.baselineDirty` lúc giao việc.

## Acceptance Criteria
- [ ] Worker chạy `git commit` khi task có `commitPolicy: forbid` sẽ bị gate từ chối nghiệm thu.
- [ ] Worker sửa file trong `forbiddenPaths` dù có commit hay không đều bị phát hiện và chặn nghiệm thu.

## Risk
🔴 **High** · Đảm bảo tính toàn vẹn của cơ chế Leader PM ↔ Worker Sandbox Protocol.

## Blocked by
- None.

---

### TICKET-22: 🔒 [bug] pm-mcp: chống deadlock conversation và lỗi xúi kill chính tiến trình MCP Server

## Problem
Khi `pm_reserve_slot` hết hạn TTL 90s, nếu lệnh `agySendMessage` tiếp theo gặp lỗi HTTP, khối `catch` ghi đè lock thành `{ pid: process.pid, reservation: false }`. Vì PID là chính MCP Server, conversation bị khóa vĩnh viễn và thông báo lỗi xúi kill chính MCP Server!

## Context
- **Where:** `mcp-servers/antigravity-pm-mcp/src/agentapi.js`, line 273, 590
  - a. `pm_reserve_slot` hết hạn và tiến trình thu hồi slot
  - b. Gửi tin nhắn HTTP thất bại hoặc sai conversationId
  - c. Khối `catch` ghi đè lock với PID của chính MCP Server đang sống
  - d. Mọi lệnh sau đều báo busy và gợi ý chạy `kill -- -<PM_PID>`
- **Who:** Toàn bộ giao tiếp giữa Claude Leader PM và Antigravity qua MCP

## Fix
Trong `catch` của `agySendMessage`, nếu slot có cờ `reservation` hoặc `pid === process.pid`, bắt buộc gọi `fs.unlinkSync(lp)` để giải phóng lock file hoàn toàn thay vì ghi đè.

## Acceptance Criteria
- [ ] Lỗi gửi tin nhắn HTTP tới Antigravity không làm khóa chết conversation ID.
- [ ] Không còn thông báo lỗi hướng dẫn kill chính tiến trình MCP Server.

## Risk
🟡 **Medium** · Tránh treo cứng giao tiếp giữa các agent.

## Blocked by
- None.

---

### TICKET-23: 🐛 [bug] pm-mcp: sửa renderReport thiếu gateCtx và regex cắt đường dẫn trong lint-diff

## Problem
`renderReport(task, g)` chỉ khai báo 2 tham số và tự gọi `gate(task)` không có `ctx`, làm mất các trường kiểm tra và khiến báo cáo nghiệm thu luôn hiển thị `CHUA DAT`. Regex cắt đường dẫn trong `lint-diff.js` cắt sai các thư mục có chữ `b`.

## Context
- **Where:** `mcp-servers/antigravity-pm-mcp/src/report.js`, `src/lint-diff.js`
  - a. Báo cáo `pm_accept` và `pm_report` luôn in `CHUA DAT` dù task đã hoàn thành tốt
  - b. File trong `src/lib/foo.js` bị regex `/b\/(.+)$/` cắt thành `foo.js`, làm lọt diff
- **Who:** Báo cáo nghiệm thu task của Leader PM

## Fix
Khai báo tham số `ctx` trong `renderReport(task, g, ctx)` và tái sử dụng kết quả gate đã đánh giá. Đổi regex trong `lint-diff.js` thành `/^\+\+\+\s+b\/(.+)$/m` neo chặt đầu dòng.

## Acceptance Criteria
- [ ] Báo cáo nghiệm thu hiển thị đúng trạng thái `DAT` khi mọi tiêu chí pass.
- [ ] Các file nằm trong thư mục `lib/`, `web/`, `db/` được nhận diện chính xác đường dẫn diff.

## Risk
🟢 **Low** · Sửa định dạng báo cáo và biểu thức chính quy tách diff.

## Blocked by
- None.

---

### TICKET-24: 🛡️ [bug] pm-mcp: vá lỗ hổng Path Traversal và kiểm soát symlink ngoài projectRoot

## Problem
Các module `proof.js`, `oracle.js`, `worktree.js`, `cite-check.js` đọc file không kiểm tra đường dẫn thực sau khi giải mã symlink, có nguy cơ bị tấn công Path Traversal đọc file nhạy cảm ngoài workspace.

## Context
- **Where:** `mcp-servers/antigravity-pm-mcp/src/proof.js`, `src/oracle.js`, `src/worktree.js`
  - a. Worker tạo symlink trong workspace trỏ tới file ngoài thư mục dự án
  - b. Leader PM đọc file proof/oracle qua symlink mà không kiểm tra ranh giới
- **Who:** Ranh giới an toàn giữa sandbox worker và hệ điều hành chủ

## Fix
Dùng `fs.realpathSync` trên mọi đường dẫn file trước khi đọc và xác thực đường dẫn thực phải nằm bên trong `fs.realpathSync(projectRoot) + path.sep`.

## Acceptance Criteria
- [ ] Symlink trỏ ra ngoài thư mục dự án bị từ chối truy cập và báo lỗi bảo mật.

## Risk
🟢 **Low** · Tăng cường bảo vệ ranh giới đọc file của MCP Server.

## Blocked by
- None.

---

### TICKET-25: 🔧 [chore] pm-mcp: hoàn thiện tồn đọng OpenCodeReview I.4 và bảo mật truyền prompt

## Problem
Prompt gửi qua CLI `agy` truyền qua argv (`--print String(prompt)`), lộ nội dung qua bảng tiến trình `ps aux` và bị giới hạn độ dài 128 KB. Provider `qa-visual` (playwright) in JSON summary nhưng parser lại regex tìm đuôi `.png`.

## Context
- **Where:** `mcp-servers/antigravity-pm-mcp/src/agentapi.js`, `src/proof.js`, `src/tasks.js`
  - a. Prompt dài bị tràn bộ đệm đối số của hệ điều hành
  - b. Thông tin nhạy cảm trong prompt hiển thị công khai qua lệnh `ps`
  - c. `qa-visual` chạy thành công nhưng gate luôn báo `produced no PNG`
- **Who:** Quản lý giao tiếp CLI với Antigravity và chụp ảnh nghiệm thu Playwright

## Fix
Chuyển sang truyền prompt qua stdin hoặc file tạm quyền `0600`. Cập nhật regex parser cho `qa-visual` và đồng bộ logic thu hồi lock trong `tasks.js`.

## Acceptance Criteria
- [ ] Prompt dài $>128\text{ KB}$ được truyền an toàn tới `agy` mà không lộ trên lệnh `ps`.
- [ ] Provider `qa-visual` được nhận diện đúng kết quả chụp ảnh nghiệm thu.

## Risk
🟢 **Low** · Nâng cấp cơ chế truyền tham số an toàn.

## Blocked by
- None.

---

## 📐 EPIC-06: Rules Consistency, Profiles & Quality Governance

### TICKET-26: 📝 [docs] rules: đồng bộ mâu thuẫn commit/push giữa AGENTS.md và rules/essentials.md

## Problem
`AGENTS.md` (Gate 4) và `handover_rule.vi.md` ghi *"Cấm tự ý commit/push, dừng lại chờ lệnh"*, trong khi `rules/essentials.md` ghi *"Git — commit and push yourself: a finished task is committed and pushed without asking"*.

## Context
- **Where:** `universal-agent-devkit/AGENTS.md`, `rules/essentials.md`, `templates/handover_rule.vi.md`
  - a. Agent nhận 2 mệnh lệnh trái ngược nhau giữa tài liệu tổng quan và tài liệu essentials
  - b. Danh sách "Hỏi người dùng" trong essentials chưa được tinh giản theo quyết định mới
- **Who:** Mọi agent làm việc trong toàn bộ 5 repositories

## Fix
Khẳng định rõ thứ bậc ưu tiên: Quy tắc dự án đặc thù (`.agents/local/rules/` hoặc user rules như FinOS Solo Dev) luôn thắng; nếu dự án cấm thì dừng chờ lệnh, nếu dự án ủy quyền thì tự commit/push khi gate pass. Thu gọn danh sách "Hỏi người dùng" trong essentials và chạy `context_sync.py` sang 5 repo.

## Acceptance Criteria
- [ ] Không còn câu chữ mâu thuẫn về hành vi tự động commit trong các file tài liệu và rules.
- [ ] Đồng bộ nhất quán nội dung rules sang toàn bộ 5 repositories.

## Risk
🟢 **Low** · Chuẩn hóa tài liệu hướng dẫn và quy tắc ứng xử của Agent.

## Blocked by
- None.

---

### TICKET-27: ⚡ [perf] context: cắt giảm byte nạp mỗi phiên đạt chuẩn rubric dưới 40 KB cho 3 repo

## Problem
Dung lượng 3 file nạp đầu phiên (`AGENTS.md` + `profile-rules.md` + `rules-index.md`) tại GeelyEx2 (56.260 B), OfficeReader (48.371 B), Goods (48.335 B) đang vượt trần rubric 40.960 B.

## Context
- **Where:** `AGENTS.md` và `.agents/context/` tại các repo `GeelyEx2`, `OfficeReader`, `Goods`
  - a. Mỗi lượt prompt nạp lượng token ngữ cảnh tĩnh quá lớn gây lãng phí chi phí và quota
  - b. Quyết định ngày 12/10 yêu cầu chuyển luật riêng của repo sang `.agents/local/rules/` chưa được thực hiện
- **Who:** Hiệu năng nạp ngữ cảnh của các repo ứng dụng lớn

## Fix
Chuyển các quy tắc riêng của từng repo từ `AGENTS.md` sang thư mục `.agents/local/rules/` theo dạng tham chiếu động qua `rules-index.md` mà không làm mất nội dung quy tắc.

## Acceptance Criteria
- [ ] Dung lượng 3 file nạp đầu phiên của cả 5 repo đều đạt $\le 40.960\text{ B}$.
- [ ] Không làm mất bất kỳ quy tắc nghiệp vụ đặc thù nào của từng dự án.

## Risk
🟢 **Low** · Tái cấu trúc vị trí lưu trữ file quy tắc, không đổi logic code.

## Blocked by
- None.

---

### TICKET-28: 🎮 [bug] profiles: sửa lỗi script Unity Game (marathon, batch, validate-assets)

## Problem
`unity-bot-marathon.sh` nổ lỗi unbound variable khi chạy `--help` và có nguy cơ arithmetic injection. `unity-batch.sh` lặp vô tận khi thiếu cờ argument. `validate-assets.sh` nuốt lệch luồng NUL khi có file rename ra ngoài `Assets/`.

## Context
- **Where:** `universal-agent-devkit/profiles/game/scripts/`, `profiles/game/hooks/`
  - a. `unity-bot-marathon.sh` nổ lỗi khi gọi xem hướng dẫn
  - b. `unity-batch.sh` treo cứng 100% CPU khi truyền thiếu tham số sau cờ `--filter`
  - c. `validate-assets.sh` dòng 99 bỏ qua đọc trường NUL thứ hai của bản ghi rename
- **Who:** Các dự án game Unity (như Neighbours-From-Hell)

## Fix
Validate an toàn đối số CLI số nguyên trong `unity-bot-marathon.sh`. Sửa lệnh `shift` trong vòng lặp parse options của `unity-batch.sh`. Đảm bảo tiêu thụ trọn vẹn 2 trường NUL của bản ghi rename trong `validate-assets.sh`.

## Acceptance Criteria
- [ ] `unity-bot-marathon.sh --help` in hướng dẫn và thoát mã 0 an toàn.
- [ ] `unity-batch.sh` không bị lặp vô tận khi truyền thiếu giá trị cờ.
- [ ] Đổi tên file từ `Assets/` ra ngoài thư mục không làm hỏng hook `validate-assets.sh`.

## Risk
🟢 **Low** · Sửa lỗi kịch bản shell cho profile game.

## Blocked by
- None.

---

### TICKET-29: 🧹 [chore] governance: tích hợp devkit_clean vào nightly, sửa fold_agent_file và intent

## Problem
Thư mục `.claude/audit-gate` phình to 15–30 MB do không tự động dọn dẹp các file `.jsonl` cũ. `fold_agent_file.py` nối đúp nội dung `AGENTS.md`. Hằng số Intent trong `enrich_context.py` bị sai tên làm dead code logic gợi ý Antigravity.

## Context
- **Where:** `universal-agent-devkit/scripts/governance/`, `scripts/context/enrich_context.py`
  - a. `devkit_clean.py` chưa được gắn vào cron nightly
  - b. `enrich_context.py` dòng 961 kiểm tra các hằng số không tồn tại trong codebase
- **Who:** Hệ thống dọn dẹp rác tự động và làm giàu ngữ cảnh thông minh

## Fix
Gắn `devkit_clean.py` vào `nightly.py` dọn dẹp file log/jsonl $>7$ ngày. Bọc nội dung fold bằng cặp thẻ HTML comment để thay thế idempotent. Cập nhật đúng hằng số Intent trong `enrich_context.py`.

## Acceptance Criteria
- [ ] Dung lượng thư mục `.claude/audit-gate` luôn được duy trì $<5\text{ MB}$.
- [ ] Chạy `fold_agent_file.py` nhiều lần không làm tăng kích thước file `AGENTS.md`.
- [ ] Ý định phức tạp kích hoạt chính xác gợi ý phân công Antigravity.

## Risk
🟢 **Low** · Tự động hóa dọn dẹp và sửa hằng số phân loại intent.

## Blocked by
- None.

---

### TICKET-30: 🧪 [test] suite: bọc hàm cho 13 file test unparseable và cập nhật impact_map

## Problem
11 file test `.sh` đặt toàn bộ code trong python heredoc cấp cao nhất khiến `codebase-memory-mcp` báo `parse_unusable` (0 symbol), 2 file đặt `&` sau heredoc báo `parse_partial`. Ngoài ra `tests/impact_map.txt` thiếu quy tắc ánh xạ cho nhiều script production.

## Context
- **Where:** `universal-agent-devkit/tests/`, `tests/impact_map.txt`
  - a. Knowledge Graph bị mù thông tin về 13 file test cốt lõi
  - b. Sửa `fold_agent_file.py` hoặc `devkit_i18n.py` không kích hoạt bài test tương ứng
- **Who:** Bộ công cụ phân tích AST Knowledge Graph và test runner chạy theo thay đổi

## Fix
Bọc thân script trong hàm `run_test() { ... }; run_test "$@"` cho 11 file test. Tách subshell `( python3 - ... <<'PY' ... PY ) &` cho 2 file parse partial. Bổ sung ánh xạ kiểm thử vào `impact_map.txt`.

## Acceptance Criteria
- [ ] `codebase-memory-mcp` index thành công 100% các file test, không còn lỗi `parse_unusable` hoặc `parse_partial`.
- [ ] Thay đổi các script production kích hoạt chính xác bài test chức năng khi chạy `run_impacted.sh`.

## Risk
🟢 **Low** · Chuẩn hóa cấu trúc file kiểm thử, không đổi logic bên trong.

## Blocked by
- None.
