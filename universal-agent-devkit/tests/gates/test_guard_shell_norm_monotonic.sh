#!/usr/bin/env bash
# hooks/shell_norm.py + hooks/block-dangerous-git.sh + hooks/hardware_safety_gate.sh: the MONOTONICITY net of the shared command reading
# (review 15/10 of the W3 lane: a refactor of two security guards must never let a dangerous command through that was blocked before).
#   - DANGEROUS: a frozen list of commands that MUST stay blocked (rc 2, and not by a crash), each through the hook that owns it:
#     git danger -> block-dangerous-git.sh, device / filesystem danger -> hardware_safety_gate.sh (never "either hook": a row that the
#     other hook happens to block proves nothing about this one). Three parts: plain commands; every wrapper of shell_norm.WRAPPERS and
#     every way to hand a command line to another program (sudo / env / time / nohup / bash -c / su -c / ssh / adb shell / xargs /
#     find -exec / eval / $(…) / backticks / heredocs / continuations / newlines / ; && || pipes) applied to a few bases; and the exact
#     strings of the review findings (heredoc delimiters, written files, hooks, compound pipes, interpreter bodies, wrapper tables).
#   - HARMLESS: strings that must pass both hooks (text that merely mentions a dangerous command, data written to notes, dry runs).
# The hooks are the real ones, fed JSON payloads only (no command is ever run). HW_HOOK / GG_HOOK point at a scratch copy of hooks/ for
# a mutation check (shell_norm.py must sit beside the copies): see the mutants in the review report of 15/10.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HW="${HW_HOOK:-$DEVKIT_DIR/hooks/hardware_safety_gate.sh}"
GG="${GG_HOOK:-$DEVKIT_DIR/hooks/block-dangerous-git.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
unset HARDWARE_SAFETY_GATE HARDWARE_OVERRIDE DEVKIT_ALLOW_BRANCH CDPATH
P="$TMP/work/proj"
mkdir -p "$P/src" "$P/build"
git -C "$P" init -q . && git -C "$P" config user.email t@t && git -C "$P" config user.name t && git -C "$P" config commit.gpgsign false
printf 'x\n' > "$P/src/a.kt" && printf 'z\n' > "$P/README.md"
git -C "$P" add -A && git -C "$P" commit -qm init && git -C "$P" branch feat

python3 -I - "$GG" "$HW" "$P" "$TMP" <<'PY'
import concurrent.futures as cf
import json
import os
import shlex
import subprocess
import sys

gg, hw, proj, tmp = sys.argv[1:5]
HOOK = {"git": gg, "hw": hw}
ENV = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
ENV.update(CLAUDE_PROJECT_DIR=proj, XDG_CONFIG_HOME=os.path.join(tmp, "xdg"), ADB_DENY_SERIALS="", ADB_ALLOW_SERIALS="", ANDROID_SERIAL="")


def run(hook, cmd):
    payload = json.dumps({"session_id": "s", "transcript_path": "", "cwd": proj, "hook_event_name": "PreToolUse",
                          "tool_name": "Bash", "tool_input": {"command": cmd, "description": "d"}})
    try:
        p = subprocess.run(["bash", HOOK[hook]], input=payload, capture_output=True, text=True, errors="replace", cwd=proj, env=ENV, timeout=90)
    except subprocess.TimeoutExpired:   # a hook that does not answer in 90 s is a failed row (its limit is 10 s)
        return "TIMEOUT", "the hook did not answer in 90 s"
    return p.returncode, p.stderr


# stderr of a hook that did not judge: a crash of the parser, python missing or failing, the module not loaded. Fail closed (rc 2) but no verdict.
CRASH = ("lỗi nội bộ", "python không chạy được", "không nạp được shell_norm.py")


GITD, RMD = "git reset --hard", "rm -rf ~"
DANGEROUS = []   # (hook, command, control)
# A CONTROL is the same shape (wrapper, heredoc, pipe, hook file …) with the danger replaced by a harmless command: it must pass. A dangerous
# row whose control is blocked too is VACUOUS: something else in the shape refused it (a push to a branch that does not exist, an unreadable
# <(…)), so its rc 2 proves nothing about the reading under test (second review 15/10). Such a row fails the run until it is fixed.
HARM = {"git": "git status", "hw": "ls"}
TWIN = [("[\"reset\", \"--hard\"]", "[\"status\"]"), ("[\"push\", \"--force\"]", "[\"status\"]"), ("[\"git\", \"reset\", \"--hard\"]", "[\"git\", \"status\"]"),
        ("system('git reset --hard')", "system('git status')"), ("qq#git reset --hard#", "qq#git status#"), ("qx#git reset --hard#", "qx#git status#"),
        ("execSync(\"git reset --hard\")", "execSync(\"git status\")"), ("git res\\\net --hard", "git sta\\\ntus"), ("gi\\\nt reset --hard", "gi\\\nt status"),
        ("git reset --ha\\\nrd", "git status"), ("git pu\\\nsh --force origin main", "git sta\\\ntus"), ("adb remo\\\nunt", "adb devi\\\nces"),
        ("fastboot fla\\\nsh boot x.img", "fastboot dev\\\nices"), ("rm -r\\\nf /system", "ls /sys\\\ntem"), ("rm -rf /sys\\\ntem", "ls /sys\\\ntem"),
        ("of=/de\\\nv/sda", "of=/tm\\\np/a.img"), ("ad\\\nb remount", "ad\\\nb devices"), ("env -iS 'rm -rf /'", "env -iS 'ls /'"),
        ("env -iS 'adb remount'", "env -iS 'adb devices'"), ("echo 'rm -rf /'", "echo 'ls /'"), ("echo 'adb remount'", "echo 'adb devices'"),
        ("; adb remount", "; adb devices"), ("; git reset --hard", "; git status"), ("\nadb remount", "\nadb devices"), ("rm -rf $HOME", "ls $HOME"), ("rm -rf ", "ls "), ("git reset --hard", "git status"), ("'git','reset','--hard'", "'git','status'"),
        ("'reset',\n  '--hard',", "'status',"), ("'reset', '--hard'", "'status'"), ("\"clean\", \"-fdx\"", "\"status\""),
        ("['reset', '--hard']", "['status']"), ("reset --hard", "status"), ("git push \\\n--force origin main", "git status \\\n--short"),
        (" remount", ""), ("of=/dev/sda", "of=/tmp/a.img"), ("fastboot \\\n -w", "fastboot \\\n devices"), ("alias.x='!rm -rf ~'", "alias.x='!ls'")]


def twin(cmd):
    """cmd with its danger replaced by a harmless twin (the control of a row that is not built from a template)."""
    out = cmd
    for old, new in TWIN:
        out = out.replace(old, new)
    assert out != cmd, "no control for: " + cmd
    return out

# ── 1. plain commands ───────────────────────────────────────────────────────────────────────────────────────────────────────────────
PLAIN_GIT = ["git push --force origin main", "git push -f origin main", "git push --force-with-lease origin main", "git push origin +main",
             "git push origin main --force", "git push --force-with-lease=main origin main", "git push origin :main",
             "git push --delete origin main", "git reset --hard", "git reset --hard HEAD~3", "git reset --hard origin/main",
             "git clean -fdx", "git clean -fd", "git clean -f", "git checkout -- .", "git checkout .", "git checkout HEAD -- src",
             "git checkout -f main", "git restore .", "git restore --source=HEAD~1 .", "git branch -D feat", "git branch -f main HEAD~1",
             "git branch -M main", "git filter-repo --force", "git filter-branch --force", "git rebase -i HEAD~3", "git rebase main",
             "git commit --no-verify -m x", "git push --no-verify origin main", "git commit -n -m x", "git -C . clean -fdx",
             "git -c core.hooksPath=/dev/null commit -m x", "git stash clear", "git stash drop", "git update-ref -d refs/heads/main",
             "git reflog expire --expire=now --all", "git gc --prune=now", "git worktree add ../x", "git checkout -b newbranch",
             "git switch -c newbranch", "git branch newbranch", "git push origin --tags --force", "git rm -rf .", "git rm -f src/a.kt",
             "git submodule foreach 'git reset --hard'", "git pull --rebase", "git fetch -f origin main:main", "git checkout src/a.kt",
             "git push origin HEAD:refs/heads/other", "DEVKIT_PRECOMMIT=0 git commit -m x"]
PLAIN_HW = ["rm -rf ~", "rm -rf /", "rm -rf /system", "rm -rf .", "rm -rf *", "rm -fr ~/", "rm -r -f ~", "rm --recursive --force ~",
            "rm -rf $HOME", "rm -rf /usr", "rm -rf /vendor/app", "find / -delete", "find ~ -exec rm -rf {} +", "find . -delete",
            "dd if=a.img of=/dev/sda", "dd if=/dev/zero of=/dev/disk2", "dd if=a of=$DISK", "adb shell rm -rf /system",
            "adb shell rm -rf /data", "adb remount", "adb shell mount -o rw,remount /", "adb shell rm -rf ~", "fastboot flash boot x.img",
            "fastboot -w", "fastboot erase userdata", "fastboot oem unlock", "adb shell pm uninstall com.android.*", "adb disable-verity",
            "adb shell su -c 'rm -rf /system'", "npm publish", "terraform destroy -auto-approve", "kubectl delete ns x",
            "rsync -a --delete empty/ /", "npx rimraf ~", "adb shell dd if=/dev/zero of=/dev/block/sda"]
DANGEROUS += [("git", c, HARM["git"]) for c in PLAIN_GIT] + [("hw", c, HARM["hw"]) for c in PLAIN_HW]

# ── 2. every wrapper / hand-over of a command line, applied to a few bases ──────────────────────────────────────────────────────────
BASES = {"git": ["git push --force origin main", "git reset --hard HEAD~1", "git clean -fdx", "git checkout -- .", "git branch -D main",
                 "git filter-repo --force", "git push -f origin main", "git restore .", "git stash drop", "git reflog expire --expire=now --all"],
         "hw": ["rm -rf /", "rm -rf /system", "dd if=a.img of=/dev/sda bs=1m", "rm -rf /vendor/app"]}
