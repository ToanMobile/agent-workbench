# 🧪 Regression Checklist

**An toàn 0% (0/218)** · ❌ 108 · 🔁 0 · 🚫 0 · 🟡 45 cần chạy lại · ⚠️ 2 cần test · ⚠️ 4 test có thể không suite nào chạy · 🐞 2 chưa sửa · ⏳ 61 chờ · 🚗 0 chờ chạy lặp trên xe · 🟡 REPORTED 31 · ma trận chờ duyệt: không

> Sinh tự động lúc 2026-10-24 14:53:55 — **không sửa tay**. % an toàn = PASS ÷ mọi dòng test/REQ/bug đã xác nhận (REPORTED không tính). PASS chỉ từ lần chạy thật + (bug/REQ) test đã chứng minh ĐỎ.

**Bug không có test hồi quy nào chặn tái phát: 2** (0 chưa có test · 2 có test nhưng gate không chạy)

## 🚨 Cần xử lý (161)

| Trạng thái | ID | Tính năng / Bug | Component | Việc cần làm |
|---|---|---|---|---|
| ❌ FAIL | BUG-20260925-prompt-bao-bug-that-cung-se-khong-con-du | prompt báo bug thật cũng sẽ không còn được ghi nhận nữa -> là sao bug đúng ko fix đi phải tự động ghi nhận chứ | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20260926-dev-kit-lam-tao-branch-push-lung-tung-kh | dev kit làm tạo branch, push lung tung không đồng bộ dẫn tới lệch code, vd geely ex2 hiện có 2 pull chưa pull về dẫn tớ… | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20260928-audit-review-them-geely-ex2-hien-no-bao | audit, review thêm geely ex2 hiện nó báo tôi rất nhiều lỗi vậy có nghĩa là bộ devkit hoàn toàn chất lượng kém để thủng… | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20260928-fix-luon-loi-git-guard-chan-grep-di-ngoa | fix luôn lỗi git guard chặn grep đi ngoài ra đã tối ưu token sử dụng cũng như thời gian chạy chưa ? Đề xuất các phương… | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20260928-push-geely-va-fix-luon-loi-red-proof | push geely và fix luôn lỗi red_proof | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20260928-san-check-luon-chat-luong-dev-kit-workfl | sẵn check luôn chất lượng dev kit workflow có bị lỗi gì ko fix luôn đi | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20260929-audit-review-nguyen-nhan-tai-sao-cac-ses | audit, review nguyên nhân tại sao các sesion cài dev kit chạy rất chậm có lỗi gì hay ko? | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261001-lam-luon-fix-bug-worktree-di | làm luôn fix bug worktree đi | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261001-sua-luon-bug-init-xoa-mcp-server-di | sửa luôn bug init xoá MCP server đi | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261002-agent-kit-health-run-tests-scores-96-100 | agent-kit health --run-tests scores 96/100: agent-kit test runs ~90 test scripts one after another (~19 min), past the 900 s limit health allows | devkit-health | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261002-chay-finagling-running-stop-hooks-8-9-27 | chạy Finagling… (running Stop hooks… 8/9 · 27m 24s · ↓ 46.3k tokens) quá lâu audit, review sửa lại đi Stop hooks… rất h… | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261002-evidence-gate-foreign-xml-nonrunner | test_evidence_gate: a Bash that only names a foreign project (cd && git status) made its fresh XML count as this session's test evidence | devkit | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261002-gate-rejects-a-change-that-moves-a-test | Gate REJECTs a change that moves a test file the matrix names: it runs the base matrix, whose command names the removed path (exit 127), and flags the matrix edit for review | devkit-gate | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261002-proof-gate-reinit-same-profile | proof gate: re-init rewriting the same backend profile counted as a profile switch and demanded a PNG | devkit | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261002-sessionstart-skips-the-checklist-block-a | SessionStart skips the checklist block and the background STALE re-run after the scripts/ regrouping (bin/ and stale_rerun.py paths) | devkit-hooks | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261008-sua-4-loi-kit-phien-office-nho-di | sửa 4 lỗi kit phiên Office nhờ đi | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261009-automerge-refusal-reason-lost | worktree automerge: a commit refused by the repo's pre-commit gate was reported with only the last 500 characters of the gate output, which is the passed-checks footer, never the finding: the worktree stayed unmerged and nobody could tell why (GeelyEx2 giao-tichhop-09-10, base-hoiquy-09-10) | devkit-worktree | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261009-churn-guard-no-fast-path | churn_guard started python on every Edit although it can warn only when the transcript names the file at least N times | devkit-hooks | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261009-comment-claim-docstring-trailing | comment_claim_guard: a claim inside a Python docstring or after code on the same line (# / //) passed while the same words in a full-line comment warn | devkit-hooks | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261009-gate-js-describe-title-false-flag | post-fix-gate: the same it('title') in two different describe blocks flagged a pure append of a JS test as an edited test | devkit-gate | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261009-gate-runner-no-errexit-append | post-fix-gate: any command appended to a shell test runner WITHOUT set -e counted as a pure append, though it decides the exit status over an earlier failure (user decision 2026-10-09) | devkit-gate | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261009-git-guard-bash-c-subst-tee-shell | block-dangerous-git: bash -c "$(curl ...)" and a shell inside >(...) ran generated text that curl \| bash and bash <(...) already refuse | devkit-git-guard | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261009-hardware-find-negated-or-unfiltered | hardware_safety_gate: find ! -name x -delete, -not, and an -o alternative without a filter counted as filtered, so the start point was never judged | devkit-hardware-gate | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261009-hooks-log-dir-process-cwd | 7 hooks (bash_write_ledger, security_gate, proof_gate, regression_gate, test_evidence_gate, review_timing_guard, prompt_context) took the project from the PROCESS cwd when CLAUDE_PROJECT_DIR was unset and created .claude/audit-gate there (a run at / wrote /.claude) | devkit-hooks | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261009-merge-gate-held-vanished-worktree | worktree_merge_gate: a worktree removed by the last Stop's background merge while this Stop decided stayed in the hold list (flaky test_worktree_merge_gate_owner) | devkit-worktree | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261009-review-timing-guard-env-payload | review_timing_guard: the hook payload travelled in an environment variable, so an Edit of a big file (payload past the 1 MiB exec limit) made the shell fail with Argument list too long and the guard never ran | devkit-hooks | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261009-run-impacted-recent-commits-in-sandbox | run_impacted.sh in a checkout with no upstream (every RED-proof sandbox) selected the tests of every commit of the last 6 hours: 25+ minutes per proof instead of the few tests of the reverted file | devkit-tests | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261009-scratch-cleanup-prune-could-delete-a-liv | scratch_cleanup: prune could delete a live idle session's dir and follow a slug swapped for a symlink (TOCTOU) | devkit-scratch-cleanup | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261009-session-lock-a-cp-rc-copy-of-a-checkout | session_lock: a cp -Rc copy of a checkout carried the original's lock and was held by its live holder up to 600 s | devkit-session-lock | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261009-session-lock-an-idle-holder-turn-over-wa | session_lock: an idle holder (turn over, waiting at the prompt) kept the checkout 600 s, other sessions needed /exit | devkit-session-lock | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261009-session-lock-case-only-path | session_lock: a path spelled with other letter case (APFS) fell outside the locked checkout, so the write took no lock and a live holder lost it | devkit-session-lock | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261010-gate-swallows-a-failed-linter-import-and | gate swallows a failed linter import and switches the lint off silently | devkit-guards | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261010-gate-wants-a-regression-test-for-red-pro | gate wants a regression test for red-proof patch files | devkit-guards | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261010-guard-hooks-lose-the-command-that-follow | guard hooks lose the command that follows a comment or a hash inside a word | devkit-guards | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261010-health-reports-100-while-a-tracked-symli | health reports 100 while a tracked symlink points at a missing target | devkit-guards | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261010-matrix-accepts-one-suite-id-with-two-dif | matrix accepts one suite id with two different commands without a word | devkit-guards | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261010-proof-gate-blocks-a-push-turn-whose-4-it | proof_gate blocks a push turn whose 4-item report was already written right after the push | proof_gate | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261010-red-proof-keeps-a-patch-of-any-size-in-a | red proof keeps a patch of any size in a tracked folder | devkit-guards | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261010-regression-gate-re-runs-every-suite-on-a | regression_gate re-runs every suite on a repeated FAIL when one suite cannot run here, ignores local config and age, and sessions erase each other's stored blocks | regression_gate | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261010-session-lock-blocks-read-only-commands-s | session lock blocks read-only commands: stash list and grep naming the gate | devkit-guards | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261010-test-evidence-gate-rebuilds-the-shell-va | test_evidence_gate rebuilds the shell variable table of every earlier command for each command (quadratic, 25 s on a 58 MB transcript) | test_evidence_gate | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261010-test-evidence-gate-treats-a-source-file | test_evidence_gate treats a source file written in a temp or scratchpad dir as the last code edit, so a green run goes stale (36% of 171 real blocks) | test_evidence_gate | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261010-testsourceset-gate-compiles-the-test-sou | testsourceset_gate compiles the test source sets on every unfinished (CHUA XONG) stop | testsourceset_gate | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261011-review-log-py-loses-lines-under-concurre | review_log.py loses lines under concurrent writes, erases damaged lines, reads the model from text, takes older results for newer dispatches and counts implement runs as reviews | review_log | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261012-a-bug-linked-to-a-test-file-git-does-not | a bug linked to a test file git does not track yet stays NOT_IN_MATRIX forever (no regression test counted) | checklist | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261012-a-session-blocked-by-a-held-checkout-sto | a session blocked by a held checkout stops to ask the user instead of making its own worktree | session-lock | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261012-hardware-gate-passes-a-quoted-or-root-gl | hardware gate passes a quoted or root-glob rm on a system partition | hardware-gate | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261012-hardware-gate-passes-ansi-c-or-locale-qu | hardware gate passes ANSI-C or locale quoted rm on a system partition (dollar left glued to the command) | hardware-gate | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261012-hardware-gate-refuses-clearing-adb-scrat | hardware gate refuses clearing adb scratch folder /data/local/tmp | hardware-gate | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261012-regression-gate-blocks-the-stop-on-a-sui | regression gate blocks the Stop on a suite killed from outside (exit 137/143) as if a test failed | regression-gate | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261012-regression-gate-reuse-key-moves-with-age | regression_gate reuse key moves with agent memory notes because devkit_harness.OWN lacks claude-auto (tree_fp already excludes it) | tree-fp | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261012-stop-gates-run-on-progress-replies-whose | stop gates run on progress replies whose only claim is a check mark or a table row | stop-hook | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261012-test-evidence-gate-lets-a-pass-claim-thr | test_evidence_gate lets a pass claim through when an exempted match swallows it, and blocks the Vietnamese cycle name or quoted mentions of its trigger words | test-evidence-gate | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261012-test-session-lock-resolve-compares-bash | test_session_lock_resolve compares bash errno wording that flips with the directory the test is started from (red from the repo root, also on the unpatched kit) | session-lock | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261012-tree-fingerprint-moves-with-agent-memory | tree fingerprint moves with agent memory notes so a green gate receipt is lost | tree-fp | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261012-user-prompt-hook-exits-127-silently-when | user prompt hook exits 127 silently when the hook files are gone, so every guard is off with no warning | hooks | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261013-a-repo-link-to-the-old-scripts-red-proof | a repo link to the old scripts/red_proof.py path is broken since scripts/ was split into groups | installer | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261013-agent-test-approval-claude-transcript | post-fix-gate never read the agent's in-turn test approval in a Claude Code transcript (message.content), so the Stop hook kept asking the user | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261013-merge-gate-folder-deleted-before-stop | worktree_merge_gate passed a worktree whose folder was deleted before the Stop while its commit was not in main | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261013-merge-gate-vanished-worktree-race | worktree_merge_gate held a Stop on a worktree another merge landed, and passed vanished/reflog-only/rewound worktrees whose work never reached main | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261013-opencodereview-never-ran-ocr-review-exit | OpenCodeReview never ran: ocr review exits 1 without an LLM endpoint, nothing reported it, and review_gate ignored OCR | review-gate | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261013-regression-gate-blocks-the-stop-of-a-rea | regression_gate blocks the Stop of a read-only session on the diff of the session that holds the checkout | regression-gate | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261013-relink-check-never-links-a-skill-the-dev | relink_check never links a skill the DevKit gained after the install | relink | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261013-test-approval-from-foreign-records | post-fix-gate approved edited tests from records that are not the agent's approval (queue-operation, Antigravity USER_INPUT, other projects' logs, prose, substrings) | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261013-worktree-gc-deletes-unique-work | worktree gc could delete unique work (unreachable blobs, ignored non-build files, a person's worktree, a live session's worktree) | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-agpm-global-config-guessable-tmp | ANTIGRAVITY_PM_GLOBAL_CONFIG test pin pointed at a guessable path in a shared TMPDIR (kit tests/lib/clean_git_env.sh, MCP tests/helpers.js): a file planted there with giaoDefault/testCommand steered every test | pm-mcp | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-automerge-gate-result-not-object | automerge printed a traceback instead of its JSON line when the gate's last line was JSON but no object | devkit-worktree | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-automerge-untracked-symlink | worktree automerge committed an untracked symlink and the fast-forward replaced main's ignored node_modules/ with it | devkit-worktree | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-budget-cut-forgets-passed-suites | A Stop run that spent GATE_TOTAL_BUDGET_S kept no suite results, so the next Stop on the same content ran every suite again | devkit-gate | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-evidence-outcome-quoted-mention | test_evidence_gate check 7 read a quoted mention of the phrase 'da fix' as an outcome claim | devkit-gate | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-fifo-harness-canary-false-green | test_hook_gitignore_fifo canaries printed a pass when their child never started within the limit (nothing was tested) | devkit-tests | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-fifo-harness-cleanup-kill-gone | test_hook_gitignore_fifo crashed with ProcessLookupError when the leaked canary it cleans up had already ended, skipping every later hook check | devkit-tests | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-fifo-harness-grandchild | test_hook_gitignore_fifo killed only the bash child on its timeout, a grandchild blocked on a FIFO outlived the case for ever | devkit-tests | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-fifo-harness-killpg-eperm | test_hook_gitignore_fifo crashed with PermissionError when killpg met a process group holding only zombies on macOS | devkit-tests | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-gate-recreates-removed-project | gate re-created a worktree folder removed while its suites ran (regression_status.json, INBOX, evidence, journal) | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-guard-shell-norm-fail-open | command guards let through commands hidden behind su -c, adb shell, ssh option values, bash -lc, wrapper option values, a heredoc operator inside quotes or a comment, and device-side rm forms (braces, dot-dot paths, cd then rm, find -delete, tilde) | devkit-guard | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-heredoc-data-false-block | command guards read heredoc data as commands: block-dangerous-git refused a quoted python heredoc whose body held a backtick, hardware_safety_gate walked cat-to-file heredoc bodies as rm commands | devkit-guard | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-lock-file-stale-takeover-race | worktree.py _lock_file (automerge, MAIN_LOCK, worktree add) let two waiters take over a dead holder's O_EXCL lock file together, and gave up at once when the file vanished mid-read | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-ocr-endpoint-rejected-holds-stop | ocr-review failed hard when the OCR LLM endpoint rejected every request (API key over its usage limit), so review_gate held every session's Stop | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-proof-report-label-variants | proof_gate blocked a report that carried all four items under other labels (Nguy co moi, Da lam gi, Chan loi cu, Da fix duoc gi) | devkit-gate | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-python-isolation-heartbeat-age | test_hook_python_isolation compared the session_lock heartbeat age in whole seconds, so a run stalled past 1 s under load reported a false BYPASS of session_lock.sh | devkit-tests | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-red-proof-runner-under-tests-read-as-test | red_proof read a production runner under tests/ as a test, so the 09/10 audit rows could not be proven | devkit-gate | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-review-gate-ocr-scope | review_gate OCR requirement: --from without --to failed, one report cleared committed+uncommitted code, ranged flag read from the whole command | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-session-lock-let-cp-mv-rm-tee-sed-i-touc | session_lock let cp/mv/rm/tee/sed -i/touch into a held checkout through, and blocked reads naming the gate folder | devkit-hooks | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-shell-writes-env-split-escapes | shell_writes read env -S lines with shlex only, so the env escapes \_ (word separator) and \c (end of line) were misread: a write slipped through or a false block | devkit-hooks | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-shell-writes-env-split-sq-escape | shell_writes dropped an env -S line that shlex cannot parse (an escaped quote inside single quotes, which env honours), so its write was never judged | devkit-hooks | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-shell-writes-env-split-string | shell_writes skipped the command line of env -S / --split-string as an option value, so its writes were never judged | devkit-hooks | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-shell-writes-git-c-tilde | shell_writes did not expand ~ in the -C directory of a repository write, so worktree_guard missed a commit into main and blocked one into the worktree | devkit-hooks | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-testsourceset-lock-fifo-hang | testsourceset_gate hung on a FIFO planted at test_run.lock after its FIFO sweep (exec 9>> waits for a reader) | devkit-hooks | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-worktree-reflog-gone-folder | worktree inventory: a commit only the HEAD reflog names passes once the worktree folder is deleted (reflog read only while the folder exists) | devkit-worktree | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261014-worktree-secret-carry | git-ignored secret files made only in a worktree (keystore, key.properties) were deleted with it by finish/automerge/gc | devkit-worktree | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261015-android-rules-reach | android rules: selection-size and wiring-pin sections unreachable from the prompts that need them; PII half-rule in an on-demand block; ambiguous bucket spec | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261015-churn-guard-p6 | churn_guard untracked-edit warning starts repo-owned code, repeats process spawns on re-edit, walks huge payloads | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261015-generic-traps-id | android generic-traps test hard-codes the promoted instinct id and exports a DEVKIT_ROOT agent-kit overwrites | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261015-generic-traps-round2 | android generic-traps test: stale comment, literal id 908 coupled to the real file, promote exit code unchecked in section C | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261015-lens-pin | state-matrix lens pin could not fail (token anywhere in the file) and the kit lens named document-viewer axes | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261015-nightly-idle-holder | nightly named run ignores an idle session that holds the checkout | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261015-nightly-round2 | nightly named run: unreadable git dir and trunk-mode main went ahead, one repo ran twice under two letter cases, ~user raised | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261015-nightly-run-paths | nightly run accepts an empty path, runs one repo twice and passes a non-project folder | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261015-rule-titles-noise | android rules section titles stuffed with common words pointed ordinary prompts at section 12 or 16 | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261015-wiring-pin-detect | wiring_pin scan: pin name per View only, View-only test silences, same-file object ignored, data class taken for a View, comment counted as a call, empty-bodied pin, unrunnable verify hint | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261015-wiring-pin-round2 | wiring_pin verify misreads an inner trailing comma, counts a raw-string decoy, accepts a string-literal mention as a call | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261015-wiring-pin-scan | wiring_pin scan skips non-ASCII paths, hangs on a FIFO, tracebacks on a Latin-1 byte, flags renamed files as new | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261015-wiring-pin-verify | wiring_pin verify says holds for a wrapped or unreadable assertion, a comment-only call, an empty pin, a path outside root | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261016-proof-gate-recursion-fail-open | proof_gate: a deeply nested receipt or state file crashes the hook with RecursionError and XONG passes (python exit 1 becomes wrapper exit 0) | devkit-gate | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-VACUITY-SINCE-BASE | gate: vacuity revert uses HEAD under --since, so committed fixes look vacuous | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-WT-1013 | worktree copies keep the macOS uchg flag so remove cannot delete them and leaves an unregistered orphan folder | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | REG-DK-ALL-01 | DevKit tests that name a changed file (code, templates, rules) + repo consistency; the full suite exceeds the 900 s gate limit | devkit-all | sửa code/test rồi chạy lại — xem log |
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
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-AUTO-ANTIGRAVITY-PM-MCP-01 | antigravity-pm-mcp: package.json test script | mcp-servers/antigravity-pm-mcp | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-AUTO-CC-SWITCHER-MCP-01 | cc-switcher-mcp: package.json test script | mcp-servers/cc-switcher-mcp | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-AUTO-PLAY-STORE-MCP-01 | play-store-mcp: pytest | mcp-servers/play-store-mcp | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-COST-01 | token cost tracker counts each message id once and prices the longest model key | devkit-token-cost | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-GATE-01 | post-fix gate | devkit-gate | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-GATE-02 | proof gate (tree_fp) | devkit-gate | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-HEALTH-01 | health | devkit-health | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-HOOK-01 | hook contract | devkit-hooks | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-HOOK-02 | proof gate | devkit-hooks | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-SANDBOX-01 | worktree sandbox cleanup keeps unmerged work unless --force | devkit-worktree-sandbox | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-SESSION-01 | session lock + multi-session gate verdict (own session is never counted as another) | devkit-session-lock | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-GITHUB-READ-01 | super-board github-read helper | super-board-runner | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-MERGE-GATE-STALE-01 | merge gate says stale only when the branch is behind base | super-board-merge-gate | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-MERGE-LOAD-WAIT-01 | merge gate waits (bounded, inside the lock before the base is pinned, lock stamp refreshed) for the machine load to drop, then verifies anyway | super-board-merge-gate-load-wait | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-MERGE-POLICY-NL-01 | merge-policy sees always_human keywords after VT/FF/CR/NEL/U+2028, in ++ lines and across odd whitespace | super-board-diff-policy | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-NEEDS-DEVICE-01 | runner, planner and status hold needs-device QA cards while no real device is online (emulator, denylist, no adb) | super-board-needs-device | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-NEEDS-YOU-01 | needs-you mark is idempotent, migrates human-gated and carries no machine line | super-board-needs-you | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-NEEDS-YOU-SKIP-01 | runner, planner and status leave Ready cards that wait for a person (needs-you / human-gated) to the person | super-board-needs-you-skip | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-POST-MERGE-CLEAN-01 | post-merge clean and --sweep remove merged lane worktrees, keep work, one sweep at a time, salvage leaves no junk | super-board-post-merge-clean | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-PREFLIGHT-TOO-BIG-01 | preflight holds too-big cards before a builder pass, proceeds on normal ones | super-board-preflight | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RUN-STOP-MTIME-01 | runner reads the stop marker mtime on GNU and BSD stat | super-board-run-stop-mark-mtime | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RUN-SWEEP-TICK-01 | runner starts the post-merge sweep at startup and on every tick (before cap-reached), throttled, in the background | super-board-run-sweep-wiring | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RUNNER-LANES-01 | super-board runner lanes | super-board-runner | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RUNNER-WATCHDOG-01 | super-board runner survives a killed sleep; durable stop marker; launchd watchdog never restarts a stopped board | super-board-runner-watchdog | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-SCRATCH-CONFIG-01 | merge gate scratch tree gets ignored local config, build inputs and the ignored hooks settings registers | super-board-scratch-config | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-SETUP-BIN-01 | setup BIN lists every super-board script the runner, merge gate and skills call | super-board-setup-bin-list | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-UPSTREAM-66-67-01 | github-read keeps odd-newline diffs byte-exact without halting; approval links body issues off the default base | super-board-diff-policy | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-WATCHDOG-PATHS-01 | watchdog compares .state paths on physical paths and takes back a stale check lock on GNU and BSD stat | super-board-watchdog-path-sanitize | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-WB-CONFIG-01 | agent-kit health: every registered hook exists, imports resolve, context in sync | workbench-agent-config | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |
| 🐞 chưa sửa | BUG-20261012-test-chap-chon-flaky-reg-dk-session-01 | Test chập chờn (flaky): REG-DK-SESSION-01 | devkit-session-lock | sửa theo ĐỎ→XANH rồi `agent-kit bugs link` |
| 🐞 chưa sửa | BUG-20261013-test-chap-chon-flaky-reg-dk-all-01 | Test chập chờn (flaky): REG-DK-ALL-01 | devkit-all | sửa theo ĐỎ→XANH rồi `agent-kit bugs link` |
| ⚠️ có test, gate không chạy | BUG-20261013-bug-capture-copied-a-pasted-secret | Bug capture copied an API key pasted in a prompt into regression_status.json and CHECKLIST.md (title and id unredacted) | checklist | test có nhưng gate không chạy — đưa vào ma trận hoặc link suite của ma trận |
| ⚠️ có test, gate không chạy | BUG-20261013-regression-gate-held-skip-ignored-writers | regression_gate skipped the Stop for a payload without session_id or with DEVKIT_ALLOW_SHARED_CHECKOUT=1 while another session held the lock | gates | test có nhưng gate không chạy — đưa vào ma trận hoặc link suite của ma trận |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/agent-office/tests/approval_test.js | mcp-servers/agent-office/tests/approval_test.js | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/agent-office/tests/pathing_test.js | mcp-servers/agent-office/tests/pathing_test.js | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/agent-office/tests/present_pose_test.js | mcp-servers/agent-office/tests/present_pose_test.js | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/agent-office/tests/repo_label_test.js | mcp-servers/agent-office/tests/repo_label_test.js | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |

## 🧩 Phân hệ

### agent-office-agent-message — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-AGENT-OFFICE-INBOX-02 | agent-office: hook hộp thư lệnh (rỗng, có lệnh, sai session, file hỏng, subagent, thiếu nonce, song song) và POST /api/agent-message (rate limit, tunnel cần mã, resume bị từ chối khi phiên còn chạy hoặc thẻ còn worker) | chưa chạy | cd mcp-servers/agent-office && python3 -m unittest tests.test_inbox_hook tests.test_agent_message |
| ⏳ chưa chạy | REG-SB-AGENT-OFFICE-INBOX-01 | runner: có bản cài ~/.agent-office/app/inbox_hook.py thì worker claude mang --session-id, --settings (hook PostToolUse hộp thư) và system prompt có nonce, ghi session id vào log; không có hoặc hook lỗi thì lệnh bật như cũ; agy/grok không đổi | chưa chạy | bash tests/super-board/test_runner_agent_office_inbox.sh |

### capacity — 0/9 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-CAPACITY-CODEX-WAVE-01 | codex-wave: số lane Codex = min(max_workers, capacity build_workers); max_workers 0 lấy capacity; capacity vắng/hỏng/rác thì công thức cũ | chưa chạy | bash tests/super-board/test_codex_wave_workers.sh |
| ⏳ chưa chạy | REG-CAPACITY-MERGE-HOLD-01 | merge gate: config thiếu merge_load_max thì chờ theo capacity hold_load (12 lõi: 96, biên 95/96), capacity vắng thì cùng công thức 8 × lõi (lệnh trùng REG-SB-MERGE-LOAD-WAIT-01) | chưa chạy | bash tests/super-board/test_merge_gate_load_wait.sh |
| ⏳ chưa chạy | REG-CAPACITY-OFFICE-01 | agent-office dashboard: hiển thị ngưỡng tải hold_load từ capacity, capacity hỏng không làm sập dashboard | chưa chạy | cd mcp-servers/agent-office && python3 -m unittest tests.test_dashboard_stats |
| ⏳ chưa chạy | REG-CAPACITY-RUNNER-01 | super-board-run resolve_build_*: config vắng thì build_workers và build_load_max (busy_load) lấy từ capacity, capacity vắng thì số cũ (lệnh trùng REG-SB-BUILD-WORKERS-01: gate gộp, không chạy hai lần) | chưa chạy | bash tests/super-board/test_runner_build_workers.sh |
| ⏳ chưa chạy | REG-CAPACITY-RUNNER-02 | super-board-run resolve_lane_workers: config vắng thì lane_workers từ capacity, capacity vắng thì 1 (lệnh trùng REG-SB-LANE-WORKERS-01) | chưa chạy | bash tests/super-board/test_runner_lane_workers.sh |
| ⏳ chưa chạy | REG-CAPACITY-RUNNER-03 | super-board-run resolve_gate_max: config vắng thì gate_max từ capacity (4 lõi: 2), capacity vắng thì 6 (lệnh trùng REG-SB-WIP-LIMIT-01) | chưa chạy | bash tests/super-board/test_runner_wip_limit.sh |
| ⏳ chưa chạy | REG-CAPACITY-SLOTS-01 | heavy_slot CLI / wrapper super-board: ngưỡng tải mặc định là capacity hold_load (lệnh trùng REG-SB-HEAVY-SLOT-01) | chưa chạy | bash tests/super-board/test_heavy_slot.sh |
| ⏳ chưa chạy | REG-CAPACITY-SLOTS-02 | test super-board không xếp hàng sau slot thật của máy khi ngưỡng tải đến từ capacity (lệnh trùng REG-SB-TEST-SLOT-ISO-01) | chưa chạy | bash tests/super-board/test_tests_skip_machine_slots.sh |
| ⏳ chưa chạy | REG-CAPACITY-SLOTS-03 | super_board_all: dòng khởi động in ngưỡng hold_load của capacity, nút DEVKIT_CAPACITY không lái test (lệnh trùng REG-SB-NOTIFY-SLOTS-01) | chưa chạy | python3 tests/super-board/test_notify.py && python3 tests/super-board/test_super_board_all_slots.py && bash tests/super-board/test_runner_claim_loop.sh |

### devkit-all — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ❌ FAIL | REG-DK-ALL-01 | DevKit tests that name a changed file (code, templates, rules) + repo consistency; the full suite exceeds the 900 s gate limit | 2026-10-19 23:53:58 · 165.78s · exit 1 · 799a29b+dirty · [log](evidence/REG-DK-ALL-01/20261019-235358.log) | bash universal-agent-devkit/tests/run_impacted.sh |

### devkit-gate — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-GATE-01 | post-fix gate | 2026-10-19 23:50:21 · 202.37s · exit 0 · 799a29b+dirty · [log](evidence/REG-DK-GATE-01/20261019-234753.log) | bash universal-agent-devkit/tests/gates/test_postfix_gate.sh |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-GATE-02 | proof gate (tree_fp) | 2026-10-19 23:50:21 · 30.59s · exit 0 · 799a29b+dirty · [log](evidence/REG-DK-GATE-02/20261019-234501.log) | bash universal-agent-devkit/tests/gates/test_proof_gate.sh |

### devkit-guard-heredoc-text — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GUARD-HEREDOC-TEXT-01 | chữ rm -rf / git nằm trong heredoc là dữ liệu: hardware_safety_gate và worktree_guard không chặn nhầm, rm -rf / và ghi vào main thật vẫn bị chặn (#299 b, c) | chưa chạy | bash universal-agent-devkit/tests/gates/test_guard_heredoc_text_not_command.sh |

### devkit-guard-kill-by-name — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GUARD-KILL-BY-NAME-01 | git guard chặn pkill / killall / pgrep -f (kill theo tên trúng mọi board); kill <PID>, pgrep không -f và chữ pkill trong echo/grep/commit -m vẫn qua (#144) | chưa chạy | bash universal-agent-devkit/tests/gates/test_guard_kill_by_name.sh |

### devkit-health — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-HEALTH-01 | health | 2026-10-10 10:21:01 · 35.19s · exit 0 · 6f1734f+dirty · [log](evidence/REG-DK-HEALTH-01/20261010-101929.log) | bash universal-agent-devkit/tests/installer/test_agent_health.sh |

### devkit-heavy-slot-cap — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-HEAVY-CAP-01 | trần 3 suite nặng (cpu/gradle/xcode) cùng lúc: hết slot thì xếp hàng chờ không lỗi, hết ngân sách vẫn chạy kèm ghi chú, suite nhẹ/lồng không bị đếm, slot nặng không làm held | chưa chạy | bash universal-agent-devkit/tests/gates/test_heavy_slot_cap.sh |

### devkit-hooks — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-HOOK-01 | hook contract | 2026-10-19 23:53:58 · 57.51s · exit 0 · 799a29b+dirty · [log](evidence/REG-DK-HOOK-01/20261019-235210.log) | bash universal-agent-devkit/hooks/tests/hook_contract_test.sh |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-HOOK-02 | proof gate | 2026-10-19 23:53:58 · 21.86s · exit 0 · 799a29b+dirty · [log](evidence/REG-DK-HOOK-02/20261019-235134.log) | bash universal-agent-devkit/tests/gates/test_proof_gate.sh |

### devkit-matrix-merge-driver — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-MATRIX-MERGE-01 | merge driver ma trận hồi quy: hai nhánh cùng nối rule khác nhau vào cuối thì gộp không conflict và gate vẫn tin ma trận chỉ-thêm; cùng id khác nội dung thì lỗi rõ; sửa rule cũ vẫn conflict; githooks install cài driver | chưa chạy | bash universal-agent-devkit/tests/gates/test_matrix_merge_driver.sh |

### devkit-multi-session-gate-env — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-SESSION-ENV-01 | test_multi_session_gate + test_gate_stop_reuse_race xanh khi id phiên của máy thật (CLAUDE_CODE_SESSION_ID, DEVKIT_SESSION_ID) rò vào môi trường (#240) | chưa chạy | bash universal-agent-devkit/tests/gates/test_multi_session_gate_session_env.sh |

### devkit-sentinel-merge-env — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-SENTINEL-MERGE-ENV-01 | test_gate_sentinel.sh xanh khi DEVKIT_SLOT_PRIORITY=merge / DEVKIT_SLOT_LOAD_WAIT_S=0 rò từ merge gate vào verify (#167) | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_sentinel_merge_env.sh |

### devkit-session-lock — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-SESSION-01 | session lock + multi-session gate verdict (own session is never counted as another) | 2026-10-19 23:50:21 · 29.84s · exit 0 · 799a29b+dirty · [log](evidence/REG-DK-SESSION-01/20261019-234500.log) | bash universal-agent-devkit/tests/context_memory/test_session_lock.sh && bash universal-agent-devkit/tests/gates/test_multi_session_gate.sh |

### devkit-settings-read-deny-apk — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-SETTINGS-READ-DENY-APK-01 | luật deny Read của settings không chặn build/outputs và *.apk (worker QA liệt kê, cài APK debug), vẫn chặn build/intermediates, build/tmp, *.aab, *.hprof | chưa chạy | bash universal-agent-devkit/tests/verification/test_settings_template_read_deny.sh |

### devkit-slot-classes — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-SLOT-CLASSES-01 | quyền chạy theo tải máy của từng suite (P1b): bỏ 2 slot engine; tải cao thì chờ rồi vẫn chạy, không UNTESTED; chờ tải không ăn vào thời gian chờ khoá; khoá Unity (độc quyền) vẫn chặn, không còn khoá thiết bị; bash -lc nhận ra Unity; hàng đợi ưu tiên + SJF; suite STALE bị SLOT không lọt PASS | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_slot_classes.sh |

### devkit-suite-cache — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-SUITE-CACHE-01 | cache PASS theo khoá nội dung từng suite (cached-full): chỉ suite có input đổi chạy lại; khoá chính xác chỉ cho suite thêm vào, suite được chọn theo khoá cả cây; FAIL dính khoá, không-PASS vô hiệu PASS cũ; PASS theo khoá chính xác không vào biên nhận / DEVKIT_GATE_DONE; gộp lượt trùng khoá; suite tự sửa input không được ghi | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_suite_cache.sh |

### devkit-suite-cache-sentinel — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-SENTINEL-01 | sentinel: lần chạy thật > 24 h thì --full không dùng khoá (không ở merge gate), suite quá giờ không đóng mốc; cache sai thì học input thiếu hoặc cách ly flaky; run_one/nightly ghi cùng sổ khoá | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_sentinel.sh |

### devkit-token-cost — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-COST-01 | token cost tracker counts each message id once and prices the longest model key | 2026-10-02 16:10:23 · 0.29s · exit 0 · cf9ef39+dirty · [log](evidence/REG-DK-COST-01/20261002-160414.log) | bash universal-agent-devkit/tests/context_memory/test_token_cost_tracker.sh |

### devkit-verification-py — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-VERIFY-PY-01 | unity compile skip when editmode/playmode runs + proof-capture run-before under device lock | chưa chạy | python3 universal-agent-devkit/tests/verification/test_unity_compile_skip.py && python3 universal-agent-devkit/tests/verification/test_proof_run_before.py |

### devkit-worktree-sandbox — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-SANDBOX-01 | worktree sandbox cleanup keeps unmerged work unless --force | 2026-10-19 23:50:21 · 55.50s · exit 0 · 799a29b+dirty · [log](evidence/REG-DK-SANDBOX-01/20261019-234526.log) | bash universal-agent-devkit/tests/worktree_git/test_worktree_sandbox.sh |

### kit-merge-tree-no-leak — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-MERGE-TREE-NOLEAK-01 | merge-tree dò bị kill giữa chừng không để .merge_file_* ở cây làm việc (cwd tạm), kết luận 'đã tích hợp' không đổi khi driver chạy kịp (#309) | chưa chạy | bash universal-agent-devkit/tests/worktree_git/test_worktree_merge_tree_no_leak.sh |

### mcp-servers/agent-office — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-AGENT-OFFICE-01 | agent-office: unittest (server, redact, host check) và tìm đường A* của người đi trong xưởng (node) | chưa chạy | cd mcp-servers/agent-office && python3 -m unittest discover -s tests |

### mcp-servers/agent-office/blender — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-AGENT-OFFICE-02 | agent-office: bộ nội thất office.glb dựng bằng Blender còn đủ khối có tên (Desk, Chair, Monitor/Screen có UV, Shelf...) và đủ nhỏ | chưa chạy | cd mcp-servers/agent-office && python3 -m unittest tests.test_office_glb |

### mcp-servers/antigravity-pm-mcp — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-AUTO-ANTIGRAVITY-PM-MCP-01 | antigravity-pm-mcp: package.json test script | 2026-10-19 17:05:39 · 64.66s · exit 0 · 9c46389+dirty · [log](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261019-170227.log) | cd mcp-servers/antigravity-pm-mcp && npm test |

### mcp-servers/cc-switcher-mcp — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-AUTO-CC-SWITCHER-MCP-01 | cc-switcher-mcp: package.json test script | 2026-10-19 23:50:21 · 0.37s · exit 0 · 799a29b+dirty · [log](evidence/REG-AUTO-CC-SWITCHER-MCP-01/20261019-234837.log) | cd mcp-servers/cc-switcher-mcp && npm test |

### mcp-servers/play-store-mcp — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-AUTO-PLAY-STORE-MCP-01 | play-store-mcp: pytest | 2026-10-02 20:00:40 · 4.83s · exit 0 · 4d568d9+dirty · [log](evidence/REG-AUTO-PLAY-STORE-MCP-01/20261002-195614.log) | cd mcp-servers/play-store-mcp && uv run --frozen --extra dev pytest -q |

### post-fix-gate-tree-mode — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-GATE-TREE-01 | post-fix-gate --tree HEAD: cây sạch chạy đủ suite và exit 0, tin ma trận đã commit, từ chối cây bẩn, biên nhận theo cây cho proof_gate (#307) | chưa chạy | bash universal-agent-devkit/tests/gates/test_gate_tree_mode.sh |

### super-board-blocked-by-open-only — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-BLOCKED-BY-OPEN-ONLY-01 | dòng blocked-by: chỉ ghi issue còn mở; số đã đóng bị bỏ kèm lý do, không còn số mở thì `-`, không đọc được trạng thái thì exit 79 (#253) | chưa chạy | python3 tests/super-board/test_blocked_by_open_only.py |

### super-board-board-heartbeat — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-BOARD-HEARTBEAT-01 | GitHub Actions cron marks a 🟢/🟠 board ⚫ when the watchdog's 'cập nhật HH:MM dd/MM' is stale; leaves ⏸️/⚪/⚫ and foreign descriptions alone | chưa chạy | bash tests/super-board/test_board_heartbeat.sh |

### super-board-build-workers — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-BUILD-WORKERS-01 | lane build chạy nhiều worker theo tải máy: trần build_workers, tối đa một worker mới mỗi tick, tải >= build_load_max hoặc không đọc được thì giữ, quét mồ côi/zombie/dừng khẩn nhận ra N worker | chưa chạy | bash tests/super-board/test_runner_build_workers.sh |

### super-board-card-items-retry — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-CARD-ITEMS-RETRY-01 | card.sh items đọc lại 1 lần khi số item lệch totalCount (không chết runner); lệch cả hai lần vẫn exit 69; stop.sh ghi marker trước kill (#256) | chưa chạy | bash tests/super-board/test_card_items_count_retry.sh |

### super-board-diff-policy — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-MERGE-POLICY-NL-01 | merge-policy sees always_human keywords after VT/FF/CR/NEL/U+2028, in ++ lines and across odd whitespace | 2026-10-19 17:05:39 · 1.88s · exit 0 · 9c46389+dirty · [log](evidence/REG-SB-MERGE-POLICY-NL-01/20261019-170442.log) | bash tests/super-board/test_merge_policy_odd_newlines.sh |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-UPSTREAM-66-67-01 | github-read keeps odd-newline diffs byte-exact without halting; approval links body issues off the default base | 2026-10-19 17:05:39 · 0.53s · exit 0 · 9c46389+dirty · [log](evidence/REG-SB-UPSTREAM-66-67-01/20261019-170443.log) | bash tests/super-board/test_upstream_66_67.sh |

### super-board-gh-write-once-marker — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-WRITE-MARKER-01 | gh_write_once: comment ghi chưa rõ kết quả mang marker duy nhất cho mỗi lần, comment cố định lặp không làm reconcile báo đã áp dụng nhầm | chưa chạy | bash tests/super-board/test_gh_write_once_marker.sh |

### super-board-github-read-foreign-halt — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-GITHUB-READ-FOREIGN-HALT-01 | github-read: a failed read of ANOTHER repository (test fixture o/r from a worktree) never writes the real board halt; a read of the checkout's own repository, or one naming no repository, still halts | chưa chạy | bash tests/super-board/test_github_read_foreign_halt.sh |

### super-board-github-read-reconcile — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-GITHUB-RECONCILE-01 | github-read --halt --verify / --reconcile: đọc lại lần ghi chưa rõ kết quả; đã áp dụng thì lưu trữ halt, chưa áp dụng hay không kiểm chứng được thì giữ halt | chưa chạy | bash tests/super-board/test_github_read_reconcile.sh |

### super-board-heavy-slot — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-HEAVY-SLOT-01 | heavy slot theo tải máy (P1b): CLI/wrapper super-board chạy ngay khi tải < DEVKIT_SLOT_LOAD_MAX, chờ rồi vẫn chạy khi tải cao, --nonblock không chạy khi tải cao, DEVKIT_SLOT_LOAD_WAIT_S=0 không chờ, suite Unity lồng trong CLI vẫn xin khoá Unity; --force-full với suite nhẹ không chờ | chưa chạy | bash tests/super-board/test_heavy_slot.sh |

### super-board-lane-workers — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-LANE-WORKERS-01 | lane QA và Review chạy nhiều worker (qa_workers / review_workers, mặc định 1): một worker mới mỗi tick, cổng tải build_load_max, zombie/reap/dừng khẩn/nhận lại nhận ra cả worker thêm, worker thêm không bị trần max_workers chặn | chưa chạy | bash tests/super-board/test_runner_lane_workers.sh |

### super-board-merge-call-failed — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-CALL-FAILED-01 | merge gate: gh pr merge lỗi mà PR vẫn OPEN đúng head → exit 4, không halt board; đọc lại lỗi/CLOSED vẫn halt; MERGED muộn exit 0; head đổi exit 6 | chưa chạy | bash tests/super-board/test_merge_gate_merge_call_failed.sh |

### super-board-merge-gate — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-MERGE-GATE-STALE-01 | merge gate says stale only when the branch is behind base | 2026-10-19 23:50:21 · 7.47s · exit 0 · 799a29b+dirty · [log](evidence/REG-SB-MERGE-GATE-STALE-01/20261019-234812.log) | bash tests/super-board/test_merge_gate_stale_message.sh |

### super-board-merge-gate-dead-holder — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-DEAD-HOLDER-01 | merge gate: khoá merge có pid đã chết (gate bị giết trước trap EXIT) được reap ngay, không chờ stale-after; pid còn sống và khoá không có pid vẫn chờ như cũ (exit 4) | chưa chạy | bash tests/super-board/test_merge_gate_dead_holder.sh |

### super-board-merge-gate-load-wait — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-MERGE-LOAD-WAIT-01 | merge gate waits (bounded, inside the lock before the base is pinned, lock stamp refreshed) for the machine load to drop, then verifies anyway | 2026-10-19 23:50:21 · 36.23s · exit 0 · 799a29b+dirty · [log](evidence/REG-SB-MERGE-LOAD-WAIT-01/20261019-235021.log) | bash tests/super-board/test_merge_gate_load_wait.sh |

### super-board-merge-gate-timeout-retry — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-TIMEOUT-RETRY-01 | merge gate retries a post-fix-gate verify once only when every red suite is TIMEOUT (REJECT exit 1, static checks passed); a real FAIL, UNTESTED or static finding is not retried; verify exit 124 still retried once | chưa chạy | bash tests/super-board/test_merge_gate_timeout_retry.sh |

### super-board-merge-gate-verified-tree — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-GATE-TREE-01 | merge gate: cây gộp đã verify xanh với cùng bộ lệnh thì lượt gate sau bỏ verify; base đổi, lệnh đổi hoặc verify đỏ thì verify đủ (#226 gap 7) | chưa chạy | bash tests/super-board/test_merge_gate_verified_tree.sh |

### super-board-merge-train — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-MERGE-TRAIN-01 | merge train: 3 PR sẵn sàng thì verify đúng một lần và cả 3 merge; một PR đỏ được chia đôi tìm ra (exit 11) và hai PR còn lại vẫn merge; một PR chạy như gate thường (#110) | chưa chạy | bash tests/super-board/test_merge_train.sh |

### super-board-needs-device — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-NEEDS-DEVICE-01 | runner, planner and status hold needs-device QA cards while no real device is online (emulator, denylist, no adb) | 2026-10-19 23:50:21 · 1.87s · exit 0 · 799a29b+dirty · [log](evidence/REG-SB-NEEDS-DEVICE-01/20261019-234944.log) | bash tests/super-board/test_needs_device_skip.sh |

### super-board-needs-you — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-NEEDS-YOU-01 | needs-you mark is idempotent, migrates human-gated and carries no machine line | 2026-10-19 17:05:39 · 4.64s · exit 0 · 9c46389+dirty · [log](evidence/REG-SB-NEEDS-YOU-01/20261019-170448.log) | bash tests/super-board/test_needs_you.sh |

### super-board-needs-you-skip — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-NEEDS-YOU-SKIP-01 | runner, planner and status leave Ready cards that wait for a person (needs-you / human-gated) to the person | 2026-10-19 23:50:21 · 0.90s · exit 0 · 799a29b+dirty · [log](evidence/REG-SB-NEEDS-YOU-SKIP-01/20261019-234838.log) | bash tests/super-board/test_needs_you_skip.sh |

### super-board-notify-and-slots — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-NOTIFY-SLOTS-01 | notify blocks test/lib/runaway Telegram spam; super_board_all covers all 6 repos; monitor scans worktree transcripts; claim loop caps total early deaths | chưa chạy | python3 tests/super-board/test_notify.py && python3 tests/super-board/test_super_board_all_slots.py && bash tests/super-board/test_runner_claim_loop.sh |

### super-board-post-merge-clean — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-POST-MERGE-CLEAN-01 | post-merge clean and --sweep remove merged lane worktrees, keep work, one sweep at a time, salvage leaves no junk | 2026-10-19 23:50:21 · 62.39s · exit 0 · 799a29b+dirty · [log](evidence/REG-SB-POST-MERGE-CLEAN-01/20261019-234941.log) | bash tests/super-board/test_post_merge_clean.sh && bash tests/super-board/test_post_merge_squash_leftovers.sh && bash tests/super-board/test_post_merge_sweep_wiring.sh |

### super-board-preflight — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-PREFLIGHT-TOO-BIG-01 | preflight holds too-big cards before a builder pass, proceeds on normal ones | 2026-10-19 17:05:39 · 2.23s · exit 0 · 9c46389+dirty · [log](evidence/REG-SB-PREFLIGHT-TOO-BIG-01/20261019-170418.log) | bash tests/super-board/test_preflight_too_big.sh |

### super-board-preflight-numbered-ac — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-PREFLIGHT-NUMBERED-AC-01 | AC đánh số 1) / 1. được nhận ở preflight (không hold unclear) và ở luật kéo Backlog; AC chỉ văn xuôi vẫn bị chặn (#283) | chưa chạy | bash tests/super-board/test_preflight_numbered_ac.sh |

### super-board-preflight-stale-overlap — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-PREFLIGHT-STALE-OVERLAP-01 | preflight câu 3: PR của thẻ Backlog/Blocked không chặn; PR của thẻ đang chạy vẫn chặn; thẻ có PR riêng không bị sequence lại; không --inflight giữ hành vi cũ (#280) | chưa chạy | bash tests/super-board/test_preflight_overlap_stale.sh |

### super-board-red-on-base — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-RED-ON-BASE-01 | merge gate: suite đỏ cả trên origin/base không REJECT PR, mở thẻ riêng; suite do PR làm đỏ vẫn exit 11 (#251) | chưa chạy | bash tests/super-board/test_merge_gate_red_on_base.sh |
| ⏳ chưa chạy | REG-SB-VERIFY-CMD-01 | QA in đúng lệnh verify của merge gate (cùng hàm chèn --diff/--force-full) (#251) | chưa chạy | bash tests/super-board/test_verify_cmd_same_as_gate.sh |

### super-board-review-approved-head — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-REVIEW-APPROVED-HEAD-01 | runner: thẻ Review đã duyệt đúng head (comment approved-head:<sha> của OWNER/MEMBER/COLLABORATOR) chỉ chạy merge-only với --expect-head, kể cả sau merge gate exit 4; head đổi, người ngoài duyệt hay đọc GitHub hỏng thì review đầy đủ (#227) | chưa chạy | bash tests/super-board/test_runner_review_approved_head.sh |

### super-board-review-merge-train — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-REVIEW-MERGE-TRAIN-01 | runner: từ 2 thẻ Review đã duyệt đúng head trở lên thì một worker chạy super-board-merge-train.sh --prs cho cả đợt (lock chung PID, không bị coi là zombie khi thẻ đầu đã Done); thẻ chưa duyệt, sai head, đã khoá hay SB_REVIEW_TRAIN=0 thì đường từng thẻ như cũ (#228) | chưa chạy | bash tests/super-board/test_runner_review_merge_train.sh |

### super-board-run-stop-mark-mtime — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RUN-STOP-MTIME-01 | runner reads the stop marker mtime on GNU and BSD stat | 2026-10-19 23:50:21 · 0.54s · exit 0 · 799a29b+dirty · [log](evidence/REG-SB-RUN-STOP-MTIME-01/20261019-234839.log) | bash tests/super-board/test_run_stop_mark_mtime.sh |

### super-board-run-sweep-wiring — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RUN-SWEEP-TICK-01 | runner starts the post-merge sweep at startup and on every tick (before cap-reached), throttled, in the background | 2026-10-19 23:50:21 · 0.68s · exit 0 · 799a29b+dirty · [log](evidence/REG-SB-RUN-SWEEP-TICK-01/20261019-234944.log) | bash tests/super-board/test_post_merge_sweep_wiring.sh |

### super-board-runner — 0/2 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-GITHUB-READ-01 | super-board github-read helper | 2026-10-19 23:50:21 · 3.08s · exit 0 · 799a29b+dirty · [log](evidence/REG-SB-GITHUB-READ-01/20261019-234756.log) | bash tests/super-board/test_github_read.sh |
| 💤 đã nghỉ (suite không còn trong ma trận) | REG-SB-MERGE-SYNC-01 | super-board merge gate: local base sync after merge (identical uncommitted copies K13, squash, work in progress) | 2026-10-19 19:33:10 · 67.26s · exit 0 · d775dd9+dirty · [log](evidence/REG-SB-MERGE-SYNC-01/20261019-193310.log) | bash tests/super-board/test_merge_gate_identical_sync.sh && bash tests/super-board/test_merge_gate_squash_sync.sh |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RUNNER-LANES-01 | super-board runner lanes | 2026-10-19 23:50:21 · 8.25s · exit 0 · 799a29b+dirty · [log](evidence/REG-SB-RUNNER-LANES-01/20261019-234804.log) | bash tests/super-board/test_runner_lanes.sh |

### super-board-runner-board-read-retry — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-RUNNER-READ-RETRY-01 | runner đọc lại board có backoff khi lần đọc hỏng tạm thời; hỏng hết lượt thì bỏ tick thay vì chết; halt 79 vẫn dừng; vòng chính chỉ đọc qua tick_fetch (#256) | chưa chạy | bash tests/super-board/test_runner_board_read_retry.sh |

### super-board-runner-noop-worker — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-RUNNER-NOOP-WORKER-01 | runner: worker qa/review thoát mà thẻ vẫn ở cột cũ và không comment mới thì tính no-op; 2 lần liên tiếp thì thẻ sang Blocked (📱 nếu log nhắc máy thật, còn lại ❓) kèm dòng cuối log, không giao lại; chuyển cột hoặc có comment thì không tính | chưa chạy | bash tests/super-board/test_runner_noop_worker.sh |

### super-board-runner-preflight-swept — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-RUNNER-PREFLIGHT-SWEPT-01 | runner chạy preflight trước khi nhận thẻ build (hold/sequence có blockedBy: không claim, thẻ sang Blocked kèm blocked-by; exit 79 dừng run) và sổ SWEPT_CARDS bền qua lần khởi động lại (#253) | chưa chạy | bash tests/super-board/test_runner_preflight_swept.sh |

### super-board-runner-ready-order — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-RUNNER-READY-ORDER-01 | runner giao thẻ Ready theo priority label, bug trước, số issue tăng dần; thẻ body nhắm repo khác → Blocked kèm block-template; thẻ có Fix trùng thẻ đang mở → comment một lần, không giao | chưa chạy | bash tests/super-board/test_runner_ready_order.sh |

### super-board-runner-reclaim-dead-build — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-RUNNER-RECLAIM-DEAD-BUILD-01 | runner trả thẻ Building có worker build chết giữa lượt chạy về lại Ready kèm sổ reclaims; quá trần trong cửa sổ thì chuyển sang Blocked có dòng blocked-by: - | chưa chạy | bash tests/super-board/test_runner_reclaim_dead_build.sh |

### super-board-runner-watchdog — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-RUNNER-WATCHDOG-01 | super-board runner survives a killed sleep; durable stop marker; launchd watchdog never restarts a stopped board | 2026-10-19 23:50:21 · 25.06s · exit 0 · 799a29b+dirty · [log](evidence/REG-SB-RUNNER-WATCHDOG-01/20261019-234837.log) | bash tests/super-board/test_runner_watchdog.sh |

### super-board-scratch-config — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-SCRATCH-CONFIG-01 | merge gate scratch tree gets ignored local config, build inputs and the ignored hooks settings registers | 2026-10-19 23:50:21 · 0.67s · exit 0 · 799a29b+dirty · [log](evidence/REG-SB-SCRATCH-CONFIG-01/20261019-234942.log) | bash tests/super-board/test_scratch_config.sh |

### super-board-self-reload — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-SELF-RELOAD-01 | runner rảnh tự nạp lại super-board-run.sh khi origin đổi: ff main rồi exec lại; main lệch origin / ff hỏng / sai cú pháp thì notify một lần, không restart mù; còn worker thì không đụng | chưa chạy | bash tests/super-board/test_runner_self_reload.sh |

### super-board-setup-bin-list — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-SETUP-BIN-01 | setup BIN lists every super-board script the runner, merge gate and skills call | 2026-10-19 17:05:39 · 0.15s · exit 0 · 9c46389+dirty · [log](evidence/REG-SB-SETUP-BIN-01/20261019-170449.log) | bash tests/super-board/test_setup_bin_list.sh |

### super-board-status-needs-you-column — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-STATUS-NEEDS-YOU-01 | status: option Needs You của Project vẽ thành ô riêng và vào nhóm Waiting on you; không có thẻ Needs You thì đầu ra không đổi | chưa chạy | bash tests/super-board/test_status_needs_you_column.sh |

### super-board-total-worker-cap — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-TOTAL-CAP-01 | một trần worker duy nhất: build+qa+review của mọi repo trên máy <= max_workers (5), đếm qua thư mục slot chung, PID chết tự trả slot; tải CPU, WIP, gate_max không còn chi phối | chưa chạy | bash tests/super-board/test_runner_total_cap.sh |

### super-board-waiting-label — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-WAITING-LABEL-01 | thẻ Blocked chỉ chờ thẻ khác mang nhãn '⏳ chờ thẻ khác' (planner pending, runner gắn/gỡ), thẻ 🙋 không có nhãn, status tách hai nhóm (#235) | chưa chạy | bash tests/super-board/test_waiting_label.sh |

### super-board-watchdog-lock-atomic — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-WATCHDOG-LOCK-ATOMIC-01 | 8 check cùng gặp khoá check cũ quá 120 s thì đúng một check giữ được khoá (không khởi động 2 runner) | chưa chạy | bash tests/super-board/test_watchdog_lock_atomic.sh |

### super-board-watchdog-path-sanitize — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-SB-WATCHDOG-PATHS-01 | watchdog compares .state paths on physical paths and takes back a stale check lock on GNU and BSD stat | 2026-10-19 17:05:39 · 1.42s · exit 0 · 9c46389+dirty · [log](evidence/REG-SB-WATCHDOG-PATHS-01/20261019-170450.log) | bash tests/super-board/test_watchdog_path_sanitize.sh && bash tests/super-board/test_watchdog_lock_mtime.sh |

### super-board-wave-needs-you-mark — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-WAVE-NEEDSYOU-01 | wave.js: prompt exit 7 và exit 8 của merge gate gọi super-board-needs-you.py mark với --next comment done (#106) | chưa chạy | bash tests/super-board/test_wave_needs_you_mark.sh |

### super-board-wip-limit — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-WIP-LIMIT-01 | runner giới hạn WIP (#252): không giao build khi QA+Review chờ >= build_wip_k × (qa_workers+review_workers); không giao build / worker QA-Review thêm khi số post-fix-gate đang chạy >= gate_max; log lý do; số gate không đếm được thì không chặn | chưa chạy | bash tests/super-board/test_runner_wip_limit.sh |

### test-heavy-slot-isolation — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-SB-TEST-SLOT-ISO-01 | tests never queue behind the machine's real heavy-verify slots | chưa chạy | bash tests/super-board/test_tests_skip_machine_slots.sh |

### workbench-agent-config — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-WB-CONFIG-01 | agent-kit health: every registered hook exists, imports resolve, context in sync | 2026-10-19 17:05:39 · 0.68s · exit 0 · 9c46389+dirty · [log](evidence/REG-WB-CONFIG-01/20261019-170403.log) | bash universal-agent-devkit/bin/agent-kit health -t . |

### worktree-discard-squash — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-DK-DISCARD-SQUASH-01 | worktree discard: chuỗi commit đã squash vào origin/<trunk> (main local chưa pull) + file xoá thì gỡ được kèm refs/devkit/discarded; còn commit trunk chưa có patch hoặc có file bị sửa thì vẫn từ chối | chưa chạy | bash universal-agent-devkit/tests/worktree_git/test_worktree_discard_squash.sh |

## 📒 Sổ tay bug (127)

| Trạng thái | Mã | Mô tả | Component | Test bảo vệ | Bằng chứng |
|---|---|---|---|---|---|
| ❌ FAIL | BUG-20260925-prompt-bao-bug-that-cung-se-khong-con-du | prompt báo bug thật cũng sẽ không còn được ghi nhận nữa -> là sao bug đúng ko fix đi phải tự động ghi nhận chứ | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_bug_capture.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20260925-prompt-bao-bug-that-cung-se-khong-con-du/20261009-185852.log) |
| ❌ FAIL | BUG-20260926-dev-kit-lam-tao-branch-push-lung-tung-kh | dev kit làm tạo branch, push lung tung không đồng bộ dẫn tới lệch code, vd geely ex2 hiện có 2 pull chưa pull về dẫn tớ… | - | REG-DK-ALL-01, REG-DK-HOOK-01, REG-DK-HOOK-02, universal-agent-devkit/hooks/tests/hook_contract_test.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20260928-audit-review-them-geely-ex2-hien-no-bao | audit, review thêm geely ex2 hiện nó báo tôi rất nhiều lỗi vậy có nghĩa là bộ devkit hoàn toàn chất lượng kém để thủng… | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_friction.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20260928-fix-luon-loi-git-guard-chan-grep-di-ngoa | fix luôn lỗi git guard chặn grep đi ngoài ra đã tối ưu token sử dụng cũng như thời gian chạy chưa ? Đề xuất các phương… | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_friction.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20260928-push-geely-va-fix-luon-loi-red-proof | push geely và fix luôn lỗi red_proof | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_red_proof.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20260928-push-geely-va-fix-luon-loi-red-proof/20261024-114055.log) |
| ❌ FAIL | BUG-20260928-san-check-luon-chat-luong-dev-kit-workfl | sẵn check luôn chất lượng dev kit workflow có bị lỗi gì ko fix luôn đi | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_friction.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20260929-audit-review-nguyen-nhan-tai-sao-cac-ses | audit, review nguyên nhân tại sao các sesion cài dev kit chạy rất chậm có lỗi gì hay ko? | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_regression_gate_hook.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20260929-audit-review-nguyen-nhan-tai-sao-cac-ses/20261024-114634.log) |
| ❌ FAIL | BUG-20261001-lam-luon-fix-bug-worktree-di | làm luôn fix bug worktree đi | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_worktree_merge_gate.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261001-lam-luon-fix-bug-worktree-di/20261009-182503.log) |
| ❌ FAIL | BUG-20261001-sua-luon-bug-init-xoa-mcp-server-di | sửa luôn bug init xoá MCP server đi | - | REG-DK-ALL-01, universal-agent-devkit/tests/installer/test_platform_rules.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261001-sua-luon-bug-init-xoa-mcp-server-di/20261024-145202.log) |
| ❌ FAIL | BUG-20261002-agent-kit-health-run-tests-scores-96-100 | agent-kit health --run-tests scores 96/100: agent-kit test runs ~90 test scripts one after another (~19 min), past the 900 s limit health allows | devkit-health | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_run_impacted.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261002-agent-kit-health-run-tests-scores-96-100/20261024-114737.log) |
| ❌ FAIL | BUG-20261002-chay-finagling-running-stop-hooks-8-9-27 | chạy Finagling… (running Stop hooks… 8/9 · 27m 24s · ↓ 46.3k tokens) quá lâu audit, review sửa lại đi Stop hooks… rất h… | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_regression_gate_hook.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261002-evidence-gate-foreign-xml-nonrunner | test_evidence_gate: a Bash that only names a foreign project (cd && git status) made its fresh XML count as this session's test evidence | devkit | REG-DK-ALL-01, REG-DK-HOOK-01, REG-DK-HOOK-02, universal-agent-devkit/hooks/tests/hook_contract_test.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261002-evidence-gate-foreign-xml-nonrunner/20261024-120020.log) |
| ❌ FAIL | BUG-20261002-gate-rejects-a-change-that-moves-a-test | Gate REJECTs a change that moves a test file the matrix names: it runs the base matrix, whose command names the removed path (exit 127), and flags the matrix edit for review | devkit-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_matrix_rename.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261002-gate-rejects-a-change-that-moves-a-test/20261009-172300.log) |
| ❌ FAIL | BUG-20261002-proof-gate-reinit-same-profile | proof gate: re-init rewriting the same backend profile counted as a profile switch and demanded a PNG | devkit | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_proof_gate.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261002-sessionstart-skips-the-checklist-block-a | SessionStart skips the checklist block and the background STALE re-run after the scripts/ regrouping (bin/ and stale_rerun.py paths) | devkit-hooks | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_stale.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261002-sessionstart-skips-the-checklist-block-a/20261009-173233.log) |
| ❌ FAIL | BUG-20261008-sua-4-loi-kit-phien-office-nho-di | sửa 4 lỗi kit phiên Office nhờ đi | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_session_lock_target_repo.sh (trong suite), universal-agent-devkit/tests/worktree_git/test_worktree_automerge.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261009-automerge-refusal-reason-lost | worktree automerge: a commit refused by the repo's pre-commit gate was reported with only the last 500 characters of the gate output, which is the passed-checks footer, never the finding: the worktree stayed unmerged and nobody could tell why (GeelyEx2 giao-tichhop-09-10, base-hoiquy-09-10) | devkit-worktree | REG-DK-ALL-01, universal-agent-devkit/tests/worktree_git/test_worktree_automerge_reason.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261009-automerge-refusal-reason-lost/20261009-192819.log) |
| ❌ FAIL | BUG-20261009-churn-guard-no-fast-path | churn_guard started python on every Edit although it can warn only when the transcript names the file at least N times | devkit-hooks | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_churn_guard_fast_path.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261009-comment-claim-docstring-trailing | comment_claim_guard: a claim inside a Python docstring or after code on the same line (# / //) passed while the same words in a full-line comment warn | devkit-hooks | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_comment_claim_docstring_trailing.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261009-comment-claim-docstring-trailing/20261024-120145.log) |
| ❌ FAIL | BUG-20261009-gate-js-describe-title-false-flag | post-fix-gate: the same it('title') in two different describe blocks flagged a pure append of a JS test as an edited test | devkit-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_js_describe_scope.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261009-gate-js-describe-title-false-flag/20261024-120741.log) |
| ❌ FAIL | BUG-20261009-gate-runner-no-errexit-append | post-fix-gate: any command appended to a shell test runner WITHOUT set -e counted as a pure append, though it decides the exit status over an earlier failure (user decision 2026-10-09) | devkit-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_runner_no_errexit.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261009-gate-runner-no-errexit-append/20261024-121235.log) |
| ❌ FAIL | BUG-20261009-git-guard-bash-c-subst-tee-shell | block-dangerous-git: bash -c "$(curl ...)" and a shell inside >(...) ran generated text that curl \| bash and bash <(...) already refuse | devkit-git-guard | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_git_guard_shell_subst.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261009-hardware-find-negated-or-unfiltered | hardware_safety_gate: find ! -name x -delete, -not, and an -o alternative without a filter counted as filtered, so the start point was never judged | devkit-hardware-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_hardware_find_not_or.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261009-hooks-log-dir-process-cwd | 7 hooks (bash_write_ledger, security_gate, proof_gate, regression_gate, test_evidence_gate, review_timing_guard, prompt_context) took the project from the PROCESS cwd when CLAUDE_PROJECT_DIR was unset and created .claude/audit-gate there (a run at / wrote /.claude) | devkit-hooks | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_hook_log_dir.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261009-hooks-log-dir-process-cwd/20261009-203143.log) |
| ❌ FAIL | BUG-20261009-merge-gate-held-vanished-worktree | worktree_merge_gate: a worktree removed by the last Stop's background merge while this Stop decided stayed in the hold list (flaky test_worktree_merge_gate_owner) | devkit-worktree | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_worktree_merge_gate_vanished.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261009-review-timing-guard-env-payload | review_timing_guard: the hook payload travelled in an environment variable, so an Edit of a big file (payload past the 1 MiB exec limit) made the shell fail with Argument list too long and the guard never ran | devkit-hooks | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_review_timing_guard_big_payload.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261009-review-timing-guard-env-payload/20261024-121246.log) |
| ❌ FAIL | BUG-20261009-run-impacted-recent-commits-in-sandbox | run_impacted.sh in a checkout with no upstream (every RED-proof sandbox) selected the tests of every commit of the last 6 hours: 25+ minutes per proof instead of the few tests of the reverted file | devkit-tests | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_run_impacted_since.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261009-scratch-cleanup-prune-could-delete-a-liv | scratch_cleanup: prune could delete a live idle session's dir and follow a slug swapped for a symlink (TOCTOU) | devkit-scratch-cleanup | REG-DK-ALL-01, universal-agent-devkit/tests/context_memory/test_scratch_cleanup.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261009-session-lock-a-cp-rc-copy-of-a-checkout | session_lock: a cp -Rc copy of a checkout carried the original's lock and was held by its live holder up to 600 s | devkit-session-lock | REG-DK-ALL-01, universal-agent-devkit/tests/context_memory/test_session_lock.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261009-session-lock-a-cp-rc-copy-of-a-checkout/20261024-121858.log) |
| ❌ FAIL | BUG-20261009-session-lock-an-idle-holder-turn-over-wa | session_lock: an idle holder (turn over, waiting at the prompt) kept the checkout 600 s, other sessions needed /exit | devkit-session-lock | REG-DK-ALL-01, universal-agent-devkit/tests/context_memory/test_session_lock.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261009-session-lock-case-only-path | session_lock: a path spelled with other letter case (APFS) fell outside the locked checkout, so the write took no lock and a live holder lost it | devkit-session-lock | REG-DK-ALL-01, universal-agent-devkit/tests/context_memory/test_session_lock.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261009-session-lock-case-only-path/20261024-122913.log) |
| ❌ FAIL | BUG-20261010-gate-swallows-a-failed-linter-import-and | gate swallows a failed linter import and switches the lint off silently | devkit-guards | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_linter_import_loud.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-gate-swallows-a-failed-linter-import-and/20261010-102355.log) |
| ❌ FAIL | BUG-20261010-gate-wants-a-regression-test-for-red-pro | gate wants a regression test for red-proof patch files | devkit-guards | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_redpatch_no_test.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-gate-wants-a-regression-test-for-red-pro/20261010-103756.log) |
| ❌ FAIL | BUG-20261010-guard-hooks-lose-the-command-that-follow | guard hooks lose the command that follows a comment or a hash inside a word | devkit-guards | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_guard_comment_not_swallowing.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-guard-hooks-lose-the-command-that-follow/20261010-101953.log) |
| ❌ FAIL | BUG-20261010-health-reports-100-while-a-tracked-symli | health reports 100 while a tracked symlink points at a missing target | devkit-guards | REG-DK-ALL-01, universal-agent-devkit/tests/installer/test_agent_health_broken_tracked_link.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-health-reports-100-while-a-tracked-symli/20261010-104501.log) |
| ❌ FAIL | BUG-20261010-matrix-accepts-one-suite-id-with-two-dif | matrix accepts one suite id with two different commands without a word | devkit-guards | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_matrix_duplicate_id.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-matrix-accepts-one-suite-id-with-two-dif/20261010-105445.log) |
| ❌ FAIL | BUG-20261010-proof-gate-blocks-a-push-turn-whose-4-it | proof_gate blocks a push turn whose 4-item report was already written right after the push | proof_gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_proof_gate_report_after_push.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-proof-gate-blocks-a-push-turn-whose-4-it/20261010-125933.log) |
| ❌ FAIL | BUG-20261010-red-proof-keeps-a-patch-of-any-size-in-a | red proof keeps a patch of any size in a tracked folder | devkit-guards | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_red_proof_patch_cap.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-red-proof-keeps-a-patch-of-any-size-in-a/20261024-145355.log) |
| ❌ FAIL | BUG-20261010-regression-gate-re-runs-every-suite-on-a | regression_gate re-runs every suite on a repeated FAIL when one suite cannot run here, ignores local config and age, and sessions erase each other's stored blocks | regression_gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_regression_gate_repeat_cache.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261010-session-lock-blocks-read-only-commands-s | session lock blocks read-only commands: stash list and grep naming the gate | devkit-guards | REG-DK-ALL-01, universal-agent-devkit/tests/context_memory/test_session_lock_readonly.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-session-lock-blocks-read-only-commands-s/20261010-102107.log) |
| ❌ FAIL | BUG-20261010-test-evidence-gate-rebuilds-the-shell-va | test_evidence_gate rebuilds the shell variable table of every earlier command for each command (quadratic, 25 s on a 58 MB transcript) | test_evidence_gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_evidence_gate_linear.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-test-evidence-gate-rebuilds-the-shell-va/20261010-183459.log) |
| ❌ FAIL | BUG-20261010-test-evidence-gate-treats-a-source-file | test_evidence_gate treats a source file written in a temp or scratchpad dir as the last code edit, so a green run goes stale (36% of 171 real blocks) | test_evidence_gate | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_evidence_scratch_edits.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-test-evidence-gate-treats-a-source-file/20261010-190713.log) |
| ❌ FAIL | BUG-20261010-testsourceset-gate-compiles-the-test-sou | testsourceset_gate compiles the test source sets on every unfinished (CHUA XONG) stop | testsourceset_gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_testsourceset_wip_skip.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-testsourceset-gate-compiles-the-test-sou/20261010-183332.log) |
| ❌ FAIL | BUG-20261011-review-log-py-loses-lines-under-concurre | review_log.py loses lines under concurrent writes, erases damaged lines, reads the model from text, takes older results for newer dispatches and counts implement runs as reviews | review_log | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_review_log.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261012-a-bug-linked-to-a-test-file-git-does-not | a bug linked to a test file git does not track yet stays NOT_IN_MATRIX forever (no regression test counted) | checklist | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_bug_untracked_test_ref.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261012-a-bug-linked-to-a-test-file-git-does-not/20261012-222502.log) |
| ❌ FAIL | BUG-20261012-a-session-blocked-by-a-held-checkout-sto | a session blocked by a held checkout stops to ask the user instead of making its own worktree | session-lock | REG-DK-ALL-01, universal-agent-devkit/tests/context_memory/test_session_lock_worktree_hint.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261012-a-session-blocked-by-a-held-checkout-sto/20261024-123721.log) |
| ❌ FAIL | BUG-20261012-hardware-gate-passes-a-quoted-or-root-gl | hardware gate passes a quoted or root-glob rm on a system partition | hardware-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_hardware_unglob_quoted.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261012-hardware-gate-passes-a-quoted-or-root-gl/20261012-205707.log) |
| ❌ FAIL | BUG-20261012-hardware-gate-passes-ansi-c-or-locale-qu | hardware gate passes ANSI-C or locale quoted rm on a system partition (dollar left glued to the command) | hardware-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_hardware_unglob_quoted.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261012-hardware-gate-passes-ansi-c-or-locale-qu/20261012-211115.log) |
| ❌ FAIL | BUG-20261012-hardware-gate-refuses-clearing-adb-scrat | hardware gate refuses clearing adb scratch folder /data/local/tmp | hardware-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_hardware_data_local_tmp.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261012-hardware-gate-refuses-clearing-adb-scrat/20261012-224411.log) |
| ❌ FAIL | BUG-20261012-regression-gate-blocks-the-stop-on-a-sui | regression gate blocks the Stop on a suite killed from outside (exit 137/143) as if a test failed | regression-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_regression_gate_killed_suite.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261012-regression-gate-blocks-the-stop-on-a-sui/20261012-205459.log) |
| ❌ FAIL | BUG-20261012-regression-gate-reuse-key-moves-with-age | regression_gate reuse key moves with agent memory notes because devkit_harness.OWN lacks claude-auto (tree_fp already excludes it) | tree-fp | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_harness_fp_claude_auto.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261012-regression-gate-reuse-key-moves-with-age/20261012-210837.log) |
| ❌ FAIL | BUG-20261012-stop-gates-run-on-progress-replies-whose | stop gates run on progress replies whose only claim is a check mark or a table row | stop-hook | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_outcome_table_rows.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261012-stop-gates-run-on-progress-replies-whose/20261012-211004.log) |
| ❌ FAIL | BUG-20261012-test-evidence-gate-lets-a-pass-claim-thr | test_evidence_gate lets a pass claim through when an exempted match swallows it, and blocks the Vietnamese cycle name or quoted mentions of its trigger words | test-evidence-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_evidence_claim_mentions.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261012-test-evidence-gate-lets-a-pass-claim-thr/20261012-220235.log) |
| ❌ FAIL | BUG-20261012-test-session-lock-resolve-compares-bash | test_session_lock_resolve compares bash errno wording that flips with the directory the test is started from (red from the repo root, also on the unpatched kit) | session-lock | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_session_lock_resolve.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261012-tree-fingerprint-moves-with-agent-memory | tree fingerprint moves with agent memory notes so a green gate receipt is lost | tree-fp | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_tree_fp_claude_auto.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261012-tree-fingerprint-moves-with-agent-memory/20261012-204933.log) |
| ❌ FAIL | BUG-20261012-user-prompt-hook-exits-127-silently-when | user prompt hook exits 127 silently when the hook files are gone, so every guard is off with no warning | hooks | REG-DK-ALL-01, universal-agent-devkit/tests/installer/test_prompt_hook_missing.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261012-user-prompt-hook-exits-127-silently-when/20261012-210439.log) |
| ❌ FAIL | BUG-20261013-a-repo-link-to-the-old-scripts-red-proof | a repo link to the old scripts/red_proof.py path is broken since scripts/ was split into groups | installer | REG-DK-ALL-01, universal-agent-devkit/tests/installer/test_legacy_script_paths.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261013-a-repo-link-to-the-old-scripts-red-proof/20261013-072833.log) |
| ❌ FAIL | BUG-20261013-agent-test-approval-claude-transcript | post-fix-gate never read the agent's in-turn test approval in a Claude Code transcript (message.content), so the Stop hook kept asking the user | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_approval_content_hash.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261013-merge-gate-folder-deleted-before-stop | worktree_merge_gate passed a worktree whose folder was deleted before the Stop while its commit was not in main | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_worktree_merge_gate_vanished.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261013-merge-gate-vanished-worktree-race | worktree_merge_gate held a Stop on a worktree another merge landed, and passed vanished/reflog-only/rewound worktrees whose work never reached main | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_worktree_merge_gate_vanished.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261013-opencodereview-never-ran-ocr-review-exit | OpenCodeReview never ran: ocr review exits 1 without an LLM endpoint, nothing reported it, and review_gate ignored OCR | review-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_review_gate_ocr.sh (trong suite) | RED-proof INCONCLUSIVE: [log](evidence/redproof-BUG-20261013-opencodereview-never-ran-ocr-review-exit/20261013-151107.log) |
| ❌ FAIL | BUG-20261013-regression-gate-blocks-the-stop-of-a-rea | regression_gate blocks the Stop of a read-only session on the diff of the session that holds the checkout | regression-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_regression_gate_held_by_other.sh (trong suite) | RED-proof INCONCLUSIVE: [log](evidence/redproof-BUG-20261013-regression-gate-blocks-the-stop-of-a-rea/20261013-154215.log) |
| ❌ FAIL | BUG-20261013-relink-check-never-links-a-skill-the-dev | relink_check never links a skill the DevKit gained after the install | relink | REG-DK-ALL-01, universal-agent-devkit/tests/worktree_git/test_relink_skills.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261013-relink-check-never-links-a-skill-the-dev/20261013-072848.log) |
| ❌ FAIL | BUG-20261013-test-approval-from-foreign-records | post-fix-gate approved edited tests from records that are not the agent's approval (queue-operation, Antigravity USER_INPUT, other projects' logs, prose, substrings) | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_approval_content_hash.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261013-worktree-gc-deletes-unique-work | worktree gc could delete unique work (unreachable blobs, ignored non-build files, a person's worktree, a live session's worktree) | - | REG-DK-ALL-01, universal-agent-devkit/tests/worktree_git/test_worktree_gc.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-agpm-global-config-guessable-tmp | ANTIGRAVITY_PM_GLOBAL_CONFIG test pin pointed at a guessable path in a shared TMPDIR (kit tests/lib/clean_git_env.sh, MCP tests/helpers.js): a file planted there with giaoDefault/testCommand steered every test | pm-mcp | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-automerge-gate-result-not-object | automerge printed a traceback instead of its JSON line when the gate's last line was JSON but no object | devkit-worktree | REG-DK-ALL-01, universal-agent-devkit/tests/worktree_git/test_worktree_trunk_merge.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-automerge-untracked-symlink | worktree automerge committed an untracked symlink and the fast-forward replaced main's ignored node_modules/ with it | devkit-worktree | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-budget-cut-forgets-passed-suites | A Stop run that spent GATE_TOTAL_BUDGET_S kept no suite results, so the next Stop on the same content ran every suite again | devkit-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_budget_resume.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-evidence-outcome-quoted-mention | test_evidence_gate check 7 read a quoted mention of the phrase 'da fix' as an outcome claim | devkit-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_evidence_outcome_mention.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-fifo-harness-canary-false-green | test_hook_gitignore_fifo canaries printed a pass when their child never started within the limit (nothing was tested) | devkit-tests | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-fifo-harness-cleanup-kill-gone | test_hook_gitignore_fifo crashed with ProcessLookupError when the leaked canary it cleans up had already ended, skipping every later hook check | devkit-tests | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-fifo-harness-grandchild | test_hook_gitignore_fifo killed only the bash child on its timeout, a grandchild blocked on a FIFO outlived the case for ever | devkit-tests | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-fifo-harness-killpg-eperm | test_hook_gitignore_fifo crashed with PermissionError when killpg met a process group holding only zombies on macOS | devkit-tests | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-gate-recreates-removed-project | gate re-created a worktree folder removed while its suites ran (regression_status.json, INBOX, evidence, journal) | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_project_removed_midrun.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-guard-shell-norm-fail-open | command guards let through commands hidden behind su -c, adb shell, ssh option values, bash -lc, wrapper option values, a heredoc operator inside quotes or a comment, and device-side rm forms (braces, dot-dot paths, cd then rm, find -delete, tilde) | devkit-guard | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_guard_shell_norm.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-heredoc-data-false-block | command guards read heredoc data as commands: block-dangerous-git refused a quoted python heredoc whose body held a backtick, hardware_safety_gate walked cat-to-file heredoc bodies as rm commands | devkit-guard | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_guard_shell_norm.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-lock-file-stale-takeover-race | worktree.py _lock_file (automerge, MAIN_LOCK, worktree add) let two waiters take over a dead holder's O_EXCL lock file together, and gave up at once when the file vanished mid-read | - | REG-DK-ALL-01, universal-agent-devkit/tests/worktree_git/test_worktree_lock_helper.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-ocr-endpoint-rejected-holds-stop | ocr-review failed hard when the OCR LLM endpoint rejected every request (API key over its usage limit), so review_gate held every session's Stop | - | REG-DK-ALL-01, universal-agent-devkit/tests/installer/test_ocr_review_helper.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-proof-report-label-variants | proof_gate blocked a report that carried all four items under other labels (Nguy co moi, Da lam gi, Chan loi cu, Da fix duoc gi) | devkit-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_proof_gate_report_labels.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-python-isolation-heartbeat-age | test_hook_python_isolation compared the session_lock heartbeat age in whole seconds, so a run stalled past 1 s under load reported a false BYPASS of session_lock.sh | devkit-tests | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-red-proof-runner-under-tests-read-as-test | red_proof read a production runner under tests/ as a test, so the 09/10 audit rows could not be proven | devkit-gate | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_red_proof.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261014-red-proof-runner-under-tests-read-as-test/20261024-125135.log) |
| ❌ FAIL | BUG-20261014-review-gate-ocr-scope | review_gate OCR requirement: --from without --to failed, one report cleared committed+uncommitted code, ranged flag read from the whole command | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_review_gate_ocr.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-session-lock-let-cp-mv-rm-tee-sed-i-touc | session_lock let cp/mv/rm/tee/sed -i/touch into a held checkout through, and blocked reads naming the gate folder | devkit-hooks | REG-DK-ALL-01, universal-agent-devkit/tests/context_memory/test_session_lock_file_writes.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-shell-writes-env-split-escapes | shell_writes read env -S lines with shlex only, so the env escapes \_ (word separator) and \c (end of line) were misread: a write slipped through or a false block | devkit-hooks | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-shell-writes-env-split-sq-escape | shell_writes dropped an env -S line that shlex cannot parse (an escaped quote inside single quotes, which env honours), so its write was never judged | devkit-hooks | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-shell-writes-env-split-string | shell_writes skipped the command line of env -S / --split-string as an option value, so its writes were never judged | devkit-hooks | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-shell-writes-git-c-tilde | shell_writes did not expand ~ in the -C directory of a repository write, so worktree_guard missed a commit into main and blocked one into the worktree | devkit-hooks | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-testsourceset-lock-fifo-hang | testsourceset_gate hung on a FIFO planted at test_run.lock after its FIFO sweep (exec 9>> waits for a reader) | devkit-hooks | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-worktree-reflog-gone-folder | worktree inventory: a commit only the HEAD reflog names passes once the worktree folder is deleted (reflog read only while the folder exists) | devkit-worktree | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261014-worktree-secret-carry | git-ignored secret files made only in a worktree (keystore, key.properties) were deleted with it by finish/automerge/gc | devkit-worktree | REG-DK-ALL-01,  (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261015-android-rules-reach | android rules: selection-size and wiring-pin sections unreachable from the prompts that need them; PII half-rule in an on-demand block; ambiguous bucket spec | - | REG-DK-ALL-01, universal-agent-devkit/tests/context_memory/test_profile_split.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261015-churn-guard-p6 | churn_guard untracked-edit warning starts repo-owned code, repeats process spawns on re-edit, walks huge payloads | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_untracked_edit_warning.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261015-generic-traps-id | android generic-traps test hard-codes the promoted instinct id and exports a DEVKIT_ROOT agent-kit overwrites | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_android_generic_traps.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261015-generic-traps-round2 | android generic-traps test: stale comment, literal id 908 coupled to the real file, promote exit code unchecked in section C | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_android_generic_traps.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261015-lens-pin | state-matrix lens pin could not fail (token anywhere in the file) and the kit lens named document-viewer axes | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_state_matrix_lens.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261015-nightly-idle-holder | nightly named run ignores an idle session that holds the checkout | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_nightly.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261015-nightly-round2 | nightly named run: unreadable git dir and trunk-mode main went ahead, one repo ran twice under two letter cases, ~user raised | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_nightly.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261015-nightly-run-paths | nightly run accepts an empty path, runs one repo twice and passes a non-project folder | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_nightly.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261015-rule-titles-noise | android rules section titles stuffed with common words pointed ordinary prompts at section 12 or 16 | - | REG-DK-ALL-01, universal-agent-devkit/tests/context_memory/test_profile_split.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261015-wiring-pin-detect | wiring_pin scan: pin name per View only, View-only test silences, same-file object ignored, data class taken for a View, comment counted as a call, empty-bodied pin, unrunnable verify hint | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_wiring_pin.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261015-wiring-pin-round2 | wiring_pin verify misreads an inner trailing comma, counts a raw-string decoy, accepts a string-literal mention as a call | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_wiring_pin.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261015-wiring-pin-scan | wiring_pin scan skips non-ASCII paths, hangs on a FIFO, tracebacks on a Latin-1 byte, flags renamed files as new | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_wiring_pin.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261015-wiring-pin-verify | wiring_pin verify says holds for a wrapped or unreadable assertion, a comment-only call, an empty pin, a path outside root | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_wiring_pin.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-20261016-proof-gate-recursion-fail-open | proof_gate: a deeply nested receipt or state file crashes the hook with RecursionError and XONG passes (python exit 1 becomes wrapper exit 0) | devkit-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_proof_gate.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ❌ FAIL | BUG-VACUITY-SINCE-BASE | gate: vacuity revert uses HEAD under --since, so committed fixes look vacuous | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_vacuity_since.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-VACUITY-SINCE-BASE/20261009-171732.log) |
| ❌ FAIL | BUG-WT-1013 | worktree copies keep the macOS uchg flag so remove cannot delete them and leaves an unregistered orphan folder | - | REG-DK-ALL-01, universal-agent-devkit/tests/worktree_git/test_worktree_immutable_copy.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261014-pm-agy-init-compact-json-only | agy init event was found by a compact-JSON substring only: a stream-json line with spaces after the colon made every agy dispatch fail or wait the 60 s init timeout | pm-mcp | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261019-170227.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261014-pm-agy-lock-takeover-race | agy registry lock: stale-lock takeover was delete-then-create, so two PMs that saw the same stale lock could both enter the critical section (the second deleted the first one's NEW lock) and overwrite agy-conversations.json | pm-mcp | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261019-170227.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261014-pm-agy-prune-budget-breaks-loop | agy registry prune: once 3 entries with a pid had been checked with ps the loop stopped, so older entries without a pid (no ps needed) were kept and the registry grew past 500 | pm-mcp | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261019-170227.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261014-pm-doctor-agy-only-default-model | pm_doctor printed the agy diagnostics (binary, broken registry, permission policy) only when defaultModel was an agy model, so a task that runs agy through its own model or pm_dispatch model got no explanation for a failed dispatch | pm-mcp | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261019-170227.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261014-pm-ping-kills-reused-pid | pm_doctor ping stopped its agy turns with kill(pid,0)+kill(-pid): up to 90 s later the pid may have exited and been reused, so it could SIGKILL a stranger's process group | pm-mcp | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261019-170227.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261014-pm-status-agy-by-task-model | pm_status trusted task.model to tell an agy conversation from an IDE one: with ps broken a tier task whose conversation went through agy (pm_dispatch model=...) was nudged anyway and lost its whole report; the PLAN-phase nudge branch had no unknown-state check at all | pm-mcp | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261019-170227.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261014-pm-tests-guessable-agy-path | MCP tests that simulate a missing agy pointed ANTIGRAVITY_PM_AGY at a guessable path in the shared TMPDIR: an executable planted there would be run, in two tests with --dangerously-skip-permissions | pm-mcp | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261019-170227.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-droppending-always-writes | pm-mcp: dropPending rewrote the registry even when it removed nothing (delete returns true for absent keys) | - | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261019-170227.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-droppending-foreign-entry | pm-mcp: dropPending deleted by key only and could remove another live PM's pending entry | - | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261019-170227.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-null-selftag-accepted | pm-mcp: a null own fingerprint was accepted, leaving an entry that is never reaped | - | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261019-170227.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-orphan-sigkill | pm-mcp: agy opened by newConversation is orphaned when the PM is SIGKILLed while waiting for init (no pending record by pid) | - | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261019-170227.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-pending-leak-final-write | pm-mcp: a failed real-entry write after agy init left a pending-<pid> record in the registry | - | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261019-170227.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-reaper-recheck-before-kill | pm-mcp: reaper identity check ran outside the lock, long before the kill under the lock | - | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261019-170227.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-reaper-same-key-kill | pm-mcp: reaper re-check compared only the pid under a pid-keyed entry, so a rewritten pending entry (pid reuse) was killed | - | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261019-170227.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-reaper-stale-snapshot-kill | pm-mcp: orphan reaper killed from a stale registry snapshot, so an agy a PM had just registered could be killed | - | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261019-170227.log) |
| 🟡 CẦN CHẠY LẠI (code đã đổi) | BUG-20261015-agy-selftag-after-spawn | pm-mcp: the PM read its own ps fingerprint after spawning agy, widening the untracked window | - | REG-AUTO-ANTIGRAVITY-PM-MCP-01, mcp-servers/antigravity-pm-mcp/tests/agy-round2.test.js (trong suite) | [log REG-AUTO-ANTIGRAVITY-PM-MCP-01](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261019-170227.log) |
| 🐞 chưa sửa | BUG-20261012-test-chap-chon-flaky-reg-dk-session-01 | Test chập chờn (flaky): REG-DK-SESSION-01 | devkit-session-lock | REG-DK-SESSION-01 | [log REG-DK-SESSION-01](evidence/REG-DK-SESSION-01/20261019-234500.log) |
| 🐞 chưa sửa | BUG-20261013-test-chap-chon-flaky-reg-dk-all-01 | Test chập chờn (flaky): REG-DK-ALL-01 | devkit-all | REG-DK-ALL-01 | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261019-235358.log) |
| ⚠️ có test, gate không chạy | BUG-20261013-bug-capture-copied-a-pasted-secret | Bug capture copied an API key pasted in a prompt into regression_status.json and CHECKLIST.md (title and id unredacted) | checklist | tests/verification/test_bug_secret_redaction.sh (ngoài matrix) | 13/10 workbench: REPORTED row held a pasted key; redact_secrets at register_bug/ |
| ⚠️ có test, gate không chạy | BUG-20261013-regression-gate-held-skip-ignored-writers | regression_gate skipped the Stop for a payload without session_id or with DEVKIT_ALLOW_SHARED_CHECKOUT=1 while another session held the lock | gates | tests/gates/test_regression_gate_held_by_other.sh (ngoài matrix) | OpenCodeReview of Dot 29 (13/10): held-by-other skip ignored the cases session_l |

## 🟡 REPORTED — bug báo qua prompt, chưa xác nhận (31)

> Chưa tính là bug. Xác nhận: `agent-kit bugs add "<tiêu đề>" --id <ID>` · có test ĐỎ→XANH: `agent-kit bugs link <ID> <TEST>` · không phải bug: `agent-kit bugs drop <ID>`

| ID | Prompt | Ngày |
|---|---|---|
| BUG-20261014-goal-set-fix-het-toan-bo-roi-xoa-issues | Goal set: fix hết toàn bộ rồi xoá issues-bugs vs workflow-improvements.md luôn | 2026-10-14 19:09:28 |
| BUG-20261015-hien-dang-co-phien-dang-chay-do-bi-limit | hiện đang có phiên đang chạy dở bị limit hãy làm tiếp đi | 2026-10-15 20:28:30 |
| BUG-20261016-audit-review-cho-toi-5-repo-https-github | audit, review cho tôi 5 repo https://github.com/ToanMobile?tab=projects hiện nhiều task bị blocked,ready ko chạy được t… | 2026-10-16 17:44:34 |
| BUG-20261016-background-from-the-session-that-started | Background (from the session that started this one): | 2026-10-16 19:53:56 |
| BUG-20261016-first-operation-run-claude-bin-super-boa | First operation: run .claude/bin/super-board-skills-ready.py --root '/Volumes/Data/Toan/agent-workbench' --host claude… | 2026-10-16 14:32:22 |
| BUG-20261016-gan-label-theo-thu-tu-uu-tien-da-lap-va | Gắn label theo thứ tự ưu tiên đã lập và dừng vòng lặp super-board đang lỗi | 2026-10-16 20:57:33 |
| BUG-20261016-phien-sort-task-backlog-cua-account-kia | phiên sort task backlog của account kia bị limit á | 2026-10-16 20:56:35 |
| BUG-20261016-update-toan-bo-status-vao-issues-bugs-vs | update toàn bộ status vào issues-bugs vs workflow-improvements chưa xoá những task hay issues đã làm xong rồi | 2026-10-16 11:21:24 |
| BUG-20261016-update-toan-bo-status-vao-issues-bugs-vs-2 | update toàn bộ status vào issues-bugs vs workflow-improvements hết sau đó xoá những task hay issues đã làm xong rồi | 2026-10-16 11:22:11 |
| BUG-20261017-them-watch-files-cho-super-board-vao-reg | Thêm watch_files cho super-board vào regression checklist để test_github_read.sh và test_runner_lanes.sh được chọn khi… | 2026-10-17 08:02:27 |
| BUG-20261017-toi-se-chi-file-hoac-config-co-duong-dan | Tôi sẽ chỉ file hoặc config có đường dẫn push_gate sai | 2026-10-17 08:23:46 |
| BUG-20261018-https-github-com-toanmobile-neighbours-f | https://github.com/ToanMobile/Neighbours-From-Hell/issues/8 đang bị blocked check và fix | 2026-10-18 20:28:30 |
| BUG-20261018-kiem-tra-cac-task-dang-bi-blocked-cho-to | kiểm tra các task đang bị blocked cho tôi fix root cause | 2026-10-18 21:57:27 |
| BUG-20261018-lam-cho-toi-89-vs-76 | làm cho tôi 89 vs 76 | 2026-10-18 21:18:33 |
| BUG-20261019-108-88-duyet-a-con-worktree-treo-nao-mo | #108, #88 duyệt á, còn worktree treo nào mồ côi thì xoá đi | 2026-10-19 21:44:31 |
| BUG-20261019-ban-tiep-quan-mot-viec-do-trong-repo-vol | Bạn tiếp quản một việc dở trong repo /Volumes/Data/Toan/agent-workbench (agent-workbench, GitHub ToanMobile/agent-workb… | 2026-10-19 22:37:59 |
| BUG-20261019-dong-y-sao-luu-2-file-trang-thai-abort-m | Đồng ý: sao lưu 2 file trạng thái, abort merge kẹt, rồi reset main local agent-workbench về origin/main. | 2026-10-19 16:38:19 |
| BUG-20261019-hien-cac-task-dang-bi-ket-o-cac-luong-re | hiện các task đang bị kẹt ở các luồng review, QA, building xử lý ntn? | 2026-10-19 09:07:27 |
| BUG-20261019-hien-con-nhieu-branch-dang-bi-mo-coi-ngu | hiện còn nhiều branch đang bị mồ côi nguyên nhân tại sao vậy? | 2026-10-19 16:53:00 |
| BUG-20261019-hoc-tu-kandev-centralized-daemon-global | Học từ Kandev (Centralized Daemon & Global Worker Pool): | 2026-10-19 16:41:26 |
| BUG-20261019-ok-da-tao-phien-fix-loi-nay-chua | ok đã tạo phiên fix lỗi này chưa? | 2026-10-19 10:44:50 |
| BUG-20261019-qua-nhieu-task-bi-blocked-tim-nguyen-nha | quá nhiều task bị blocked tìm nguyên nhân và fix root cause ở devkit | 2026-10-19 07:23:33 |
| BUG-20261019-sao-bi-ket-hoai-vay-truoc-do-chay-test-2 | sao bị kẹt hoài vậy trước đó chạy test 20 phiên mỗi repo đều pass trơn tru mà? | 2026-10-19 09:10:06 |
| BUG-20261019-tao-5-agent-quet-toan-bo-xem-con-toi-uu | tạo 5 agent quét toàn bộ xem còn tối ưu hay bugs chỗ nào nữa ko? | 2026-10-19 21:54:26 |
| BUG-20261019-tao-worktree-cho | tạo worktree cho | 2026-10-19 14:50:08 |
| BUG-20261019-tiep-quan-agent-workbench-19-10-2026-22 | Tiếp quản agent-workbench (19/10/2026, ~22:30). Đọc trước: .agents/local/memory/claude-auto/handoff-2026-10-19-ocr-batc… | 2026-10-19 22:38:14 |
| BUG-20261019-update-lai-cac-pr-log-comment-don-gian-t | update lại các PR log comment đơn giản tự nhiên nhanh gọn ko dài dòng tránh lỗi chặn khi diff PR quá lớn | 2026-10-19 07:34:55 |
| BUG-20261020-commit-di-khong-chay-gate | commit đi, không chạy gate | 2026-10-20 00:37:23 |
| BUG-20261020-hien-van-bi-ket-tin-nhan | hiện vẫn bị kẹt tin nhắn | 2026-10-20 00:17:04 |
| BUG-20261020-la-sao-fix-chua-do-hien-van-ket-phai-bam | là sao fix chưa? đó hiện vẫn kẹt phải bấm send now để gửi ép | 2026-10-20 00:07:23 |
| BUG-20261020-no-ket-stop-hook-prompt-cua-toi-ko-run-d | nó kẹt stop hook prompt của tôi ko run đc | 2026-10-20 00:02:14 |
