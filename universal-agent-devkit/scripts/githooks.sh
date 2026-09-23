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

is_ours() { [ -f "$HOOK" ] && grep -qF "$MARKER" "$HOOK"; }

case "$ACTION" in
  status)
    if is_ours; then
      echo "✔ pre-commit: $(L "đã cài (DevKit)" "installed (DevKit)") — $HOOK"
    elif [ -e "$HOOK" ] && grep -qF "scripts/git-pre-commit.sh" "$HOOK" 2>/dev/null; then
      echo "✔ pre-commit: $(L "hook riêng của dự án, có gọi cổng DevKit" "the project's own hook, chaining the DevKit gate") — $HOOK"
    elif [ -e "$HOOK" ]; then
      echo "• pre-commit: $(L "có hook riêng của dự án, không phải DevKit" "a project hook exists, not the DevKit's") — $HOOK"
    else
      echo "• pre-commit: $(L "chưa cài" "not installed") — $HOOK"
    fi
    ;;
  install)
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
    if is_ours; then
      rm -f "$HOOK" && echo "✔ $(L "Đã gỡ" "Removed") $HOOK"
    elif [ -e "$HOOK" ]; then
      echo "• $(L "$HOOK không phải của DevKit — giữ nguyên" "$HOOK is not the DevKit's — kept")"
    else
      echo "• $(L "Chưa cài pre-commit của DevKit" "The DevKit pre-commit is not installed")"
    fi
    ;;
esac
