#!/usr/bin/env bash
# #676: merge queue verify từng PR song song, khoá chỉ quanh lúc ghi main.
# Phần A (train + merge gate thật, gh giả, origin bare):
#   A1 verify của train nhận `--diff origin/main --scoped`; post-fix-gate gọi thẳng (DEVKIT_SLOT_ADVISORY_HELD không đặt: không lách pool heavy).
#   A2 verify BUSY (exit 4 + JSON busy): `timeout`, không merge, không xanh.
#   A3 base dời giữa verify của train và lượt merge: gate --require-receipt thoát 12 (không verify trong khoá), train verify lại ngoài khoá
#      rồi merge cây mới. Base dời mãi: sau 2 lần `base-moved`, exit 12, không merge.
#   A4 hai train khác PR chạy song song: `gh pr merge` không bao giờ chồng nhau; gate không verify trong khoá.
#   A5 cây của gate khác biên nhận mà base KHÔNG dời (file merge=union): gate tự verify, merged — không lặp base-moved.
# Phần B (queue thật, train giả):
#   B1 PR2 gắn nhãn khi train của PR1 còn chạy: lượt queue sau phóng train cho PR2 ngay (không chờ PR1, không "holds lock"), PR2 merge
#      và được route trước khi PR1 xong; lượt queue thường thoát < 5 s.
#   B2 merge_queue.max_trains=1: PR thứ hai không được phóng, không tính lần thử.
#   B3 train chết vì tín hiệu (không rc): lượt sau tính một lần thử "train died". `base-moved`: giữ nhãn, KHÔNG tính lần thử.
#   B4 super-board-status.py gộp state của hai train sống.
#   B5 launchd giết process group của job sau khi queue thoát: train nền (session riêng) vẫn sống và ghi rc.
# Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-mq-parallel.XXXXXX")"
KILLS=""
trap 'for k in $KILLS; do kill "$k" 2>/dev/null; done; rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$TMP/xdg"
export SB_HEAVY_SLOT_DIR="$TMP/heavy-slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
export SB_GITHUB_RETRY_DELAY=0 SB_NOTIFY_SKIP=1
unset SB_MERGE_CALLER SB_MERGE_QUEUE SB_BOARD_WORKER DEVKIT_SLOT_ADVISORY_HELD

# ════ Phần A: train + gate thật ════════════════════════════════════════════════════════════════════════════════════════════════════════
A="$TMP/a"; mkdir -p "$A"
O="$A/origin.git"; R="$A/repo"; W="$R/.claude/worktrees"
git init -q --bare -b main "$O"; git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"; echo a > "$R/a"; git -C "$R" add .gitignore a; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
card_branch() {   # card_branch <N> <file>
  git -C "$R" fetch -q origin
  git -C "$R" branch -q --no-track "issue-$1-x" origin/main
  git -C "$R" worktree add -q "$W/issue-$1-build" "issue-$1-x"
  echo "$1" > "$W/issue-$1-build/$2"; git -C "$W/issue-$1-build" add "$2"; git -C "$W/issue-$1-build" commit -qm "card $1"
  git -C "$R" push -q origin "issue-$1-x"
  git -C "$R" rev-parse "issue-$1-x" > "$A/pr$1.head"
  git -C "$R" diff origin/main "issue-$1-x" > "$A/pr$1.diff"
  printf '{"files":[{"path":"%s"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' "$2" > "$A/pr$1.meta"
}
# main_moves <file>: một commit khác lên origin/main (như PR khác vừa merge).
main_moves() {
  local d="$A/mv.$$.$RANDOM"
  git clone -q "$O" "$d" 2>/dev/null && git -C "$d" config user.email t@example.invalid && git -C "$d" config user.name t \
    && echo "$1" > "$d/$1" && git -C "$d" add "$1" && git -C "$d" commit -qm "main moves $1" && git -C "$d" push -q origin HEAD:main
  rm -rf "$d"
}
mkdir -p "$A/bin"
cat > "$A/bin/gh" <<'SH'
#!/usr/bin/env bash
# gh giả: `pr merge` mô phỏng squash; mkdir "merging" phát hiện hai lượt merge chồng nhau.
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr merge "*)
    mkdir "$FAKE_DIR/merging" 2>/dev/null || echo "OVERLAP $n" >> "$FAKE_DIR/merge.overlap"
    sleep 1
    git -C "$FAKE_REPO" fetch -q origin main "issue-$n-x"
    tree=$(git -C "$FAKE_REPO" merge-tree --write-tree origin/main "$head") || { rmdir "$FAKE_DIR/merging"; exit 1; }
    c=$(git -C "$FAKE_REPO" commit-tree "$tree" -p origin/main -m "squash #$n")
    git -C "$FAKE_REPO" push -q origin "$c:refs/heads/main" && echo "$n" >> "$FAKE_DIR/merged"
    rmdir "$FAKE_DIR/merging"; echo "merged #$n" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$A/bin/gh"
mkdir -p "$A/sbbin"
for f in "$ROOT"/.claude/bin/*; do ln -s "$f" "$A/sbbin/$(basename "$f")"; done
rm -f "$A/sbbin/super-board-merge-gate.sh"
cat > "$A/sbbin/super-board-merge-gate.sh" <<SH
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = --preflight ] && { echo "preflight: ok"; exit 0; }; done
echo "\$*" >> "\$FAKE_DIR/gate.calls"
exec bash "$ROOT/.claude/bin/super-board-merge-gate.sh" "\$@"
SH
chmod +x "$A/sbbin/super-board-merge-gate.sh"
# post-fix-gate giả (đường dẫn tuyệt đối: train / gate chèn cờ, gọi thẳng): ghi argv, thư mục, DEVKIT_SLOT_ADVISORY_HELD; hành vi theo file:
#   busy           → JSON busy + exit 4        move-once → đẩy main đi một lần        move-always → mỗi lượt verify đẩy main đi
mkdir -p "$A/kit"
cat > "$A/kit/post-fix-gate.py" <<'PY'
import os, subprocess, sys, time
d = os.environ["FAKE_DIR"]
open(d + "/pfg.log", "a").write("%s|%s|held=%s\n" % (" ".join(sys.argv[1:]), os.getcwd(), os.environ.get("DEVKIT_SLOT_ADVISORY_HELD", "")))
if os.path.exists(d + "/busy"):
    print('{"exit_code": 4, "busy": true}'); sys.exit(4)
mv = None
if os.path.exists(d + "/move-once"):
    os.remove(d + "/move-once"); mv = "m%d" % time.time_ns()
elif os.path.exists(d + "/move-always"):
    mv = "m%d" % time.time_ns()
if mv:
    subprocess.run(["bash", "-c", 'main_moves() { :; }; . "$0"; amove "$1"', d + "/move.sh", mv], check=False)
sys.exit(0)
PY
cat > "$A/move.sh" <<SH
amove() {
  local d="$A/mv.\$1"
  git clone -q "$O" "\$d" 2>/dev/null && git -C "\$d" config user.email t@example.invalid && git -C "\$d" config user.name t \\
    && echo "\$1" > "\$d/\$1" && git -C "\$d" add "\$1" && git -C "\$d" commit -qm "main moves \$1" && git -C "\$d" push -q origin HEAD:main
  rm -rf "\$d"
}
SH
export PATH="$A/bin:$PATH" FAKE_DIR="$A" FAKE_REPO="$R" SB_GITHUB_HALT_FILE="$A/halt.json"
TRAIN="$A/sbbin/super-board-merge-train.sh"
CFG="$A/cfg.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["python3 %s/kit/post-fix-gate.py --run-tests --brief"]}\n' "$A" > "$CFG"
git -C "$R" worktree add -q --detach "$W/review" origin/main
reset_a() { rm -f "$A/pfg.log" "$A/merged" "$A/gate.calls" "$A/merge.overlap" "$A/busy" "$A/move-once" "$A/move-always"; }
pfg_n() { [ -f "$A/pfg.log" ] && grep -c -- "$1" "$A/pfg.log" | tr -d ' ' || echo 0; }

# A1 + A3a: một PR; main dời đúng một lần trong verify ⇒ gate 12, verify lại ngoài khoá, merge.
card_branch 1 f1; reset_a; : > "$A/move-once"
( cd "$W/review" && bash "$TRAIN" --config "$CFG" --prs 1 ) >"$A/a1.out" 2>"$A/a1.err"; rc=$?
[ "$rc" -eq 0 ] && grep -q "^train-result: 1 merged$" "$A/a1.out" && ok "A3 base moved once during verify: verified again outside the lock, merged" \
  || fail "A3 move once: exit $rc: $(grep train- "$A/a1.out") $(tail -4 "$A/a1.err")"
grep -q "exit 12\|base moved since the train verified" "$A/a1.err" && ok "  … the gate refused to verify inside the merge lock (exit 12)" || fail "  … no exit-12 line: $(grep -i 'base' "$A/a1.err" | tail -3)"
[ "$(pfg_n .train-scratch-)" = 2 ] && [ "$(pfg_n .merge-scratch-)" = 0 ] && ok "  … two verifies, both in the train scratch, none in the gate" || fail "  … verifies: $(cat "$A/pfg.log" 2>/dev/null)"
grep -q -- "--diff origin/main --scoped" "$A/pfg.log" && ok "A1 verify gets --diff origin/main --scoped" || fail "A1 flags: $(head -1 "$A/pfg.log")"
grep -q "held=1" "$A/pfg.log" && fail "A1 post-fix-gate ran under the heavy-slot wrapper (DEVKIT_SLOT_ADVISORY_HELD=1)" || ok "A1 post-fix-gate called directly (not under the heavy-slot advisory hold)"

# A3b: main dời ở mọi lượt verify ⇒ sau 2 lần chứng minh lại thì base-moved, exit 12, không merge.
card_branch 2 f2; reset_a; : > "$A/move-always"
( cd "$W/review" && bash "$TRAIN" --config "$CFG" --prs 2 ) >"$A/a3.out" 2>"$A/a3.err"; rc=$?
[ "$rc" -eq 12 ] && grep -q "^train-result: 2 base-moved$" "$A/a3.out" && [ ! -s "$A/merged" ] && [ "$(pfg_n .train-scratch-)" = 3 ] \
  && ok "A3 base keeps moving: base-moved after 2 re-proofs (3 verifies), exit 12, nothing merged" \
  || fail "A3 move always: exit $rc verifies=$(pfg_n .train-scratch-): $(grep train- "$A/a3.out") $(tail -3 "$A/a3.err")"
rm -f "$A/move-always"

# A2: verify BUSY ⇒ timeout, không merge.
card_branch 3 f3; reset_a; : > "$A/busy"
( cd "$W/review" && bash "$TRAIN" --config "$CFG" --prs 3 ) >"$A/a2.out" 2>"$A/a2.err"; rc=$?
[ "$rc" -eq 12 ] && grep -q "^train-result: 3 timeout$" "$A/a2.out" && [ ! -s "$A/merged" ] && ok "A2 verify BUSY: timeout, exit 12, nothing merged" \
  || fail "A2 busy: exit $rc: $(grep train- "$A/a2.out") $(tail -3 "$A/a2.err")"
rm -f "$A/busy"

# A4: hai train khác PR song song: merge không chồng, cả hai merged, gate không verify.
card_branch 4 f4; card_branch 5 f5; reset_a
( cd "$W/review" && bash "$TRAIN" --config "$CFG" --prs 4 ) >"$A/a4.out" 2>"$A/a4.err" & T4=$!; KILLS="$KILLS $T4"
( cd "$W/review" && bash "$TRAIN" --config "$CFG" --prs 5 ) >"$A/a5.out" 2>"$A/a5.err" & T5=$!; KILLS="$KILLS $T5"
wait "$T4"; r4=$?; wait "$T5"; r5=$?
[ "$r4" -eq 0 ] && [ "$r5" -eq 0 ] && grep -q "^train-result: 4 merged$" "$A/a4.out" && grep -q "^train-result: 5 merged$" "$A/a5.out" \
  && ok "A4 two trains on different PRs in parallel: both merged" || fail "A4: r4=$r4 r5=$r5: $(grep train- "$A/a4.out" "$A/a5.out") $(tail -2 "$A/a4.err" "$A/a5.err")"
[ ! -s "$A/merge.overlap" ] && ok "  … gh pr merge never ran twice at once (merge lock)" || fail "  … merges overlapped: $(cat "$A/merge.overlap")"
[ "$(pfg_n .merge-scratch-)" = 0 ] && ok "  … and the merge gate verified nothing inside its lock" || fail "  … gate verified: $(grep merge-scratch "$A/pfg.log")"

# A5: file merge=union bị sửa ở CẢ hai phía, origin/main đứng yên. Train dựng biên nhận theo chiều base+head, gate dựng cây head+base:
#     với union thứ tự dòng khác nên cây khác dù base không dời (review Claude #676, P1). Gate thoát 12 ⇒ train thấy base KHÔNG đổi ⇒ gọi
#     lại gate không --require-receipt (gate tự verify như trước #676) ⇒ merged; không bao giờ base-moved lặp mãi.
printf 'u merge=union\n' > "$R/.gitattributes"; echo base > "$R/u"; git -C "$R" add .gitattributes u; git -C "$R" commit -qm attrs; git -C "$R" push -q origin main
card_branch 6 u; printf '{"files":[{"path":"u"}],"labels":[],"body":"","additions":1,"deletions":1,"changedFiles":1}' > "$A/pr6.meta"
git clone -q "$O" "$A/mvu" && git -C "$A/mvu" config user.email t@example.invalid && git -C "$A/mvu" config user.name t \
  && echo main-side > "$A/mvu/u" && git -C "$A/mvu" commit -qam "main touches u" && git -C "$A/mvu" push -q origin HEAD:main
reset_a
( cd "$W/review" && bash "$TRAIN" --config "$CFG" --prs 6 ) >"$A/a6.out" 2>"$A/a6.err"; rc=$?
[ "$rc" -eq 0 ] && grep -q "^train-result: 6 merged$" "$A/a6.out" && ! grep -q "base-moved" "$A/a6.out" \
  && ok "A5 union file changed on both sides, base unchanged: the gate verifies itself, merged (no base-moved loop)" \
  || fail "A5 union: exit $rc: $(grep train- "$A/a6.out") $(grep -E 'exit 12|moved' "$A/a6.err" | tail -3)"

# ════ Phần B: queue thật, train giả ═══════════════════════════════════════════════════════════════════════════════════════════════════
B="$TMP/b"; F="$B/fake"; QR="$B/repo"; Q="$B/qbin"
mkdir -p "$F/labeled" "$Q" "$B/path"
git init -q -b main "$QR"; git -C "$QR" config user.email t@example.invalid; git -C "$QR" config user.name t
printf '.claude/\n' > "$QR/.gitignore"; git -C "$QR" add .gitignore; git -C "$QR" commit -qm init
QC="$QR/.git/super-board"
for f in super-board-merge-queue.sh super-board-github-read.py super-board-approved-head.jq super-board-audit-check.py; do ln -s "$ROOT/.claude/bin/$f" "$Q/$f"; done
QUEUE="$Q/super-board-merge-queue.sh"
# train giả: một PR mỗi lượt; hold-<N> giữ tới khi file biến mất; die-<N> tự SIGKILL; in dòng train-* của PR đó.
cat > "$Q/super-board-merge-train.sh" <<'SH'
#!/usr/bin/env bash
n=""; prev=""; for a in "$@"; do [ "$prev" = --prs ] && n="${a%%:*}"; prev="$a"; done
echo "train $n" >> "$FAKE/calls"; : > "$FAKE/started-$n"
[ ! -e "$FAKE/die-$n" ] || kill -9 $$
i=0; while [ -e "$FAKE/hold-$n" ] && [ "$i" -lt 600 ]; do sleep 0.1; i=$((i + 1)); done
grep -E "^train-(result|detail|red): ${n}( |\$)" "$FAKE/train.out"
exit "$(cat "$FAKE/train.rc.$n" 2>/dev/null || echo 0)"
SH
cat > "$Q/super-board-card.sh" <<'SH'
#!/usr/bin/env bash
while [ "${1#--}" != "$1" ]; do shift 2; done
echo "card $*" >> "$FAKE/writes"
SH
printf 'import os, sys\nopen(os.environ["FAKE"] + "/writes", "a").write("needs-you " + " ".join(sys.argv[1:]) + "\\n")\n' > "$Q/super-board-needs-you.py"
printf 'import os, sys\nopen(os.environ["FAKE"] + "/writes", "a").write("notify " + " ".join(sys.argv[1:]) + "\\n")\n' > "$Q/super-board-notify.py"
chmod +x "$Q"/*.sh
cat > "$B/path/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
F = os.environ['FAKE']; a = sys.argv[1:]
def opt(name):
    return a[a.index(name) + 1] if name in a else None
def num():
    return next(x for x in a[2:] if x.isdigit())
def w(line):
    open(F + '/writes', 'a').write(line + '\n')
if a[:2] == ['pr', 'list']:
    st = (opt('--state') or 'open').upper()
    prs = [p for p in json.load(open(F + '/prs.json')) if st == ('MERGED' if os.path.exists(f"{F}/merged-{p['number']}") else 'OPEN')
           and os.path.exists(f"{F}/labeled/{p['number']}")]
    print(json.dumps(prs))
elif a[:2] == ['pr', 'view'] and opt('--json') == 'comments':
    print(json.dumps({'comments': [{'authorAssociation': 'OWNER', 'body': 'approved-head:' + open(f'{F}/head-{num()}').read().strip()}]}))
elif a[:2] == ['pr', 'view'] and 'state' in (opt('--json') or ''):
    n = num(); m = f'{F}/merged-{n}'
    print(json.dumps({'state': 'MERGED', 'mergeCommit': {'oid': 'c' * 40}, 'headRefOid': 'a' * 40} if os.path.exists(m)
                     else {'state': 'OPEN', 'mergeCommit': None, 'headRefOid': 'a' * 40}))
elif a[0] == 'api' and '/timeline' in a[1]:
    n = a[1].split('/issues/')[1].split('/')[0]
    print(json.dumps([[{'event': 'labeled', 'label': {'name': 'merge-queue'}, 'created_at': '2026-11-01T00:0%s:00Z' % n}]]))
elif a[:2] == ['issue', 'view']:
    print(json.dumps({'number': int(num()), 'title': 'card', 'body': '', 'state': 'OPEN', 'labels': []}))
elif a[:2] == ['pr', 'edit']:
    n = num(); w(f'pr-unlabel {n} ' + str(opt('--remove-label')))
    if os.path.exists(f'{F}/labeled/{n}'):
        os.remove(f'{F}/labeled/{n}')
elif a[:2] in (['pr', 'comment'], ['issue', 'comment'], ['issue', 'close'], ['issue', 'edit'], ['label', 'create']):
    w(' '.join(a[:3]))
else:
    sys.stderr.write('fake gh: unexpected ' + ' '.join(a) + '\n'); sys.exit(1)
PY
chmod +x "$B/path/gh"
qenv() { PATH="$B/path:$PATH" FAKE="$F" SB_GITHUB_HALT_FILE="$B/halt.json" "$@"; }
sha() { printf '%040d' "$1" | tr 0 a; }
PRS=""
qpr() {   # qpr <N>: PR mở, nhánh issue-1<N>-x, nhãn merge-queue, approved-head = sha(N)
  PRS="${PRS}${PRS:+,}{\"number\":$1,\"headRefName\":\"issue-1$1-x\",\"headRefOid\":\"$(sha "$1")\",\"isDraft\":false,\"closingIssuesReferences\":[]}"
  printf '[%s]\n' "$PRS" > "$F/prs.json"; : > "$F/labeled/$1"; sha "$1" > "$F/head-$1"
}
qcfg() { printf '{"base_branch":"main","repo":{"path":".","remote":"https://github.com/o/r"},"worker_backend":"claude-p","rebuild_cap":2,"verify_commands":["true"],"merge_queue":{"enabled":true%s}}\n' "${1:-}" > "$B/cfg.json"; }
qrun() { local t0 t1; t0=$(date +%s); ( cd "$QR" && qenv bash "$QUEUE" --config "$B/cfg.json" ) >"$B/q.out" 2>"$B/q.err"; QRC=$?; t1=$(date +%s); QSECS=$((t1 - t0)); }
wait_file() { local i=0; while [ ! -e "$1" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done; [ -e "$1" ]; }
settle() {   # chờ mọi train nền của inflight xong
  local i=0 busy pid dir
  while [ "$i" -lt 300 ]; do
    busy=0; [ -s "$QC/merge-queue.inflight" ] && while read -r _ _ _ _ pid dir; do [ -f "$dir/rc" ] || ! kill -0 "$pid" 2>/dev/null || busy=1; done < "$QC/merge-queue.inflight"
    [ "$busy" = 0 ] && return 0; sleep 0.1; i=$((i + 1))
  done
  fail "settle: background trains still running after 30 s: $(tr '\n' '|' < "$QC/merge-queue.inflight")"; return 1
}
: > "$F/writes"; : > "$F/calls"
printf 'train-result: 1 merged\ntrain-result: 2 merged\ntrain-result: 5 base-moved\n' > "$F/train.out"; echo 12 > "$F/train.rc.5"

# B1: PR1 giữ train; queue lượt 1 (nền: bản cũ giữ khoá tới khi train xong) phóng train PR1.
qcfg; qpr 1; : > "$F/hold-1"
( cd "$QR" && qenv bash "$QUEUE" --config "$B/cfg.json" ) >"$B/q1.out" 2>"$B/q1.err" & Q1=$!; KILLS="$KILLS $Q1"
wait_file "$F/started-1" && ok "B1 PR1's train started" || fail "B1 PR1's train never started: $(cat "$B/q1.err")"
qpr 2
qrun
grep -q "PR #2: train started" "$B/q.err" && wait_file "$F/started-2" && ok "B1 PR2 labelled while PR1's train runs: its own train starts at once" || fail "B1 PR2 not started: rc=$QRC $(cat "$B/q.err")"
grep -qi "holds\|another merge-queue run" "$B/q.err" && fail "B1 the second run was held by the first run's lock" || ok "  … the queue lock was not held while PR1's train verifies"
[ "$QSECS" -lt 5 ] && ok "  … the queue run exited in ${QSECS}s without waiting for any train" || fail "  … queue run took ${QSECS}s"
[ "$(grep -c '^train 1$' "$F/calls")" = 1 ] && ok "  … PR1's running train is not started twice" || fail "  … PR1 started $(grep -c '^train 1$' "$F/calls") times"
touch "$F/merged-2"; D2=$(awk '$1 == 2 {print $6}' "$QC/merge-queue.inflight")
[ -n "$D2" ] && wait_file "$D2/rc" && ok "  … PR2's train finished while PR1's is held" || fail "  … PR2's train did not finish (dir=${D2:-<none>})"
qrun
grep -q "pr-unlabel 2 merge-queue" "$F/writes" && grep -q "card move 12 Done" "$F/writes" && [ -e "$F/labeled/1" ] && [ ! -e "$F/merged-1" ] \
  && ok "B1 PR2 merged and routed (card Done) while PR1's train is still running" || fail "B1 PR2 route: $(cat "$F/writes") err=$(tail -3 "$B/q.err")"

# B2: max_trains=1 với PR1 còn chạy: PR3 không phóng, không tính lần thử.
qcfg ',"max_trains":1'; qpr 3
qrun
grep -q "^train 3$" "$F/calls" && fail "B2 PR3 started over max_trains=1" || ok "B2 max_trains=1 and PR1 running: PR3 not started"
grep -q "^3 " "$QC/merge-queue.attempts" 2>/dev/null && fail "  … PR3 got an attempt counted" || ok "  … no attempt counted for PR3"
rm -f "$F/hold-1"; touch "$F/merged-1"; settle; qcfg; qrun; settle; qrun

# B3: train chết vì tín hiệu ⇒ lượt sau tính một lần thử; base-moved ⇒ giữ nhãn, không tính lần thử.
qpr 4; : > "$F/die-4"; qpr 5
qrun; settle; qrun
grep -q "^4 $(sha 4) 1 " "$QC/merge-queue.attempts" 2>/dev/null && grep -q "PR #4: its train .*ended without an exit code" "$B/q.err" \
  && ok "B3 a train killed by a signal (no rc): one attempt counted (train died)" || fail "B3 killed train: att=$(cat "$QC/merge-queue.attempts" 2>/dev/null) err=$(tail -3 "$B/q.err")"
grep -q "^5 " "$QC/merge-queue.attempts" 2>/dev/null && fail "B3 base-moved counted an attempt" || ok "B3 base-moved: no attempt counted"
[ -e "$F/labeled/5" ] && ! grep -q "pr-comment 5" "$F/writes" && ok "  … label kept, no comment" || fail "  … PR5 unlabelled or commented: $(grep ' 5' "$F/writes")"

# B5: như launchd (lịch super-board-queue-schedule.sh không đặt AbandonProcessGroup): queue thoát rồi cả process group của job bị
#     TERM. Train nền phải sống tiếp (session riêng) và ghi rc, không thành "train died" mỗi phút (OCR #676, critical).
printf 'train-result: 6 merged\n' >> "$F/train.out"; qpr 6; : > "$F/hold-6"
( cd "$QR" && qenv python3 -c 'import os, subprocess, sys
os.setsid(); open(sys.argv[1], "w").write(str(os.getpgid(0)))
sys.exit(subprocess.run(sys.argv[2:]).returncode)' "$B/pgid" bash "$QUEUE" --config "$B/cfg.json" ) >"$B/q6.out" 2>"$B/q6.err"
wait_file "$F/started-6" || fail "B5 PR6's train never started: $(cat "$B/q6.err")"
kill -TERM -- "-$(cat "$B/pgid")" 2>/dev/null; sleep 0.3
rm -f "$F/hold-6"; settle
D6=$(awk '$1 == 6 {print $6}' "$QC/merge-queue.inflight")
[ -n "$D6" ] && [ -f "$D6/rc" ] && ok "B5 the job's process group is killed after the queue exits: the background train survives and writes its rc" \
  || fail "B5 train killed with the job's process group: dir=${D6:-<none>} $(cat "$D6/launch.log" 2>/dev/null)"

# B4: status gộp state của hai train sống.
SB="$B/sbstate/super-board"; mkdir -p "$SB"
sleep 30 & S2=$!; KILLS="$KILLS $S2"
printf 'pid %s\nstarted_at 100\nstep gate\npr 7 %s issue-17-x\n' "$$" "$(sha 7)" > "$SB/merge-train.$$.state"
printf 'pid %s\nstarted_at 50\nstep merge\npr 8 %s issue-18-x\n' "$S2" "$(sha 8)" > "$SB/merge-train.$S2.state"
out=$(python3 - "$ROOT/.claude/bin/super-board-status.py" "$B/sbstate" <<'PY'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("sbs", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
t = m.read_merge_train(Path(sys.argv[2]), 200.0)
print(t["step"], t["started_at"], ",".join(str(x["pr"]) for x in t["prs"]), ",".join(str(c) for c in t["cards"]))
PY
)
[ "$out" = "merge 50 8,7 18,17" ] && ok "B4 status merges two live trains (oldest first, step merge, both cards)" || fail "B4 status: [$out]"
kill "$S2" 2>/dev/null

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_queue_parallel: PASS"; exit 0; } || { echo "test_merge_queue_parallel: FAIL ($FAILS)"; exit 1; }
