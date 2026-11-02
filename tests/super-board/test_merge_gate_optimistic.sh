#!/usr/bin/env bash
# PR3 (merge gate optimistic) — test ĐỎ nháp. Đích: tests/super-board/test_merge_gate_optimistic.sh.
# Hôm nay merge gate giữ khoá merge suốt verify (20–35 phút): gate thứ hai, PR không đụng PR thứ nhất, chờ ở acquire cả lượt verify của
# gate thứ nhất. Sau PR3: verify chạy NGOÀI khoá; khoá ngắn trước merge đọc lại origin/<base> (BASE_NOW); base dời thì verify lại ĐÚNG lệnh
# trên merge(BASE_NOW, head) (suite cache theo input: suite không bị đụng không chạy lại), tối đa 2 lần ngoài khoá, lần cuối trong khoá.
#   M1 verify của gate 2 bắt đầu khi verify của gate 1 còn chạy            (ĐỎ hôm nay)
#   M2 verify lần 1 của mỗi gate không giữ khoá merge                       (ĐỎ hôm nay)
#   M3 gate 2 verify lại trên cây có f1, lần đó 0 suite chạy (cache giả)    (ĐỎ hôm nay)
#   M4 verify cuối của gate 2 chạy trên merge-tree(BASE_NOW, head2)         (lưới an toàn: xanh cả trước lẫn sau)
#   C1 main dời chạm input suite ⇒ suite chạy lại; C2 main dời đổi TẬP CHỌN ⇒ suite mới chạy;
#   C3 base dời trong 3 lần verify ⇒ 4 lần verify, lần 4 trong khoá; C4 base dời sau verify trong khoá ⇒ exit 4, không merge.
# "0 suite" của post-fix-gate THẬT không kiểm ở đây: verify giả mô phỏng cache theo input (khoá = tên suite + nội dung input).
# Cả hai gate chạy từ CÙNG một worktree: khoá chung cả trước lẫn sau rmlock (khoá ở git common dir), nên M1 đỏ vì khoá, không vì đường khoá.
# Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
export SB_NOTIFY_SKIP=1
ROOT="${SB_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-optimistic-test.XXXXXX")"
trap 'touch "$TMP"/release* 2>/dev/null; kill $(jobs -p) 2>/dev/null; wait 2>/dev/null; rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/review"; B="$TMP/builder"; M="$TMP/merger"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n' > "$R/.gitignore"
mkdir -p "$R/.agents"; echo '[]' > "$R/.agents/regression_matrix.active.json"
# suites.txt: "<suite> <input>…". Verify giả chọn suite có input nằm trong diff của PR (như --scoped), khoá = suite + nội dung input.
printf 's1 f1\ns2 f2\ns3 f3 lib\ns4 f4\ns5 f5\ns6 f6\n' > "$R/suites.txt"
echo lib0 > "$R/lib"
git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
git -C "$R" fetch -q origin
git -C "$R" worktree add -q --detach "$WT" main
git clone -q "$O" "$B"; git -C "$B" config user.email t@example.invalid; git -C "$B" config user.name t
git clone -q "$O" "$M"; git -C "$M" config user.email t@example.invalid; git -C "$M" config user.name t

# PR n: nhánh issue-n-x từ main lúc tạo, thêm file f<n>. Không có nhánh local trong R (dọn sau merge không đụng worktree của test).
mkpr() {
  local n="$1" h
  git -C "$B" fetch -q origin; git -C "$B" checkout -q -B "issue-$n-x" origin/main
  echo "pr$n" > "$B/f$n"; git -C "$B" add "f$n"; git -C "$B" commit -qm "card$n"
  git -C "$B" push -q origin "issue-$n-x"
  h=$(git -C "$B" rev-parse HEAD)
  git -C "$B" diff "$h~1" "$h" > "$TMP/pr$n.diff"
  printf '{"files":[{"path":"f%s"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' "$n" > "$TMP/pr$n.meta"
  echo "$h" > "$TMP/pr$n.head"
}

