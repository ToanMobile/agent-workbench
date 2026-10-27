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

# check <rc mong đợi> <lệnh> [project] — payload cwd và CLAUDE_PROJECT_DIR là project. CHECK_CPU: giới hạn giây CPU của hook (ulimit -t:
# đo CPU, không đo đồng hồ); CHECK_LABEL: tên in ra thay cho lệnh dài (review vòng 3, như tests/gates/test_hardware_backlog427.sh)
check() {
  local want="$1" c="$2" p="${3:-$P}"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$c" "$p" > "$TMP/in.json"
  ( cd "$p" && { [ -z "${CHECK_CPU:-}" ] || ulimit -t "$CHECK_CPU"; } && CLAUDE_PROJECT_DIR="$p" bash "$HOOK" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$? c="${CHECK_LABEL:-$c}"
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

# ── Review vòng 3 ──
# R1. (P1) tên glob dưới / trên một đích chép: shell khớp * với tree/lnk (link tới ~), rm đi theo nó xoá ~/x. Từng đọc * như một tên.
check 2 'cp -R tree dist/t && rm -rf dist/t/*/x'
check 2 'cp -R tree dist/t && rm -rf dist/t/l?k/x'
check 2 'rsync -a tree/ dist/t/ && rm -rf dist/t/*/x'
check 2 'ditto tree dist/t && rm -rf dist/t/[l]nk/x'
check 2 'cp -R tree dist/t && rm -rf dist/t/[!L]nk/x'                         # lớp phủ định: casefold một mình không khớp lnk
check 2 'cp -R tree dist/t && rm -rf dist/t/[^S]*/x'
check 2 'cp -R tree dist/t && rm -r dist/t/*/x'                               # không -f
check 2 "cp -R tree dist/t; trap 'rm -rf dist/t/*/x' EXIT"                    # thân trap
check 2 'cp -R tree dist/ && rm -rf dist/*/lnk/x'                             # đích/<tên nguồn>: glob ở tên nguồn
check 2 'cp -R tree dist/t && rm -rf dist/t*/lnk/x'                           # glob ở chính tên đích
check 2 'tar -xf a.tar -C build/e && rm -rf build/e*/pkg/x'                   # glob ở tên thư mục giải nén
check 0 'cp -R tree dist/t && rm -rf dist/t/s*/x'                             # đối chứng: s* chỉ khớp sub (thư mục thật)
check 0 'cp -R tree dist/t && rm -rf dist/t/*'                                # đối chứng: glob ở tên cuối, không dấu /
check 0 'cp -R src dist/s && rm -rf dist/s/*/x'                               # đối chứng: nguồn không có link
check 0 'cp -R tree dist/t && rm -rf dist/u*/lnk/x'                           # đối chứng: glob không khớp đích nào

# R2. (P0) rm -r chứa một worktree git đã đăng ký (của phiên khác): `rm -rf .claude/worktrees` từ main
W="$TMP/work/wtp"
newrepo "$W"
for w in .claude/worktrees/w1 .claude/worktrees/w2 build/wt; do git -C "$W" worktree add -q --detach "$W/$w" 2>/dev/null || fail "worktree add $w"; done
check 2 'rm -rf .claude/worktrees' "$W"
check 2 'rm -r .claude/worktrees' "$W"                                        # không -f
check 2 'rm -rf .claude/worktrees/*' "$W"
check 2 'find .claude/worktrees -delete' "$W"
check 2 'rsync -a --delete empty/ .claude/worktrees/' "$W"
check 2 'rm -rf build' "$W"                                                    # build output chứa worktree
check 2 'cd .claude && rm -rf worktrees/' "$W"
check 0 'rm -rf .claude/worktrees/w1' "$W"                                     # đối chứng: chính một worktree — phán quyết cũ
check 0 'rm -rf .claude/worktrees/w1/build' "$W"
check 0 'rm -rf .claude/worktrees/x*' "$W"                                     # đối chứng: glob không khớp worktree nào
check 0 'rm -rf build/tmp' "$W"
check 0 'rm -rf build/wt/node_modules' "$W"

# R3. (P2 chặn nhầm) đích chép / clone không đọc được không còn chặn mọi rm qua một thư mục; cả hai không biết thì vẫn chặn
printf '#!/bin/sh\ncp -R "$A" "$B"\ntar -x -C "$D" -f a.tar\ngit clone "$U" "$D"\n' > "$P/cpvar.sh"
check 0 'cp -R src "$OUT" && rm -rf build/tmp/x'
check 0 'git clone "$URL" && rm -rf build/tmp/x'
check 0 'ssh host "cp -r /a /b" && rm -rf build/tmp/x'
check 0 'bash cpvar.sh && rm -rf build/tmp/x'
check 2 'cp -R src "$OUT" && rm -r "$OUT"/x/'                                  # đường dẫn rm cũng không đọc được
check 2 'cp -R src "$OUT" && rm -rf build/*/x'
check 2 'cd "$NOPE_DEVKIT_R3" && cp -R ~/nope_devkit_r3 "$OUT" && rm -r pkg/x'   # cwd không biết, rm -r không -f
check 2 'cd "$NOPE_DEVKIT_R3" && cp -R ~/nope_devkit_r3 "$OUT" && rm -r "$PWD/pkg/x"'
check 2 'tar -xf a.tar -C "$NOPE_DEVKIT_R3" && rm -rf build/tmp/x/'           # giải nén trên dòng lệnh: như vòng 2
check 2 'ssh host "cp -r /a /b" && ssh host "rm -rf /b/x/"'                    # lệnh ssh sau vẫn thấy đích không biết
check 2 'ssh host "cp -r /a /b && rm -rf /b/x/"'
check 2 "ssh localhost 'ln -s ~ build/l' && rm -rf build/l/"                  # tên ln của ssh vẫn dùng chung (ssh localhost)

# R4. (P2 thời gian, giới hạn CPU) note_copy / extracted_entry so mỗi lệnh với mọi thư mục đã ghi; thân trap xét lại mỗi cwd, git mỗi đường dẫn
python3 -c 'print("#!/bin/sh"); [print("cp -R src dist/pkg/component_with_a_fairly_long_directory_name_%03d/output/release/x  # step %d" % (i, i)) for i in range(400)]' > "$P/big.sh"
CHECK_CPU=2 CHECK_LABEL="300 × (cp -R + rm -rf) (CPU ≤ 2 s)" check 0 "$(python3 -c 'print(" && ".join("cp -R src dist/s%d && rm -rf build/t%d/x" % (i, i) for i in range(300)))')"
CHECK_CPU=2 CHECK_LABEL="500 × cp -R (CPU ≤ 2 s)" check 0 "$(python3 -c 'print(" && ".join("cp -R src dist/s%d" % i for i in range(500)))') && rm -rf build/tmp/x"
CHECK_CPU=2 CHECK_LABEL="50 × (trap + cd) (CPU ≤ 2 s)" check 0 "$(python3 -c 'print(" && ".join("trap \"rm -rf build/t%d\" EXIT && cd build/d%d && cd ../.." % (i, i) for i in range(50)))')"
CHECK_CPU=2 CHECK_LABEL="bash <script 45 KB, 400 cp -R> (CPU ≤ 2 s)" check 0 'bash big.sh && rm -rf build/tmp/x'
# git ls-files một lần cho cả project từ đường dẫn thứ 5: build output đang track vẫn bị chặn, như khi hỏi từng đường dẫn
mkdir -p "$P/target/gen" && printf 'k\n' > "$P/target/gen/keep.txt" && git -C "$P" add target/gen/keep.txt && git -C "$P" commit -qm keep
check 2 'rm -rf build/q1 build/q2 build/q3 build/q4 build/q5 target/gen'
check 2 'rm -rf build/q1 build/q2 build/q3 build/q4 build/q5 target'
check 0 'rm -rf build/q1 build/q2 build/q3 build/q4 build/q5 target/other'

# R5. (P3 chặn nhầm) nguồn mkdir của chính lệnh; trap đã gỡ; cd chạy nền
check 0 'mkdir -p out && cp -R out dist/o && rm -rf dist/o/cache/'
check 0 'mkdir -p out/sub && cp -R out dist/o && rm -rf dist/o/sub/x/'
check 2 'mkdir -p out && ln -s ~ out/l && cp -R out dist/o && rm -rf dist/o/l/'
check 2 'mkdir -p out && tar -xf a.tar -C out && cp -R out dist/o && rm -rf dist/o/pkg/'
check 2 'ln -s ~ out; mkdir -p out && cp -R out dist/o && rm -rf dist/o/x/'
check 0 "trap 'rm -rf build' EXIT; trap - EXIT; cd ~"
check 0 "trap 'rm -rf build' EXIT; trap 'echo bye' EXIT; cd ~"
check 0 "trap 'rm -rf build' 0; trap SIGEXIT; cd ~"                               # một toán hạng: gỡ; 0 là EXIT
check 2 "trap 'rm -rf build' EXIT; false && trap - EXIT; cd ~"                     # gỡ không chắc chạy
check 2 "trap 'rm -rf build' EXIT INT; trap - EXIT; cd ~"                          # còn INT
check 2 "trap 'rm -rf build' EXIT; (trap - EXIT); cd ~"                            # gỡ ở shell con
check 2 "trap 'rm -rf build' EXIT; { trap - EXIT; } | cat; cd ~"                   # nhóm trong ống: shell con
check 2 "trap 'rm -rf build' EXIT; if true; then trap - EXIT; fi; cd ~"
check 2 "trap 'rm -rf build' EXIT; trap - EXIT & cd ~"                             # gỡ ở shell con chạy nền
check 2 "trap 'rm -rf build' EXIT; f() { trap - EXIT; }; cd ~"                     # thân hàm: chạy lúc gọi
check 2 "trap 'rm -rf build' EXIT; while false; do trap - EXIT; done; cd ~"
check 2 "trap 'rm -rf build' EXIT; trap 'rm -rf build' EXIT; cd ~"                 # cùng thân đặt lại: vẫn còn
check 2 "trap - EXIT; trap 'rm -rf build' EXIT; cd ~"
check 0 'cd ~ & rm -rf build'
check 2 'cd ~ &>/dev/null && rm -rf build'                                        # &> là chuyển hướng, không phải chạy nền
check 2 'cd ~ 2>&1 && rm -rf build'
check 2 'cd ~ >&2; rm -rf build'

# R6. (có từ trước) cd trong chuỗi eval, trong script mà source / . chạy, chdir của zsh
printf '#!/bin/sh\ncd ~\n' > "$P/go.sh"
printf '#!/bin/sh\nX=$(cd build && pwd)\necho "$X"\n' > "$P/sub.sh"
check 2 "eval 'cd ~' && rm -rf build"
check 2 'eval cd ~; rm -rf build'
check 2 'source go.sh && rm -rf build'
check 2 '. ./go.sh; rm -rf build'
check 2 'chdir ~ && rm -rf build'
check 0 "eval 'echo hi' && rm -rf build"
check 0 'source sub.sh && rm -rf build'                                       # cd trong $( … ): shell con
check 0 'eval "$(ssh-agent -s)" && rm -rf build'

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
