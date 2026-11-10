#!/usr/bin/env bash
# Regression test (#860): claude_memory.py --check-index reports a MEMORY.md that Claude Code
# would cut when it loads the index at session start.
#  - the load limit is 25,000 UTF-16 code units (not bytes) or 200 lines; the cut is by whole line
#  - a line over 200 chars is reported too (the warning text of Claude Code asks for <= ~200)
#  - violation: exit 1 and names the line; clean index: exit 0 and prints nothing
#  - the old --check keeps its behaviour (exit 1 without autoMemoryDirectory in the project)
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$DEVKIT_DIR/scripts/governance/claude_memory.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

mk() {  # mk <name> -> project dir with an empty claude-auto folder
  local p="$TMP/$1"; mkdir -p "$p/.agents/local/memory/claude-auto"; echo "$p"
}
idx() { echo "$1/.agents/local/memory/claude-auto/MEMORY.md"; }
run() { python3 "$TOOL" "$1" --check-index 2>&1; }

# 1. ASCII, 26 KB, short lines -> over the unit limit
P=$(mk ascii)
python3 - "$(idx "$P")" <<'EOF'
import sys
open(sys.argv[1], "w").write("".join("- [n%03d](n%03d.md) — %s\n" % (i, i, "x" * 150) for i in range(150)))
EOF
out=$(run "$P"); rc=$?
[ "$rc" -eq 1 ] && ok "26 KB ASCII index: exit 1" || fail "26 KB ASCII index: exit $rc (want 1)"
echo "$out" | grep -q "MEMORY.md" && echo "$out" | grep -Eq "line [0-9]+" \
  && ok "26 KB ASCII index: names MEMORY.md and the first cut line" || fail "report lacks file/line: $out"

# 2. one 250-char line, file far under the limit
P=$(mk longline)
python3 - "$(idx "$P")" <<'EOF'
import sys
lines = ["- [a](a.md) — short\n"] * 3 + ["- [b](b.md) — " + "y" * 235 + "\n"] + ["- [c](c.md) — short\n"]
open(sys.argv[1], "w").write("".join(lines))
EOF
out=$(run "$P"); rc=$?
[ "$rc" -eq 1 ] && ok "250-char line: exit 1" || fail "250-char line: exit $rc (want 1)"
echo "$out" | grep -Eq "line 4\b" && ok "250-char line: reports line 4" || fail "wrong line reported: $out"

# 3. Vietnamese text: many bytes but under 25,000 UTF-16 units and 200 lines -> clean
P=$(mk viet-ok)
python3 - "$(idx "$P")" <<'EOF'
import sys
line = "- [n](n.md) — " + "Tiếng Việt ưu ộ ữ " * 8
line = line[:150]
open(sys.argv[1], "w").write((line + "\n") * 150)   # 150 lines, ~22.5k units, ~33k bytes
EOF
bytes=$(wc -c < "$(idx "$P")")
out=$(run "$P"); rc=$?
[ "$bytes" -gt 25000 ] || fail "fixture must exceed 25000 bytes (got $bytes)"
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "Vietnamese index over 25000 bytes but under 25000 units: exit 0, silent" \
  || fail "Vietnamese index flagged by bytes: rc=$rc out=$out"

# 4. more than 200 lines -> cut at line 201
P=$(mk manylines)
python3 - "$(idx "$P")" <<'EOF'
import sys
open(sys.argv[1], "w").write("- [a](a.md)\n" * 210)
EOF
out=$(run "$P"); rc=$?
[ "$rc" -eq 1 ] && echo "$out" | grep -Eq "line 201\b" && ok "210 lines: exit 1, cut starts at line 201" || fail "210 lines: rc=$rc out=$out"

# 5. clean index -> exit 0, no output
P=$(mk clean)
printf '# Memory index\n\n- [a](a.md) — short\n' > "$(idx "$P")"
out=$(run "$P"); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "clean index: exit 0, silent" || fail "clean index: rc=$rc out=$out"

# 6. no MEMORY.md at all -> nothing to cut
P=$(mk none)
out=$(run "$P"); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "no MEMORY.md: exit 0, silent" || fail "no MEMORY.md: rc=$rc out=$out"

# 7. the index file is never rewritten by the check
P=$(mk readonly)
python3 - "$(idx "$P")" <<'EOF'
import sys
open(sys.argv[1], "w").write("- [b](b.md) — " + "z" * 300 + "\n")
EOF
before=$(shasum "$(idx "$P")")
run "$P" >/dev/null
[ "$(shasum "$(idx "$P")")" = "$before" ] && ok "check does not modify MEMORY.md" || fail "MEMORY.md was modified"

# 8. old --check unchanged: no autoMemoryDirectory -> 1; pointing into the project -> 0
P=$(mk oldcheck)
python3 "$TOOL" "$P" --check >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "--check without autoMemoryDirectory: exit 1" || fail "--check without setting: exit $rc"
mkdir -p "$P/.claude"
python3 - "$P" <<'EOF'
import json, os, sys
p = os.path.realpath(sys.argv[1])
json.dump({"autoMemoryDirectory": os.path.join(p, ".agents/local/memory/claude-auto")}, open(os.path.join(p, ".claude/settings.local.json"), "w"))
EOF
python3 "$TOOL" "$P" --check >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "--check with autoMemoryDirectory in project: exit 0" || fail "--check with setting: exit $rc"

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; } || { echo "FAIL ($FAILS)"; exit 1; }
