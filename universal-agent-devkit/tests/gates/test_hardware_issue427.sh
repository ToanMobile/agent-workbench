#!/usr/bin/env bash
# hooks/hardware_safety_gate.sh, issue #427 (lỗ còn lại sau audit DevKit 25–26/10):
#   1. link do CHÍNH lệnh đó tạo rồi xoá xuyên qua nó: `ln -s $HOME <scratch>/l && rm -rf <scratch>/l/`. Hook xét đường dẫn trước khi ln
#      chạy, lúc đó `l` chưa là link nên `l/` bị coi là thư mục thường của scratch (hoặc /tmp, build output) và được cho qua. rm -rf (cả
#      rm -r, find -delete) đi qua link — dấu / sau nó, đường dẫn bên dưới nó — xoá nội dung nơi link trỏ tới. Nay bị chặn khi một tên mà
#      đích đi qua trùng tên một toán hạng của ln trong lệnh (link nó tạo, và nguồn: `ln -s ~ dir` tạo dir/<user>), hoặc là glob có thể
#      khớp link; toán hạng ln không đọc được thì chặn mọi đường dẫn đi qua một thư mục. `l` trần vẫn cho qua (rm chỉ xoá chính link).
#   2. H4: `git ls-files` phân biệt hoa thường dù core.ignorecase=true: `rm -rf build` khi `Build/` được track (APFS, mặc định của macOS)
#      lọt như build output không track. Nay dùng pathspec `:(icase)` khi core.ignorecase là true.
# Chỉ chạy hook — không bao giờ chạy lệnh.  HW_HOOK=<đường dẫn hook> chạy bản hook khác (bản chưa sửa: RED).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # bỏ GIT_* thừa kế: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${HW_HOOK:-$DEVKIT_DIR/hooks/hardware_safety_gate.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }

newrepo() {   # newrepo <dir>: repo git rỗng có một file nguồn (chưa commit)
  mkdir -p "$1/src" && git -C "$1" init -q . && git -C "$1" config user.email t@t && git -C "$1" config user.name t \
    && git -C "$1" config commit.gpgsign false && printf 'x\n' > "$1/src/a.kt"
}
P="$TMP/work/proj"
newrepo "$P" && mkdir -p "$P/build" "$TMP/other" && git -C "$P" add -A && git -C "$P" commit -qm init