WRAP = [
    "{c}", "sudo {c}", "sudo -u root {c}", "sudo --user root {c}", "sudo -E {c}", "doas {c}", "env FOO=1 {c}", "env -i {c}",
    "env -u HOME {c}", "env -P /usr/bin {c}", "env -S '{c}'", "time {c}", "time -p {c}", "nohup {c}", "command {c}", "exec {c}",
    "setsid {c}", "caffeinate -t 5 {c}", "unbuffer {c}", "nice {c}", "nice -n 5 {c}", "ionice -c 3 {c}", "stdbuf -oL {c}",
    "timeout 5 {c}", "timeout -s KILL 5 {c}", "gtimeout 5 {c}", "arch -arm64 {c}", "chrt 1 {c}", "taskset 1 {c}", "flock /tmp/l {c}",
    "bash -c '{c}'", "bash -lc '{c}'", "sh -c '{c}'", "sh -ec '{c}'", "zsh -c '{c}'", "su -c '{c}'", "su root -c '{c}'",
    "su --command='{c}'", "su -s /bin/sh root {c}", "sudo -s '{c}'", "sudo -i '{c}'",
    "ssh host '{c}'", "ssh -tp 22 u@h '{c}'", "adb shell '{c}'", "adb -s ABC shell '{c}'", "adb wait-for-device shell '{c}'",
    "echo x | xargs {c}", "find . -exec {c} \\;", "find . -name x -exec {c} +", "eval '{c}'", 'eval "{c}"', "echo $({c})", "echo `{c}`",
    "true; {c}", "true && {c}", "false || {c}", "echo x | {c}", "echo x\n{c}", "( {c} )", "{ {c}; }", "! {c}",
    "if true; then {c}; fi", "for i in 1; do {c}; done", "while true; do {c}; break; done",
    "2>&1 {c}", ">&2 {c}", "2>/dev/null {c}", "VAR=1 {c}",
    "bash <<'EOF'\n{c}\nEOF", "bash <<EOF\n{c}\nEOF", "cat <<'EOF' | sh\n{c}\nEOF", "ssh host <<'EOF'\n{c}\nEOF",
    "cat > x.sh <<'EOF'\n{c}\nEOF\nbash x.sh", "cat > x.sh <<'EOF'\n{c}\nEOF\nmv x.sh y.sh && sh y.sh",
    "cat > x.sh <<'EOF'\n{c}\nEOF\nchmod +x x.sh && ./x.sh", "{ cat <<'EOF'; } | sh\n{c}\nEOF",
    "cat <<$'EOF'\nhi\nEOF\n{c}\n$EOF", "cat <<'EOF' # c\nhi\nEOF\n{c}", "echo hi # <<'EOF'\n{c}\nEOF", "cat <<< 'x'\n{c}\nx",
    "bash <(echo '{c}')", "source <(echo '{c}')", ". <(echo '{c}')", "echo '{c}' | bash", "echo '{c}' | sh -s", "bash <<< '{c}'",
    "CONT",
]
# process substitution of an echo is read as a script by neither guard (the old ones did not either): not part of the net
# git, vacuous by design: the git guard refuses ANY shell that is fed by a group or a <(…) it cannot read ("shell chạy văn bản do lệnh khác sinh
# ra"), whatever the text: the control with git status is blocked too. Those git rows say nothing about shell_norm, so they are not counted
# (the hardware gate has no such rule: its rows of the same shapes stay and are the ones that test the heredoc reading).
SKIP = {("hw", "bash <(echo '{c}')"), ("hw", "source <(echo '{c}')"), ("hw", ". <(echo '{c}')"),
        ("git", "source <(echo '{c}')"), ("git", ". <(echo '{c}')"),
        ("git", "bash <(echo '{c}')"), ("git", "{ cat <<'EOF'; } | sh\n{c}\nEOF")}
GIT_FEED_BLOCKS = {"{ cat <<'EOF'; } | sh\n@BODY@\nEOF", "if true; then cat <<'EOF'; fi | sh\n@BODY@\nEOF",
                   "while true; do cat <<'EOF'; break; done | sh\n@BODY@\nEOF", "for i in 1; do cat <<'EOF'; done | bash\n@BODY@\nEOF",
                   "{ cat <<'EOF'\n@BODY@\nEOF\n} | sh", "( cat <<'EOF'\n@BODY@\nEOF\n) | sh", "{ cat <<'EOF'; } | xargs -0 sh -c\n@BODY@\nEOF",
                   "echo \"$(cat <<EOF\n@BODY@\nEOF\n)\" | sh"}
for hook, bases in BASES.items():
    for b in bases:
        for w in WRAP:
            if (hook, w) in SKIP:
                continue
            shape = lambda base: base.replace(" ", " \\\n", 1) if w == "CONT" else w.replace("{c}", base)
            DANGEROUS.append((hook, shape(b), shape(HARM[hook])))
MATRIX = len(DANGEROUS) - len(PLAIN_GIT) - len(PLAIN_HW)

# ── 3. the strings of the review findings (each template through the git guard with a git danger and the hardware gate with an rm) ──
def both(tpl):
    for hook, danger in (("git", GITD), ("hw", RMD)):
        if hook == "git" and tpl in GIT_FEED_BLOCKS:   # vacuous by design, see SKIP above
            continue
        fill = lambda x: tpl.replace("@BODY@", x).replace("@CMD@", x)
        DANGEROUS.append((hook, fill(danger), fill(HARM[hook])))


