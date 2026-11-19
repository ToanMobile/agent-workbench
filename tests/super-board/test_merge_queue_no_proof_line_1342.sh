#!/usr/bin/env bash
# #1342 (19/11): a gate-exit-11 whose EVERY reason is `qa-report: AC đã tích [x] nhưng không có dòng bằng chứng '↳'` is a PR-body presentation defect, not a code bug.
# It used to count as a rebuild round, so a card at rebuild_cap was Blocked 🛡 (#1342, loop:rebuild-8). New rule, same kind as `qa-report: stale` (#979):
#  - first time for a head           -> card back to QA, NO new loop:rebuild-N, NOT Blocked;
#  - second time for the same head   -> the old path (cap reached -> Blocked 🛡);
#  - any other reason mixed in       -> the old path, no free pass.
# Offline, frame of test_merge_queue_root_cause_cap.sh. bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-mq-noproof1342.XXXXXX")"
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
HELPER="$ROOT/.claude/bin/super-board-root-cause-hash.py"
ln -s "$HELPER" "$Q/super-board-root-cause-hash.py" 2>/dev/null
NOPROOF="qa-report: AC đã tích [x] nhưng không có dòng bằng chứng '↳': review-output.md có mục Convergence"
printf '[{"number":1,"headRefName":"issue-11-a","headRefOid":"%s","isDraft":false,"closingIssuesReferences":[]},{"number":2,"headRefName":"issue-12-b","headRefOid":"%s","isDraft":false,"closingIssuesReferences":[]}]\n' "$(sha 1)" "$(sha 2)" > "$F/prs.json"
sha 1 > "$F/head-1"; sha 2 > "$F/head-2"
printf '{"number":11,"title":"c","body":"","state":"OPEN","labels":[{"name":"loop:rebuild-2"}],"comments":[]}' > "$F/issue-11.json"
printf '{"number":12,"title":"c","body":"","state":"OPEN","labels":[{"name":"loop:rebuild-2"}],"comments":[]}' > "$F/issue-12.json"
run_queue() { : > "$F/labeled/$1"; ( cd "$R" && bash "$QUEUE" --config "$TMP/cfg.json" --wait ) >"$TMP/out" 2>"$TMP/err"; }
echo 11 > "$F/train.rc"

# 1) only the no-proof-line reason, first time for the head
printf 'train-result: 1 gate-exit-11\ntrain-detail: 1 %s\n' "$NOPROOF" > "$F/train.out"
: > "$F/writes"; run_queue 1
grep -q "card move 11 QA" "$F/writes" && ok "first time: card #11 -> QA" || fail "not moved to QA: $(tr '\n' ';' < "$F/writes")"
grep -q "card move 11 Blocked" "$F/writes" && fail "first time: Blocked at the cap" || ok "first time: not Blocked"
grep -q "issue-labels 11 .*loop:rebuild-3" "$F/writes" && fail "first time: loop:rebuild-3 added" || ok "first time: no new loop:rebuild-N"

# 2) the same head again -> the old path (cap reached -> Blocked)
: > "$F/writes"; run_queue 1
grep -q "card move 11 Blocked" "$F/writes" && ok "second time, same head: old path -> Blocked at the cap" || fail "second time not Blocked: $(tr '\n' ';' < "$F/writes")"

# 3) another reason mixed in -> the old path, no free pass
printf 'train-result: 2 gate-exit-11\ntrain-detail: 2 %s\ntrain-detail: 2 qa-report: Not done: AC2 chưa làm\n' "$NOPROOF" > "$F/train.out"
: > "$F/writes"; run_queue 2
grep -q "card move 12 QA" "$F/writes" && fail "mixed reasons got the free pass to QA" || ok "mixed reasons: no free pass"
grep -q "card move 12 Blocked" "$F/writes" && ok "mixed reasons at the cap: Blocked (old path)" || fail "mixed reasons not Blocked: $(tr '\n' ';' < "$F/writes")"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_queue_no_proof_line_1342: PASS"; exit 0; } || { echo "test_merge_queue_no_proof_line_1342: FAIL ($FAILS)"; exit 1; }
