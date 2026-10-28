#!/usr/bin/env bash
# Kiểm thử đơn vị và tích hợp cho scripts/testing/skill_eval.py (runner A/B đo hiệu quả skill DevKit).
# Tuân thủ bash 3.2, chạy hoàn toàn bằng claude giả (không gọi claude thật hay mạng ngoài).

. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -uo pipefail

DEVKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_EVAL_PY="$DEVKIT_ROOT/scripts/testing/skill_eval.py"

# Tạo thư mục tạm có tiền tố test_ để đồng thời kiểm chứng chuẩn hoá đường dẫn tương đối ở ca 4
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test_skill_eval.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

FAILS=0
PASSES=0

pass() {
  echo "  ✔ $1"
  PASSES=$((PASSES + 1))
}

fail() {
  echo "  ✖ FAIL: $1"
  FAILS=$((FAILS + 1))
}

echo "=== Verification: skill_eval.py A/B runner & pilot evals ==="

# Kiểm tra sự tồn tại và quyền thực thi của skill_eval.py trước khi chạy các ca
if [[ -f "$SKILL_EVAL_PY" && -x "$SKILL_EVAL_PY" ]]; then
  pass "scripts/testing/skill_eval.py tồn tại và có quyền thực thi (+x)"
else
  fail "scripts/testing/skill_eval.py thiếu hoặc chưa có quyền +x"
fi

# ---------------------------------------------------------------------------
# Dựng claude giả viết bằng Python (đóng hộp stream-json theo biến môi trường)
# ---------------------------------------------------------------------------
FAKE_BIN_DIR="$TMP/fake_bin"
mkdir -p "$FAKE_BIN_DIR"
FAKE_CLAUDE="$FAKE_BIN_DIR/fake_claude.py"

cat >"$FAKE_CLAUDE" <<'PY'
#!/usr/bin/env python3
# Chương trình giả lập CLI claude để kiểm thử cô lập mọi nhánh của skill_eval.py
import json
import os
import sys
import time

argv = sys.argv[1:]
cwd = os.getcwd()
stdin_data = sys.stdin.read()

# Ghi nhận lời gọi vào file log nếu ca test yêu cầu
call_log = os.environ.get("FAKE_CLAUDE_LOG", "")
if call_log:
    rec = {
        "argv": argv,
        "cwd": cwd,
        "stdin_len": len(stdin_data),
        "claude_config_dir": os.environ.get("CLAUDE_CONFIG_DIR"),
    }
    with open(call_log, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(rec, ensure_ascii=False) + "\n")

mode = os.environ.get("FAKE_CLAUDE_MODE", "normal")

if mode == "sleep_timeout":
    print(json.dumps({"type": "system", "subtype": "init", "skills": [], "marker": "ONCE_BEFORE_TIMEOUT"}), flush=True)
    time.sleep(30)
    sys.exit(0)

if mode == "judge_a_fenced":
    init_ev = {"type": "system", "subtype": "init", "skills": [], "model": "fake-judge"}
    res_txt = '```json\n{"winner": "A", "reasoning": "Bản A tuân thủ hệ thống thiết kế tốt hơn"}\n```'
    res_ev = {
        "type": "result",
        "subtype": "success",
        "is_error": False,
        "total_cost_usd": 0.002,
        "num_turns": 1,
        "duration_ms": 250,
        "result": res_txt,
        "usage": {"input_tokens": 200, "output_tokens": 50},
    }
    print(json.dumps(init_ev))
    print(json.dumps(res_ev))
    sys.exit(0)

if mode == "judge_inner_backticks":
    init_ev = {"type": "system", "subtype": "init", "skills": [], "model": "fake-judge"}
    payload = {
        "winner": "A",
        "reasoning": "Bản A đã xoá khối ```css\na:focus { outline: none; }\n``` và bổ sung :focus-visible.",
    }
    res_txt = json.dumps(payload, ensure_ascii=False)
    if os.environ.get("FAKE_CLAUDE_OUTER_FENCE") == "1":
        res_txt = "```json\n" + res_txt + "\n```"
    res_ev = {
        "type": "result",
        "subtype": "success",
        "is_error": False,
        "total_cost_usd": 0.002,
        "num_turns": 1,
        "duration_ms": 210,
        "result": res_txt,
        "usage": {"input_tokens": 200, "output_tokens": 60},
    }
    print(json.dumps(init_ev))
    print(json.dumps(res_ev))
    sys.exit(0)

if mode == "judge_bad_json":
    init_ev = {"type": "system", "subtype": "init", "skills": [], "model": "fake-judge"}
    res_ev = {
        "type": "result",
        "subtype": "success",
        "is_error": False,
        "total_cost_usd": 0.001,
        "num_turns": 1,
        "duration_ms": 100,
        "result": "Khong phai JSON hop le",
        "usage": {"input_tokens": 100, "output_tokens": 20},
    }
    print(json.dumps(init_ev))
    print(json.dumps(res_ev))
    sys.exit(0)

# Xác định danh sách skill xuất hiện trong sự kiện init
skills_dir = os.path.join(cwd, ".claude", "skills")
installed_skills = []
if os.path.isdir(skills_dir):
    installed_skills = sorted(
        d for d in os.listdir(skills_dir) if os.path.isdir(os.path.join(skills_dir, d))
    )

if mode == "force_leak":
    leak_name = os.environ.get("FAKE_CLAUDE_LEAK_SKILL", "demo-skill")
    if leak_name not in installed_skills:
        installed_skills.append(leak_name)
elif mode == "force_missing_skill":
    installed_skills = []

# Kèm một dòng không phải JSON hợp lệ để xác minh parser đếm bad_lines thay vì sập
if os.environ.get("FAKE_CLAUDE_EMIT_BAD_LINE") == "1":
    print("NOT_VALID_JSON_LINE")

init_ev = {
    "type": "system",
    "subtype": "init",
    "skills": installed_skills,
    "slash_commands": installed_skills,
    "tools": ["Read", "Edit", "Write", "Bash"],
    "model": "fake-sonnet",
}
print(json.dumps(init_ev))

# Phát sinh chuỗi sự kiện tool_use theo kịch bản kiểm thử
scenario = os.environ.get("FAKE_CLAUDE_TOOL_SCENARIO", "default")
abs_app = os.path.join(cwd, "app.py")
abs_test = os.path.join(cwd, "test_app.py")
outside_file = os.environ.get("FAKE_CLAUDE_OUTSIDE_PATH", "")

tool_uses = []
if scenario == "test_before_edit":
    tool_uses = [
        {"type": "tool_use", "id": "t1", "name": "Bash", "input": {"command": "python3 -m unittest"}},
        {"type": "tool_use", "id": "t2", "name": "Edit", "input": {"file_path": abs_app}},
    ]
elif scenario == "edit_before_test":
    tool_uses = [
        {"type": "tool_use", "id": "t1", "name": "Edit", "input": {"file_path": abs_app}},
        {"type": "tool_use", "id": "t2", "name": "Bash", "input": {"command": "python3 -m unittest"}},
    ]
elif scenario == "edit_testfile_then_bash_then_prod":
    tool_uses = [
        {"type": "tool_use", "id": "t1", "name": "Write", "input": {"file_path": abs_test}},
        {"type": "tool_use", "id": "t2", "name": "Bash", "input": {"command": "python3 -m unittest"}},
        {"type": "tool_use", "id": "t3", "name": "Edit", "input": {"file_path": abs_app}},
    ]
elif scenario == "outside_edit" and outside_file:
    tool_uses = [
        {"type": "tool_use", "id": "t1", "name": "Edit", "input": {"file_path": outside_file}},
    ]

if tool_uses:
    print(json.dumps({"type": "assistant", "message": {"content": tool_uses}}))

# Ghi file đầu ra trong project nếu kịch bản yêu cầu
write_out = os.environ.get("FAKE_CLAUDE_WRITE_OUT", "")
if write_out:
    with open(os.path.join(cwd, "out.txt"), "w", encoding="utf-8") as fh:
        fh.write(write_out)

if os.environ.get("FAKE_CLAUDE_TAMPER_PROJECT") == "1":
    with open(os.path.join(cwd, "DESIGN.md"), "w", encoding="utf-8") as fh:
        fh.write("TAMPERED_BY_AGENT\n")
    os.makedirs(os.path.join(cwd, ".impeccable"), exist_ok=True)
    with open(os.path.join(cwd, ".impeccable", "config.json"), "w", encoding="utf-8") as fh:
        fh.write('{"ignore": true}\n')

res_ev = {
    "type": "result",
    "subtype": "success",
    "is_error": False,
    "total_cost_usd": 0.0125,
    "num_turns": 2,
    "duration_ms": 1500,
    "result": os.environ.get("FAKE_CLAUDE_RESULT_TEXT", "DONE_OK"),
    "usage": {
        "input_tokens": 500,
        "output_tokens": 150,
        "cache_creation_input_tokens": 50,
        "cache_read_input_tokens": 300,
    },
}
print(json.dumps(res_ev))
PY
chmod +x "$FAKE_CLAUDE"
export SKILL_EVAL_CLAUDE_BIN="$FAKE_CLAUDE"

# Dựng skill giả cơ bản để test các ca 1-9
DEMO_SKILL_DIR="$TMP/fixtures/skills/demo-skill"
mkdir -p "$DEMO_SKILL_DIR/evals/files/eval-1/input" "$DEMO_SKILL_DIR/evals/files/eval-1/oracle" "$DEMO_SKILL_DIR/scripts"
cat >"$DEMO_SKILL_DIR/SKILL.md" <<'EOF'
---
name: demo-skill
description: Dùng khi kiểm thử runner skill_eval. Bỏ qua khi chạy thật.
---
# Demo Skill
EOF
printf 'helper content\n' >"$DEMO_SKILL_DIR/helper.txt"
printf 'def add(a, b):\n    return a - b\n' >"$DEMO_SKILL_DIR/evals/files/eval-1/input/app.py"
printf 'DESIGN_CANONICAL\n' >"$DEMO_SKILL_DIR/evals/files/eval-1/input/DESIGN.md"
printf 'ORACLE_SECRET\n' >"$DEMO_SKILL_DIR/evals/files/eval-1/oracle/test_oracle.py"

