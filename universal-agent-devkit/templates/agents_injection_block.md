# Universal Agent DevKit
Loaded at every session start. Claude Code and Gemini CLI expand the `@` lines. Grok, Codex and Cursor read this same file: open each path after the @ before any work. Grok has no separate directory.
- DevKit essentials (always apply): @.agents/context/essentials.md
- Domain profile rules: @.agents/context/profile-rules.md
- Project rules index (`.agents/local/rules/`): @.agents/context/rules-index.md

On demand — everything agent-related lives in `.agents/`: master rules `.agents/devkit/AGENTS.md` · engineering standards `.agents/devkit/rules/core-rules.md` · skills `.agents/skills/` · traps from past bugs `.agents/instincts.md` · profile `.agents/active-profile.json`.
<<<<<<< HEAD
Post-fix gate: `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full` — only exit `0` counts as PASS. Every prompt also attaches a real device proof PNG from this turn before the reply may open with XONG. Standing text: the top of this file and `.agents/context/essentials.md` ("Every prompt"). A serial in `.adb-denylist`, or forbidden by a project rule, is never captured.
=======
Post-fix gate before handover: `postfix-gate --run-tests --full` (or `python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full`). `--run-tests` alone checks only the impacted tests — a fast check, not a handover. Exit `0` PASS · `1` REJECT: fix and rerun · `2` UNVERIFIED, `4` UNTESTED: stop and report CHƯA XONG with the gate's reason · `3` nothing to audit: no code changed, the gate does not apply.
>>>>>>> eda06e8c15410069033dd2c274ef19bcc0f5035a
