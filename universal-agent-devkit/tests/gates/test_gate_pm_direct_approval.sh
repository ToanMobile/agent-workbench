#!/usr/bin/env bash
# Nguồn duyệt thứ 3 cho test cũ bị sửa (04/11, không bước người): post-fix-gate tra THẲNG biên bản antigravity-pm (push_gate.audited_heads)
# — không cần mục approved_tests.json, trailer `Test-approved-by:` hay comment PR. Cùng luật audit_covers (head trên chuỗi first-parent
# của PR, không trên trunk, audit mới nhất, blob khớp, main không đổi file) và audit_reviewer(legacy=False) khác danh tính phiên.
#  P1: biên bản grok (PM tự chạy, lượt audit gần nhất grok) tại head PR, không json/trailer -> nhận (code cũ: exit 2). P2: scratch merge gate
#      (PR + main) -> nhận. P3: thông điệp CHƯA XÁC MINH chỉ cách PM audit, không bảo ghi json.
#  N1-N8: phiên là grok; audit mới hơn khác blob; pm home lạ không phải fixture; reviewer pm không dispatch (biên bản cũ); auditedHead đã
#      nằm trên main; mục json tự khai author grok-build; head chỉ còn trong auditHistory; hai biên bản cùng task id (reviewer khác biên bản).
#  N9-N11: lượt grok không ghi phạm vi; test ngoài danh sách edited; auditBase muộn hơn merge-base. N12 PASS rồi fail cùng head.
#  N13 auditBase muộn hơn merge-base dù edited có test. N14/N14c REVISE ở task khác / PASS mới hơn. N15/N15c REVISE ở head sau
#  (cùng / khác blob). N16 PASS do message dẫn không đè REVISE. N17 REVISE thiếu at coi là mới nhất.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_AUTO_APPROVE_TESTS DEVKIT_TRANSCRIPTS_DIR TARGET_DIR DEVKIT_AGENT_ID CLAUDE_CODE_SESSION_ID DEVKIT_SESSION_ID CLAUDE_SESSION_ID
unset WORKTREE_TRUNK_MODE DEVKIT_GATE_MERGE_CHECK CI
unset CLAUDECODE GROK_SESSION_ID GROK_WORKSPACE_ROOT GROK_HOOK_EVENT
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.claude/projects"
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm"   # biên bản giả dưới $TMP, không bao giờ ~/.antigravity-pm thật
export DEVKIT_PM_HOME_TEST=1
export GIT_CONFIG_GLOBAL=/dev/null
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
has() { printf '%s' "$OUT" | grep -qF -- "$1"; }
pm_grok() {   # pm_grok <task-id> <project> <auditedHead> [dir] [scope]: audit pass do PM tự chạy grok (reviewer grok, lượt audit gần nhất
  # grok) kèm phạm vi đã đưa grok xem như tools.js ghi: auditBase = merge-base(main, head), edited = file đã có bị sửa/xoá. scope: full
  # (mặc định) | none (lượt không ghi phạm vi, như /giao hay PM cũ) | other (edited không có tests/t.sh) | late (auditBase = head^)
  local d="${4:-p-$1}" scope="${5:-full}"
  mkdir -p "$TMP/pm/projects/$d/tasks/$1"
  python3 - "$TMP/pm/projects/$d/tasks/$1/task.json" "$1" "$(cd "$2" && pwd -P)" "$3" "$scope" <<'PY2'
import json, subprocess, sys
dest, tid, proj, head, scope = sys.argv[1:6]
g = lambda *a: subprocess.run(["git", "-C", proj, *a], capture_output=True, text=True).stdout.strip()
disp = {"kind": "audit", "agent": "grok", "at": "2026-11-04T00:00:00Z", "auditedHead": head, "verdict": "pass"}
if scope != "none":
    mb = g("merge-base", "main", head)
    base = g("rev-parse", head + "^") if scope in ("late", "latefull") else mb
    # latefull: auditBase muộn (head^) nhưng edited vẫn liệt kê đủ file như phạm vi merge-base — chỉ luật "auditBase là tổ tiên
    # merge-base" chặn được (OCR vòng cuối M5)
    ns = g("diff", "--name-status", "--no-renames", mb if scope == "latefull" else base, head).splitlines()
    edited = [l.split("\t", 1)[1] for l in ns if l[:1] in "MDT"]
    disp.update(auditBase=base, edited=[e for e in edited if e != "tests/t.sh"] if scope == "other" else edited)
disps = [disp]
if scope == "refail":                               # lượt grok sau cùng head trả REVISE: dispatch fail, verdicts.audit vẫn pass cũ
    disps.append(dict(disp, at="2026-11-04T01:00:00Z", verdict="fail"))
json.dump({"id": tid, "project": proj, "dispatches": disps, "verdicts": {
    "audit": {"verdict": "pass", "round": 1, "reviewer": "grok", "notes": "ok", "auditedHead": head},
    "auditHistory": [{"auditedHead": head, "reviewer": "grok", "at": "2026-11-04T00:00:01Z"}]}}, open(dest, "w"))
PY2
}
V0='#!/bin/sh\ngrep -q "ok" src/Core.kt\ngrep -q "fun" src/Core.kt\n'
V1='#!/bin/sh\ngrep -q "ok()" src/Core.kt\ngrep -q "fun" src/Core.kt\n'
V2='#!/bin/sh\ngrep -q "ok()" src/Core.kt\ngrep -q "fun" src/Core.kt\ngrep -q "=" src/Core.kt\n'
mk() {   # mk <dir>: main M0 (test V0), nhánh feat
  mkdir -p "$1/src" "$1/tests" && cd "$1" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  printf '.claude/audit-gate/\n' > .gitignore
  mkdir -p .claude && echo '{"DEVKIT_IMPACT_TEST_ENABLED":"1","DEVKIT_REGRESSION_TEST_ENABLED":"1"}' > .claude/config.json
  cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh tests/t.sh"}]}]}
JSON
  echo 'fun ok()=1' > src/Core.kt; echo 'fun other()=1' > src/Other.kt; printf "$V0" > tests/t.sh
  git add -A && git commit -qm "M0"
  git checkout -q -b feat
}
pr_commit() { printf "$1" > tests/t.sh; echo "fun ok()=$RANDOM" > src/Core.kt; git commit -qam "$2"; git rev-parse HEAD; }
main_moves() { git checkout -q main && echo "fun other()=$RANDOM" > src/Other.kt && git commit -qam "main tiến" && git checkout -q "${1:-feat}"; }
run_gate() { local d="$1"; shift; OUT="$(cd "$d" && env "$@" CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --matrix "$d/matrix.json" --lang vi --run-tests --diff main 2>&1)"; RC=$?; }
accepted() { [ "$RC" = 0 ] && has "duyệt chéo bởi grok (thay Antigravity) (task $1)"; }
refused()  { [ "$RC" = 2 ] && ! has "duyệt chéo bởi"; }
tailout()  { printf '%s' "$OUT" | grep -E "Duyệt test|duyệt chéo|Test đã có|CHƯA XÁC MINH|exit" | tail -4 | cut -c1-240; }

