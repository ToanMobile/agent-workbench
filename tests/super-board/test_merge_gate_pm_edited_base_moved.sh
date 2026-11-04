#!/usr/bin/env bash
# 04/11: duyệt test sửa tra thẳng biên bản antigravity-pm (không comment edited-tests). Merge gate #959 bị exit 2 "edited-test review is
# stale before fast-forward" chỉ vì main tiến (#972) mà không chạm file test. Với duyệt từ biên bản PM, verify chạy TRONG khoá trên base
# hiện tại và post-fix-gate audit_covers tự kiểm main không đổi file test kể từ audit, nên base dời không làm hỏng duyệt:
#  G1 merge gate: PR sửa tests/t.sh, audit PM tại head PR, main tiến không chạm test -> verify trong khoá, merge (code cũ: exit 2).
#  G2 merge train: như G1 -> không gate-exit-2 trước chuỗi, merge (code cũ: exit 2).
#  G3 đối chứng: duyệt bằng comment edited-tests (đường cũ) + main tiến -> vẫn exit 2 stale như #643.
#  G4 duyệt từ biên bản PM nhưng verify_commands không chạy post-fix-gate -> vẫn exit 2 (không ai kiểm lại trên base mới).
# Chạy offline với gh giả. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
TRAIN="$ROOT/.claude/bin/super-board-merge-train.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-pm-stale.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm"
export DEVKIT_PM_HOME_TEST=1
unset DEVKIT_AGENT_ID CLAUDECODE CLAUDE_CODE_SESSION_ID GROK_SESSION_ID GROK_WORKSPACE_ROOT GROK_HOOK_EVENT
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

O="$TMP/origin.git"; R="$TMP/repo"; W="$R/.claude/worktrees"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid && git -C "$R" config user.name t && git -C "$R" config commit.gpgsign false
mkdir -p "$R/tests" && printf '#!/bin/sh\ntrue\n' > "$R/tests/t.sh" && printf '/.claude/worktrees/\n' > "$R/.gitignore" && echo a > "$R/a"
git -C "$R" add .gitignore a tests/t.sh && git -C "$R" commit -qm init
git -C "$R" remote add origin "$O" && git -C "$R" push -q origin main
mkdir -p "$W" && git -C "$R" worktree add -q --detach "$W/review" origin/main
RP="$(cd "$R" && pwd -P)"

pm_grok() {   # pm_grok <task-id> <auditedHead>: audit pass do PM tự chạy grok
  mkdir -p "$TMP/pm/projects/p-$1/tasks/$1"
  printf '{"id":"%s","project":"%s","dispatches":[{"kind":"audit","agent":"grok","at":"2026-11-04T00:00:00Z"}],"verdicts":{"audit":{"verdict":"pass","round":1,"reviewer":"grok","notes":"ok","auditedHead":"%s"}}}\n' \
    "$1" "$RP" "$2" > "$TMP/pm/projects/p-$1/tasks/$1/task.json"
}
card() {   # card <n> <comment 0|1>: nhánh issue-<n>-x sửa tests/t.sh (test đã có), đẩy lên origin, biên bản PM tại head
  local n="$1" sha
  git -C "$R" fetch -q origin
  git -C "$R" worktree add -q -b "issue-$n-x" "$W/issue-$n-build" origin/main
  printf '#!/bin/sh\ntrue # %s\n' "$n" > "$W/issue-$n-build/tests/t.sh"
  git -C "$W/issue-$n-build" commit -qam "card $n sửa test"
  git -C "$R" push -q origin "issue-$n-x"
  sha=$(git -C "$R" rev-parse "issue-$n-x"); echo "$sha" > "$TMP/pr$n.head"
  git -C "$R" diff origin/main "issue-$n-x" > "$TMP/pr$n.diff"
  pm_grok "T300$n-card" "$sha"
  python3 - "$TMP/pr$n.meta" "$sha" "$2" "T300$n-card" "$W/issue-$n-build/tests/t.sh" <<'PY'
import hashlib, json, sys
dest, sha, comment, task, test = sys.argv[1:6]
meta = {"files": [{"path": "tests/t.sh"}], "labels": [], "body": "", "additions": 1, "deletions": 1, "changedFiles": 1,
        "author": {"login": "builder"}, "comments": []}
if comment == "1":
    dig = hashlib.sha256(open(test, "rb").read()).hexdigest()
    meta["comments"] = [{"authorAssociation": "OWNER", "body":
        "approved-head:%s\napproved-by: {\"reviewer\":\"grok\",\"builder\":\"claude-lane\",\"task_id\":\"%s\",\"gate_receipt\":\"fp\"}\n"
        "edited-tests: [{\"path\":\"tests/t.sh\",\"sha256\":\"%s\",\"reviewer\":\"grok\",\"author\":\"claude-lane\",\"task_id\":\"%s\",\"reason\":\"r\"}]\n"
        % (sha, task, dig, task)}]
json.dump(meta, open(dest, "w"))
PY
}
advance_main() {   # main tiến một commit KHÔNG chạm tests/t.sh
  git -C "$R" fetch -q origin
  git -C "$R" worktree add -q --detach "$W/adv" origin/main
  echo adv >> "$W/adv/a" && git -C "$W/adv" commit -qam "main moves" && git -C "$W/adv" push -q origin HEAD:main
  git -C "$R" worktree remove --force "$W/adv"
}

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *"--json labels,files,comments"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr view "*"title"*) printf 'card\n' ;;
  *" pr view "*"body"*) printf '\n' ;;
  *" pr comment "*) exit 0 ;;
  *" pr merge "*)
    git -C "$FAKE_REPO" fetch -q origin main "issue-$n-x"
    tree=$(git -C "$FAKE_REPO" merge-tree --write-tree origin/main "$head") || exit 1
    c=$(git -C "$FAKE_REPO" commit-tree "$tree" -p origin/main -m "squash #$n")
    git -C "$FAKE_REPO" push -q origin "$c:refs/heads/main" && echo "$n" >> "$FAKE_DIR/merged" && echo "merged #$n" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
. "$ROOT/tests/super-board/lib/fake_ci_checks.sh"; sb_ci_checks_fixture "$TMP/bin"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" FAKE_REPO="$R"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_NOTIFY_SKIP=1
unset SB_MERGE_CALLER SB_MERGE_QUEUE
export GH_TOKEN=fake-token
# verify giả mang tên post-fix-gate: merge gate chỉ bỏ exit 2 "stale" cho duyệt từ biên bản PM khi verify chạy gate (nơi audit_covers
# kiểm main không đổi file test); G4 dùng verify khác -> vẫn exit 2.
mkdir -p "$TMP/kit/bin" && printf '#!/bin/sh\necho x >> "%s/verify.count"\n' "$TMP" > "$TMP/kit/bin/post-fix-gate.py"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["sh %s/kit/bin/post-fix-gate.py --run-tests --scoped"]}\n' "$TMP" > "$TMP/cfg.json"
printf '#!/bin/sh\necho x >> "%s/verify.count"\n' "$TMP" > "$TMP/verify.sh"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["sh %s/verify.sh"]}\n' "$TMP" > "$TMP/cfg-nogate.json"
merged() { sort "$TMP/merged" 2>/dev/null | tr '\n' ' '; }
reset_run() { rm -f "$TMP/verify.count" "$TMP/merged" "$TMP/halt.json"; }

# G1. merge gate, duyệt chỉ từ biên bản PM, main tiến không chạm test
card 1 0; advance_main; reset_run
( cd "$W/review" && bash "$GATE" --config "$TMP/cfg.json" --pr 1 --expect-head "$(cat "$TMP/pr1.head")" --subject card --lock-timeout 20 ) >"$TMP/g1.log" 2>&1
rc=$?
if [ "$rc" -eq 0 ] && [ "$(merged)" = "1 " ] && grep -q "verifying inside the merge lock" "$TMP/g1.log" && ! grep -q "stale before fast-forward" "$TMP/g1.log"; then
  ok "G1: biên bản PM, main tiến không chạm test -> verify trong khoá, merge"
else fail "G1: exit $rc merged='$(merged)': $(tail -6 "$TMP/g1.log" | tr '\n' ' ')"; fi

# G2. merge train, như G1
card 2 0; advance_main; reset_run
( cd "$W/review" && bash "$TRAIN" --config "$TMP/cfg.json" --prs 2 --lock-timeout 20 ) >"$TMP/g2.log" 2>&1
rc=$?
if [ "$rc" -eq 0 ] && [ "$(merged)" = "2 " ] && ! grep -q "gate-exit-2" "$TMP/g2.log"; then ok "G2: train, biên bản PM, main tiến -> merge"
else fail "G2: exit $rc merged='$(merged)': $(grep -E 'train-|stale' "$TMP/g2.log" | tail -4 | tr '\n' ' ')"; fi

# G3. đối chứng: duyệt bằng comment edited-tests (đường #643) + main tiến -> vẫn exit 2 stale
card 3 1; advance_main; reset_run
( cd "$W/review" && bash "$GATE" --config "$TMP/cfg.json" --pr 3 --expect-head "$(cat "$TMP/pr3.head")" --subject card --lock-timeout 20 ) >"$TMP/g3.log" 2>&1
rc=$?
if [ "$rc" -eq 2 ] && grep -q "edited-test review is stale before fast-forward" "$TMP/g3.log"; then ok "G3: comment edited-tests + main tiến -> exit 2 như cũ"
else fail "G3: exit $rc: $(tail -6 "$TMP/g3.log" | tr '\n' ' ')"; fi

# G4. biên bản PM, main tiến, nhưng verify KHÔNG chạy post-fix-gate (không ai kiểm lại duyệt trên base mới) -> exit 2 như comment
card 4 0; advance_main; reset_run
( cd "$W/review" && bash "$GATE" --config "$TMP/cfg-nogate.json" --pr 4 --expect-head "$(cat "$TMP/pr4.head")" --subject card --lock-timeout 20 ) >"$TMP/g4.log" 2>&1
rc=$?
if [ "$rc" -eq 2 ] && grep -q "edited-test review is stale before fast-forward" "$TMP/g4.log"; then ok "G4: verify không chạy gate -> vẫn exit 2"
else fail "G4: exit $rc: $(tail -6 "$TMP/g4.log" | tr '\n' ' ')"; fi

[ "$FAILS" -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }
