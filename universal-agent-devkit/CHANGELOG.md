# Changelog

All notable changes to Universal Agent DevKit. Versions follow `.claude-plugin/plugin.json`.

## Unreleased

- **Luật "1 dev, 1 nhánh" và hook chống lệch nhánh** (`rules/essentials.md`, `AGENTS.md` §7.1, `rules/core-rules.md` §2). Sự cố gốc (GeelyEx2, 2026-09-26): push `<sha>:main` từ commit mà `main` local chưa có làm `main` local tụt 2 commit so với origin; nhánh worktree bị bỏ lại. Git guard (`hooks/block-dangerous-git.sh`) giờ chặn tạo nhánh (`checkout -b/-t/--orphan`, `switch -c/-t/--orphan`, `branch <mới>`, `branch -c`, `worktree add`), push tạo nhánh remote mới, và push `<src>:<dst>` khi `<dst>` local chưa chứa `<src>` (kiểm trong repo của `-C`, `cd` cuối — `cd` trong `( … )` không tính cho lệnh sau —, hoặc `cwd` của hook; push `<src>:<dst>` không kiểm được — thư mục `cd "$R"`, nguồn `$(…)`, git lỗi/quá 5 s — cũng bị chặn). Mỗi đoạn `$(…)`/backtick được coi là một từ rồi mới phân tích, nên message commit viết bằng `$(cat <<'EOF' …)` không bị đọc thành lệnh (review: bản đầu chặn theo mẫu chữ và chặn nhầm cả message commit); redirection (`2>/dev/null`) không bị coi là tên nhánh; alias git (`-c alias.nb='checkout -b'`) cũng bị kiểm; push tag `v1.0:v1.0` được phép. Nhánh người dùng yêu cầu: `DEVKIT_ALLOW_BRANCH=1` — chỉ mở khoá tạo nhánh, không mở khoá push `<sha>:<nhánh>` mà local chưa chứa. Thông báo chặn nêu cách sửa (kéo origin về nhánh local bằng lệnh riêng rồi `git push origin <nhánh>`), khác thông báo "User đã chặn" của lệnh phá huỷ. Lúc mở phiên (`hooks/session_context.sh`): fetch upstream (tối đa 6 s, ssh `BatchMode` + `ConnectTimeout=4` nên không hỏi mật khẩu, hết giờ thì giết cả nhóm tiến trình nên không để lại ssh mồ côi; `SESSION_FETCH=0` bỏ qua) rồi báo nhánh tụt/vượt/lệch hai phía, HEAD tách rời, nhánh phụ, worktree còn lại, nhánh thừa đã merge (`git branch -d …`) hoặc chưa merge. Hai test cũ khẳng định `checkout -b`/`switch -c` được phép giờ chạy với `DEVKIT_ALLOW_BRANCH=1` (vẫn kiểm là không bị nhầm với `-B`/`-C`). Test: `hooks/tests/hook_contract_test.sh` (solo:…), `tests/test_session_context.sh` (drift:…).
- **`BUG_CAPTURE` không còn ghi prompt giao việc thành bug** (`scripts/enrich_context.py`): "bug" dùng như một tập đã biết hoặc làm đối tượng của việc ("viết test cho các bug còn lại", "link bug luôn đi", "40 bug", "tổng số bugs"), hoặc chỉ nằm trong đường dẫn / lệnh slash ("docs/plan/…-bug.md", "/geely-fixbugs"), không còn tạo dòng REPORTED. Ảnh hoặc video trong thư mục `bug(s)/` (kể cả trong ngoặc, tên có dấu cách) vẫn là dấu hiệu báo bug. Chỉ token thật sự giống đường dẫn mới bị bỏ: "crash/văng", "fail/timeout", "App crash.Fix" vẫn là từ; "2 crash bugs" giữ "crash". Regex neo đầu token nên token dài 160 KB vẫn chỉ ~11 ms. Đo trên 2307 prompt thật (Claude Code, 30 ngày): 17 prompt thôi bị ghi, cả 17 đều là prompt giao việc; trong bộ này không mất báo cáo bug thật nào. Còn lại: "gặp 1 bug ở checkout, tổng tiền lệch" (đếm số, không có từ lỗi) không được ghi.
- **Quy tắc tác giả của lệnh shell hẹp lại, đúng như transcript thật** (`bin/session_authorship.py`, hai vòng review 2026-09-25): chỉ lệnh đứng đầu một đoạn mới là động từ ghi, và chỉ đường dẫn của đoạn đó được tính. Parser đọc được từ khoá shell (`for … do cp`, `if … then`, `{`, `!`), wrapper (`timeout`, `nice`, `sudo -u`, `xargs -n`), `sh -c`/`eval`, `$(…)` và heredoc đưa vào shell. Động từ ghi còn lại mà parser không đặt được vào đoạn nào thì quay về quy tắc cũ (mọi token). Token `/` đứng một mình không còn là "mọi file". Đo trên 214 phiên thật trong 30 ngày: tỷ lệ tính nhầm "của mình" giảm từ 69,6% xuống 24,8%, và không bỏ sót lệnh ghi thật nào mà quy tắc cũ bắt được.
- **Bằng chứng "phiên khác sửa test" khó giả hơn**: phiên đã ghi một `*.jsonl`, hoặc ghi vào thư mục transcript (trừ auto-memory `memory/` của Claude Code), thì không có bằng chứng "phiên khác". Phiên đã khởi chạy một agent CLI (kể cả qua `timeout`, vòng lặp, `bash -c`, `npx …claude-code`; không tính `claude mcp …`, `codex --version`) thì mọi phiên bắt đầu sau đó được coi là phiên con của nó. Giới hạn còn lại (`ponytail:`): một tiến trình tách rời vẫn ghi được transcript hoặc ledger mà không ai thấy. Thời gian file không chứng minh được gì, vì `utime` trên macOS lùi được cả `st_birthtime`.
- **`test_evidence_gate`: dấu `:` ngay sau động từ trích dẫn vẫn là lời người khác.** "The user said: …", "Phiên khác báo: …", "Người dùng báo: đã fix…" và "reported, at 08:41, that …" không còn bị chặn. Dấu phẩy trần sau động từ, ", that's …", và ": I fixed it" (ngôi thứ nhất) vẫn là claim của agent.
- **`stale_rerun`/nightly: khi đã giữ khoá test, suite được cấp đủ timeout của nó.** TIMEOUT ghi lại luôn là của chính suite. Trước đây thời gian chờ khoá bị trừ vào timeout, nên có lúc suite xanh bị báo đỏ oan, có lúc treo thật lại bị bỏ qua. Đổi lại, một job có thể chạy tối đa gấp đôi timeout.
- **`worktree_guard` quét transcript theo kiểu tăng dần**: cache số byte đã quét trong `.claude/audit-gate/wg_scan/`. Trên transcript 50 MB, mỗi tool call giảm từ 249 ms xuống ~28 ms (hook rỗng mất 19 ms). File bị ghi lại ngắn hơn thì được quét lại từ đầu. Phiên trong worktree không được ghi vào cache này.

- **Kết quả không bị ghi đỏ oan khi phải chờ khoá test** (`scripts/stale_rerun.py`): suite chỉ hết giờ vì một lượt khác giữ `test_run.lock` thì bị bỏ kết quả, không ghi TIMEOUT (trước đó nightly báo "chuyển sang đỏ"); lần chạy lại dùng phần thời gian còn lại.
- **`test_evidence_gate`: dấu phẩy và ": " kết thúc phần trích lời người khác.** "Người dùng báo crash…, đã fix xong." giờ là claim của agent và phải có bằng chứng.

