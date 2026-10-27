#!/usr/bin/env python3
"""Bất biến production của merge theo đợt (Pha 2, lớp 3): PR merged phải đi qua train, không đi đường merge gate lẻ. Lần trước
train chạy 0 lần mà test vẫn xanh; canary này đo trên dữ liệu thật để điều đó không lặp lại.

  batch_canary.py --runs <runs.jsonl> (--since <ISO> | --config <board cfg>) [--merged-json <file>]

Đọc <git common dir>/postfix-gate/runs.jsonl: lượt verify của merge gate có project `.merge-scratch*`, của train
`.train-scratch*`. PR merged lấy từ --merged-json, không có thì `gh pr list --state merged --limit 200 --json number,mergedAt`
(timeout 15 s). Exit 1 (ĐỎ) khi có >= 2 PR merged mà 0 lượt train, hoặc số lượt merge gate lẻ >= 2 và > số lượt train (đường lẻ áp đảo;
một lượt --standalone lẻ ngoài board không tính).
Không có luật tỉ lệ: một đợt nhỏ lúc máy rảnh (1 PR / 1 train) là bình thường. Exit 0 (XANH, hoặc "canary off" khi config board
không bật merge_queue / enabled_at null). Exit 2: lỗi đầu vào, kèm lý do.
Mốc: --since; không có thì merge_queue.enabled_at của --config; có cả hai thì lấy mốc muộn hơn (lượt trước lúc bật không tính).
Chỉ đọc, không ghi gì. Dòng JSON hỏng bị bỏ qua. Thư viện chuẩn, Python >= 3.9.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import subprocess
import sys
from pathlib import Path

GH_TIMEOUT_S = 15
MERGE_PREFIX = ".merge-scratch"
TRAIN_PREFIX = ".train-scratch"


class CanaryError(Exception):
    """Lỗi đầu vào: CLI in lý do và exit 2."""


def parse_time(value) -> float:
    """Epoch (số) hoặc chuỗi ISO 8601 ('Z' hoặc múi giờ; không múi giờ = UTC) → epoch giây."""
    if isinstance(value, bool):
        raise ValueError(f"not a time: {value!r}")
    if isinstance(value, (int, float)):
        return float(value)
    text = str(value).strip()
    try:
        return float(text)
    except ValueError:
        pass
    stamp = dt.datetime.fromisoformat(text.replace("Z", "+00:00"))
    if stamp.tzinfo is None:
        stamp = stamp.replace(tzinfo=dt.timezone.utc)
    return stamp.timestamp()


def queue_since(cfg_path) -> float | None:
    """Mốc bật merge queue trong config board, hoặc None khi tắt (thiếu khoá, enabled false, enabled_at null)."""
    try:
        cfg = json.loads(Path(cfg_path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise CanaryError(f"config {cfg_path}: {e}") from e
    mq = cfg.get("merge_queue") if isinstance(cfg, dict) else None
    if not isinstance(mq, dict) or mq.get("enabled") is not True or mq.get("enabled_at") in (None, ""):
        return None
    if (cfg.get("worker_backend") or "workflow") != "claude-p":   # cùng định nghĩa "bật" với gate/runner/queue/train (audit 26/10 #5)
        return None
    try:
        return parse_time(mq["enabled_at"])
    except (TypeError, ValueError) as e:
        raise CanaryError(f"config {cfg_path}: merge_queue.enabled_at {mq['enabled_at']!r}: {e}") from e


def enabled_configs(repo) -> list:
    """[(config, enabled_at)] của các config board trong repo có merge_queue bật. Config hỏng bị bỏ qua (người gọi là health /
    nightly: một config hỏng không được làm hỏng bước khác)."""
    out = []
    for cfg in sorted((Path(repo) / ".claude" / "super-board" / "configs").glob("*.json")):
        try:
            since = queue_since(cfg)
        except CanaryError as e:
            print(f"batch_canary: skip {cfg.name}: {e}", file=sys.stderr)
            continue
        if since is not None:
            out.append((cfg, since))
    return out


def runs_path(repo) -> Path | None:
    """<git common dir>/postfix-gate/runs.jsonl của repo (worktree dùng chung git dir của repo chính), None khi không đọc được."""
    try:
        res = subprocess.run(["git", "-C", str(repo), "rev-parse", "--git-common-dir"], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError) as e:
        print(f"batch_canary: git rev-parse in {repo}: {e}", file=sys.stderr)
        return None
    if res.returncode != 0 or not res.stdout.strip():
        return None
    common = Path(res.stdout.strip())
    if not common.is_absolute():
        common = Path(repo) / common
    return common / "postfix-gate" / "runs.jsonl"


def count_verifies(runs, since: float) -> tuple:
    """(lượt merge gate, lượt train) có epoch >= since. Dòng hỏng, không phải object, epoch không phải số: bỏ qua. Lượt gate không chạy
    suite nào (verdict BUSY, hoặc exit 4: hàng đợi gate / khe / khoá bận) không phải lượt verify: bỏ qua. Lượt train có exit khác 0 cũng không
    tính (train đỏ không merge gì, #471; verdict như REUSED với exit 0 vẫn là train xanh); dòng thiếu exit vẫn tính."""
    merge_v = train_v = 0
    try:
        with open(runs, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(r, dict):
                    continue
                epoch = r.get("epoch")
                if isinstance(epoch, bool) or not isinstance(epoch, (int, float)) or epoch < since:
                    continue
                project = r.get("project")
                if not isinstance(project, str) or r.get("verdict") == "BUSY" or r.get("exit") == 4:
                    continue
                if project.startswith(MERGE_PREFIX):
                    merge_v += 1
                elif project.startswith(TRAIN_PREFIX):
                    if r.get("exit") not in (None, 0):
                        continue   # train đỏ không merge gì: không chứng minh hàng đợi chạy đúng (#471)
                    train_v += 1
    except OSError as e:
        raise CanaryError(f"runs {runs}: {e}") from e
    return merge_v, train_v


def merged_since(items, since: float) -> int:
    """Số PR merged có mergedAt >= since trong danh sách dạng `gh pr list --json number,mergedAt`."""
    if not isinstance(items, list):
        raise CanaryError("merged PR list is not a JSON list")
    n = 0
    for x in items:
        if not isinstance(x, dict) or not x.get("mergedAt"):
            raise CanaryError(f"merged PR item without mergedAt: {x!r}"[:200])
        try:
            if parse_time(x["mergedAt"]) >= since:
                n += 1
        except ValueError as e:
            raise CanaryError(f"merged PR mergedAt {x['mergedAt']!r}: {e}") from e
    return n


def load_merged_json(path) -> list:
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise CanaryError(f"merged-json {path}: {e}") from e


def gh_merged(cwd=None) -> list:
    """PR merged gần nhất của repo ở cwd, qua gh (timeout 15 s)."""
    cmd = ["gh", "pr", "list", "--state", "merged", "--limit", "200", "--json", "number,mergedAt"]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=GH_TIMEOUT_S, cwd=cwd)
    except FileNotFoundError as e:
        raise CanaryError(f"gh not found: {e}") from e
    except subprocess.TimeoutExpired as e:
        raise CanaryError(f"gh pr list timed out after {GH_TIMEOUT_S} s") from e
    except OSError as e:
        raise CanaryError(f"gh pr list: {e}") from e
    if res.returncode != 0:
        raise CanaryError(f"gh pr list exit {res.returncode}: {res.stderr.strip()[:300]}")
    try:
        return json.loads(res.stdout or "[]")
    except ValueError as e:
        raise CanaryError(f"gh pr list output is not JSON: {e}") from e


def evaluate(merge_v: int, train_v: int, merged_n: int | None) -> tuple:
    """(đỏ?, dòng tóm tắt, lý do). merged_n None = người gọi không đưa dữ liệu PR: chỉ còn luật theo runs —
    >= 2 lượt merge gate lẻ mà 0 lượt train nghĩa là PR đi đường lẻ, hàng đợi không chạy."""
    reasons = []
    if merged_n is None:
        summary = f"merged PRs=n/a merge-gate verifies={merge_v} train verifies={train_v} (runs only)"
        if merge_v >= 2 and train_v == 0:
            reasons.append(f"{merge_v} single merge-gate verifies and no train verify")
        return bool(reasons), summary, reasons
    summary = f"merged PRs={merged_n} merge-gate verifies={merge_v} train verifies={train_v}"
    if merged_n >= 2 and train_v == 0:
        reasons.append(f"no train verify at all ({merged_n} merged PRs)")
    if merge_v >= 2 and merge_v > train_v:   # sàn 2: một lượt /super-review --standalone lẻ ngoài board không làm đỏ (PM 26/10)
        reasons.append(f"{merge_v} single merge-gate verifies > {train_v} train verifies")
    return bool(reasons), summary, reasons


def check(runs, since: float, merged=None) -> tuple:
    """Canary trên runs + danh sách PR merged (None: chỉ runs). Ném CanaryError khi đầu vào hỏng."""
    merge_v, train_v = count_verifies(runs, since)
    merged_n = None if merged is None else merged_since(merged, since)
    return evaluate(merge_v, train_v, merged_n)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Canary của merge theo đợt: ĐỎ khi PR merged mà train không chạy.")
    ap.add_argument("--runs", required=True, help="<git common dir>/postfix-gate/runs.jsonl")
    ap.add_argument("--since", help="ISO time (no zone = UTC) or epoch; default merge_queue.enabled_at of --config")
    ap.add_argument("--config", help="board config (.claude/super-board/configs/<slug>.json)")
    ap.add_argument("--merged-json", help="output of `gh pr list --state merged --json number,mergedAt`; default: call gh")
    a = ap.parse_args(argv)
    try:
        bounds = []
        if a.config:
            enabled_at = queue_since(a.config)
            if enabled_at is None:
                print("canary off: merge_queue not enabled (or enabled_at null) in config")
                return 0
            bounds.append(enabled_at)
        if a.since:
            try:
                bounds.append(parse_time(a.since))
            except ValueError as e:
                raise CanaryError(f"--since {a.since!r}: {e}") from e
        if not bounds:
            raise CanaryError("need --since or --config with merge_queue.enabled_at")
        since = max(bounds)
        merged = load_merged_json(a.merged_json) if a.merged_json else gh_merged()
        red, summary, reasons = check(a.runs, since, merged)
    except CanaryError as e:
        print(f"batch_canary: error: {e}", file=sys.stderr)
        return 2
    print(summary)
    if red:
        print("RED: " + "; ".join(reasons))
        return 1
    print("GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
