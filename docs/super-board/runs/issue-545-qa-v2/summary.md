# QA v2 — thẻ #545, PR #602 (chạy trên nhánh đã merge origin/main)

Kiểm lại độc lập từng AC; không tin summary của Builder.

- AC1: `len()` UTF-8 trên 42 SKILL.md (universal-agent-devkit/skills + .claude/skills): lớn nhất 19381 (ui-ux-pro-max), 0 file ≥ 20000.
  Ba skill: super-qa 39708 → 16447, super-review 34014 → 17334, super-build 25649 → 16351 (so với fb9a4716^).
- AC2: mọi liên kết markdown trong 3 SKILL.md trỏ tới file có thật (kể cả `../super-board/references/`, `../super-qa/references/`); 0 liên kết hỏng.
  `super-board-skills-ready.py --lane qa --hydrate`: exit 0.
- AC3: RED — chép cây `fb9a4716^` vào thư mục tạm, chạy test_skill_size.sh: "42 SKILL.md checked, 3 over the limit" (FAIL cho super-build, super-qa, super-review).
  GREEN — trên nhánh: `bash universal-agent-devkit/tests/verification/test_skill_size.sh` exit 0, "42 SKILL.md checked, 0 over the limit".
  Khai báo: `universal-agent-devkit/tests/impact_map.txt` dòng 59 (`skills/*/SKILL.md   tests/verification/test_skill_size.sh`).

Local tests: bash universal-agent-devkit/tests/verification/test_skill_size.sh
Test gaps (not written): không có; PR #602 chỉ thêm file Markdown bằng chứng.
