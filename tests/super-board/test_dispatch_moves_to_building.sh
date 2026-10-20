#!/usr/bin/env bash
# Kiểm thử chống kẹt bảng Super-Board:
# 1. dispatch_lane chuyển thẻ Ready -> Building ngay khi giao worker build.
# 2. super_board_monitor.py tìm đúng transcript của repo có dấu chấm (Humans-vs.-UFOs).
# 3. top_card_in_column không bỏ kẹt thẻ Ready/QA/Review không có lock nhưng còn sót assignee của chính BOT_LOGIN (vẫn bỏ qua thẻ của người khác).
# 4. super-board-needs-you.py unmark xoá sổ early-deaths/<issue> để thẻ vừa gỡ needs-you không bị cầu chì SB_EARLY_MAX_TOTAL giữ kẹt.
# 5. super_board_all.py tự cấp quyền hasTrustDialogAccepted trong .claude.json và xoá early-deaths cũ khi start.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUN_SH="$REPO_ROOT/.claude/bin/super-board-run.sh"
NEEDS_YOU_PY="$REPO_ROOT/.claude/bin/super-board-needs-you.py"
MONITOR_PY="$REPO_ROOT/universal-agent-devkit/scripts/governance/super_board_monitor.py"
ALL_PY="$REPO_ROOT/universal-agent-devkit/scripts/governance/super_board_all.py"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

# 1. Kiểm tra dispatch_lane trong super-board-run.sh có chuyển thẻ từ Ready sang Building ngay khi claim
if grep -q 'set_card_status.*Building' "$RUN_SH"; then
  pass "dispatch_lane chuyển thẻ Ready -> Building ngay khi giao worker build"
else
  fail "dispatch_lane chưa chuyển thẻ Ready -> Building ngay khi giao worker build"
fi

