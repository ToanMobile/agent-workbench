#!/usr/bin/env bash
# Owner rule 21/11/2026: a host repo (GeelyEx2, OfficeReader, …) hit by a DevKit defect files a `[devkit]` task at the kit
# source and never patches its synced kit copy (the next sync overwrites it, the other hosts keep the bug).
# The full rule lives in core-rules §20; essentials (loaded in every host session) must point to it.
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
ESS="$DK/rules/essentials.md"
CORE="$DK/rules/core-rules.md"
fail() { echo "✖ $1" >&2; exit 1; }

sec="$(awk '/^## 20\./{on=1} on&&/^## 21\./{exit} on' "$CORE")"
[ -n "$sec" ] || fail "core-rules.md has no §20 (host-repo DevKit defect rule)"
for must in '[devkit]' 'Cấm sửa mã của kit' 'Gom lỗi cùng nguyên nhân' 'Oracle' '--resume --reconciled' \
            '--no-verify' 'Không hỏi xin phép tạo task' '.agents/local/**' 'tự chạy' 'giả thuyết'; do
  printf '%s' "$sec" | grep -qF -- "$must" || fail "core-rules §20 lacks: $must"
done
grep -qE 'DevKit defect.*core-rules §20' "$ESS" || fail "rules/essentials.md has no pointer to core-rules §20"
echo "✅ test_host_devkit_defect_rule: core-rules §20 + essentials pointer present"
