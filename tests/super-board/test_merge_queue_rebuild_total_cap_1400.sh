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
for f in super-board-merge-queue.sh super-board-github-read.py super-board-approved-head.jq super-board-audit-check.py super-board-root-cause-hash.py; do
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

# ── A2: Vòng rebase thuần (gate-exit-2) không cộng vào trần tổng
: > "$F/labeled/1"; : > "$F/writes"
printf '[{"number":2,"headRefName":"issue-22-b","headRefOid":"%s","isDraft":false,"closingIssuesReferences":[]}]\n' "$(sha 2)" > "$F/prs.json"
sha 2 > "$F/head-2"
printf '{"number":22,"title":"c","body":"","state":"OPEN","labels":[],"comments":[]}' > "$F/issue-22.json"
: > "$F/labeled/2"; : > "$F/writes"
printf 'train-result: 2 gate-exit-2\n' > "$F/train.out"; echo 0 > "$F/train.rc"
( cd "$R" && bash "$QUEUE" --config "$TMP/cfg.json" --wait ) >/dev/null 2>"$TMP/err"
# Sau rebase thuần, thẻ vẫn còn đủ 3 vòng rebuild khác nguyên nhân
: > "$F/writes"
printf 'train-result: 2 red\ntrain-detail: 2 tests/x.sh:1 AssertionError x1\n' > "$F/train.out"; echo 11 > "$F/train.rc"
: > "$F/labeled/2"
( cd "$R" && bash "$QUEUE" --config "$TMP/cfg.json" --wait ) >/dev/null 2>"$TMP/err"
if grep -q "card move 22 Ready" "$F/writes" && ! grep -q "card move 22 Blocked" "$F/writes"; then
  ok "A2: pure rebase does not consume total rebuild cap"
else
  fail "A2: pure rebase consumed rebuild cap (writes=$(cat "$F/writes"))"
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

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_queue_rebuild_total_cap_1400: PASS"; exit 0; } || { echo "test_merge_queue_rebuild_total_cap_1400: FAIL ($FAILS)"; exit 1; }
