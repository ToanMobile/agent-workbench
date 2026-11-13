#!/usr/bin/env bash
# Đợt 2 gate, lane A mục 2: `agent-kit approve-tests <task-id>` ghi mục duyệt chéo từ biên bản antigravity-pm. 13/11: chủ repo bỏ
# Grok — biên bản / trailer / mục reviewer grok không còn duyệt gì; các ca hợp lệ dùng reviewer antigravity.
#  C1  antigravity hợp lệ (verdicts.audit.reviewer antigravity, lượt audit gần nhất agent antigravity): lệnh ghi mục reviewer antigravity,
#      author = DEVKIT_AGENT_ID; gate nhận, nhãn "duyệt chéo bởi antigravity".
#  C2  DEVKIT_AGENT_ID rỗng -> lệnh từ chối, không ghi.   C3  reviewer trùng author -> lệnh từ chối; gate từ chối khi phiên là antigravity.
#  C4  biên bản grok (reviewer grok, lượt audit gần nhất grok) -> lệnh từ chối; mục viết tay reviewer grok -> gate từ chối.
#  C5  biên bản cũ (reviewer pm) + dispatch audit không ghi agent -> antigravity.   C6  biên bản cũ không dispatch -> lệnh từ chối.
#  C7  alias Antigravity-Pro / Antigravity -> antigravity.   C8  trailer `Test-approved-by: antigravity` phải khớp reviewer PM; trailer grok sai dạng.
#  C9  test sửa sau audit không được ghi.   C10  .claude/audit-gate trỏ ra ngoài checkout -> từ chối.
#  Sửa sau review đợt 2: C11 (F2) author = danh tính phiên (CLAUDECODE=1 -> claude) khi không có DEVKIT_AGENT_ID;
#  C12 (F2) phiên antigravity + reviewer antigravity -> tự duyệt; C13 (F6) ngoại lệ -> exit 3 (1 giữ nghĩa "không có test để ghi").
#  Vòng kiểm lại: C15 (H3) alias khớp laGrok/normalizeAgent của PM; C16-C17 (H4) tập danh tính phiên session_agents().
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_AUTO_APPROVE_TESTS DEVKIT_TRANSCRIPTS_DIR TARGET_DIR DEVKIT_AGENT_ID CLAUDE_CODE_SESSION_ID DEVKIT_SESSION_ID CLAUDE_SESSION_ID
unset WORKTREE_TRUNK_MODE DEVKIT_GATE_MERGE_CHECK CI
unset CLAUDECODE GROK_SESSION_ID GROK_WORKSPACE_ROOT GROK_HOOK_EVENT   # danh tính phiên (push_gate.session_agent): từng ca tự đặt
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.claude/projects"
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm"
export DEVKIT_PM_HOME_TEST=1
export GIT_CONFIG_GLOBAL=/dev/null
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
has() { printf '%s' "$OUT" | grep -qF -- "$1"; }
DA='{"kind":"audit","agent":"antigravity","at":"2026-11-01T00:00:00Z"}'
DG='{"kind":"audit","agent":"antigravity","at":"2026-11-02T00:00:00Z"}'      # lượt audit Antigravity gần nhất (reviewer hợp lệ)
DK='{"kind":"audit","agent":"grok","at":"2026-11-02T00:00:00Z"}'             # lượt grok cũ (trước 13/11): không còn duyệt
DL='{"kind":"audit","at":"2026-11-01T00:00:00Z"}'
pm_rec() {   # pm_rec <task-id> <project> <auditedHead> <reviewer> <dispatches-json-array>
  mkdir -p "$TMP/pm/projects/p-$1/tasks/$1"
  printf '{"id":"%s","project":"%s","dispatches":%s,"verdicts":{"audit":{"verdict":"pass","round":1,"reviewer":"%s","notes":"ok","auditedHead":"%s"}}}\n' \
    "$1" "$(cd "$2" && pwd -P)" "$5" "$4" "$3" > "$TMP/pm/projects/p-$1/tasks/$1/task.json"
}
mk() {   # mk <dir>: main M0, nhánh feat có commit X sửa tests/t.sh (không phải nối thêm); in X qua biến X
  mkdir -p "$1/src" "$1/tests" && cd "$1" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  printf '.claude/audit-gate/\n' > .gitignore
  mkdir -p .claude && echo '{"DEVKIT_IMPACT_TEST_ENABLED":"1","DEVKIT_REGRESSION_TEST_ENABLED":"1"}' > .claude/config.json
  cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh tests/t.sh && sh tests/u.sh"}]}]}
JSON
  echo 'fun ok()=1' > src/Core.kt
  printf '#!/bin/sh\ngrep -q "ok" src/Core.kt\n' > tests/t.sh; printf '#!/bin/sh\ngrep -q "fun" src/Core.kt\n' > tests/u.sh
  git add -A && git commit -qm M0 && git checkout -q -b feat
  printf '#!/bin/sh\ngrep -q "ok()" src/Core.kt\n' > tests/t.sh; echo 'fun ok()=2' > src/Core.kt
  git commit -qam "PR sửa test"; X="$(git rev-parse HEAD)"
}
kit() { OUT="$(cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$KIT" approve-tests "$2" 2>&1)"; RC=$?; }
run_gate() { OUT="$(cd "$1" && CLAUDE_PROJECT_DIR="$1" python3 "$GATE" --matrix "$1/matrix.json" --lang vi --run-tests --diff main 2>&1)"; RC=$?; }
ledger() { python3 - "$1/.claude/audit-gate/approved_tests.json" "$2" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
print(" ".join(f"{e['path']}:{e['reviewer']}:{e['author']}:{e['task_id']}" for e in d["approvals"] if e["path"] == sys.argv[2] or sys.argv[2] == "*"))
PY
}
hand_entry() {   # hand_entry <repo> <task> <reviewer>: mục viết tay cho tests/t.sh
  mkdir -p "$1/.claude/audit-gate"
  python3 - "$1" "$2" "$3" <<'PY'
import hashlib, json, os, sys
root, tid, rv = sys.argv[1:4]
sha = hashlib.sha256(open(os.path.join(root, "tests/t.sh"), "rb").read()).hexdigest()
json.dump({"approvals": [{"path": "tests/t.sh", "sha256": sha, "reviewer": rv, "author": "claude", "task_id": tid, "reason": "tay"}]},
          open(os.path.join(root, ".claude/audit-gate/approved_tests.json"), "w"))
PY
}

