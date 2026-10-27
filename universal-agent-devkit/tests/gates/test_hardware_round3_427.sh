#!/usr/bin/env bash
# hooks/hardware_safety_gate.sh, #427 vòng 3 (các lỗ vòng 2 để lại; vòng 2: tests/gates/test_hardware_backlog427.sh):
#   1. (P0) một tên glob rồi `..` sau nó: `mkdir -p build/x/1 && rm -rf build/x/*/../../../src` qua (tên chưa có lúc hook xét: glob không khớp
#      gì, chỉ build/x được xét), chạy thật xoá src/ đang track. Nay xét thêm đường dẫn với mỗi tên glob là một tên thường.
#   2. (P0) rm -r KHÔNG -f sau cd vào link chính lệnh tạo (`ln -s ~ l && cd l && rm -r Documents`): chính sách 10-09 bỏ qua cwd không biết,
#      nhưng ở đây cwd chắc là nơi link trỏ tới — xét như có -f.
#   3. Thân trap từng được xét với cwd lúc đặt trap, nhưng chạy ở cwd lúc thoát: nay xét với mọi cwd từ lúc đặt tới lúc thoát (cd tới chỗ
#      không biết thì không biết); trap đặt trong ( … ) chạy khi ( … ) thoát.
#   4. Lệnh tạo link khác (luật của tar vòng 2: chặn khi rm -r đi XUYÊN qua một mục dưới đích): cp -R / -r / -a / -P, rsync -a / -l, git
#      clone, 7z x, ditto, cpio -i / -p. Một nguồn có thể là link (link có sẵn, chưa có): cả chính đích (đích/, đích/x) bị chặn.
#   5. Script mà lệnh chạy (bash x.sh, sh x.sh, ./x.sh, source x.sh) dưới project, < 64 KB: đọc để gom lệnh tạo link của nó (rm của script
#      vẫn không bị xét, như trước).
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
export XDG_CONFIG_HOME="$TMP/cfg"; unset ADB_DENY_SERIALS ADB_ALLOW_SERIALS

newrepo() {   # newrepo <dir>: repo git có một file nguồn đã commit, build/ không track
  mkdir -p "$1/src" "$1/build" && git -C "$1" init -q . && git -C "$1" config user.email t@t && git -C "$1" config user.name t \
    && git -C "$1" config commit.gpgsign false && printf 'x\n' > "$1/src/a.kt" && git -C "$1" add -A && git -C "$1" commit -qm init
}
P="$TMP/work/proj"
newrepo "$P"

