#!/usr/bin/env bash
# worktree.py đọc nội dung bằng `git show` / `git diff` porcelain: chúng chạy diff.<drv>.textconv (và diff ngoài) theo attribute của
# repo. Một textconv lossy (docx/pdf → text; ở đây mọi phiên bản *.bin đọc ra "same") làm một thay đổi nhị phân VÔ HÌNH (OCR review
# 26/10): _clean_merges thấy `show --cc` rỗng (merge có sửa riêng bị coi là sạch), _patch_already_in_main và `same_bytes` của
# _reflog_only nhận `diff --quiet` rc 0 (commit chỉ reflog giữ bị coi là main đã có → `remove` gỡ worktree, commit mất), `restore`
# không thấy sửa chưa commit (checkout đè lên), `worktree diff` ra patch không mang byte nào, `_sync_main_to` không thấy thay đổi đã
# stage của main. Mọi lệnh đó nay chạy `--no-textconv --no-ext-diff`, như `log -p` của _same_patches_verbatim.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WT="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@example.invalid -c user.name=t "${@:2}"; }

R="$TMP/repo"; mkdir -p "$R"; G "$R" init -q -b main
printf '*.bin diff=lossy\n' > "$R/.gitattributes"; printf '\000\001base' > "$R/b.bin"; echo t > "$R/t.txt"
G "$R" add -A; G "$R" commit -qm base
G "$R" config diff.lossy.textconv "sh -c 'echo same'"
H="$R/.claude/worktrees"; mkdir -p "$H"

# 1. a commit with a binary change main lacks, that only the worktree's HEAD reflog still names
G "$R" worktree add -q --detach "$H/lost" main
printf '\000\001LOST' > "$H/lost/b.bin"; G "$H/lost" commit -qam "binary work"; LOST="$(G "$H/lost" rev-parse HEAD)"
G "$H/lost" checkout -q --detach main
G "$R" diff --quiet main "$LOST" -- b.bin && ok "setup: the lossy textconv hides the binary change from a plain git diff" \
  || fail "setup: the textconv does not hide the change (the fixture proves nothing)"

out="$(python3 -B - "$DEVKIT_DIR/scripts/git" "$R" "$H/lost" "$LOST" <<'PY' 2>&1
import os, subprocess, sys
sys.path.insert(0, sys.argv[1])
import worktree as wt
repo, lost_wt, lost = sys.argv[2], sys.argv[3], sys.argv[4]
def g(*a):
    return subprocess.run(["git", "-C", repo, "-c", "user.email=t@t", "-c", "user.name=t", *a], capture_output=True, text=True, check=True).stdout.strip()
def tree(data):
    with open(os.path.join(repo, "b.bin"), "wb") as f:
        f.write(data)
    g("add", "b.bin")
    return g("write-tree")
c0 = g("rev-parse", "HEAD")
main = g("commit-tree", tree(b"\0\1main"), "-p", c0, "-m", "main")
side = g("commit-tree", tree(b"\0\1side"), "-p", c0, "-m", "side")
evil = g("commit-tree", tree(b"\0\1EVIL"), "-p", main, "-p", side, "-m", "merge with an edit of its own")
g("reset", "-q", "--hard", "HEAD")
print("patch_in_main", wt._patch_already_in_main(repo, main, side))
print("clean_merge", evil in wt._clean_merges(repo, {evil}))
# same_bytes alone (_patch_already_in_main answers first in the real flow, so it is held off here)
wt._patch_already_in_main = lambda *a, **k: False
refs = g("for-each-ref", "--format=%(objectname)", "refs/heads", "refs/remotes", "refs/tags").split()
head = subprocess.run(["git", "-C", lost_wt, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
print("reflog_lost", lost in (wt._reflog_only(lost_wt, head, g("rev-parse", "main"), refs) or []))
PY
)"
case "$out" in *Traceback*) fail "a check crashed: $(echo "$out" | tail -1)" ;; esac
echo "$out" | grep -qx "patch_in_main False" && ok "_patch_already_in_main: a binary change the textconv hides is not 'already in main'" \
  || fail "_patch_already_in_main: $out"
