# 🧪 Regression Checklist

**An toàn 39% (7/18)** · ❌ 0 · 🔁 0 · 🚫 0 · 🟡 0 cần chạy lại · ⚠️ 0 cần test · ⚠️ 0 test có thể không suite nào chạy · 🐞 0 chưa sửa · ⏳ 11 chờ · 🚗 0 chờ chạy lặp trên xe · 🟡 REPORTED 1 · ma trận chờ duyệt: không

> Sinh tự động lúc 2026-09-30 16:05:27 — **không sửa tay**. % an toàn = PASS ÷ mọi dòng test/REQ/bug đã xác nhận (REPORTED không tính). PASS chỉ từ lần chạy thật + (bug/REQ) test đã chứng minh ĐỎ.

**Bug không có test hồi quy nào chặn tái phát: 0** (0 chưa có test · 0 có test nhưng gate không chạy)

## 🚨 Cần xử lý (0)

Không có gì — mọi dòng đã xác nhận đang an toàn hoặc chờ lần chạy tới.

## 🧩 Phân hệ

### antigravity-pm-mcp — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-AUTO-ANTIGRAVITY-PM-MCP-01 | antigravity-pm-mcp: package.json test script | chưa chạy | cd antigravity-pm-mcp && npm test |

### core — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-01 | core tests | chưa chạy | echo FULL_TEST_EXECUTED |

<details><summary>✅ devkit-all — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-ALL-01 | DevKit tests that name a changed file (code, templates, rules) + repo consistency; the full suite exceeds the 900 s gate limit | 2026-09-30 16:04:33 · 304.48s · exit 0 · e69550c+dirty · [log](evidence/REG-DK-ALL-01/20260930-160433.log) | bash universal-agent-devkit/tests/run_impacted.sh |

</details>

<details><summary>✅ devkit-gate — 2/2 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-GATE-01 | post-fix gate | 2026-09-30 11:46:47 · 74.65s · exit 0 · e69550c+dirty · [log](evidence/REG-DK-GATE-01/20260930-114032.log) | bash universal-agent-devkit/tests/test_postfix_gate.sh |
| ✅ PASS | REG-DK-GATE-02 | proof gate (tree_fp) | 2026-09-30 11:46:47 · 142.27s · exit 0 · e69550c+dirty · [log](evidence/REG-DK-GATE-02/20260930-114254.log) | bash universal-agent-devkit/tests/test_proof_gate.sh |

</details>

<details><summary>✅ devkit-health — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-HEALTH-01 | health | 2026-09-25 11:42:03 · 19.12s · exit 0 · 05ce90e+dirty · [log](evidence/REG-DK-HEALTH-01/20260925-112905.log) | bash universal-agent-devkit/tests/test_agent_health.sh |

</details>

<details><summary>✅ devkit-hooks — 2/2 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-HOOK-01 | hook contract | 2026-09-30 11:46:47 · 41.93s · exit 0 · e69550c+dirty · [log](evidence/REG-DK-HOOK-01/20260930-114336.log) | bash universal-agent-devkit/hooks/tests/hook_contract_test.sh |
| ✅ PASS | REG-DK-HOOK-02 | proof gate | 2026-09-30 11:46:47 · 142.27s · exit 0 · e69550c+dirty · [log](evidence/REG-DK-GATE-02/20260930-114254.log) | bash universal-agent-devkit/tests/test_proof_gate.sh |

</details>

### play-store-mcp — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-AUTO-PLAY-STORE-MCP-01 | play-store-mcp: pytest | chưa chạy | cd play-store-mcp && uv run --frozen --extra dev pytest -q |

<details><summary>✅ workbench-agent-config — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-WB-CONFIG-01 | agent-kit health: every registered hook exists, imports resolve, context in sync | 2026-09-30 11:46:47 · 0.31s · exit 0 · e69550c+dirty · [log](evidence/REG-WB-CONFIG-01/20260930-114647.log) | bash universal-agent-devkit/bin/agent-kit health -t . |

</details>

## 📒 Sổ tay bug (8)

| Trạng thái | Mã | Mô tả | Component | Test bảo vệ | Bằng chứng |
|---|---|---|---|---|---|
| ⏳ chưa chứng minh ĐỎ | BUG-20260925-prompt-bao-bug-that-cung-se-khong-con-du | prompt báo bug thật cũng sẽ không còn được ghi nhận nữa -> là sao bug đúng ko fix đi phải tự động ghi nhận chứ | - | REG-DK-ALL-01 | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20260930-160433.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20260926-dev-kit-lam-tao-branch-push-lung-tung-kh | dev kit làm tạo branch, push lung tung không đồng bộ dẫn tới lệch code, vd geely ex2 hiện có 2 pull chưa pull về dẫn tớ… | - | REG-DK-ALL-01, REG-DK-HOOK-01, REG-DK-HOOK-02, universal-agent-devkit/hooks/tests/hook_contract_test.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20260930-160433.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20260928-audit-review-them-geely-ex2-hien-no-bao | audit, review thêm geely ex2 hiện nó báo tôi rất nhiều lỗi vậy có nghĩa là bộ devkit hoàn toàn chất lượng kém để thủng… | - | REG-DK-ALL-01, universal-agent-devkit/tests/test_gate_friction.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20260930-160433.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20260928-fix-luon-loi-git-guard-chan-grep-di-ngoa | fix luôn lỗi git guard chặn grep đi ngoài ra đã tối ưu token sử dụng cũng như thời gian chạy chưa ? Đề xuất các phương… | - | REG-DK-ALL-01, universal-agent-devkit/tests/test_gate_friction.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20260930-160433.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20260928-push-geely-va-fix-luon-loi-red-proof | push geely và fix luôn lỗi red_proof | - | REG-DK-ALL-01, universal-agent-devkit/tests/test_red_proof.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20260930-160433.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20260928-san-check-luon-chat-luong-dev-kit-workfl | sẵn check luôn chất lượng dev kit workflow có bị lỗi gì ko fix luôn đi | - | REG-DK-ALL-01, universal-agent-devkit/tests/test_gate_friction.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20260930-160433.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20260929-audit-review-nguyen-nhan-tai-sao-cac-ses | audit, review nguyên nhân tại sao các sesion cài dev kit chạy rất chậm có lỗi gì hay ko? | - | REG-DK-ALL-01, universal-agent-devkit/tests/test_regression_gate_hook.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20260930-160433.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-VACUITY-SINCE-BASE | gate: vacuity revert uses HEAD under --since, so committed fixes look vacuous | - | REG-DK-ALL-01, universal-agent-devkit/tests/test_vacuity_since.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20260930-160433.log) |

## 🟡 REPORTED — bug báo qua prompt, chưa xác nhận (1)

> Chưa tính là bug. Xác nhận: `agent-kit bugs add "<tiêu đề>" --id <ID>` · có test ĐỎ→XANH: `agent-kit bugs link <ID> <TEST>` · không phải bug: `agent-kit bugs drop <ID>`

| ID | Prompt | Ngày |
|---|---|---|
| BUG-20260925-reader-office-dang-bi-ket-boi-1-agent-gr | reader office đang bị kẹt bởi 1 agent grok làm audit do dev kit lỗi ko? | 2026-09-25 08:41:07 |
