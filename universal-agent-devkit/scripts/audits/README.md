# DevKit Audits & Governance Verifiers

Bộ công cụ kiểm toán độc lập (Audit & Verification Suite) nhằm đánh giá chất lượng toàn diện của mã nguồn, quy tắc, skills, và cơ chế an toàn:

- `adversarial_chaos_test_10_agents.py`: Chaos test tấn công đối kháng 10 kịch bản giả mạo kết quả test / receipt.
- `audit_agent_perfection_50_agents.py`: Kiểm toán 50 tiêu chí hoàn thiện Agent theo 10 hội đồng thẩm định.
- `audit_production_lifecycle_50_agents.py`: Kiểm toán vòng đời sản phẩm, tài nguyên, coroutines và leak memory.
- `audit_test_suite_50_agents.py`: Kiểm toán độ tin cậy và phân vùng kiểm thử (Paired Executable Oracle).
- `audit_workflows_rules_skills_50_agents.py`: Kiểm toán toàn vẹn quy tắc, profile isolation, và YAML frontmatter.
- `audit_zero_regression_10_agents.py`: Kiểm toán cơ chế chặn lỗi hồi quy (zero-regression gate).
