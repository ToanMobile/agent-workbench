#!/usr/bin/env bash
# 04/11 (PR #977): PR sửa test đã có, duyệt tra thẳng biên bản antigravity-pm (EDITED_SRC=pm). Main tiến chạm ma trận (merge=devkit-matrix,
# driver chỉ có ở local) ⇒ GitHub báo CONFLICTING. Code cũ: sync_candidate từ chối MỌI PR có duyệt test sửa ⇒ exit 14 mỗi lần main tiến,
# agent tự gộp main rồi push lại. Duyệt từ biên bản PM không gắn head khi verify chạy post-fix-gate (audit_covers nhận merge(X, base) vì
# auditedHead X nằm trên chuỗi first-parent; verify chạy TRONG khoá trên cây gộp) nên gate được tự đồng bộ nhánh PR như PR không sửa test.
#   P1 duyệt pm + CONFLICTING chỉ vì file có driver + verify chạy post-fix-gate ⇒ đẩy merge commit Y (cha X, B) lên nhánh PR TRONG khoá,
#      biên nhận approved-merge-heads/Y = X, verify chạy trên Y, merge --match-head-commit Y, exit 0 (code cũ: exit 14)
#   P2 cùng kịch bản, duyệt bằng comment edited-tests (true, #643 gắn head) ⇒ vẫn exit 14, không đẩy, không verify
#   P3 duyệt pm nhưng verify không chạy post-fix-gate ⇒ vẫn exit 14, không đẩy, không verify
#   P4 main tiến 3 lần trong lúc PR chờ (verify đỏ 2 lượt đầu để PR còn mở) ⇒ không lượt nào exit 14 (code cũ: 3 lần exit 14)
# gh giả đọc head và mergeable từ remote trần (CONFLICTING khi main chưa là tổ tiên của nhánh PR). Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
export SB_NOTIFY_SKIP=1
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
ETA="$ROOT/.claude/bin/super-board-install-edited-test-approval.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-autosync-pm.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$TMP/xdg"
export HOME="$TMP/home"; mkdir -p "$HOME"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm" DEVKIT_PM_HOME_TEST=1
unset DEVKIT_AGENT_ID CLAUDECODE CLAUDE_CODE_SESSION_ID GROK_SESSION_ID GROK_WORKSPACE_ROOT GROK_HOOK_EVENT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
export SB_GITHUB_RETRY_DELAY=0 SB_MERGEABLE_POLL_S=0 GH_TOKEN=fake-token
unset SB_MERGE_QUEUE SB_MERGE_CALLER SB_BOARD_WORKER SB_MERGE_LOAD_WAIT_S SB_MERGE_LOAD_MAX

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
O="$FAKE_DIR/origin.git"
tip() { git -C "$O" rev-parse refs/heads/issue-61-x 2>/dev/null || echo 0000000000000000000000000000000000000000; }
conflicting() { ! git -C "$O" merge-base --is-ancestor refs/heads/main "$(tip)" 2>/dev/null; }
case " $* " in
  *" pr view "*"--json mergeable"*) if conflicting; then echo CONFLICTING; else echo MERGEABLE; fi ;;
  *" pr view "*"headRefName,headRefOid"*) echo "issue-61-x $(tip)" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$(tip)" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr61.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr61.diff" ;;
  *" pr view "*"title"*) printf 'card\n' ;;
  *" pr view "*"body"*) printf '\n' ;;
  *" pr comment "*) exit 0 ;;
  *" pr merge "*)
    echo "$*" > "$FAKE_DIR/merge-args"
    conflicting && { echo "GraphQL: Pull Request has merge conflicts (mergePullRequest)" >&2; exit 1; }
    case " $* " in *" --match-head-commit $(tip) "*) echo "merged #61" ;; *) echo "GraphQL: Head branch was modified" >&2; exit 1 ;; esac ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
. "$ROOT/tests/super-board/lib/fake_ci_checks.sh"; sb_ci_checks_fixture "$TMP/bin"
export PATH="$TMP/bin:$PATH"