# P1. biên bản PM grok tại head PR; KHÔNG approved_tests.json, KHÔNG trailer, KHÔNG comment -> nhận
mk "$TMP/p1"; X="$(pr_commit "$V1" "PR sửa test")"; pm_grok T1001-p1 "$TMP/p1" "$X"
run_gate "$TMP/p1"
if accepted T1001-p1 && [ ! -e "$TMP/p1/.claude/audit-gate/approved_tests.json" ]; then ok "P1: biên bản PM grok tại head PR, không json/trailer -> nhận"
else bad "P1: tra thẳng biên bản PM: rc=$RC, $(tailout)"; fi

# P2. scratch như merge gate: tách rời ở đầu PR, gộp main mới (không chạm test) -> nhận
mk "$TMP/p2"; X="$(pr_commit "$V1" "PR sửa test")"; pm_grok T1002-p2 "$TMP/p2" "$X"
main_moves; git checkout -q --detach feat && git merge -q --no-ff --no-edit main
run_gate "$TMP/p2"
if accepted T1002-p2; then ok "P2: scratch merge gate (PR + main) -> nhận"
else bad "P2: scratch merge gate: rc=$RC, $(tailout)"; fi

# P3. chưa có audit: CHƯA XÁC MINH chỉ cách PM audit grok/Antigravity trên head PR rồi chạy lại; không bảo agent ghi json
mk "$TMP/p3"; pr_commit "$V1" "PR sửa test" >/dev/null
run_gate "$TMP/p3"
if refused && has "pm_dispatch kind=audit agent=grok" && ! has "approved_tests.json\` (khoá"; then ok "P3: thông điệp chỉ luồng PM audit, không bảo ghi json"
else bad "P3: thông điệp CHƯA XÁC MINH: rc=$RC, $(tailout)"; fi

