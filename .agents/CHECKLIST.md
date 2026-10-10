# 🧪 Regression Checklist

**An toàn 89% (49/55)** · ❌ 0 · 🔁 0 · 🚫 0 · 🟡 0 cần chạy lại · ⚠️ 0 cần test · ⚠️ 0 test có thể không suite nào chạy · 🐞 0 chưa sửa · ⏳ 6 chờ · 🚗 0 chờ chạy lặp trên xe · 🟡 REPORTED 0 · ma trận chờ duyệt: không

> Sinh tự động lúc 2026-10-10 18:29:30 — **không sửa tay**. % an toàn = PASS ÷ mọi dòng test/REQ/bug đã xác nhận (REPORTED không tính). PASS chỉ từ lần chạy thật + (bug/REQ) test đã chứng minh ĐỎ.

**Bug không có test hồi quy nào chặn tái phát: 0** (0 chưa có test · 0 có test nhưng gate không chạy)

## 🚨 Cần xử lý (0)

Không có gì — mọi dòng đã xác nhận đang an toàn hoặc chờ lần chạy tới.

## 🧩 Phân hệ

<details><summary>✅ devkit-all — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-ALL-01 | DevKit tests that name a changed file (code, templates, rules) + repo consistency; the full suite exceeds the 900 s gate limit | 2026-10-10 18:29:13 · 80.87s · exit 0 · 55c54fa+dirty · [log](evidence/REG-DK-ALL-01/20261010-182913.log) | bash universal-agent-devkit/tests/run_impacted.sh |

</details>

<details><summary>✅ devkit-gate — 2/2 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-GATE-01 | post-fix gate | 2026-10-10 10:21:01 · 127.11s · exit 0 · 6f1734f+dirty · [log](evidence/REG-DK-GATE-01/20261010-102101.log) | bash universal-agent-devkit/tests/gates/test_postfix_gate.sh |
| ✅ PASS | REG-DK-GATE-02 | proof gate (tree_fp) | 2026-10-10 10:21:01 · 24.43s · exit 0 · 6f1734f+dirty · [log](evidence/REG-DK-GATE-02/20261010-101918.log) | bash universal-agent-devkit/tests/gates/test_proof_gate.sh |

</details>

<details><summary>✅ devkit-health — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-HEALTH-01 | health | 2026-10-10 10:21:01 · 35.19s · exit 0 · 6f1734f+dirty · [log](evidence/REG-DK-HEALTH-01/20261010-101929.log) | bash universal-agent-devkit/tests/installer/test_agent_health.sh |

</details>

<details><summary>✅ devkit-hooks — 2/2 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-HOOK-01 | hook contract | 2026-10-10 18:29:13 · 60.15s · exit 0 · 55c54fa+dirty · [log](evidence/REG-DK-HOOK-01/20261010-182852.log) | bash universal-agent-devkit/hooks/tests/hook_contract_test.sh |
| ✅ PASS | REG-DK-HOOK-02 | proof gate | 2026-10-10 18:29:13 · 22.76s · exit 0 · 55c54fa+dirty · [log](evidence/REG-DK-HOOK-02/20261010-182815.log) | bash universal-agent-devkit/tests/gates/test_proof_gate.sh |

</details>

<details><summary>✅ devkit-session-lock — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-SESSION-01 | session lock + multi-session gate verdict (own session is never counted as another) | 2026-10-10 10:21:01 · 17.16s · exit 0 · 6f1734f+dirty · [log](evidence/REG-DK-SESSION-01/20261010-101911.log) | bash universal-agent-devkit/tests/context_memory/test_session_lock.sh && bash universal-agent-devkit/tests/gates/test_multi_session_gate.sh |

</details>

<details><summary>✅ devkit-token-cost — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-COST-01 | token cost tracker counts each message id once and prices the longest model key | 2026-10-02 16:10:23 · 0.29s · exit 0 · cf9ef39+dirty · [log](evidence/REG-DK-COST-01/20261002-160414.log) | bash universal-agent-devkit/tests/context_memory/test_token_cost_tracker.sh |

</details>