# setup <tên> <comment 0|1>: nhánh PR sửa tests/t.sh (test đã có) và nối đuôi m.txt (merge=devkit-matrix); biên bản PM (grok audit pass)
# tại head X; main tiến chỉ nối đuôi m.txt ⇒ GitHub CONFLICTING, gộp local sạch. comment=1: thêm comment approved-head/edited-tests (#643).
setup() {
  local name="$1" comment="$2" rp
  D="$TMP/$name"; mkdir -p "$D"
  export FAKE_DIR="$D" SB_GITHUB_HALT_FILE="$D/halt.json"
  O="$D/origin.git"; R="$D/repo"; WT="$D/repo/.claude/worktrees/review-x"
  git init -q --bare -b main "$O"
  git init -q -b main "$R"
  git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t; git -C "$R" config commit.gpgsign false
  git -C "$R" config merge.devkit-matrix.driver 'git merge-file --union -q %A %O %B'
  printf '/.claude/worktrees/\n' > "$R/.gitignore"
  printf 'm.txt merge=devkit-matrix\n' > "$R/.gitattributes"
  mkdir -p "$R/tests"; printf '#!/bin/sh\ntrue\n' > "$R/tests/t.sh"
  echo m0 > "$R/m.txt"; echo a > "$R/a"
  git -C "$R" add -A; git -C "$R" commit -qm init
  git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
  git -C "$R" branch -q --no-track issue-61-x main
  git -C "$R" worktree add -q "$WT" issue-61-x
  echo m-pr >> "$WT/m.txt"; printf '#!/bin/sh\ntrue # 61\n' > "$WT/tests/t.sh"
  git -C "$WT" commit -qam "card61 sửa test"
  git -C "$R" push -q origin issue-61-x
  X=$(git -C "$R" rev-parse issue-61-x)
  git -C "$R" diff "$X~1" "$X" > "$D/pr61.diff"
  rp=$(cd "$R" && pwd -P)
  mkdir -p "$TMP/pm/projects/p-$name/tasks/T6100-$name"
  printf '{"id":"T6100-%s","project":"%s","dispatches":[{"kind":"audit","agent":"grok","at":"2026-11-04T00:00:00Z"}],"verdicts":{"audit":{"verdict":"pass","round":1,"reviewer":"grok","notes":"ok","auditedHead":"%s"}}}\n' \
    "$name" "$rp" "$X" > "$TMP/pm/projects/p-$name/tasks/T6100-$name/task.json"
  git -C "$R" diff --numstat "$X~1" "$X" | python3 -c 'import hashlib,json,sys
sha, comment, task, test = sys.argv[1:5]
rows=[l.split("\t") for l in sys.stdin.read().splitlines() if l]
meta={"files":[{"path":r[2]} for r in rows],"labels":[],"body":"","additions":sum(int(r[0]) for r in rows),
  "deletions":sum(int(r[1]) for r in rows),"changedFiles":len(rows),"author":{"login":"builder"},"comments":[]}
if comment == "1":
    dig = hashlib.sha256(open(test, "rb").read()).hexdigest()
    meta["comments"] = [{"authorAssociation": "OWNER", "body":
        "approved-head:%s\napproved-by: {\"reviewer\":\"grok\",\"builder\":\"claude-lane\",\"task_id\":\"%s\",\"gate_receipt\":\"fp\"}\n"
        "edited-tests: [{\"path\":\"tests/t.sh\",\"sha256\":\"%s\",\"reviewer\":\"grok\",\"author\":\"claude-lane\",\"task_id\":\"%s\",\"reason\":\"r\"}]\n"
        % (sha, task, dig, task)}]
print(json.dumps(meta))' "$X" "$comment" "T6100-$name" "$WT/tests/t.sh" > "$D/pr61.meta"
  advance_main
  B=$(git -C "$R" rev-parse main)
  # verify giả mang tên post-fix-gate (sb_verify_runs_gate nhận token post-fix-gate.py); fail-left: số lượt đỏ còn lại.
  mkdir -p "$D/kit/bin"
  cat > "$D/kit/bin/post-fix-gate.py" <<SH
#!/bin/sh
git rev-parse HEAD > "$D/verify-head"; echo x >> "$D/verify.count"
n=\$(cat "$D/fail-left" 2>/dev/null || echo 0)
if [ "\$n" -gt 0 ]; then echo \$((n - 1)) > "$D/fail-left"; exit 1; fi
exit 0
SH
  cp "$D/kit/bin/post-fix-gate.py" "$D/verify.sh"
  printf '{"base_branch":"main","repo":{"path":".","remote":"https://github.com/o/r"},"verify_commands":["sh %s/kit/bin/post-fix-gate.py --run-tests --scoped"]}\n' "$D" > "$D/cfg.json"
  printf '{"base_branch":"main","repo":{"path":".","remote":"https://github.com/o/r"},"verify_commands":["sh %s/verify.sh"]}\n' "$D" > "$D/cfg-nogate.json"
}
advance_main() {   # main tiến một commit chỉ nối đuôi m.txt (không chạm tests/t.sh)
  echo "m-main-$(date +%s%N)-$RANDOM" >> "$R/m.txt"
  git -C "$R" commit -qam main-moves; git -C "$R" push -q origin main
}
# gate <cfg> [cờ…]: chạy gate từ worktree; RC, ORIGIN_HEAD.
gate() {
  local cfg="$1"; shift
  ( cd "$WT" && bash "$GATE" --config "$cfg" --pr 61 --subject card --lock-timeout 20 "$@" ) >>"$D/gate.log" 2>&1; RC=$?
  ORIGIN_HEAD=$(git -C "$O" rev-parse issue-61-x)
}
eta_word() { bash "$ETA" --has-edited-tests "$D/pr61.meta" "$X" --top "$WT" --base origin/main 2>/dev/null; }

# P1) duyệt pm, verify chạy post-fix-gate: đồng bộ trong khoá, verify trên Y, merge Y
setup p1 0
W1=$(eta_word)
[ "$W1" = pm ] && ok "P1: fixture: --has-edited-tests prints pm" || fail "P1: fixture: --has-edited-tests prints '$W1', want pm"
gate "$D/cfg.json" --expect-head "$X"
N="$ORIGIN_HEAD"
[ "$RC" -eq 0 ] && ok "P1: pm approval + matrix-only CONFLICTING: gate exit 0" \
  || fail "P1: gate exit $RC, want 0: $(grep 'merge-gate' "$D/gate.log" | tail -4 | tr '\n' ' ')"
[ "$(git -C "$O" rev-list --parents -n 1 "$N")" = "$N $X $B" ] \
  && ok "P1: PR branch on origin is one merge commit on the reviewed head (parents ${X:0:8} + ${B:0:8})" \
  || fail "P1: origin issue-61-x ${N:0:8} parents: $(git -C "$O" rev-list --parents -n 1 "$N")"
[ "$(cat "$R/.git/super-board/approved-merge-heads/$N" 2>/dev/null)" = "$X" ] && ok "P1: receipt approved-merge-heads/<Y> = X" \
  || fail "P1: receipt missing or wrong"
[ "$(cat "$D/verify-head" 2>/dev/null)" = "$N" ] && ok "P1: verify ran on the pushed merge commit" \
  || fail "P1: verify head $(cat "$D/verify-head" 2>/dev/null || echo none), want ${N:0:8}"
grep -q -- "--match-head-commit $N" "$D/merge-args" 2>/dev/null && ok "P1: merged with --match-head-commit = Y" \
  || fail "P1: merge args: $(cat "$D/merge-args" 2>/dev/null || echo 'gh pr merge not called')"
L_LOCK=$(grep -n 'verifying inside the merge lock' "$D/gate.log" | head -1 | cut -d: -f1)
L_PUSH=$(grep -n "pushed issue-61-x: $X -> $N" "$D/gate.log" | head -1 | cut -d: -f1)
[ -n "$L_LOCK" ] && [ -n "$L_PUSH" ] && [ "$L_LOCK" -lt "$L_PUSH" ] && ok "P1: lock taken (edited tests) before the sync push" \
  || fail "P1: lock line ${L_LOCK:-none}, push line ${L_PUSH:-none}"
grep -q 'stale before fast-forward' "$D/gate.log" && fail "P1: exit-2 stale message in the log" || ok "P1: no stale-review message"

# P2) duyệt bằng comment edited-tests (#643, gắn head): exit 14 như cũ
setup p2 1
W2=$(eta_word)
[ "$W2" = true ] && ok "P2: fixture: --has-edited-tests prints true" || fail "P2: fixture: --has-edited-tests prints '$W2', want true"
gate "$D/cfg.json" --expect-head "$X"
[ "$RC" -eq 14 ] && [ "$ORIGIN_HEAD" = "$X" ] && [ ! -e "$D/verify.count" ] && [ ! -e "$D/merge-args" ] \
  && ok "P2: comment approval: exit 14, nothing pushed, no verify, no merge" \
  || fail "P2: gate exit $RC, origin ${ORIGIN_HEAD:0:8} (want ${X:0:8}): $(grep 'merge-gate' "$D/gate.log" | tail -3 | tr '\n' ' ')"
grep -q 'not syncing issue-61-x itself: .*edited-test approval' "$D/gate.log" && ok "P2: log names the edited-test approval" \
  || fail "P2: reason line missing: $(grep 'not syncing' "$D/gate.log")"

# P3) duyệt pm, verify KHÔNG chạy post-fix-gate: exit 14 như cũ
setup p3 0
W3=$(eta_word)
[ "$W3" = pm ] && ok "P3: fixture: --has-edited-tests prints pm" || fail "P3: fixture: --has-edited-tests prints '$W3', want pm"
gate "$D/cfg-nogate.json" --expect-head "$X"
[ "$RC" -eq 14 ] && [ "$ORIGIN_HEAD" = "$X" ] && [ ! -e "$D/verify.count" ] && [ ! -e "$D/merge-args" ] \
  && ok "P3: pm approval, verify without post-fix-gate: exit 14, nothing pushed, no verify" \
  || fail "P3: gate exit $RC, origin ${ORIGIN_HEAD:0:8} (want ${X:0:8}): $(grep 'merge-gate' "$D/gate.log" | tail -3 | tr '\n' ' ')"
grep -q 'not syncing issue-61-x itself: .*edited-test approval' "$D/gate.log" && ok "P3: log names the edited-test approval" \
  || fail "P3: reason line missing: $(grep 'not syncing' "$D/gate.log")"

# P4) main tiến 3 lần trong lúc PR chờ (2 lượt verify đỏ đầu giữ PR mở): không lượt nào exit 14, lượt 3 merge
setup p4 0; echo 2 > "$D/fail-left"
RCS=""
for i in 1 2 3; do
  [ "$i" -eq 1 ] || advance_main
  gate "$D/cfg.json" --expect-head "$X"; RCS="$RCS $RC"
done
N14=$(printf '%s\n' $RCS | grep -c '^14$')
echo "P4: exits:$RCS (exit 14: $N14)"
[ "$N14" -eq 0 ] && [ "$RCS" = " 11 11 0" ] && grep -q -- "--match-head-commit $ORIGIN_HEAD" "$D/merge-args" 2>/dev/null \
  && ok "P4: main moved 3 times while the PR waited: no exit 14 (11 11 0), merged the gate's last sync head" \
  || fail "P4: exits$RCS, want 11 11 0: $(grep 'merge-gate' "$D/gate.log" | tail -3 | tr '\n' ' ')"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_autosync_pm_approval: PASS"; exit 0; } || { echo "test_merge_gate_autosync_pm_approval: FAIL ($FAILS)"; exit 1; }