# P3b. 07/11: gợi ý đặt Antigravity (mặc định) lên trước grok; grok chỉ khi Antigravity bị giới hạn
if refused && has 'pm_dispatch kind=audit` (mặc định Antigravity' && has 'pm_verdict kind=audit verdict=pass auditedHead=' && has 'agent-kit approve-tests <task-id>' \
   && has 'chỉ khi Antigravity bị giới hạn mới dùng `pm_dispatch kind=audit agent=grok`'; then ok "P3b: thông điệp gợi ý Antigravity trước, grok khi bị giới hạn"
else bad "P3b: thông điệp vẫn gợi ý grok trước: rc=$RC, $(tailout)"; fi

# N1. phiên là grok (GROK_SESSION_ID) -> không duyệt (tự duyệt); DEVKIT_AGENT_ID=grok-build cũng vậy
mk "$TMP/n1"; X="$(pr_commit "$V1" "PR sửa test")"; pm_grok T1011-n1 "$TMP/n1" "$X"
run_gate "$TMP/n1" GROK_SESSION_ID=g-1
if refused; then ok "N1: phiên grok, reviewer PM grok -> không duyệt"; else bad "N1: phiên grok: rc=$RC, $(tailout)"; fi
run_gate "$TMP/n1" DEVKIT_AGENT_ID=grok-build
if refused; then ok "N1b: DEVKIT_AGENT_ID=grok-build -> không duyệt"; else bad "N1b: grok-build: rc=$RC, $(tailout)"; fi

# N2. audit mới hơn (V2, T1022) có blob khác; test chép về V1 đã audit ở T1021 -> không duyệt (chỉ audit mới nhất)
mk "$TMP/n2"; X1="$(pr_commit "$V1" "V1")"; pm_grok T1021-n2 "$TMP/n2" "$X1"
X2="$(pr_commit "$V2" "V2 làm mạnh")"; pm_grok T1022-n2 "$TMP/n2" "$X2"
pr_commit "$V1" "chép về V1" >/dev/null
run_gate "$TMP/n2"
if refused; then ok "N2: audit mới hơn khác blob -> không duyệt"; else bad "N2: replay audit cũ: rc=$RC, $(tailout)"; fi
pr_commit "$V2" "về lại V2" >/dev/null; run_gate "$TMP/n2"
if accepted T1022-n2; then ok "N2c: đối chứng nội dung = audit mới nhất -> nhận"; else bad "N2c: đối chứng: rc=$RC, $(tailout)"; fi

# N3. pm home lạ, không phải fixture (DEVKIT_PM_HOME_TEST tắt) -> không duyệt
mk "$TMP/n3"; X="$(pr_commit "$V1" "PR sửa test")"; pm_grok T1031-n3 "$TMP/n3" "$X"
run_gate "$TMP/n3" DEVKIT_PM_HOME_TEST=0
if refused; then ok "N3: pm home lạ không phải fixture -> không duyệt"; else bad "N3: pm home lạ: rc=$RC, $(tailout)"; fi

# N4. biên bản cũ: reviewer pm, không lượt audit nào trong dispatches -> không duyệt (legacy=False: thiếu bằng chứng reviewer)
mk "$TMP/n4"; X="$(pr_commit "$V1" "PR sửa test")"
mkdir -p "$TMP/pm/projects/p-n4/tasks/T1041-n4"
printf '{"id":"T1041-n4","project":"%s","verdicts":{"audit":{"verdict":"pass","round":1,"reviewer":"pm","notes":"auditedHead: %s"}}}\n' \
  "$(pwd -P)" "$X" > "$TMP/pm/projects/p-n4/tasks/T1041-n4/task.json"
