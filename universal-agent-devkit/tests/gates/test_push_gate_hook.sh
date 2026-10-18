#!/usr/bin/env bash
# Regression test: hooks/block-dangerous-git.sh blocks a `git push` that the last full gate PASS
# does not cover (bin/push_gate.py), and lets it through once bin/post-fix-gate.py --full passed
# on that content. Audit 2026-09-28: `git push origin main` passed with no gate run at all.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${HOOK:-$DEVKIT_DIR/hooks/block-dangerous-git.sh}"; GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
hook() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$TMP/repo" \
  | CLAUDE_PROJECT_DIR="$TMP/repo" bash "$HOOK" >/dev/null 2>&1; }
expect() { hook "$2"; local rc=$?; [ "$rc" = "$3" ] && echo "✔ $1 (exit $rc)" || { echo "✖ $1: exit $rc, expected $3"; FAILS=$((FAILS + 1)); }; }
git init -q --bare "$TMP/remote.git"
mkdir -p "$TMP/repo/src" "$TMP/repo/.agents" && cd "$TMP/repo" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t && git remote add origin "$TMP/remote.git"
echo "fun ok() = 1" > src/Core.kt
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}
JSON
git add -A && git commit -qm init && git push -q -u origin main 2>/dev/null
gate() { CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --run-tests --full --brief "$@" >/dev/null 2>&1; }
echo "fun ok() = 2" > src/Core.kt && git commit -qam fix
expect "push with no gate run: blocked" "git push origin main" 2
expect "cd + push with no gate run: blocked" "cd $TMP/repo && git push" 2
gate --diff origin/main
expect "push after a full gate PASS of the commits (--diff origin/main): allowed" "git push origin main" 0
echo "fun ok() = 3" > src/Core.kt && git commit -qam "after gate"
expect "push of a commit made after the gate: blocked" "git push origin main" 2
git reset -q --soft HEAD~1; gate; git commit -qm "gated, then committed"
expect "gate on the dirty tree, then commit: allowed" "git push origin main" 0
# 18/10: nhánh ungated ở đây phải là trunk (develop): nhánh PR ungated nay push được không cần biên nhận (ca bên dưới)
git branch -q develop HEAD~1 2>/dev/null; git reset -q --soft HEAD~1; gate; git commit -qm "gated again"
git checkout -q develop && echo "fun ok() = 9" > src/Core.kt && git commit -qam "develop, never gated" && git checkout -q main
expect "one push of a gated branch plus an ungated trunk one: blocked" "git push origin main develop" 2
expect "the gated branch alone: allowed" "git push origin main" 0
expect "git status is never checked" "git status" 0

# 18/10 (người dùng, GeelyEx2): mỗi PR chạy --full HAI lần trên cùng nội dung — push nhánh PR đòi biên nhận, merge gate chạy lại.
# Push lên nhánh PR (đích không phải trunk) không cần biên nhận: merge gate chạy --full một lần trước khi gộp. Trunk vẫn cần.
echo "fun ok() = 4" > src/Core.kt && git commit -qam "PR code, never gated"
git branch -q feat/x && git branch -q -u origin/main feat/x 2>/dev/null
expect "PR: push origin feat/x, chưa gate: cho" "git push origin feat/x" 0
expect "PR: push origin HEAD:feat/x: cho" "git push origin HEAD:feat/x" 0
expect "PR: push -u origin HEAD:refs/heads/feat/x: cho" "git push -u origin HEAD:refs/heads/feat/x" 0
expect "trunk: push origin HEAD:main, chưa gate: chặn" "git push origin HEAD:main" 2
expect "trunk: push origin HEAD:refs/heads/main: chặn" "git push origin HEAD:refs/heads/main" 2
expect "trunk: push origin main (đang ở main): chặn" "git push origin main" 2
expect "trunk: push origin HEAD (đang ở main): chặn" "git push origin HEAD" 2
expect "trunk: git push trần ở main: chặn" "git push" 2
expect "trunk: push origin HEAD:MAIN: chặn" "git push origin HEAD:MAIN" 2
expect "PR + trunk trong một lệnh: chặn" "git push origin feat/x main" 2
expect "đích không giải được (\$b): chặn" 'git push origin $b:feat/x' 2
expect "--all: luật cũ, chặn" "git push --all origin" 2
git config remote.origin.push HEAD:refs/heads/main
expect "remote.origin.push ánh xạ lại đích: luật cũ, chặn" "git push origin feat/x" 2
git config --unset remote.origin.push
git tag feat/x 2>/dev/null
expect "đích trùng tên tag local: luật cũ, chặn" "git push origin HEAD:feat/x" 2
git tag -d feat/x >/dev/null
expect "--follow-tags đẩy kèm tag: luật cũ, chặn" "git push --follow-tags origin feat/x" 2
expect "--follow viết tắt: luật cũ, chặn" "git push --follow origin feat/x" 2
git config push.followTags true
expect "push.followTags=true: luật cũ, chặn" "git push origin feat/x" 2
git config --unset push.followTags
git tag v4 feat/x
expect "nguồn là tag, đích ngắn (git tạo refs/tags/feat/x): luật cũ, chặn" "git push origin v4:feat/x" 2
git tag -d v4 >/dev/null
git branch -q feat/y && git -C "$TMP/remote.git" update-ref refs/tags/feat/y "$(git -C "$TMP/remote.git" rev-parse main)"
expect "remote đã có TAG feat/y (chưa fetch): HEAD:feat/y ghi vào tag đó, chặn" "git push origin HEAD:feat/y" 2
expect "cùng tên nhưng ghi rõ refs/heads/feat/y: cho" "git push origin HEAD:refs/heads/feat/y" 0
git branch -q fix/config-loader
expect "nhánh có chữ config trong tên (fix/config-loader): vẫn cho" "git push origin fix/config-loader" 0
git config remote.origin.mirror false
expect "remote.origin.mirror=false: vẫn cho" "git push origin HEAD:feat/x" 0
git config remote.origin.mirror yes
expect "remote.origin.mirror=yes (bool của git): luật cũ, chặn" "git push origin HEAD:feat/x" 2
git config remote.origin.mirror true
expect "remote.origin.mirror=true: luật cũ, chặn" "git push origin HEAD:feat/x" 2
git config --unset remote.origin.mirror
git checkout -q feat/x && git config branch.feat/x.remote origin && git config branch.feat/x.merge refs/heads/feat/x
expect "PR: git push trần trên feat/x (upstream origin/feat/x): cho" "git push" 0
expect "PR: push origin HEAD trên feat/x: cho" "git push origin HEAD" 0
expect "trên feat/x, refspec không giải được (\$b): luật cũ, chặn" 'git push origin $b' 2
expect "trên feat/x, feat/x kèm một \$(…) không giải được: luật cũ, chặn" 'git push origin feat/x "$(cat ref)"' 2
git config push.default upstream
expect "push.default=upstream: không tự suy đích, luật cũ (chặn)" "git push" 2
git config branch.feat/x.merge refs/heads/main
# review 18/10: upstream/tracking ánh xạ cả `git push origin feat/x` sang branch.feat/x.merge = main (git đã đo: main bị ghi)
expect "push.default=upstream, git push origin feat/x (merge=main): chặn" "git push origin feat/x" 2
expect "push.default=upstream, refs/heads/feat/x không có ':' (merge=main): chặn" "git push origin refs/heads/feat/x" 2
expect "push.default=upstream, nhưng HEAD:refs/heads/feat/x ghi rõ đích: cho" "git push origin HEAD:refs/heads/feat/x" 0
git config push.default tracking
expect "push.default=tracking, git push origin feat/x (merge=main): chặn" "git push origin feat/x" 2
expect "push.default=upstream, upstream là main: chặn" "git push" 2
git config push.default matching
expect "push.default=matching: luật cũ, chặn" "git push" 2
git config --unset push.default
expect "-c push.default=upstream (upstream là main): luật cũ, chặn" "git -c push.default=upstream push" 2
expect "-c vô hại vẫn tắt lối tắt (fail closed)" "git -c color.ui=never push origin HEAD:feat/x" 2
expect "ghi config rồi push cùng lệnh: luật cũ, chặn" "git config push.default upstream && git push" 2
expect "ghi config rồi xuống dòng git push: luật cũ, chặn" "git config push.default upstream
git push" 2
expect "GIT_CONFIG_PARAMETERS: luật cũ, chặn" "GIT_CONFIG_PARAMETERS=\"'push.default=upstream'\" git push" 2
mkdir -p "$TMP/home" && printf '[push]\n\tdefault = upstream\n' > "$TMP/home/.gitconfig"
expect "HOME=<thư mục có .gitconfig> git push: luật cũ, chặn" "HOME=$TMP/home git push origin feat/x" 2
expect "ghi .git/con''fig (chữ bị tách) rồi push: luật cũ, chặn" "printf '[push]\\n\\tdefault = upstream\\n' >> .git/con''fig; git push origin feat/x" 2
expect "--repo=X kèm remote vị trí: luật cũ, chặn" "git push --repo=origin origin HEAD:refs/heads/feat/x" 2
expect "--repo X (cách) kèm remote vị trí: luật cũ, chặn" "git push --repo origin origin HEAD:refs/heads/feat/x" 2
expect "cd <đường dẫn> && git push origin feat/x: cho" "cd $TMP/repo && git push origin feat/x" 0
expect "-c push.followTags (bật true, không có =): chặn" "git -c push.followTags push origin feat/x" 2
expect "-c remote.origin.push trên nhánh PR: chặn" "git -c remote.origin.push=refs/heads/main push origin feat/x" 2
git config branch.feat/x.merge refs/heads/feat/x
expect "PR: lại cho khi không có ghi đè config" "git push" 0
git checkout -q main
[ "$FAILS" -eq 0 ] && echo "push gate hook: all checks passed" || { echo "push gate hook: $FAILS FAILED"; exit 1; }
