#!/usr/bin/env python3
"""Test fixture: the first prompt of a super-board Codex lane, as .claude/bin/super-board-codex-lane.sh builds it for the build lane
(its f-string copied verbatim on 2026-10-25; only --root and the config path are fixed values). The prompt hook must read only the
card's own words in it (title, body), never the runner's fixed sentences.

Usage: codex_lane_prompt.py <title> <body> [<line 2>]   (an empty title leaves the key out, as a hydrated card without one;
a third argument replaces line 2, the skills-ready opener, for the "not a lane" controls)."""
import json
import sys

title, body = sys.argv[1], sys.argv[2]
card = {"number": 9, "status": "Ready", "labels": ["bug"], "body": body}
if title:
    card["title"] = title
root, config_path, skill, section, lane = "/repo", "/repo/.claude/super-board/configs/agent-workbench.json", "super-build", "Builder", "build"
skills = {"ready": True, "host": "codex", "entries": [{"name": "super-build", "status": "resolved",
                                                     "resolved_path": "/repo/.claude/skills/super-build/SKILL.md"}]}
prompt = f'''Run {skill} for issue #{card['number']} as a Codex lane worker.
First operation: recheck .claude/bin/super-board-skills-ready.py --root {root} --host codex --cards - --lane {lane} with the Card JSON below as a one-element stdin array, before worktree creation, classification or lifecycle writes. Exit 10 means status=halted, detail=skills-readiness:, preserve all state. Load resolved_path files and only declared fallback IDs from the report. Before activating any conditional helper, repeat with --require <exact-name>.
Resolved skill report: {json.dumps(skills)}
Config: {config_path}
Card: {json.dumps(card)}
Read .claude/skills/{skill}/SKILL.md and .claude/skills/super-board/references/run.md → {section} lifecycle; follow all its board, branch, worktree, comments, test and merge requirements.
Source .claude/bin/super-board-gh-guard.sh and use its quota checks. Required GitHub reads go through .claude/bin/super-board-github-read.py; a read that misses its --kind shape exits 64 for that call only and prints the valid form, so fix the read. Check --check before new writes, migrations and merges; exit 79 means status=halted, no more GitHub calls, preserve claims/worktree/card/approval. Never retry a mutation.
Use .claude/bin/super-board-card.sh for board reads/moves and .claude/bin/super-board-pr-body.sh for owned PR blocks; follow writing-standard.md and pr-author-notes.md.
Use your own worktree under .claude/worktrees/; never edit the main checkout. Clean up on ordinary exit, preserve work on halt/interruption.
Codex adaptation: do not launch Claude or other sub-agents. Perform preflight, classification, independent review and truth-check duties inline. This changes the execution host, never the evidence requirements, confidence threshold or merge policy.
Return JSON: status=advanced|bounced|blocked|human-gate|failed|halted; column=current board column; detail=one line; prUrl/branch when known, otherwise null; priorFindings=review counts or null. A non-advanced exit ends this card's lane chain. On merge-gate exit 9, return status=halted with detail starting exactly "verification-readiness:"; preserve work and never bounce/retry.
'''
prompt += '''Before creating any worktree or changing code, perform run.md's Builder pre-flight inline: call super-board-preflight.sh, judge its candidates semantically, and act on proceed/hold/sequence/skipped. Blind preflight leaves Ready and returns failed. Your own issue branch PR is not a duplicate. Read the issue and all comments; preserve qa/bug/feature labels. Existing docs/ux/tests/refactor/tech-debt rows keep their label chain: classify complexity without adding feature/bug. If truly untyped, classify feature or bug, re-run skills-ready on the proposed labelled card before adding that label, never qa. Then follow the Builder lifecycle.
'''
if len(sys.argv) > 3:
    head, _, rest = prompt.partition("\n")
    prompt = head + "\n" + sys.argv[3] + "\n" + rest.partition("\n")[2]
sys.stdout.write(prompt)
