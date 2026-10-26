#!/usr/bin/env python3
"""per_test_cache.py — sổ PASS theo TỪNG test của run_impacted.sh (audit DevKit 25/10, mục B2).

Một TIMEOUT của REG-DK-ALL-01 (run_impacted.sh, trần 900 s của gate) vô hiệu mọi PASS bên trong nó: lượt sau chạy lại cả tập, lại quá giờ
(54 TIMEOUT = 14,3 h trong 54 h đo ở workbench). Nay mỗi test PASS được ghi NGAY khi nó xong, vào kho của bin/suite_cache.py theo khoá CẢ
CÂY của lệnh `bash <test>` (SuiteCache.keys()[1]: nội dung mọi file + đường dẫn test + môi trường + đích ngoài cây); lượt sau trên đúng cây đó
bỏ qua test đã PASS (sau TIMEOUT, worktree anh em cùng cây, merge gate cùng cây). Không khoá theo bao đóng tĩnh: nó bỏ sót "$D/lib/x" ở kit
lồng và `import` trong heredoc python của file .sh (review 26/10, F1).

  per_test_cache.py plan <kit> <out> <test>...   in "reuse<TAB><test><TAB><tuổi giây>" cho test dùng lại; test phải chạy thì ghi ảnh
                                                  khoá <out>/<test, "/"→"_">.ptc.json (+ dấu vân tay cây chung <out>/ptc.base.json)
  per_test_cache.py record <out> <test> <rc>     ghi kết quả của một lần chạy THẬT (rc của test)

Chỉ chạy khi gate bật (DEVKIT_PER_TEST_CACHE, post-fix-gate.py: "1" dùng lại + ghi theo khoá nội dung, "record" chỉ ghi — lượt sentinel /
--no-cache); `agent-kit test` của người dùng không đặt biến nên luôn chạy hết. Luật như suite (cùng mã SuiteCache, kho riêng
<kho suite>/per_test để không đẩy bản ghi suite ra khỏi STORE_MAX):
  - dùng lại ⇔ SuiteCache.hit: PASS trên đúng khoá (pass_n ≥ 1, fail_n = 0, không cách ly, không bị void) có lần chạy THẬT trong tuổi tối
    đa (DEVKIT_SUITE_CACHE_MAX_S / DEVKIT_GATE_CACHE_MAX_S, mặc định 6 h) — test được dùng lại phải chạy thật ít nhất một lần mỗi 6 h;
  - record ghi PASS khi cả cây (và đích ngoài cây) y nguyên sau khi test chạy; ghi FAIL lên khoá (SuiteCache.hit đòi fail_n = 0) và, khi
    khoá đang có PASS, gọi SuiteCache.contradiction (cùng cây mà khác kết quả: cách ly); PASS trên khoá có fail_n > 0 (cùng nội dung, chập
    chờn): cách ly id (QUARANTINE_S); TIMEOUT (124 của run_bounded) ghi timeout_n và void id; rc ≥ 128 (tín hiệu: crash của chính test,
    hay gate giết cả nhóm khi REG-DK-ALL-01 quá giờ) hay 64 (lỗi dùng run_bounded): không ghi kết quả, void id (review 26/10, F2).
  - plan không ghi ảnh khoá cho test có lệnh mạng (suite_cache.NETWORK): test đó chạy mỗi lượt.
Lỗi của helper (ngoại lệ, kho không đọc được) làm plan không in "reuse": test chạy.
"""
import importlib.util
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ID_PREFIX = "per-test:"


def _bin(kit):
    return os.path.join(kit, "bin")


def _suite_cache(kit):
    sys.path.insert(0, _bin(kit))
    import suite_cache  # noqa: PLC0415 - bin/ của kit vừa vào sys.path
    return suite_cache


def _snap_path(out, test):
    return os.path.join(out, test.replace("/", "_") + ".ptc.json")


def _project(kit):
    r = subprocess.run(["git", "-C", kit, "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=30)
    return os.path.realpath(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else None


def _head(project):
    r = subprocess.run(["git", "-C", project, "rev-parse", "HEAD"], capture_output=True, text=True, timeout=30)
    return r.stdout.strip() if r.returncode == 0 else None


def plan(kit, out, tests):
    mode = os.environ.get("DEVKIT_PER_TEST_CACHE", "")
    if mode not in ("1", "record"):
        return 0
    kit = os.path.realpath(kit)
    project = _project(kit)
    if not project:
        return 0
    spec = importlib.util.spec_from_file_location("post_fix_gate_for_per_test", os.path.join(_bin(kit), "post-fix-gate.py"))
    gate = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gate)
    mod = gate.suite_cache_mod()
    sc = gate.suite_cache_for(project, [], None, {})   # None khi DEVKIT_SUITE_CACHE=0 hay kho hỏng: mọi test chạy, không ghi gì
    if mod is None or sc is None:
        return 0
    sc.store = os.path.join(sc.store, "per_test")
    sc.learned = sc.load_learned()   # input học được của kho per_test, không của kho suite
    # Ảnh lúc tính khoá: một file chung (dấu vân tay cả cây) + mỗi test khoá và đích ngoài cây của nó; record so lại cả cây sau khi test chạy.
    base = {"v": 2, "project": project, "store": sc.store, "head": _head(project), "tree": sc.tree_digest}
    if not _write(os.path.join(out, "ptc.base.json"), base):
        return 0
    now = time.time()
    for test in tests:
        full = os.path.realpath(os.path.join(kit, test))
        rel = os.path.relpath(full, project)
        if rel.startswith("..") or not os.path.isfile(full):
            continue
        entry = {"id": ID_PREFIX + rel, "command": "bash " + rel}
        if mod.NETWORK.search(mod._read_text(full) or ""):
            continue   # đọc mạng ngay trong test: khoá nội dung không nói gì về kết quả
        # KHOÁ CẢ CÂY (nội dung mọi file + đường dẫn test + môi trường), không khoá theo bao đóng: bao đóng tĩnh bỏ sót "$D/lib/x" ở kit lồng
        # và `import` trong heredoc python của file .sh (review 26/10, F1) — PASS chỉ dùng lại khi đúng cây đó chạy lại (sau TIMEOUT, worktree
        # anh em cùng cây, merge gate trên cùng cây).
        key = sc.keys(entry)[1]
        if not key:
            continue
        rec = sc.hit(key, entry, now) if mode == "1" else None   # hit() đã giới hạn tuổi PASS (mặc định 6 h)
        if rec:
            print(f"reuse\t{test}\t{int(now - rec['last_pass_at'])}")
            continue
        _write(_snap_path(out, test), {"id": entry["id"], "command": entry["command"], "key": key,
                                       "ext": sc.input_values[(entry["id"], entry["command"])][1]})
    return 0


def _write(path, data):
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f)
        return True
    except OSError as exc:
        print(f"per_test_cache: không ghi được {path}: {exc}", file=sys.stderr)
        return False


def record(out, test, rc):
    try:
        with open(_snap_path(out, test), encoding="utf-8") as f:
            snap = json.load(f)
        with open(os.path.join(out, "ptc.base.json"), encoding="utf-8") as f:
            base = json.load(f)
        project, store, tree = base["project"], base["store"], base["tree"]
        rc = int(rc)
    except (OSError, ValueError, KeyError, TypeError):
        return 0   # không có ảnh khoá (lượt không bật cache, test đọc mạng…) hay ảnh hỏng: không ghi gì
    finished = time.time()
    mod = _suite_cache(os.path.dirname(os.path.dirname(HERE)))
    sc = mod.SuiteCache(project, [], None, {}, "per-test-record", 0, {}, learned={})
    sc.store = store
    entry = {"id": snap["id"], "command": snap["command"]}
    if rc >= 128 or rc == 64:
        # tín hiệu (crash 139/134 của chính test, hay gate giết nhóm) / lỗi dùng run_bounded: không phải kết luận PASS/FAIL, nhưng PASS cũ của
        # test này không còn đáng tin (review 26/10, F2) — void: lượt sau chạy thật
        sc.void(entry["id"], finished)
        print(f"per_test_cache: {entry['id']}: rc {rc} (tín hiệu / helper) — PASS cũ của test này hết dùng lại")
        return 0
    status = "PASS" if rc == 0 else ("TIMEOUT" if rc == 124 else "FAIL")
    if status == "PASS":
        same = sc.cmap is not None and mod.tree_digest(sc.cmap) == tree
        for tok, dig in snap["ext"].items():
            hit = mod._external(project, tok, "")
            same = same and bool(hit) and mod._file_digest(hit[1]) == dig
        if not same:
            print(f"per_test_cache: cây đổi trong lúc {test} chạy — không ghi PASS")
            return 0
    sc.input_values[(entry["id"], entry["command"])] = (dict.fromkeys(sc.cmap or {}), snap["ext"])   # input = cả cây (contradiction)
    prev = sc.record(snap["key"], entry, status, {"head": base.get("head")}, at=finished)
    if status == "TIMEOUT":
        sc.void(entry["id"], finished)
    elif status == "FAIL":
        msg = sc.contradiction(snap["key"], entry, prev, False)
        if msg:
            print(f"per_test_cache: {msg}")
    elif prev and isinstance(prev.get("fail_n"), int) and prev["fail_n"] > 0:
        sc.quarantine(entry["id"])   # cùng khoá (cùng nội dung) từng FAIL nay PASS: chập chờn — hit() trả None cho id này hết QUARANTINE_S
        print(f"per_test_cache: {entry['id']}: khoá từng đỏ nay xanh (chập chờn) — cách ly, lượt sau chạy thật")
    return 0


def main(argv):
    if len(argv) >= 3 and argv[0] == "plan":
        return plan(argv[1], argv[2], argv[3:])
    if len(argv) == 4 and argv[0] == "record":
        return record(argv[1], argv[2], argv[3])
    print(__doc__.split("\n\n")[1], file=sys.stderr)
    return 64


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as exc:   # noqa: BLE001 - mọi lỗi chỉ làm test chạy lại, không bao giờ là PASS; nói rõ lỗi gì
        print(f"per_test_cache: {exc!r}", file=sys.stderr)
        sys.exit(0)