- **Cài lại DevKit mở rộng matcher của hook đã có.** `scripts/merge_json.py`: hook DevKit đang gắn dưới matcher hẹp hơn (vd. `worktree_guard` dưới `Edit|Write` trong khi template là `Edit|Write|MultiEdit|NotebookEdit`) được thêm cho đúng các tool còn thiếu, trong một nhóm riêng; nhóm của người dùng giữ nguyên, không tool nào bị phủ hai lần. README.vi có mục `worktree_guard`.
- **Test đã có do PHIÊN CLAUDE KHÁC sửa bằng Edit/Write không còn chặn phiên này.** Edit/Write không để lại cửa sổ Bash trong `bash_write_ledger.tsv`, nên `split_tests_by_author` coi là "không xác định" và chặn. Giờ gate đọc transcript của các phiên khác cạnh transcript của phiên này (`~/.claude/projects/<slug>/<id>.jsonl` và `<id>/subagents/*.jsonl`): một Edit/Write/MultiEdit/NotebookEdit cùng đường dẫn tuyệt đối mà khoảng tool_use → tool_result (±1 s; chưa có kết quả: 5 s) chứa mtime của file là bằng chứng "phiên khác" (cửa sổ hẹp nhất thắng, như cửa sổ Bash). Có giới hạn: chỉ transcript sửa từ lúc phiên này bắt đầu, tối đa 64 file, 8 MB cuối mỗi file, 2 s; bỏ bản ghi mang sessionId của chính phiên (fork), bỏ lời gọi lỗi (`is_error`); lỗi/quá hạn → không có bằng chứng → vẫn chặn. Đo trên máy: 82 MB transcript trong 24 h quét hết 0,17 s. Test: `tests/test_postfix_gate.sh`.
- **Tool MCP chỉ-đọc dạng camelCase và tool đọc của antigravity-pm/replicant không còn tắt quy tác giả.** `getJiraIssue`, `getConfluencePage`, `searchJiraIssuesUsingJql` (tiền tố get/read/list/search/query/fetch + chữ hoa; `fetch_` cũng nhận), `mcp__antigravity-pm__pm_status|pm_diff|pm_report|pm_doctor|pm_ack` (pm_report chỉ ghi file báo cáo trong thư mục trạng thái task, pm_ack ghi task.json) và `mcp__replicant-mcp__ui-query` là chỉ-đọc; `ui-capture` có `localPath` được tính là phiên ghi đúng file đó. Tên có từ ghi (`getOrCreateFile`, `searchAndReplace`, create/edit/update…) và `ui-action`, `Monitor`, `pm_task_create`, `pm_accept` vẫn "mờ" (chặn). Test: `tests/test_postfix_gate.sh`.
- **Phiên tự khôi phục/sửa test bằng lệnh đặt lại mtime giờ bị tính là của phiên.** `git archive … | tar -x`, `rsync -a …/src/ src/`, `cp -p … src/test/`, `sed -i … src/test/*.kt && touch -t 2020… src/test/*.kt` trước đây ra "phiên khác" (cảnh báo, exit 0): tên chỉ khớp bằng/đuôi, thiếu động từ tar/rsync/unzip/cpio/7z/git archive, và "trước phiên" xét theo mtime. Giờ tên khớp cả glob và thư mục chứa file (`src/`, `.`), có thêm các động từ đó, và "trước phiên" xét theo max(mtime, ctime) — ctime không đặt lùi được. Test: `tests/test_postfix_gate.sh`.
- **`testsourceset_gate.sh` dùng chung luật tác giả với post-fix-gate** (`bin/session_authorship.py`, không chép lại). Trước đây phiên ghi Kotlin bằng tool MCP, MultiEdit, `touch`, `rsync` vào thư mục… bị coi là "không ghi Kotlin" → PASS mà không compile. Giờ: tool không nhìn xuyên được → compile toàn repo (fail closed); MultiEdit, các động từ ghi mới, glob/thư mục → phạm vi đúng module; không tìm thấy `bin/session_authorship.py` (cạnh hook, `.agents/devkit/bin`, `$DEVKIT_ROOT/bin`, `~/.universal-agent-devkit/bin`) → toàn repo. Test: `tests/test_testsourceset.sh`.

- **`worktree_guard`: build chạy qua trình thông dịch và file ĐƯỢC TRACK trong thư mục memory của main lại bị chặn** (review 2026-09-25). `sh ./gradlew assembleDebug`, `bash gradlew test`, `python3 -m pytest|mypy|black|ruff|pip|…` chạy ở main checkout trước đó lọt (nhánh trình thông dịch chỉ xét toán hạng sau script) trong khi `./gradlew` bị chặn; giờ script là build tool hoặc module là builder/test runner/formatter thì tính là ghi vào main. Miễn trừ "chỉ có ở main" hẹp lại: `.claude/agent-memory`, `.claude/audit-gate` chỉ khi file không được track; `.agents/local/memory` chỉ nơi git của main ignore, trừ `claude-auto/` (auto-memory của Claude Code) luôn được miễn — GeelyEx2 và Goods track `bugs/*.md`, nên agent trong worktree trước đó ghi được file đã track của main. Test: `hooks/tests/hook_contract_test.sh` (2026-09-25).
- **`worktree_guard` bắt lại phiên VÀO worktree giữa chừng bằng tool `EnterWorktree`.** Từ khi chỉ tính nơi phiên BẮT ĐẦU, phiên bắt đầu ở main rồi gọi `EnterWorktree` không còn được coi là có worktree, nên ghi vào main checkout không bị chặn. Giờ hook đọc transcript chính: lời gọi `EnterWorktree`/`ExitWorktree` cuối cùng có tool_result không lỗi là Enter → worktree đó được khai (đường dẫn lấy từ `input.path`, đường dẫn tuyệt đối trong kết quả là một linked worktree, hoặc `M/.claude/worktrees/<input.name>`); `ExitWorktree` kết thúc; lời gọi lỗi không đổi gì (không khai, cũng không huỷ một Enter thành công trước đó). Leader chỉ `cd` vào worktree để xem vẫn không bị khai. Đường nhanh vẫn rẻ: python chỉ chạy khi transcript có một lời gọi (`"name":"EnterWorktree","input"`), không phải chỉ có schema của tool. Chưa có transcript thật nào gọi tool này trên máy, nên tên tool lấy theo tài liệu và hình dạng block theo các tool khác. Chưa bắt: `claude --resume` từ thư mục khác. Tài liệu: `AGENTS.md` §7.1. Test: `hooks/tests/hook_contract_test.sh` (S3–S7) (2026-09-25).
- **BUG_CAPTURE chỉ bỏ prompt GIAO VAI**, không bỏ mọi prompt mở đầu bằng "You are …"/"Bạn là …": "You are right, but it still crashes", "Bạn là dev Android thì xem giúp: app crash…", "Your task is to fix the crash" giờ được ghi REPORTED; "You are a senior reviewer…", "Bạn là một reviewer…" vẫn bị bỏ.
- **`test_evidence_gate`: lời khai của chính agent không còn được coi là lời người khác.** Luật ATTRIBUTION chỉ còn nhận một actor KHÁC: another/other/a different hook|session|person|user, hook|phiên|người khác, "by someone", the user said. Bỏ previous/earlier/prior/separate, run/job/process/worker, "lần chạy trước" và cả "agent" (leader chuyển lời subagent chưa kiểm chứng không được qua). Trước đó "Previous run: 13/13 tests pass.", "Lần chạy trước 13/13 test pass.", "Previous session fixed bug A.", "The other agent ran the suite: 13/13 tests pass." bỏ qua kiểm XML (review P1). XML của project KHÁC giờ chỉ tính khi cửa sổ Bash hẹp nhất chứa nó trong `bash_write_ledger.tsv` là của chính phiên này (không ledger / không cửa sổ → không tính); trước đó một XML xanh agent khác để lại, phiên này chỉ `cat`, vẫn chống lưng được claim (review P3). Test: `hooks/tests/hook_contract_test.sh` (te-p1…p6, te-f7…f9) (2026-09-25).
- **Quy tác giả test đã có: không xác định được thì chặn (fail closed).** `post-fix-gate.py split_tests_by_author` chỉ nhìn Edit/Write/NotebookEdit và Bash, nên một test do CHÍNH phiên sửa bằng tool MCP ghi file (vd. `mcp__jetbrains__replace_text_in_file`) hoặc sửa rồi `touch -t 2020… <test>` bị tính là "phiên khác" → PASS kèm cảnh báo. Giờ: phiên có gọi tool nào ngoài danh sách chỉ-đọc (lấy từ tên tool trong transcript thật; MCP chỉ khi tên tool bắt đầu bằng get/read/list/search/query) thì mọi test đã có bị sửa đều chặn; `touch`/`ln` là lệnh ghi; "phiên khác" cần bằng chứng: mtime nằm trong cửa sổ Bash của phiên khác, hoặc trước prompt đầu của phiên mà không lệnh ghi nào của phiên nêu tên file (file đã xoá: phiên không chạy Bash nào). Đổi trong phiên nhưng ngoài mọi cửa sổ → chặn (trước đây là cảnh báo). Test: `tests/test_postfix_gate.sh`, `tests/test_regression_gate_hook.sh`.
- **Khoá chạy test bận (BUSY) được báo đúng nguyên nhân.** Stop hook `regression_gate.sh` truyền `TEST_RUN_LOCK_WAIT_S=120` (trừ khi đã đặt; 900 cộng thời gian suite có thể vượt timeout 1800 s của hook); gate trả `"busy": true` và kết luận "một lượt chạy test khác đang giữ khoá dự án"; hook in "một lượt chạy test khác đang giữ khoá dự án — chạy lại sau", không lưu thành UNTESTED cho cây (trước đây báo "thiếu công cụ" và chế độ degraded dùng lại kết quả đó). `scripts/stale_rerun.py run_one` chờ khoá tối đa bằng timeout của suite (trước đây chờ vô hạn), quá hạn → BUSY, không chạy, không ghi; phần thời gian chờ bị trừ khỏi timeout của suite. Test: `tests/test_postfix_gate.sh`, `tests/test_regression_gate_hook.sh`, `tests/test_stale_rerun.sh`.
- **`worktree_guard` không còn chặn việc hợp lệ** (review 2026-09-25). Leader bắt đầu ở main checkout rồi `cd` vào worktree để xem không còn bị coi là "đang làm trong worktree": `cwd` của hook đi theo mọi `cd`, nên giờ chỉ tính nơi phiên BẮT ĐẦU (`cwd` đầu tiên trong transcript) — sửa file, `git merge`, `git apply` ở main lại được. Subagent có worktree mà shell ở main không còn bị chặn `git stash list/show`, `python3 -c …` hay chạy script (trình thông dịch chỉ bị xét theo toán hạng sau script; `bash -c '…'` được quét bên trong; build tool vẫn bị chặn), `scp … host:/…`, `dd if=…` (chỉ `of=` là đích ghi); `.claude/agent-memory`, `.claude/audit-gate`, `.agents/local/memory` của main được ghi. Hook giờ bắt cả `MultiEdit` và `NotebookEdit` (nhóm matcher riêng `Edit|Write|MultiEdit|NotebookEdit` trong `hooks/hooks.json`, `templates/claude_settings.json`, `.claude/settings.json`; `agent-kit init` bổ sung các tool còn thiếu cho bản cài cũ — xem mục `merge_json.py` ở trên). Tài liệu: `AGENTS.md` §7 + §7.1, `README.md` (`DEVKIT_WORKTREE`, `WORKTREE_GUARD=0`). Test: `hooks/tests/hook_contract_test.sh`.
- **Checklist journal: đổi nhánh / pull / reset / stash không còn bị báo ROLLBACK, và journal không mất dòng khi hai tiến trình ghi.** Mỗi bản ghi journal mang `head` (sha HEAD). `load()` coi file là mốc mới (`external`, `via: git`) khi file đúng bằng bản đã commit ở HEAD và nội dung journal trước đó vẫn là một object của git (commit ở nhánh khác, ở HEAD cũ, hoặc trong stash) — so HEAD đổi + blob HEAD thôi thì sẽ bỏ lọt ca commit code rồi `git show HEAD:… > …` đè công việc chưa commit. Sự cố gốc (HEAD không đổi, nội dung chưa từng vào git) vẫn báo. Trước đó về lại `main` sau khi commit bug trên `feat` báo "chép đè bằng bản cũ hơn", `checklist check` exit 1 và `checklist restore` kéo dòng của `feat` vào `main`. Ghi journal, xoay snapshot, `rollback.json` và bước thay file của `save()` giữ một khoá journal riêng (re-entrant, sau khoá checklist); caller chỉ đọc (health, check, SessionStart) chờ tối đa 2 giây rồi bỏ qua bước kiểm, không treo, không lỗi; snapshot làm mốc so sánh không bị xoay mất. Trước đó hai tiến trình ghi ở mức trần 500 dòng mất 51/300 dòng (2026-09-25).

