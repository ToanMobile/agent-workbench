#!/usr/bin/env bash
# #1000 mục 5: biên nhận train (--train-receipt) khớp cây thì gate bỏ verify (TRAIN_PROVED) — kể cả khi duyệt test sửa đến từ biên bản
# antigravity-pm (pm), thứ biên nhận không khoá: lượt grok sau cùng head có thể đã REVISE sau khi train verify. Như biên nhận cây (G6),
# với pm / pm-unknown gate phải verify lại (post-fix-gate đọc lại biên bản).
#  R1 pm + biên nhận train khớp cây -> verify chạy (1 lần), log nói không dùng biên nhận train (code cũ: 0 lần, "merge train already proved").
#  R2 đối chứng: duyệt bằng comment edited-tests (true) + cùng biên nhận -> verify bỏ qua như cũ (0 lần).
#  R3 pm + --require-receipt + biên nhận khớp -> không thoát 12 (base không dời), verify chạy trong gate (1 lần).
# Offline, gh giả, git thật. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-train-rcpt-pm.XXXXXX")"
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

card() {   # card <n> <comment 0|1>: nhánh issue-<n>-x sửa tests/t.sh, biên bản PM (grok pass) tại head, biên nhận train = cây của head
  local n="$1" sha
  git -C "$R" fetch -q origin
  git -C "$R" worktree add -q -b "issue-$n-x" "$W/issue-$n-build" origin/main
  printf '#!/bin/sh\ntrue # %s\n' "$n" > "$W/issue-$n-build/tests/t.sh"
  git -C "$W/issue-$n-build" commit -qam "card $n sửa test"
  git -C "$R" push -q origin "issue-$n-x"
  sha=$(git -C "$R" rev-parse "issue-$n-x"); echo "$sha" > "$TMP/pr$n.head"
  git -C "$R" diff origin/main "issue-$n-x" > "$TMP/pr$n.diff"
  echo "$sha $(git -C "$R" rev-parse "$sha^{tree}")" > "$TMP/receipt$n"
  mkdir -p "$TMP/pm/projects/p-$n/tasks/T500$n-card"
  printf '{"id":"T500%s-card","project":"%s","dispatches":[{"kind":"audit","agent":"grok","at":"2026-11-04T00:00:00Z"}],"verdicts":{"audit":{"verdict":"pass","round":1,"reviewer":"grok","notes":"ok","auditedHead":"%s"}}}\n' \
    "$n" "$RP" "$sha" > "$TMP/pm/projects/p-$n/tasks/T500$n-card/task.json"
  python3 - "$TMP/pr$n.meta" "$sha" "$2" "T500$n-card" "$W/issue-$n-build/tests/t.sh" <<'PY'
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
  *" pr merge "*) echo "fake gh: dry run must not merge" >&2; exit 1 ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
. "$ROOT/tests/super-board/lib/fake_ci_checks.sh"; sb_ci_checks_fixture "$TMP/bin"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" FAKE_REPO="$R"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_NOTIFY_SKIP=1 SB_HEAVY_SLOT_DIR="$TMP/slots"
unset SB_MERGE_CALLER SB_MERGE_QUEUE
export GH_TOKEN=fake-token
mkdir -p "$TMP/kit/bin" && printf '#!/bin/sh\necho x >> "%s/verify.count"\n' "$TMP" > "$TMP/kit/bin/post-fix-gate.py"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["sh %s/kit/bin/post-fix-gate.py --run-tests --scoped"]}\n' "$TMP" > "$TMP/cfg.json"
runs() { [ -f "$TMP/verify.count" ] && wc -l < "$TMP/verify.count" | tr -d ' ' || echo 0; }
gate() {   # gate <n> <log> [extra args]
  local n="$1" log="$2"; shift 2
  rm -f "$TMP/verify.count" "$TMP/halt.json"
  ( cd "$W/review" && bash "$GATE" --config "$TMP/cfg.json" --pr "$n" --expect-head "$(cat "$TMP/pr$n.head")" --subject card \
      --lock-timeout 20 --dry-run --train-receipt "$TMP/receipt$n" "$@" ) >"$log" 2>&1
}

card 1 0; gate 1 "$TMP/r1.log"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(runs)" = 1 ] && grep -q "train receipt not used" "$TMP/r1.log"; then
  ok "R1: pm + biên nhận train -> verify chạy lại"
else fail "R1: exit $rc, verify $(runs) lần (muốn 1): $(grep -aiE 'receipt|verif|proved' "$TMP/r1.log" | tail -3 | tr '\n' '|')"; fi

card 2 1; gate 2 "$TMP/r2.log"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(runs)" = 0 ] && grep -q "merge train already proved" "$TMP/r2.log"; then
  ok "R2: comment edited-tests + biên nhận train -> verify bỏ qua như cũ"
else fail "R2: exit $rc, verify $(runs) lần (muốn 0): $(grep -aiE 'receipt|verif|proved' "$TMP/r2.log" | tail -3 | tr '\n' '|')"; fi

card 3 0; gate 3 "$TMP/r3.log" --require-receipt; rc=$?
if [ "$rc" -eq 0 ] && [ "$(runs)" = 1 ]; then
  ok "R3: pm + --require-receipt -> không exit 12, verify trong gate"
else fail "R3: exit $rc, verify $(runs) lần (muốn exit 0, 1 lần): $(grep -aiE 'receipt|verif|proved|exit 12' "$TMP/r3.log" | tail -3 | tr '\n' '|')"; fi

[ "$FAILS" -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }
