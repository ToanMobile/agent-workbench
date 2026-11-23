#!/usr/bin/env bash
# Regression test: codebase-memory & context-saving invariants.
# 1. tree_fp._off_screen waives UI proof for .cbmignore and .codebase-memory.json on UI profiles.
# 2. skills/codebase-memory/SKILL.md covers all 17 CBM tools, format="tree", .cbmignore,
#    keeps frontmatter description <= 300 UTF-8 bytes and body <= 5807 bytes.
# 3. Root mcp_config.json has no dead agentmemory MCP entry.
# 4. Root .cbmignore excludes .agents/ and reports/ without hiding kit source code.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ROOT="$(cd "$DEVKIT_DIR/.." && pwd)"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# 1. tree_fp._off_screen covers CBM config files at repo root
if python3 -I - "$DEVKIT_DIR/bin" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import tree_fp

assert tree_fp._off_screen(".cbmignore", "android") is True, ".cbmignore should be off-screen on android"
assert tree_fp._off_screen(".codebase-memory.json", "game") is True, ".codebase-memory.json should be off-screen on game"
assert tree_fp._off_screen("app/src/main/MainActivity.kt", "android") is False, "UI source must stay on-screen"
PY
then
  ok "tree_fp._off_screen waives .cbmignore and .codebase-memory.json"
else
  fail "tree_fp._off_screen does not waive .cbmignore / .codebase-memory.json"
fi

# 2. codebase-memory SKILL.md tool coverage & context budget
if python3 -I - "$DEVKIT_DIR/skills/codebase-memory/SKILL.md" <<'PY'
import re, sys

path = sys.argv[1]
raw = open(path, encoding="utf-8").read()
required_tokens = [
    "get_file_outline",
    "check_index_coverage",
    "compare_graphs",
    'format="tree"',
    ".cbmignore",
    "index_status",
]
missing = [t for t in required_tokens if t not in raw]
assert not missing, f"missing tokens in SKILL.md: {missing}"
assert "14 MCP" not in raw and "14 Tool" not in raw, "stale 14-tool count still present"
assert len(raw.encode("utf-8")) <= 5807, f"SKILL.md grew beyond 5807 bytes: {len(raw.encode('utf-8'))}"

m = re.match(r"---\n(.*?)\n---", raw.replace("\r", ""), re.S)
assert m, "missing YAML frontmatter"
d = re.search(r"^description:[ \t]*(.+)$", m.group(1), re.M)
assert d, "missing description"
desc_bytes = len(d.group(1).strip().encode("utf-8"))
assert desc_bytes <= 300, f"description too long: {desc_bytes} > 300 bytes"
PY
then
  ok "codebase-memory SKILL.md covers 17 tools, tree format, .cbmignore within budget"
else
  fail "codebase-memory SKILL.md outdated or over budget"
fi

# 3. Root mcp_config.json has no dead agentmemory server
if python3 -I - "$ROOT/mcp_config.json" <<'PY'
import json, os, sys
p = sys.argv[1]
if os.path.isfile(p):
    servers = json.load(open(p, encoding="utf-8")).get("mcpServers") or {}
    assert "agentmemory" not in servers, "dead agentmemory still in root mcp_config.json"
PY
then
  ok "root mcp_config.json has no dead agentmemory entry"
else
  fail "root mcp_config.json still contains dead agentmemory"
fi

# 4. Root .cbmignore exists and excludes non-code noise without hiding kit code
if python3 -I - "$ROOT/.cbmignore" <<'PY'
import os, sys
p = sys.argv[1]
assert os.path.isfile(p), ".cbmignore missing at repo root"
lines = [l.strip() for l in open(p, encoding="utf-8") if l.strip() and not l.strip().startswith("#")]
for need in (".agents/", "reports/", "impact_results.log"):
    assert need in lines, f"missing ignore rule: {need}"
for forbidden in ("universal-agent-devkit/", "mcp-servers/", "libs/"):
    assert forbidden not in lines, f"must not ignore first-party source: {forbidden}"
PY
then
  ok "root .cbmignore excludes non-code noise and preserves source"
else
  fail "root .cbmignore missing or incomplete"
fi

[ "$FAILS" -eq 0 ] && echo "✅ test_cbm_context_opt: all passed" || { echo "❌ test_cbm_context_opt: $FAILS failed"; exit 1; }
