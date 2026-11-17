#!/usr/bin/env bash
# #1235: verify "CHƯA XÁC MINH — N file test đã có bị sửa/xoá" (test đã có bị sửa, thiếu audit có phạm vi) KHÔNG phải đỏ thật.
# A) lần đầu cho một head: thẻ về Review, không loop:rebuild-N, không Blocked, nhãn merge-queue gỡ, một comment `blocked-by: agent`.
# B) lần hai cùng head: đường cũ (rebuild-N rồi Blocked ở trần). C) đỏ thật: tăng rebuild-N như cũ. D) head mới: lại là lần đầu.
# Chạy offline (cùng khung test_merge_queue_refused_detail.sh): gh giả, train/card/needs-you/notify là stub. bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-mq-unverified.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
F="$TMP/fake"; R="$TMP/repo"; Q="$TMP/qbin"
mkdir -p "$F/labeled" "$Q" "$TMP/path"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"; git -C "$R" add .gitignore; git -C "$R" commit -qm init
for f in super-board-merge-queue.sh super-board-github-read.py super-board-approved-head.jq super-board-audit-check.py; do
  ln -s "$ROOT/.claude/bin/$f" "$Q/$f"
done
QUEUE="$Q/super-board-merge-queue.sh"
cat > "$Q/super-board-merge-train.sh" <<'SH'
#!/usr/bin/env bash
n=""; prev=""; for a in "$@"; do [ "$prev" = --prs ] && n="${a%%:*}"; prev="$a"; done
grep -E "^train-(result|detail|red): ${n}( |\$)" "$FAKE/train.out"; exit "$(cat "$FAKE/train.rc.$n" 2>/dev/null || cat "$FAKE/train.rc")"
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
elif a[:2] == ['issue', 'edit']:
    k = num(); d = issue(k); names = [l['name'] for l in d['labels']]
    for i, x in enumerate(a):
        if x == '--add-label' and a[i + 1] not in names:
            names.append(a[i + 1])
    d['labels'] = [{'name': y} for y in names]; json.dump(d, open(f'{F}/issue-{k}.json', 'w'))
    w(f'issue-labels {k} ' + ','.join(sorted(names)))
else:
    sys.stderr.write('fake gh: unexpected ' + ' '.join(a) + '\n'); sys.exit(1)
PY
chmod +x "$TMP/path/gh"
export PATH="$TMP/path:$PATH" FAKE="$F" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_NOTIFY_SKIP=1
unset SB_MERGE_QUEUE SB_MERGE_CALLER SB_GITHUB_READ_STRICT
printf '{"base_branch":"main","repo":{"path":".","remote":"https://github.com/o/r"},"worker_backend":"claude-p","rebuild_cap":2,"verify_commands":["true"],"merge_queue":{"enabled":true}}\n' > "$TMP/cfg.json"
sha() { printf '%040d' "$1" | tr 0 a; }
UNV='train-result: 1 red\ntrain-detail: 1 KẾT LUẬN: CHƯA XÁC MINH — 1 file test đã có bị sửa/xoá trong thay đổi: cần duyệt chéo\n'
REDT='train-result: 1 red\ntrain-detail: 1 KẾT LUẬN: ĐỎ — 2 suite hỏng (REAL-RED)\n'
# run_case <head n> <train.out printf format> <labels json>: PR 1 / thẻ #11 dựng lại, chạy queue một lượt.
run_case() {
  printf '[{"number":1,"headRefName":"issue-11-a","headRefOid":"%s","isDraft":false,"closingIssuesReferences":[]}]\n' "$(sha "$1")" > "$F/prs.json"
  : > "$F/labeled/1"; sha "$1" > "$F/head-1"
  printf '{"number":11,"title":"card","body":"","state":"OPEN","labels":%s}' "$3" > "$F/issue-11.json"
  printf "$2" > "$F/train.out"; echo 11 > "$F/train.rc"; : > "$F/writes"; rm -f "$F"/*-comment-*.txt
  ( cd "$R" && bash "$QUEUE" --config "$TMP/cfg.json" --wait ) >"$TMP/out" 2>"$TMP/err"; RC=$?
}
labeled() { [ -e "$F/labeled/1" ]; }

run_case 1 "$UNV" '[]'
[ "$RC" -eq 0 ] && ok "A: queue exit 0" || fail "A: exit $RC: $(tail -3 "$TMP/err")"
grep -q "card move 11 Review" "$F/writes" && ok "A: first unverified: card returned to Review" || fail "A: no Review move: $(cat "$F/writes")"
grep -q "loop:rebuild\|card move 11 Blocked\|card move 11 Ready" "$F/writes" && fail "A: rebuilt or blocked: $(cat "$F/writes")" || ok "A: no loop:rebuild-N, no Blocked, no Ready"
labeled && fail "A: merge-queue label kept" || ok "A: merge-queue label removed"
grep -q "Pham vi:" "$F/issue-comment-11.txt" 2>/dev/null && [ "$(tail -2 "$F/issue-comment-11.txt" | head -1)" = "blocked-by: agent" ] \
  && ok "A: one comment, tells the reviewer how to audit, last line blocked-by: agent" || fail "A: comment: $(cat "$F/issue-comment-11.txt" 2>/dev/null)"
grep -q "^1 $(sha 1) 1" "$R/.git/super-board/merge-queue.unverified" 2>/dev/null && ok "A: head recorded in the ledger" || fail "A: ledger: $(cat "$R/.git/super-board/merge-queue.unverified" 2>/dev/null)"

run_case 1 "$UNV" '[]'
grep -q "issue-labels 11 loop:rebuild-1" "$F/writes" && grep -q "card move 11 Ready" "$F/writes" && ok "B: second time, same head: old behaviour (loop:rebuild-1, Ready)" \
  || fail "B: $(cat "$F/writes")"
grep -q "card move 11 Review" "$F/writes" && fail "B: still routed to Review" || ok "B: not sent to Review again"
run_case 1 "$UNV" '[{"name":"loop:rebuild-2"}]'
grep -q "card move 11 Blocked" "$F/writes" && ok "B: at the cap: Blocked as before" || fail "B cap: $(cat "$F/writes")"

run_case 2 "$REDT" '[]'
grep -q "issue-labels 11 loop:rebuild-1" "$F/writes" && grep -q "card move 11 Ready" "$F/writes" && ok "C: genuinely red: loop:rebuild-1, Ready (unchanged)" || fail "C: $(cat "$F/writes")"
grep -q "card move 11 Review" "$F/writes" && fail "C: red routed to Review" || ok "C: red not routed to Review"

run_case 3 "$UNV" '[]'
grep -q "card move 11 Review" "$F/writes" && ! grep -q "loop:rebuild" "$F/writes" && ok "D: new head after the earlier one: first again (Review, no rebuild)" || fail "D: $(cat "$F/writes")"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_queue_unverified_edited_test_1235: PASS"; exit 0; } || { echo "test_merge_queue_unverified_edited_test_1235: FAIL ($FAILS)"; exit 1; }
