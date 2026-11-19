#!/usr/bin/env bash
# Hồi quy #1265: công cụ DevKit (agent-config.py, install.sh, worktree.py) không được làm bẩn
# `.agents/active-profile.json` (ghi lại `updated_at` hoặc định dạng lại) trên cây sạch,
# để dispatch audit Antigravity trên worktree review ghi được `Pham vi:` thay vì `Khong ghi pham vi`.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
DEVKIT_DIR="$REPO_ROOT/universal-agent-devkit"
CFG="$DEVKIT_DIR/bin/agent-config.py"
INSTALL="$DEVKIT_DIR/bin/install.sh"
WT="$DEVKIT_DIR/scripts/git/worktree.py"
MCP_DIR="$REPO_ROOT/mcp-servers/antigravity-pm-mcp"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
unset DEVKIT_LANG CLAUDE_PROJECT_DIR TARGET_DIR

FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "${@:2}"; }

# ------------------------------------------------------------------
# Ca 1: agent-config.py chạy lại trên cây sạch có trailing newline
# ------------------------------------------------------------------
P1="$TMP/p1"
mkdir -p "$P1"
G "$P1" init -q -b main .
echo "x" > "$P1/a.txt"
G "$P1" add a.txt && G "$P1" commit -qm init
bash "$INSTALL" -t "$P1" -a claude -p backend -y --lang=vi >/dev/null 2>&1 || { fail "Ca 1: install fixture lỗi"; exit 1; }
# Thêm newline cuối file (chuẩn POSIX / editor hay lưu) và commit
printf '\n' >> "$P1/.agents/active-profile.json"
G "$P1" add -A >/dev/null 2>&1
G "$P1" commit -qm "commit active-profile with trailing newline" >/dev/null 2>&1

sleep 1
python3 "$CFG" --profile backend --target "$P1" --lang vi >/dev/null 2>&1
st1="$(G "$P1" status --porcelain --untracked-files=no)"
if [ -z "$st1" ]; then
  ok "Ca 1: agent-config.py giữ sạch git status khi active-profile.json có trailing newline"
else
  fail "Ca 1: agent-config.py làm bẩn cây sạch: $st1"
fi

# ------------------------------------------------------------------
# Ca 2 + 3: worktree add --lane=review khi kit ở main có profile.json mới hơn
# nhánh PR + chạy lại install.sh trong worktree + dispatch audit Antigravity
# ------------------------------------------------------------------
# Tạo bản kit riêng tạm để mô phỏng kit trên main đổi description (như #1243 -> #1259)
KIT_COPY="$TMP/kit"
cp -R "$DEVKIT_DIR" "$KIT_COPY"

P2="$TMP/p2"
mkdir -p "$P2"
G "$P2" init -q -b main .
echo "base" > "$P2/app.py"
G "$P2" add app.py && G "$P2" commit -qm init
bash "$KIT_COPY/bin/install.sh" -t "$P2" -a claude -p backend -y --lang=vi >/dev/null 2>&1 || { fail "Ca 2: install fixture lỗi"; exit 1; }
G "$P2" add -A >/dev/null 2>&1
G "$P2" commit -qm "install devkit" >/dev/null 2>&1

# Nhánh PR giữ bản active-profile.json cũ trước khi kit đổi description
G "$P2" checkout -q -b feat
echo "change" >> "$P2/app.py"
G "$P2" add app.py && G "$P2" commit -qm "feat change" >/dev/null 2>&1
G "$P2" checkout -q main

# Kit trên main cập nhật mô tả backend trong profile.json (không chạm nhánh feat)
python3 - "$KIT_COPY/profiles/backend/profile.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
d["description"] = d.get("description", "") + " [cap nhat moi]"
json.dump(d, open(p, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
PY

REV="$P2/.claude/worktrees/issue-1265-review"
(cd "$P2" && env WORKTREE_DISK_WARN_GIB=0 WORKTREE_DISK_MIN_GIB=0 python3 "$KIT_COPY/scripts/git/worktree.py" add "$REV" --lane=review --base=feat >"$TMP/wt.log" 2>&1)
wt_rc=$?
if [ "$wt_rc" -ne 0 ]; then
  fail "Ca 2: worktree add --lane=review thất bại (rc=$wt_rc): $(tail -3 "$TMP/wt.log")"
else
  st2="$(G "$REV" status --porcelain --untracked-files=no)"
  if [ -z "$st2" ]; then
    ok "Ca 2a: worktree add --lane=review giữ sạch git status dù kit mới hơn nhánh PR"
  else
    fail "Ca 2a: worktree add --lane=review làm bẩn cây review: $st2"
  fi
fi

# Chạy lại install.sh trực tiếp trong worktree review cũng không được làm bẩn file đã track
bash "$KIT_COPY/bin/install.sh" -t "$REV" -a claude -p backend -y --lang=vi >/dev/null 2>&1 || true
st2b="$(G "$REV" status --porcelain --untracked-files=no)"
if [ -z "$st2b" ]; then
  ok "Ca 2b: install.sh chạy lại trong worktree liên kết không làm bẩn active-profile.json đã track"
else
  fail "Ca 2b: install.sh trong worktree làm bẩn cây: $st2b"
fi

# Ca 3: Dispatch audit Antigravity trên cây review phải ghi được Pham vi:, không in Khong ghi pham vi
if command -v node >/dev/null 2>&1; then
  FAKE_BIN="$TMP/fakebin"
  mkdir -p "$FAKE_BIN"
  cat > "$FAKE_BIN/agy" <<'JS'
#!/usr/bin/env node
console.log(JSON.stringify({ event: 'init', conversation_id: 'c0c0c0c0-1111-2222-3333-444444444444', init: { cwd: process.cwd() } }));
console.log(JSON.stringify({ event: 'result', result: { conversation_id: 'c0c0c0c0-1111-2222-3333-444444444444', status: 'SUCCESS' } }));
JS
  chmod +x "$FAKE_BIN/agy"
  cat > "$FAKE_BIN/agentapi" <<'SH'
#!/bin/sh
echo '{"response": {}, "error": "rpc error: code = Unavailable"}'
exit 1
SH
  chmod +x "$FAKE_BIN/agentapi"

  python3 - "$REV" <<'PY'
import json, pathlib, sys
rev = pathlib.Path(sys.argv[1])
(rev / ".antigravity-pm.json").write_text(json.dumps({
    "projectName": "test-1265",
    "testCommand": "echo ok",
    "defaultModel": "gemini-4-argon-high",
}), encoding="utf-8")
PY
  EXCLUDE_FILE="$(git -C "$REV" rev-parse --path-format=absolute --git-path info/exclude)"
  printf '\n/.antigravity-pm.json\n/.antigravity-pm/\n' >> "$EXCLUDE_FILE"

  OUT_AUDIT="$(ANTIGRAVITY_PM_STATE_HOME="$TMP/pm" DEVKIT_PM_HOME_TEST=1 ANTIGRAVITY_PM_QUIET=1 \
    ANTIGRAVITY_PM_AGY="$FAKE_BIN/agy" ANTIGRAVITY_PM_AGY_SKIP_PERMISSIONS=1 ANTIGRAVITY_PM_AGENTAPI="$FAKE_BIN/agentapi" \
    node --input-type=module - "$MCP_DIR" "$REV" <<'MJS'
import path from 'node:path';
import { pathToFileURL } from 'node:url';
const [,, mcpDir, rev] = process.argv;
const { TOOLS_BY_NAME } = await import(pathToFileURL(path.join(mcpDir, 'src', 'tools.js')).href);
const call = async (name, args) => {
  const out = await TOOLS_BY_NAME.get(name).handler(args);
  return typeof out === 'string' ? out : out.text;
};
const created = await call('pm_task_create', { project: rev, title: 'audit-1265', brief: 'check scope', definitionOfDone: ['clean'] });
const taskId = /T\d{4}-[a-z0-9-]+/.exec(created)[0];
const dispatched = await call('pm_dispatch', { project: rev, taskId, kind: 'audit' });
console.log(dispatched);
MJS
  )"
  if printf '%s' "$OUT_AUDIT" | grep -q 'Pham vi:' && ! printf '%s' "$OUT_AUDIT" | grep -q 'Khong ghi pham vi'; then
    ok "Ca 3: dispatch audit trên cây review ghi được Pham vi:, không in Khong ghi pham vi"
  else
    fail "Ca 3: dispatch audit không ghi được phạm vi: $(printf '%s' "$OUT_AUDIT" | tr '\n' ' ')"
  fi
else
  fail "Ca 3: thiếu node"
fi

# ------------------------------------------------------------------
# Ca 4 (control): trên main checkout khi profile.json thật sự đổi, agent-config.py vẫn cập nhật
# ------------------------------------------------------------------
python3 - "$KIT_COPY/bin/agent-config.py" "$P1" <<'PY'
import json, pathlib, subprocess, sys
cfg, p1 = sys.argv[1], pathlib.Path(sys.argv[2])
kit_prof = pathlib.Path(cfg).resolve().parent.parent / "profiles" / "backend" / "profile.json"
d = json.loads(kit_prof.read_text(encoding="utf-8"))
d["description"] = d.get("description", "") + " [main updated]"
kit_prof.write_text(json.dumps(d, indent=2, ensure_ascii=False), encoding="utf-8")
subprocess.run([sys.executable, cfg, "--profile", "backend", "--target", str(p1), "--lang", "vi"],
               check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
cur = json.loads((p1 / ".agents" / "active-profile.json").read_text(encoding="utf-8"))
assert "[main updated]" in cur["description"], "main checkout did not update when profile.json changed"
PY
if [ $? -eq 0 ]; then
  ok "Ca 4 (control): main checkout vẫn cập nhật active-profile.json khi nội dung thật sự đổi"
else
  fail "Ca 4 (control): main checkout không cập nhật khi profile.json đổi"
fi

echo
[ "$FAILS" -eq 0 ] && echo "test_worktree_active_profile_clean: ALL PASSED" || echo "test_worktree_active_profile_clean: $FAILS FAILED"
exit "$FAILS"
