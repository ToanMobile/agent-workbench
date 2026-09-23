#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# validate-assets.sh — Unity Asset Database hygiene (game profile)
#
# Two modes:
#   • PostToolUse hook (Edit|Write, JSON on stdin): checks the file just written. A
#     document / scratch file inside Assets/ → exit 2, the reason goes back to the agent.
#   • Scan (no JSON on stdin — regression matrix REG-GAME-04, manual run): checks every
#     uncommitted change under Assets/ → exit 1 on a violation, 0 when clean.
#
# Why: Unity imports everything under Assets/. A .md/.txt/.log there becomes a TextAsset
# with a new .meta (GUID noise, merge conflicts, shipped in builds); an asset deleted or
# moved without its .meta leaves an orphan, and a .meta deleted while its asset stays makes
# Unity mint a NEW GUID — every scene/prefab reference to that asset silently breaks.
# Docs belong in docs/ (or design/, production/); scratch files outside the repo.
#
# Rules checked:
#   R1 no docs / scratch inside Assets/: *.md *.markdown *.rst *.tmp *.bak *.orig *.rej
#      *.log notes.txt, Assets/Temp/**, Assets/InitTestScene*.unity (left by a crashed
#      PlayMode test run). Third-party folders (Assets/Plugins/**, **/Documentation~/**)
#      are exempt. Scan mode flags only new files (untracked/added), not tracked ones.
#   R2 (scan) a deleted .meta whose asset still exists → GUID will be regenerated.
#   R3 (scan) a deleted asset whose .meta is still on disk → orphan .meta.
#   Advisory (scan, exit unaffected): a new asset file without its .meta yet — let the
#   Editor import it (it writes the .meta) and commit both together.
# bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$REPO_ROOT" 2>/dev/null || exit 0

# Not a Unity project → nothing to check.
[ -d "Assets" ] && [ -d "ProjectSettings" ] || exit 0

is_rogue() {  # $1 = repo-relative path
  case "$1" in
    Assets/Plugins/*|*/Documentation~/*) return 1 ;;
    Assets/Temp/*|Assets/Temp|Assets/Temp.meta) return 0 ;;
    Assets/InitTestScene*.unity|Assets/InitTestScene*.unity.meta) return 0 ;;
  esac
  case "$1" in
    Assets/*)
      case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
        *.md|*.markdown|*.rst|*.tmp|*.bak|*.orig|*.rej|*.log|*/notes.txt|\
        *.md.meta|*.markdown.meta|*.rst.meta|*.tmp.meta|*.bak.meta|*.orig.meta|*.rej.meta|*.log.meta|*/notes.txt.meta)
          return 0 ;;
      esac ;;
  esac
  return 1
}

HINT="Unity sẽ import file này thành TextAsset kèm .meta mới (nhiễu GUID, xung đột git, lọt vào build). Chuyển tài liệu sang docs/ (hoặc design/, production/), file tạm ra ngoài repo."

# ---------- hook mode ----------
INPUT=""
[ -t 0 ] || INPUT="$(cat 2>/dev/null || true)"
FILE_PATH=""
if [ -n "$INPUT" ]; then
  FILE_PATH="$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try: print((json.load(sys.stdin).get("tool_input") or {}).get("file_path") or "")
except Exception: print("")' 2>/dev/null)"
fi
if [ -n "$FILE_PATH" ]; then
  case "$FILE_PATH" in
    "$REPO_ROOT"/*) REL="${FILE_PATH#"$REPO_ROOT"/}" ;;
    /*) REL="$(python3 -c 'import os,sys; print(os.path.relpath(os.path.realpath(sys.argv[1]), os.path.realpath(sys.argv[2])))' "$FILE_PATH" "$REPO_ROOT" 2>/dev/null)" ;;
    *) REL="$FILE_PATH" ;;
  esac
  if is_rogue "$REL"; then
    echo "❌ [UNITY ASSET HYGIENE] $REL nằm trong Assets/. $HINT" >&2
    exit 2
  fi
  exit 0
fi

# ---------- scan mode ----------
fail=0
r1=0
advisory=""
while IFS= read -r -d '' entry; do
  st="${entry:0:2}"
  path="${entry:3}"
  case "$st" in R*|C*) IFS= read -r -d '' _orig || true ;; esac
  case "$path" in Assets/*) ;; *) continue ;; esac
  case "$st" in
    "??"|A?|?A)
      if is_rogue "$path"; then
        echo "❌ R1 file tài liệu/tạm trong Assets/: $path" >&2; fail=1; r1=1
      elif [ -f "$path" ] && [ "${path%.meta}" = "$path" ] && [ ! -e "$path.meta" ]; then
        advisory="$advisory\n  - $path (chưa có .meta — mở Editor để import rồi commit cả hai)"
      fi ;;
    D?|?D)
      if [ "${path%.meta}" != "$path" ]; then
        asset="${path%.meta}"
        if [ -e "$asset" ]; then
          echo "❌ R2 đã xoá $path nhưng $asset vẫn còn — Unity sẽ sinh GUID mới, mọi tham chiếu tới asset này sẽ gãy. Khôi phục .meta (git checkout -- \"$path\")." >&2; fail=1
        fi
      elif [ -e "$path.meta" ]; then
        echo "❌ R3 đã xoá $path nhưng $path.meta vẫn còn — xoá/di chuyển asset phải đi kèm .meta của nó." >&2; fail=1
      fi ;;
  esac
done < <(git status --porcelain=v1 -z -uall -- Assets 2>/dev/null)

if [ -n "$advisory" ]; then
  printf '⚠️  Asset mới chưa có .meta:%b\n' "$advisory" >&2
fi
if [ "$fail" -ne 0 ]; then
  [ "$r1" -eq 1 ] && echo "$HINT" >&2
  exit 1
fi
echo "PASS: Assets/ hygiene — no docs/scratch files, .meta pairs consistent"
exit 0