cat >"$DEMO_SKILL_DIR/evals/evals.json" <<'EOF'
{
  "skill_name": "demo-skill",
  "evals": [
    {
      "id": 1,
      "prompt": "Sua ham add trong app.py",
      "expected_output": "Ham add tra ve tong dung",
      "files_dir": "evals/files/eval-1/input",
      "disallowed_tools": "Bash(*dangerous*) WebFetch",
      "expectations": [
        "Co chay test truoc khi sua"
      ],
      "checks": [
        {
          "id": "order_tdd",
          "text": "Chay unittest truoc khi sua file production",
          "type": "tool_order",
          "first": {"tool": "Bash", "command_regex": "python3 -m unittest"},
          "before": {"tool": "Edit|Write", "path_not_regex": "(^|/)test_"}
        },
        {
          "id": "res_ok",
          "text": "Ket qua cuoi chua DONE_OK",
          "type": "result_regex",
          "regex": "DONE_OK"
        }
      ]
    }
  ]
}
EOF

# ---------------------------------------------------------------------------
# Ca 1: Chặn nhiễm workspace có cha chứa AGENTS.md / CLAUDE.md / .claude (exit 2)
#       và cho phép workspace sạch (exit 0)
# ---------------------------------------------------------------------------
DIRTY_AGENTS="$TMP/dirty_agents"
mkdir -p "$DIRTY_AGENTS/sub"
touch "$DIRTY_AGENTS/AGENTS.md"
python3 "$SKILL_EVAL_PY" run --skill demo-skill --evals "$DEMO_SKILL_DIR/evals/evals.json" \
  --workspace "$DIRTY_AGENTS/sub/ws" --runs 1 >"$TMP/c1_d1.out" 2>"$TMP/c1_d1.err"
RC_DIRTY1=$?

DIRTY_CLAUDE_MD="$TMP/dirty_claude_md"
mkdir -p "$DIRTY_CLAUDE_MD/sub"
touch "$DIRTY_CLAUDE_MD/CLAUDE.md"
python3 "$SKILL_EVAL_PY" run --skill demo-skill --evals "$DEMO_SKILL_DIR/evals/evals.json" \
  --workspace "$DIRTY_CLAUDE_MD/sub/ws" --runs 1 >"$TMP/c1_d2.out" 2>"$TMP/c1_d2.err"
RC_DIRTY2=$?

DIRTY_DOT_CLAUDE="$TMP/dirty_dot_claude"
mkdir -p "$DIRTY_DOT_CLAUDE/.claude" "$DIRTY_DOT_CLAUDE/sub"
python3 "$SKILL_EVAL_PY" run --skill demo-skill --evals "$DEMO_SKILL_DIR/evals/evals.json" \
  --workspace "$DIRTY_DOT_CLAUDE/sub/ws" --runs 1 >"$TMP/c1_d3.out" 2>"$TMP/c1_d3.err"
RC_DIRTY3=$?

# Symlink từ thư mục sạch trỏ vào thư mục bẩn -> phải bị từ chối (exit 2)
CLEAN_LINK_HOLDER="$TMP/clean_link_holder"
mkdir -p "$CLEAN_LINK_HOLDER"
ln -s "$DIRTY_AGENTS/sub" "$CLEAN_LINK_HOLDER/sym_to_dirty"
python3 "$SKILL_EVAL_PY" run --skill demo-skill --evals "$DEMO_SKILL_DIR/evals/evals.json" \
  --workspace "$CLEAN_LINK_HOLDER/sym_to_dirty/ws" --runs 1 >"$TMP/c1_d4.out" 2>"$TMP/c1_d4.err"
RC_DIRTY4=$?

# Đường dẫn --workspace tương đối chạy từ bên trong thư mục bẩn -> phải bị từ chối (exit 2)
(
  cd "$DIRTY_AGENTS/sub" && python3 "$SKILL_EVAL_PY" run --skill demo-skill \
    --evals "$DEMO_SKILL_DIR/evals/evals.json" --workspace "rel_ws" --runs 1 \
    >"$TMP/c1_d5.out" 2>"$TMP/c1_d5.err"
)
RC_DIRTY5=$?

if [[ "$RC_DIRTY1" -eq 2 && "$RC_DIRTY2" -eq 2 && "$RC_DIRTY3" -eq 2 && "$RC_DIRTY4" -eq 2 && "$RC_DIRTY5" -eq 2 ]] \
  && grep -q "AGENTS.md" "$TMP/c1_d1.err" \
  && grep -q "CLAUDE.md" "$TMP/c1_d2.err" \
  && grep -q "\.claude" "$TMP/c1_d3.err" \
  && grep -q "AGENTS.md" "$TMP/c1_d4.err" \
  && grep -q "AGENTS.md" "$TMP/c1_d5.err"; then
  pass "Ca 1a: Từ chối đúng (exit 2) khi thư mục cha workspace chứa AGENTS.md, CLAUDE.md, .claude (kể cả qua symlink và đường dẫn tương đối)"
else
  fail "Ca 1a: Chặn nhiễm chưa đạt (rcs=$RC_DIRTY1/$RC_DIRTY2/$RC_DIRTY3/$RC_DIRTY4/$RC_DIRTY5)"
fi

WS1_CLEAN="$TMP/ws_case1_clean"
python3 "$SKILL_EVAL_PY" run --skill demo-skill --evals "$DEMO_SKILL_DIR/evals/evals.json" \
  --workspace "$WS1_CLEAN" --runs 1 --configs with_skill >/dev/null 2>&1
RC_CLEAN1=$?
if [[ "$RC_CLEAN1" -eq 0 && -f "$WS1_CLEAN/demo-skill/eval-1/with_skill/run-1/run.json" ]]; then
  pass "Ca 1b: Workspace sạch ngoài cây dự án chạy thành công (exit 0)"
else
  fail "Ca 1b: Workspace sạch thất bại (rc=$RC_CLEAN1)"
fi

# ---------------------------------------------------------------------------
# Ca 2: Thiết lập with_skill vs without_skill, argv, stdin rỗng, bỏ evals/ khi chép skill
# ---------------------------------------------------------------------------
WS2="$TMP/ws_case2"
LOG2="$TMP/case2_calls.jsonl"
FAKE_CLAUDE_LOG="$LOG2" FAKE_CLAUDE_EMIT_BAD_LINE=1 \
  python3 "$SKILL_EVAL_PY" run --skill demo-skill --evals "$DEMO_SKILL_DIR/evals/evals.json" \
  --workspace "$WS2" --runs 1 --configs with_skill,without_skill --model haiku --budget-usd 0.25 >/dev/null 2>&1
RC2=$?

python3 - "$WS2" "$LOG2" "$RC2" >"$TMP/c2.out" <<'PY'
import json, os, sys

ws, log_path, rc = sys.argv[1], sys.argv[2], int(sys.argv[3])
if rc != 0:
    print(f"ERR:rc={rc}")
    sys.exit(0)

w_proj = os.path.join(ws, "demo-skill", "eval-1", "with_skill", "run-1", "project")
wo_proj = os.path.join(ws, "demo-skill", "eval-1", "without_skill", "run-1", "project")

if not os.path.isfile(os.path.join(w_proj, ".claude", "skills", "demo-skill", "SKILL.md")):
    print("ERR:with_skill missing SKILL.md")
    sys.exit(0)
if not os.path.isfile(os.path.join(w_proj, ".claude", "skills", "demo-skill", "helper.txt")):
    print("ERR:with_skill missing helper.txt")
    sys.exit(0)
if os.path.exists(os.path.join(w_proj, ".claude", "skills", "demo-skill", "evals")):
    print("ERR:with_skill leaked evals/ into .claude/skills")
    sys.exit(0)
if os.path.exists(os.path.join(wo_proj, ".claude", "skills")) or os.path.exists(os.path.join(wo_proj, ".claude")):
    print("ERR:without_skill must not have .claude/skills")
    sys.exit(0)

if os.path.exists(os.path.join(w_proj, "test_oracle.py")) or os.path.exists(os.path.join(w_proj, "oracle")):
    print("ERR:oracle leaked into project/")
    sys.exit(0)
w_run = json.load(open(os.path.join(ws, "demo-skill", "eval-1", "with_skill", "run-1", "run.json"), encoding="utf-8"))
if w_run.get("bad_lines") != 1 or w_run.get("tokens") != 1000:
    print(f"ERR:bad_lines={w_run.get('bad_lines')} tokens={w_run.get('tokens')}")
    sys.exit(0)

calls = [json.loads(line) for line in open(log_path, encoding="utf-8") if line.strip()]
if len(calls) != 2:
    print(f"ERR:expected 2 calls, got {len(calls)}")
    sys.exit(0)

by_cfg = {}
for c in calls:
    argv = c["argv"]
    p_idx = argv.index("-p")
    prompt = argv[p_idx + 1]
    cfg = "with_skill" if prompt.startswith("/demo-skill ") else "without_skill"
    by_cfg[cfg] = (c, argv, prompt)

if set(by_cfg.keys()) != {"with_skill", "without_skill"}:
    print(f"ERR:missing config in calls: {list(by_cfg.keys())}")
    sys.exit(0)

for cfg, (c, argv, prompt) in by_cfg.items():
    if c["stdin_len"] != 0:
        print(f"ERR:{cfg} stdin not empty")
        sys.exit(0)
    if cfg == "without_skill" and prompt.startswith("/"):
        print(f"ERR:without_skill prompt starts with /: {prompt}")
        sys.exit(0)
    for flag, expected in [
        ("--setting-sources", "project"),
        ("--max-budget-usd", "0.25"),
        ("--permission-mode", "acceptEdits"),
        ("--permission-prompts", "none"),
    ]:
        if flag not in argv or argv[argv.index(flag) + 1] != expected:
            print(f"ERR:{cfg} missing {flag}={expected}: {argv}")
            sys.exit(0)
    if "--disallowedTools" not in argv:
        print(f"ERR:{cfg} missing --disallowedTools")
        sys.exit(0)
    dis = argv[argv.index("--disallowedTools") + 1]
    for item in ("AskUserQuestion", "Bash(*dangerous*)", "WebFetch"):
        if item not in dis:
            print(f"ERR:{cfg} disallowedTools missing {item}: {dis}")
            sys.exit(0)