<details><summary>✅ devkit-worktree-sandbox — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-SANDBOX-01 | worktree sandbox cleanup keeps unmerged work unless --force | 2026-10-02 16:10:23 · 2.54s · exit 0 · cf9ef39+dirty · [log](evidence/REG-DK-SANDBOX-01/20261002-160414.log) | bash universal-agent-devkit/tests/worktree_git/test_worktree_sandbox.sh |

</details>

<details><summary>✅ mcp-servers/antigravity-pm-mcp — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-AUTO-ANTIGRAVITY-PM-MCP-01 | antigravity-pm-mcp: package.json test script | 2026-10-03 13:19:03 · 3.29s · exit 0 · 3695a70+dirty · [log](evidence/REG-AUTO-ANTIGRAVITY-PM-MCP-01/20261003-131903.log) | cd mcp-servers/antigravity-pm-mcp && npm test |

</details>

<details><summary>✅ mcp-servers/play-store-mcp — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-AUTO-PLAY-STORE-MCP-01 | play-store-mcp: pytest | 2026-10-02 20:00:40 · 4.83s · exit 0 · 4d568d9+dirty · [log](evidence/REG-AUTO-PLAY-STORE-MCP-01/20261002-195614.log) | cd mcp-servers/play-store-mcp && uv run --frozen --extra dev pytest -q |

</details>

<details><summary>✅ workbench-agent-config — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-WB-CONFIG-01 | agent-kit health: every registered hook exists, imports resolve, context in sync | 2026-10-09 19:48:46 · 0.47s · exit 0 · e504f82+dirty · [log](evidence/REG-WB-CONFIG-01/20261009-194846.log) | bash universal-agent-devkit/bin/agent-kit health -t . |

</details>

## 📒 Sổ tay bug (43)

