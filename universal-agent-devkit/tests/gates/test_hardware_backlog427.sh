#!/usr/bin/env bash
# hooks/hardware_safety_gate.sh, backlog #427 vòng 2 (các lỗ vòng 1 để lại; vòng 1: tests/gates/test_hardware_issue427.sh):
#   1. Thứ tự: rm -r / find -delete / rsync --delete / cd đứng TRƯỚC ln mà chạy SAU nó (vòng lặp, hàm gọi sau) được xét khi tên link
#      chưa được ghi. Nay cổng gom mọi tên link của cả lệnh trước (lượt 1), rồi xét lại cả lệnh với đủ tên (lượt 2).
#   2. Lệnh tạo link khác ln: cp -s / --symbolic-link (ghi tên như ln); os.symlink / symlinkSync / symlink / `ln -s` trong chương trình
#      python -c / node -e / perl -e (cả thân heredoc) → "*"; mv (link chuyển đi vẫn là link) → tên đích; tar -x / unzip: rm -r đi xuyên qua
#      một mục bên dưới thư mục giải nén (mục đó có thể là link trong file nén) bị chặn — xoá chính thư mục đó, hay mục cuối không có
#      dấu /, vẫn được.
#   3. adb shell "<lệnh>" (và ssh): cùng phép đó trong lệnh chạy trên máy kia — `ln -s /data /data/local/tmp/l; rm -rf /data/local/tmp/l/`
#      lọt qua miễn trừ /data/local/tmp; cd vào link đó làm thư mục hiện tại trên máy kia thành "chỉ biết lúc chạy".
#   4. glob được xét theo kết quả khớp: hơn 2000 kết quả thì từ chối (đã có từ 6bf699e8, ghim lại); nay thêm: Python glob đọc [^…] và
#      [[:alpha:]] khác shell, và {a..c} không được bung — kết quả khớp thật (link tới home) không được xét.
#   5. git_tracks: mọi lần git lỗi (rc ≠ 0) được xét như build output chưa track → cho xoá. Nay rc 128 kèm "not a git repository (or
#      any …" (project ngoài git) giữ cách xét đó; git lỗi khác, quá hạn, index hỏng, worktree mất gitdir được xét như đang track → chặn.
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
# chính sách thiết bị rỗng: dòng adb chỉ đo phép rm, không hỏi adb get-serialno
export XDG_CONFIG_HOME="$TMP/cfg"; unset ADB_DENY_SERIALS ADB_ALLOW_SERIALS

newrepo() {   # newrepo <dir>: repo git có một file nguồn đã commit, build/ không track
  mkdir -p "$1/src" "$1/build" && git -C "$1" init -q . && git -C "$1" config user.email t@t && git -C "$1" config user.name t \
    && git -C "$1" config commit.gpgsign false && printf 'x\n' > "$1/src/a.kt" && git -C "$1" add -A && git -C "$1" commit -qm init
}
P="$TMP/work/proj"
newrepo "$P"

