# QA #483 v1 — push_gate docs + câu khuyên --full

Kết luận: PASS (AC đạt; gate impacted đỏ do test đua thời gian, đỏ cả trên origin/main).

| AC | Kết quả | Bằng chứng |
|---|---|---|
| CHANGELOG có mục đổi hành vi push_gate, kèm lệnh bị từ chối và đường thay thế | ✅ | `universal-agent-devkit/CHANGELOG.md` mục Unreleased: 3 nhóm bị từ chối, đường thay thế cho từng nhóm |
| proof_gate.sh và `post-fix-gate.py --help` không còn khuyên task chạy `--full` | ✅ | grep cụm cũ ("full ngoài worktree", "Use --full before handover") ngoài CHANGELOG: 0 kết quả; `--help` in câu mới; `bash -n proof_gate.sh` ok |

Diff: 3 file (CHANGELOG, help string, 1 dòng nhắc trong proof_gate.sh). Không đụng logic, không có test nào kiểm câu chữ cũ.

Gate impacted (`post-fix-gate.py --run-tests --brief`) trên nhánh đã merge origin/main, 2 lần: exit 1, 16/17.
- Lần 1: REG-DK-ALL-01 TIMEOUT (HANG) ở `tests/gates/test_tlimit_signal.sh`; chạy riêng PASS 1,3 s.
- Lần 2: REG-DK-ALL-01 FAIL ở `tests/gates/test_gate_stop_reuse_race.sh` ("A waited=no re-used=no").
- `test_gate_stop_reuse_race.sh` chạy riêng trên nhánh: 1-2 FAILED mỗi lần; trên bản `origin/main` sạch: 1 FAILED ở 2/3 lần. Đỏ sẵn trên base, không do PR này.
