# #545 — PR chứng minh AC (sau PR #594)

PR #594 đã merge (954fd1cd). Cả 3 AC đã đúng trên origin/main 56ca38e3; PR này chép đủ dòng AC vào khối `sb:ac`.

- AC1: `python3 len()` trên 42 SKILL.md (universal-agent-devkit/skills + .claude/skills): lớn nhất 19381 (ui-ux-pro-max); super-qa 16447, super-review 17334, super-build 16351.
- AC2: phần tách nằm ở `.claude/skills/<skill>/references/`; SKILL.md dẫn chiếu; `super-board-skills-ready.py --hydrate` exit 0.
- AC3: `bash universal-agent-devkit/tests/verification/test_skill_size.sh` exit 0 ("42 SKILL.md checked, 0 over the limit"); đã khai báo ở `universal-agent-devkit/tests/impact_map.txt` dòng 59. RED trước khi cắt: xem QA v1 (`docs/super-board/runs/issue-545-qa-v1/summary.md`, exit 1 trên main cũ).
