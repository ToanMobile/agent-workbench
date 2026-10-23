#!/bin/bash
# Probe: real `worktree finish` on a main that diverged from origin (issue #308 unverified item).
S=/private/tmp/claude-501/-Volumes-Data-Toan-agent-workbench/68fe48a4-edb9-49c0-9966-968bbc202989/scratchpad/probe308
WT=/Volumes/Data/Toan/agent-workbench/.claude/worktrees/issue-308-qa/.agents/devkit/scripts/git/worktree.py
rm -rf "$S"; mkdir -p "$S"
G="git -c user.email=a@b.c -c user.name=t"
git init -q --bare -b main "$S/origin.git"
git clone -q "$S/origin.git" "$S/main" 2>/dev/null
echo a > "$S/main/a.txt"; echo r > "$S/main/runner.sh"
$G -C "$S/main" add . && $G -C "$S/main" commit -qm base && $G -C "$S/main" push -q origin HEAD:main
git clone -q "$S/origin.git" "$S/other"
echo r2 > "$S/other/runner.sh"; $G -C "$S/other" commit -qam originchange && $G -C "$S/other" push -q origin HEAD:main
echo local > "$S/main/local.txt"; $G -C "$S/main" add local.txt && $G -C "$S/main" commit -qm localcommit
git -C "$S/main" fetch -q origin
git -C "$S/main" status -sb | head -1
cd "$S/main" || exit 1
python3 "$WT" add .claude/worktrees/self-reload-1 --base=origin/main 2>&1 | tail -3; echo "add=${PIPESTATUS[0]}"
python3 "$WT" finish .claude/worktrees/self-reload-1 2>&1 | tail -8; echo "finish=${PIPESTATUS[0]}"
git log --oneline --graph -5; echo "runner.sh=$(cat runner.sh)"; ls .claude/worktrees 2>&1 | head
