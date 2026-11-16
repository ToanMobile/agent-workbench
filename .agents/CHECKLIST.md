# 🧪 Regression Checklist

**An toàn 1% (5/457)** · ❌ 113 · 🔁 0 · 🚫 0 · 🟡 95 cần chạy lại · ⚠️ 2 cần test · ⚠️ 0 test có thể không suite nào chạy · 🐞 3 chưa sửa · ⏳ 239 chờ · 🚗 0 chờ chạy lặp trên xe · 🟡 REPORTED 22 · ma trận chờ duyệt: không

> Sinh tự động lúc 2026-11-14 19:26:50 — **không sửa tay**. % an toàn = PASS ÷ mọi dòng test/REQ/bug đã xác nhận (REPORTED không tính). PASS chỉ từ lần chạy thật + (bug/REQ) test đã chứng minh ĐỎ.

**Bug không có test hồi quy nào chặn tái phát: 2** (0 chưa có test · 2 có test nhưng gate không chạy)

## 🚨 Cần xử lý (213)

| Trạng thái | ID | Tính năng / Bug | Component | Việc cần làm |
|---|---|---|---|---|
| ❌ TIMEOUT | BUG-20260925-prompt-bao-bug-that-cung-se-khong-con-du | prompt báo bug thật cũng sẽ không còn được ghi nhận nữa -> là sao bug đúng ko fix đi phải tự động ghi nhận chứ | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20260926-dev-kit-lam-tao-branch-push-lung-tung-kh | dev kit làm tạo branch, push lung tung không đồng bộ dẫn tới lệch code, vd geely ex2 hiện có 2 pull chưa pull về dẫn tớ… | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20260928-audit-review-them-geely-ex2-hien-no-bao | audit, review thêm geely ex2 hiện nó báo tôi rất nhiều lỗi vậy có nghĩa là bộ devkit hoàn toàn chất lượng kém để thủng… | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20260928-fix-luon-loi-git-guard-chan-grep-di-ngoa | fix luôn lỗi git guard chặn grep đi ngoài ra đã tối ưu token sử dụng cũng như thời gian chạy chưa ? Đề xuất các phương… | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20260928-push-geely-va-fix-luon-loi-red-proof | push geely và fix luôn lỗi red_proof | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20260928-san-check-luon-chat-luong-dev-kit-workfl | sẵn check luôn chất lượng dev kit workflow có bị lỗi gì ko fix luôn đi | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20260929-audit-review-nguyen-nhan-tai-sao-cac-ses | audit, review nguyên nhân tại sao các sesion cài dev kit chạy rất chậm có lỗi gì hay ko? | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261001-lam-luon-fix-bug-worktree-di | làm luôn fix bug worktree đi | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261001-sua-luon-bug-init-xoa-mcp-server-di | sửa luôn bug init xoá MCP server đi | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261002-agent-kit-health-run-tests-scores-96-100 | agent-kit health --run-tests scores 96/100: agent-kit test runs ~90 test scripts one after another (~19 min), past the 900 s limit health allows | devkit-health | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261002-chay-finagling-running-stop-hooks-8-9-27 | chạy Finagling… (running Stop hooks… 8/9 · 27m 24s · ↓ 46.3k tokens) quá lâu audit, review sửa lại đi Stop hooks… rất h… | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261002-evidence-gate-foreign-xml-nonrunner | test_evidence_gate: a Bash that only names a foreign project (cd && git status) made its fresh XML count as this session's test evidence | devkit | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261002-gate-rejects-a-change-that-moves-a-test | Gate REJECTs a change that moves a test file the matrix names: it runs the base matrix, whose command names the removed path (exit 127), and flags the matrix edit for review | devkit-gate | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261002-proof-gate-reinit-same-profile | proof gate: re-init rewriting the same backend profile counted as a profile switch and demanded a PNG | devkit | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261002-sessionstart-skips-the-checklist-block-a | SessionStart skips the checklist block and the background STALE re-run after the scripts/ regrouping (bin/ and stale_rerun.py paths) | devkit-hooks | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261008-sua-4-loi-kit-phien-office-nho-di | sửa 4 lỗi kit phiên Office nhờ đi | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261009-automerge-refusal-reason-lost | worktree automerge: a commit refused by the repo's pre-commit gate was reported with only the last 500 characters of the gate output, which is the passed-checks footer, never the finding: the worktree stayed unmerged and nobody could tell why (GeelyEx2 giao-tichhop-09-10, base-hoiquy-09-10) | devkit-worktree | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261009-churn-guard-no-fast-path | churn_guard started python on every Edit although it can warn only when the transcript names the file at least N times | devkit-hooks | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261009-comment-claim-docstring-trailing | comment_claim_guard: a claim inside a Python docstring or after code on the same line (# / //) passed while the same words in a full-line comment warn | devkit-hooks | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261009-gate-js-describe-title-false-flag | post-fix-gate: the same it('title') in two different describe blocks flagged a pure append of a JS test as an edited test | devkit-gate | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261009-gate-runner-no-errexit-append | post-fix-gate: any command appended to a shell test runner WITHOUT set -e counted as a pure append, though it decides the exit status over an earlier failure (user decision 2026-10-09) | devkit-gate | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261009-git-guard-bash-c-subst-tee-shell | block-dangerous-git: bash -c "$(curl ...)" and a shell inside >(...) ran generated text that curl \| bash and bash <(...) already refuse | devkit-git-guard | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261009-hardware-find-negated-or-unfiltered | hardware_safety_gate: find ! -name x -delete, -not, and an -o alternative without a filter counted as filtered, so the start point was never judged | devkit-hardware-gate | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261009-hooks-log-dir-process-cwd | 7 hooks (bash_write_ledger, security_gate, proof_gate, regression_gate, test_evidence_gate, review_timing_guard, prompt_context) took the project from the PROCESS cwd when CLAUDE_PROJECT_DIR was unset and created .claude/audit-gate there (a run at / wrote /.claude) | devkit-hooks | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261009-merge-gate-held-vanished-worktree | worktree_merge_gate: a worktree removed by the last Stop's background merge while this Stop decided stayed in the hold list (flaky test_worktree_merge_gate_owner) | devkit-worktree | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261009-review-timing-guard-env-payload | review_timing_guard: the hook payload travelled in an environment variable, so an Edit of a big file (payload past the 1 MiB exec limit) made the shell fail with Argument list too long and the guard never ran | devkit-hooks | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261009-run-impacted-recent-commits-in-sandbox | run_impacted.sh in a checkout with no upstream (every RED-proof sandbox) selected the tests of every commit of the last 6 hours: 25+ minutes per proof instead of the few tests of the reverted file | devkit-tests | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261009-scratch-cleanup-prune-could-delete-a-liv | scratch_cleanup: prune could delete a live idle session's dir and follow a slug swapped for a symlink (TOCTOU) | devkit-scratch-cleanup | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261009-session-lock-a-cp-rc-copy-of-a-checkout | session_lock: a cp -Rc copy of a checkout carried the original's lock and was held by its live holder up to 600 s | devkit-session-lock | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261009-session-lock-an-idle-holder-turn-over-wa | session_lock: an idle holder (turn over, waiting at the prompt) kept the checkout 600 s, other sessions needed /exit | devkit-session-lock | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261009-session-lock-case-only-path | session_lock: a path spelled with other letter case (APFS) fell outside the locked checkout, so the write took no lock and a live holder lost it | devkit-session-lock | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261010-gate-swallows-a-failed-linter-import-and | gate swallows a failed linter import and switches the lint off silently | devkit-guards | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261010-gate-wants-a-regression-test-for-red-pro | gate wants a regression test for red-proof patch files | devkit-guards | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261010-guard-hooks-lose-the-command-that-follow | guard hooks lose the command that follows a comment or a hash inside a word | devkit-guards | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261010-health-reports-100-while-a-tracked-symli | health reports 100 while a tracked symlink points at a missing target | devkit-guards | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261010-matrix-accepts-one-suite-id-with-two-dif | matrix accepts one suite id with two different commands without a word | devkit-guards | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261010-proof-gate-blocks-a-push-turn-whose-4-it | proof_gate blocks a push turn whose 4-item report was already written right after the push | proof_gate | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261010-red-proof-keeps-a-patch-of-any-size-in-a | red proof keeps a patch of any size in a tracked folder | devkit-guards | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261010-regression-gate-re-runs-every-suite-on-a | regression_gate re-runs every suite on a repeated FAIL when one suite cannot run here, ignores local config and age, and sessions erase each other's stored blocks | regression_gate | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261010-session-lock-blocks-read-only-commands-s | session lock blocks read-only commands: stash list and grep naming the gate | devkit-guards | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261010-test-evidence-gate-rebuilds-the-shell-va | test_evidence_gate rebuilds the shell variable table of every earlier command for each command (quadratic, 25 s on a 58 MB transcript) | test_evidence_gate | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261010-test-evidence-gate-treats-a-source-file | test_evidence_gate treats a source file written in a temp or scratchpad dir as the last code edit, so a green run goes stale (36% of 171 real blocks) | test_evidence_gate | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261010-testsourceset-gate-compiles-the-test-sou | testsourceset_gate compiles the test source sets on every unfinished (CHUA XONG) stop | testsourceset_gate | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261011-review-log-py-loses-lines-under-concurre | review_log.py loses lines under concurrent writes, erases damaged lines, reads the model from text, takes older results for newer dispatches and counts implement runs as reviews | review_log | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261012-a-bug-linked-to-a-test-file-git-does-not | a bug linked to a test file git does not track yet stays NOT_IN_MATRIX forever (no regression test counted) | checklist | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261012-a-session-blocked-by-a-held-checkout-sto | a session blocked by a held checkout stops to ask the user instead of making its own worktree | session-lock | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261012-hardware-gate-passes-a-quoted-or-root-gl | hardware gate passes a quoted or root-glob rm on a system partition | hardware-gate | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261012-hardware-gate-passes-ansi-c-or-locale-qu | hardware gate passes ANSI-C or locale quoted rm on a system partition (dollar left glued to the command) | hardware-gate | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261012-hardware-gate-refuses-clearing-adb-scrat | hardware gate refuses clearing adb scratch folder /data/local/tmp | hardware-gate | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261012-regression-gate-blocks-the-stop-on-a-sui | regression gate blocks the Stop on a suite killed from outside (exit 137/143) as if a test failed | regression-gate | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261012-regression-gate-reuse-key-moves-with-age | regression_gate reuse key moves with agent memory notes because devkit_harness.OWN lacks claude-auto (tree_fp already excludes it) | tree-fp | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261012-stop-gates-run-on-progress-replies-whose | stop gates run on progress replies whose only claim is a check mark or a table row | stop-hook | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261012-test-evidence-gate-lets-a-pass-claim-thr | test_evidence_gate lets a pass claim through when an exempted match swallows it, and blocks the Vietnamese cycle name or quoted mentions of its trigger words | test-evidence-gate | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261012-test-session-lock-resolve-compares-bash | test_session_lock_resolve compares bash errno wording that flips with the directory the test is started from (red from the repo root, also on the unpatched kit) | session-lock | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261012-tree-fingerprint-moves-with-agent-memory | tree fingerprint moves with agent memory notes so a green gate receipt is lost | tree-fp | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261012-user-prompt-hook-exits-127-silently-when | user prompt hook exits 127 silently when the hook files are gone, so every guard is off with no warning | hooks | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261013-a-repo-link-to-the-old-scripts-red-proof | a repo link to the old scripts/red_proof.py path is broken since scripts/ was split into groups | installer | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261013-agent-test-approval-claude-transcript | post-fix-gate never read the agent's in-turn test approval in a Claude Code transcript (message.content), so the Stop hook kept asking the user | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261013-merge-gate-folder-deleted-before-stop | worktree_merge_gate passed a worktree whose folder was deleted before the Stop while its commit was not in main | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261013-merge-gate-vanished-worktree-race | worktree_merge_gate held a Stop on a worktree another merge landed, and passed vanished/reflog-only/rewound worktrees whose work never reached main | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261013-opencodereview-never-ran-ocr-review-exit | OpenCodeReview never ran: ocr review exits 1 without an LLM endpoint, nothing reported it, and review_gate ignored OCR | review-gate | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261013-regression-gate-blocks-the-stop-of-a-rea | regression_gate blocks the Stop of a read-only session on the diff of the session that holds the checkout | regression-gate | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261013-relink-check-never-links-a-skill-the-dev | relink_check never links a skill the DevKit gained after the install | relink | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261013-test-approval-from-foreign-records | post-fix-gate approved edited tests from records that are not the agent's approval (queue-operation, Antigravity USER_INPUT, other projects' logs, prose, substrings) | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261013-worktree-gc-deletes-unique-work | worktree gc could delete unique work (unreachable blobs, ignored non-build files, a person's worktree, a live session's worktree) | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-agpm-global-config-guessable-tmp | ANTIGRAVITY_PM_GLOBAL_CONFIG test pin pointed at a guessable path in a shared TMPDIR (kit tests/lib/clean_git_env.sh, MCP tests/helpers.js): a file planted there with giaoDefault/testCommand steered every test | pm-mcp | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-automerge-gate-result-not-object | automerge printed a traceback instead of its JSON line when the gate's last line was JSON but no object | devkit-worktree | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-automerge-untracked-symlink | worktree automerge committed an untracked symlink and the fast-forward replaced main's ignored node_modules/ with it | devkit-worktree | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-budget-cut-forgets-passed-suites | A Stop run that spent GATE_TOTAL_BUDGET_S kept no suite results, so the next Stop on the same content ran every suite again | devkit-gate | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-evidence-outcome-quoted-mention | test_evidence_gate check 7 read a quoted mention of the phrase 'da fix' as an outcome claim | devkit-gate | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-fifo-harness-canary-false-green | test_hook_gitignore_fifo canaries printed a pass when their child never started within the limit (nothing was tested) | devkit-tests | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-fifo-harness-cleanup-kill-gone | test_hook_gitignore_fifo crashed with ProcessLookupError when the leaked canary it cleans up had already ended, skipping every later hook check | devkit-tests | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-fifo-harness-grandchild | test_hook_gitignore_fifo killed only the bash child on its timeout, a grandchild blocked on a FIFO outlived the case for ever | devkit-tests | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-fifo-harness-killpg-eperm | test_hook_gitignore_fifo crashed with PermissionError when killpg met a process group holding only zombies on macOS | devkit-tests | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-gate-recreates-removed-project | gate re-created a worktree folder removed while its suites ran (regression_status.json, INBOX, evidence, journal) | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-guard-shell-norm-fail-open | command guards let through commands hidden behind su -c, adb shell, ssh option values, bash -lc, wrapper option values, a heredoc operator inside quotes or a comment, and device-side rm forms (braces, dot-dot paths, cd then rm, find -delete, tilde) | devkit-guard | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-heredoc-data-false-block | command guards read heredoc data as commands: block-dangerous-git refused a quoted python heredoc whose body held a backtick, hardware_safety_gate walked cat-to-file heredoc bodies as rm commands | devkit-guard | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-lock-file-stale-takeover-race | worktree.py _lock_file (automerge, MAIN_LOCK, worktree add) let two waiters take over a dead holder's O_EXCL lock file together, and gave up at once when the file vanished mid-read | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-ocr-endpoint-rejected-holds-stop | ocr-review failed hard when the OCR LLM endpoint rejected every request (API key over its usage limit), so review_gate held every session's Stop | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-proof-report-label-variants | proof_gate blocked a report that carried all four items under other labels (Nguy co moi, Da lam gi, Chan loi cu, Da fix duoc gi) | devkit-gate | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-python-isolation-heartbeat-age | test_hook_python_isolation compared the session_lock heartbeat age in whole seconds, so a run stalled past 1 s under load reported a false BYPASS of session_lock.sh | devkit-tests | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-red-proof-runner-under-tests-read-as-test | red_proof read a production runner under tests/ as a test, so the 09/10 audit rows could not be proven | devkit-gate | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-review-gate-ocr-scope | review_gate OCR requirement: --from without --to failed, one report cleared committed+uncommitted code, ranged flag read from the whole command | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-session-lock-let-cp-mv-rm-tee-sed-i-touc | session_lock let cp/mv/rm/tee/sed -i/touch into a held checkout through, and blocked reads naming the gate folder | devkit-hooks | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-shell-writes-env-split-escapes | shell_writes read env -S lines with shlex only, so the env escapes \_ (word separator) and \c (end of line) were misread: a write slipped through or a false block | devkit-hooks | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-shell-writes-env-split-sq-escape | shell_writes dropped an env -S line that shlex cannot parse (an escaped quote inside single quotes, which env honours), so its write was never judged | devkit-hooks | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-shell-writes-env-split-string | shell_writes skipped the command line of env -S / --split-string as an option value, so its writes were never judged | devkit-hooks | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-shell-writes-git-c-tilde | shell_writes did not expand ~ in the -C directory of a repository write, so worktree_guard missed a commit into main and blocked one into the worktree | devkit-hooks | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-testsourceset-lock-fifo-hang | testsourceset_gate hung on a FIFO planted at test_run.lock after its FIFO sweep (exec 9>> waits for a reader) | devkit-hooks | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-worktree-reflog-gone-folder | worktree inventory: a commit only the HEAD reflog names passes once the worktree folder is deleted (reflog read only while the folder exists) | devkit-worktree | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261014-worktree-secret-carry | git-ignored secret files made only in a worktree (keystore, key.properties) were deleted with it by finish/automerge/gc | devkit-worktree | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261015-android-rules-reach | android rules: selection-size and wiring-pin sections unreachable from the prompts that need them; PII half-rule in an on-demand block; ambiguous bucket spec | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261015-churn-guard-p6 | churn_guard untracked-edit warning starts repo-owned code, repeats process spawns on re-edit, walks huge payloads | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261015-generic-traps-id | android generic-traps test hard-codes the promoted instinct id and exports a DEVKIT_ROOT agent-kit overwrites | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261015-generic-traps-round2 | android generic-traps test: stale comment, literal id 908 coupled to the real file, promote exit code unchecked in section C | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261015-lens-pin | state-matrix lens pin could not fail (token anywhere in the file) and the kit lens named document-viewer axes | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261015-nightly-idle-holder | nightly named run ignores an idle session that holds the checkout | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261015-nightly-round2 | nightly named run: unreadable git dir and trunk-mode main went ahead, one repo ran twice under two letter cases, ~user raised | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261015-nightly-run-paths | nightly run accepts an empty path, runs one repo twice and passes a non-project folder | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261015-rule-titles-noise | android rules section titles stuffed with common words pointed ordinary prompts at section 12 or 16 | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261015-wiring-pin-detect | wiring_pin scan: pin name per View only, View-only test silences, same-file object ignored, data class taken for a View, comment counted as a call, empty-bodied pin, unrunnable verify hint | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261015-wiring-pin-round2 | wiring_pin verify misreads an inner trailing comma, counts a raw-string decoy, accepts a string-literal mention as a call | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261015-wiring-pin-scan | wiring_pin scan skips non-ASCII paths, hangs on a FIFO, tracebacks on a Latin-1 byte, flags renamed files as new | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261015-wiring-pin-verify | wiring_pin verify says holds for a wrapped or unreadable assertion, a comment-only call, an empty pin, a path outside root | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261016-proof-gate-recursion-fail-open | proof_gate: a deeply nested receipt or state file crashes the hook with RecursionError and XONG passes (python exit 1 becomes wrapper exit 0) | devkit-gate | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-20261024-fix-root-cause-devkit-de-sau-nay-ko-bi-l | Fix root cause devkit để sau này ko bị lỗi dừng board cũng như cáv task bị kẹt lại như thế này nữa | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-VACUITY-SINCE-BASE | gate: vacuity revert uses HEAD under --since, so committed fixes look vacuous | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | BUG-WT-1013 | worktree copies keep the macOS uchg flag so remove cannot delete them and leaves an unregistered orphan folder | - | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | REG-DK-HOOK-01 | hook contract | devkit-hooks | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | REG-DK-SENTINEL-MERGE-ENV-01 | test_gate_sentinel.sh xanh khi DEVKIT_SLOT_PRIORITY=merge / DEVKIT_SLOT_LOAD_WAIT_S=0 rò từ merge gate vào verify (#167) | devkit-sentinel-merge-env | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | REG-SB-MERGE-LOAD-WAIT-01 | merge gate waits (bounded, inside the lock before the base is pinned, lock stamp refreshed) for the machine load to drop, then verifies anyway | super-board-merge-gate-load-wait | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | REG-SB-MERGE-TIMEOUT-RETRY-01 | merge gate retries a post-fix-gate verify once only when every red suite is TIMEOUT (REJECT exit 1, static checks passed); a real FAIL, UNTESTED or static finding is not retried; verify exit 124 still retried once | super-board-merge-gate-timeout-retry | suite quá giờ — tìm test treo, chạy lại |
| ❌ TIMEOUT | REG-SB-RUNNER-WATCHDOG-01 | super-board runner survives a killed sleep; durable stop marker; launchd watchdog never restarts a stopped board | super-board-runner-watchdog | suite quá giờ — tìm test treo, chạy lại |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261014-pm-agy-init-compact-json-only | agy init event was found by a compact-JSON substring only: a stream-json line with spaces after the colon made every agy dispatch fail or wait the 60 s init timeout | pm-mcp | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261014-pm-agy-lock-takeover-race | agy registry lock: stale-lock takeover was delete-then-create, so two PMs that saw the same stale lock could both enter the critical section (the second deleted the first one's NEW lock) and overwrite agy-conversations.json | pm-mcp | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261014-pm-agy-prune-budget-breaks-loop | agy registry prune: once 3 entries with a pid had been checked with ps the loop stopped, so older entries without a pid (no ps needed) were kept and the registry grew past 500 | pm-mcp | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261014-pm-doctor-agy-only-default-model | pm_doctor printed the agy diagnostics (binary, broken registry, permission policy) only when defaultModel was an agy model, so a task that runs agy through its own model or pm_dispatch model got no explanation for a failed dispatch | pm-mcp | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261014-pm-ping-kills-reused-pid | pm_doctor ping stopped its agy turns with kill(pid,0)+kill(-pid): up to 90 s later the pid may have exited and been reused, so it could SIGKILL a stranger's process group | pm-mcp | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261014-pm-status-agy-by-task-model | pm_status trusted task.model to tell an agy conversation from an IDE one: with ps broken a tier task whose conversation went through agy (pm_dispatch model=...) was nudged anyway and lost its whole report; the PLAN-phase nudge branch had no unknown-state check at all | pm-mcp | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261014-pm-tests-guessable-agy-path | MCP tests that simulate a missing agy pointed ANTIGRAVITY_PM_AGY at a guessable path in the shared TMPDIR: an executable planted there would be run, in two tests with --dangerously-skip-permissions | pm-mcp | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-droppending-always-writes | pm-mcp: dropPending rewrote the registry even when it removed nothing (delete returns true for absent keys) | - | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-droppending-foreign-entry | pm-mcp: dropPending deleted by key only and could remove another live PM's pending entry | - | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-null-selftag-accepted | pm-mcp: a null own fingerprint was accepted, leaving an entry that is never reaped | - | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-orphan-sigkill | pm-mcp: agy opened by newConversation is orphaned when the PM is SIGKILLed while waiting for init (no pending record by pid) | - | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-pending-leak-final-write | pm-mcp: a failed real-entry write after agy init left a pending-<pid> record in the registry | - | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-reaper-recheck-before-kill | pm-mcp: reaper identity check ran outside the lock, long before the kill under the lock | - | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-reaper-same-key-kill | pm-mcp: reaper re-check compared only the pid under a pid-keyed entry, so a rewritten pending entry (pid reuse) was killed | - | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-reaper-stale-snapshot-kill | pm-mcp: orphan reaper killed from a stale registry snapshot, so an agy a PM had just registered could be killed | - | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-selftag-after-spawn | pm-mcp: the PM read its own ps fingerprint after spawning agy, widening the untracked window | - | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261022-check-cac-task-trong-blocked-dang-bi-gi | check các task trong blocked đang bị gì fix devkit rồi restart lại | - | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261022-co-dang-bi-stuck-ko-vay | có đang bị stuck ko vậy? | - | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261023-cac-config-cpu-workload-hoat-dong-khong | các config cpu workload hoạt động không chính xác cần đổi logic lại đơn giản hơn là tổng số task chạy cùng trên buildin… | - | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-AGENT-OFFICE-01 | agent-office: unittest (server, redact, host check) và tìm đường A* của người đi trong xưởng (node) | mcp-servers/agent-office | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-AGENT-OFFICE-INBOX-02 | agent-office: hook hộp thư lệnh (rỗng, có lệnh, sai session, file hỏng, subagent, thiếu nonce, song song) và POST /api/agent-message (rate limit, tunnel cần mã, resume bị từ chối khi phiên còn chạy hoặc thẻ còn worker) | agent-office-agent-message | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-AUTO-ANTIGRAVITY-PM-MCP-01 | antigravity-pm-mcp: package.json test script | mcp-servers/antigravity-pm-mcp | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-AUTO-CC-SWITCHER-MCP-01 | cc-switcher-mcp: package.json test script | mcp-servers/cc-switcher-mcp | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-AUTO-PLAY-STORE-MCP-01 | play-store-mcp: pytest | mcp-servers/play-store-mcp | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-CAPACITY-CODEX-WAVE-01 | codex-wave: số lane Codex = min(max_workers, capacity build_workers); max_workers 0 lấy capacity; capacity vắng/hỏng/rác thì công thức cũ | capacity | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-CAPACITY-MERGE-HOLD-01 | merge gate: config thiếu merge_load_max thì chờ theo capacity hold_load (12 lõi: 96, biên 95/96), capacity vắng thì cùng công thức 8 × lõi (lệnh trùng REG-SB-MERGE-LOAD-WAIT-01) | capacity | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-CAPACITY-OFFICE-01 | agent-office dashboard: hiển thị ngưỡng tải hold_load từ capacity, capacity hỏng không làm sập dashboard | capacity | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-CAPACITY-RUNNER-01 | super-board-run resolve_build_*: config vắng thì build_workers và build_load_max (busy_load) lấy từ capacity, capacity vắng thì số cũ (lệnh trùng REG-SB-BUILD-WORKERS-01: gate gộp, không chạy hai lần) | capacity | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-CAPACITY-RUNNER-02 | super-board-run resolve_lane_workers: config vắng thì lane_workers từ capacity, capacity vắng thì 1 (lệnh trùng REG-SB-LANE-WORKERS-01) | capacity | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-CAPACITY-RUNNER-03 | super-board-run resolve_gate_max: config vắng thì gate_max từ capacity (4 lõi: 2), capacity vắng thì 6 (lệnh trùng REG-SB-WIP-LIMIT-01) | capacity | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-CAPACITY-SLOTS-01 | heavy_slot CLI / wrapper super-board: ngưỡng tải mặc định là capacity hold_load (lệnh trùng REG-SB-HEAVY-SLOT-01) | capacity | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-CAPACITY-SLOTS-02 | test super-board không xếp hàng sau slot thật của máy khi ngưỡng tải đến từ capacity (lệnh trùng REG-SB-TEST-SLOT-ISO-01) | capacity | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-CAPACITY-SLOTS-03 | super_board_all: dòng khởi động in ngưỡng hold_load của capacity, nút DEVKIT_CAPACITY không lái test (lệnh trùng REG-SB-NOTIFY-SLOTS-01) | capacity | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-DISCARD-SQUASH-01 | worktree discard: chuỗi commit đã squash vào origin/<trunk> (main local chưa pull) + file xoá thì gỡ được kèm refs/devkit/discarded; còn commit trunk chưa có patch hoặc có file bị sửa thì vẫn từ chối | worktree-discard-squash | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-GATE-01 | post-fix gate | devkit-gate | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-GATE-02 | proof gate (tree_fp) | devkit-gate | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-HEALTH-01 | health | devkit-health | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-HEAVY-CAP-01 | trần 3 suite nặng (cpu/gradle/xcode) cùng lúc: hết slot thì xếp hàng chờ không lỗi, hết ngân sách vẫn chạy kèm ghi chú, suite nhẹ/lồng không bị đếm, slot nặng không làm held | devkit-heavy-slot-cap | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-HOOK-02 | proof gate | devkit-hooks | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-MATRIX-MERGE-01 | merge driver ma trận hồi quy: hai nhánh cùng nối rule khác nhau vào cuối thì gộp không conflict và gate vẫn tin ma trận chỉ-thêm; cùng id khác nội dung thì lỗi rõ; sửa rule cũ vẫn conflict; githooks install cài driver | devkit-matrix-merge-driver | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-MERGE-TREE-NOLEAK-01 | merge-tree dò bị kill giữa chừng không để .merge_file_* ở cây làm việc (cwd tạm), kết luận 'đã tích hợp' không đổi khi driver chạy kịp (#309) | kit-merge-tree-no-leak | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-SANDBOX-01 | worktree sandbox cleanup keeps unmerged work unless --force | devkit-worktree-sandbox | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-SENTINEL-01 | sentinel: lần chạy thật > 24 h thì --full không dùng khoá (không ở merge gate), suite quá giờ không đóng mốc; cache sai thì học input thiếu hoặc cách ly flaky; run_one/nightly ghi cùng sổ khoá | devkit-suite-cache-sentinel | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-SESSION-01 | session lock + multi-session gate verdict (own session is never counted as another) | devkit-session-lock | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-SESSION-ENV-01 | test_multi_session_gate + test_gate_stop_reuse_race xanh khi id phiên của máy thật (CLAUDE_CODE_SESSION_ID, DEVKIT_SESSION_ID) rò vào môi trường (#240) | devkit-multi-session-gate-env | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-SLOT-CLASSES-01 | quyền chạy theo tải máy của từng suite (P1b): bỏ 2 slot engine; tải cao thì chờ rồi vẫn chạy, không UNTESTED; chờ tải không ăn vào thời gian chờ khoá; khoá Unity (độc quyền) vẫn chặn, không còn khoá thiết bị; bash -lc nhận ra Unity; hàng đợi ưu tiên + SJF; suite STALE bị SLOT không lọt PASS | devkit-slot-classes | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-SUITE-CACHE-01 | cache PASS theo khoá nội dung từng suite (cached-full): chỉ suite có input đổi chạy lại; khoá chính xác chỉ cho suite thêm vào, suite được chọn theo khoá cả cây; FAIL dính khoá, không-PASS vô hiệu PASS cũ; PASS theo khoá chính xác không vào biên nhận / DEVKIT_GATE_DONE; gộp lượt trùng khoá; suite tự sửa input không được ghi | devkit-suite-cache | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-VERIFY-PY-01 | unity compile skip when editmode/playmode runs + proof-capture run-before under device lock | devkit-verification-py | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-AGENT-OFFICE-INBOX-01 | runner: có bản cài ~/.agent-office/app/inbox_hook.py thì worker claude mang --session-id, --settings (hook PostToolUse hộp thư) và system prompt có nonce, ghi session id vào log; không có hoặc hook lỗi thì lệnh bật như cũ; agy/grok không đổi | agent-office-agent-message | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-BUILD-WORKERS-01 | lane build chạy nhiều worker theo tải máy: trần build_workers, tối đa một worker mới mỗi tick, tải >= build_load_max hoặc không đọc được thì giữ, quét mồ côi/zombie/dừng khẩn nhận ra N worker | super-board-build-workers | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-CARD-ITEMS-RETRY-01 | card.sh items đọc lại 1 lần khi số item lệch totalCount (không chết runner); lệch cả hai lần vẫn exit 69; stop.sh ghi marker trước kill (#256) | super-board-card-items-retry | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-GITHUB-READ-01 | super-board github-read helper | super-board-runner | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-GITHUB-READ-FOREIGN-HALT-01 | github-read: a failed read of ANOTHER repository (test fixture o/r from a worktree) never writes the real board halt; a read of the checkout's own repository, or one naming no repository, still halts | super-board-github-read-foreign-halt | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-GITHUB-RECONCILE-01 | github-read --halt --verify / --reconcile: đọc lại lần ghi chưa rõ kết quả; đã áp dụng thì lưu trữ halt, chưa áp dụng hay không kiểm chứng được thì giữ halt | super-board-github-read-reconcile | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-HEAVY-SLOT-01 | heavy slot theo tải máy (P1b): CLI/wrapper super-board chạy ngay khi tải < DEVKIT_SLOT_LOAD_MAX, chờ rồi vẫn chạy khi tải cao, --nonblock không chạy khi tải cao, DEVKIT_SLOT_LOAD_WAIT_S=0 không chờ, suite Unity lồng trong CLI vẫn xin khoá Unity; --force-full với suite nhẹ không chờ | super-board-heavy-slot | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-LANE-WORKERS-01 | lane QA và Review chạy nhiều worker (qa_workers / review_workers, mặc định 1): một worker mới mỗi tick, cổng tải build_load_max, zombie/reap/dừng khẩn/nhận lại nhận ra cả worker thêm, worker thêm không bị trần max_workers chặn | super-board-lane-workers | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-MERGE-CALL-FAILED-01 | merge gate: gh pr merge lỗi mà PR vẫn OPEN đúng head → exit 4, không halt board; đọc lại lỗi/CLOSED vẫn halt; MERGED muộn exit 0; head đổi exit 6 | super-board-merge-call-failed | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-MERGE-DEAD-HOLDER-01 | merge gate: khoá merge có pid đã chết (gate bị giết trước trap EXIT) được reap ngay, không chờ stale-after; pid còn sống và khoá không có pid vẫn chờ như cũ (exit 4) | super-board-merge-gate-dead-holder | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-MERGE-GATE-STALE-01 | merge gate says stale only when the branch is behind base | super-board-merge-gate | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-MERGE-GATE-TREE-01 | merge gate: cây gộp đã verify xanh với cùng bộ lệnh thì lượt gate sau bỏ verify; base đổi, lệnh đổi hoặc verify đỏ thì verify đủ (#226 gap 7) | super-board-merge-gate-verified-tree | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-MERGE-POLICY-NL-01 | merge-policy sees always_human keywords after VT/FF/CR/NEL/U+2028, in ++ lines and across odd whitespace | super-board-diff-policy | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-MERGE-TRAIN-01 | merge train: 3 PR sẵn sàng thì verify đúng một lần và cả 3 merge; một PR đỏ được chia đôi tìm ra (exit 11) và hai PR còn lại vẫn merge; một PR chạy như gate thường (#110) | super-board-merge-train | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-NEEDS-DEVICE-01 | runner, planner and status hold needs-device QA cards while no real device is online (emulator, denylist, no adb) | super-board-needs-device | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-NEEDS-YOU-01 | needs-you mark is idempotent, migrates human-gated and carries no machine line | super-board-needs-you | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-NEEDS-YOU-SKIP-01 | runner, planner and status leave Ready cards that wait for a person (needs-you / human-gated) to the person | super-board-needs-you-skip | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-NOTIFY-SLOTS-01 | notify blocks test/lib/runaway Telegram spam; super_board_all covers all 6 repos; monitor scans worktree transcripts; claim loop caps total early deaths | super-board-notify-and-slots | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-POST-MERGE-CLEAN-01 | post-merge clean and --sweep remove merged lane worktrees, keep work, one sweep at a time, salvage leaves no junk | super-board-post-merge-clean | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-PREFLIGHT-NUMBERED-AC-01 | AC đánh số 1) / 1. được nhận ở preflight (không hold unclear) và ở luật kéo Backlog; AC chỉ văn xuôi vẫn bị chặn (#283) | super-board-preflight-numbered-ac | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-PREFLIGHT-STALE-OVERLAP-01 | preflight câu 3: PR của thẻ Backlog/Blocked không chặn; PR của thẻ đang chạy vẫn chặn; thẻ có PR riêng không bị sequence lại; không --inflight giữ hành vi cũ (#280) | super-board-preflight-stale-overlap | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-PREFLIGHT-TOO-BIG-01 | preflight holds too-big cards before a builder pass, proceeds on normal ones | super-board-preflight | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RED-ON-BASE-01 | merge gate: suite đỏ cả trên origin/base không REJECT PR, mở thẻ riêng; suite do PR làm đỏ vẫn exit 11 (#251) | super-board-red-on-base | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-REVIEW-APPROVED-HEAD-01 | runner: thẻ Review đã duyệt đúng head (comment approved-head:<sha> của OWNER/MEMBER/COLLABORATOR) chỉ chạy merge-only với --expect-head, kể cả sau merge gate exit 4; head đổi, người ngoài duyệt hay đọc GitHub hỏng thì review đầy đủ (#227) | super-board-review-approved-head | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-REVIEW-MERGE-TRAIN-01 | runner: từ 2 thẻ Review đã duyệt đúng head trở lên thì một worker chạy super-board-merge-train.sh --prs cho cả đợt (lock chung PID, không bị coi là zombie khi thẻ đầu đã Done); thẻ chưa duyệt, sai head, đã khoá hay SB_REVIEW_TRAIN=0 thì đường từng thẻ như cũ (#228) | super-board-review-merge-train | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RUN-STOP-MTIME-01 | runner reads the stop marker mtime on GNU and BSD stat | super-board-run-stop-mark-mtime | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RUN-SWEEP-TICK-01 | runner starts the post-merge sweep at startup and on every tick (before cap-reached), throttled, in the background | super-board-run-sweep-wiring | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RUNNER-LANES-01 | super-board runner lanes | super-board-runner | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RUNNER-NOOP-WORKER-01 | runner: worker qa/review thoát mà thẻ vẫn ở cột cũ và không comment mới thì tính no-op; 2 lần liên tiếp thì thẻ sang Blocked (📱 nếu log nhắc máy thật, còn lại ❓) kèm dòng cuối log, không giao lại; chuyển cột hoặc có comment thì không tính | super-board-runner-noop-worker | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RUNNER-PREFLIGHT-SWEPT-01 | runner chạy preflight trước khi nhận thẻ build (hold/sequence có blockedBy: không claim, thẻ sang Blocked kèm blocked-by; exit 79 dừng run) và sổ SWEPT_CARDS bền qua lần khởi động lại (#253) | super-board-runner-preflight-swept | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RUNNER-READ-RETRY-01 | runner đọc lại board có backoff khi lần đọc hỏng tạm thời; hỏng hết lượt thì bỏ tick thay vì chết; halt 79 vẫn dừng; vòng chính chỉ đọc qua tick_fetch (#256) | super-board-runner-board-read-retry | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RUNNER-READY-ORDER-01 | runner giao thẻ Ready theo priority label, bug trước, số issue tăng dần; thẻ body nhắm repo khác → Blocked kèm block-template; thẻ có Fix trùng thẻ đang mở → comment một lần, không giao | super-board-runner-ready-order | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RUNNER-RECLAIM-DEAD-BUILD-01 | runner trả thẻ Building có worker build chết giữa lượt chạy về lại Ready kèm sổ reclaims; quá trần trong cửa sổ thì chuyển sang Blocked có dòng blocked-by: - | super-board-runner-reclaim-dead-build | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-SCRATCH-CONFIG-01 | merge gate scratch tree gets ignored local config, build inputs and the ignored hooks settings registers | super-board-scratch-config | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-SELF-RELOAD-01 | runner rảnh tự nạp lại super-board-run.sh khi origin đổi: ff main rồi exec lại; main lệch origin / ff hỏng / sai cú pháp thì notify một lần, không restart mù; còn worker thì không đụng | super-board-self-reload | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-SETUP-BIN-01 | setup BIN lists every super-board script the runner, merge gate and skills call | super-board-setup-bin-list | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-STATUS-NEEDS-YOU-01 | status: option Needs You của Project vẽ thành ô riêng và vào nhóm Waiting on you; không có thẻ Needs You thì đầu ra không đổi | super-board-status-needs-you-column | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-TEST-SLOT-ISO-01 | tests never queue behind the machine's real heavy-verify slots | test-heavy-slot-isolation | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-TOTAL-CAP-01 | một trần worker max_workers (5) cho mọi repo, cộng phanh spawn khi load1 vượt ngưỡng (mặc định busy_load); dưới ngưỡng tải không chặn; lib mode không đọc máy thật | super-board-total-worker-cap | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-UPSTREAM-66-67-01 | github-read keeps odd-newline diffs byte-exact without halting; approval links body issues off the default base | super-board-diff-policy | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-VERIFY-CMD-01 | QA in đúng lệnh verify của merge gate (cùng hàm chèn --diff/--force-full) (#251) | super-board-red-on-base | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-WATCHDOG-LOCK-ATOMIC-01 | 8 check cùng gặp khoá check cũ quá 120 s thì đúng một check giữ được khoá (không khởi động 2 runner) | super-board-watchdog-lock-atomic | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-WATCHDOG-PATHS-01 | watchdog compares .state paths on physical paths and takes back a stale check lock on GNU and BSD stat | super-board-watchdog-path-sanitize | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-WAVE-NEEDSYOU-01 | wave.js: prompt exit 7 và exit 8 của merge gate gọi super-board-needs-you.py mark với --next comment done (#106) | super-board-wave-needs-you-mark | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-WIP-LIMIT-01 | runner giới hạn WIP (#252): không giao build khi QA+Review chờ >= build_wip_k × (qa_workers+review_workers); không giao build / worker QA-Review thêm khi số post-fix-gate đang chạy >= gate_max; log lý do; số gate không đếm được thì không chặn | super-board-wip-limit | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-WRITE-MARKER-01 | gh_write_once: comment ghi chưa rõ kết quả mang marker duy nhất cho mỗi lần, comment cố định lặp không làm reconcile báo đã áp dụng nhầm | super-board-gh-write-once-marker | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-WB-CONFIG-01 | agent-kit health: every registered hook exists, imports resolve, context in sync | workbench-agent-config | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🐞 chưa sửa | BUG-20261012-test-chap-chon-flaky-reg-dk-session-01 | Test chập chờn (flaky): REG-DK-SESSION-01 | devkit-session-lock | sửa theo ĐỎ→XANH rồi `agent-kit bugs link` |
| 🐞 chưa sửa | BUG-20261013-test-chap-chon-flaky-reg-dk-all-01 | Test chập chờn (flaky): REG-DK-ALL-01 | devkit-all | sửa theo ĐỎ→XANH rồi `agent-kit bugs link` |
| 🐞 chưa sửa | BUG-20261023-test-chap-chon-flaky-reg-sb-runner-recla | Test chập chờn (flaky): REG-SB-RUNNER-RECLAIM-DEAD-BUILD-01 | super-board-runner-reclaim-dead-build | sửa theo ĐỎ→XANH rồi `agent-kit bugs link` |
| ⚠️ có test, gate không chạy | BUG-20261013-bug-capture-copied-a-pasted-secret | Bug capture copied an API key pasted in a prompt into regression_status.json and CHECKLIST.md (title and id unredacted) | checklist | test có nhưng gate không chạy — đưa vào ma trận hoặc link suite của ma trận |
| ⚠️ có test, gate không chạy | BUG-20261013-regression-gate-held-skip-ignored-writers | regression_gate skipped the Stop for a payload without session_id or with DEVKIT_ALLOW_SHARED_CHECKOUT=1 while another session held the lock | gates | test có nhưng gate không chạy — đưa vào ma trận hoặc link suite của ma trận |

## 🧩 Phân hệ

### agent-office-agent-message — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-AGENT-OFFICE-INBOX-02 | agent-office: hook hộp thư lệnh (rỗng, có lệnh, sai session, file hỏng, subagent, thiếu nonce, song song) và POST /api/agent-message (rate limit, tunnel cần mã, resume bị từ chối khi phiên còn chạy hoặc thẻ còn worker) | 2026-10-24 13:07:21 · 1.80s · exit 0 · 38166b6b+dirty · [log](evidence/REG-AGENT-OFFICE-INBOX-02/20261024-130716.log) | cd mcp-servers/agent-office && python3 -m unittest tests.test_inbox_hook tests.test_agent_message |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-AGENT-OFFICE-INBOX-01 | runner: có bản cài ~/.agent-office/app/inbox_hook.py thì worker claude mang --session-id, --settings (hook PostToolUse hộp thư) và system prompt có nonce, ghi session id vào log; không có hoặc hook lỗi thì lệnh bật như cũ; agy/grok không đổi | 2026-10-24 13:07:21 · 0.64s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-AGENT-OFFICE-INBOX-01/20261024-130714.log) | bash tests/super-board/test_runner_agent_office_inbox.sh |

### agent-office-cc-switcher-page-742-split — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-742-R3-WEB-NO-EMPTY-CATCH-01 | #742 review 409a7296 (fc1b157568, INSTINCT-007), tách từ #742: không trang nào trong agent-office/web có catch rỗng | chưa chạy | cd mcp-servers/agent-office && python3 -m unittest tests.test_web_no_empty_catch |
| ⏳ chưa chạy | REG-742-R4-CC-RETRY-01 | #742 review c27d199d (c39f91d4e7, INSTINCT-002), tách từ #742: nút Thử lại của /cc-switcher disabled + aria-busy ngay khi bấm, khoá >= 1000 ms; load() chỉ một request đang chạy; vùng chạm >= 44px | chưa chạy | cd mcp-servers/agent-office && python3 -m unittest tests.test_cc_switcher_retry tests.test_cc_switcher_touch_targets |

### agent-office-gate-full-weekdays — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-AGENT-OFFICE-GATE-FULL-WEEKDAYS-01 | Gate speed v26 mục 6: agent-office đọc lịch heavy gate thứ Hai + thứ Năm (dict hoặc list StartCalendarInterval) | chưa chạy | cd mcp-servers/agent-office && python3 -m unittest discover -s tests -p test_gate_full_runner_weekdays.py |

### approval-auto-merge-head — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-APPROVAL-AUTO-MERGE-01 | duyệt head X vẫn hiệu lực khi merge gate tự gộp main thành Y; commit khác đẩy thêm thì đòi duyệt lại (#262) | chưa chạy | python3 tests/super-board/test_approval_auto_merge_head.py |

### audited-head-ascii-space-629 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-AUDITED-HEAD-ASCII-629-01 | #629: push_gate.AUDITED_HEAD (khoảng trắng [ \t\n\r\f\v], cùng regex pm_verdict) không nhận `auditedHead:` ngăn bởi \x1c-\x1f/U+0085 mà regex JS của pm_verdict không thấy; dấu cách/tab vẫn nhận | chưa chạy | bash universal-agent-devkit/tests/gates/test_audited_head_ascii_space.sh |

### batch-canary — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-BATCH-CANARY-01 | canary merge theo đợt: >=2 PR merged mà 0 train hoặc verify/PR > 0.5 thì ĐỎ; enabled_at lọc lượt cũ; health chỉ WARN không đổi exit; nightly tạo thẻ incident chống trùng | chưa chạy | bash tests/super-board/test_batch_canary.sh |

### capacity — 0/9 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-CAPACITY-CODEX-WAVE-01 | codex-wave: số lane Codex = min(max_workers, capacity build_workers); max_workers 0 lấy capacity; capacity vắng/hỏng/rác thì công thức cũ | 2026-10-24 13:07:21 · 16.04s · exit 0 · 38166b6b+dirty · [log](evidence/REG-CAPACITY-CODEX-WAVE-01/20261024-130622.log) | bash tests/super-board/test_codex_wave_workers.sh |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-CAPACITY-MERGE-HOLD-01 | merge gate: config thiếu merge_load_max thì chờ theo capacity hold_load (12 lõi: 96, biên 95/96), capacity vắng thì cùng công thức 8 × lõi (lệnh trùng REG-SB-MERGE-LOAD-WAIT-01) | 2026-10-24 13:07:21 · 104.53s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-MERGE-LOAD-WAIT-01/20261024-125932.log) | bash tests/super-board/test_merge_gate_load_wait.sh |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-CAPACITY-OFFICE-01 | agent-office dashboard: hiển thị ngưỡng tải hold_load từ capacity, capacity hỏng không làm sập dashboard | 2026-10-24 13:07:21 · 0.11s · exit 0 · 38166b6b+dirty · [log](evidence/REG-CAPACITY-OFFICE-01/20261024-130653.log) | cd mcp-servers/agent-office && python3 -m unittest tests.test_dashboard_stats |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-CAPACITY-RUNNER-01 | super-board-run resolve_build_*: config vắng thì build_workers và build_load_max (busy_load) lấy từ capacity, capacity vắng thì số cũ (lệnh trùng REG-SB-BUILD-WORKERS-01: gate gộp, không chạy hai lần) | 2026-10-24 13:07:21 · 6.33s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-BUILD-WORKERS-01/20261024-125949.log) | bash tests/super-board/test_runner_build_workers.sh |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-CAPACITY-RUNNER-02 | super-board-run resolve_lane_workers: config vắng thì lane_workers từ capacity, capacity vắng thì 1 (lệnh trùng REG-SB-LANE-WORKERS-01) | 2026-10-24 13:07:21 · 20.97s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-LANE-WORKERS-01/20261024-130100.log) | bash tests/super-board/test_runner_lane_workers.sh |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-CAPACITY-RUNNER-03 | super-board-run resolve_gate_max: config vắng thì gate_max từ capacity (4 lõi: 2), capacity vắng thì 6 (lệnh trùng REG-SB-WIP-LIMIT-01) | 2026-10-24 13:07:21 · 0.14s · exit 0 · 38166b6b+dirty · [log](evidence/REG-CAPACITY-RUNNER-03/20261024-130653.log) | bash tests/super-board/test_runner_wip_limit.sh |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-CAPACITY-SLOTS-01 | heavy_slot CLI / wrapper super-board: ngưỡng tải mặc định là capacity hold_load (lệnh trùng REG-SB-HEAVY-SLOT-01) | 2026-10-24 13:07:21 · 10.31s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-HEAVY-SLOT-01/20261024-125943.log) | bash tests/super-board/test_heavy_slot.sh |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-CAPACITY-SLOTS-02 | test super-board không xếp hàng sau slot thật của máy khi ngưỡng tải đến từ capacity (lệnh trùng REG-SB-TEST-SLOT-ISO-01) | 2026-10-24 13:07:21 · 0.11s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-TEST-SLOT-ISO-01/20261024-125828.log) | bash tests/super-board/test_tests_skip_machine_slots.sh |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-CAPACITY-SLOTS-03 | super_board_all: dòng khởi động in ngưỡng hold_load của capacity, nút DEVKIT_CAPACITY không lái test (lệnh trùng REG-SB-NOTIFY-SLOTS-01) | 2026-10-24 13:07:21 · 9.84s · exit 0 · 38166b6b+dirty · [log](evidence/REG-CAPACITY-SLOTS-03/20261024-130701.log) | python3 tests/super-board/test_notify.py && python3 tests/super-board/test_super_board_all_slots.py && bash tests/super-board/test_runner_claim_loop.sh |

### card-batch-fresh-lead — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-CARD-BATCH-FRESH-LEAD-01 | #731: pick_batch_lead kiểm lại Risk 🔴 High và trần AC trên body đọc lại của thẻ trưởng; thẻ Backlog có PR mở không thành đích gom | chưa chạy | bash universal-agent-devkit/tests/verification/test_card_batch_fresh_lead.sh |

### card-batch-one-branch-724 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-GATE-BATCH-724-01 | #724: một đợt thẻ = một nhánh/PR/gate — ac-check nhận Closes của thẻ mang marker sb:batch-of của thẻ nhánh (marker thẻ khác, trong code fence, body rỗng vẫn là thẻ lạ) và đếm AC của nó; merge gate merge PR đợt đủ AC, thiếu AC exit 11, còn AC chưa tick thì Refs cả đợt + ac-open, Closes thẻ ngoài đợt hoặc PR không sb:ac vẫn exit 11 | chưa chạy | bash tests/super-board/test_merge_gate_batch.sh |

### checklist-overlay-ttl-3d-992 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-CHECKLIST-OVERLAY-TTL-3D-992-01 | #992: regression_checklist._overlay_fresh mặc định 3 ngày như hạn PASS của gate (2 ngày tin, 4 ngày không); DEVKIT_GATE_CACHE_MAX_S vẫn ghi đè | chưa chạy | bash universal-agent-devkit/tests/gates/test_checklist_overlay_ttl_3d.sh |

### create-task-pr-mention — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-CREATE-TASK-PR-MENTION-01 | #735: create-task không gom vào thẻ Ready/Backlog đã có PR mở nhắc nó (Closes/Fixes/Resolves/Refs #N, closingIssuesReferences) dù nhánh không theo mẫu issue-<N>- | chưa chạy | bash universal-agent-devkit/tests/verification/test_create_task_pr_mention.sh |

### devkit-active-profile-link-not-committed — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-COPY-PROFILE-01 | #1153: `agent-kit init -m copy` ghi link .agents/active-profile (trỏ về kit của máy cài) vào .git/info/exclude như chế độ symlink: `git add -A` không commit link, bản clone không có symlink treo, health không cảnh báo link DevKit chưa loại khỏi git, cài lại không nhân đôi dòng và không đụng .gitignore đã commit | chưa chạy | bash universal-agent-devkit/tests/installer/test_active_profile_link_not_committed.sh |

### devkit-agent-kit-approve-tests — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-APPROVE-TESTS-CMD-01 | Đợt 2 gate mục 2 (04/11): agent-kit approve-tests <task> ghi mục duyệt chéo từ biên bản antigravity-pm (reviewer antigravity hoặc grok, nhãn rõ); tác giả không tự duyệt | chưa chạy | bash universal-agent-devkit/tests/gates/test_agent_kit_approve_tests.sh |

### devkit-all — 0/0 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 💤 đã nghỉ (suite không còn trong ma trận) | REG-DK-ALL-01 | DevKit tests that name a changed file (code, templates, rules) + repo consistency; the full suite exceeds the 900 s gate limit | 2026-10-24 07:30:48 · 119.88s · exit None · 82f868e7+dirty · [log](evidence/REG-DK-ALL-01/20261024-073048.log) | bash universal-agent-devkit/tests/run_impacted.sh |

### devkit-all-kit-runner — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-ALL-KIT-01 | Gate speed v14 mục 5a: lượt --scoped chạy test kit đã chọn qua một runner run_impacted.sh, thay ba shard | chưa chạy | bash universal-agent-devkit/tests/run_impacted.sh |

### devkit-all-shard-gates — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-ALL-GATES-01 | #616 shard thay REG-DK-ALL-01 (đã bỏ ở #650) theo thư mục (tests/gates): DevKit tests that name a changed file, chia để mỗi suite ngắn hơn trần 900 s | chưa chạy | DEVKIT_IMPACTED_DIRS=gates bash universal-agent-devkit/tests/run_impacted.sh |

### devkit-all-shard-rest — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-ALL-REST-01 | #616 shard thay REG-DK-ALL-01 (đã bỏ ở #650) theo thư mục (phần còn lại: verification, installer, context_memory, hooks/tests): DevKit tests that name a changed file, chia để mỗi suite ngắn hơn trần 900 s | chưa chạy | DEVKIT_IMPACTED_DIRS=!gates,!worktree_git bash universal-agent-devkit/tests/run_impacted.sh |

### devkit-all-shard-rules — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-ALL-SHARD-RULES-616-01 | #616: ba suite shard REG-DK-ALL-* thay REG-DK-ALL-01 (đã bỏ khỏi ma trận), khối shard liền nhau và chỉ-thêm sau các rule trước nó (rule nối sau không làm đỏ, #453), theo dõi universal-agent-devkit/*, run_impacted.sh --list của ba lệnh hợp lại đúng tập không shard, không trùng | chưa chạy | bash tests/super-board/test_matrix_shard_rules.sh |

### devkit-all-shard-worktree — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-ALL-WORKTREE-01 | #616 shard thay REG-DK-ALL-01 (đã bỏ ở #650) theo thư mục (tests/worktree_git): DevKit tests that name a changed file, chia để mỗi suite ngắn hơn trần 900 s | chưa chạy | DEVKIT_IMPACTED_DIRS=worktree_git bash universal-agent-devkit/tests/run_impacted.sh |

### devkit-evidence-gate-block-reason-log — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-EVIDENCE-GATE-REASON-LOG-01 | Đợt 2 gate mục 8 (04/11): test_evidence_gate ghi lý do giữ Stop (nhắc nào) vào log để chẩn đoán được | chưa chạy | bash universal-agent-devkit/tests/gates/test_evidence_gate_block_reason_log.sh |

### devkit-gate — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-GATE-01 | post-fix gate | 2026-10-24 13:12:26 · 35.01s · exit 0 · b93a50cc+dirty · [log](evidence/REG-DK-GATE-01/20261024-131226.log) | bash universal-agent-devkit/tests/gates/test_postfix_gate.sh |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-GATE-02 | proof gate (tree_fp) | 2026-10-24 13:12:49 · 21.97s · exit 0 · b93a50cc+dirty · [log](evidence/REG-DK-GATE-02/20261024-131248.log) | bash universal-agent-devkit/tests/gates/test_proof_gate.sh |

### devkit-gate-approval-after-main-merge — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-APPROVAL-AFTER-MAIN-MERGE-01 | Đợt 2 gate mục 1 (04/11): duyệt test sửa (ledger + trailer Test-approved-by) còn hiệu lực sau khi gộp main vào nhánh PR; reviewer thuộc danh tính phiên bị từ chối; reviewer và auditedHead cùng một biên bản PM | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_approval_after_main_merge.sh |

### devkit-gate-approved-tests-same-second — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-APPROVED-SAME-SECOND-01 | #485 + đợt 2 lane A: duyệt test sửa không lệch theo giây; test sửa sau khi duyệt không còn được duyệt; fixture nằm trên nhánh feat như PR thật | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_approved_tests_same_second.sh |

### devkit-gate-audited-head-base — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-AUDITED-HEAD-BASE-01 | duyệt chéo: auditedHead trước base không duyệt chép lùi test (mục duyệt, trailer, push_gate.approved); audited_head đọc verdicts.audit.auditedHead trước notes; ANTIGRAVITY_PM_STATE_HOME lạ không cấp biên nhận task / full_pass exit 0 (#605 audit T0066 vòng 2) | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_audited_head_base.sh |

### devkit-gate-pm-direct-approval — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-PM-DIRECT-APPROVAL-01 | 04/11: test sửa được duyệt bằng biên bản antigravity-pm tra thẳng (không comment / json / trailer); phiên cùng reviewer, audit mới hơn khác blob, pm home lạ, biên bản cũ, head trên main, author tự khai, head chỉ trong history, hai biên bản cùng id đều bị từ chối | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_pm_direct_approval.sh |

### devkit-gate-pool-live-holder-busy — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GATE-POOL-LIVE-HOLDER-01 | Đợt 2 gate lane C2 (04/11): Stop run gặp slot hàng đợi gate máy bị gate dự án khác giữ thì trả BUSY sớm theo luật B5 thay vì chờ hết 45 s | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_pool_live_holder_busy.sh |

### devkit-gate-pool-mixed-size — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GATE-POOL-MIXED-01 | pool gate có vé khác cỡ (P1): vé ghi n = số path; vé đứng sau ghép tham lam (vé trước theo n tăng dần giữ chỗ trống lớn nhất < n), còn dư thì lấy chỗ nhỏ nhất — không còn slot trống mà không ai lấy; chừa đúng slot cho vé nhỏ đứng trước; .held chỉ cho slot giữ | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_pool_mixed_size.sh |

### devkit-gate-robustness — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GATE-ROBUSTNESS-01 | gate không sập, không treo, không để rác: repo lồng, tên file non-UTF-8, tín hiệu giết suite, không có git, killpg bị từ chối; suite quá giờ lúc máy rảnh ghi HANG kèm test cuối và ảnh chụp tiến trình, lúc tải cao vẫn TIMEOUT (#370) | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_robustness.sh |

### devkit-gate-shard-group — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GATE-SHARD-GROUP-01 | 04/11 Việc 2: shard REG-DK-ALL-* của runner chạy cạnh nhau một nhóm, chung một bể và JOBS, giữ đúng một slot nặng, shard đỏ không bỏ shard cùng nhóm, DEVKIT_GATE_PARALLEL=0 giữ tuần tự | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_shard_group.sh |

### devkit-gate-slot-queue — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GATE-SLOT-QUEUE-01 | hàng đợi gate toàn máy (pool gate, N = capacity gate_max; 12 lõi = 3): hết giờ chờ thoát 4 BUSY không ghi biên nhận, kế thừa DEVKIT_GATE_SLOT_HELD, kiểm lại reuse sau khi lấy slot và Stop hook giữ UNTESTED | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_slot_queue.sh |

### devkit-guard-heredoc-text — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GUARD-HEREDOC-TEXT-01 | chữ rm -rf / git nằm trong heredoc là dữ liệu: hardware_safety_gate và worktree_guard không chặn nhầm, rm -rf / và ghi vào main thật vẫn bị chặn (#299 b, c) | chưa chạy | bash universal-agent-devkit/tests/gates/test_guard_heredoc_text_not_command.sh |

### devkit-guard-kill-by-name — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GUARD-KILL-BY-NAME-01 | git guard chặn pkill / killall / pgrep -f (kill theo tên trúng mọi board); kill <PID>, pgrep không -f và chữ pkill trong echo/grep/commit -m vẫn qua (#144) | chưa chạy | bash universal-agent-devkit/tests/gates/test_guard_kill_by_name.sh |

### devkit-guard-merge-queue-label-536 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GUARD-MQ-LABEL-01 | #536: git guard hỏi .claude/bin/super-board-queue-label.sh --check trước khi cho gắn nhãn merge-queue (gh pr/issue edit --add-label, gh api …/issues/N/labels, interpreter gọi gh); helper từ chối / treo → chặn trong thời hạn, không gợi ý prefix !; gh pr create\|new --label merge-queue và mutation graphql gắn nhãn theo id → chặn; nhãn khác / gỡ nhãn / GET / DELETE → qua, không gọi helper; helper của project phiên (checkout chính khi là worktree), không theo cd; project chưa có helper → luật không chạy | chưa chạy | bash universal-agent-devkit/tests/gates/test_guard_merge_queue_label.sh |

### devkit-guard-nested-c-quotes — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GUARD-NESTED-C-QUOTES-01 | #844: $"…" (locale) và \$ trước nháy trong nháy kép của script bash -c / sh -c / eval được đọc thêm đã giải mã (không bao giờ thành '…'); corpus tìm kiếm rg/grep -E/git grep/sed vẫn qua | chưa chạy | bash universal-agent-devkit/tests/gates/test_guard_nested_c_quotes.sh |

### devkit-guard-protected-delete — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GUARD-PROTECTED-DELETE-01 | git guard chỉ hỏi người khi: force push (-f/--force/--force-with-lease/+ref), xoá ref remote (push --delete/-d/:ref/--mirror/--prune), xoá file quan trọng (rm/unlink/git rm/find -delete theo protected_delete mặc định + .antigravity-pm.json); xoá file thường vẫn qua (#605) | chưa chạy | bash universal-agent-devkit/tests/gates/test_guard_protected_delete.sh |

### devkit-guard-self-approval-comment — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GUARD-SELF-APPROVAL-01 | git guard chặn agent tự đăng approved-head trơn (không approved-by:) hoặc dòng done qua gh pr/issue comment, gh api …/comments (--body, -b, --body-file, -F, -f/-F body=); approved-head + approved-by và cross-review-approved vẫn qua (#605 Lane H) | chưa chạy | bash universal-agent-devkit/tests/gates/test_guard_self_approval_comment.sh |

### devkit-hardware-empty-serial — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-HW-EMPTY-SERIAL-01 | #829: adb -s "" / -s '' (adb tự chọn thiết bị, cả khi lệnh shell có ; && \| trong nháy), serial bị cấm trong nháy, nháy mở ở segment trước (FOO="a;b" adb …), biến ở chỗ subcommand, lệnh con ở phép gán tiền tố (X=$(pwd) adb …), mở rộng tham số (${S##*}) và biến lệnh tự gán lại, -s/-t mà adb không phân giải được hay không tìm thấy adb, -s lặp lại (-s cuối thắng, cả -s<số>), -t cùng -s (-t thắng) và biến chưa biết hay lệnh con $( ) / ` ` ở tuỳ chọn chọn thiết bị bị chặn khi máy đích nằm trong denylist (--serial được xét như -s); emulator, biến đã biết, -P chưa biết cạnh -s literal, lệnh con trong lệnh shell của serial đã ghi, backtick markdown trong chuỗi nháy đơn, host-only, HARDWARE_OVERRIDE=1 vẫn cho qua; -s làm giá trị tuỳ chọn khác không làm hook lỗi; adb giả chỉ nhận get-serialno | chưa chạy | bash universal-agent-devkit/tests/gates/test_hardware_empty_serial.sh |

### devkit-health — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-HEALTH-01 | health | 2026-10-24 13:07:21 · 219.55s · exit 0 · 38166b6b+dirty · [log](evidence/REG-DK-HEALTH-01/20261024-125542.log) | bash universal-agent-devkit/tests/installer/test_agent_health.sh |

### devkit-health-kit-host-checkout — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-HEALTH-KIT-HOST-01 | #1146: agent-health in một dòng khi checkout chính của repo chứa kit detached hoặc lệch nhánh trunk, và một dòng khi .git/index.lock của nó cũ hơn 10 phút mà không tiến trình git nào giữ; không tính điểm, không xoá khoá, không đổi nhánh; đúng checkout khi chạy từ worktree liên kết hoặc repo app | chưa chạy | bash universal-agent-devkit/tests/installer/test_health_kit_host_checkout.sh |

### devkit-heavy-slot-cap — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-HEAVY-CAP-01 | trần 3 suite nặng (cpu/gradle/xcode) cùng lúc: hết slot thì xếp hàng chờ không lỗi, hết ngân sách vẫn chạy kèm ghi chú, suite nhẹ/lồng không bị đếm, slot nặng không làm held | 2026-10-24 13:07:21 · 5.49s · exit 0 · 38166b6b+dirty · [log](evidence/REG-DK-HEAVY-CAP-01/20261024-125955.log) | bash universal-agent-devkit/tests/gates/test_heavy_slot_cap.sh |

### devkit-hook-alternative-paths — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-HOOK-ALT-PATHS-01 | #1153: lệnh hook thử nguồn kit rồi tới link .claude/hooks (`[ -f "$p" ] && exec …; [ -f "$f" ] && exec …`, hooks.json từ #1108) không bị agent-kit health và post-fix-gate báo thiếu file ở repo ngoài agent-workbench khi một đường dẫn tồn tại; cả hai thiếu vẫn bị chặn, và mọi dạng không có exec (chuỗi &&, phép thử trong echo, nháy đơn, chạy không canh) vẫn bắt buộc | chưa chạy | bash universal-agent-devkit/tests/gates/test_hook_alternative_paths.sh |

### devkit-hook-cached-python — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-HOOK-CACHED-PY-01 | 04/11 (#967): python của hardware_safety_gate.sh / block-dangerous-git.sh là module cạnh hook, bytecode chỉ ở thư mục riêng $TMPDIR/devkit-pycache-$UID (thư mục nhóm ghi được / symlink thì không dùng, không bao giờ __pycache__ cạnh hook); thiếu hoặc hỏng module thì chặn rc 2 nêu tên module; phán quyết giữ nguyên | chưa chạy | bash universal-agent-devkit/tests/gates/test_hook_cached_python.sh |

### devkit-hooks — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ❌ TIMEOUT | REG-DK-HOOK-01 | hook contract | 2026-10-24 13:52:46 · 119.97s · exit None · 1b575f4f+dirty · [log](evidence/REG-DK-HOOK-01/20261024-135246.log) | bash universal-agent-devkit/hooks/tests/hook_contract_test.sh |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-HOOK-02 | proof gate | 2026-10-24 21:33:58 · 19.78s · exit 0 · ae868292+dirty · [log](evidence/REG-DK-HOOK-02/20261024-213358.log) | bash universal-agent-devkit/tests/gates/test_proof_gate.sh |

### devkit-impeccable-skill — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-IMPECCABLE-01 | skill impeccable v4.7.1: SKILL.md frontmatter + Apache-2.0/MIT NOTICE, launcher tắt telemetry mặc định & probe cô lập exit 127, đủ reference/JSON 62 rule, 3 lớp bảo vệ DevKit (billing, hook/.grok, .adb-denylist), lọc profile và đồng bộ tài liệu 35 skills | chưa chạy | bash universal-agent-devkit/tests/verification/test_impeccable_skill.sh |

### devkit-incident-reporter — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-INCIDENT-01 | lỗi do DevKit trong log board/watchdog/hook của repo app thành đúng 1 thẻ trên ToanMobile/agent-workbench; trùng chữ ký không thêm thẻ; nhiễu không thành thẻ; gh hỏng giữ spool, exit 0 | chưa chạy | bash universal-agent-devkit/tests/verification/test_devkit_incident.sh |

### devkit-init-parity-sync — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-INIT-PARITY-SYNC-01 | #774: init đồng bộ super-board (drift exit 0, giữ file chỉ có ở repo), cài lịch gate-full đêm, đăng ký guard-protected-push fail closed | chưa chạy | bash universal-agent-devkit/tests/installer/test_parity_check.sh |

### devkit-integrate — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-INTEGRATE-01 | agent-kit integrate (repo trunk-push): chưa tới hạn không làm gì; tới hạn chạy --full một lần trong scratch rồi push đúng HEAD đã gate; gate đỏ/bận không push; origin phân kỳ dừng; khoá bận exit 0; _TRUNK_ALLOWED | chưa chạy | bash universal-agent-devkit/tests/worktree_git/test_agent_kit_integrate.sh |

### devkit-lane-lock-merge-gate-release-p5 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-LANE-LOCK-MG-RELEASE-01 | P5 (gate kẹt và chậm 02/11): lane_lock nhả slot lane khi super-board-merge-gate.sh (argv[0] / env … bash <path>) có hậu duệ giữ slot pool gate (.held PID hậu duệ, mtime ≥ lúc tạo con) hoặc chờ vé queue/gate ≥ 5 s; vé queue/heavy, bash -c bọc gate thường, .held của tiến trình lạ ⇒ giữ slot; ps lỗi ⇒ giữ slot, log một lần; không deadlock | chưa chạy | bash universal-agent-devkit/tests/gates/test_lane_lock_merge_gate_release.sh |

### devkit-lane-lock-stagger-p7 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-LANE-LOCK-STAGGER-01 | P7 (gate kẹt và chậm 02/11): lane_lock chống dồn — 2 lane nặng chờ ở tải 30, tải xuống 9 hay 5 ⇒ lane đầu vào ngay (0 slot giữ không chặn), lane sau chỉ vào khi .owner lane đầu ≥ LANE_LOCK_STAGGER_S; đối chứng tải 5 chưa chờ tải ⇒ vào ngay; tải 8: gate scoped nhỏ #849 không bị chống dồn, việc nặng thứ hai chờ; không file mới trong LANE_LOCK_DIR | chưa chạy | bash universal-agent-devkit/tests/gates/test_lane_lock_stagger.sh |

### devkit-matrix-detect-unittest-fallback — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-MATRIX-UNITTEST-01 | #1153: matrix_detect chọn `python3 -m unittest discover -s <thư mục>` khi dự án không khai báo pytest, python3 không import được pytest và file test dùng unittest; dự án khai báo pytest, máy có pytest hoặc test kiểu pytest vẫn giữ `python3 -m pytest -q`; lệnh unittest sinh ra chạy thật được test của dự án | chưa chạy | bash universal-agent-devkit/tests/verification/test_matrix_detect_unittest_fallback.sh |

### devkit-matrix-driver-refresh — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-MATRIX-DRIVER-REFRESH-01 | githooks refresh-matrix-driver (SessionStart): lệnh merge driver cũ được ghi lại bản mới; lệnh đã đúng thì im lặng, không ghi config; repo chưa cài driver thì không bị cài | chưa chạy | bash universal-agent-devkit/tests/worktree_git/test_matrix_driver_refresh.sh |

### devkit-matrix-merge-driver — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-MATRIX-MERGE-01 | merge driver ma trận hồi quy: hai nhánh cùng nối rule khác nhau vào cuối thì gộp không conflict và gate vẫn tin ma trận chỉ-thêm; cùng id khác nội dung thì lỗi rõ; sửa rule cũ vẫn conflict; githooks install cài driver | 2026-10-24 15:47:42 · 4.44s · exit 0 · ae868292+dirty · [log](evidence/REG-DK-MATRIX-MERGE-01/20261024-154742.log) | bash universal-agent-devkit/tests/gates/test_matrix_merge_driver.sh |

### devkit-multi-session-gate-env — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-SESSION-ENV-01 | test_multi_session_gate + test_gate_stop_reuse_race xanh khi id phiên của máy thật (CLAUDE_CODE_SESSION_ID, DEVKIT_SESSION_ID) rò vào môi trường (#240) | 2026-10-24 13:07:21 · 15.95s · exit 0 · 38166b6b+dirty · [log](evidence/REG-DK-SESSION-ENV-01/20261024-130712.log) | bash universal-agent-devkit/tests/gates/test_multi_session_gate_session_env.sh |

### devkit-ocr-review-content-map — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-OCR-REVIEW-CONTENT-01 | Đợt 2 gate mục 6 (04/11): ocr-review ghi content_sha256 + content_base của file đã review, hash trước khi review chạy | chưa chạy | bash universal-agent-devkit/tests/installer/test_ocr_review_content.sh |

### devkit-regression-gate-reminder-approval-key — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-REMINDER-APPROVAL-KEY-01 | Đợt 2 gate mục 3 (04/11): nhắc 'test sửa chờ duyệt' khoá theo cây + digest sổ duyệt, bỏ TTL 300 s; sổ duyệt đổi thì chạy lại | chưa chạy | bash universal-agent-devkit/tests/gates/test_regression_gate_reminder_approval_key.sh |

### devkit-regression-gate-reminder-throttle — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-REMINDER-THROTTLE-01 | Nhắc 'test sửa chờ duyệt' không chạy lại cả gate mỗi lần Stop khi cây và sổ duyệt không đổi (ca 4 cập nhật đợt 2: khoá theo digest, không TTL) | chưa chạy | bash universal-agent-devkit/tests/gates/test_regression_gate_reminder_throttle.sh |

### devkit-review-gate-ocr-content — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-REVIEW-GATE-OCR-CONTENT-01 | Đợt 2 gate mục 6 (04/11): review_gate công nhận báo cáo OCR theo hash nội dung file thay vì mtime | chưa chạy | bash universal-agent-devkit/tests/gates/test_review_gate_ocr_content.sh |

### devkit-scoped-per-test-cache-p4 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-SCOPED-PER-TEST-CACHE-01 | PR 1 gate kẹt (P4): lượt --scoped bật sổ PASS per-test của run_impacted.sh — cùng cây, test đã PASS in ↺ (ptc_reuse > 0), chỉ test đỏ chạy lại; --scoped --no-cache và DEVKIT_GATE_CACHE=0 chỉ ghi (mọi test chạy thật) | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_scoped_per_test_cache.sh |

### devkit-sentinel-merge-env — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ❌ TIMEOUT | REG-DK-SENTINEL-MERGE-ENV-01 | test_gate_sentinel.sh xanh khi DEVKIT_SLOT_PRIORITY=merge / DEVKIT_SLOT_LOAD_WAIT_S=0 rò từ merge gate vào verify (#167) | 2026-10-24 13:13:52 · 21.64s · exit None · b93a50cc+dirty · [log](evidence/REG-DK-SENTINEL-MERGE-ENV-01/20261024-131352.log) | bash universal-agent-devkit/tests/gates/test_gate_sentinel_merge_env.sh |

### devkit-session-card-hook — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-SESSION-CARD-01 | 03/11 chủ repo: task bắt đầu từ chat có đúng MỘT thẻ board (nhãn session, cột Building) từ lần sửa file đầu; bỏ qua subagent, lane issue-N, repo không board, file ngoài repo; không chặn, thử lại 3 lần | chưa chạy | bash universal-agent-devkit/tests/gates/test_session_card_hook.sh |

### devkit-session-card-title-envelope — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-SESSION-CARD-TITLE-01 | #1140: tiêu đề thẻ phiên lấy từ dòng người dùng viết: bóc khối <system-reminder> (nhiều khối, nhiều dòng) và thẻ bọc <pasted_content>, giữ nội dung dán; prompt chỉ có khối reminder rơi về transcript rồi tiêu đề mặc định theo file sửa đầu tiên | chưa chạy | bash universal-agent-devkit/tests/gates/test_session_card_title_envelope.sh |

### devkit-session-lock — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-SESSION-01 | session lock + multi-session gate verdict (own session is never counted as another) | 2026-10-24 13:29:26 · 12.85s · exit 0 · b93a50cc+dirty · [log](evidence/REG-DK-SESSION-01/20261024-132926.log) | bash universal-agent-devkit/tests/context_memory/test_session_lock.sh && bash universal-agent-devkit/tests/gates/test_multi_session_gate.sh |

### devkit-session-lock-grok-shell — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-SESSION-LOCK-GROK-SHELL-01 | #1146: công cụ shell của Grok (run_terminal_command, run_terminal_cmd, Shell, hoặc tên lạ mang `command`) bị luật trunk mode xét y như Bash: `git checkout --detach` hay redirect vào checkout chính bị chặn (rc 2), lệnh hợp lệ của lane (git fetch, git -C <worktree>, worktree.py add) vẫn qua, công cụ MCP không bị xét | chưa chạy | bash universal-agent-devkit/tests/context_memory/test_session_lock_grok_shell.sh |

### devkit-settings-read-deny-apk — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-SETTINGS-READ-DENY-APK-01 | luật deny Read của settings không chặn build/outputs và *.apk (worker QA liệt kê, cài APK debug), vẫn chặn build/intermediates, build/tmp, *.aab, *.hprof | chưa chạy | bash universal-agent-devkit/tests/verification/test_settings_template_read_deny.sh |

### devkit-shard-group-job-pool — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-JOB-POOL-01 | 04/11 Việc 2: tests/lib/job_pool.py — tối đa <size> việc cùng lúc giữa nhiều tiến trình, --alone không chạy cạnh ai, holder chết nhả slot, không có bể thì chạy ngay, dòng · start chỉ in khi đã giữ slot | chưa chạy | bash universal-agent-devkit/tests/gates/test_job_pool.sh |
| ⏳ chưa chạy | REG-DK-RUNNER-SHARED-POOL-01 | 04/11 Việc 2: hai run_impacted.sh chung DEVKIT_TEST_POOL_DIR không vượt DEVKIT_TEST_JOBS test cùng lúc, test alone chạy một mình, biến bể/JOBS không rò vào test | chưa chạy | bash universal-agent-devkit/tests/gates/test_run_impacted_shared_pool.sh |

### devkit-shell-writes-dollar-quotes — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-SHELL-WRITES-DQ-01 | T4 #844: đích ghi dạng $'…' / $"…" (đích, động từ, bash -c, cd, heredoc cho shell) được shell_writes đọc thêm đã giải mã - worktree_guard, session_lock (anh em bị giữ, bash_collides, trunk_write) chặn; đích của cách đọc cũ còn nguyên; lệnh tìm kiếm rg/grep -E/git grep/sed vẫn qua | chưa chạy | bash universal-agent-devkit/tests/gates/test_shell_writes_dollar_quotes.sh |

### devkit-skill-description-budget — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-SKILL-DESC-BUDGET-01 | T0211: mọi description skill/command được liệt kê (kit skills, commands, .claude/skills) ≤ 300 byte UTF-8, không rỗng | chưa chạy | bash universal-agent-devkit/tests/verification/test_skill_description_budget.sh |

### devkit-slot-classes — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-SLOT-CLASSES-01 | quyền chạy theo tải máy của từng suite (P1b): bỏ 2 slot engine; tải cao thì chờ rồi vẫn chạy, không UNTESTED; chờ tải không ăn vào thời gian chờ khoá; khoá Unity (độc quyền) vẫn chặn, không còn khoá thiết bị; bash -lc nhận ra Unity; hàng đợi ưu tiên + SJF; suite STALE bị SLOT không lọt PASS | 2026-10-24 13:30:29 · 62.23s · exit 0 · b93a50cc+dirty · [log](evidence/REG-DK-SLOT-CLASSES-01/20261024-133029.log) | bash universal-agent-devkit/tests/gates/test_gate_slot_classes.sh |

### devkit-slot-prio-aging — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-SLOT-AGING-01 | hàng đợi vé heavy_slot lão hoá ưu tiên (P2): mỗi DEVKIT_SLOT_PRIO_AGE_S (450 s) đã chờ lên một mức tới merge; interactive chờ 1000 s đứng trước merge mới đến, chờ 10 s vẫn sau; núm 0/rác = mặc định, không chia cho 0 | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_slot_aging.sh |

### devkit-suite-cache — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-SUITE-CACHE-01 | cache PASS theo khoá nội dung từng suite (cached-full): chỉ suite có input đổi chạy lại; khoá chính xác chỉ cho suite thêm vào, suite được chọn theo khoá cả cây; FAIL dính khoá, không-PASS vô hiệu PASS cũ; PASS theo khoá chính xác không vào biên nhận / DEVKIT_GATE_DONE; gộp lượt trùng khoá; suite tự sửa input không được ghi | 2026-10-24 13:30:59 · 28.34s · exit 0 · b93a50cc+dirty · [log](evidence/REG-DK-SUITE-CACHE-01/20261024-133059.log) | bash universal-agent-devkit/tests/gates/test_gate_suite_cache.sh |

### devkit-suite-cache-selection-inputs — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-SUITE-CACHE-SEL-INPUTS-851-01 | #851: suite run_impacted.sh có dấu devkit-selection-inputs khoá chính xác theo input của tập chọn (đồ thị scoped_gate, symlink kit, dữ liệu code nhắc, công cụ và đích ngoài cây của tập chọn, bỏ DEVKIT_SCOPED_TESTS); test quét cả kit (devkit-selection-tree) trong tập ⇒ chỉ khoá cả cây; merge gate H+main dùng lại shard khi main đổi file ngoài input | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_suite_cache_selection_inputs.sh |

### devkit-suite-cache-sentinel — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-SENTINEL-01 | sentinel: lần chạy thật > 24 h thì --full không dùng khoá (không ở merge gate), suite quá giờ không đóng mốc; cache sai thì học input thiếu hoặc cách ly flaky; run_one/nightly ghi cùng sổ khoá | 2026-10-24 13:13:27 · 35.73s · exit 0 · b93a50cc+dirty · [log](evidence/REG-DK-SENTINEL-01/20261024-131326.log) | bash universal-agent-devkit/tests/gates/test_gate_sentinel.sh |

### devkit-suite-timeout-gates-shard — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-SUITE-TIMEOUT-GATES-01 | #801 / chủ repo 02/11: shard REG-DK-ALL-GATES-01 được trần gấp đôi --timeout (900 → 1800 s, SUITE_TIMEOUT_FACTOR); suite khác giữ trần cũ; --timeout dưới sàn DEVKIT_GATE_EXTEND_MIN_S (giờ ngắn của test) không nâng | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_suite_timeout_gates_shard.sh |

### devkit-test-run-lock-holder-session — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-TEST-RUN-LOCK-SESSION-01 | Đợt 2 gate mục 4 (04/11): khoá test_run.lock do chính phiên giữ thì trả BUSY ngay; holder cùng phiên không đọc được giờ khởi động vẫn BUSY (không thành exit 0 chỉ đọc) | chưa chạy | bash universal-agent-devkit/tests/gates/test_test_run_lock_holder_session.sh |

<details><summary>✅ devkit-token-cost — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-COST-01 | token cost tracker counts each message id once and prices the longest model key | 2026-10-23 07:29:43 · 0.53s · exit 0 · fcca1085+dirty · [log](evidence/REG-DK-COST-01/20261023-072508.log) | bash universal-agent-devkit/tests/context_memory/test_token_cost_tracker.sh |

</details>

### devkit-tree-fp-settings-local — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-TREE-FP-SETTINGS-01 | tree_fingerprint bỏ qua sửa chưa commit của .claude/settings.json (bản cài kit), vẫn tính nội dung đã commit và mọi file tracked khác (#691) | chưa chạy | bash universal-agent-devkit/tests/gates/test_tree_fp_settings_local.sh |

### devkit-verification-py — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-VERIFY-PY-01 | unity compile skip when editmode/playmode runs + proof-capture run-before under device lock | 2026-10-24 13:07:21 · 10.46s · exit 0 · 38166b6b+dirty · [log](evidence/REG-DK-VERIFY-PY-01/20261024-124402.log) | python3 universal-agent-devkit/tests/verification/test_unity_compile_skip.py && python3 universal-agent-devkit/tests/verification/test_proof_run_before.py |

### devkit-worktree-merge-gate-block-reason-log — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-WT-MERGE-GATE-REASON-LOG-01 | Đợt 2 gate mục 8 (04/11): worktree_merge_gate ghi một dòng log cho mỗi lần giữ và nhả Stop; state quá 1 MiB coi như không có | chưa chạy | bash universal-agent-devkit/tests/gates/test_worktree_merge_gate_block_reason_log.sh |

### devkit-worktree-prune-merged-ancestor — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-WT-PRUNE-MERGED-ANCESTOR-01 | #453 prune-branch nhận nhánh có tip là tổ tiên head của PR MERGED vào trunk (PR lấy head từ nhánh khác); commit ngoài head đó, hoặc PR gộp vào nhánh khác trunk: giữ | chưa chạy | bash universal-agent-devkit/tests/worktree_git/test_worktree_prune_ancestor_of_merged.sh |

### devkit-worktree-sandbox — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-SANDBOX-01 | worktree sandbox cleanup keeps unmerged work unless --force | 2026-10-24 13:07:21 · 48.68s · exit 0 · 38166b6b+dirty · [log](evidence/REG-DK-SANDBOX-01/20261024-125631.log) | bash universal-agent-devkit/tests/worktree_git/test_worktree_sandbox.sh |

### durations-union-merge — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-DURATIONS-UNION-01 | test_durations.txt gộp bằng merge=union: hai nhánh cùng nối dòng cuối không xung đột, dòng trùng còn một (#302) | chưa chạy | bash universal-agent-devkit/tests/gates/test_durations_union_merge.sh |

### essentials-pr-repo-no-local-gate — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-ESSENTIALS-PR-NO-LOCAL-GATE-984-01 | 05/11 (#984): repo đi PR không chạy gate scoped ở local, push rồi merge gate --dry-run nền; repo push trunk giữ gate local | chưa chạy | bash universal-agent-devkit/tests/verification/test_essentials_pr_repo_no_local_gate.sh |

### essentials-pr-repo-no-local-regate-997 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-ESSENTIALS-PR-NO-LOCAL-REGATE-997-01 | #997: essentials bước 5 (PR repo: merge receipt), câu Git (not in a PR repo) và core-rules §19 không còn bảo repo đi PR chạy lại gate scoped local; merge gate là gate | chưa chạy | bash universal-agent-devkit/tests/verification/test_essentials_pr_repo_no_local_regate.sh |

### file-wait-ready-556 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-FILE-WAIT-556-01 | #556: sequence conflictWith giữ Ready + nhãn chờ thẻ khác, gỡ khi PR không còn đụng file, không tính RUNAWAY, không giao cùng thẻ đụng file | chưa chạy | bash tests/super-board/test_runner_file_wait.sh |

### gate-approval-fresh-worktree-628 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GATE-APPROVAL-FRESH-WT-628-01 | #628 AC2: lời duyệt test (approved_hashes.json) của main checkout còn hiệu lực ở worktree mới (chỉ so sha256 nội dung, không mtime); đổi 1 byte test: vẫn exit 2 | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_approval_fresh_worktree.sh |

### gate-cache-ttl-3d — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-CACHE-TTL-3D-01 | 05/11: hạn tuổi mặc định của PASS dùng lại là 3 ngày (khoá nội dung, biên nhận --full, biên nhận scoped): 2 ngày dùng lại, 4 ngày không; DEVKIT_GATE_CACHE_MAX_S vẫn ghi đè | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_cache_ttl_3d.sh |

### gate-cross-review-approval-605 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GATE-CROSS-REVIEW-605-01 | #605: test có sẵn bị sửa chỉ được duyệt chéo (approved_tests.json approvals: reviewer khác author/DEVKIT_AGENT_ID, sha256 khớp, đủ 6 trường); tự duyệt (--auto-approve-tests, DEVKIT_AUTO_APPROVE_TESTS, AUTO-APPROVE:) và dạng cũ không nguồn = exit 2, in cần duyệt lại + sha256 | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_cross_review_approval.sh |

### gate-fail-fast-647 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-FAIL-FAST-647-01 | #647: suite FAIL hoặc TIMEOUT thì phần NOT_RUN còn lại thành UNTESTED; --no-fail-fast chạy tiếp; merge-train và gate_full truyền cờ | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_fail_fast.sh |

### gate-matrix-append-only-coverage-p6 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GATE-MATRIX-APPEND-COVERAGE-P6-01 | P6: PR chỉ nối rule ma trận ở repo không [smoke], không rule theo dõi ma trận — test mới XANH ⇒ exit 0 (không còn no_match exit 2); test mới ĐỎ ⇒ 1; code không test, ma trận không đổi ⇒ vẫn 2 | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_matrix_append_only_coverage.sh |

### gate-merge-guard-inject — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-MERGE-GUARD-INJECT-01 | Gate speed v26 mục 7: [merge-guard] (∪ base) tiêm sau cap chỉ ở điểm gộp, luôn chạy thật, id thiếu trong ma trận ⇒ đỏ | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_merge_guard_inject.sh |

### gate-merge-width-slots — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-MERGE-WIDTH-SLOTS-01 | Gate speed v26 mục 10: cần gạt độ rộng và sàn slot của điểm gộp mặc định tắt (đo tải 08/11 trượt ngưỡng), bật khi đặt biến; verify lạc quan hạn từ số lõi; guard có hạn giờ chạy sau cùng | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_merge_width_slots.sh |

### gate-reject-rerun-trunc-timeout-992 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-REJECT-RERUN-TRUNC-TIMEOUT-992-01 | #992: khối 'Chạy lại riêng' của REJECT in '… +N' khi cắt 20 lệnh, shard TIMEOUT có lệnh cả shard, vế 'không chạy lại cả gate local' chỉ ở repo đi PR | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_reject_rerun_trunc_timeout.sh |

### gate-rerun-skip-648 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-RERUN-SKIP-648-01 | #648: cùng cây, cùng chế độ, cùng danh sách suite thì thoát 0 từ rerun_skip.json trước khi lấy khoá; --force, --no-cache và DEVKIT_GATE_CACHE=0 vẫn chạy | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_rerun_skip.sh |

### gate-same-tree-reuse-d1a — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-SAME-TREE-REUSE-01 | D1(a): lượt không cưỡng bức (Stop, task, --scoped) dùng lại PASS thật cùng cây ≤ 1 h; đổi byte chạy lại; --full không dùng; quá hạn chạy lại | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_scoped_same_tree_reuse.sh |

### gate-scoped-no-fail-fast — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GATE-SCOPED-NO-FAIL-FAST-01 | 04/11: lượt --scoped chạy hết suite và lộ mọi suite đỏ trong một lượt; --fail-fast bật lại; lượt không --scoped giữ fail-fast; lane_lock coi --fail-fast là việc nhẹ | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_scoped_no_fail_fast.sh |

### gate-slot-holder-log — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GATE-SLOT-HOLDER-984-01 | 05/11 (#984 a): lượt xin slot pool gate ghi gate_slot vào runs.jsonl (giữ được / hết giờ), gate_speed_report in giây giữ theo loại lượt, repo và lúc merge gate chờ | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_slot_holder_log.sh |

### gate-speed-report-merge-p90 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GATE-SPEED-MERGE-P90-01 | 04/11 (#983): gate_speed_report đếm mode=scoped và in p90 merge gate thật (.merge-scratch-*, gồm chờ khoá) + lock_p90, có trong bảng --baseline | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_speed_report_merge_p90.sh |

### guard-push-742-split-a1 — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-742-A1-GUARD-PUSH-WRAPPERS-01 | #742 tách A1 (critical scan 31/10, BUG-REV-gpp-*): guard-protected-push chặn force push lên main sau wrapper/keyword (time, nohup, nice, timeout, env -i, sudo -u, if/then, { }, !), trong bash -lc STR, sau --signed / --repo, sau comment có dấu nháy; đọc payload camelCase; config FIFO không treo hook; mỗi ca có đối chứng không force vẫn được phép | chưa chạy | bash universal-agent-devkit/tests/gates/test_guard_protected_push_wrappers.sh |
| ⏳ chưa chạy | REG-742-A1-PUSH-GATE-DEVKIT-NO-MATRIX-01 | #742 tách A1 (#482, BUG-REV-push-gate-own-check-devkit): push_gate.check() từ chối main checkout đã cài DevKit (.agents/devkit) mà mất ma trận hồi quy; repo chưa cài DevKit không ma trận vẫn qua | chưa chạy | bash universal-agent-devkit/tests/gates/test_push_gate_devkit_no_matrix.sh |

### issue-363-batch — 0/8 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GIT241-ATTR-01 | worktree prune-branch không từ chối nhầm trên git 2.41 thiếu --attr-source (#371) | chưa chạy | bash universal-agent-devkit/tests/worktree_git/test_worktree_git241_attr_source.sh |
| ⏳ chưa chạy | REG-DK-GITHOOKS-HEAL-01 | githooks cài từ worktree rồi xoá worktree vẫn chạy; heal cài lại hook trỏ đường mất (#363) | chưa chạy | bash universal-agent-devkit/tests/worktree_git/test_githooks_heal.sh |
| ⏳ chưa chạy | REG-DK-GUARD-SECRETS-01 | guard-secrets không chặn nhầm thông điệp commit, vẫn chặn đọc dotenv (#367) | chưa chạy | bash universal-agent-devkit/tests/gates/test_guard_secrets.sh |
| ⏳ chưa chạy | REG-DK-SUITE-CACHE-FIFO-01 | suite_cache không treo trên FIFO ở learned_inputs/.run/prune.stamp (#371) | chưa chạy | bash universal-agent-devkit/tests/gates/test_suite_cache_store_fifo.sh |
| ⏳ chưa chạy | REG-DK-WT-REMOVE-DURATIONS-01 | worktree remove không bị chặn bởi diff chỉ ở test_durations.txt (#365) | chưa chạy | bash universal-agent-devkit/tests/worktree_git/test_worktree_remove_durations.sh |
| ⏳ chưa chạy | REG-SB-DRIFT-01 | phát hiện bản sao super-board ở repo app bị lệch hash (#368) | chưa chạy | bash tests/super-board/test_drift.sh |
| ⏳ chưa chạy | REG-SB-QA-REPORT-01 | merge gate từ chối report QA còn ❌ Not done và AC [x] không bằng chứng (#364) | chưa chạy | bash tests/super-board/test_merge_gate_qa_report.sh |
| ⏳ chưa chạy | REG-SB-REVIEW-SLOT-01 | lane Review không bị bỏ đói slot (#369) | chưa chạy | bash tests/super-board/test_runner_review_slot.sh |

### kit-merge-tree-no-leak — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-MERGE-TREE-NOLEAK-01 | merge-tree dò bị kill giữa chừng không để .merge_file_* ở cây làm việc (cwd tạm), kết luận 'đã tích hợp' không đổi khi driver chạy kịp (#309) | 2026-10-24 14:58:53 · 1.44s · exit 0 · 7a3d58a8+dirty · [log](evidence/REG-DK-MERGE-TREE-NOLEAK-01/20261024-145853.log) | bash universal-agent-devkit/tests/worktree_git/test_worktree_merge_tree_no_leak.sh |

### matrix-real-readers-p6 — 0/3 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-MATRIX-READER-QA-EXIT2-P6-01 | P6: test đọc ma trận thật — #643 rule qa-exit2 / spawn-load trong ma trận (cùng lệnh REG-SB-QA-EXIT2-643-01) | chưa chạy | bash tests/super-board/test_qa_exit2_edited_test.sh |
| ⏳ chưa chạy | REG-DK-MATRIX-READER-SHARD-P6-01 | P6: test đọc ma trận thật — #616 khối shard REG-DK-ALL-* (cùng lệnh REG-DK-ALL-SHARD-RULES-616-01, gate chia kết quả theo lệnh) | chưa chạy | bash tests/super-board/test_matrix_shard_rules.sh |
| ⏳ chưa chạy | REG-DK-MATRIX-REAL-READERS-P6-01 | P6: test nào mở ma trận thật ở gốc repo (biến dirname $0 + .agents/regression_matrix.active.json) mà không nằm trong rule có ma trận trong watch_files ⇒ ĐỎ (PR nối rule chỉ chạy danh sách đó) | chưa chạy | bash universal-agent-devkit/tests/gates/test_matrix_real_readers.sh |

### mcp-servers/agent-office — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-AGENT-OFFICE-01 | agent-office: unittest (server, redact, host check) và tìm đường A* của người đi trong xưởng (node) | 2026-10-24 12:09:21 · 8.36s · exit 0 · 38166b6b+dirty · [log](evidence/REG-AGENT-OFFICE-01/20261024-120921.log) | cd mcp-servers/agent-office && python3 -m unittest discover -s tests |

<details><summary>✅ mcp-servers/agent-office/blender — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-AGENT-OFFICE-02 | agent-office: bộ nội thất office.glb dựng bằng Blender còn đủ khối có tên (Desk, Chair, Monitor/Screen có UV, Shelf...) và đủ nhỏ | 2026-10-24 13:07:21 · 0.07s · exit 0 · 38166b6b+dirty · [log](evidence/REG-AGENT-OFFICE-02/20261024-130523.log) | cd mcp-servers/agent-office && python3 -m unittest tests.test_office_glb |

</details>

### mcp-servers/agent-office/gate-full-runner — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-AGENT-OFFICE-GATE-FULL-RUNNER-01 | agent-office: nút "Chạy gate full" — hàng đợi FIFO bỏ trùng, lưu qua khởi động lại, một lượt mỗi lúc, chờ khoá toàn máy, huỷ, repo chưa cài lịch, đọc khoá repo không flock, endpoint chặn tunnel/CSRF/DNS rebinding (gate_full.py giả) | chưa chạy | cd mcp-servers/agent-office && python3 -m unittest discover -s tests -p test_gate_full_runner.py |

### mcp-servers/antigravity-pm-mcp — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-AUTO-ANTIGRAVITY-PM-MCP-01 | antigravity-pm-mcp: package.json test script | 2026-10-24 13:07:21 · 98.05s · exit 0 · 38166b6b+dirty · [log](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261024-124541.log) | cd mcp-servers/antigravity-pm-mcp && npm test |

### mcp-servers/cc-switcher-mcp — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-AUTO-CC-SWITCHER-MCP-01 | cc-switcher-mcp: package.json test script | 2026-10-24 13:07:21 · 0.45s · exit 0 · 38166b6b+dirty · [log](evidence/REG-AUTO-CC-SWITCHER-MCP-01/20261024-125635.log) | cd mcp-servers/cc-switcher-mcp && npm test |

### mcp-servers/play-store-mcp — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-AUTO-PLAY-STORE-MCP-01 | play-store-mcp: pytest | 2026-10-24 13:07:21 · 47.36s · exit 0 · 38166b6b+dirty · [log](evidence/REG-AUTO-PLAY-STORE-MCP-01/20261024-124450.log) | cd mcp-servers/play-store-mcp && uv run --frozen --extra dev pytest -q |

### merge-gate-approved-head-receipt — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-APPROVED-HEAD-RECEIPT-01 | gate đẩy merge commit Y rồi thoát: lượt gate thứ hai vẫn nhận duyệt của X qua biên nhận; commit người đẩy thêm thì đòi duyệt lại (#262) | chưa chạy | bash tests/super-board/test_merge_gate_approved_head_second_run.sh |

### merge-gate-autosync-pm-approval — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-AUTOSYNC-PM-01 | 04/11: merge gate tự gộp base (driver ma trận) cho PR có duyệt test sửa từ biên bản PM khi verify chạy post-fix-gate; comment edited-tests và pm không gate vẫn exit 14 | chưa chạy | bash tests/super-board/test_merge_gate_autosync_pm_approval.sh |

### merge-gate-ci-742-split-a4 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-742-A4-MERGE-GATE-CI-01 | #742 tách A4 (F5): merge gate đọc gh pr checks sau verify, trước migration và merge: check đỏ hay bucket lạ/rỗng → exit 11, không merge, migration không chạy, tên check trên stdout và stderr; không đọc được → exit 4; no checks reported → merge như cũ; pending rồi pass → merge, pending quá SB_MERGE_AUTO_WAIT_S → exit 4; --dry-run đọc CI một lần không ngủ; head đổi lúc chờ hay lúc check đỏ → exit 6 không in ci-check; mỗi ca có đối chứng | chưa chạy | bash tests/super-board/test_merge_gate_ci_checks.sh |

### merge-gate-conflicting-precheck — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-GATE-CONFLICTING-01 | #881 #883 #885 (02/11): driver gộp chỉ có ở local (merge=union, devkit-matrix) ⇒ scratch sạch nhưng GitHub CONFLICTING; merge gate đọc mergeable trong khoá trước verify: CONFLICTING (cả sau UNKNOWN) ⇒ exit 14, không verify, không gh pr merge, câu báo gộp origin/main + push + --expect-head mới, khoá được thả; MERGEABLE, UNKNOWN rồi MERGEABLE, UNKNOWN mãi (đọc lại có giới hạn) và lỗi đọc ⇒ verify + merge như cũ, không halt | chưa chạy | bash tests/super-board/test_merge_gate_conflicting_precheck.sh |
| ⏳ chưa chạy | REG-SB-MERGE-QUEUE-EXIT14-01 | PR #893: train in gate-exit-14 (GitHub CONFLICTING, cả ở --preflight) ⇒ merge queue route như xung đột: thẻ về Ready + loop:rebase, gỡ nhãn merge-queue, comment PR và thẻ ghi GitHub CONFLICTING; không tính lần thử lại, không Blocked | chưa chạy | bash tests/super-board/test_merge_queue_gate_exit_14.sh |

### merge-gate-edited-test-486 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-MERGE-GATE-EDITED-TEST-486-01 | #486: worktree finish từ chối gate exit 2 (test đã sửa chưa duyệt, nêu tên file), exit 1 khi suite PASS, và exit 4 nhãn SLOT; exit 0, exit 3, và exit 4 thiếu thiết bị vẫn fast-forward | chưa chạy | bash universal-agent-devkit/tests/worktree_git/test_worktree_merge_gate_edited_test.sh |

### merge-gate-install-untracked-merge-error — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-ERROR-SHOWN-01 | GeelyEx2 #179: git merge base vào scratch bị hook commit-msg từ chối (không file xung đột) ⇒ gate in stderr thật, không in 'conflicts:' rỗng, không bảo rebase; xung đột thật vẫn in tên file + rebase pass; exit 5 giữ nguyên | chưa chạy | bash tests/super-board/test_merge_gate_merge_error_shown.sh |
| ⏳ chưa chạy | REG-SB-MERGE-INSTALL-UNTRACKED-01 | Idle #18: install.sh ghi .mcp.json/.gemini chưa track vào scratch ⇒ merge gate xoá phần install.sh thêm (chụp ls-files --others trước/sau), giữ .agents/devkit bị ignore và file PR đã track (kể cả cùng tên bị install ghi đè); PR Markdown verify xanh, dry run exit 0 | chưa chạy | bash tests/super-board/test_merge_gate_install_untracked.sh |

### merge-gate-lock-shared-worktrees — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-LOCK-SHARED-WT-01 | 02/11 lane rmlock: khoá merge nằm trong git common dir, chung mọi worktree: gate ở worktree B thấy khoá gate ở worktree A đang giữ (exit 4 / chờ tới khi A nhả); khoá common dir của pid đã chết được reap, của pid sống giữ nguyên; REPO_PATH không phải repo git thì giữ đường cũ và nói ra | chưa chạy | bash tests/super-board/test_merge_gate_lock_shared_worktrees.sh |

### merge-gate-no-push-pr-branch — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-GATE-NO-PUSH-PR-01 | gate không ghi lên nhánh PR: PR chậm hơn base thì head trên origin giữ nguyên, verify chạy trên cây scratch đã gộp, approved-head và --match-head-commit vẫn khớp head PR (#570) | chưa chạy | bash tests/super-board/test_merge_gate_no_push_pr_branch.sh |

### merge-gate-no-stale-verify-1012 — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-INLOCK-SYNC-1012-01 | #1012 (a): GitHub báo CONFLICTING chỉ trong khoá (main dời lúc verify, chỉ file có driver gộp đặt tên) ⇒ gộp base mới, verify lại trong khoá, đẩy merge commit đồng bộ rồi merge, không exit 14; file không driver và --dry-run vẫn exit 14 | chưa chạy | bash tests/super-board/test_merge_gate_conflicting_in_lock_sync.sh |
| ⏳ chưa chạy | REG-SB-MERGE-WAIT-HOLDER-1012-01 | #1012 (b): khoá merge đang bị gate sống giữ ⇒ gate lạc quan chờ nó thả rồi verify đúng một lần trên base mới; người giữ chết không chờ; hết SB_MERGE_WAIT_HOLDER_S thì verify như cũ | chưa chạy | bash tests/super-board/test_merge_gate_wait_lock_holder.sh |

### merge-gate-opt-load-cap — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-OPT-LOAD-CAP-01 | 05/11 chủ repo: hạn số merge gate chạy cùng lúc theo tải — tải ≥ số lõi thì verify lạc quan (ngoài khoá) chỉ thấy N−1 slot pool gate, slot cuối để dành cho verify trong khoá; 3 merge gate cùng lúc tối đa 1 verify lạc quan chạy suite; hết SB_MERGE_OPT_SLOT_WAIT_S thì chạy với cả pool; tải thấp và verify trong khoá như cũ | chưa chạy | bash tests/super-board/test_merge_gate_opt_load_cap.sh |

### merge-gate-scratch-agents-clean — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-SCRATCH-AGENTS-CLEAN-01 | scratch của merge gate không để AGENTS.md đã track bị sửa sau khi cài DevKit (#234) | chưa chạy | bash tests/super-board/test_merge_gate_scratch_agents_clean.sh |

### merge-gate-stale-unreadable-831 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-MERGE-GATE-STALE-UNREADABLE-01 | #831: worktree finish từ chối gate exit 4 có suite nhãn STALE (cả khi lẫn suite thiếu thiết bị) và exit 2 có file unreadable (nêu tên, en+vi); exit 4 chỉ thiếu thiết bị và exit 2 no_match vẫn fast-forward | chưa chạy | bash universal-agent-devkit/tests/worktree_git/test_worktree_merge_gate_stale_unreadable.sh |

### merge-guard-checklist-journal — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GUARD-CHECKLIST-JOURNAL-01 | merge-guard: nhật ký checklist không mất dòng (gate speed v26 mục 7) | chưa chạy | bash universal-agent-devkit/tests/verification/test_checklist_journal.sh |

### merge-guard-gate-audit-holes — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GUARD-GATE-AUDIT-HOLES-01 | merge-guard: lỗ kiểm của post-fix-gate đã vá vẫn kín (gate speed v26 mục 7) | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_audit_holes.sh |

### merge-guard-git-guard-bypass — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GUARD-GIT-BYPASS-01 | merge-guard: git guard không bị lách (gate speed v26 mục 7) | chưa chạy | bash universal-agent-devkit/hooks/tests/test_git_guard_bypass.sh |

### merge-guard-hardware-rm — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GUARD-HARDWARE-RM-01 | merge-guard: rm trong hardware_safety_gate bị giam đúng phạm vi (gate speed v26 mục 7) | chưa chạy | bash universal-agent-devkit/tests/gates/test_hardware_rm_containment.sh |

### merge-guard-merge-policy-sql — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-GUARD-MERGE-POLICY-SQL-01 | merge-guard: merge policy bắt mọi dạng SQL phá dữ liệu (gate speed v26 mục 7) | chưa chạy | bash tests/super-board/test_merge_policy_sql_forms.sh |

### merge-guard-push-gate-integrity — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GUARD-PUSH-GATE-INTEGRITY-01 | merge-guard: push gate không bị lách (gate speed v26 mục 7) | chưa chạy | bash universal-agent-devkit/tests/gates/test_push_gate_integrity.sh |

### merge-policy-diff-paths-742-split-a3 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-742-A3-MERGE-POLICY-DIFF-PATHS-01 | #742 tách A3 (review P0 d1facdea5d, INSTINCT-089): merge-policy đọc đường dẫn file bị xoá từ header diff git: C-quoted (UTF-8, dấu cách, escape bát phân), file rỗng chỉ có diff --git + deleted file mode, tên chứa " b/"; header không đọc được → delete-protected (fail-closed, trừ protected_paths []); dòng nội dung hunk giả --- a/ + +++ /dev/null không tính là xoá | chưa chạy | bash tests/super-board/test_merge_policy_diff_header_paths.sh |

### merge-queue-parallel-trains — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-QUEUE-PARALLEL-01 | #676: queue lượt ngắn phóng một train nền mỗi PR (PR đến sau không chờ train khác, khoá queue không giữ lúc verify chờ slot, max_trains, train chết ⇒ một lần thử, base-moved không tính lần thử); train claim theo PR, verify --scoped gọi thẳng post-fix-gate; gate --require-receipt thoát 12 khi base dời ⇒ train verify lại ngoài khoá (2 lần rồi base-moved); gh pr merge không chồng; BUSY ⇒ timeout; status gộp state các train sống | chưa chạy | bash tests/super-board/test_merge_queue_parallel.sh |

### merge-scratch-keep-559 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-SCRATCH-KEEP-559-01 | #559: REG-DK-ALL-01 không PASS thì giữ scratch, log đỏ và env.txt đã che secret; PASS thì dọn; tối đa 2 bản | chưa chạy | bash tests/super-board/test_merge_gate_keep_scratch.sh |

### merge-scratch-keep-shards-712 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-SCRATCH-KEEP-SHARDS-712-01 | #712: merge gate giữ scratch cả khi shard REG-DK-ALL-GATES/WORKTREE/REST-01 FAIL/TIMEOUT/HANG (dòng '<ID> : …' có mã màu); PASS, UNTESTED và suite khác chỉ nhắc REG-DK-ALL-01 trong mô tả thì không | chưa chạy | bash tests/super-board/test_merge_gate_keep_scratch_shards.sh |

### merge-train-hook-refusal — 0/3 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-STDERR-FILE-01 | #775: merge gate ghi stderr của git merge ra file (hook để tiến trình nền giữ stderr không làm gate treo), in dòng CONFLICT của git khi xung đột thật, giữ link .agents/devkit khi repo không ignore nó | chưa chạy | bash tests/super-board/test_merge_gate_merge_stderr.sh |
| ⏳ chưa chạy | REG-SB-MQ-REFUSED-DETAIL-01 | #775: queue route gate-exit-5 kèm train-detail (git/hook từ chối) ⇒ comment PR + thẻ ghi 'merge refused' kèm lời hook, vẫn loop:rebase + Ready; conflict thật giữ chữ cũ | chưa chạy | bash tests/super-board/test_merge_queue_refused_detail.sh |
| ⏳ chưa chạy | REG-SB-TRAIN-HOOK-REFUSAL-01 | #740/#775: train dựng chuỗi bằng git merge thật (hook vẫn chạy); hook guard-check kiểu GeelyEx2 #181 ⇒ 2 PR đụng file guard khác nhau cùng merged, PR chậm hơn base vẫn verify + merged; hook từ chối không file xung đột ⇒ gate-exit-5 + lời hook ở train-detail (không 'conflict'), chỉ trong chuỗi ⇒ deferred có lý do trong log; xung đột thật vẫn conflict exit 5 kèm tên file | chưa chạy | bash tests/super-board/test_merge_train_hook_refusal.sh |

### pm-audit-scope-antigravity — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-PM-AUDIT-SCOPE-01 | 13/11 (chủ repo bỏ Grok): pm_dispatch agent=grok bị từ chối; audit Antigravity ghi phạm vi PR (auditedHead, auditBase, edited) vào lượt giao, pm_verdict ghi verdict vào lượt đó | chưa chạy | cd mcp-servers/antigravity-pm-mcp && node --test tests/audit-scope.test.js |

### pm-grok-gate-approval-e2e — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-E2E-PM-GROK-GATE-01 | 04/11 đầu-cuối: code PM thật ghi biên bản audit grok, post-fix-gate thật đọc và duyệt test sửa không bước người; sửa sau audit, REVISE, message, phiên grok, người gọi grok đều không duyệt | chưa chạy | bash tests/super-board/test_e2e_pm_grok_gate_approval.sh |

### pm-grok-timeout-by-diff — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-PM-GROK-TIMEOUT-01 | 04/11: hạn grok audit theo kích thước diff (sàn 20 phút, +1 phút/100 dòng, trần 60), env ghi đè vẫn thắng | chưa chạy | cd mcp-servers/antigravity-pm-mcp && node --test tests/grok-timeout.test.js |

### post-fix-gate-tree-mode — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GATE-TREE-01 | post-fix-gate --tree HEAD: cây sạch chạy đủ suite và exit 0, tin ma trận đã commit, từ chối cây bẩn, biên nhận theo cây cho proof_gate (#307) | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_tree_mode.sh |

### proof-gate-merge-receipt — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-PROOF-MERGE-RECEIPT-01 | proof_gate nhận biên nhận merge của merge gate (lượt gộp qua merge gate chạy nền, push qua pipe: cho qua); biên nhận lượt trước / phiên khác / không session, squash không có trên origin, cha squash khác base, commit chưa qua gate sau squash (kể cả ngày giả), main bẩn file của phiên, gh pr merge, ghi tay kho biên nhận: chặn | chưa chạy | bash universal-agent-devkit/tests/gates/test_proof_gate_merge_receipt.sh |
| ⏳ chưa chạy | REG-SB-MERGE-GATE-PROOF-RECEIPT-01 | merge gate THẬT ghi biên nhận merge (pr, head, base, verified_tree, squash, session) mà proof_gate nhận; phiên khác / không session: chặn; kho không ghi được: gate vẫn gộp, exit 0 | chưa chạy | bash tests/super-board/test_merge_gate_proof_receipt.sh |

### proof-gate-trunk-main-722 — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-PROOF-API-BLOB-01 | #722: dòng api-request-blob (không timestamp) không đóng cửa biên nhận merge khi tool_use đã có bản ghi assistant (hay chỉ đọc); tool_use chỉ có trong blob mà ghi kho / gh pr merge / Bash bất kỳ, id rỗng hay null, blob nhắc kho không có tool_use, dòng assistant không timestamp (kể cả cặp gh pr merge + blob trùng id): chặn | chưa chạy | bash universal-agent-devkit/tests/gates/test_proof_gate_api_request_blob.sh |
| ⏳ chưa chạy | REG-DK-PROOF-MAIN-PREDATES-01 | #722: main trunk mode có file người khác để từ trước phiên, lệnh shell chỉ đọc nhắc tên; biên nhận trong lượt cho fp commit HEAD (PR squash, hay --tree HEAD trong worktree tạm): cho qua; file tạo trong phiên, nested repo, symlink, t0 tương lai, Edit nêu tên, touch -t, file đã xoá, không gate / gate lượt trước / main đi tiếp / trunk tắt / không biết t0: chặn; lời khuyên nêu --tree HEAD; copy-mode vẫn exit 2 | chưa chạy | bash universal-agent-devkit/tests/gates/test_proof_gate_main_predates_session.sh |

### qa-detached-worktree-557 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-QA-DETACHED-557-01 | #557: QA thêm worktree detached tại origin/<PR branch>, không gỡ worktree build khi nhánh đã đổi tên hoặc còn agent-memory chưa commit, và đẩy commit bằng chứng bằng git push origin HEAD:<PR branch> | chưa chạy | bash tests/super-board/test_qa_detached_worktree.sh |

### qa-exit2-edited-test-643 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-QA-EXIT2-643-01 | #643: QA exit 2 chỉ vì test sửa đi Review rồi merge nhờ duyệt chéo | chưa chạy | bash tests/super-board/test_qa_exit2_edited_test.sh |

### rerun-skip-ttl-3d-992 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-RERUN-SKIP-TTL-3D-992-01 | #992: rerun_skip.json (#648) dùng hạn mặc định 3 ngày như biên nhận (7 giờ dùng lại, 4 ngày chạy lại); DEVKIT_GATE_CACHE_MAX_S vẫn ghi đè, =0 không dùng lại | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_rerun_skip_ttl_3d.sh |

### review-gate-handover — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-REVIEW-GATE-HANDOVER-01 | 04/11: review gate coi gh pr create / agent-kit worktree finish\|integrate / merge gate là bàn giao như git push; thông điệp chặn: P0/P1 sửa ngay, P2/P3 thành thẻ Backlog, OCR delegate không cần agent thứ hai, không cắt output bằng tail | chưa chạy | bash universal-agent-devkit/tests/gates/test_review_gate_handover.sh |

### review-gate-handover-gtimeout-flag-value-992 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-REVIEW-GATE-GTIMEOUT-FLAG-VALUE-992-01 | #992: review_gate — gtimeout N …merge-gate.sh là bàn giao; --dry-run/--preflight làm giá trị của option khác (--subject --dry-run) không phải dry-run | chưa chạy | bash universal-agent-devkit/tests/gates/test_review_gate_handover_gtimeout_flag_value.sh |

### review-gate-handover-merge-gate-forms-992 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-REVIEW-GATE-MERGE-GATE-FORMS-992-01 | #992: review_gate — merge gate --dry-run/--preflight không là bàn giao; timeout N bash …merge-gate.sh là bàn giao | chưa chạy | bash universal-agent-devkit/tests/gates/test_review_gate_handover_merge_gate_forms.sh |

### review-gate-ocr-out-literal-hint-992 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-REVIEW-GATE-OCR-OUT-LITERAL-992-01 | #992: review_gate — thông điệp thiếu OCR nhắc --out viết thẳng đường dẫn; --out $S/spec (biến) vẫn không tính, --out viết thẳng tính | chưa chạy | bash universal-agent-devkit/tests/gates/test_review_gate_ocr_out_literal_hint.sh |

### review-wait-receipt-671 — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-GATE-RECEIPT-BY-HEAD-671-01 | #671 AC1: super-board-gate-receipt.sh in fp theo head từ store chung; biên nhận của cây bẩn (file thật) không phủ commit sạch, file cài đặt worktree thì qua | chưa chạy | bash tests/super-board/test_issue671_gate_receipt_by_head.sh |
| ⏳ chưa chạy | REG-SB-REVIEW-WAIT-NOT-NOOP-671-01 | #671 AC2/AC3: review worker kết thúc sạch khi chờ (comment [reviewer] cuối blocked-by:) không bị đếm no-op và nghỉ SB_REVIEW_WAIT_S; bị kill, is_error hoặc comment không phải reviewer vẫn Blocked | chưa chạy | bash tests/super-board/test_issue671_review_wait_not_noop.sh |

### sb-runner-suite-fuse — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-SUITE-FUSE-01 | cầu chì suite của runner: ≥2 thẻ Blocked cùng suite id trong N giờ gộp một thẻ và ngưng giao Builder tới khi thẻ gộp rời Blocked; khác suite hay ngoài cửa sổ giờ không gộp (#363) | chưa chạy | bash tests/super-board/test_runner_suite_fuse.sh |

### scoped-gate-matrix-append-p6 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-SCOPED-MATRIX-APPEND-P6-01 | P6: scoped_gate.decide — ma trận chỉ nối rule (so merge-base, và base khi changed do caller chọn) ⇒ không lõi, chỉ test đọc thật; sửa rule cũ / trùng id / trùng component / covered_by / đổi khoá top-level / JSON hỏng ⇒ như cũ | chưa chạy | bash universal-agent-devkit/tests/gates/test_scoped_gate_matrix_append.sh |

### selection-inputs-order-and-reject-rerun — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-REJECT-RERUN-CMDS-01 | 05/11: gate REJECT in lệnh chạy lại riêng từng chỗ đỏ (test đỏ của shard run_impacted.sh, lệnh suite thường) + nhắc merge gate verify một lần | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_reject_rerun_cmds.sh |
| ⏳ chưa chạy | REG-DK-SELECTION-INPUTS-ORDER-01 | 05/11: selection_inputs (#851) không phụ thuộc PYTHONHASHSEED; sổ PASS từng test khoá cả cây nên test glob file ngoài đồ thị chạy lại khi file đổi | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_selection_inputs_order.sh |

### shard-key-failclosed-994 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-SHARD-KEY-FAILCLOSED-994-01 | #994: shard run_impacted.sh chỉ khoá cả cây (fail-closed) — file test chỉ glob lúc chạy đổi thì shard chạy lại và ĐỎ, không dùng lại PASS cũ | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_shard_key_enum_failclosed.sh |

### suite-env-board-worker-528 — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-SUITE-ENV-WORKER-528-01 | #528: suite_env và clean_git_env bỏ SB_BOARD_WORKER, SB_MERGE_CALLER, SB_MERGE_QUEUE, SB_REPO_PATH, SB_GITHUB_READ_STRICT | chưa chạy | bash universal-agent-devkit/tests/gates/test_suite_env_worker_vars.sh |
| ⏳ chưa chạy | REG-DK-WORKER-MAIN-528-01 | #528: SB_BOARD_WORKER=1 trên main thì hook thoát 0 và không chạy suite; không có cờ thì chạy; worktree liên kết vẫn chạy | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_worker_main.sh |

### suite-env-heavy-slot-knobs-p3 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-SUITE-ENV-HEAVY-KNOBS-01 | PR 1 gate kẹt (P3): suite_env bỏ DEVKIT_SLOT_HEAVY_MAX, DEVKIT_SLOT_HEAVY_WAIT_S, DEVKIT_SLOT_HEAVY_BUDGET_S (núm của một lần gate), vẫn giữ DEVKIT_GATE_SLOT_HELD (T0056) | chưa chạy | bash universal-agent-devkit/tests/gates/test_suite_env_heavy_knobs.sh |

### super-board-ac-check-cross-repo — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-AC-CHECK-CROSS-REPO-01 | #731: ac-check — Closes owner/repo#N của repo khác luôn là thẻ lạ kể cả trùng số thẻ nhánh / thành viên đợt; --rewrite-closes --foreign cùng luật; closes_own chỉ tính repo này; origin đọc ở SB_REPO_PATH | chưa chạy | bash tests/super-board/test_ac_check_cross_repo.sh |

### super-board-ac-proven-before-close — 0/3 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-AC-CHECK-01 | ac-check (T0054): đếm mọi dạng mục AC, mở rộng AC gián tiếp 'AC của thẻ #X', bắt AC nén (#318/PR #343), Closes thẻ lạ, dòng chưa tick, đổi Closes → Refs | chưa chạy | bash tests/super-board/test_ac_check.sh |
| ⏳ chưa chạy | REG-SB-AC-OPEN-NOT-DONE-01 | thẻ ac-open không vào Done (T0054): card.sh move Done exit 5; runner mở lại issue đóng còn ac-open thay vì reconcile Done; preflight không coi là đã giao | chưa chạy | bash tests/super-board/test_card_done_ac_open.sh && bash tests/super-board/test_runner_reconcile_ac_open.sh && bash tests/super-board/test_preflight_ac_open.sh |
| ⏳ chưa chạy | REG-SB-MERGE-GATE-AC-01 | merge gate (T0054): AC nén / Closes thẻ lạ (body, message, commit) → exit 11; còn AC chưa tick → merge nhưng Refs, nhãn ac-open, thẻ về Ready; đủ AC → gỡ nhãn; PR không sb:ac như cũ | chưa chạy | bash tests/super-board/test_merge_gate_ac_check.sh |

### super-board-ac-short-heading — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-AC-SHORT-HEADING-01 | #616/#618: heading `## AC` là mục AC ở preflight (không hold unclear), luật kéo Backlog và ac-check; `## ACL` không phải | chưa chạy | bash tests/super-board/test_preflight_ac_short_heading.sh |

### super-board-agents-md-block — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-AGENTS-MD-BLOCK-01 | super-board AGENTS.md block stays within 40 lines and does not repeat the worker pipeline | chưa chạy | bash tests/super-board/test_agents_md_block_size.sh |

### super-board-agents-md-block-pointer — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-AGENTS-MD-BLOCK-02 | run.md still points every lane to the DevKit pipeline that moved out of the AGENTS.md block (same test as REG-SB-AGENTS-MD-BLOCK-01, watched on run.md and the test itself) | chưa chạy | bash tests/super-board/test_agents_md_block_size.sh |

### super-board-approval-cross-review-605 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-APPROVAL-CROSS-REVIEW-605-01 | #605: marker cross-review-approved hợp lệ (reviewer khác builder, head/scope khớp request, task_id + gate_receipt không rỗng, người đăng có quyền ghi) thay cho done; tự duyệt, head lệch, sửa comment, đăng trước request = không nhận; chỉ plan có delete-protected mới cần done của người (schema / needs_you nhận marker); policy: xoá file khớp merge_policy.protected_paths → human delete-protected (cả file nhị phân qua github-read); --deps --config nhận marker khi plan hiện tại cho phép | chưa chạy | python3 tests/super-board/test_approval_cross_review.py |

### super-board-approved-head-605 — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-APPROVED-HEAD-605-01 | #605: approved-head kèm approved-by {reviewer,builder,task_id,gate_receipt} được nhận (reviewer khác builder); tự duyệt, approved-by hỏng/thiếu trường, head lệch bị loại; marker mới nhất thắng; bare approved-head của OWNER vẫn nhận (runner) | chưa chạy | bash tests/super-board/test_runner_review_approved_head.sh |
| ⏳ chưa chạy | REG-SB-APPROVED-HEAD-605-02 | #605: merge-queue dùng chung luật approved-head (super-board-approved-head.jq): marker hợp lệ và bare OWNER vào train; tự duyệt, approved-by hỏng, task_id rỗng, head lệch, marker tự duyệt mới hơn bị loại kèm lý do | chưa chạy | bash tests/super-board/test_merge_queue.sh |

### super-board-approved-head-closing-ref — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-APPROVED-HEAD-CLOSING-REF-01 | #607/#614: review_approved_head nhận PR nhánh không phải issue-<N>- khi đúng một PR mở có closingIssuesReferences chứa N; nhánh issue-<N>- vẫn thắng, hai PR đóng N thì không chọn; thẻ Review có PR như vậy đã vào hàng không bị đẩy Blocked vì no-op | chưa chạy | bash tests/super-board/test_runner_approved_head_closing_ref.sh |

### super-board-audit-check-605 — 0/3 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-AUDIT-CHECK-605-01 | #605 (audit T0066 vòng 2): task_id của cross-review-approved chỉ tính khi antigravity-pm có audit pass với auditedHead == head của request; không biên bản, head khác, verdict fail, project khác, task_id sai dạng = không duyệt; CLI super-board-audit-check.py exit 0/1 | chưa chạy | python3 tests/super-board/test_approval_cross_review.py |
| ⏳ chưa chạy | REG-SB-AUDIT-CHECK-605-02 | #605 (audit T0066 vòng 2): merge-queue loại approved-by có task_id không có audit pass khớp head PR (giả, head cũ, verdict fail, sai dạng); bare OWNER vẫn vào train | chưa chạy | bash tests/super-board/test_merge_queue.sh |
| ⏳ chưa chạy | REG-SB-AUDIT-CHECK-605-03 | #605 (audit T0066 vòng 2): review_approved_head của runner chỉ merge-only khi task_id của approved-by có audit pass khớp head PR | chưa chạy | bash tests/super-board/test_runner_review_approved_head.sh |

<details><summary>✅ super-board-blocked-by-open-only — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-SB-BLOCKED-BY-OPEN-ONLY-01 | dòng blocked-by: chỉ ghi issue còn mở; số đã đóng bị bỏ kèm lý do, không còn số mở thì `-`, không đọc được trạng thái thì exit 79 (#253) | 2026-10-24 13:07:21 · 0.61s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-BLOCKED-BY-OPEN-ONLY-01/20261024-130458.log) | python3 tests/super-board/test_blocked_by_open_only.py |

</details>

<details><summary>✅ super-board-board-heartbeat — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-SB-BOARD-HEARTBEAT-01 | GitHub Actions cron marks a 🟢/🟠 board ⚫ when the watchdog's 'cập nhật HH:MM dd/MM' is stale; leaves ⏸️/⚪/⚫ and foreign descriptions alone | 2026-10-24 13:07:21 · 0.49s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-BOARD-HEARTBEAT-01/20261024-125804.log) | bash tests/super-board/test_board_heartbeat.sh |

</details>

### super-board-build-workers — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-BUILD-WORKERS-01 | lane build chạy nhiều worker theo tải máy: trần build_workers, tối đa một worker mới mỗi tick, tải >= build_load_max hoặc không đọc được thì giữ, quét mồ côi/zombie/dừng khẩn nhận ra N worker | 2026-10-24 13:07:21 · 6.33s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-BUILD-WORKERS-01/20261024-125949.log) | bash tests/super-board/test_runner_build_workers.sh |

### super-board-card-items-retry — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-CARD-ITEMS-RETRY-01 | card.sh items đọc lại 1 lần khi số item lệch totalCount (không chết runner); lệch cả hai lần vẫn exit 69; stop.sh ghi marker trước kill (#256) | 2026-10-24 13:07:21 · 6.75s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-CARD-ITEMS-RETRY-01/20261024-130107.log) | bash tests/super-board/test_card_items_count_retry.sh |

### super-board-card-write-fail-blocks-card — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-CARD-WRITE-BLOCK-01 | gh_write_once: lệnh ghi GitHub của MỘT thẻ hỏng thì thẻ đó vào Blocked kèm comment chặn, board chạy tiếp; bước chặn hỏng hoặc lệnh không thuộc thẻ thì halt 79 như cũ; dispatch không phóng worker cho thẻ vừa bị chặn (28/10) | chưa chạy | bash tests/super-board/test_card_write_fail_blocks_card.sh |

### super-board-decision-prompts — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-DECISION-PROMPTS-01 | #518: prompt orchestrator (run.md) áp luật 1–5 của decision-policy.md, ghi [orchestrator] [decision] kèm marker sb-decision:orchestrator, unmark needs-you, danh sách dừng giữ needs-you; prompt builder/QA/reviewer/block-template/wave lanePrompt coi AC đã quyết là xong, không dựng lại blocker, cấm tự đăng [decision] | chưa chạy | bash tests/super-board/test_decision_prompts.sh |

### super-board-decision-reader — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-DECISION-READER-01 | [orchestrator] [decision] hợp lệ (marker orchestrator hoặc comment tay của chủ không marker) gỡ blocker ở deps.sh, needs-you mark, qa-report; lane tự đăng thì bị bỏ qua; ca DỪNG vẫn gắn needs-you (#516, 28/10) | chưa chạy | bash tests/super-board/test_decision_reader.sh |

### super-board-dependency-unblock-v1 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-DEPENDENCY-UNBLOCK-V1-01 | P3 cờ dependency_unblock_v1: thẻ Ready còn ## Blocked by mở ở lại Ready (waiting-on), không claim/Building/Blocked/spawn; cờ tắt giữ nguyên writes/log; deps lỗi giao như cũ, file halt riêng | chưa chạy | bash tests/super-board/test_dependency_unblock_v1.sh |

### super-board-diff-policy — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-MERGE-POLICY-NL-01 | merge-policy sees always_human keywords after VT/FF/CR/NEL/U+2028, in ++ lines and across odd whitespace | 2026-10-24 14:59:54 · 1.83s · exit 0 · 7a3d58a8+dirty · [log](evidence/REG-SB-MERGE-POLICY-NL-01/20261024-145954.log) | bash tests/super-board/test_merge_policy_odd_newlines.sh |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-UPSTREAM-66-67-01 | github-read keeps odd-newline diffs byte-exact without halting; approval links body issues off the default base | 2026-10-24 15:08:27 · 0.96s · exit 0 · 7a3d58a8+dirty · [log](evidence/REG-SB-UPSTREAM-66-67-01/20261024-150827.log) | bash tests/super-board/test_upstream_66_67.sh |

### super-board-door-blast-host-agy-549 — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-HOST-AGY-549-01 | #549: super-board-host.sh nhận diện claude, codex, agy (SUPER_BOARD_HOST hoặc ANTIGRAVITY_*), host lạ thoát 64 | chưa chạy | bash tests/super-board/test_host_detect.sh |
| ⏳ chưa chạy | REG-SB-RISK-DOOR-BLAST-549-01 | #549: khối Risk nêu Door (one-way/two-way) và Blast radius ở writing-standard và các tài liệu lane; mọi SKILL.md dưới 20000 byte | chưa chạy | bash tests/super-board/test_risk_door_blast.sh |

### super-board-failopen-1000 — 0/5 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-1000-CHAIN-AUDIT-01 | #1000 mục 7, 8: --chain-audit đọc script byte không UTF-8; head chỉ trong auditHistory -> pm-unknown | chưa chạy | bash tests/super-board/test_chain_audit_robust.sh |
| ⏳ chưa chạy | REG-SB-1000-QA-PIN-FETCH-01 | #1000 mục 2: merge gate thử lại fetch rồi exit 1, không bỏ ghim sha QA | chưa chạy | bash tests/super-board/test_merge_gate_qa_pin_fetch.sh |
| ⏳ chưa chạy | REG-SB-1000-QA-STALE-PIN-01 | #1000 mục 1: ghim sha QA — lời khai tiêu đề, merge sửa tay/giải conflict, amend, mọi sha own, lỗi git = exit 2 | chưa chạy | bash tests/super-board/test_qa_report_stale_pin.sh |
| ⏳ chưa chạy | REG-SB-1000-TRAIN-RECEIPT-PM-01 | #1000 mục 5: biên nhận train không bỏ verify khi duyệt test sửa đến từ biên bản PM (pm / pm-unknown) | chưa chạy | bash tests/super-board/test_merge_gate_train_receipt_pm.sh |
| ⏳ chưa chạy | REG-SB-1000-VERIFY-RUNS-GATE-01 | #1000 mục 6: sb_verify_runs_gate không nhận echo python3 post-fix-gate.py / not-post-fix-gate.py | chưa chạy | bash tests/super-board/test_verify_runs_gate_boundary.sh |

### super-board-gh-write-once-marker — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-WRITE-MARKER-01 | gh_write_once: comment ghi chưa rõ kết quả mang marker duy nhất cho mỗi lần, comment cố định lặp không làm reconcile báo đã áp dụng nhầm | 2026-10-24 12:13:59 · 2.63s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-WRITE-MARKER-01/20261024-121359.log) | bash tests/super-board/test_gh_write_once_marker.sh |

### super-board-gh-write-retry-520 — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-CARD-WRITE-RETRY-01 | #520: thẻ Blocked vì lệnh ghi GitHub hỏng (card-write-failed) được runner ghi lại mỗi tick từ state cục bộ: được thì về cột cũ, 3 tick hỏng liên tiếp thì needs-you một lần rồi thôi thử (sống qua restart, không bao giờ halt); không phát lại chuyển cột / nhận thẻ đã huỷ; cột cũ Blocked thì giữ Blocked; người kéo thẻ ra thì bỏ state | chưa chạy | bash tests/super-board/test_card_write_failed_sweep.sh |
| ⏳ chưa chạy | REG-SB-GH-WRITE-RETRY-01 | #520: gh_write_once thử lại lỗi ghi GitHub thoáng qua (5xx, timeout, rate limit, mạng) tối đa 2 lần trước đường #517; 422/404/401/không tìm thấy và stderr rỗng không thử lại; comment đọc lại marker token trước khi thử lại (đã đăng thì không đăng lần 2, đọc hỏng thì không đăng mù); lệnh không thuộc thẻ vẫn halt 79 khi hết lượt | chưa chạy | bash tests/super-board/test_gh_write_retry.sh |

### super-board-github-read-foreign-halt — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-GITHUB-READ-FOREIGN-HALT-01 | github-read: a failed read of ANOTHER repository (test fixture o/r from a worktree) never writes the real board halt; a read of the checkout's own repository, or one naming no repository, still halts | 2026-10-24 13:07:21 · 1.14s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-GITHUB-READ-FOREIGN-HALT-01/20261024-130714.log) | bash tests/super-board/test_github_read_foreign_halt.sh |

### super-board-github-read-reconcile — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-GITHUB-RECONCILE-01 | github-read --halt --verify / --reconcile: đọc lại lần ghi chưa rõ kết quả; đã áp dụng thì lưu trữ halt, chưa áp dụng hay không kiểm chứng được thì giữ halt | 2026-10-24 13:07:21 · 2.43s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-GITHUB-RECONCILE-01/20261024-130536.log) | bash tests/super-board/test_github_read_reconcile.sh |

### super-board-has-edited-tests-pm-record — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-HAS-EDITED-PM-01 | 04/11: merge gate / train --has-edited-tests nhận duyệt test sửa từ biên bản PM (audit pass trên base..head) để giữ khoá và không autosync; base hỏng = bi quan | chưa chạy | bash tests/super-board/test_has_edited_tests_pm_record.sh |
| ⏳ chưa chạy | REG-SB-PM-EDITED-BASE-MOVED-01 | 04/11: merge gate / train không exit 2 'stale' khi duyệt test sửa đến từ biên bản PM và main tiến không chạm test (verify trong khoá); comment edited-tests vẫn exit 2 như #643 | chưa chạy | bash tests/super-board/test_merge_gate_pm_edited_base_moved.sh |

### super-board-heavy-slot — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-HEAVY-SLOT-01 | heavy slot theo tải máy (P1b): CLI/wrapper super-board chạy ngay khi tải < DEVKIT_SLOT_LOAD_MAX, chờ rồi vẫn chạy khi tải cao, --nonblock không chạy khi tải cao, DEVKIT_SLOT_LOAD_WAIT_S=0 không chờ, suite Unity lồng trong CLI vẫn xin khoá Unity; --force-full với suite nhẹ không chờ | 2026-10-24 13:07:21 · 10.31s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-HEAVY-SLOT-01/20261024-125943.log) | bash tests/super-board/test_heavy_slot.sh |

### super-board-lane-workers — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-LANE-WORKERS-01 | lane QA và Review chạy nhiều worker (qa_workers / review_workers, mặc định 1): một worker mới mỗi tick, cổng tải build_load_max, zombie/reap/dừng khẩn/nhận lại nhận ra cả worker thêm, worker thêm không bị trần max_workers chặn | 2026-10-24 13:07:21 · 20.97s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-LANE-WORKERS-01/20261024-130100.log) | bash tests/super-board/test_runner_lane_workers.sh |

### super-board-merge-call-failed — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-MERGE-CALL-FAILED-01 | merge gate: gh pr merge lỗi mà PR vẫn OPEN đúng head → exit 4, không halt board; đọc lại lỗi/CLOSED vẫn halt; MERGED muộn exit 0; head đổi exit 6 | 2026-10-24 14:59:04 · 6.19s · exit 0 · 7a3d58a8+dirty · [log](evidence/REG-SB-MERGE-CALL-FAILED-01/20261024-145904.log) | bash tests/super-board/test_merge_gate_merge_call_failed.sh |

### super-board-merge-gate — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-MERGE-GATE-STALE-01 | merge gate says stale only when the branch is behind base | 2026-10-24 14:59:40 · 8.69s · exit 0 · 7a3d58a8+dirty · [log](evidence/REG-SB-MERGE-GATE-STALE-01/20261024-145940.log) | bash tests/super-board/test_merge_gate_stale_message.sh |

### super-board-merge-gate-approve-request — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-GATE-APPROVE-REQUEST-01 | PR #924: gate tự gửi nút Approve (standalone, --preflight khi queue tắt) thì tự đăng đúng một comment PR chứa dòng approval-request: của head; chạy lại không đăng trùng; train/queue khi queue bật không comment, không nút; đăng lỗi chỉ log, exit 7/8 giữ nguyên; --dry-run không đăng | chưa chạy | bash tests/super-board/test_merge_gate_approve_button_request.sh |

### super-board-merge-gate-autosync-driver — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-GATE-AUTOSYNC-DRIVER-01 | ngoại lệ hẹp của #570: GitHub báo CONFLICTING mà mọi file hai phía cùng đổi đều có merge driver đặt tên (ma trận merge=devkit-matrix, merge=union) ⇒ gate gộp base ở scratch, đẩy merge commit lên nhánh PR bằng fast-forward (không --force), ghi biên nhận approved-merge-heads, verify và merge theo head mới; file không driver, PR sửa .gitattributes, nhánh remote đã dời, --dry-run: exit 14 không đẩy gì; lượt sau --expect-head cũ nhận head của gate, có commit lạ chồng lên thì exit 6 | chưa chạy | bash tests/super-board/test_merge_gate_autosync_driver_conflict.sh |

### super-board-merge-gate-base-suite-pool — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-BASE-SUITE-POOL-914-01 | #914 mục 1: run_suite_on_base (kiểm đỏ sẵn trên base) xin slot pool gate, trần 900 s nhân SUITE_TIMEOUT_FACTOR của suite, hết giờ chờ slot ra 75 (không phải 1 hay 2), exception không ra exit 1 | chưa chạy | bash tests/super-board/test_merge_gate_base_suite_pool.sh |

### super-board-merge-gate-busy-slot — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-GATE-BUSY-SLOT-01 | merge-gate và merge-train đặt mặc định DEVKIT_GATE_SLOT_WAIT_S=1800; khi post-fix-gate thoát 4 busy thì giữ thẻ ở Review (exit 4 / train exit 12 không retry), không ra exit 11 | chưa chạy | bash tests/super-board/test_merge_gate_busy_slot.sh |

### super-board-merge-gate-card-merged-comment — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-GATE-CARD-MERGED-01 | P2 đợt 2 (03/11): gate gọi trực tiếp comment '[reviewer] [report] ✅ merged <sha> · PR #N' lên mọi thẻ PR đóng (closingIssuesReferences), cả nhánh split/… và khi phản hồi merge mất; queue/train, AC chưa đủ (ac-open), PR không Closes: không comment | chưa chạy | bash tests/super-board/test_merge_gate_card_merged_comment.sh |

### super-board-merge-gate-dead-holder — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-MERGE-DEAD-HOLDER-01 | merge gate: khoá merge có pid đã chết (gate bị giết trước trap EXIT) được reap ngay, không chờ stale-after; pid còn sống và khoá không có pid vẫn chờ như cũ (exit 4) | 2026-10-24 14:59:31 · 26.23s · exit 0 · 7a3d58a8+dirty · [log](evidence/REG-SB-MERGE-DEAD-HOLDER-01/20261024-145931.log) | bash tests/super-board/test_merge_gate_dead_holder.sh |

### super-board-merge-gate-load-wait — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ❌ TIMEOUT | REG-SB-MERGE-LOAD-WAIT-01 | merge gate waits (bounded, inside the lock before the base is pinned, lock stamp refreshed) for the machine load to drop, then verifies anyway | 2026-10-24 14:40:53 · 62.66s · exit None · cef7994b+dirty · [log](evidence/REG-SB-MERGE-LOAD-WAIT-01/20261024-144053.log) | bash tests/super-board/test_merge_gate_load_wait.sh |

### super-board-merge-gate-queue-guard — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-GATE-QUEUE-GUARD-01 | merge gate: queue bật mà gọi thẳng (không SB_MERGE_CALLER train/queue, không --standalone) thì exit 13 không verify/không khoá; --preflight chỉ chạy kiểm rẻ, in preflight: ok; --standalone; SB_MERGE_QUEUE=0 như cũ | chưa chạy | bash tests/super-board/test_merge_gate_queue_guard.sh |

### super-board-merge-gate-scratch-live-lock — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-SCRATCH-LIVE-LOCK-01 | 03/11 (merge gate #940): scratch của merge gate khoá bằng worktree lock khi gate còn sống — lệnh remove trần giữa lúc verify bị từ chối; cleanup/keep mở khoá trước khi gỡ | chưa chạy | bash tests/super-board/test_merge_gate_scratch_live_lock.sh |

### super-board-merge-gate-timeout-retry — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ❌ TIMEOUT | REG-SB-MERGE-TIMEOUT-RETRY-01 | merge gate retries a post-fix-gate verify once only when every red suite is TIMEOUT (REJECT exit 1, static checks passed); a real FAIL, UNTESTED or static finding is not retried; verify exit 124 still retried once | 2026-10-24 14:48:14 · 118.90s · exit None · cef7994b+dirty · [log](evidence/REG-SB-MERGE-TIMEOUT-RETRY-01/20261024-144814.log) | bash tests/super-board/test_merge_gate_timeout_retry.sh |

### super-board-merge-gate-verified-tree — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-MERGE-GATE-TREE-01 | merge gate: cây gộp đã verify xanh với cùng bộ lệnh thì lượt gate sau bỏ verify; base đổi, lệnh đổi hoặc verify đỏ thì verify đủ (#226 gap 7) | 2026-10-24 14:59:52 · 11.12s · exit 0 · 7a3d58a8+dirty · [log](evidence/REG-SB-MERGE-GATE-TREE-01/20261024-145952.log) | bash tests/super-board/test_merge_gate_verified_tree.sh |

### super-board-merge-guard-retry — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-GUARD-RETRY-01 | Gate speed v26 mục 7: merge gate chạy lại guard đỏ (theo [merge-guard] của base) đúng một lần, comment PR; guard vẫn đỏ ⇒ exit 11 | chưa chạy | bash tests/super-board/test_merge_guard_retry.sh |

### super-board-merge-queue — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-QUEUE-01 | hàng đợi merge: --if-due gom khi đủ batch_max / PR cũ nhất chờ max_wait_min / máy rảnh; khoá fcntl không chạy chồng; approved-head lệch hay người ngoài bị loại; route từng train-result; đợt sau đợt đỏ thu nhỏ | chưa chạy | bash tests/super-board/test_merge_queue.sh |

### super-board-merge-queue-e2e — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-QUEUE-E2E-01 | đầu-cuối qua runner + hàng đợi + train + merge gate THẬT: 3 PR lệch nhịp (2 thẻ + 1 PR tương tác) chỉ 1 lượt verify trong train, 0 verify lẻ, thẻ Done; lane worker gọi thẳng gate khi queue bật ra exit 13; SB_MERGE_QUEUE=0 giữ đường cũ (trên origin/main trước Pha 2: 0 train) | chưa chạy | bash tests/super-board/test_merge_queue_e2e.sh |

### super-board-merge-queue-route-rows — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-QUEUE-ROUTE-01 | #762/#637/#639: route của hàng đợi merge — card_of/head_of/cache load_rows không chết khi dữ liệu lớn hơn bộ đệm ống (printf \| awk exit dưới pipefail); thẻ qua closingIssuesReferences khi nhánh không theo mẫu issue-<N>-; đọc GitHub hỏng giữa lượt route không cắt dở các PR còn lại; gate-exit-11 của preflight không ghi là verify đỏ | chưa chạy | bash tests/super-board/test_merge_queue_route_rows.sh |

### super-board-merge-train — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-MERGE-TRAIN-01 | merge train: 3 PR sẵn sàng thì verify đúng một lần và cả 3 merge; một PR đỏ được chia đôi tìm ra (exit 11) và hai PR còn lại vẫn merge; một PR chạy như gate thường (#110) | 2026-10-24 15:00:37 · 42.71s · exit 0 · 7a3d58a8+dirty · [log](evidence/REG-SB-MERGE-TRAIN-01/20261024-150037.log) | bash tests/super-board/test_merge_train.sh |

### super-board-merge-train-single-test-retry-578 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-TRAIN-SINGLE-TEST-RETRY-578-01 | #578: verify đỏ chỉ vì đúng một test của REG-DK-ALL-01 thì train chạy lại riêng test đó một lần (xanh = flaky ghi vào PR + thẻ test; đỏ hai lần = red kèm tên test); hai test trở lên, suite khác đỏ, tên test mất, đường dẫn lạ = red ngay | chưa chạy | env -u SB_BOARD_WORKER -u SB_MERGE_QUEUE bash tests/super-board/test_merge_train_single_test_retry.sh |

### super-board-needs-device — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-NEEDS-DEVICE-01 | runner, planner and status hold needs-device QA cards while no real device is online (emulator, denylist, no adb) | 2026-10-24 12:09:58 · 3.13s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-NEEDS-DEVICE-01/20261024-120958.log) | bash tests/super-board/test_needs_device_skip.sh |

### super-board-needs-you — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-NEEDS-YOU-01 | needs-you mark is idempotent, migrates human-gated and carries no machine line | 2026-10-24 15:07:48 · 4.86s · exit 0 · 7a3d58a8+dirty · [log](evidence/REG-SB-NEEDS-YOU-01/20261024-150748.log) | bash tests/super-board/test_needs_you.sh |

### super-board-needs-you-guard-v2 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-NEEDS-YOU-GUARD-V2-01 | optimizer đợt 1: cờ needs_you_guard_v2 tắt = nhận mọi lời 🙋 như v1; bật = từ chối 8 lời nhắm thứ agent sở hữu (duyệt test đã sửa, AC/nội dung thẻ #N, đóng thẻ đã có PR, cây dirty, --full + merge gate), vẫn nhận 44 lời còn lại, việc phải hỏi người dù mở đầu bằng quyết định/chọn hướng, và câu human-gate của merge-queue; cờ đọc từ flags.json của checkout chính | chưa chạy | bash tests/super-board/test_needs_you_guard_v2.sh |

### super-board-needs-you-guard-v2-dependabot-file — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-NEEDS-YOU-GUARD-V2-03 | Review r1 đợt 2 (03/11): miễn dependabot của needs-you v2 không áp cho tên file (.github/dependabot.yml, test-dependabot-*.sh → 64); chữ Dependabot thường vẫn miễn (bật auto-approve cho Dependabot → 0) | chưa chạy | bash tests/super-board/test_needs_you_guard_v2_dependabot_file.sh |

### super-board-needs-you-guard-v2-exempt — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-NEEDS-YOU-GUARD-V2-02 | OCR review 03/11 sau #924: deploy/production trong đường dẫn hay tên file không miễn câu nhắm việc agent; bước trên GitHub settings/cài đặt không bị chặn nhầm; env SB_NEEDS_YOU_GUARD_V2 thắng flags.json | chưa chạy | bash tests/super-board/test_needs_you_guard_v2_exempt.sh |

### super-board-needs-you-skip — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-NEEDS-YOU-SKIP-01 | runner, planner and status leave Ready cards that wait for a person (needs-you / human-gated) to the person | 2026-10-24 12:10:00 · 0.89s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-NEEDS-YOU-SKIP-01/20261024-121000.log) | bash tests/super-board/test_needs_you_skip.sh |

### super-board-notify-and-slots — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-NOTIFY-SLOTS-01 | notify blocks test/lib/runaway Telegram spam; super_board_all covers all 6 repos; monitor scans worktree transcripts; claim loop caps total early deaths | 2026-10-24 12:10:10 · 8.47s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-NOTIFY-SLOTS-01/20261024-121010.log) | python3 tests/super-board/test_notify.py && python3 tests/super-board/test_super_board_all_slots.py && bash tests/super-board/test_runner_claim_loop.sh |

### super-board-post-merge-clean — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-POST-MERGE-CLEAN-01 | post-merge clean and --sweep remove merged lane worktrees, keep work, one sweep at a time, salvage leaves no junk | 2026-10-24 13:07:21 · 78.85s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-POST-MERGE-CLEAN-01/20261024-125803.log) | bash tests/super-board/test_post_merge_clean.sh && bash tests/super-board/test_post_merge_squash_leftovers.sh && bash tests/super-board/test_post_merge_sweep_wiring.sh |

### super-board-preflight — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-PREFLIGHT-TOO-BIG-01 | preflight holds too-big cards before a builder pass, proceeds on normal ones | 2026-10-24 13:07:21 · 5.49s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-PREFLIGHT-TOO-BIG-01/20261024-125625.log) | bash tests/super-board/test_preflight_too_big.sh |

### super-board-preflight-numbered-ac — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-PREFLIGHT-NUMBERED-AC-01 | AC đánh số 1) / 1. được nhận ở preflight (không hold unclear) và ở luật kéo Backlog; AC chỉ văn xuôi vẫn bị chặn (#283) | 2026-10-24 12:10:12 · 1.27s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-PREFLIGHT-NUMBERED-AC-01/20261024-121012.log) | bash tests/super-board/test_preflight_numbered_ac.sh |

### super-board-preflight-stale-overlap — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-PREFLIGHT-STALE-OVERLAP-01 | preflight câu 3: PR của thẻ Backlog/Blocked không chặn; PR của thẻ đang chạy vẫn chặn; thẻ có PR riêng không bị sequence lại; không --inflight giữ hành vi cũ (#280) | 2026-10-24 13:07:21 · 12.32s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-PREFLIGHT-STALE-OVERLAP-01/20261024-130512.log) | bash tests/super-board/test_preflight_overlap_stale.sh |

### super-board-qa-head-pin — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-QA-HEAD-PIN-01 | merge gate từ chối khi report QA mới nhất nêu sha nhánh PR mà head còn commit code sau đó (T0255) | chưa chạy | bash tests/super-board/test_merge_gate_qa_head_pin.sh |

### super-board-queue-label-536 — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MQ-REJECT-NOTE-01 | #536: hàng đợi merge loại PR vì approved-head thiếu / lệch head thì comment thêm lên thẻ PR đóng (nhánh issue-<K>- hoặc closingIssuesReferences, chỉ khi thẻ trên board, đọc hỏng không để lại file halt); --dry-run không ghi | chưa chạy | bash tests/super-board/test_merge_queue_reject_card_note.sh |
| ⏳ chưa chạy | REG-SB-QUEUE-LABEL-01 | #536: super-board-queue-label.sh gắn nhãn merge-queue chỉ khi approved-head hợp lệ (luật chung super-board-approved-head.jq + audit-check) khớp head hiện tại; thiếu / head cũ / không phải OWNER-MEMBER-COLLABORATOR / audit không khớp → exit 3 kèm lý do và bước đúng; đọc/ghi GitHub hỏng → 69; --check không ghi | chưa chạy | bash tests/super-board/test_queue_label.sh |

### super-board-queue-schedule — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-WAVE-PLAN-QUEUED-01 | #453 backend workflow + queue bật: wave-plan bỏ thẻ Review có PR nhãn merge-queue (chờ lịch rút hàng); queue tắt / codex / SB_MERGE_QUEUE=0 giữ nguyên | chưa chạy | bash tests/super-board/test_wave_plan_queued.sh |

### super-board-red-on-base — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RED-ON-BASE-01 | merge gate: suite đỏ cả trên origin/base không REJECT PR, mở thẻ riêng; suite do PR làm đỏ vẫn exit 11 (#251) | 2026-10-24 15:08:17 · 27.92s · exit 0 · 7a3d58a8+dirty · [log](evidence/REG-SB-RED-ON-BASE-01/20261024-150817.log) | bash tests/super-board/test_merge_gate_red_on_base.sh |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-VERIFY-CMD-01 | QA in đúng lệnh verify của merge gate (cùng hàm chèn --diff/--force-full) (#251) | 2026-10-24 15:08:29 · 0.35s · exit 0 · 7a3d58a8+dirty · [log](evidence/REG-SB-VERIFY-CMD-01/20261024-150828.log) | bash tests/super-board/test_verify_cmd_same_as_gate.sh |

### super-board-red-on-base-kit-tests — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-RED-ON-BASE-KIT-TESTS-01 | Gate speed v26 mục 5a: runner kit đỏ ⇒ red-on-base chạy riêng từng test ✖ trên base; danh sách thiếu, lạ hay có thể bị cắt ⇒ đỏ | chưa chạy | bash tests/super-board/test_merge_gate_red_on_base_kit_tests.sh |

### super-board-review-approved-head — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-REVIEW-APPROVED-HEAD-01 | runner: thẻ Review đã duyệt đúng head (comment approved-head:<sha> của OWNER/MEMBER/COLLABORATOR) chỉ chạy merge-only với --expect-head, kể cả sau merge gate exit 4; head đổi, người ngoài duyệt hay đọc GitHub hỏng thì review đầy đủ (#227) | 2026-10-24 13:07:21 · 5.57s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-REVIEW-APPROVED-HEAD-01/20261024-130529.log) | bash tests/super-board/test_runner_review_approved_head.sh |

### super-board-review-merge-train — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-REVIEW-MERGE-TRAIN-01 | runner: từ 2 thẻ Review đã duyệt đúng head trở lên thì một worker chạy super-board-merge-train.sh --prs cho cả đợt (lock chung PID, không bị coi là zombie khi thẻ đầu đã Done); thẻ chưa duyệt, sai head, đã khoá hay SB_REVIEW_TRAIN=0 thì đường từng thẻ như cũ (#228) | 2026-10-24 12:10:21 · 8.02s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-REVIEW-MERGE-TRAIN-01/20261024-121021.log) | bash tests/super-board/test_runner_review_merge_train.sh |

### super-board-review-plan-858 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-REVIEW-PLAN-01 | #858: super-board-review-plan.sh in bậc review S/M/L (review_tier.py) và các bên review theo config review_tiers: PR giả bậc S ⇒ 1 bên (claude), M ⇒ 2, diff 5 dòng merge-gate ⇒ L 4 bên, --deletes-data ⇒ L; config tuỳ biến được đọc; danh sách rỗng / sai kiểu / JSON hỏng ⇒ mặc định luật chủ repo; thiếu review_tier.py ⇒ L kèm cảnh báo; super-review review-flow.md và run.md gọi script | chưa chạy | bash tests/super-board/test_review_plan_tier.sh |

### super-board-reviewer-antigravity-audit-605 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-REVIEWER-AUDIT-605-01 | #605 (audit T0066 vòng 3): prompt Review headless, run.md, worker-preamble.md, super-review/SKILL.md và ai-factory doc cùng một hợp đồng: reviewer chạy audit Antigravity thật qua antigravity-pm (pm_task_create, pm_dispatch kind=audit, audit-agent.json, pm_verdict auditedHead) trước approved-by, gate_receipt = biên nhận task impacted, Antigravity không có thì thẻ ở Review với blocked-by | chưa chạy | bash tests/super-board/test_reviewer_antigravity_audit_contract.sh |

### super-board-run-stop-mark-mtime — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RUN-STOP-MTIME-01 | runner reads the stop marker mtime on GNU and BSD stat | 2026-10-24 12:10:23 · 0.68s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-RUN-STOP-MTIME-01/20261024-121023.log) | bash tests/super-board/test_run_stop_mark_mtime.sh |

### super-board-run-sweep-wiring — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RUN-SWEEP-TICK-01 | runner starts the post-merge sweep at startup and on every tick (before cap-reached), throttled, in the background | 2026-10-24 12:10:25 · 1.01s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-RUN-SWEEP-TICK-01/20261024-121025.log) | bash tests/super-board/test_post_merge_sweep_wiring.sh |

### super-board-runner — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-GITHUB-READ-01 | super-board github-read helper | 2026-10-24 14:58:57 · 3.44s · exit 0 · 7a3d58a8+dirty · [log](evidence/REG-SB-GITHUB-READ-01/20261024-145857.log) | bash tests/super-board/test_github_read.sh |
| 💤 đã nghỉ (suite không còn trong ma trận) | REG-SB-MERGE-SYNC-01 | super-board merge gate: local base sync after merge (identical uncommitted copies K13, squash, work in progress) | 2026-10-20 16:21:03 · 119.61s · exit None · 98430be2+dirty · [log](evidence/REG-SB-MERGE-SYNC-01/20261020-162103.log) | bash tests/super-board/test_merge_gate_identical_sync.sh && bash tests/super-board/test_merge_gate_squash_sync.sh |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RUNNER-LANES-01 | super-board runner lanes | 2026-10-24 15:08:25 · 7.38s · exit 0 · 7a3d58a8+dirty · [log](evidence/REG-SB-RUNNER-LANES-01/20261024-150825.log) | bash tests/super-board/test_runner_lanes.sh |

### super-board-runner-board-read-retry — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RUNNER-READ-RETRY-01 | runner đọc lại board có backoff khi lần đọc hỏng tạm thời; hỏng hết lượt thì bỏ tick thay vì chết; halt 79 vẫn dừng; vòng chính chỉ đọc qua tick_fetch (#256) | 2026-10-24 12:10:59 · 2.72s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-RUNNER-READ-RETRY-01/20261024-121059.log) | bash tests/super-board/test_runner_board_read_retry.sh |

### super-board-runner-merge-queue — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-RUNNER-MERGE-QUEUE-01 | runner khi bật merge queue: không phóng lại reviewer cho thẻ đã vào hàng, không merge-only/train, không phạt no-op/RUNAWAY, gọi merge-queue --if-due mỗi tick; SB_MERGE_QUEUE=0 giữ đường cũ | chưa chạy | bash tests/super-board/test_runner_merge_queue.sh |

### super-board-runner-mq-restart-599 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-RUNNER-MQ-RESTART-599-01 | #599: runner restart giữa chừng khi bộ gom nền còn chạy không bật bộ gom thứ hai (đọc lại .mq.pid); .mq.rc do runner cũ để lại vẫn được runner mới đọc và áp 79/9 (halt), mã khác chỉ ghi log | chưa chạy | bash tests/super-board/test_runner_mq_restart.sh |

### super-board-runner-noop-worker — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RUNNER-NOOP-WORKER-01 | runner: worker qa/review thoát mà thẻ vẫn ở cột cũ và không comment mới thì tính no-op; 2 lần liên tiếp thì thẻ sang Blocked (📱 nếu log nhắc máy thật, còn lại ❓) kèm dòng cuối log, không giao lại; chuyển cột hoặc có comment thì không tính | 2026-10-24 13:07:21 · 3.45s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-RUNNER-NOOP-WORKER-01/20261024-130656.log) | bash tests/super-board/test_runner_noop_worker.sh |

### super-board-runner-preflight-swept — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RUNNER-PREFLIGHT-SWEPT-01 | runner chạy preflight trước khi nhận thẻ build (hold/sequence có blockedBy: không claim, thẻ sang Blocked kèm blocked-by; exit 79 dừng run) và sổ SWEPT_CARDS bền qua lần khởi động lại (#253) | 2026-10-24 12:10:54 · 14.89s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-RUNNER-PREFLIGHT-SWEPT-01/20261024-121054.log) | bash tests/super-board/test_runner_preflight_swept.sh |

### super-board-runner-ready-order — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RUNNER-READY-ORDER-01 | runner giao thẻ Ready theo priority label, bug trước, số issue tăng dần; thẻ body nhắm repo khác → Blocked kèm block-template; thẻ có Fix trùng thẻ đang mở → comment một lần, không giao | 2026-10-24 12:11:06 · 4.56s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-RUNNER-READY-ORDER-01/20261024-121106.log) | bash tests/super-board/test_runner_ready_order.sh |

### super-board-runner-reclaim-dead-build — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RUNNER-RECLAIM-DEAD-BUILD-01 | runner trả thẻ Building có worker build chết giữa lượt chạy về lại Ready kèm sổ reclaims; quá trần trong cửa sổ thì chuyển sang Blocked có dòng blocked-by: - | 2026-10-24 12:13:26 · 2.37s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-RUNNER-RECLAIM-DEAD-BUILD-01/20261024-121326.log) | bash tests/super-board/test_runner_reclaim_dead_build.sh |

### super-board-runner-session-cards — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-WB-SESSION-CARD-RECLAIM-01 | 03/11: reclaim_stranded_building không trả thẻ Building nhãn session (task từ chat, phiên đang làm) về Ready; thẻ thường vẫn về Ready | chưa chạy | bash tests/super-board/test_runner_skips_session_cards.sh |

### super-board-runner-watchdog — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ❌ TIMEOUT | REG-SB-RUNNER-WATCHDOG-01 | super-board runner survives a killed sleep; durable stop marker; launchd watchdog never restarts a stopped board | 2026-10-24 13:55:01 · 51.07s · exit None · 1b575f4f+dirty · [log](evidence/REG-SB-RUNNER-WATCHDOG-01/20261024-135501.log) | bash tests/super-board/test_runner_watchdog.sh |

### super-board-scratch-config — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-SCRATCH-CONFIG-01 | merge gate scratch tree gets ignored local config, build inputs and the ignored hooks settings registers | 2026-10-24 13:07:21 · 0.80s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-SCRATCH-CONFIG-01/20261024-125748.log) | bash tests/super-board/test_scratch_config.sh |

### super-board-self-reload — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-SELF-RELOAD-01 | runner rảnh tự nạp lại super-board-run.sh khi origin đổi: ff main rồi exec lại; main lệch origin / ff hỏng / sai cú pháp thì notify một lần, không restart mù; còn worker thì không đụng | 2026-10-24 12:13:44 · 14.51s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-SELF-RELOAD-01/20261024-121343.log) | bash tests/super-board/test_runner_self_reload.sh |

### super-board-setup-bin-list — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-SETUP-BIN-01 | setup BIN lists every super-board script the runner, merge gate and skills call | 2026-10-24 13:07:21 · 0.24s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-SETUP-BIN-01/20261024-125644.log) | bash tests/super-board/test_setup_bin_list.sh |

### super-board-setup-bin-scan — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-SETUP-BIN-02 | test_setup_bin_list.sh quét .claude/bin, skills, workflows, hooks theo thư mục: thêm hay sửa script super-* ở đó phải chọn lại suite này (main đỏ REG-SB-SETUP-BIN-01 sau #656 vì watch_files chỉ liệt kê 2 file) | chưa chạy | bash tests/super-board/test_setup_bin_list.sh |

### super-board-spawn-load-530 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-SPAWN-LOAD-530-01 | #530: load1 vượt ngưỡng thì build+qa+review hoãn spawn (log holding spawn load1); 30 vẫn spawn; 36.5 hoãn; rỗng/rác/lib mode không chặn; tick rẻ không nuốt merge queue hay no-progress khi 0 worker | chưa chạy | bash tests/super-board/test_runner_total_cap.sh |

### super-board-status-needs-you-column — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-STATUS-NEEDS-YOU-01 | status: option Needs You của Project vẽ thành ô riêng và vào nhóm Waiting on you; không có thẻ Needs You thì đầu ra không đổi | 2026-10-24 13:07:21 · 0.21s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-STATUS-NEEDS-YOU-01/20261024-130604.log) | bash tests/super-board/test_status_needs_you_column.sh |

### super-board-sweep-needs-you-529 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-SWEEP-NEEDS-YOU-529-01 | #529: Blocked by không bullet đọc được số; resume gỡ needs-you trước khi sang Review; denylist soi --next và từng mệnh đề; reclaim/no-op ❓ không ghi blocked-by: -; trần im lặng build/qa; tick rẻ đếm chu kỳ không tiến triển | chưa chạy | bash tests/super-board/test_issue529_sweep_needs_you.sh |

### super-board-total-worker-cap — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-TOTAL-CAP-01 | một trần worker max_workers (5) cho mọi repo, cộng phanh spawn khi load1 vượt ngưỡng (mặc định busy_load); dưới ngưỡng tải không chặn; lib mode không đọc máy thật | 2026-10-24 12:13:53 · 7.51s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-TOTAL-CAP-01/20261024-121352.log) | bash tests/super-board/test_runner_total_cap.sh |

### super-board-train-guard-retry — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-TRAIN-GUARD-RETRY-01 | Gate speed v26 mục 7: merge train chạy lại guard đỏ đúng một lần (không áp rows == 1), comment PR khi merge | chưa chạy | bash tests/super-board/test_merge_train_guard_retry.sh |

### super-board-verify-single-pfg — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-VERIFY-SINGLE-PFG-01 | Gate speed v26 mục 7: guard chỉ chạy lại khi lệnh verify là một post-fix-gate đơn (từ chối $( ), backtick, tên giả kiểu xpost-fix-gate.py) | chưa chạy | bash tests/super-board/test_verify_single_pfg_cmd.sh |

<details><summary>✅ super-board-waiting-label — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-SB-WAITING-LABEL-01 | thẻ Blocked chỉ chờ thẻ khác mang nhãn '⏳ chờ thẻ khác' (planner pending, runner gắn/gỡ), thẻ 🙋 không có nhãn, status tách hai nhóm (#235) | 2026-10-24 13:07:21 · 1.55s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-WAITING-LABEL-01/20261024-130606.log) | bash tests/super-board/test_waiting_label.sh |

</details>

### super-board-waiting-on-601 — 0/3 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-WAITING-ON-HELPER-601-01 | #601 helper waiting-on: mark gắn nhãn waiting-on:#N + comment một lần (không dòng blocked-by:); sweep gỡ nhãn khi N CLOSED/MERGED, mỗi N đọc một lần, số lỗi không chặn số khác; migrate thẻ Blocked chỉ chờ → Ready + nhãn, bỏ needs-you/fuse, chạy 2 lần cùng kết quả | chưa chạy | bash tests/super-board/test_waiting_on_helper.sh |
| ⏳ chưa chạy | REG-SB-WAITING-ON-RUNNER-601-01 | #601 runner: preflight sequence có blocker mở không Blocked mà gọi mark, thẻ ở Ready; dispatch/inflight bỏ qua thẻ waiting-on; sweep_waiting_on theo nhịp, lỗi không halt; hold vẫn Blocked | chưa chạy | bash tests/super-board/test_waiting_on_runner.sh |
| ⏳ chưa chạy | REG-SB-WAITING-ON-WAVE-601-01 | #601 workflow: planner để thẻ waiting-on ngoài Ready (vào waiting), pending có needsYou; wave.js không build sequence có blocker mở, preflightExit = waiting@Ready | chưa chạy | bash tests/super-board/test_waiting_on_wave.sh |

### super-board-waiting-on-skip-619 — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-WAITING-ON-SKIP-01 | #619: runner, planner và helper cùng một regex nhãn waiting-on:#<số> (nhãn sai dạng không giữ thẻ Ready); preflight không giao thẻ Ready đầu (mark hỏng) thì thẻ Ready kế được giao trong cùng tick, tối đa 3 thẻ mỗi tick | chưa chạy | bash tests/super-board/test_waiting_on_skip_next.sh |

### super-board-watchdog-lock-atomic — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-WATCHDOG-LOCK-ATOMIC-01 | 8 check cùng gặp khoá check cũ quá 120 s thì đúng một check giữ được khoá (không khởi động 2 runner) | 2026-10-24 14:28:01 · 4.50s · exit 0 · 74586478+dirty · [log](evidence/REG-SB-WATCHDOG-LOCK-ATOMIC-01/20261024-142801.log) | bash tests/super-board/test_watchdog_lock_atomic.sh |

### super-board-watchdog-path-sanitize — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-WATCHDOG-PATHS-01 | watchdog compares .state paths on physical paths and takes back a stale check lock on GNU and BSD stat | 2026-10-24 14:28:03 · 1.56s · exit 0 · 74586478+dirty · [log](evidence/REG-SB-WATCHDOG-PATHS-01/20261024-142803.log) | bash tests/super-board/test_watchdog_path_sanitize.sh && bash tests/super-board/test_watchdog_lock_mtime.sh |

### super-board-watchdog-run-capped-fast — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-WATCHDOG-RUN-CAPPED-FAST-01 | 03/11 lane 5: run_capped của watchdog chờ tăng dần 0,02 s ⇒ 0,5 s (10 lệnh nhanh < 3 s), timeout vẫn ra 124, mã thoát của lệnh giữ nguyên | chưa chạy | bash tests/super-board/test_watchdog_run_capped_fast.sh |

### super-board-wave-model-ladder — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-WAVE-MODEL-LADDER-01 | #553: thang model của super-board-wave.js — tier medium thẻ high không yếu hơn thẻ medium (không để undefined = model phiên, có thể là sonnet); tier low/high giữ nguyên; comment trên LADDERS, SKILL.md, run-workflow.md ghi đúng thang | chưa chạy | bash tests/super-board/test_wave_model_ladder.sh |

### super-board-wave-needs-you-mark — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-WAVE-NEEDSYOU-01 | wave.js: prompt exit 7 và exit 8 của merge gate gọi super-board-needs-you.py mark với --next comment done (#106) | 2026-10-24 13:07:21 · 0.05s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-WAVE-NEEDSYOU-01/20261024-130000.log) | bash tests/super-board/test_wave_needs_you_mark.sh |

### super-board-wip-limit — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-WIP-LIMIT-01 | runner giới hạn WIP (#252): không giao build khi QA+Review chờ >= build_wip_k × (qa_workers+review_workers); không giao build / worker QA-Review thêm khi số post-fix-gate đang chạy >= gate_max; log lý do; số gate không đếm được thì không chặn | 2026-10-24 12:13:54 · 0.22s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-WIP-LIMIT-01/20261024-121354.log) | bash tests/super-board/test_runner_wip_limit.sh |

### super-board-worker-wrap-term — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-WORKER-WRAP-TERM-01 | worker-wrap dừng được worker dù con nuốt mất SIGTERM đầu tiên (TERM tới con trước exec): gửi lại sau 1 s, không treo kill + wait (#489) | chưa chạy | bash tests/super-board/test_worker_wrap_term.sh |

### super-build-rebuild-gate-once — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-REBUILD-GATE-ONCE-01 | 03/11 lane 1: mục rebuild sau review của super-build nêu đúng một gate scoped trên cây sau sửa, không gate riêng giữa chừng | chưa chạy | bash tests/super-board/test_rebuild_gate_once.sh |

### super-review-receipt-before-rerun — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-REVIEW-RECEIPT-RERUN-01 | Đợt 2 gate mục 5 (04/11): sau khi duyệt test sửa, lane Review chỉ bỏ lần chạy lại gate khi có biên nhận exit 0 đúng head + fingerprint; chưa có thì chạy gate scoped một lần | chưa chạy | bash tests/super-board/test_reviewer_receipt_before_rerun.sh |

### test-heavy-slot-isolation — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-TEST-SLOT-ISO-01 | tests never queue behind the machine's real heavy-verify slots | 2026-10-24 13:07:21 · 0.11s · exit 0 · 38166b6b+dirty · [log](evidence/REG-SB-TEST-SLOT-ISO-01/20261024-125828.log) | bash tests/super-board/test_tests_skip_machine_slots.sh |

### verify-flags-arg-span — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-VERIFY-FLAGS-ARG-SPAN-01 | #802: sb_verify_inject_flags chỉ xét --full/--force-full/--scoped/--diff/--json trong phần đối số của post-fix-gate.py; token của lệnh khác trong lệnh ghép không chặn ' --diff origin/<base> --scoped' chèn ngay sau token | chưa chạy | bash tests/super-board/test_verify_flags_arg_span.sh |

### workbench-agent-config — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-WB-CONFIG-01 | agent-kit health: every registered hook exists, imports resolve, context in sync | 2026-10-24 14:28:05 · 0.43s · exit 0 · 74586478+dirty · [log](evidence/REG-WB-CONFIG-01/20261024-142805.log) | bash universal-agent-devkit/bin/agent-kit health -t . |

### worktree-discard-squash — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-DISCARD-SQUASH-01 | worktree discard: chuỗi commit đã squash vào origin/<trunk> (main local chưa pull) + file xoá thì gỡ được kèm refs/devkit/discarded; còn commit trunk chưa có patch hoặc có file bị sửa thì vẫn từ chối | 2026-10-24 14:58:51 · 11.11s · exit 0 · 7a3d58a8+dirty · [log](evidence/REG-DK-DISCARD-SQUASH-01/20261024-145851.log) | bash universal-agent-devkit/tests/worktree_git/test_worktree_discard_squash.sh |

### worktree-essentials-block-remove — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-WT-ESSENTIALS-BLOCK-01 | worktree remove/discard gỡ được worktree chỉ lệch ở khối devkit-essentials của AGENTS.md; sửa ngoài khối vẫn bị từ chối (#234) | chưa chạy | bash universal-agent-devkit/tests/worktree_git/test_worktree_remove_essentials_block.sh |

### worktree-merged-cleaner — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-WT-MERGED-CLEANER-01 | một bộ dọn worktree đã gộp (U2 25/10): gc --merged / held / remove --merged của worktree.py và post-merge clean của board không gỡ worktree có commit trunk chưa có, chỉ file chưa commit, commit chỉ reflog giữ, phiên sống giữ, nhánh có PR mở; gỡ worktree đã tích hợp sạch; không còn đường git trần | chưa chạy | bash universal-agent-devkit/tests/worktree_git/test_worktree_gc_merged.sh && bash tests/super-board/test_post_merge_clean.sh |

### worktree-remove-reflog-squash — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-REMOVE-REFLOG-SQUASH-01 | worktree remove: commit chỉ còn trong reflog mà trunk đã có patch (squash) thì gỡ được kèm refs/devkit/discarded; trunk chưa có patch thì vẫn từ chối UNREACHABLE (#421) | chưa chạy | bash universal-agent-devkit/tests/worktree_git/test_worktree_remove_reflog_squash.sh |

## 📒 Sổ tay bug (150)

| Trạng thái | Mã | Mô tả | Component | Test bảo vệ | Bằng chứng |
|---|---|---|---|---|---|
| ❌ TIMEOUT | BUG-20260925-prompt-bao-bug-that-cung-se-khong-con-du | prompt báo bug thật cũng sẽ không còn được ghi nhận nữa -> là sao bug đúng ko fix đi phải tự động ghi nhận chứ | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_bug_capture.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20260925-prompt-bao-bug-that-cung-se-khong-con-du/20261009-185852.log) |
| ❌ TIMEOUT | BUG-20260926-dev-kit-lam-tao-branch-push-lung-tung-kh | dev kit làm tạo branch, push lung tung không đồng bộ dẫn tới lệch code, vd geely ex2 hiện có 2 pull chưa pull về dẫn tớ… | - | REG-DK-ALL-01, REG-DK-HOOK-01, REG-DK-HOOK-02, universal-agent-devkit/hooks/tests/hook_contract_test.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20260926-dev-kit-lam-tao-branch-push-lung-tung-kh/20261009-181041.log) |
| ❌ TIMEOUT | BUG-20260928-audit-review-them-geely-ex2-hien-no-bao | audit, review thêm geely ex2 hiện nó báo tôi rất nhiều lỗi vậy có nghĩa là bộ devkit hoàn toàn chất lượng kém để thủng… | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_friction.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20260928-audit-review-them-geely-ex2-hien-no-bao/20261009-180103.log) |
| ❌ TIMEOUT | BUG-20260928-fix-luon-loi-git-guard-chan-grep-di-ngoa | fix luôn lỗi git guard chặn grep đi ngoài ra đã tối ưu token sử dụng cũng như thời gian chạy chưa ? Đề xuất các phương… | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_friction.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20260928-fix-luon-loi-git-guard-chan-grep-di-ngoa/20261009-182605.log) |
| ❌ TIMEOUT | BUG-20260928-push-geely-va-fix-luon-loi-red-proof | push geely và fix luôn lỗi red_proof | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_red_proof.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20260928-push-geely-va-fix-luon-loi-red-proof/20261009-174029.log) |
| ❌ TIMEOUT | BUG-20260928-san-check-luon-chat-luong-dev-kit-workfl | sẵn check luôn chất lượng dev kit workflow có bị lỗi gì ko fix luôn đi | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_friction.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20260928-san-check-luon-chat-luong-dev-kit-workfl/20261009-180602.log) |
| ❌ TIMEOUT | BUG-20260929-audit-review-nguyen-nhan-tai-sao-cac-ses | audit, review nguyên nhân tại sao các sesion cài dev kit chạy rất chậm có lỗi gì hay ko? | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_regression_gate_hook.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261001-lam-luon-fix-bug-worktree-di | làm luôn fix bug worktree đi | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_worktree_merge_gate.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261001-lam-luon-fix-bug-worktree-di/20261009-182503.log) |
| ❌ TIMEOUT | BUG-20261001-sua-luon-bug-init-xoa-mcp-server-di | sửa luôn bug init xoá MCP server đi | - | REG-DK-ALL-01, universal-agent-devkit/tests/installer/test_platform_rules.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261001-sua-luon-bug-init-xoa-mcp-server-di/20261009-175104.log) |
| ❌ TIMEOUT | BUG-20261002-agent-kit-health-run-tests-scores-96-100 | agent-kit health --run-tests scores 96/100: agent-kit test runs ~90 test scripts one after another (~19 min), past the 900 s limit health allows | devkit-health | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_run_impacted.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261002-chay-finagling-running-stop-hooks-8-9-27 | chạy Finagling… (running Stop hooks… 8/9 · 27m 24s · ↓ 46.3k tokens) quá lâu audit, review sửa lại đi Stop hooks… rất h… | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_regression_gate_hook.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261002-chay-finagling-running-stop-hooks-8-9-27/20261009-173819.log) |
| ❌ TIMEOUT | BUG-20261002-evidence-gate-foreign-xml-nonrunner | test_evidence_gate: a Bash that only names a foreign project (cd && git status) made its fresh XML count as this session's test evidence | devkit | REG-DK-ALL-01, REG-DK-HOOK-01, REG-DK-HOOK-02, universal-agent-devkit/hooks/tests/hook_contract_test.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261002-evidence-gate-foreign-xml-nonrunner/20261009-190334.log) |
| ❌ TIMEOUT | BUG-20261002-gate-rejects-a-change-that-moves-a-test | Gate REJECTs a change that moves a test file the matrix names: it runs the base matrix, whose command names the removed path (exit 127), and flags the matrix edit for review | devkit-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_matrix_rename.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261002-gate-rejects-a-change-that-moves-a-test/20261009-172300.log) |
| ❌ TIMEOUT | BUG-20261002-proof-gate-reinit-same-profile | proof gate: re-init rewriting the same backend profile counted as a profile switch and demanded a PNG | devkit | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_proof_gate.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261002-proof-gate-reinit-same-profile/20261009-170334.log) |
| ❌ TIMEOUT | BUG-20261002-sessionstart-skips-the-checklist-block-a | SessionStart skips the checklist block and the background STALE re-run after the scripts/ regrouping (bin/ and stale_rerun.py paths) | devkit-hooks | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_stale.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261002-sessionstart-skips-the-checklist-block-a/20261009-173233.log) |
| ❌ TIMEOUT | BUG-20261008-sua-4-loi-kit-phien-office-nho-di | sửa 4 lỗi kit phiên Office nhờ đi | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_session_lock_target_repo.sh (trong suite), universal-agent-devkit/tests/worktree_git/test_worktree_automerge.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261008-sua-4-loi-kit-phien-office-nho-di/20261008-235601.log) |
| ❌ TIMEOUT | BUG-20261009-automerge-refusal-reason-lost | worktree automerge: a commit refused by the repo's pre-commit gate was reported with only the last 500 characters of the gate output, which is the passed-checks footer, never the finding: the worktree stayed unmerged and nobody could tell why (GeelyEx2 giao-tichhop-09-10, base-hoiquy-09-10) | devkit-worktree | REG-DK-ALL-01, universal-agent-devkit/tests/worktree_git/test_worktree_automerge_reason.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261009-automerge-refusal-reason-lost/20261009-192819.log) |
| ❌ TIMEOUT | BUG-20261009-churn-guard-no-fast-path | churn_guard started python on every Edit although it can warn only when the transcript names the file at least N times | devkit-hooks | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_churn_guard_fast_path.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261009-churn-guard-no-fast-path/20261009-190532.log) |
| ❌ TIMEOUT | BUG-20261009-comment-claim-docstring-trailing | comment_claim_guard: a claim inside a Python docstring or after code on the same line (# / //) passed while the same words in a full-line comment warn | devkit-hooks | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_comment_claim_docstring_trailing.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261009-comment-claim-docstring-trailing/20261009-210844.log) |
| ❌ TIMEOUT | BUG-20261009-gate-js-describe-title-false-flag | post-fix-gate: the same it('title') in two different describe blocks flagged a pure append of a JS test as an edited test | devkit-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_js_describe_scope.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261009-gate-js-describe-title-false-flag/20261009-211414.log) |
| ❌ TIMEOUT | BUG-20261009-gate-runner-no-errexit-append | post-fix-gate: any command appended to a shell test runner WITHOUT set -e counted as a pure append, though it decides the exit status over an earlier failure (user decision 2026-10-09) | devkit-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_runner_no_errexit.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261009-gate-runner-no-errexit-append/20261009-211102.log) |
| ❌ TIMEOUT | BUG-20261009-git-guard-bash-c-subst-tee-shell | block-dangerous-git: bash -c "$(curl ...)" and a shell inside >(...) ran generated text that curl \| bash and bash <(...) already refuse | devkit-git-guard | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_git_guard_shell_subst.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261009-git-guard-bash-c-subst-tee-shell/20261009-220947.log) |
| ❌ TIMEOUT | BUG-20261009-hardware-find-negated-or-unfiltered | hardware_safety_gate: find ! -name x -delete, -not, and an -o alternative without a filter counted as filtered, so the start point was never judged | devkit-hardware-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_hardware_find_not_or.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261009-hardware-find-negated-or-unfiltered/20261009-213309.log) |
| ❌ TIMEOUT | BUG-20261009-hooks-log-dir-process-cwd | 7 hooks (bash_write_ledger, security_gate, proof_gate, regression_gate, test_evidence_gate, review_timing_guard, prompt_context) took the project from the PROCESS cwd when CLAUDE_PROJECT_DIR was unset and created .claude/audit-gate there (a run at / wrote /.claude) | devkit-hooks | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_hook_log_dir.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261009-hooks-log-dir-process-cwd/20261009-203143.log) |
| ❌ TIMEOUT | BUG-20261009-merge-gate-held-vanished-worktree | worktree_merge_gate: a worktree removed by the last Stop's background merge while this Stop decided stayed in the hold list (flaky test_worktree_merge_gate_owner) | devkit-worktree | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_worktree_merge_gate_vanished.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261009-merge-gate-held-vanished-worktree/20261009-181812.log) |
| ❌ TIMEOUT | BUG-20261009-review-timing-guard-env-payload | review_timing_guard: the hook payload travelled in an environment variable, so an Edit of a big file (payload past the 1 MiB exec limit) made the shell fail with Argument list too long and the guard never ran | devkit-hooks | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_review_timing_guard_big_payload.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261009-review-timing-guard-env-payload/20261009-181603.log) |
| ❌ TIMEOUT | BUG-20261009-run-impacted-recent-commits-in-sandbox | run_impacted.sh in a checkout with no upstream (every RED-proof sandbox) selected the tests of every commit of the last 6 hours: 25+ minutes per proof instead of the few tests of the reverted file | devkit-tests | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_run_impacted_since.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261009-scratch-cleanup-prune-could-delete-a-liv | scratch_cleanup: prune could delete a live idle session's dir and follow a slug swapped for a symlink (TOCTOU) | devkit-scratch-cleanup | REG-DK-ALL-01, universal-agent-devkit/tests/context_memory/test_scratch_cleanup.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261009-scratch-cleanup-prune-could-delete-a-liv/20261009-171413.log) |
| ❌ TIMEOUT | BUG-20261009-session-lock-a-cp-rc-copy-of-a-checkout | session_lock: a cp -Rc copy of a checkout carried the original's lock and was held by its live holder up to 600 s | devkit-session-lock | REG-DK-ALL-01, universal-agent-devkit/tests/context_memory/test_session_lock.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261009-session-lock-a-cp-rc-copy-of-a-checkout/20261009-203323.log) |
| ❌ TIMEOUT | BUG-20261009-session-lock-an-idle-holder-turn-over-wa | session_lock: an idle holder (turn over, waiting at the prompt) kept the checkout 600 s, other sessions needed /exit | devkit-session-lock | REG-DK-ALL-01, universal-agent-devkit/tests/context_memory/test_session_lock.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261009-session-lock-an-idle-holder-turn-over-wa/20261009-203838.log) |
| ❌ TIMEOUT | BUG-20261009-session-lock-case-only-path | session_lock: a path spelled with other letter case (APFS) fell outside the locked checkout, so the write took no lock and a live holder lost it | devkit-session-lock | REG-DK-ALL-01, universal-agent-devkit/tests/context_memory/test_session_lock.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261009-session-lock-case-only-path/20261009-202937.log) |
| ❌ TIMEOUT | BUG-20261010-gate-swallows-a-failed-linter-import-and | gate swallows a failed linter import and switches the lint off silently | devkit-guards | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_linter_import_loud.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-gate-swallows-a-failed-linter-import-and/20261010-102355.log) |
| ❌ TIMEOUT | BUG-20261010-gate-wants-a-regression-test-for-red-pro | gate wants a regression test for red-proof patch files | devkit-guards | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_redpatch_no_test.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-gate-wants-a-regression-test-for-red-pro/20261010-103756.log) |
| ❌ TIMEOUT | BUG-20261010-guard-hooks-lose-the-command-that-follow | guard hooks lose the command that follows a comment or a hash inside a word | devkit-guards | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_guard_comment_not_swallowing.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-guard-hooks-lose-the-command-that-follow/20261010-101953.log) |
| ❌ TIMEOUT | BUG-20261010-health-reports-100-while-a-tracked-symli | health reports 100 while a tracked symlink points at a missing target | devkit-guards | REG-DK-ALL-01, universal-agent-devkit/tests/installer/test_agent_health_broken_tracked_link.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-health-reports-100-while-a-tracked-symli/20261010-104501.log) |
| ❌ TIMEOUT | BUG-20261010-matrix-accepts-one-suite-id-with-two-dif | matrix accepts one suite id with two different commands without a word | devkit-guards | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_matrix_duplicate_id.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-matrix-accepts-one-suite-id-with-two-dif/20261010-105445.log) |
| ❌ TIMEOUT | BUG-20261010-proof-gate-blocks-a-push-turn-whose-4-it | proof_gate blocks a push turn whose 4-item report was already written right after the push | proof_gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_proof_gate_report_after_push.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-proof-gate-blocks-a-push-turn-whose-4-it/20261010-125933.log) |
| ❌ TIMEOUT | BUG-20261010-red-proof-keeps-a-patch-of-any-size-in-a | red proof keeps a patch of any size in a tracked folder | devkit-guards | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_red_proof_patch_cap.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261010-red-proof-keeps-a-patch-of-any-size-in-a/20261010-110336.log) |
| ❌ TIMEOUT | BUG-20261010-regression-gate-re-runs-every-suite-on-a | regression_gate re-runs every suite on a repeated FAIL when one suite cannot run here, ignores local config and age, and sessions erase each other's stored blocks | regression_gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_regression_gate_repeat_cache.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261010-regression-gate-re-runs-every-suite-on-a/20261010-183218.log) |
| ❌ TIMEOUT | BUG-20261010-session-lock-blocks-read-only-commands-s | session lock blocks read-only commands: stash list and grep naming the gate | devkit-guards | REG-DK-ALL-01, universal-agent-devkit/tests/context_memory/test_session_lock_readonly.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-session-lock-blocks-read-only-commands-s/20261010-102107.log) |
| ❌ TIMEOUT | BUG-20261010-test-evidence-gate-rebuilds-the-shell-va | test_evidence_gate rebuilds the shell variable table of every earlier command for each command (quadratic, 25 s on a 58 MB transcript) | test_evidence_gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_evidence_gate_linear.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-test-evidence-gate-rebuilds-the-shell-va/20261010-183459.log) |
| ❌ TIMEOUT | BUG-20261010-test-evidence-gate-treats-a-source-file | test_evidence_gate treats a source file written in a temp or scratchpad dir as the last code edit, so a green run goes stale (36% of 171 real blocks) | test_evidence_gate | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_evidence_scratch_edits.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-test-evidence-gate-treats-a-source-file/20261010-190713.log) |
| ❌ TIMEOUT | BUG-20261010-testsourceset-gate-compiles-the-test-sou | testsourceset_gate compiles the test source sets on every unfinished (CHUA XONG) stop | testsourceset_gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_testsourceset_wip_skip.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261010-testsourceset-gate-compiles-the-test-sou/20261010-183332.log) |
| ❌ TIMEOUT | BUG-20261011-review-log-py-loses-lines-under-concurre | review_log.py loses lines under concurrent writes, erases damaged lines, reads the model from text, takes older results for newer dispatches and counts implement runs as reviews | review_log | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_review_log.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261012-a-bug-linked-to-a-test-file-git-does-not | a bug linked to a test file git does not track yet stays NOT_IN_MATRIX forever (no regression test counted) | checklist | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_bug_untracked_test_ref.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261012-a-bug-linked-to-a-test-file-git-does-not/20261012-222502.log) |
| ❌ TIMEOUT | BUG-20261012-a-session-blocked-by-a-held-checkout-sto | a session blocked by a held checkout stops to ask the user instead of making its own worktree | session-lock | REG-DK-ALL-01, universal-agent-devkit/tests/context_memory/test_session_lock_worktree_hint.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261012-a-session-blocked-by-a-held-checkout-sto/20261012-210656.log) |
| ❌ TIMEOUT | BUG-20261012-hardware-gate-passes-a-quoted-or-root-gl | hardware gate passes a quoted or root-glob rm on a system partition | hardware-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_hardware_unglob_quoted.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261012-hardware-gate-passes-a-quoted-or-root-gl/20261012-205707.log) |
| ❌ TIMEOUT | BUG-20261012-hardware-gate-passes-ansi-c-or-locale-qu | hardware gate passes ANSI-C or locale quoted rm on a system partition (dollar left glued to the command) | hardware-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_hardware_unglob_quoted.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261012-hardware-gate-passes-ansi-c-or-locale-qu/20261012-211115.log) |
| ❌ TIMEOUT | BUG-20261012-hardware-gate-refuses-clearing-adb-scrat | hardware gate refuses clearing adb scratch folder /data/local/tmp | hardware-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_hardware_data_local_tmp.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261012-hardware-gate-refuses-clearing-adb-scrat/20261012-224411.log) |
| ❌ TIMEOUT | BUG-20261012-regression-gate-blocks-the-stop-on-a-sui | regression gate blocks the Stop on a suite killed from outside (exit 137/143) as if a test failed | regression-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_regression_gate_killed_suite.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261012-regression-gate-blocks-the-stop-on-a-sui/20261012-205459.log) |
| ❌ TIMEOUT | BUG-20261012-regression-gate-reuse-key-moves-with-age | regression_gate reuse key moves with agent memory notes because devkit_harness.OWN lacks claude-auto (tree_fp already excludes it) | tree-fp | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_harness_fp_claude_auto.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261012-regression-gate-reuse-key-moves-with-age/20261012-210837.log) |
| ❌ TIMEOUT | BUG-20261012-stop-gates-run-on-progress-replies-whose | stop gates run on progress replies whose only claim is a check mark or a table row | stop-hook | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_outcome_table_rows.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261012-stop-gates-run-on-progress-replies-whose/20261012-211004.log) |
| ❌ TIMEOUT | BUG-20261012-test-evidence-gate-lets-a-pass-claim-thr | test_evidence_gate lets a pass claim through when an exempted match swallows it, and blocks the Vietnamese cycle name or quoted mentions of its trigger words | test-evidence-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_evidence_claim_mentions.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261012-test-evidence-gate-lets-a-pass-claim-thr/20261012-220235.log) |
| ❌ TIMEOUT | BUG-20261012-test-session-lock-resolve-compares-bash | test_session_lock_resolve compares bash errno wording that flips with the directory the test is started from (red from the repo root, also on the unpatched kit) | session-lock | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_session_lock_resolve.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261012-tree-fingerprint-moves-with-agent-memory | tree fingerprint moves with agent memory notes so a green gate receipt is lost | tree-fp | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_tree_fp_claude_auto.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261012-tree-fingerprint-moves-with-agent-memory/20261012-204933.log) |
| ❌ TIMEOUT | BUG-20261012-user-prompt-hook-exits-127-silently-when | user prompt hook exits 127 silently when the hook files are gone, so every guard is off with no warning | hooks | REG-DK-ALL-01, universal-agent-devkit/tests/installer/test_prompt_hook_missing.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261012-user-prompt-hook-exits-127-silently-when/20261012-210439.log) |
| ❌ TIMEOUT | BUG-20261013-a-repo-link-to-the-old-scripts-red-proof | a repo link to the old scripts/red_proof.py path is broken since scripts/ was split into groups | installer | REG-DK-ALL-01, universal-agent-devkit/tests/installer/test_legacy_script_paths.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261013-a-repo-link-to-the-old-scripts-red-proof/20261013-072833.log) |
| ❌ TIMEOUT | BUG-20261013-agent-test-approval-claude-transcript | post-fix-gate never read the agent's in-turn test approval in a Claude Code transcript (message.content), so the Stop hook kept asking the user | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_approval_content_hash.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261013-merge-gate-folder-deleted-before-stop | worktree_merge_gate passed a worktree whose folder was deleted before the Stop while its commit was not in main | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_worktree_merge_gate_vanished.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261013-merge-gate-vanished-worktree-race | worktree_merge_gate held a Stop on a worktree another merge landed, and passed vanished/reflog-only/rewound worktrees whose work never reached main | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_worktree_merge_gate_vanished.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261013-opencodereview-never-ran-ocr-review-exit | OpenCodeReview never ran: ocr review exits 1 without an LLM endpoint, nothing reported it, and review_gate ignored OCR | review-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_review_gate_ocr.sh (trong suite) | RED-proof INCONCLUSIVE: [log](evidence/redproof-BUG-20261013-opencodereview-never-ran-ocr-review-exit/20261013-151107.log) |
| ❌ TIMEOUT | BUG-20261013-regression-gate-blocks-the-stop-of-a-rea | regression_gate blocks the Stop of a read-only session on the diff of the session that holds the checkout | regression-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_regression_gate_held_by_other.sh (trong suite) | RED-proof INCONCLUSIVE: [log](evidence/redproof-BUG-20261013-regression-gate-blocks-the-stop-of-a-rea/20261013-154215.log) |
| ❌ TIMEOUT | BUG-20261013-relink-check-never-links-a-skill-the-dev | relink_check never links a skill the DevKit gained after the install | relink | REG-DK-ALL-01, universal-agent-devkit/tests/worktree_git/test_relink_skills.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261013-relink-check-never-links-a-skill-the-dev/20261013-072848.log) |
| ❌ TIMEOUT | BUG-20261013-test-approval-from-foreign-records | post-fix-gate approved edited tests from records that are not the agent's approval (queue-operation, Antigravity USER_INPUT, other projects' logs, prose, substrings) | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_approval_content_hash.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261013-worktree-gc-deletes-unique-work | worktree gc could delete unique work (unreachable blobs, ignored non-build files, a person's worktree, a live session's worktree) | - | REG-DK-ALL-01, universal-agent-devkit/tests/worktree_git/test_worktree_gc.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-agpm-global-config-guessable-tmp | ANTIGRAVITY_PM_GLOBAL_CONFIG test pin pointed at a guessable path in a shared TMPDIR (kit tests/lib/clean_git_env.sh, MCP tests/helpers.js): a file planted there with giaoDefault/testCommand steered every test | pm-mcp | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-automerge-gate-result-not-object | automerge printed a traceback instead of its JSON line when the gate's last line was JSON but no object | devkit-worktree | REG-DK-ALL-01, universal-agent-devkit/tests/worktree_git/test_worktree_trunk_merge.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-automerge-untracked-symlink | worktree automerge committed an untracked symlink and the fast-forward replaced main's ignored node_modules/ with it | devkit-worktree | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-budget-cut-forgets-passed-suites | A Stop run that spent GATE_TOTAL_BUDGET_S kept no suite results, so the next Stop on the same content ran every suite again | devkit-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_budget_resume.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-evidence-outcome-quoted-mention | test_evidence_gate check 7 read a quoted mention of the phrase 'da fix' as an outcome claim | devkit-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_evidence_outcome_mention.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-fifo-harness-canary-false-green | test_hook_gitignore_fifo canaries printed a pass when their child never started within the limit (nothing was tested) | devkit-tests | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-fifo-harness-cleanup-kill-gone | test_hook_gitignore_fifo crashed with ProcessLookupError when the leaked canary it cleans up had already ended, skipping every later hook check | devkit-tests | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-fifo-harness-grandchild | test_hook_gitignore_fifo killed only the bash child on its timeout, a grandchild blocked on a FIFO outlived the case for ever | devkit-tests | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-fifo-harness-killpg-eperm | test_hook_gitignore_fifo crashed with PermissionError when killpg met a process group holding only zombies on macOS | devkit-tests | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-gate-recreates-removed-project | gate re-created a worktree folder removed while its suites ran (regression_status.json, INBOX, evidence, journal) | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_project_removed_midrun.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-guard-shell-norm-fail-open | command guards let through commands hidden behind su -c, adb shell, ssh option values, bash -lc, wrapper option values, a heredoc operator inside quotes or a comment, and device-side rm forms (braces, dot-dot paths, cd then rm, find -delete, tilde) | devkit-guard | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_guard_shell_norm.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-heredoc-data-false-block | command guards read heredoc data as commands: block-dangerous-git refused a quoted python heredoc whose body held a backtick, hardware_safety_gate walked cat-to-file heredoc bodies as rm commands | devkit-guard | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_guard_shell_norm.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-lock-file-stale-takeover-race | worktree.py _lock_file (automerge, MAIN_LOCK, worktree add) let two waiters take over a dead holder's O_EXCL lock file together, and gave up at once when the file vanished mid-read | - | REG-DK-ALL-01, universal-agent-devkit/tests/worktree_git/test_worktree_lock_helper.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-ocr-endpoint-rejected-holds-stop | ocr-review failed hard when the OCR LLM endpoint rejected every request (API key over its usage limit), so review_gate held every session's Stop | - | REG-DK-ALL-01, universal-agent-devkit/tests/installer/test_ocr_review_helper.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-proof-report-label-variants | proof_gate blocked a report that carried all four items under other labels (Nguy co moi, Da lam gi, Chan loi cu, Da fix duoc gi) | devkit-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_proof_gate_report_labels.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-python-isolation-heartbeat-age | test_hook_python_isolation compared the session_lock heartbeat age in whole seconds, so a run stalled past 1 s under load reported a false BYPASS of session_lock.sh | devkit-tests | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-red-proof-runner-under-tests-read-as-test | red_proof read a production runner under tests/ as a test, so the 09/10 audit rows could not be proven | devkit-gate | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_red_proof.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-review-gate-ocr-scope | review_gate OCR requirement: --from without --to failed, one report cleared committed+uncommitted code, ranged flag read from the whole command | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_review_gate_ocr.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-session-lock-let-cp-mv-rm-tee-sed-i-touc | session_lock let cp/mv/rm/tee/sed -i/touch into a held checkout through, and blocked reads naming the gate folder | devkit-hooks | REG-DK-ALL-01, universal-agent-devkit/tests/context_memory/test_session_lock_file_writes.sh (trong suite) | RED-proof OUTDATED: [log](evidence/redproof-BUG-20261014-session-lock-let-cp-mv-rm-tee-sed-i-touc/20261014-134259.log) |
| ❌ TIMEOUT | BUG-20261014-shell-writes-env-split-escapes | shell_writes read env -S lines with shlex only, so the env escapes \_ (word separator) and \c (end of line) were misread: a write slipped through or a false block | devkit-hooks | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-shell-writes-env-split-sq-escape | shell_writes dropped an env -S line that shlex cannot parse (an escaped quote inside single quotes, which env honours), so its write was never judged | devkit-hooks | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-shell-writes-env-split-string | shell_writes skipped the command line of env -S / --split-string as an option value, so its writes were never judged | devkit-hooks | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-shell-writes-git-c-tilde | shell_writes did not expand ~ in the -C directory of a repository write, so worktree_guard missed a commit into main and blocked one into the worktree | devkit-hooks | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-testsourceset-lock-fifo-hang | testsourceset_gate hung on a FIFO planted at test_run.lock after its FIFO sweep (exec 9>> waits for a reader) | devkit-hooks | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-worktree-reflog-gone-folder | worktree inventory: a commit only the HEAD reflog names passes once the worktree folder is deleted (reflog read only while the folder exists) | devkit-worktree | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261014-worktree-secret-carry | git-ignored secret files made only in a worktree (keystore, key.properties) were deleted with it by finish/automerge/gc | devkit-worktree | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261015-android-rules-reach | android rules: selection-size and wiring-pin sections unreachable from the prompts that need them; PII half-rule in an on-demand block; ambiguous bucket spec | - | REG-DK-ALL-01, universal-agent-devkit/tests/context_memory/test_profile_split.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261015-churn-guard-p6 | churn_guard untracked-edit warning starts repo-owned code, repeats process spawns on re-edit, walks huge payloads | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_untracked_edit_warning.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261015-generic-traps-id | android generic-traps test hard-codes the promoted instinct id and exports a DEVKIT_ROOT agent-kit overwrites | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_android_generic_traps.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261015-generic-traps-round2 | android generic-traps test: stale comment, literal id 908 coupled to the real file, promote exit code unchecked in section C | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_android_generic_traps.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261015-lens-pin | state-matrix lens pin could not fail (token anywhere in the file) and the kit lens named document-viewer axes | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_state_matrix_lens.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261015-nightly-idle-holder | nightly named run ignores an idle session that holds the checkout | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_nightly.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261015-nightly-round2 | nightly named run: unreadable git dir and trunk-mode main went ahead, one repo ran twice under two letter cases, ~user raised | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_nightly.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261015-nightly-run-paths | nightly run accepts an empty path, runs one repo twice and passes a non-project folder | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_nightly.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261015-rule-titles-noise | android rules section titles stuffed with common words pointed ordinary prompts at section 12 or 16 | - | REG-DK-ALL-01, universal-agent-devkit/tests/context_memory/test_profile_split.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261015-wiring-pin-detect | wiring_pin scan: pin name per View only, View-only test silences, same-file object ignored, data class taken for a View, comment counted as a call, empty-bodied pin, unrunnable verify hint | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_wiring_pin.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261015-wiring-pin-round2 | wiring_pin verify misreads an inner trailing comma, counts a raw-string decoy, accepts a string-literal mention as a call | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_wiring_pin.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261015-wiring-pin-scan | wiring_pin scan skips non-ASCII paths, hangs on a FIFO, tracebacks on a Latin-1 byte, flags renamed files as new | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_wiring_pin.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261015-wiring-pin-verify | wiring_pin verify says holds for a wrapped or unreadable assertion, a comment-only call, an empty pin, a path outside root | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_wiring_pin.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261016-proof-gate-recursion-fail-open | proof_gate: a deeply nested receipt or state file crashes the hook with RecursionError and XONG passes (python exit 1 becomes wrapper exit 0) | devkit-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_proof_gate.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ❌ TIMEOUT | BUG-20261024-fix-root-cause-devkit-de-sau-nay-ko-bi-l | Fix root cause devkit để sau này ko bị lỗi dừng board cũng như cáv task bị kẹt lại như thế này nữa | - | REG-SB-RUNNER-WATCHDOG-01 | [log REG-SB-RUNNER-WATCHDOG-01](evidence/REG-SB-RUNNER-WATCHDOG-01/20261024-135501.log) |
| ❌ TIMEOUT | BUG-VACUITY-SINCE-BASE | gate: vacuity revert uses HEAD under --since, so committed fixes look vacuous | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_vacuity_since.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-VACUITY-SINCE-BASE/20261009-171732.log) |
| ❌ TIMEOUT | BUG-WT-1013 | worktree copies keep the macOS uchg flag so remove cannot delete them and leaves an unregistered orphan folder | - | REG-DK-ALL-01, universal-agent-devkit/tests/worktree_git/test_worktree_immutable_copy.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261014-pm-agy-init-compact-json-only | agy init event was found by a compact-JSON substring only: a stream-json line with spaces after the colon made every agy dispatch fail or wait the 60 s init timeout | pm-mcp | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261024-124541.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261014-pm-agy-lock-takeover-race | agy registry lock: stale-lock takeover was delete-then-create, so two PMs that saw the same stale lock could both enter the critical section (the second deleted the first one's NEW lock) and overwrite agy-conversations.json | pm-mcp | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261024-124541.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261014-pm-agy-prune-budget-breaks-loop | agy registry prune: once 3 entries with a pid had been checked with ps the loop stopped, so older entries without a pid (no ps needed) were kept and the registry grew past 500 | pm-mcp | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261024-124541.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261014-pm-doctor-agy-only-default-model | pm_doctor printed the agy diagnostics (binary, broken registry, permission policy) only when defaultModel was an agy model, so a task that runs agy through its own model or pm_dispatch model got no explanation for a failed dispatch | pm-mcp | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261024-124541.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261014-pm-ping-kills-reused-pid | pm_doctor ping stopped its agy turns with kill(pid,0)+kill(-pid): up to 90 s later the pid may have exited and been reused, so it could SIGKILL a stranger's process group | pm-mcp | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261024-124541.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261014-pm-status-agy-by-task-model | pm_status trusted task.model to tell an agy conversation from an IDE one: with ps broken a tier task whose conversation went through agy (pm_dispatch model=...) was nudged anyway and lost its whole report; the PLAN-phase nudge branch had no unknown-state check at all | pm-mcp | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261024-124541.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261014-pm-tests-guessable-agy-path | MCP tests that simulate a missing agy pointed ANTIGRAVITY_PM_AGY at a guessable path in the shared TMPDIR: an executable planted there would be run, in two tests with --dangerously-skip-permissions | pm-mcp | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261024-124541.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-droppending-always-writes | pm-mcp: dropPending rewrote the registry even when it removed nothing (delete returns true for absent keys) | - | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261024-124541.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-droppending-foreign-entry | pm-mcp: dropPending deleted by key only and could remove another live PM's pending entry | - | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261024-124541.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-null-selftag-accepted | pm-mcp: a null own fingerprint was accepted, leaving an entry that is never reaped | - | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261024-124541.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-orphan-sigkill | pm-mcp: agy opened by newConversation is orphaned when the PM is SIGKILLed while waiting for init (no pending record by pid) | - | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261024-124541.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-pending-leak-final-write | pm-mcp: a failed real-entry write after agy init left a pending-<pid> record in the registry | - | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261024-124541.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-reaper-recheck-before-kill | pm-mcp: reaper identity check ran outside the lock, long before the kill under the lock | - | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261024-124541.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-reaper-same-key-kill | pm-mcp: reaper re-check compared only the pid under a pid-keyed entry, so a rewritten pending entry (pid reuse) was killed | - | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261024-124541.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-reaper-stale-snapshot-kill | pm-mcp: orphan reaper killed from a stale registry snapshot, so an agy a PM had just registered could be killed | - | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261024-124541.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-selftag-after-spawn | pm-mcp: the PM read its own ps fingerprint after spawning agy, widening the untracked window | - | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261024-124541.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261022-check-cac-task-trong-blocked-dang-bi-gi | check các task trong blocked đang bị gì fix devkit rồi restart lại | - | REG-SB-PREFLIGHT-STALE-OVERLAP-01 | [log REG-SB-PREFLIGHT-STALE-OVERLAP-01](evidence/REG-SB-PREFLIGHT-STALE-OVERLAP-01/20261024-130512.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261022-co-dang-bi-stuck-ko-vay | có đang bị stuck ko vậy? | - | REG-SB-RUNNER-READ-RETRY-01 | [log REG-SB-RUNNER-READ-RETRY-01](evidence/REG-SB-RUNNER-READ-RETRY-01/20261024-121059.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261023-cac-config-cpu-workload-hoat-dong-khong | các config cpu workload hoạt động không chính xác cần đổi logic lại đơn giản hơn là tổng số task chạy cùng trên buildin… | - | REG-SB-TOTAL-CAP-01 | [log REG-SB-TOTAL-CAP-01](evidence/REG-SB-TOTAL-CAP-01/20261024-121352.log) |
| 🐞 chưa sửa | BUG-20261012-test-chap-chon-flaky-reg-dk-session-01 | Test chập chờn (flaky): REG-DK-SESSION-01 | devkit-session-lock | REG-DK-SESSION-01 | [log REG-DK-SESSION-01](evidence/REG-DK-SESSION-01/20261024-132926.log) |
| 🐞 chưa sửa | BUG-20261013-test-chap-chon-flaky-reg-dk-all-01 | Test chập chờn (flaky): REG-DK-ALL-01 | devkit-all | REG-DK-ALL-01 | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| 🐞 chưa sửa | BUG-20261023-test-chap-chon-flaky-reg-sb-runner-recla | Test chập chờn (flaky): REG-SB-RUNNER-RECLAIM-DEAD-BUILD-01 | super-board-runner-reclaim-dead-build | REG-SB-RUNNER-RECLAIM-DEAD-BUILD-01 | [log REG-SB-RUNNER-RECLAIM-DEAD-BUILD-01](evidence/REG-SB-RUNNER-RECLAIM-DEAD-BUILD-01/20261024-121326.log) |
| ⚠️ có test, gate không chạy | BUG-20261013-bug-capture-copied-a-pasted-secret | Bug capture copied an API key pasted in a prompt into regression_status.json and CHECKLIST.md (title and id unredacted) | checklist | tests/verification/test_bug_secret_redaction.sh (ngoài matrix) | 13/10 workbench: REPORTED row held a pasted key; redact_secrets at register_bug/ |
| ⚠️ có test, gate không chạy | BUG-20261013-regression-gate-held-skip-ignored-writers | regression_gate skipped the Stop for a payload without session_id or with DEVKIT_ALLOW_SHARED_CHECKOUT=1 while another session held the lock | gates | tests/gates/test_regression_gate_held_by_other.sh (ngoài matrix) | OpenCodeReview of Dot 29 (13/10): held-by-other skip ignored the cases session_l |
| ⏳ chưa chạy | BUG-20261024-antigravity-2-tien-trinh-da-chay-03-35-1 | Antigravity · / · 2 tiến trình · đã chạy 03:35:14 chạy 26 tiến trình có đúng ko hay là lỗi | - | REG-AGENT-OFFICE-01, mcp-servers/agent-office/tests/test_agent_workload.py (trong suite) | [log REG-AGENT-OFFICE-01](evidence/REG-AGENT-OFFICE-01/20261024-120921.log) |
| ⏳ chưa chạy | BUG-20261024-dieu-tra-tai-sao-test-gate-suite-cache-s | Điều tra tại sao test_gate_suite_cache_selection S5 đỏ khi chạy trong gate gộp nhưng xanh khi chạy lẻ, sửa nếu là lỗi c… | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_suite_cache_selection.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ⏳ chưa chạy | BUG-20261024-fix-dev-kit-de-lan-sau-ko-bi-loi-nghiem | fix dev kit để lần sau ko bị lỗi nghiêm trọng này nữa, đây là lỗi tuyệt đối nghiêm trọng sau này ko đc phép bị lại nữa | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_run_bounded.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ⏳ chưa chạy | BUG-20261024-fix-het-cac-cho-bi-ket-luon-di | Fix hết các chỗ bị kẹt luôn đi | - | REG-DK-ALL-01, tests/gates/test_gate_robustness.sh (ngoài matrix) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ⏳ chưa chạy | BUG-20261024-tai-sao-tien-trinh-bi-ket-check-fix-dev | tại sao tiến trình bị kẹt check fix dev kit | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_run_bounded.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ⏳ chưa chạy | BUG-20261027-1-the-backlog-xep-integrate-py-thieu-han | 1. Thẻ Backlog: xếp "integrate.py thiếu handler SIGTERM → scratch chứa .env/keystore bị bỏ lại" lên P2, trên 2 điểm P3… | - | REG-DK-ALL-01, universal-agent-devkit/tests/worktree_git/test_integrate_signal_cleanup.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ⏳ chưa chạy | BUG-20261028-check-cac-task-bi-blocked-nguyen-nhan-la | check các task bị blocked nguyên nhân là gì thế fix root cause rồi chuyển task về lại ready | - | REG-DK-ALL-01, universal-agent-devkit/tests/worktree_git/test_worktree_remove_branch_rename.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ⏳ chưa chạy | BUG-20261031-ao-3d-ve-60fps-khi-dung-yen | agent-office: cảnh 3D vẽ 60 khung/giây ở DPR 2 cả khi đứng yên / giảm chuyển động (~45% CPU renderer + ~44% GPU lúc rảnh), tab ẩn vẫn tải /api/state ~480 KB mỗi 3 giây | agent-office-perf | REG-AGENT-OFFICE-01, mcp-servers/agent-office/tests/test_frame_pacing.py (trong suite), mcp-servers/agent-office/tests/test_poll.py (trong suite) | [log REG-AGENT-OFFICE-01](evidence/REG-AGENT-OFFICE-01/20261024-120921.log) |
| ⏳ chưa chạy | BUG-20261031-ao-dash-khong-hien-khi-drawer-mo | agent-office: bấm "Chỉ số" khi drawer (Vừa xảy ra / agent / repo) đang mở không hiện gì — bảng bật ngầm, CSS body.drawer-open ẩn .dash | agent-office-ui | REG-AGENT-OFFICE-01, mcp-servers/agent-office/tests/test_ui_toolbar_account.py (trong suite) | [log REG-AGENT-OFFICE-01](evidence/REG-AGENT-OFFICE-01/20261024-120921.log) |
| ⏳ chưa chạy | BUG-20261031-ao-mobile-khung-agent-tran-mep-tren | agent-office điện thoại: khung "Ai đang làm gì" mọc lên quá mép trên (top -60px), nút + / − đè chữ, drawer/bảng chồng lên khung trái; chỗ bấm ⋯ / + / − / × / Ẩn dưới 44px | agent-office-ui | REG-AGENT-OFFICE-01, mcp-servers/agent-office/tests/test_ui_toolbar_account.py (trong suite) | [log REG-AGENT-OFFICE-01](evidence/REG-AGENT-OFFICE-01/20261024-120921.log) |
| ⏳ chưa chạy | BUG-20261031-ao-phone-dialog-mat-focus | agent-office: đóng hộp Điện thoại (Esc / Đóng) mở từ menu ⋯ làm focus rơi về <body> (mục menu đã ẩn không nhận focus) | agent-office-ui | REG-AGENT-OFFICE-01, mcp-servers/agent-office/tests/test_ui_toolbar_account.py (trong suite) | [log REG-AGENT-OFFICE-01](evidence/REG-AGENT-OFFICE-01/20261024-120921.log) |
| ⏳ chưa chạy | BUG-20261031-ao-server-glob-transcript-moi-3s | agent-office server: glob lại ~5000 transcript / ~3500 thư mục mỗi 3 giây (~100 ms CPU mỗi vòng), /api/state ~480 KB không nén | agent-office-perf | REG-AGENT-OFFICE-01, mcp-servers/agent-office/tests/test_perf_server.py (trong suite) | [log REG-AGENT-OFFICE-01](evidence/REG-AGENT-OFFICE-01/20261024-120921.log) |
| ⏳ chưa chạy | BUG-20261031-ao-texture-xuong-moi-luoi | agent-office: mỗi lưới có da của người 3D giữ Skeleton riêng dù cùng bộ xương — ~300 lần texSubImage2D (tải texture xương) mỗi khung | agent-office-perf | REG-AGENT-OFFICE-01, mcp-servers/agent-office/tests/test_share_skeleton.py (trong suite) | [log REG-AGENT-OFFICE-01](evidence/REG-AGENT-OFFICE-01/20261024-120921.log) |
| ⏳ chưa chạy | BUG-20261031-gate-full-chay-chong-nhieu-repo | gate-full: lịch đêm nhiều repo + chạy tay chạy --full song song trên cùng máy (chỉ có khoá theo repo) | gate-full | REG-DK-ALL-GATES-01, universal-agent-devkit/tests/gates/test_gate_full_global_lock.sh (trong suite) | - |
| ⏳ chưa chạy | BUG-20261114-command-guards-allow-tag-deletion-stdin | command guards allow tag deletion, stdin-fed shells and interpreter deletes | hooks | REG-DK-ALL-01, REG-DK-ALL-GATES-01, REG-DK-ALL-REST-01, REG-DK-ALL-WORKTREE-01, universal-agent-devkit/tests/gates/test_guard_zero_defect_c4.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ⏳ chưa chạy | BUG-20261114-gate-misses-placeholder-variants-unscann | gate misses placeholder variants, unscanned file types and secret forms | gate | REG-DK-ALL-01, REG-DK-ALL-GATES-01, REG-DK-ALL-REST-01, REG-DK-ALL-WORKTREE-01, universal-agent-devkit/tests/gates/test_gate_placeholder_secret_zero_defect.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ⏳ chưa chạy | BUG-20261114-guard-secrets-allows-reading-secret-file | guard-secrets allows reading secret files the gate forbids to commit | hooks | REG-DK-ALL-01, REG-DK-ALL-GATES-01, REG-DK-ALL-REST-01, REG-DK-ALL-WORKTREE-01, universal-agent-devkit/tests/gates/test_guard_secrets_zero_defect.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |
| ⏳ chưa chạy | BUG-20261114-stop-gate-accepts-unverified-test-result | stop gate accepts unverified test-result wording and zero-test runner runs | hooks | REG-DK-ALL-01, REG-DK-ALL-GATES-01, REG-DK-ALL-REST-01, REG-DK-ALL-WORKTREE-01, universal-agent-devkit/tests/gates/test_evidence_zero_defect_c1.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261024-073048.log) |

## 🟡 REPORTED — bug báo qua prompt, chưa xác nhận (22)

> Chưa tính là bug. Xác nhận: `agent-kit bugs add "<tiêu đề>" --id <ID>` · có test ĐỎ→XANH: `agent-kit bugs link <ID> <TEST>` · không phải bug: `agent-kit bugs drop <ID>`

| ID | Prompt | Ngày |
|---|---|---|
| BUG-20261016-audit-review-cho-toi-5-repo-https-github | audit, review cho tôi 5 repo https://github.com/ToanMobile?tab=projects hiện nhiều task bị blocked,ready ko chạy được t… | 2026-10-16 17:44:34 |
| BUG-20261016-gan-label-theo-thu-tu-uu-tien-da-lap-va | Gắn label theo thứ tự ưu tiên đã lập và dừng vòng lặp super-board đang lỗi | 2026-10-16 20:57:33 |
| BUG-20261017-toi-se-chi-file-hoac-config-co-duong-dan | Tôi sẽ chỉ file hoặc config có đường dẫn push_gate sai | 2026-10-17 08:23:46 |
| BUG-20261019-hien-cac-task-dang-bi-ket-o-cac-luong-re | hiện các task đang bị kẹt ở các luồng review, QA, building xử lý ntn? | 2026-10-19 09:07:27 |
| BUG-20261019-hien-con-nhieu-branch-dang-bi-mo-coi-ngu | hiện còn nhiều branch đang bị mồ côi nguyên nhân tại sao vậy? | 2026-10-19 16:53:00 |
| BUG-20261019-sao-bi-ket-hoai-vay-truoc-do-chay-test-2 | sao bị kẹt hoài vậy trước đó chạy test 20 phiên mỗi repo đều pass trơn tru mà? | 2026-10-19 09:10:06 |
| BUG-20261019-update-lai-cac-pr-log-comment-don-gian-t | update lại các PR log comment đơn giản tự nhiên nhanh gọn ko dài dòng tránh lỗi chặn khi diff PR quá lớn | 2026-10-19 07:34:55 |
| BUG-20261020-hien-van-bi-ket-tin-nhan | hiện vẫn bị kẹt tin nhắn | 2026-10-20 00:17:04 |
| BUG-20261020-la-sao-fix-chua-do-hien-van-ket-phai-bam | là sao fix chưa? đó hiện vẫn kẹt phải bấm send now để gửi ép | 2026-10-20 00:07:23 |
| BUG-20261020-no-ket-stop-hook-prompt-cua-toi-ko-run-d | nó kẹt stop hook prompt của tôi ko run đc | 2026-10-20 00:02:14 |
| BUG-20261020-tai-sao-no-phai-chay-full-nhi-no-chay-te | tại sao nó phải chạy --full nhỉ nó chạy tets trên những file sửa của worktree đó thôi còn full thì chạy 1 lần khi push… | 2026-10-20 17:36:09 |
| BUG-20261021-xu-ly-cho-xong-nhung-issues-bi-ket-het-c | xử lý cho xong những issues bị kẹt hết cho tôi | 2026-10-21 08:04:56 |
| BUG-20261022-audit-review-devkit-board-dang-bi-ket-ch | audit, review devkit board đang bị kẹt check tại sao fix đi | 2026-10-22 07:33:51 |
| BUG-20261022-bi-dung-roi-a | bị đứng rồi à | 2026-10-22 16:56:22 |
| BUG-20261022-check-21-gate-hien-lam-gi-nhieu-vay-dc-c | Check 21 gate hiện làm gì nhiều vậy đc chắc chắn có gate bị kẹt cũ lại | 2026-10-22 21:22:12 |
| BUG-20261022-dung-ai-factory-test-va-sua-luon-loi-kie | dùng ai-factory.test và sửa luôn lỗi kiểm Host | 2026-10-22 13:15:47 |
| BUG-20261022-la-sao-gate-bi-dinh-cu-dung-ko | Là sao gate bị dính cũ đúng ko | 2026-10-22 21:28:12 |
| BUG-20261022-sao-228-cung-nam-trong-blocked-de-ntn-to | sao 228 cũng nằm trong blocked? Để ntn tôi sẽ bị nhầm nó đang đứng ko chạy được? | 2026-10-22 17:22:36 |
| BUG-20261022-tuong-nam-hang-doc-sai-roi-tuong-phai-ha | tường nằm hàng dọc sai rồi tường phải hàng ngang còn các phòng có tường nhưng giữa cùng 1 repo có cửa để di chuyển sang… | 2026-10-22 16:18:33 |
| BUG-20261022-van-de-la-toi-uu-de-no-ko-chay-gate-lien | Vấn đề là tối ưu để nó ko chạy gate liên tục chỉ có 3 review sao chạy tới 21 gate logic sai | 2026-10-22 21:33:10 |
| BUG-20261023-update-them-toi-muon-cai-ban-xoay-lai-hu | update thêm tôi muốn cái bàn xoay lại hướng tôi hiện bị quay lưng rồi | 2026-10-23 11:46:11 |
| BUG-20261024-need-you-vs-gom-task-toi-da-tung-lam-tru | need you vs gom task tôi đã từng làm trước đó nhưng hiện không hoạt động được | 2026-10-24 08:29:21 |