# check <rc mong đợi> <lệnh> [project]
check() {
  local want="$1" c="$2" p="${3:-$P}"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$c" "$p" > "$TMP/in.json"
  ( cd "$p" && CLAUDE_PROJECT_DIR="$p" bash "$HOOK" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$?
  if [ "$rc" = "$want" ]; then ok "rc $rc: $c"; else fail "rc $rc (want $want): $c — $(head -c 200 "$TMP/err" | tr '\n' ' ')"; fi
}

# 1. link do chính lệnh tạo. Scratch không chứa link nào tới $HOME (nếu có, dòng glob bị bản chưa sửa chặn vì lý do khác): `inside` trỏ
#    vào chính scratch, `inner` và `plain` là thư mục thật.
U="$(id -u)"; mkdir -p "/tmp/claude-$U" && SCR="$(mktemp -d "/tmp/claude-$U/devkit-hw427.XXXXXX")" || { fail "no scratch dir"; SCR=""; }
if [ -n "$SCR" ]; then
  trap 'rm -rf "$TMP" "$SCR"' EXIT
  SCRP="$(cd "$SCR" && pwd -P)"
  mkdir -p "$SCR/inner" "$SCR/plain" && ln -s "$SCRP/inner" "$SCR/inside"
  ME="$(basename "$HOME")"
  check 2 "ln -s \$HOME $SCRP/l && rm -rf $SCRP/l/"
  check 2 "ln -sf \$HOME $SCRP/l; rm -rf $SCRP/l/"
  check 2 "ln -sfn \$HOME $SCRP/inside && rm -rf $SCRP/inside/"     # link vô hại có sẵn bị trỏ lại về \$HOME trước
  check 2 "ln -s \$HOME $SCRP/l"$'\n'"rm -rf $SCRP/l/"               # ngăn cách bằng xuống dòng
  check 2 "ln -s ~ $SCRP/l && rm -rf $SCRP/l/."
  check 2 "ln -s ~ $SCRP/l && rm -rf $SCRP/l/Documents"            # đường dẫn bên dưới link
  check 2 "ln -s ~ $SCRP/l && rm -rf $SCRP/L/"                     # khác hoa thường (APFS)
  check 2 "ln -s ~ $SCRP/l && rm -rf $SCRP/*/"                     # glob khớp link vừa tạo
  check 2 "cd $SCRP && ln -s ~ l && rm -rf l/"
  check 2 "L=$SCRP/l; ln -s ~ \$L && rm -rf \$L/"
  check 2 "ln -s \$HOME $SCRP && rm -rf $SCRP/$ME/"                  # vào thư mục có sẵn: link là <thư mục>/<user>
  check 2 "ln -s -t $SCRP \$HOME && rm -rf $SCRP/$ME/"
  check 2 "ln -s ~ $SCRP/l && rm -r $SCRP/l/"                       # không -f: rm -r không có terminal vẫn xoá
  check 2 "ln -s ~ $SCRP/l && find $SCRP/l/ -delete"
  check 2 "sh -c 'ln -s ~ $SCRP/l' && rm -rf $SCRP/l/"
  check 2 "ln -s ~ \"\$NOPE_DEVKIT_427\" && rm -rf $SCRP/plain/"    # toán hạng ln không đọc được: mọi đường dẫn đi qua thư mục
  check 2 "ln -s ~ $SCRP/l && cd $SCRP/l && rm -rf *"               # cd vào link vừa tạo: thư mục hiện tại là nơi link trỏ tới
  check 2 "cd $SCRP && ln -s ~ l && cd l && rm -rf Documents"
  check 0 "ln -s x $SCRP/l && cd $SCRP/inner && rm -rf *"           # đối chứng: cd vào thư mục thật
  check 0 "ln -s ~ $SCRP/l && rm -rf $SCRP/l"                       # đối chứng: không dấu /, rm chỉ xoá chính link
  check 0 'ln -s a b && ls b/'
  check 0 "rm -rf $SCRP/plain/"
  check 0 "ln -s x $SCRP/l && rm -rf $SCRP/inner/"                  # có ln, nhưng thư mục không liên quan
  check 0 "ln -s x $SCRP/l && rm -rf $SCRP/kit*"
  check 0 "rm -rf $SCRP/inside/"                                    # link nằm trong scratch, như trước
fi
# … trong /tmp ($TMPDIR) và trong build output của project: cùng lỗ đó ngoài thư mục scratch
check 2 "ln -s ~ $TMP/x && rm -rf $TMP/x/"
check 2 'ln -s ~ build/l && rm -rf build/l/'
check 0 'ln -s ~ build/l && rm -rf build/l'
check 0 'rm -rf node_modules && ln -s ../shared/node_modules node_modules'
check 0 "rm -rf $TMP/other/"                                   # đối chứng: thư mục thật trong /tmp, có dấu / cuối

# 2. H4: build output được git track ở dạng hoa thường khác. core.ignorecase đặt tường minh: phán quyết theo nó trên mọi filesystem.
Q="$TMP/work/icase"
newrepo "$Q" && mkdir -p "$Q/Build" "$Q/app/Build" "$Q/out" && printf 'y\n' > "$Q/Build/x.txt" && printf 'y\n' > "$Q/app/Build/y.txt" \
  && git -C "$Q" add -A && git -C "$Q" commit -qm init && git -C "$Q" config core.ignorecase true
check 2 'rm -rf build' "$Q"
check 2 'rm -rf app/build' "$Q"
check 2 'rm -rf Build' "$Q"                                   # đối chứng: đúng tên được track, đã bị chặn từ trước
check 0 'rm -rf out' "$Q"                                     # đối chứng: không có gì được track ở đó, mọi kiểu hoa thường
check 0 'rm -rf node_modules' "$Q"

[ "$FAILS" -eq 0 ] && echo "✅ test_hardware_issue427: all passed" || { echo "❌ test_hardware_issue427: $FAILS failed"; exit 1; }
