#!/usr/bin/env bash
# Test hồi quy cho bước dọn worktree lane sau merge (.claude/bin/super-board-post-merge-clean.sh), chạy offline với `gh` giả.
# 19/10 (issue #96): PR của thẻ landed bằng SQUASH, worktree issue-N-build / -qa / -review không bao giờ được gỡ: 5 repo đầy
# đĩa (OfficeReader 28G / 21 worktree, Goods 79G, NFH 51G). Đo trên dữ liệu thật: worktree đã merge bị giữ vì (1) chỉ còn file
# đã xoá (OR 72-qa, Geely 40-qa), (2) ghi chú memory của agent trong .agents/local/ (OR 73/80-build), (3) asset Unity tự
# serialize lại (NFH 3-qa, 53-build/qa), (4) worktree review luôn được giữ và không ai gỡ sau đó (OR 79-review), (5) nhánh
# "kept branch …: still checked out" vì worktree build còn đó. Head đã squash không nằm trong trunk, nên kit chỉ gỡ được
# worktree detached khi còn một ref giữ head (nhánh, origin/<nhánh>, hay refs/pull/<PR>/head của GitHub).
#   A  qua merge gate (squash): build (ghi chú memory) + qa (chỉ file đã xoá) được gỡ, phần sửa được cất thành patch NGOÀI cây
#      làm việc (main không bẩn thêm), nhánh bị xoá; review (cwd của gate) và thẻ khác giữ nguyên.
#   B  --sweep cho worktree còn sót: chỉ thẻ có PR MERGED đúng head, đã quá thời gian chờ, issue CLOSED, không lane sống nào giữ;
#      head không ref nào giữ thì giữ tạm bằng refs/pull/<PR>/head rồi bỏ ref đó; sửa thật (code) thì giữ và nói lý do.
# Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
CLEAN="$ROOT/.claude/bin/super-board-post-merge-clean.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-squash-leftovers.XXXXXX")"
SL=""
trap '[ -n "$SL" ] && kill "$SL" 2>/dev/null; rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; C="$TMP/clone"; W="$R/.claude/worktrees"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"
mkdir -p "$R/.agents/local/memory/agents/rev" "$R/unity/Assets" "$R/src"
echo note > "$R/.agents/local/memory/agents/rev/MEMORY.md"
echo asset > "$R/unity/Assets/x.asset"; echo code > "$R/src/x.c"
for i in 1 2 3 7 8 21 22 23 24 25 26 27 28 29 70; do echo "$i" > "$R/f$i"; done
git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"
git -C "$R" push -q -u origin main
git -C "$R" remote set-head origin main
git -C "$R" merge-tree --write-tree HEAD HEAD >/dev/null 2>&1 || { echo "skip: git < 2.38 has no merge-tree --write-tree"; exit 0; }
git clone -q "$O" "$C"
git -C "$C" config user.email t@example.invalid; git -C "$C" config user.name t
mkdir -p "$W" "$R/.claude/super-board/inflight"

# card <N> <PR> <branch>: nhánh có một commit sửa f<N>, đã push; GitHub giữ refs/pull/<PR>/head; gh giả biết PR đó.
card() {
  git -C "$R" branch "$3" main
  git -C "$R" worktree add -q "$TMP/edit" "$3"
  echo "card $1" > "$TMP/edit/f$1"; git -C "$TMP/edit" commit -qam "card $1"
  git -C "$R" worktree remove "$TMP/edit"
  git -C "$R" push -q origin "$3"
  h=$(git -C "$R" rev-parse "$3")
  git -C "$O" update-ref "refs/pull/$2/head" "$h"
  echo "$h" > "$TMP/pr$2.head"; echo "$3" > "$TMP/pr$2.ref"
  git -C "$R" diff main "$3" > "$TMP/pr$2.diff"
  printf '{"files":[{"path":"f%s"}],"labels":[],"body":"","additions":1,"deletions":1,"changedFiles":1}' "$1" > "$TMP/pr$2.meta"
}
# squash <PR> [later]: GitHub squash PR vào main, xoá nhánh remote; "later" = một PR khác sửa lại đúng file đó sau (head không
# còn gộp thử được vào trunk: merge-tree xung đột).
squash() {
  b=$(cat "$TMP/pr$1.ref"); h=$(cat "$TMP/pr$1.head")
  git -C "$C" fetch -q origin
  tree=$(git -C "$C" merge-tree --write-tree origin/main "$h")
  sq=$(git -C "$C" commit-tree "$tree" -p origin/main -m "squash #$1")
  if [ "${2:-}" = later ]; then
    n=$(printf '%s' "$b" | sed -E 's/^issue-([0-9]+)-.*/\1/')
    git -C "$C" read-tree "$sq"
    echo "later $n" > "$TMP/later"; blob=$(git -C "$C" hash-object -w "$TMP/later")
    git -C "$C" update-index --cacheinfo "100644,$blob,f$n"
    sq=$(git -C "$C" commit-tree "$(git -C "$C" write-tree)" -p "$sq" -m "later #$1")
  fi
  git -C "$C" push -q origin "$sq:refs/heads/main"
  git -C "$C" push -q origin --delete "$b"
}
merged_row() {  # merged_row <PR> <mergedAt>: thêm PR vào danh sách gh pr list --state merged
  printf '{"number":%s,"headRefName":"%s","headRefOid":"%s","baseRefName":"main","isCrossRepository":false,"mergedAt":"%s"}\n' \
    "$1" "$(cat "$TMP/pr$1.ref")" "$(cat "$TMP/pr$1.head")" "$2" >> "$TMP/merged.jsonl"
}

# gh giả: pr view / diff / merge cho merge gate, pr list --state merged (lọc theo --head như kit), issue view. Ghi lại mọi lệnh.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/gh.calls"
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "$(cat "$FAKE_DIR/pr$n.ref") $(cat "$FAKE_DIR/pr$n.head")" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$(cat "$FAKE_DIR/pr$n.head")" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr merge "*) bash "$FAKE_DIR/squash.sh" "$n" && echo "merged #$n" ;;
  *" pr list "*"--state merged"*)
    head=""; prev=""; for a in "$@"; do [ "$prev" = --head ] && head="$a"; prev="$a"; done
    python3 -c 'import json,sys
rows=[json.loads(l) for l in open(sys.argv[1]) if l.strip()] if __import__("os").path.exists(sys.argv[1]) else []
print(json.dumps([r for r in rows if not sys.argv[2] or r["headRefName"]==sys.argv[2]]))' "$FAKE_DIR/merged.jsonl" "$head" ;;
  *" issue view "*) cat "$FAKE_DIR/issue$n.state" 2>/dev/null || echo OPEN ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
{ declare -f squash; echo 'TMP="$FAKE_DIR"; C="$FAKE_DIR/clone"; squash "$1"'; } > "$TMP/squash.sh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0
CFG="$TMP/cfg.json"
echo '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["true"]}' > "$CFG"
SALV="$R/.git/super-board/salvage"

# ── A. merge gate, thẻ 7 = PR 11: Reviewer chạy gate từ worktree issue-7-review của nó (repo.path ".").
card 7 11 issue-7-fix
H7=$(cat "$TMP/pr11.head")
git -C "$R" worktree add -q "$W/issue-7-build" issue-7-fix
git -C "$R" worktree add -q --detach "$W/issue-7-qa" "$H7"
git -C "$R" worktree add -q --detach "$W/issue-7-review" "$H7"
echo "learned" >> "$W/issue-7-build/.agents/local/memory/agents/rev/MEMORY.md"     # subagent memory note (tracked), OR 73/80
echo "new note" > "$W/issue-7-build/.agents/local/memory/agents/rev/new.md"        # và một note mới chưa track
rm "$W/issue-7-qa/f1" "$W/issue-7-qa/f2"                                            # chỉ còn file đã xoá, OR 72 / Geely 40
card 8 18 issue-8-other; git -C "$R" worktree add -q "$W/issue-8-build" issue-8-other
echo wip > "$W/issue-8-build/f8"                                                     # thẻ khác đang sửa dở
card 70 170 issue-70-similar; git -C "$R" worktree add -q "$W/issue-70-build" issue-70-similar
MAIN_STATUS_BEFORE=$(git -C "$R" status --porcelain)
( cd "$W/issue-7-review" && bash "$GATE" --config "$CFG" --pr 11 --expect-head "$H7" ) >"$TMP/gateA.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "A0 gate squash-merged PR #11 (exit 0)" || { fail "A0 gate exit $rc"; tail -20 "$TMP/gateA.log"; }
[ ! -d "$W/issue-7-build" ] && ok "A1 build worktree with only agent memory notes uncommitted is removed" \
  || { fail "A1 build worktree with memory notes kept"; grep -a "issue-7-build" "$TMP/gateA.log"; }
[ ! -d "$W/issue-7-qa" ] && ok "A2 qa worktree holding only deleted files is removed" \
  || { fail "A2 qa worktree with only deletions kept"; grep -a "issue-7-qa" "$TMP/gateA.log"; }
[ -d "$W/issue-7-review" ] && ok "A3 the calling Reviewer's issue-7-review is kept (its post-merge steps run there)" || fail "A3 review worktree removed under the gate"
if git -C "$R" rev-parse --verify -q refs/heads/issue-7-fix >/dev/null; then fail "A4 merged branch kept"; grep -a "branch" "$TMP/gateA.log"
else ok "A4 merged branch issue-7-fix deleted"; fi
P=$(ls "$SALV"/issue-7-build-*.patch 2>/dev/null | head -1)
if [ -n "$P" ] && grep -q "rev/MEMORY.md" "$P" && grep -q "rev/new.md" "$P"; then
  rm -f "$TMP/idx"
  if GIT_INDEX_FILE="$TMP/idx" git -C "$R" read-tree "$H7" && GIT_INDEX_FILE="$TMP/idx" git -C "$R" apply --cached "$P"; then
    ok "A5 the memory notes are salvaged to a patch that applies on the merged head ($P)"
  else fail "A5 salvage patch does not apply on the merged head"; fi
else fail "A5 no salvage patch with both memory notes under $SALV"; ls -R "$SALV" 2>/dev/null | head; fi
[ "$(git -C "$R" status --porcelain)" = "$MAIN_STATUS_BEFORE" ] && ok "A6 main checkout status unchanged (salvage lives outside the work tree)" \
  || { fail "A6 main checkout got dirtier"; git -C "$R" status --porcelain; }
[ "$(cat "$W/issue-8-build/f8" 2>/dev/null)" = wip ] && [ -d "$W/issue-70-build" ] && ok "A7 other cards' worktrees (8, 70) untouched" \
  || fail "A7 another card's worktree touched"

