#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# githooks.sh — install / remove the DevKit git pre-commit hook in a project.
#   githooks.sh install   [path]   write <hooks dir>/pre-commit
#   githooks.sh uninstall [path]   remove it (only if it is the DevKit's)
#   githooks.sh status    [path]
#
# The hooks dir comes from git itself (`--git-path hooks`), so core.hooksPath
# (husky, lefthook, …) and linked worktrees are honoured. The written hook is a
# 3-line stub marked `universal-agent-devkit:githook` that execs
# scripts/git-pre-commit.sh from this DevKit. A pre-commit hook that is not the
# DevKit's is never overwritten: the command to chain it is printed instead.
# bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
set -u

DEVKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$DEVKIT_ROOT/scripts/i18n.sh"
MARKER="universal-agent-devkit:githook"
BODY="$DEVKIT_ROOT/scripts/git-pre-commit.sh"

ACTION="${1:-status}"
TARGET="${2:-$PWD}"
DEVKIT_LANG="$(devkit_resolve_lang "" "$TARGET")"; export DEVKIT_LANG

die() { echo "✖ githooks: $1" >&2; exit "${2:-1}"; }

case "$ACTION" in install|uninstall|status) ;; *)
  die "$(L "lệnh không hợp lệ '$ACTION' (install | uninstall | status)" "unknown action '$ACTION' (install | uninstall | status)")" 2 ;;
esac
[ -d "$TARGET" ] || die "$(L "không có thư mục: $TARGET" "no such directory: $TARGET")" 2
git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 \
  || die "$(L "$TARGET không phải git repository" "$TARGET is not a git repository")" 2
HOOKS_DIR="$(git -C "$TARGET" rev-parse --path-format=absolute --git-path hooks 2>/dev/null)" || {
  GIT_DIR="$(cd "$TARGET" && git rev-parse --git-dir 2>/dev/null)" || die "$(L "không đọc được git dir" "cannot resolve git dir")" 2
  HOOKS_DIR="$(cd "$TARGET" && cd "$GIT_DIR" && pwd -P)/hooks"
}
[ -n "$HOOKS_DIR" ] || die "$(L "không xác định được thư mục hooks" "cannot resolve the hooks dir")" 2
HOOK="$HOOKS_DIR/pre-commit"
MSG_HOOK="$HOOKS_DIR/commit-msg"
MSG_BODY="$DEVKIT_ROOT/scripts/git-commit-msg.sh"
msg_is_ours() { [ -f "$MSG_HOOK" ] && grep -qF "$MARKER" "$MSG_HOOK"; }
# The project's own commit-msg (GeelyEx2 tracks .githooks/commit-msg) gets ONE line after its #!,
# marked with CHAIN_MARK (not MARKER: msg_is_ours must stay false, uninstall must not delete the
# project's hook). It calls <repo>/.agents/devkit, so the tracked hook works on every clone and
# does nothing where the DevKit is not installed.
CHAIN_MARK="universal-agent-devkit-chain:commit-msg"
# shellcheck disable=SC2016
CHAIN_LINE='D="$(git rev-parse --show-toplevel)/.agents/devkit/scripts/git-commit-msg.sh"; [ -f "$D" ] && { bash "$D" "$1" || exit 1; }  # '"$CHAIN_MARK"
msg_is_chained() { [ -f "$MSG_HOOK" ] && grep -qF "$CHAIN_MARK" "$MSG_HOOK"; }
msg_target() { python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$MSG_HOOK" 2>/dev/null || echo "$MSG_HOOK"; }
install_msg_hook() {
  if [ -e "$MSG_HOOK" ] && ! msg_is_ours; then
    msg_is_chained && { echo "✔ commit-msg: $(L "hook riêng của dự án, đã nối luật DevKit" "the project's own hook, DevKit rule chained")"; return 0; }
    if ! head -1 "$MSG_HOOK" | grep -qE '^#!.*(/|env[[:space:]]+)(ba|z|da)?sh([[:space:]]|$)'; then
      echo "• commit-msg: $(L "hook riêng của dự án không phải shell — giữ nguyên; muốn thêm luật DevKit, gọi:" "the project's own hook is not a shell script — kept; to add the DevKit rule, call:") $CHAIN_LINE"
      return 0
    fi
    local f; f="$(msg_target)"   # a symlinked hook: edit its (tracked) target, keep the link and the mode
    cp -p "$f" "$f.devkit-tmp" && { head -1 "$f"; printf '%s\n' "$CHAIN_LINE"; tail -n +2 "$f"; } > "$f.devkit-tmp" \
      && mv "$f.devkit-tmp" "$f" \
      && echo "✔ commit-msg: $(L "đã nối luật DevKit vào hook riêng của dự án (1 dòng sau #!) — file có thể được git track, commit nó cùng dự án" "DevKit rule chained into the project's own hook (1 line after #!) — the file may be tracked; commit it with the project")"
    return 0
  fi
  {
    echo "#!/usr/bin/env bash"
    echo "# $MARKER — fix commits name their bug (Bug: <id>) or say why not (No-Guard: <reason>)."
    printf 'DEVKIT_HOOK=%q\n' "$MSG_BODY"
    # shellcheck disable=SC2016
    echo '[ -f "$DEVKIT_HOOK" ] || { echo "✖ DevKit commit-msg: $DEVKIT_HOOK not found — re-run agent-kit githooks install, or git commit --no-verify" >&2; exit 1; }'
    echo 'exec bash "$DEVKIT_HOOK" "$@"'
  } > "$MSG_HOOK.devkit-tmp" && chmod +x "$MSG_HOOK.devkit-tmp" && mv "$MSG_HOOK.devkit-tmp" "$MSG_HOOK"
}
# Git operations that can remove untracked DevKit links from the working tree; each gets a
# stub running scripts/relink_check.py (instant when nothing is missing).
RELINK_HOOKS="post-merge post-checkout post-rewrite"
RELINK="$DEVKIT_ROOT/scripts/relink_check.py"
relink_is_ours() { [ -f "$HOOKS_DIR/$1" ] && grep -qF "$MARKER" "$HOOKS_DIR/$1"; }
install_relink_hooks() {
  local h f
  for h in $RELINK_HOOKS; do
    f="$HOOKS_DIR/$h"
    if [ -e "$f" ] && ! relink_is_ours "$h"; then
      echo "• $h: $(L "hook riêng của dự án — giữ nguyên; muốn tự sửa link DevKit, chèn sau dòng #!:" "the project's own hook — kept; to repair DevKit links, add after its #! line:") python3 $(printf %q "$RELINK") \"\$(git rev-parse --show-toplevel)\" --hook=$h \"\$@\" --quiet"
      continue
    fi
    {
      echo "#!/usr/bin/env bash"
      echo "# $MARKER — restores DevKit links a git operation removed (agent-kit githooks uninstall removes it)."
      printf 'RELINK=%q\n' "$RELINK"
      # shellcheck disable=SC2016
      echo "[ -f \"\$RELINK\" ] && python3 \"\$RELINK\" \"\$(git rev-parse --show-toplevel)\" --hook=$h \"\$@\" || true"
    } > "$f.devkit-tmp" && chmod +x "$f.devkit-tmp" && mv "$f.devkit-tmp" "$f"
  done
}

is_ours() { [ -f "$HOOK" ] && grep -qF "$MARKER" "$HOOK"; }

case "$ACTION" in
  status)
    n=0; for h in $RELINK_HOOKS; do relink_is_ours "$h" && n=$((n + 1)); done
    echo "• $(L "tự sửa link sau merge/checkout/rebase" "link repair after merge/checkout/rebase"): $n/3 hook"
    if is_ours; then
      echo "✔ pre-commit: $(L "đã cài (DevKit)" "installed (DevKit)") — $HOOK"
    elif [ -e "$HOOK" ] && grep -qF "scripts/git-pre-commit.sh" "$HOOK" 2>/dev/null; then
      echo "✔ pre-commit: $(L "hook riêng của dự án, có gọi cổng DevKit" "the project's own hook, chaining the DevKit gate") — $HOOK"
    elif [ -e "$HOOK" ]; then
      echo "• pre-commit: $(L "có hook riêng của dự án, không phải DevKit" "a project hook exists, not the DevKit's") — $HOOK"
    else
      echo "• pre-commit: $(L "chưa cài" "not installed") — $HOOK"
    fi
    if msg_is_ours; then
      echo "✔ commit-msg: $(L "đã cài (DevKit)" "installed (DevKit)") — $MSG_HOOK"
    elif msg_is_chained; then
      echo "✔ commit-msg: $(L "hook riêng của dự án, đã nối luật DevKit" "the project's own hook, DevKit rule chained") — $MSG_HOOK"
    elif [ -e "$MSG_HOOK" ]; then
      echo "• commit-msg: $(L "hook riêng của dự án, CHƯA nối luật DevKit (agent-kit githooks install)" "the project's own hook, DevKit rule NOT chained (agent-kit githooks install)") — $MSG_HOOK"
    else
      echo "• commit-msg: $(L "chưa cài" "not installed") — $MSG_HOOK"
    fi
    ;;
  install)
    mkdir -p "$HOOKS_DIR" 2>/dev/null
    install_relink_hooks
    install_msg_hook
    if [ -e "$HOOK" ] && ! is_ours; then
      echo "✖ githooks: $(L "$HOOK đã có và không phải của DevKit — giữ nguyên, không ghi đè." "$HOOK exists and is not the DevKit's — left untouched.")" >&2
      # Right after the shebang, not at the end: a hook that ends with `exit 0` (or
      # `exec` of another tool) would never reach an appended line.
      echo "  $(L "Muốn chạy thêm cổng DevKit, chèn dòng này NGAY SAU dòng đầu (#!) của hook đó — không thêm ở cuối (hook có thể 'exit 0' trước):" "To add the DevKit gate, insert this line RIGHT AFTER the first (#!) line of that hook — not at the end (the hook may 'exit 0' first):")" >&2
      printf '    bash %q "$@" || exit 1\n' "$BODY" >&2
      echo "  $(L "Ví dụ:" "For example:") sed -i.bak '1a\\'\$'\\n''bash $(printf %q "$BODY") \"\$@\" || exit 1' $HOOK" >&2
      exit 1
    fi
    mkdir -p "$HOOKS_DIR" || die "$(L "không tạo được $HOOKS_DIR" "cannot create $HOOKS_DIR")"
    {
      echo "#!/usr/bin/env bash"
      echo "# $MARKER — written by 'agent-kit githooks install'; remove with 'agent-kit githooks uninstall'."
      echo "# Static post-fix gate on the staged content. Skip once: git commit --no-verify"
      printf 'DEVKIT_HOOK=%q\n' "$BODY"
      # shellcheck disable=SC2016
      echo '[ -f "$DEVKIT_HOOK" ] || { echo "✖ DevKit pre-commit: $DEVKIT_HOOK not found (DevKit moved?) — re-run agent-kit githooks install, or git commit --no-verify" >&2; exit 1; }'
      echo 'exec bash "$DEVKIT_HOOK" "$@"'
    } > "$HOOK.devkit-tmp" && chmod +x "$HOOK.devkit-tmp" && mv "$HOOK.devkit-tmp" "$HOOK" \
      || { rm -f "$HOOK.devkit-tmp"; die "$(L "không ghi được $HOOK" "cannot write $HOOK")"; }
    echo "✔ $(L "Đã cài git pre-commit" "Installed git pre-commit") → $HOOK"
    echo "  $(L "Mỗi git commit (kể cả ngoài agent) sẽ kiểm tĩnh nội dung đã stage. Bỏ qua 1 lần: git commit --no-verify" "Every git commit (also outside any agent) now statically checks the staged content. Skip once: git commit --no-verify")"
    ;;
  uninstall)
    for h in $RELINK_HOOKS; do relink_is_ours "$h" && rm -f "$HOOKS_DIR/$h"; done
    msg_is_ours && rm -f "$MSG_HOOK"
    if msg_is_chained; then
      f="$(msg_target)"
      cp -p "$f" "$f.devkit-tmp" && grep -vF "$CHAIN_MARK" "$f" > "$f.devkit-tmp" && mv "$f.devkit-tmp" "$f"
    fi
    if is_ours; then
      rm -f "$HOOK" && echo "✔ $(L "Đã gỡ" "Removed") $HOOK"
    elif [ -e "$HOOK" ]; then
      echo "• $(L "$HOOK không phải của DevKit — giữ nguyên" "$HOOK is not the DevKit's — kept")"
    else
      echo "• $(L "Chưa cài pre-commit của DevKit" "The DevKit pre-commit is not installed")"
    fi
    ;;
esac
