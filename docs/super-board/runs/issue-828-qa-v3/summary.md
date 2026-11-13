# QA #828 vòng 3 — head eae4dc2e (đã chứa origin/main 3a995cb7)

- Lệnh: `bash universal-agent-devkit/tests/installer/test_agent_health_kit_overwritten.sh`
- GREEN trên head: exit 0, "all passed" (R1 index thiếu/symlink, R2 `git commit -- <path>` thật, R3 hook unset biến thừa kế).
- RED: thay `agent-health.py` bằng bản origin/main thì exit 1, 2 ca đỏ: "a kit file staged in the commit's temp index is reported (#828)" và "real pathspec commit: the committed kit file was reported (R2)"; khôi phục thì XANH.
- Ca #462 giữ nguyên: file kit sửa ngoài lần commit vẫn đỏ (test "stray edit still goes red").
- Security pass trên diff: DEVKIT_PRECOMMIT_INDEX chỉ được tin khi là file thường, không symlink, nằm trong git dir của kit; không có finding.
- Không phải UI, không có ảnh.
