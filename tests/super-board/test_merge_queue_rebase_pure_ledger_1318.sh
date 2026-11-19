#!/usr/bin/env bash
# #1318 audit finding (19/11): the pure-rebase ledger (merge-queue.rebase-pure) (a) was not cleared when the PR left Blocked, so a returning
# card started above the ceiling, and (b) was incremented before add_label finished, so a failed label write counted twice on the retry.
# Offline, frame of test_merge_queue_rebase_pure_cap_1318.sh. bash 3.2.
# Offline, frame of test_merge_queue_rebase_not_capped_1319.sh. bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-mq-rebasecap1318.XXXXXX")"
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
elif a[:2] == ['issue', 'edit'] and os.path.exists(F + '/failedit'):
    sys.stderr.write('edit failed\n'); sys.exit(1)
elif a[:2] == ['issue', 'label'] or a[:2] == ['label', 'create']:
    sys.exit(1)
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
export SB_REBASE_PURE_MAX=2
printf '[{"number":1,"headRefName":"issue-11-a","headRefOid":"%s","isDraft":false,"closingIssuesReferences":[]}]\n' "$(sha 1)" > "$F/prs.json"
sha 1 > "$F/head-1"
printf '{"number":11,"title":"c","body":"","state":"OPEN","labels":[{"name":"loop:rebuild-2"}],"comments":[]}' > "$F/issue-11.json"
printf 'train-result: 1 gate-exit-2\n' > "$F/train.out"
echo 11 > "$F/train.rc"; : > "$F/writes"
run_queue() { : > "$F/labeled/1"; ( cd "$R" && bash "$QUEUE" --config "$TMP/cfg.json" --wait ) >"$TMP/out" 2>"$TMP/err"; }
LEDGER="$Q/../repo/.git/super-board/merge-queue.rebase-pure"
LEDGER="$(cd "$R" && git rev-parse --git-common-dir)/super-board/merge-queue.rebase-pure"
case "$LEDGER" in /*) ;; *) LEDGER="$R/$LEDGER" ;; esac
row() { awk '$1 == 1 {print $2}' "$LEDGER" 2>/dev/null; }
# (b) add_label fails: nothing counted
: > "$F/failedit"; : > "$F/writes"; run_queue
[ -z "$(row)" ] && ok "failed loop:rebase label write -> ledger not incremented" || fail "ledger counted a failed label write: $(row)"
rm -f "$F/failedit"
# two real pure rebases, then the third is Blocked and clears the ledger (a)
for i in 1 2; do : > "$F/writes"; run_queue; done
[ "$(row)" = 2 ] && ok "two pure rebases -> ledger 2" || fail "ledger after two rebases: '$(row)'"
: > "$F/writes"; run_queue
grep -q "card move 11 Blocked" "$F/writes" && ok "third -> Blocked" || fail "third not Blocked: $(cat "$F/writes")"
[ -z "$(row)" ] && ok "Blocked -> ledger row cleared" || fail "ledger row survives Blocked: $(row)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_queue_rebase_pure_ledger_1318: PASS"; exit 0; } || { echo "test_merge_queue_rebase_pure_ledger_1318: FAIL ($FAILS)"; exit 1; }
