#!/usr/bin/env bash
# Test hồi quy cho .claude/bin/super-board-scratch-config.sh (merge gate dựng worktree sạch để verify).
# 2026-10-16 (OfficeReader #73, PR #126): review đạt, test xanh, nhưng merge gate đỏ vì worktree sạch thiếu
# google-services.json (file bị git ignore), build Android hỏng, thẻ kẹt ở Review chờ người.
# Config cục bộ bị git ignore phải được chép từ main checkout; file không bị ignore thì không chép (không commit nhầm).
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="$ROOT/.claude/bin/super-board-scratch-config.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-scratchcfg-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; S="$TMP/scratch"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
mkdir -p "$R/app/libs"
printf 'google-services.json\nlocal.properties\n*.aar\n*.jks\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add .gitignore a; git -C "$R" commit -qm init
echo '{"project_info":{}}' > "$R/app/google-services.json"
echo 'sdk.dir=/x' > "$R/local.properties"
echo 'TOKEN=x' > "$R/.env"                      # không bị ignore: không được chép
# Build input bị ignore (aar trong libs/, keystore): thiếu chúng build trong worktree sạch cũng đỏ.
echo aar > "$R/app/libs/sdk.aar"; echo jks > "$R/app/release.jks"
# DevKit cũ đứng đầu danh sách ứng viên: có copy_local_config nhưng chưa có copy_build_inputs. Phải bỏ qua nó
# và dùng ứng viên kế tiếp, không dừng ở bản đầu tiên tìm thấy.
mkdir -p "$R/universal-agent-devkit/scripts/git"
# Bản cũ mượn copy_local_config thật (DevKit cũ thật vẫn chép được config), chỉ thiếu copy_build_inputs.
cat > "$R/universal-agent-devkit/scripts/git/worktree.py" <<PYF
import importlib.util
_spec = importlib.util.spec_from_file_location("real_wt", "$ROOT/universal-agent-devkit/scripts/git/worktree.py")
_real = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(_real)
copy_local_config = _real.copy_local_config
PYF
git -C "$R" worktree add -q --detach "$S" main

bash "$HELPER" "$R" "$S" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0" || fail "exit $rc"
[ -f "$S/app/google-services.json" ] && ok "ignored google-services.json copied into the scratch worktree" \
  || fail "google-services.json missing in the scratch worktree (Android build red, card stuck in Review)"
[ -f "$S/local.properties" ] && ok "ignored local.properties copied" || fail "local.properties missing"
[ ! -e "$S/.env" ] && ok "config file git does not ignore is not copied (cannot be committed by mistake)" || fail ".env copied although not ignored"
[ -f "$S/app/libs/sdk.aar" ] && ok "ignored build input libs/*.aar copied (copy_build_inputs)" || fail "app/libs/sdk.aar missing in the scratch worktree"
[ -f "$S/app/release.jks" ] && ok "ignored keystore *.jks copied" || fail "app/release.jks missing in the scratch worktree"
[ -z "$(git -C "$S" status --porcelain)" ] && ok "scratch worktree stays clean for git" || fail "scratch worktree dirty: $(git -C "$S" status --porcelain | head -3)"

# Merge gate truyền repo.path "." và có thể chạy từ worktree của Reviewer: nguồn chép vẫn phải là main checkout.
RV="$R/.claude/worktrees/issue-7-review"; S2="$TMP/scratch2"
git -C "$R" worktree add -q --detach "$RV" main
git -C "$R" worktree add -q --detach "$S2" main
( cd "$RV" && bash "$HELPER" . "$S2" >/dev/null 2>&1 )
[ -f "$S2/app/google-services.json" ] && [ -f "$S2/app/libs/sdk.aar" ] \
  && ok "repo.path '.' from a linked review worktree: copied from the main checkout" \
  || fail "repo.path '.' from a linked review worktree: nothing copied (source was the review worktree, not main)"

# Chỉ có DevKit cũ (copy_local_config, chưa có copy_build_inputs): vẫn phải chép config cục bộ như trước bản sửa,
# không được rơi về "không chép gì" (google-services.json thiếu là OfficeReader #73 quay lại). Bản sao helper đặt ở
# thư mục không có DevKit để ứng viên duy nhất là DevKit cũ của repo.
mkdir -p "$TMP/oldonly/.claude/bin"; cp "$HELPER" "$TMP/oldonly/.claude/bin/"
S3="$TMP/scratch3"; git -C "$R" worktree add -q --detach "$S3" main
bash "$TMP/oldonly/.claude/bin/$(basename "$HELPER")" "$R" "$S3" >/dev/null 2>&1
[ -f "$S3/app/google-services.json" ] && [ -f "$S3/local.properties" ] \
  && ok "only an old DevKit (no copy_build_inputs): local config still copied" \
  || fail "only an old DevKit: google-services.json/local.properties not copied (regression vs before the fix)"

# agent-workbench #12 / PR #87 (19/10): verify của merge gate đỏ vì cây tạm thiếu các hook bị git ignore mà .claude/settings.json
# đăng ký (guard-*.py, cleanup-wt.py): `agent-kit health` FAIL "hook đăng ký nhưng thiếu file", thẻ quay về Ready mãi. Cây tạm phải
# nhận chúng từ main checkout như worktree do agent-kit tạo (worktree.py copy_local_hooks, #93).
R4="$TMP/repo4"; S4="$TMP/scratch4"
git init -q -b main "$R4"
git -C "$R4" config user.email t@example.invalid; git -C "$R4" config user.name t
printf '.claude/hooks/\n' > "$R4/.gitignore"; echo a > "$R4/a"
git -C "$R4" add .gitignore a; git -C "$R4" commit -qm init
mkdir -p "$R4/.claude/hooks"; printf 'import sys\nsys.exit(0)\n' > "$R4/.claude/hooks/guard-secrets.py"
git -C "$R4" worktree add -q --detach "$S4" main
bash "$HELPER" "$R4" "$S4" >/dev/null 2>&1
[ -f "$S4/.claude/hooks/guard-secrets.py" ] && ok "ignored hook registered by settings (.claude/hooks/guard-secrets.py) copied into the scratch tree" \
  || fail "ignored hook .claude/hooks/guard-secrets.py missing in the scratch tree (health FAIL, merge gate verify red)"
[ -z "$(git -C "$S4" status --porcelain)" ] && ok "scratch tree with copied hooks stays clean for git" \
  || fail "scratch4 dirty: $(git -C "$S4" status --porcelain | head -3)"

[ "$FAILS" -eq 0 ] && echo "✅ test_scratch_config: all passed" || { echo "❌ test_scratch_config: $FAILS failed"; exit 1; }
