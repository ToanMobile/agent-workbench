"""build_inputs.py — the files a build needs that git does not hold, in ONE place.

Two consumers copy them from the main checkout into a fresh tree:
  • scripts/red_proof.py  — into its throwaway RED/GREEN sandbox (furnish());
  • scripts/worktree.py   — into a new agent worktree (`agent-kit worktree add`), git-ignored
    files only, so nothing copied can ever be committed from there.

The list is DEFAULT_INPUTS plus the project's own globs in .agents/local/red_proof.json
{"copy": [...]} (e.g. "CarConnect/keys/**"). Globs are fnmatch patterns on the path relative to
the project root; `*` also crosses `/`. Standard library only.
"""

from __future__ import annotations

import fnmatch
import json
import os
from pathlib import Path

# Build inputs git does not hold (ignored on purpose) that a build cannot do without.
DEFAULT_INPUTS = ("local.properties", "**/local.properties", "google-services.json", "**/google-services.json",
                  "**/GoogleService-Info.plist", "key.properties", "**/key.properties", "**/keystore.properties",
                  "**/*.jks", "**/*.keystore", "**/libs/*.aar", "**/libs/*.jar", ".env", ".env.*", "**/.env")
SKIP_WALK = {".git", "build", ".gradle", "node_modules", "Library", "Temp", "Logs", "obj", ".venv", "venv",
             "__pycache__", ".idea", ".agents", ".claude", "dist", "out", ".cxx", ".kotlin"}


def patterns(project) -> list:
    """DEFAULT_INPUTS + the "copy" globs of <project>/.agents/local/red_proof.json."""
    pats = list(DEFAULT_INPUTS)
    try:
        pats += list(json.loads((Path(project) / ".agents" / "local" / "red_proof.json")
                                .read_text(encoding="utf-8")).get("copy", []))
    except (OSError, ValueError, AttributeError, TypeError):
        pass
    return [p for p in pats if isinstance(p, str) and p]


def build_inputs(project) -> list:
    """Relative paths of every file under <project> matching patterns() (tracked or not)."""
    project = Path(project)
    pats = patterns(project)
    out = []
    for root, dirs, files in os.walk(project):
        dirs[:] = [d for d in dirs if d not in SKIP_WALK]
        for f in files:
            rel = os.path.relpath(os.path.join(root, f), project)
            if any(fnmatch.fnmatch(rel, p) for p in pats):
                out.append(rel)
    return out
