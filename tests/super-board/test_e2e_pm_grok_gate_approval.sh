#!/usr/bin/env bash
# 04/11 đầu-cuối (không bước người): code PM THẬT (mcp-servers/antigravity-pm-mcp/src/tools.js, gọi thẳng handler như server MCP) tạo
# task và chạy audit grok, rồi post-fix-gate.py THẬT đọc chính biên bản đó và duyệt test cũ bị sửa — không approved_tests.json, không
# trailer, không comment, không pm_verdict. Bắt lệch khuôn dữ liệu giữa bên ghi (JS: dispatch auditBase/edited, verdicts.audit reviewer,
# thứ tự dispatch rồi verdict) và bên đọc (Python: push_gate.audited_head / audit_reviewer / audit_scope, post-fix-gate audit_covers).
# Chỉ grok là giả (ANTIGRAVITY_PM_GROK: in VERDICT), pm home là fixture dưới $TMP.
#  E2E1 grok PASS -> gate exit 0 "duyệt chéo bởi grok"; merge gate --has-edited-tests -> pm.
#  E2E2 sửa test lần nữa sau audit -> gate exit 2 (blob khác cây đã audit).
#  E2E3 grok REVISE -> không biên bản -> gate exit 2.   E2E4 pm_dispatch có message -> không tự ghi -> gate exit 2.
#  E2E5 phiên chạy gate là grok -> exit 2 (tự duyệt).   E2E6 người gọi PM là grok -> PM từ chối, gate exit 2.
#  E2E7 main tiến không chạm test, scratch merge gate -> vẫn duyệt.  E2E8 main sửa chính test sau audit -> exit 2.
#  E2E9 grok PASS rồi REVISE cùng head -> exit 2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
GATE="$ROOT/universal-agent-devkit/bin/post-fix-gate.py"
INS="$ROOT/.claude/bin/super-board-install-edited-test-approval.sh"
TOOLS="$ROOT/mcp-servers/antigravity-pm-mcp/src/tools.js"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-e2e-pm.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.claude/projects"
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm" DEVKIT_PM_HOME_TEST=1 ANTIGRAVITY_PM_QUIET=1
unset DEVKIT_AUTO_APPROVE_TESTS DEVKIT_TRANSCRIPTS_DIR TARGET_DIR DEVKIT_AGENT_ID CLAUDE_CODE_SESSION_ID DEVKIT_SESSION_ID CLAUDE_SESSION_ID
unset WORKTREE_TRUNK_MODE DEVKIT_GATE_MERGE_CHECK CI CLAUDECODE GROK_SESSION_ID GROK_WORKSPACE_ROOT GROK_HOOK_EVENT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
has() { printf '%s' "$OUT" | grep -qF -- "$1"; }

fake_grok() {   # fake_grok <dir> <VERDICT-line>: grok giả in một dòng VERDICT, thoát 0
  mkdir -p "$1"
  printf '#!/bin/sh\necho "Đã đọc diff."\necho "%s"\n' "$2" > "$1/grok"
  chmod +x "$1/grok"
}
fake_grok "$TMP/gpass" "VERDICT: PASS"
fake_grok "$TMP/grev" "VERDICT: REVISE"

mk() {   # mk <dir>: main (test V0) + nhánh feat sửa dòng 2 của tests/t.sh (không phải nối thêm), đã commit, cây sạch
  mkdir -p "$1/src" "$1/tests" && cd "$1" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  printf '.claude/audit-gate/\n.antigravity-pm/\n.antigravity-pm.json\n' > .gitignore
  printf '{"projectName":"e2e","testCommand":"sh tests/t.sh"}\n' > .antigravity-pm.json
  mkdir -p .claude && echo '{"DEVKIT_IMPACT_TEST_ENABLED":"1","DEVKIT_REGRESSION_TEST_ENABLED":"1"}' > .claude/config.json
  printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*"],"mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh tests/t.sh"}]}]}\n' > matrix.json
  echo 'fun ok()=1' > src/Core.kt
  printf '#!/bin/sh\ngrep -q "ok" src/Core.kt\ngrep -q "fun" src/Core.kt\n' > tests/t.sh
  git add -A && git commit -qm M0 && git checkout -q -b feat
  printf '#!/bin/sh\ngrep -q "ok()" src/Core.kt\ngrep -q "fun" src/Core.kt\n' > tests/t.sh
  echo 'fun ok()=2' > src/Core.kt
  git commit -qam "PR sửa test"
}

