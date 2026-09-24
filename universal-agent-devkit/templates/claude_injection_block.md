# Universal Agent DevKit Integration
This project is configured with Universal Agent DevKit standards:
- Central Engineering Rules & SSOT: @AGENTS.md
- Active Domain Profile: @.active-profile.json
- High-Performance & Security Standards: @rules/core-rules.md
- Post-Fix Verification Gate before handover: `postfix-gate --run-tests --full` (installed on PATH by `make install` in the DevKit; without it: `python3 <DevKit dir>/bin/post-fix-gate.py --run-tests --full`). `--run-tests` alone checks only the impacted tests — a fast check, not a handover. Exit `0` PASS · `1` REJECT: fix and rerun · `2` UNVERIFIED, `4` UNTESTED: stop and report CHƯA XONG with the gate's reason · `3` nothing to audit: no code changed, the gate does not apply.
