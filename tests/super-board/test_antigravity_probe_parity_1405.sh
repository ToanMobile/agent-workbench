#!/usr/bin/env bash
# Test oracle #1405 (AC2): antigravity_probe cua runner va discover() cua MCP phai cho cung ket qua tren cung fixture.
# Chay offline, tuong thich bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-1405.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# Chuan bi entrypoint antigravity-pm-mcp.js chay duoc ca trong worktree chua npm install (muon node_modules tu git common checkout neu can).
MCP_SRC="$ROOT/mcp-servers/antigravity-pm-mcp"
if [ -d "$MCP_SRC/node_modules/@modelcontextprotocol/sdk" ]; then
  MCP_JS="$MCP_SRC/bin/antigravity-pm-mcp.js"
else
  COMMON_DIR="$(git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null || true)"
  [ "${COMMON_DIR#/}" = "$COMMON_DIR" ] && [ -n "$COMMON_DIR" ] && COMMON_DIR="$ROOT/$COMMON_DIR"
  COMMON_ROOT="$(cd "$COMMON_DIR/.." 2>/dev/null && pwd -P || true)"
  if [ -n "$COMMON_ROOT" ] && [ -d "$COMMON_ROOT/mcp-servers/antigravity-pm-mcp/node_modules/@modelcontextprotocol/sdk" ]; then
    mkdir -p "$TMP/mcp-pkg"
    cp -R "$MCP_SRC/bin" "$MCP_SRC/src" "$MCP_SRC/package.json" "$TMP/mcp-pkg/"
    ln -s "$COMMON_ROOT/mcp-servers/antigravity-pm-mcp/node_modules" "$TMP/mcp-pkg/node_modules"
    MCP_JS="$TMP/mcp-pkg/bin/antigravity-pm-mcp.js"
  else
    echo "✖ Thieu node_modules/@modelcontextprotocol/sdk cho antigravity-pm-mcp"
    exit 1
  fi
fi

mkdir -p "$TMP/home/.gemini/antigravity/daemon" "$TMP/home/.gemini/config/projects" "$TMP/repo" "$TMP/bin" "$TMP/wl"
cat > "$TMP/repo/.antigravity-pm.json" <<'JSON'
{
  "antigravity": { "projectId": "00000000-0000-4000-8000-000000001405" }
}
JSON

# Fake agentapi tra loi trajectory not found khi dung dia chi + token dong cua phien test
TEST_NONCE="$(node -e 'console.log(require("node:crypto").randomUUID())')"
export TEST_NONCE
cat > "$TMP/bin/agentapi" <<'NODE'
#!/usr/bin/env node
const addr = process.env.ANTIGRAVITY_LS_ADDRESS || '';
const tok = process.env.ANTIGRAVITY_CSRF_TOKEN || '';
if (addr === '127.0.0.1:63286' && tok === process.env.TEST_NONCE) {
  process.stdout.write('{"response": {}, "error": "rpc error: code = NotFound desc = not_found: trajectory not found"}');
  process.exit(1);
}
process.stderr.write('rpc error: code = Unauthenticated desc = missing CSRF token');
process.exit(1);
NODE
chmod +x "$TMP/bin/agentapi"

cat > "$TMP/bin/agy" <<'SH'
#!/usr/bin/env bash
echo 'Error: unexpected argument "get-conversation-metadata"' >&2
exit 2
SH
chmod +x "$TMP/bin/agy"

export HOME="$TMP/home"
export ANTIGRAVITY_PM_PROJECTS_DIR="$TMP/home/.gemini/config/projects"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/state"
export ANTIGRAVITY_PM_AGENTAPI="$TMP/bin/agentapi"
export ANTIGRAVITY_PM_AGY="$TMP/bin/agy"
export ANTIGRAVITY_PM_PS="$TMP/bin/ps"
export WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0
unset ANTIGRAVITY_LS_ADDRESS ANTIGRAVITY_CSRF_TOKEN ANTIGRAVITY_AGENTAPI_EXE SB_ANTIGRAVITY_PROBE

SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ Khong nap duoc $RUNNER"; exit 1; }
set +e
REPO_ROOT="$TMP/repo"
export SB_ANTIGRAVITY_PM_MCP="$MCP_JS"

run_discover() {
  node --input-type=module -e '
    import { pathToFileURL } from "node:url";
    const mod = await import(pathToFileURL(process.argv[1]).href);
    mod.forgetCache();
    try { await mod.discover({ force: true }); process.exit(0); }
    catch (e) { console.error(e.message); process.exit(1); }
  ' "$1"
}

# Case 1: argv moi (--read_host_bridge_token_from_stdin, khong --csrf_token) + hub_63286.json khop pid -> ca discover va probe deu PASS
cat > "$TMP/bin/ps" <<'SH'
#!/usr/bin/env sh
printf '%s\n' '78760 /Applications/Antigravity.app/Contents/Resources/bin/language_server --standalone --app_data_dir antigravity --host_bridge_url=http://127.0.0.1:63281 --read_host_bridge_token_from_stdin'
SH
chmod +x "$TMP/bin/ps"
printf '{"pid":78760,"httpsPort":63285,"httpPort":63286,"lsVersion":"2.34.0","csrfToken":"%s"}\n' "$TEST_NONCE" > "$TMP/home/.gemini/antigravity/daemon/hub_63286.json"
chmod 600 "$TMP/home/.gemini/antigravity/daemon/hub_63286.json"