run_gate "$TMP/n4"
if refused; then ok "N4: reviewer pm, không dispatch -> không duyệt"; else bad "N4: biên bản cũ: rc=$RC, $(tailout)"; fi

# N5. auditedHead đã nằm trên main (nhánh phụ gộp vào main), PR mới chép test về bản đó -> không duyệt
mk "$TMP/n5"; git checkout -q -b side main; S="$(pr_commit "$V1" "side V1")"; pm_grok T1051-n5 "$TMP/n5" "$S"
git checkout -q main && git merge -q --no-ff --no-edit side && printf "$V2" > tests/t.sh && git commit -qam "main V2"
git checkout -q -B feat main; pr_commit "$V1" "chép V1 về" >/dev/null
run_gate "$TMP/n5"
if refused; then ok "N5: auditedHead trên main -> không duyệt"; else bad "N5: head trên main: rc=$RC, $(tailout)"; fi

# N6. mục json tự khai author grok-build (= reviewer PM grok) bị từ chối là tự duyệt: đường tra thẳng không được duyệt lại file đó
mk "$TMP/n6"; X="$(pr_commit "$V1" "PR sửa test")"; pm_grok T1061-n6 "$TMP/n6" "$X"
mkdir -p .claude/audit-gate
python3 - "$TMP/n6" <<'PY'
import hashlib, json, os, sys
root = sys.argv[1]
sha = hashlib.sha256(open(os.path.join(root, "tests/t.sh"), "rb").read()).hexdigest()
json.dump({"approvals": [{"path": "tests/t.sh", "sha256": sha, "reviewer": "grok", "author": "grok-build", "task_id": "T1061-n6",
                          "reason": "fixture"}]}, open(os.path.join(root, ".claude/audit-gate/approved_tests.json"), "w"))
PY
run_gate "$TMP/n6"
if refused && has "tự duyệt"; then ok "N6: mục json author grok-build bị từ chối -> tra thẳng không duyệt lại"
else bad "N6: author tự khai: rc=$RC, $(tailout)"; fi

# N7. verdicts.audit bị ghi đè thành fail, head pass chỉ còn trong auditHistory -> không duyệt (chỉ head của verdicts.audit hiện tại)
mk "$TMP/n7"; X="$(pr_commit "$V1" "PR sửa test")"
mkdir -p "$TMP/pm/projects/p-n7/tasks/T1071-n7"
printf '{"id":"T1071-n7","project":"%s","dispatches":[{"kind":"audit","agent":"grok","at":"2026-11-04T00:00:00Z"}],"verdicts":{"audit":{"verdict":"fail","round":2,"reviewer":"grok","notes":"fail"},"auditHistory":[{"auditedHead":"%s","reviewer":"grok","at":"2026-11-04T00:00:01Z"}]}}\n' \
  "$(pwd -P)" "$X" > "$TMP/pm/projects/p-n7/tasks/T1071-n7/task.json"
run_gate "$TMP/n7"
if refused; then ok "N7: head chỉ còn trong auditHistory (verdict fail) -> không duyệt"; else bad "N7: history head: rc=$RC, $(tailout)"; fi

# N8. hai biên bản cùng task id: A (sắp trước) head PR, reviewer grok nhưng lượt audit gần nhất antigravity -> reviewer không xác định;
#     B reviewer grok hợp lệ nhưng head khác (M0 trên main). Không mượn reviewer của B cho head của A -> không duyệt
mk "$TMP/n8"; M0="$(git rev-parse main)"; X="$(pr_commit "$V1" "PR sửa test")"; P8="$(pwd -P)"
mkdir -p "$TMP/pm/projects/p-a-n8/tasks/T1081" "$TMP/pm/projects/p-b-n8/tasks/T1081"
printf '{"id":"T1081","project":"%s","dispatches":[{"kind":"audit","agent":"grok","at":"2026-11-04T01:00:00Z"},{"kind":"audit","agent":"antigravity","at":"2026-11-04T02:00:00Z"}],"verdicts":{"audit":{"verdict":"pass","round":1,"reviewer":"grok","notes":"ok","auditedHead":"%s"}}}\n' \
  "$P8" "$X" > "$TMP/pm/projects/p-a-n8/tasks/T1081/task.json"