# C1
mk "$TMP/c1"; pm_rec T0901-c1 "$TMP/c1" "$X" antigravity "[$DA,$DG]"
DEVKIT_AGENT_ID=claude-lane kit "$TMP/c1" T0901-c1; L="$(ledger "$TMP/c1" tests/t.sh)"
if [ "$RC" = 0 ] && [ "$L" = "tests/t.sh:antigravity:claude-lane:T0901-c1" ]; then ok "C1: lệnh ghi mục reviewer antigravity, author = DEVKIT_AGENT_ID"
else bad "C1: lệnh antigravity: rc=$RC ledger='$L' $(printf '%s' "$OUT" | tail -3)"; fi
run_gate "$TMP/c1"
if [ "$RC" = 0 ] && has "duyệt chéo bởi antigravity (task T0901-c1)"; then ok "C1: gate nhận, nhãn antigravity"
else bad "C1: gate với mục antigravity: rc=$RC $(printf '%s' "$OUT" | grep -E 'duyệt|Duyệt' | tail -3)"; fi
# C3 (gate): cùng mục, phiên hiện tại là antigravity -> từ chối
OUT="$(cd "$TMP/c1" && DEVKIT_AGENT_ID=antigravity CLAUDE_PROJECT_DIR="$TMP/c1" python3 "$GATE" --matrix "$TMP/c1/matrix.json" --lang vi --run-tests --diff main 2>&1)"; RC=$?
if [ "$RC" = 2 ] && has "trùng author"; then ok "C3: gate, phiên là antigravity, reviewer PM antigravity -> từ chối (tự duyệt)"
else bad "C3: gate tự duyệt antigravity: rc=$RC $(printf '%s' "$OUT" | grep -E 'Duyệt' | tail -2)"; fi

