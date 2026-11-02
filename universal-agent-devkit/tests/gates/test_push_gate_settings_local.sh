#!/usr/bin/env bash
# bin/push_gate.py + bin/post-fix-gate.py, #691 (plan r5, mục 3, ca P1-P9). Bản cài kit sửa .claude/settings.json của worktree và không commit;
# tree_fingerprint() ghim file đó về blob HEAD, nên biên nhận hợp lệ phải KHÔNG ghi nó vào `dirty` (push_gate dựng lại cây từ head+dirty).
# Gate chạy THẬT (post-fix-gate --full), settings.json sửa giữ khối hooks hợp lệ (settings_problems đọc nó, mẫu test_push_gate.sh).
#   ĐỎ-THẬT (đỏ trên da9ad59e vì `dirty` còn chứa path ghim: "fingerprint không khớp code head+dirty" hoặc _covered bác path đó):
#     P1 push trực tiếp · P2 worktree liên kết · P3 `worktree finish` rồi push từ main · P4 HEAD chưa có settings.json · P5 project là thư mục con
#     P6 thư mục chưa track .claude/settings.json/foo (HEAD chưa có file, có commit đổi file watched)
#   CHỐT-CHẶN (xanh cả trước lẫn sau, không được lỏng đi): P7 commit đúng bản sửa sau gate khi ma trận có rule Cfg theo dõi settings.json
#     bị từ chối · P8 settings.json ĐÃ commit đổi sau gate (Cfg) bị từ chối, fingerprint commit ≠ biên nhận · P9 không có Cfg thì file "không cần test" qua.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"; WTPY="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
R="$TMP/repo"; W="$TMP/wt"

HOOKS_BASE='"Stop":[{"hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/session_lock.sh\""}]}]'
SET_COMMITTED="{\"hooks\":{$HOOKS_BASE}}"
# sửa cục bộ của bản cài kit: thêm một hook có thật của kit, khối hooks vẫn hợp lệ
SET_LOCAL="{\"hooks\":{$HOOKS_BASE,\"PreToolUse\":[{\"matcher\":\"Read\",\"hooks\":[{\"type\":\"command\",\"command\":\"bash \\\"\$CLAUDE_PROJECT_DIR/.claude/hooks/instincts_file_context.sh\\\"\"}]}]}}"

# chk <thư mục> <rev> <linked 0|1>: đặt CHK_OK (OK|NO) và CHK_WHY từ push_gate.check
chk() {
  local o; o="$(python3 - "$DEVKIT_DIR/bin" "$1" "$2" "$3" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import push_gate
ok, why = push_gate.check(sys.argv[2], sys.argv[3], linked=sys.argv[4] == "1")
print(("OK" if ok else "NO") + "|" + str(why).replace("\n", " "))
PY
  )"; CHK_OK="${o%%|*}"; CHK_WHY="${o#*|}"
}
want_ok() { # <tên>: ca đã gọi chk, phải được phép
  [ "$CHK_OK" = OK ] && ok "$1: push hợp lệ không bị từ chối" || bad "$1: bị từ chối — $(printf '%s' "$CHK_WHY" | head -c 300)"
}
want_no() { # <tên>: ca đã gọi chk, phải bị từ chối
  [ "$CHK_OK" = NO ] && ok "$1: bị từ chối ($(printf '%s' "$CHK_WHY" | head -c 90))" || bad "$1: bị cho qua — $CHK_WHY"
}
gate_in() { # <thư mục project> [đối số gate…]: gate --full THẬT; exit khác 0 là lỗi dựng ca, không phải kết quả
  local d="$1"; shift
  CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --run-tests --full --brief "$@" > "$TMP/gate.out" 2>&1 \
    || bad "dựng ca: gate --full trong $d exit $? ($(tail -3 "$TMP/gate.out" | tr '\n' ' '))"
}

# newrepo <cfg|nocfg> <settings|nosettings>: repo + origin + worktree W (nhánh task); cfg = ma trận có rule Cfg theo dõi .claude/settings.json
newrepo() {
  git -C "$R" worktree prune 2>/dev/null; rm -rf "$R" "$W" "$TMP/origin.git"; mkdir -p "$R/src" "$R/.agents" && cd "$R" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  echo "fun ok() = 1" > src/Core.kt
  if [ "$1" = cfg ]; then
    cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]},
 {"component":"Cfg","watch_files":[".claude/settings.json"],
 "mandatory_regression_tests":[{"id":"REG-CFG","name":"config","command":"true"}]}]}
JSON
  else
    cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}
JSON
  fi
  printf '.agents/CHECKLIST.md\n.agents/regression_status.json\n.agents/evidence/\n.agents/regression_journal/\n.claude/audit-gate/\n' > .gitignore
  if [ "$2" = settings ]; then mkdir -p .claude && printf '%s\n' "$SET_COMMITTED" > .claude/settings.json; fi
  git add -A && git commit -qm init
  git init -q --bare "$TMP/origin.git" && git remote add origin "$TMP/origin.git" && git push -q -u origin HEAD 2>/dev/null
  git worktree add -q -b task "$W" main
}
put_local() { mkdir -p "$(dirname "$1")" && printf '%s\n' "$SET_LOCAL" > "$1"; }   # file settings.json sửa cục bộ

# P1 (đỏ-thật): gate trên cây có settings.json sửa chưa commit, push HEAD từ chính repo đó
newrepo cfg settings
put_local "$R/.claude/settings.json"; gate_in "$R"; chk "$R" HEAD 0
want_ok "P1 settings.json sửa cục bộ, gate xong, push trực tiếp"

# P2 (đỏ-thật): như P1 trong worktree liên kết, chỉ xét biên nhận của chính worktree đó
newrepo cfg settings
put_local "$W/.claude/settings.json"; gate_in "$W"; chk "$W" HEAD 1
want_ok "P2 settings.json sửa cục bộ trong worktree liên kết (linked)"

