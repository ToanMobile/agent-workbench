#!/usr/bin/env bash
# test_uninstall.sh — `agent-kit uninstall` removes only what the installer added.
# Install onto a project that already has its own CLAUDE.md (folded into AGENTS.md, put
# back by uninstall), MCP server, settings hook
# and a command clashing with a DevKit one; `uninstall --apply` + `restore-old --apply`
# must give back exactly the original project (ignoring *_old backups and ledgers),
# keep the user's hook, and leave no settings entry pointing at a removed hook.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export DEVKIT_LANG=en   # the assertions below match the English output

DEVKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/uninstall-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok()  { echo "✔ $1"; PASS=$((PASS + 1)); }
bad() { echo "✘ $1"; FAIL=$((FAIL + 1)); }

make_project() { # <dir>
  local p="$1"
  mkdir -p "$p/.claude/hooks" "$p/.claude/commands" "$p/src"
  (cd "$p" && git init -q)
  printf '# My project\n\nOur own agent notes.\n' > "$p/CLAUDE.md"
  printf 'node_modules/\n' > "$p/.gitignore"
  printf '{\n  "mcpServers": {\n    "mine": {\n      "command": "my-mcp"\n    }\n  }\n}\n' > "$p/.mcp.json"
  cat > "$p/.claude/settings.json" <<'JSON'
{
  "permissions": {
    "allow": [
      "Bash(ls)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/my_guard.sh"
          }
        ]
      }
    ]
  }
}
JSON
  printf '#!/usr/bin/env bash\nexit 0\n' > "$p/.claude/hooks/my_guard.sh"
  printf 'my own fix command\n' > "$p/.claude/commands/fix.md"
  printf 'console.log(1)\n' > "$p/src/app.js"
}

# Everything but .git, *_old backups and DevKit ledgers: type, path, content/link target.
snapshot() {
  (cd "$1" && find . -path ./.git -prune -o -print | LC_ALL=C sort | while IFS= read -r f; do
    case "$f" in .|./.git) continue ;; esac
    case "$(basename "$f")" in *_old|*_old.*|*_old_*|.devkit_backups.log) continue ;; esac
    case "$f" in *_old/*|*_old.*/*|*_old_*/*) continue ;; esac
    if [ -L "$f" ]; then echo "L $f -> $(readlink "$f")"
    elif [ -d "$f" ]; then echo "D $f"
    else echo "F $f $(shasum < "$f" | cut -d' ' -f1)"; fi
  done)
}

# __pycache__ is created by the first import of a DevKit helper: a fresh checkout has none, a used one has it
devkit_snapshot() { (cd "$DEVKIT" && ls -A . rules skills commands hooks | grep -v '^__pycache__$' | shasum); }

dangling_hook_refs() { # settings.json commands naming .claude/hooks/<x> that does not exist
  python3 - "$1" <<'PY'
import json, os, re, sys
p = sys.argv[1]
s = os.path.join(p, ".claude", "settings.json")
if not os.path.exists(s):
    sys.exit(0)
bad = []
for groups in (json.load(open(s)).get("hooks") or {}).values():
    for g in groups:
        for h in g.get("hooks", []):
            for m in re.finditer(r"\.claude/hooks/([\w.-]+)", h.get("command", "")):
                if not os.path.exists(os.path.join(p, ".claude", "hooks", m.group(1))):
                    bad.append(m.group(1))
print(" ".join(bad))
PY
}

dk_before="$(devkit_snapshot)"

for MODE in symlink copy; do
  P="$TMP/proj-$MODE"
  make_project "$P"
  orig="$(snapshot "$P")"
  bash "$DEVKIT/bin/install.sh" -t "$P" -y -p universal -a all -m "$MODE" >/dev/null 2>&1 \
    && ok "[$MODE] install" || bad "[$MODE] install failed"
  [ "$(snapshot "$P")" != "$orig" ] && grep -q "universal-agent-devkit" "$P/AGENTS.md" && [ ! -e "$P/CLAUDE.md" ] \
    && grep -q "Our own agent notes." "$P/AGENTS.md" \
    && ok "[$MODE] install changed the project (CLAUDE.md folded into AGENTS.md)" || bad "[$MODE] install changed nothing?"

  before_dry="$(cd "$P" && find . -path ./.git -prune -o -print | LC_ALL=C sort | shasum)"
  out="$(bash "$DEVKIT/bin/agent-kit" uninstall "$P" 2>&1)"; rc=$?
  after_dry="$(cd "$P" && find . -path ./.git -prune -o -print | LC_ALL=C sort | shasum)"
  [ "$rc" -eq 0 ] && [ "$before_dry" = "$after_dry" ] && echo "$out" | grep -q "would" \
    && ok "[$MODE] dry-run lists actions and changes nothing" || bad "[$MODE] dry-run: rc=$rc $out"

  out="$(bash "$DEVKIT/bin/agent-kit" uninstall "$P" --apply 2>&1)" \
    && ok "[$MODE] uninstall --apply exit 0" || bad "[$MODE] uninstall --apply failed: $out"
  out2="$(bash "$DEVKIT/bin/agent-kit" restore-old "$P" --apply 2>&1)" \
    && ok "[$MODE] restore-old --apply exit 0" || bad "[$MODE] restore-old failed: $out2"

  now="$(snapshot "$P")"
  if [ "$now" = "$orig" ]; then
    ok "[$MODE] project is back to its original state"
  else
    bad "[$MODE] project differs from the original:"
    diff <(echo "$orig") <(echo "$now") | head -20
  fi
  grep -q "my_guard.sh" "$P/.claude/settings.json" 2>/dev/null \
    && ok "[$MODE] the user's own hook is still wired" || bad "[$MODE] user hook lost"
  refs="$(dangling_hook_refs "$P")"
  [ -z "$refs" ] && ok "[$MODE] no settings entry points at a removed hook" || bad "[$MODE] dangling hook refs: $refs"
done

# Edits made after install are kept: an edited DevKit copy, an edited MCP entry, an
# extra setting. DevKit hooks/servers still go, and nothing points at a removed hook.
P="$TMP/proj-edited"
make_project "$P"
bash "$DEVKIT/bin/install.sh" -t "$P" -y -p universal -a claude -m copy >/dev/null 2>&1
echo "# team tweak" >> "$P/.claude/hooks/churn_guard.sh"
python3 - "$P" <<'PY'
import json, sys, os
p = sys.argv[1]
m = json.load(open(os.path.join(p, ".mcp.json")))
name = next(n for n in m["mcpServers"] if n != "mine")
m["mcpServers"][name]["env"] = {"EDITED": "1"}
json.dump(m, open(os.path.join(p, ".mcp.json"), "w"), indent=2)
s = json.load(open(os.path.join(p, ".claude", "settings.json")))
s["permissions"]["allow"].append("Bash(pwd)")
json.dump(s, open(os.path.join(p, ".claude", "settings.json"), "w"), indent=2)
open(os.path.join(p, ".edited-mcp"), "w").write(name)
PY
edited_mcp="$(cat "$P/.edited-mcp")"; rm -f "$P/.edited-mcp"
out="$(bash "$DEVKIT/bin/agent-kit" uninstall "$P" --apply 2>&1)"
grep -q "team tweak" "$P/.claude/hooks/churn_guard.sh" 2>/dev/null && echo "$out" | grep -q "KEEP.*churn_guard.sh" \
  && ok "edited DevKit copy is kept and reported" || bad "edited DevKit copy: $out"
python3 - "$P" "$edited_mcp" <<'PY' && ok "edited MCP entry kept, untouched DevKit servers removed, user server kept" || bad "MCP cleanup"
import json, sys, os
p, edited = sys.argv[1], sys.argv[2]
srv = json.load(open(os.path.join(p, ".mcp.json")))["mcpServers"]
sys.exit(0 if set(srv) == {"mine", edited} else 1)
PY
python3 - "$P" <<'PY' && ok "settings: user permissions kept, DevKit deny list and DevKit hooks removed" || bad "settings surgical cleanup"
import json, sys, os
s = json.load(open(os.path.join(sys.argv[1], ".claude", "settings.json")))
perm = s.get("permissions", {})
cmds = [h["command"] for g in s.get("hooks", {}).values() for grp in g for h in grp["hooks"]]
ok = perm.get("allow") == ["Bash(ls)", "Bash(pwd)"] and "deny" not in perm and cmds == ["bash .claude/hooks/my_guard.sh"]
sys.exit(0 if ok else 1)
PY
ls "$P/.claude/" | grep -q "settings_old.uninstall-" && ok "settings.json backed up before it was changed" \
  || bad "no settings_old.uninstall-* backup"
refs="$(dangling_hook_refs "$P")"
[ -z "$refs" ] && ok "edited project: no settings entry points at a removed hook" || bad "dangling hook refs: $refs"

# .gitattributes of the matrix merge driver (23/10, review): the user's other lines survive byte for byte (CRLF, no final newline),
# a dry-run changes neither the file nor the repo config, a symlinked .gitattributes is kept, an unwritable one is kept (no crash),
# and a run from a subdirectory of the git root finds the file the installer wrote.
ATTR=".agents/regression_matrix.active.json merge=devkit-matrix"
mkattr() { # <dir> <content-printf-format>: a git project with the driver config and a .gitattributes
  mkdir -p "$1" && git -C "$1" init -q . && git -C "$1" config merge.devkit-matrix.driver "true %O"
  printf "$2" > "$1/.gitattributes"
}
A="$TMP/attr1"; mkattr "$A" "*.png binary\r\n$ATTR\r\nfoo"
sum_before="$(shasum < "$A/.gitattributes")"
bash "$DEVKIT/bin/agent-kit" uninstall "$A" >/dev/null 2>&1
[ "$(shasum < "$A/.gitattributes")" = "$sum_before" ] && [ -n "$(git -C "$A" config --get merge.devkit-matrix.driver)" ] \
  && ok "attr: dry-run leaves .gitattributes and merge.devkit-matrix config alone" || bad "attr: dry-run changed something"
bash "$DEVKIT/bin/agent-kit" uninstall "$A" --apply >/dev/null 2>&1
[ "$(cat "$A/.gitattributes")" = "$(printf '*.png binary\r\nfoo')" ] && [ -z "$(git -C "$A" config --get merge.devkit-matrix.driver)" ] \
  && ok "attr: --apply drops only the driver line (CRLF, no final newline kept) and the config section" || bad "attr: apply result: $(od -c "$A/.gitattributes" | head -3)"
A="$TMP/attr2"; mkdir -p "$A/sub"; mkattr "$A" "$ATTR\n"
bash "$DEVKIT/bin/agent-kit" uninstall "$A/sub" --apply >/dev/null 2>&1
[ ! -e "$A/.gitattributes" ] && ok "attr: from a subdirectory the git root's file is found and removed when it held only that line" || bad "attr: subdirectory run left the file"
A="$TMP/attr3"; mkattr "$A" "x\n"; printf '%s\n' "$ATTR" > "$TMP/attr3-target"; rm "$A/.gitattributes"; ln -s "$TMP/attr3-target" "$A/.gitattributes"
bash "$DEVKIT/bin/agent-kit" uninstall "$A" --apply >/dev/null 2>&1
[ "$(cat "$TMP/attr3-target")" = "$ATTR" ] && ok "attr: a symlinked .gitattributes is kept, its target untouched" || bad "attr: symlink target changed"
A="$TMP/attr4"; mkattr "$A" "keep\n$ATTR\n"; chmod 444 "$A/.gitattributes"; chmod 555 "$A"
out="$(bash "$DEVKIT/bin/agent-kit" uninstall "$A" --apply 2>&1)"; rc=$?
chmod 755 "$A"; chmod 644 "$A/.gitattributes"
[ "$rc" -eq 0 ] && ! echo "$out" | grep -q Traceback && ok "attr: an unwritable .gitattributes is reported, no traceback" || bad "attr: unwritable: rc=$rc $(echo "$out" | tail -3)"

# CLI guards
bash "$DEVKIT/bin/agent-kit" uninstall "$DEVKIT" --apply >/dev/null 2>&1
[ $? -eq 2 ] && ok "refuses to uninstall the DevKit from itself (exit 2)" || bad "uninstall on the DevKit itself"
bash "$DEVKIT/bin/agent-kit" uninstall "$TMP" --bogus >/dev/null 2>&1
[ $? -eq 2 ] && ok "unknown option -> exit 2" || bad "unknown option -> exit 2"

[ "$(devkit_snapshot)" = "$dk_before" ] && ok "DevKit tree untouched" || bad "DevKit tree changed"

echo
echo "uninstall: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] && echo "uninstall: all checks passed"
[ "$FAIL" -eq 0 ]
