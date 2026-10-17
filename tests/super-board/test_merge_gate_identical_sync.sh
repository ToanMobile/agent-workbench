#!/usr/bin/env bash
# Test hồi quy cho bước đồng bộ base local sau merge của .claude/bin/super-board-merge-gate.sh khi main giữ bản CHƯA commit giống hệt
# origin (K13, OfficeReader PR #143, 18/10): merge xong gate báo "not fast-forwarded; local base is stale: Your local changes to the
# following files would be overwritten by merge … reset to origin/main refused too: Entry '…' not uptodate" dù hai file dở trùng byte
# với origin/main và hai file chưa track cũng đã có trên origin: không gì mất mà main kẹt (0 trước, 2 sau).
#   1 file đã track sửa dở, trùng byte + mode với origin/main: gate stage đúng đường dẫn đó rồi ff, main về origin/main
#   2 file chưa track trùng byte với file PR thêm vào: như trên
#   3 một file dở KHÁC byte: không stage gì, main để nguyên, bản dở còn nguyên, cảnh báo như cũ
#   4 như 1 nhưng main đã giữ chính commit của PR (trunk mode, squash làm lệch): stage rồi `reset --keep`
#   5 bản dở trùng byte nhưng khác mode: không stage
#   6 file phiên khác đã stage (đường dẫn khác) còn nguyên trong index sau khi gate stage bản trùng và ff
#   7 origin thêm một file mà main giữ bản riêng bị git IGNORE ở đúng đường dẫn (review 18/10): không stage, không ff, file riêng còn nguyên
# Tương thích bash 3.2. Fixture `gh` giả như tests/super-board/test_merge_gate_squash_sync.sh.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-identical-sync.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add .gitignore a; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"
git -C "$R" push -q origin main
git -C "$R" merge-tree --write-tree HEAD HEAD >/dev/null 2>&1 || { echo "skip: git < 2.38 has no merge-tree --write-tree"; exit 0; }

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr merge "*) git -C "$FAKE_REPO" fetch -q origin main \
                    && tree=$(git -C "$FAKE_REPO" merge-tree --write-tree origin/main "$head") \
                    && sq=$(git -C "$FAKE_REPO" commit-tree "$tree" -p origin/main -m "squash #$n") \
                    && git -C "$FAKE_REPO" push -q origin "$sq:refs/heads/main" && echo "merged #$n" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" FAKE_REPO="$R"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0
CFG="$TMP/cfg.json"
echo '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["true"]}' > "$CFG"

# branch <N> <file> <content>: nhánh issue-<N>-x có một commit ghi <file>, đã push. main local chưa đổi.
branch() {
  git -C "$R" fetch -q origin
  git -C "$R" checkout -q -b "issue-$1-x" origin/main
  printf '%s\n' "$3" > "$R/$2"; git -C "$R" add "$2"; git -C "$R" commit -qm "card $1"
  git -C "$R" push -q origin "issue-$1-x"
  git -C "$R" rev-parse "issue-$1-x" > "$TMP/pr$1.head"
  meta "$1"
  git -C "$R" checkout -q main
}
# meta <N>: diff + metadata của PR N, số dòng thêm/xoá lấy từ numstat (github-read đối chiếu chúng với diff)
meta() {
  git -C "$R" diff "origin/main" "issue-$1-x" > "$TMP/pr$1.diff"
  git -C "$R" diff --numstat "origin/main" "issue-$1-x" | python3 -c 'import json,sys
rows=[l.split("\t") for l in sys.stdin.read().splitlines() if l]
print(json.dumps({"files":[{"path":r[2]} for r in rows],"labels":[],"body":"","additions":sum(int(r[0]) for r in rows),
                  "deletions":sum(int(r[1]) for r in rows),"changedFiles":len(rows)}))' > "$TMP/pr$1.meta"
}
git -C "$R" worktree add -q --detach "$TMP/lw" main
gate() { ( cd "$TMP/lw" && bash "$GATE" --config "$CFG" --pr "$1" --expect-head "$(cat "$TMP/pr$1.head")" ) >"$TMP/gate$1.log" 2>&1; }
synced() { [ "$(git -C "$R" rev-parse main)" = "$(git -C "$R" rev-parse origin/main)" ] && grep -q "merged " "$TMP/gate$1.log"; }
resync() { git -C "$R" fetch -q origin; git -C "$R" reset -q --hard origin/main; git -C "$R" clean -qfd; }

