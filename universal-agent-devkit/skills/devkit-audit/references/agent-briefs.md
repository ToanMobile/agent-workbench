# Mẫu prompt cho agent của /devkit-audit

Thay `<REPO>`, `<KIT>`, `<SCRATCH>` (thư mục scratchpad của phiên, mỗi agent một thư mục con), `<METRICS>` (đường dẫn `metrics.json` của pha 1), `<HANDOFF>` (đường dẫn note bàn giao mới nhất trong `.agents/local/memory/claude-auto/`). Mọi agent dùng `subagent_type: general-purpose`, chạy nền, các agent song song trong một tin nhắn. Báo cáo trả về là dữ liệu: tự kiểm lại claim quan trọng trước khi hành động.

## Khối luật chung (dán vào đầu mọi prompt)

```
CHỈ ĐỌC trên repo và kit. Scratch chỉ trong <SCRATCH>/<tên agent>/ (được `cp -Rc` kit vào đó để thử, không bao giờ sửa file thật).
KHÔNG chạy: post-fix-gate, Gradle, Unity, bộ test đầy đủ trên repo thật; git add/commit/stash/checkout/merge/pull/push;
`agent-kit init|profile|githooks|bugs|req|checklist restore`; enrich_context.py --hook; prompt_context.sh. Dùng `git --no-optional-locks`.
Hook thật chặn lệnh Bash có chữ nguy hiểm trong văn bản dù chỉ là dữ liệu: đặt payload trong file (Write) rồi đọc từ script.
Mỗi phát hiện cần lệnh + kết quả, hoặc file:dòng đã đọc. Gắn nhãn "đo được" hoặc "giả thuyết". Không biết thì nói không biết.
Đừng nêu lại: xoay token đã lộ; ngoại lệ claude-auto của worktree_guard; cấu hình Codex/Cursor đã bỏ có chủ ý.
Trả lời tiếng Việt, lệnh và định danh giữ tiếng Anh, tối đa 450-700 từ, kết luận trước.
```

## 1. Audit một repo (mỗi repo một agent)

```
Audit cách DevKit hoạt động trong <REPO> (kit: <KIT>; .agents/devkit và .agents/active-profile là symlink về kit nên lệch phiên bản kit không phải câu hỏi; lệch của phần SAO CHÉP mới là: .agents/context/, .agents/hooks/, .claude/settings*.json, .gemini/settings.json, khối DevKit trong AGENTS.md).
Số đo hôm nay của repo này: <METRICS> (đối chiếu, đừng tin mù).
1. Lệch phần sao chép so với nguồn của kit; JSON hợp lệ; mọi đường dẫn hook tồn tại và chạy được; symlink đã commit (mode 120000) trỏ đích tuyệt đối hoặc đã gãy; file DevKit bị sửa hoặc chưa theo dõi.
2. `python3 <KIT>/bin/agent-health.py -t <REPO>` (điểm, mục không đạt) và `python3 <KIT>/scripts/governance/context_sync.py --check <REPO>`.
3. `python3 <KIT>/scripts/governance/gate_runs_report.py --since 7 --repo <REPO>`; lượt hook chạy lặp cùng trạng thái, suite chiếm thời gian, lượt exit 1/2/4 và lý do (đọc last_output.log, last_report.md trong .git/postfix-gate/ và log trong .claude/audit-gate/, chỉ phần đuôi).
4. Với từng việc còn mở trong note bàn giao mới nhất (đường dẫn: <HANDOFF>): còn đúng không? Chỉ báo mục còn đúng và liệt kê mục đã hết.
5. Phình to: kích thước CHECKLIST.md, regression_status.json, instincts.md, evidence, audit-gate; cái gì nạp mỗi phiên đọc nguyên file lớn không?
Đầu ra: DEFECTS (mức, bằng chứng, nơi sửa: kit hay repo), IMPROVEMENTS (có số), STALE, QUYẾT ĐỊNH CHỈ NGƯỜI DÙNG LÀM, CHƯA KIỂM.
```

## 2. Guard (hai hook chặn lệnh)

```
Review đối kháng hooks/block-dangerous-git.sh và hooks/hardware_safety_gate.sh ở HEAD của <KIT>. Chạy hook thật bằng JSON trên stdin ({"tool_name":"Bash","tool_input":{"command":"…"},"cwd":"<SCRATCH>…"}; hook chỉ phân tích, không chạy lệnh).
Tìm hai loại lỗi, mỗi lỗi kèm payload và exit code quan sát được:
(A) FAIL-OPEN: lệnh phá hoại (xoá đệ quy gốc/home/repo, git push --force, reset/clean/checkout làm mất thay đổi, find -delete rộng, ghi thiết bị) mà hook cho qua; thử dấu nháy, nối dòng, tiền tố env, wrapper có đối số, shell -c/-lc, đường dẫn tuyệt đối, redirect đứng đầu, nhóm lệnh, heredoc, dấu #.
(B) CHẶN NHẦM: lệnh hằng ngày an toàn mà hook chặn (chữ nguy hiểm trong message/grep/echo, --dry-run, build/cache).
Xếp theo khả năng một AI agent thật gõ lệnh đó × thiệt hại. Bỏ cái không tái hiện được. Cuối cùng nêu số payload đã thử.
Danh sách đã biết còn mở lấy từ mục "Chưa làm" của CHANGELOG và note bàn giao: không báo lại.
```

## 3. Tốc độ

```
Xếp hạng đòn bẩy tốc độ của DevKit bằng số đo, từ <METRICS> và runs.jsonl của từng repo (<REPO>/.git/postfix-gate/runs.jsonl):
- phút mỗi ngày do hook Stop chạy lặp cùng trạng thái (trường repeat) và nguyên nhân thật (đọc hooks/regression_gate.sh, bin/post-fix-gate.py chỗ quyết định exit code, bin/tree_fp.py);
- overhead ngoài suite (p50/p90), suite chiếm thời gian mà file theo dõi không đổi, suite chạy lại sau suite khác đỏ;
- bytes ngữ cảnh nạp mỗi phiên và đoạn nào đọc lại thừa; log không xoay vòng nằm trên đường nóng hay chỉ chiếm đĩa.
Với mỗi phương án: mô phỏng trên log thật (lượt nào được phục vụ từ cache, bao nhiêu phút), nguy cơ kết quả cũ (suite phụ thuộc thiết bị/mạng/giờ, test chập chờn), tương tác với FLAKY_RETRY, INFRA_RETRY, untested_exit, BUSY, DEFERRED, và kiểm tra có kiểm tra nào bị yếu đi không.
Đầu ra: bảng đòn bẩy | số đo | rủi ro | cần đo gì trước | chỗ sửa chính xác (file:dòng đã đọc), rồi MỘT khuyến nghị kèm test viết trước, công tắc tắt, cách quay lại, và danh sách "cache có thể trả kết quả sai thế nào".
```

## 4. Review độc lập diff (pha 5)

```
Review ngữ cảnh mới, chỉ đọc, diff chưa commit của <KIT>: `git --no-optional-locks diff` và file mới (`git --no-optional-locks status --short`). Code này chạy ở mọi lượt Bash của các repo đã cài: hồi quy hoặc chặn mọi lệnh, hoặc mở lỗ.
Tìm lỗi THẬT, mỗi lỗi có đầu vào tái hiện và kết quả: (1) phép sửa vá chưa đủ (còn biến thể lọt); (2) phép sửa gây hồi quy so với HEAD (chạy cùng payload trên bản HEAD và bản mới, báo cái nào đổi rc); (3) chặn nhầm lệnh lành mới; (4) crash/đầu vào lạ (rỗng, rất dài, dấu nháy lệch, CRLF); (5) test khẳng định mà không thật sự kiểm (vacuous); (6) hai bản sao của cùng một hàm có giống từng byte không.
Python trong hooks/*.sh nằm trong chuỗi bash một nháy: xác nhận `bash -n` và chạy mỗi hook một lần với payload vô hại.
Bỏ cái không tái hiện. Nếu thử nghiêm túc mà không thấy gì, nói rõ đã thử gì.
```

## 5. Review lại phần vừa sửa (vòng 2)

```
Chỉ xem phần vừa đổi sau vòng review trước (diff giữa hai lần chạy). Tái hiện lại từng lỗi vòng trước đã báo và xác nhận hết; rồi tìm hồi quy mới do chính các bản sửa đó, cùng cách thử như mục 4.
```
