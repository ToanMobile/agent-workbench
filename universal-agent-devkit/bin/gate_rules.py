#!/usr/bin/env python3
"""Cờ của gate (#686, thiết kế ổn định DevKit v3.1 §2/§10): `.agents/gate-rules.json`, override, chốt bật cờ, archive quyết định, watcher.

Guard `[core]` cứng. Chỉ thư viện chuẩn, tự đủ (không import anh em, không đụng `__file__` lúc nạp): merge gate chạy bản lấy từ
BASE_SHA bằng `python3 -I -B -c "$(git show BASE_SHA:…/gate_rules.py)" raise-check …`. Mọi lỗi ⇒ `off`, không bao giờ raise.

Thứ tự đọc (§2.2): blob đã commit (HEAD của main checkout ∧ origin/<trunk>; main bẩn ⇒ off; không bao giờ đọc working tree của worktree)
→ file override `<common>/postfix-gate/gate-rules.override.json` → env `DEVKIT_GATE_RULE_<R>`. Override và env chỉ HẠ (off; riêng CACHE
thêm `zero`). Hai env cũ DEVKIT_SUITE_CACHE_MAX_S / DEVKIT_GATE_CACHE_MAX_S chỉ hạ TTL. `shadow` hay giá trị lạ đều là off.

CLI: get <R|CACHE> | ttl suite_cache_max_s | json | tokens | off <R|CACHE> [--zero] --reason T | raise-check … | watch [--dry-run].
Các lệnh đọc luôn exit 0 và in `off` khi lỗi.
"""

from __future__ import annotations

import argparse
import copy
import datetime
import fcntl
import fnmatch
import functools
import glob
import hashlib
import itertools
import json
import math
import os
import plistlib
import re
import shlex
import subprocess
import sys
import tempfile
import time

RULES = ("L1", "L2", "L3", "B")
KEYS = RULES + ("CACHE",)          # CACHE = ttl.suite_cache_max_s
TTL = {"suite_cache_max_s": (21600, 86400)}   # (mặc định, trần)
GATE_FILE = ".agents/gate-rules.json"
OVERRIDE_NAME = "gate-rules.override.json"
LOG_LINE_MAX = 16 * 1024
ARCHIVE_KEEP_DAYS = 30
NIGHT_MAX_AGE_S = 36 * 3600        # L2: quá ngần này không có lượt đêm thì tắt

# glob path mà PR bật khoá được chạm (§2.4 đk 3); mọi khoá cộng thêm GATE_FILE. Nằm trong guard nên PR bật không mở rộng được manifest của chính nó.
MANIFEST = {
    "CACHE": ["universal-agent-devkit/bin/suite_cache.py", "universal-agent-devkit/bin/post-fix-gate.py",
              "universal-agent-devkit/tests/gates/test_gate_suite_cache_ttl_file.sh",
              "universal-agent-devkit/tests/gates/test_gate_rerun_skip_unity.sh", ".agents/regression_matrix.active.json"],
    "L3": ["universal-agent-devkit/bin/l3_gate.py", "universal-agent-devkit/bin/post-fix-gate.py",
           ".claude/bin/super-board-merge-gate.sh", ".claude/bin/super-board-merge-train.sh",
           "universal-agent-devkit/hooks/guard-pm-state.sh", "universal-agent-devkit/hooks/hooks.json",
           "universal-agent-devkit/adapters/setup_claude.sh", "universal-agent-devkit/bin/agent-health.py",
           "mcp-servers/antigravity-pm-mcp/src/tools.js", "*/tests/*l3*", "tests/super-board/test_merge_gate_l3_*",
           "*/tests/*guard_pm_state*", ".agents/regression_matrix.active.json", ".agents/gate-core.txt"],
    "B": ["universal-agent-devkit/bin/post-fix-gate.py", "universal-agent-devkit/tests/gates/test_gate_red_rerun_skip.sh",
          ".agents/instincts.md", ".agents/regression_matrix.active.json"],
    "L1": [".claude/bin/super-board-merge-gate.sh", ".claude/bin/super-board-merge-queue.sh", ".claude/bin/super-board-run.sh",
           ".claude/bin/super-board-status.py", "tests/super-board/test_merge_gate_two_phase.sh", ".agents/regression_matrix.active.json"],
    "L2": ["universal-agent-devkit/bin/scoped_gate.py", "universal-agent-devkit/bin/post-fix-gate.py", ".agents/gate-core.txt",
           "universal-agent-devkit/scripts/governance/rules_replay.py", "universal-agent-devkit/tests/gates/test_scoped_gate_l2.sh",
           ".agents/regression_matrix.active.json"],
}