# C2
mk "$TMP/c2"; pm_rec T0902-c2 "$TMP/c2" "$X" antigravity "[$DG]"
kit "$TMP/c2" T0902-c2
if [ "$RC" = 2 ] && has "DEVKIT_AGENT_ID" && [ ! -f "$TMP/c2/.claude/audit-gate/approved_tests.json" ]; then ok "C2: DEVKIT_AGENT_ID rỗng -> từ chối, không ghi"
else bad "C2: id rỗng: rc=$RC $(printf '%s' "$OUT" | tail -2)"; fi

# C3 (lệnh): author trùng reviewer qua alias
DEVKIT_AGENT_ID=antigravity-ultra kit "$TMP/c2" T0902-c2
if [ "$RC" = 2 ] && has "tự duyệt" && [ ! -f "$TMP/c2/.claude/audit-gate/approved_tests.json" ]; then ok "C3: lệnh, author antigravity-ultra = reviewer antigravity -> từ chối"
else bad "C3: lệnh tự duyệt: rc=$RC $(printf '%s' "$OUT" | tail -2)"; fi

# C4 (13/11): biên bản grok cũ hợp lệ theo luật trước (reviewer grok, lượt audit gần nhất grok) -> lệnh từ chối
mk "$TMP/c4"; pm_rec T0904-c4 "$TMP/c4" "$X" grok "[$DA,$DK]"
DEVKIT_AGENT_ID=claude-lane kit "$TMP/c4" T0904-c4
if [ "$RC" = 2 ] && has "reviewer" && [ ! -f "$TMP/c4/.claude/audit-gate/approved_tests.json" ]; then ok "C4: biên bản grok -> lệnh từ chối"
else bad "C4: lệnh với biên bản grok: rc=$RC $(printf '%s' "$OUT" | tail -2)"; fi
hand_entry "$TMP/c4" T0904-c4 grok; run_gate "$TMP/c4"
if [ "$RC" = 2 ] && has "không xác định được reviewer"; then ok "C4: mục viết tay reviewer grok -> gate từ chối"
else bad "C4: gate mục grok: rc=$RC $(printf '%s' "$OUT" | grep -E 'duyệt|Duyệt' | tail -2)"; fi

# C5: biên bản cũ (reviewer pm) + dispatch audit không ghi agent -> antigravity
mk "$TMP/c5"; pm_rec T0905-c5 "$TMP/c5" "$X" pm "[$DL]"
DEVKIT_AGENT_ID=claude-lane kit "$TMP/c5" T0905-c5; L="$(ledger "$TMP/c5" tests/t.sh)"
run_gate "$TMP/c5"
if [ "$L" = "tests/t.sh:antigravity:claude-lane:T0905-c5" ] && [ "$RC" = 0 ] && has "duyệt chéo bởi antigravity (task T0905-c5)"; then
  ok "C5: biên bản cũ + dispatch audit không agent -> antigravity, gate nhận"
else bad "C5: biên bản cũ: rc=$RC ledger='$L'"; fi

# C6: biên bản cũ không dispatch nào -> lệnh từ chối
mk "$TMP/c6"; pm_rec T0906-c6 "$TMP/c6" "$X" pm "[]"
DEVKIT_AGENT_ID=claude-lane kit "$TMP/c6" T0906-c6
if [ "$RC" = 2 ] && [ ! -f "$TMP/c6/.claude/audit-gate/approved_tests.json" ]; then ok "C6: biên bản cũ không dispatch audit -> lệnh từ chối"
else bad "C6: biên bản cũ không dispatch: rc=$RC $(printf '%s' "$OUT" | tail -2)"; fi

# C7: alias
mk "$TMP/c7"; pm_rec T0907-c7 "$TMP/c7" "$X" Antigravity-Pro '[{"kind":"audit","agent":"Antigravity","at":"2026-11-02T00:00:00Z"}]'
DEVKIT_AGENT_ID=claude-lane kit "$TMP/c7" T0907-c7; L="$(ledger "$TMP/c7" tests/t.sh)"
if [ "$RC" = 0 ] && [ "$L" = "tests/t.sh:antigravity:claude-lane:T0907-c7" ]; then ok "C7: alias Antigravity-Pro / Antigravity -> antigravity"
else bad "C7: alias: rc=$RC ledger='$L'"; fi