# gh giả. `pr merge` squash-push THẬT vào origin (không thì BASE_NOW không bao giờ khác BASE_SHA) rồi PR thành MERGED.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"--json mergeable"*) echo MERGEABLE ;;
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*)
    if [ -s "$FAKE_DIR/merged$n" ]; then printf '{"state":"MERGED","mergeCommit":{"oid":"%s"},"headRefOid":"%s"}\n' "$(cat "$FAKE_DIR/merged$n")" "$head"
    else printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head"; fi ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr view "*"--json body"*) jq -r '.body // ""' "$FAKE_DIR/pr$n.meta" ;;
  *" pr view "*"--json title"*) echo "fix: t" ;;
  *" pr view "*"mergeCommit"*) [ -s "$FAKE_DIR/merged$n" ] && cat "$FAKE_DIR/merged$n" || echo "" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr comment "*) : ;;
  *" pr merge "*)
    ( cd "$FAKE_DIR/merger" && git fetch -q origin && git checkout -q -B main origin/main \
        && git merge -q --squash "origin/issue-$n-x" && git commit -qm "squash #$n" && git push -q origin main ) >&2 || exit 1
    git -C "$FAKE_DIR/merger" rev-parse HEAD > "$FAKE_DIR/merged$n"
    echo "merged #$n" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
. "$ROOT/tests/super-board/lib/fake_ci_checks.sh"; sb_ci_checks_fixture "$TMP/bin"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_RETRY_DELAY=0 SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_HELD=1
export DEVKIT_SLOT_LOAD_FILE="$TMP/slot-load"; echo 1 > "$DEVKIT_SLOT_LOAD_FILE"
mkdir -p "$TMP/cache"
# Đường khoá merge: sau rmlock ở git common dir, trước rmlock dưới REPO_PATH (= WT). Verify giả đọc file `pr` của khoá nào đang có.
printf '%s\n%s\n' "$(cd "$R" && cd "$(git rev-parse --git-common-dir)" && pwd -P)/super-board/merge.lock" \
  "$WT/.claude/super-board/inflight/merge.lock" > "$TMP/lockpaths"

# move.sh <n> <inv>: main dời trong lúc verify (một merge khác vừa vào). Loại theo movekind<n>: lib (chạm input của s3), sel (thêm suite
# mới chọn f<n>), other (file không ai đọc).
cat > "$TMP/move.sh" <<'SH'
#!/usr/bin/env bash
n="$1" inv="$2"; cd "$FAKE_DIR/merger" || exit 1
git fetch -q origin && git checkout -q -B main origin/main || exit 1
case "$(cat "$FAKE_DIR/movekind$n" 2>/dev/null)" in
  lib) echo "lib $n $inv" >> lib ;;
  sel) echo "x$n$inv f$n" >> suites.txt ;;
  *) echo "$n $inv" >> "other$n" ;;
esac
git add -A && git commit -qm "main moves ($n/$inv)" && git push -q origin main
SH
# verify.sh <n>: lệnh verify giả (cwd = scratch). Ghi vlog: start (lần thứ mấy, cây, có f1, PR đang giữ khoá), hit/run từng suite, end.
cat > "$TMP/verify.sh" <<'SH'
#!/usr/bin/env bash
n="$1"; T="$FAKE_DIR"
lockpr=none
while IFS= read -r l; do [ -r "$l/pr" ] && { lockpr=$(cat "$l/pr"); break; }; done < "$T/lockpaths"
inv=$(( $(grep -c "^start $n " "$T/vlog" 2>/dev/null || true) + 1 ))
has1=0; [ -f f1 ] && has1=1
echo "start $n inv=$inv tree=$(git rev-parse 'HEAD^{tree}') has_f1=$has1 lockpr=$lockpr" >> "$T/vlog"
if [ -f "$T/move$n" ] && [ "$inv" -le "$(cat "$T/move$n")" ]; then bash "$T/move.sh" "$n" "$inv" >/dev/null 2>&1; fi
mb=$(git merge-base origin/main HEAD 2>/dev/null)
changed=$(git diff --name-only "${mb:-HEAD}" HEAD)
miss=0
while read -r name inputs; do
  [ -n "$name" ] || continue
  sel=0; for i in $inputs; do printf '%s\n' "$changed" | grep -qx "$i" && sel=1; done
  [ "$sel" -eq 1 ] || continue
  key=$( { echo "$name"; for i in $inputs; do echo "== $i"; cat "$i" 2>/dev/null; done; } | shasum -a 256 | cut -c1-24)
  if [ -e "$T/cache/$key" ]; then echo "hit $n inv=$inv $name" >> "$T/vlog"
  else echo "run $n inv=$inv $name" >> "$T/vlog"; miss=1; : > "$T/cache/$key"; fi