- **`test_evidence_gate` nhận ra các bộ test bash của chính DevKit** (`tests/test_*.sh`, `*contract_test.sh`, `run_impacted.sh`, `agent-kit test`): phán đỏ/xanh theo dòng tổng kết (`N failed`, `N deviating`, `❌`, `✖` → đỏ; `all passed`, `0 deviating` → xanh), vì tên ca đã qua có thể chứa FAIL/REJECT/ERROR viết hoa. Trước đó một cặp ĐỎ→XANH thật của `test_bug_capture.sh` bị coi là "không có lần chạy test nào" (2026-09-25).

- **Regression gate không còn chặn mọi lượt khi chỉ chờ người duyệt diff test.** Khi lý do duy nhất là test đã có bị chính phiên này sửa (chỉ người review hoặc commit mới gỡ được), `regression_gate.sh` chặn MỘT lần cho mỗi thay đổi để agent báo người dùng; các lần dừng sau của cùng thay đổi được cho qua kèm lời nhắc (không phải PASS). Thay đổi mới → chặn lại một lần. Trước đó một phiên bị chặn 6 lần liền (2026-09-25).

### Báo cáo nghiệm thu 4 mục được ép, không chỉ ghi trong luật
- **Nguyên nhân sót (2026-09-25):** báo cáo 4 mục chỉ nằm ở `core-rules.md` §1.3 (đọc khi cần); `essentials.md` (luôn nạp) không nhắc, chỉ có "mở đầu 3 dòng, ngắn gọn"; không hook nào kiểm. Một lượt push bàn giao đã thiếu nó mà không gì chặn.
- `essentials.md` bước 5 có khuôn 4 mục. `proof_gate.sh` chặn câu trả lời mở bằng XONG, hoặc của lượt đã chạy `git push` (dù không ghi XONG), khi thiếu một trong 4 mục (nhãn tiếng Việt hoặc Anh); lượt push chỉ bị kiểm phần báo cáo. Test: `tests/test_proof_gate.sh` (XONG thiếu báo cáo, lượt push thiếu/đủ báo cáo, trả lời thường không bị kiểm).

### Audit 2026-09-25 — workflow fixes
- **Ảnh proof chỉ miễn khi thay đổi chắc chắn không lên màn hình.** `proof_gate.sh` hỏi `bin/tree_fp.py image_required`: mặc định CẦN ảnh; chỉ miễn khi profile là `backend` lúc đầu lượt (file profile đã commit, hoặc chưa commit nhưng có từ trước lượt; đổi profile trong lượt không miễn gì), hoặc MỌI file đổi so với HEAD lúc đầu lượt (qua reflog: commit, merge, pull, reset đều tính; file mới; đổi tên thấy cả hai đường dẫn) nằm dưới `.agents/ .claude/ .gemini/ .github/ .githooks/ .codebase-memory/ docs/ reports/ scripts/ bin/ tools/` ở gốc, thư mục test ở gốc hoặc `src/<test source set>/`, hoặc là Markdown/LICENSE ở gốc (Markdown sâu hơn, và `docs/` của profile web, có thể là nội dung site). PNG được trích luôn bị kiểm: giờ trong tên phải thuộc lượt này (không trước lượt, không ở tương lai) và không trùng byte với ảnh proof khác (chặn `touch` và `cp` ảnh cũ; `mv` ảnh cũ sang tên mới rồi `touch` thì không bắt được — giới hạn còn lại). XONG luôn cần gate `--full` exit 0. Trước đây mọi lượt sửa tooling/backend chỉ có hai lối: CHƯA XONG mãi hoặc XONG sai luật.
- **Lượt không sửa file** (hỏi, review, lập kế hoạch) trả lời thẳng: không gate, không ảnh, không dòng trạng thái (`essentials.md` "Every prompt").
- **Thay đổi chỉ gồm tài liệu** (`.md/.rst/.adoc`, LICENSE…) qua gate mà không cần test hồi quy; `.txt` và ảnh vẫn cần (có thể là `requirements.txt` hay asset của app).
- **Cảnh báo dependency mới** thêm pip (`requirements*.txt`), Podfile, SwiftPM, pubspec, Cargo / `pyproject.toml` (Python 3.11+), `pom.xml`; và nằm trong `--json` dưới khoá `advisories` (không phải `findings`, vì không chặn).
- **Commit trong lượt không còn làm mất biên nhận gate.** Dấu vân tay (`bin/tree_fp.py`) là nội dung cây (index tạm, không đụng index thật), không phải mã HEAD: commit đúng code đã qua gate giữ XONG; sửa gì khác vẫn huỷ. Vân tay rỗng không bao giờ khớp.
- **Proof block chỉ chấm ảnh mới** (mtime sau `POSTFIX_PROOF_SINCE`, mặc định 6 giờ gần nhất; cả ảnh trong `reports/` bị gitignore hay đã commit). Ảnh đã xoá không còn bị báo "0 byte"; ảnh cũ hơn chỉ làm mẫu để so, nên hai ảnh cũ trùng nhau không chặn mọi lượt sau (một phiên Grok ở OfficeReader bị kẹt vì lỗi này).
- **`tests/run_impacted.sh`**: chạy các test nhắc tên file DevKit vừa đổi (working tree, file mới, commit chưa push) + repo-consistency, `--list` để xem; ma trận của agent-workbench dùng nó vì cả bộ `agent-kit test` vượt quá 900 s/lệnh của gate.
- **Antigravity nhận được luật DevKit.** Đo 2026-09-25 bằng `agy -p`: Antigravity đọc `AGENTS.md` như văn bản thường, không mở rộng `@import` nào (cũng không đọc `.agents/rules/`), nên essentials chưa từng tới nó ("NOT LOADED"). Khối DevKit giờ chép nguyên văn `rules/essentials.md` giữa `<!-- devkit-essentials:start/end -->`; `scripts/context_sync.py` làm mới đoạn đó (init, SessionStart, relink) và `--check` báo khi ai sửa tay. Dòng `@…/essentials.md` bỏ đi nên Claude không nạp hai lần (đo: 1 lần). Sau đổi: Antigravity trả lời đúng bậc 4 của thang. Gemini CLI trên máy này không còn dùng được (IneligibleTierError).
- **Gate không còn ghép sai module Gradle trong composite build** (GeelyEx2): file thuộc một build Gradle khác thư mục mà lệnh chạy Gradle (`cd <dir> &&|;`, `(cd …)`, `gradlew -p <dir>`) thì không thu hẹp lệnh test (trước đây ra `:testDebugUnitTest` không tồn tại → FAIL mà không test nào chạy); chạy đủ lệnh.
- **`agent-kit health <dir>`** nhận thư mục như `init <dir>` (trước đây lỗi usage, phải dùng `-t`).
- **`AGENTS.md`**: trả lời theo ngôn ngữ người dùng (khớp essentials, bỏ "English by default"); §8.1 nói rõ khoanh theo tenant là cho hành vi khác nhau, còn lỗi mọi caller gặp thì sửa một lần ở gốc.

