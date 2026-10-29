#!/usr/bin/env python3
"""Bộ đọc `[orchestrator] [decision]` dùng chung (#516): MỘT nơi quyết định comment nào là quyết định hợp lệ của chủ.

Luật (references/decision-policy.md): comment hợp lệ CHỈ KHI dòng đầu là `[orchestrator] [decision]` VÀ người đăng đáng tin
(authorAssociation OWNER hoặc login = decision_policy.owner) VÀ một trong hai:
  (a) mang marker riêng của lane orchestrator `<!-- sb-decision:orchestrator -->`;
  (b) là comment tay của chủ: KHÔNG mang marker `<!-- … -->` nào (sb-write, super-review:report, super-board:needs-you …).
Header `[builder]`/`[qa]`/`[reviewer]`, hay marker lane khác mà không có marker (a), thì bỏ qua: lane không tự quyết cho thẻ mình.
`decision_policy.enabled: false` trong config tắt hẳn bộ đọc (mọi comment không hợp lệ).

    super-board-decision.py annotate [--config <cfg.json>]   stdin: mảng issue (comments.nodes hoặc comments); stdout: thêm decisionValid, decisionStop
    super-board-decision.py latest   [--config <cfg.json>]   stdin: mảng comment; stdout: chỉ số comment hợp lệ mới nhất hoặc -1

Module khác nạp bằng importlib (tên file có gạch ngang). Không mạng, không tác dụng phụ.
"""
from __future__ import annotations

import argparse
import json
import re
import sys

ORCH_MARKER = "<!-- sb-decision:orchestrator -->"
HEADER = re.compile(r"^\s*\[orchestrator\]\s*\[decision\]", re.I)
COMMENT_MARKER = re.compile(r"<!--.*?-->", re.S)
TRUSTED_ASSOC = {"OWNER"}
# DANH SÁCH DỪNG của chủ (28/10): bước cần người thật, secret, quyền push, nới gate, mất dữ liệu: vẫn gắn needs-you.
STOP_RE = re.compile(
    r"lái\s+xe|ngồi\s+xe|trên\s+xe\s+thật|elm327|phần\s+cứng|thiết\s+bị\s+thật|\bobd\b|hardware|"
    r"secret|api[ _-]?key|keystore|token|mật\s+khẩu|password|đăng\s+nhập|\blogin\b|credential|org\s+admin|write\s+access|bảo\s+mật|"
    r"thanh\s+toán|billing|tài\s+khoản|quyền\s+push|nới\s+(?:hook|gate)|--no-verify|"
    r"(?:xoá|xóa|đổi|sửa)\s+AC(?:\s*-?\s*#?\d+)?\b|đổi\s+phạm\s+vi|chưa\s+commit\s+của\s+người\s+khác|mất\s+dữ\s+liệu|xoá\s+(?:file|nhánh|dữ\s+liệu)|xóa\s+(?:file|nhánh|dữ\s+liệu)",
    re.I,
)


def load_policy(config_path=None):
    policy = {"enabled": True, "owner": "", "marker": ORCH_MARKER}
    if not config_path:
        return policy
    try:
        with open(config_path, encoding="utf-8") as fh:
            cfg = json.load(fh).get("decision_policy") or {}
    except (OSError, ValueError, AttributeError) as exc:
        # Config không đọc được: giữ mặc định (bật) nhưng nói ra, không nuốt im.
        print(f"decision: không đọc được config {config_path} ({exc}); dùng mặc định", file=sys.stderr)
        return policy
    for key in policy:
        if key in cfg:
            policy[key] = cfg[key]
    return policy


def is_valid(comment, policy):
    if not policy.get("enabled", True) or not isinstance(comment, dict):
        return False
    body = comment.get("body")
    if not isinstance(body, str):
        return False
    first = next((l for l in COMMENT_MARKER.sub("", body).splitlines() if l.strip()), "")
    if not HEADER.match(first):
        return False
    # GraphQL (`author`, `authorAssociation`) và REST (`user`, `author_association`, đường needs-you mark) đều được nhận.
    login = (comment.get("author") or comment.get("user") or {}).get("login")
    owner = policy.get("owner") or ""
    if not ((comment.get("authorAssociation") or comment.get("author_association")) in TRUSTED_ASSOC or (owner and login == owner)):
        return False
    markers = COMMENT_MARKER.findall(body)
    return (policy.get("marker") or ORCH_MARKER) in markers or not markers


def newest_valid_index(comments, policy):
    idx = -1
    for i, c in enumerate(comments or []):
        if is_valid(c, policy):
            idx = i
    return idx


def is_stop(text):
    return bool(STOP_RE.search(text or ""))


_FIELD = re.compile(r"^\s*([A-Za-zÀ-ỹ][^:\n]{0,40}):")
_STOP_FIELDS = ("reason tag", "why blocked", "what blocks", "to unblock", "why i (bot) cannot decide")


def stop_text(body):
    """Chữ để dò DANH SÁCH DỪNG trong một comment: Block comment chỉ xét các trường lý do, không xét Evidence/Checked (log, lệnh)."""
    keep, scan = [], True
    for line in (body or "").splitlines():
        m = _FIELD.match(line)
        if m and m.group(1).strip().lower() in _STOP_FIELDS + ("card", "pr", "evidence", "checked", "owner", "move back", "blocked-by"):
            scan = m.group(1).strip().lower() in _STOP_FIELDS
        if scan:
            keep.append(line)
    return "\n".join(keep)


def _comment_list(issue):
    c = issue.get("comments")
    return c.get("nodes") if isinstance(c, dict) else c


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=("annotate", "latest"))
    ap.add_argument("--config")
    args = ap.parse_args()
    policy = load_policy(args.config)
    data = json.load(sys.stdin)
    if args.cmd == "latest":
        print(newest_valid_index(data, policy))
        return 0
    for issue in data:
        for c in _comment_list(issue) or []:
            if isinstance(c, dict):
                c["decisionValid"] = is_valid(c, policy)
                c["decisionStop"] = is_stop(stop_text(c.get("body")))  # deps.sh: comment 🙋/blocked-by thuộc DANH SÁCH DỪNG thì decision không gỡ
    json.dump(data, sys.stdout, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
