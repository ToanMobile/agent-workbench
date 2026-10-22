# QA #254 v1
- Test mới: `bash tests/super-board/test_builder_already_met_and_model_tier.sh` — trên file origin/main: FAIL 8/8 (RED); trên nhánh: PASS 8/8 (GREEN).
- Gate: `post-fix-gate.py --run-tests --full --diff origin/main --brief` sau khi merge origin/main vào nhánh — exit 0, 52/52 hồi quy PASS.
- Lần gate đầu REJECT 51/53 (nhánh cũ hơn main thiếu test_matrix_merge_driver.sh; REG-SB-RUNNER-RECLAIM-DEAD-BUILD-01 flake khi tải cao, chạy riêng 3/3 PASS). Không do diff PR.
- Hạn chế: test lối ra "already met" chỉ kiểm văn bản run.md/SKILL.md, không chạy builder thật.