# ── B. --sweep: worktree còn sót của các thẻ đã merge trước đó.
OLD="2026-01-01T00:00:00Z"; NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# 7 = PR 11 từ phần A: worktree review của Reviewer còn lại sau gate; sweep gỡ nó sau (head chỉ còn refs/pull/11/head giữ)
merged_row 11 "$OLD"; echo CLOSED > "$TMP/issue7.state"
# 21 = PR 31: không ref nào còn giữ head (nhánh local + remote đã xoá); review sạch, qa có asset Unity tự serialize (NFH 3-qa)
card 21 31 issue-21-a; H21=$(cat "$TMP/pr31.head")
git -C "$R" worktree add -q --detach "$W/issue-21-review" "$H21"
git -C "$R" worktree add -q --detach "$W/issue-21-qa" "$H21"
echo "reserialized" >> "$W/issue-21-qa/unity/Assets/x.asset"
squash 31 later; merged_row 31 "$OLD"; echo CLOSED > "$TMP/issue21.state"
git -C "$R" branch -D issue-21-a >/dev/null
# 22 = PR 32: build còn sửa code thật (giữ, nói lý do), qa sạch (gỡ)
card 22 32 issue-22-b; H22=$(cat "$TMP/pr32.head")
git -C "$R" worktree add -q "$W/issue-22-build" issue-22-b
git -C "$R" worktree add -q --detach "$W/issue-22-qa" "$H22"
echo "real fix" >> "$W/issue-22-build/src/x.c"
squash 32 later; merged_row 32 "$OLD"; echo CLOSED > "$TMP/issue22.state"
# 23: issue CLOSED nhưng PR vẫn OPEN (OR #84 / PR 133)
card 23 33 issue-23-c; git -C "$R" worktree add -q --detach "$W/issue-23-review" "$(cat "$TMP/pr33.head")"; echo CLOSED > "$TMP/issue23.state"
# 24 = PR 34: một lane còn sống giữ thẻ (inflight/24, PID sống)
card 24 34 issue-24-d; git -C "$R" worktree add -q --detach "$W/issue-24-qa" "$(cat "$TMP/pr34.head")"
squash 34; merged_row 34 "$OLD"; echo CLOSED > "$TMP/issue24.state"
sleep 300 & SL=$!; disown "$SL" 2>/dev/null
printf 'PID=%s\nLANE=review\nSTARTED=%s\n' "$SL" "$NOW" > "$R/.claude/super-board/inflight/24"
# 29 = PR 39: lock inflight dạng cũ (trước v1.3.0: một dòng chỉ có PID) của một lane còn sống
card 29 39 issue-29-i; git -C "$R" worktree add -q --detach "$W/issue-29-qa" "$(cat "$TMP/pr39.head")"
squash 39; merged_row 39 "$OLD"; echo CLOSED > "$TMP/issue29.state"
printf '%s\n' "$SL" > "$R/.claude/super-board/inflight/29"
# 25 = PR 35: vừa merge (Reviewer còn làm bước sau merge)
card 25 35 issue-25-e; git -C "$R" worktree add -q --detach "$W/issue-25-qa" "$(cat "$TMP/pr35.head")"
squash 35; merged_row 35 "$NOW"; echo CLOSED > "$TMP/issue25.state"
# 26 = PR 36: PR merged nhưng issue còn OPEN
card 26 36 issue-26-f; git -C "$R" worktree add -q --detach "$W/issue-26-qa" "$(cat "$TMP/pr36.head")"
squash 36; merged_row 36 "$OLD"; echo OPEN > "$TMP/issue26.state"
# 27 = PR 37: qa ở một commit KHÔNG thuộc head đã merge (repro chưa đẩy, giữ trên nhánh scratch-27)
card 27 37 issue-27-g; git -C "$R" worktree add -q -b scratch-27 "$W/issue-27-qa" "$(cat "$TMP/pr37.head")"
echo repro > "$W/issue-27-qa/f27"; git -C "$W/issue-27-qa" commit -qam repro; git -C "$W/issue-27-qa" checkout -q --detach
squash 37; merged_row 37 "$OLD"; echo CLOSED > "$TMP/issue27.state"
# 28 = PR 38: build sạch trên nhánh, squash rồi trunk sửa lại file (kit chỉ xoá nhánh nhờ bằng chứng PR MERGED đúng tip)
card 28 38 issue-28-h; git -C "$R" worktree add -q "$W/issue-28-build" issue-28-h
squash 38 later; merged_row 38 "$OLD"; echo CLOSED > "$TMP/issue28.state"
# 2 = PR 12: chỉ còn nhánh local, không worktree (và issue-2 không được khớp nhầm issue-21 / issue-22 / issue-28)
card 2 12 issue-2-z; squash 12 later; merged_row 12 "$OLD"; echo CLOSED > "$TMP/issue2.state"
git -C "$R" fetch -q --prune origin
MAIN_STATUS_BEFORE=$(git -C "$R" status --porcelain)
LIST_BEFORE=$(git -C "$R" worktree list --porcelain | grep '^worktree ' | sort)
REFS_BEFORE=$(git -C "$R" for-each-ref --format='%(refname) %(objectname)' | sort)

# B1 --dry-run: nói sẽ gỡ gì, không đổi gì (không salvage, không ref, không gỡ)
bash "$CLEAN" --sweep "$R" --dry-run >"$TMP/dry.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(git -C "$R" worktree list --porcelain | grep '^worktree ' | sort)" = "$LIST_BEFORE" ] \
  && [ "$(git -C "$R" for-each-ref --format='%(refname) %(objectname)' | sort)" = "$REFS_BEFORE" ] && ! ls "$SALV"/issue-21-qa-* >/dev/null 2>&1 \
  && ok "B1 --dry-run changes nothing" || { fail "B1 --dry-run changed something (rc $rc)"; cat "$TMP/dry.log"; }
miss=""
for w in issue-7-review issue-21-review issue-21-qa issue-22-qa issue-28-build; do grep -q "would remove .*/$w" "$TMP/dry.log" || miss="$miss $w"; done
for w in issue-22-build issue-23-review issue-24-qa issue-29-qa issue-25-qa issue-26-qa issue-27-qa; do grep -q "would remove .*/$w" "$TMP/dry.log" && miss="$miss !$w"; done
# nhánh của worktree "sẽ gỡ" (issue-28-build) cũng "sẽ xoá", không phải "still checked out"; nhánh của worktree giữ lại thì giữ
for b in issue-28-h issue-2-z; do grep -q "would delete branch $b " "$TMP/dry.log" || miss="$miss branch:$b"; done
grep -q "kept branch issue-22-b: still checked out" "$TMP/dry.log" || miss="$miss kept-branch:issue-22-b"
[ -z "$miss" ] && ok "B2 --dry-run names exactly the five removable leftovers" || { fail "B2 dry-run list wrong:$miss"; cat "$TMP/dry.log"; }

# B3 bảng đang halt GitHub: sweep không đọc GitHub, không gỡ gì
echo '{"reason":"test"}' > "$TMP/halt.json"; : > "$TMP/gh.calls"
bash "$CLEAN" --sweep "$R" --min-interval 0 >"$TMP/halt.log" 2>&1
[ ! -s "$TMP/gh.calls" ] && [ -d "$W/issue-21-review" ] && ok "B3 a GitHub halt stops the sweep before any read" \
  || { fail "B3 sweep ran while GitHub reads are halted"; cat "$TMP/halt.log"; }
rm -f "$TMP/halt.json"

# B4 sweep thật
bash "$CLEAN" --sweep "$R" --min-interval 0 >"$TMP/sweep.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "B4 sweep exit 0" || fail "B4 sweep exit $rc"
for w in issue-7-review issue-21-review issue-21-qa issue-22-qa issue-28-build; do
  [ ! -d "$W/$w" ] && ok "B5 merged leftover $w removed" || { fail "B5 merged leftover $w kept"; grep -a "$w" "$TMP/sweep.log"; }
done
for w in issue-22-build issue-23-review issue-24-qa issue-29-qa issue-25-qa issue-26-qa issue-27-qa issue-70-build issue-8-build; do
  [ -d "$W/$w" ] && ok "B6 $w kept" || fail "B6 $w REMOVED"
done
grep -q "issue-22-build: uncommitted edits.*src/x.c" "$TMP/sweep.log" && [ "$(tail -1 "$W/issue-22-build/src/x.c")" = "real fix" ] \
  && ok "B7 real code edits are kept in place and the log says why" || { fail "B7 no reason logged for the kept real edit"; cat "$TMP/sweep.log"; }
P=$(ls "$SALV"/issue-21-qa-*.patch 2>/dev/null | head -1)
[ -n "$P" ] && grep -q "unity/Assets/x.asset" "$P" && ok "B8 the Unity re-serialized asset is salvaged ($P)" || fail "B8 no salvage patch for issue-21-qa"
git -C "$R" rev-parse -q --verify refs/remotes/origin/pull/31/head >/dev/null && fail "B9 temporary refs/pull hold left behind" \
  || ok "B9 the temporary refs/pull/31/head hold is dropped after the removal"
for b in issue-28-h issue-2-z; do
  if git -C "$R" rev-parse -q --verify "refs/heads/$b" >/dev/null; then fail "B10 merged branch $b kept"; grep -a "$b" "$TMP/sweep.log"
  else ok "B10 merged branch $b deleted (PR merged at its tip)"; fi
done
for b in issue-22-b scratch-27 issue-23-c issue-26-f; do
  git -C "$R" rev-parse -q --verify "refs/heads/$b" >/dev/null && ok "B11 branch $b kept" || fail "B11 branch $b deleted"
done
[ "$(git -C "$R" status --porcelain)" = "$MAIN_STATUS_BEFORE" ] && ok "B12 main checkout status unchanged" || fail "B12 main checkout got dirtier"

# B13 chạy lại ngay với khoảng nghỉ mặc định: kỳ vọng bỏ qua — assert dưới kiểm gh.calls của gh giả rỗng
: > "$TMP/gh.calls"
bash "$CLEAN" --sweep "$R" >"$TMP/again.log" 2>&1
[ ! -s "$TMP/gh.calls" ] && ok "B13 a second sweep inside the minimum interval makes no GitHub call" || { fail "B13 the interval stamp is ignored"; cat "$TMP/gh.calls"; }

[ "$FAILS" -eq 0 ] && echo "✅ test_post_merge_squash_leftovers: all passed" || { echo "❌ test_post_merge_squash_leftovers: $FAILS failed"; exit 1; }