FINDINGS = [
    # P1: ANSI-C / locale quoted delimiters
    "cat <<$'EOF'\nhi\nEOF\n@BODY@\n$EOF", "cat <<$\"EOF\"\nhi\nEOF\n@BODY@\n$EOF", "cat <<-$'EOF'\n\thi\n\tEOF\n@BODY@\n$EOF",
    "cat <<$'E\\x4fF'\nhi\nEOF\n@BODY@\n$EOF",
    # P2 (a) rename / copy / link
    "cat > x <<EOF\n@BODY@\nEOF\nmv x y.sh && bash y.sh", "cat > x <<'EOF'\n@BODY@\nEOF\nmv x y.sh && bash y.sh",
    "cat > x <<'EOF'\n@BODY@\nEOF\ncp x y.sh; sh y.sh", "cat > a.sh <<'EOF'\n@BODY@\nEOF\ncp a.sh b.sh; bash b.sh",
    "cat > a.sh <<'EOF'\n@BODY@\nEOF\nmv a.sh b.sh && sh b.sh", "cat > x <<'EOF'\n@BODY@\nEOF\nln -s x y.sh; sh y.sh",
    "cat > x <<'EOF'\n@BODY@\nEOF\ninstall -m755 x /tmp/y; /tmp/y",
    # P2 (b) variable / glob / loop / redirect spellings
    "cat > \"$F\" <<EOF\n@BODY@\nEOF\nsh \"${F}\"", "cat > ${F} <<'EOF'\n@BODY@\nEOF\nbash ${F}", "F=a.sh; cat > $F <<'EOF'\n@BODY@\nEOF\nbash a.sh",
    "cat > x.sh <<'EOF'\n@BODY@\nEOF\nF=x.sh; bash $F", "cat > x.sh <<'EOF'\n@BODY@\nEOF\nbash x.s?", "cat > x.sh <<'EOF'\n@BODY@\nEOF\nbash ./*.sh",
    "cat > x.sh <<'EOF'\n@BODY@\nEOF\nfor f in *.sh; do bash $f; done", "cat > x.sh <<'EOF'\n@BODY@\nEOF\nbash $(ls *.sh)",
    "cat 1>a.sh <<'EOF'\n@BODY@\nEOF\nbash a.sh", "cat &> a.sh <<'EOF'\n@BODY@\nEOF\nbash a.sh",
    # P2 (c) a git hook, then a git command that runs it
    "cat > .git/hooks/pre-commit <<EOF\n@BODY@\nEOF\ngit commit -m x", "cat > .git/hooks/pre-commit <<'EOF'\n@BODY@\nEOF\ngit commit -m x",
    "cat > .githooks/pre-push <<'EOF'\n@BODY@\nEOF\ngit push origin main", "cat > hooks/post-checkout <<'EOF'\n@BODY@\nEOF\ngit checkout main",
    "cd .git/hooks && cat > pre-commit <<'EOF'\n@BODY@\nEOF\ngit commit -m x", "H=.git/hooks; cat > $H/pre-commit <<'EOF'\n@BODY@\nEOF\ngit commit -m x",
    "cat > pre-commit <<'EOF'\n@BODY@\nEOF\ngit commit -m x",
    # a loop that ran the file on its previous round
    "while true; do bash x.sh; cat > x.sh <<'EOF'\n@BODY@\nEOF\ndone", "for i in 1 2; do sh x.sh; cat > x.sh <<'EOF'\n@BODY@\nEOF\ndone",
    # P2 (d) a compound command piped into a shell
    "{ cat <<'EOF'; } | sh\n@BODY@\nEOF", "if true; then cat <<'EOF'; fi | sh\n@BODY@\nEOF", "while true; do cat <<'EOF'; break; done | sh\n@BODY@\nEOF",
    "for i in 1; do cat <<'EOF'; done | bash\n@BODY@\nEOF", "{ cat <<'EOF'\n@BODY@\nEOF\n} | sh", "( cat <<'EOF'\n@BODY@\nEOF\n) | sh",
    "{ cat <<'EOF'; } | xargs -0 sh -c\n@BODY@\nEOF", "$(cat <<'EOF'\n@BODY@\nEOF\n)",
    # P3: the reader is a shell in disguise
    "sudo -s <<'EOF'\n@BODY@\nEOF", "sudo -i <<'EOF'\n@BODY@\nEOF", "sudo -u root -s <<'EOF'\n@BODY@\nEOF", "sudo --shell <<'EOF'\n@BODY@\nEOF",
    # OCR 4: an interpreter / unknown program given a heredoc on stdin keeps its body in the scan
    "python3 tool.py <<'EOF'\n@BODY@\nEOF", "python3 -m runner <<'EOF'\n@BODY@\nEOF", "node tool.js <<'EOF'\n@BODY@\nEOF",
    "ruby -e 'system(STDIN.read)' <<'EOF'\n@BODY@\nEOF", "perl -ne 'system $_' <<'EOF'\n@BODY@\nEOF", "ruby -ne 'system $_' <<'EOF'\n@BODY@\nEOF",
    "perl -e 'system(<STDIN>)' <<'EOF'\n@BODY@\nEOF",
    "node -e \"require('child_process').execSync(require('fs').readFileSync(0,'utf8'))\" <<'EOF'\n@BODY@\nEOF",
    "cat <<'EOF' | python3 -c 'import os,sys; os.system(sys.stdin.read())'\n@BODY@\nEOF",
    # OCR 7 / 8 and the review wrapper tables
    "time -p @CMD@", "sudo --user=root @CMD@", "sudo --user root @CMD@", "sudo --chdir /tmp @CMD@", "sudo --group wheel @CMD@",
    "sudo --host h @CMD@", "sudo -s '@CMD@'", "sudo -i '@CMD@'", "sudo -u root -s '@CMD@'", "doas -s '@CMD@'", "env -P /usr/bin @CMD@",
    "env -S '@CMD@'", "env -S\"@CMD@\"", "env -i -S 'FOO=1 @CMD@'", "2>&1 @CMD@", ">&2 @CMD@", "3<&0 @CMD@", "2>&1 sudo -u root @CMD@",
    # su --command / --session-command
    "su --command='@CMD@'", "su --command '@CMD@'", "su root --session-command '@CMD@'", "su --session-command='@CMD@'",
]
# F1: a << the shell does not read as a heredoc (parameter expansion, arithmetic, a comment after a subshell): the lines after it RUN
FINDINGS += [
    "echo ${x//<<EOF}\n@BODY@\nEOF}", "echo ${x:-<<EOF}\n@BODY@\nEOF}", "echo ${x/a/<<EOF}\n@BODY@\nEOF}", "echo ${x#<<EOF}\n@BODY@\nEOF}",
    "echo ${x//<<-EOF}\n@BODY@\nEOF}", "echo ${x//<<EOF} <<'B'\nb\nB\n@BODY@\nEOF}", "echo $[1<<EOF]\n@BODY@\nEOF]",
    "echo $[1 << EOF]\n@BODY@\nEOF]", "echo ${x:1<<2:3}\n@BODY@\n2:3}", "(true)#<<EOF\n@BODY@\nEOF", "(true)# <<'EOF'\n@BODY@\nEOF",
    "echo $((1 << EOF))\n@BODY@\nEOF", "a[1<<2]=1\n@BODY@\n2]=1",
    # F2: a $'..' / $".." delimiter that bash, zsh and python read differently: no heredoc, the lines after it are commands
    "cat <<$'\\eOF'\nx\n\x1bOF\n@BODY@\n\\eOF", "cat <<$'\\?OF'\nx\n?OF\n@BODY@\n\\?OF", "cat <<$'\\EOF'\nx\n\x1bOF\n@BODY@\n\\EOF",
    "cat <<$'\u00e9\\x41'\nx\n\u00e9A\n@BODY@\n\u00e9\\x41", "cat <<$'\\N{BULLET}'\nx\n@BODY@\n\\N{BULLET}", "cat <<-$'\\eOF'\nx\n\x1bOF\n@BODY@\n\\eOF",
    # F4: something set up BEFORE the write runs the file, or a program named by config / an option does (what follows is not tracked)
    "cat > x.sh <<'EOF'\n@BODY@\nEOF\ngit bisect run sh x.sh", "cat > x.sh <<'EOF'\n@BODY@\nEOF\ngit config core.fsmonitor 'sh x.sh'\ngit status",
    "cat > x.sh <<'EOF'\n@BODY@\nEOF\ngit grep -O'sh x.sh' foo", "cat > x.sh <<'EOF'\n@BODY@\nEOF\ngit clone --upload-pack='sh x.sh' . /tmp/zz",
    "cat > x.sh <<'EOF'\n@BODY@\nEOF\nrg --pre sh foo x.sh", "cat > x.sh <<'EOF'\n@BODY@\nEOF\nsort --compress-program=sh -S 1 -T . x.sh",
    "trap 'sh x.sh' EXIT\ncat > x.sh <<'EOF'\n@BODY@\nEOF", "(sleep 1; bash x.sh) &\ncat > x.sh <<EOF\n@BODY@\nEOF",
    "cat > ~/.config/git/config <<'EOF'\n@BODY@\nEOF\ngit status", "cat > ~/.zshenv <<'EOF'\n@BODY@\nEOF\nzsh -c true",
    "cat > .pre-commit-config.yaml <<'EOF'\n@BODY@\nEOF\ngit commit --allow-empty -m x",
    "cat > ~/.config/git/config <<'EOF'\n@BODY@\nEOF", "cat > ~/.zshenv <<'EOF'\n@BODY@\nEOF", "cat > .pre-commit-config.yaml <<'EOF'\n@BODY@\nEOF",
    "cat > run.sh <<'EOF'\n@BODY@\nEOF", "cat > Makefile <<'EOF'\n@BODY@\nEOF", "cat > package.json <<'EOF'\n@BODY@\nEOF",
    "cat > lefthook.yml <<'EOF'\n@BODY@\nEOF", "cat > .vscode/tasks.json <<'EOF'\n@BODY@\nEOF", "cat > docker-compose.yml <<'EOF'\n@BODY@\nEOF",
    # F3: the quoted $( ) is the value of an option that RUNS it (an alias, a pager, an editor, a monitor, a shell alias, python -c)
    "git -c core.pager=\"$(cat <<EOF\n@BODY@\nEOF\n)\" --paginate log", "git -c core.editor=\"$(cat <<EOF\n@BODY@\nEOF\n)\" config --edit",
    "git -c core.fsmonitor=\"$(cat <<EOF\n@BODY@\nEOF\n)\" status", "gh alias set --shell x \"$(cat <<EOF\n@BODY@\nEOF\n)\"",
    "git -c core.sshCommand=\"$(cat <<'EOF'\n@BODY@\nEOF\n)\" ls-remote ssh://h/r",
    "echo \"$(cat <<EOF\n@BODY@\nEOF\n)\" > .git/hooks/pre-commit", "echo \"$(cat <<EOF\n@BODY@\nEOF\n)\" | sh",
]
FINDINGS += [
    "cat > n.md <<EOF\n$(echo \")\" ; @BODY@)\nEOF", "cat > n.md <<EOF\n$(echo ')' ; @BODY@)\nEOF", "cat > n.md <<EOF\n$(echo x # )\n@BODY@\n)\nEOF",
    "cat > n.md <<EOF\n$(case x in x) @BODY@;; esac)\nEOF", "cat > n.md <<EOF\ntext `echo \\`; @BODY@` more\nEOF",
    "cat > n.md <<EOF\n$(( $(@BODY@) ))\nEOF", "cat > n.md <<EOF\n${x:-$(@BODY@)}\nEOF", "cat > n.md <<EOF\n$(echo \"(\" ; @BODY@)\nEOF",
    "cat > n.md <<EOF\n$(@BODY@)\nEOF", "cat > n.md <<EOF\n`@BODY@`\nEOF", "cat > n.md <<-EOF\n\t$(echo \")\" ; @BODY@)\n\tEOF",
    "cat <<EOF > n.md\n$(echo \")\" ; @BODY@)\nEOF", "tee n.md <<EOF\n$(echo \")\" ; @BODY@)\nEOF",
    "git commit -F - <<EOF\n$(echo \")\" ; @BODY@)\nEOF", "git commit -F - <<EOF\n`@BODY@`\nEOF", "python3 - <<EOF\n$(echo \")\" ; @BODY@)\nEOF",
    # ── N2: a file a tool executes or reads as configuration is no prose: not a data target whatever its extension
    "cat > Taskfile.yml <<'EOF'\n@BODY@\nEOF", "cat > pyproject.toml <<'EOF'\n@BODY@\nEOF", "cat > .cargo/config.toml <<'EOF'\n@BODY@\nEOF",
    "cat > pom.xml <<'EOF'\n@BODY@\nEOF", "cat > .lintstagedrc.json <<'EOF'\n@BODY@\nEOF", "cat > .claude/settings.json <<'EOF'\n@BODY@\nEOF",
    "cat > .mcp.json <<'EOF'\n@BODY@\nEOF", "cat > .github/workflows/ci.yml <<'EOF'\n@BODY@\nEOF", "cat > .gitlab-ci.yml <<'EOF'\n@BODY@\nEOF",
    "cat > ansible.yml <<'EOF'\n@BODY@\nEOF", "cat > n.sql <<'EOF'\n@BODY@\nEOF", "cat > fix.patch <<'EOF'\n@BODY@\nEOF",
    "cat > n.json <<'EOF'\n@BODY@\nEOF", "cat > n.yaml <<'EOF'\n@BODY@\nEOF", "cat > n.toml <<'EOF'\n@BODY@\nEOF", "cat > n.xml <<'EOF'\n@BODY@\nEOF",
    "cat > n.csv <<'EOF'\n@BODY@\nEOF", "cat > n.log <<'EOF'\n@BODY@\nEOF", "tee -a n.json <<'EOF'\n@BODY@\nEOF",
    # a prose file inside a hooks dir (or after cd into one) is no data target either: the rule is independent of the extension
    "cd .git/hooks && cat > n.md <<'EOF'\n@BODY@\nEOF", "cd .git && cat > hooks.md <<'EOF'\n@BODY@\nEOF", "mkdir -p .git/hooks && cat > .git/hooks/n.md <<'EOF'\n@BODY@\nEOF",
    "cat > hooks/README.md <<'EOF'\n@BODY@\nEOF", "cat > .githooks/x.md <<'EOF'\n@BODY@\nEOF", "cat > .husky/readme.md <<'EOF'\n@BODY@\nEOF",
    "cat > .claude/hooks/x.md <<'EOF'\n@BODY@\nEOF", "cat > hooks/hooks.json <<'EOF'\n@BODY@\nEOF", "cat > .husky/config.json <<'EOF'\n@BODY@\nEOF",
    "cat > .githooks/x.yml <<'EOF'\n@BODY@\nEOF", "cat > ~/.zshenv.md <<'EOF'\n@BODY@\nEOF",
]
# 15/10 r4, independent verification of 4f1e4b0: each template ran its marker twin (a harmless echo into a file) under /bin/bash 3.2.57 and zsh 5.9
# and the marker RAN, so a verdict of 0 was a hole (OLD blocked every one of these through one hook or both)
R16 = [
    # P0-A: a backslash-newline inside a heredoc body or terminator: E\<nl>OF is EOF in both shells (unquoted), and in bash 3.2 (zsh: backticks too)
    # for a quoted heredoc inside $( ) or backticks; the next lines RUN
    "cat > n.md <<EOF\nhello\nE\\\nOF\n@BODY@\nEOF\n", "git commit -F - <<EOF\nhello\nE\\\nOF\n@BODY@\nEOF\n", "tee n.md <<EOF\nhello\nE\\\nOF\n@BODY@\nEOF\n",
    "python3 - <<EOF\nx = 1\nE\\\nOF\n@BODY@\nEOF\n", "cat > n.md <<-EOF\n\thello\n\tE\\\nOF\n@BODY@\nEOF\n", "cat > n.md <<EOF \nhello\nE\\\nOF\n@BODY@\nEOF\n",
    "cat > n.md <<EOF\nhello\nEO\\\nF\n@BODY@\nEOF\n", "cat > n.md <<EOF\nhello\nE\\\nO\\\nF\n@BODY@\nEOF\n",
    "cat > n.md <<EOF\nhi\nx\\\\\nEOF\n@BODY@\nEOF\n", "git commit -F - <<EOF\nhi\nx\\\\\\\\\nEOF\n@BODY@\nEOF\n",   # an escaped backslash joins nothing: EOF ends the body
    "git commit -m \"$(cat <<EOF\nx\nE\\\nOF\n@BODY@\nEOF\n)\"", "git commit -m \"$(cat <<'EOF'\nx\nE\\\nOF\n@BODY@\nEOF\n)\"",
    "x=$(cat <<'EOF'\nx\nE\\\nOF\n@BODY@\nEOF\n)", "x=`cat <<'EOF'\nx\nE\\\nOF\n@BODY@\nEOF\n`", "echo \"$(python3 - <<'EOF'\nx\nE\\\nOF\n@BODY@\nEOF\n)\"",
    "echo \"$(echo $(cat <<'EOF'\nx\nE\\\nOF\n@BODY@\nEOF\n))\"",
    # P0-B: a comment that ends in a backslash does not continue; the next line runs
    "#c\\\n@BODY@", "echo hi #c\\\n@BODY@", "ls\n#c\\\n@BODY@", "true; #c\\\n@BODY@", "#c\\\n\\\n@BODY@", "#c\\\n@BODY@ && ls", "echo $(true)\n#c\\\n@BODY@",
    # P0-D: the sink after the operator is inside the $( ); the body is an argument of the program; sudo -s / -i with no command is a shell
    "python3 -c \"pass\" \"$(cat <<'EOF' | sh\n@BODY@\nEOF\n)\"", "python3 -c \"$(cat <<'EOF' | sh\n@BODY@\nEOF\n)\"",
    "node -e \"require('child_process').execSync(process.argv[1])\" \"$(cat <<'EOF'\n@BODY@\nEOF\n)\"", "x=$(cat <<'EOF' | bash\n@BODY@\nEOF\n)",
    "sudo -s <<'EOF' | python3 -\n@BODY@\nEOF", "sudo -i <<'EOF' | python3 -\n@BODY@\nEOF", "doas -s <<'EOF' | python3 -\n@BODY@\nEOF",
    "sudo -u root -s <<'EOF' | python3 -\n@BODY@\nEOF", "sudo --shell <<'EOF' | python3 -\n@BODY@\nEOF", "sudo -s <<'EOF' | cat\n@BODY@\nEOF",
    # P1: an escaped backslash then a real newline: the next line is a command
    "echo a\\\\\n@BODY@", "echo a\\\\\\\\\n@BODY@", "echo ok\\\\\n\\\n@BODY@",
    # P1b (OLD too): a # comment inside a multi-line quoted script ends at its own newline; flattening the newlines to ' ; ' let it swallow the rest
    "echo \"$(\n# c\n@BODY@\n)\"", "echo \"$(true # c\n@BODY@\n)\"", "sh -c \"\n# c\n@BODY@\n\"", "bash -c 'true # c\n@BODY@'", "bash -lc 'true # c\n@BODY@'",
    "eval \"true # c\n@BODY@\"", "bash -c \"bash -c 'true # c\n@BODY@'\"", "echo \"$(cat <<'EOF' | sh\nx\nEOF #\n@BODY@\nEOF\n)\"",
]
# P3: not prose for a note file (an agent reads CLAUDE.md as instructions; build and dependency lists; a path outside the project)
R16 += ["cat > %s <<'EOF'\n@BODY@\nEOF" % t for t in ("CLAUDE.md", "AGENTS.md", "GEMINI.md", "docs/agents.md", "CMakeLists.txt", "requirements.txt", "requirements-dev.txt",
                                                    ".claude/commands/x.md", ".agents/notes.md", ".gemini/x.md", "/etc/n.md", "~root/n.md", "~/n.md", "../n.md")]
