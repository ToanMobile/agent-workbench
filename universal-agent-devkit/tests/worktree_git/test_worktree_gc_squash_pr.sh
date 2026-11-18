#!/usr/bin/env bash
# #1201: `gc --merged` coi worktree/branch là đã tích hợp khi PR của branch đã MERGED đúng tip (repo merge bằng SQUASH: HEAD không là tổ
# tiên của trunk, và trunk local chưa có nội dung), cùng kiểm với `prune-branch`; sau khi gỡ worktree thì xoá nhánh local + origin.
# Worktree detached ở tip của PR đã merge cũng vậy. Nhánh chưa merge, PR mở, tip đi tiếp sau lần merge: giữ.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WT="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
trap 'chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
has_branch() { G "$R" show-ref --verify --quiet "refs/heads/$1"; }
has_remote() { git -C "$O" show-ref --verify --quiet "refs/heads/$1"; }
export WORKTREE_GC_MIN_AGE_S=0 WORKTREE_GC_FRESH_S=0

O="$TMP/origin.git"; git init -q --bare -b main "$O"
R="$TMP/repo"; mkdir -p "$R" && G "$R" init -q -b main .
echo base > "$R/a.txt"; G "$R" add -A && G "$R" commit -qm init
G "$R" remote add origin "$O" && G "$R" push -q -u origin main 2>/dev/null
H="$R/.claude/worktrees"; mkdir -p "$H"
# worktree + nhánh có một commit; publish lên origin
mk() { G "$R" worktree add -q -b "$2" "$H/$1" main; echo "$2" > "$H/$1/$2.txt"; G "$H/$1" add -A; G "$H/$1" commit -qm "$2"; G "$H/$1" push -q origin "$2" 2>/dev/null; }
mk sq feat-sq; mk sq-det feat-sqdet; mk unmerged feat-unmerged; mk moved feat-moved; mk openpr feat-openpr
G "$H/sq-det" checkout -q --detach
echo more > "$H/moved/more.txt"; G "$H/moved" add -A; G "$H/moved" commit -qm more   # đi tiếp sau lần merge (không push)
SQ=$(G "$R" rev-parse feat-sq); SQD=$(G "$R" rev-parse feat-sqdet); MV=$(G "$R" rev-parse feat-moved~1)
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
case " $* " in
  *" pr list "*"--state open"*) echo "[{\"number\":9,\"headRefName\":\"feat-openpr\",\"baseRefName\":\"main\"}]" ;;
  *" pr list "*"--state merged"*) cat "$FAKE_DIR/merged.json" ;;
  *) exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"; export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
row() { printf '{"number":%s,"headRefOid":"%s","baseRefName":"main","isCrossRepository":false}' "$1" "$2"; }
echo "[$(row 11 "$SQ"),$(row 12 "$SQD"),$(row 13 "$MV")]" > "$TMP/merged.json"   # trunk local KHÔNG có nội dung (squash trên GitHub)

(cd "$R" && python3 "$WT" gc --merged >"$TMP/o" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "exit 0" || { fail "exit $rc"; cat "$TMP/o"; }
[ ! -e "$H/sq" ] && ! has_branch feat-sq && ! has_remote feat-sq && ok "1 squash-merged worktree: removed, local + origin branch deleted" || { fail "1 squash worktree/branch kept"; cat "$TMP/o"; }
[ ! -e "$H/sq-det" ] && ! has_branch feat-sqdet && ! has_remote feat-sqdet && ok "2 detached at a merged PR tip: removed, branch deleted" || { fail "2 detached kept"; cat "$TMP/o"; }
[ -d "$H/unmerged" ] && has_branch feat-unmerged && has_remote feat-unmerged && ok "3 branch with no merged PR untouched" || fail "3 unmerged touched"
[ -d "$H/moved" ] && has_branch feat-moved && has_remote feat-moved && ok "4 tip moved on after the merge: untouched" || fail "4 moved-on touched"
[ -d "$H/openpr" ] && has_branch feat-openpr && ok "5 open PR untouched" || fail "5 open PR touched"
# --- #1201 mục 2: file sinh ra / mục 3: commit chỉ reflog ---
mk gen feat-gen; mk genmix feat-genmix; mk refl feat-refl
GEN=$(G "$R" rev-parse feat-gen); MIX=$(G "$R" rev-parse feat-genmix); RF=$(G "$R" rev-parse feat-refl)
echo "[$(row 11 "$SQ"),$(row 14 "$GEN"),$(row 15 "$MIX"),$(row 16 "$RF")]" > "$TMP/merged.json"
mkdir -p "$H/gen/.claude" "$H/genmix/.claude"
echo '{"synced":1}' > "$H/gen/.claude/settings.json"
echo '{"synced":1}' > "$H/genmix/.claude/settings.json"; echo "real work" > "$H/genmix/work.txt"
G "$H/refl" checkout -q --detach; echo lost > "$H/refl/lost.txt"; G "$H/refl" add -A; G "$H/refl" commit -qm lost
LOSTC=$(G "$H/refl" rev-parse HEAD); G "$H/refl" checkout -q --detach "$RF"
(cd "$R" && python3 "$WT" gc --merged >"$TMP/o2" 2>&1)
(cd "$R" && python3 "$WT" remove --merged="$RF" "$H/refl" >"$TMP/o3" 2>&1)   # what the board's sweep calls
[ ! -e "$H/gen" ] && [ -n "$(G "$R" for-each-ref refs/devkit/discarded | grep -c gen)" ] && ! has_branch feat-gen && ok "7 worktree with only a regenerated file (.claude/settings.json): backed up in refs/devkit/discarded, removed, branch deleted" || { fail "7 generated-only worktree kept"; cat "$TMP/o2"; }
[ -f "$H/genmix/work.txt" ] && has_branch feat-genmix && ok "8 worktree with a real uncommitted file besides the generated one is kept" || fail "8 genmix removed"
[ ! -e "$H/refl" ] && [ -n "$(G "$R" for-each-ref --contains "$LOSTC" refs/devkit/discarded)" ] || { fail "9 reflog-only commit worktree not removed with a backup"; cat "$TMP/o3"; }
[ ! -e "$H/refl" ] && ok "9 merged worktree holding a commit only its reflog names: removed, commit kept in refs/devkit/discarded"
# --- #1201 audit: the squash is already in the local trunk (main pulled) and the PR merged at the tip: still deleted, local + origin ---
mk sqin feat-sqin; SQI=$(G "$R" rev-parse feat-sqin)
echo "[$(row 11 "$SQ"),$(row 17 "$SQI")]" > "$TMP/merged.json"
G "$R" cherry-pick feat-sqin >/dev/null 2>&1 || G "$R" cherry-pick --abort >/dev/null 2>&1
(cd "$R" && python3 "$WT" gc --merged >"$TMP/o4" 2>&1)
[ ! -e "$H/sqin" ] && ! has_branch feat-sqin && ! has_remote feat-sqin && ok "10 squash already in the local trunk and PR merged at the tip: removed, local + origin branch deleted" || { fail "10 content-in-trunk branch kept"; cat "$TMP/o4"; }
echo "FAILS=$FAILS"; [ "$FAILS" -eq 0 ]
