# QA #549 v1 — head 0368055a

| Lệnh | Exit | Kết quả |
|---|---|---|
| `bash tests/super-board/test_host_detect.sh` | 0 | 9/9 ✔ (claude, codex, agy, ANTIGRAVITY_*, ưu tiên codex, host lạ → exit 64) |
| `bash tests/super-board/test_risk_door_blast.sh` | 0 | 5 tài liệu lane có Door + Blast radius; 7 SKILL.md < 20000 (lớn nhất super-review 17688) |
| `post-fix-gate.py --run-tests --brief` (sau merge origin/main) | 0 | hồi quy 5/5 |

RED trên base (origin/main):
- `SUPER_BOARD_HOST=agy` → exit 64 "must be claude or codex" (đáng lẽ in `agy`).
- `writing-standard.md`, `super-build/SKILL.md`: 0 lần "Blast radius".

Ảnh nghiệm thu: không cần (chỉ tài liệu và script shell).
