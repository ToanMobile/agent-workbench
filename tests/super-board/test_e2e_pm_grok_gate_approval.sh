#!/usr/bin/env bash
# 04/11 đầu-cuối (không bước người); 13/11 chủ repo bỏ Grok: code PM THẬT (mcp-servers/antigravity-pm-mcp/src/tools.js, gọi thẳng handler
# như server MCP) tạo task, giao audit Antigravity (PM ghi phạm vi PR vào lượt giao) và pm_verdict ghi kết luận vào lượt đó, rồi
# post-fix-gate.py THẬT đọc chính biên bản đó và duyệt test cũ bị sửa — không approved_tests.json, không trailer, không comment. Bắt lệch
# khuôn dữ liệu giữa bên ghi (JS: dispatch auditedHead/auditBase/edited/verdict, verdicts.audit reviewer) và bên đọc (Python:
# push_gate.audited_head / audit_reviewer / audit_scope / scoped_audit_runs, post-fix-gate audit_covers).
# Chỉ agy là giả (ANTIGRAVITY_PM_AGY), báo cáo audit-agent.json do test ghi thay Antigravity, pm home là fixture dưới $TMP.
#  E2E1 Antigravity PASS -> gate exit 0 "duyệt chéo bởi antigravity"; merge gate --has-edited-tests -> pm.
#  E2E2 sửa test lần nữa sau audit -> gate exit 2 (blob khác cây đã audit).
#  E2E3 REVISE -> pm_verdict fail -> gate exit 2.   E2E4 pm_dispatch có message -> không ghi phạm vi -> gate exit 2.
#  E2E5 phiên chạy gate là antigravity -> exit 2 (tự duyệt).   E2E6 pm_dispatch agent=grok -> PM từ chối, gate exit 2.
#  E2E7 main tiến không chạm test, scratch merge gate -> vẫn duyệt.  E2E8 main sửa chính test sau audit -> exit 2.
#  E2E9 PASS rồi REVISE cùng head -> exit 2.  E2E10 PASS rồi REVISE ở task MỚI cùng head -> exit 2.
#  E2E11 test đổi tên rồi sửa -> duyệt theo đường mới.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
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

# agy giả: in init + result (stream-json), không làm gì khác; agentapi giả báo IDE đóng (#768: không chạy agentapi thật của máy).
mkdir -p "$TMP/agy"
printf '#!/usr/bin/env node\nconsole.log(JSON.stringify({event:"init",conversation_id:"e2e00000-1111-2222-3333-444444444444",init:{cwd:process.cwd()}}));\nconsole.log(JSON.stringify({event:"result",result:{conversation_id:"e2e00000-1111-2222-3333-444444444444",status:"SUCCESS"}}));\n' > "$TMP/agy/agy"
printf '#!/bin/sh\necho %s\nexit 1\n' "'{\"response\": {}, \"error\": \"rpc error: code = Unavailable\"}'" > "$TMP/agy/agentapi"
chmod +x "$TMP/agy/agy" "$TMP/agy/agentapi"
export ANTIGRAVITY_PM_AGY="$TMP/agy/agy" ANTIGRAVITY_PM_AGENTAPI="$TMP/agy/agentapi" ANTIGRAVITY_PM_AGY_SKIP_PERMISSIONS=1

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

# pm <project> <pass|revise> [message] [task-id|-] [agent]: (pm_task_create khi task-id rỗng/-) + pm_dispatch kind=audit bằng code PM thật,
# rồi báo cáo audit-agent.json của Antigravity cho HEAD và pm_verdict (pass kèm auditedHead / fail kèm finding); in kết quả
pm() {
  local dir="$1" v="$2" msg="${3:-}" tid="${4:--}" agent="${5:-}"
  OUT="$(cd "$dir" && node --input-type=module -e '
const [tools, project, v, msg, tid0, agent] = process.argv.slice(1);
const fs = await import("node:fs");
const { execFileSync } = await import("node:child_process");
const { TOOLS_BY_NAME } = await import(tools);
const call = (n, a) => TOOLS_BY_NAME.get(n).handler(a);
try {
  let id = tid0;
  if (id === "-") {
    const created = await call("pm_task_create", { project, title: "Audit PR e2e", brief: "Audit chéo test sửa của PR.",
      definitionOfDone: ["Test sửa không nới assertion"] });
    id = String(created).match(/T\d{4,}-[a-z0-9-]+/)[0];
  }
  console.log("TASK " + id);
  console.log(await call("pm_dispatch", { project, taskId: id, kind: "audit", ...(agent ? { agent } : {}), ...(msg ? { message: msg } : {}) }));
  const head = execFileSync("git", ["rev-parse", "HEAD"], { cwd: project, encoding: "utf8" }).trim();
  const verdict = v === "pass" ? "pass" : "fail";
  fs.writeFileSync(`${project}/.antigravity-pm/tasks/${id}/audit-agent.json`,
    JSON.stringify({ phase: "AUDIT", verdict, reviewer: "antigravity", auditedHead: head, findings: [] }));
  console.log(await call("pm_verdict", { project, taskId: id, kind: "audit", verdict,
    ...(verdict === "pass" ? { auditedHead: head, notes: "ok" } : { findings: ["tests/t.sh:2 nới assertion"] }) }));
} catch (e) { console.log("PM-ERROR " + e.message); }
' "$TOOLS" "$dir" "$v" "$msg" "$tid" "$agent" 2>&1)"
}
run_gate() { local d="$1"; shift; OUT="$(cd "$d" && env "$@" CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --matrix "$d/matrix.json" --lang vi --run-tests --diff main 2>&1)"; RC=$?; }
approved() { [ "$RC" = 0 ] && has "duyệt chéo bởi antigravity" && [ ! -e "$1/.claude/audit-gate/approved_tests.json" ] \
             && [ -z "$(git -C "$1" log --format=%B main..HEAD | grep -i 'Test-approved-by')" ]; }