# C8: trailer phải khớp reviewer PM
pgok() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import push_gate as p; print(*p.approved(sys.argv[2], "HEAD^!"))' "$DEVKIT_DIR/bin" "$1" 2>&1; }
mk "$TMP/c8"; pm_rec T0908-g "$TMP/c8" "$X" grok "[$DK]"; pm_rec T0908-l "$TMP/c8" "$X" pm "[$DL]"
git commit -q --allow-empty -m a -m "Test-approved-by: grok T0908-g"; OUT="$(pgok "$TMP/c8")"
case "$OUT" in False*"sai dạng"*) ok "C8: trailer grok + biên bản grok -> từ chối (13/11)";; *) bad "C8: trailer grok: $OUT";; esac
git commit -q --allow-empty --amend -m a -m "Test-approved-by: antigravity T0908-g"; OUT="$(pgok "$TMP/c8")"
case "$OUT" in False*reviewer*) ok "C8: trailer antigravity, biên bản grok -> từ chối";; *) bad "C8: trailer antigravity/biên bản grok: $OUT";; esac
git commit -q --allow-empty --amend -m a -m "Test-approved-by: grok T0908-l"; OUT="$(pgok "$TMP/c8")"
case "$OUT" in False*"sai dạng"*) ok "C8: trailer grok, biên bản cũ (antigravity) -> từ chối";; *) bad "C8: trailer grok/biên bản cũ: $OUT";; esac
git commit -q --allow-empty --amend -m a -m "Test-approved-by: antigravity T0908-l"; OUT="$(pgok "$TMP/c8")"
case "$OUT" in True*) ok "C8: trailer antigravity + biên bản cũ -> approved (như trước)";; *) bad "C8: trailer antigravity cũ: $OUT";; esac

# C9: tests/u.sh sửa SAU audit -> không ghi; tests/t.sh vẫn ghi
mk "$TMP/c9"; pm_rec T0909-c9 "$TMP/c9" "$X" antigravity "[$DG]"
printf '#!/bin/sh\ngrep -q "fun ok" src/Core.kt\n' > tests/u.sh
DEVKIT_AGENT_ID=claude-lane kit "$TMP/c9" T0909-c9; L="$(ledger "$TMP/c9" '*')"
if [ "$RC" = 0 ] && [ "$L" = "tests/t.sh:antigravity:claude-lane:T0909-c9" ] && has "bỏ qua tests/u.sh"; then ok "C9: test sửa sau audit không được ghi"
else bad "C9: test sửa sau audit: rc=$RC ledger='$L'"; fi

# C10: .claude/audit-gate là symlink ra ngoài checkout
mk "$TMP/c10"; pm_rec T0910-c10 "$TMP/c10" "$X" antigravity "[$DG]"
mkdir -p "$TMP/outside" && ln -s "$TMP/outside" "$TMP/c10/.claude/audit-gate"
DEVKIT_AGENT_ID=claude-lane kit "$TMP/c10" T0910-c10
if [ "$RC" = 2 ] && has "ngoài checkout" && [ ! -f "$TMP/outside/approved_tests.json" ]; then ok "C10: thư mục duyệt trỏ ra ngoài checkout -> từ chối"
else bad "C10: symlink ra ngoài: rc=$RC $(printf '%s' "$OUT" | tail -2)"; fi
# C10b (OCR P3 đợt 2): .claude là symlink ra ngoài -> từ chối VÀ không tạo audit-gate/ ở đích ngoài checkout (cũ: mkdir trước khi kiểm)
mk "$TMP/c10b"; pm_rec T0910-c10b "$TMP/c10b" "$X" antigravity "[$DG]"
mkdir -p "$TMP/outside2" && mv "$TMP/c10b/.claude/config.json" "$TMP/outside2/" && rmdir "$TMP/c10b/.claude" && ln -s "$TMP/outside2" "$TMP/c10b/.claude"
DEVKIT_AGENT_ID=claude-lane kit "$TMP/c10b" T0910-c10b
if [ "$RC" = 2 ] && has "ngoài checkout" && [ ! -e "$TMP/outside2/audit-gate" ]; then ok "C10b: .claude trỏ ra ngoài -> từ chối, không tạo thư mục ở ngoài"
else bad "C10b: .claude symlink: rc=$RC audit-gate ngoài=$([ -e "$TMP/outside2/audit-gate" ] && echo có || echo không) $(printf '%s' "$OUT" | tail -2)"; fi

# ── Đợt 2, sửa sau review (F2, F6) ────────────────────────────────────────────────────────────────────────────────────────
# C11 (F2): không DEVKIT_AGENT_ID, phiên Claude Code (CLAUDECODE=1) -> author "claude", lệnh ghi
mk "$TMP/c11"; pm_rec T0911-c11 "$TMP/c11" "$X" antigravity "[$DG]"
CLAUDECODE=1 kit "$TMP/c11" T0911-c11; L="$(ledger "$TMP/c11" tests/t.sh)"
if [ "$RC" = 0 ] && [ "$L" = "tests/t.sh:antigravity:claude:T0911-c11" ]; then ok "C11: phiên Claude Code không DEVKIT_AGENT_ID -> author claude, ghi mục"
else bad "C11: CLAUDECODE=1: rc=$RC ledger='$L' $(printf '%s' "$OUT" | tail -2)"; fi
# C12 (F2): phiên Antigravity (DEVKIT_AGENT_ID=antigravity), reviewer PM antigravity -> tự duyệt, từ chối
mk "$TMP/c12"; pm_rec T0912-c12 "$TMP/c12" "$X" antigravity "[$DG]"
DEVKIT_AGENT_ID=antigravity CLAUDECODE=1 kit "$TMP/c12" T0912-c12
if [ "$RC" = 2 ] && has "tự duyệt" && [ ! -f "$TMP/c12/.claude/audit-gate/approved_tests.json" ]; then ok "C12: phiên antigravity, reviewer antigravity -> từ chối (tự duyệt)"
else bad "C12: phiên antigravity: rc=$RC $(printf '%s' "$OUT" | tail -2)"; fi
# C13 (F6): lỗi ngoài dự kiến (.claude/audit-gate là file thường: mkdir ném) -> exit 3 kèm thông báo, không phải exit 1 ("không có test")
mk "$TMP/c13"; pm_rec T0913-c13 "$TMP/c13" "$X" antigravity "[$DG]"
printf 'x\n' > "$TMP/c13/.claude/audit-gate"
DEVKIT_AGENT_ID=claude-lane kit "$TMP/c13" T0913-c13
if [ "$RC" = 3 ] && has "approve-tests: lỗi"; then ok "C13: ngoại lệ -> exit 3 kèm thông báo"
else bad "C13: ngoại lệ: rc=$RC (muốn 3) $(printf '%s' "$OUT" | tail -2)"; fi

# C14 (khớp normalizeAgent/laGrok của PM): "grok"/"antigravity" rồi hết chuỗi hoặc - _ . -> tên chuẩn; "grokker" giữ nguyên;
#     session_agent: DEVKIT_AGENT_ID chỉ khoảng trắng -> bước sau; CLAUDECODE phải đúng "1"
OUT="$(env -u DEVKIT_AGENT_ID -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID python3 -c 'import os, sys
sys.path.insert(0, sys.argv[1]); import push_gate as p
names = [p.normalize_reviewer(v) for v in ("grok_x", "grok.x", " GROK-4 ", "antigravity-pro", "Antigravity_2", "antigravity.x", "grokker")]
os.environ["DEVKIT_AGENT_ID"] = "   "; os.environ["CLAUDECODE"] = "true"; a = p.session_agent()
os.environ["CLAUDECODE"] = "1"; b = p.session_agent()
print(" ".join(names + [a or "-", b or "-"]))' "$DEVKIT_DIR/bin" 2>&1)"
if [ "$OUT" = "grok grok grok antigravity antigravity antigravity grokker - claude" ]; then ok "C14: alias grok_x / grok.x / antigravity-pro chuẩn hoá như PM; id chỉ khoảng trắng bỏ qua, CLAUDECODE phải là 1"
else bad "C14: chuẩn hoá alias / danh tính: '$OUT' (muốn 'grok grok grok antigravity antigravity antigravity grokker - claude')"; fi

