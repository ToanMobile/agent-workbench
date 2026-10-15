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
#      PlayMode test run). Blender 3D is the only asset source (game-rules.md §2): the
#      Blender source (*.blend *.blend1..99 *.blend@, kept in Art/Source/ outside Assets/) and
#      2D sources (*.svg *.psd *.psb *.ai *.aseprite *.ase *.xcf *.kra) are rogue too.
#      Third-party folders (Assets/Plugins/**, Assets/TextMesh Pro/**, Assets/Samples/**,
#      **/Documentation~/**) are exempt. Scan mode flags only new files (untracked/added), not tracked ones.
#   R2 (scan) a deleted .meta whose asset still exists → GUID will be regenerated.
#   R3 (scan) a deleted asset whose .meta is still on disk → orphan .meta.
#   Advisory (scan, exit unaffected): a new asset file without its .meta yet — let the
#   Editor import it (it writes the .meta) and commit both together.
# bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$REPO_ROOT" 2>/dev/null || exit 0

# The Unity project is at the repo root, or one level down in unity/ (Neighbours-From-Hell): U is its prefix as git and the agent write paths.
U=""
if [ ! -d Assets ] && [ -d unity/Assets ] && [ -d unity/ProjectSettings ]; then U="unity/"; fi
# Not a Unity project → nothing to check.
[ -d "${U}Assets" ] && [ -d "${U}ProjectSettings" ] || exit 0

is_rogue() {  # $1 = repo-relative path
  case "$1" in
    Assets/Plugins/*|"Assets/TextMesh Pro/"*|Assets/Samples/*|*/Documentation~/*) return 1 ;;
    Assets/Temp/*|Assets/Temp|Assets/Temp.meta) return 0 ;;
    Assets/InitTestScene*.unity|Assets/InitTestScene*.unity.meta) return 0 ;;
  esac
  case "$1" in
    Assets/*)
      local lc
      lc="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
      case "$lc" in
        *.md|*.markdown|*.rst|*.tmp|*.bak|*.orig|*.rej|*.log|*/notes.txt|\
        *.md.meta|*.markdown.meta|*.rst.meta|*.tmp.meta|*.bak.meta|*.orig.meta|*.rej.meta|*.log.meta|*/notes.txt.meta)
          return 0 ;;
      esac
      case "${lc%.meta}" in
        *.blend|*.blend[0-9]|*.blend[0-9][0-9]|*.blend@|*.svg|*.psd|*.psb|*.ai|*.aseprite|*.ase|*.xcf|*.kra) return 0 ;;
      esac ;;
  esac
  return 1
}

HINT="Unity import mọi thứ trong Assets/: .md/.txt thành TextAsset kèm .meta mới (nhiễu GUID, xung đột git, lọt vào build), .blend khiến Unity gọi Blender mỗi lần import. Tài liệu chuyển sang docs/ (hoặc design/, production/), file tạm ra ngoài repo. Blender 3D là nguồn duy nhất của asset: giữ .blend ở Art/Source/ (ngoài Assets/), không đưa nguồn 2D (.svg/.psd/...) vào; chỉ vào Assets/ FBX/glTF hoặc PNG do Blender render."

# ---------- hook mode ----------
INPUT=""
[ -t 0 ] || INPUT="$(cat 2>/dev/null || true)"
FILE_PATH=""
if [ -n "$INPUT" ]; then
  FILE_PATH="$(printf '%s' "$INPUT" | python3 -I -c 'import json,sys
try: print((json.load(sys.stdin).get("tool_input") or {}).get("file_path") or "")
except Exception: print("")' 2>/dev/null)"
fi
if [ -n "$FILE_PATH" ]; then
  case "$FILE_PATH" in
    "$REPO_ROOT"/*) REL="${FILE_PATH#"$REPO_ROOT"/}" ;;
    /*) REL="$(python3 -I -c 'import os,sys; print(os.path.relpath(os.path.realpath(sys.argv[1]), os.path.realpath(sys.argv[2])))' "$FILE_PATH" "$REPO_ROOT" 2>/dev/null)" ;;
    *) REL="$FILE_PATH" ;;
  esac
  case "$REL" in "$U"*) REL="${REL#"$U"}" ;; *) exit 0 ;; esac   # only the Unity project's own files are judged, by their path inside it
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
  _orig=""
  case "$st" in *[RC]*) IFS= read -r -d '' _orig || true ;; esac   # a rename/copy on EITHER side carries its source path
  case "$path" in "${U}Assets/"*) ;; *) continue ;; esac
  rel="${path#"$U"}"
  case "$st" in
    "??"|A?|?A|R?|?R|C?|?C)
      # a rename/copy is judged by its NEW path. Only a RENAME of a file that was already rogue and keeps its kind (same extension) is
      # grandfathered: git mv Art/Source/hero.blend Assets/..., hero.fbx -> hero.blend and notes.md -> hero.blend are all caught
      case "$st" in *C*) ;; *R*) case "$_orig" in "${U}Assets/"*) is_rogue "${_orig#"$U"}" && o="${_orig%.meta}" && n="${path%.meta}" && [ "$(printf '%s' "${o##*.}" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "${n##*.}" | tr '[:upper:]' '[:lower:]')" ] && continue ;; esac ;; esac
      if is_rogue "$rel"; then
        echo "❌ R1 file không thuộc Assets/ (tài liệu, tạm, nguồn .blend/2D): $path" >&2; fail=1; r1=1
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
done < <(git status --porcelain=v1 -z -uall -- "${U}Assets" 2>/dev/null)

if [ -n "$advisory" ]; then
  printf '⚠️  Asset mới chưa có .meta:%b\n' "$advisory" >&2
fi
if [ "$fail" -ne 0 ]; then
  [ "$r1" -eq 1 ] && echo "$HINT" >&2
  exit 1
fi
echo "PASS: Assets/ hygiene — no docs/scratch files, .meta pairs consistent"
exit 0