def _warn(msg: str) -> None:
    try:
        print("gate_rules: " + msg, file=sys.stderr)
    except OSError:
        pass


# --- git -----------------------------------------------------------------------------------------------------------------------

def _git(cwd, *args, timeout=15):
    """(rc, stdout). Lỗi chạy git ⇒ (1, "")."""
    try:
        p = subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True, timeout=timeout, check=False)
        return p.returncode, p.stdout
    except (OSError, subprocess.SubprocessError, ValueError):
        return 1, ""


def _roots(project_dir=None):
    """(main checkout, git common dir), đường dẫn thật; (None, None) khi không phải repo. Main = cha của common dir (như
    post-fix-gate._main_checkout_root), không phải worktree đang đứng."""
    pd = os.path.realpath(project_dir or os.getcwd())
    rc, out = _git(pd, "rev-parse", "--path-format=absolute", "--git-common-dir")
    common = out.strip()
    if rc != 0 or not common:
        return None, None
    common = os.path.realpath(common)
    main = os.path.dirname(common) if os.path.basename(common) == ".git" else pd
    return main, common


def _trunk(main) -> str:
    rc, out = _git(main, "symbolic-ref", "--short", "refs/remotes/origin/HEAD")
    name = out.strip()
    if rc == 0 and name.startswith("origin/") and len(name) > 7:
        return name[7:]
    return "main"


def _origin_ref(main):
    """refs/remotes/origin/<trunk> khi repo có remote origin; None khi không có remote (chỉ đọc HEAD). "" khi có remote mà chưa có ref."""
    rc, _ = _git(main, "remote", "get-url", "origin")
    if rc != 0:
        return None
    ref = "refs/remotes/origin/" + _trunk(main)
    rc, _ = _git(main, "rev-parse", "--verify", "-q", ref)
    return ref if rc == 0 else ""


# --- đọc cờ ----------------------------------------------------------------------------------------------------------------------

def _norm_ttl(v, warn=True) -> int:
    """TTL hợp lệ: số nguyên (không phải bool) trong (0, trần]; lớn hơn trần ⇒ cắt kèm cảnh báo; rác/thiếu/≤0 ⇒ mặc định."""
    default, cap = TTL["suite_cache_max_s"]
    if v is None:
        return default
    if isinstance(v, bool) or not isinstance(v, int) or v <= 0:
        if warn:
            _warn("ttl.suite_cache_max_s không hợp lệ (%r): dùng %d" % (v, default))
        return default
    if v > cap:
        if warn:
            _warn("ttl.suite_cache_max_s %d vượt trần: cắt về %d" % (v, cap))
        return cap
    return v


def _parse_doc(doc):
    """doc (dict hay None) → ({R: bool on}, ttl int). Giá trị khác đúng chuỗi "on" (shadow, ON, true…) là off."""
    on = {r: False for r in RULES}
    ttl = TTL["suite_cache_max_s"][0]
    if not isinstance(doc, dict):
        return on, ttl
    rules = doc.get("rules")
    if isinstance(rules, dict):
        for r in RULES:
            on[r] = isinstance(rules.get(r), str) and rules.get(r) == "on"
    t = doc.get("ttl")
    if isinstance(t, dict):
        ttl = _norm_ttl(t.get("suite_cache_max_s"))
    return on, ttl


def _parse_text(text):
    try:
        return _parse_doc(json.loads(text))
    except (TypeError, ValueError):
        return _parse_doc(None)


def _show(main, ref, path=GATE_FILE):
    rc, out = _git(main, "show", "%s:%s" % (ref, path))
    return out if rc == 0 else None


def _committed(main):
    """({R: bool}, ttl) từ blob đã commit: rule on khi CẢ HEAD và origin/<trunk> ghi on; ttl = min hai blob. Main bẩn / thiếu blob ⇒ off."""
    off = _parse_doc(None)
    if main is None:
        return off
    rc, _ = _git(main, "diff", "--quiet", "HEAD", "--", GATE_FILE)
    if rc != 0:   # 1 = khác HEAD; khác 0 khác = git lỗi: cùng coi là bẩn
        return off
    head = _show(main, "HEAD")
    if head is None:
        return off
    h_on, h_ttl = _parse_text(head)
    oref = _origin_ref(main)
    if oref is None:
        return h_on, h_ttl
    o_txt = _show(main, oref) if oref else None
    if o_txt is None:
        return off
    o_on, o_ttl = _parse_text(o_txt)
    return {r: h_on[r] and o_on[r] for r in RULES}, min(h_ttl, o_ttl)