# check <rc mong đợi> <lệnh> [project] — payload cwd và CLAUDE_PROJECT_DIR là project
check() {
  local want="$1" c="$2" p="${3:-$P}"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$c" "$p" > "$TMP/in.json"
  ( cd "$p" && CLAUDE_PROJECT_DIR="$p" bash "$HOOK" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$?
  if [ "$rc" = "$want" ]; then ok "rc $rc: $c"; else fail "rc $rc (want $want): $c — $(head -c 200 "$TMP/err" | tr '\n' ' ')"; fi
}

# 1. (P0) tên glob rồi `..`: tên chưa có lúc hook xét (mkdir của chính lệnh)
check 2 'mkdir -p build/x/1 && rm -rf build/x/*/../../../src'
check 2 'rm -rf build/x/?/../../../src'
check 2 'rm -rf build/x/[0-9]/../../../src'
check 2 'rm -rf build/x/*/y/../../../../src'
check 2 'rm -rf build/x/*/../../../*'                                      # mọi thứ trong project
check 2 'rm -r build/x/*/../../..'                                         # không -f: là gốc project
check 2 'rm -rf node_modules/*/../..'
check 0 'rm -rf build/*/../tmp'                                            # đối chứng: build/*/.. là build
check 0 'rm -rf build/x/*/..'
check 0 'rm -rf build/x/*'
check 0 'rm -rf build/*/node_modules'
check 0 'rm -rf build/x/{1..3}'                                            # đối chứng: dòng dãy của vòng 2

# 3. thân trap: cwd lúc thoát
check 2 "trap 'rm -rf build' EXIT; cd ~"                                    # chạy lúc thoát ở ~: ~/build
check 2 "trap 'rm -rf build/x' EXIT; cd \"\$NOPE_DEVKIT_R3\""                # cd tới chỗ không biết
check 2 "cd build && trap 'rm -rf src' EXIT && cd .."                       # lúc đặt: build/src; lúc thoát: src/ đang track
check 2 "(trap 'rm -rf build' EXIT; cd ~); echo done"                       # trap của ( … ) chạy khi nó thoát, ở ~
check 2 "trap -- 'rm -rf build' EXIT INT; pushd ~"
check 0 "T=\$(mktemp -d); trap 'rm -rf \"\$T\"' EXIT; cd ~"                  # đối chứng: đường dẫn tuyệt đối
check 0 "T=\$(mktemp -d); trap 'rm -rf \"\$T\"' EXIT"
check 0 "trap 'rm -rf build/x' EXIT && cd build && cd .."                   # đối chứng: lúc thoát lại ở project
check 0 "(cd build && trap 'rm -rf tmp' EXIT); cd ~"                        # đối chứng: trap chạy khi ( … ) thoát, ở build
check 0 "trap 'rm -rf build/x' EXIT"

# 4. lệnh chép / giải nén tạo link. hl: link có sẵn tới home (chỉ để xét: lệnh không bao giờ chạy)
ln -s "$HOME" "$P/hl"
check 2 'cp -a ~/nope_devkit_r3 build/ && rm -rf build/nope_devkit_r3/'    # chép vào build/: mục bên dưới có thể là link
check 2 'cp -R hl build/l && rm -rf build/l/'                               # nguồn là link: đích là link
check 2 'cp -P hl build/l && rm -rf build/l/x'
check 2 'cp -r hl build/l && rm -rf build/l/'
check 2 'gcp -a hl build/l && rm -rf build/l/'
check 2 'cp --archive -t build hl && rm -rf build/hl/'
check 2 'rsync -a hl build/r && rm -rf build/r/'
check 2 'rsync -av --exclude .git hl build/r && rm -rf build/r/'
# nguồn là cây có thật: mục dưới đích là link chỉ khi mục tương ứng của nguồn là link. tree/lnk: link có sẵn tới home, tree/sub: thư mục thật
mkdir -p "$P/tree/sub" && ln -s "$HOME" "$P/tree/lnk"
check 2 'rsync -rl tree/ build/r/ && rm -rf build/r/lnk/'                   # đích/x ↔ nguồn/x
check 2 'cp -R tree build/t && rm -rf build/t/lnk/x'
check 2 'cp -R tree build/ && rm -rf build/tree/lnk/'                        # đích/<tên nguồn>/x ↔ nguồn/x
check 2 'tar -xf a.tar -C tree && cp -R tree build/t && rm -rf build/t/pkg/'   # nguồn đổi trước lúc chép (giải nén vào nó): như tar
check 2 'ln -s ~ tree/new && cp -R tree build/t && rm -rf build/t/new/'       # link chính lệnh tạo trong nguồn: theo tên
check 2 'cp -R tree build/a && cp -R build/a build/b && rm -rf build/b/lnk/'   # nguồn chưa có lúc hook xét: như tar
check 0 'cp -R tree build/t && rm -rf build/t/sub/x'                          # đối chứng: sub là thư mục thật ở nguồn
# cwd không biết, đích tương đối: tên cuối của đích như tên link của ln
check 2 'cd "$NOPE_DEVKIT_R3" && cp -R ~/nope_devkit_r3 bx && rm -rf /tmp/devkit-r3-x/bx/y/'
check 2 'cd "$NOPE_DEVKIT_R3" && git clone https://example.invalid/r.git yy && rm -rf /tmp/devkit-r3-x/yy/sub/'
check 0 'cd "$NOPE_DEVKIT_R3" && cp -R ~/nope_devkit_r3 bx && rm -rf /tmp/devkit-r3-x/other/'   # đối chứng (corpus 27/10: cd $W && cp -cR)
check 0 'rsync -rl src/ build/r/ && rm -rf build/r/main/x/'                   # đối chứng: nguồn không có link
check 0 'cp -a src build/ && rm -rf build/tmp/'                               # đối chứng: bản chép nằm ở build/src
check 2 'rsync -a --delete hl build/r && rm -rf build/r/'                   # --delete: đích vẫn được ghi
check 2 'git clone https://example.invalid/a/repo.git build/y && rm -rf build/y/sub/'
check 2 'git clone -b main --depth 1 https://example.invalid/a/repo.git && rm -rf repo/sub/x'   # tên thư mục lấy từ URL
check 2 'git -C build clone https://example.invalid/r.git y && rm -rf build/y/l/'
check 2 '7z x a.7z -obuild/e && rm -rf build/e/pkg/'
check 2 '7za x a.7z && rm -rf build/'                                       # giải nén vào project, như tar
check 2 'ditto hl build/d && rm -rf build/d/'
check 2 'ditto -x -k a.zip build/d && rm -rf build/d/pkg/'
check 2 'cpio -idm < a.cpio && rm -rf build/pkg/'
check 2 'find src | cpio -pdm build/c && rm -rf build/c/src/'
check 0 'cp -a src build/ && rm -rf build'                                  # đối chứng: xoá chính đích, không dấu /
check 0 'cp -r src build/s && rm -rf build/s/.git'                           # đối chứng: nguồn thật, mục cuối không dấu /
check 0 'cp -a ~/nope_devkit_r3 build/ && rm -rf build/tmp'
check 0 'git clone https://example.invalid/x.git build/y && rm -rf build/y'
check 0 'git clone https://example.invalid/x.git build/y && rm -rf build/y/'
check 0 'git clone https://example.invalid/x.git build/y && rm -rf build/z/'
check 0 'git clone --bare https://example.invalid/x.git build/y.git && rm -rf build/y.git/hooks/'
check 0 'cp a.txt b.txt && rm -rf build/x/'                                  # đối chứng: cp không đệ quy
check 0 'rsync -a build/ host:/x && rm -rf build/x/'                         # đối chứng: đích ở máy khác
check 0 'ditto -c -k build a.zip && rm -rf build/x/'                         # đối chứng: nén, không chép
check 0 '7z a a.7z build && rm -rf build/x/'
check 0 'cpio -o < list > a.cpio && rm -rf build/x/'

# 5. script mà lệnh chạy: gom lệnh tạo link của nó
printf '#!/usr/bin/env bash\nset -e\nln -s ~ build/l\n' > "$P/mk.sh"
printf '#!/bin/sh\necho hi\n' > "$P/ok.sh"
printf '#!/bin/sh\nrm -rf ~/nope_devkit_r3\n' > "$P/clean.sh"
printf '#!/bin/sh\ntmp="$1.tmp"; echo x > "$tmp"\nmv "$tmp" "$1"\n' > "$P/atomic.sh"        # ghi file nguyên tử: mv tên không đọc được
printf '#!/bin/sh\nln -s ~ "$TMPDIR/x"\nmv "$TMPDIR/x" build/l\n' > "$P/lnmv.sh"             # link rồi chuyển nó đi
chmod +x "$P/mk.sh" "$P/ok.sh" "$P/clean.sh" "$P/atomic.sh" "$P/lnmv.sh"
check 0 'bash atomic.sh out.json && rm -rf build/x/y'                       # đối chứng (corpus 27/10): mv của script không tạo link
check 2 'bash lnmv.sh && rm -rf build/l/'
check 2 'bash mk.sh && rm -rf build/l/'
check 2 'sh ./mk.sh; rm -rf build/l/x'
check 2 './mk.sh && rm -rf build/l/'
check 2 'source mk.sh && rm -rf build/l/'
check 2 '. ./mk.sh && rm -rf build/l/'
check 2 'bash -e mk.sh && rm -rf build/l/'
check 2 'for i in 1 2; do rm -rf build/l/; bash mk.sh; done'               # rm đứng trước nhưng chạy sau (lượt 2)
check 0 'bash ok.sh && rm -rf build/l/'                                     # đối chứng: script không tạo link
check 0 'bash mk.sh && rm -rf build/l'                                      # đối chứng: không dấu /, xoá chính link
check 0 'bash clean.sh'                                                     # đối chứng: rm trong script không bị xét (như trước)

U="$(id -u)"; mkdir -p "/tmp/claude-$U" && SCR="$(mktemp -d "/tmp/claude-$U/devkit-hwr3.XXXXXX")" || { fail "no scratch dir"; SCR=""; }
if [ -n "$SCR" ]; then
  trap 'rm -rf "$TMP" "$SCR"' EXIT
  SCRP="$(cd "$SCR" && pwd -P)"
  mkdir -p "$SCR/plain"
  # 1. trong thư mục scratch: glob rồi `..` ra khỏi nó
  check 2 "rm -rf $SCRP/plain/*/../../../.."
  check 0 "rm -rf $SCRP/plain/*/../x"                                       # đối chứng: vẫn trong scratch
  # 2. (P0) rm -r không -f sau cd vào link chính lệnh tạo
  check 2 "ln -s ~ $SCRP/l && cd $SCRP/l && rm -r Documents"
  check 2 "cd $SCRP/plain && ln -s ~ l; cd l; rm -r *"
  check 2 "cd $SCRP && ln -s ~ l && cd l && rm -r Documents"
  check 2 "ln -s ~ $SCRP/l && cd $SCRP/l && cd Library && rm -r Caches"       # cd tương đối từ đó: vẫn ở nơi link trỏ tới
  check 2 "ln -s ~ $SCRP/l && pushd $SCRP/l && rm -r Documents"
  check 2 "ln -s ~ $SCRP/l && cd $SCRP/l && rm -r \"\$PWD/Documents\""
  check 2 "ln -s ~ $SCRP/l && cd $SCRP/l && rsync -a --delete $SCRP/plain/ Documents/"
  check 0 "ln -s ~ $SCRP/l && cd $SCRP/plain && rm -r x"                      # đối chứng: cd vào thư mục khác
  check 0 "ln -s ~ $SCRP/l && cd $SCRP/l && cd $SCRP/plain && rm -r x"        # đối chứng: cd tuyệt đối sau đó
  check 0 "cd $SCRP/plain && rm -r x"
  check 0 "ln -s ~ $SCRP/l && cd $SCRP/l && ls"
fi

[ "$FAILS" -eq 0 ] && echo "✅ test_hardware_round3_427: all passed" || { echo "❌ test_hardware_round3_427: $FAILS failed"; exit 1; }