FINDINGS += R16
for tpl in FINDINGS:
    both(tpl)
# the hardware gate also with adb remount (no rm: only its patterns see it)
for tpl in R16:
    DANGEROUS.append(("hw", tpl.replace("@BODY@", "adb remount"), tpl.replace("@BODY@", "ls")))
for p in ("adb remount", "adb disable-verity", "adb enable-verity", "adb shell pm uninstall com.android.systemui", "adb shell mount -o remount,rw /system",
          "fastboot erase userdata", "fastboot flash boot x.img", "fastboot oem unlock", "dd if=a.img of=/dev/sda", "npm publish", "terraform destroy -auto-approve",
          "kubectl delete ns x", "helm uninstall x", "firebase deploy", "docker volume rm x", "aws s3 rm s3://b --recursive", "redis-cli flushall",
          "prisma migrate reset", "security delete-keychain x", "xcrun simctl erase all", "fastlane match nuke", "psql -c 'DROP DATABASE x'", "vercel --prod",
          "rails db:drop", "rm -rf /system", "rm -rf ~", "rm -fr /", "adb shell rm -rf /data", "mount -o remount,rw /system", "terraform apply -destroy",
          "pulumi destroy", "kubectl delete pvc x"):
    for lead in ("#c\\\n", "echo hi #c\\\n", "ls\n#c\\\n", "true; #c\\\n"):
        DANGEROUS.append(("hw", lead + p, lead + "ls"))
# P0-C: a quote, a backtick or a $( left open by a prose body that stays in the scan: the rules the raw regex lacks must still run
NON_RAW_GIT = ["git push -f origin main", "git checkout . ", "git switch -c newb", "git checkout -f main", "git branch -f main HEAD~1", "git branch -M main",
               "git checkout -b newb", "git branch newb", "git worktree add ../x", "git push origin HEAD:refs/heads/other", "DEVKIT_PRECOMMIT=0 git commit -m x",
               "git push --force origin main", "git reset --hard", "git clean -fd", "git stash drop", "git commit --no-verify -m x", "git rm -f src/a.kt"]
PROSE = ["don't", "star's", "say \"hi", "the 5\" screen", "use `foo", "use $(foo", "foo\\", "it's \"x"]
for d in NON_RAW_GIT:
    for b in PROSE:
        DANGEROUS.append(("git", d + " && cat <<'EOF'\n" + b + "\nEOF", "git status && cat <<'EOF'\n" + b + "\nEOF"))
# a danger on a line whose own quote stays open: the text no longer parses, every line is read word by word (the shell rejects some of these; a guard fails closed)
DANGEROUS += [("git", "git push -f origin main 'x", "git status 'x"), ("git", "git commit --no-verify -m don't", "git commit -m don't"),
              ("git", "git push -f origin main \\", "git status \\"), ("git", "echo ok\ngit worktree add ../x \"y", "echo ok\ngit status \"y")]
DANGEROUS.append(("git", "cd /tmp && git switch -c chore/x && git add -A && git commit -q -F - <<'EOF'\nfix: the user's file\nEOF",
                  "cd /tmp && git status && git add -A && git commit -q -F - <<'EOF'\nfix: the user's file\nEOF"))
# P0-D (3): ruby / perl run a backtick as a command: the branch, worktree and hooks-off rules read it too
for interp in ("ruby", "perl"):
    for d in ("git checkout -b newbranch", "git worktree add ../x", "DEVKIT_PRECOMMIT=0 git commit -m x", "git switch -c newb", "git branch -f main HEAD~1"):
        DANGEROUS.append(("git", interp + " <<'EOF'\n`" + d + "`\nEOF", interp + " <<'EOF'\n`git status`\nEOF"))
# P2: an interpreter heredoc with no delimiter line is the program it is
DANGEROUS += [("git", "python3 - <<'EOF'\nimport os\nos.system('git reset --hard')", "python3 - <<'EOF'\nimport os\nos.system('git status')"),
              ("git", "python3 - <<'EOF'\ngit reset --hard", "python3 - <<'EOF'\ngit status")]
# the same shapes with the danger inside a JSON / YAML value (the hardware gate reads the text for adb remount whatever surrounds it)
for tpl in ('{"hooks": "@ADB@"}', "run: @ADB@", '{"command": "@ADB@"}'):
    for tgt in (".claude/settings.json", "~/.claude/settings.json", ".mcp.json", ".vscode/settings.json", ".github/workflows/ci.yml"):
        DANGEROUS.append(("hw", "cat > " + tgt + " <<'EOF'\n" + tpl.replace("@ADB@", "adb remount") + "\nEOF",
                          "cat > " + tgt + " <<'EOF'\n" + tpl.replace("@ADB@", "adb devices") + "\nEOF"))
for tpl in (
    "git -c alias.x=\"$(cat <<EOF\n!@BODY@\nEOF\n)\" x", "git config alias.x \"$(cat <<EOF\n!@BODY@\nEOF\n)\" && git x",
    "git bisect run python3 -c \"$(cat <<'EOF'\nimport os\nos.system('@BODY@')\nEOF\n)\"",
    "git bisect run node -e \"$(cat <<'EOF'\nrequire('child_process').execSync('@BODY@')\nEOF\n)\"",
    "git bisect run ruby -e \"$(cat <<'EOF'\nsystem('@BODY@')\nEOF\n)\"", "git bisect run perl -e \"$(cat <<'EOF'\nsystem('@BODY@');\nEOF\n)\"",):   # git rows: the hardware gate does not read the string literals of a program
    DANGEROUS.append(("git", tpl.replace("@BODY@", GITD), tpl.replace("@BODY@", HARM["git"])))