### Lazy senior (from [ponytail](https://github.com/DietrichGebert/ponytail), MIT)
- **Thang 7 bậc nằm trong luật luôn nạp.** `rules/essentials.md` có mục "Lazy senior: build less, never check less": hiểu xong mới leo YAGNI → tái sử dụng → stdlib → native → dependency đã cài → một dòng → tối thiểu; bug sửa một lần ở hàm dùng chung; không bao giờ cắt validate, bảo mật, a11y, hiệu chỉnh phần cứng, oracle hay gate. `core-rules.md` §4 có bản đầy đủ. Không lấy luật "one-liner không cần test" của ponytail.
- **Post-fix gate cảnh báo, không chặn:** dependency mới được thêm (Gradle, version catalog, `package.json`, Unity `Packages/manifest.json`; nâng version không tính) và marker `ponytail:` mới thiếu "khi nào nâng cấp". Chạy cả ở `--staged`.
- **`principal-code-reviewer`** có lens simplicity với 5 tag `delete/stdlib/native/yagni/shrink` và dòng `net: -N`.
- Không thêm hook SubagentStart như ponytail: đo 2026-09-24 bằng `claude -p`, subagent general-purpose đã nhận `AGENTS.md`/`CLAUDE.md` (Explore thì không, nhưng Explore không viết code).

### Proof
- **Không có device thì mở máy ảo rồi mới chụp.** `bin/proof-capture.py` chỉ screencap serial đang `device` và không nằm trong denylist. Serial khai báo offline, hoặc không có máy được phép, thì lệnh mở AVD (`proof.providers.<tên>.avd`; không khai thì máy ảo điện thoại với profile android, `CarConnect` với profile automotive) và ghi `reports/proof-<stamp>.png`. Không chụp địa chỉ chết, không lấy điện thoại đang cắm thay thế.

### Grok
- **Grok uses the same toolkit.** It reads `AGENTS.md` and does not get an adapter, a `.grok/` directory, or its own hook, command or MCP files. `-a grok` only installs that shared `AGENTS.md` (and folds `CLAUDE.md` / `GEMINI.md` / `Agent.md` into it).

### Layout — one instruction file, one agent folder
- **AGENTS.md is the only instruction file.** The installer folds the project's own `CLAUDE.md`,
  `GEMINI.md` and `Agent.md` into `AGENTS.md` (text kept verbatim above the DevKit block, original
  kept as `<name>_old.md`) and removes them; a `CLAUDE.md` link to `AGENTS.md` is just removed.
  Claude Code (2.1.277+) reads `AGENTS.md` when there is no `CLAUDE.md`; Gemini gets
  `context.fileName: ["AGENTS.md"]`. Health fails while a `CLAUDE.md` shadows `AGENTS.md`.
- **Everything agent-related in `.agents/`.** The DevKit is one link `.agents/devkit` (copy mode:
  `AGENTS.md rules/ bin/`); the root `rules/ skills/ commands/` links are removed on re-init;
  `.active-profile.json` moves to `.agents/active-profile.json` (readers take the new path, then the
  old one).
- **Startup context ≤ 60 KB, and actually loaded.** Measured 2026-09-24: every `@` import through a
  DevKit symlink (master AGENTS.md, core-rules, profile RULES.md) was silently skipped — Claude Code
  does not expand an import whose real path is outside the project unless external imports were
  approved. The block now imports three generated real files, `.agents/context/essentials.md`
  (new `rules/essentials.md`), `profile-rules.md` and `rules-index.md` (one line per section of
  `.agents/local/rules/`, with the `sed -n` range to open it) — `scripts/context_sync.py`, run by
  init, `agent-kit profile`, SessionStart and the relink hooks; git-ignored. Verified with real
  `claude -p` sessions. Three migrated projects: 55 / 49 / 50 KB (were 116–220 KB estimated, and
  the DevKit rules in them were never loaded).
- **Claude auto-memory in the repo:** `autoMemoryDirectory` → `.agents/local/memory/claude-auto/`
  (`scripts/claude_memory.py`); notes of the old per-user folder are moved in and indexed in `MEMORY.md`.
- **Relink hooks are repair-only:** `relink_check.py` re-creates missing untracked links and never
  runs the installer, never changes the profile or a tracked file; skipped in linked worktrees, on
  file checkouts and in trees without a 1.3 install (a worktree checkout had re-installed with the
  wrong profile).
- Fixes found on the way: `.agents/devkit` (a link to the DevKit root itself) was not written to
  `.git/info/exclude`; a first Gemini install left `.gemini/settings_old.json`.
- **Prompt hook names the matching project rule:** `scripts/rule_context.py` matches the request
  against `.agents/context/rules-index.md` (accents folded, prefix match for 4+ letters) and prints
  up to 3 sections with their `sed -n` range; runs in parallel with `enrich_context.py`, so the
  hook stays one python start (~75–100 ms).
- **Hook protections recovered from OfficeReader's originals** (its 249-point contract suite: 217 →
  232 on the DevKit hooks; the rest are deliberate differences or OR-only): `bash_write_ledger.sh`
  restored and registered on Pre/PostToolUse Bash (session time windows in
  `.claude/audit-gate/bash_write_ledger.tsv`, no command text); `review_gate` re-arms after its
  3-attempt release when new unreviewed code appears; `security_gate` no longer flags camelCase
  `clearText`; `testsourceset_gate` keeps Kotlin written from Bash in scope and no longer blocks a
  session that wrote no Kotlin for another session's broken module; `test_evidence_gate` anti-loop
  honours per-suite disclosures and ignores other sessions' red runs. New
  `hooks/tests/or_ported_contract_test.sh` (72 points), part of `agent-kit test`.
- **post-fix gate `vacuity_revert` is off by default** (`VACUITY_REVERT=1` turns it on for a
  manual run): it rewrote production files in the working tree to re-run an impacted PASS, so a
  killed Stop hook could lose the fix, and it failed every behaviour-preserving change. The vacuity
  proof is `scripts/red_proof.py` (sandbox copy, GREEN control, off the Stop path).
- **Skills:** generic rules from OfficeReader's old skill copies merged into deep-module-design,
  deprecation-migration, documentation-and-adrs, grill-plan, incremental-implementation,
  observability-instrumentation and writing-skills.


### Living regression checklist
- **Bugs and requirements reach the checklist by themselves.** A bug prompt → `REPORTED` row (UserPromptSubmit);
  `agent-kit bugs add|link|drop`, `agent-kit req add|link|drop` (criteria locked by hash); Stop links a bug to its test
  when the evidence is one-to-one (🤖), else holds once with the command; a REPORTED row untouched 14 days → 💤.
- **No PASS without a RED-proof:** `scripts/red_proof.py` runs the bug's test in a sandbox without the fix (must fail and
  name the test) and with it (must pass) — `UNPROVEN` / `VACUOUS` otherwise; past bugs by reverting the fix commit named
  in their evidence. `FLAKY` (post-fix-gate re-runs a failure once), `STALE` (watched files changed since the PASS;
  light suites re-run in the background at session start).
- **Evidence:** every real run's output in `.agents/evidence/<test>/` (last 10, git-ignored), linked from the row.
- **Dashboard `.agents/CHECKLIST.md`** (old name is a link): one HUD line with the safe %, alert zone first, modules
  folded at 100% PASS, bug ledger, `.agents/archive/BUG_ARCHIVE.md` for bugs stable ≥ 30 days and ≥ 30 commits.
- **`.agents/INBOX.md`**, the user's to-do lines (never written by the agent), and the prompts "làm inbox" / "làm backlog".
- **`agent-kit nightly`**: local LaunchAgent — every suite, pending RED-proofs, a notification only when a row turns red,
  a weekly one-line report.
