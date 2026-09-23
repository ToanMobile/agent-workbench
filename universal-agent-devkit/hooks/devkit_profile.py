"""devkit_profile — source extensions of the project's active profile, for hooks.

Hooks import this (the hook's own directory is on sys.path) to decide which files are
"code" for review / claim checks, instead of hard-coding Kotlin/Java.

Order: $DEVKIT_SOURCE_EXTS (comma list) > `source_extensions` in
<project>/.agents/active-profile/profile.json > DEFAULT_EXTS (every language the
DevKit profiles cover). Not a hook: no shebang, not wired.
"""
import json
import os

DEFAULT_EXTS = (".kt", ".kts", ".java", ".swift", ".m", ".mm", ".ts", ".tsx", ".js", ".jsx",
                ".mjs", ".cjs", ".vue", ".svelte", ".py", ".go", ".rs", ".rb", ".php", ".cs",
                ".dart", ".c", ".cc", ".cpp", ".h", ".hpp", ".scala")

# Languages whose comments start with // or /* (comment_claim_guard reads only those).
SLASH_COMMENT_EXTS = {".kt", ".kts", ".java", ".swift", ".m", ".mm", ".ts", ".tsx", ".js", ".jsx",
                      ".mjs", ".cjs", ".go", ".rs", ".php", ".cs", ".dart", ".c", ".cc", ".cpp",
                      ".h", ".hpp", ".scala"}


def source_exts(project_root):
    env = os.environ.get("DEVKIT_SOURCE_EXTS", "").strip()
    if env:
        return tuple("." + e.strip().lstrip(".") for e in env.split(",") if e.strip())
    try:
        with open(os.path.join(project_root, ".agents", "active-profile", "profile.json"), encoding="utf-8") as f:
            exts = json.load(f).get("source_extensions")
        if isinstance(exts, list) and exts and all(isinstance(e, str) and e.startswith(".") for e in exts):
            return tuple(exts)
    except (OSError, ValueError, AttributeError):
        pass
    return DEFAULT_EXTS