| Trạng thái | Mã | Mô tả | Component | Test bảo vệ | Bằng chứng |
|---|---|---|---|---|---|
| ✅ PASS | BUG-20260925-prompt-bao-bug-that-cung-se-khong-con-du | prompt báo bug thật cũng sẽ không còn được ghi nhận nữa -> là sao bug đúng ko fix đi phải tự động ghi nhận chứ | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_bug_capture.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20260925-prompt-bao-bug-that-cung-se-khong-con-du/20261009-185852.log) |
| ✅ PASS | BUG-20260926-dev-kit-lam-tao-branch-push-lung-tung-kh | dev kit làm tạo branch, push lung tung không đồng bộ dẫn tới lệch code, vd geely ex2 hiện có 2 pull chưa pull về dẫn tớ… | - | REG-DK-ALL-01, REG-DK-HOOK-01, REG-DK-HOOK-02, universal-agent-devkit/hooks/tests/hook_contract_test.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20260926-dev-kit-lam-tao-branch-push-lung-tung-kh/20261009-181041.log) |
| ✅ PASS | BUG-20260928-audit-review-them-geely-ex2-hien-no-bao | audit, review thêm geely ex2 hiện nó báo tôi rất nhiều lỗi vậy có nghĩa là bộ devkit hoàn toàn chất lượng kém để thủng… | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_friction.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20260928-audit-review-them-geely-ex2-hien-no-bao/20261009-180103.log) |
| ✅ PASS | BUG-20260928-fix-luon-loi-git-guard-chan-grep-di-ngoa | fix luôn lỗi git guard chặn grep đi ngoài ra đã tối ưu token sử dụng cũng như thời gian chạy chưa ? Đề xuất các phương… | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_friction.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20260928-fix-luon-loi-git-guard-chan-grep-di-ngoa/20261009-182605.log) |
| ✅ PASS | BUG-20260928-push-geely-va-fix-luon-loi-red-proof | push geely và fix luôn lỗi red_proof | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_red_proof.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20260928-push-geely-va-fix-luon-loi-red-proof/20261009-174029.log) |
| ✅ PASS | BUG-20260928-san-check-luon-chat-luong-dev-kit-workfl | sẵn check luôn chất lượng dev kit workflow có bị lỗi gì ko fix luôn đi | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_friction.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20260928-san-check-luon-chat-luong-dev-kit-workfl/20261009-180602.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20260929-audit-review-nguyen-nhan-tai-sao-cac-ses | audit, review nguyên nhân tại sao các sesion cài dev kit chạy rất chậm có lỗi gì hay ko? | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_regression_gate_hook.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261010-182913.log) |
| ✅ PASS | BUG-20261001-lam-luon-fix-bug-worktree-di | làm luôn fix bug worktree đi | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_worktree_merge_gate.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261001-lam-luon-fix-bug-worktree-di/20261009-182503.log) |
| ✅ PASS | BUG-20261001-sua-luon-bug-init-xoa-mcp-server-di | sửa luôn bug init xoá MCP server đi | - | REG-DK-ALL-01, universal-agent-devkit/tests/installer/test_platform_rules.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261001-sua-luon-bug-init-xoa-mcp-server-di/20261009-175104.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20261002-agent-kit-health-run-tests-scores-96-100 | agent-kit health --run-tests scores 96/100: agent-kit test runs ~90 test scripts one after another (~19 min), past the 900 s limit health allows | devkit-health | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_run_impacted.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261010-182913.log) |
| ✅ PASS | BUG-20261002-chay-finagling-running-stop-hooks-8-9-27 | chạy Finagling… (running Stop hooks… 8/9 · 27m 24s · ↓ 46.3k tokens) quá lâu audit, review sửa lại đi Stop hooks… rất h… | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_regression_gate_hook.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261002-chay-finagling-running-stop-hooks-8-9-27/20261009-173819.log) |
| ✅ PASS | BUG-20261002-evidence-gate-foreign-xml-nonrunner | test_evidence_gate: a Bash that only names a foreign project (cd && git status) made its fresh XML count as this session's test evidence | devkit | REG-DK-ALL-01, REG-DK-HOOK-01, REG-DK-HOOK-02, universal-agent-devkit/hooks/tests/hook_contract_test.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261002-evidence-gate-foreign-xml-nonrunner/20261009-190334.log) |
| ✅ PASS | BUG-20261002-gate-rejects-a-change-that-moves-a-test | Gate REJECTs a change that moves a test file the matrix names: it runs the base matrix, whose command names the removed path (exit 127), and flags the matrix edit for review | devkit-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_matrix_rename.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261002-gate-rejects-a-change-that-moves-a-test/20261009-172300.log) |
| ✅ PASS | BUG-20261002-proof-gate-reinit-same-profile | proof gate: re-init rewriting the same backend profile counted as a profile switch and demanded a PNG | devkit | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_proof_gate.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261002-proof-gate-reinit-same-profile/20261009-170334.log) |
| ✅ PASS | BUG-20261002-sessionstart-skips-the-checklist-block-a | SessionStart skips the checklist block and the background STALE re-run after the scripts/ regrouping (bin/ and stale_rerun.py paths) | devkit-hooks | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_stale.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261002-sessionstart-skips-the-checklist-block-a/20261009-173233.log) |
| ✅ PASS | BUG-20261008-sua-4-loi-kit-phien-office-nho-di | sửa 4 lỗi kit phiên Office nhờ đi | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_session_lock_target_repo.sh (trong suite), universal-agent-devkit/tests/worktree_git/test_worktree_automerge.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261008-sua-4-loi-kit-phien-office-nho-di/20261008-235601.log) |
| ✅ PASS | BUG-20261009-automerge-refusal-reason-lost | worktree automerge: a commit refused by the repo's pre-commit gate was reported with only the last 500 characters of the gate output, which is the passed-checks footer, never the finding: the worktree stayed unmerged and nobody could tell why (GeelyEx2 giao-tichhop-09-10, base-hoiquy-09-10) | devkit-worktree | REG-DK-ALL-01, universal-agent-devkit/tests/worktree_git/test_worktree_automerge_reason.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261009-automerge-refusal-reason-lost/20261009-192819.log) |
| ✅ PASS | BUG-20261009-churn-guard-no-fast-path | churn_guard started python on every Edit although it can warn only when the transcript names the file at least N times | devkit-hooks | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_churn_guard_fast_path.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261009-churn-guard-no-fast-path/20261009-190532.log) |
| ✅ PASS | BUG-20261009-comment-claim-docstring-trailing | comment_claim_guard: a claim inside a Python docstring or after code on the same line (# / //) passed while the same words in a full-line comment warn | devkit-hooks | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_comment_claim_docstring_trailing.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261009-comment-claim-docstring-trailing/20261009-210844.log) |
| ✅ PASS | BUG-20261009-gate-js-describe-title-false-flag | post-fix-gate: the same it('title') in two different describe blocks flagged a pure append of a JS test as an edited test | devkit-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_js_describe_scope.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261009-gate-js-describe-title-false-flag/20261009-211414.log) |
| ✅ PASS | BUG-20261009-gate-runner-no-errexit-append | post-fix-gate: any command appended to a shell test runner WITHOUT set -e counted as a pure append, though it decides the exit status over an earlier failure (user decision 2026-10-09) | devkit-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_runner_no_errexit.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261009-gate-runner-no-errexit-append/20261009-211102.log) |
| ✅ PASS | BUG-20261009-git-guard-bash-c-subst-tee-shell | block-dangerous-git: bash -c "$(curl ...)" and a shell inside >(...) ran generated text that curl \| bash and bash <(...) already refuse | devkit-git-guard | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_git_guard_shell_subst.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261009-git-guard-bash-c-subst-tee-shell/20261009-220947.log) |
| ✅ PASS | BUG-20261009-hardware-find-negated-or-unfiltered | hardware_safety_gate: find ! -name x -delete, -not, and an -o alternative without a filter counted as filtered, so the start point was never judged | devkit-hardware-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_hardware_find_not_or.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261009-hardware-find-negated-or-unfiltered/20261009-213309.log) |
| ✅ PASS | BUG-20261009-hooks-log-dir-process-cwd | 7 hooks (bash_write_ledger, security_gate, proof_gate, regression_gate, test_evidence_gate, review_timing_guard, prompt_context) took the project from the PROCESS cwd when CLAUDE_PROJECT_DIR was unset and created .claude/audit-gate there (a run at / wrote /.claude) | devkit-hooks | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_hook_log_dir.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261009-hooks-log-dir-process-cwd/20261009-203143.log) |
| ✅ PASS | BUG-20261009-merge-gate-held-vanished-worktree | worktree_merge_gate: a worktree removed by the last Stop's background merge while this Stop decided stayed in the hold list (flaky test_worktree_merge_gate_owner) | devkit-worktree | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_worktree_merge_gate_vanished.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261009-merge-gate-held-vanished-worktree/20261009-181812.log) |
| ✅ PASS | BUG-20261009-review-timing-guard-env-payload | review_timing_guard: the hook payload travelled in an environment variable, so an Edit of a big file (payload past the 1 MiB exec limit) made the shell fail with Argument list too long and the guard never ran | devkit-hooks | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_review_timing_guard_big_payload.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261009-review-timing-guard-env-payload/20261009-181603.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20261009-run-impacted-recent-commits-in-sandbox | run_impacted.sh in a checkout with no upstream (every RED-proof sandbox) selected the tests of every commit of the last 6 hours: 25+ minutes per proof instead of the few tests of the reverted file | devkit-tests | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_run_impacted_since.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261010-182913.log) |
| ✅ PASS | BUG-20261009-scratch-cleanup-prune-could-delete-a-liv | scratch_cleanup: prune could delete a live idle session's dir and follow a slug swapped for a symlink (TOCTOU) | devkit-scratch-cleanup | REG-DK-ALL-01, universal-agent-devkit/tests/context_memory/test_scratch_cleanup.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261009-scratch-cleanup-prune-could-delete-a-liv/20261009-171413.log) |
| ✅ PASS | BUG-20261009-session-lock-a-cp-rc-copy-of-a-checkout | session_lock: a cp -Rc copy of a checkout carried the original's lock and was held by its live holder up to 600 s | devkit-session-lock | REG-DK-ALL-01, universal-agent-devkit/tests/context_memory/test_session_lock.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261009-session-lock-a-cp-rc-copy-of-a-checkout/20261009-203323.log) |
| ✅ PASS | BUG-20261009-session-lock-an-idle-holder-turn-over-wa | session_lock: an idle holder (turn over, waiting at the prompt) kept the checkout 600 s, other sessions needed /exit | devkit-session-lock | REG-DK-ALL-01, universal-agent-devkit/tests/context_memory/test_session_lock.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261009-session-lock-an-idle-holder-turn-over-wa/20261009-203838.log) |
| ✅ PASS | BUG-20261009-session-lock-case-only-path | session_lock: a path spelled with other letter case (APFS) fell outside the locked checkout, so the write took no lock and a live holder lost it | devkit-session-lock | REG-DK-ALL-01, universal-agent-devkit/tests/context_memory/test_session_lock.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261009-session-lock-case-only-path/20261009-202937.log) |
| ✅ PASS | BUG-20261010-gate-swallows-a-failed-linter-import-and | gate swallows a failed linter import and switches the lint off silently | devkit-guards | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_linter_import_loud.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-gate-swallows-a-failed-linter-import-and/20261010-102355.log) |
| ✅ PASS | BUG-20261010-gate-wants-a-regression-test-for-red-pro | gate wants a regression test for red-proof patch files | devkit-guards | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_redpatch_no_test.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-gate-wants-a-regression-test-for-red-pro/20261010-103756.log) |
| ✅ PASS | BUG-20261010-guard-hooks-lose-the-command-that-follow | guard hooks lose the command that follows a comment or a hash inside a word | devkit-guards | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_guard_comment_not_swallowing.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-guard-hooks-lose-the-command-that-follow/20261010-101953.log) |
| ✅ PASS | BUG-20261010-health-reports-100-while-a-tracked-symli | health reports 100 while a tracked symlink points at a missing target | devkit-guards | REG-DK-ALL-01, universal-agent-devkit/tests/installer/test_agent_health_broken_tracked_link.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-health-reports-100-while-a-tracked-symli/20261010-104501.log) |
| ✅ PASS | BUG-20261010-matrix-accepts-one-suite-id-with-two-dif | matrix accepts one suite id with two different commands without a word | devkit-guards | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_matrix_duplicate_id.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-matrix-accepts-one-suite-id-with-two-dif/20261010-105445.log) |
| ✅ PASS | BUG-20261010-proof-gate-blocks-a-push-turn-whose-4-it | proof_gate blocks a push turn whose 4-item report was already written right after the push | proof_gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_proof_gate_report_after_push.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-proof-gate-blocks-a-push-turn-whose-4-it/20261010-125933.log) |
| ✅ PASS | BUG-20261010-red-proof-keeps-a-patch-of-any-size-in-a | red proof keeps a patch of any size in a tracked folder | devkit-guards | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_red_proof_patch_cap.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-red-proof-keeps-a-patch-of-any-size-in-a/20261010-110336.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20261010-regression-gate-re-runs-every-suite-on-a | regression_gate re-runs every suite on a repeated FAIL when one suite cannot run here, ignores local config and age, and sessions erase each other's stored blocks | regression_gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_regression_gate_repeat_cache.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261010-182913.log) |
| ✅ PASS | BUG-20261010-session-lock-blocks-read-only-commands-s | session lock blocks read-only commands: stash list and grep naming the gate | devkit-guards | REG-DK-ALL-01, universal-agent-devkit/tests/context_memory/test_session_lock_readonly.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-20261010-session-lock-blocks-read-only-commands-s/20261010-102107.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20261010-test-evidence-gate-rebuilds-the-shell-va | test_evidence_gate rebuilds the shell variable table of every earlier command for each command (quadratic, 25 s on a 58 MB transcript) | test_evidence_gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_evidence_gate_linear.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261010-182913.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20261010-testsourceset-gate-compiles-the-test-sou | testsourceset_gate compiles the test source sets on every unfinished (CHUA XONG) stop | testsourceset_gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_testsourceset_wip_skip.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261010-182913.log) |
| ✅ PASS | BUG-VACUITY-SINCE-BASE | gate: vacuity revert uses HEAD under --since, so committed fixes look vacuous | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_vacuity_since.sh (trong suite) | RED-proof PROVEN: [log](evidence/redproof-BUG-VACUITY-SINCE-BASE/20261009-171732.log) |
