# DevKit Audit: quy trình chi tiết

Đọc khi chạy `/devkit-audit`. Mọi lệnh dưới đây đã chạy thật ngày 2026-10-10; `$KIT` là đường dẫn THẬT của thư mục kit (`cd .agents/devkit && pwd -P`: `.agents/devkit` là symlink, và `cp -Rc` trên một symlink tạo ra symlink chứ không tạo bản sao), `$SCRATCH` là thư mục scratchpad của phiên. Biến shell không giữ giữa các lệnh Bash: gán lại ở đầu mỗi lệnh dùng chúng.

## Pha 0. Chuẩn bị

1. Đọc note bàn giao mới nhất trong `.agents/local/memory/claude-auto/` (tên bắt đầu `handoff-`), mục `Unreleased` của `CHANGELOG.md` và dòng cuối của `devkit-audit-trend.jsonl` nếu có. Việc còn mở và quyết định của người dùng nằm ở đó.
2. Phạm vi repo là WHITE LIST của người dùng (12/10: "4 repo này là repo chính tôi dùng"), không phải mọi repo có link về kit: GeelyEx2 `/Volumes/Data/Toan/GeelyEx2`, OfficeReader `/Volumes/Data/Toan/OfficeReader/OfficeReader` (thư mục con mới là git root; thư mục ngoài rỗng), Goods `/Volumes/Data/Toan/Game/Goods-Triple-Shelf-Match-3D`, Neighbours-From-Hell `/Volumes/Data/Toan/Game/Neighbours-From-Hell`, cộng agent-workbench (nhà của kit, nơi sửa). Chép đường dẫn, không đoán. Repo khác có link về kit (GalaxyHolding, `*-keystore`, bản sao worktree) không đo; nêu nhiều nhất một dòng "ngoài white list". Danh sách gốc: memory `default-four-repos`. Muốn xem repo nào đang link về kit (chỉ để báo cáo, không audit):
   `KIT=$(cd .agents/devkit && pwd -P); find /Volumes -maxdepth 6 -path '*/.agents/devkit' -type l -lname "*$(basename "$KIT")" | sed 's#/.agents/devkit##'`
   Repo trong white list không có phiên nào gần đây thì chỉ đo và nêu trong báo cáo, không audit sâu.
3. Khoá checkout, trong từng repo: `python3 .agents/devkit/bin/session_lock.py --status`. Exit 0 là trống, 3 là có phiên giữ. Từ lệnh con, khoá của chính phiên này cũng báo 3: xem `session_id` trong `.git/devkit-session.lock`. Repo do phiên khác giữ thì chỉ đọc; không dùng `agent-kit allow-shared`.
4. Đĩa: `df -h <ổ của repo>`; dưới 10 GiB trống thì dọn bản sao và scratch của chính mình trước (ENOSPC từng làm công cụ lỗi trước khi chạy lệnh).

## Pha 1. Đo

`python3 $KIT/skills/devkit-audit/scripts/devkit_metrics.py --since-days 7 --repo <R1> --repo <R2> ... --json > $SCRATCH/metrics.json`

Script chỉ đọc. Ghi chú khi đọc số: log `runs.jsonl` bắt đầu từ ngày bật ghi và bị cắt khi vượt khoảng 1,25 MB (xem `first_run`, cửa sổ thực có thể ngắn hơn `--since-days`); `overhead_s` là tổng thời gian trừ thời gian suite, có thể gồm cả chờ khoá test (giả thuyết, chưa kiểm); `lock.exit` 3 có thể là chính phiên này.
Số hook Stop là xấp xỉ, định nghĩa đầy đủ trong docstring của script và cuối `rubric.md`: "sự kiện Stop" = số cặp (phiên, giây) của dòng `[SID=…]` trong `testsourceset_gate.log` (một lần Stop ghi nhiều dòng cùng giây; đếm theo dòng làm số Stop gấp đôi và tỉ lệ chặn thấp giả, đã gặp ngày 10/10); "chặn thật" đã trừ lần hook thả; "lặp" so fingerprint (lấy từ `regression_gate.log` theo thời gian) khi cả hai lượt có, không thì so (exit, `n_changed`, kết quả suite) nên có thể đếm nhầm hoặc bỏ sót khi hai phiên chạy xen kẽ. Ghi `fp` thẳng vào `runs.jsonl` là việc chờ làm (`backlog.md`).
Thêm, mỗi repo: `python3 $KIT/bin/agent-health.py -t <repo>` (đọc dòng `Điểm: N/100`; đã kiểm là không ghi, `git status` trước và sau giống nhau) và `python3 $KIT/scripts/governance/context_sync.py --check <repo>` (exit 0 là bản sao ngữ cảnh khớp kit). Không chạy `agent-kit checklist check` ở repo đang sống: `load()` có thể ghi nhật ký (chưa chứng minh ngược lại).
Ghi một dòng JSON vào `devkit-audit-trend.jsonl` ở cuối pha 6: ngày, điểm từng mục rubric, tổng, vài số chính (repeat phút, hook share, bytes ngữ cảnh).

