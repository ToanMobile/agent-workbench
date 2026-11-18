# QA #1295 v2 — PR #1297, head 791d83e7 (đã gộp origin/main, "Already up to date")

| AC | Lệnh | Exit |
|---|---|---|
| A/B/C (+D cold restart, E blocked) | bash tests/super-board/test_runner_self_reload_catchup_ff.sh | 0 (all passed) |
| 3 test self_reload cũ | test_runner_self_reload_absorbed_ff.sh / _absorbed.sh / test_runner_self_reload.sh | 0 / 0 / 0 |
| Scoped gate | post-fix-gate.py --run-tests --scoped --brief --json (qa-exit2.sh) | xem comment QA |

Không sửa test cũ; không có ảnh (không UI).