- **test_evidence_gate:** ANTI-LOOP "deliberate red" disclosure is per testcase again (a quoted "RED-check", an edited
  test file or another suite's disclosure no longer silences it), and only this session's runs count (bash_write_ledger windows).

### Gates
- **post-fix gate — dependency check (6th static check):** floating versions (Gradle `1.+` /
  `latest.release`, version catalogs, npm `latest`/`*` outside `peerDependencies`, Cargo/Poetry `*`,
  pubspec `any`, Maven `LATEST`/`RELEASE`) and plain-`http://` / TLS-off package sources (Gradle
  `maven { url }`, `allowInsecureProtocol`, `.npmrc`, pip `--index-url`/`--trusted-host`, Podfile
  `source`, pom `<repository>`) now REJECT. Rules are anchored to declaration shapes: license URLs,
  loopback repositories, caret ranges and test fixtures are not flagged.
- **post-fix gate `--staged`:** the 6 static checks on the staged blobs (not the working tree), for
  pre-commit use. Clean is exit 2 (tests not run), never PASS.
- **`agent-kit githooks install|uninstall|status`:** git pre-commit hook running `--staged` on every
  commit, also outside any agent. Honours `core.hooksPath`; never overwrites a project's own hook
  (prints the line to chain it); fails closed when the gate gives no verdict. `agent-kit uninstall`
  removes it.
- **post-fix gate `--json` `findings`:** every static finding also comes as
  `{category, rule, message, file, line, snippet}`, so an agent can go straight to `file:line`
  instead of parsing the colored log. Secrets carry their line but never a snippet.
- **`hardware_safety_gate.sh` device policy:** an adb command that reaches a serial on the denylist
  (`ADB_DENY_SERIALS`, `~/.config/universal-agent-devkit/adb-denylist`, `<repo>/.adb-denylist`) or
  outside a non-empty allowlist (`ADB_ALLOW_SERIALS`, `adb-allowlist`, `.adb-allowlist`) is refused
  (exit 2). Without `-s`, the serial adb would pick (`-d`/`-e`/`-t`, `ANDROID_SERIAL`, the only
  device online) comes from `adb get-serialno`; an unresolvable one (`$VAR`, adb timeout) is
  refused. Host-only subcommands (`devices`, `connect`, `kill-server` …) are never checked. Keep
  personal serials in the per-user file, not in the repo. No policy set = no change.
- **`adb-safe-exec.sh`:** checks the device policy against the serial it actually picks (one device
  plugged in may be a personal phone). On a native crash it keeps the whole tombstone that
  debuggerd logged since the command started (never an older one) and, with `--symbols DIR` /
  `ANDROID_SYMBOLS` plus `ndk-stack`, prints it decoded to function and `file:line`; otherwise
  the raw `#NN pc` frames. Refuses to run when a device policy is set but the gate is missing.

### Memory
- **`agent-kit learn "<title>" --cause=… --rule=…`** (`bin/instincts.py`): adds a lesson to
  `.agents/instincts.md` under the next `[INSTINCT-NNN]` id, refuses a title already recorded
  (`--force` to add anyway), escapes Markdown, and refuses to write through a link into the DevKit.
  `post-fix-gate --record-lesson` uses the same writer, so it no longer stamps `[INSTINCT-AUTO]`.

### Install
- **Project-tier rules are no longer silent:** the rule files moved to `.agents/local/rules/` are
  listed as `@.agents/local/rules/<file>` imports in the DevKit block of `CLAUDE.md`, `GEMINI.md`,
  `.cursorrules`, `CODEX.md` and a project's own `AGENTS.md`, refreshed on every install (dated
  copies left out). `AGENTS.md` §4 says how they rank: they add project rules; where one
  contradicts §6 or `rules/core-rules.md`, the DevKit rule wins and the conflict is reported.
- **Project tier `.agents/local/` replaces the 1.1.0 `commands_old/`, `skills_old/`, `agents_old/`,
  `hooks_old/` backups.**
  DevKit is the core: a project skill/command/agent/hook with a DevKit name moves to
  `.agents/local/<kind>/<name>` and the DevKit item is installed. The folder is committed (not
  git-ignored), never written by later installs, and its items with a free name are linked back into
  the agent folders (relative links); when a DevKit update later claims such a name, the DevKit wins
  and the project's copy stays in place, inactive. In copy mode an edited DevKit copy keeps only the
  edited files there (a later edit gets a dated folder, never overwriting the first); root `rules/`
  edits land in `.agents/local/rules/` instead of `rules_old/`. `list-old` shows active/shadowed items;
  `restore-old --apply` puts items back and removes consumed ledgers and empty folders. Top-level
  `*_old` snapshots (`CLAUDE_old.md`, …) are unchanged. Existing `*_old` folders from earlier installs
  are not migrated.
- **Root `rules/`, `skills/`, `commands/` owned by the project are no longer skipped** (1.1.0 left them
  in place without the DevKit one, so DevKit paths like `@rules/core-rules.md` broke). Agent material
  (`*.md`, `SKILL.md` folders) moves to `.agents/local/<dir>/`; a source-code dir (e.g. `commands/build.js`)
  stays and gets every DevKit item placed inside it (a same-named file moves to the tier). `uninstall`
  removes those placed items. Fixed on the way: `has_user_content` leaked its loop variable `item`.

- **`bin/quick-install.sh` re-runs update instead of nesting.** The first run moved
  `universal-agent-devkit/` out of a temp clone and deleted the clone, so `~/.universal-agent-devkit` had
  no `.git`; a second run cloned again and `mv` put the new copy *inside* the old one — never updated.
  Now `~/.agent-workbench` is a sparse git checkout of only `universal-agent-devkit/` (re-runs `git pull
  --ff-only`, local edits skip the update) and `~/.universal-agent-devkit` is a stable link to it, so
  existing CLI/project links keep working. An old non-git copy is kept as `.old-<time>`;
  `DEVKIT_LOCAL_SOURCE` links a local checkout in place instead of copying the whole monorepo.
  `tests/test_quick_install.sh` covers it against a local remote.

