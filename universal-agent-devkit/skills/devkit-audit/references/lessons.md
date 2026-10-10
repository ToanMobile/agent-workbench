# Bài học /devkit-audit. Nguồn: I-n=INSTINCT-n, Đn=CHANGELOG Đợt n, H=handoff (ngày), còn lại tên note memory.. [đk]=đã kiểm trên code/trạng thái 10/10; không nhãn=quy tắc rút từ sự cố đã ghi trong note hoặc instinct (chưa kiểm lại hôm 10/10): mỗi lần chạy, kiểm lại các dòng nêu tên file hoặc hàm trước khi dựa vào
## A. Sửa guard, hook, gate
A1 Sửa lỗ parser: test hai chiều (chặn đúng, cho qua đúng); reviewer tấn công chính bản sửa | I-031, Đ13 (4 vòng đều hồi quy)
A2 Một mục ra P1 mới hai vòng liền: dừng, thu hẹp, ghi giới hạn chấp nhận | H10-05 (land)
A3 Bản sửa hook/gate/khoá/worktree nào cũng cần reviewer sạch, rồi review lại phần vừa sửa | H10-04, H10-08 (23 lỗi/2 vòng)
A4 Hook sống qua symlink: stage `cp -Rc`, file tạm, `bash -n` + chạy mẫu, `mv`; từ chối nếu file sống khác gốc stage | I-012, I-016
A5 Python trong `hooks/*.sh` nằm trong `-c '…'`: không `'` (cả docstring), dùng `\x27`; luôn `python3 -I` | I-012, I-031 [đk]
A6 Guard hỏng phải chặn (exit 2); exit 127/1 và `except: pass` là cho qua | devkit-symlink-merge-reinit, Đ14 [đk]
A7 Sau merge/ff mất symlink: `agent-kit init . -y -p <profile>` + `health -t .` (health một mình vẫn PASS) | devkit-symlink-merge-reinit
A8 Nới nhánh bỏ qua: viết trước mọi câu bàn giao thật thành ca phải-chặn; tin `ls-remote`, không tin state agent ghi được | I-015/027/028
A9 Cache/mốc: một hàm fingerprint; mọi trạng thái kết thúc hợp lệ dời mốc và nhớ theo nội dung | I-017/018, H10-07
A10 Tự dò mới không thắng trường người dùng khai; đổi chỗ file thì grep cả phép ghép đường dẫn, thêm `tests/impact_map.txt` | I-021/025/029
A11 Test bằng `/bin/bash` 3.2 và python 3.14.7 lẫn 3.9.6; APFS so inode | I-030, Đ13 [đk]
A12 Payload nguy hiểm ghi bằng Write vào file, không đặt trong lệnh Bash; dùng thư mục mới thay `rm -rf $VAR` | I-031, H10-05
## B. Chứng cứ và phép đo
B1 Kết quả toàn-0/toàn-sạch đáng ngờ: zsh không tách `for x in $v`, `echo $(basename d) rc=$?` in rc sai, glob lỗi huỷ lệnh | zsh-no-word-split
B2 Guard mới có đột biến bị giết (neo raw string, kiểm "applied"); cấm `grep -qv`, `@Test` rỗng | H10-07, H09-30
B3 RED-proof VACUOUS: `tests/run_impacted.sh --list`, `DEVKIT_IMPACTED_SINCE=0`, `.sh` cần `--patch` | I-029, Đ13 [đk]
B4 Báo cáo agent (Antigravity, `result.json`) là lời khai: tái hiện bằng probe/đột biến | antigravity-implementer-pitfalls
B5 Đồng hồ tường gồm máy ngủ: trừ Sleep của `pmset -g log` | I-019
B6 `runs.jsonl` chỉ có từ ngày bật ghi, bị cắt khi vượt `RUN_LOG_MAX_BYTES` (1,25 MB), thiếu `fp` và lý do exit 2, lượt bị timeout không ghi: tổng là cận dưới, "lặp" là xấp xỉ | post-fix-gate.py, H10-10 [đk]
B7 Dùng `total_wall_s` (suite song song chồng nhau); 5 s là lượng tử thăm dò; Gradle FROM-CACHE: `--rerun`; đo máy yên | H10-07, H10-09 [đk]
B8 So cùng trạng thái: `--since <sha>` khi ma trận đổi, `--no-cache` sau exit 2; quyết định theo ngưỡng `gate_runs_report.py`; `--full` CLI không xét test sửa đã commit | H10-07, gate-run-log-3day-review [đk]
## C. Nhiều phiên, repo, agent
C1 Repo do phiên khác giữ khoá (GeelyEx2 hôm nay): chỉ đọc; lỗi do kit sửa ở kit rồi `context_sync.py` | devkit-fix-at-kit-not-per-repo [đk]
C2 `session_lock.py --status` trong lệnh con báo khoá chính mình (3); pid chết = trống; state hook ghi tay bị lượt hook đang chạy ghi đè | H10-07, H10-10 [đk]
C3 Bản `cp -Rc` repo sống: stash `-u`, `active-profile` tuyệt đối, xoá ngay khi đã push | H10-08, scratch-cleanup-after-use
C4 Không `cmd | tail && git push`, không `<sha>:main`, không export `GIT_INDEX_FILE` (hỏng: `git read-tree HEAD`); Geely không upstream: `git push origin main` | pipe-masks-exit-before-push, never-export-git-index-file
C5 Antigravity viết lại hàm, để `patch_*.py`/`.git` lồng/file rác, báo test chưa tạo: mặc định `principal-code-reviewer`, Antigravity chỉ việc lớn | antigravity-implementer-pitfalls
C6 `agent-kit worktree status` trước khi gộp/xoá; không đụng worktree phiên sống hoặc rảnh | I-020, Đ8-9
C7 `.adb-denylist` theo repo (một repo cấm IP đầu xe, repo khác cấm serial điện thoại cá nhân, kể cả máy mặc định của repo thứ ba): không áp chéo giữa repo | officereader-real-phone-default [đk]
C8 Thêm skill: số đếm README/plugin.json/AGENTS (R7), `+x` file shebang, host nhận link sau `agent-kit init` | test_repo_consistency, H10-09 [đk]
## D. Ưa thích người dùng (không hỏi lại)
D1 Tự làm A-Z; không `!`, không menu; "audit" = tìm VÀ sửa; commit + push nhánh hiện tại | user-lazy-senior, user-no-bang-handoffs [đk]
D2 Bị từ chối quyền: không lách, báo CHƯA XONG nêu bước đó | user-no-bang-handoffs
D3 Xoá dữ liệu thật (backup, `.git` rỗng, `origin/trunk`, force-push): luật an toàn thắng, hỏi một lần bằng AskUserQuestion; scratch của mình tự xoá ngay | AGENTS.md, scratch-cleanup-after-use
D4 Chỉ Claude + Gemini (Gemini CLI không thăm dò được); không Codex/Cursor, không LaunchAgent | devkit-agents-claude-gemini-only, user-lazy-senior
D5 Đã quyết, không nêu lại: xoay token, ngoại lệ claude-auto, `origin/trunk` Office giữ tới khi được bảo, W1-g chưa đáng | token-rotation-declined, worktree-guard-claude-auto-exemption
D6 Proof dùng serial khai trong `.antigravity-pm.json` của repo, AVD chỉ dự phòng; trả lời tiếng Việt | officereader-real-phone-default
## E. Kiểm hằng ngày (chỉ đọc; R=từng repo)
E1 `KIT=$(cd .agents/devkit && pwd -P); find /Volumes -maxdepth 6 -path '*/.agents/devkit' -type l -lname "*$(basename "$KIT")" | sed 's#/.agents/devkit##'` (ngày 10/10 ra 7 repo, kể cả repo ngoài thư mục cha của kit) [đk]
E2 `(cd $R && python3 .agents/devkit/bin/session_lock.py --status)`; file khoá cũ: `ps -p <pid>` [đk]
E3 `git -C $R worktree list; pgrep -fl 'red_proof|run_impacted|post-fix-gate'; git -C $R ls-remote --heads origin` (nhánh lạ: báo, không xoá) [đk]
E4 `df -h <ổ chứa repo>; du -sh "${TMPDIR:-/tmp}"/claude-$(id -u)` (<10 GiB trống thì dọn của mình) [đk]
E5 `git -C $R status --porcelain; git -C $R status --ignored --porcelain | grep '^!!'; find $R -maxdepth 3 -name .git -not -path "$R/.git"` [đk]
E6 `du -sh $R/.claude/audit-gate $R/.git` (audit-gate không xoay vòng: Goods 28 MB) [đk]
E7 `ls *.md | while read f; do grep -q "($f)" MEMORY.md || echo UNINDEXED $f; done`; `grep -oh '/Volumes/[A-Za-z0-9_./-]*' *.md | sort -u | while read p; do [ -e "$p" ] || echo GONE $p; done` (đường dẫn trong note đã mất) [đk]
E8 `wc -l < .agents/instincts.md` so với `grep -o '[0-9]* dòng' .agents/instincts-index.md`; sửa: `agent-kit index-memory` [đk]
E9 `bash universal-agent-devkit/tests/verification/test_repo_consistency.sh` (R7 số đếm) [chưa chạy]
E10 id suite trùng (python đọc `.agents/regression_matrix.active.json`); `git -C $R ls-files -s | awk '$1=="120000"{print $4}' | while read f; do [ -e "$R/$f" ] || echo BROKEN $f; done` [đk]
E11 `verified_head` (`.claude/audit-gate/regression_gate.state.json`) phải là commit tổ tiên HEAD: `git cat-file -t`, `merge-base --is-ancestor` [đk]
E12 `git log --since=14.days --format= --name-only -- universal-agent-devkit/bin universal-agent-devkit/hooks | sort | uniq -c | sort -rn | head` (điểm nóng cho review vòng 2); `git rev-list --left-right --count '@{u}...HEAD'`; việc ghi "xong": `merge-base --is-ancestor <sha> origin/main` [đk]
## F. Từ lần chạy đầu (10/10)
F1 Số đo mới của chính skill cũng sai: đếm Stop theo dòng log phồng gấp 1,8 lần, đếm cả lần hook thả; chỉ reviewer đọc định nghĩa và đối chiếu log thật mới bắt được. Mọi metric mới: reviewer đọc định nghĩa, và có test đột biến (đổi định nghĩa thì test phải đỏ) | H10-10 [đk]
F2 Hook Stop chạy song song, thời gian tường là hook chậm nhất: đừng tối ưu thứ tự hook; chi phí nằm ở `regression_gate`, `testsourceset_gate` và ở số lượt model thừa sau mỗi lần chặn | nghiên cứu hook Stop 10/10 [đk]
F3 Cửa sổ đo dài lẫn giai đoạn trước các bản vá (Office: 100 trên 110 lượt lặp là trước Dot 7a): chấm trên 1 ngày, nêu cửa sổ trong báo cáo | H10-10 [đk]
F4 `/giao` plan_review: sửa file mà phản biện đã dẫn chứng thì trích dẫn thành NOT-FOUND và `pm_verdict kind=plan` bị chặn; chuyển `plan-review.json` sang `logs/` bị coi là chưa nghe phản biện; đường đúng là `pm_plan` v2 rồi `focus=delta` | T0025 [đk]
F5 Hook git chặn cả lệnh Bash dài có `$(` hoặc dấu backtick không đóng trong chuỗi heredoc: viết đoạn mã dài bằng Write hoặc Edit rồi chạy file | H10-10 [đk]
F6 Bản sửa đầu cho một lỗi đo lường hay parser thường thiếu: chạy reviewer hai lần (một lần cho tài liệu, một lần `principal-code-reviewer` cho code) và tái hiện từng phát hiện trước khi sửa | H10-10 [đk]