pm_grok T1081 "$TMP/n8" "$M0" p-b-n8
run_gate "$TMP/n8"
if refused; then ok "N8: reviewer và head phải cùng một biên bản -> không duyệt"; else bad "N8: mượn reviewer: rc=$RC, $(tailout)"; fi

# N9-N11 (review 04/11, audit phạm vi hẹp như /giao): lượt grok không ghi phạm vi; tests/t.sh ngoài danh sách edited; auditBase muộn
#     hơn merge-base (phạm vi không phủ commit PR đã sửa test) -> không duyệt. Đối chứng: P1 (phạm vi đầy đủ) nhận.
mk "$TMP/n9"; X="$(pr_commit "$V1" "PR sửa test")"; pm_grok T1091-n9 "$TMP/n9" "$X" p-n9 none
run_gate "$TMP/n9"
if refused; then ok "N9: lượt grok không ghi phạm vi -> không duyệt"; else bad "N9: thiếu phạm vi: rc=$RC, $(tailout)"; fi
mk "$TMP/n10"; X="$(pr_commit "$V1" "PR sửa test")"; pm_grok T1101-n10 "$TMP/n10" "$X" p-n10 other
run_gate "$TMP/n10"
if refused; then ok "N10: test ngoài danh sách edited -> không duyệt"; else bad "N10: ngoài edited: rc=$RC, $(tailout)"; fi
mk "$TMP/n11"; pr_commit "$V1" "PR sửa test" >/dev/null; echo 'fun other()=11' > src/Other.kt && git commit -qam "PR tiếp"
X="$(git rev-parse HEAD)"; pm_grok T1111-n11 "$TMP/n11" "$X" p-n11 late
run_gate "$TMP/n11"
if refused; then ok "N11: auditBase muộn hơn merge-base (không phủ commit sửa test) -> không duyệt"; else bad "N11: phạm vi hẹp: rc=$RC, $(tailout)"; fi

# N12 (OCR vòng 3): grok PASS ở head rồi chạy lại cùng head trả REVISE (lượt cuối fail, verdicts.audit còn pass cũ) -> không duyệt
mk "$TMP/n12"; X="$(pr_commit "$V1" "PR sửa test")"; pm_grok T1121-n12 "$TMP/n12" "$X" p-n12 refail
run_gate "$TMP/n12"
if refused; then ok "N12: lượt grok cuối cùng head là fail -> không duyệt"; else bad "N12: pass rồi fail: rc=$RC, $(tailout)"; fi

# N13 (OCR vòng cuối M5): auditBase muộn hơn merge-base, edited vẫn có tests/t.sh -> không duyệt (luật tổ tiên merge-base)
mk "$TMP/n13"; pr_commit "$V1" "PR sửa test" >/dev/null; echo 'fun other()=13' > src/Other.kt && git commit -qam "PR tiếp"
X="$(git rev-parse HEAD)"; pm_grok T1131-n13 "$TMP/n13" "$X" p-n13 latefull
run_gate "$TMP/n13"
if refused; then ok "N13: auditBase muộn hơn merge-base dù edited có test -> không duyệt"; else bad "N13: phạm vi muộn: rc=$RC, $(tailout)"; fi