# P3 (đỏ-thật): bản cài kit sửa settings.json của worktree (baseline lấy SAU bước giả lập), gate, finish, push từ main
newrepo cfg settings
put_local "$W/.claude/settings.json"
python3 - "$WTPY" "$W" "$R" <<'PY' || bad "dựng ca P3: ghi state của worktree thất bại"
# việc `worktree add` ghi khi kit đã cài: phần cài đặt là baseline, `finish` không bao giờ commit nó (mẫu ca L25, test_push_gate_linked_worktree.sh)
import os, subprocess, sys
sys.path.insert(0, os.path.dirname(sys.argv[1]))
import worktree as w
wt, main = sys.argv[2], sys.argv[3]
head = subprocess.run(["git", "-C", wt, "rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
w._write_state(wt, {"branch": "task", "base": head, "main": main, "baseline": w.snapshot(wt), "fp": w.FP_VERSION})
PY
echo "fun ok() = 3" > "$W/src/Core.kt"; gate_in "$W"
git -C "$W" commit -qm "task work 3" -- src/Core.kt || bad "dựng ca P3: commit việc thật thất bại"   # chỉ việc thật, không bao giờ phần cài đặt
(cd "$R" && GIT_CONFIG_GLOBAL=/dev/null python3 "$WTPY" finish "$W" > "$TMP/finish.out" 2>&1); FRC=$?
if [ "$FRC" != 0 ] || [ -d "$W" ]; then bad "P3 worktree finish hợp lệ bị từ chối (exit $FRC): $(tail -3 "$TMP/finish.out" | tr '\n' ' ' | head -c 300)"
else chk "$R" HEAD 0; want_ok "P3 gate trong worktree, finish, rồi push từ main"; fi

# P4 (đỏ-thật): HEAD chưa có settings.json, file hợp lệ mới chưa track
newrepo cfg nosettings
put_local "$R/.claude/settings.json"; gate_in "$R"; chk "$R" HEAD 0
want_ok "P4 HEAD chưa có settings.json, file mới chưa track"

# P5 (đỏ-thật): project là thư mục con app/ của repo; path ghim tính theo project
cd "$TMP" && rm -rf "$R" "$W" "$TMP/origin.git" && mkdir -p "$R/app/src" "$R/app/.agents" "$R/app/.claude" && cd "$R" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
echo "fun ok() = 1" > app/src/Core.kt; printf '%s\n' "$SET_COMMITTED" > app/.claude/settings.json
cat > app/.agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}
JSON
printf '.agents/CHECKLIST.md\n.agents/regression_status.json\n.agents/evidence/\n.agents/regression_journal/\n.claude/audit-gate/\n' > app/.gitignore
git add -A && git commit -qm init
put_local "$R/app/.claude/settings.json"; gate_in "$R/app"; chk "$R/app" HEAD 0
want_ok "P5 project là thư mục con (app/.claude/settings.json sửa cục bộ)"

# P6 (đỏ-thật): HEAD chưa có settings.json; commit đổi file watched để gate --diff đạt exit 0; thư mục chưa track .claude/settings.json/foo
newrepo nocfg nosettings
echo "fun ok() = 6" > "$W/src/Core.kt"; git -C "$W" commit -qam "task work 6"
mkdir -p "$W/.claude/settings.json" && printf 'x\n' > "$W/.claude/settings.json/foo"
gate_in "$W" --diff main; chk "$W" HEAD 1
want_ok "P6 thư mục chưa track .claude/settings.json/foo (linked)"

# P7 (chốt chặn): bản sửa cục bộ được commit SAU gate, ma trận có Cfg theo dõi settings.json: không được tự phủ
newrepo cfg settings
put_local "$R/.claude/settings.json"; gate_in "$R"
git -C "$R" commit -qm "commit đúng bản sửa cục bộ" -- .claude/settings.json || bad "dựng ca P7: commit thất bại"
chk "$R" HEAD 0; want_no "P7 commit đúng bản sửa settings.json sau gate (Cfg theo dõi)"

# P8 (chốt chặn): settings.json ĐÃ commit đổi sau gate (gate chạy trên cây sạch); Cfg theo dõi; fingerprint commit ≠ biên nhận
newrepo cfg settings
echo "fun ok() = 8" > "$R/src/Core.kt"; gate_in "$R"; git -C "$R" commit -qm "việc đã gate" -- src/Core.kt   # cây sạch thì gate exit 3: cần một thay đổi code để có biên nhận
RECFP="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["fingerprint"])' "$(git -C "$R" rev-parse --absolute-git-dir)/postfix-gate/full_pass.json")"
put_local "$R/.claude/settings.json"; git -C "$R" commit -qm "đổi settings.json sau gate" -- .claude/settings.json || bad "dựng ca P8: commit thất bại"
CFP="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import tree_fp; print(tree_fp.commit_fingerprint(sys.argv[2]))' "$DEVKIT_DIR/bin" "$R")"
[ -n "$CFP" ] && [ "$CFP" != "$RECFP" ] && ok "P8a commit_fingerprint(HEAD) ≠ fingerprint của biên nhận (settings.json đã commit thay đổi thật)" || bad "P8a fingerprint commit trùng biên nhận ($CFP / $RECFP)"
chk "$R" HEAD 0; want_no "P8 settings.json đã commit đổi sau gate (Cfg theo dõi)"

# P9 (chốt chặn, hành vi hiện có): không có rule Cfg thì settings.json hợp lệ là file "không cần test"
newrepo nocfg settings
echo "fun ok() = 9" > "$R/src/Core.kt"; gate_in "$R"; git -C "$R" commit -qm "việc đã gate" -- src/Core.kt
put_local "$R/.claude/settings.json"; git -C "$R" commit -qm "đổi settings.json sau gate" -- .claude/settings.json || bad "dựng ca P9: commit thất bại"
chk "$R" HEAD 0; want_ok "P9 không có rule Cfg: settings.json hợp lệ không cần test"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