### Automation (what runs without the model choosing to)
- **Regression gate actually runs.** `regression_gate.sh` never looked at
  `.agents/regression_matrix.active.json` (what `agent-kit profile` writes), so the Stop-time regression
  run was silently skipped on every real project. It now reads it first; profile matrices marked
  `"enforce_as_is": true` (web, backend — they auto-detect the project's own runner) are enforced as
  installed; a copy-mode hook finds the gate via `$DEVKIT_ROOT` / `~/.universal-agent-devkit`, and a
  missing gate is reported once per session instead of skipped silently.
- **"Đã fix" is satisfiable.** `test_evidence_gate.sh` check 7 accepted only a multi-lens-audit workflow
  result the installer never ships, so every true "fixed" claim was blocked. It now also accepts the
  paired RED→GREEN the rules require, seen in the session's own tool results: a test run that failed
  before the last source edit and one that passed after it (npm/jest/pytest/cargo/go/gradle…). A green
  run alone still blocks.
- **The agent cannot skip the pre-commit gate:** `block-dangerous-git.sh` blocks `commit|push
  --no-verify`, `commit -n`, `git -c core.hooksPath=…` and `DEVKIT_PRECOMMIT=0 git commit`. `agent-kit
  init` installs the pre-commit gate in git projects (`--no-githooks` to skip).
- **`git restore <file>` is allowed after an automatic backup** to `.claude/audit-gate/restore-backup/`,
  so the agent can undo its own bad edit without costing uncommitted work; `.`, directories, globs and
  unknown options stay blocked.
- **New hooks `session_context.sh` (SessionStart) and `prompt_context.sh` (UserPromptSubmit):** a session
  starts with the profile, the line-numbered map of `.agents/instincts.md` (the index is regenerated
  above 20 KB instead of loading the file) and the regression-checklist state; every request gets the
  matching traps with their `sed -n` range, intent-specific requirements and, for a bug fix, the
  RED→GREEN rule. Questions and chit-chat get nothing. `enrich_context.py` ranks traps (stopwords and
  syllables common to many entries ignored, intent terms added, template/commented entries skipped)
  and has `--compact`.
- **Review and comment checks follow the profile:** `review_gate.sh` and `comment_claim_guard.sh` use the
  active profile's new `source_extensions` (`hooks/devkit_profile.py`) instead of Kotlin/Java only —
  `.ts` on web, `.swift` on iOS, `.py/.go/.rs` on backend, every language without a profile.
  `open-code-review` counts as a review; the block message names the reviewer the DevKit installs.
- **Codex, Gemini CLI and Cursor get the gates too:** `hooks/agent_bridge.sh` translates their hook
  protocols; `scripts/agent_hooks.py` registers session/prompt context, the git & device guards and the
  Stop regression run in `.codex/hooks.json`, `.gemini/settings.json` and `.cursor/hooks.json` (only
  entries running the bridge are ever touched; JSONC files are left alone). `agent-kit uninstall`
  removes them. Transcript-based gates (review, test evidence, claims) stay Claude-only.
- **Regression matrix from the project's own runner** (`scripts/matrix_detect.py`, `agent-kit matrix`):
  when the profile ships only an illustrative sample (android, ios, universal, …), `agent-kit profile` /
  `init` writes a matrix that runs what the project really has — `./gradlew testDebugUnitTest` / `test`,
  `swift test`, the package.json test script via pnpm/yarn/bun/npm, pytest, `go test ./...`, `cargo test`,
  flutter/dart — watching every source file of the profile. The post-fix gate trusts it uncommitted only
  while byte-identical to a fresh generation (edit `exit 1` → `true` and it becomes UNVERIFIED); an edited
  one is kept as `*_old` on regeneration; `uninstall` removes it while unchanged.
- **RED-check beyond Kotlin/Java:** a test file written this session in JS/TS, Python, Go, Swift, Dart or
  Ruby that ran green must have been run red after its last edit (runner output naming the file when the
  runner names files), mutate/restore pairs handled as for the JVM.
- **Lesson reminder:** after a proven fix ("đã fix" backed by RED→GREEN or workflow proof) with no
  `agent-kit learn` / `--record-lesson` in the session, the Stop is held once with the command to run;
  the next stop passes. `LESSON_REMINDER=0` turns it off.
- `agent-kit index-memory` defaults to the current project's `.agents/instincts.md`, not the DevKit's.
- **Found by a 100-scenario end-to-end simulation, fixed:** a passing `node --test` run ("ℹ fail 0")
  and a test named "shows error message" read as RED (the failure regex was case-insensitive), so a
  correct TDD flow on a Node project was held forever; `agent-kit learn` called through a quoted path
  did not count as a recorded lesson; chit-chat ("cảm ơn…", "thời tiết…") pulled in unrelated traps —
  with no intent detected, a trap now needs a strong match (3+ points).
- **Found by a 100-scenario Android/iOS simulation, fixed:** the device gate now blocks `adb shell pm
  uninstall|disable-user|hide` of system packages (SystemUI, GMS, vendor), `fastlane match nuke`,
  `security delete-keychain|identity|certificate`, removing provisioning profiles / keychains and
  `xcrun simctl erase|delete all`; the post-fix gate rejects committed `local.properties` /
  `keystore.properties` (core-rules §1), SwiftPM dependencies on a `branch:` and secrets in property
  lists (`<key>API_KEY</key><string>…</string>`, `$(BUILD_SETTING)` references allowed); prompt context
  recognises "giật", jank, recomposition, memory leak / retain cycle, TestFlight / App Store.
- **Fast path in the Bash gates:** `block-dangerous-git.sh` and `hardware_safety_gate.sh` read the
  command with a bash builtin regex and allow it at once when it has no trigger word
  (case-insensitive) and no backslash, quote, `$`, backtick or glob character — ~73 ms and ~91 ms per
  Bash call down to ~5 ms for `ls`, `npm test`, `./gradlew …`. Anything else still goes to the full
  parser. Found while testing it and fixed in the parsers: `GIT reset --hard`, `/usr/bin/g?t …`
  (git guard) and `ADB remount`, `a?b remount`, `a""db remount`, `Fastboot flash`, `RM -rf /system`
  (device gate) got through — macOS resolves upper-case names and the shell expands globs/quotes.
- **`agent-kit clean [path] [--days=N] [--apply] [--old-installs]`** (`scripts/devkit_clean.py`):
  removes hook logs, per-session state, `restore-backup/` copies and `adb-safe-exec/` evidence in
  `.claude/audit-gate` older than N days (default 14), trims logs over 5 MB to their last 2000 lines;
  `--old-installs` also removes old `~/.universal-agent-devkit.old-*` copies. Dry-run unless
  `--apply`; never touches code, `.agents/` or `.gitignore`.
- **Found by a 100-scenario Web/Backend simulation, fixed:** the device gate now also holds
  irreversible release / infrastructure / data commands for the user (`!` prefix): `npm|pnpm|yarn
  publish`, `vercel|netlify --prod`, `firebase deploy`, `prisma migrate reset`, `rails db:drop`,
  `DROP DATABASE|TABLE` / `TRUNCATE` via a database CLI, MongoDB drop, `redis-cli FLUSHALL`, `kubectl
  delete namespace|pv|pvc|--all`, `terraform|pulumi destroy`, `helm uninstall`, docker volume removal,
  `aws s3 rm --recursive` (fast-path triggers extended; the block message no longer says "hardware"
  only). The post-fix gate rejects npm `_authToken` in `.npmrc`, passwords inside connection URLs
  (`postgres://user:pass@…`; placeholders like `password` / `${DB_PASS}` allowed) and private SSH key
  files (`id_rsa`, `id_ed25519`, …). Prompt context has a SECURITY intent (XSS, CSRF, SSRF, injection,
  auth bypass …) that points to `security-checklist`.
- **Monorepo test runners** (`scripts/matrix_detect.py`): first-level folders with their own runner
  (`CarConnect/gradlew`, `PhoneConnect/gradlew`, `PCConnect/go.mod` …) each get a rule that watches only
  that folder (every common source extension — modules may differ in language) and runs `cd <folder> &&
  <runner>`, so a change runs only the suites it can affect; before, the root reported "no test runner"
  and the regression gate stayed off for the whole monorepo. Folders the root runner covers (pnpm/yarn/
  npm workspaces, Cargo workspace, Gradle settings include) stay with the root; `node_modules`, build
  output and hidden folders are skipped. Profiles web/backend use this per-module matrix too when the
  root has no runner of its own (their root-only sample would fail every stop).
- `post-fix-gate.py`: the `.env` rule is an explicit `ENV_FILE_PATTERN` instead of "the last entry of
  FORBIDDEN_SECRET_FILES", so adding a forbidden-file rule can no longer disable the `.env` value scan.
- **`agent-kit worktree add|diff|remove|list`** (`scripts/worktree.py`): one step for AGENTS §7.1 —
  `add <path> [branch]` creates the worktree (branch default `feat/<folder>`), copies the main
  checkout's git-ignored local config (`.env*`, `local.properties`, `google-services.json` …) and
  installs the DevKit with the main checkout's profile, agents and mode, then records that set-up
  (path + content fingerprint) in the worktree's own git dir. `diff <path>` prints the worktree's
  commits and uncommitted work as one patch with the DevKit set-up left out — the documented
  `git add -A | git apply --3way` carried the DevKit files, which already exist in the main checkout,
  and the apply failed. `remove <path>` refuses while an uncommitted change is not in the main
  checkout byte-for-byte; the branch is kept.
- **Fixes from migrating three real projects (OfficeReader / android, GeelyEx2 / automotive,
  Goods-Triple-Shelf-Match-3D / game):**
  - Injected block (CLAUDE.md / AGENTS.md / CODEX.md / .cursorrules):
    - The DevKit master rules now reach the agent in a project that keeps its own AGENTS.md: they
      are linked at `.agents/devkit/AGENTS.md` and imported from there. `@AGENTS.md` imported only
      the project's file.
    - The active profile's rules are imported through `.agents/active-profile/RULES.md`, a new
      stable link in every profile that follows `agent-kit profile` switches. Before, `rules_file`
      was never imported.
    - The gate command no longer points at `bin/post-fix-gate.py`, which is not installed in
      projects.
    - A CLAUDE.md that links to AGENTS.md gets one block, and AGENTS_old.md is still made.
  - Installer:
    - Relative links moved into `.agents/local/` are re-pointed; they used to dangle.
    - Project-tier rule files that are links are imported too, once per real file.
    - `list-old` shows imported rules as active.
    - A project-tier skill gets a `/name` command, so Claude Code can reach it.
    - `.claude/hooks/` gets only hook scripts; old `tests`/`hooks.json` links are removed.
    - A new DESIGN.md comes from the chosen profile.
    - The universal instincts template no longer ships voice-assistant traps. They moved to that
      profile as VOICE-06..08.
    - Unity projects and monorepos whose runners sit in first-level folders are auto-detected
      (domain game / android).
    - A project `.gitignore` that hides `.agents/` is reported, with the fix.
    - A curated `.agents/regression_matrix.active.json` stays active on re-init or a profile
      switch. The fresh one is written to `regression_matrix.generated.json`; before, a re-init
      renamed the curated matrix to `*_old`.
  - `scripts/merge_json.py`: under `mcpServers`, a list the user already has (`args`) is kept.
    Before, it was unioned element by element, so npx got stray arguments on every re-init.
  - `scripts/matrix_detect.py`:
    - Detects Unity (EditMode through the profile's `unity-batch.sh`) before .NET.
    - Detects Android via version-catalog aliases, convention plugins or a module manifest.
    - Test tasks are named only when the build files prove they exist: `testBuildType` →
      `:m:test<X>UnitTest`, productFlavors → `:m:test`, KMP → `testAndroidHostTest` / `jvmTest` /
      `allTests`. Plugins declared `apply false` are ignored.
    - A module's `includeBuild` composites are watched by its rule.
    - A Gradle build with no test sources gets no rule of its own (zero tests would pass green).
  - `post-fix-gate`:
    - A matrix test may declare `untested_exit` (`unity-batch.sh`: 2 = no Editor). That result is
      UNTESTED, exit 4: never PASS, never a failing test. `regression_gate.sh` lets the stop through
      with a "not a PASS" warning, once per change.
    - UNCOVERED follows the profile's `source_extensions` and skips `docs/`, `.agents/`, `.claude/`.
    - The project name falls back to the active profile, not "Universal Application".
    - `regression_gate.sh` says once per session when the gate is off because the matrix is only a
      sample.
  - `agent-kit health --run-tests`: a red suite is FAIL (exit 1), whatever the score.
  - `agent-kit index-memory` defaults to `$CLAUDE_PROJECT_DIR`.
  - `instincts.py`: the check command is rendered as pasteable inline code.
  - `workflows/multi-lens-audit.js`: takes a caller-supplied `nowMs`. The Workflow runtime forbids
    `Date.now()`, and every run failed with INTERNAL_VALIDATION_ERROR.
  - Skills `qc`, `security-checklist`, `deploy`, `unity-gc-audit`, `qa-visual`: project-specific
    leftovers (Supabase RLS, XLSX gate, `scripts/qa` paths) generalised, and paths the DevKit does
    not ship removed.
  - Prompt context: a lone Vietnamese syllable scores half, and an adjacent-word phrase match
    scores in full. On the three projects' 292 own traps, recall from 8 words of the symptom went
    from 288 to 291, with the same amount of noise.
- **`agent-kit bugs import <table> [--dry-run]`** (`bin/regression_checklist.py import`): past bugs
  enter the regression checklist from a tab- or `|`-separated table
  (`bug_id | title | severity | fixed? | module | test_id_or_NONE | evidence`).
  - A bug is never PASS on import. It is one of:
    - NEEDS_TEST: no test.
    - NOT_IN_MATRIX: a test the gate never runs.
    - NOT_RUN: linked to a matrix test that has not run since the import or link.
    - OPEN: not fixed.
  - Only a real gate run of its matrix test after that sets PASS/FAIL.
  - `regression_checklist.md` and SessionStart show how many bugs no regression test guards.
  - Re-importing updates the rows and keeps their results.
- **Static gate, every layer** (empty catch, raw log, placeholder, performance, dependency, secrets):
  a finding whose text is already in HEAD (or the `--diff` base), counted per occurrence, is a
  warning with `file:line`. It no longer blocks a commit that merely touches the file.
- `profiles/game/scripts/unity-batch.sh` restores the Editor's PlayerPrefs domain after every run
  (macOS; `UNITY_KEEP_PREFS=1` to keep the run's writes).
- **Fixes from auditing the three migrated projects end to end:**
  - Secrets:
    - A secret whose exact text is already in HEAD (or the `--diff` base) was not introduced by the
      change, so it is now a warning with `file:line`. It used to be a REJECT on every stop and
      commit touching that file, forever (a public Supabase anon key).
    - A new secret is still REJECT, now with `file:line`.
    - The Stop block text lists the static findings with their location.
  - Symlink mode: the machine-local DevKit links are written to `.git/info/exclude`. Before, 80–120
    of them showed as untracked in `git status` and were one `git add -A` away from being committed.
  - Guards:
    - The device guard also checks the `replicant-mcp` MCP tools (adb-shell, device selection …),
      which bypassed it.
    - A destructive-`rm` guard blocks recursive+force deletes of the project root, a top-level
      source folder, or paths outside the project, in any flag spelling. Build outputs, /tmp and
      single files are allowed. It covers Claude Code and, through the bridge, Codex / Gemini / Cursor.
  - Other agents:
    - Codex reads AGENTS.md as plain text. The DevKit block now tells it which rule files to open.
    - Gemini gets a generated `GEMINI.md`; in symlink mode the DevKit folder is added to
      `context.includeDirectories`.
    - Cursor gets the always-applied `.cursor/rules/universal-agent-devkit.mdc`.
    - `uninstall` removes all three.
  - Profiles filter MCP servers and agents: a game project no longer gets the Android MCPs or
    `android-principal-architect`, and a server whose command is not on PATH is not added.
  - DESIGN.md: a project with its own design system (`*design-system*`, token files) gets a short
    pointer, not the generic token table.
  - Regression gate:
    - An uncommitted matrix that is the only problem lets the stop through, with "commit
      `.agents/regression_matrix.active.json`" once per change. It used to block with a wrong cure.
    - Deleting the committed matrix blocks once per session instead of silently turning the gate off.
    - `"adopted": true` marks a project matrix even when it is identical to a sample.
    - REG-GAME-01 and REG-GAME-02/03 declare `untested_exit: 2`.
    - Stale UNCOVERED rows are pruned, and none are recorded when the gate does not trust the matrix.
  - SessionStart reports the real matrix state: none, sample, untrusted (with the cure) or trusted.
  - `health` checks the project's own wiring: registered hooks exist, no broken links, every
    `@`-import of the block resolves, the gate trusts the matrix (else FAIL: no regression test
    runs), and no DevKit link leaks into `git status`.
  - Test evidence knows Unity: unity-batch.sh / unity-test.sh / `-runTests` runs, NUnit
    `<test-run>` XML (`Logs/agent-kit/tests_*.xml`) and antigravity-pm `pm_run` exits.
  - `testsourceset_gate.sh` compiles `compile<TestBuildType>UnitTestKotlin`.
  - Re-init raises a DevKit hook's timeout to the DevKit's value (it kept an old 180 s).
  - Prompt context:
    - Defect wording ("bị xoá/mất", "không chạy", "sai") is a bug fix, not a migration.
    - Identifier parts count (DocxEditor → docx), so the XXE trap surfaces for DOCX/XML prompts.
    - A lone Vietnamese phrase no longer pulls an unrelated entry.
    - The instincts index fits 20 KB, skips commented-out templates, and its `sed` paths work from
      the repo root.
  - `instincts.py`: only `<` is escaped (as `&lt;`), so identifiers and `inline code` stay
    greppable. `\<!--` would still have hidden the entries after it from the matcher.
  - Smaller fixes:
    - `githooks install` next to a project's own hook says to insert the gate line after the
      shebang: an appended line can sit after `exit 0`.
    - The QA script paths of the Android skills work in projects of any profile.
    - `review_gate` does not count symlinks as code to review.
    - The `/audit-gate` and `/profile` commands have descriptions.
- **`agent-kit learn --from-json FILE [--dry-run]`:** imports a list of lessons in one run (e.g. old
  memory an agent classified): only `"verdict": "INSTINCT"` items of this project, each with its
  `found_on` date and a `Nguồn/Source` line; titles already recorded are reported, not added again,
  so the import can be re-run.
- **`agent-kit completion bash|zsh`** (`completions/agent-kit.bash`): tab completion for commands,
  profiles (read from `profiles/`), sub-actions and flags; `eval "$(agent-kit completion bash)"`.
- **Fixed: `agent-kit` / `agent-install` through their `~/.local/bin` links** (quick-install,
  `install-global`) took the link's folder for the DevKit (`~/.local`) — every command that reads
  DevKit files failed. Both now follow links first; the quick-install test runs `list` and
  `agent-install --help` through the links (it ran only `help`, which reads no file).
- post-fix gate: bare AI / cloud tokens are caught by their prefix even in a variable not named
  key/token — Anthropic `sk-ant-…`, OpenAI `sk-proj-…`, Hugging Face `hf_…`, Stripe `sk_live_`/`rk_live_`,
  GitLab `glpat-…`, npm `npm_…`, SendGrid, Supabase `sbp_…`, Groq `gsk_…`, Replicate `r8_…`. Raw
  console output is no longer flagged in command-line code under `bin/`, `cmd/`, `tools/` (was
  `scripts/` only). Antigravity sessions untouched for `POSTFIX_GATE_BRAIN_DAYS` (default 7) are not
  read for proof images.
- `testsourceset_gate.sh`: a monorepo without `./gradlew` at the root (e.g. `android/gradlew`) is no
  longer skipped — each changed `.kt`/`.java` is compiled with the nearest `gradlew` above it, module
  path relative to that build.
- Hook latency on long sessions: `churn_guard.sh` walks the transcript backwards and stops at the last
  evidence call; `precode_gate.sh` skips lines without the file's name (or a Read) before parsing
  them; `prompt_context.sh` runs one python process instead of three (`enrich_context.py --hook`
  reads the payload itself); `read_ledger.sh` re-reads its ledger only past 512 KB. Measured on an
  8 MB transcript: churn 68 → 42 ms, precode 59 → 46 ms, prompt context 74 → 34 ms.
- `AGENTS.md` §7.1: `agent-kit worktree` for create / bring back / clean up; `agent-kit init` in a
  worktree can add the DevKit `.gitignore` block (the text said it changes no tracked file).
- Docs: `AGENTS.md` §7 lists what each platform actually enforces; §8.2 and `core-rules.md` §16 mark
  hook-enforced steps `[hook]` and drop the "Zero Manual Effort" / "CỔNG BẮT BUỘC" claims no hook backed;
  §2.3 asks for real evidence (screenshot for UI, test output for CLI/backend) instead of a PASS
  screenshot for every report.

### Android
- **`profiles/android/scripts/qa/adb-safe-exec.sh`:** runs an adb command and FAILs on error text adb
  prints with exit 0 (`Error type 3`, `Failure [`, `INSTRUMENTATION_FAILED`) and on a FATAL
  EXCEPTION / ANR / fatal signal of the package in logcat since the command started (device clock).
  No or several devices ⇒ exit 3, never a pass; commands `hardware_safety_gate.sh` blocks are refused.
- **`anr-logcat-triage.sh`:** no online device is now exit 3 (UNVERIFIED) instead of exit 0.

### Docs
- **`AGENTS.md` §7.1 — parallel agents, one git worktree each:** how to create one (Claude Code
  `isolation: "worktree"` / `EnterWorktree`, else `git worktree add ../<repo>-<task>`), what a new
  worktree lacks (untracked local config, a symlink-mode DevKit install → `agent-kit init` inside
  it), one device per agent at a time, acceptance only on a gate run inside the worktree with
  `CLAUDE_PROJECT_DIR` pointing at it, bringing the result back as a patch unless commits were
  asked for, and which clean-up steps are the user's (the git guard blocks `--force` removal).

## 1.1.0 — 2026-09-23

A PO + QA review of the whole DevKit found 58 verified defects (1 critical, 13 high) and a gap
between what the docs claimed and what the code did. This release fixes them.

### Security / gates
- **post-fix gate:** test commands are read from the regression matrix at `HEAD`; a matrix or an
  existing test edited in the same change is UNVERIFIED, never PASS (previously an agent could turn
  `exit 1` into `true` and pass). Secret scan whitelists only exact example suffixes, detects AWS/GitHub/
  Slack/Google keys, JWTs, private keys, base64 and unquoted values; test files are recognised by
  directory/suffix, not by the substring "test". `--diff` values starting with `-` are refused. Lessons
  are recorded only after a PASS. DevKit-installed links no longer count as user changes. Output labels
  each section BLOCKING or REMINDER.
- **hooks:** `block-dangerous-git` catches subshells, `if`/`{}` blocks, `timeout`/`nice`/`sudo -u`/`watch`/
  `find -exec`/`xargs` wrappers, `$var` commands, git aliases and `os.system`/`subprocess`; `git restore
  --staged` is allowed. `hardware_safety_gate` handles flags before subcommands, `rm -fr /system`,
  `dd of=/dev/…`, and fails closed on bad JSON. `security_gate` only accepts a real review (not `echo
  security-check`) and sees Bash writes to sensitive files. `precode_gate`/`security_gate` fail closed
  without python3; the rest warn. Stop gates block one re-stop, then release with a logged warning.
  Hooks create `.claude/audit-gate/.gitignore`. `contract_facts_test.sh` rewritten for this repo.

### Installer / CLI
- `agent-kit init [path] [opts]` works with a path and with flags, and without a TTY.
- Unknown options, profiles, modes and languages exit 2 before writing anything.
- A project's own `commands/`, `rules/`, `skills/` directories are left in place (skipped with a warning)
  instead of being renamed to `*_old`.
- The installer no longer writes into the DevKit checkout; copy mode is honoured by every adapter;
  per-file hash ledger (`.devkit-files`) so upgrades only back up files the user edited; backups of
  commands/hooks go to a sibling `<dir>_old/` (no more `/fix_old` commands); same-second backups never
  clobber each other; `.gitignore` entries are added to git projects; symlink mode warns in git repos.
- `make install` / `agent-kit install-global` also install `postfix-gate`.
- New `agent-kit restore-old [path] [--apply]` puts recorded `*_old` backups back (dry-run by default,
  never overwrites content that is not the DevKit's; recreates install dirs `uninstall` removed).
- New `agent-kit uninstall [path] [--apply]` (`scripts/devkit_uninstall.py`, dry-run by default) removes
  only DevKit content: links into the DevKit, copies still matching `.devkit-files`/`.devkit-copy`,
  DevKit hook entries in `.claude/settings.json`, unchanged DevKit MCP servers, marker blocks, and
  unmodified template files. JSON files are backed up (`*_old.uninstall-<time>`) and written atomically.
  `tests/test_uninstall.sh`: install + uninstall + restore-old gives back the original project.

### Profiles / health / scripts
- `agent-kit profile` writes to the git root of the current directory (refuses the DevKit itself), backs
  up instead of deleting, accepts positional/case-insensitive names and aliases, writes the matrix to
  `.agents/regression_matrix.active.json`.
- `agent-kit health` no longer prints hard-coded test results; tests are "not run" unless `--run-tests`.
- Councils: one list of 10, duplicates removed; profiles reference only existing councils and MCPs
  (Unity/Blender MCPs are listed as external for the game profile).
- `voice-assistant` profile gained `DESIGN.md` and `instincts.md`.
- Linters are documented as regex-based, support multi-line signatures and exit 2 on a missing path.
- The `scripts/audit_*` "agent" scripts are relabelled as grep-based self-consistency checks.
- **New profiles `web` and `backend`** (rules, `DESIGN.md`, `instincts.md`, regression matrix that
  detects pnpm/yarn/bun/npm, go, cargo or pytest and fails when no runner is found). `-y` maps the
  detected web/backend domain to them; aliases `frontend/react/nextjs` and `server/api`.
- **Skills filtered per profile:** `profile.json` takes `exclude_skills` (or an allow-list `skills`);
  only allowed skills and their commands are linked. universal/web/backend/ios drop the Android/Unity
  skills, game drops the Android ones.
- **i18n:** installer, adapters, `agent-config`, `agent-health` and the post-fix gate print English or
  Vietnamese: `--lang` > `$DEVKIT_LANG` > `lang` in `.active-profile.json` > `vi`.
- Fixed: the gate did not read `.agents/regression_matrix.active.json` (the new matrix location); an
  uncommitted matrix byte-identical to a DevKit profile matrix is trusted, an edited one is UNVERIFIED.
- `hooks/regression_gate.sh` and `bin/regression_checklist.py` (regression checklist gate) were added in
  a parallel change during this release.
- `profiles/ios/regression_matrix.json` moved from a `checklist` list (silently ignored by the gate) to
  the `rules`/`watch_files`/`mandatory_regression_tests` schema; REG-MEM-01 ran `… || true` and could never
  fail — it now runs `swift test --filter RetainCycleTests`. `test_repo_consistency.sh` checks every
  profile matrix has the schema the gate reads and no test command ends in `|| true`.

### CI (`.github/workflows/devkit-ci.yml` in the monorepo)
- Step names no longer carry fixed counts or retired claims; `actions/setup-node` pinned to a commit SHA
  (v4.4.0); Node 22 (Node 20 is end-of-life; `workflows/*.test.mjs` pass on 20.20.2 and 22.23.2).
- `py_compile` covers `bin/*.py` and `scripts/*.py`; `bash -n` covers `bin`, `hooks`, `hooks/tests`,
  `scripts`, `adapters` and `tests`; a step prints whether ruby (strict YAML frontmatter check) exists.

### Catalog / docs
- 10 documented aliases now exist (`/adr /android-qa /deprecate /enrich /grill /logging /module-design
  /postfix-gate /skill-author /step`).
- `skills/giao` frontmatter is valid YAML; references to another repo's `.Codex/` and `rulebook/` removed;
  `qc` detects the build tool for non-Gradle projects; `qc`/`deploy` state their Android scope.
- README EN/VI: Quick Start moved to the top; counts and claims corrected ("8-layer" gate, "AST linter",
  "50 agents", fixed test totals removed); new sections: which QA command when, Team/CI, uninstall/
  restore, troubleshooting.
- MCP npm packages pinned to exact versions.
- Added `LICENSE` (MIT) and this changelog; plugin version 1.1.0.
- New `tests/test_repo_consistency.sh` keeps links, JSON, frontmatter, documented commands and
  documented counts honest; `agent-kit test` also runs `contract_facts_test.sh`.
- **QA ladder / renamed commands:** the QA commands now run as `/plan-tests` (qa-review) →
  `/review-code` (open-code-review) → `/check` (qc) → `/done` (verification-before-completion) +
  `/audit-gate`. **Deprecated:** `/review` → `/plan-tests` (it collided with the agent's built-in
  `/review`), `/qa` and `/test` → `/check`, `/bugs` and `/crashlytics` → `/fix`. The old names are
  kept for this release only as stub commands (marked `<!-- devkit:deprecated-alias -->`, generated by
  `scripts/sync_commands.sh` from `DEPRECATED_ALIASES`) that run the same skill and tell the user the
  new name; they are **removed in 1.2.0**.
- **Rulebook de-duplicated:** `AGENTS.md` and `rules/core-rules.md` (both `@`-imported every session)
  no longer repeat the same sections; each rule lives in one place and the other file points to it.
  No MUST/NEVER rule was dropped.

### Action needed by maintainers
- Local state files are still tracked from earlier commits. `.gitignore` now lists them; untrack them
  once with:
  `git rm --cached .active-profile.json .antigravity-pm.json .claude/settings_old.json templates/regression_matrix.active.json templates/last_postfix_audit_report.md`
- Symlinks committed before this release were absolute; the working tree now uses relative links —
  commit them.

## 1.0.0

Initial release.
