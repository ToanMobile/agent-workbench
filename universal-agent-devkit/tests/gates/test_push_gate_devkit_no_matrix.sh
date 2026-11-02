#!/usr/bin/env bash
# #742 tách A1 (#482 / BUG-REV-push-gate-own-check-devkit): main checkout đã cài DevKit (.agents/devkit, symlink cũng tính)
# mà mất ma trận hồi quy thì push_gate.check() cũng từ chối (fail closed), như strict_check đã làm; repo chưa cài DevKit
# và không có ma trận vẫn được qua ("no regression matrix").
# ĐỎ trên push_gate.py của main d49f26cf (check() trả True "no regression matrix"); XANH sau khi áp hunk #742.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
mkrepo() {   # mkrepo <dir> [devkit]
  mkdir -p "$1" && (cd "$1" && git init -q && git config user.email t@t && git config user.name t && mkdir -p .agents \
    && { [ "${2:-}" != devkit ] || ln -s /nonexistent-devkit .agents/devkit; } && echo x > f && git add f && git commit -qm i)
}
judge() {   # judge <repo>
  python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import push_gate as pg; ok, why = pg.check(sys.argv[2]); print(ok, why)' \
    "$DEVKIT_DIR/bin" "$1" 2>&1
}
mkrepo "$TMP/dk" devkit
r="$(judge "$TMP/dk")"
case "$r" in False*DevKit*missing*) echo "✔ check(): DevKit installed without the matrix → refused (fail closed)" ;;
  *) echo "✖ check() without matrix but with .agents/devkit: $r"; FAILS=$((FAILS + 1)) ;; esac
mkrepo "$TMP/plain"
r="$(judge "$TMP/plain")"
case "$r" in "True no regression matrix") echo "✔ control: no DevKit, no matrix → still allowed" ;;
  *) echo "✖ check() in a repo without DevKit and matrix: $r"; FAILS=$((FAILS + 1)) ;; esac

[ "$FAILS" -eq 0 ] && echo "push gate devkit/no-matrix: all checks passed" || { echo "push gate devkit/no-matrix: $FAILS FAILED"; exit 1; }
