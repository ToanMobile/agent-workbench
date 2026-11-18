#!/usr/bin/env bash
# #1311 (vòng 4): GitHub rate limit (exit 69 của github-read sau backoff) là TẠM THỜI. Merge train phải đẩy 69 thẳng lên caller,
# queue không tính lần thử / không Blocked PR khoẻ chỉ vì rate limit; card.sh items không đọc lại (nhân backoff) khi lỗi là
# rate limit, chỉ đọc lại khi "board read incomplete". Chạy offline với gh giả. Đổi file bằng R1311_TRAIN / R1311_QUEUE / R1311_CARD
# để dựng RED trên bản main. bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$ROOT/.claude/bin"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-r1311.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$TMP/xdg" SB_HEAVY_SLOT_DIR="$TMP/slots"
mkdir -p "$SB_HEAVY_SLOT_DIR" "$TMP/path"
TRAIN_SRC="${R1311_TRAIN:-$BIN/super-board-merge-train.sh}"
QUEUE_SRC="${R1311_QUEUE:-$BIN/super-board-merge-queue.sh}"
CARD_SRC="${R1311_CARD:-$BIN/super-board-card.sh}"
H=$(printf 'a%.0s' $(seq 40))

# ---- 1. train: gate preflight exit 69 -> train exit 69, PR not treated as failed ----------------------------------------------
O="$TMP/origin.git"; R="$TMP/repo"; T="$TMP/tbin"; mkdir -p "$T"
git init -q --bare -b main "$O"; git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"; echo a > "$R/a"; git -C "$R" add .gitignore a; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
for f in "$BIN"/*; do case "$(basename "$f")" in super-board-merge-train.sh|super-board-merge-gate.sh) ;; *) ln -s "$f" "$T/$(basename "$f")" ;; esac; done
cp "$TRAIN_SRC" "$T/super-board-merge-train.sh"
printf '#!/usr/bin/env bash\necho "gate $*" >> "%s/gate.calls"\nexit 69\n' "$TMP" > "$T/super-board-merge-gate.sh"
chmod +x "$T/super-board-merge-gate.sh" "$T/super-board-merge-train.sh"
cat > "$TMP/path/gh" <<'PY'
#!/usr/bin/env python3
import sys
a = sys.argv[1:]
if a[:2] == ['pr', 'view']:
    print('issue-5-x ' + 'a' * 40)
else:
    sys.stderr.write('fake gh: unexpected ' + ' '.join(a) + '\n'); sys.exit(1)
PY
chmod +x "$TMP/path/gh"
printf '{"base_branch":"main","repo":{"path":"%s","remote":"https://github.com/o/r"},"worker_backend":"claude-p","verify_commands":["true"]}\n' "$R" > "$TMP/cfg.json"
export PATH="$TMP/path:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_NOTIFY_SKIP=1
unset SB_MERGE_QUEUE SB_MERGE_CALLER SB_BOARD_WORKER SB_GITHUB_READ_STRICT
( cd "$R" && bash "$T/super-board-merge-train.sh" --config "$TMP/cfg.json" --prs "5:$H" ) >"$TMP/tout" 2>"$TMP/terr"; rc=$?
[ "$rc" = 69 ] && ok "train: gate exit 69 at preflight -> train exits 69" \
  || fail "train preflight 69: rc=$rc out=$(cat "$TMP/tout") err=$(tail -3 "$TMP/terr")"
grep -q "fails the gate preflight" "$TMP/terr" && fail "train treated the rate limit as a PR failure ($(grep 'fails the gate' "$TMP/terr"))" \
  || ok "train: no 'fails the gate preflight' for a rate limit"

# ---- 2. queue: train exit 69 (with or without a train-result line) is not an attempt and not Blocked -------------------------
F="$TMP/fake"; Q="$TMP/qbin"; QR="$TMP/qrepo"; mkdir -p "$F/labeled" "$Q"
git init -q -b main "$QR"; git -C "$QR" config user.email t@example.invalid; git -C "$QR" config user.name t
printf '.claude/\n' > "$QR/.gitignore"; git -C "$QR" add .gitignore; git -C "$QR" commit -qm init
for f in super-board-github-read.py super-board-approved-head.jq super-board-audit-check.py super-board-ac-check.py; do ln -s "$BIN/$f" "$Q/$f"; done
cp "$QUEUE_SRC" "$Q/super-board-merge-queue.sh"
cat > "$Q/super-board-merge-train.sh" <<'SH'
#!/usr/bin/env bash
cat "$FAKE/train.out"; exit "$(cat "$FAKE/train.rc")"
SH
cat > "$Q/super-board-card.sh" <<'SH'
#!/usr/bin/env bash
while [ "${1#--}" != "$1" ]; do shift 2; done
if [ -f "$FAKE/card-69-$2" ] || [ -f "$FAKE/card-69" ]; then exit 69; fi
echo "card $*" >> "$FAKE/writes"
SH
printf 'import os, sys\nopen(os.environ["FAKE"] + "/writes", "a").write("needs-you " + " ".join(sys.argv[1:]) + "\\n")\n' > "$Q/super-board-needs-you.py"
printf 'import os, sys\nopen(os.environ["FAKE"] + "/writes", "a").write("notify " + " ".join(sys.argv[1:]) + "\\n")\n' > "$Q/super-board-notify.py"
chmod +x "$Q"/*.sh
cat > "$TMP/path/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
F = os.environ['FAKE']; a = sys.argv[1:]
def opt(n): return a[a.index(n) + 1] if n in a else None
def w(l): open(F + '/writes', 'a').write(l + '\n')
if a[:2] == ['pr', 'list']:
    st = (opt('--state') or 'open').upper()
    print(json.dumps([p for p in json.load(open(F + '/prs.json')) if st == 'OPEN' and os.path.exists(f"{F}/labeled/{p['number']}")]))
elif a[:2] == ['pr', 'view'] and opt('--json') == 'comments':
    print(json.dumps({'comments': [{'authorAssociation': 'OWNER', 'body': 'approved-head:' + open(f'{F}/head-1').read().strip()}]}))
elif a[:2] == ['pr', 'view'] and 'state' in (opt('--json') or ''):
    print(json.dumps({'state': 'MERGED', 'mergeCommit': {'oid': 'a' * 40}, 'headRefOid': 'a' * 40}))
elif a[:2] == ['pr', 'view'] and opt('--json') == 'body,headRefOid':
    if os.path.exists(f'{F}/pr-body-rl'):
        sys.stderr.write('You have exceeded a secondary rate limit.\n'); sys.exit(1)
    print(json.dumps({'body': '', 'headRefOid': 'a' * 40}))
elif a[0] == 'api' and '/timeline' in a[1]:
    print(json.dumps([[{'event': 'labeled', 'label': {'name': 'merge-queue'}, 'created_at': '2026-11-01T00:00:00Z'}]]))
elif a[:2] == ['issue', 'view']:
    print(json.dumps({'number': 11, 'title': 'card', 'body': '', 'state': 'OPEN', 'labels': []}))
elif a[:2] == ['pr', 'edit']:
    w('pr-edit ' + ' '.join(a[2:]))
    if os.path.exists(f'{F}/labeled/1') and '--remove-label' in a: os.remove(f'{F}/labeled/1')
elif a[:2] in (['pr', 'comment'], ['issue', 'comment'], ['issue', 'edit'], ['issue', 'close']):
    w(a[0] + '-' + a[1])
else:
    sys.stderr.write('fake gh: unexpected ' + ' '.join(a) + '\n'); sys.exit(1)
PY
chmod +x "$TMP/path/gh"
export FAKE="$F"
printf '{"base_branch":"main","repo":{"path":".","remote":"https://github.com/o/r"},"worker_backend":"claude-p","rebuild_cap":2,"verify_commands":["true"],"merge_queue":{"enabled":true}}\n' > "$TMP/qcfg.json"
printf '[{"number":1,"headRefName":"issue-11-a","headRefOid":"%s","isDraft":false,"closingIssuesReferences":[]}]\n' "$H" > "$F/prs.json"
echo "$H" > "$F/head-1"
for variant in with-line no-line; do
  : > "$F/labeled/1"; : > "$F/writes"; rm -f "$QR/.git/super-board/merge-queue.attempts"
  if [ "$variant" = with-line ]; then printf 'train-result: 1 gate-exit-69\n' > "$F/train.out"; else : > "$F/train.out"; fi
  echo 69 > "$F/train.rc"
  for pass in 1 2 3; do ( cd "$QR" && bash "$Q/super-board-merge-queue.sh" --config "$TMP/qcfg.json" --wait ) >"$TMP/qout" 2>"$TMP/qerr"; done
  if [ ! -s "$QR/.git/super-board/merge-queue.attempts" ] && ! grep -q "card move 11 Blocked" "$F/writes" && ! grep -q "pr-edit" "$F/writes"; then
    ok "queue ($variant): 3 passes of train exit 69 -> no attempt counted, card not Blocked, PR keeps its label"
  else
    fail "queue ($variant): attempts=$(cat "$QR/.git/super-board/merge-queue.attempts" 2>/dev/null) writes=$(tr '\n' ';' < "$F/writes") err=$(tail -2 "$TMP/qerr")"
  fi
done

# ---- 2b. #1311 R1: route_one gặp 69 ở card_move / unproven_ac / ac_autofix / resolve_card tại trần -> không exit 79, không tính lần thử, không gỡ nhãn
# 2b-1: route_one red -> card_move 69 lặp 3 lần -> exit 0, không attempts, không Blocked, giữ nhãn; hết rate limit thì route xong từ pending
: > "$F/labeled/1"; : > "$F/writes"; : > "$F/card-69"; rm -f "$QR/.git/super-board/merge-queue.attempts" "$QR/.git/super-board/merge-queue.pending" "$SB_GITHUB_HALT_FILE" "$TMP/halt.json"
printf 'train-result: 1 red\n' > "$F/train.out"; echo 11 > "$F/train.rc"
q_rc=0
for pass in 1 2 3; do
  ( cd "$QR" && bash "$Q/super-board-merge-queue.sh" --config "$TMP/qcfg.json" --wait ) >"$TMP/qout" 2>"$TMP/qerr" || q_rc=$?
done
if [ "$q_rc" -eq 0 ] && [ ! -s "$QR/.git/super-board/merge-queue.attempts" ] && [ -s "$QR/.git/super-board/merge-queue.pending" ] \
   && [ -e "$F/labeled/1" ] && ! grep -q "card move 11 Blocked" "$F/writes" && ! grep -q "pr-edit" "$F/writes" && [ ! -e "$TMP/halt.json" ]; then
  ok "route_one red + card_move 69 (x3): exits 0 (not 79), no attempt counted, pending kept, PR keeps label"
else
  fail "route_one card_move 69: rc=$q_rc attempts=$(cat "$QR/.git/super-board/merge-queue.attempts" 2>/dev/null) pending=$(cat "$QR/.git/super-board/merge-queue.pending" 2>/dev/null) writes=$(tr '\n' ';' < "$F/writes") err=$(tail -2 "$TMP/qerr")"
fi
rm -f "$F/card-69"; : > "$F/writes"
( cd "$QR" && bash "$Q/super-board-merge-queue.sh" --config "$TMP/qcfg.json" --wait ) >"$TMP/qout" 2>"$TMP/qerr"; q_rc=$?
if [ "$q_rc" -eq 0 ] && grep -q "card move 11 Ready" "$F/writes" && grep -q "pr-edit 1 .*--remove-label merge-queue" "$F/writes" && [ ! -s "$QR/.git/super-board/merge-queue.pending" ]; then
  ok "route_one card_move 69 recovery: next run completes card move Ready from pending and unlabels PR"
else
  fail "route_one card_move 69 recovery: rc=$q_rc writes=$(tr '\n' ';' < "$F/writes") err=$(tail -2 "$TMP/qerr")"
fi

# 2b-2: route_one merged -> unproven_ac 69 -> exit 0, không tính lần thử, giữ nhãn; hết rate limit phải ghi đủ comment ✅ merged và Done
: > "$F/labeled/1"; : > "$F/writes"; : > "$F/pr-body-rl"; rm -f "$QR/.git/super-board/merge-queue.attempts" "$QR/.git/super-board/merge-queue.pending"
printf 'train-result: 1 merged\n' > "$F/train.out"; echo 0 > "$F/train.rc"
SB_GITHUB_RATE_RETRIES=0 SB_GITHUB_RATE_DELAY=0 bash -c 'cd "$1" && bash "$2" --config "$3" --wait' _ "$QR" "$Q/super-board-merge-queue.sh" "$TMP/qcfg.json" >"$TMP/qout" 2>"$TMP/qerr"; q_rc=$?
if [ "$q_rc" -eq 0 ] && [ ! -s "$QR/.git/super-board/merge-queue.attempts" ] && [ -e "$F/labeled/1" ] && ! grep -q "pr-edit" "$F/writes" && [ ! -e "$TMP/halt.json" ]; then
  ok "route_one merged + unproven_ac 69: exits 0, no attempt counted, PR keeps label"
else
  fail "route_one unproven_ac 69: rc=$q_rc attempts=$(cat "$QR/.git/super-board/merge-queue.attempts" 2>/dev/null) writes=$(tr '\n' ';' < "$F/writes") err=$(tail -2 "$TMP/qerr")"
fi
rm -f "$F/pr-body-rl"; : > "$F/writes"
( cd "$QR" && bash "$Q/super-board-merge-queue.sh" --config "$TMP/qcfg.json" --wait ) >"$TMP/qout" 2>"$TMP/qerr"; q_rc=$?
if [ "$q_rc" -eq 0 ] && grep -q "issue-comment" "$F/writes" && grep -q "card move 11 Done" "$F/writes" && grep -q "pr-edit 1 .*--remove-label merge-queue" "$F/writes"; then
  ok "route_one unproven_ac 69 recovery: next run posts issue comment, moves card Done, unlabels PR"
else
  fail "route_one unproven_ac 69 recovery: rc=$q_rc writes=$(tr '\n' ';' < "$F/writes") err=$(tail -2 "$TMP/qerr")"
fi

# 2b-3: route_one gate-exit-11 -> ac_autofix 69 -> exit 0, không tính lần thử, giữ nhãn; hết rate limit phải dựng lại sb:ac và đăng comment PR
: > "$F/labeled/1"; : > "$F/writes"; : > "$F/pr-body-rl"; rm -f "$QR/.git/super-board/merge-queue.attempts" "$QR/.git/super-board/merge-queue.pending"
printf 'train-result: 1 gate-exit-11\ntrain-detail: 1 ac-check: card #11 has 2 acceptance criteria\n' > "$F/train.out"; echo 11 > "$F/train.rc"
SB_GITHUB_RATE_RETRIES=0 SB_GITHUB_RATE_DELAY=0 bash -c 'cd "$1" && bash "$2" --config "$3" --wait' _ "$QR" "$Q/super-board-merge-queue.sh" "$TMP/qcfg.json" >"$TMP/qout" 2>"$TMP/qerr"; q_rc=$?
if [ "$q_rc" -eq 0 ] && [ ! -s "$QR/.git/super-board/merge-queue.attempts" ] && [ -e "$F/labeled/1" ] && ! grep -q "pr-edit" "$F/writes" && [ ! -e "$TMP/halt.json" ]; then
  ok "route_one gate-exit-11 + ac_autofix 69: exits 0, no attempt counted, PR keeps label"
else
  fail "route_one ac_autofix 69: rc=$q_rc attempts=$(cat "$QR/.git/super-board/merge-queue.attempts" 2>/dev/null) writes=$(tr '\n' ';' < "$F/writes") err=$(tail -2 "$TMP/qerr")"
fi
rm -f "$F/pr-body-rl"; : > "$F/writes"
cat > "$TMP/path/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
F = os.environ['FAKE']; a = sys.argv[1:]
def opt(n): return a[a.index(n) + 1] if n in a else None
def w(l): open(F + '/writes', 'a').write(l + '\n')
if a[:2] == ['pr', 'list']:
    st = (opt('--state') or 'open').upper()
    print(json.dumps([p for p in json.load(open(F + '/prs.json')) if st == 'OPEN' and os.path.exists(f"{F}/labeled/{p['number']}")]))
elif a[:2] == ['pr', 'view'] and opt('--json') == 'comments':
    print(json.dumps({'comments': [{'authorAssociation': 'OWNER', 'body': 'approved-head:' + open(f'{F}/head-1').read().strip()}]}))
elif a[:2] == ['pr', 'view'] and 'state' in (opt('--json') or ''):
    print(json.dumps({'state': 'MERGED', 'mergeCommit': {'oid': 'a' * 40}, 'headRefOid': 'a' * 40}))
elif a[:2] == ['pr', 'view'] and opt('--json') == 'body,headRefOid':
    if os.path.exists(f'{F}/pr-body-rl'):
        sys.stderr.write('You have exceeded a secondary rate limit.\n'); sys.exit(1)
    print(json.dumps({'body': '## Acceptance criteria\n- [ ] a1\n- [ ] a2\n', 'headRefOid': 'a' * 40}))
elif a[0] == 'api' and '/timeline' in a[1]:
    print(json.dumps([[{'event': 'labeled', 'label': {'name': 'merge-queue'}, 'created_at': '2026-11-01T00:00:00Z'}]]))
elif a[:2] == ['issue', 'view']:
    print(json.dumps({'number': 11, 'title': 'card', 'body': '## Acceptance Criteria\n- [ ] a1\n- [ ] a2\n', 'state': 'OPEN', 'labels': []}))
elif a[:2] == ['pr', 'edit']:
    w('pr-edit ' + ' '.join(a[2:]))
    if os.path.exists(f'{F}/labeled/1') and '--remove-label' in a: os.remove(f'{F}/labeled/1')
elif a[:2] in (['pr', 'comment'], ['issue', 'comment'], ['issue', 'edit']):
    w(a[0] + '-' + a[1])
else:
    sys.stderr.write('fake gh: unexpected ' + ' '.join(a) + '\n'); sys.exit(1)
PY
chmod +x "$TMP/path/gh"
( cd "$QR" && bash "$Q/super-board-merge-queue.sh" --config "$TMP/qcfg.json" --wait ) >"$TMP/qout" 2>"$TMP/qerr"; q_rc=$?
if [ "$q_rc" -eq 0 ] && grep -q "pr-edit 1 .*--body-file" "$F/writes" && grep -q "pr-comment" "$F/writes" && [ ! -s "$QR/.git/super-board/merge-queue.pending" ]; then
  ok "route_one ac_autofix 69 recovery: next run rebuilds sb:ac, posts PR comment, clears pending"
else
  fail "route_one ac_autofix 69 recovery: rc=$q_rc writes=$(tr '\n' ';' < "$F/writes") err=$(tail -2 "$TMP/qerr")"
fi

# 2b-4: attempt_retry ở trần (n=2 -> 3) khi resolve_card (card.sh item-id) gặp 69 -> exit 0, không unlabel, không chạm #21
printf '[{"number":1,"headRefName":"fix-bar","headRefOid":"%s","isDraft":false,"closingIssuesReferences":[{"number":21,"repository":{"name":"r","owner":{"login":"o"}}}]}]\n' "$H" > "$F/prs.json"
: > "$F/labeled/1"; : > "$F/writes"; : > "$F/card-69-21"; rm -f "$QR/.git/super-board/merge-queue.pending"
mkdir -p "$QR/.git/super-board"; echo "1 $H 2 $(date +%s)" > "$QR/.git/super-board/merge-queue.attempts"
printf 'train-result: 1 deferred\n' > "$F/train.out"; echo 0 > "$F/train.rc"
( cd "$QR" && bash "$Q/super-board-merge-queue.sh" --config "$TMP/qcfg.json" --wait ) >"$TMP/qout" 2>"$TMP/qerr"; q_rc=$?
if [ "$q_rc" -eq 0 ] && [ -e "$F/labeled/1" ] && ! grep -q "pr-edit" "$F/writes" && ! grep -q "issue-comment" "$F/writes" && [ ! -e "$TMP/halt.json" ]; then
  ok "attempt_retry at cap + resolve_card 69: exits 0, PR keeps label, issue #21 untouched"
else
  fail "attempt_retry resolve_card 69: rc=$q_rc writes=$(tr '\n' ';' < "$F/writes") err=$(tail -2 "$TMP/qerr")"
fi
rm -f "$F/card-69-21"

# ---- 3. card.sh items: rate limit (69 from github-read) is not re-read; a real incomplete read still is ------------------------
CB="$TMP/cbin"; mkdir -p "$CB"
for f in "$BIN"/*; do case "$(basename "$f")" in super-board-card.sh) ;; *) ln -s "$f" "$CB/$(basename "$f")" ;; esac; done
cp "$CARD_SRC" "$CB/super-board-card.sh"
printf '#!/usr/bin/env bash\necho x >> "%s/count"\necho "You have exceeded a secondary rate limit." >&2\nexit 1\n' "$TMP" > "$TMP/path/gh"
rm -f "$TMP/count" "$SB_GITHUB_HALT_FILE"
SB_GITHUB_RATE_RETRIES=1 SB_GITHUB_RATE_DELAY=0 SB_CARD_RETRY_SLEEP=0 SB_GITHUB_READ_STRICT=1 SB_CARD_CACHE_DIR="$TMP/cc" \
  bash "$CB/super-board-card.sh" --owner o --number 1 items >"$TMP/cout" 2>"$TMP/cerr"; rc=$?
n=$(wc -l < "$TMP/count" 2>/dev/null | tr -d ' ')
if [ "$rc" = 69 ] && [ "$n" = 2 ] && [ ! -e "$SB_GITHUB_HALT_FILE" ] && ! grep -q "re-reading once" "$TMP/cerr"; then
  ok "card.sh items under rate limit: one bounded read (2 gh calls), no re-read, exit 69, no halt"
else
  fail "card.sh items rate limit: rc=$rc gh_calls=$n ($(tail -2 "$TMP/cerr"))"
fi

echo
[ "$FAILS" -eq 0 ] && { echo "test_rate_limit_69_train_queue_1311: PASS"; exit 0; } || { echo "test_rate_limit_69_train_queue_1311: FAIL ($FAILS)"; exit 1; }
