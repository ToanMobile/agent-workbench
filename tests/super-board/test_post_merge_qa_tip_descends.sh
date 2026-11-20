#!/usr/bin/env bash
# #1378: --sweep recovers a closed card's detached `issue-<N>-qa` worktree whose tip DESCENDS from the merged PR head (QA evidence commits
# on top, never pushed): archived under refs/devkit/discarded/worktrees/, removed through the kit. A tip that does not descend, a real code
# edit, or an open card keeps it. Offline: fake gh, real kit. CLEAN=<file> runs an older script to see RED.
set -u
export LC_ALL=C LANG=C DEVKIT_LANG=en
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLEAN="${CLEAN:-$ROOT/.claude/bin/super-board-post-merge-clean.sh}"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-qa-tip-1378.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; W="$R/.claude/worktrees"
git init -q --bare -b main "$O"; git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/worktrees/\n.claude/super-board/\n' > "$R/.gitignore"
mkdir -p "$R/src" "$R/.claude"; echo code > "$R/src/app.py"; echo '{}' > "$R/.claude/settings.json"
git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q -u origin main; git -C "$R" remote set-head origin main
mkdir -p "$W" "$R/.claude/super-board/inflight"
OLD="2020-01-01T00:00:00Z"

# card <N> <state>: pushed card branch (the merged PR head), merged-PR row, issue state; QA worktree detached on that head
card() {
  git -C "$R" branch "issue-$1-x" main; git -C "$R" worktree add -q "$TMP/edit" "issue-$1-x"
  echo "c$1" > "$TMP/edit/f$1"; git -C "$TMP/edit" add -A; git -C "$TMP/edit" commit -qm "card $1"
  git -C "$R" worktree remove "$TMP/edit"; git -C "$R" push -q origin "issue-$1-x"
  H=$(git -C "$R" rev-parse "issue-$1-x")
  printf '[{"number":%s,"headRefName":"issue-%s-x","headRefOid":"%s","baseRefName":"main","isCrossRepository":false,"mergedAt":"%s"}]\n' \
    "$((1000 + $1))" "$1" "$H" "$OLD" > "$TMP/merged$1.json"
  printf '{"state":"%s","stateReason":"COMPLETED","closedAt":"%s"}\n' "$2" "$OLD" > "$TMP/issue$1.json"
  git -C "$R" worktree add -q --detach "$W/issue-$1-qa" "$H"
}
evidence() { mkdir -p "$W/issue-$1-qa/docs/super-board/runs/issue-$1-qa-v1"; echo "ev$1" > "$W/issue-$1-qa/docs/super-board/runs/issue-$1-qa-v1/summary.md"
  git -C "$W/issue-$1-qa" add -A; git -C "$W/issue-$1-qa" commit -qm "QA evidence $1"; }

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
case " $* " in
  *" pr list "*"--state merged"*)
    m=$(printf '%s\n' "$*" | sed -nE 's/.*head:issue-([0-9]+)-.*/\1/p')
    if [ -f "$FAKE_DIR/merged$m.json" ]; then cat "$FAKE_DIR/merged$m.json"; else echo '[]'; fi ;;
  *" pr list "*"--state open"*) echo '[]' ;;
  *" issue view "*)
    f="$FAKE_DIR/issue$n.json"; [ -f "$f" ] || echo '{"state":"OPEN","stateReason":"","closedAt":""}' > "$f"
    case " $* " in *" -q .state "*) python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["state"])' "$f" ;; *) cat "$f" ;; esac ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"; export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
unset SB_SWEEP_GRACE_S; export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0

# A: closed, tip descends, clean tree -> archived + removed
card 41 CLOSED; evidence 41; TIP41=$(git -C "$W/issue-41-qa" rev-parse HEAD)
# B: closed, tip descends, but a real code edit -> kept
card 42 CLOSED; evidence 42; echo edit >> "$W/issue-42-qa/src/app.py"
# C: closed, tip does NOT descend from the merged head (on top of main, unrelated) -> kept
card 43 CLOSED; git -C "$W/issue-43-qa" checkout -q --detach main; echo other > "$W/issue-43-qa/other"; git -C "$W/issue-43-qa" add -A; git -C "$W/issue-43-qa" commit -qm unrelated
# D: card OPEN, tip descends -> kept
card 44 OPEN; evidence 44

# F: closed, tip descends, but a COMMITTED repro/code file on top of the evidence (unpushed Tester commit) -> kept
card 45 CLOSED; evidence 45; echo repro > "$W/issue-45-qa/repro.py"; git -C "$W/issue-45-qa" add -A; git -C "$W/issue-45-qa" commit -qm repro
# G: closed, evidence + a merge of main on top (like the real QA tips) -> archived + removed
card 46 CLOSED; evidence 46; git -C "$R" commit -q --allow-empty -m "main moves"; git -C "$R" push -q origin main
git -C "$W/issue-46-qa" fetch -q origin; git -C "$W/issue-46-qa" merge -q --no-edit origin/main; TIP46=$(git -C "$W/issue-46-qa" rev-parse HEAD)

bash "$CLEAN" --sweep "$R" --dry-run --min-interval 0 >"$TMP/dry.log" 2>&1
for k in 41 42 43 44; do [ -d "$W/issue-$k-qa" ] || fail "d0 --dry-run removed worktree $k"; done
grep -q "would archive QA tip $TIP41" "$TMP/dry.log" && ok "d1 dry-run says it would archive and remove 41" || { fail "d1 dry-run silent about 41"; grep -a "issue-41" "$TMP/dry.log"; }

bash "$CLEAN" --sweep "$R" --min-interval 0 >"$TMP/sweep.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "s0 sweep exit 0" || fail "s0 sweep exit $rc"
arch=0; for r in $(git -C "$R" for-each-ref --format='%(refname)' 'refs/devkit/discarded/worktrees/issue-41-qa-*'); do [ "$(git -C "$R" rev-parse "$r")" = "$TIP41" ] && arch=1; done
[ ! -d "$W/issue-41-qa" ] && [ "$arch" = 1 ] && ok "A clean QA tip: worktree removed, tip archived under refs/devkit/discarded/worktrees/" || { fail "A removed=$([ -d "$W/issue-41-qa" ] && echo no || echo yes) archived=$arch"; grep -a "issue-41" "$TMP/sweep.log"; }
[ -z "$(git -C "$R" for-each-ref 'refs/remotes/super-board-hold/qa-*')" ] && ok "A2 hold ref dropped" || fail "A2 hold ref left behind"
[ -d "$W/issue-42-qa" ] && [ "$(cat "$W/issue-42-qa/src/app.py" | wc -l | tr -d ' ')" = 2 ] && ok "B real code edit: kept, edit intact" || fail "B worktree 42 removed or edit lost"
[ -d "$W/issue-43-qa" ] && grep -aq "issue-43-qa: HEAD .* is not the head of a merged PR" "$TMP/sweep.log" && ok "C non-descending tip: kept with reason" || fail "C worktree 43 removed or no reason"
[ -d "$W/issue-44-qa" ] && ok "D open card kept" || fail "D worktree 44 removed"
[ -d "$W/issue-45-qa" ] && ok "F committed repro on top: kept" || fail "F worktree 45 removed"
arch46=0; for r in $(git -C "$R" for-each-ref --format='%(refname)' 'refs/devkit/discarded/worktrees/issue-46-qa-*'); do [ "$(git -C "$R" rev-parse "$r")" = "$TIP46" ] && arch46=1; done
[ ! -d "$W/issue-46-qa" ] && [ "$arch46" = 1 ] && ok "G evidence + merge of main: archived and removed" || { fail "G removed=$([ -d "$W/issue-46-qa" ] && echo no || echo yes) archived=$arch46"; grep -a "issue-46" "$TMP/sweep.log"; }
[ -z "$(git -C "$R" for-each-ref 'refs/devkit/discarded/worktrees/issue-4[2345]-qa-*')" ] && ok "E nothing archived for kept worktrees" || fail "E archive made for a kept worktree"
[ "$FAILS" -eq 0 ] && { echo "✅ test_post_merge_qa_tip_descends: all passed"; exit 0; }
echo "❌ test_post_merge_qa_tip_descends: $FAILS failed"; exit 1