d_rc=0; p_rc=0
run_discover "$MCP_SRC/src/discover.js" >/dev/null 2>&1 || d_rc=$?
antigravity_probe >/dev/null 2>&1 || p_rc=$?
if [ "$d_rc" -eq 0 ] && [ "$p_rc" -eq 0 ]; then
  ok "Case 1: new argv + daemon hub JSON -> both discover and antigravity_probe succeed (d=$d_rc p=$p_rc)"
else
  fail "Case 1: mismatch or fail on new argv + daemon hub JSON (discover=$d_rc probe=$p_rc)"
fi

# Case 2: argv moi NHUNG thieu hub_*.json khop pid -> ca discover va probe deu FAIL
rm -f "$TMP/home/.gemini/antigravity/daemon/hub_63286.json"
d_rc=0; p_rc=0
run_discover "$MCP_SRC/src/discover.js" >/dev/null 2>&1 || d_rc=$?
antigravity_probe >/dev/null 2>&1 || p_rc=$?
if [ "$d_rc" -ne 0 ] && [ "$p_rc" -ne 0 ]; then
  ok "Case 2: new argv without matching daemon hub JSON -> both discover and antigravity_probe fail (d=$d_rc p=$p_rc)"
else
  fail "Case 2: mismatch on missing daemon hub JSON (discover=$d_rc probe=$p_rc)"
fi

# Case 3: env ANTIGRAVITY_LS_ADDRESS + ANTIGRAVITY_AGENTAPI_EXE=agy dat trong shell (mo phong chay tu phien agy) trong khi IDE dong:
# antigravity_probe phai bo qua env cua phien cha va tra FAIL (khop voi worker khong co env IDE)
export ANTIGRAVITY_LS_ADDRESS="127.0.0.1:63286"
export ANTIGRAVITY_CSRF_TOKEN="$TEST_NONCE"
export ANTIGRAVITY_AGENTAPI_EXE="$TMP/bin/agy"
unset ANTIGRAVITY_PM_AGENTAPI
mkdir -p "$TMP/home/.gemini/antigravity/bin"
cp "$TMP/bin/agentapi" "$TMP/home/.gemini/antigravity/bin/agentapi"
chmod +x "$TMP/home/.gemini/antigravity/bin/agentapi"

p_rc=0
antigravity_probe >/dev/null 2>&1 || p_rc=$?
if [ "$p_rc" -ne 0 ]; then
  ok "Case 3: antigravity_probe ignores parent ANTIGRAVITY_LS_ADDRESS/CSRF_TOKEN when IDE is closed (probe=$p_rc)"
else
  fail "Case 3: antigravity_probe falsely succeeded from parent env while IDE closed"
fi

# Khi IDE co daemon hub JSON, du env co ANTIGRAVITY_AGENTAPI_EXE=agy thi ca probe va discover van PASS
printf '{"pid":78760,"httpsPort":63285,"httpPort":63286,"lsVersion":"2.34.0","csrfToken":"%s"}\n' "$TEST_NONCE" > "$TMP/home/.gemini/antigravity/daemon/hub_63286.json"
chmod 600 "$TMP/home/.gemini/antigravity/daemon/hub_63286.json"

d_rc=0; p_rc=0
( unset ANTIGRAVITY_LS_ADDRESS ANTIGRAVITY_CSRF_TOKEN; run_discover "$MCP_SRC/src/discover.js" >/dev/null 2>&1 ) || d_rc=$?
antigravity_probe >/dev/null 2>&1 || p_rc=$?
if [ "$d_rc" -eq 0 ] && [ "$p_rc" -eq 0 ]; then
  ok "Case 4: with ANTIGRAVITY_AGENTAPI_EXE=agy in env, both discover and antigravity_probe fall back to agentapi and pass"
else
  fail "Case 4: failed with ANTIGRAVITY_AGENTAPI_EXE=agy in env (discover=$d_rc probe=$p_rc)"
fi

# Case 5: super-board-worker-wrap.sh bo ANTIGRAVITY_LS_ADDRESS/ANTIGRAVITY_CSRF_TOKEN cua shell cha de worker dung dung duong discover nhu probe
WRAP="$ROOT/.claude/bin/super-board-worker-wrap.sh"
wrap_out="$("$WRAP" env 2>/dev/null || true)"
if ! grep -qE '^ANTIGRAVITY_LS_ADDRESS=|^ANTIGRAVITY_CSRF_TOKEN=' <<<"$wrap_out"; then
  ok "Case 5: super-board-worker-wrap.sh clears parent ANTIGRAVITY_LS_ADDRESS/ANTIGRAVITY_CSRF_TOKEN so worker matches probe"
else
  fail "Case 5: worker wrapper leaked parent ANTIGRAVITY_LS_ADDRESS/ANTIGRAVITY_CSRF_TOKEN"
fi

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; } || { echo "FAIL ($FAILS)"; exit 1; }