# check <rc mong đợi> <lệnh> [project]; CHECK_PATH thay PATH của hook (git giả)
check() {
  local want="$1" c="$2" p="${3:-$P}"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$c" "$p" > "$TMP/in.json"
  ( cd "$p" && PATH="${CHECK_PATH:-$PATH}" CLAUDE_PROJECT_DIR="$p" bash "$HOOK" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$?
  if [ "$rc" = "$want" ]; then ok "rc $rc: $c"; else fail "rc $rc (want $want): $c — $(head -c 200 "$TMP/err" | tr '\n' ' ')"; fi
}

U="$(id -u)"; mkdir -p "/tmp/claude-$U" && SCR="$(mktemp -d "/tmp/claude-$U/devkit-hwb427.XXXXXX")" || { fail "no scratch dir"; SCR=""; }
if [ -n "$SCR" ]; then
  trap 'rm -rf "$TMP" "$SCR"' EXIT
  SCRP="$(cd "$SCR" && pwd -P)"
  # plain, ex, d: thư mục thật; inside: link có sẵn tới plain; gx/l: link có sẵn tới home (chỉ dòng glob mục 4 đi vào gx)
  mkdir -p "$SCR/plain" "$SCR/ex" "$SCR/d" "$SCR/gx/real" && ln -s "$SCRP/plain" "$SCR/inside" && ln -s "$HOME" "$SCR/gx/l"

  # 1. rm / find -delete / rsync --delete / cd đứng trước ln trong vòng lặp hay hàm: lượt 2 xét với mọi tên link của cả lệnh
  check 2 "for i in 1 2; do rm -rf $SCRP/l/; ln -s ~ $SCRP/l; done"
  check 2 "while true; do rm -rf $SCRP/l/; ln -s ~ $SCRP/l; done"
  check 2 "f() { rm -rf $SCRP/l/; }; ln -s ~ $SCRP/l; f"
  check 2 "for i in 1 2; do rm -r $SCRP/l/; ln -s ~ $SCRP/l; done"            # không -f
  check 2 "for i in 1 2; do find $SCRP/l/ -delete; ln -s ~ $SCRP/l; done"
  check 2 "for i in 1 2; do rsync -a --delete $SCRP/plain/ $SCRP/l/; ln -s ~ $SCRP/l; done"
  check 2 "for i in 1 2; do cd $SCRP/l && rm -rf Documents; ln -s ~ $SCRP/l; done"
  check 2 "while rm -rf $SCRP/l/; do ln -s ~ $SCRP/l; done"                  # điều kiện của while cũng chạy lại
  check 2 "until false; do rm -rf $SCRP/l/; ln -s ~ $SCRP/l; done"
  check 2 "for a in 1 2; do for b in 1; do rm -rf $SCRP/l/; done; ln -s ~ $SCRP/l; done"   # rm ở vòng trong, ln sau đó ở vòng ngoài
  check 2 "repeat 2; do rm -rf $SCRP/l/; ln -s ~ $SCRP/l; done"               # vòng lặp của zsh (Bash tool chạy zsh)
  check 2 "foreach x (1 2) rm -rf $SCRP/l/; ln -s ~ $SCRP/l; end"
  check 2 "(sleep 1; rm -rf $SCRP/l/) & ln -s ~ $SCRP/l"                      # chạy nền: rm có thể chạy sau ln
  check 2 "(sleep 1; rm -rf $SCRP/l/) | ln -s ~ $SCRP/l"                      # chặng ống chạy cùng lúc
  check 2 "rm -rf $SCRP/l/ | ln -s ~ $SCRP/l"
  check 2 "rm -rf $SCRP/l/ \"\$(ln -s ~ $SCRP/l)\""                           # lệnh con chạy trước lệnh chứa nó
  check 2 "find $SCRP -maxdepth 0 -exec sh -c 'rm -rf $SCRP/l/; ln -s ~ $SCRP/l' \\;"   # chạy lại theo từng mục
  check 2 "printf 'a\\nb\\n' | xargs -I{} sh -c 'rm -rf $SCRP/l/; ln -s ~ $SCRP/l'"
  # đối chứng: rm ở ngoài vòng lặp, đứng trước, chạy một lần trước mọi ln (dạng dọn scratch rồi dựng lại, corpus 27/10: 11 lệnh thật)
  check 0 "rm -rf $SCRP/l/; ln -s ~ $SCRP/l"
  check 0 "S=$SCRP/s2; rm -rf \$S; mkdir -p \$S; for d in a b; do ln -s ~ \$S/\$d; done; ls \$S | head -3"
  check 0 "S=$SCRP/m; ln -s x \$S/lib; for i in 1 2; do rm -rf \$S/plain2; done"   # lượt 2 vẫn biết phép gán S= (lệnh ngoài vòng lặp)
  check 0 "$(printf 'S=%s/m2; rm -rf $S; mkdir -p $S; for d in a b; do ln -s ~ $S/$d; done; python3 - <<%s\ns = "void F() {"\nprint(s)\nEOF' "$SCRP" "'EOF'")"   # "F() {" trong thân heredoc đã cắt: không phải hàm shell
  check 0 "for i in 1 2; do rm -rf $SCRP/plain/; ln -s ~ $SCRP/l; done"       # đối chứng: thư mục không liên quan
  check 0 "for i in 1 2; do rm -rf $SCRP/l; ln -s ~ $SCRP/l; done"            # đối chứng: không dấu /, rm chỉ xoá chính link

  # 2a. cp -s / --symbolic-link: tên như ln (đích, và nguồn: đích là thư mục có sẵn thì link là <đích>/<nguồn>)
  check 2 "cp -s ~ $SCRP/l && rm -rf $SCRP/l/"
  check 2 "cp --symbolic-link ~ $SCRP/l && rm -rf $SCRP/l/"
  check 2 "cp -rs ~/Documents $SCRP/l && rm -rf $SCRP/l/x"
  check 2 "gcp -s ~ $SCRP/l; rm -rf $SCRP/l/"
  check 2 "cp -s \"\$NOPE_DEVKIT_B427\" $SCRP && rm -rf $SCRP/plain/"         # toán hạng không đọc được: mọi đường đi qua thư mục
  check 0 "cp ~/.profile $SCRP/l && rm -rf $SCRP/plain/"                      # đối chứng: cp thường không tạo link
  check 0 "cp -s a $SCRP/l && rm -rf $SCRP/plain/"
  # 2b. chương trình nội tuyến của interpreter tạo link: tên không đọc được → "*"
  check 2 "python3 -c 'import os; os.symlink(os.path.expanduser(\"~\"), \"$SCRP/l\")' && rm -rf $SCRP/l/"
  check 2 "node -e \"require('fs').symlinkSync(require('os').homedir(), '$SCRP/l')\" && rm -rf $SCRP/l/"
  check 2 "perl -e 'symlink \$ENV{HOME}, \"$SCRP/l\"' && rm -rf $SCRP/l/"
  check 2 "python3 -c 'import os; os.system(\"ln -s ~ $SCRP/l\")' && rm -rf $SCRP/l/"
  check 2 "uv run python -c 'import os; os.symlink(\"/\", \"$SCRP/l\")' && rm -rf $SCRP/l/"
  check 2 "$(printf 'python3 - <<%s\nimport os\nos.symlink(os.path.expanduser("~"), "%s/l")\nEOF\nrm -rf %s/l/' "'EOF'" "$SCRP" "$SCRP")"
  check 2 "ruby -e 'File.symlink(Dir.home, \"$SCRP/l\")' && rm -rf $SCRP/l/"
  check 2 "php -r 'symlink(\"/\", \"$SCRP/l\");' && rm -rf $SCRP/l/"
  check 0 "python3 -c 'print(1)' && rm -rf $SCRP/plain/"                       # đối chứng: không tạo link
  # đối chứng (corpus 27/10): chữ symlink trong đối số / chuỗi, không phải lời gọi tạo link
  check 0 "python3 tool.py -b \"relink: bỏ qua thư mục là symlink\" --out $SCRP/o && rm -rf $SCRP/plain/"
  check 0 "$(printf 'python3 - <<%s\nimport subprocess\nsubprocess.run(["bash", "install.sh", "--mode=symlink"])\nEOF\nrm -rf %s/plain/' "'EOF'" "$SCRP")"
  check 0 "$(printf 'cat > %s/x.sh <<%s\nln -s /etc/hosts %s/hl\nEOF\nrm -rf %s/plain/' "$SCRP" "'EOF'" "$SCRP" "$SCRP")"   # thân shell: ln có tên
  check 0 "python3 -c 'import os; os.symlink(\"a\", \"b\")' && rm -rf build"   # đối chứng: rm không đi qua thư mục nào
  check 0 "$(printf 'git commit -q -m "$(cat <<%s\nfix: symlink handling\nEOF\n)" && rm -rf %s/plain/' "'EOF'" "$SCRP")"   # thân heredoc là message
  # 2c. mv: một link chuyển đi vẫn là link — tên đích (cả -t DIR, đích là thư mục có sẵn)
  check 2 "ln -s ~ $SCRP/x; mv $SCRP/x $SCRP/l; rm -rf $SCRP/l/"
  check 2 "mv $SCRP/inside $SCRP/l && rm -rf $SCRP/l/"                        # link có sẵn đổi tên
  check 2 "mv -t $SCRP/d $SCRP/inside && rm -rf $SCRP/d/inside/"
  check 2 "mv $SCRP/inside $SCRP/d/ && rm -rf $SCRP/d/inside/"
  check 2 "mv \"\$NOPE_DEVKIT_B427\" \"\$NOPE2_DEVKIT_B427\" && rm -rf $SCRP/plain/"   # đích không đọc được
  check 2 "mv $SCRP/inside \"$SCRP/proof-\$NOPE_DEVKIT_B427.png\" && rm -rf $SCRP/proof-1.png/"   # tên đích chỉ biết đuôi: *.png
  check 2 "mv $SCRP/inside \"$SCRP/proof-\$NOPE_DEVKIT_B427.png\" && rm -rf $SCRP/PROOF-1.PNG/x"
  check 0 'mv a b && rm -rf build'                                            # đối chứng: thường gặp, phải qua
  check 0 "st=\$(date +%s); mv Assets/Temp/s.png reports/proof-\$st.png && rm -rf Assets/Temp"   # đối chứng: quy trình ảnh nghiệm thu
  check 0 "mv $SCRP/inside \"$SCRP/proof-\$NOPE_DEVKIT_B427.png\" && rm -rf $SCRP/plain/"
  check 0 "mv $SCRP/a $SCRP/b && rm -rf $SCRP/plain/"
  check 0 "mv $SCRP/inside $SCRP/l && rm -rf $SCRP/l"                         # đối chứng: không dấu /, chỉ xoá chính link
  # 2d. tar -x / unzip: rm -r đi xuyên qua một mục bên dưới thư mục giải nén
  check 2 "tar -xf a.tar -C $SCRP/ex && rm -rf $SCRP/ex/pkg/"
  check 2 "tar xzf a.tgz -C $SCRP/ex; rm -rf $SCRP/ex/pkg/build"
  check 2 "cd $SCRP/ex && tar -xzf a.tgz && rm -rf pkg/"
  check 2 "tar -xf a.tar -C $SCRP/ex && cd $SCRP/ex/pkg && rm -r *"
  check 2 "unzip -o a.zip -d $SCRP/ex && rm -rf $SCRP/ex/pkg/"
  check 2 "bsdtar -xf a.tar --directory=$SCRP/ex && find $SCRP/ex/pkg/ -delete"
  check 2 'tar -xzf deps.tgz && rm -rf build/tmp'                             # giải nén vào chính project
  check 2 "for i in 1 2; do rm -rf $SCRP/ex/pkg/; tar -xf a.tar -C $SCRP/ex; done"
  check 2 "tar -xf a.tar -C \"\$NOPE_DEVKIT_B427\" && rm -rf $SCRP/plain/"     # thư mục giải nén không biết: mọi đường qua thư mục
  check 0 "tar -xf a.tar -C $SCRP/ex && rm -rf $SCRP/ex"                       # đối chứng: xoá chính thư mục giải nén (rm không theo link bên trong)
  check 0 "tar -xf a.tar -C $SCRP/ex && rm -rf $SCRP/ex/pkg"                   # đối chứng: mục cuối không dấu /
  check 0 "tar -xf a.tar -C $SCRP/ex && rm -rf $SCRP/plain/"                   # đối chứng: ngoài thư mục giải nén
  check 0 'tar -czf a.tgz build && rm -rf build/'                              # đối chứng: nén, không giải nén
  check 0 'tar -tzf deps.tgz && rm -rf build/tmp'                              # đối chứng: chỉ liệt kê
  check 0 "unzip -l a.zip && rm -rf $SCRP/ex/pkg/"
  check 0 'tar -xzf deps.tgz && rm -rf build'

  # 4. glob: kết quả khớp thật của shell. Ghim (đã chặn từ 6bf699e8): hơn 2000 kết quả có thể ra ngoài thư mục
  mkdir -p "$SCR/many" && ( cd "$SCR/many" && mkdir d{1..2100} )
  check 2 "rm -rf $SCRP/many/*/"
  check 2 "find $SCRP/many/*/ -delete"
  check 0 "rm -rf $SCRP/many/*"                                               # tên cuối là glob: không duyệt, như cũ
  # mới: [^…] (Python đọc ^ là chữ), lớp POSIX [[:alpha:]] (Python không biết), {a..c} (không được bung): link tới home không được xét
  check 2 "rm -rf $SCRP/gx/[^z]*/"
  check 2 "rm -r $SCRP/gx/[^z]/"
  check 2 "rm -rf $SCRP/gx/[[:alpha:]]/"
  check 2 "rm -rf $SCRP/gx/{k..m}/"
  check 2 "rm -rf $SCRP/gx/{a..z}*/"
  check 0 "rm -rf $SCRP/gx/[^l]*/"                                            # đối chứng: chỉ khớp real (bản cũ chặn nhầm: Python đọc [^l] là {^, l})
  check 0 "rm -rf $SCRP/gx/[[:alpha:]]eal/"
  check 0 "rm -rf $SCRP/gx/{q..s}eal/"
  check 0 "rm -rf $SCRP/gx/*"
fi
# … trong build output của project: cùng lỗ ngoài thư mục scratch
check 2 'for i in 1 2; do rm -rf build/l/; ln -s ~ build/l; done'
check 0 'for i in 1 2; do rm -rf build/l; ln -s ~ build/l; done'

# 3. adb shell / ssh: lệnh chạy trên máy kia, cùng phép tên link
check 2 'adb shell "ln -s /data /data/local/tmp/l; rm -rf /data/local/tmp/l/"'
check 2 'adb shell "ln -s /system/app /data/local/tmp/l; rm -rf /data/local/tmp/l/"'   # tên nguồn (app) không trùng: chặn nhờ tên link l
check 2 'adb shell "ln -s /data /data/local/tmp/l && rm -r /data/local/tmp/l/app"'
check 2 "adb shell 'ln -s /system /data/local/tmp/l; find /data/local/tmp/l/ -delete'"
check 2 'adb shell "ln -s /system/app /data/local/tmp/l; cd /data/local/tmp/l && rm -rf *"'   # cwd trên máy kia: chỉ biết lúc chạy
check 2 'adb -s emulator-5554 shell "cd /data/local/tmp && ln -s /system/app l && rm -rf l/"'
check 2 'adb shell "for i in 1 2; do rm -rf /data/local/tmp/l/; ln -s /data /data/local/tmp/l; done"'
check 2 'adb shell "cp -s /data /data/local/tmp/l; rm -rf /data/local/tmp/l/"'
check 2 "ssh host 'ln -s / l; rm -rf l/'"
check 0 'adb shell "rm -rf /data/local/tmp/plain/"'                          # đối chứng: như cũ
# đối chứng. Nguồn /data thì tên data cũng được ghi như ở máy này (ln -s /data <thư mục có sẵn> tạo <thư mục>/data): mọi đường qua /data
# bị chặn — nên đối chứng dùng nguồn khác
check 0 'adb shell "ln -s /system/bin/sh /data/local/tmp/l; rm -rf /data/local/tmp/l"'   # không dấu /: rm chỉ xoá chính link
check 0 'adb shell "ln -s /data/local/tmp/a /data/local/tmp/l; rm -rf /data/local/tmp/plain/"'
check 0 'adb shell "ln -s /system/bin/sh /data/local/tmp/l; cd /data/local/tmp/plain && rm -rf *"'
check 0 "ssh host 'rm -rf build/'"
# 3b. thiết bị bắt đầu ở / (biết): cd tới chỗ chỉ biết lúc chạy ($VAR, ~, -, `..` của nó) từng làm đích tương đối không được xét
check 2 "adb shell 'cd \$ANDROID_DATA && rm -rf *'"
check 2 "adb shell 'cd && rm -rf *'"
check 2 "adb shell 'cd /data/local/tmp && cd - && rm -rf app'"
check 2 "adb shell 'cd \$ANDROID_DATA/app && cd .. && rm -rf local'"
check 2 'adb shell "ln -s /system/app /data/local/tmp/l; cd /data/local/tmp/l && cd .. && rm -rf x"'
check 2 "ssh host 'ln -s / l; cd l && rm -rf *'"
check 2 "ssh host 'ln -s / l; cd l && cd etc && rm -rf *'"                  # cd tương đối từ đó vẫn chỉ biết lúc chạy
check 0 "adb shell 'cd /data/local/tmp && rm -rf *'"                        # đối chứng: cwd biết, trong /data/local/tmp
check 0 "adb shell 'cd /data/local/tmp/x && cd .. && rm -rf y'"
check 0 "ssh host 'cd \$HOME/x && rm -rf build'"                             # đối chứng: máy ssh không xét đích tương đối, như cũ

# 5. git_tracks khi git lỗi. Đối chứng: repo thật (build/ không track) và thư mục không phải repo (rc 128 "not a git repository")
check 0 'rm -rf build'
N="$TMP/nogit"; mkdir -p "$N/build"
if git -C "$N" rev-parse --git-dir >/dev/null 2>&1; then echo "skip: $N nằm trong một repo git"; else check 0 'rm -rf build' "$N"; fi
B="$TMP/work/broken"; newrepo "$B" && printf 'garbage' > "$B/.git/index"     # index hỏng: ls-files rc 128, không phải "not a git repository"
check 2 'rm -rf build' "$B"
W="$TMP/work/lostwt"; mkdir -p "$W/build" && printf 'gitdir: %s/nowhere/.git/worktrees/x\n' "$TMP" > "$W/.git"   # worktree mất gitdir
check 2 'rm -rf build' "$W"
FG="$TMP/fakegit"; mkdir -p "$FG"
cat > "$FG/git" <<'EOF'
#!/usr/bin/env bash
# git giả: config trả false, ls-files làm theo FAKE_GIT_MODE
case " $* " in
  *" config "*) echo false; exit 0 ;;
esac
case "${FAKE_GIT_MODE:-}" in
  corrupt) echo "fatal: index file corrupt" >&2; exit 128 ;;
  rc1) exit 1 ;;
  slow) exec sleep 8 ;;
  nonrepo) echo "fatal: not a git repository (or any of the parent directories): .git" >&2; exit 128 ;;
esac
exit 0
EOF
chmod +x "$FG/git"
export CHECK_PATH="$FG:$PATH"
FAKE_GIT_MODE=corrupt; export FAKE_GIT_MODE; check 2 'rm -rf build'
FAKE_GIT_MODE=rc1; check 2 'rm -rf build'
FAKE_GIT_MODE=slow; check 2 'rm -rf build'                                    # quá hạn 5 s của ls-files
FAKE_GIT_MODE=nonrepo; check 0 'rm -rf build'                                 # đối chứng: không phải repo
FAKE_GIT_MODE=nonrepo; check 0 'rm -rf src/old/build'                         # đối chứng: đường dẫn sâu, như cũ
unset CHECK_PATH FAKE_GIT_MODE

[ "$FAILS" -eq 0 ] && echo "✅ test_hardware_backlog427: all passed" || { echo "❌ test_hardware_backlog427: $FAILS failed"; exit 1; }
