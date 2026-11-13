#!/usr/bin/env bash
# Hồi quy (13/11): từ #1108 hooks/hooks.json đăng ký guard-protected-push bằng lệnh thử HAI đường dẫn và chạy cái đầu tiên tồn tại:
#   p="$CLAUDE_PROJECT_DIR"/universal-agent-devkit/hooks/guard-protected-push.py; f="$CLAUDE_PROJECT_DIR"/.claude/hooks/guard-protected-push.py;
#   [ -f "$p" ] && exec python3 "$p"; [ -f "$f" ] && exec python3 "$f"; echo "⛔ …" >&2; exit 2
# `p` chỉ có ở agent-workbench (nơi chứa kit), `f` là link `agent-kit init` tạo ở mọi repo. Phép kiểm dây nối hook dùng chung
# (registered_hook_scripts của bin/agent-health.py, INSTINCT-015) coi CẢ HAI là bắt buộc, nên mọi repo vừa cài bị:
#   `agent-kit health` → FAIL "hook đăng ký nhưng thiếu file" (đo thật 13/11 trên 3 repo thử: 92/100, 96/100, 92/100, exit 1),
#   `post-fix-gate.py` → ✖ ".claude/settings.json: hook chạy file không tồn tại: universal-agent-devkit/hooks/guard-protected-push.py".
# Nay các đường dẫn gán vào biến shell và được canh bằng `[ -f "$biến" ]` trong CÙNG một lệnh là một nhóm thay thế: nhóm đạt khi ít nhất
# một đường dẫn tồn tại. Test hai chiều: cả nhóm thiếu vẫn bị chặn, đường dẫn không canh vẫn bắt buộc, một đường dẫn có canh vẫn bắt buộc.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HEALTH="$DEVKIT_DIR/bin/agent-health.py"; GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# Lệnh thật kit đang phát hành (đọc từ hooks.json để test đi theo đúng thứ được cài), và cùng dạng đó với tên script kit KHÔNG có.
SHIPPED="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print([h["command"] for ms in d["hooks"].values() for m in ms for h in m.get("hooks", []) if "guard-protected-push.py" in h.get("command", "")][0])' "$DEVKIT_DIR/hooks/hooks.json")"
alt() {   # $1 = tên script: lệnh hai đường dẫn thay thế có canh, cùng dạng lệnh kit phát hành
  printf 'p="$CLAUDE_PROJECT_DIR"/universal-agent-devkit/hooks/%s; f="$CLAUDE_PROJECT_DIR"/.claude/hooks/%s; [ -f "$p" ] && exec python3 "$p"; [ -f "$f" ] && exec python3 "$f"; echo missing >&2; exit 2' "$1" "$1"
}
hook() {  # settings.json có một hook Stop cho mỗi lệnh truyền vào
  python3 -c 'import json,sys; print(json.dumps({"permissions": {"allow": []}, "hooks": {"Stop": [{"hooks": [{"type": "command", "command": c} for c in sys.argv[1:]]}]}}))' "$@"
}

# ── Đơn vị: nhóm thay thế và danh sách thiếu ──
unit() {  # $1 = mô tả, $2 = JSON mong đợi, $3 = biểu thức Python trên module m và settings s(cmd…)
  local got
  got="$(python3 - "$HEALTH" "$3" "${@:4}" <<'PY' 2>&1
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("agent_health", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
s = {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": c} for c in sys.argv[3:]]}]}}
print(json.dumps(eval(sys.argv[2])))
PY
)"
  [ "$got" = "$2" ] && ok "$1" || fail "$1: got $(printf '%s' "$got" | tail -1 | cut -c1-200), expected $2"
}
P="universal-agent-devkit/hooks/x.py"; F=".claude/hooks/x.py"
unit "U1: two guarded candidates of one command are ONE alternative group" "[[\"$P\", \"$F\"]]" 'm.registered_hook_groups(s)' "$(alt x.py)"
unit "U1b: registered_hook_scripts keeps its flat list and order" "[\"$P\", \"$F\"]" 'm.registered_hook_scripts(s)' "$(alt x.py)"
unit "U2a: only the installed link exists (every app repo) → nothing missing" "[]" "m.missing_hook_scripts(s, lambda r: r == '$F')" "$(alt x.py)"
unit "U2b: only the kit source exists (the workbench without init) → nothing missing" "[]" "m.missing_hook_scripts(s, lambda r: r == '$P')" "$(alt x.py)"
unit "U2c: both candidates missing → both reported (still blocked)" "[\"$P\", \"$F\"]" 'm.missing_hook_scripts(s, lambda r: False)' "$(alt x.py)"
unit "U3a: a variable that is NOT guarded by [ -f ] stays mandatory" '[".claude/hooks/a.sh"]' 'm.missing_hook_scripts(s, lambda r: False)' \
  'x="$CLAUDE_PROJECT_DIR"/.claude/hooks/a.sh; bash "$x"'
unit "U3b: a single guarded candidate stays mandatory (no second place to run from)" '[".claude/hooks/a.sh"]' 'm.missing_hook_scripts(s, lambda r: False)' \
  'p="$CLAUDE_PROJECT_DIR"/.claude/hooks/a.sh; [ -f "$p" ] && exec bash "$p"'
unit "U3c: one guarded and one unguarded variable are NOT alternatives of each other" '[".claude/hooks/a.sh"]' "m.missing_hook_scripts(s, lambda r: r == '.claude/hooks/b.sh')" \
  'p="$CLAUDE_PROJECT_DIR"/.claude/hooks/a.sh; f="$CLAUDE_PROJECT_DIR"/.claude/hooks/b.sh; [ -f "$p" ] && exec bash "$p"; bash "$f"'
unit "U4: a satisfied group does not hide a mandatory script of another command" '[".claude/hooks/req.sh"]' "m.missing_hook_scripts(s, lambda r: r == '$F')" \
  "$(alt x.py)" 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/req.sh"'
unit "U5: groups never span two commands (each command needs its own existing candidate)" "[\"universal-agent-devkit/hooks/y.py\", \".claude/hooks/y.py\"]" "m.missing_hook_scripts(s, lambda r: r == '$F')" \
  "$(alt x.py)" "$(alt y.py)"
# Review 13/11 (principal-code-reviewer, P2): chỉ `[ -f "$v" ] && exec … "$v"` mới là thay thế. exec thay shell nên phần sau chỉ chạy khi
# file thiếu; mọi dạng khác (không exec, chuỗi &&, phép thử nằm trong echo, nháy đơn, dùng biến trước các mệnh đề) vẫn bắt buộc.
A='p="$CLAUDE_PROJECT_DIR"/.claude/hooks/a.sh; f="$CLAUDE_PROJECT_DIR"/.claude/hooks/b.sh; '
only_a="m.missing_hook_scripts(s, lambda r: r == '.claude/hooks/a.sh')"
unit "U6: guarded without exec, then run unguarded → the unguarded script stays mandatory" '[".claude/hooks/b.sh"]' "$only_a" \
  "$A"'[ -f "$p" ] && bash "$p"; [ -f "$f" ] && bash "$f"; bash "$f"'
unit "U7: an AND chain needs BOTH scripts" '[".claude/hooks/b.sh"]' "$only_a" \
  "$A"'[ -f "$p" ] && [ -f "$f" ] && bash "$p" && bash "$f"'
unit "U8: a guard that is only text inside an echo guards nothing" '[".claude/hooks/b.sh"]' "$only_a" \
  "$A"'echo "[ -f $p ] && exec bash $p; [ -f $f ] && exec bash $f"; bash "$p"; bash "$f"'
unit "U9: a variable run BEFORE the guarded clauses is not an alternative" '[".claude/hooks/b.sh"]' "$only_a" \
  "$A"'bash "$f"; [ -f "$p" ] && exec bash "$p"; [ -f "$f" ] && exec bash "$f"; exit 2'
unit "U10: a single-quoted guard tests a literal name, not the variable" '[".claude/hooks/b.sh"]' "$only_a" \
  "$A"'[ -f '"'"'$p'"'"' ] && exec bash "$p"; [ -f '"'"'$f'"'"' ] && exec bash "$f"; exit 2'
unit "U11: the fail-closed message after the last clause may name the variables" '[]' "$only_a" \
  "$A"'[ -f "$p" ] && exec bash "$p"; [ -f "$f" ] && exec bash "$f"; echo "missing ($p and $f)" >&2; exit 2'

# ── agent-kit health thật: repo chỉ có link đã cài, không có universal-agent-devkit/ ──
H="$TMP/h"; mkdir -p "$H/.claude/hooks"
hook "$SHIPPED" > "$H/.claude/settings.json"
echo 'print("guard")' > "$H/.claude/hooks/guard-protected-push.py"
DEVKIT_LANG=en python3 "$HEALTH" -t "$H" > "$TMP/h1.out" 2>&1
if grep -qE 'registered hooks missing|Registered hooks with no file' "$TMP/h1.out"; then
  fail "H1: health calls the shipped guard-protected-push hook missing although .claude/hooks/guard-protected-push.py exists: $(grep -E 'Registered hooks with no file' "$TMP/h1.out" | cut -c1-160)"
elif grep -qF 'Every hook in `.claude/settings.json` exists' "$TMP/h1.out"; then
  ok "H1: health accepts the shipped two-path hook when the installed link exists"
else
  fail "H1: health printed neither verdict of the hook check: $(tail -3 "$TMP/h1.out" | tr '\n' ' ' | cut -c1-200)"
fi
rm -f "$H/.claude/hooks/guard-protected-push.py"
DEVKIT_LANG=en python3 "$HEALTH" -t "$H" > "$TMP/h2.out" 2>&1; rc=$?
if [ "$rc" = 1 ] && grep -qF 'registered hooks missing' "$TMP/h2.out" && grep -qF '.claude/hooks/guard-protected-push.py' "$TMP/h2.out"; then
  ok "H2: with BOTH candidates gone health still fails (exit 1) and names the path"
else
  fail "H2: both candidates gone but health exit $rc / no 'registered hooks missing': $(grep -E 'Result|hooks' "$TMP/h2.out" | tail -2 | tr '\n' ' ' | cut -c1-200)"
fi

# ── post-fix-gate thật: settings.json đổi sang lệnh hai đường dẫn ──
mk() {
  R="$TMP/$1"; mkdir -p "$R/src" "$R/.agents" "$R/.claude/hooks" && cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt
  printf '.claude/hooks/\n' > .gitignore                               # link hook đã cài bị git ignore, như agent-kit init tạo
  echo 'echo stop' > .claude/hooks/stop.sh
  hook 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/stop.sh"' > .claude/settings.json
  # suite này FAIL nếu chạy: exit 0 bên dưới chứng minh thay đổi chỉ-settings không chạy suite nào
  printf '{"project":"t","rules":[{"component":"C","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-1","name":"c","command":"false"}]}]}\n' \
    > .agents/regression_matrix.active.json
  git add -A && git commit -qm init
}
expect() {   # tên repo, mô tả, exit mong đợi [, chuỗi output phải có]
  local rc; rc="$( cd "$TMP/$1" && CLAUDE_PROJECT_DIR="$TMP/$1" python3 "$GATE" --run-tests --json > "$TMP/$1.out" 2>&1; echo $? )"
  if [ "$rc" != "$3" ]; then
    fail "$2: exit $rc, expected $3 ($(grep -o 'hook runs a file that does not exist: [^"]*' "$TMP/$1.out" | head -1 | cut -c1-120))"
  elif [ -n "${4:-}" ] && ! grep -qF -- "$4" "$TMP/$1.out"; then
    fail "$2: exit $rc but the output does not name '$4'"
  else
    ok "$2 → exit $rc"
  fi
}
mk g1; hook 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/stop.sh"' "$SHIPPED" > .claude/settings.json
expect g1 "G1: the shipped guard-protected-push registration passes in a repo without universal-agent-devkit/" 0
mk g2; hook 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/stop.sh"' "$(alt zz_not_in_kit.py)" > .claude/settings.json
expect g2 "G2: both candidates of a script the kit does not ship are missing: still REJECT" 1 ".claude/hooks/zz_not_in_kit.py"
mk g3; hook 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/stop.sh"' "$(alt zz_not_in_kit.py)" > .claude/settings.json; echo 'print(1)' > .claude/hooks/zz_not_in_kit.py
expect g3 "G3: the same registration passes once the fallback file exists" 0

[ "$FAILS" -eq 0 ] && echo "✅ test_hook_alternative_paths: all passed" || { echo "❌ test_hook_alternative_paths: $FAILS failed"; exit 1; }