TAIL = [
    # OCR 1: hardware gate, interpreter bodies that can start a process stay in the rm walk
    ("hw", "perl <<'EOF'\nmy $x = `rm -rf ~`;\nEOF"), ("hw", "ruby <<'EOF'\n%x(rm -rf ~)\nEOF"), ("hw", "ruby <<'EOF'\n`rm -rf $HOME`\nEOF"),
    ("hw", "perl <<'EOF'\nqx(rm -rf ~);\nEOF"), ("hw", "php <<'EOF'\n<?php `rm -rf ~`; ?>\nEOF"),
    ("hw", "cat > x.rb <<'EOF'\n`rm -rf ~`\nEOF\nruby x.rb"),
    # OCR 6: git guard, interpreter heredocs
    ("git", "python3 - <<'EOF'\nimport subprocess\nsubprocess.run(['git','status'])\nsubprocess.run(['git','reset','--hard'])\nEOF"),
    ("git", "python3 - <<'EOF'\nimport subprocess\nsubprocess.run([\n  'git', 'reset',\n  '--hard',\n])\nEOF"),
    ("git", "ruby <<'EOF'\nsystem \"git reset --hard\"\nEOF"),
    ("git", "ruby <<'EOF'\nexec 'git', 'reset', '--hard'\nEOF"), ("git", "perl <<'EOF'\nsystem(\"git\", \"clean\", \"-fdx\");\nEOF"),
    ("git", "node - <<'EOF'\nconst {spawn} = require('child_process');\nspawn('git', ['reset', '--hard']);\nEOF"),
    ("git", "git -c alias.x='!sh' x <<'EOF'\ngit reset --hard\nEOF"),
    # OCR 3 (the device policy behind a wrapper option value) needs a serial deny list, which this payload driver does not set: its
    # check_deny lines are in tests/gates/test_guard_shell_norm.sh, section "the device policy sees a shell / su behind a wrapper"
    # OCR 9: a brace bomb is the worst target
    ("hw", "adb shell 'rm -rf /{,x}{,x}{,x}{,x}{,x}{,x}{,x}system'"), ("hw", "rm -rf /{,x}{,x}{,x}{,x}{,x}{,x}{,x}system"),
    # optional: wait-for-device, adb shell -e
    ("hw", "adb wait-for-device remount"), ("hw", "adb wait-for-device shell rm -rf ~"), ("hw", "adb shell -e ^ rm -rf ~"),
    # line continuations
    ("hw", "dd \\\nif=a.img of=/dev/sda bs=1m"), ("hw", "fastboot \\\n -w"), ("git", "git \\\nreset --hard"), ("git", "git push \\\n--force origin main"),
]
# F5 (git): the literals of a -c / heredoc program spell the danger in several lists: the old flat judgement sees it
TAIL += [("git", "python3 -c 'import subprocess; subprocess.run([\"git\"] + [\"reset\", \"--hard\"])'"),
         ("git", "python3 -c 'import subprocess; subprocess.run([\"git\", \"-C\", \".\"] + [\"push\", \"--force\"])'"),
         ("git", "python3 -c 'import subprocess\nsubprocess.run([\"git\", \"reset\", \"--hard\"])'"),
         ("git", "python3 - <<'EOF'\nimport subprocess\nsubprocess.run([\"git\"] + [\"reset\", \"--hard\"])\nEOF"),
         ("git", "python3 - <<'EOF'\nimport subprocess\ncmd = [\"git\"]\ncmd += [\"reset\", \"--hard\"]\nsubprocess.run(cmd)\nEOF"),
         # F6 (git): code that a comment stripper would delete: a # / // / s### / q## / qq## inside the program
         ("git", "perl <<'EOF'\nsystem(qq#git reset --hard#);\nEOF"), ("git", "perl <<'EOF'\n$x =~ s#a#b#; system('git reset --hard');\nEOF"),
         ("git", "perl <<'EOF'\nmy $s = q#a#; system('git reset --hard');\nEOF"), ("git", "ruby <<'EOF'\nx = %q#a#; system('git reset --hard')\nEOF"),
         ("git", "node <<'EOF'\nconst r = /\\/\\//; require('child_process').execSync(\"git reset --hard\")\nEOF"),
         ("git", "perl - <<'EOF'\nqx#git reset --hard#;\nEOF"),
         # F8: a backslash-newline inside a word, env -iS, a shell fed by a process substitution
         ("git", "echo $(true); git reset --ha\\\nrd"), ("git", "strace gi\\\nt reset --hard $(true)"), ("git", "echo \"$(gi\\\nt reset --hard)\""),
         ("git", "gi\\\nt reset --hard"), ("git", "git res\\\net --hard"), ("git", "git reset --ha\\\nrd"), ("git", "git pu\\\nsh --force origin main"),
         ("hw", "adb remo\\\nunt"), ("hw", "fastboot fla\\\nsh boot x.img"), ("hw", "rm -r\\\nf /system"), ("hw", "rm -rf /sys\\\ntem"),
         ("hw", "dd if=a.img of=/de\\\nv/sda"), ("hw", "ad\\\nb remount"),
         ("git", "env -iS 'git reset --hard'"), ("git", "env -vS 'git reset --hard'"), ("hw", "env -iS 'rm -rf /'"), ("hw", "env -iS 'adb remount'"),
         # F7: a long script of words that name the written file, then the danger (these made the old scan quadratic: 12 s and more)
         ("hw", "git -c alias.x='!rm -rf ~' x"),   # 15/10 r4 P2: the hardware gate reads a shell alias like the git guard
         ("hw", "cat > x <<EOF\nb\nEOF\n" + "x " * 4000 + "; adb remount"), ("git", "cat > x <<EOF\nb\nEOF\n" + "x " * 4000 + "; git reset --hard"),
         ("hw", "git status\n" + "\n" * 12000 + "cat > x <<EOF\nb\nEOF\nadb remount"), ("git", "git status\n" + "\n" * 12000 + "cat > x <<EOF\nb\nEOF\ngit reset --hard")]
DANGEROUS += [(hook, cmd, twin(cmd)) for hook, cmd in TAIL]

# 15/10 r5, independent verification of the r4 working tree (each dangerous template below ran its harmless marker twin under /bin/bash 3.2 and zsh; OLD blocked
# every one of the P0-1 and P1-a rows). Each template through the hook(s) that own it, with a control (the danger replaced by git status / ls).
def both_hooks(tpl, hooks=("git", "hw")):
    for hook in hooks:
        DANGEROUS.append((hook, tpl.replace("@CMD@", GITD if hook == "git" else RMD), tpl.replace("@CMD@", HARM[hook])))


BSL = "\\"
R5_WRAPS = ["bash -c %s", "sh -c %s", "bash -lc %s", "eval %s", "ssh host %s", "zsh -c %s", "env bash -c %s", "sudo bash -c %s", "nohup sh -c %s"]
# P0-1: the newline of the OUTER text was rewritten to " ;\n" inside a quoted script: a terminator line read "EOF ;", and a later line equal to the delimiter
# swallowed the real command of an interpreter heredoc
R5_SCRIPTS = ["python3 - <<EOF\nx = 1\nEOF\n@CMD@\nEOF", "python3 - <<EOF\nx = 1\nEOF\n@CMD@\ncat > n.md <<EOF\nhi\nEOF",
              "python3 - <<EOF\nprint(1)\nEOF\n@CMD@\npython3 - <<EOF\nprint(2)\nEOF", "node - <<EOF\nconsole.log(1)\nEOF\n@CMD@\nEOF",
              "python3 - <<'EOF'\nx = 1\nEOF\n@CMD@\nEOF", "python3 - <<-EOF\nx\nEOF\n@CMD@\nEOF\n\tEOF", "python3 - <<EOF\nx = 1\nEOF\n@CMD@\npython3 - <<EOT\nprint(2)\nEOT",
              "cat > n.md <<EOF\nhi\nEOF\n@CMD@\nEOF", "python3 - <<EOF\nx = 1\nEOF\n@CMD@"]
def hooks_of(w):
    """ssh runs the script on another machine: the hardware gate does not refuse rm -rf ~ there (the remote home), for every version: git guard only."""
    return ("git",) if w.startswith("ssh") else ("git", "hw")


for sc in R5_SCRIPTS:
    for w in R5_WRAPS:
        both_hooks(w % shlex.quote(sc), hooks_of(w))
    both_hooks("bash -c \"" + sc.replace("\\", "\\\\").replace("\"", "\\\"").replace("$", "\\$") + "\"")
    both_hooks("x=$(" + sc + "\n)")
    both_hooks("echo \"$(" + sc + "\n)\"")
# P1-c: a backslash-newline inside SINGLE quotes is literal for the outer shell: the script it hands over holds a comment that ENDS at the newline
for w in R5_WRAPS + ["zsh -fc %s"]:
    for sc in ("true # c" + BSL + "\n@CMD@", "# c" + BSL + "\n@CMD@", "ls\n# c" + BSL + "\n@CMD@", "echo hi # c" + BSL + "\n@CMD@",
               "true # c" + BSL + "\n" + BSL + "\n@CMD@", "true # c" + BSL + "\n@CMD@ && ls"):
        both_hooks(w % shlex.quote(sc), hooks_of(w))
both_hooks("bash -c " + shlex.quote("bash -c " + shlex.quote("true # c" + BSL + "\n@CMD@")))
both_hooks("echo \"$(true # c" + BSL + "\n@CMD@\n)\"")
# P1-a: an interpreter that cannot start a process still PRINTS, and the shell runs what is printed (git guard: the hardware gate does not read the string
# literals of a program, the same for every version)
R5_PRINT = "print('@CMD@')"
for tpl in ("$(python3 - <<'EOF'\n%s\nEOF\n)", "x=$(python3 - <<'EOF'\n%s\nEOF\n); $x", "$(python3 - <<'EOF'\n%s\nEOF\n) arg",
            "for c in $(python3 - <<'EOF'\n%s\nEOF\n); do $c; done", "`python3 - <<'EOF'\n%s\nEOF\n`", "x=`python3 - <<'EOF'\n%s\nEOF\n`; $x",
            "python3 -c \"$(cat <<'EOF'\n%s\nEOF\n)\" > s.sh; sh s.sh", "python3 -c \"$(cat <<'EOF'\n%s\nEOF\n)\" >> s.sh; sh s.sh",
            "python3 -c \"$(cat <<'EOF'\n%s\nEOF\n)\" | tee s.sh; sh s.sh", "python3 - <<'EOF' > s.sh\n%s\nEOF\nsh s.sh", "python3 - <<'EOF' >> s.sh\n%s\nEOF\nsh s.sh",
            "python3 - <<'EOF' | tee s.sh\n%s\nEOF\nsh s.sh", "python3 > s.sh <<'EOF'\n%s\nEOF\nsh s.sh", "cat <<'EOF' | python3 - > s.sh\n%s\nEOF\nsh s.sh",
            "{ python3 - <<'EOF'\n%s\nEOF\n} > s.sh; sh s.sh", "$(python3 <<'EOF'\n%s\nEOF\n)", "$(python3 -c \"$(cat <<'EOF'\n%s\nEOF\n)\")"):
    both_hooks(tpl % R5_PRINT, hooks=("git",))
for tpl in ("python3 - <<'EOF' > s.sh\n@CMD@\nEOF\nsh s.sh", "x=$(python3 - <<'EOF'\n@CMD@\nEOF\n)", "python3 - <<'EOF' | tee s.sh\n@CMD@\nEOF",
            "{ python3 - <<'EOF'\n@CMD@\nEOF\n} > s.sh; sh s.sh"):   # the same with the danger as a bare line of the body: an uncut body is judged by both guards
    both_hooks(tpl)