print("OK")
PY
if [[ "$(cat "$TMP/c2.out")" == "OK" ]]; then
  pass "Ca 2: with_skill/without_skill thiết lập đúng .claude/skills (bỏ evals/), prompt, flags, disallowedTools, stdin rỗng"
else
  fail "Ca 2 thất bại: $(cat "$TMP/c2.out")"
fi

# ---------------------------------------------------------------------------
# Ca 3: Phát hiện leak ở without_skill và skill_missing ở with_skill; aggregate loại ô lỗi & exit 1
# ---------------------------------------------------------------------------
WS3="$TMP/ws_case3"
# Lượt run 1 của without_skill bị leak; with_skill hợp lệ
FAKE_CLAUDE_MODE=force_leak FAKE_CLAUDE_LEAK_SKILL=demo-skill \
  python3 "$SKILL_EVAL_PY" run --skill demo-skill --evals "$DEMO_SKILL_DIR/evals/evals.json" \
  --workspace "$WS3" --runs 1 --configs without_skill >/dev/null 2>&1
RC3_LEAK=$?

python3 "$SKILL_EVAL_PY" run --skill demo-skill --evals "$DEMO_SKILL_DIR/evals/evals.json" \
  --workspace "$WS3" --runs 1 --configs with_skill >/dev/null 2>&1
RC3_OK=$?

python3 "$SKILL_EVAL_PY" grade --skill demo-skill --evals "$DEMO_SKILL_DIR/evals/evals.json" \
  --workspace "$WS3" >/dev/null 2>&1
python3 "$SKILL_EVAL_PY" aggregate --skill demo-skill --workspace "$WS3" >/dev/null 2>&1
RC3_AGG=$?

WS3_MISS="$TMP/ws_case3_miss"
FAKE_CLAUDE_MODE=force_missing_skill \
  python3 "$SKILL_EVAL_PY" run --skill demo-skill --evals "$DEMO_SKILL_DIR/evals/evals.json" \
  --workspace "$WS3_MISS" --runs 1 --configs with_skill >/dev/null 2>&1
RC3_MISS=$?

python3 - "$WS3" "$WS3_MISS" "$RC3_LEAK" "$RC3_OK" "$RC3_AGG" "$RC3_MISS" >"$TMP/c3.out" <<'PY'
import json, os, sys

ws3, ws_miss = sys.argv[1], sys.argv[2]
rc_leak, rc_ok, rc_agg, rc_miss = map(int, sys.argv[3:7])

if rc_leak != 1 or rc_ok != 0 or rc_agg != 1 or rc_miss != 1:
    print(f"ERR:rcs leak={rc_leak} ok={rc_ok} agg={rc_agg} miss={rc_miss}")
    sys.exit(0)

wo_run = json.load(open(os.path.join(ws3, "demo-skill", "eval-1", "without_skill", "run-1", "run.json"), encoding="utf-8"))
if not wo_run.get("leak") or wo_run.get("valid"):
    print(f"ERR:leak run.json wrong: {wo_run}")
    sys.exit(0)

miss_run = json.load(open(os.path.join(ws_miss, "demo-skill", "eval-1", "with_skill", "run-1", "run.json"), encoding="utf-8"))
if not miss_run.get("skill_missing") or miss_run.get("valid"):
    print(f"ERR:missing run.json wrong: {miss_run}")
    sys.exit(0)

bench = json.load(open(os.path.join(ws3, "demo-skill", "benchmark.json"), encoding="utf-8"))
if any(r.get("configuration") == "without_skill" for r in bench.get("runs", [])):
    print("ERR:leaked cell was not excluded from benchmark runs")
    sys.exit(0)
if bench["run_summary"]["without_skill"]["pass_rate"]["mean"] is not None:
    print(f"ERR:without_skill summary should be null when only cell leaked: {bench['run_summary']['without_skill']}")
    sys.exit(0)
if not any("leak" in n.lower() for n in bench.get("notes", [])):
    print(f"ERR:notes missing leak warning: {bench.get('notes')}")
    sys.exit(0)

print("OK")
PY
if [[ "$(cat "$TMP/c3.out")" == "OK" ]]; then
  pass "Ca 3: Phát hiện đúng leak (without_skill) & skill_missing (with_skill), loại khỏi tổng hợp và aggregate exit 1"
else
  fail "Ca 3 thất bại: $(cat "$TMP/c3.out")"
fi

# ---------------------------------------------------------------------------
# Ca 4: tool_order đạt / không đạt + chuẩn hoá file_path tuyệt đối dưới thư mục cha test_ab_...
# ---------------------------------------------------------------------------
WS4_PASS="$TMP/test_ab_parent/ws_pass"
WS4_FAIL="$TMP/test_ab_parent/ws_fail"
WS4_TESTFILE="$TMP/test_ab_parent/ws_testfile"

FAKE_CLAUDE_TOOL_SCENARIO=test_before_edit \
  python3 "$SKILL_EVAL_PY" run --skill demo-skill --evals "$DEMO_SKILL_DIR/evals/evals.json" \
  --workspace "$WS4_PASS" --runs 1 --configs with_skill >/dev/null 2>&1
python3 "$SKILL_EVAL_PY" grade --skill demo-skill --evals "$DEMO_SKILL_DIR/evals/evals.json" \
  --workspace "$WS4_PASS" >/dev/null 2>&1

FAKE_CLAUDE_TOOL_SCENARIO=edit_before_test \
  python3 "$SKILL_EVAL_PY" run --skill demo-skill --evals "$DEMO_SKILL_DIR/evals/evals.json" \
  --workspace "$WS4_FAIL" --runs 1 --configs with_skill >/dev/null 2>&1
python3 "$SKILL_EVAL_PY" grade --skill demo-skill --evals "$DEMO_SKILL_DIR/evals/evals.json" \
  --workspace "$WS4_FAIL" >/dev/null 2>&1

FAKE_CLAUDE_TOOL_SCENARIO=edit_testfile_then_bash_then_prod \
  python3 "$SKILL_EVAL_PY" run --skill demo-skill --evals "$DEMO_SKILL_DIR/evals/evals.json" \
  --workspace "$WS4_TESTFILE" --runs 1 --configs with_skill >/dev/null 2>&1
python3 "$SKILL_EVAL_PY" grade --skill demo-skill --evals "$DEMO_SKILL_DIR/evals/evals.json" \
  --workspace "$WS4_TESTFILE" >/dev/null 2>&1

python3 - "$WS4_PASS" "$WS4_FAIL" "$WS4_TESTFILE" >"$TMP/c4.out" <<'PY'
import json, os, sys

ws_p, ws_f, ws_t = sys.argv[1:4]

def get_order_check(ws):
    gp = os.path.join(ws, "demo-skill", "eval-1", "with_skill", "run-1", "grading.json")
    rp = os.path.join(ws, "demo-skill", "eval-1", "with_skill", "run-1", "run.json")
    if not os.path.isfile(gp) or not os.path.isfile(rp):
        print(f"ERR:missing grading/run in {ws}")
        sys.exit(0)
    g = json.load(open(gp, encoding="utf-8"))
    r = json.load(open(rp, encoding="utf-8"))
    return g["expectations"][0]["passed"], r["tool_events"]

p_ok, ev_p = get_order_check(ws_p)
f_ok, ev_f = get_order_check(ws_f)
t_ok, ev_t = get_order_check(ws_t)

if ev_f[0].get("file_path") != "app.py":
    print(f"ERR:file_path not normalized to relative app.py: {ev_f[0]}")
    sys.exit(0)
if not p_ok:
    print("ERR:test_before_edit should pass")
    sys.exit(0)
if f_ok:
    print("ERR:edit_before_test under test_ab_parent must fail")
    sys.exit(0)
if not t_ok:
    print("ERR:editing test_app.py before Bash test then app.py should pass")
    sys.exit(0)

print("OK")
PY
if [[ "$(cat "$TMP/c4.out")" == "OK" ]]; then
  pass "Ca 4: tool_order đạt/trượt chính xác, Edit test_*.py không tính là production, chuẩn hoá đường dẫn tuyệt đối dưới test_ab_..."
else
  fail "Ca 4 thất bại: $(cat "$TMP/c4.out")"
fi

# ---------------------------------------------------------------------------
# Ca 5: command + oracle_files + remove_paths + unavailable (exit 127, 0/0 -> null) + {skill_dir} + chặn ..
# ---------------------------------------------------------------------------
CMD_SKILL_DIR="$TMP/fixtures/skills/cmd-skill"
mkdir -p "$CMD_SKILL_DIR/evals/in" "$CMD_SKILL_DIR/evals/oracle" "$CMD_SKILL_DIR/scripts"
cat >"$CMD_SKILL_DIR/SKILL.md" <<'EOF'
---
name: cmd-skill
description: Dùng khi kiểm thử check command. Bỏ qua khi chạy thật.
---
# Cmd Skill
EOF
printf 'DESIGN_ORIGINAL\n' >"$CMD_SKILL_DIR/evals/in/DESIGN.md"
printf 'DESIGN_ORIGINAL\n' >"$CMD_SKILL_DIR/evals/oracle/DESIGN.md"
printf 'SECRET_ORACLE_TOKEN\n' >"$CMD_SKILL_DIR/evals/oracle/oracle_verify.txt"

cat >"$CMD_SKILL_DIR/scripts/checker.py" <<'PY'
import os, sys

# Xác nhận DESIGN.md đã được oracle_files chép đè và .impeccable đã bị remove_paths xoá trong bản chấm
design = open("DESIGN.md", encoding="utf-8").read().strip()
if design != "DESIGN_ORIGINAL":
    print(f"DESIGN_NOT_RESTORED:{design}")
    sys.exit(3)
if os.path.exists(".impeccable"):
    print("IMPECCABLE_DIR_NOT_REMOVED")
    sys.exit(4)
if not os.path.isfile("oracle_verify.txt"):
    print("MISSING_ORACLE_VERIFY")
    sys.exit(5)
out = open("out.txt", encoding="utf-8").read().strip() if os.path.isfile("out.txt") else ""
sys.exit(0 if out == "PASS_VAL" else 1)
PY

cat >"$CMD_SKILL_DIR/evals/evals.json" <<'EOF'
{
  "skill_name": "cmd-skill",
  "evals": [
    {
      "id": 1,
      "prompt": "Tao out.txt",
      "files_dir": "evals/in",
      "checks": [
        {
          "id": "cmd_oracle",
          "text": "Kiem tra bang script kem oracle_files va remove_paths",
          "type": "command",
          "cmd": ["python3", "{skill_dir}/scripts/checker.py"],
          "oracle_files": ["evals/oracle/DESIGN.md", "evals/oracle/oracle_verify.txt"],
          "remove_paths": [".impeccable"],
          "unavailable_exit_codes": [127]
        },
        {
          "id": "cmd_unavail",
          "text": "Lenh tra ma 127 duoc danh dau unavailable",
          "type": "command",
          "cmd": ["python3", "-c", "import sys; sys.exit(127)"],
          "unavailable_exit_codes": [127]
        },
        {
          "id": "cmd_expect_fail_ok",
          "text": "expect=fail dat khi lenh thoat 1",
          "type": "command",
          "expect": "fail",
          "cmd": ["python3", "-c", "import sys; sys.exit(1)"],
          "unavailable_exit_codes": [127]
        },
        {
          "id": "cmd_expect_fail_bad",
          "text": "expect=fail truot khi lenh thoat 0",
          "type": "command",
          "expect": "fail",
          "cmd": ["python3", "-c", "import sys; sys.exit(0)"],
          "unavailable_exit_codes": [127]
        },
        {
          "id": "cmd_expect_fail_unavail",
          "text": "expect=fail van danh dau unavailable khi ma thoat 127",
          "type": "command",
          "expect": "fail",
          "cmd": ["python3", "-c", "import sys; sys.exit(127)"],
          "unavailable_exit_codes": [127]
        }
      ]
    },
    {
      "id": 2,
      "prompt": "Ca moi check deu unavailable",
      "checks": [
        {
          "id": "only_unavail",
          "text": "Lenh khong kha dung",
          "type": "command",
          "cmd": ["python3", "-c", "import sys; sys.exit(127)"],
          "unavailable_exit_codes": [127]
        }
      ]
    }
  ]
}
EOF

WS5_PASS="$TMP/ws_case5_pass"
FAKE_CLAUDE_WRITE_OUT="PASS_VAL" FAKE_CLAUDE_TAMPER_PROJECT=1 \
  python3 "$SKILL_EVAL_PY" run --skill cmd-skill --evals "$CMD_SKILL_DIR/evals/evals.json" \
  --workspace "$WS5_PASS" --runs 1 --configs with_skill >/dev/null 2>&1
python3 "$SKILL_EVAL_PY" grade --skill cmd-skill --evals "$CMD_SKILL_DIR/evals/evals.json" \
  --workspace "$WS5_PASS" >/dev/null 2>&1
RC5_G1=$?

WS5_FAIL="$TMP/ws_case5_fail"
FAKE_CLAUDE_WRITE_OUT="BAD_VAL" FAKE_CLAUDE_TAMPER_PROJECT=1 \
  python3 "$SKILL_EVAL_PY" run --skill cmd-skill --evals "$CMD_SKILL_DIR/evals/evals.json" \
  --workspace "$WS5_FAIL" --runs 1 --configs with_skill --eval-ids 1 >/dev/null 2>&1
python3 "$SKILL_EVAL_PY" grade --skill cmd-skill --evals "$CMD_SKILL_DIR/evals/evals.json" \
  --workspace "$WS5_FAIL" >/dev/null 2>&1
RC5_G2=$?

# Kiểm tra chặn đường dẫn .. trong files_dir và oracle_files
BAD_TRAV_DIR="$TMP/fixtures/skills/trav-skill"
mkdir -p "$BAD_TRAV_DIR/evals"
cat >"$BAD_TRAV_DIR/SKILL.md" <<'EOF'
---
name: trav-skill
description: Dùng khi test chặn path traversal. Bỏ qua khi chạy thật.
---
EOF
cat >"$BAD_TRAV_DIR/evals/evals_files_dir.json" <<'EOF'
{
  "skill_name": "trav-skill",
  "evals": [
    {
      "id": 1,
      "prompt": "x",
      "files_dir": "../demo-skill",
      "checks": [{"id": "c", "text": "t", "type": "result_regex", "regex": "OK"}]
    }
  ]
}
EOF
cat >"$BAD_TRAV_DIR/evals/evals_oracle.json" <<'EOF'
{
  "skill_name": "trav-skill",
  "evals": [
    {
      "id": 1,
      "prompt": "x",
      "checks": [
        {
          "id": "c",
          "text": "t",
          "type": "command",
          "cmd": ["python3", "-c", "pass"],
          "oracle_files": ["evals/../../demo-skill/helper.txt"]
        }
      ]
    }
  ]
}
EOF

python3 "$SKILL_EVAL_PY" run --skill trav-skill --evals "$BAD_TRAV_DIR/evals/evals_files_dir.json" \
  --workspace "$TMP/ws_trav1" --runs 1 >/dev/null 2>&1
RC5_TRAV1=$?

python3 "$SKILL_EVAL_PY" run --skill trav-skill --evals "$BAD_TRAV_DIR/evals/evals_oracle.json" \
  --workspace "$TMP/ws_trav2" --runs 1 >/dev/null 2>&1
RC5_TRAV2=$?
python3 "$SKILL_EVAL_PY" grade --skill trav-skill --evals "$BAD_TRAV_DIR/evals/evals_oracle.json" \
  --workspace "$TMP/ws_trav2" >/dev/null 2>&1
RC5_TRAV3=$?

python3 - "$WS5_PASS" "$WS5_FAIL" "$RC5_G1" "$RC5_G2" "$RC5_TRAV1" "$RC5_TRAV2" "$RC5_TRAV3" >"$TMP/c5.out" <<'PY'
import json, os, sys

ws_p, ws_f = sys.argv[1], sys.argv[2]
rc_g1, rc_g2, rc_t1, rc_t2, rc_t3 = map(int, sys.argv[3:8])

if rc_g1 != 0 or rc_g2 != 0:
    print(f"ERR:grade rcs g1={rc_g1} g2={rc_g2}")
    sys.exit(0)
if rc_t1 != 2 or (rc_t2 != 2 and rc_t3 != 2):
    print(f"ERR:traversal rcs t1={rc_t1} t2={rc_t2} t3={rc_t3}")
    sys.exit(0)

# Xác minh project/ gốc không bị lộ oracle và không bị xoá .impeccable
proj_p = os.path.join(ws_p, "cmd-skill", "eval-1", "with_skill", "run-1", "project")
if os.path.exists(os.path.join(proj_p, "oracle_verify.txt")):
    print("ERR:oracle_verify.txt leaked into project/")
    sys.exit(0)
if open(os.path.join(proj_p, "DESIGN.md"), encoding="utf-8").read().strip() != "TAMPERED_BY_AGENT":
    print("ERR:project/DESIGN.md was mutated by grade")
    sys.exit(0)
if not os.path.isdir(os.path.join(proj_p, ".impeccable")):
    print("ERR:project/.impeccable was deleted in original project/")
    sys.exit(0)

g_pass = json.load(open(os.path.join(ws_p, "cmd-skill", "eval-1", "with_skill", "run-1", "grading.json"), encoding="utf-8"))
exps = {e.get("id", i): e for i, e in enumerate(g_pass["expectations"])}
if exps["cmd_oracle"]["passed"] is not True:
    print(f"ERR:cmd_oracle expected True, got {exps['cmd_oracle']}")
    sys.exit(0)
if exps["cmd_unavail"]["passed"] is not None or exps["cmd_unavail"].get("unavailable") is not True:
    print(f"ERR:cmd_unavail expected null/unavailable, got {exps['cmd_unavail']}")
    sys.exit(0)
if exps["cmd_expect_fail_ok"]["passed"] is not True:
    print(f"ERR:cmd_expect_fail_ok (exit 1) expected True, got {exps['cmd_expect_fail_ok']}")
    sys.exit(0)
if exps["cmd_expect_fail_bad"]["passed"] is not False:
    print(f"ERR:cmd_expect_fail_bad (exit 0) expected False, got {exps['cmd_expect_fail_bad']}")
    sys.exit(0)
if exps["cmd_expect_fail_unavail"]["passed"] is not None or exps["cmd_expect_fail_unavail"].get("unavailable") is not True:
    print(f"ERR:cmd_expect_fail_unavail (exit 127) expected null/unavailable, got {exps['cmd_expect_fail_unavail']}")
    sys.exit(0)
if g_pass["summary"]["total"] != 3 or g_pass["summary"]["passed"] != 2 or g_pass["summary"]["failed"] != 1:
    print(f"ERR:summary with expect=fail + unavailable wrong: {g_pass['summary']}")
    sys.exit(0)

g_all_unavail = json.load(open(os.path.join(ws_p, "cmd-skill", "eval-2", "with_skill", "run-1", "grading.json"), encoding="utf-8"))
if g_all_unavail["summary"]["total"] != 0 or g_all_unavail["summary"]["pass_rate"] is not None:
    print(f"ERR:all unavailable summary must have total=0 and pass_rate=null: {g_all_unavail['summary']}")
    sys.exit(0)

g_fail = json.load(open(os.path.join(ws_f, "cmd-skill", "eval-1", "with_skill", "run-1", "grading.json"), encoding="utf-8"))
if g_fail["expectations"][0]["passed"] is not False:
    print(f"ERR:cmd_oracle expected False on bad out.txt, got {g_fail['expectations'][0]}")
    sys.exit(0)

print("OK")
PY
if [[ "$(cat "$TMP/c5.out")" == "OK" ]]; then
  pass "Ca 5: command + oracle_files + remove_paths + {skill_dir} + unavailable (127, 0/0 -> null) + chặn '..' hoạt động đúng"
else
  fail "Ca 5 thất bại: $(cat "$TMP/c5.out")"
fi

# ---------------------------------------------------------------------------
# Ca 6: aggregate đúng schema skill-creator, mean + pstdev, delta object "+0.33", xử lý ô toàn unavailable
# ---------------------------------------------------------------------------
WS6="$TMP/ws_case6"
python3 - "$WS6" <<'PY'
import json, os, sys