# ── 1. file đã track sửa dở trùng byte với bản PR mang về (main ở sau origin: đường ff).
branch 21 a "pr21 a"
printf '%s\n' "pr21 a" > "$R/a"                 # bản chép tay vào main, chưa commit, trùng byte
gate 21; rc=$?
[ "$rc" -eq 0 ] && ok "1: the PR merged (exit 0)" || fail "1: gate exit $rc: $(tail -5 "$TMP/gate21.log")"
synced 21 && ok "1: main fast-forwarded to origin/main" || fail "1: main $(git -C "$R" rev-parse --short main) != origin/main $(git -C "$R" rev-parse --short origin/main): $(grep -E 'warning|note' "$TMP/gate21.log" | cut -c1-220)"
[ "$(cat "$R/a")" = "pr21 a" ] && [ -z "$(git -C "$R" status --porcelain)" ] && ok "1: nothing lost, main clean" || fail "1: status: $(git -C "$R" status --porcelain | tr '\n' ';')"
! grep -q "local base is stale" "$TMP/gate21.log" && ok "1: no stale-base warning" || fail "1: still warns: $(grep stale "$TMP/gate21.log" | cut -c1-200)"
grep -q "fast-forwarded after staging 1 uncommitted path" "$TMP/gate21.log" && ok "1: the note names the staging path taken" || fail "1: no 'fast-forwarded after staging' note"
resync

# ── 2. file chưa track trùng byte với file PR thêm vào.
branch 22 n "pr22 new"
printf '%s\n' "pr22 new" > "$R/n"
gate 22; rc=$?
[ "$rc" -eq 0 ] && ok "2: the PR merged (exit 0)" || fail "2: gate exit $rc: $(tail -5 "$TMP/gate22.log")"
synced 22 && ok "2: main fast-forwarded to origin/main" || fail "2: main not synced: $(grep -E 'warning|note' "$TMP/gate22.log" | cut -c1-220)"
[ "$(cat "$R/n")" = "pr22 new" ] && [ -z "$(git -C "$R" status --porcelain)" ] && ok "2: nothing lost, main clean" || fail "2: status: $(git -C "$R" status --porcelain | tr '\n' ';')"
grep -q "fast-forwarded after staging 1 uncommitted path" "$TMP/gate22.log" && ok "2: the note names the staging path taken" || fail "2: no 'fast-forwarded after staging' note"
resync

# ── 3. một file dở KHÁC byte (cùng với một file trùng byte): không stage gì, main và cả hai bản dở để nguyên, cảnh báo.
git -C "$R" fetch -q origin
git -C "$R" checkout -q -b issue-23-x origin/main
printf '%s\n' "pr23 a" > "$R/a"; printf '%s\n' "pr23 m" > "$R/m"; git -C "$R" add a m; git -C "$R" commit -qm "card 23"
git -C "$R" push -q origin issue-23-x
git -C "$R" rev-parse issue-23-x > "$TMP/pr23.head"; meta 23
git -C "$R" checkout -q main
printf '%s\n' "pr23 a" > "$R/a"                 # trùng byte
printf '%s\n' "MY OWN m" > "$R/m"               # chưa track, KHÁC byte
BEFORE3=$(git -C "$R" rev-parse main)
gate 23; rc=$?
[ "$rc" -eq 0 ] && ok "3: the PR still merged (exit 0)" || fail "3: gate exit $rc: $(tail -5 "$TMP/gate23.log")"
[ "$(git -C "$R" rev-parse main)" = "$BEFORE3" ] && ok "3: main left where it was" || fail "3: main moved"
[ "$(cat "$R/m")" = "MY OWN m" ] && [ "$(cat "$R/a")" = "pr23 a" ] && ok "3: both unfinished copies intact" || fail "3: a copy changed"
[ -z "$(git -C "$R" diff --cached --name-only)" ] && ok "3: nothing left staged" || fail "3: index changed: $(git -C "$R" diff --cached --name-only | tr '\n' ' ')"
grep -q "not fast-forwarded" "$TMP/gate23.log" && ok "3: the warning is printed as before" || fail "3: no warning"
resync

