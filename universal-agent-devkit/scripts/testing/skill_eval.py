#!/usr/bin/env python3
"""Công cụ chạy thực nghiệm A/B (with_skill vs without_skill), chấm điểm, so mù và tổng hợp benchmark cho skill DevKit."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import json
import os
import pathlib
import random
import re
import shutil
import signal
import statistics
import subprocess
import sys
import tempfile
import time
from typing import Any

# Các dấu hiệu cấu hình ở thư mục cha có thể làm nhiễm môi trường chạy CLI claude
CONTAMINATION_MARKERS = ("AGENTS.md", "CLAUDE.md", ".claude")
VALID_CONFIGS = ("with_skill", "without_skill")
VALID_CHECK_TYPES = ("tool_order", "command", "file_glob", "result_regex")
DEFAULT_ALLOWED_TOOLS = "Read Edit Write Glob Grep Bash(python3 *)"
GLOBAL_DISALLOWED_TOOLS = ("AskUserQuestion",)
ACCOUNT_RE = re.compile(r"[A-Za-z0-9_-]+")
GIT_ENV_SCRUB = (
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_COMMON_DIR",
    "GIT_OBJECT_DIRECTORY",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    "GIT_PREFIX",
)


class ConfigError(Exception):
    """Lỗi cấu hình, tham số đầu vào hoặc vi phạm rào chắn an toàn (exit 2)."""


def _to_str(data: str | bytes | None) -> str:
    """Chuyển stdout/stderr từ subprocess (kể cả khi TimeoutExpired trả bytes) về chuỗi UTF-8."""
    if data is None:
        return ""
    if isinstance(data, bytes):
        return data.decode("utf-8", errors="replace")
    return data


def split_tool_specs(raw: str | list[str] | None) -> list[str]:
    """Tách danh sách đặc tả công cụ CLI theo khoảng trắng bên ngoài dấu ngoặc đơn."""
    if not raw:
        return []
    if isinstance(raw, list):
        out: list[str] = []
        for item in raw:
            if not isinstance(item, str):
                raise ConfigError(f"Mục công cụ phải là chuỗi, nhận được: {type(item).__name__}")
            out.extend(split_tool_specs(item))
        return out
    if not isinstance(raw, str):
        raise ConfigError(f"Trường công cụ phải là chuỗi hoặc danh sách chuỗi, nhận được: {type(raw).__name__}")
    tokens: list[str] = []
    buf: list[str] = []
    depth = 0
    for ch in raw:
        if ch == "(":
            depth += 1
            buf.append(ch)
        elif ch == ")":
            depth = max(0, depth - 1)
            buf.append(ch)
        elif ch.isspace() and depth == 0:
            if buf:
                tokens.append("".join(buf))
                buf = []
        else:
            buf.append(ch)
    if buf:
        tokens.append("".join(buf))
    return tokens


def merge_disallowed_tools(eval_spec: str | list[str] | None) -> str:
    """Gộp danh sách công cụ bị cấm mặc định toàn cục (AskUserQuestion) với cấu hình riêng của eval."""
    merged: list[str] = []
    for tok in list(GLOBAL_DISALLOWED_TOOLS) + split_tool_specs(eval_spec):
        if tok and tok not in merged:
            merged.append(tok)
    return " ".join(merged)


def check_workspace_clean(ws_path: str) -> None:
    """Từ chối nếu workspace hoặc bất kỳ thư mục tổ tiên nào có AGENTS.md, CLAUDE.md hoặc .claude."""
    if not ws_path or not ws_path.strip():
        raise ConfigError("Đường dẫn --workspace không được rỗng.")
    abs_ws = os.path.abspath(ws_path)
    real_ws = os.path.realpath(abs_ws)
    checked: set[str] = set()
    for start in (abs_ws, real_ws):
        cur = start
        while True:
            if cur not in checked:
                checked.add(cur)
                for marker in CONTAMINATION_MARKERS:
                    candidate = os.path.join(cur, marker)
                    if os.path.lexists(candidate):
                        raise ConfigError(
                            f"Từ chối workspace '{ws_path}': phát hiện '{marker}' tại thư mục '{cur}' "
                            f"(nguy cơ nhiễm CLAUDE.md/AGENTS.md/hook vào nhánh thử nghiệm)."
                        )
            parent = os.path.dirname(cur)
            if parent == cur:
                break
            cur = parent


def infer_skill_dir(evals_path: str) -> str:
    """Suy ra thư mục gốc của skill từ đường dẫn file evals/evals.json."""
    abs_evals = os.path.abspath(evals_path)
    parent = os.path.dirname(abs_evals)
    if os.path.basename(parent) == "evals":
        return os.path.dirname(parent)
    return parent


def _validate_safe_rel_segments(rel_path: str, field_name: str) -> list[str]:
    """Kiểm tra đường dẫn tương đối không rỗng, không tuyệt đối và không chứa đoạn '.' hay '..'."""
    if not isinstance(rel_path, str) or not rel_path.strip():
        raise ConfigError(f"{field_name}: đường dẫn phải là chuỗi khác rỗng.")
    if os.path.isabs(rel_path) or rel_path.startswith(("/", "\\")):
        raise ConfigError(f"{field_name}: cấm dùng đường dẫn tuyệt đối '{rel_path}'.")
    norm = rel_path.replace("\\", "/").rstrip("/")
    if not norm:
        raise ConfigError(f"{field_name}: đường dẫn không hợp lệ '{rel_path}'.")
    parts = norm.split("/")
    for seg in parts:
        if seg in ("", ".", ".."):
            raise ConfigError(f"{field_name}: cấm chứa đoạn '.' hoặc '..' trong '{rel_path}'.")
    return parts


def resolve_skill_relpath(skill_dir: str, rel_path: str, field_name: str, expect_dir: bool = False) -> str:
    """Phân giải và xác minh đường dẫn tương đối nằm trọn trong thư mục skill (kể cả symlink bên trong)."""
    parts = _validate_safe_rel_segments(rel_path, field_name)
    real_skill = os.path.realpath(skill_dir)

    # Kiểm tra từng bước tiền tố để chặn symlink trung gian trỏ ra ngoài thư mục skill
    cur = skill_dir
    for seg in parts:
        cur = os.path.join(cur, seg)
        if os.path.islink(cur) and not os.path.exists(cur):
            raise ConfigError(f"{field_name}: symlink bị gãy '{rel_path}'.")
        real_cur = os.path.realpath(cur)
        if real_cur != real_skill and not real_cur.startswith(real_skill + os.sep):
            raise ConfigError(f"{field_name}: đường dẫn '{rel_path}' thoát ra ngoài thư mục skill.")

    if expect_dir:
        if not os.path.isdir(cur):
            raise ConfigError(f"{field_name}: thư mục không tồn tại '{rel_path}'.")
        # Duyệt toàn bộ cây con để chặn symlink bên trong thư mục trỏ ra ngoài skill_dir
        for dp, dns, fns in os.walk(cur, followlinks=False):
            for name in dns + fns:
                entry = os.path.join(dp, name)
                if os.path.islink(entry) and not os.path.exists(entry):
                    raise ConfigError(f"{field_name}: phát hiện symlink gãy bên trong '{rel_path}': '{name}'.")
                real_entry = os.path.realpath(entry)
                if real_entry != real_skill and not real_entry.startswith(real_skill + os.sep):
                    raise ConfigError(
                        f"{field_name}: phát hiện symlink '{name}' trong '{rel_path}' trỏ ra ngoài thư mục skill."
                    )
    else:
        if not os.path.isfile(cur):
            raise ConfigError(f"{field_name}: file không tồn tại '{rel_path}'.")

    return cur


def _compile_regex(pattern: Any, field_name: str) -> re.Pattern[str]:
    """Biên dịch và xác thực biểu thức chính quy trong cấu hình check."""
    if not isinstance(pattern, str) or pattern == "":
        raise ConfigError(f"{field_name}: regex phải là chuỗi khác rỗng.")
    try:
        return re.compile(pattern)
    except re.error as exc:
        raise ConfigError(f"{field_name}: regex không hợp lệ '{pattern}': {exc}") from exc


def validate_evals_file(evals_path: str, expected_skill: str | None = None) -> tuple[dict[str, Any], str]:
    """Đọc và kiểm tra toàn diện cấu trúc, kiểu check và an toàn đường dẫn của file evals.json."""
    if not os.path.isfile(evals_path):
        raise ConfigError(f"Không tìm thấy file evals: '{evals_path}'.")
    try:
        with open(evals_path, encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception as exc:
        raise ConfigError(f"Lỗi đọc JSON tại '{evals_path}': {exc}") from exc

    if not isinstance(data, dict):
        raise ConfigError("Gốc của evals.json phải là một JSON object.")

    skill_dir = infer_skill_dir(evals_path)
    dir_skill_name = os.path.basename(os.path.abspath(skill_dir))
    skill_name = data.get("skill_name")
    if not isinstance(skill_name, str) or not skill_name.strip():
        raise ConfigError("Thiếu trường bắt buộc 'skill_name' (chuỗi khác rỗng).")
    if skill_name != dir_skill_name:
        raise ConfigError(f"skill_name '{skill_name}' không khớp tên thư mục skill '{dir_skill_name}'.")
    if expected_skill is not None and skill_name != expected_skill:
        raise ConfigError(f"--skill '{expected_skill}' không khớp skill_name '{skill_name}' trong evals.json.")

    evals = data.get("evals")
    if not isinstance(evals, list) or not evals:
        raise ConfigError("Trường 'evals' phải là danh sách khác rỗng.")

    seen_ids: set[int] = set()
    for idx, ev in enumerate(evals):
        ctx = f"evals[{idx}]"
        if not isinstance(ev, dict):
            raise ConfigError(f"{ctx}: mỗi phần tử phải là object.")
        eid = ev.get("id")
        if isinstance(eid, bool) or not isinstance(eid, int):
            raise ConfigError(f"{ctx}.id: phải là số nguyên.")
        if eid in seen_ids:
            raise ConfigError(f"{ctx}.id: trùng id eval '{eid}'.")
        seen_ids.add(eid)

        prompt = ev.get("prompt")
        if not isinstance(prompt, str) or not prompt.strip():
            raise ConfigError(f"eval {eid}: thiếu 'prompt' hợp lệ.")

        if "name" in ev and (not isinstance(ev["name"], str) or not ev["name"].strip()):
            raise ConfigError(f"eval {eid}: 'name' phải là chuỗi khác rỗng.")
        if "expected_output" in ev and not isinstance(ev["expected_output"], str):
            raise ConfigError(f"eval {eid}: 'expected_output' phải là chuỗi.")
        if "expectations" in ev:
            exps = ev["expectations"]
            if not isinstance(exps, list) or not all(isinstance(x, str) and x.strip() for x in exps):
                raise ConfigError(f"eval {eid}: 'expectations' phải là danh sách chuỗi khác rỗng.")

        if "allowed_tools" in ev:
            if ev["allowed_tools"] is None:
                raise ConfigError(f"eval {eid}.allowed_tools: không được là null.")
            split_tool_specs(ev["allowed_tools"])
        if "disallowed_tools" in ev:
            if ev["disallowed_tools"] is None:
                raise ConfigError(f"eval {eid}.disallowed_tools: không được là null.")
            split_tool_specs(ev["disallowed_tools"])

        if "files_dir" in ev:
            resolve_skill_relpath(skill_dir, ev["files_dir"], f"eval {eid}.files_dir", expect_dir=True)

        if "files" in ev:
            files_list = ev["files"]
            if not isinstance(files_list, list):
                raise ConfigError(f"eval {eid}.files: phải là danh sách đường dẫn.")
            seen_bnames: set[str] = set()
            for frel in files_list:
                resolve_skill_relpath(skill_dir, frel, f"eval {eid}.files", expect_dir=False)
                bname = os.path.basename(frel.rstrip("/"))
                if bname in seen_bnames:
                    raise ConfigError(f"eval {eid}.files: trùng basename '{bname}'.")
                seen_bnames.add(bname)

        checks = ev.get("checks")
        if not isinstance(checks, list) or not checks:
            raise ConfigError(f"eval {eid}: thiếu danh sách 'checks' khác rỗng.")

        seen_cids: set[str] = set()
        for cidx, chk in enumerate(checks):
            cctx = f"eval {eid}.checks[{cidx}]"
            if not isinstance(chk, dict):
                raise ConfigError(f"{cctx}: check phải là object.")
            cid = chk.get("id")
            if not isinstance(cid, str) or not cid.strip():
                raise ConfigError(f"{cctx}: thiếu 'id' chuỗi khác rỗng.")
            if cid in seen_cids:
                raise ConfigError(f"{cctx}: trùng check id '{cid}'.")
            seen_cids.add(cid)

            ctext = chk.get("text")
            if not isinstance(ctext, str) or not ctext.strip():
                raise ConfigError(f"{cctx}: thiếu 'text' mô tả check.")

            ctype = chk.get("type")
            if ctype not in VALID_CHECK_TYPES:
                raise ConfigError(f"{cctx}: kiểu check không hợp lệ '{ctype}' (hợp lệ: {VALID_CHECK_TYPES}).")

            if ctype == "tool_order":
                for side in ("first", "before"):
                    spec = chk.get(side)
                    if not isinstance(spec, dict):
                        raise ConfigError(f"{cctx}.{side}: phải là object.")
                    _compile_regex(spec.get("tool"), f"{cctx}.{side}.tool")
                    for rx_key in ("command_regex", "command_not_regex", "path_regex", "path_not_regex"):
                        if rx_key in spec:
                            _compile_regex(spec[rx_key], f"{cctx}.{side}.{rx_key}")
                if "pass_if_before_absent" in chk and not isinstance(chk["pass_if_before_absent"], bool):
                    raise ConfigError(f"{cctx}.pass_if_before_absent: phải là boolean.")

            elif ctype == "command":
                cmd = chk.get("cmd")
                if not isinstance(cmd, list) or not cmd or not all(isinstance(a, str) and a != "" for a in cmd):
                    raise ConfigError(f"{cctx}.cmd: phải là danh sách chuỗi lệnh khác rỗng.")
                if "oracle_files" in chk:
                    of_list = chk["oracle_files"]
                    if not isinstance(of_list, list):
                        raise ConfigError(f"{cctx}.oracle_files: phải là danh sách.")
                    seen_obnames: set[str] = set()
                    for orel in of_list:
                        resolve_skill_relpath(skill_dir, orel, f"{cctx}.oracle_files", expect_dir=False)
                        obname = os.path.basename(orel.rstrip("/"))
                        if obname in seen_obnames:
                            raise ConfigError(f"{cctx}.oracle_files: trùng basename '{obname}'.")
                        seen_obnames.add(obname)
                if "remove_paths" in chk:
                    rp_list = chk["remove_paths"]
                    if not isinstance(rp_list, list):
                        raise ConfigError(f"{cctx}.remove_paths: phải là danh sách.")
                    for rpath in rp_list:
                        _validate_safe_rel_segments(rpath, f"{cctx}.remove_paths")
                if "env" in chk and not isinstance(chk["env"], dict):
                    raise ConfigError(f"{cctx}.env: phải là object.")
                if "timeout" in chk:
                    tval = chk["timeout"]
                    if isinstance(tval, bool) or not isinstance(tval, (int, float)) or tval <= 0:
                        raise ConfigError(f"{cctx}.timeout: phải là số dương.")
                if "unavailable_exit_codes" in chk:
                    ucodes = chk["unavailable_exit_codes"]
                    if not isinstance(ucodes, list) or not all(
                        isinstance(u, int) and not isinstance(u, bool) for u in ucodes
                    ):
                        raise ConfigError(f"{cctx}.unavailable_exit_codes: phải là danh sách số nguyên.")
                if "expect" in chk:
                    exp_mode = chk["expect"]
                    if not isinstance(exp_mode, str) or exp_mode not in ("pass", "fail"):
                        raise ConfigError(
                            f"{cctx}.expect: giá trị không hợp lệ {exp_mode!r} (chỉ chấp nhận 'pass' hoặc 'fail')."
                        )

            elif ctype == "file_glob":
                _validate_safe_rel_segments(chk.get("glob"), f"{cctx}.glob")
                if "regex" in chk:
                    _compile_regex(chk["regex"], f"{cctx}.regex")

            elif ctype == "result_regex":
                _compile_regex(chk.get("regex"), f"{cctx}.regex")

    return data, skill_dir


def resolve_claude_bin() -> str:
    """Tìm đường dẫn thực thi CLI claude (ưu tiên SKILL_EVAL_CLAUDE_BIN để phục vụ test cô lập)."""
    override = os.environ.get("SKILL_EVAL_CLAUDE_BIN", "").strip()
    if override:
        return override
    found = shutil.which("claude")
    if not found:
        raise ConfigError("Không tìm thấy CLI 'claude' trong PATH và chưa đặt SKILL_EVAL_CLAUDE_BIN.")
    return found


def _git_output(cwd: str, args: list[str]) -> str | None:
    """Chạy lệnh git chỉ-đọc để dò gốc repo hoặc git-common-dir của phiên gọi."""
    try:
        res = subprocess.run(
            ["git"] + args,
            cwd=cwd,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if res.returncode != 0:
        return None
    out = res.stdout.strip()
    return out if out else None


def _read_account_from_settings(repo_root: str) -> tuple[bool, Any]:
    """Đọc khoá 'account' từ <repo_root>/.claude/settings.local.json nếu file tồn tại."""
    spath = os.path.join(repo_root, ".claude", "settings.local.json")
    if not os.path.isfile(spath):
        return False, None
    try:
        with open(spath, encoding="utf-8") as fh:
            obj = json.load(fh)
    except (OSError, ValueError) as exc:
        sys.stderr.write(
            f"Cảnh báo: không đọc được JSON tại '{spath}' ({type(exc).__name__}); bỏ qua.\n"
        )
        return False, None
    if isinstance(obj, dict) and "account" in obj:
        return True, obj["account"]
    return False, None


def resolve_claude_config_dir(explicit_config_dir: str | None, caller_cwd: str) -> str | None:
    """Giải thư mục CLAUDE_CONFIG_DIR theo thứ tự: --config-dir -> toplevel settings -> git-common-dir -> env."""
    if explicit_config_dir:
        return os.path.abspath(explicit_config_dir)

    candidates: list[str] = []
    top = _git_output(caller_cwd, ["rev-parse", "--show-toplevel"])
    if top:
        candidates.append(top)

    common = _git_output(caller_cwd, ["rev-parse", "--path-format=absolute", "--git-common-dir"])
    if not common:
        rel_common = _git_output(caller_cwd, ["rev-parse", "--git-common-dir"])
        if rel_common:
            common = os.path.abspath(os.path.join(caller_cwd, rel_common))
    if common:
        main_root = os.path.dirname(common.rstrip("/\\"))
        if main_root and main_root not in candidates:
            candidates.append(main_root)

    for root in candidates:
        has_key, acct = _read_account_from_settings(root)
        if not has_key:
            continue
        if not isinstance(acct, str) or not ACCOUNT_RE.fullmatch(acct):
            acct_info = f"type=str, len={len(acct)}" if isinstance(acct, str) else f"type={type(acct).__name__}"
            sys.stderr.write(
                f"Cảnh báo: bỏ qua giá trị account không hợp lệ trong '{os.path.join(root, '.claude', 'settings.local.json')}' ({acct_info}).\n"
            )
            continue
        cand_dir = os.path.abspath(os.path.expanduser(f"~/.claude-{acct}"))
        if os.path.isdir(cand_dir):
            return cand_dir
        break

    return os.environ.get("CLAUDE_CONFIG_DIR")


def run_process_bounded(
    argv: list[str],
    cwd: str,
    env: dict[str, str],
    timeout_sec: float,
) -> tuple[int, str, str, bool, float]:
    """Chạy tiến trình con trong process group mới, tự động killpg kèm fallback proc.kill khi quá giờ."""
    t0 = time.monotonic()
    proc = subprocess.Popen(
        argv,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    timed_out = False
    try:
        try:
            stdout_s, stderr_s = proc.communicate(timeout=timeout_sec)
            rc = proc.returncode if proc.returncode is not None else 1
        except subprocess.TimeoutExpired as exc:
            timed_out = True
            # Theo INSTINCT-056: macOS có thể ném PermissionError khi gửi tín hiệu cho process group
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError, OSError):
                try:
                    proc.kill()
                except (ProcessLookupError, OSError):
                    pass
            try:
                rest_out, rest_err = proc.communicate(timeout=5)
                stdout_s = _to_str(rest_out)
                stderr_s = _to_str(rest_err)
            except subprocess.TimeoutExpired as exc2:
                try:
                    proc.kill()
                except (ProcessLookupError, OSError):
                    pass
                stdout_s = _to_str(exc2.stdout if exc2.stdout is not None else exc.stdout)
                stderr_s = _to_str(exc2.stderr if exc2.stderr is not None else exc.stderr)
            rc = -9
    finally:
        for stream in (proc.stdout, proc.stderr):
            if stream is not None:
                try:
                    stream.close()
                except OSError:
                    pass
        if proc.poll() is None:
            try:
                proc.wait(timeout=1)
            except subprocess.TimeoutExpired:
                pass
    elapsed = time.monotonic() - t0
    return rc, stdout_s, stderr_s, timed_out, elapsed


def compute_tokens(usage: Any) -> int:
    """Tính tổng token từ trường usage của sự kiện result."""
    if not isinstance(usage, dict):
        return 0
    inp = usage.get("input_tokens", usage.get("input", 0)) or 0
    out = usage.get("output_tokens", usage.get("output", 0)) or 0
    cc = usage.get("cache_creation_input_tokens", usage.get("cache_creation", 0)) or 0
    cr = usage.get("cache_read_input_tokens", usage.get("cache_read", 0)) or 0
    total = int(inp) + int(out) + int(cc) + int(cr)
    if total == 0 and isinstance(usage.get("total_tokens"), (int, float)):
        return int(usage["total_tokens"])
    return total


def normalize_tool_path(raw_path: str, real_project_dir: str) -> tuple[str, bool]:
    """Chuẩn hoá file_path của tool_use thành tương đối so với project/ để tránh khớp nhầm tên thư mục cha."""
    cand = raw_path if os.path.isabs(raw_path) else os.path.join(real_project_dir, raw_path)
    real_cand = os.path.realpath(cand)
    if real_cand == real_project_dir:
        return ".", False
    if real_cand.startswith(real_project_dir + os.sep):
        rel = os.path.relpath(real_cand, real_project_dir).replace(os.sep, "/")
        return rel, False
    return real_cand, True


def parse_stream_json(stdout_text: str, skill_name: str, project_dir: str) -> dict[str, Any]:
    """Phân tích luồng sự kiện stream-json của CLI claude theo từng dòng (chịu lỗi dòng hỏng)."""
    real_proj = os.path.realpath(project_dir)
    bad_lines = 0
    init_seen = False
    skill_listed = False
    tool_events: list[dict[str, Any]] = []
    tool_calls: dict[str, int] = {}
    tool_errors = 0

    result_seen = False
    total_cost_usd = 0.0
    num_turns = 0
    duration_ms: int | float | None = None
    is_error = False
    subtype: str | None = None
    usage: dict[str, Any] = {}
    result_text = ""

    for raw_line in stdout_text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        try:
            ev = json.loads(line)
        except Exception:
            bad_lines += 1
            continue
        if not isinstance(ev, dict):
            bad_lines += 1
            continue

        ev_type = ev.get("type")
        if ev_type == "system" and ev.get("subtype") == "init":
            init_seen = True
            listed_names: set[str] = set()
            for item in ev.get("skills") or []:
                if isinstance(item, str):
                    listed_names.add(item)
                elif isinstance(item, dict) and isinstance(item.get("name"), str):
                    listed_names.add(item["name"])
            if skill_name in listed_names:
                skill_listed = True

        elif ev_type == "assistant":
            msg = ev.get("message")
            blocks = msg.get("content") if isinstance(msg, dict) else None
            if isinstance(blocks, list):
                for blk in blocks:
                    if not isinstance(blk, dict) or blk.get("type") != "tool_use":
                        continue
                    tname = str(blk.get("name") or "")
                    tool_calls[tname] = tool_calls.get(tname, 0) + 1
                    inp = blk.get("input") if isinstance(blk.get("input"), dict) else {}
                    tev: dict[str, Any] = {"name": tname}
                    raw_fp = inp.get("file_path")
                    if raw_fp is None and tname in ("Read", "Edit", "Write", "MultiEdit"):
                        raw_fp = inp.get("path")
                    if isinstance(raw_fp, str) and raw_fp:
                        norm_fp, outside = normalize_tool_path(raw_fp, real_proj)
                        tev["file_path"] = norm_fp
                        if outside:
                            tev["outside"] = True
                    if isinstance(inp.get("command"), str):
                        tev["command"] = inp["command"]
                    tool_events.append(tev)

        elif ev_type == "user":
            msg = ev.get("message")
            blocks = msg.get("content") if isinstance(msg, dict) else None
            if isinstance(blocks, list):
                for blk in blocks:
                    if isinstance(blk, dict) and blk.get("type") == "tool_result" and blk.get("is_error") is True:
                        tool_errors += 1

        elif ev_type == "result":
            result_seen = True
            if isinstance(ev.get("total_cost_usd"), (int, float)):
                total_cost_usd = float(ev["total_cost_usd"])
            if isinstance(ev.get("num_turns"), int):
                num_turns = ev["num_turns"]
            if isinstance(ev.get("duration_ms"), (int, float)):
                duration_ms = ev["duration_ms"]
            is_error = bool(ev.get("is_error", False))
            subtype = ev.get("subtype") if isinstance(ev.get("subtype"), str) else None
            usage = ev.get("usage") if isinstance(ev.get("usage"), dict) else {}
            if ev.get("result") is not None:
                result_text = str(ev.get("result"))

    return {
        "bad_lines": bad_lines,
        "init_seen": init_seen,
        "skill_listed": skill_listed,
        "tool_events": tool_events,
        "tool_calls": tool_calls,
        "tool_errors": tool_errors,
        "result_seen": result_seen,
        "total_cost_usd": total_cost_usd,
        "num_turns": num_turns,
        "duration_ms": duration_ms,
        "is_error": is_error,
        "subtype": subtype,
        "usage": usage,
        "tokens": compute_tokens(usage),
        "result": result_text,
    }


def _copytree_contents(src_dir: str, dst_dir: str) -> None:
    """Chép toàn bộ cây con từ src_dir vào dst_dir dùng shutil.copy (không chép cờ BSD uchg và bỏ qua __pycache__/*.pyc)."""
    os.makedirs(dst_dir, exist_ok=True)
    for item in os.listdir(src_dir):
        if item == "__pycache__" or item.endswith(".pyc"):
            continue
        s_item = os.path.join(src_dir, item)
        d_item = os.path.join(dst_dir, item)
        if os.path.isdir(s_item) and not os.path.islink(s_item):
            shutil.copytree(
                s_item,
                d_item,
                symlinks=True,
                dirs_exist_ok=True,
                copy_function=shutil.copy,
                ignore=shutil.ignore_patterns("__pycache__", "*.pyc"),
            )
        else:
            if os.path.lexists(d_item):
                os.unlink(d_item)
            if os.path.islink(s_item):
                os.symlink(os.readlink(s_item), d_item)
            else:
                shutil.copy(s_item, d_item)


def _copy_skill_without_evals(skill_dir: str, dst_skill_dir: str) -> None:
    """Chép thư mục skill vào project/.claude/skills/<NAME>/ nhưng loại bỏ evals/ để che oracle."""
    abs_root = os.path.abspath(skill_dir)

    def _ignore(cur_dir: str, names: list[str]) -> set[str]:
        ignored = {"__pycache__"}
        if os.path.abspath(cur_dir) == abs_root and "evals" in names:
            ignored.add("evals")
        return ignored

    shutil.copytree(
        skill_dir,
        dst_skill_dir,
        symlinks=True,
        ignore=_ignore,
        dirs_exist_ok=True,
        copy_function=shutil.copy,
    )


def _init_git_repo(project_dir: str) -> None:
    """Khởi tạo kho git cục bộ sạch trong project/ để CLI claude nhận diện ranh giới dự án."""
    clean_env = {k: v for k, v in os.environ.items() if k not in GIT_ENV_SCRUB}
    res = subprocess.run(
        ["git", "init", "-q"],
        cwd=project_dir,
        env=clean_env,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        timeout=15,
    )
    if res.returncode != 0:
        raise RuntimeError(f"git init thất bại trong '{project_dir}': {res.stderr.strip()}")


def _mask_argv(argv: list[str], cfg_dir: str | None) -> list[str]:
    """Che đường dẫn đầy đủ của thư mục cấu hình trong argv nếu xuất hiện."""
    if not cfg_dir:
        return list(argv)
    bname = os.path.basename(os.path.normpath(cfg_dir))
    return [arg.replace(cfg_dir, bname) for arg in argv]


def build_run_argv(
    claude_bin: str,
    skill_name: str,
    eval_item: dict[str, Any],
    config: str,
    model: str,
    budget_usd: float,
) -> list[str]:
    """Tạo mảng đối số dòng lệnh chuẩn cho một ô thực nghiệm run."""
    raw_prompt = eval_item["prompt"]
    prompt = f"/{skill_name} {raw_prompt}" if config == "with_skill" else raw_prompt
    allowed_raw = eval_item.get("allowed_tools")
    allowed_str = " ".join(split_tool_specs(allowed_raw)) if allowed_raw else DEFAULT_ALLOWED_TOOLS
    disallowed_str = merge_disallowed_tools(eval_item.get("disallowed_tools"))
    argv = [
        claude_bin,
        "-p",
        prompt,
        "--output-format",
        "stream-json",
        "--verbose",
        "--setting-sources",
        "project",
        "--model",
        str(model),
        "--max-budget-usd",
        str(budget_usd),
        "--no-session-persistence",
        "--permission-mode",
        "acceptEdits",
        "--permission-prompts",
        "none",
        "--allowedTools",
        allowed_str,
        "--disallowedTools",
        disallowed_str,
    ]
    return argv


def execute_single_cell(task: dict[str, Any]) -> dict[str, Any]:
    """Thiết lập thư mục project/, chạy CLI claude cho một ô và lưu run.json + transcript."""
    cell_dir = task["cell_dir"]
    run_json_path = os.path.join(cell_dir, "run.json")
    if os.path.isfile(run_json_path) and not task["force"]:
        with open(run_json_path, encoding="utf-8") as fh:
            existing = json.load(fh)
        existing["_skipped"] = True
        return existing

    if os.path.exists(cell_dir):
        shutil.rmtree(cell_dir)
    project_dir = os.path.join(cell_dir, "project")
    os.makedirs(project_dir, exist_ok=True)
    _init_git_repo(project_dir)

    skill_dir = task["skill_dir"]
    skill_name = task["skill_name"]
    ev = task["eval_item"]
    config = task["config"]

    if ev.get("files_dir"):
        src_fdir = resolve_skill_relpath(skill_dir, ev["files_dir"], "files_dir", expect_dir=True)
        _copytree_contents(src_fdir, project_dir)

    for frel in ev.get("files") or []:
        src_file = resolve_skill_relpath(skill_dir, frel, "files", expect_dir=False)
        dst_file = os.path.join(project_dir, os.path.basename(src_file))
        if os.path.lexists(dst_file):
            os.unlink(dst_file)
        shutil.copy(src_file, dst_file)

    if config == "with_skill":
        dst_skill = os.path.join(project_dir, ".claude", "skills", skill_name)
        _copy_skill_without_evals(skill_dir, dst_skill)

    child_env = {k: v for k, v in os.environ.items() if k not in GIT_ENV_SCRUB}
    cfg_dir = task["cfg_dir"]
    if cfg_dir:
        child_env["CLAUDE_CONFIG_DIR"] = cfg_dir
    else:
        child_env.pop("CLAUDE_CONFIG_DIR", None)

    argv = task["argv"]
    rc, stdout_s, stderr_s, timed_out, wall_sec = run_process_bounded(
        argv=argv,
        cwd=project_dir,
        env=child_env,
        timeout_sec=task["timeout"],
    )

    with open(os.path.join(cell_dir, "transcript.jsonl"), "w", encoding="utf-8") as fh:
        fh.write(stdout_s)
    with open(os.path.join(cell_dir, "stderr.txt"), "w", encoding="utf-8") as fh:
        fh.write(stderr_s)

    parsed = parse_stream_json(stdout_s, skill_name, project_dir)
    leak = bool(config == "without_skill" and parsed["skill_listed"])
    skill_missing = bool(config == "with_skill" and not timed_out and not parsed["skill_listed"])
    valid = bool(
        not timed_out
        and rc == 0
        and parsed["result_seen"]
        and not parsed["is_error"]
        and not leak
        and not skill_missing
    )

    dur_ms = parsed["duration_ms"]
    time_seconds = round(dur_ms / 1000.0, 3) if isinstance(dur_ms, (int, float)) else round(wall_sec, 3)
    err_count = parsed["tool_errors"] + (1 if (timed_out or rc != 0 or parsed["is_error"]) else 0)
    cfg_basename = os.path.basename(os.path.normpath(cfg_dir)) if cfg_dir else None
    eval_name = ev.get("name") or ev.get("eval_name") or f"eval-{ev['id']}"

    run_record = {
        "skill_name": skill_name,
        "eval_id": ev["id"],
        "eval_name": str(eval_name),
        "configuration": config,
        "run_number": task["run_number"],
        "model": task["model"],
        "argv": _mask_argv(argv, cfg_dir),
        "claude_config_dir": cfg_basename,
        "returncode": rc,
        "timeout": timed_out,
        "wall_time_seconds": round(wall_sec, 3),
        "duration_ms": dur_ms,
        "time_seconds": time_seconds,
        "num_turns": parsed["num_turns"],
        "total_cost_usd": parsed["total_cost_usd"],
        "usage": parsed["usage"],
        "tokens": parsed["tokens"],
        "is_error": parsed["is_error"],
        "subtype": parsed["subtype"],
        "result": parsed["result"],
        "skill_listed": parsed["skill_listed"],
        "leak": leak,
        "skill_missing": skill_missing,
        "valid": valid,
        "bad_lines": parsed["bad_lines"],
        "tool_events": parsed["tool_events"],
        "tool_calls": parsed["tool_calls"],
        "errors": err_count,
    }
    with open(run_json_path, "w", encoding="utf-8") as fh:
        json.dump(run_record, fh, indent=2, ensure_ascii=False)
    return run_record


def cmd_run(args: argparse.Namespace) -> int:
    """Thực thi lệnh con `run`."""
    if args.runs < 1:
        raise ConfigError("--runs phải >= 1.")
    if args.jobs < 1:
        raise ConfigError("--jobs phải >= 1.")
    if args.timeout <= 0:
        raise ConfigError("--timeout phải > 0.")
    if args.budget_usd <= 0:
        raise ConfigError("--budget-usd phải > 0.")

    configs = [c.strip() for c in args.configs.split(",") if c.strip()]
    if not configs or any(c not in VALID_CONFIGS for c in configs):
        raise ConfigError(f"--configs không hợp lệ '{args.configs}' (chỉ nhận {VALID_CONFIGS}).")

    # Chặn nhiễm trước khi tạo bất kỳ thư mục nào và ngay cả ở chế độ --dry-run
    check_workspace_clean(args.workspace)
    evals_data, skill_dir = validate_evals_file(args.evals, expected_skill=args.skill)
    skill_name = evals_data["skill_name"]

    selected_ids: set[int] | None = None
    if args.eval_ids:
        try:
            selected_ids = {int(x.strip()) for x in args.eval_ids.split(",") if x.strip()}
        except ValueError as exc:
            raise ConfigError(f"--eval-ids phải là danh sách số nguyên phân tách bởi dấu phẩy: {exc}") from exc

    eval_items = [
        ev for ev in evals_data["evals"] if selected_ids is None or ev["id"] in selected_ids
    ]
    if not eval_items:
        raise ConfigError("Không có eval nào khớp --eval-ids đã chọn.")

    claude_bin = resolve_claude_bin()
    caller_cwd = os.getcwd()
    cfg_dir = resolve_claude_config_dir(args.config_dir, caller_cwd)
    cfg_label = os.path.basename(os.path.normpath(cfg_dir)) if cfg_dir else "(default)"

    tasks: list[dict[str, Any]] = []
    ws_abs = os.path.abspath(args.workspace)
    for ev in eval_items:
        for cfg in configs:
            for rnum in range(1, args.runs + 1):
                cell_dir = os.path.join(ws_abs, skill_name, f"eval-{ev['id']}", cfg, f"run-{rnum}")
                argv = build_run_argv(claude_bin, skill_name, ev, cfg, args.model, args.budget_usd)
                tasks.append(
                    {
                        "cell_dir": cell_dir,
                        "skill_dir": skill_dir,
                        "skill_name": skill_name,
                        "eval_item": ev,
                        "config": cfg,
                        "run_number": rnum,
                        "model": args.model,
                        "budget_usd": args.budget_usd,
                        "timeout": args.timeout,
                        "force": args.force,
                        "cfg_dir": cfg_dir,
                        "argv": argv,
                    }
                )

    if args.dry_run:
        print(f"[dry-run] skill={skill_name} cells={len(tasks)} config_dir={cfg_label}")
        for t in tasks:
            masked = _mask_argv(t["argv"], cfg_dir)
            print(f"  {t['cell_dir']} -> {masked}")
        return 0

    os.makedirs(ws_abs, exist_ok=True)
    results: list[dict[str, Any]] = []
    if args.jobs == 1:
        for t in tasks:
            results.append(execute_single_cell(t))
    else:
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            futs = [pool.submit(execute_single_cell, t) for t in tasks]
            for fut in as_completed(futs):
                results.append(fut.result())

    valid_n = sum(1 for r in results if r.get("valid"))
    leak_n = sum(1 for r in results if r.get("leak"))
    timeout_n = sum(1 for r in results if r.get("timeout"))
    skip_n = sum(1 for r in results if r.get("_skipped"))
    print(
        f"[run] skill={skill_name} total={len(results)} valid={valid_n} "
        f"skipped={skip_n} leaks={leak_n} timeouts={timeout_n} config_dir={cfg_label}"
    )
    return 0 if valid_n == len(results) else 1


def _event_matches(ev: dict[str, Any], spec: dict[str, Any]) -> bool:
    """Kiểm tra một sự kiện tool_use đã chuẩn hoá có khớp điều kiện first/before của tool_order không."""
    tname = ev.get("name") or ""
    if not re.fullmatch(spec["tool"], tname):
        return False
    if spec.get("command_regex") is not None:
        cmd = ev.get("command")
        if not isinstance(cmd, str) or not re.search(spec["command_regex"], cmd):
            return False
    if spec.get("command_not_regex") is not None:
        cmd = ev.get("command")
        if isinstance(cmd, str) and re.search(spec["command_not_regex"], cmd):
            return False
    if spec.get("path_regex") is not None:
        fp = ev.get("file_path")
        if not isinstance(fp, str) or not re.search(spec["path_regex"], fp):
            return False
    if spec.get("path_not_regex") is not None:
        fp = ev.get("file_path") or ""
        if re.search(spec["path_not_regex"], fp):
            return False
    return True


def _eval_tool_order(chk: dict[str, Any], run_data: dict[str, Any]) -> dict[str, Any]:
    """Chấm check kiểu tool_order trên danh sách tool_events đã chuẩn hoá đường dẫn."""
    events = run_data.get("tool_events") or []
    first_idx: int | None = None
    before_idx: int | None = None
    for idx, ev in enumerate(events):
        if first_idx is None and _event_matches(ev, chk["first"]):
            first_idx = idx
        if before_idx is None and _event_matches(ev, chk["before"]):
            before_idx = idx

    if before_idx is None:
        passed = bool(chk.get("pass_if_before_absent", False))
        evidence = (
            f"Không có sự kiện khớp 'before'; pass_if_before_absent={passed} (first_idx={first_idx})."
        )
    elif first_idx is not None and first_idx < before_idx:
        passed = True
        evidence = (
            f"Đạt: sự kiện 'first' tại bước {first_idx} ({events[first_idx]}) chạy trước "
            f"'before' tại bước {before_idx} ({events[before_idx]})."
        )
    else:
        passed = False
        evidence = (
            f"Trượt: 'before' xuất hiện tại bước {before_idx} ({events[before_idx]}), "
            f"trong khi 'first' ở bước {first_idx}."
        )
    return {
        "id": chk["id"],
        "text": chk["text"],
        "passed": passed,
        "unavailable": False,
        "evidence": evidence,
    }


def _safe_remove_in_copy(copy_root: str, rel_path: str) -> None:
    """Xoá an toàn đường dẫn tương đối bên trong bản sao chấm điểm tạm thời."""
    parts = _validate_safe_rel_segments(rel_path, "remove_paths")
    real_root = os.path.realpath(copy_root)
    cur = copy_root
    for seg in parts[:-1]:
        cur = os.path.join(cur, seg)
        if not os.path.lexists(cur):
            return
        if os.path.islink(cur):
            return
        real_cur = os.path.realpath(cur)
        if real_cur != real_root and not real_cur.startswith(real_root + os.sep):
            return
    target = os.path.join(cur, parts[-1])
    if not os.path.lexists(target):
        return
    if os.path.islink(target) or os.path.isfile(target):
        os.unlink(target)
    elif os.path.isdir(target):
        shutil.rmtree(target)


def _eval_command_check(chk: dict[str, Any], project_dir: str, skill_dir: str) -> dict[str, Any]:
    """Chấm check kiểu command trên bản sao tạm của project/, kèm chép đè oracle_files và xoá remove_paths."""
    real_skill_dir = os.path.realpath(skill_dir)
    resolved_cmd = [arg.replace("{skill_dir}", real_skill_dir) for arg in chk["cmd"]]
    raw_unavail = chk.get("unavailable_exit_codes")
    unavail_codes = set(raw_unavail if raw_unavail is not None else [127])
    raw_timeout = chk.get("timeout")
    timeout_sec = float(raw_timeout if raw_timeout is not None else 120)
    raw_expect = chk.get("expect")
    expect_mode = raw_expect if raw_expect is not None else "pass"

    tmp_parent = tempfile.mkdtemp(prefix="skill_eval_grade_")
    try:
        tmp_proj = os.path.join(tmp_parent, "project")
        # Loại bỏ __pycache__/*.pyc để việc chép đè oracle_files cùng giây/cùng kích thước (PEP 552) luôn dịch lại nguồn mới.
        shutil.copytree(
            project_dir,
            tmp_proj,
            symlinks=True,
            copy_function=shutil.copy,
            ignore=shutil.ignore_patterns("__pycache__", "*.pyc"),
        )

        raw_rm = chk.get("remove_paths")
        for rpath in (raw_rm if raw_rm is not None else []):
            _safe_remove_in_copy(tmp_proj, rpath)

        raw_of = chk.get("oracle_files")
        for orel in (raw_of if raw_of is not None else []):
            src_oracle = resolve_skill_relpath(skill_dir, orel, "oracle_files", expect_dir=False)
            dst_oracle = os.path.join(tmp_proj, os.path.basename(src_oracle))
            if os.path.islink(dst_oracle) or os.path.isfile(dst_oracle):
                os.unlink(dst_oracle)
            elif os.path.isdir(dst_oracle):
                shutil.rmtree(dst_oracle)
            shutil.copy(src_oracle, dst_oracle)

        cmd_env = {k: v for k, v in os.environ.items() if k not in GIT_ENV_SCRUB}
        raw_env = chk.get("env")
        for ek, ev in (raw_env if raw_env is not None else {}).items():
            cmd_env[str(ek)] = str(ev)

        try:
            rc, out_s, err_s, timed_out, _ = run_process_bounded(
                argv=resolved_cmd,
                cwd=tmp_proj,
                env=cmd_env,
                timeout_sec=timeout_sec,
            )
        except FileNotFoundError:
            return {
                "id": chk["id"],
                "text": chk["text"],
                "passed": None,
                "unavailable": True,
                "evidence": f"Không tìm thấy lệnh thực thi: {resolved_cmd[0]}",
            }

        combined = (out_s + ("\n" if out_s and err_s else "") + err_s).strip()
        tail_lines = "\n".join(combined.splitlines()[-20:])

        if timed_out:
            return {
                "id": chk["id"],
                "text": chk["text"],
                "passed": False,
                "unavailable": False,
                "evidence": f"Quá thời gian ({timeout_sec}s).\n{tail_lines}".strip(),
            }
        if rc in unavail_codes:
            return {
                "id": chk["id"],
                "text": chk["text"],
                "passed": None,
                "unavailable": True,
                "evidence": f"exit_code={rc} (unavailable)\n{tail_lines}".strip(),
            }
        passed = (rc != 0) if expect_mode == "fail" else (rc == 0)
        return {
            "id": chk["id"],
            "text": chk["text"],
            "passed": passed,
            "unavailable": False,
            "evidence": f"exit_code={rc} (expect={expect_mode})\n{tail_lines}".strip(),
        }
    finally:
        shutil.rmtree(tmp_parent, ignore_errors=True)


def _eval_file_glob(chk: dict[str, Any], project_dir: str) -> dict[str, Any]:
    """Chấm check kiểu file_glob bên trong project/ (bỏ qua .git và .claude để tránh khớp nhầm file hệ thống)."""
    real_proj = os.path.realpath(project_dir)
    proj_path = pathlib.Path(project_dir)
    matched_rels: list[str] = []
    for candidate in sorted(proj_path.glob(chk["glob"])):
        try:
            rel_parts = candidate.relative_to(proj_path).parts
        except ValueError:
            continue
        if not rel_parts or rel_parts[0] in (".git", ".claude"):
            continue
        full_p = str(candidate)
        if not os.path.isfile(full_p):
            continue
        real_f = os.path.realpath(full_p)
        if real_f != real_proj and not real_f.startswith(real_proj + os.sep):
            continue
        matched_rels.append("/".join(rel_parts))

    if not matched_rels:
        return {
            "id": chk["id"],
            "text": chk["text"],
            "passed": False,
            "unavailable": False,
            "evidence": f"Không có file nào khớp glob '{chk['glob']}'.",
        }

    rx_pat = chk.get("regex")
    if rx_pat is None:
        return {
            "id": chk["id"],
            "text": chk["text"],
            "passed": True,
            "unavailable": False,
            "evidence": f"Khớp file: {', '.join(matched_rels[:10])}",
        }

    rx = re.compile(rx_pat, re.M)
    for rel_f in matched_rels:
        fpath = os.path.join(project_dir, rel_f)
        if not os.path.isfile(fpath):
            continue
        with open(fpath, encoding="utf-8", errors="replace") as fh:
            content = fh.read()
        m = rx.search(content)
        if m:
            snippet = m.group(0)[:120].replace("\n", " ")
            return {
                "id": chk["id"],
                "text": chk["text"],
                "passed": True,
                "unavailable": False,
                "evidence": f"Khớp regex trong '{rel_f}': {snippet!r}",
            }

    return {
        "id": chk["id"],
        "text": chk["text"],
        "passed": False,
        "unavailable": False,
        "evidence": f"Các file {matched_rels[:5]} tồn tại nhưng không khớp regex '{rx_pat}'.",
    }


def _eval_result_regex(chk: dict[str, Any], run_data: dict[str, Any]) -> dict[str, Any]:
    """Chấm check kiểu result_regex trên chuỗi result cuối cùng của phiên chạy."""
    res_text = str(run_data.get("result") or "")
    m = re.search(chk["regex"], res_text)
    if m:
        return {
            "id": chk["id"],
            "text": chk["text"],
            "passed": True,
            "unavailable": False,
            "evidence": f"Khớp result: {m.group(0)[:120]!r}",
        }
    return {
        "id": chk["id"],
        "text": chk["text"],
        "passed": False,
        "unavailable": False,
        "evidence": f"Chuỗi result không khớp regex '{chk['regex']}'.",
    }


def cmd_grade(args: argparse.Namespace) -> int:
    """Thực thi lệnh con `grade`: chấm mọi ô hợp lệ trong workspace và xuất grading.json."""
    evals_data, skill_dir = validate_evals_file(args.evals, expected_skill=args.skill)
    skill_name = evals_data["skill_name"]
    eval_map = {ev["id"]: ev for ev in evals_data["evals"]}

    skill_ws = os.path.join(os.path.abspath(args.workspace), skill_name)
    if not os.path.isdir(skill_ws):
        raise ConfigError(f"Không tìm thấy dữ liệu skill trong workspace: '{skill_ws}'.")

    graded_cells = 0
    skipped_invalid = 0

    for eid, ev in sorted(eval_map.items()):
        eval_dir = os.path.join(skill_ws, f"eval-{eid}")
        if not os.path.isdir(eval_dir):
            continue
        for cfg in VALID_CONFIGS:
            cfg_dir = os.path.join(eval_dir, cfg)
            if not os.path.isdir(cfg_dir):
                continue
            for entry in sorted(os.listdir(cfg_dir)):
                if not entry.startswith("run-"):
                    continue
                cell_dir = os.path.join(cfg_dir, entry)
                run_json = os.path.join(cell_dir, "run.json")
                project_dir = os.path.join(cell_dir, "project")
                if not os.path.isfile(run_json):
                    continue
                with open(run_json, encoding="utf-8") as fh:
                    run_data = json.load(fh)
                if not run_data.get("valid", False):
                    skipped_invalid += 1
                    continue

                t_start = time.monotonic()
                exp_results: list[dict[str, Any]] = []
                for chk in ev["checks"]:
                    ctype = chk["type"]
                    if ctype == "tool_order":
                        exp_results.append(_eval_tool_order(chk, run_data))
                    elif ctype == "command":
                        exp_results.append(_eval_command_check(chk, project_dir, skill_dir))
                    elif ctype == "file_glob":
                        exp_results.append(_eval_file_glob(chk, project_dir))
                    elif ctype == "result_regex":
                        exp_results.append(_eval_result_regex(chk, run_data))

                passed_cnt = sum(1 for r in exp_results if r["passed"] is True)
                failed_cnt = sum(1 for r in exp_results if r["passed"] is False)
                unavail_cnt = sum(1 for r in exp_results if r["passed"] is None)
                total_cnt = passed_cnt + failed_cnt
                pass_rate = round(passed_cnt / total_cnt, 4) if total_cnt > 0 else None
                grader_sec = round(time.monotonic() - t_start, 3)

                notes: list[str] = []
                raw_exps = ev.get("expectations") or []
                if raw_exps:
                    notes.append(
                        f"Giữ nguyên {len(raw_exps)} expectations câu chữ (không chấm tự động bằng LLM trong pilot)."
                    )
                if unavail_cnt > 0:
                    notes.append(f"{unavail_cnt} check ở trạng thái unavailable được loại khỏi mẫu số.")

                tool_calls = run_data.get("tool_calls") or {}
                exec_sec = float(run_data.get("time_seconds") or 0.0)
                grading_payload = {
                    "expectations": exp_results,
                    "summary": {
                        "passed": passed_cnt,
                        "failed": failed_cnt,
                        "unavailable": unavail_cnt,
                        "total": total_cnt,
                        "pass_rate": pass_rate,
                    },
                    "execution_metrics": {
                        "tool_calls": tool_calls,
                        "total_tool_calls": sum(int(v) for v in tool_calls.values()),
                        "total_steps": int(run_data.get("num_turns") or 0),
                        "errors_encountered": int(run_data.get("errors") or 0),
                    },
                    "timing": {
                        "executor_duration_seconds": exec_sec,
                        "grader_duration_seconds": grader_sec,
                        "total_duration_seconds": round(exec_sec + grader_sec, 3),
                    },
                    "notes": notes,
                }
                with open(os.path.join(cell_dir, "grading.json"), "w", encoding="utf-8") as fh:
                    json.dump(grading_payload, fh, indent=2, ensure_ascii=False)
                graded_cells += 1

    print(f"[grade] skill={skill_name} graded={graded_cells} skipped_invalid={skipped_invalid}")
    return 0


def _calc_stats(values: list[float], ndigits: int = 4) -> tuple[dict[str, float | None], float | None]:
    """Tính mean, pstdev, min, max an toàn trên danh sách đã lọc None (trả cả mean gốc chưa làm tròn)."""
    if not values:
        return {"mean": None, "stddev": None, "min": None, "max": None}, None
    raw_mean = statistics.mean(values)
    raw_sd = statistics.pstdev(values) if len(values) >= 2 else 0.0
    return (
        {
            "mean": round(raw_mean, ndigits),
            "stddev": round(raw_sd, ndigits),
            "min": round(min(values), ndigits),
            "max": round(max(values), ndigits),
        },
        raw_mean,
    )


def _render_benchmark_md(bench: dict[str, Any]) -> str:
    """Sinh báo cáo Markdown tóm tắt từ dữ liệu benchmark.json."""
    meta = bench["metadata"]
    rs = bench["run_summary"]
    lines = [
        f"# Benchmark: {meta['skill_name']}",
        "",
        f"- Timestamp: `{meta['timestamp']}`",
        f"- Model: `{meta['executor_model']}`",
        f"- Evals: `{meta['evals_run']}`",
        f"- Runs per configuration: `{meta['runs_per_configuration']}`",
        "",
        "## Summary",
        "",
        "| Metric | with_skill (mean ± sd) | without_skill (mean ± sd) | Delta |",
        "|---|---|---|---|",
    ]
    for metric in ("pass_rate", "time_seconds", "tokens"):
        w = rs["with_skill"][metric]
        wo = rs["without_skill"][metric]
        w_str = f"{w['mean']} ± {w['stddev']}" if w["mean"] is not None else "null"
        wo_str = f"{wo['mean']} ± {wo['stddev']}" if wo["mean"] is not None else "null"
        d_str = rs["delta"].get(metric) if rs["delta"].get(metric) is not None else "null"
        lines.append(f"| `{metric}` | {w_str} | {wo_str} | `{d_str}` |")

    if bench.get("notes"):
        lines.extend(["", "## Notes", ""])
        for n in bench["notes"]:
            lines.append(f"- {n}")
    return "\n".join(lines) + "\n"


def cmd_aggregate(args: argparse.Namespace) -> int:
    """Thực thi lệnh con `aggregate`: tổng hợp benchmark.json và benchmark.md đúng schema skill-creator."""
    skill_name = args.skill
    skill_ws = os.path.join(os.path.abspath(args.workspace), skill_name)
    if not os.path.isdir(skill_ws):
        raise ConfigError(f"Không tìm thấy thư mục skill trong workspace: '{skill_ws}'.")

    runs_list: list[dict[str, Any]] = []
    notes: list[str] = []
    has_leak = False
    total_cost_usd = 0.0
    models_seen: list[str] = []
    eval_ids_seen: set[int] = set()
    max_run_num = 0
    any_cell_found = False

    # Gom kết quả từng check để phát hiện check không phân biệt giữa hai nhánh
    check_outcomes: dict[tuple[int, str], dict[str, list[bool]]] = {}
    # Gom pass_rate theo (eval_id, config) để phát hiện dao động lớn
    eval_cfg_prs: dict[tuple[int, str], list[float]] = {}

    for ev_entry in sorted(os.listdir(skill_ws)):
        if not ev_entry.startswith("eval-"):
            continue
        ev_dir = os.path.join(skill_ws, ev_entry)
        if not os.path.isdir(ev_dir):
            continue
        try:
            eid_from_dir = int(ev_entry.split("-", 1)[1])
        except ValueError:
            continue

        valid_runs_by_cfg: dict[str, set[int]] = {"with_skill": set(), "without_skill": set()}
        for cfg in VALID_CONFIGS:
            cfg_dir = os.path.join(ev_dir, cfg)
            if not os.path.isdir(cfg_dir):
                continue
            for run_entry in sorted(os.listdir(cfg_dir)):
                if not run_entry.startswith("run-"):
                    continue
                cell_dir = os.path.join(cfg_dir, run_entry)
                run_json = os.path.join(cell_dir, "run.json")
                if not os.path.isfile(run_json):
                    continue
                any_cell_found = True
                with open(run_json, encoding="utf-8") as fh:
                    rdata = json.load(fh)

                eid = int(rdata.get("eval_id", eid_from_dir))
                rnum = int(rdata.get("run_number", 1))
                eval_ids_seen.add(eid)
                max_run_num = max(max_run_num, rnum)
                total_cost_usd += float(rdata.get("total_cost_usd") or 0.0)
                if rdata.get("model") and rdata["model"] not in models_seen:
                    models_seen.append(str(rdata["model"]))

                if rdata.get("leak"):
                    has_leak = True
                    notes.append(f"LEAK excluded: eval-{eid}/{cfg}/run-{rnum} phát hiện skill rò rỉ trong init.skills.")
                    continue

                if not rdata.get("valid", False):
                    reason = (
                        "skill_missing"
                        if rdata.get("skill_missing")
                        else ("timeout" if rdata.get("timeout") else "invalid_or_error")
                    )
                    notes.append(f"Invalid cell excluded: eval-{eid}/{cfg}/run-{rnum} ({reason}).")
                    continue

                valid_runs_by_cfg[cfg].add(rnum)

                grading_json = os.path.join(cell_dir, "grading.json")
                if not os.path.isfile(grading_json):
                    notes.append(f"Excluded ungraded cell: eval-{eid}/{cfg}/run-{rnum} (chưa chạy grade).")
                    continue

                with open(grading_json, encoding="utf-8") as fh:
                    gdata = json.load(fh)

                summary = gdata.get("summary") or {}
                pr = summary.get("pass_rate")
                if pr is None:
                    notes.append(
                        f"Unavailable pass_rate (null): eval-{eid}/{cfg}/run-{rnum} có mọi check unavailable."
                    )
                else:
                    eval_cfg_prs.setdefault((eid, cfg), []).append(float(pr))

                exps = gdata.get("expectations") or []
                for exp in exps:
                    cid = str(exp.get("id") or exp.get("text") or "")
                    pval = exp.get("passed")
                    if pval is not None:
                        check_outcomes.setdefault((eid, cid), {"with_skill": [], "without_skill": []})[cfg].append(
                            bool(pval)
                        )

                tc_dict = rdata.get("tool_calls") or {}
                total_tc = sum(int(v) for v in tc_dict.values()) if isinstance(tc_dict, dict) else int(tc_dict or 0)
                runs_list.append(
                    {
                        "eval_id": eid,
                        "eval_name": str(rdata.get("eval_name") or f"eval-{eid}"),
                        "configuration": cfg,
                        "run_number": rnum,
                        "result": {
                            "pass_rate": pr,
                            "passed": int(summary.get("passed") or 0),
                            "failed": int(summary.get("failed") or 0),
                            "total": int(summary.get("total") or 0),
                            "time_seconds": float(rdata.get("time_seconds") or 0.0),
                            "tokens": int(rdata.get("tokens") or 0),
                            "tool_calls": total_tc,
                            "errors": int(rdata.get("errors") or 0),
                        },
                        "expectations": exps,
                        "notes": gdata.get("notes") or [],
                    }
                )

        # Đọc thêm các file comparison-*.json chỉ khi cả hai ô run-<n> đều còn hợp lệ
        both_valid_runs = valid_runs_by_cfg["with_skill"] & valid_runs_by_cfg["without_skill"]
        cmp_files = sorted(
            f for f in os.listdir(ev_dir) if f.startswith("comparison-") and f.endswith(".json")
        )
        if cmp_files:
            w_wins = wo_wins = ties = errs = 0
            for cf in cmp_files:
                cpath = os.path.join(ev_dir, cf)
                if not os.path.isfile(cpath):
                    continue
                with open(cpath, encoding="utf-8") as fh:
                    cdata = json.load(fh)
                c_rnum = cdata.get("run_number")
                if not isinstance(c_rnum, int) or isinstance(c_rnum, bool):
                    stem = cf[len("comparison-") : -len(".json")]
                    try:
                        c_rnum = int(stem)
                    except ValueError:
                        continue
                if c_rnum not in both_valid_runs:
                    continue
                if cdata.get("error"):
                    errs += 1
                elif cdata.get("winner_configuration") == "with_skill":
                    w_wins += 1
                elif cdata.get("winner_configuration") == "without_skill":
                    wo_wins += 1
                elif cdata.get("winner_configuration") == "tie":
                    ties += 1
            valid_cmps = w_wins + wo_wins + ties
            if valid_cmps > 0:
                w_rate = w_wins / valid_cmps
                notes.append(
                    f"Blind comparison eval-{eid_from_dir}: with_skill={w_wins}, without_skill={wo_wins}, "
                    f"tie={ties}, errors={errs} (with_skill win_rate={w_rate:.0%})."
                )
            elif errs > 0:
                notes.append(f"Blind comparison eval-{eid_from_dir}: tất cả {errs} cặp bị lỗi phân tích JSON.")

    if not any_cell_found:
        raise ConfigError(f"Không tìm thấy ô run.json nào dưới '{skill_ws}'.")

    by_cfg: dict[str, list[dict[str, Any]]] = {"with_skill": [], "without_skill": []}
    for r in runs_list:
        by_cfg[r["configuration"]].append(r)

    summary_cfg: dict[str, dict[str, dict[str, float | None]]] = {}
    raw_means: dict[str, dict[str, float | None]] = {}

    for cfg in VALID_CONFIGS:
        c_runs = by_cfg[cfg]
        pr_vals = [float(r["result"]["pass_rate"]) for r in c_runs if r["result"]["pass_rate"] is not None]
        time_vals = [float(r["result"]["time_seconds"]) for r in c_runs]
        tok_vals = [float(r["result"]["tokens"]) for r in c_runs]

        if not pr_vals:
            notes.append(f"Nhánh {cfg}: không có giá trị số cho pass_rate (mọi ô bị loại hoặc unavailable).")

        pr_stat, pr_m = _calc_stats(pr_vals, 4)
        tm_stat, tm_m = _calc_stats(time_vals, 2)
        tk_stat, tk_m = _calc_stats(tok_vals, 1)

        summary_cfg[cfg] = {
            "pass_rate": pr_stat,
            "time_seconds": tm_stat,
            "tokens": tk_stat,
        }
        raw_means[cfg] = {"pass_rate": pr_m, "time_seconds": tm_m, "tokens": tk_m}

    delta_obj: dict[str, str | None] = {"pass_rate": None, "time_seconds": None, "tokens": None}
    if raw_means["with_skill"]["pass_rate"] is not None and raw_means["without_skill"]["pass_rate"] is not None:
        delta_obj["pass_rate"] = f"{raw_means['with_skill']['pass_rate'] - raw_means['without_skill']['pass_rate']:+.2f}"
    if raw_means["with_skill"]["time_seconds"] is not None and raw_means["without_skill"]["time_seconds"] is not None:
        delta_obj["time_seconds"] = (
            f"{raw_means['with_skill']['time_seconds'] - raw_means['without_skill']['time_seconds']:+.1f}"
        )
    if raw_means["with_skill"]["tokens"] is not None and raw_means["without_skill"]["tokens"] is not None:
        delta_obj["tokens"] = f"{int(round(raw_means['with_skill']['tokens'] - raw_means['without_skill']['tokens'])):+d}"

    # Ghi chú tự động: check không phân biệt giữa hai nhánh và eval có phương sai cao (> 0.3)
    for (eid, cid), outcomes in sorted(check_outcomes.items()):
        w_obs, wo_obs = outcomes["with_skill"], outcomes["without_skill"]
        if w_obs and wo_obs:
            w_rate = sum(1 for x in w_obs if x) / len(w_obs)
            wo_rate = sum(1 for x in wo_obs if x) / len(wo_obs)
            if abs(w_rate - wo_rate) < 1e-9:
                notes.append(
                    f"Non-discriminating check eval-{eid}:{cid} đạt tỉ lệ như nhau ({w_rate:.2f}) ở cả hai nhánh."
                )

    for (eid, cfg), prs in sorted(eval_cfg_prs.items()):
        if len(prs) >= 2:
            sd = statistics.pstdev(prs)
            if sd > 0.3:
                notes.append(f"High variance eval-{eid} ({cfg}): pstdev={sd:.2f} > 0.30.")

    notes.append(f"Total cost: ${total_cost_usd:.4f} USD.")

    benchmark_payload = {
        "metadata": {
            "skill_name": skill_name,
            "executor_model": models_seen[0] if len(models_seen) == 1 else (",".join(models_seen) or "unknown"),
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "evals_run": sorted(eval_ids_seen),
            "runs_per_configuration": max_run_num,
        },
        "runs": runs_list,
        "run_summary": {
            "with_skill": summary_cfg["with_skill"],
            "without_skill": summary_cfg["without_skill"],
            "delta": delta_obj,
        },
        "notes": notes,
    }

    bench_json_path = os.path.join(skill_ws, "benchmark.json")
    bench_md_path = os.path.join(skill_ws, "benchmark.md")
    with open(bench_json_path, "w", encoding="utf-8") as fh:
        json.dump(benchmark_payload, fh, indent=2, ensure_ascii=False)
    with open(bench_md_path, "w", encoding="utf-8") as fh:
        fh.write(_render_benchmark_md(benchmark_payload))

    print(
        f"[aggregate] skill={skill_name} valid_runs={len(runs_list)} "
        f"delta_pass_rate={delta_obj['pass_rate']} leak={has_leak} -> {bench_json_path}"
    )
    return 1 if has_leak else 0


def _parse_outermost_json_object(candidate: str) -> dict[str, Any]:
    """Tìm và phân tích object JSON ngoài cùng từ chuỗi văn bản (bỏ qua dấu ngoặc nằm trong chuỗi JSON)."""
    start = candidate.find("{")
    if start == -1:
        raise ValueError("Không tìm thấy ký tự mở object '{' trong phản hồi của judge.")

    depth = 0
    in_str = False
    esc = False
    end = -1
    for idx in range(start, len(candidate)):
        ch = candidate[idx]
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
        else:
            if ch == '"':
                in_str = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    end = idx
                    break
    if end == -1:
        end = candidate.rfind("}")
    if end <= start:
        raise ValueError("Không tìm thấy object JSON hoàn chỉnh trong phản hồi của judge.")

    obj = json.loads(candidate[start : end + 1])
    if not isinstance(obj, dict):
        raise ValueError("Kết quả phân tích không phải JSON object.")
    return obj


def _extract_judge_json(raw_text: str) -> dict[str, Any]:
    """Bóc hàng rào code fence ngoài cùng (neo đầu/cuối) hoặc phân tích trực tiếp object JSON ngoài cùng."""
    txt = raw_text.strip()
    candidates: list[str] = []
    # Chỉ bóc code fence khi toàn bộ chuỗi mở đầu và kết thúc bằng ``` (dùng .* tham lam để không cắt nhầm ``` bên trong reasoning)
    anchored_fence = re.match(r"^```(?:json)?\s*(.*)\s*```$", txt, re.S | re.I)
    if anchored_fence:
        candidates.append(anchored_fence.group(1).strip())
    candidates.append(txt)

    obj: dict[str, Any] | None = None
    last_exc: Exception | None = None
    for cand in candidates:
        try:
            obj = _parse_outermost_json_object(cand)
            break
        except Exception as exc:
            last_exc = exc
    if obj is None:
        raise ValueError(str(last_exc) if last_exc else "Không trích được JSON hợp lệ từ judge.")

    winner = obj.get("winner")
    reasoning = obj.get("reasoning")
    if winner not in ("A", "B", "tie"):
        raise ValueError(f"Trường 'winner' không hợp lệ: {winner!r} (chỉ nhận 'A', 'B' hoặc 'tie').")
    if not isinstance(reasoning, str) or not reasoning.strip():
        raise ValueError("Trường 'reasoning' phải là chuỗi giải thích khác rỗng.")
    return {"winner": winner, "reasoning": reasoning.strip()}


def _make_clean_scratch_dir() -> str:
    """Tạo thư mục scratch rỗng cho compare và kiểm tra chặn nhiễm trước khi gọi CLI claude."""
    bases = [None, "/private/tmp", "/tmp"]
    last_err: Exception | None = None
    for base in bases:
        if base is not None and not os.path.isdir(base):
            continue
        d = tempfile.mkdtemp(prefix="skill_eval_cmp_", dir=base)
        try:
            check_workspace_clean(d)
            return d
        except ConfigError as exc:
            shutil.rmtree(d, ignore_errors=True)
            last_err = exc
    raise ConfigError(f"Không thể tạo thư mục scratch sạch cho compare: {last_err}")


def _resolve_cell_artifact(project_dir: str, rel_artifact: str) -> str | None:
    """Phân giải an toàn đường dẫn artifact bên trong thư mục project/ của một ô."""
    _validate_safe_rel_segments(rel_artifact, "--artifact")
    real_proj = os.path.realpath(project_dir)
    cand = os.path.join(project_dir, rel_artifact)
    if not os.path.isfile(cand):
        return None
    real_cand = os.path.realpath(cand)
    if real_cand != real_proj and not real_cand.startswith(real_proj + os.sep):
        raise ConfigError(f"Artifact '{rel_artifact}' trỏ ra ngoài thư mục project/.")
    return cand


def cmd_compare(args: argparse.Namespace) -> int:
    """Thực thi lệnh con `compare`: chấm so mù từng cặp run-n giữa with_skill và without_skill."""
    if args.timeout <= 0:
        raise ConfigError("--timeout phải > 0.")
    if args.budget_usd <= 0:
        raise ConfigError("--budget-usd phải > 0.")

    check_workspace_clean(args.workspace)
    _validate_safe_rel_segments(args.artifact, "--artifact")

    eval_dir = os.path.join(os.path.abspath(args.workspace), args.skill, f"eval-{args.eval}")
    if not os.path.isdir(eval_dir):
        raise ConfigError(f"Không tìm thấy thư mục eval: '{eval_dir}'.")

    with_dir = os.path.join(eval_dir, "with_skill")
    without_dir = os.path.join(eval_dir, "without_skill")
    if not os.path.isdir(with_dir) or not os.path.isdir(without_dir):
        raise ConfigError(f"Thiếu nhánh with_skill hoặc without_skill trong '{eval_dir}'.")

    run_nums_set: set[int] = set()
    for bdir in (with_dir, without_dir):
        for entry in sorted(os.listdir(bdir)):
            if not entry.startswith("run-"):
                continue
            try:
                run_nums_set.add(int(entry.split("-", 1)[1]))
            except ValueError:
                continue
    for entry in sorted(os.listdir(eval_dir)):
        if entry.startswith("comparison-") and entry.endswith(".json"):
            try:
                run_nums_set.add(int(entry[len("comparison-") : -len(".json")]))
            except ValueError:
                continue

    run_nums = sorted(run_nums_set)
    if not run_nums:
        raise ConfigError(f"Không tìm thấy cặp run-n nào trong '{eval_dir}'.")

    claude_bin = resolve_claude_bin()
    cfg_dir = resolve_claude_config_dir(args.config_dir, os.getcwd())
    had_error = False
    compared = 0

    def _remove_stale_cmp(path: str) -> None:
        if os.path.lexists(path):
            try:
                os.unlink(path)
            except OSError:
                pass

    for n in run_nums:
        w_cell = os.path.join(with_dir, f"run-{n}")
        wo_cell = os.path.join(without_dir, f"run-{n}")
        cmp_out_path = os.path.join(eval_dir, f"comparison-{n}.json")

        if not os.path.isdir(w_cell) or not os.path.isdir(wo_cell):
            _remove_stale_cmp(cmp_out_path)
            continue

        # Bỏ qua cặp (và dọn comparison cũ) nếu run.json có mặt và đánh dấu valid=False
        skip_pair = False
        for cdir in (w_cell, wo_cell):
            rj = os.path.join(cdir, "run.json")
            if os.path.isfile(rj):
                with open(rj, encoding="utf-8") as fh:
                    rdata = json.load(fh)
                if rdata.get("valid") is False:
                    skip_pair = True
        if skip_pair:
            _remove_stale_cmp(cmp_out_path)
            continue

        w_art = _resolve_cell_artifact(os.path.join(w_cell, "project"), args.artifact)
        wo_art = _resolve_cell_artifact(os.path.join(wo_cell, "project"), args.artifact)
        if not w_art or not wo_art:
            _remove_stale_cmp(cmp_out_path)
            continue

        with open(w_art, encoding="utf-8", errors="replace") as fh:
            w_content = fh.read(60000)
        with open(wo_art, encoding="utf-8", errors="replace") as fh:
            wo_content = fh.read(60000)

        rng = random.Random(args.seed + n)
        if rng.choice([True, False]):
            assignment = {"A": "with_skill", "B": "without_skill"}
            art_a, art_b = w_content, wo_content
        else:
            assignment = {"A": "without_skill", "B": "with_skill"}
            art_a, art_b = wo_content, w_content

        judge_prompt = (
            "You are an impartial UI/code craft judge performing a blind A/B evaluation.\n"
            "Rubric:\n"
            "1. Preservation of incumbent product identity, copy, structure, and links.\n"
            "2. Visual hierarchy, spacing rhythm, typography legibility, and color contrast (WCAG AA).\n"
            "3. Absence of AI slop patterns (nested cards, icon tiles stacked on headings, raw #808080 grey, "
            "monotonous padding, missing keyboard focus states).\n"
            "4. Clean, maintainable HTML/CSS implementation.\n\n"
            f"=== ARTIFACT A ({args.artifact}) ===\n{art_a}\n\n"
            f"=== ARTIFACT B ({args.artifact}) ===\n{art_b}\n\n"
            'Respond ONLY with a single JSON object matching exactly: '
            '{"winner": "A" | "B" | "tie", "reasoning": "<concise technical justification>"}'
        )

        argv = [
            claude_bin,
            "-p",
            judge_prompt,
            "--output-format",
            "stream-json",
            "--verbose",
            "--setting-sources",
            "project",
            "--model",
            str(args.model),
            "--max-budget-usd",
            str(args.budget_usd),
            "--no-session-persistence",
            "--permission-prompts",
            "none",
            "--tools",
            "",
        ]

        child_env = {k: v for k, v in os.environ.items() if k not in GIT_ENV_SCRUB}
        if cfg_dir:
            child_env["CLAUDE_CONFIG_DIR"] = cfg_dir
        else:
            child_env.pop("CLAUDE_CONFIG_DIR", None)

        scratch_dir = _make_clean_scratch_dir()
        try:
            rc, stdout_s, stderr_s, timed_out, _ = run_process_bounded(
                argv=argv,
                cwd=scratch_dir,
                env=child_env,
                timeout_sec=args.timeout,
            )
        finally:
            shutil.rmtree(scratch_dir, ignore_errors=True)

        parsed = parse_stream_json(stdout_s, args.skill, eval_dir)
        cmp_out_path = os.path.join(eval_dir, f"comparison-{n}.json")

        if timed_out or rc != 0 or parsed["is_error"] or not parsed["result_seen"]:
            had_error = True
            err_msg = (
                "timeout"
                if timed_out
                else f"judge process failed (rc={rc}, is_error={parsed['is_error']}): {stderr_s.strip()[:200]}"
            )
            cmp_record = {
                "eval_id": args.eval,
                "run_number": n,
                "artifact": args.artifact,
                "seed": args.seed,
                "assignment": assignment,
                "winner": None,
                "winner_configuration": None,
                "reasoning": None,
                "duration_ms": parsed["duration_ms"],
                "total_cost_usd": parsed["total_cost_usd"],
                "error": err_msg,
            }
        else:
            try:
                verdict = _extract_judge_json(parsed["result"])
                w_label = verdict["winner"]
                w_cfg = "tie" if w_label == "tie" else assignment[w_label]
                cmp_record = {
                    "eval_id": args.eval,
                    "run_number": n,
                    "artifact": args.artifact,
                    "seed": args.seed,
                    "assignment": assignment,
                    "winner": w_label,
                    "winner_configuration": w_cfg,
                    "reasoning": verdict["reasoning"],
                    "duration_ms": parsed["duration_ms"],
                    "total_cost_usd": parsed["total_cost_usd"],
                    "error": None,
                }
            except Exception as exc:
                had_error = True
                cmp_record = {
                    "eval_id": args.eval,
                    "run_number": n,
                    "artifact": args.artifact,
                    "seed": args.seed,
                    "assignment": assignment,
                    "winner": None,
                    "winner_configuration": None,
                    "reasoning": None,
                    "duration_ms": parsed["duration_ms"],
                    "total_cost_usd": parsed["total_cost_usd"],
                    "error": f"Invalid judge JSON: {exc}",
                }

        with open(cmp_out_path, "w", encoding="utf-8") as fh:
            json.dump(cmp_record, fh, indent=2, ensure_ascii=False)
        compared += 1

    if compared == 0:
        raise ConfigError(f"Không có cặp hợp lệ nào chứa artifact '{args.artifact}' trong '{eval_dir}'.")

    print(f"[compare] skill={args.skill} eval={args.eval} pairs={compared} errors={int(had_error)}")
    return 1 if had_error else 0


def cmd_validate(args: argparse.Namespace) -> int:
    """Thực thi lệnh con chỉ-đọc `validate`: kiểm tra cấu trúc và an toàn đường dẫn của evals.json."""
    data, skill_dir = validate_evals_file(args.evals, expected_skill=args.skill)
    print(f"[validate] OK: skill={data['skill_name']} evals={len(data['evals'])} dir={skill_dir}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    """Khởi tạo bộ phân tích tham số dòng lệnh cho 5 lệnh con của skill_eval.py."""
    parser = argparse.ArgumentParser(
        prog="skill_eval.py",
        description="Runner A/B đo hiệu quả skill DevKit (with_skill vs without_skill).",
    )
    sub = parser.add_subparsers(dest="subcommand", required=True)

    p_run = sub.add_parser("run", help="Chạy các ô thực nghiệm A/B cho một skill.")
    p_run.add_argument("--skill", required=True, help="Tên skill cần đo.")
    p_run.add_argument("--evals", required=True, help="Đường dẫn tới evals/evals.json.")
    p_run.add_argument("--workspace", required=True, help="Thư mục workspace sạch ngoài dự án.")
    p_run.add_argument("--runs", type=int, default=3, help="Số lần lặp mỗi cấu hình (mặc định: 3).")
    p_run.add_argument(
        "--configs",
        default="with_skill,without_skill",
        help="Danh sách cấu hình phân tách bởi dấu phẩy (mặc định: with_skill,without_skill).",
    )
    p_run.add_argument("--model", default="sonnet", help="Model thực thi (mặc định: sonnet).")
    p_run.add_argument("--budget-usd", type=float, default=1.0, help="Trần chi phí USD mỗi ô (mặc định: 1.0).")
    p_run.add_argument("--timeout", type=float, default=900.0, help="Hạn giờ giây mỗi ô (mặc định: 900).")
    p_run.add_argument("--jobs", type=int, default=1, help="Số ô chạy song song (mặc định: 1).")
    p_run.add_argument("--config-dir", default=None, help="Ghi đè CLAUDE_CONFIG_DIR.")
    p_run.add_argument("--eval-ids", default=None, help="Chỉ chạy các id eval được liệt kê (vd: 1,3).")
    p_run.add_argument("--force", action="store_true", help="Chạy lại kể cả khi ô đã có run.json.")
    p_run.add_argument("--dry-run", action="store_true", help="Chỉ in danh sách ô và argv, không thực thi.")

    p_grade = sub.add_parser("grade", help="Chấm điểm các ô hợp lệ trong workspace và ghi grading.json.")
    p_grade.add_argument("--skill", required=True, help="Tên skill.")
    p_grade.add_argument("--evals", required=True, help="Đường dẫn tới evals/evals.json.")
    p_grade.add_argument("--workspace", required=True, help="Thư mục workspace.")

    p_agg = sub.add_parser("aggregate", help="Tổng hợp benchmark.json và benchmark.md từ workspace.")
    p_agg.add_argument("--skill", required=True, help="Tên skill.")
    p_agg.add_argument("--workspace", required=True, help="Thư mục workspace.")

    p_cmp = sub.add_parser("compare", help="So mù từng cặp run-n cho một artifact đầu ra.")
    p_cmp.add_argument("--skill", required=True, help="Tên skill.")
    p_cmp.add_argument("--workspace", required=True, help="Thư mục workspace.")
    p_cmp.add_argument("--eval", type=int, required=True, help="ID của eval cần so mù.")
    p_cmp.add_argument("--artifact", required=True, help="Đường dẫn tương đối của artifact trong project/.")
    p_cmp.add_argument("--model", default="sonnet", help="Model làm giám khảo (mặc định: sonnet).")
    p_cmp.add_argument("--seed", type=int, default=0, help="Seed ngẫu nhiên hoá thứ tự A/B (mặc định: 0).")
    p_cmp.add_argument("--config-dir", default=None, help="Ghi đè CLAUDE_CONFIG_DIR.")
    p_cmp.add_argument("--budget-usd", type=float, default=0.5, help="Trần USD mỗi lượt chấm mù (mặc định: 0.5).")
    p_cmp.add_argument("--timeout", type=float, default=300.0, help="Hạn giờ giây mỗi lượt chấm mù (mặc định: 300).")

    p_val = sub.add_parser("validate", help="Kiểm tra tính hợp lệ chỉ-đọc của file evals/evals.json.")
    p_val.add_argument("--evals", required=True, help="Đường dẫn tới evals/evals.json.")
    p_val.add_argument("--skill", default=None, help="Tên skill kỳ vọng (tuỳ chọn).")

    return parser


def main(argv: list[str] | None = None) -> int:
    """Điểm vào chính của CLI skill_eval.py (exit 0: ổn, 1: ô lỗi/leak, 2: sai tham số/từ chối)."""
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.subcommand == "run":
            return cmd_run(args)
        if args.subcommand == "grade":
            return cmd_grade(args)
        if args.subcommand == "aggregate":
            return cmd_aggregate(args)
        if args.subcommand == "compare":
            return cmd_compare(args)
        if args.subcommand == "validate":
            return cmd_validate(args)
        raise ConfigError(f"Lệnh con không xác định: {args.subcommand}")
    except ConfigError as exc:
        sys.stderr.write(f"Lỗi cấu hình/từ chối: {exc}\n")
        return 2


if __name__ == "__main__":
    sys.exit(main())