# 2. Kiểm tra find_latest_jsonl trong super_board_monitor.py tìm được thư mục project có dấu chấm (vd Humans-vs.-UFOs -> -Volumes-...-Humans-vs--UFOs)
out=$(python3 - "$MONITOR_PY" <<'PY'
import importlib.util, os, sys, tempfile

spec = importlib.util.spec_from_file_location("sb_mon", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

with tempfile.TemporaryDirectory() as home:
    os.environ["HOME"] = home
    repo_dir = "/Volumes/Data/Toan/Game/Humans-vs.-UFOs"
    proj_dir = os.path.join(home, ".claude-finos", "projects", "-Volumes-Data-Toan-Game-Humans-vs--UFOs")
    os.makedirs(proj_dir, exist_ok=True)
    jsonl = os.path.join(proj_dir, "session-1.jsonl")
    with open(jsonl, "w") as f:
        f.write("{}\n")
    found = mod.find_latest_jsonl(repo_dir)
    print(found or "NONE")
PY
)

if [[ "$out" == *"session-1.jsonl" ]]; then
  pass "super_board_monitor.py tìm đúng transcript của repo có dấu chấm trong tên (Humans-vs.-UFOs)"
else
  fail "super_board_monitor.py KHÔNG tìm thấy transcript của repo có dấu chấm (out=$out)"
fi

# 3. Kiểm tra top_card_in_column nhận lại thẻ không có lock mà còn sót assignee của chính BOT_LOGIN, nhưng vẫn bỏ qua thẻ giao cho người khác
top_out=$(bash -c '
  RUNNER="$1"
  TMP=$(mktemp -d "${TMPDIR:-/tmp}/sb-bot-assignee.XXXXXX")
  trap "rm -rf \"$TMP\"" EXIT
  SB_LIB_ONLY=1 . "$RUNNER"
  set +e
  INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"
  BOT_LOGIN="ToanMobile"
  NO_DEVICE=0
  gh_checkpoint() { :; }
  issue_is_open() { return 0; }
  log() { :; }
  PROJECT_ITEMS_JSON="{\"items\":[
    {\"id\":\"PVTI_1\",\"status\":\"QA\",\"labels\":[],\"content\":{\"type\":\"Issue\",\"number\":101,\"assignees\":[\"alice\"]}},
    {\"id\":\"PVTI_2\",\"status\":\"QA\",\"labels\":[],\"content\":{\"type\":\"Issue\",\"number\":102,\"assignees\":[\"ToanMobile\"]}}
  ]}"
  if top_card_in_column "QA"; then
    echo "PICKED=$TOP_ISSUE"
  else
    echo "PICKED=NONE"
  fi
' _ "$RUN_SH")

if [[ "$top_out" == "PICKED=102" ]]; then
  pass "top_card_in_column nhận lại thẻ không có lock còn sót assignee BOT_LOGIN (#102) và bỏ qua thẻ của người khác (#101)"
else
  fail "top_card_in_column làm kẹt thẻ còn sót assignee BOT_LOGIN ($top_out)"
fi

# 4. Kiểm tra super-board-needs-you.py unmark xoá file early-deaths/<issue>
ed_out=$(python3 - "$NEEDS_YOU_PY" <<'PY'
import importlib.util, os, sys, tempfile

spec = importlib.util.spec_from_file_location("sb_ny", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

with tempfile.TemporaryDirectory() as tmp:
    cwd = os.getcwd()
    try:
        os.chdir(tmp)
        ed_dir = os.path.join(".claude", "super-board", "inflight", "early-deaths")
        os.makedirs(ed_dir, exist_ok=True)
        ed_file = os.path.join(ed_dir, "114")
        with open(ed_file, "w") as f:
            f.write("1700000000 review\n1700000100 review\n1700000200 review\n")
        mod.read_issue = lambda repo, issue: (["needs-you"], [], "")
        mod.remove_label = lambda repo, issue, name: True
        mod.gh = lambda *a, **kw: {}
        res = mod.unmark("ToanMobile/OfficeReader", 114, False)
        print("GONE" if not os.path.exists(ed_file) else "STILL_THERE")
    finally:
        os.chdir(cwd)
PY
)

if [[ "$ed_out" == "GONE" ]]; then
  pass "super-board-needs-you.py unmark tự động xoá early-deaths/<issue> khi gỡ needs-you"
else
  fail "super-board-needs-you.py unmark chưa xoá early-deaths/<issue> (ed_out=$ed_out)"
fi

# 5. Kiểm tra super_board_all.py có ensure_claude_workspace_trust và clear_early_deaths
all_out=$(python3 - "$ALL_PY" <<'PY'
import importlib.util, json, os, sys, tempfile

spec = importlib.util.spec_from_file_location("sb_all", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

if not hasattr(mod, "ensure_claude_workspace_trust") or not hasattr(mod, "clear_early_deaths"):
    print("MISSING_FUNCS")
    sys.exit(0)

with tempfile.TemporaryDirectory() as home:
    cfg = os.path.join(home, ".claude-finos", ".claude.json")
    os.makedirs(os.path.dirname(cfg), exist_ok=True)
    with open(cfg, "w") as f:
        json.dump({"projects": {}}, f)
    rdir = os.path.join(home, "repo1")
    ed = os.path.join(rdir, ".claude", "super-board", "inflight", "early-deaths", "42")
    os.makedirs(os.path.dirname(ed), exist_ok=True)
    with open(ed, "w") as f:
        f.write("1700000000 build\n")
    mod.ensure_claude_workspace_trust(home_dir=home, repo_dirs=[rdir])
    mod.clear_early_deaths(rdir)
    data = json.load(open(cfg))
    trusted = data.get("projects", {}).get(rdir, {}).get("hasTrustDialogAccepted") is True
    cleared = not os.path.exists(ed)
    print("OK" if (trusted and cleared) else f"BAD:trusted={trusted},cleared={cleared}")
PY
)

if [[ "$all_out" == "OK" ]]; then
  pass "super_board_all.py tự cấp quyền hasTrustDialogAccepted trong .claude.json và xoá early-deaths cũ"
else
  fail "super_board_all.py thiếu cơ chế tự cấp quyền workspace trust hoặc xoá early-deaths ($all_out)"
fi

# 6. Kiểm tra hardware_safety_gate.sh chặn mọi lệnh mở Android Emulator thiếu -no-window và cho phép khi có -no-window / -list-avds / PROOF_WINDOW=1
GATE_SH="$REPO_ROOT/universal-agent-devkit/hooks/hardware_safety_gate.sh"
run_gate() {
  local cmd_str="$1"
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$cmd_str")" \
    | REPO_ROOT="$REPO_ROOT" bash "$GATE_SH" >/dev/null 2>&1
  echo $?
}
rc_win1=$(run_gate "nohup /Volumes/Data/AndroidSDK/emulator/emulator -avd PhoneConnect -port 5556 -no-snapshot-save -no-audio > /tmp/emu.log 2>&1 &")
rc_win2=$(run_gate "EMU=/Volumes/Data/AndroidSDK/emulator/emulator; (nohup \$EMU -avd PhoneConnect -port 5556 -no-boot-anim &)")
rc_win3=$(run_gate "emulator @PhoneConnect -port 5556")
rc_ok1=$(run_gate "nohup /Volumes/Data/AndroidSDK/emulator/emulator -avd PhoneConnect -port 5556 -no-window -no-snapshot-save -no-audio > /tmp/emu.log 2>&1 &")
rc_ok2=$(run_gate "/Volumes/Data/AndroidSDK/emulator/emulator -list-avds")
rc_ok3=$(run_gate "PROOF_WINDOW=1 /Volumes/Data/AndroidSDK/emulator/emulator -avd PhoneConnect -port 5556")

if [[ "$rc_win1" -eq 2 && "$rc_win2" -eq 2 && "$rc_win3" -eq 2 && "$rc_ok1" -eq 0 && "$rc_ok2" -eq 0 && "$rc_ok3" -eq 0 ]]; then
  pass "hardware_safety_gate.sh chặn tuyệt đối lệnh mở emulator thiếu -no-window (exit 2) và cho phép -no-window / -list-avds / PROOF_WINDOW=1 (exit 0)"
else
  fail "hardware_safety_gate.sh kiểm tra -no-window chưa đúng (win1=$rc_win1 win2=$rc_win2 win3=$rc_win3 ok1=$rc_ok1 ok2=$rc_ok2 ok3=$rc_ok3)"
fi

echo ""
echo "Summary: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
