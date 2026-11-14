#!/usr/bin/env bash
# Run 2026-11-10 17:30 halted the board (exit 79): PR #341 touches more than 300 files, so GitHub answers `gh pr diff`
# with HTTP 406 "diff exceeded the maximum number of files" on every attempt and the halt replays forever.
# The read must build the same three-dot diff from local git (pinned to the PR head and base) and still validate it
# against the PR metadata; a local diff that disagrees with the metadata must still fail.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
READ="$ROOT/.claude/bin/super-board-github-read.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

git -C "$TMP" init -q -b main repo
R="$TMP/repo"
git -C "$R" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
printf 'one\n' > "$R/a.txt"; printf 'keep\n' > "$R/b.txt"
git -C "$R" add a.txt b.txt; git -C "$R" -c user.name=t -c user.email=t@t commit -q -m files
BASE="$(git -C "$R" rev-parse HEAD)"
git -C "$R" checkout -q -b feature
printf 'one\ntwo\n' > "$R/a.txt"; printf 'new\n' > "$R/c.txt"; git -C "$R" rm -q b.txt
git -C "$R" add a.txt c.txt; git -C "$R" -c user.name=t -c user.email=t@t commit -q -m change
HEAD="$(git -C "$R" rev-parse HEAD)"
git -C "$R" checkout -q main

SB_REPO_PATH="$R" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 \
python3 - "$READ" "$HEAD" "$BASE" <<'PY'
import importlib.util, json, subprocess, sys
spec = importlib.util.spec_from_file_location('ghread', sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
head, base = sys.argv[2], sys.argv[3]
calls = []
def fake_gh(args):
    calls.append(args)
    if args[:2] == ['pr', 'diff']:
        return subprocess.CompletedProcess(args, 1, '', 'could not find pull request diff: HTTP 406: Sorry, the diff '
            'exceeded the maximum number of files (300). Consider using \'List pull requests files\' API or locally '
            'cloning the repository instead. (https://api.github.com/repos/o/r/pulls/7)\nPullRequest.diff too_large\n')
    if args[:2] == ['pr', 'view']:
        return subprocess.CompletedProcess(args, 0, json.dumps({'headRefOid': head, 'baseRefOid': base}), '')
    raise AssertionError(f'unexpected gh call {args}')
m.run_gh = fake_gh
files = [{'path': 'a.txt', 'additions': 1, 'deletions': 0}, {'path': 'b.txt', 'additions': 0, 'deletions': 1},
         {'path': 'c.txt', 'additions': 1, 'deletions': 0}]
meta = {'files': files, 'additions': 2, 'deletions': 1, 'changedFiles': 3, 'labels': [], 'body': ''}
fails = 0
try:
    text, _ = m.read(['pr', 'diff', '7', '--repo', 'o/r'], 'diff', meta)
    ok = text.count('diff --git ') == 3 and '+two' in text and '-keep' in text
    print(('✔' if ok else '✖') + ' too-large diff rebuilt from local git'); fails += not ok
except BaseException as e:
    print('✖ too-large diff not rebuilt:', type(e).__name__, e); fails += 1
# Metadata that disagrees with the local diff (PR moved on) must still be refused, never accepted.
bad = dict(meta, additions=5)
try:
    m.read(['pr', 'diff', '7', '--repo', 'o/r'], 'diff', bad)
    print('✖ accepted a local diff that disagrees with the metadata'); fails += 1
except BaseException as e:
    print('✔ disagreeing local diff refused:', type(e).__name__)
sys.exit(1 if fails else 0)
PY