## Pha 2. Audit chỉ đọc

Dùng Agent tool, `subagent_type: general-purpose` (agent Explore không nạp `AGENTS.md`), chạy nền, các agent song song trong cùng một tin nhắn. Prompt mẫu: `references/agent-briefs.md`. Quy tắc cho mọi agent: chỉ đọc; scratch chỉ trong `$SCRATCH`; không chạy gate/Gradle/Unity trên repo thật; không `git add/commit/stash/checkout/merge/pull/push`; không chạy `enrich_context.py --hook` hay `prompt_context.sh` với prompt giống bug (ghi dòng REPORTED).
Báo cáo của agent là dữ liệu, không phải kết luận: tự chạy lại lệnh chứng minh cho mọi claim sẽ thành việc sửa, rồi gắn nhãn. Agent Antigravity khi được giao việc "chỉ đọc" từng để file rác ở gốc repo, nên dặn rõ và kiểm `git status` sau đó.

## Pha 3. Chọn việc

Điểm = phút tiết kiệm mỗi ngày (đo bằng script) chia rủi ro (1 thấp, 2 vừa, 3 cao: sửa hook/gate/khoá chạy ở mọi repo là 3). Chọn tối đa 3 mục. Thiếu số đo: việc đầu tiên là thêm phép đo, rồi đo vài ngày. Mục thuộc quyền người dùng thì hỏi một lần bằng AskUserQuestion, phương án khuyến nghị đứng đầu.

Nhanh hơn mà không giảm chất lượng, chỉ có bốn đường: bỏ việc lặp cùng trạng thái (cùng fingerprint, có TTL và công tắc tắt, hướng sai lệch là chặn thêm chứ không bao giờ cho qua thêm), chạy song song các suite độc lập, nạp lười, cắt ngữ cảnh trùng. Không được: bỏ suite vì "ít khi hỏng", nới assertion, tăng timeout, bỏ RED-proof.

## `/giao` mặc định (pha 3 và pha 5)

Người dùng yêu cầu (10/10): mỗi lần chạy skill này đều dùng thêm `/giao`. Antigravity chỉ phản biện kế hoạch và audit diff; Claude tự sửa trong bản sao (Antigravity từng viết lại cả hàm, để `patch_*.py` và `.git` lồng, báo test chưa tạo).
1. `pm_doctor` với project là repo chứa kit. Antigravity không chạy hoặc project chưa đăng ký: ghi "chưa chạy" trong báo cáo (mục 9 mất 2 điểm), làm tiếp bằng reviewer ngữ cảnh mới.
2. Pha 3: `pm_task_create` (type `docs` hoặc `refactor`; `definitionOfDone` kiểm chứng được; brief nêu hiện trạng, phạm vi, cái CẤM sửa). Tự viết kế hoạch (tối đa 12000 ký tự): hiện trạng dẫn file:dòng thật, các bước từ nhỏ đến lớn, file sẽ sửa, rủi ro, cách chứng minh, và các câu hỏi cụ thể cần phản biện. Ghi bằng `pm_plan` (đừng đặt vào `forbidden` những file mình sẽ sửa), rồi `pm_dispatch kind=plan_review` (model `pro`), `pm_status`, đọc `plan-review.json`.
3. Tự kiểm từng phát hiện bằng lệnh của mình trước khi tin hoặc bác. Ngày 10/10: một phát hiện sai (log cho thấy hook không bị bỏ qua nên mẫu số không mất), một lời khuyên sai (đổi thứ tự hook: hook chạy song song), các phát hiện còn lại đúng (bước push thiếu pull và gate lại, "lặp" chỉ xấp xỉ, câu mâu thuẫn "đưa lệnh cho người dùng").
4. Bẫy của công cụ: sửa file mà phản biện đã dẫn chứng làm trích dẫn thành NOT-FOUND, và `pm_verdict kind=plan` bị chặn vì "trích dẫn BỊA"; chuyển `plan-review.json` sang `logs/` thì công cụ coi như chưa nghe phản biện (đừng làm). Cách đúng: `pm_plan` bản v2 nêu thay đổi sau vòng 1, rồi `pm_dispatch kind=plan_review focus=delta`; chỉ `pm_verdict kind=plan verdict=pass` khi dẫn chứng của vòng cuối còn khớp file (khoá các file đã dẫn chứng cho tới lúc chốt). Không chốt được thì ghi rõ trong báo cáo, không ép.
5. Pha 5, sau khi sửa và test xanh: `pm_dispatch kind=audit` (message nêu trọng tâm: lỗ fail-open, hồi quy do chính bản sửa, test vacuous), đọc kết quả và tự tái hiện, rồi `pm_verdict kind=audit` và `kind=review`. Không `pm_dispatch kind=implement` mặc định.
6. Sau mỗi lượt Antigravity: `git status`; xoá file mới chưa theo dõi mà chính nó tạo (chỉ những file đó). Task chỉ phản biện hoặc audit không cần `pm_accept`.
7. Số liệu người review (người dùng yêu cầu 11/10, để so Antigravity với reviewer Claude): sau mỗi lượt `python3 $KIT/skills/devkit-audit/scripts/review_log.py collect` (mỗi lần giao một dòng, kèm tên model THẬT đọc từ file hội thoại; `pro` từng là `gemini-3.1-pro-low`, `flash` là `gemini-3.8-flash-tiered`), rồi `note` kết luận ngay khi biết (`--conversation ID --real N --nit N --false-positive N --missed N --stray-files N`; reviewer Claude thêm bằng `note --source claude --model <model> --findings N --real N …`). real = lỗi có thật bạn tái hiện được, nit = đúng nhưng vặt, false-positive = sai, missed = lỗi có trong thứ nó duyệt mà reviewer khác tìm ra sau. Cuối phiên `review_log.py summary` vào báo cáo; log ở `.agents/local/memory/claude-auto/reviewer-log.jsonl`.

## Pha 4. Sửa an toàn

1. `cp -Rc "$KIT" "$SCRATCH/kitcopy"` với `$KIT` là đường dẫn thật (kit khoảng 13 MB, APFS clone gần như tức thì). Kiểm bản sao là thư mục thật: `[ -d "$SCRATCH/kitcopy/hooks" ] && [ ! -L "$SCRATCH/kitcopy" ]`. Sửa và chạy test trong bản sao; test tự tìm kit theo vị trí file của chúng. Xoá bản sao ngay khi đã cài và push.
2. Test ĐỎ trước: viết test mới (file mới, đặt tên `tests/<nhóm>/test_*.sh`, khung `check()` xem `tests/gates/test_guard_comment_not_swallowing.sh`), chạy trên mã chưa sửa và thấy ĐỎ đúng lý do. Sau đó sửa tối thiểu, thấy XANH, rồi chạy mọi test có nhắc tên file vừa sửa: `grep -rlE '<tên file>' tests hooks/tests`.
3. Cài vào kit thật từng file một: `cp -p new <dir>/.<tên>.new && mv -f <dir>/.<tên>.new <dir>/<tên>`. Hook, `session_lock.py` và gate được symlink sống vào mọi repo, ghi tại chỗ sẽ làm hỏng phiên đang chạy.
4. Chạy lại test mới trên file thật, từng test bằng một lệnh trực tiếp `bash tests/<nhóm>/test_x.sh`. Hook bằng chứng của Stop không công nhận một lượt chạy gộp trong vòng lặp `bash -c '…'` (đã gặp ngày 10/10), nên không dựa vào dạng gộp đó.

Bẫy khi sửa hook/gate:
- Python trong `hooks/*.sh` nằm trong chuỗi bash `python3 -I -c '…'` một nháy: không được có dấu `'` trong code mới, kể cả docstring; dùng `\x27`.
- Hook thật chặn lệnh Bash có chữ nguy hiểm trong văn bản dù chỉ là dữ liệu (`git reset --hard`, `rm -rf` trong chuỗi): ghi payload bằng Write/Edit vào file test, không đặt trong lệnh Bash.
- Sửa parser bằng một dòng đã từng làm hồi quy (`commenters=""` làm dấu nháy trong comment làm `shlex` lỗi và mất luật nhánh). Mọi sửa parser phải có test hai chiều: chặn đúng và cho qua đúng; reviewer thử phá bản sửa chứ không chỉ bản gốc.
- zsh không tách từ `for x in $var`: dùng `bash -c` hoặc `while read`.
- Lệnh Bash `cd` vào repo đang bị phiên khác giữ và nhắc `post-fix-gate` (kể cả trong heredoc) bị `session_lock` chặn: dùng `git -C <repo>` và chạy từ repo của mình.

## Pha 5. Review độc lập

**Reviewer thứ hai = OpenCodeReview (OCR), người dùng yêu cầu 13/10.** Chạy `python3 $KIT/bin/ocr-review --from origin/main --to HEAD` (hoặc `--commit <sha>`, hoặc không cờ cho thay đổi chưa commit) từ gốc repo. Có endpoint LLM (`ocr config provider`, khoá do người dùng tự nhập) thì OCR tự review và in `report: <file>`; không có thì in `spec: <file>` (chế độ delegation, không cần khoá): giao spec đó cho một agent `general-purpose` ngữ cảnh mới KHÁC reviewer thứ nhất, nó review đúng các file và luật trong spec. Kết quả OCR đi chung luồng: tự tái hiện từng phát hiện, lỗi thật thì ĐỎ→XANH; ghi `review_log.py note --source ocr --model <model hoặc delegate> …`. `ocr` không cài (`ocr-review` thoát 3): ghi "OCR chưa chạy" trong báo cáo.

Agent `general-purpose` ngữ cảnh mới, chỉ đọc, mẫu trong `agent-briefs.md`. Nó phải tái hiện từng lỗi bằng đầu vào cụ thể và kết quả quan sát. Mọi lỗi thật: sửa với test ĐỎ→XANH, rồi một lượt review thứ hai chỉ trên phần vừa sửa (bản sửa vòng 1 từng gây hai hồi quy mà chỉ review mới bắt được). Việc thuộc phạm vi lớn (từ 3 file, 2 module hoặc 200 dòng) cũng nên hỏi ý Antigravity qua `antigravity-pm` nếu đang chạy; chưa có thì ghi rõ "chưa chạy" trong báo cáo.

## Pha 6. Cổng và bàn giao

1. Đăng ký bug cho mỗi lỗi đã sửa: `agent-kit bugs add "<tiêu đề trung tính>" --fixed --module <m> --severity <s> --test <đường dẫn test từ gốc repo>`; lệnh in id. Commit sửa code phải có dòng `Bug: <id>[, <id>]`.
2. Gate ở mỗi repo đã đụng: `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief` từ gốc repo (workbench mất vài phút: chạy nền). Chỉ exit 0 là đạt. Không chạy song song với phép đo độ trễ.
3. Commit đúng file của mình (`git add <đường dẫn>`, không `-A`; khi checkout dùng chung có file staged của phiên khác thì `git commit -m "…" -- <đường dẫn>`). `.agents/regression_status.json` và `.agents/CHECKLIST.md` do gate ghi: đi cùng commit. Trước push: `git fetch`; nếu origin đi trước thì `git pull --ff-only` (hai bên cùng có commit mới: `git pull --no-rebase --no-edit`), kiểm exit code (không đặt sau `|`), rồi chạy lại gate trên nội dung sẽ push (`post-fix-gate.py --run-tests --full --diff origin/<nhánh>`). Chỉ khi gate exit 0: `git push origin <nhánh hiện tại>`; không bao giờ `<sha>:<nhánh>` hay force.
4. RED-proof sau commit: tạo patch đưa lỗi trở lại từ chính commit (`git diff <commit> <commit cha> -- <file sản xuất>`; chỉ file sản xuất, dưới 5 MiB), rồi `DEVKIT_IMPACTED_SINCE=0 python3 $KIT/scripts/testing/red_proof.py . --bug <id> --patch <file> --wait` cho từng bug. Kết quả PROVEN vào commit tài liệu riêng.
5. Ghi bẫy mới: `agent-kit learn "<tên>" --cause="…" --rule="…"`. Sửa memory đã lỗi thời (dòng chỉ mục cũng vậy). Ghi dòng trend và note bàn giao: việc chưa xong, quyết định đang chờ, số đo, bước tiếp.
6. Dọn: xoá bản sao kit, clone và file tạm của chính mình bằng đường dẫn cụ thể ngay khi đã push (không glob, không biến chưa kiểm).
7. Hàng RED-proof chờ (W4b): `nightly.py run <repo>` MỘT lần cho mỗi repo rảnh. Người dùng quyết 24/09 không cài job đêm, nên lượt audit hằng ngày làm việc đó và không cài gì cả. Làm sau pha 1 (số đo hôm nay không bị lệch) và sau các gate ở bước 2 (cả hai giữ `test_run.lock`, không chạy chồng). Mỗi repo trong white list, MỘT repo một lúc:
   1. Ngay trước khi chạy repo đó (không dùng kết quả pha 0: lượt này kéo dài): `python3 .agents/devkit/bin/session_lock.py --status` trong repo. Chỉ exit 0 mới chạy. Exit 3 (phiên khác giữ; workbench cũng báo 3 vì chính phiên này đang giữ) và exit 5 (trunk mode: main chỉ nhận merge, mà nightly ghi checklist đã commit vào checkout đó) thì bỏ qua repo và ghi "bỏ qua: <lý do>" trong báo cáo. Không `allow-shared`, không worktree. Exit 0 KHÔNG có nghĩa là không có phiên nào ở đó: `--status` coi phiên đã xong lượt và đang chờ người dùng gõ là rảnh, mà phiên ấy nhận lại khoá ngay khi người dùng gõ rồi sửa đúng cây đang chạy suite (Stop gate của nó xếp hàng sau `test_run.lock` tới 3600 s). Phép kiểm khoá chặt hơn nằm trong `nightly.py run <repo>`: phiên còn sống giữ checkout, kể cả đang rảnh, thì nó không chạy repo, in `skip: <lý do>` và kiểm lại trước mỗi suite; ghi dòng đó vào báo cáo. Phần dư đã biết: phiên mở trong lúc một suite đang chạy chỉ bị thấy ở ranh giới suite kế.
   2. `python3 $KIT/scripts/governance/nightly.py run <đường dẫn gốc git của repo>` chạy nền (`run_in_background`), đợi xong rồi mới sang repo kế. Một đường dẫn: chỉ repo đó chạy, danh sách `nightly-projects` không đổi, không báo cáo tuần. Nó chạy mọi suite của ma trận thật (cả Gradle/Unity, trần `NIGHTLY_SUITE_TIMEOUT_S` mỗi suite) rồi `red_proof.py --pending --heavy --wait`: một repo có thể mất hàng chục phút đến hơn một giờ. Ma trận không được gate tin thì nó tự bỏ qua và in lý do: ghi lại.
   3. Kết quả: dòng nó in, kèm `checklist.waiting` của repo (`devkit_metrics.py --repo <repo>`) trước ở pha 1 và sau. Nó ghi `.agents/regression_status.json` và `.agents/CHECKLIST.md` của repo như một lượt gate; để nguyên cho commit kế tiếp của repo đó, không commit hộ. (Bước này thêm 15/10; mới chạy trên repo mẫu của `tests/verification/test_nightly.sh`, chưa trên repo thật: lần đầu ở repo thật, đọc kỹ dòng nó in.)

## Pha 7. Báo cáo

Ba dòng đầu: XONG hoặc CHƯA XONG, người dùng nhận được gì, gate exit và lý do không cần ảnh. Rồi bốn mục (đã fix gì, chặn bug cũ, nguy cơ bug mới, an toàn mã nguồn), điểm /100 theo `references/rubric.md` với từng mục bị trừ và lý do. Câu "đã fix" cần cặp ĐỎ→XANH trong chính lượt; câu "test đạt" cần test chạy trực tiếp sau lần sửa cuối. Thiếu bằng chứng thì nêu đúng phạm vi và ghi chưa xác nhận. Xoá dữ liệu thật của người dùng (backup, repo rỗng, nhánh remote) và force-push: luật an toàn thắng, không tự làm; hỏi một lần bằng AskUserQuestion, họ tự thực hiện. Mọi bước khác (gate ở mọi repo, cài kit, đồng bộ, commit, push) tự làm: không đưa lệnh `!` hay danh sách việc cho người dùng; bước bị từ chối quyền thì báo CHƯA XONG nêu đúng bước đó, không lách.
