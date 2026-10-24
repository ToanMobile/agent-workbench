#!/usr/bin/env bash
# Hồi quy (#386, từ #346 ngày 24/10): `worktree remove` chặn nhầm vì coi việc đã có trên origin là "mất":
#   o1. commit chỉ có trên origin/issue-* (đã fetch), không có ở nhánh local hay main: gỡ được
#   o2. (âm) commit không có ở đâu cả (chưa push): vẫn từ chối
#   o3. merge sạch (combined diff rỗng) của hai parent đã an toàn, chính nó chưa push: gỡ được
#   o4. (âm) merge có giải xung đột (combined diff khác rỗng): vẫn từ chối
#   o5. file chưa commit trùng byte (và mode) bản trên origin/<nhánh PR>: gỡ được
#   o6. (âm) file chưa commit khác một byte: vẫn từ chối
#   o7. dựng lại #346: detached ở merge sạch + file trùng origin: gỡ được, không cần --force
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

git init -q --bare -b main "$TMP/origin.git"
R="$TMP/r"; mkdir -p "$R" && G "$R" init -q -b main . && cd "$R" || exit 1
G "$R" config devkit.trunkMode true; G "$R" remote add origin "$TMP/origin.git"
printf 'a1\n' > a.txt; printf 'm1\n' > m.txt; printf 'f1\n' > f.txt
G "$R" add -A && G "$R" commit -qm init && G "$R" push -q origin main
# PR branch on origin only (a clone pushes it): two commits on f.txt / p.txt
git clone -q "$TMP/origin.git" "$TMP/pr" && G "$TMP/pr" checkout -q -b issue-9-x
printf 'f2\n' > "$TMP/pr/f.txt"; G "$TMP/pr" commit -qam p1
printf 'p\n' > "$TMP/pr/p.txt"; printf '#!/bin/sh\n' > "$TMP/pr/run.sh"; chmod +x "$TMP/pr/run.sh"; G "$TMP/pr" add -A; G "$TMP/pr" commit -qm p2
G "$TMP/pr" push -q origin issue-9-x
G "$R" fetch -q origin
# main advances locally (a commit on no PR branch)
printf 'm2\n' > m.txt; G "$R" commit -qam main2
mk() { bash "$KIT" worktree add "../$1" >/dev/null 2>&1 || fail "add $1"; G "$TMP/$1" checkout -q --detach; }
force_rm() { G "$R" worktree remove --force "$TMP/$1" >/dev/null 2>&1; G "$R" branch -D issue-9-x >/dev/null 2>&1; true; }
rm_wt() { ( cd "$R" && bash "$KIT" worktree remove "../$1" >"$TMP/$1.out" 2>&1 ); echo $?; }

# o1 / o2
mk w1; G "$TMP/w1" reset -q --hard origin/issue-9-x
rc=$(rm_wt w1); [ "$rc" = 0 ] && [ ! -d "$TMP/w1" ] && ok "o1 commit only on origin/issue-9-x: removed" || { fail "o1 refused (rc=$rc)"; cat "$TMP/w1.out"; }
mk w2; printf 'z\n' > "$TMP/w2/z.txt"; G "$TMP/w2" add z.txt; G "$TMP/w2" commit -qm lone
rc=$(rm_wt w2); [ "$rc" = 1 ] && [ -d "$TMP/w2" ] && ok "o2 unpushed commit: still refused" || { fail "o2 not refused (rc=$rc)"; cat "$TMP/w2.out"; }

# o3 / o4: merge of origin/issue-9-x into local main's line, clean vs conflict-resolved
mk w3; G "$TMP/w3" merge -q --no-ff -m clean origin/issue-9-x
rc=$(rm_wt w3); [ "$rc" = 0 ] && [ ! -d "$TMP/w3" ] && ok "o3 clean merge of safe parents: removed" || { fail "o3 refused (rc=$rc)"; cat "$TMP/w3.out"; }
mk w4; G "$TMP/w4" merge -q --no-ff --no-commit origin/issue-9-x; printf 'resolved\n' > "$TMP/w4/f.txt"; G "$TMP/w4" add f.txt; G "$TMP/w4" commit -qm evil
rc=$(rm_wt w4); [ "$rc" = 1 ] && [ -d "$TMP/w4" ] && ok "o4 merge with own content: still refused" || { fail "o4 not refused (rc=$rc)"; cat "$TMP/w4.out"; }

# o5 / o6: uncommitted file equal / different to origin's PR branch (worktree on a branch of that name)
mk w5; G "$TMP/w5" checkout -q -B issue-9-x origin/issue-9-x; G "$TMP/w5" reset -q --hard origin/issue-9-x~1
git -C "$TMP/w5" show origin/issue-9-x:f.txt > "$TMP/w5/f.txt"; git -C "$TMP/w5" show origin/issue-9-x:p.txt > "$TMP/w5/p.txt"
git -C "$TMP/w5" show origin/issue-9-x:run.sh > "$TMP/w5/run.sh"; chmod +x "$TMP/w5/run.sh"
rc=$(rm_wt w5); [ "$rc" = 0 ] && [ ! -d "$TMP/w5" ] && ok "o5 uncommitted files equal to origin's PR branch: removed" || { fail "o5 refused (rc=$rc)"; cat "$TMP/w5.out"; }
force_rm w5; mk w6; G "$TMP/w6" checkout -q -B issue-9-x origin/issue-9-x~1
printf 'f2x\n' > "$TMP/w6/f.txt"
rc=$(rm_wt w6); [ "$rc" = 1 ] && [ -d "$TMP/w6" ] && ok "o6 file differing by a byte: still refused" || { fail "o6 not refused (rc=$rc)"; cat "$TMP/w6.out"; }
force_rm w6; mk w6b; G "$TMP/w6b" checkout -q -B issue-9-x origin/issue-9-x~1
printf 'p\n' > "$TMP/w6b/p.txt"; printf '#!/bin/sh\n' > "$TMP/w6b/run.sh"   # same bytes, but run.sh lacks the executable bit
rc=$(rm_wt w6b); [ "$rc" = 1 ] && [ -d "$TMP/w6b" ] && ok "o6b same bytes, other mode: still refused" || { fail "o6b not refused (rc=$rc)"; cat "$TMP/w6b.out"; }

# o7: #346 — detached at a clean local merge of main into the PR's parent, other files equal to origin's PR tip, no local branch
force_rm w6b; mk w7; G "$TMP/w7" merge -q --no-ff -m "merge main" origin/issue-9-x~1
git -C "$TMP/w7" show origin/issue-9-x:p.txt > "$TMP/w7/p.txt"; git -C "$TMP/w7" show origin/issue-9-x:f.txt > "$TMP/w7/f.txt"
rc=$(rm_wt w7); [ "$rc" = 0 ] && [ ! -d "$TMP/w7" ] && ok "o7 #346 shape: removed without --force" || { fail "o7 refused (rc=$rc)"; cat "$TMP/w7.out"; }
[ "$FAILS" = 0 ] && { echo "remove_origin_safe: all passed"; exit 0; } || { echo "remove_origin_safe: $FAILS FAILED"; exit 1; }