# ── 4. main đã giữ chính commit của PR (trunk mode) nên squash làm lệch (đường reset --keep), cộng một file dở trùng byte với origin.
branch 24 b "pr24 b"
git -C "$R" merge -q --ff-only issue-24-x
git -C "$R" checkout -q -b other-24 origin/main; printf '%s\n' "origin a" > "$R/a"; git -C "$R" commit -qam "origin edits a"
git -C "$R" push -q origin other-24:refs/heads/main; git -C "$R" checkout -q main; git -C "$R" fetch -q origin
printf '%s\n' "origin a" > "$R/a"               # bản dở ở main trùng byte với origin/main
gate 24; rc=$?
[ "$rc" -eq 0 ] && ok "4: the PR merged (exit 0)" || fail "4: gate exit $rc: $(tail -5 "$TMP/gate24.log")"
synced 24 && ok "4: main moved to origin/main (reset --keep after staging the identical path)" || fail "4: main not synced: $(grep -E 'warning|note' "$TMP/gate24.log" | cut -c1-260)"
[ "$(cat "$R/a")" = "origin a" ] && [ -z "$(git -C "$R" status --porcelain)" ] && ok "4: nothing lost, main clean" || fail "4: status: $(git -C "$R" status --porcelain | tr '\n' ';')"
grep -q "moved to origin/main after staging 1 uncommitted path" "$TMP/gate24.log" && ok "4: the note names the reset-after-staging path" || fail "4: no 'moved … after staging' note"
! grep -q "did not move" "$TMP/gate24.log" && ok "4: no futile ff staging attempt on a diverged base" || fail "4: ff staging was tried on a diverged base"
resync

# ── 5. bản dở trùng byte nhưng KHÁC mode (chmod +x): không stage, main để nguyên, cảnh báo như cũ.
branch 25 a "pr25 a"
printf '%s\n' "pr25 a" > "$R/a"; chmod +x "$R/a"
BEFORE5=$(git -C "$R" rev-parse main)
gate 25; rc=$?
[ "$rc" -eq 0 ] && ok "5: the PR merged (exit 0)" || fail "5: gate exit $rc: $(tail -5 "$TMP/gate25.log")"
[ "$(git -C "$R" rev-parse main)" = "$BEFORE5" ] && [ -x "$R/a" ] && [ -z "$(git -C "$R" diff --cached --name-only)" ] \
  && ok "5: a copy with another mode is not staged, main left alone" || fail "5: main moved or index changed: $(git -C "$R" status --porcelain | tr '\n' ';')"
grep -q "not fast-forwarded" "$TMP/gate25.log" && ok "5: the warning is printed as before" || fail "5: no warning"
chmod -x "$R/a"; resync

# ── 6. phiên khác đang STAGE một file khác (x) trong main, cộng một file dở trùng byte (a): gate chỉ stage đúng `a`, ff được, và
#    entry đã stage của phiên kia (x) vẫn nằm nguyên trong index.
branch 26 a "pr26 a"
printf '%s\n' "pr26 a" > "$R/a"
echo "other session" > "$R/x"; git -C "$R" add x
gate 26; rc=$?
[ "$rc" -eq 0 ] && ok "6: the PR merged (exit 0)" || fail "6: gate exit $rc: $(tail -5 "$TMP/gate26.log")"
synced 26 && ok "6: main fast-forwarded" || fail "6: main not synced: $(grep -E 'warning|note' "$TMP/gate26.log" | cut -c1-220)"
[ "$(git -C "$R" diff --cached --name-only)" = x ] && [ "$(cat "$R/x")" = "other session" ] \
  && ok "6: another session's staged entry survives" || fail "6: staged entry lost: $(git -C "$R" status --porcelain | tr '\n' ';')"
git -C "$R" rm -q --cached -f x >/dev/null 2>&1; rm -f "$R/x"; resync