done < suites.txt
if [ "$miss" -eq 1 ] && [ -f "$T/block$n" ]; then
  w=0; while [ ! -e "$T/release$n" ] && [ "$w" -lt 900 ]; do sleep 0.1; w=$((w + 1)); done
fi
echo "end $n inv=$inv" >> "$T/vlog"
exit 0
SH

gate() {  # gate <n> [args…] — chạy từ WT; ghi $TMP/gate<n>.log, mã thoát vào $TMP/rc<n>
  local n="$1" cfg="$TMP/cfg$1.json"; shift
  python3 -c 'import json,sys; print(json.dumps({"base_branch":"main","repo":{"path":".","remote":"https://github.com/o/r"},"project":{"owner":"o","number":1},"verify_commands":[sys.argv[1]]}))' \
    "bash $TMP/verify.sh $n" > "$cfg"
  ( cd "$WT" && SB_GITHUB_HALT_FILE="$TMP/halt$n.json" bash "$GATE" --config "$cfg" --pr "$n" \
      --expect-head "$(cat "$TMP/pr$n.head")" --lock-timeout 120 "$@" ) >"$TMP/gate$n.log" 2>&1
  echo $? > "$TMP/rc$n"
}
rc() { cat "$TMP/rc$1" 2>/dev/null || echo none; }
# wait_for <giây> <lệnh…>: chờ tới khi lệnh đúng.
wait_for() { local s="$1" n=0; shift; while ! "$@"; do [ "$n" -ge $((s * 10)) ] && return 1; sleep 0.1; n=$((n + 1)); done; }
vlog_has() { grep -q "$1" "$TMP/vlog" 2>/dev/null; }
line_no() { grep -n "$1" "$TMP/vlog" 2>/dev/null | head -1 | cut -d: -f1; }
starts() { grep -c "^start $1 " "$TMP/vlog" 2>/dev/null || true; }
why() { grep 'merge-gate' "$TMP/gate$1.log" | tail -4 | tr '\n' '|'; }
origin_has() { git -C "$M" fetch -q origin && git -C "$M" cat-file -e "origin/main:$1" 2>/dev/null; }

# ── M: hai PR không đụng nhau, hai gate song song ────────────────────────────────────────────────
mkpr 1; mkpr 2
: > "$TMP/block1"; : > "$TMP/block2"
gate 1 & G1=$!
wait_for 60 vlog_has '^start 1 inv=1' || fail "setup: gate 1 never started its verify: $(why 1)"
gate 2 & G2=$!
if wait_for 20 vlog_has '^start 2 inv=1'; then
  L2=$(line_no '^start 2 inv=1'); E1=$(line_no '^end 1 inv=1')
  { [ -z "$E1" ] || [ "$L2" -lt "$E1" ]; } && ok "M1: gate 2 verifies while gate 1 is still verifying" \
    || fail "M1: gate 2 started verifying only after gate 1 finished"
else
  fail "M1: gate 2 did not start verifying while gate 1 verified (it waits for the merge lock through the whole verify)"
fi
touch "$TMP/release1"
wait_for 90 test -s "$TMP/merged1" || fail "setup: gate 1 never merged (rc=$(rc 1)): $(why 1)"
touch "$TMP/release2"
wait "$G1" 2>/dev/null; wait "$G2" 2>/dev/null
[ "$(rc 1)" = 0 ] && [ "$(rc 2)" = 0 ] && origin_has f1 && origin_has f2 \
  && ok "M: both gates merge (exit 0), origin/main has f1 and f2" \
  || fail "M: rc1=$(rc 1) rc2=$(rc 2): $(why 1) / $(why 2)"
grep -q '^start 1 inv=1 .*lockpr=none' "$TMP/vlog" && grep -q '^start 2 inv=1 .*lockpr=none' "$TMP/vlog" \
  && ok "M2: the first verify of each gate runs without the merge lock" \
  || fail "M2: a first verify ran inside the merge lock: $(grep '^start [12] inv=1' "$TMP/vlog" | tr '\n' '|')"
