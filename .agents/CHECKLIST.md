# 🧪 Regression Checklist

**An toàn 58% (7/12)** · ❌ 0 · 🔁 0 · 🚫 0 · 🟡 1 cần chạy lại · ⚠️ 0 cần test · 🐞 0 chưa sửa · ⏳ 4 chờ · 🚗 0 chờ chạy lặp trên xe · 🟡 REPORTED 1 · ma trận chờ duyệt: không

> Sinh tự động lúc 2026-09-27 10:52:31 — **không sửa tay**. % an toàn = PASS ÷ mọi dòng test/REQ/bug đã xác nhận (REPORTED không tính). PASS chỉ từ lần chạy thật + (bug/REQ) test đã chứng minh ĐỎ.

**Bug không có test hồi quy nào chặn tái phát: 0** (0 chưa có test · 0 có test nhưng gate không chạy)

## 🚨 Cần xử lý (1)

| Trạng thái | ID | Tính năng / Bug | Component | Việc cần làm |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-DOCS-01 | repo consistency (documented counts, commands, links) | devkit-docs | code đổi sau lần PASS — chạy lại (suite nhẹ tự chạy nền; nặng: `postfix-gate --run-tests --full`) |

## 🧩 Phân hệ

### antigravity-pm-mcp — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-AUTO-ANTIGRAVITY-PM-MCP-01 | antigravity-pm-mcp: package.json test script | chưa chạy | cd antigravity-pm-mcp && npm test |

<details><summary>✅ devkit-all — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-ALL-01 | DevKit tests that name a changed file (code, templates, rules) + repo consistency; the full suite exceeds the 900 s gate limit | 2026-09-27 10:02:00 · 276.04s · exit 0 · a94c071+dirty · [log](evidence/REG-DK-ALL-01/20260927-100159.log) | bash universal-agent-devkit/tests/run_impacted.sh |

</details>

### devkit-docs — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| 🟡 CẦN CHẠY LẠI (code đã đổi) | REG-DK-DOCS-01 | repo consistency (documented counts, commands, links) | 2026-09-26 12:04:31 · 1.86s · exit 0 · f15393b+dirty · [log](evidence/REG-DK-DOCS-01/20260926-120431.log) | bash universal-agent-devkit/tests/test_repo_consistency.sh |

<details><summary>✅ devkit-gate — 2/2 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-GATE-01 | post-fix gate | 2026-09-27 10:02:00 · 54.77s · exit 0 · a94c071+dirty · [log](evidence/REG-DK-GATE-01/20260927-095236.log) | bash universal-agent-devkit/tests/test_postfix_gate.sh |
| ✅ PASS | REG-DK-GATE-02 | proof gate (tree_fp) | 2026-09-27 10:02:00 · 124.15s · exit 0 · a94c071+dirty · [log](evidence/REG-DK-GATE-02/20260927-095440.log) | bash universal-agent-devkit/tests/test_proof_gate.sh |

</details>

<details><summary>✅ devkit-health — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-HEALTH-01 | health | 2026-09-25 11:42:03 · 19.12s · exit 0 · 05ce90e+dirty · [log](evidence/REG-DK-HEALTH-01/20260925-112905.log) | bash universal-agent-devkit/tests/test_agent_health.sh |

</details>

<details><summary>✅ devkit-hooks — 2/2 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-HOOK-01 | hook contract | 2026-09-27 10:02:00 · 38.67s · exit 0 · a94c071+dirty · [log](evidence/REG-DK-HOOK-01/20260927-095519.log) | bash universal-agent-devkit/hooks/tests/hook_contract_test.sh |
| ✅ PASS | REG-DK-HOOK-02 | proof gate | 2026-09-27 10:02:00 · 124.30s · exit 0 · a94c071+dirty · [log](evidence/REG-DK-HOOK-02/20260927-095723.log) | bash universal-agent-devkit/tests/test_proof_gate.sh |

</details>

### play-store-mcp — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-AUTO-PLAY-STORE-MCP-01 | play-store-mcp: pytest | chưa chạy | cd play-store-mcp && uv run --frozen --extra dev pytest -q |

<details><summary>✅ workbench-agent-config — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-WB-CONFIG-01 | agent-kit health: every registered hook exists, imports resolve, context in sync | 2026-09-27 10:52:31 · 0.43s · exit 0 · 9d29ca8+dirty · [log](evidence/REG-WB-CONFIG-01/20260927-105231.log) | bash universal-agent-devkit/bin/agent-kit health -t . |

</details>

## 📒 Sổ tay bug (2)

| Trạng thái | Mã | Mô tả | Component | Test bảo vệ | Bằng chứng |
|---|---|---|---|---|---|
| ⏳ chưa chứng minh ĐỎ | BUG-20260925-prompt-bao-bug-that-cung-se-khong-con-du | prompt báo bug thật cũng sẽ không còn được ghi nhận nữa -> là sao bug đúng ko fix đi phải tự động ghi nhận chứ | - | REG-DK-ALL-01 | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20260927-100159.log) |
| ⏳ chưa chứng minh ĐỎ | BUG-20260926-dev-kit-lam-tao-branch-push-lung-tung-kh | dev kit làm tạo branch, push lung tung không đồng bộ dẫn tới lệch code, vd geely ex2 hiện có 2 pull chưa pull về dẫn tớ… | - | REG-DK-ALL-01, REG-DK-HOOK-01, REG-DK-HOOK-02, universal-agent-devkit/hooks/tests/hook_contract_test.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20260927-100159.log) |

## 🟡 REPORTED — bug báo qua prompt, chưa xác nhận (1)

> Chưa tính là bug. Xác nhận: `agent-kit bugs add "<tiêu đề>" --id <ID>` · có test ĐỎ→XANH: `agent-kit bugs link <ID> <TEST>` · không phải bug: `agent-kit bugs drop <ID>`

| ID | Prompt | Ngày |
|---|---|---|
| BUG-20260925-reader-office-dang-bi-ket-boi-1-agent-gr | reader office đang bị kẹt bởi 1 agent grok làm audit do dev kit lỗi ko? | 2026-09-25 08:41:07 |