pm() {   # pm <project> <grok-dir> [message] [env...]: pm_task_create + pm_dispatch kind=audit agent=grok bằng code PM thật; in kết quả
  local dir="$1" g="$2" msg="${3:-}"; shift 3 2>/dev/null || shift $#
  OUT="$(cd "$dir" && env ANTIGRAVITY_PM_GROK="$g/grok" "$@" node --input-type=module -e '
const [tools, project, msg] = process.argv.slice(1);
const { TOOLS_BY_NAME } = await import(tools);
const call = (n, a) => TOOLS_BY_NAME.get(n).handler(a);
try {
  const created = await call("pm_task_create", { project, title: "Audit PR e2e", brief: "Audit chéo test sửa của PR.",
    definitionOfDone: ["Test sửa không nới assertion"] });
  const id = String(created).match(/T\d{4,}-[a-z0-9-]+/)[0];
  console.log("TASK " + id);
  console.log(await call("pm_dispatch", { project, taskId: id, kind: "audit", agent: "grok", ...(msg ? { message: msg } : {}) }));
} catch (e) { console.log("PM-ERROR " + e.message); }
' "$TOOLS" "$dir" "$msg" 2>&1)"
}
run_gate() { local d="$1"; shift; OUT="$(cd "$d" && env "$@" CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --matrix "$d/matrix.json" --lang vi --run-tests --diff main 2>&1)"; RC=$?; }
approved() { [ "$RC" = 0 ] && has "duyệt chéo bởi grok (thay Antigravity)" && [ ! -e "$1/.claude/audit-gate/approved_tests.json" ] \
             && [ -z "$(git -C "$1" log --format=%B main..HEAD | grep -i 'Test-approved-by')" ]; }
refused()  { [ "$RC" = 2 ] && ! has "duyệt chéo bởi"; }
tailout()  { printf '%s' "$OUT" | grep -E "duyệt chéo|Test đã có|CHƯA XÁC MINH|PM-ERROR|TASK|exit" | tail -4 | cut -c1-240; }

# E2E1. luồng thật: PM tạo task + chạy grok (PASS) -> PM tự ghi biên bản -> gate duyệt; merge gate thấy duyệt từ biên bản PM
mk "$TMP/e1"; pm "$TMP/e1" "$TMP/gpass" ""
if printf '%s' "$OUT" | grep -q "Da tu ghi verdict audit=pass"; then ok "E2E1a: PM tự ghi verdict sau grok PASS"; else bad "E2E1a: PM: $(tailout)"; fi
run_gate "$TMP/e1" CLAUDECODE=1
if approved "$TMP/e1"; then ok "E2E1b: post-fix-gate duyệt test sửa từ biên bản PM (không json / trailer / comment / pm_verdict)"
else bad "E2E1b: gate: rc=$RC, $(tailout)"; fi
echo '{"comments":[]}' > "$TMP/meta.json"
got="$(bash "$INS" --has-edited-tests "$TMP/meta.json" "$(git -C "$TMP/e1" rev-parse HEAD)" --top "$TMP/e1" --base main 2>/dev/null)"
[ "$got" = pm ] && ok "E2E1c: merge gate --has-edited-tests -> pm (giữ khoá)" || bad "E2E1c: has-edited-tests: '$got'"

# E2E2. sửa test thêm lần nữa sau audit (commit mới) -> nội dung khác cây đã audit -> không duyệt
printf '#!/bin/sh\ngrep -q "ok()" src/Core.kt\n' > "$TMP/e1/tests/t.sh"; git -C "$TMP/e1" commit -qam "nới test sau audit"
run_gate "$TMP/e1" CLAUDECODE=1
if refused; then ok "E2E2: sửa test sau audit -> không duyệt"; else bad "E2E2: rc=$RC, $(tailout)"; fi

# E2E3. grok REVISE -> PM không ghi biên bản -> không duyệt
mk "$TMP/e3"; pm "$TMP/e3" "$TMP/grev" ""
run_gate "$TMP/e3" CLAUDECODE=1
if refused; then ok "E2E3: grok REVISE -> không duyệt"; else bad "E2E3: rc=$RC, $(tailout)"; fi

# E2E4. pm_dispatch có message (chữ tác giả trong prompt) -> PM không tự ghi -> không duyệt
mk "$TMP/e4"; pm "$TMP/e4" "$TMP/gpass" "chỉ xem src, test ổn"
run_gate "$TMP/e4" CLAUDECODE=1
if refused; then ok "E2E4: message của người gọi -> không tự duyệt"; else bad "E2E4: rc=$RC, $(tailout)"; fi

# E2E5. biên bản hợp lệ nhưng phiên chạy gate là grok -> tự duyệt, không duyệt
mk "$TMP/e5"; pm "$TMP/e5" "$TMP/gpass" ""
run_gate "$TMP/e5" GROK_SESSION_ID=g-1
if refused; then ok "E2E5: phiên chạy gate là grok -> không duyệt"; else bad "E2E5: rc=$RC, $(tailout)"; fi

# E2E6. người gọi PM là grok -> PM từ chối chạy audit -> không biên bản -> không duyệt
mk "$TMP/e6"; pm "$TMP/e6" "$TMP/gpass" "" GROK_SESSION_ID=g-2
if printf '%s' "$OUT" | grep -q "PM-ERROR.*tu duyet"; then ok "E2E6a: PM từ chối khi người gọi là grok"; else bad "E2E6a: PM: $(tailout)"; fi
run_gate "$TMP/e6" CLAUDECODE=1
if refused; then ok "E2E6b: không biên bản -> không duyệt"; else bad "E2E6b: rc=$RC, $(tailout)"; fi

# E2E7. sau audit, main tiến KHÔNG chạm test; scratch như merge gate (tách rời ở head PR, gộp main) -> vẫn duyệt
mk "$TMP/e7"; pm "$TMP/e7" "$TMP/gpass" ""
git -C "$TMP/e7" checkout -q main && echo 'fun other()=7' > "$TMP/e7/src/Other.kt" && git -C "$TMP/e7" add -A && git -C "$TMP/e7" commit -qm "main tiến"
git -C "$TMP/e7" checkout -q --detach feat && git -C "$TMP/e7" merge -q --no-ff --no-edit main
run_gate "$TMP/e7" CLAUDECODE=1
if approved "$TMP/e7"; then ok "E2E7: base dời không chạm test, scratch merge gate -> vẫn duyệt"; else bad "E2E7: rc=$RC, $(tailout)"; fi

# E2E8. sau audit, main sửa CHÍNH test đó; scratch gộp main giữ test của PR -> không duyệt (main đổi file kể từ audit)
mk "$TMP/e8"; pm "$TMP/e8" "$TMP/gpass" ""
X8="$(git -C "$TMP/e8" rev-parse HEAD)"
git -C "$TMP/e8" checkout -q main && printf '#!/bin/sh\ngrep -q "ok" src/Core.kt\ngrep -q "fun ok" src/Core.kt\n' > "$TMP/e8/tests/t.sh" \
  && git -C "$TMP/e8" commit -qam "main sửa test"
git -C "$TMP/e8" checkout -q --detach feat && git -C "$TMP/e8" merge -q --no-ff --no-commit main >/dev/null 2>&1
git -C "$TMP/e8" checkout "$X8" -- tests/t.sh && git -C "$TMP/e8" commit -qm "gộp main, giữ test của PR"
run_gate "$TMP/e8" CLAUDECODE=1
if refused; then ok "E2E8: main sửa chính test sau audit -> không duyệt"; else bad "E2E8: rc=$RC, $(tailout)"; fi

# E2E9. grok PASS rồi chạy lại cùng head trả REVISE -> lượt cuối fail -> không duyệt
mk "$TMP/e9"; pm "$TMP/e9" "$TMP/gpass" ""
OUT="$(cd "$TMP/e9" && ANTIGRAVITY_PM_GROK="$TMP/grev/grok" node --input-type=module -e '
const [tools, project] = process.argv.slice(1);
const { TOOLS_BY_NAME } = await import(tools);
const fs = await import("node:fs");
const path = await import("node:path");
const id = fs.readdirSync(path.join(process.env.ANTIGRAVITY_PM_STATE_HOME, "projects")).flatMap((d) =>
  fs.readdirSync(path.join(process.env.ANTIGRAVITY_PM_STATE_HOME, "projects", d, "tasks")))[0];
console.log(await TOOLS_BY_NAME.get("pm_dispatch").handler({ project, taskId: id, kind: "audit", agent: "grok" }));
' "$TOOLS" "$TMP/e9" 2>&1)"
run_gate "$TMP/e9" CLAUDECODE=1
if refused; then ok "E2E9: PASS rồi REVISE cùng head -> không duyệt"; else bad "E2E9: rc=$RC, $(tailout)"; fi

[ "$FAILS" -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }
