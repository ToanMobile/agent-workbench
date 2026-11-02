#!/usr/bin/env bash
# Runner: verdict merge gộp thẻ vào Done và không build. proceed có absorb thì gộp rồi mới giao.
# Gộp lỗi thì thẻ ở Ready, không vào Blocked. Exit 3 (nguồn đã chạy) thì waiting-on, không Blocked.
# Offline. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-runner-merge.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/path" "$TMP/repo/docs/super-board" "$TMP/repo/wl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/super-board-github-read.py"
printf 'print("ok")\n' > "$TMP/bin/super-board-skills-ready.py"
cat > "$TMP/bin/super-board-preflight.sh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$STUB_DIR/preflight-calls"
printf '%s\n' "${STUB_PREFLIGHT_JSON:-}"
exit 0
SH
cat > "$TMP/bin/super-board-merge-cards.py" <<'PY'
#!/usr/bin/env python3
import os, sys
open(os.environ["STUB_DIR"] + "/merge-calls", "a").write(" ".join(sys.argv[1:]) + "\n")
sys.exit(int(os.environ.get("STUB_MERGE_RC", "0")))
PY
printf 'import os, sys\nwith open(os.environ["STUB_DIR"] + "/writes", "a") as f:\n    f.write("waiting-on " + " ".join(sys.argv[1:]) + "\\n")\nprint("{\\"labels\\":[\\"waiting-on:#7\\"]}\\n")\n' > "$TMP/bin/super-board-waiting-on.py"
cat > "$TMP/path/claude" <<'SH'
#!/usr/bin/env bash
echo spawned >> "$STUB_DIR/spawned"
SH
chmod +x "$TMP/bin/"* "$TMP/path/claude"
export STUB_DIR="$TMP" PATH="$TMP/path:$PATH" WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0
unset SB_GITHUB_READ_STRICT SB_ACCOUNT_POOL
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
SB_GITHUB_READ="$TMP/bin/super-board-github-read.py"
SB_MERGE_CARDS="$TMP/bin/super-board-merge-cards.py"
CONFIG_PATH="$TMP/cfg.json"
echo '{"repo":{"remote":"https://github.com/acme/widgets"},"merge_policy":{"auto_max_lines":0}}' > "$CONFIG_PATH"
INFLIGHT_DIR="$TMP/repo/.claude/super-board/inflight"; mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="wl"; REPO_ROOT="$TMP/repo"; BOT_LOGIN="bot"
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }
issue_is_open() { return 0; }
resolve_worker_account() { POOL_ENGINE=""; POOL_ACCT=""; POOL_CFG=""; return 0; }
cd "$TMP/repo" || exit 1
PROJECT_ITEMS_JSON='{"items":[
 {"id":"PVTI_7","status":"Ready","labels":[],"content":{"type":"Issue","number":7,"title":"keep","assignees":[]}},
 {"id":"PVTI_8","status":"Ready","labels":[],"content":{"type":"Issue","number":8,"title":"fold","assignees":[]}}]}'
reset() { : > "$TMP/writes"; : > "$TMP/log"; rm -f "$TMP/spawned" "$TMP/preflight-calls" "$TMP/merge-calls" "$INFLIGHT_DIR"/*; }
PF="$TMP/bin/super-board-preflight.sh"

reset
export STUB_MERGE_RC=0
export STUB_PREFLIGHT_JSON='{"8":{"number":8,"verdict":"merge","tag":"overlap","reason":"fold","mergeInto":7,"blockedBy":[]}}'
SB_PREFLIGHT="$PF" dispatch_lane build 8 >/dev/null 2>&1
[ ! -e "$TMP/spawned" ] && grep -q "move PVTI_8 Done" "$TMP/writes" && ! grep -q "Blocked" "$TMP/writes" \
  && grep -q -- "--into 7" "$TMP/merge-calls" && grep -q -- "--absorb 8" "$TMP/merge-calls" \
  && ok "merge #8 vào #7: Done, không build, không Blocked" \
  || fail "merge: spawned=$(cat "$TMP/spawned" 2>/dev/null) writes=$(cat "$TMP/writes") merge=$(cat "$TMP/merge-calls" 2>/dev/null)"
grep -q -- "--issues 7,8" "$TMP/preflight-calls" && ok "preflight nhận cả hai thẻ Ready" \
  || fail "issues: $(cat "$TMP/preflight-calls" 2>/dev/null)"

reset
export STUB_MERGE_RC=3
SB_PREFLIGHT="$PF" dispatch_lane build 8 >/dev/null 2>&1
[ ! -e "$TMP/spawned" ] && ! grep -q "move PVTI_8" "$TMP/writes" && ! grep -q Blocked "$TMP/writes" \
  && grep -Eq "^waiting-on mark .*--issue 8 --on 7( |$)" "$TMP/writes" \
  && ok "nguồn đã chạy: waiting-on #7, ở Ready" || fail "exit 3: $(cat "$TMP/writes")"

reset
export STUB_MERGE_RC=1
SB_PREFLIGHT="$PF" dispatch_lane build 8 >/dev/null 2>&1
[ ! -e "$TMP/spawned" ] && ! grep -q "move PVTI_8" "$TMP/writes" && ! grep -q Blocked "$TMP/writes" \
  && ok "gộp lỗi: ở Ready, thử lại, không Blocked" || fail "exit 1: $(cat "$TMP/writes")"

reset
export STUB_MERGE_RC=0
export STUB_PREFLIGHT_JSON='{"7":{"number":7,"verdict":"proceed","tag":"clean","reason":"","absorb":[8],"blockedBy":[]}}'
SB_PREFLIGHT="$PF" dispatch_lane build 7 >/dev/null 2>&1
sleep 0.3
[ -e "$INFLIGHT_DIR/7" ] && grep -q "move PVTI_8 Done" "$TMP/writes" \
  && grep -q -- "--into 7" "$TMP/merge-calls" && grep -q -- "--absorb 8" "$TMP/merge-calls" \
  && ok "proceed + absorb: gộp #8 rồi giao #7" || fail "absorb: $(cat "$TMP/writes") $(cat "$TMP/merge-calls" 2>/dev/null)"

reset
export STUB_MERGE_RC=1
SB_PREFLIGHT="$PF" dispatch_lane build 7 >/dev/null 2>&1
[ ! -e "$INFLIGHT_DIR/7" ] && ! grep -q Blocked "$TMP/writes" \
  && ok "absorb lỗi: không giao #7, không Blocked" || fail "absorb fail: $(cat "$TMP/writes") spawned=$(ls "$INFLIGHT_DIR" 2>/dev/null)"

[ "$FAILS" -eq 0 ] && echo PASS || { echo "FAIL ($FAILS)"; exit 1; }