ws = sys.argv[1]
# Dựng 3 lần chạy cho mỗi nhánh ở eval-1 với pass_rate biết trước:
# with_skill: [1.0, 1.0, 0.0] -> mean = 0.6667, pstdev = 0.4714
# without_skill: [1.0, 0.0, 0.0] -> mean = 0.3333, pstdev = 0.4714 -> delta.pass_rate = "+0.33"
# Thêm eval-2 có mọi check unavailable (pass_rate = null) để đảm bảo aggregate không ném TypeError
specs = [
    ("with_skill", 1, 1, 1.0, 1, 0, 1, 10.0, 1000),
    ("with_skill", 1, 2, 1.0, 1, 0, 1, 20.0, 2000),
    ("with_skill", 1, 3, 0.0, 0, 1, 1, 30.0, 3000),
    ("without_skill", 1, 1, 1.0, 1, 0, 1, 5.0, 500),
    ("without_skill", 1, 2, 0.0, 0, 1, 1, 10.0, 1000),
    ("without_skill", 1, 3, 0.0, 0, 1, 1, 15.0, 1500),
    ("with_skill", 2, 1, None, 0, 0, 0, 12.0, 1200),
]

for cfg, eid, rnum, pr, passed, failed, total, tsec, tok in specs:
    cdir = os.path.join(ws, "agg-skill", f"eval-{eid}", cfg, f"run-{rnum}")
    os.makedirs(cdir, exist_ok=True)
    with open(os.path.join(cdir, "run.json"), "w", encoding="utf-8") as fh:
        json.dump({
            "skill_name": "agg-skill",
            "eval_id": eid,
            "eval_name": f"eval-{eid}",
            "configuration": cfg,
            "run_number": rnum,
            "model": "fake-sonnet",
            "valid": True,
            "leak": False,
            "skill_missing": False,
            "timeout": False,
            "duration_ms": int(tsec * 1000),
            "time_seconds": tsec,
            "tokens": tok,
            "total_cost_usd": 0.01,
            "tool_calls": {"Bash": 2},
            "errors": 0,
        }, fh)
    exps = (
        [{"id": "u1", "text": "unavail", "passed": None, "unavailable": True, "evidence": "exit 127"}]
        if pr is None
        else [{"id": "c1", "text": "chk", "passed": bool(passed), "unavailable": False, "evidence": "ok"}]
    )
    with open(os.path.join(cdir, "grading.json"), "w", encoding="utf-8") as fh:
        json.dump({
            "expectations": exps,
            "summary": {"passed": passed, "failed": failed, "total": total, "pass_rate": pr},
        }, fh)

# Thêm comparison-1.json hợp lệ ở eval-1 (cả hai nhánh run-1 đều valid)
with open(os.path.join(ws, "agg-skill", "eval-1", "comparison-1.json"), "w", encoding="utf-8") as fh:
    json.dump({"eval_id": 1, "run_number": 1, "winner_configuration": "with_skill", "error": None}, fh)

# Thêm comparison-1.json mồ côi ở eval-2 (thiếu without_skill/run-1 valid) -> aggregate KHÔNG được gộp
with open(os.path.join(ws, "agg-skill", "eval-2", "comparison-1.json"), "w", encoding="utf-8") as fh:
    json.dump({"eval_id": 2, "run_number": 1, "winner_configuration": "with_skill", "error": None}, fh)
PY

python3 "$SKILL_EVAL_PY" aggregate --skill agg-skill --workspace "$WS6" >/dev/null 2>&1
RC6=$?

python3 - "$WS6" "$RC6" >"$TMP/c6.out" <<'PY'
import json, math, os, statistics, sys

ws, rc = sys.argv[1], int(sys.argv[2])
if rc != 0:
    print(f"ERR:rc={rc}")
    sys.exit(0)

bpath = os.path.join(ws, "agg-skill", "benchmark.json")
mpath = os.path.join(ws, "agg-skill", "benchmark.md")
if not os.path.isfile(bpath) or not os.path.isfile(mpath):
    print("ERR:missing benchmark.json or benchmark.md")
    sys.exit(0)

b = json.load(open(bpath, encoding="utf-8"))
for key in ("metadata", "runs", "run_summary", "notes"):
    if key not in b:
        print(f"ERR:missing top-level {key}")
        sys.exit(0)

if b["metadata"].get("skill_name") != "agg-skill":
    print(f"ERR:metadata.skill_name={b['metadata']}")
    sys.exit(0)

for r in b["runs"]:
    if r.get("configuration") not in ("with_skill", "without_skill"):
        print(f"ERR:bad configuration in run: {r}")
        sys.exit(0)
    if "pass_rate" not in r.get("result", {}):
        print(f"ERR:missing result.pass_rate in run: {r}")
        sys.exit(0)

rs = b["run_summary"]
exp_w_mean = round(statistics.mean([1.0, 1.0, 0.0]), 4)
exp_wo_mean = round(statistics.mean([1.0, 0.0, 0.0]), 4)
exp_sd = round(statistics.pstdev([1.0, 1.0, 0.0]), 4)

if not math.isclose(rs["with_skill"]["pass_rate"]["mean"], exp_w_mean, abs_tol=1e-3):
    print(f"ERR:with_skill mean {rs['with_skill']['pass_rate']} != {exp_w_mean}")
    sys.exit(0)
if not math.isclose(rs["with_skill"]["pass_rate"]["stddev"], exp_sd, abs_tol=1e-3):
    print(f"ERR:with_skill stddev {rs['with_skill']['pass_rate']} != {exp_sd}")
    sys.exit(0)
if not math.isclose(rs["without_skill"]["pass_rate"]["mean"], exp_wo_mean, abs_tol=1e-3):
    print(f"ERR:without_skill mean {rs['without_skill']['pass_rate']} != {exp_wo_mean}")
    sys.exit(0)

delta = rs.get("delta")
if not isinstance(delta, dict):
    print(f"ERR:delta must be dict, got {type(delta)}")
    sys.exit(0)
if delta.get("pass_rate") != "+0.33":
    print(f"ERR:delta.pass_rate={delta.get('pass_rate')} != +0.33")
    sys.exit(0)
if "time_seconds" not in delta or "tokens" not in delta:
    print(f"ERR:delta missing time_seconds or tokens: {delta}")
    sys.exit(0)

notes_joined = "\n".join(b.get("notes", []))
if "Blind comparison eval-1:" not in notes_joined:
    print(f"ERR:missing valid Blind comparison eval-1 in notes: {b.get('notes')}")
    sys.exit(0)
if "Blind comparison eval-2:" in notes_joined:
    print(f"ERR:stale/incomplete Blind comparison eval-2 must not be aggregated: {b.get('notes')}")
    sys.exit(0)

print("OK")
PY
if [[ "$(cat "$TMP/c6.out")" == "OK" ]]; then
  pass "Ca 6: aggregate xuất benchmark.json + benchmark.md chuẩn schema, mean/pstdev chính xác, delta='+0.33', lọc None an toàn"
else
  fail "Ca 6 thất bại: $(cat "$TMP/c6.out")"
fi

# ---------------------------------------------------------------------------
# Ca 7: Timeout — claude giả ngủ 30 s, --timeout 2 -> timeout: true, kết thúc < 10 s
# ---------------------------------------------------------------------------
WS7="$TMP/ws_case7"
T0="$(python3 -c 'import time; print(time.monotonic())')"
FAKE_CLAUDE_MODE=sleep_timeout \
  python3 "$SKILL_EVAL_PY" run --skill demo-skill --evals "$DEMO_SKILL_DIR/evals/evals.json" \
  --workspace "$WS7" --runs 1 --configs with_skill --timeout 2 >/dev/null 2>&1
RC7=$?
T1="$(python3 -c 'import time; print(time.monotonic())')"

python3 - "$WS7" "$RC7" "$T0" "$T1" >"$TMP/c7.out" <<'PY'
import json, os, sys

ws, rc = sys.argv[1], int(sys.argv[2])
elapsed = float(sys.argv[4]) - float(sys.argv[3])
if rc != 1:
    print(f"ERR:timeout rc={rc}, expected 1")
    sys.exit(0)
if elapsed >= 10.0:
    print(f"ERR:timeout took {elapsed:.2f}s >= 10s")
    sys.exit(0)
r = json.load(open(os.path.join(ws, "demo-skill", "eval-1", "with_skill", "run-1", "run.json"), encoding="utf-8"))
if r.get("timeout") is not True or r.get("valid") is not False:
    print(f"ERR:run.json timeout/valid wrong: {r}")
    sys.exit(0)
tr = open(os.path.join(ws, "demo-skill", "eval-1", "with_skill", "run-1", "transcript.jsonl"), encoding="utf-8").read()
cnt = tr.count("ONCE_BEFORE_TIMEOUT")
if cnt != 1:
    print(f"ERR:stdout duplicated on timeout, ONCE_BEFORE_TIMEOUT count={cnt} (expected 1)")
    sys.exit(0)
print(f"OK:{elapsed:.2f}s")
PY
C7_RES="$(cat "$TMP/c7.out")"
if [[ "$C7_RES" == OK:* ]]; then
  pass "Ca 7: Quá hạn --timeout 2 ngắt nhóm tiến trình sạch sẽ (${C7_RES#OK:}), ghi timeout=true"
else
  fail "Ca 7 thất bại: $C7_RES"
fi

# ---------------------------------------------------------------------------
# Ca 8: compare mù A/B ánh xạ ngược về đúng configuration với 2 seed ngược thứ tự + bóc code fence + bắt JSON hỏng
# ---------------------------------------------------------------------------
WS8="$TMP/ws_case8"
mkdir -p "$WS8/imp-skill/eval-1/with_skill/run-1/project" "$WS8/imp-skill/eval-1/without_skill/run-1/project"
printf '<html><body>With skill</body></html>\n' >"$WS8/imp-skill/eval-1/with_skill/run-1/project/index.html"
printf '<html><body>Without skill</body></html>\n' >"$WS8/imp-skill/eval-1/without_skill/run-1/project/index.html"

