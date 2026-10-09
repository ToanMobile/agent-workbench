#!/usr/bin/env bash
# rules/essentials.md is copied into the tracked AGENTS.md of every host project. A host's own doc verifier
# reads a backticked `Name.member` there as a code symbol that must exist in the host's sources: GeelyEx2's
# verify-docs.sh rejected a commit over `Color.Gray` (04/10/2026). Write such names without backticks.
# File names (`AGENTS.md`, `*.kt`) and ALL-CAPS words are not symbols, so they stay allowed.
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
ESS="$DK/rules/essentials.md"
fail() { echo "✖ $1" >&2; exit 1; }

[ -f "$ESS" ] || fail "missing $ESS"
bad="$(grep -noE '`[A-Z][A-Za-z0-9]*[a-z][A-Za-z0-9]*\.[A-Za-z][A-Za-z0-9]*`' "$ESS" \
  | grep -viE '\.(md|py|sh|json|txt|kt|java|xml|png|csv|ya?ml|mdc|toml|gradle|swift|cs|dart|tsx?|jsx?|vue|css)`$')"
[ -z "$bad" ] || fail "rules/essentials.md has a backticked code-looking name a host doc verifier reads as a symbol: $(echo "$bad" | tr '\n' ' ')"
# 09/10/2026: GeelyEx2's verify-docs.sh resolves a backticked `scripts/…` / `tools/…` / `docs/…` pointer from the HOST root;
# essentials named `scripts/governance/scratch_cleanup.py`, which exists only under `.agents/devkit/` there (REG-DOCS-01 red).
# A kit file is named with its host path `.agents/devkit/<path>`.
ptr="$(grep -noE '`(\./)?(scripts|tools|docs)/[A-Za-z0-9_./-]+`' "$ESS")"
[ -z "$ptr" ] || fail "rules/essentials.md has a backticked kit path a host verifier resolves from its own root (write .agents/devkit/<path>): $(echo "$ptr" | tr '\n' ' ')"
echo "✅ test_essentials_host_safe: no host-unsafe backticked symbol or pointer in rules/essentials.md"
