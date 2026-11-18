#!/usr/bin/env bash
# Regression #1266 (18/11): #1243 changed the backend profile's description in the kit but never committed the workbench's
# generated .agents/active-profile.json. Every DevKit install into a worktree rewrote it, every review tree was dirty, the
# Antigravity PM refused to record an audit scope (auditScopeOf: dirty tree => null; 74 review logs, 1 with a scope), and
# edited-test PRs could not be approved: reviewer no-op twice, card Blocked.
# Rule: the committed file matches what agent-config.py writes for its own profile (every field but updated_at/mcp_profile).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
kit = root / "universal-agent-devkit"
sys.path.insert(0, str(kit / "scripts" / "governance"))
from devkit_i18n import pick, set_lang  # same helper agent-config.py uses
cur = json.loads((root / ".agents" / "active-profile.json").read_text(encoding="utf-8"))
set_lang(cur.get("lang") or "vi")
meta = json.loads((kit / "profiles" / cur["profile"] / "profile.json").read_text(encoding="utf-8"))
want = {
    "profile": cur["profile"],
    "name": meta.get("name", cur["profile"].upper()),
    "description": pick(meta, "description"),
    "essential_mcps": meta.get("essential_mcps", []),
    "active_councils": meta.get("active_councils", []),
    "rules_file": meta.get("rules_file", ""),
    "regression_matrix": meta.get("regression_matrix", ""),
}
bad = [k for k, v in want.items() if cur.get(k) != v]
if bad:
    print("✖ .agents/active-profile.json is stale vs profiles/%s/profile.json: %s" % (cur["profile"], ", ".join(bad)))
    print("  fix: python3 universal-agent-devkit/bin/agent-config.py %s, then commit .agents/active-profile.json" % cur["profile"])
    sys.exit(1)
print("✔ committed .agents/active-profile.json matches the kit's %s profile" % cur["profile"])
PY
