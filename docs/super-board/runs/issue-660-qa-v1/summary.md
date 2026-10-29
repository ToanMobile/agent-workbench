# QA #660 v1 (PR #664)

AC1: test_impacted_ambiguous_basename.sh voi DEVKIT_IMPACTED_DIRS=verification + DEVKIT_GATE_DONE dat san, chay qua tests/run_impacted.sh
- run_impacted.sh cua origin/main: rc=1 (DO)
- run_impacted.sh cua nhanh: rc=0 (XANH)
- chay test truc tiep, khong bien: exit 0

AC2: gate --scoped: REG-DK-ALL-REST-01 PASS (153/155 hoi quy dat).
Hai suite do: REG-SB-SETUP-BIN-01 (BIN thieu super-board-merge-cards.py) va
REG-SB-MERGE-TRAIN-01 (F4 no worker flag: exit 13). Nhanh chi doi universal-agent-devkit/tests/run_impacted.sh;
hai test do chay .claude/bin/* va tests/super-board/* ma PR khong dung, nen do san tren main.
Gate REJECT chi vi hai suite tren + run_impacted.sh la file test bi sua (can Antigravity audit duyet cheo).