# ── 7. PR đổi `a` VÀ thêm `local.json` (bị main ignore, ép add); main có `a` dở trùng byte và một `local.json` RIÊNG bị ignore:
#    stage `a` rồi ff sẽ đè mất file riêng (trước đây chính `a` dở làm git từ chối, file riêng được giữ). Gate không được dời main.
printf 'local.json\n' >> "$R/.git/info/exclude"
git -C "$R" fetch -q origin
git -C "$R" checkout -q -b issue-27-x origin/main
printf '%s\n' "pr27 a" > "$R/a"; printf '%s\n' '{"from":"origin"}' > "$R/local.json"; git -C "$R" add a; git -C "$R" add -f local.json
git -C "$R" commit -qm "card 27"; git -C "$R" push -q origin issue-27-x
git -C "$R" rev-parse issue-27-x > "$TMP/pr27.head"; meta 27
git -C "$R" checkout -q main
printf '%s\n' "pr27 a" > "$R/a"
printf '%s\n' '{"secret":"MINE"}' > "$R/local.json"
BEFORE7=$(git -C "$R" rev-parse main)
gate 27; rc=$?
[ "$rc" -eq 0 ] && ok "7: the PR merged (exit 0)" || fail "7: gate exit $rc: $(tail -5 "$TMP/gate27.log")"
[ "$(cat "$R/local.json")" = '{"secret":"MINE"}' ] && ok "7: the private ignored file is intact" || fail "7: the private ignored file was overwritten: $(cat "$R/local.json")"
[ "$(git -C "$R" rev-parse main)" = "$BEFORE7" ] && [ -z "$(git -C "$R" diff --cached --name-only)" ] && ok "7: main not moved, nothing left staged" \
  || fail "7: main moved or index changed: $(git -C "$R" status --porcelain | tr '\n' ';')"
rm -f "$R/local.json"; resync

# ── 8. cùng ý ca 7 nhưng file riêng bị ignore nằm ở chỗ ĐƯỜNG DẪN CHA / khác hoa thường / là symlink (review 18/10): PR đổi `a` và thêm
#    <add>; main có `a` dở trùng byte và <mine> bị ignore. Gate không được dời main, <mine> còn nguyên.
#    ignored_case <N> <đường dẫn PR thêm> <đường dẫn file riêng ở main> <kiểu: file|link> <tên ca>
ignored_case() {
  git -C "$R" fetch -q origin
  git -C "$R" checkout -q -b "issue-$1-x" origin/main
  printf '%s\n' "pr$1 a" > "$R/a"; mkdir -p "$R/$(dirname "$2")"; printf '%s\n' "from origin" > "$R/$2"
  git -C "$R" add a; git -C "$R" add -f "$2"; git -C "$R" commit -qm "card $1"; git -C "$R" push -q origin "issue-$1-x"
  git -C "$R" rev-parse "issue-$1-x" > "$TMP/pr$1.head"; meta "$1"
  git -C "$R" checkout -q main; git -C "$R" clean -qfdx -e .claude >/dev/null 2>&1
  printf '%s\n' "pr$1 a" > "$R/a"
  if [ "$4" = link ]; then mkdir -p "$TMP/linktarget$1"; echo "MINE" > "$TMP/linktarget$1/keep"; ln -s "$TMP/linktarget$1" "$R/$3"
  else printf '%s\n' "MINE" > "$R/$3"; fi
  printf '%s\n' "$3" >> "$R/.git/info/exclude"
  local before; before=$(git -C "$R" rev-parse main)
  gate "$1"
  if [ "$(git -C "$R" rev-parse main)" = "$before" ] && { [ "$4" = link ] && [ -L "$R/$3" ] || [ "$(cat "$R/$3" 2>/dev/null)" = MINE ]; } \
     && [ -z "$(git -C "$R" diff --cached --name-only)" ]; then ok "8 $5: main not moved, the private ignored $4 intact, nothing staged"
  else fail "8 $5: main moved or the private $4 changed: $(ls -la "$R/$3" 2>&1 | tail -1) | $(grep -E 'note|warning' "$TMP/gate$1.log" | cut -c1-160)"; fi
  rm -rf "${R:?}/$3"; resync
}
ignored_case 31 cfg/x cfg file "parent path is an ignored file"
ignored_case 34 nm/pkg/x nm link "parent path is an ignored symlink"
# 8 reset: main đã giữ commit của PR (squash lệch: đường reset --keep); origin còn nhận một commit đổi `a` VÀ thêm cfg/x; main có `a`
#   dở trùng byte origin và `cfg` là file riêng bị ignore.
branch 35 b "pr35 b"; git -C "$R" merge -q --ff-only issue-35-x
git -C "$R" checkout -q -b other-35 origin/main; printf '%s\n' "origin a 35" > "$R/a"; mkdir -p "$R/rcfg"; echo "from origin" > "$R/rcfg/x"
git -C "$R" add a rcfg/x; git -C "$R" commit -qm "origin edits a, adds rcfg/x"
git -C "$R" push -q origin other-35:refs/heads/main; git -C "$R" checkout -q main; git -C "$R" fetch -q origin
printf '%s\n' "origin a 35" > "$R/a"; echo MINE > "$R/rcfg"; printf 'rcfg\n' >> "$R/.git/info/exclude"
git -C "$R" diff --name-only main origin/main | grep -qx rcfg/x && git -C "$R" status --porcelain --ignored | grep -qx '!! rcfg' \
  || fail "8 reset path: fixture: origin does not add rcfg/x or main's rcfg is not an ignored file"
BEFORE35=$(git -C "$R" rev-parse main)
gate 35
[ "$(git -C "$R" rev-parse main)" = "$BEFORE35" ] && [ "$(cat "$R/rcfg" 2>/dev/null)" = MINE ] && [ -z "$(git -C "$R" diff --cached --name-only)" ] \
  && ok "8 reset path: main not moved, the private ignored file intact, nothing staged" \
  || fail "8 reset path: main moved or the private file changed: $(ls -la "$R/rcfg" 2>&1 | tail -1) | $(grep -E 'note|warning' "$TMP/gate35.log" | cut -c1-160)"
rm -rf "${R:?}/rcfg"; resync

# 8 NFD: như "8 reset path" nhưng origin thêm `café.local` với tên dạng NFD trong tree (review 18/10), còn main giữ file riêng bị ignore
#   cùng tên dạng NFC: APFS coi là một file, so chuỗi thì khác. Gate không được dời main.
branch 36 b2 "pr36 b2"; git -C "$R" merge -q --ff-only issue-36-x
NFD=$(printf 'cafe\314\201.local'); NFC=$(printf 'caf\303\251.local')
blob_a=$(printf '%s\n' "origin a 36" | git -C "$R" hash-object -w --stdin); blob_c=$(echo "from origin" | git -C "$R" hash-object -w --stdin)
IDX="$TMP/idx36"
GIT_INDEX_FILE="$IDX" git -C "$R" read-tree origin/main
GIT_INDEX_FILE="$IDX" git -C "$R" update-index --cacheinfo "100644,$blob_a,a"
GIT_INDEX_FILE="$IDX" git -C "$R" update-index --add --cacheinfo "100644,$blob_c,$NFD"
c36=$(git -C "$R" commit-tree "$(GIT_INDEX_FILE="$IDX" git -C "$R" write-tree)" -p origin/main -m "origin edits a, adds NFD name")
git -C "$R" push -q origin "$c36:refs/heads/main"; git -C "$R" fetch -q origin
printf '%s\n' "origin a 36" > "$R/a"; echo MINE > "$R/$NFC"; printf '*.local\n' >> "$R/.git/info/exclude"
git -C "$R" config core.precomposeunicode false   # true (mặc định git init trên macOS) thì git diff tự đổi NFD → NFC và ca này không thử gì
BEFORE36=$(git -C "$R" rev-parse main)
gate 36
[ "$(git -C "$R" rev-parse main)" = "$BEFORE36" ] && [ "$(cat "$R/$NFC" 2>/dev/null)" = MINE ] && [ -z "$(git -C "$R" diff --cached --name-only)" ] \
  && ok "8 NFD name vs NFC ignored file: main not moved, the private file intact" \
  || fail "8 NFD name vs NFC ignored file: main moved or the private file changed: $(cat "$R/$NFC" 2>&1) | $(grep -E 'note|warning' "$TMP/gate36.log" | cut -c1-160)"
git -C "$R" config --unset core.precomposeunicode; rm -f "$R/$NFC" "$R/$NFD"; resync
if [ "$(git -C "$R" config --get core.ignorecase)" = true ]; then
  ignored_case 33 Local2.json local2.json file "case-only variant on a case-insensitive disk"
else echo "skip 8 case-variant: core.ignorecase is not true"; fi

[ "$FAILS" -eq 0 ] && echo "✅ test_merge_gate_identical_sync: all passed" || { echo "❌ test_merge_gate_identical_sync: $FAILS failed"; exit 1; }
