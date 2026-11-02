#!/usr/bin/env bash
# #775 (review Claude, P2): train in `train-result: N gate-exit-5` kèm lời hook ở `train-detail:` khi git/hook từ chối commit gộp mà không
# có file xung đột, nhưng nhánh rebase của super-board-merge-queue.sh bỏ các dòng đó: comment PR và thẻ vẫn ghi "❌ conflict" và
# "(the base does not merge in cleanly)" — đúng triệu chứng #775 ở mức thẻ. Luật: gate-exit-5 có train-detail ⇒ comment PR và thẻ ghi
# "merge refused" + lời hook; `conflict` thật giữ nguyên chữ cũ. Route vẫn là rebase (loop:rebase, thẻ về Ready).
# Chạy offline: gh (python giả), train / card.sh / needs-you.py / notify.py là stub (cùng khung test_merge_queue_route_rows.sh). bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-mq-refused.XXXXXX")"
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
# #676: một train cho MỘT PR — stub chỉ in dòng train-* của PR trong --prs; mã thoát train.rc.<N> nếu có, không thì train.rc
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
# PR 1 (thẻ #11): hook từ chối; PR 2 (thẻ #12): xung đột thật.
printf '[{"number":1,"headRefName":"issue-11-a","headRefOid":"%s","isDraft":false,"closingIssuesReferences":[]},{"number":2,"headRefName":"issue-12-b","headRefOid":"%s","isDraft":false,"closingIssuesReferences":[]},{"number":3,"headRefName":"issue-13-c","headRefOid":"%s","isDraft":false,"closingIssuesReferences":[]}]\n' "$(sha 1)" "$(sha 2)" "$(sha 3)" > "$F/prs.json"
for n in 1 2 3; do : > "$F/labeled/$n"; sha "$n" > "$F/head-$n"; printf '{"number":1%s,"title":"card","body":"","state":"OPEN","labels":[]}' "$n" > "$F/issue-1$n.json"; done
# PR 3 (thẻ #13): gate-exit-5 do gate tự thoát (không train-detail) ⇒ vẫn chữ conflict. PR 2 có train-detail KHÔNG phải merge-refused
# (vd ac-check của gate) ⇒ thẻ không kèm dòng đó (một nơi quyết định).
printf 'train-result: 2 conflict\ntrain-detail: 2 ac-check: STALE-DETAIL\ntrain-result: 1 gate-exit-5\ntrain-detail: 1 merge-refused: guard-check: commit gop bi tu choi (HOOK-REFUSED)\ntrain-detail: 1 merge-refused: huong dan 1\ntrain-result: 3 gate-exit-5\n' > "$F/train.out"
echo 5 > "$F/train.rc"; : > "$F/writes"
( cd "$R" && bash "$QUEUE" --config "$TMP/cfg.json" --wait ) >"$TMP/out" 2>"$TMP/err"; rc=$?

[ "$rc" -eq 0 ] && ok "queue exit 0" || fail "queue exit $rc: $(tail -3 "$TMP/err")"
grep -q "issue-labels 11 loop:rebase" "$F/writes" && grep -q "card move 11 Ready" "$F/writes" \
  && ok "gate-exit-5: still a rebase pass (loop:rebase, card #11 Ready)" || fail "gate-exit-5 route: $(cat "$F/writes")"
grep -q "HOOK-REFUSED" "$F/pr-comment-1.txt" 2>/dev/null && ok "  … the PR comment carries the hook's lines" \
  || fail "  … PR comment without the hook's lines: $(cat "$F/pr-comment-1.txt" 2>/dev/null)"
grep -q "HOOK-REFUSED" "$F/issue-comment-11.txt" 2>/dev/null && ok "  … the card comment carries the hook's lines" \
  || fail "  … card comment without the hook's lines: $(cat "$F/issue-comment-11.txt" 2>/dev/null)"
if grep -q "❌ conflict\|does not merge in cleanly" "$F/pr-comment-1.txt" "$F/issue-comment-11.txt" 2>/dev/null; then
  fail "  … a hook refusal is still called a conflict: $(grep -h '❌ conflict\|cleanly' "$F/pr-comment-1.txt" "$F/issue-comment-11.txt")"
else ok "  … neither comment calls it a conflict"; fi
grep -q "❌ conflict" "$F/pr-comment-2.txt" 2>/dev/null && grep -q "does not merge in cleanly" "$F/issue-comment-12.txt" 2>/dev/null \
  && grep -q "issue-labels 12 loop:rebase" "$F/writes" && ok "real conflict: wording and route unchanged" \
  || fail "real conflict: $(cat "$F/pr-comment-2.txt" "$F/issue-comment-12.txt" 2>/dev/null)"
grep -q "STALE-DETAIL" "$F/issue-comment-12.txt" "$F/pr-comment-2.txt" 2>/dev/null && fail "  … a conflict comment carries non-refusal train-detail lines" || ok "  … conflict comments carry no train-detail lines"
grep -q "❌ conflict" "$F/pr-comment-3.txt" 2>/dev/null && grep -q "does not merge in cleanly" "$F/issue-comment-13.txt" 2>/dev/null \
  && ok "gate-exit-5 without a merge-refused detail (the gate's own exit 5): still worded as a conflict" \
  || fail "gate-exit-5 without detail: $(cat "$F/pr-comment-3.txt" "$F/issue-comment-13.txt" 2>/dev/null)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_queue_refused_detail: PASS"; exit 0; } || { echo "test_merge_queue_refused_detail: FAIL ($FAILS)"; exit 1; }