if grep -q '^start 2 inv=2 .*has_f1=1' "$TMP/vlog" && ! grep -q '^run 2 inv=2 ' "$TMP/vlog" && grep -q '^hit 2 inv=2 s2' "$TMP/vlog"; then
  ok "M3: base moved under gate 2: it verified merge(BASE_NOW, head) again and ran 0 suites (s2 reused by input)"
else
  fail "M3: gate 2 did not re-verify on the moved base with 0 suites run: $(grep ' 2 inv=' "$TMP/vlog" | tr '\n' '|')"
fi
BASE_NOW=$(cat "$TMP/merged1" 2>/dev/null)
WANT=$(git -C "$R" merge-tree --write-tree "$BASE_NOW" "$(cat "$TMP/pr2.head")" 2>/dev/null | head -1)
LAST2=$(grep '^start 2 ' "$TMP/vlog" | tail -1 | sed -n 's/.* tree=\([0-9a-f]*\) .*/\1/p')
[ -n "$WANT" ] && [ "$LAST2" = "$WANT" ] \
  && ok "M4: gate 2's last verify before merging ran on merge-tree(BASE_NOW, head2)" \
  || fail "M4: gate 2 merged without a verify of merge(BASE_NOW, head2) (last tree ${LAST2:-none}, want ${WANT:-?})"

# ── C1: main dời CHẠM input của suite đã chọn ⇒ suite chạy lại ──────────────────────────────────
mkpr 3; echo 1 > "$TMP/move3"; echo lib > "$TMP/movekind3"
gate 3
[ "$(rc 3)" = 0 ] && [ "$(starts 3)" -eq 2 ] && grep -q '^run 3 inv=2 s3' "$TMP/vlog" \
  && ok "C1: main changed an input of s3 during verify: re-verified, s3 ran again" \
  || fail "C1: rc=$(rc 3) verifies=$(starts 3): $(grep ' 3 inv=' "$TMP/vlog" | tr '\n' '|') $(why 3)"

# ── C2: main dời đổi TẬP CHỌN (suite mới chọn file của PR) ⇒ suite mới chạy, suite cũ dùng lại ──
mkpr 4; echo 1 > "$TMP/move4"; echo sel > "$TMP/movekind4"
gate 4
[ "$(rc 4)" = 0 ] && grep -q '^run 4 inv=2 x41' "$TMP/vlog" && grep -q '^hit 4 inv=2 s4' "$TMP/vlog" \
  && ok "C2: main added a suite that selects f4: the new suite ran, s4 was reused" \
  || fail "C2: rc=$(rc 4): $(grep ' 4 inv=' "$TMP/vlog" | tr '\n' '|') $(why 4)"

# ── C3: base dời trong 3 lần verify ⇒ 2 lần lại ngoài khoá, lần 4 trong khoá, rồi merge ─────────
mkpr 5; echo 3 > "$TMP/move5"; echo other > "$TMP/movekind5"
gate 5
[ "$(rc 5)" = 0 ] && [ "$(starts 5)" -eq 4 ] && grep -q '^start 5 inv=4 .*lockpr=5' "$TMP/vlog" \
  && [ "$(grep -c '^start 5 inv=[123] .*lockpr=none' "$TMP/vlog")" -eq 3 ] && origin_has f5 \
  && ok "C3: base moved 3 times: 2 re-verifies outside the lock, the 4th inside it, then merged" \
  || fail "C3: rc=$(rc 5) verifies=$(starts 5): $(grep '^start 5 ' "$TMP/vlog" | tr '\n' '|') $(why 5)"

# ── C4: base dời cả trong lần verify trong khoá (push ngoài gate) ⇒ exit 4, không merge ───────────
mkpr 6; echo 4 > "$TMP/move6"; echo other > "$TMP/movekind6"
gate 6
[ "$(rc 6)" = 4 ] && [ ! -s "$TMP/merged6" ] \
  && ok "C4: base moved while the gate held the lock: exit 4, nothing merged" \
  || fail "C4: rc=$(rc 6) merged=$(cat "$TMP/merged6" 2>/dev/null || echo no): $(why 6)"

echo "---"; [ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; } || { echo "FAIL ($FAILS)"; exit 1; }