# ── Vòng kiểm lại (H3, H4) ──────────────────────────────────────────────────────────────────────────────────────────────────
# C15 (H3): normalize_reviewer dùng đúng luật laGrok của PM (`^grok(?![a-z0-9])` sau strip+casefold; "grok build", "grok:" là grok,
#     "grok4"/"grokker" không) và cùng tập ký tự strip với PM (JS trim bỏ ﻿, Python strip bỏ \x1f: hai bên bỏ cả hai)
OUT="$(python3 -c 'import sys
sys.path.insert(0, sys.argv[1]); import push_gate as p
vals = ("grok build", "grok:", "Grok4", "grokker", "﻿grok", "\x1fgrok-4", " antigravity_2﻿", "antigravity.x", "antigravityx")
print("|".join(p.normalize_reviewer(v) for v in vals))' "$DEVKIT_DIR/bin" 2>&1)"
if [ "$OUT" = "grok|grok|grok4|grokker|grok|grok|antigravity|antigravity|antigravityx" ]; then ok "C15: alias grok/antigravity khớp normalizeAgent/laGrok của PM"
else bad "C15: normalize_reviewer: '$OUT' (muốn 'grok|grok|grok4|grokker|grok|grok|antigravity|antigravity|antigravityx')"; fi
# C16 (H4): session_agents() = {DEVKIT_AGENT_ID chuẩn hoá} ∪ {grok khi GROK_*} ∪ {claude khi CLAUDECODE=1/CLAUDE_CODE_SESSION_ID};
#     session_agent() giữ nguyên (codex)
OUT="$(env -u CLAUDE_CODE_SESSION_ID DEVKIT_AGENT_ID=Codex GROK_SESSION_ID=g-1 CLAUDECODE=1 python3 -c 'import sys
sys.path.insert(0, sys.argv[1]); import push_gate as p
print(p.session_agent(), ",".join(sorted(p.session_agents())))' "$DEVKIT_DIR/bin" 2>&1)"
if [ "$OUT" = "codex claude,codex,grok" ]; then ok "C16: session_agents = {codex, grok, claude}, session_agent vẫn codex"
else bad "C16: danh tính phiên: '$OUT' (muốn 'codex claude,codex,grok')"; fi
# C17 (H4; 13/11 bỏ Grok): phiên Claude Code mang DEVKIT_AGENT_ID=Antigravity-Ultra -> tập danh tính {antigravity, claude} chứa
#     reviewer antigravity -> tự duyệt, từ chối. Tập nhiều danh tính (GROK_*) đã kiểm ở C16.
mk "$TMP/c17"; pm_rec T0917-c17 "$TMP/c17" "$X" antigravity "[$DG]"
DEVKIT_AGENT_ID=Antigravity-Ultra CLAUDECODE=1 kit "$TMP/c17" T0917-c17
if [ "$RC" = 2 ] && has "tự duyệt" && [ ! -f "$TMP/c17/.claude/audit-gate/approved_tests.json" ]; then ok "C17: reviewer thuộc tập danh tính phiên -> từ chối (tự duyệt)"
else bad "C17: Antigravity-Ultra + CLAUDECODE: rc=$RC $(printf '%s' "$OUT" | tail -2)"; fi
# C17c đối chứng: cùng biên bản, phiên claude-lane -> ghi
mk "$TMP/c17c"; pm_rec T0918-c17c "$TMP/c17c" "$X" antigravity "[$DG]"
DEVKIT_AGENT_ID=claude-lane kit "$TMP/c17c" T0918-c17c; L="$(ledger "$TMP/c17c" tests/t.sh)"
if [ "$RC" = 0 ] && [ "$L" = "tests/t.sh:antigravity:claude-lane:T0918-c17c" ]; then ok "C17c: phiên claude-lane -> ghi mục author claude-lane"
else bad "C17c: đối chứng: rc=$RC ledger='$L' $(printf '%s' "$OUT" | tail -2)"; fi

[ "$FAILS" -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }
