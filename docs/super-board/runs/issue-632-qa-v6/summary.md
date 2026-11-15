# QA #632 v6 — PR #1186 @ b9171da0 (main đã gộp, up to date)

- test_verdict_seal.sh: exit 0 (gồm 3 ca TMPDIR = cha của repo thật; cũng exit 0 với `env -i PATH HOME`)
- test_gate_seal_required.sh: exit 0
- test_gate_seal_e2e.sh: exit 0
- test_verdict_seal_audit.sh: exit 0 (cả TMPDIR=/tmp)
- test_repo_consistency.sh: 28/28
- R1: verdict_seal.py:_under_tmp và push_gate.py:pm_home_test_fixture chỉ dùng TEST_TMP_ROOTS cố định
- R2/AC4: không còn ponytail ở push_gate.approved (ponytail còn lại ở push_gate.py:897 nói về merge sau audit, không liên quan)
- Gate: xem comment [qa] [report]
- Chưa kiểm: rule 20 (chủ repo cài khoá Keychain bằng sudo); Antigravity audit head mới