# Thêm cặp run-2 bị đánh dấu valid=false kèm file comparison-2.json cũ để xác minh compare tự xoá file cũ
mkdir -p "$WS8/imp-skill/eval-1/with_skill/run-2/project" "$WS8/imp-skill/eval-1/without_skill/run-2/project"
printf '<html><body>Stale</body></html>\n' >"$WS8/imp-skill/eval-1/with_skill/run-2/project/index.html"
printf '<html><body>Stale</body></html>\n' >"$WS8/imp-skill/eval-1/without_skill/run-2/project/index.html"
printf '{"valid": false}\n' >"$WS8/imp-skill/eval-1/with_skill/run-2/run.json"
printf '{"stale": true}\n' >"$WS8/imp-skill/eval-1/comparison-2.json"

LOG8="$TMP/case8_calls.jsonl"
FAKE_CLAUDE_MODE=judge_a_fenced FAKE_CLAUDE_LOG="$LOG8" \
  python3 "$SKILL_EVAL_PY" compare --skill imp-skill --workspace "$WS8" --eval 1 --artifact index.html --seed 0 >/dev/null 2>&1
RC8_S0=$?
[[ -f "$WS8/imp-skill/eval-1/comparison-1.json" ]] && cp "$WS8/imp-skill/eval-1/comparison-1.json" "$TMP/cmp_s0.json"
STALE_CMP2_EXISTS=0
[[ -e "$WS8/imp-skill/eval-1/comparison-2.json" ]] && STALE_CMP2_EXISTS=1

FAKE_CLAUDE_MODE=judge_a_fenced \
  python3 "$SKILL_EVAL_PY" compare --skill imp-skill --workspace "$WS8" --eval 1 --artifact index.html --seed 4 >/dev/null 2>&1
RC8_S4=$?
[[ -f "$WS8/imp-skill/eval-1/comparison-1.json" ]] && cp "$WS8/imp-skill/eval-1/comparison-1.json" "$TMP/cmp_s4.json"

# Judge trả JSON có chứa ``` trong chuỗi reasoning (cả trần lẫn bọc ngoài bởi ```json)
FAKE_CLAUDE_MODE=judge_inner_backticks \
  python3 "$SKILL_EVAL_PY" compare --skill imp-skill --workspace "$WS8" --eval 1 --artifact index.html --seed 0 >/dev/null 2>&1
RC8_INNER1=$?
[[ -f "$WS8/imp-skill/eval-1/comparison-1.json" ]] && cp "$WS8/imp-skill/eval-1/comparison-1.json" "$TMP/cmp_inner1.json"

FAKE_CLAUDE_MODE=judge_inner_backticks FAKE_CLAUDE_OUTER_FENCE=1 \
  python3 "$SKILL_EVAL_PY" compare --skill imp-skill --workspace "$WS8" --eval 1 --artifact index.html --seed 0 >/dev/null 2>&1
RC8_INNER2=$?
[[ -f "$WS8/imp-skill/eval-1/comparison-1.json" ]] && cp "$WS8/imp-skill/eval-1/comparison-1.json" "$TMP/cmp_inner2.json"

FAKE_CLAUDE_MODE=judge_bad_json \
  python3 "$SKILL_EVAL_PY" compare --skill imp-skill --workspace "$WS8" --eval 1 --artifact index.html --seed 0 >/dev/null 2>&1
RC8_BAD=$?
[[ -f "$WS8/imp-skill/eval-1/comparison-1.json" ]] && cp "$WS8/imp-skill/eval-1/comparison-1.json" "$TMP/cmp_bad.json"

python3 - "$TMP/cmp_s0.json" "$TMP/cmp_s4.json" "$TMP/cmp_bad.json" "$LOG8" "$RC8_S0" "$RC8_S4" "$RC8_BAD" "$STALE_CMP2_EXISTS" "$RC8_INNER1" "$RC8_INNER2" "$TMP/cmp_inner1.json" "$TMP/cmp_inner2.json" >"$TMP/c8.out" <<'PY'
import json, os, sys

for p in (sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[11], sys.argv[12]):
    if not os.path.isfile(p):
        print(f"ERR:missing {os.path.basename(p)}")
        sys.exit(0)
c0 = json.load(open(sys.argv[1], encoding="utf-8"))
c4 = json.load(open(sys.argv[2], encoding="utf-8"))
cbad = json.load(open(sys.argv[3], encoding="utf-8"))
calls = [json.loads(l) for l in open(sys.argv[4], encoding="utf-8") if l.strip()]
rc0, rc4, rcbad, stale2, rci1, rci2 = map(int, sys.argv[5:11])
ci1 = json.load(open(sys.argv[11], encoding="utf-8"))
ci2 = json.load(open(sys.argv[12], encoding="utf-8"))

if rc0 != 0 or rc4 != 0 or rcbad != 1 or rci1 != 0 or rci2 != 0:
    print(f"ERR:rcs rc0={rc0} rc4={rc4} rcbad={rcbad} rci1={rci1} rci2={rci2}")
    sys.exit(0)
if stale2 != 0:
    print("ERR:stale comparison-2.json was not removed when pair was skipped")
    sys.exit(0)
if "```css" not in (ci1.get("reasoning") or "") or "```css" not in (ci2.get("reasoning") or ""):
    print(f"ERR:inner backticks reasoning corrupted: ci1={ci1} ci2={ci2}")
    sys.exit(0)

# Xác nhận --tools "" đã được truyền để tắt toàn bộ tool của judge
argv0 = calls[0]["argv"]
if "--tools" not in argv0 or argv0[argv0.index("--tools") + 1] != "":
    print(f"ERR:compare missing --tools '': {argv0}")
    sys.exit(0)

if c0.get("winner") != "A" or c4.get("winner") != "A":
    print(f"ERR:winner not A: {c0} / {c4}")
    sys.exit(0)

if c0.get("winner_configuration") != c0["assignment"]["A"]:
    print(f"ERR:seed 0 mapping mismatch: {c0}")
    sys.exit(0)
if c4.get("winner_configuration") != c4["assignment"]["A"]:
    print(f"ERR:seed 4 mapping mismatch: {c4}")
    sys.exit(0)
if {c0["winner_configuration"], c4["winner_configuration"]} != {"with_skill", "without_skill"}:
    print(f"ERR:two seeds did not exercise both A/B orders: {c0['winner_configuration']} vs {c4['winner_configuration']}")
    sys.exit(0)
if not cbad.get("error") or cbad.get("winner_configuration") is not None:
    print(f"ERR:bad json should record error and null winner_configuration: {cbad}")
    sys.exit(0)

print("OK")
PY
if [[ "$(cat "$TMP/c8.out")" == "OK" ]]; then
  pass "Ca 8: compare tắt tool (--tools ''), bóc code fence, ánh xạ mù A/B chuẩn trên 2 seed đảo chiều và bắt lỗi JSON sai"
else
  fail "Ca 8 thất bại: $(cat "$TMP/c8.out")"
fi

# ---------------------------------------------------------------------------
# Ca 9: Giải CLAUDE_CONFIG_DIR từ repo, từ git worktree qua --git-common-dir, chặn ../evil, ưu tiên --config-dir
# ---------------------------------------------------------------------------
FAKE_HOME="$TMP/fake_home"
mkdir -p "$FAKE_HOME/.claude-x" "$FAKE_HOME/.claude-override" "$FAKE_HOME/evil"

FAKE_REPO="$TMP/fake_repo"
mkdir -p "$FAKE_REPO/.claude"
(
  cd "$FAKE_REPO" && git init -q && git -c user.name=t -c user.email=t@t commit --allow-empty -qm "init"
)
printf '{"account": "x"}\n' >"$FAKE_REPO/.claude/settings.local.json"

FAKE_WT="$TMP/fake_wt"
git -C "$FAKE_REPO" worktree add -q --detach "$FAKE_WT"
mkdir -p "$FAKE_WT/.claude"
printf '{"autoMemoryDirectory": "/tmp/mem"}\n' >"$FAKE_WT/.claude/settings.local.json"

EVIL_REPO="$TMP/evil_repo"
mkdir -p "$EVIL_REPO/.claude"
(
  cd "$EVIL_REPO" && git init -q && git -c user.name=t -c user.email=t@t commit --allow-empty -qm "init"
)
printf '{"account": "../evil_raw_secret"}\n' >"$EVIL_REPO/.claude/settings.local.json"

# Worktree có account sai phải cảnh báo (không lộ giá trị) và tiếp tục xét git-common-dir (FAKE_REPO -> x)
FAKE_WT_BAD_ACCT="$TMP/fake_wt_bad_acct"
git -C "$FAKE_REPO" worktree add -q --detach "$FAKE_WT_BAD_ACCT"
mkdir -p "$FAKE_WT_BAD_ACCT/.claude"
printf '{"account": "../wt_bad_raw"}\n' >"$FAKE_WT_BAD_ACCT/.claude/settings.local.json"

CORRUPT_REPO="$TMP/corrupt_repo"
mkdir -p "$CORRUPT_REPO/.claude"
(
  cd "$CORRUPT_REPO" && git init -q && git -c user.name=t -c user.email=t@t commit --allow-empty -qm "init"
)
printf '{broken_raw_marker\n' >"$CORRUPT_REPO/.claude/settings.local.json"