for tpl in ("$(node -e \"$(cat <<'EOF'\nconsole.log('@CMD@')\nEOF\n)\")", "$(ruby <<'EOF'\nputs '@CMD@'\nEOF\n)", "$(perl <<'EOF'\nprint '@CMD@';\nEOF\n)",
            "$(node - <<'EOF'\nconsole.log('@CMD@')\nEOF\n)"):
    both_hooks(tpl, hooks=("git",))
# P1-b: zx / Bun / dax start a process with a tagged template, Deno with Deno.Command / Deno.run: none of them had a word in the sink list
for tpl in ("node - <<'EOF'\nimport {$} from 'zx'\nawait $`@CMD@`\nEOF", "node - <<'EOF'\nconst {$} = require('zx');\n$`@CMD@`\nEOF",
            "node - <<'EOF'\nimport 'zx/globals'\nawait $`@CMD@`\nEOF", "node - <<'EOF'\nimport {$} from 'zx'\nawait $.sync`@CMD@`\nEOF",
            "node - <<'EOF'\nimport {$} from 'zx'\nawait $({quiet: true})`@CMD@`\nEOF", "node - <<'EOF'\nawait $`@CMD@`\nEOF",
            "bun - <<'EOF'\nimport {$} from 'bun'\nawait $`@CMD@`\nEOF", "bun - <<'EOF'\nawait Bun.$`@CMD@`\nEOF",
            "deno run -A - <<'EOF'\nimport $ from 'https://deno.land/x/dax/mod.ts'\nawait $`@CMD@`\nEOF"):
    both_hooks(tpl)
for tpl in ("deno run -A - <<'EOF'\nawait new Deno.Command('sh', {args: ['-c', '@CMD@']}).output()\nEOF",
            "deno run -A - <<'EOF'\nconst p = Deno.run({cmd: ['sh', '-c', '@CMD@']})\nEOF"):
    both_hooks(tpl, hooks=("git",))
# the hardware gate: newline is a separator of its own lexer (the fallback for text that does not parse, the && before a newline)
DANGEROUS += [("hw", "echo don't\nrm -rf ~", "echo don't\nls"), ("hw", "echo \"a\nrm -rf ~", "echo \"a\nls"), ("git", "echo don't\ngit reset --hard", "echo don't\ngit status"),
              ("hw", "cd src &&\nrm -rf ~", "cd src &&\nls"), ("git", "echo 'git reset --hard' |\nsh", "echo 'git status' |\nsh")]

# 15/10 r6, independent verification of 76899f4 (each template ran its harmless marker twin under /bin/bash 3.2 and zsh 5.9: the command between / after the
# bodies RAN while a guard answered 0). P0-1: a quote character in two heredoc bodies that stay in the scan paired across the command between them in every quote
# scanner (the lexer, the comment dropper, the single-quote and $( ) strippers of the git guard). P0-2: the join of a backslash-newline inside the single
# quotes of a -c script moved the terminator of its quoted heredoc.
R6_APOS = "it's"
R6_READERS = ["cat <<EOF", "cat <<'EOF'", "cat > n.md <<'EOF'", "git commit -F - <<'EOF'", "grep x <<'EOF'", ": <<'EOF'", "tee n.md <<EOF", "echo a <<EOF"]
for r in R6_READERS:
    for b in (R6_APOS, "don't", "say \"hi", "the 5\" screen"):
        both_hooks(r + "\n" + b + "\nEOF\n@CMD@\n" + r + "\n" + b + "\nEOF")
both_hooks("cat > n.md <<'EOF'\n" + R6_APOS + "\nEOF\n@CMD@\ncat > m.md <<'EOF'\n" + R6_APOS + "\nEOF")
both_hooks("echo $'\\''\n@CMD@\ncat <<EOF\n" + R6_APOS + "\nEOF")
both_hooks("echo $'it\\'s'\n@CMD@\ncat <<EOF\n" + R6_APOS + "\nEOF")
for pre, post in (("ls && ", " && ls"), ("( ", " )"), ("if true; then ", "; fi"), ("env ", ""), ("$(", ")"), ("echo $(", ")"), ("echo `", "`"), ("x=\"$(", ")\""), ("echo \"$(", ")\"")):
    both_hooks("cat <<EOF\n" + R6_APOS + "\nEOF\n" + pre + "@CMD@" + post + "\ncat <<EOF\n" + R6_APOS + "\nEOF")
for pre, post in (("x=$(", "\n)"), ("echo `", "\n`"), ("echo \"$(", "\n)\"")):
    both_hooks(pre + "cat <<'EOF'\n" + R6_APOS + "\nEOF\n@CMD@\ncat <<'EOF'\n" + R6_APOS + "\nEOF" + post)
for w in R5_WRAPS:
    for sc in ("cat <<EOF\n" + R6_APOS + "\nEOF\n@CMD@\ncat <<EOF\n" + R6_APOS + "\nEOF", "git commit -F - <<'EOF'\n" + R6_APOS + "\nEOF\n@CMD@\ngit commit -F - <<'EOF'\n" + R6_APOS + "\nEOF"):
        if not w.startswith("sudo"):   # sudo has no effect in a marker run (a stub): same text as the others
            both_hooks(w % shlex.quote(sc), hooks_of(w))
for extra in ("git checkout -b newb", "git worktree add ../w"):   # rules the raw regex of the git guard does not read
    for tpl in ("cat <<EOF\n" + R6_APOS + "\nEOF\n" + extra + "\ncat <<EOF\n" + R6_APOS + "\nEOF", "git commit -F - <<'EOF'\n" + R6_APOS + "\nEOF\n" + extra + "\ngit commit -F - <<'EOF'\n" + R6_APOS + "\nEOF"):
        DANGEROUS.append(("git", tpl, tpl.replace(extra, "git status")))
# the scanners that run before the lexer: a # inside a string after a body with a quote, a $( ) between two bodies, a quote in a body inside "$( )"
for q in ("'", "\""):
    both_hooks("cat <<EOF\n" + R6_APOS + "\nEOF\necho " + q + "a # b" + q + "; @CMD@")
    both_hooks("cat <<'EOF'\n" + R6_APOS + "\nEOF\necho " + q + "a # b" + q + "; @CMD@")
both_hooks("cat <<EOF\nsay \"hi\nEOF\necho \"a # b\"; @CMD@")
both_hooks("echo \"$(cat <<EOF\nsay \"hi\nEOF\n)\" \"a # b\"; @CMD@")
both_hooks("echo \"$(cat <<EOF\n" + R6_APOS + "\nEOF\n)\" 'a # b'; @CMD@")
both_hooks("cat <<EOF\nsay \"hi\nEOF\necho '$(' \"$(@CMD@)\"\ncat <<EOF\nsay \"hi\nEOF")
# the scanners of the git guard that read comments and quotes (marker fuzz, OLD too): an apostrophe in a comment paired with a later quote and hid a "$( )" between them, a #
# after a backslash-newline or inside ${ } was read as a comment and dropped the substitution after it
for sub in ("\"$(@CMD@)\"", "$(@CMD@)", "`@CMD@`", "x=\"$(@CMD@)\"", "echo \"a\" \"$(@CMD@)\""):
    for tpl in ("${: #}" + sub, "echo ${x:-a # b} " + sub, "a" + BSL + "\n#" + sub, "echo a " + BSL + "\n#x\n" + sub.replace("\"", ""), "echo a" + BSL + "\n# b; " + sub,
                "# it's a comment\n" + sub + "\n# it's a comment", "echo hi # it's\n" + sub + "\necho hi # it's", "#'\n" + sub + "\n'", "echo a # \"\n" + sub + "\n# \""):
        both_hooks(tpl)
for tpl in ("bash -c %s" % shlex.quote("#'\n\"$(@CMD@)\"\n'"), "eval %s" % shlex.quote("${: #}\"$(@CMD@)\"")):
    both_hooks(tpl)
# the lexer of the hardware gate pairs the quotes of a "$( )" that holds quotes of its own, and what the shell runs inside it ended up inside a word (review P1-3)
for tpl in ("echo \"$(echo \"a b\"; @CMD@)\"", "echo \"$(echo \"a\" ; @CMD@)\"", "echo \"$(echo \"a\" && @CMD@)\"", "echo \"$(echo \"a\"\n@CMD@\n)\"", "echo \"x$(echo \"a b\"; @CMD@)y\"",
            "x=\"$(echo \"a b\"; @CMD@)\"", "echo \"`echo \\\"a b\\\"; @CMD@`\"", "echo \"$(echo \"$(echo \"a b\"; @CMD@)\")\"", "git commit -m \"$(echo \"a b\"; @CMD@)\"",
            "echo \"$(echo \"a b\" | cat; @CMD@) $(echo \"b\")\"", "echo \"$(printf \"%s\" \"a b\"; @CMD@)\"", "echo \"$(\" \";if true; then @CMD@; fi)\"", "echo \"$(\" \"\nif true; then @CMD@; fi)\"",
            "echo \"$(echo \"a b\"; echo \"c d\"; @CMD@)\"", "for i in \"$(echo \"a b\"; @CMD@)\"; do :; done", "cat <<EOF\n$(echo \"a b\"; @CMD@)\nEOF",
            "echo \"a\"; echo \"$(echo \"a b\"; @CMD@)\" >/dev/null"):
    both_hooks(tpl)
# P0-2
R6_INNERS = ["cat > n.md <<\"EOF\"\nx" + BSL + "\nEOF\n@CMD@\nEOF", "cat > n.md <<\"EOF\"\nhello\nx" + BSL + "\nEOF\n@CMD@", "cat > n.md <<\"EOF\"\nhello\nx" + BSL * 3 + "\nEOF\n@CMD@\nEOF",
             "cat > n.md <<\"EOF\"\nx" + BSL + "\nEOF\nEOF \n@CMD@ ;\nEOF", "git commit -F - <<\"EOF\"\nx" + BSL + "\nEOF\n@CMD@\nEOF", "tee n.md <<\"EOF\"\nx" + BSL + "\nEOF\n@CMD@\nEOF",
             "python3 - <<\"EOF\"\nx = 1" + BSL + "\nEOF\n@CMD@\nEOF", "node - <<\"EOF\"\nx" + BSL + "\nEOF\n@CMD@\nEOF", "cat <<\"EOF\"\nx" + BSL + "\nEOF\n@CMD@\nEOF",
             "cat > n.md <<\"EOF\"\n" + BSL + "\nEOF\n@CMD@\nEOF", "cat > n.md <<\"EOF\"\nhi" + BSL + "\n" + BSL + "\nEOF\n@CMD@\nEOF", "cat > n.md <<\"EOF\" # c\nx" + BSL + "\nEOF\n@CMD@\nEOF",
             "cat > n.md <<" + BSL + "EOF\nx" + BSL + "\nEOF\n@CMD@\nEOF", "cat > n.md <<E" + BSL + "OF\nx" + BSL + "\nEOF\n@CMD@\nEOF", "true; cat > n.md <<\"EOF\"\nx" + BSL + "\nEOF\n@CMD@\nEOF"]
R6_SQ_WRAPS = ["bash -c %s", "sh -c %s", "zsh -c %s", "eval %s", "env bash -c %s", "bash -lc %s", "nohup sh -c %s", "time bash -c %s", "x=$(bash -c %s)", "echo $(bash -c %s)"]
for sc in R6_INNERS:
    both_hooks(sc)   # typed at top level, no outer quotes: a quoted heredoc body is not joined by the shell either
    for w in R6_SQ_WRAPS:
        both_hooks(w % shlex.quote(sc))
    both_hooks("cat <<EOF\n" + R6_APOS + "\nEOF\nbash -c " + shlex.quote(sc))   # the quote of the script must not pair with the one of a body before it
# what the model of the outer quotes must get right before the script: a quote inside "…", an ANSI-C string, a "$( )" around the script or before it
for tpl in ("echo \"it's\"\nbash -c %s", "echo $'\\''\nbash -c %s", "echo \"$(bash -c %s)\"", "echo \"a $(echo \"b\" ; bash -c %s)\"", "echo \"$(echo x)\" ; bash -c %s",
            "echo \"x\" 'y' ; eval %s"):
    both_hooks(tpl % shlex.quote(R6_INNERS[0]))
# the operator of python3 -c "$(cat <<'EOF' …)" is no end of line when cat prints into a shell or a file that is run: the body is a command, never a program
for tail in (" | sh", " > s.sh", " | tee s.sh"):
    both_hooks("python3 -c \"$(cat <<'EOF'" + tail + "\n@CMD@\nEOF\n)\"; sh s.sh")

HARMLESS = [
    "git log --grep=rm -3", "git log --grep=\"rm -rf\" --oneline", "echo \"git push --force\"", "echo 'git reset --hard'",
    "grep -r 'rm -rf' src", "grep -rn \"git reset --hard\" README.md", "git commit -m \"docs: mention git reset --hard and rm -rf in README\"",
    "git commit -m \"$(cat <<'EOF'\nmessage that mentions git reset --hard and rm -rf ~\nEOF\n)\"",
    "git add -A && git commit -m \"$(cat <<'EOF'\nmessage git reset --hard\nEOF\n)\" && git status",
    "gh pr create --title t --body \"$(cat <<'EOF'\nsummary: never run git reset --hard or rm -rf ~\nEOF\n)\"",
    "git commit -F - <<'EOF'\nmessage git reset --hard rm -rf ~\nEOF",
    "gh pr create --title \"support for the hooks/ dir while testing\" --body \"$(cat <<'EOF'\nsummary: git reset --hard rm -rf ~\nEOF\n)\"",
    "cat <<'EOF' > notes.md\ngit reset --hard\nrm -rf ~\nEOF",
    "cat > notes.md <<'EOF'\ngit reset --hard\nrm -rf ~\nEOF",
    "cat > notes.md <<EOF\ngit reset --hard is never used here\nEOF",
    "python3 - <<'EOF'\ncases = ['git reset --hard', 'rm -rf ~']\nprint(len(cases))\nEOF",
    "git status", "git diff --stat", "git log --oneline | head -5", "git branch --show-current", "git show HEAD:README.md", "git checkout feat",
    "git clean -n", "git clean -fd --dry-run", "git rm -f --cached src/a.kt", "git fetch origin", "git pull --ff-only",
    "time -p git status", "sudo --user=root git status", "2>&1 git status", "env -P /usr/bin git status", "nohup git status",
    "rm -rf build", "rm -rf bu\\\nild", "rm -rf \"$PWD/build\"", "rm -rf node_modules", "time -p rm -rf build", "sudo --user root rm -rf build", "2>&1 rm -rf build",
    "su --command='rm -rf /tmp/build'", "su -c 'rm -rf /tmp/build'", "bash -lc 'rm -rf build'", "sudo -s 'rm -rf build'",
    "adb devices", "adb wait-for-device", "adb -s ABC shell ls /sdcard", "adb shell rm -rf /sdcard/Download/old",
    "adb wait-for-device shell ls /sdcard", "npm publish --dry-run", "dd if=/dev/zero of=/tmp/x.img bs=1m count=1", "rsync -a --delete src/ build/",
    "find . -name '*.pyc' -exec rm {} +", "ls -la | grep -v total", "npm test 2>&1 | tail -5", "./gradlew build 2>&1 | grep -v warning",
    "echo \"rm -rf ~ is dangerous\"", "cat README.md | grep -n 'git push --force'",
    "ruby <<'EOF'\nputs 'rm -rf ~ is dangerous'\nEOF",
    "echo \"<<'EOF'\"\ngit status\nEOF", "echo a # <<'EOF'\ngit status",
    # 15/10 r4: the shapes of the independent verification where the shell does NOT run the line (marker twin did not run under bash 3.2 and zsh)
    "cat > n.md <<'EOF'\nhello\nE\\\nOF\ngit reset --hard\nrm -rf ~\nadb remount\nEOF\n",     # a quoted heredoc at top level joins nothing
    "cat > n.md <<EOF\nhello\nx\\\nEOF\ngit reset --hard\nrm -rf ~\nadb remount\nEOF\n",     # x\<nl>EOF is xEOF: the body goes on to the last EOF
    "cat > n.md <<EOF\nhello\nE\\\\\nOF\ngit reset --hard\nrm -rf ~\nadb remount\nEOF\n",    # an escaped backslash joins nothing
    "cat > n.md <<EOF\nhi\nx\\\\\\\nEOF\ngit reset --hard\nrm -rf ~\nadb remount\nEOF\n",    # three backslashes: the last one joins, EOF is swallowed
    "git commit -m \"$(cat <<'EOF'\nx\nE\\\nOF\ngit status\nEOF\n)\"", "x=`cat <<'EOF'\nx\nE\\\nOF\nls\nEOF\n`", "echo a\\\\\ngit status", "echo a\\\\\nls",
    "echo a\\\\\\\ngit reset --hard", "echo a\\\\\\\nrm -rf ~", "#c\\\nls", "# c \\\ngit status", "echo hi #c\\\nls",
    "echo \"a # b\ngit reset --hard\nrm -rf ~\"", "sh -c \"\n# c\nls\n\"", "bash -c 'true # c\ngit status'",
    "git status && cat <<'EOF'\nstar's\nEOF", "git status && cat <<'EOF'\ndon't\nEOF", "git status && cat <<'EOF'\nsay \"hi\nEOF",
    "git status && cat <<'EOF'\nthe 5\" screen\nEOF", "git status && cat <<'EOF'\nuse `foo\nEOF", "git status && cat <<'EOF'\nuse $(foo\nEOF",
    "ls && cat <<'EOF'\nstar's\nEOF", "ls && cat <<'EOF'\nuse `foo\nEOF", "ls && cat <<'EOF'\nuse $(foo\nEOF",
    "cd /tmp && git status && git add -A && git commit -q -F - <<'EOF'\nfix: the user's file\nEOF",
    "python3 -c \"$(cat <<'EOF'\ncases = ['git reset --hard']\nprint(len(cases))\nEOF\n)\"", "python3 -c \"pass\" \"$(cat <<'EOF' | wc -l\nhello\nEOF\n)\"",
    "cat > docs/guide.md <<'EOF'\ngit reset --hard\nrm -rf ~\nadb remount\nEOF", "ruby <<'EOF'\nputs `git status`\nEOF", "perl <<'EOF'\nprint `git status`;\nEOF",
    "python3 - <<'EOF'\nprint(1)",
    # 15/10 r5: a program whose output nothing captures (a bare run, stderr only) and a node template literal are still data
    "python3 - <<'EOF'\nprint('git reset --hard is dangerous')\nEOF", "python3 - <<'EOF' 2>/dev/null\nprint(1)\nEOF", "python3 - <<'EOF'\nprint('rm -rf ~ is dangerous')\nEOF",
    "node - <<'EOF'\nconsole.log(`git reset --hard is dangerous`)\nEOF", "node - <<'EOF'\nconsole.log(`rm -rf ~ is dangerous`)\nEOF",
    "bash -c 'true # c\ngit status'", "bash -c 'true # c\\\ngit status'", "bash -c 'true # c\\\nls'", "ssh host 'true # c\\\nls'",
    # 15/10 r6: a body line that closes its own quotes is read as typed (a ; inside them is no separator); only the lines that do not close them lose their quote characters
    "cat <<'EOF'\nsay \"ok; git reset --hard\"\nEOF", "cat <<'EOF'\nsay \"ok; rm -rf ~\"\nEOF", "cat <<EOF\nsay \"ok; git reset --hard\"\nEOF",
    "git status\ncat <<'EOF'\nsay 'a; rm -rf ~' and \"b; git reset --hard\"\nEOF", "cat <<'EOF'\nthe 5\" screen\nEOF\necho \"a # b\"; git status",
    "cat <<EOF\nit's\nEOF\nls\ncat <<EOF\nit's\nEOF",
    # 15/10 r6: quotes inside "$( )", comments with a quote or a $( ), a # inside ${ } or after a backslash-newline: nothing dangerous in them
    "echo \"$(echo \"a b\"; ls)\"", "echo \"$(date +\"%F\")\"", "git commit -m \"$(git log -1 --format=\"%s\")\"", "echo ${x:-a # b} \"$(git status)\"",
    "echo a # it's $(git status)\necho \"$(git status)\" # it's", "echo a \\\n# b $(git status)",
]
# ACCEPTED FALSE POSITIVES (policy of 15/10: fail closed, build less). Harmless commands the guards refuse because a heredoc body is cut only for
# a known message option or the one file statement of a modeled command, and a program body is judged on its raw text. They are pinned BLOCKED
# here so that nobody loosens them quietly: a change that lets one through must edit this list and say why.
UNMODELED_BEFORE = ["echo ${x}", "echo $[1+2]", "(true)", "true &", "trap true EXIT", "echo `true`", "echo $'a'", "eval true", "source x",
                    "if true; then true; fi", "echo a\\\nb", "diff <(true) <(true)"]
