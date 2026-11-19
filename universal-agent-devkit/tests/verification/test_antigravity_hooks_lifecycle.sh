#!/usr/bin/env bash
# Test hồi quy: vòng đời .agents/hooks.json (state/fingerprint/gate), parity & health cho Antigravity,
# và xử lý an toàn tool manage_task trong agent_bridge.sh.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
export DEVKIT_LANG=en

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
BRIDGE="$DEVKIT_DIR/hooks/agent_bridge.sh"
AH="$DEVKIT_DIR/scripts/context/agent_hooks.py"
PARITY="$DEVKIT_DIR/bin/parity_check.py"
HEALTH="$DEVKIT_DIR/bin/agent-health.py"
PFG="$DEVKIT_DIR/bin/post-fix-gate.py"
TFP="$DEVKIT_DIR/bin/tree_fp.py"
SG="$DEVKIT_DIR/bin/scoped_gate.py"
WT_PY="$DEVKIT_DIR/scripts/git/worktree.py"
RG="$DEVKIT_DIR/hooks/regression_gate.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/ag-lifecycle.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# --- Ca A (P1-1): .agents/hooks.json trong tree_fp, post-fix-gate, scoped_gate, regression_gate, worktree ---
A="$TMP/proj_a"
mkdir -p "$A/.agents/hooks"
(
  cd "$A" || exit 1
  git init -q
  git config user.email t@t
  git config user.name t
  git config commit.gpgsign false
  echo 'VALUE = 1' > app.py
  cat > test_app.py <<'PY'
import app
assert app.VALUE >= 1
PY
  cat > .agents/regression_matrix.active.json <<'JSON'
{
  "version": 1,
  "rules": [
    {
      "component": "demo",
      "watch_files": ["app.py", "test_app.py"],
      "mandatory_regression_tests": [
        {
          "id": "REG-DEMO-01",
          "name": "demo check",
          "command": "python3 test_app.py",
          "parallel_safe": true
        }
      ]
    }
  ]
}
JSON
  echo '.agents/hooks/' > .gitignore
  git add app.py test_app.py .agents/regression_matrix.active.json .gitignore
  git commit -qm init
)

# Gắn các link hook cầu nối và tạo .agents/hooks.json chưa commit (giống trạng thái worktree mới sau worktree add)
for h in agent_bridge.sh block-dangerous-git.sh block_dangerous_git_main.py hardware_safety_gate.sh hardware_safety_gate_main.py shell_norm.py; do
  ln -s "$DEVKIT_DIR/hooks/$h" "$A/.agents/hooks/$h"
done
python3 "$AH" install antigravity "$A" >/dev/null

# Kiểm tra các module nội bộ nhận diện đúng .agents/hooks.json
python3 - "$DEVKIT_DIR" "$A" "$RG" <<'PY' && ok "P1-1: module DevKit ghim/bỏ qua test cho .agents/hooks.json và kiểm tra settings_problems" || fail "P1-1: module kiểm tra .agents/hooks.json chưa đủ"
import importlib.util
import json
import sys
from pathlib import Path

devkit, repo, rg_path = sys.argv[1], sys.argv[2], sys.argv[3]
sys.path.insert(0, str(Path(devkit) / "bin"))
sys.path.insert(0, str(Path(devkit) / "scripts" / "git"))

def load_mod(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

tree_fp = load_mod("tree_fp", str(Path(devkit) / "bin" / "tree_fp.py"))
scoped_gate = load_mod("scoped_gate", str(Path(devkit) / "bin" / "scoped_gate.py"))
pfg = load_mod("post_fix_gate", str(Path(devkit) / "bin" / "post-fix-gate.py"))
wt = load_mod("worktree", str(Path(devkit) / "scripts" / "git" / "worktree.py"))

assert ".agents/hooks.json" in tree_fp.HEAD_PINNED, tree_fp.HEAD_PINNED
fp_with_untracked = tree_fp.tree_fingerprint(repo)
fp_commit = tree_fp.commit_fingerprint(repo, "HEAD")
assert fp_with_untracked and fp_with_untracked == fp_commit, (fp_with_untracked, fp_commit)

assert ".agents/hooks.json" in scoped_gate.AGENT_STATE, scoped_gate.AGENT_STATE
assert ("antigravity", ".agents/hooks.json") in wt.AGENT_MARKERS, wt.AGENT_MARKERS
assert ".agents/hooks.json" in wt.GENERATED_DIRTY, wt.GENERATED_DIRTY

assert ".agents/hooks.json" in pfg.AGENT_STATE_FILES, pfg.AGENT_STATE_FILES
assert ".agents/hooks.json" in pfg.SETTINGS_FILES, pfg.SETTINGS_FILES
assert pfg.needs_no_test(".agents/hooks.json") is True

root = Path(repo)
good_text = (root / ".agents" / "hooks.json").read_text(encoding="utf-8")
assert pfg.settings_problems(".agents/hooks.json", good_text, root) == []
assert pfg.settings_problems(".agents/hooks.json", None, root) != []
assert pfg.settings_problems(".agents/hooks.json", "{bad json", root) != []
bad_empty = json.dumps({"universal-agent-devkit": {"PreToolUse": []}})
assert pfg.settings_problems(".agents/hooks.json", bad_empty, root) != []
bad_dangling = json.dumps({
    "universal-agent-devkit": {
        "PreToolUse": [{
            "matcher": "run_command",
            "hooks": [
                {"command": "bash hooks/agent_bridge.sh antigravity shell missing_guard.sh"},
                {"command": "bash hooks/agent_bridge.sh antigravity shell block-dangerous-git.sh"},
                {"command": "bash hooks/agent_bridge.sh antigravity shell hardware_safety_gate.sh"},
            ]
        }]
    }
})
assert pfg.settings_problems(".agents/hooks.json", bad_dangling, root) != []

# Kiểm tra hàm no_test_needed nhúng trong hooks/regression_gate.sh
src = Path(rg_path).read_text(encoding="utf-8")
start = src.index("def no_test_needed(p):")
end = src.index("\n\nrfp, rwhy", start)
ns = {"re": __import__("re")}
exec(src[start:end], ns)
assert ns["no_test_needed"](".agents/hooks.json") is True
PY

# Chỉ có ?? .agents/hooks.json trên cây sạch -> post-fix-gate --scoped phải thoát 0 (không exit 2 thiếu test)
(cd "$A" && DEVKIT_GATE_NO_LOG=1 CLAUDE_PROJECT_DIR="$A" python3 "$PFG" --run-tests --scoped --brief >"$TMP/gate_hooks_only.out" 2>&1)
rc=$?
[ "$rc" -eq 0 ] && ok "P1-1: post-fix-gate --scoped thoát 0 khi chỉ có ?? .agents/hooks.json" \
  || { fail "P1-1: post-fix-gate --scoped thất bại với chỉ ?? .agents/hooks.json (rc=$rc)"; tail -15 "$TMP/gate_hooks_only.out"; }

# Giả lập sửa app.py trong khi .agents/hooks.json vẫn chưa track -> post-fix-gate --scoped chạy REG-DEMO-01 và thoát 0
echo 'VALUE = 2' > "$A/app.py"
(cd "$A" && DEVKIT_GATE_NO_LOG=1 CLAUDE_PROJECT_DIR="$A" python3 "$PFG" --run-tests --scoped --brief >"$TMP/gate_a.out" 2>&1)
rc=$?
[ "$rc" -eq 0 ] && ok "P1-1: post-fix-gate --scoped thoát 0 khi sửa app.py cùng ?? .agents/hooks.json" \
  || { fail "P1-1: post-fix-gate --scoped thất bại khi sửa app.py (rc=$rc)"; tail -15 "$TMP/gate_a.out"; }

# --- Ca B (P1-2): parity_check.py và agent-health.py cho Antigravity .agents/hooks.json ---
H="$TMP/proj_h"
mkdir -p "$H"
(cd "$H" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false && echo x > f && git add f && git commit -qm init)
bash "$DEVKIT_DIR/bin/install.sh" -t "$H" -a claude,gemini -p backend -y >"$TMP/inst_h.out" 2>&1
rc=$?
[ "$rc" -eq 0 ] || { fail "P1-2: install -a claude,gemini thất bại (rc=$rc)"; tail -10 "$TMP/inst_h.out"; }

python3 "$PARITY" "$H" >"$TMP/par_ok.out" 2>&1; prc=$?
[ "$prc" -eq 0 ] && ok "P1-2: parity_check thoát 0 khi .agents/hooks.json hợp lệ" \
  || fail "P1-2: parity_check lẽ ra 0 nhưng exit $prc: $(cat "$TMP/par_ok.out")"

# Xoá .agents/hooks.json trong khi .gemini/settings.json vẫn dùng agent_bridge.sh -> parity & health đều phải báo lỗi
cp "$H/.agents/hooks.json" "$TMP/hooks.json.bak"
rm -f "$H/.agents/hooks.json"

python3 "$PARITY" "$H" >"$TMP/par_miss.out" 2>&1; prc=$?
[ "$prc" -eq 1 ] && grep -q 'hook-missing: .agents/hooks.json' "$TMP/par_miss.out" \
  && ok "P1-2: parity bắt đúng khi thiếu .agents/hooks.json ở repo gemini/antigravity" \
  || fail "P1-2: parity không bắt thiếu .agents/hooks.json (rc=$prc): $(cat "$TMP/par_miss.out")"

CLAUDE_PROJECT_DIR="$H" python3 "$HEALTH" -t "$H" >"$TMP/hl_miss.out" 2>&1; hrc=$?
[ "$hrc" -ne 0 ] && grep -q '.agents/hooks.json' "$TMP/hl_miss.out" \
  && ok "P1-2: agent-health thất bại khi thiếu .agents/hooks.json" \
  || fail "P1-2: agent-health không bắt thiếu .agents/hooks.json (rc=$hrc)"

# Phục hồi .agents/hooks.json rồi làm treo 1 đường dẫn script trong PreToolUse
cat > "$H/.agents/hooks.json" <<'JSON'
{
  "universal-agent-devkit": {
    "PreToolUse": [
      {
        "matcher": "run_command|send_command_input|shell_exec|manage_task",
        "hooks": [
          {"type": "command", "command": "bash hooks/agent_bridge.sh antigravity shell block-dangerous-git.sh", "timeout": 10},
          {"type": "command", "command": "bash hooks/agent_bridge.sh antigravity shell hardware_safety_gate.sh", "timeout": 10},
          {"type": "command", "command": "bash hooks/agent_bridge.sh antigravity shell does_not_exist_guard.sh", "timeout": 10}
        ]
      }
    ]
  }
}
JSON

python3 "$PARITY" "$H" >"$TMP/par_dang.out" 2>&1; prc=$?
[ "$prc" -eq 1 ] && grep -q 'hook-dangling: .agents/hooks.json' "$TMP/par_dang.out" \
  && ok "P1-2: parity bắt đúng script treo và chấp nhận matcher kèm manage_task" \
  || fail "P1-2: parity kiểm tra hook treo thất bại (rc=$prc): $(cat "$TMP/par_dang.out")"

CLAUDE_PROJECT_DIR="$H" python3 "$HEALTH" -t "$H" >"$TMP/hl_dang.out" 2>&1; hrc=$?
[ "$hrc" -ne 0 ] && grep -q 'does_not_exist_guard.sh' "$TMP/hl_dang.out" \
  && ok "P1-2: agent-health bắt đúng script treo trong .agents/hooks.json" \
  || fail "P1-2: agent-health không bắt script treo (rc=$hrc)"

# Repo chỉ cài claude (không gemini/antigravity) -> parity không báo thiếu .agents/hooks.json
C="$TMP/proj_c"
mkdir -p "$C"
(cd "$C" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false && echo x > f && git add f && git commit -qm init)
bash "$DEVKIT_DIR/bin/install.sh" -t "$C" -a claude -p backend -y >"$TMP/inst_c.out" 2>&1
python3 "$PARITY" "$C" >"$TMP/par_c.out" 2>&1; prc=$?
[ "$prc" -eq 0 ] && ok "P1-2: repo chỉ cài --agents=claude không bị parity báo lỗi giả .agents/hooks.json" \
  || fail "P1-2: repo claude-only bị lỗi parity (rc=$prc): $(cat "$TMP/par_c.out")"

# --- Ca C (P2-1): agent_bridge.sh xử lý manage_task ---
M="$TMP/proj_m"
mkdir -p "$M/.agents"
(cd "$M" && git init -q)

call_manage_task() {
  local guard="$1"
  local args_json="$2"
  local payload
  payload="$(python3 -c 'import json,sys; print(json.dumps({"toolCall":{"id":"mt1","name":"manage_task","args":json.loads(sys.argv[2])},"cwd":sys.argv[1]}))' "$M" "$args_json")"
  OUT="$(cd "$M/.agents" && printf '%s' "$payload" | bash "$BRIDGE" antigravity shell "$guard" 2>"$TMP/mt.err")"
  RC=$?
}

for act in status list kill; do
  call_manage_task block-dangerous-git.sh "{\"Action\":\"$act\",\"TaskId\":\"git reset --hard HEAD~1\"}"
  [ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "P2-1: manage_task Action=$act không chặn nhầm dù TaskId chứa chuỗi nguy hiểm" \
    || fail "P2-1: manage_task Action=$act bị chặn nhầm (rc=$RC out=$OUT)"
done

call_manage_task block-dangerous-git.sh '{"Action":"send_input","TaskId":"t1","Input":"git reset --hard HEAD~1\n"}'
[ "$RC" -eq 0 ] && printf '%s' "$OUT" | python3 -c 'import json,sys; assert json.load(sys.stdin)["decision"]=="deny"' 2>/dev/null \
  && ok "P2-1: manage_task send_input lệnh git nguy hiểm -> deny" \
  || fail "P2-1: manage_task send_input git nguy hiểm không deny (rc=$RC out=$OUT)"

call_manage_task hardware_safety_gate.sh '{"Action":"send_input","TaskId":"t1","Input":"adb remount\n"}'
[ "$RC" -eq 0 ] && printf '%s' "$OUT" | python3 -c 'import json,sys; assert json.load(sys.stdin)["decision"]=="deny"' 2>/dev/null \
  && ok "P2-1: manage_task send_input lệnh adb nguy hiểm -> deny" \
  || fail "P2-1: manage_task send_input adb nguy hiểm không deny (rc=$RC out=$OUT)"

call_manage_task block-dangerous-git.sh '{"Action":"send_input","TaskId":"t1","Input":"git status\n"}'
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "P2-1: manage_task send_input lệnh an toàn -> không output (không auto-allow)" \
  || fail "P2-1: manage_task send_input lệnh an toàn in output lạ (rc=$RC out=$OUT)"

[ "$FAILS" -eq 0 ] && { echo "test_antigravity_hooks_lifecycle: PASS"; exit 0; }
echo "test_antigravity_hooks_lifecycle: $FAILS FAILED"
exit 1
