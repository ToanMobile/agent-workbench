# QA #1285 (PR #1286) — pass

Base: origin/main merged (already up to date). Head tested: 68bc2bf8.

| Lệnh | Exit | Kết quả |
|---|---|---|
| bash tests/super-board/test_runner_self_reload_absorbed_ff.sh | 0 | A, B, C đều ✔ |
| bash tests/super-board/test_runner_self_reload.sh | 0 | all passed |
| bash tests/super-board/test_runner_self_reload_absorbed.sh | 0 | all passed |
| post-fix-gate.py --run-tests --scoped --brief --json (qua super-board-qa-exit2.sh) | 0 | `pass` |

RED trên runner gốc (origin/main): case A fail
`exec=1 head=fa36398 origin=bf2c899 st= M .claude/bin/super-board-run.sh`; B, C vẫn ✔.
Runner của PR: A ✔ (HEAD == origin/main, cây sạch).

AC: 4/4 đạt. Log thô ở /tmp/qa-agent-workbench-1285-*.log (không commit).
