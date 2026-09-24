#!/usr/bin/env python3
"""Load .agents/context/hardware-boundaries.json and match a prompt or a path.

The catalog is the project's measured dead-ends. A match is a warning the agent
must apply the recorded rescue instead of patching around the hardware limit.
"""

from __future__ import annotations

import json
import os
import re
from pathlib import Path


def catalog_path(project: str | os.PathLike) -> Path:
    return Path(project) / ".agents" / "context" / "hardware-boundaries.json"


def load(project: str | os.PathLike) -> list:
    path = catalog_path(project)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    rows = data.get("boundaries") if isinstance(data, dict) else None
    return [r for r in rows or [] if isinstance(r, dict) and r.get("id")]


def _norm(text: str) -> str:
    return re.sub(r"\s+", " ", (text or "").lower())


def match_text(rows: list, text: str) -> list:
    hay = _norm(text)
    if len(hay) < 3:
        return []
    hit = []
    for row in rows:
        symptoms = [s for s in row.get("symptoms") or [] if isinstance(s, str) and len(s) >= 3]
        if any(_norm(s) in hay for s in symptoms):
            hit.append(row)
    return hit


def match_paths(rows: list, rels: list) -> list:
    hit = []
    for row in rows:
        globs = row.get("watch") or []
        for rel in rels:
            clean = rel.replace("\\", "/")
            for g in globs:
                pat = "^" + re.escape(g).replace(r"\*\*", ".*").replace(r"\*", ".*") + "$"
                if re.search(pat, clean):
                    hit.append(row)
                    break
            else:
                continue
            break
    return hit


def warning(row: dict) -> str:
    return (f"DỪNG: {row.get('id')} — {row.get('title')}. "
            f"{row.get('measured', '')} Cứu hộ: {row.get('rescue', '')}").strip()