# N14 (OCR vòng 6): T1 grok PASS ở head; task KHÁC T2 chạy grok cùng head trả REVISE (lượt fail, không verdict) -> không duyệt.
#     N14c: task thứ ba T3 sau đó grok PASS cùng head -> lượt mới nhất pass -> nhận.
grok_fail() {   # grok_fail <task-id> <project> <head> <at> <dir>: task chỉ có một lượt grok fail (PM không ghi verdict khi fail)
  mkdir -p "$TMP/pm/projects/$5/tasks/$1"
  printf '{"id":"%s","project":"%s","dispatches":[{"kind":"audit","agent":"grok","at":"%s","auditedHead":"%s","verdict":"fail"}]}\n' \
    "$1" "$(cd "$2" && pwd -P)" "$4" "$3" > "$TMP/pm/projects/$5/tasks/$1/task.json"
}
mk "$TMP/n14"; X="$(pr_commit "$V1" "PR sửa test")"; pm_grok T1141-n14 "$TMP/n14" "$X" p-n14a
grok_fail T1142-n14 "$TMP/n14" "$X" "2026-11-04T05:00:00Z" p-n14b
run_gate "$TMP/n14"
if refused; then ok "N14: REVISE mới hơn ở task khác, cùng head -> không duyệt"; else bad "N14: REVISE task khác: rc=$RC, $(tailout)"; fi
python3 - "$TMP/pm/projects/p-n14a/tasks/T1141-n14/task.json" "$TMP/pm/projects/p-n14c/tasks/T1143-n14/task.json" <<'PY'
import json, os, sys
src, dest = sys.argv[1:3]
t = json.load(open(src)); t["id"] = "T1143-n14"
for d in t["dispatches"]:
    d["at"] = "2026-11-04T06:00:00Z"
os.makedirs(os.path.dirname(dest), exist_ok=True); json.dump(t, open(dest, "w"))
PY
run_gate "$TMP/n14"
if [ "$RC" = 0 ] && has "duyệt chéo bởi grok (thay Antigravity)"; then ok "N14c: PASS mới hơn REVISE (task thứ ba) -> nhận"; else bad "N14c: PASS sau REVISE: rc=$RC, $(tailout)"; fi

# N15 (OCR vòng 6b): PASS ở X; REVISE ở head SAU (X2, cùng blob test) ở task khác -> không duyệt.
#     N15c: REVISE ở X2 nhưng test ở X2 khác blob (V2), rồi test về V1 ở X3 -> REVISE không xét V1 -> nhận (qua audit X).
mk "$TMP/n15"; X="$(pr_commit "$V1" "PR sửa test")"; pm_grok T1151-n15 "$TMP/n15" "$X" p-n15a
echo 'fun other()=15' > src/Other.kt && git commit -qam "PR tiếp"; X2="$(git rev-parse HEAD)"
grok_fail T1152-n15 "$TMP/n15" "$X2" "2026-11-04T05:00:00Z" p-n15b
run_gate "$TMP/n15"
if refused; then ok "N15: REVISE ở head sau, cùng blob test -> không duyệt"; else bad "N15: REVISE head sau: rc=$RC, $(tailout)"; fi
mk "$TMP/n15c"; X="$(pr_commit "$V1" "PR sửa test")"; pm_grok T1153-n15c "$TMP/n15c" "$X" p-n15ca
X2="$(pr_commit "$V2" "V2")"; grok_fail T1154-n15c "$TMP/n15c" "$X2" "2026-11-04T05:00:00Z" p-n15cb
printf "$V1" > tests/t.sh; git commit -qam "về V1"
run_gate "$TMP/n15c"
if [ "$RC" = 0 ] && has "duyệt chéo bởi grok (thay Antigravity) (task T1153-n15c)"; then ok "N15c: REVISE xét blob khác -> không chặn V1 đã PASS"
else bad "N15c: REVISE blob khác: rc=$RC, $(tailout)"; fi

# N16 (OCR vòng 6b, P1): PASS có phạm vi (A), REVISE (B), rồi lượt grok có `message` PASS (C, không ghi phạm vi, mới nhất) -> không duyệt
mk "$TMP/n16"; X="$(pr_commit "$V1" "PR sửa test")"; pm_grok T1161-n16 "$TMP/n16" "$X" p-n16a
grok_fail T1162-n16 "$TMP/n16" "$X" "2026-11-04T05:00:00Z" p-n16b
mkdir -p "$TMP/pm/projects/p-n16c/tasks/T1163-n16"
printf '{"id":"T1163-n16","project":"%s","dispatches":[{"kind":"audit","agent":"grok","at":"2026-11-04T06:00:00Z","auditedHead":"%s","verdict":"pass"}]}\n' \
  "$(pwd -P)" "$X" > "$TMP/pm/projects/p-n16c/tasks/T1163-n16/task.json"
