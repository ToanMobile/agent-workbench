"""Universal Agent DevKit scripts package.

Exposes the 6 domain groups to Python imports automatically:
- audits
- context
- git
- governance
- linters
- testing
"""
import sys
from pathlib import Path

_here = Path(__file__).resolve().parent
for _sub in ("audits", "context", "git", "governance", "linters", "testing"):
    _sub_path = str(_here / _sub)
    if _sub_path not in sys.path:
        sys.path.insert(0, _sub_path)