def _override(common):
    """({key: "off"}, cache) từ file override; cache ∈ {None, "off", "zero"}. "on" và giá trị lạ bị bỏ."""
    offs, cache = {}, None
    if not common:
        return offs, cache
    try:
        with open(os.path.join(common, "postfix-gate", OVERRIDE_NAME), encoding="utf-8") as fh:
            d = json.load(fh)
    except (OSError, ValueError):
        return offs, cache

    def val(e):
        v = e.get("value") if isinstance(e, dict) else e
        return v if isinstance(v, str) else None
    if isinstance(d, dict):
        rules = d.get("rules")
        if isinstance(rules, dict):
            for r in RULES:
                if val(rules.get(r)) == "off":
                    offs[r] = "off"
        t = d.get("ttl")
        if isinstance(t, dict) and val(t.get("suite_cache_max_s")) in ("off", "zero"):
            cache = val(t.get("suite_cache_max_s"))
    return offs, cache


def _env_float(name):
    try:
        v = float(os.environ.get(name, "").strip())
    except ValueError:
        return None
    return v if math.isfinite(v) and v >= 0 else None


def _compute(project_dir=None) -> dict:
    default = TTL["suite_cache_max_s"][0]
    try:
        main, common = _roots(project_dir)
        on, ttl = _committed(main)
        o_offs, o_cache = _override(common)
        cache_mode = o_cache
        for r in RULES:
            if o_offs.get(r) == "off" or os.environ.get("DEVKIT_GATE_RULE_" + r, "").strip() == "off":
                on[r] = False
        env_cache = os.environ.get("DEVKIT_GATE_RULE_CACHE", "").strip()
        if env_cache == "zero" or cache_mode == "zero":
            cache_mode = "zero"
        elif env_cache == "off" or cache_mode == "off":
            cache_mode = "off"
        t = float(ttl)
        if cache_mode == "zero":
            t = 0.0
        elif cache_mode == "off":
            t = min(t, float(default))
        for name in ("DEVKIT_SUITE_CACHE_MAX_S", "DEVKIT_GATE_CACHE_MAX_S"):   # env cũ chỉ được hạ
            v = _env_float(name)
            if v is not None:
                t = min(t, v)
        t = int(t) if float(t).is_integer() else t
        return {"version": 1, "rules": {r: ("on" if on[r] else "off") for r in RULES}, "ttl": {"suite_cache_max_s": t}}
    except Exception as exc:   # lỗi ⇒ off, không raise
        _warn("không đọc được cờ (%s): off" % exc)
        return {"version": 1, "rules": {r: "off" for r in RULES}, "ttl": {"suite_cache_max_s": default}}


@functools.lru_cache(maxsize=16)
def _compute_cached(key):
    return _compute(key)


def clear_cache() -> None:
    _compute_cached.cache_clear()


def effective(project_dir=None) -> dict:
    """{"version", "rules": {L1..B: on|off}, "ttl": {suite_cache_max_s}}. Tính một lần cho mỗi tiến trình (lru_cache) và mỗi thư mục."""
    return copy.deepcopy(_compute_cached(os.path.realpath(project_dir or os.getcwd())))


def on(rule, project_dir=None) -> bool:
    try:
        e = effective(project_dir)
        if rule == "CACHE":
            return e["ttl"]["suite_cache_max_s"] > TTL["suite_cache_max_s"][0]
        return e["rules"].get(rule) == "on"
    except Exception:
        return False


def ttl(key="suite_cache_max_s", project_dir=None) -> float:
    """Hàm chung cho mọi bên đọc TTL: đã min với env; override zero ⇒ 0. Khoá lạ trả 0 (coi như hết hạn)."""
    try:
        if key not in TTL:
            return 0.0
        return float(effective(project_dir)["ttl"][key])
    except Exception:
        return float(TTL.get(key, (0, 0))[0])


def _state_word(key, project_dir=None) -> str:
    if key == "CACHE":
        t = ttl("suite_cache_max_s", project_dir)
        return "zero" if t == 0 else ("on" if t > TTL["suite_cache_max_s"][0] else "off")
    return "on" if on(key, project_dir) else "off"


def used_ok(rules_used, project_dir=None):
    """(ok, why): ok khi mọi luật biên nhận đã dùng (list tên hoặc dict {tên: giá trị}) còn on. Luật lạ ⇒ không ok. So bất đối xứng:
    bật thêm luật khác không làm mất biên nhận."""
    try:
        if not rules_used:
            return True, ""
        names = list(rules_used.keys()) if isinstance(rules_used, dict) else list(rules_used)
        for n in names:
            if n not in KEYS or not on(n, project_dir):
                return False, "%s không còn on" % n
        return True, ""
    except Exception as exc:
        return False, "không đọc được cờ: %s" % exc


def verify_tokens(project_dir=None) -> list:
    """Token khoá verified-trees `L2=<v>,L3=<v>`: hiện hành đầu tiên, rồi mọi tổ hợp có từng luật ≤ hiện hành (L2/L3 on thì thử cả off)."""
    cur = {r: ("on" if on(r, project_dir) else "off") for r in ("L2", "L3")}
    opts = [["on", "off"] if cur[r] == "on" else ["off"] for r in ("L2", "L3")]
    return ["L2=%s,L3=%s" % (a, b) for a, b in itertools.product(*opts)]


# --- ghi override ----------------------------------------------------------------------------------------------------------------

def write_override(key, zero, reason, project_dir=None) -> bool:
    """Ghi nguyên tử `off` (hay `zero` cho CACHE) vào file override. True khi file đổi. Idempotent; `zero` không bị `off` nới lại."""
    _, common = _roots(project_dir)
    if not common:
        raise OSError("không tìm thấy git common dir")
    pg = os.path.join(common, "postfix-gate")
    os.makedirs(pg, exist_ok=True)
    path = os.path.join(pg, OVERRIDE_NAME)
    value = "zero" if zero else "off"
    with open(path + ".lock", "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            with open(path, encoding="utf-8") as fh:
                d = json.load(fh)
            if not isinstance(d, dict):
                d = {}
        except (OSError, ValueError):
            d = {}
        if key == "CACHE":
            slot = d.setdefault("ttl", {})
            name = "suite_cache_max_s"
        else:
            slot = d.setdefault("rules", {})
            name = key
        if not isinstance(slot, dict):
            slot = d["ttl" if key == "CACHE" else "rules"] = {}
        old = slot.get(name)
        old_v = old.get("value") if isinstance(old, dict) else None
        if old_v == "zero" or old_v == value:
            return False
        slot[name] = {"value": value, "reason": reason, "at": int(time.time()),
                      "by": os.environ.get("DEVKIT_AGENT_ID") or os.environ.get("USER") or "?"}
        fd, tmp = tempfile.mkstemp(prefix=OVERRIDE_NAME + ".", dir=pg)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                json.dump(d, fh, ensure_ascii=False, indent=1)
                fh.write("\n")
            os.replace(tmp, path)
        except BaseException:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise
    clear_cache()
    return True


# --- archive quyết định (§10.2) ---------------------------------------------------------------------------------------------------

def _archive_dir(common):
    return os.path.join(common, "postfix-gate", "archive")


def log_decision(rule, record, project_dir=None) -> None:
    """Ghi một dòng JSON vào `<common>/postfix-gate/archive/rules-<RULE>-<YYYYMMDD UTC>.jsonl` (flock, ≤ 16 KiB). Lỗi chỉ in cảnh báo."""
    try:
        if rule not in KEYS:
            _warn("log_decision: luật lạ %r, bỏ qua" % (rule,))
            return
        _, common = _roots(project_dir)
        if not common:
            _warn("log_decision: không có git common dir, bỏ qua")
            return
        rec = dict(record) if isinstance(record, dict) else {"detail": {"raw": repr(record)}}
        rec.setdefault("ts", time.time())
        rec["rule"] = rule
        rec.setdefault("value", _state_word(rule, project_dir))
        rec.setdefault("kind", "decision")
        rec.setdefault("caller", os.path.basename(sys.argv[0]) if sys.argv and sys.argv[0] else "?")
        line = json.dumps(rec, ensure_ascii=False, default=str)
        if len(line.encode("utf-8")) > LOG_LINE_MAX:
            rec["detail"] = {"truncated": True, "bytes": len(line)}
            line = json.dumps(rec, ensure_ascii=False, default=str)
            if len(line.encode("utf-8")) > LOG_LINE_MAX:
                line = json.dumps({k: rec.get(k) for k in ("ts", "rule", "value", "decision", "kind", "detail")}, default=str)
        day = datetime.datetime.fromtimestamp(float(rec["ts"]), datetime.timezone.utc).strftime("%Y%m%d")
        d = _archive_dir(common)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "rules-%s-%s.jsonl" % (rule, day)), "a", encoding="utf-8") as fh:
            fcntl.flock(fh, fcntl.LOCK_EX)
            fh.write(line + "\n")
    except Exception as exc:
        _warn("log_decision(%s) lỗi, bỏ qua: %s" % (rule, exc))


# --- chốt bật cờ (§2.4) -----------------------------------------------------------------------------------------------------------

def raise_check(old, new, changed_paths, guard_same):
    """(rc, lý do). rc 0 khi không khoá nào được nâng; khi có, phải đủ bốn điều kiện, thiếu một là rc 10:
    1. guard_same (blob gate_rules.py ở HEAD bằng ở BASE); 2. đúng một khoá nâng và không khoá nào đổi khác (kể cả hạ);
    3. mọi path khớp MANIFEST[khoá] ∪ {GATE_FILE}; 4. trailer Freeze-exception không tính (bộ kiểm không đọc commit message).
    old/new: dict của file cờ (old None = chưa có file). Hạ (on→off, TTL giảm) luôn rc 0."""
    try:
        o_on, o_ttl = _parse_doc(old)
        n_on, n_ttl = _parse_doc(new)
        raised = [r for r in RULES if n_on[r] and not o_on[r]] + (["CACHE"] if n_ttl > o_ttl else [])
        lowered = [r for r in RULES if o_on[r] and not n_on[r]] + (["CACHE"] if n_ttl < o_ttl else [])
        if not raised:
            return 0, []
        why = []
        if not guard_same:
            why.append("gate_rules.py ở HEAD khác ở BASE_SHA")
        if len(raised) != 1:
            why.append("nâng nhiều khoá cùng lúc: " + ", ".join(raised))
        if lowered:
            why.append("hạ khoá khác cùng lúc: " + ", ".join(lowered))
        paths = [p.strip() for p in (changed_paths or []) if p and p.strip()]
        if GATE_FILE not in paths:
            why.append("diff không có %s" % GATE_FILE)
        if len(raised) == 1:
            allowed = MANIFEST.get(raised[0], []) + [GATE_FILE]
            for p in paths:
                if not any(fnmatch.fnmatchcase(p, g) for g in allowed):
                    why.append("%s ngoài manifest %s" % (p, raised[0]))
        return (10 if why else 0), why
    except Exception as exc:   # không phân tích được: đóng
        return 10, ["raise_check lỗi: %s" % exc]


# --- watcher (§10.3) --------------------------------------------------------------------------------------------------------------

def _now() -> float:
    try:
        return float(os.environ["DEVKIT_RULES_WATCH_NOW"])
    except (KeyError, ValueError):
        return time.time()


def _jsonl(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line.startswith("{"):
                    continue
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if isinstance(d, dict):
                    yield d
    except OSError:
        return


def _num(v):
    return float(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else None


def _records(common, key):
    """Record archive của một khoá, theo ts tăng dần; bỏ dòng không có ts."""
    out = []
    for f in sorted(glob.glob(os.path.join(_archive_dir(common), "rules-%s-*.jsonl" % key))):
        for d in _jsonl(f):
            ts = _num(d.get("ts"))
            if ts is not None:
                d["ts"] = ts
                if not isinstance(d.get("detail"), dict):
                    d["detail"] = {}
                out.append(d)
    return sorted(out, key=lambda d: d["ts"])


def _nights(common):
    """Lịch sử lượt đêm `nightly/history.jsonl` (gate_full.py): [{at epoch, result, red:set}] theo thời gian. `red` + `red_tests` (nếu có)."""
    out = []
    for d in _jsonl(os.path.join(common, "postfix-gate", "nightly", "history.jsonl")):
        try:
            at = datetime.datetime.fromisoformat(str(d.get("at"))).timestamp()
        except (ValueError, TypeError):
            continue
        red = set()
        for k in ("red", "red_tests"):
            if isinstance(d.get(k), list):
                red |= {x for x in d[k] if isinstance(x, str)}
        out.append({"at": at, "result": d.get("result"), "red": red})
    return sorted(out, key=lambda e: e["at"])


def _active(rules, ttl_v, key):
    return ttl_v > TTL["suite_cache_max_s"][0] if key == "CACHE" else bool(rules.get(key))


def _enabled_at(main, key):
    """Epoch của commit đầu chuỗi liên tục bật `key` trên origin/<trunk> (HEAD khi không có remote); None khi không tính được."""
    oref = _origin_ref(main)
    ref = oref if oref else "HEAD"
    rc, out = _git(main, "log", "-n", "50", "--format=%H %ct", ref, "--", GATE_FILE)
    if rc != 0:
        return None
    commits = [ln.split() for ln in out.splitlines() if len(ln.split()) == 2]
    earliest = None
    for sha, ct in commits:   # mới → cũ
        txt = _show(main, sha)
        rules, t = _parse_text(txt) if txt is not None else (_parse_doc(None))
        if not _active(rules, t, key):
            break
        earliest = float(ct)
    return earliest


def _baseline(nights, enabled):
    """Tập đỏ nền: suite/test đỏ của lượt đêm gần nhất trước khi bật."""
    prior = [n for n in nights if enabled is not None and n["at"] < enabled]
    return set(prior[-1]["red"]) if prior else set()


def _after(recs, enabled):
    return [r for r in recs if enabled is None or r["ts"] >= enabled]


def _night_windows(nights, enabled):
    """(đêm, tập đỏ mới ngoài nền, mốc đầu khoảng) cho từng lượt đêm đỏ kể từ khi bật; khoảng = (đêm trước, đêm này]."""
    base = _baseline(nights, enabled)
    out = []
    for i, n in enumerate(nights):
        if enabled is not None and n["at"] < enabled:
            continue
        new = n["red"] - base
        if n["result"] == "red" and new:
            prev = nights[i - 1]["at"] if i else (enabled if enabled is not None else 0.0)
            out.append((n, new, prev))
    return out


def _sig_b(recs, enabled, **_):
    for r in _after(recs, enabled):
        if "red_reused" in (r.get("kind"), r.get("decision")) and r["detail"].get("exit") != 1:
            return "red_reused_exit", "record red_reused có exit=%r (cần 1)" % (r["detail"].get("exit"),)
    return None


def _sig_cache(recs, enabled, **_):
    for r in _after(recs, enabled):
        if r.get("kind") == "false_green":
            return "false_green", "sentinel full FAIL trong khi cache còn PASS cùng khoá (suite %s)" % (r["detail"].get("suite"),)
    return None


def _sig_l3(recs, enabled, nights, main, **_):
    recs = [r for r in _after(recs, enabled) if r.get("decision") == "applied" and r["detail"].get("used")]
    oref = _origin_ref(main)
    ref = oref if oref else "HEAD"
    for r in recs:   # a. blob test đã duyệt lệch với commit squash trên main
        blobs, pr = r["detail"].get("approved_blobs"), r.get("pr")
        if not isinstance(blobs, dict) or not blobs or pr in (None, ""):
            continue
        rc, out = _git(main, "log", ref, "--reverse", "--format=%H %ct", "--fixed-strings", "--grep=(#%s)" % pr)
        sq = None
        for ln in out.splitlines() if rc == 0 else ():
            p = ln.split()
            if len(p) == 2 and float(p[1]) >= int(r["ts"]) - 1:
                sq = p[0]
                break
        if not sq:   # PR chưa vào main: chưa kết luận
            continue
        for path, blob in blobs.items():
            rc2, got = _git(main, "rev-parse", "--verify", "-q", "%s:%s" % (sq, path))
            if rc2 != 0 or got.strip() != blob:
                return "approved_blob_mismatch", "blob %s ở commit squash #%s khác approved_blobs của record L3" % (path, pr)
    # b. test đỏ ∈ protected ở đêm
    protected = {}
    for r in recs:
        prot = r["detail"].get("protected")
        if isinstance(prot, dict):
            for p in prot:
                protected.setdefault(p, r["ts"])
    for n, new, _prev in _night_windows(nights, enabled):
        for t in sorted(new & set(protected)):
            if protected[t] <= n["at"]:
                return "protected_red", "test %s ∈ protected của record L3 đỏ ở lượt đêm" % t
    return None


def _sig_l2(recs, enabled, nights, main, now, **_):
    if _plist_missing(main):
        return "plist_missing", "không thấy plist lịch gate-full đêm của repo"
    last = nights[-1]["at"] if nights else None
    if (last is None or last < now - NIGHT_MAX_AGE_S) and (enabled is None or enabled < now - NIGHT_MAX_AGE_S):
        return "no_night_run", "không có lượt đêm trong 36 giờ"
    applied = [r for r in _after(recs, enabled) if r.get("decision") == "applied"]
    for n, new, prev in _night_windows(nights, enabled):
        for r in applied:
            if not (prev < r["ts"] <= n["at"]):
                continue
            d = r["detail"]
            chosen = set()
            for k in ("suites", "tests", "smoke"):
                if isinstance(d.get(k), list):
                    chosen |= {x for x in d[k] if isinstance(x, str)}
            miss = sorted(new - chosen)
            if miss:
                return "unselected_red", "đêm đỏ %s mà quyết định L2 đã áp không chọn" % ", ".join(miss)
    return None


def _sig_l1(recs, enabled, nights, **_):
    applied = [r for r in _after(recs, enabled) if r.get("decision") == "applied"]
    for n, new, prev in _night_windows(nights, enabled):
        for r in applied:
            if not (prev < r["ts"] <= n["at"]):
                continue
            d = r["detail"]
            skipped = set()
            for k in ("skipped_tests", "skipped_suites"):
                if isinstance(d.get(k), list):
                    skipped |= {x for x in d[k] if isinstance(x, str)}
            hit = sorted(new & skipped)
            if hit:
                return "skipped_red", "đêm đỏ %s mà một lần miễn L1 đã bỏ qua" % ", ".join(hit)
    return None


_SIGNALS = {"L1": _sig_l1, "L2": _sig_l2, "L3": _sig_l3, "B": _sig_b, "CACHE": _sig_cache}


def _plist_missing(main) -> bool:
    la = os.environ.get("DEVKIT_LAUNCH_AGENTS_DIR") or os.path.join(os.path.expanduser("~"), "Library", "LaunchAgents")
    phys = os.path.realpath(main)
    slug = re.sub(r"[^A-Za-z0-9-]", "-", os.path.basename(phys)) + "-" + hashlib.sha1(phys.encode()).hexdigest()[:8]
    if os.path.isfile(os.path.join(la, "com.toanmobile.devkit.gate-full.%s.plist" % slug)):
        return False
    for p in glob.glob(os.path.join(la, "com.toanmobile.devkit.gate-full.*.plist")):   # đổi tên thư mục: tìm theo --repo
        try:
            with open(p, "rb") as fh:
                args = plistlib.load(fh).get("ProgramArguments") or []
            if "--repo" in args and os.path.realpath(args[args.index("--repo") + 1]) == phys:
                return False
        except (OSError, ValueError, IndexError, plistlib.InvalidFileException):
            continue
    return True


def _atomic_json(path, obj) -> None:
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=os.path.basename(path) + ".", dir=d)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(obj, fh, ensure_ascii=False, indent=1)
        fh.write("\n")
    os.replace(tmp, path)


def _run_hook(env_name, extra):
    """Lệnh móc PR / thẻ (env), thêm tham số. (trạng thái, rc)."""
    raw = os.environ.get(env_name, "").strip()
    if not raw:
        return "chưa nối (đặt %s)" % env_name, None
    try:
        p = subprocess.run(shlex.split(raw) + extra, capture_output=True, text=True, timeout=300, check=False)
        if p.returncode != 0:
            _warn("%s exit %d: %s" % (env_name, p.returncode, (p.stderr or p.stdout).strip()[-200:]))
        return ("xong" if p.returncode == 0 else "lỗi"), p.returncode
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        _warn("%s lỗi: %s" % (env_name, exc))
        return "lỗi", None


def watch(dry_run=False, project_dir=None) -> int:
    """Tín hiệu tắt ngay của cả năm khoá (§10.3-A), dựa trên record archive (§10.2) và lịch sử đêm. Mỗi khoá đang nâng mà có một tín hiệu ⇒ một
    action (JSON một dòng): off (có hiệu lực ngay) + PR hạ cờ + thẻ P1. `dry_run` không ghi gì. Exit 3 khi SB_BOARD_WORKER=1.
    ponytail: PR hạ cờ và thẻ P1 chỉ chạy qua DEVKIT_RULES_WATCH_PR_CMD / DEVKIT_RULES_WATCH_CARD_CMD; nối thẳng gh + create_task.py khi
    watcher chạy thật (PR 1 chỉ cần dry-run). Chưa có: ngưỡng chặn sai ≥ 2, BUSY, p90 (§10.3-B), nguồn base-red."""
    if os.environ.get("SB_BOARD_WORKER") == "1":
        _warn("watch không chạy trong worker của board")
        return 3
    try:
        main, common = _roots(project_dir)
        if not main or not common:
            return 0
        clear_cache()
        eff = effective(project_dir)
        raised = [k for k in KEYS if (eff["ttl"]["suite_cache_max_s"] > TTL["suite_cache_max_s"][0] if k == "CACHE"
                                      else eff["rules"].get(k) == "on")]
        now, nights = _now(), _nights(common)
        today = datetime.datetime.fromtimestamp(now, datetime.timezone.utc).strftime("%Y%m%d")
        state = {"enabled_at": {}, "baseline_red": {}}
        for k in raised:
            enabled = _enabled_at(main, k)
            if enabled is not None:
                state["enabled_at"][k] = enabled
            state["baseline_red"][k] = sorted(_baseline(nights, enabled))
            hit = _SIGNALS[k](recs=_records(common, k), enabled=enabled, nights=nights, main=main, now=now)
            if not hit:
                continue
            signal, why = hit
            reason = "%s: %s" % (signal, why)
            zero = k == "CACHE"
            branch = "gate-rules-off-%s-%s" % (k, today)
            title = "tắt %s (%s)" % (k, signal)
            steps = [{"step": "off", "cmd": ["gate_rules.py", "off", k] + (["--zero"] if zero else []) + ["--reason", reason]},
                     {"step": "pr", "branch": branch, "title": "🔧 [chore] gate-rules: " + title},
                     {"step": "card", "title": "🐛 [fix] P1 gate-rules: " + title, "labels": "bug"}]
            if not dry_run:
                try:
                    steps[0]["status"] = "xong" if write_override(k, zero, reason, project_dir) else "đã off"
                except OSError as exc:
                    steps[0]["status"] = "lỗi: %s" % exc
                    _warn("off %s lỗi: %s" % (k, exc))
                steps[1]["status"], _ = _run_hook("DEVKIT_RULES_WATCH_PR_CMD", [k, branch, steps[1]["title"]])
                steps[2]["status"], _ = _run_hook("DEVKIT_RULES_WATCH_CARD_CMD", [k, steps[2]["title"], reason])
            print(json.dumps({"rule": k, "signal": signal, "reason": reason, "dry_run": bool(dry_run),
                              "enabled_at": state["enabled_at"].get(k), "steps": steps}, ensure_ascii=False))
        if not dry_run:
            _atomic_json(os.path.join(common, "postfix-gate", "gate-rules-watch.json"), state)
            cutoff = (datetime.datetime.fromtimestamp(now, datetime.timezone.utc) - datetime.timedelta(days=ARCHIVE_KEEP_DAYS)).strftime("%Y%m%d")
            for f in glob.glob(os.path.join(_archive_dir(common), "rules-*-*.jsonl")):
                m = re.search(r"-(\d{8})\.jsonl$", f)
                if m and m.group(1) < cutoff:
                    try:
                        os.unlink(f)
                    except OSError as exc:
                        _warn("không xoá được %s: %s" % (f, exc))
    except Exception as exc:
        _warn("watch lỗi: %s" % exc)
    return 0


# --- CLI ---------------------------------------------------------------------------------------------------------------------------

def _load_json_file(path, stdin_ok=False):
    try:
        if path == "-" and stdin_ok:
            return json.loads(sys.stdin.read())
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def main(argv=None) -> int:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--project-dir", default=None)
    ap = argparse.ArgumentParser(prog="gate_rules.py", description="Cờ gate-rules (#686)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("get", parents=[common]); p.add_argument("rule")
    p = sub.add_parser("ttl", parents=[common]); p.add_argument("key", nargs="?", default="suite_cache_max_s")
    sub.add_parser("json", parents=[common])
    sub.add_parser("tokens", parents=[common])
    p = sub.add_parser("off", parents=[common])
    p.add_argument("rule", choices=KEYS); p.add_argument("--zero", action="store_true"); p.add_argument("--reason", required=True)
    p = sub.add_parser("raise-check", parents=[common])
    p.add_argument("--old", required=True); p.add_argument("--new", required=True); p.add_argument("--paths", required=True)
    p.add_argument("--guard-same", required=True, choices=("0", "1"))
    p = sub.add_parser("watch", parents=[common]); p.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)
    try:
        if a.cmd == "get":
            print(_state_word(a.rule, a.project_dir) if a.rule in KEYS else "off")
        elif a.cmd == "ttl":
            v = ttl(a.key, a.project_dir)
            print(int(v) if float(v).is_integer() else v)
        elif a.cmd == "json":
            print(json.dumps(effective(a.project_dir), ensure_ascii=False))
        elif a.cmd == "tokens":
            print("\n".join(verify_tokens(a.project_dir)))
        elif a.cmd == "off":
            if os.environ.get("SB_BOARD_WORKER") == "1":
                _warn("off bị từ chối trong worker của board (SB_BOARD_WORKER=1)")
                return 3
            if a.zero and a.rule != "CACHE":
                ap.error("--zero chỉ dùng cho CACHE")
            try:
                changed = write_override(a.rule, a.zero, a.reason, a.project_dir)
            except OSError as exc:
                _warn("không ghi được override: %s" % exc)
                return 1
            print("%s: %s" % (a.rule, "zero" if a.zero else "off") + ("" if changed else " (đã có)"))
        elif a.cmd == "raise-check":
            try:
                with open(a.paths, encoding="utf-8") as fh:
                    paths = fh.read().splitlines()
            except OSError:
                paths = []
            old = None if a.old == "-" else _load_json_file(a.old)
            rc, why = raise_check(old, _load_json_file(a.new, stdin_ok=True), paths, a.guard_same == "1")
            for w in why:
                print("gate-rules raise: " + w, file=sys.stderr)
            return rc
        elif a.cmd == "watch":
            return watch(a.dry_run, a.project_dir)
    except SystemExit:
        raise
    except Exception as exc:
        _warn("lỗi: %s" % exc)
        if a.cmd in ("get", "ttl"):
            print("off" if a.cmd == "get" else TTL["suite_cache_max_s"][0])
        elif a.cmd == "raise-check":
            return 10
    return 0


if __name__ == "__main__":
    sys.exit(main())
