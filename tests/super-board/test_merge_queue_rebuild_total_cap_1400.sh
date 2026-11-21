#!/usr/bin/env bash
# Test hồi quy #1400 (gộp vào #1397): trần TỔNG số vòng rebuild mỗi thẻ (mọi nguyên nhân cộng lại)
# ở cả super-board-merge-queue.sh lẫn sweep_cap_progress() của super-board-run.sh.
#  A. Oracle (AC9): thẻ bị trả về Build 3 lần với 3 nguyên nhân khác nhau -> sau 3 vòng (lần 4 hoặc khi tổng đạt trần 3),
#     thẻ bị Blocked ở trần tổng, comment nêu số vòng và các nguyên nhân (trên main cũ: vẫn giao tiếp vòng 4, 5, ...).
#  B. Oracle (Plan-review v2 AC): thẻ đã chạm trần tổng KHÔNG bị sweep_cap_progress đưa về Ready (trên main cũ: bị đưa về Ready).
#  C. Dưới trần tổng (2 vòng với 2 nguyên nhân) + vòng rebase thuần (gate-exit-2) vẫn về Ready bình thường.
# Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-mq-totalcap-1400.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
F="$TMP/fake"; R="$TMP/repo"; Q="$TMP/qbin"
mkdir -p "$F/labeled" "$Q" "$TMP/path"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"; git -C "$R" add .gitignore; git -C "$R" commit -qm init
for f in super-board-merge-queue.sh super-board-github-read.py super-board-approved-head.jq super-board-audit-check.py super-board-root-cause-hash.py super-board-ac-check.py; do
  ln -s "$ROOT/.claude/bin/$f" "$Q/$f"
done
QUEUE="$Q/super-board-merge-queue.sh"
cat > "$Q/super-board-merge-train.sh" <<'SH'
#!/usr/bin/env bash
n=""; prev=""; for a in "$@"; do [ "$prev" = --prs ] && n="${a%%:*}"; prev="$a"; done
grep -E "^train-(result|detail|red): ${n}( |\$)" "$FAKE/train.out"; exit "$(cat "$FAKE/train.rc")"
SH
cat > "$Q/super-board-card.sh" <<'SH'
#!/usr/bin/env bash
while [ "${1#--}" != "$1" ]; do shift 2; done
echo "card $*" >> "$FAKE/writes"
SH
printf 'import os, sys\nopen(os.environ["FAKE"] + "/writes", "a").write("needs-you " + " ".join(sys.argv[1:]) + "\\n")\n' > "$Q/super-board-needs-you.py"
printf 'import os, sys\nopen(os.environ["FAKE"] + "/writes", "a").write("notify " + " ".join(sys.argv[1:]) + "\\n")\n' > "$Q/super-board-notify.py"
chmod +x "$Q"/*.sh

cat > "$TMP/path/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
F = os.environ['FAKE']; a = sys.argv[1:]
def opt(name):
    return a[a.index(name) + 1] if name in a else None
def num():
    return next(x for x in a[2:] if x.isdigit())
def w(line):
    open(F + '/writes', 'a').write(line + '\n')
def issue(k):
    return json.load(open(f'{F}/issue-{k}.json'))
if a[:2] == ['pr', 'list']:
    st = (opt('--state') or 'open').upper()
    prs = [p for p in json.load(open(F + '/prs.json')) if st == 'OPEN' and os.path.exists(f"{F}/labeled/{p['number']}")]
    print(json.dumps(prs))
elif a[:2] == ['pr', 'view'] and opt('--json') == 'comments':
    print(json.dumps({'comments': [{'authorAssociation': 'OWNER', 'body': 'approved-head:' + open(f'{F}/head-{num()}').read().strip()}]}))
elif a[0] == 'api' and '/timeline' in a[1]:
    print(json.dumps([[{'event': 'labeled', 'label': {'name': 'merge-queue'}, 'created_at': '2026-11-01T00:00:00Z'}]]))
elif a[:2] == ['issue', 'view']:
    print(json.dumps(issue(num())))
elif a[:2] == ['issue', 'close']:
    k = num(); d = issue(k); d['state'] = 'CLOSED'; json.dump(d, open(f'{F}/issue-{k}.json', 'w')); w(f'issue-close {k}')
elif a[:2] == ['pr', 'edit']:
    n = num(); w(f'pr-unlabel {n} ' + str(opt('--remove-label')))
    if os.path.exists(f'{F}/labeled/{n}'):
        os.remove(f'{F}/labeled/{n}')
elif a[:2] in (['pr', 'comment'], ['issue', 'comment']):
    n = num(); body = opt('--body'); w(f'{a[0]}-comment {n} ' + body.splitlines()[0])
    open(f'{F}/{a[0]}-comment-{n}.txt', 'a').write(body + '\n----\n')
    if a[0] == 'issue':
        d = issue(n); d.setdefault('comments', []).append({'body': body})
        json.dump(d, open(f'{F}/issue-{n}.json', 'w'))
elif a[:2] == ['issue', 'edit']:
    k = num(); d = issue(k); names = [l['name'] for l in d['labels']]
    i = 0
    while i < len(a):
        if a[i] == '--add-label' and a[i + 1] not in names:
            names.append(a[i + 1]); i += 2
        elif a[i] == '--remove-label':
            names = [y for y in names if y != a[i + 1]]; i += 2
        else:
            i += 1
    d['labels'] = [{'name': y} for y in names]; json.dump(d, open(f'{F}/issue-{k}.json', 'w'))
    w(f'issue-labels {k} ' + ','.join(sorted(names)))
else:
    sys.stderr.write('fake gh: unexpected ' + ' '.join(a) + '\n'); sys.exit(1)
PY
chmod +x "$TMP/path/gh"

export PATH="$TMP/path:$PATH" FAKE="$F" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_NOTIFY_SKIP=1
unset SB_MERGE_QUEUE SB_MERGE_CALLER SB_GITHUB_READ_STRICT SB_REBUILD_TOTAL_MAX
printf '{"base_branch":"main","repo":{"path":".","remote":"https://github.com/o/r"},"worker_backend":"claude-p","rebuild_cap":2,"verify_commands":["true"],"merge_queue":{"enabled":true}}\n' > "$TMP/cfg.json"
sha() { printf '%040d' "$1" | tr 0 a; }

# ── A: 3 vòng thất bại với 3 nguyên nhân khác nhau (cause1, cause2, cause3) vẫn chạy; lần 4 (cause4) chạm trần tổng -> Blocked
printf '[{"number":1,"headRefName":"issue-21-a","headRefOid":"%s","isDraft":false,"closingIssuesReferences":[]}]\n' "$(sha 1)" > "$F/prs.json"
sha 1 > "$F/head-1"
printf '{"number":21,"title":"c","body":"","state":"OPEN","labels":[],"comments":[]}' > "$F/issue-21.json"

run_red_round() {
  local detail="$1"
  : > "$F/labeled/1"; : > "$F/writes"
  printf 'train-result: 1 red\ntrain-detail: 1 %s\n' "$detail" > "$F/train.out"
  echo 11 > "$F/train.rc"
  ( cd "$R" && bash "$QUEUE" --config "$TMP/cfg.json" --wait ) >/dev/null 2>"$TMP/err"
}

run_red_round "tests/a.sh:10 AssertionError cause_one"
r1_ok=0; grep -q "card move 21 Ready" "$F/writes" && r1_ok=1
run_red_round "tests/b.sh:20 AssertionError cause_two"
r2_ok=0; grep -q "card move 21 Ready" "$F/writes" && r2_ok=1
run_red_round "tests/c.sh:30 AssertionError cause_three"
r3_ok=0; grep -q "card move 21 Ready" "$F/writes" && r3_ok=1
run_red_round "tests/d.sh:40 AssertionError cause_four"
if [ "$r1_ok" = 1 ] && [ "$r2_ok" = 1 ] && [ "$r3_ok" = 1 ] \
   && grep -q "card move 21 Blocked" "$F/writes" && ! grep -q "card move 21 Ready" "$F/writes" \
   && grep -qE "3" "$F/issue-comment-21.txt" \
   && grep -q "cause_one" "$F/issue-comment-21.txt" \
   && grep -q "cause_four" "$F/issue-comment-21.txt"; then
  ok "A (Oracle AC9): 3 different-cause rebuilds allowed, 4th Blocked at total cap citing round count & causes"
else
  fail "A (Oracle AC9): r1=$r1_ok r2=$r2_ok r3=$r3_ok writes=$(cat "$F/writes") comment=$(tail -n 15 "$F/issue-comment-21.txt" 2>/dev/null | tr '\n' '|')"
fi

# ── A2: Vòng rebase thuần (gate-exit-2) không cộng vào trần tổng (kiểm đủ 3 vòng red sau gate-exit-2)
: > "$F/labeled/1"; : > "$F/writes"
printf '[{"number":2,"headRefName":"issue-22-b","headRefOid":"%s","isDraft":false,"closingIssuesReferences":[]}]\n' "$(sha 2)" > "$F/prs.json"
sha 2 > "$F/head-2"
printf '{"number":22,"title":"c","body":"","state":"OPEN","labels":[],"comments":[]}' > "$F/issue-22.json"
: > "$F/labeled/2"; : > "$F/writes"
printf 'train-result: 2 gate-exit-2\n' > "$F/train.out"; echo 0 > "$F/train.rc"
( cd "$R" && bash "$QUEUE" --config "$TMP/cfg.json" --wait ) >/dev/null 2>"$TMP/err"
ledger_after_rebase=0
[ -e "$R/.git/super-board/rebuild-total/22" ] && ledger_after_rebase=1
# Sau rebase thuần, thẻ vẫn còn đủ 3 vòng rebuild khác nguyên nhân (x1, x2, x3 -> Ready); vòng 4 (x4) -> Blocked
run_red_pr2() {
  local detail="$1"
  : > "$F/labeled/2"; : > "$F/writes"
  printf 'train-result: 2 red\ntrain-detail: 2 %s\n' "$detail" > "$F/train.out"
  echo 11 > "$F/train.rc"
  ( cd "$R" && bash "$QUEUE" --config "$TMP/cfg.json" --wait ) >/dev/null 2>"$TMP/err"
}
run_red_pr2 "tests/x1.sh:1 AssertionError x1"; p2_r1=0; grep -q "card move 22 Ready" "$F/writes" && p2_r1=1
run_red_pr2 "tests/x2.sh:2 AssertionError x2"; p2_r2=0; grep -q "card move 22 Ready" "$F/writes" && p2_r2=1
run_red_pr2 "tests/x3.sh:3 AssertionError x3"; p2_r3=0; grep -q "card move 22 Ready" "$F/writes" && p2_r3=1
run_red_pr2 "tests/x4.sh:4 AssertionError x4"; p2_r4_blk=0; grep -q "card move 22 Blocked" "$F/writes" && ! grep -q "card move 22 Ready" "$F/writes" && p2_r4_blk=1
if [ "$ledger_after_rebase" = 0 ] && [ "$p2_r1" = 1 ] && [ "$p2_r2" = 1 ] && [ "$p2_r3" = 1 ] && [ "$p2_r4_blk" = 1 ]; then
  ok "A2: pure rebase does not consume total rebuild cap (all 3 different-cause rounds allowed afterwards, 4th Blocked)"
else
  fail "A2: pure rebase ledger=$ledger_after_rebase r1=$p2_r1 r2=$p2_r2 r3=$p2_r3 r4_blk=$p2_r4_blk (writes=$(cat "$F/writes"))"
fi

# ── B (Plan-review v2 AC): sweep_cap_progress KHÔNG được đưa thẻ đã chạm trần tổng về Ready
: > "$TMP/run.writes"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
(
  unset SB_GITHUB_READ_STRICT SB_CAP_PROGRESS_MAX SB_REBUILD_TOTAL_MAX
  SB_LIB_ONLY=1 . "$RUNNER" || exit 1
  set +e
  INFLIGHT_DIR="$TMP/run_inflight"; mkdir -p "$INFLIGHT_DIR"
  REPO_ROOT="$R"
  REBUILD_CAP=2
  SWEPT_CARDS=""
  log() { echo "$*" >> "$TMP/run.log"; }
  gh_checkpoint() { :; }
  gh_write_once() { echo "gh $*" >> "$TMP/run.writes"; }
  set_card_status() { echo "move $1 $2" >> "$TMP/run.writes"; return 0; }
  # issue 21 đã có blocker comment trần tổng + 2 comment khác hash
  cap_progress_comments() { cat "$F/issue-$1.json" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin).get("comments",[])))'; }
  PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_21","status":"Blocked","labels":["bug","loop:rebuild-2"],"content":{"type":"Issue","number":21,"title":"c"}}]}'
  # Đặt thêm label loop:rebuild-2 để chắc chắn sweep_cap_progress coi là ứng viên nếu không kiểm trần tổng
  sweep_cap_progress; rc=$?
  tdir_check=$(rebuild_total_dir)
  if [ "$rc" -ne 0 ] && ! grep -q "move PVTI_21 Ready" "$TMP/run.writes" && [ "$tdir_check" = "$INFLIGHT_DIR/rebuild-total" ]; then
    exit 0
  else
    echo "run.writes: $(tr '\n' ';' < "$TMP/run.writes") tdir=$tdir_check" >&2
    exit 1
  fi
)
if [ $? -eq 0 ]; then
  ok "B (Plan-review v2 AC): sweep_cap_progress does NOT reopen card that reached total rebuild cap"
else
  fail "B (Plan-review v2 AC): sweep_cap_progress reopened total-capped card #21"
fi

# ── C (R1): bounce_n không đếm nhầm `stranded in Building` / `blockers closed` / `GitHub write re-applied`, và không reset cờ capped
printf '[{"number":3,"headRefName":"issue-23-c","headRefOid":"%s","isDraft":false,"closingIssuesReferences":[]}]\n' "$(sha 3)" > "$F/prs.json"
sha 3 > "$F/head-3"
python3 -c '
import json, sys
cs = [
  {"body": "[merge-queue] [report] ❌ red · PR #3 back to Build (loop:rebuild-1)\n<!-- sb-rebuild-total: 1 -->"},
  {"body": "[orchestrator] [report] ↩️ back to Ready · stranded in Building\nDid: worker died"},
  {"body": "[orchestrator] [report] ↩️ back to Ready · blockers closed\nDid: #10 closed"},
  {"body": "[orchestrator] [report] ↩️ back to Ready · GitHub write re-applied\nDid: re-applied"},
]
json.dump({"number": 23, "title": "c", "body": "", "state": "OPEN", "labels": [{"name": "loop:rebuild-1"}], "comments": cs}, open(sys.argv[1], "w"))
' "$F/issue-23.json"
: > "$F/labeled/3"; : > "$F/writes"
printf 'train-result: 3 red\ntrain-detail: 3 tests/e.sh:5 AssertionError e1\n' > "$F/train.out"; echo 11 > "$F/train.rc"
( cd "$R" && bash "$QUEUE" --config "$TMP/cfg.json" --wait ) >/dev/null 2>"$TMP/err"
if grep -q "card move 23 Ready" "$F/writes" && ! grep -q "card move 23 Blocked" "$F/writes"; then
  ok "C1 (R1): merge-queue bounce_n ignores stranded/blockers-closed/write-reapplied comments"
else
  fail "C1 (R1): bounce_n miscounted non-rebuild comments (writes=$(cat "$F/writes"))"
fi

(
  unset SB_GITHUB_READ_STRICT SB_CAP_PROGRESS_MAX SB_REBUILD_TOTAL_MAX
  SB_LIB_ONLY=1 . "$RUNNER" || exit 1
  set +e
  INFLIGHT_DIR="$TMP/run_inflight_c2"; mkdir -p "$INFLIGHT_DIR"
  REPO_ROOT="$R"; REBUILD_CAP=2; SWEPT_CARDS=""
  log() { :; }; gh_checkpoint() { :; }
  gh_write_once() { echo "gh $*" >> "$TMP/run_c2.writes"; }
  set_card_status() { echo "move $1 $2" >> "$TMP/run_c2.writes"; return 0; }
  cj_c2=$(python3 -c 'import json; print(json.dumps([
    {"body": "[merge-queue] [blocker] 🛑 blocked · 🛡 total rebuild cap\nEvidence: a.sh:1 AssertionError a\n<!-- sb-rebuild-total-capped -->\n<!-- sb-rebuild-total: 1 -->"},
    {"body": "[orchestrator] [report] ↩️ back to Ready · stranded in Building\nEvidence: b.sh:2 AssertionError b"},
    {"body": "[orchestrator] [report] ↩️ back to Ready · blockers closed\nEvidence: c.sh:3 AssertionError c"}
  ]))')
  read -r tot capf <<EOF
$(card_rebuild_total 230 2 2 "$cj_c2")
EOF
  cap_progress_comments() { printf '%s' "$cj_c2"; }
  PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_230","status":"Blocked","labels":["bug","loop:rebuild-2"],"content":{"type":"Issue","number":230,"title":"c"}}]}'
  : > "$TMP/run_c2.writes"
  SB_REBUILD_TOTAL_MAX=5 sweep_cap_progress
  if [ "$tot" = 1 ] && [ "$capf" = 1 ] && ! grep -q "move PVTI_230 Ready" "$TMP/run_c2.writes"; then
    exit 0
  else
    echo "tot=$tot capf=$capf writes=$(cat "$TMP/run_c2.writes")" >&2
    exit 1
  fi
)
if [ $? -eq 0 ]; then
  ok "C2 (R1): card_rebuild_total keeps capped=1 and ignores non-rebuild back-to-Ready comments"
else
  fail "C2 (R1): card_rebuild_total lost capped=1 or miscounted non-rebuild comments"
fi

# ── D (R2): qa_apply_report & sweep_cap_progress ghi tab (\t), qa_apply_report dùng card_rebuild_total & block ở trần tổng, rebuild_total_drop khi merge
(
  unset SB_GITHUB_READ_STRICT SB_CAP_PROGRESS_MAX SB_REBUILD_TOTAL_MAX
  SB_LIB_ONLY=1 . "$RUNNER" || exit 1
  set +e
  INFLIGHT_DIR="$TMP/run_inflight_d"; mkdir -p "$INFLIGHT_DIR"
  WORKER_LOG_DIR="$TMP/wl_d"; mkdir -p "$WORKER_LOG_DIR"
  REPO_ROOT="$R"; REBUILD_CAP=2; BOT_LOGIN="sb-bot"; SWEPT_CARDS=""
  log() { echo "$*" >> "$TMP/run_d.log"; }
  gh_checkpoint() { :; }
  gh_write_once() { echo "gh $*" >> "$TMP/run_d.writes"; }
  set_card_status() { echo "move $1 $2" >> "$TMP/run_d.writes"; return 0; }
  note_worker_limit() { :; }; note_early_death() { :; }; fetch_project_items() { :; }; issue_is_open() { return 0; }
  issue_pr_head() { printf 'abc1234deadbeef'; }
  sleep 0 & DEAD=$!; wait "$DEAD"
  printf '=== dispatch x\n{"type":"result","subtype":"success","is_error":false,"result":"done"}\nworker_exit: exit=0 signal=- elapsed=10s\n' > "$WORKER_LOG_DIR/worker-qa-31.log"
  cp "$WORKER_LOG_DIR/worker-qa-31.log" "$WORKER_LOG_DIR/worker-qa-32.log"
  cp "$WORKER_LOG_DIR/worker-qa-31.log" "$WORKER_LOG_DIR/worker-qa-33.log"

  # D1: dưới trần -> ghi tab `\t`, merge-queue đọc được cả qa-fail lẫn cap-progress
  cap_progress_comments() { printf '[]'; }
  issue_comment_count() { printf '4'; }
  issue_last_comment() { printf '[qa] [report] ❌ fail @ abc1234\n'; }
  PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_31","status":"QA","labels":["bug"],"content":{"type":"Issue","number":31,"title":"c","assignees":["sb-bot"]}}]}'
  : > "$TMP/run_d.writes"
  printf 'PID=%s\nLANE=qa\nSTARTED=2026-11-21T10:00:00Z\nWORKER_LOG=%s\nFROM_COL=QA\nCOMMENTS0=3\n' "$DEAD" "$WORKER_LOG_DIR/worker-qa-31.log" > "$INFLIGHT_DIR/31"
  NOOP_CHECK=""
  reap_finished_locks; block_noop_workers
  d1_col3=$(awk -F '\t' 'NF >= 3 {print $3}' "$INFLIGHT_DIR/rebuild-total/31" 2>/dev/null || true)

  # cap-progress cũng phải ghi tab
  cap_progress_comments() { printf '%s' '[{"body":"[merge-queue] [blocker] 🛑 blocked · a\nEvidence: a.sh:1 AssertionError a"},{"body":"[reviewer] [blocker] 🛑 blocked · b\nEvidence: b.sh:2 AssertionError b"}]'; }
  PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_31","status":"Blocked","labels":["bug","loop:rebuild-2"],"content":{"type":"Issue","number":31,"title":"c"}}]}'
  sweep_cap_progress >/dev/null
  d1_cap_col3=$(awk -F '\t' 'NF >= 3 && $3 == "cap-progress" {print $3}' "$INFLIGHT_DIR/rebuild-total/31" 2>/dev/null || true)

  # D2: ledger cục bộ trống, comment đã có <!-- sb-rebuild-total: 3 -->, cur=1 (< REBUILD_CAP=2) -> qa_apply_report phải block về Blocked (không kẹt ở QA, không về Ready)
  cap_progress_comments() { printf '%s' '[{"body":"[merge-queue] [report] ❌ red · back to Build\n<!-- sb-rebuild-total: 3 -->"}]'; }
  PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_32","status":"QA","labels":["bug","loop:rebuild-1"],"content":{"type":"Issue","number":32,"title":"c","assignees":["sb-bot"]}}]}'
  : > "$TMP/run_d.writes"
  printf 'PID=%s\nLANE=qa\nSTARTED=2026-11-21T10:00:00Z\nWORKER_LOG=%s\nFROM_COL=QA\nCOMMENTS0=3\n' "$DEAD" "$WORKER_LOG_DIR/worker-qa-32.log" > "$INFLIGHT_DIR/32"
  NOOP_CHECK=""
  reap_finished_locks; block_noop_workers
  d2_blocked=0; grep -qx "move PVTI_32 Blocked" "$TMP/run_d.writes" && ! grep -qx "move PVTI_32 Ready" "$TMP/run_d.writes" && grep -q "sb-rebuild-total-capped" "$TMP/run_d.writes" && grep -q "blocked-by:  -" "$TMP/run_d.writes" && d2_blocked=1

  # D3: ledger cục bộ có 3 dòng và cur=2 (bằng REBUILD_CAP=2) -> vẫn phải block về Blocked (không return 1 kẹt ở QA)
  mkdir -p "$INFLIGHT_DIR/rebuild-total"
  printf '1\th1\tc1\n2\th2\tc2\n3\th3\tc3\n' > "$INFLIGHT_DIR/rebuild-total/33"
  cap_progress_comments() { printf '[]'; }
  PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_33","status":"QA","labels":["bug","loop:rebuild-2"],"content":{"type":"Issue","number":33,"title":"c","assignees":["sb-bot"]}}]}'
  : > "$TMP/run_d.writes"
  printf 'PID=%s\nLANE=qa\nSTARTED=2026-11-21T10:00:00Z\nWORKER_LOG=%s\nFROM_COL=QA\nCOMMENTS0=3\n' "$DEAD" "$WORKER_LOG_DIR/worker-qa-33.log" > "$INFLIGHT_DIR/33"
  NOOP_CHECK=""
  reap_finished_locks; block_noop_workers
  d3_blocked=0; grep -qx "move PVTI_33 Blocked" "$TMP/run_d.writes" && ! grep -qx "move PVTI_33 Ready" "$TMP/run_d.writes" && d3_blocked=1

  if [ "$d1_col3" = "qa-fail" ] && [ "$d1_cap_col3" = "cap-progress" ] && [ "$d2_blocked" = 1 ] && [ "$d3_blocked" = 1 ]; then
    exit 0
  else
    echo "d1_col3=$d1_col3 d1_cap_col3=$d1_cap_col3 d2_blocked=$d2_blocked d3_blocked=$d3_blocked writes=$(tr '\n' ';' < "$TMP/run_d.writes")" >&2
    exit 1
  fi
)
if [ $? -eq 0 ]; then
  ok "D1-D3 (R2): qa_apply_report & sweep_cap_progress use tabs and qa_apply_report blocks at total rebuild cap"
else
  fail "D1-D3 (R2): qa_apply_report / tab formatting / total cap block failed"
fi

# D4: tab causes từ qa-fail xuất hiện trong rebuild_total_info (nối bằng `; ` chuẩn, không bị lỗi BSD paste `;a b`) + rebuild_total_drop xoá sổ khi PR merged
printf '[{"number":4,"headRefName":"issue-24-d","headRefOid":"%s","isDraft":false,"closingIssuesReferences":[]}]\n' "$(sha 4)" > "$F/prs.json"
sha 4 > "$F/head-4"
printf '{"number":24,"title":"d","body":"","state":"OPEN","labels":[],"comments":[]}' > "$F/issue-24.json"
mkdir -p "$R/.git/super-board/rebuild-total"
printf '1\tqa\tqa-fail\n2\th2\tcap-progress\n3\th3\ttests/d4.sh:1\n' > "$R/.git/super-board/rebuild-total/24"
: > "$F/labeled/4"; : > "$F/writes"; : > "$F/issue-comment-24.txt"
printf 'train-result: 4 red\ntrain-detail: 4 tests/d4_last.sh:9 AssertionError last\n' > "$F/train.out"; echo 11 > "$F/train.rc"
( cd "$R" && bash "$QUEUE" --config "$TMP/cfg.json" --wait ) >/dev/null 2>"$TMP/err"
d4_causes=0; grep -q "qa-fail; cap-progress; tests/d4.sh:1" "$F/issue-comment-24.txt" && d4_causes=1
: > "$F/labeled/4"; : > "$F/writes"
printf 'train-result: 4 merged\n' > "$F/train.out"; echo 0 > "$F/train.rc"
# Fake gh pr view --json state,mergeCommit,headRefOid và body,headRefOid cho merged
python3 -c '
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
old = "elif a[:2] == [\x27pr\x27, \x27view\x27] and opt(\x27--json\x27) == \x27comments\x27:"
new = (
    "elif a[:2] == [\x27pr\x27, \x27view\x27] and opt(\x27--json\x27) == \x27state,mergeCommit,headRefOid\x27:\n"
    "    print(json.dumps({\x27state\x27: \x27MERGED\x27, \x27mergeCommit\x27: {\x27oid\x27: \x27deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\x27}, \x27headRefOid\x27: open(f\x27{F}/head-{num()}\x27).read().strip()}))\n"
    "elif a[:2] == [\x27pr\x27, \x27view\x27] and opt(\x27--json\x27) == \x27body,headRefOid\x27:\n"
    "    print(json.dumps({\x27body\x27: \x27\x27, \x27headRefOid\x27: open(f\x27{F}/head-{num()}\x27).read().strip()}))\n"
    + old
)
assert old in s
p.write_text(s.replace(old, new, 1))
' "$TMP/path/gh"
( cd "$R" && bash "$QUEUE" --config "$TMP/cfg.json" --wait ) >/dev/null 2>"$TMP/err"
if [ "$d4_causes" = 1 ] && [ ! -e "$R/.git/super-board/rebuild-total/24" ]; then
  ok "D4 (R2+R7): '; ' causes surfaced cleanly on cap block and rebuild_total_drop cleans ledger on merge"
else
  fail "D4 (R2+R7): d4_causes=$d4_causes ledger_exists=$([ -e "$R/.git/super-board/rebuild-total/24" ] && echo yes || echo no) comment=$(cat "$F/issue-comment-24.txt" 2>/dev/null | tr '\n' '|')"
fi

# ── E (R6): rebuild_total_dir() trong SB_LIB_ONLY=1 không rò rỉ về .git/super-board/rebuild-total thật
rm -rf "$R/.git/super-board/rebuild-total"
(
  unset SB_REBUILD_TOTAL_DIR INFLIGHT_DIR
  REPO_ROOT="$R"
  SB_LIB_ONLY=1 . "$RUNNER" || exit 1
  set +e
  d_default=$(rebuild_total_dir)
  INFLIGHT_DIR=""
  d_empty=$(rebuild_total_dir)
  INFLIGHT_DIR=".claude/super-board/inflight"
  d_std=$(rebuild_total_dir)
  # Ghi thử qua qa_apply_report khi chưa set INFLIGHT_DIR riêng -> không được tạo sổ dưới $R/.git/super-board/rebuild-total
  log() { :; }; gh_checkpoint() { :; }; gh_write_once() { :; }
  set_card_status() { return 0; }
  issue_last_comment() { printf '[qa] [report] ❌ fail\n'; }
  issue_pr_head() { printf ''; }
  PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_77","status":"QA","labels":["bug"],"content":{"type":"Issue","number":77,"title":"c"}}]}'
  INFLIGHT_DIR="/dev/null"
  qa_apply_report 77 4 >/dev/null 2>&1 || true
  if [ -z "$d_default" ] && [ -z "$d_empty" ] && [ -z "$d_std" ] && [ ! -d "$R/.git/super-board/rebuild-total" ]; then
    exit 0
  else
    echo "d_default='$d_default' d_empty='$d_empty' d_std='$d_std' leaked=$([ -d "$R/.git/super-board/rebuild-total" ] && echo yes || echo no)" >&2
    exit 1
  fi
)
if [ $? -eq 0 ]; then
  ok "E (R6): rebuild_total_dir stays empty in SB_LIB_ONLY=1 without custom INFLIGHT_DIR/SB_REBUILD_TOTAL_DIR"
else
  fail "E (R6): rebuild_total_dir leaked real .git/super-board/rebuild-total in SB_LIB_ONLY=1"
fi

# ── F (R7 + R8): qa_apply_report cũng nối nguyên nhân bằng '; ' (không BSD paste) + review_dash_is_bounceable ghi sổ và marker
(
  unset SB_GITHUB_READ_STRICT SB_CAP_PROGRESS_MAX SB_REBUILD_TOTAL_MAX SB_REVIEW_BOUNCE_MAX
  SB_LIB_ONLY=1 . "$RUNNER" || exit 1
  set +e
  INFLIGHT_DIR="$TMP/run_inflight_f"; mkdir -p "$INFLIGHT_DIR/rebuild-total"
  WORKER_LOG_DIR="$TMP/wl_f"; mkdir -p "$WORKER_LOG_DIR"
  REPO_ROOT="$R"; REBUILD_CAP=2; BOT_LOGIN="sb-bot"; SWEPT_CARDS=""
  log() { :; }; gh_checkpoint() { :; }
  gh_write_once() { echo "gh $*" >> "$TMP/run_f.writes"; }
  set_card_status() { echo "move $1 $2" >> "$TMP/run_f.writes"; return 0; }
  note_worker_limit() { :; }; note_early_death() { :; }; fetch_project_items() { :; }; issue_is_open() { return 0; }
  merge_queue_on() { return 1; }; review_approved_head() { return 1; }
  issue_pr_head() { printf 'abc1234deadbeef'; }
  sleep 0 & DEAD=$!; wait "$DEAD"
  printf '=== dispatch x\n{"type":"result","subtype":"success","is_error":false,"result":"done"}\nworker_exit: exit=0 signal=- elapsed=10s\n' > "$WORKER_LOG_DIR/worker-qa-34.log"
  cp "$WORKER_LOG_DIR/worker-qa-34.log" "$WORKER_LOG_DIR/worker-review-34.log"

  # R7 trong qa_apply_report: 3 nguyên nhân trong ledger -> blocked comment phải có "c1; c2; c3; qa-fail"
  printf '1\th1\tc1\n2\th2\tc2\n3\th3\tc3\n' > "$INFLIGHT_DIR/rebuild-total/35"
  cap_progress_comments() { printf '[]'; }
  issue_comment_count() { printf '4'; }
  issue_last_comment() { printf '[qa] [report] ❌ fail @ abc1234\n'; }
  PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_35","status":"QA","labels":["bug","loop:rebuild-1"],"content":{"type":"Issue","number":35,"title":"c","assignees":["sb-bot"]}}]}'
  : > "$TMP/run_f.writes"
  qa_apply_report 35 4
  f_r7=0; grep -q "c1; c2; c3; qa-fail" "$TMP/run_f.writes" && f_r7=1

  # R8: 1 lượt qa-fail + 1 lượt review_dash_is_bounceable trên thẻ #34 -> total_now=2 (không bị max(1,1)=1)
  : > "$TMP/run_f.writes"
  cap_progress_comments() { printf '[]'; }
  issue_comment_count() { printf '4'; }
  issue_last_comment() { printf '[qa] [report] ❌ fail @ abc1234\n'; }
  PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_34","status":"QA","labels":["bug"],"content":{"type":"Issue","number":34,"title":"c","assignees":["sb-bot"]}}]}'
  printf 'PID=%s\nLANE=qa\nSTARTED=2026-11-21T10:00:00Z\nWORKER_LOG=%s\nFROM_COL=QA\nCOMMENTS0=3\n' "$DEAD" "$WORKER_LOG_DIR/worker-qa-34.log" > "$INFLIGHT_DIR/34"
  NOOP_CHECK=""
  reap_finished_locks; block_noop_workers

  # Lượt tiếp: Reviewer trả blocked-by: - với finding cụ thể -> review_dash_is_bounceable
  issue_comment_count() { printf '5'; }
  issue_last_comment() { printf '[reviewer] [report] ⏸ chờ\n❌ Bug: `.claude/bin/super-board-run.sh:459` sai.\nNext: người xem.\nblocked-by: -'; }
  PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_34","status":"Review","labels":["bug","loop:rebuild-1"],"content":{"type":"Issue","number":34,"title":"c","assignees":["sb-bot"]}}]}'
  : > "$TMP/run_f.writes"
  printf 'PID=%s\nLANE=review\nSTARTED=2026-11-21T10:05:00Z\nWORKER_LOG=%s\nFROM_COL=Review\nCOMMENTS0=5\n' "$DEAD" "$WORKER_LOG_DIR/worker-review-34.log" > "$INFLIGHT_DIR/34"
  NOOP_CHECK=""
  reap_finished_locks; block_noop_workers

  f_lines=$(wc -l < "$INFLIGHT_DIR/rebuild-total/34" 2>/dev/null | tr -d ' ' || echo 0)
  f_rv=$(awk -F '\t' '$3 == "rvbounce" {print $3}' "$INFLIGHT_DIR/rebuild-total/34" 2>/dev/null || true)
  f_marker=0; grep -q "<!-- sb-rebuild-total: 2 -->" "$TMP/run_f.writes" && f_marker=1
  f_bb=0; grep -qx "blocked-by: agent" "$TMP/run_f.writes" && f_bb=1
  cj_34='[{"body":"[orchestrator] [report] \u21a9\ufe0f back to Ready \u00b7 the reviewer\u0027s finding is a code fix, not a person\u0027s decision\n<!-- sb-rebuild-total: 2 -->"}]'
  read -r tot_34 _ <<EOF
$(card_rebuild_total 34 1 2 "$cj_34")
EOF
  read -r tot_34_noledger _ <<EOF
$(card_rebuild_total 340 1 2 "$cj_34")
EOF
  if [ "$f_r7" = 1 ] && [ "$f_lines" = 2 ] && [ "$f_rv" = "rvbounce" ] && [ "$f_marker" = 1 ] && [ "$f_bb" = 1 ] && [ "$tot_34" = 2 ] && [ "$tot_34_noledger" = 2 ]; then
    exit 0
  else
    echo "f_r7=$f_r7 f_lines=$f_lines f_rv=$f_rv f_marker=$f_marker f_bb=$f_bb tot_34=$tot_34 tot_34_noledger=$tot_34_noledger writes=$(tr '\n' ';' < "$TMP/run_f.writes")" >&2
    exit 1
  fi
)
if [ $? -eq 0 ]; then
  ok "F (R7+R8): qa_apply_report joins causes with '; ' and review_dash_is_bounceable records qa-fail + rvbounce total=2"
else
  fail "F (R7+R8): '; ' join in qa_apply_report or qa-fail + rvbounce total count failed"
fi

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_queue_rebuild_total_cap_1400: PASS"; exit 0; } || { echo "test_merge_queue_rebuild_total_cap_1400: FAIL ($FAILS)"; exit 1; }