ACCEPTED_FP = [
    # an unquoted body is never cut when it holds a $ or a backtick (the shell runs its $( ) at once, and we do not pair the parentheses)
    ("git", "cat > notes.md <<EOF\n# Notes for $(date +%F)\nNever run git reset --hard\nEOF"), ("hw", "cat > notes.md <<EOF\n# Notes for $(date +%F)\nrm -rf ~\nEOF"),
    ("git", "git commit -F - <<EOF\nmessage $USER\ngit reset --hard\nEOF"), ("hw", "git commit -F - <<EOF\nmessage $USER\nrm -rf ~\nEOF"),
    ("git", "cat > notes.md <<EOF\nuse `date`\ngit reset --hard\nEOF"),
    # a message argument is data, cut only in a command that is fully modeled: any unmodeled construct elsewhere keeps the body in the scan
    *[(h, x + "\ngit commit -m \"$(cat <<'EOF'\n" + d + "\nEOF\n)\"") for x in UNMODELED_BEFORE for h, d in (("git", GITD), ("hw", RMD))],
    # the quoted $( ) is the value of an option that is no message: only -m / --message and --body / --title / --notes are cut
    ("git", "git merge -s \"$(cat <<'EOF'\ngit reset --hard\nEOF\n)\" x"), ("hw", "git merge -s \"$(cat <<'EOF'\nrm -rf ~\nEOF\n)\" x"),
    ("git", "git commit --author \"$(cat <<'EOF'\ngit reset --hard\nEOF\n)\" -m x"), ("hw", "git commit --author \"$(cat <<'EOF'\nrm -rf ~\nEOF\n)\" -m x"),
    ("git", "gh pr create --head \"$(cat <<'EOF'\ngit reset --hard\nEOF\n)\""), ("hw", "gh pr create --head \"$(cat <<'EOF'\nrm -rf ~\nEOF\n)\""),
    ("git", "gh release create v1 --target \"$(cat <<'EOF'\ngit reset --hard\nEOF\n)\""), ("hw", "gh release create v1 --target \"$(cat <<'EOF'\nrm -rf ~\nEOF\n)\""),
    ("git", "git -c user.name=x commit -m \"$(cat <<'EOF'\ngit reset --hard\nEOF\n)\""), ("hw", "git -c user.name=x commit -m \"$(cat <<'EOF'\nrm -rf ~\nEOF\n)\""),
    # refused by design whatever the text (a shell that runs a process substitution): like the git guard, the hardware gate cannot read it
    ("hw", "bash <(echo 'rm -rf /')"), ("hw", "bash < <(echo 'rm -rf /')"), ("hw", "sh -x <(echo 'adb remount')"), ("hw", "bash <(echo 'ls /')"),
    # a statement after the written file, a second heredoc, a heredoc to stdout, a reader that is not cat, a message of no known option
    ("git", "cat > notes.md <<'EOF'\ngit reset --hard\nEOF\nwc -l notes.md"), ("hw", "cat > notes.md <<'EOF'\nrm -rf ~\nEOF\nwc -l notes.md"),
    ("git", "cat > notes.md <<'EOF'\ngit reset --hard\nEOF\ncat notes.md; ls -la notes.md"),
    ("hw", "cat > notes.md <<'EOF'\nrm -rf ~\nEOF\ncat notes.md; ls -la notes.md"),
    ("git", "cat > notes.md <<'EOF'\ngit reset --hard\nEOF\ngit add notes.md && git commit -m x"),
    ("hw", "cat > notes.md <<'EOF'\nrm -rf ~\nEOF\ngit add notes.md && git commit -m x"),
    ("git", "echo \"for a while\" && cat > notes.md <<'EOF'\ngit reset --hard\nEOF"), ("hw", "echo \"for a while\" && cat > notes.md <<'EOF'\nrm -rf ~\nEOF"),
    ("git", "cat > a.md <<'EOF'\nprose\nEOF\ncat > b.md <<'EOF'\ngit reset --hard\nEOF\nls"),
    ("hw", "cat > a.md <<'EOF'\nprose\nEOF\ncat > b.md <<'EOF'\nrm -rf ~\nEOF\nls"),
    ("git", "cat <<'EOF'\ngit reset --hard\nEOF"), ("hw", "cat <<'EOF'\nrm -rf ~\nEOF"),
    ("git", "sudo -u root cat <<'EOF'\ngit reset --hard\nEOF"), ("hw", "sudo -u root cat <<'EOF'\nrm -rf ~\nEOF"),
    ("git", "echo \"$(cat <<'EOF'\ngit reset --hard\nEOF\n)\""), ("hw", "echo \"$(cat <<'EOF'\nrm -rf ~\nEOF\n)\""),
    ("hw", "cat > notes.md <<$'EOF'\nrm -rf ~\nEOF"), ("git", "cat > notes.md <<$'EOF'\ngit reset --hard\nEOF"),
    ("hw", "cat > probe.py <<'EOF'\nrm -rf ~\nEOF\npython3 probe.py"), ("hw", "cat > notes.txt <<'EOF'\nrm -rf ~\nEOF\nwc -l notes.txt"),
    ("hw", "cat > notes.mk <<'EOF'\nall:\n\trm -rf ~\nEOF\nmake"),
    # a program: a comment or a string that mentions the danger, two calls whose literals add up, another reader that is not a shell
    ("git", "python3 - <<'EOF'\nimport subprocess\n# never run: git reset --hard\nsubprocess.run(['git','status'])\nEOF"),
    ("git", "python3 - <<'EOF'\nimport subprocess\nsubprocess.run(['git','checkout','main'])\nsubprocess.run(['rm','-f','t'])\nEOF"),
    ("git", "node - <<'EOF'\nconst {spawn} = require('child_process');\n// git reset --hard is dangerous\nspawn('git', ['status']);\nEOF"),
    ("git", "python3 - <<'EOF'\nimport subprocess, json\ncases = ['git reset --hard', 'git push -f']\nprint(len(cases))\nsubprocess.run(['ls'])\nEOF"),
    ("git", "docker build -t x - <<'EOF'\nFROM alpine\nRUN apk add git && git reset --hard\nEOF"),
    ("git", "ed f.txt <<'EOF'\na\ngit reset --hard\n.\nw\nq\nEOF"),
    ("git", "while read -r l; do echo \"$l\"; done <<'EOF'\ngit status\ngit reset --hard\nEOF"),
    # a prose body with an open quote stays in the scan and the text no longer parses: the raw regex reads it first, so danger text in the prose is
    # refused (15/10 r4: it was the ONLY check then; now every rule runs line by line after it)
    ("git", "git status && cat <<'EOF'\ndon't run git reset --hard\nEOF"),
    # 15/10 r6: the operator of python3 -c "$(cat <<'EOF' …)" followed by ; or && (no pipe, no redirect): the output of cat is still the program, yet the guards
    # judge the body as lines of a command source instead of cutting it as a program (_code_operand: tail). Pinned so that a change that cuts it says why
    *[(h, "python3 -c \"$(cat <<'EOF'" + t + "\n" + d + "\nEOF\n)\"") for t in (" ; echo x", " && echo x", " || echo x") for h, d in (("git", GITD), ("hw", RMD))],
    # 15/10 r5: the text is read joined AND as typed (a backslash-newline inside single quotes is literal for the outer shell, so a comment that ends in a
    # backslash ends at the newline there). Inside DOUBLE quotes the outer shell removes it and the comment swallows the next word: harmless, but the
    # as-typed reading cannot tell, and is blocked
    ("git", "bash -c \"true # c\\\ngit reset --hard\""), ("hw", "bash -c \"true # c\\\nrm -rf ~\""), ("git", "eval \"true # c\\\ngit reset --hard\""),
    # the hardware gate reads the text as shlex words too (readings: norm): the real newline becomes a blank, so mount … rw … /system is matched across two
    # commands. Blocked by 5fd5fd9 as well (not a hole, not this lane): pinned so that it is not loosened quietly
    ("hw", "echo mount \\\\\nrw /system"),
]
assert len(DANGEROUS) - MATRIX >= 80, len(DANGEROUS)
assert len(HARMLESS) >= 25, len(HARMLESS)

CONTROLS = sorted({(h, ctl) for h, _c, ctl in DANGEROUS})
jobs = ([("D", h, c) for h, c, _ctl in DANGEROUS] + [("H", h, c) for c in HARMLESS for h in ("git", "hw")]
        + [("C", h, ctl) for h, ctl in CONTROLS] + [("A", h, c) for h, c in ACCEPTED_FP])
with cf.ThreadPoolExecutor(8) as ex:
    results = list(ex.map(lambda j: run(j[1], j[2]), jobs))
fails = 0
blocked_controls = set()
for (kind, hook, cmd), (rc, err) in zip(jobs, results):
    crashed = any(m in err for m in CRASH)
    ok = (rc == 2 and not crashed) if kind in ("D", "A") else (rc == 0)
    if kind == "C" and not ok:
        blocked_controls.add((hook, cmd))
    if not ok:
        fails += 1
        want = "2" if kind in ("D", "A") else "0"
        what = {"C": "CONTROL ", "A": "ACCEPTED FALSE POSITIVE no longer blocked (loosened?) "}.get(kind, "")
        print(f"✖ {what}{hook} rc {rc} (want {want}{', a crash is no verdict' if crashed else ''}): {cmd.replace(chr(10), ' ⏎ ')[:130]} — {err[:100].strip()!r}")
vacuous = [(h, c) for h, c, ctl in DANGEROUS if (h, ctl) in blocked_controls]
for h, c in vacuous:
    fails += 1
    print(f"✖ VACUOUS (its control is blocked too): {h} {c.replace(chr(10), ' ⏎ ')[:120]}")
print(f"{len(DANGEROUS)} dangerous ({len(PLAIN_GIT) + len(PLAIN_HW)} plain, {MATRIX} wrapped, {len(DANGEROUS) - MATRIX - len(PLAIN_GIT) - len(PLAIN_HW)} "
      f"findings) each with a control ({len(CONTROLS)} distinct, {len(blocked_controls)} blocked, {len(vacuous)} vacuous rows), "
      f"{len(HARMLESS)} harmless x 2 hooks, {len(ACCEPTED_FP)} accepted false positives pinned blocked, {fails} failed")
sys.exit(1 if fails else 0)
PY
rc=$?
[ "$rc" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS (rc $rc)"; exit 1; }
