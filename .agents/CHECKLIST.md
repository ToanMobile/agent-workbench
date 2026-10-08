# 🧪 Regression Checklist

**An toàn 41% (12/29)** · ❌ 0 · 🔁 0 · 🚫 0 · 🟡 0 cần chạy lại · ⚠️ 0 cần test · ⚠️ 0 test có thể không suite nào chạy · 🐞 0 chưa sửa · ⏳ 17 chờ · 🚗 0 chờ chạy lặp trên xe · 🟡 REPORTED 0 · ma trận chờ duyệt: không

> Sinh tự động lúc 2026-10-08 15:24:45 — **không sửa tay**. % an toàn = PASS ÷ mọi dòng test/REQ/bug đã xác nhận (REPORTED không tính). PASS chỉ từ lần chạy thật + (bug/REQ) test đã chứng minh ĐỎ.

**Bug không có test hồi quy nào chặn tái phát: 0** (0 chưa có test · 0 có test nhưng gate không chạy)

## 🚨 Cần xử lý (0)

Không có gì — mọi dòng đã xác nhận đang an toàn hoặc chờ lần chạy tới.

## 🧩 Phân hệ

### core — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-01 | core tests | chưa chạy | echo FULL_TEST_EXECUTED |

<details><summary>✅ devkit-all — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-ALL-01 | DevKit tests that name a changed file (code, templates, rules) + repo consistency; the full suite exceeds the 900 s gate limit | 2026-10-08 15:14:19 · 310.86s · exit 0 · e70638e+dirty · [log](evidence/REG-DK-ALL-01/20261008-151418.log) | bash universal-agent-devkit/tests/run_impacted.sh |

</details>

<details><summary>✅ devkit-gate — 2/2 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-GATE-01 | post-fix gate | 2026-10-08 15:14:19 · 161.45s · exit 0 · e70638e+dirty · [log](evidence/REG-DK-GATE-01/20261008-151148.log) | bash universal-agent-devkit/tests/gates/test_postfix_gate.sh |
| ✅ PASS | REG-DK-GATE-02 | proof gate (tree_fp) | 2026-10-08 15:14:19 · 24.69s · exit 0 · e70638e+dirty · [log](evidence/REG-DK-GATE-02/20261008-150932.log) | bash universal-agent-devkit/tests/gates/test_proof_gate.sh |

</details>

<details><summary>✅ devkit-health — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-HEALTH-01 | health | 2026-10-04 15:48:02 · 16.12s · exit 0 · 23d0541+dirty · [log](evidence/REG-DK-HEALTH-01/20261004-154436.log) | bash universal-agent-devkit/tests/installer/test_agent_health.sh |

</details>

<details><summary>✅ devkit-hooks — 2/2 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-HOOK-01 | hook contract | 2026-10-08 15:14:19 · 86.06s · exit 0 · e70638e+dirty · [log](evidence/REG-DK-HOOK-01/20261008-151033.log) | bash universal-agent-devkit/hooks/tests/hook_contract_test.sh |
| ✅ PASS | REG-DK-HOOK-02 | proof gate | 2026-10-08 15:14:19 · 24.69s · exit 0 · e70638e+dirty · [log](evidence/REG-DK-GATE-02/20261008-150932.log) | bash universal-agent-devkit/tests/gates/test_proof_gate.sh |

</details>

<details><summary>✅ devkit-session-lock — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-SESSION-01 | session lock + multi-session gate verdict (own session is never counted as another) | 2026-10-08 15:14:19 · 15.53s · exit 0 · e70638e+dirty · [log](evidence/REG-DK-SESSION-01/20261008-150922.log) | bash universal-agent-devkit/tests/context_memory/test_session_lock.sh && bash universal-agent-devkit/tests/gates/test_multi_session_gate.sh |

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
| ✅ PASS | REG-WB-CONFIG-01 | agent-kit health: every registered hook exists, imports resolve, context in sync | 2026-10-08 15:14:19 · 0.53s · exit 0 · e70638e+dirty · [log](evidence/REG-WB-CONFIG-01/20261008-151418.log) | bash universal-agent-devkit/bin/agent-kit health -t . |

</details>

## 📒 Sổ tay bug (16)

| Trạng thái | Mã | Mô tả | Component | Test bảo vệ | Bằng chứng |
|---|---|---|---|---|---|
| ⏳ chưa chứng minh ĐỎ | BUG-20260925-prompt-bao-bug-that-cung-se-khong-con-du | prompt báo bug thật cũng sẽ không còn được ghi nhận nữa -> là sao bug đúng ko fix đi phải tự động ghi nhận chứ | - | REG-DK-ALL-01 | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261008-151418.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20260926-dev-kit-lam-tao-branch-push-lung-tung-kh | dev kit làm tạo branch, push lung tung không đồng bộ dẫn tới lệch code, vd geely ex2 hiện có 2 pull chưa pull về dẫn tớ… | - | REG-DK-ALL-01, REG-DK-HOOK-01, REG-DK-HOOK-02, universal-agent-devkit/hooks/tests/hook_contract_test.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261008-151418.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20260928-audit-review-them-geely-ex2-hien-no-bao | audit, review thêm geely ex2 hiện nó báo tôi rất nhiều lỗi vậy có nghĩa là bộ devkit hoàn toàn chất lượng kém để thủng… | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_friction.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261008-151418.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20260928-fix-luon-loi-git-guard-chan-grep-di-ngoa | fix luôn lỗi git guard chặn grep đi ngoài ra đã tối ưu token sử dụng cũng như thời gian chạy chưa ? Đề xuất các phương… | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_friction.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261008-151418.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20260928-push-geely-va-fix-luon-loi-red-proof | push geely và fix luôn lỗi red_proof | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_red_proof.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261008-151418.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20260928-san-check-luon-chat-luong-dev-kit-workfl | sẵn check luôn chất lượng dev kit workflow có bị lỗi gì ko fix luôn đi | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_friction.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261008-151418.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20260929-audit-review-nguyen-nhan-tai-sao-cac-ses | audit, review nguyên nhân tại sao các sesion cài dev kit chạy rất chậm có lỗi gì hay ko? | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_regression_gate_hook.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261008-151418.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20261001-lam-luon-fix-bug-worktree-di | làm luôn fix bug worktree đi | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_worktree_merge_gate.sh (trong suite) | RED-proof INCONCLUSIVE: [log](evidence/redproof-BUG-20261001-lam-luon-fix-bug-worktree-di/20261001-175745.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20261001-sua-luon-bug-init-xoa-mcp-server-di | sửa luôn bug init xoá MCP server đi | - | REG-DK-ALL-01, universal-agent-devkit/tests/installer/test_platform_rules.sh (trong suite) | RED-proof INCONCLUSIVE: [log](evidence/redproof-BUG-20261001-sua-luon-bug-init-xoa-mcp-server-di/20261001-192737.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20261002-agent-kit-health-run-tests-scores-96-100 | agent-kit health --run-tests scores 96/100: agent-kit test runs ~90 test scripts one after another (~19 min), past the 900 s limit health allows | devkit-health | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_run_impacted.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261008-151418.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20261002-chay-finagling-running-stop-hooks-8-9-27 | chạy Finagling… (running Stop hooks… 8/9 · 27m 24s · ↓ 46.3k tokens) quá lâu audit, review sửa lại đi Stop hooks… rất h… | - | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_regression_gate_hook.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261008-151418.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20261002-evidence-gate-foreign-xml-nonrunner | test_evidence_gate: a Bash that only names a foreign project (cd && git status) made its fresh XML count as this session's test evidence | devkit | REG-DK-ALL-01, REG-DK-HOOK-01, REG-DK-HOOK-02, universal-agent-devkit/hooks/tests/hook_contract_test.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261008-151418.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20261002-gate-rejects-a-change-that-moves-a-test | Gate REJECTs a change that moves a test file the matrix names: it runs the base matrix, whose command names the removed path (exit 127), and flags the matrix edit for review | devkit-gate | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_gate_matrix_rename.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261008-151418.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20261002-proof-gate-reinit-same-profile | proof gate: re-init rewriting the same backend profile counted as a profile switch and demanded a PNG | devkit | REG-DK-ALL-01, universal-agent-devkit/tests/gates/test_proof_gate.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261008-151418.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20261002-sessionstart-skips-the-checklist-block-a | SessionStart skips the checklist block and the background STALE re-run after the scripts/ regrouping (bin/ and stale_rerun.py paths) | devkit-hooks | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_stale.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261008-151418.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-VACUITY-SINCE-BASE | gate: vacuity revert uses HEAD under --since, so committed fixes look vacuous | - | REG-DK-ALL-01, universal-agent-devkit/tests/verification/test_vacuity_since.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261008-151418.log) |