echo "$out" | grep -qx "clean_merge False" && ok "_clean_merges: a merge whose own binary edit the textconv hides is not clean" \
  || fail "_clean_merges: $out"
echo "$out" | grep -qx "reflog_lost True" && ok "_reflog_only same_bytes: the reflog-only binary commit counts as lost" \
  || fail "_reflog_only: $out"

# 2. `remove` end to end: that worktree holds the only copy of the binary commit
(cd "$R" && python3 -B "$WT" remove "$H/lost" >"$TMP/rm.out" 2>&1); rc=$?
[ "$rc" -ne 0 ] && [ -d "$H/lost" ] && ok "remove refuses the worktree whose reflog-only binary commit the textconv hides" \
  || { fail "remove rc=$rc: the reflog-only binary commit went with the worktree"; tail -3 "$TMP/rm.out"; }

# 3. `restore` must not overwrite an uncommitted binary edit
G "$R" worktree add -q --detach "$H/rst" main
printf '\000\001EDIT' > "$H/rst/b.bin"
(cd "$H/rst" && python3 -B "$WT" restore HEAD -- b.bin >"$TMP/rst.out" 2>&1); rc=$?
[ "$rc" -ne 0 ] && [ "$(od -An -c "$H/rst/b.bin" | tr -d ' \n')" = '\0001EDIT' ] && grep -q "uncommitted" "$TMP/rst.out" \
  && ok "restore refuses a path whose uncommitted binary edit the textconv hides" \
  || { fail "restore rc=$rc overwrote the uncommitted binary edit"; cat "$TMP/rst.out"; }

# 4. `worktree diff` carries the binary bytes, not the textconv's text
G "$R" worktree add -q --detach "$H/carry" main
printf '{"base":"%s","baseline":{},"fp":2}\n' "$(G "$R" rev-parse main)" > "$(G "$H/carry" rev-parse --absolute-git-dir)/devkit-worktree.json"
printf '\000\001CARRY' > "$H/carry/b.bin"
(cd "$R" && python3 -B "$WT" diff "$H/carry" >"$TMP/carry.patch" 2>"$TMP/carry.err"); rc=$?
[ "$rc" -eq 0 ] && grep -q "GIT binary patch" "$TMP/carry.patch" && ok "worktree diff carries the binary change as a binary patch" \
  || { fail "worktree diff rc=$rc: no binary patch for the edit"; head -8 "$TMP/carry.patch"; cat "$TMP/carry.err"; }

# 5. `_sync_main_to`: a staged binary change in main's index blocks the reset --keep (another session's work)
R2="$TMP/repo2"; mkdir -p "$R2"; G "$R2" init -q -b main
printf '*.bin diff=lossy\n' > "$R2/.gitattributes"; printf '\000\001base' > "$R2/b.bin"; G "$R2" add -A; G "$R2" commit -qm base
G "$R2" config diff.lossy.textconv "sh -c 'echo same'"
echo a > "$R2/a.txt"; G "$R2" add a.txt; G "$R2" commit -qm "local a"
SQ="$(G "$R2" commit-tree "$(G "$R2" rev-parse 'HEAD^{tree}')" -p HEAD~1 -m "a (squash on origin)")"
printf '\000\001STAGED' > "$R2/b.bin"; G "$R2" add b.bin
out="$(python3 -B - "$DEVKIT_DIR/scripts/git" "$R2" "$SQ" <<'PY' 2>&1
import sys
sys.path.insert(0, sys.argv[1])
import worktree as wt
r = wt._sync_main_to(sys.argv[2], sys.argv[3])
print("sync", "None" if r is None else r[1])
PY
)"
echo "$out" | grep -q "staged" && ok "_sync_main_to: a staged binary change the textconv hides blocks the reset" \
  || fail "_sync_main_to: $out"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