LOG9="$TMP/case9_calls.jsonl"
(
  cd "$FAKE_REPO" && env -u CLAUDE_CONFIG_DIR HOME="$FAKE_HOME" FAKE_CLAUDE_LOG="$LOG9" \
    python3 "$SKILL_EVAL_PY" run --skill demo-skill --evals "$DEMO_SKILL_DIR/evals/evals.json" \
    --workspace "$TMP/ws9_repo" --runs 1 --configs with_skill >/dev/null 2>&1
)
(
  cd "$FAKE_WT" && env -u CLAUDE_CONFIG_DIR HOME="$FAKE_HOME" FAKE_CLAUDE_LOG="$LOG9" \
    python3 "$SKILL_EVAL_PY" run --skill demo-skill --evals "$DEMO_SKILL_DIR/evals/evals.json" \
    --workspace "$TMP/ws9_wt" --runs 1 --configs with_skill >/dev/null 2>&1
)
(
  cd "$EVIL_REPO" && env -u CLAUDE_CONFIG_DIR HOME="$FAKE_HOME" FAKE_CLAUDE_LOG="$LOG9" \
    python3 "$SKILL_EVAL_PY" run --skill demo-skill --evals "$DEMO_SKILL_DIR/evals/evals.json" \
    --workspace "$TMP/ws9_evil" --runs 1 --configs with_skill >/dev/null 2>"$TMP/c9_evil.err"
)
(
  cd "$FAKE_REPO" && env -u CLAUDE_CONFIG_DIR HOME="$FAKE_HOME" FAKE_CLAUDE_LOG="$LOG9" \
    python3 "$SKILL_EVAL_PY" run --skill demo-skill --evals "$DEMO_SKILL_DIR/evals/evals.json" \
    --workspace "$TMP/ws9_ovr" --runs 1 --configs with_skill --config-dir "$FAKE_HOME/.claude-override" >/dev/null 2>&1
)
(
  cd "$CORRUPT_REPO" && env -u CLAUDE_CONFIG_DIR HOME="$FAKE_HOME" FAKE_CLAUDE_LOG="$LOG9" \
    python3 "$SKILL_EVAL_PY" run --skill demo-skill --evals "$DEMO_SKILL_DIR/evals/evals.json" \
    --workspace "$TMP/ws9_corrupt" --runs 1 --configs with_skill >/dev/null 2>"$TMP/c9_corrupt.err"
)
RC9_CORRUPT=$?
(
  cd "$FAKE_WT_BAD_ACCT" && env -u CLAUDE_CONFIG_DIR HOME="$FAKE_HOME" FAKE_CLAUDE_LOG="$LOG9" \
    python3 "$SKILL_EVAL_PY" run --skill demo-skill --evals "$DEMO_SKILL_DIR/evals/evals.json" \
    --workspace "$TMP/ws9_wt_bad" --runs 1 --configs with_skill >/dev/null 2>"$TMP/c9_wt_bad.err"
)

python3 - "$LOG9" "$FAKE_HOME" "$TMP/ws9_repo" "$TMP/c9_evil.err" "$TMP/c9_corrupt.err" "$RC9_CORRUPT" "$TMP/c9_wt_bad.err" >"$TMP/c9.out" <<'PY'
import json, os, sys

log_path, raw_fake_home, ws_repo, evil_err_path, corrupt_err_path, rc_corrupt_s, wt_bad_err_path = sys.argv[1:8]
rc_corrupt = int(rc_corrupt_s)
fake_home = os.path.normpath(raw_fake_home)
if not os.path.isfile(log_path):
    print("ERR:missing case9_calls.jsonl")
    sys.exit(0)
calls = [json.loads(l) for l in open(log_path, encoding="utf-8") if l.strip()]
if len(calls) != 6:
    print(f"ERR:expected 6 calls, got {len(calls)}")
    sys.exit(0)

exp_x = os.path.join(fake_home, ".claude-x")
exp_ovr = os.path.join(fake_home, ".claude-override")

if calls[0]["claude_config_dir"] != exp_x:
    print(f"ERR:repo account did not resolve to {exp_x}: {calls[0]['claude_config_dir']}")
    sys.exit(0)
if calls[1]["claude_config_dir"] != exp_x:
    print(f"ERR:worktree fallback via --git-common-dir failed: {calls[1]['claude_config_dir']}")
    sys.exit(0)
if calls[2]["claude_config_dir"] is not None:
    print(f"ERR:invalid ../evil account must be ignored, got {calls[2]['claude_config_dir']}")
    sys.exit(0)
if calls[3]["claude_config_dir"] != exp_ovr:
    print(f"ERR:--config-dir did not override: {calls[3]['claude_config_dir']}")
    sys.exit(0)
if rc_corrupt != 0 or calls[4]["claude_config_dir"] is not None:
    print(f"ERR:corrupt settings.local.json should still run with default config, got rc={rc_corrupt} cfg={calls[4]['claude_config_dir']}")
    sys.exit(0)
if calls[5]["claude_config_dir"] != exp_x:
    print(f"ERR:invalid worktree account did not continue to git-common-dir (.claude-x): {calls[5]['claude_config_dir']}")
    sys.exit(0)

# Đảm bảo run.json chỉ lưu tên thư mục cấu hình chứ không lộ đường dẫn đầy đủ FAKE_HOME
r_txt = open(os.path.join(ws_repo, "demo-skill", "eval-1", "with_skill", "run-1", "run.json"), encoding="utf-8").read()
if fake_home in r_txt:
    print("ERR:run.json leaked full config_dir parent path")
    sys.exit(0)
r_obj = json.loads(r_txt)
if r_obj.get("claude_config_dir") != ".claude-x":
    print(f"ERR:run.json claude_config_dir basename wrong: {r_obj.get('claude_config_dir')}")
    sys.exit(0)

evil_err = open(evil_err_path, encoding="utf-8").read()
if not evil_err.strip():
    print("ERR:expected warning on stderr for ../evil account")
    sys.exit(0)
if "evil_raw_secret" in evil_err:
    print(f"ERR:invalid account warning printed raw value: {evil_err!r}")
    sys.exit(0)

wt_bad_err = open(wt_bad_err_path, encoding="utf-8").read()
if not wt_bad_err.strip() or "wt_bad_raw" in wt_bad_err:
    print(f"ERR:worktree invalid account warning missing or leaked raw value: {wt_bad_err!r}")
    sys.exit(0)

corrupt_err = open(corrupt_err_path, encoding="utf-8").read()
if "settings.local.json" not in corrupt_err or "JSONDecodeError" not in corrupt_err:
    print(f"ERR:expected stderr warning with path and JSONDecodeError for corrupt settings, got: {corrupt_err!r}")
    sys.exit(0)
if "broken_raw_marker" in corrupt_err:
    print("ERR:corrupt settings warning leaked raw file content")
    sys.exit(0)

print("OK")
PY
if [[ "$(cat "$TMP/c9.out")" == "OK" ]]; then
  pass "Ca 9: CLAUDE_CONFIG_DIR đọc đúng từ repo & git-common-dir worktree, chặn '../evil', ưu tiên --config-dir, che đường dẫn trong run.json"
else
  fail "Ca 9 thất bại: $(cat "$TMP/c9.out")"
fi

# ---------------------------------------------------------------------------
# Ca 10: Validate mọi KIT/skills/*/evals/evals.json thật (dùng lệnh con `skill_eval.py validate`)
#        và từ chối các fixture xấu (thiếu file, .., symlink thoát ra ngoài, trùng basename, sai tên skill, trùng id)
# ---------------------------------------------------------------------------
REAL_EVALS_COUNT=0
for ef in "$DEVKIT_ROOT"/skills/*/evals/evals.json; do
  [[ -f "$ef" ]] || continue
  REAL_EVALS_COUNT=$((REAL_EVALS_COUNT + 1))
  rel_ef="${ef#$DEVKIT_ROOT/}"
  if VAL_OUT="$(python3 -I "$SKILL_EVAL_PY" validate --evals "$ef" 2>&1)"; then
    pass "Ca 10a: Validate đạt cho $rel_ef"
  else
    fail "Ca 10a: Validate thất bại cho $rel_ef: $VAL_OUT"
  fi
done

if [[ "$REAL_EVALS_COUNT" -ge 3 ]] && [[ -f "$DEVKIT_ROOT/skills/verification-before-completion/evals/evals.json" ]] \
  && python3 -I -c 'import json,sys
with open(sys.argv[1], encoding="utf-8") as fh:
    d = json.load(fh)
sys.exit(0 if len(d.get("evals", [])) >= 3 else 1)' \
     "$DEVKIT_ROOT/skills/verification-before-completion/evals/evals.json"; then
  pass "Ca 10b: Đủ bộ evals pilot trong skills/*/evals/evals.json ($REAL_EVALS_COUNT bộ, gồm tdd-workflow, impeccable và verification-before-completion)"
else
  fail "Ca 10b: Chưa đủ bộ evals pilot (tìm thấy $REAL_EVALS_COUNT, cần >= 3 gồm verification-before-completion >= 3 ca)"
fi

# Dựng các bộ evals xấu để xác minh `skill_eval.py validate` từ chối hết
BAD_SKILL_DIR="$TMP/fixtures/skills/bad-skill"
mkdir -p "$BAD_SKILL_DIR/evals/a" "$BAD_SKILL_DIR/evals/b"
cat >"$BAD_SKILL_DIR/SKILL.md" <<'EOF'
---
name: bad-skill
description: Dùng khi kiểm thử validate âm tính. Bỏ qua khi chạy thật.
---
EOF
printf '1\n' >"$BAD_SKILL_DIR/evals/a/dup.py"
printf '2\n' >"$BAD_SKILL_DIR/evals/b/dup.py"
ln -s "$TMP/c9.out" "$BAD_SKILL_DIR/evals/a/escape_link.py"

python3 -I - "$SKILL_EVAL_PY" "$BAD_SKILL_DIR" >"$TMP/c10_neg.out" <<'PY'
import json, os, subprocess, sys

script, sdir = sys.argv[1], sys.argv[2]
evals_dir = os.path.join(sdir, "evals")

bad_cases = {
    "wrong_skill_name": {
        "skill_name": "other-name",
        "evals": [{"id": 1, "prompt": "p", "checks": [{"id": "c", "text": "t", "type": "result_regex", "regex": "x"}]}],
    },
    "dup_eval_id": {
        "skill_name": "bad-skill",
        "evals": [
            {"id": 1, "prompt": "p1", "checks": [{"id": "c", "text": "t", "type": "result_regex", "regex": "x"}]},
            {"id": 1, "prompt": "p2", "checks": [{"id": "c", "text": "t", "type": "result_regex", "regex": "x"}]},
        ],
    },
    "missing_file": {
        "skill_name": "bad-skill",
        "evals": [
            {
                "id": 1,
                "prompt": "p",
                "files": ["evals/a/nonexistent.py"],
                "checks": [{"id": "c", "text": "t", "type": "result_regex", "regex": "x"}],
            }
        ],
    },
    "missing_files_dir": {
        "skill_name": "bad-skill",
        "evals": [
            {
                "id": 1,
                "prompt": "p",
                "files_dir": "evals/no_such_dir",
                "checks": [{"id": "c", "text": "t", "type": "result_regex", "regex": "x"}],
            }
        ],
    },
    "dotdot_path": {
        "skill_name": "bad-skill",
        "evals": [
            {
                "id": 1,
                "prompt": "p",
                "files": ["evals/../SKILL.md"],
                "checks": [{"id": "c", "text": "t", "type": "result_regex", "regex": "x"}],
            }
        ],
    },
    "symlink_escape": {
        "skill_name": "bad-skill",
        "evals": [
            {
                "id": 1,
                "prompt": "p",
                "files_dir": "evals/a",
                "checks": [{"id": "c", "text": "t", "type": "result_regex", "regex": "x"}],
            }
        ],
    },
    "dup_basename_files": {
        "skill_name": "bad-skill",
        "evals": [
            {
                "id": 1,
                "prompt": "p",
                "files": ["evals/a/dup.py", "evals/b/dup.py"],
                "checks": [{"id": "c", "text": "t", "type": "result_regex", "regex": "x"}],
            }
        ],
    },
    "dup_basename_oracle": {
        "skill_name": "bad-skill",
        "evals": [
            {
                "id": 1,
                "prompt": "p",
                "checks": [
                    {
                        "id": "c",
                        "text": "t",
                        "type": "command",
                        "cmd": ["python3", "-c", "pass"],
                        "oracle_files": ["evals/a/dup.py", "evals/b/dup.py"],
                    }
                ],
            }
        ],
    },
    "unknown_check_type": {
        "skill_name": "bad-skill",
        "evals": [{"id": 1, "prompt": "p", "checks": [{"id": "c", "text": "t", "type": "not_a_type"}]}],
    },
    "invalid_command_expect": {
        "skill_name": "bad-skill",
        "evals": [
            {
                "id": 1,
                "prompt": "p",
                "checks": [{"id": "c", "text": "t", "type": "command", "expect": "maybe", "cmd": ["python3", "-c", "pass"]}],
            }
        ],
    },
    "null_timeout": {
        "skill_name": "bad-skill",
        "evals": [
            {
                "id": 1,
                "prompt": "p",
                "checks": [{"id": "c", "text": "t", "type": "command", "timeout": None, "cmd": ["python3", "-c", "pass"]}],
            }
        ],
    },
    "null_unavailable_codes": {
        "skill_name": "bad-skill",
        "evals": [
            {
                "id": 1,
                "prompt": "p",
                "checks": [{"id": "c", "text": "t", "type": "command", "unavailable_exit_codes": None, "cmd": ["python3", "-c", "pass"]}],
            }
        ],
    },
    "null_expect": {
        "skill_name": "bad-skill",
        "evals": [
            {
                "id": 1,
                "prompt": "p",
                "checks": [{"id": "c", "text": "t", "type": "command", "expect": None, "cmd": ["python3", "-c", "pass"]}],
            }
        ],
    },
    "null_command_regex": {
        "skill_name": "bad-skill",
        "evals": [
            {
                "id": 1,
                "prompt": "p",
                "checks": [
                    {
                        "id": "c",
                        "text": "t",
                        "type": "tool_order",
                        "first": {"tool": "Bash", "command_regex": None},
                        "before": {"tool": "Edit"},
                    }
                ],
            }
        ],
    },
}

for name, payload in bad_cases.items():
    p = os.path.join(evals_dir, f"bad_{name}.json")
    with open(p, "w", encoding="utf-8") as fh:
        json.dump(payload, fh)
    if not os.path.isfile(script):
        print("ERR:skill_eval.py missing")
        sys.exit(0)
    r = subprocess.run([sys.executable, "-I", script, "validate", "--evals", p], capture_output=True, text=True, timeout=30)
    if r.returncode == 0 or "Traceback" in r.stderr:
        print(f"ERR:validate failed properly rejecting {name} (rc={r.returncode})")
        sys.exit(0)

print(f"OK:{len(bad_cases)}")
PY
C10_NEG="$(cat "$TMP/c10_neg.out")"
if [[ "$C10_NEG" == OK:* ]]; then
  pass "Ca 10c: skill_eval.py validate từ chối đầy đủ ${C10_NEG#OK:} mẫu cấu hình xấu (thiếu file, .., symlink thoát, trùng basename, sai tên/id, kiểu lạ)"
else
  fail "Ca 10c thất bại: $C10_NEG"
fi

# Ca 10d: Kiểm chứng vòng đời fixture verification-before-completion (starter XANH giả, oracle ĐỎ thật, không lộ đáp án, không rác __pycache__)
#         và chặn lỗi PEP 552 __pycache__/*.pyc cùng giây cùng kích thước khi grade chép đè oracle_files.
python3 -I -B - "$SKILL_EVAL_PY" "$DEVKIT_ROOT/skills/verification-before-completion" "$TMP" >"$TMP/c10d.out" <<'PY'
import json, os, py_compile, shutil, subprocess, sys, tempfile

script, vbc_dir, tmp_root = sys.argv[1], sys.argv[2], sys.argv[3]
evals_path = os.path.join(vbc_dir, "evals", "evals.json")
with open(evals_path, encoding="utf-8") as fh:
    spec = json.load(fh)

# 1. Không để sót __pycache__ trong cây evals/files/
for dp, dns, fns in os.walk(os.path.join(vbc_dir, "evals", "files")):
    if "__pycache__" in dns or any(f.endswith(".pyc") for f in fns):
        print(f"ERR:leftover pycache in {dp}")
        sys.exit(0)

# 2. HANDOFF.md của eval-2 không lộ thẳng cụm từ 'off-by-one'; eval-3 có >= 2 starter tests và không lộ thẳng '0 dòng' trong prompt
handoff = open(os.path.join(vbc_dir, "evals", "files", "eval-2", "HANDOFF.md"), encoding="utf-8").read()
if "off-by-one" in handoff.lower():
    print("ERR:eval-2 HANDOFF.md leaks 'off-by-one'")
    sys.exit(0)
ev3_prompt = [e["prompt"] for e in spec["evals"] if e["id"] == 3][0]
if "0 dòng" in ev3_prompt:
    print("ERR:eval-3 prompt leaks exact '0 dòng' root cause instead of verification-shortcut framing")
    sys.exit(0)

# 3. Mọi ca trong verification-before-completion: starter test XANH (rc=0), oracle test ĐỎ (rc!=0) trên mã lỗi gốc
for ev in spec["evals"]:
    with tempfile.TemporaryDirectory(dir=tmp_root) as box:
        for rel in ev.get("files", []):
            shutil.copy(os.path.join(vbc_dir, rel), os.path.join(box, os.path.basename(rel)))
        r_base = subprocess.run([sys.executable, "-I", "-B", "-m", "unittest", "-v"], cwd=box, capture_output=True, text=True, timeout=15)
        if r_base.returncode != 0:
            print(f"ERR:eval-{ev['id']} starter test not green (rc={r_base.returncode}): {r_base.stderr}")
            sys.exit(0)
        if ev["id"] == 3 and "Ran 2 tests" not in r_base.stderr:
            print(f"ERR:eval-3 starter should have 2 green tests covering false-clean empty status: {r_base.stderr}")
            sys.exit(0)
        oracle_chk = [c for c in ev["checks"] if c["id"] == "oracle_passes"][0]
        for orel in oracle_chk["oracle_files"]:
            shutil.copy(os.path.join(vbc_dir, orel), os.path.join(box, os.path.basename(orel)))
        r_ora = subprocess.run([sys.executable, "-I", "-B", "-m", "unittest", "-q", "test_oracle"], cwd=box, capture_output=True, text=True, timeout=15)
        if r_ora.returncode == 0:
            print(f"ERR:eval-{ev['id']} oracle passed on buggy baseline code")
            sys.exit(0)

# 4. Chặn bẫy PEP 552 __pycache__: mod.py sửa có cùng số byte + cùng giây mtime với bản chép oracle_files lúc grade
import importlib.util, time as _t
spec_mod = importlib.util.spec_from_file_location("se", script)
se = importlib.util.module_from_spec(spec_mod)
spec_mod.loader.exec_module(se)
pyc_case = os.path.join(tmp_root, "pyc_trap")
sdir = os.path.join(pyc_case, "pyc-skill")
proj_dir = os.path.join(pyc_case, "project")
os.makedirs(os.path.join(sdir, "evals", "orig"), exist_ok=True)
os.makedirs(proj_dir, exist_ok=True)
orig_mod = os.path.join(sdir, "evals", "orig", "mod.py")
open(orig_mod, "w", encoding="utf-8").write("VAL = 1\n")
fixed_mod = os.path.join(proj_dir, "mod.py")
while (_t.time() % 1.0) > 0.35:
    _t.sleep(0.02)
open(fixed_mod, "w", encoding="utf-8").write("VAL = 2\n")  # cùng đúng 8 byte như VAL = 1\n
py_compile.compile(fixed_mod, doraise=True)
res_chk = se._eval_command_check({
    "id": "catches_orig_bug",
    "text": "must fail on orig VAL=1",
    "type": "command",
    "expect": "fail",
    "cmd": [sys.executable, "-I", "-c", "import os, sys; sys.path.insert(0, os.getcwd()); import mod; sys.exit(0 if mod.VAL == 2 else 3)"],
    "oracle_files": ["evals/orig/mod.py"],
}, proj_dir, sdir)
if not res_chk.get("passed") or "exit_code=3" not in str(res_chk.get("evidence", "")):
    print(f"ERR:PEP 552 stale pycache poisoned oracle_files check: {res_chk}")
    sys.exit(0)

print("OK")
PY
if [[ "$(cat "$TMP/c10d.out")" == "OK" ]]; then
  pass "Ca 10d: Bộ fixture verification-before-completion đạt chuẩn (starter XANH, oracle ĐỎ, 0 lộ đáp án, 0 __pycache__) và chặn lỗi PEP 552 .pyc khi chép oracle_files"
else
  fail "Ca 10d thất bại: $(cat "$TMP/c10d.out")"
fi

echo ""
if [[ "$FAILS" -gt 0 ]]; then
  echo "FAILED: $FAILS lỗi ($PASSES kiểm tra đạt)"
  exit 1
fi
echo "ALL $PASSES CHECKS PASSED"
exit 0