run_gate "$TMP/n16"
if refused; then ok "N16: PASS do message dẫn (không phạm vi) không đè REVISE -> không duyệt"; else bad "N16: message PASS: rc=$RC, $(tailout)"; fi

# N17 (OCR vòng 6b): REVISE cùng `at` với PASS -> fail thắng; REVISE thiếu `at` -> coi là mới nhất -> không duyệt
mk "$TMP/n17"; X="$(pr_commit "$V1" "PR sửa test")"; pm_grok T1171-n17 "$TMP/n17" "$X" p-n17a
grok_fail T1172-n17 "$TMP/n17" "$X" "" p-n17b
run_gate "$TMP/n17"
if refused; then ok "N17: REVISE thiếu at -> coi là mới nhất -> không duyệt"; else bad "N17: fail thiếu at: rc=$RC, $(tailout)"; fi

# N17b (review vòng 6): PASS và REVISE trùng `at` -> fail thắng -> không duyệt
mk "$TMP/n17b"; X="$(pr_commit "$V1" "PR sửa test")"; pm_grok T1173-n17b "$TMP/n17b" "$X" p-n17ba
grok_fail T1174-n17b "$TMP/n17b" "$X" "2026-11-04T00:00:00Z" p-n17bb
run_gate "$TMP/n17b"
if refused; then ok "N17b: PASS và REVISE trùng at -> fail thắng"; else bad "N17b: trùng at: rc=$RC, $(tailout)"; fi

# N18 (review vòng 6): REVISE phạm vi đầy đủ (B), rồi PASS mới hơn nhưng phạm vi muộn (C: auditBase = head^, edited vẫn có test vì test
#     đổi ở commit cuối) -> PASS đó không đè REVISE -> không duyệt (A là PASS phạm vi đầy đủ cũ hơn REVISE)
mk "$TMP/n18"; echo 'fun other()=18' > src/Other.kt && git commit -qam "PR code trước"; X="$(pr_commit "$V1" "PR sửa test ở commit cuối")"
pm_grok T1181-n18 "$TMP/n18" "$X" p-n18a
grok_fail T1182-n18 "$TMP/n18" "$X" "2026-11-04T05:00:00Z" p-n18b
pm_grok T1183-n18 "$TMP/n18" "$X" p-n18c late
python3 - "$TMP/pm/projects/p-n18c/tasks/T1183-n18/task.json" <<'PY'
import json, sys
p = sys.argv[1]; t = json.load(open(p))
t["dispatches"][0]["at"] = "2026-11-04T06:00:00Z"
json.dump(t, open(p, "w"))
PY
run_gate "$TMP/n18"
if refused; then ok "N18: PASS phạm vi muộn không đè REVISE phạm vi đầy đủ"; else bad "N18: PASS phạm vi muộn: rc=$RC, $(tailout)"; fi

# N19 (OCR vòng 8, P2): REVISE chạy từ worktree ANH EM (project ngoài checkout chính, kiểu agent-kit worktree add ../<repo>-x) cùng head
#     -> vẫn chặn: lượt fail có auditedHead trên chuỗi PR là của PR này dù project ở đâu
mk "$TMP/n19"; X="$(pr_commit "$V1" "PR sửa test")"; pm_grok T1191-n19 "$TMP/n19" "$X" p-n19a
mkdir -p "$TMP/n19-sibling" "$TMP/pm/projects/p-n19b/tasks/T1192-n19"
printf '{"id":"T1192-n19","project":"%s","dispatches":[{"kind":"audit","agent":"grok","at":"2026-11-04T05:00:00Z","auditedHead":"%s","verdict":"fail"}]}\n' \
  "$(cd "$TMP/n19-sibling" && pwd -P)" "$X" > "$TMP/pm/projects/p-n19b/tasks/T1192-n19/task.json"
run_gate "$TMP/n19"
if refused; then ok "N19: REVISE từ worktree anh em cùng head -> không duyệt"; else bad "N19: REVISE worktree anh em: rc=$RC, $(tailout)"; fi

[ "$FAILS" -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }
