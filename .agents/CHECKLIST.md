# 🧪 Regression Checklist

**An toàn 32% (8/25)** · ❌ 14 · 🔁 0 · 🚫 0 · 🟡 0 cần chạy lại · ⚠️ 33 cần test · ⚠️ 50 test có thể không suite nào chạy · 🐞 0 chưa sửa · ⏳ 3 chờ · 🚗 0 chờ chạy lặp trên xe · 🟡 REPORTED 1 · ma trận chờ duyệt: có

> Sinh tự động lúc 2026-10-02 16:26:49 — **không sửa tay**. % an toàn = PASS ÷ mọi dòng test/REQ/bug đã xác nhận (REPORTED không tính). PASS chỉ từ lần chạy thật + (bug/REQ) test đã chứng minh ĐỎ.

**Bug không có test hồi quy nào chặn tái phát: 0** (0 chưa có test · 0 có test nhưng gate không chạy)

## 🚨 Cần xử lý (97)

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
| ❌ FAIL | BUG-20261002-evidence-gate-foreign-xml-nonrunner | test_evidence_gate: a Bash that only names a foreign project (cd && git status) made its fresh XML count as this session's test evidence | devkit | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-20261002-proof-gate-reinit-same-profile | proof gate: re-init rewriting the same backend profile counted as a profile switch and demanded a PNG | devkit | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | BUG-VACUITY-SINCE-BASE | gate: vacuity revert uses HEAD under --since, so committed fixes look vacuous | - | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | REG-DK-ALL-01 | DevKit tests that name a changed file (code, templates, rules) + repo consistency; the full suite exceeds the 900 s gate limit | devkit-all | sửa code/test rồi chạy lại — xem log |
| ❌ FAIL | REG-WB-CONFIG-01 | agent-kit health: every registered hook exists, imports resolve, context in sync | workbench-agent-config | sửa code/test rồi chạy lại — xem log |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/antigravity-pm-mcp/tests/audit-23-09.test.js | mcp-servers/antigravity-pm-mcp/tests/audit-23-09.test.js | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/antigravity-pm-mcp/tests/bai-hoc-14-09.test.js | mcp-servers/antigravity-pm-mcp/tests/bai-hoc-14-09.test.js | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/antigravity-pm-mcp/tests/base-commit.test.js | mcp-servers/antigravity-pm-mcp/tests/base-commit.test.js | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/antigravity-pm-mcp/tests/cam-dung-theo-task.test.js | mcp-servers/antigravity-pm-mcp/tests/cam-dung-theo-task.test.js | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/antigravity-pm-mcp/tests/config-prompt.test.js | mcp-servers/antigravity-pm-mcp/tests/config-prompt.test.js | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/antigravity-pm-mcp/tests/de-xuat-pm-geely.test.js | mcp-servers/antigravity-pm-mcp/tests/de-xuat-pm-geely.test.js | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/antigravity-pm-mcp/tests/de-xuat-pm-unity.test.js | mcp-servers/antigravity-pm-mcp/tests/de-xuat-pm-unity.test.js | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/antigravity-pm-mcp/tests/evidence.test.js | mcp-servers/antigravity-pm-mcp/tests/evidence.test.js | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/antigravity-pm-mcp/tests/gate.test.js | mcp-servers/antigravity-pm-mcp/tests/gate.test.js | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/antigravity-pm-mcp/tests/plan-by-pm.test.js | mcp-servers/antigravity-pm-mcp/tests/plan-by-pm.test.js | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/antigravity-pm-mcp/tests/policy.test.js | mcp-servers/antigravity-pm-mcp/tests/policy.test.js | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/antigravity-pm-mcp/tests/projects.test.js | mcp-servers/antigravity-pm-mcp/tests/projects.test.js | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/antigravity-pm-mcp/tests/prompt-rules.test.js | mcp-servers/antigravity-pm-mcp/tests/prompt-rules.test.js | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/antigravity-pm-mcp/tests/proof-target.test.js | mcp-servers/antigravity-pm-mcp/tests/proof-target.test.js | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/antigravity-pm-mcp/tests/proof.test.js | mcp-servers/antigravity-pm-mcp/tests/proof.test.js | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/antigravity-pm-mcp/tests/workflow.test.js | mcp-servers/antigravity-pm-mcp/tests/workflow.test.js | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_apk_manager_script.py | mcp-servers/play-store-mcp/tests/test_apk_manager_script.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_app_recovery.py | mcp-servers/play-store-mcp/tests/test_app_recovery.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_audit_fixes.py | mcp-servers/play-store-mcp/tests/test_audit_fixes.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_client.py | mcp-servers/play-store-mcp/tests/test_client.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_client_extended.py | mcp-servers/play-store-mcp/tests/test_client_extended.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_crashlytics.py | mcp-servers/play-store-mcp/tests/test_crashlytics.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_credential_handling.py | mcp-servers/play-store-mcp/tests/test_credential_handling.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_credentials_endpoint.py | mcp-servers/play-store-mcp/tests/test_credentials_endpoint.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_data_safety.py | mcp-servers/play-store-mcp/tests/test_data_safety.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_device_tier_configs.py | mcp-servers/play-store-mcp/tests/test_device_tier_configs.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_edit_uploads.py | mcp-servers/play-store-mcp/tests/test_edit_uploads.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_external_transactions.py | mcp-servers/play-store-mcp/tests/test_external_transactions.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_generated_apks.py | mcp-servers/play-store-mcp/tests/test_generated_apks.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_http_auth.py | mcp-servers/play-store-mcp/tests/test_http_auth.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_inappproducts.py | mcp-servers/play-store-mcp/tests/test_inappproducts.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_integration.py | mcp-servers/play-store-mcp/tests/test_integration.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_integration_credentials.py | mcp-servers/play-store-mcp/tests/test_integration_credentials.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_internal_app_sharing.py | mcp-servers/play-store-mcp/tests/test_internal_app_sharing.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_listing_images.py | mcp-servers/play-store-mcp/tests/test_listing_images.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_live_api.py | mcp-servers/play-store-mcp/tests/test_live_api.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_models.py | mcp-servers/play-store-mcp/tests/test_models.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_onetimeproduct_offers.py | mcp-servers/play-store-mcp/tests/test_onetimeproduct_offers.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_onetimeproducts.py | mcp-servers/play-store-mcp/tests/test_onetimeproducts.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_product_purchases.py | mcp-servers/play-store-mcp/tests/test_product_purchases.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_purchase_management.py | mcp-servers/play-store-mcp/tests/test_purchase_management.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_read_only.py | mcp-servers/play-store-mcp/tests/test_read_only.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_read_siblings.py | mcp-servers/play-store-mcp/tests/test_read_siblings.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_server.py | mcp-servers/play-store-mcp/tests/test_server.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_server_extended.py | mcp-servers/play-store-mcp/tests/test_server_extended.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_subscription_baseplans.py | mcp-servers/play-store-mcp/tests/test_subscription_baseplans.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_subscription_catalog.py | mcp-servers/play-store-mcp/tests/test_subscription_catalog.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_subscription_offers.py | mcp-servers/play-store-mcp/tests/test_subscription_offers.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_system_apks.py | mcp-servers/play-store-mcp/tests/test_system_apks.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ test có thể không suite nào chạy | ORPHAN_TEST:mcp-servers/play-store-mcp/tests/test_users_grants.py | mcp-servers/play-store-mcp/tests/test_users_grants.py | - | dò lệnh suite không thấy suite nào chạy test này (có thể sai) — kiểm lại; nếu đúng: gọi nó trong lệnh / script của một suite ma trận, hoặc thêm thư mục của nó vào watch_files của suite chạy nó |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/antigravity-pm-mcp/bin/antigravity-pm-mcp.js | mcp-servers/antigravity-pm-mcp/bin/antigravity-pm-mcp.js | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/antigravity-pm-mcp/src/agentapi.js | mcp-servers/antigravity-pm-mcp/src/agentapi.js | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/antigravity-pm-mcp/src/cite-check.js | mcp-servers/antigravity-pm-mcp/src/cite-check.js | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/antigravity-pm-mcp/src/config.js | mcp-servers/antigravity-pm-mcp/src/config.js | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/antigravity-pm-mcp/src/discover.js | mcp-servers/antigravity-pm-mcp/src/discover.js | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/antigravity-pm-mcp/src/dispatch-guard.js | mcp-servers/antigravity-pm-mcp/src/dispatch-guard.js | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/antigravity-pm-mcp/src/evidence.js | mcp-servers/antigravity-pm-mcp/src/evidence.js | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/antigravity-pm-mcp/src/lint-diff.js | mcp-servers/antigravity-pm-mcp/src/lint-diff.js | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/antigravity-pm-mcp/src/oracle.js | mcp-servers/antigravity-pm-mcp/src/oracle.js | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/antigravity-pm-mcp/src/plan-review.js | mcp-servers/antigravity-pm-mcp/src/plan-review.js | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/antigravity-pm-mcp/src/policy.js | mcp-servers/antigravity-pm-mcp/src/policy.js | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/antigravity-pm-mcp/src/projects.js | mcp-servers/antigravity-pm-mcp/src/projects.js | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/antigravity-pm-mcp/src/prompt.js | mcp-servers/antigravity-pm-mcp/src/prompt.js | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/antigravity-pm-mcp/src/proof-target.js | mcp-servers/antigravity-pm-mcp/src/proof-target.js | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/antigravity-pm-mcp/src/proof.js | mcp-servers/antigravity-pm-mcp/src/proof.js | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/antigravity-pm-mcp/src/report.js | mcp-servers/antigravity-pm-mcp/src/report.js | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/antigravity-pm-mcp/src/server.js | mcp-servers/antigravity-pm-mcp/src/server.js | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/antigravity-pm-mcp/src/tasks.js | mcp-servers/antigravity-pm-mcp/src/tasks.js | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/antigravity-pm-mcp/src/tools.js | mcp-servers/antigravity-pm-mcp/src/tools.js | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/antigravity-pm-mcp/src/util.js | mcp-servers/antigravity-pm-mcp/src/util.js | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/antigravity-pm-mcp/src/worktree.js | mcp-servers/antigravity-pm-mcp/src/worktree.js | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/play-store-mcp/examples/update_credentials.py | mcp-servers/play-store-mcp/examples/update_credentials.py | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/play-store-mcp/src/play_store_mcp/__init__.py | mcp-servers/play-store-mcp/src/play_store_mcp/__init__.py | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/play-store-mcp/src/play_store_mcp/__main__.py | mcp-servers/play-store-mcp/src/play_store_mcp/__main__.py | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/play-store-mcp/src/play_store_mcp/analytics_client.py | mcp-servers/play-store-mcp/src/play_store_mcp/analytics_client.py | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/play-store-mcp/src/play_store_mcp/bigquery_client.py | mcp-servers/play-store-mcp/src/play_store_mcp/bigquery_client.py | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/play-store-mcp/src/play_store_mcp/client.py | mcp-servers/play-store-mcp/src/play_store_mcp/client.py | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/play-store-mcp/src/play_store_mcp/crashlytics_client.py | mcp-servers/play-store-mcp/src/play_store_mcp/crashlytics_client.py | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/play-store-mcp/src/play_store_mcp/credentials.py | mcp-servers/play-store-mcp/src/play_store_mcp/credentials.py | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/play-store-mcp/src/play_store_mcp/errors.py | mcp-servers/play-store-mcp/src/play_store_mcp/errors.py | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/play-store-mcp/src/play_store_mcp/models.py | mcp-servers/play-store-mcp/src/play_store_mcp/models.py | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/play-store-mcp/src/play_store_mcp/reporting_client.py | mcp-servers/play-store-mcp/src/play_store_mcp/reporting_client.py | - | file code chưa có test — gắn test (`regression_checklist.py link`) |
| ⚠️ chưa có test | UNCOVERED:mcp-servers/play-store-mcp/src/play_store_mcp/server.py | mcp-servers/play-store-mcp/src/play_store_mcp/server.py | - | file code chưa có test — gắn test (`regression_checklist.py link`) |

## 🧩 Phân hệ

### antigravity-pm-mcp — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-AUTO-ANTIGRAVITY-PM-MCP-01 | antigravity-pm-mcp: package.json test script | chưa chạy | cd antigravity-pm-mcp && npm test |

### core — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-01 | core tests | chưa chạy | echo FULL_TEST_EXECUTED |

### devkit-all — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ❌ FAIL | REG-DK-ALL-01 | DevKit tests that name a changed file (code, templates, rules) + repo consistency; the full suite exceeds the 900 s gate limit | 2026-10-02 16:10:23 · 365.56s · exit 1 · cf9ef39+dirty · [log](evidence/REG-DK-ALL-01/20261002-161020.log) | bash universal-agent-devkit/tests/run_impacted.sh |

<details><summary>✅ devkit-gate — 2/2 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-GATE-01 | post-fix gate | 2026-10-02 16:10:23 · 74.61s · exit 0 · cf9ef39+dirty · [log](evidence/REG-DK-GATE-01/20261002-160038.log) | bash universal-agent-devkit/tests/test_postfix_gate.sh |
| ✅ PASS | REG-DK-GATE-02 | proof gate (tree_fp) | 2026-10-02 16:10:23 · 141.72s · exit 0 · cf9ef39+dirty · [log](evidence/REG-DK-GATE-02/20261002-160300.log) | bash universal-agent-devkit/tests/test_proof_gate.sh |

</details>

<details><summary>✅ devkit-health — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-HEALTH-01 | health | 2026-10-02 16:10:23 · 15.39s · exit 0 · cf9ef39+dirty · [log](evidence/REG-DK-HEALTH-01/20261002-160407.log) | bash universal-agent-devkit/tests/test_agent_health.sh |

</details>

<details><summary>✅ devkit-hooks — 2/2 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-HOOK-01 | hook contract | 2026-10-02 16:10:23 · 51.53s · exit 0 · cf9ef39+dirty · [log](evidence/REG-DK-HOOK-01/20261002-160352.log) | bash universal-agent-devkit/hooks/tests/hook_contract_test.sh |
| ✅ PASS | REG-DK-HOOK-02 | proof gate | 2026-10-02 16:10:23 · 141.72s · exit 0 · cf9ef39+dirty · [log](evidence/REG-DK-GATE-02/20261002-160300.log) | bash universal-agent-devkit/tests/test_proof_gate.sh |

</details>

<details><summary>✅ devkit-session-lock — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-SESSION-01 | session lock + multi-session gate verdict (own session is never counted as another) | 2026-10-02 16:10:23 · 4.12s · exit 0 · cf9ef39+dirty · [log](evidence/REG-DK-SESSION-01/20261002-160411.log) | bash universal-agent-devkit/tests/test_session_lock.sh && bash universal-agent-devkit/tests/test_multi_session_gate.sh |

</details>

<details><summary>✅ devkit-token-cost — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-COST-01 | token cost tracker counts each message id once and prices the longest model key | 2026-10-02 16:10:23 · 0.29s · exit 0 · cf9ef39+dirty · [log](evidence/REG-DK-COST-01/20261002-160414.log) | bash universal-agent-devkit/tests/test_token_cost_tracker.sh |

</details>

<details><summary>✅ devkit-worktree-sandbox — 1/1 PASS</summary>

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ✅ PASS | REG-DK-SANDBOX-01 | worktree sandbox cleanup keeps unmerged work unless --force | 2026-10-02 16:10:23 · 2.54s · exit 0 · cf9ef39+dirty · [log](evidence/REG-DK-SANDBOX-01/20261002-160414.log) | bash universal-agent-devkit/tests/test_worktree_sandbox.sh |

</details>

### play-store-mcp — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ⏳ chưa chạy | REG-AUTO-PLAY-STORE-MCP-01 | play-store-mcp: pytest | chưa chạy | cd play-store-mcp && uv run --frozen --extra dev pytest -q |

### workbench-agent-config — 0/1 PASS

| Trạng thái | ID | Tên | Chữ ký lần chạy (thời điểm · thời lượng · exit · commit · log) | Lệnh / Test |
|---|---|---|---|---|
| ❌ FAIL | REG-WB-CONFIG-01 | agent-kit health: every registered hook exists, imports resolve, context in sync | 2026-10-02 16:10:23 · 1.06s · exit 1 · cf9ef39+dirty · [log](evidence/REG-WB-CONFIG-01/20261002-161021.log) | bash universal-agent-devkit/bin/agent-kit health -t . |

## 📒 Sổ tay bug (12)

| Trạng thái | Mã | Mô tả | Component | Test bảo vệ | Bằng chứng |
|---|---|---|---|---|---|
| ❌ FAIL | BUG-20260925-prompt-bao-bug-that-cung-se-khong-con-du | prompt báo bug thật cũng sẽ không còn được ghi nhận nữa -> là sao bug đúng ko fix đi phải tự động ghi nhận chứ | - | REG-DK-ALL-01 | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261002-161020.log) |
| ❌ FAIL | BUG-20260926-dev-kit-lam-tao-branch-push-lung-tung-kh | dev kit làm tạo branch, push lung tung không đồng bộ dẫn tới lệch code, vd geely ex2 hiện có 2 pull chưa pull về dẫn tớ… | - | REG-DK-ALL-01, REG-DK-HOOK-01, REG-DK-HOOK-02, universal-agent-devkit/hooks/tests/hook_contract_test.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261002-161020.log) |
| ❌ FAIL | BUG-20260928-audit-review-them-geely-ex2-hien-no-bao | audit, review thêm geely ex2 hiện nó báo tôi rất nhiều lỗi vậy có nghĩa là bộ devkit hoàn toàn chất lượng kém để thủng… | - | REG-DK-ALL-01, universal-agent-devkit/tests/test_gate_friction.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261002-161020.log) |
| ❌ FAIL | BUG-20260928-fix-luon-loi-git-guard-chan-grep-di-ngoa | fix luôn lỗi git guard chặn grep đi ngoài ra đã tối ưu token sử dụng cũng như thời gian chạy chưa ? Đề xuất các phương… | - | REG-DK-ALL-01, universal-agent-devkit/tests/test_gate_friction.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261002-161020.log) |
| ❌ FAIL | BUG-20260928-push-geely-va-fix-luon-loi-red-proof | push geely và fix luôn lỗi red_proof | - | REG-DK-ALL-01, universal-agent-devkit/tests/test_red_proof.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261002-161020.log) |
| ❌ FAIL | BUG-20260928-san-check-luon-chat-luong-dev-kit-workfl | sẵn check luôn chất lượng dev kit workflow có bị lỗi gì ko fix luôn đi | - | REG-DK-ALL-01, universal-agent-devkit/tests/test_gate_friction.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261002-161020.log) |
| ❌ FAIL | BUG-20260929-audit-review-nguyen-nhan-tai-sao-cac-ses | audit, review nguyên nhân tại sao các sesion cài dev kit chạy rất chậm có lỗi gì hay ko? | - | REG-DK-ALL-01, universal-agent-devkit/tests/test_regression_gate_hook.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261002-161020.log) |
| ❌ FAIL | BUG-20261001-lam-luon-fix-bug-worktree-di | làm luôn fix bug worktree đi | - | REG-DK-ALL-01, universal-agent-devkit/tests/test_worktree_merge_gate.sh (trong suite) | RED-proof INCONCLUSIVE: [log](evidence/redproof-BUG-20261001-lam-luon-fix-bug-worktree-di/20261001-175745.log) |
| ❌ FAIL | BUG-20261001-sua-luon-bug-init-xoa-mcp-server-di | sửa luôn bug init xoá MCP server đi | - | REG-DK-ALL-01, universal-agent-devkit/tests/test_platform_rules.sh (trong suite) | RED-proof INCONCLUSIVE: [log](evidence/redproof-BUG-20261001-sua-luon-bug-init-xoa-mcp-server-di/20261001-192737.log) |
| ❌ FAIL | BUG-20261002-evidence-gate-foreign-xml-nonrunner | test_evidence_gate: a Bash that only names a foreign project (cd && git status) made its fresh XML count as this session's test evidence | devkit | REG-DK-ALL-01, REG-DK-HOOK-01, REG-DK-HOOK-02, universal-agent-devkit/hooks/tests/hook_contract_test.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261002-161020.log) |
| ❌ FAIL | BUG-20261002-proof-gate-reinit-same-profile | proof gate: re-init rewriting the same backend profile counted as a profile switch and demanded a PNG | devkit | REG-DK-ALL-01, universal-agent-devkit/tests/test_proof_gate.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261002-161020.log) |
| ❌ FAIL | BUG-VACUITY-SINCE-BASE | gate: vacuity revert uses HEAD under --since, so committed fixes look vacuous | - | REG-DK-ALL-01, universal-agent-devkit/tests/test_vacuity_since.sh (trong suite) | [log REG-DK-ALL-01](evidence/REG-DK-ALL-01/20261002-161020.log) |

## 🟡 REPORTED — bug báo qua prompt, chưa xác nhận (1)

> Chưa tính là bug. Xác nhận: `agent-kit bugs add "<tiêu đề>" --id <ID>` · có test ĐỎ→XANH: `agent-kit bugs link <ID> <TEST>` · không phải bug: `agent-kit bugs drop <ID>`

| ID | Prompt | Ngày |
|---|---|---|
| BUG-20261002-chay-finagling-running-stop-hooks-8-9-27 | chạy Finagling… (running Stop hooks… 8/9 · 27m 24s · ↓ 46.3k tokens) quá lâu audit, review sửa lại đi Stop hooks… rất h… | 2026-10-02 16:26:49 |