refused()  { [ "$RC" = 2 ] && ! has "duyệt chéo bởi" && has "file test đã có bị sửa"; }   # exit 2 đúng vì test sửa chưa duyệt
tailout()  { printf '%s' "$OUT" | grep -E "duyệt chéo|Test đã có|CHƯA XÁC MINH|PM-ERROR|TASK|exit" | tail -4 | cut -c1-240; }

# E2E1. luồng thật: PM tạo task + giao audit Antigravity (ghi phạm vi) -> PASS -> pm_verdict -> gate duyệt; merge gate thấy duyệt từ biên bản PM
mk "$TMP/e1"; pm "$TMP/e1" pass ""
if printf '%s' "$OUT" | grep -q "Pham vi: .* ghi vao lan giao" && printf '%s' "$OUT" | grep -q "auditedHead = "; then ok "E2E1a: PM ghi phạm vi + auditedHead"; else bad "E2E1a: PM: $(tailout)"; fi
run_gate "$TMP/e1" CLAUDECODE=1
if approved "$TMP/e1"; then ok "E2E1b: post-fix-gate duyệt test sửa từ biên bản PM (không json / trailer / comment)"
else bad "E2E1b: gate: rc=$RC, $(tailout)"; fi
echo '{"comments":[]}' > "$TMP/meta.json"
got="$(bash "$INS" --has-edited-tests "$TMP/meta.json" "$(git -C "$TMP/e1" rev-parse HEAD)" --top "$TMP/e1" --base main 2>/dev/null)"
[ "$got" = pm ] && ok "E2E1c: merge gate --has-edited-tests -> pm (giữ khoá)" || bad "E2E1c: has-edited-tests: '$got'"

# E2E2. sửa test thêm lần nữa sau audit (commit mới) -> nội dung khác cây đã audit -> không duyệt
printf '#!/bin/sh\ngrep -q "ok()" src/Core.kt\n' > "$TMP/e1/tests/t.sh"; git -C "$TMP/e1" commit -qam "nới test sau audit"
run_gate "$TMP/e1" CLAUDECODE=1
if refused; then ok "E2E2: sửa test sau audit -> không duyệt"; else bad "E2E2: rc=$RC, $(tailout)"; fi

# E2E3. Antigravity REVISE -> pm_verdict fail -> không duyệt
mk "$TMP/e3"; pm "$TMP/e3" revise ""
run_gate "$TMP/e3" CLAUDECODE=1
if refused; then ok "E2E3: REVISE -> không duyệt"; else bad "E2E3: rc=$RC, $(tailout)"; fi

# E2E4. pm_dispatch có message (chữ tác giả trong prompt) -> PM không ghi phạm vi -> không duyệt
mk "$TMP/e4"; pm "$TMP/e4" pass "chỉ xem src, test ổn"
run_gate "$TMP/e4" CLAUDECODE=1
if refused; then ok "E2E4: message của người gọi -> không tự duyệt"; else bad "E2E4: rc=$RC, $(tailout)"; fi

# E2E5. biên bản hợp lệ nhưng phiên chạy gate là antigravity -> tự duyệt, không duyệt
mk "$TMP/e5"; pm "$TMP/e5" pass ""
run_gate "$TMP/e5" DEVKIT_AGENT_ID=antigravity
if refused; then ok "E2E5: phiên chạy gate là antigravity -> không duyệt"; else bad "E2E5: rc=$RC, $(tailout)"; fi

# E2E6. 13/11: pm_dispatch agent=grok -> PM từ chối (Grok đã gỡ) -> không biên bản -> không duyệt
mk "$TMP/e6"; pm "$TMP/e6" pass "" - grok
if printf '%s' "$OUT" | grep -q "PM-ERROR.*Grok da bi go"; then ok "E2E6a: PM từ chối agent=grok"; else bad "E2E6a: PM: $(tailout)"; fi
run_gate "$TMP/e6" CLAUDECODE=1
if refused; then ok "E2E6b: không biên bản -> không duyệt"; else bad "E2E6b: rc=$RC, $(tailout)"; fi

# E2E7. sau audit, main tiến KHÔNG chạm test; scratch như merge gate (tách rời ở head PR, gộp main) -> vẫn duyệt
mk "$TMP/e7"; pm "$TMP/e7" pass ""
git -C "$TMP/e7" checkout -q main && echo 'fun other()=7' > "$TMP/e7/src/Other.kt" && git -C "$TMP/e7" add -A && git -C "$TMP/e7" commit -qm "main tiến"
git -C "$TMP/e7" checkout -q --detach feat && git -C "$TMP/e7" merge -q --no-ff --no-edit main
run_gate "$TMP/e7" CLAUDECODE=1
if approved "$TMP/e7"; then ok "E2E7: base dời không chạm test, scratch merge gate -> vẫn duyệt"; else bad "E2E7: rc=$RC, $(tailout)"; fi

# E2E8. sau audit, main sửa CHÍNH test đó; scratch gộp main giữ test của PR -> không duyệt (main đổi file kể từ audit)
mk "$TMP/e8"; pm "$TMP/e8" pass ""
X8="$(git -C "$TMP/e8" rev-parse HEAD)"
git -C "$TMP/e8" checkout -q main && printf '#!/bin/sh\ngrep -q "ok" src/Core.kt\ngrep -q "fun ok" src/Core.kt\n' > "$TMP/e8/tests/t.sh" \
  && git -C "$TMP/e8" commit -qam "main sửa test"
git -C "$TMP/e8" checkout -q --detach feat && git -C "$TMP/e8" merge -q --no-ff --no-commit main >/dev/null 2>&1
git -C "$TMP/e8" checkout "$X8" -- tests/t.sh && git -C "$TMP/e8" commit -qm "gộp main, giữ test của PR"
run_gate "$TMP/e8" CLAUDECODE=1
if refused; then ok "E2E8: main sửa chính test sau audit -> không duyệt"; else bad "E2E8: rc=$RC, $(tailout)"; fi

# E2E9. PASS rồi giao audit lại cùng head trả REVISE (cùng task) -> lượt cuối fail -> không duyệt
mk "$TMP/e9"; pm "$TMP/e9" pass ""
T9="$(printf '%s' "$OUT" | sed -n 's/^TASK //p' | head -1)"   # đúng task vừa tạo cho e9 (id lặp giữa các project PM)
pm "$TMP/e9" revise "" "$T9"
printf '%s' "$OUT" | grep -q "audit = fail" || bad "E2E9: lượt REVISE không ghi trên task $T9: $(printf '%s' "$OUT" | tail -2)"
run_gate "$TMP/e9" CLAUDECODE=1
if refused; then ok "E2E9: PASS rồi REVISE cùng head -> không duyệt"; else bad "E2E9: rc=$RC, $(tailout)"; fi

# E2E10 (OCR vòng 6). task 1 PASS; task MỚI (pm_task_create như thông điệp gate hướng dẫn) REVISE cùng head -> không duyệt
mk "$TMP/e10"; pm "$TMP/e10" pass ""; pm "$TMP/e10" revise ""
run_gate "$TMP/e10" CLAUDECODE=1
if refused; then ok "E2E10: REVISE ở task mới sau PASS -> không duyệt"; else bad "E2E10: rc=$RC, $(tailout)"; fi

# E2E11 (OCR vòng 6). test bị ĐỔI TÊN rồi sửa một dòng: PM ghi cả đường cũ lẫn mới vào phạm vi, gate (báo theo đường mới) duyệt
mkdir -p "$TMP/e11/src" "$TMP/e11/tests" && cd "$TMP/e11" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
printf '.claude/audit-gate/\n.antigravity-pm/\n.antigravity-pm.json\n' > .gitignore
printf '{"projectName":"e2e","testCommand":"sh tests/t2.sh"}\n' > .antigravity-pm.json
mkdir -p .claude && echo '{"DEVKIT_IMPACT_TEST_ENABLED":"1","DEVKIT_REGRESSION_TEST_ENABLED":"1"}' > .claude/config.json
printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*"],"mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh tests/t2.sh"}]}]}\n' > matrix.json
echo 'fun ok()=1' > src/Core.kt
printf '#!/bin/sh\ngrep -q "ok" src/Core.kt\ngrep -q "fun" src/Core.kt\ngrep -q "1" src/Core.kt\ntrue\n' > tests/t.sh
git add -A && git commit -qm M0 && git checkout -q -b feat && git mv tests/t.sh tests/t2.sh
printf '#!/bin/sh\ngrep -q "ok()" src/Core.kt\ngrep -q "fun" src/Core.kt\ngrep -q "1" src/Core.kt\ntrue\n' > tests/t2.sh
git add -A && git commit -qm "đổi tên + sửa test"
pm "$TMP/e11" pass ""
run_gate "$TMP/e11" CLAUDECODE=1
if [ "$RC" = 0 ] && has "duyệt chéo bởi antigravity"; then ok "E2E11: test đổi tên rồi sửa -> duyệt theo đường mới"
else bad "E2E11: rc=$RC, $(tailout)"; fi

[ "$FAILS" -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }
