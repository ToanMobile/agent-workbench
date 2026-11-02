#!/usr/bin/env python3
"""Luật "chỉ-thêm" của .agents/regression_matrix.active.json và khe băm cho rule mới — MỘT nguồn cho post-fix-gate
(matrix_additions / trust_additive_matrix), scripts/git/matrix_merge_driver.py và `agent-kit matrix add` (INSTINCT-015).

Hai PR cùng NỐI một rule vào cuối ma trận sửa cùng dòng cuối ("    }" thành "    },") nên PR thứ hai luôn CONFLICTING trên GitHub
(GitHub không chạy merge driver). Rule mới chèn TRƯỚC rules[slot(component, n)] (không bao giờ ở cuối khi n > 0): hai PR khác khe,
kể cả khe kề nhau, merge sạch bằng git thuần. Gate không kiểm "rule nằm đúng khe" — chỉ kiểm rule base là DÃY CON đúng thứ tự.

  matrix_slot.py add <rule.json> [--matrix PATH]     (mặc định <toplevel>/.agents/regression_matrix.active.json)

exit 0 đã chèn · 1 rule bị từ chối (id/component đã có, rule không chỉ-thêm hợp lệ, ma trận hỏng), file không đổi · 2 sai cú pháp
"""
import hashlib
import json
import os
import subprocess
import sys
import tempfile

MATRIX = ".agents/regression_matrix.active.json"


def split(old, new):
    """[(k, rule thêm)] — k = số rule base đứng trước rule thêm — khi `new` chỉ CHÈN rule vào `old`; không thì None (kể cả 0 rule thêm).
    Chỉ-thêm: rule base là dãy con đúng thứ tự của `new`, bằng từng giá trị; mỗi rule thêm có ≥ 1 test, mỗi test có id và lệnh là chuỗi
    khác rỗng, không covered_by (test mới phải tự chạy); id chưa có ở base — kể cả đích covered_by của test base (id thêm "lấp" đích treo
    thì suite base bị đánh COVERED) — và không trùng nhau; component (khi là chuỗi) chưa có ở base và không trùng nhau. Duyệt tham lam
    đúng vì một rule thêm không thể bằng rule base (id mới). Khoá top-level ngoài "rules" do caller so."""
    if not isinstance(old, list) or not isinstance(new, list):
        return None
    out, j = [], 0
    for rule in new:
        if j < len(old) and rule == old[j]:
            j += 1
        else:
            out.append((j, rule))
    if j != len(old) or not out:
        return None
    ids = {t[k] for r in old if isinstance(r, dict) for t in (r.get("mandatory_regression_tests") or [])
           if isinstance(t, dict) for k in ("id", "covered_by") if isinstance(t.get(k), str)}
    comps = {r["component"] for r in old if isinstance(r, dict) and isinstance(r.get("component"), str)}
    for _, rule in out:
        tests = rule.get("mandatory_regression_tests") if isinstance(rule, dict) else None
        if not isinstance(tests, list) or not tests:
            return None
        comp = rule.get("component")
        if isinstance(comp, str):   # rule không có component (ma trận tay cũ) vẫn được nhận; trùng thì không
            if comp in comps:
                return None
            comps.add(comp)
        for t in tests:
            if not (isinstance(t, dict) and isinstance(t.get("id"), str) and t["id"].strip()
                    and isinstance(t.get("command"), str) and t["command"].strip() and "covered_by" not in t):
                return None
            if t["id"] in ids:
                return None
            ids.add(t["id"])
    return out


def added_rules(old, new):
    """Các rule `new` chèn thêm vào `old` theo thứ tự file, hoặc None khi không phải thay đổi chỉ-thêm (split)."""
    pairs = split(old, new)
    return None if pairs is None else [rule for _, rule in pairs]


def slot(component, n):
    """Khe chèn của rule `component` vào ma trận n rule: TRƯỚC rules[slot]; luôn < n nên rule cuối không bao giờ đổi dòng `}`
    (n == 0: nối, ca duy nhất)."""
    return int(hashlib.sha256(component.encode("utf-8")).hexdigest(), 16) % n if n else 0


def insert(matrix, rule):
    """(ma trận mới, khe). ValueError nêu tên khi component/id đã có hoặc rule không qua luật chỉ-thêm của gate."""
    rules = matrix.get("rules") if isinstance(matrix, dict) else None
    if not isinstance(rules, list):
        raise ValueError("matrix has no \"rules\" list")
    comp = rule.get("component") if isinstance(rule, dict) else None
    if not isinstance(comp, str) or not comp.strip():
        raise ValueError("the rule needs a non-empty \"component\" (it picks the slot)")
    if any(isinstance(r, dict) and r.get("component") == comp for r in rules):
        raise ValueError(f"component {comp} is already in the matrix")
    have = {t[k] for r in rules if isinstance(r, dict) for t in (r.get("mandatory_regression_tests") or [])
            if isinstance(t, dict) for k in ("id", "covered_by") if isinstance(t.get(k), str)}
    for t in rule.get("mandatory_regression_tests") or []:
        if isinstance(t, dict) and t.get("id") in have:
            raise ValueError(f"test id {t['id']} is already in the matrix")
    k = slot(comp, len(rules))
    new = rules[:k] + [rule] + rules[k:]
    if added_rules(rules, new) is None:   # tự kiểm bằng chính luật gate
        raise ValueError(f"rule {comp} is not insert-only: every test needs a non-empty id and command, no covered_by, unique ids")
    return {**matrix, "rules": new}, k


def _default_matrix():
    res = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return os.path.join(res.stdout.strip() if res.returncode == 0 and res.stdout.strip() else os.getcwd(), MATRIX)


def main(argv):
    args = argv[1:]
    path = None
    if "--matrix" in args:
        i = args.index("--matrix")
        if i + 1 >= len(args):
            print("usage: matrix_slot.py add <rule.json> [--matrix PATH]", file=sys.stderr)
            return 2
        path = args[i + 1]
        del args[i:i + 2]
    if len(args) != 2 or args[0] != "add":
        print("usage: matrix_slot.py add <rule.json> [--matrix PATH]", file=sys.stderr)
        return 2
    path = path or _default_matrix()
    try:
        with open(args[1], encoding="utf-8") as f:
            rule = json.load(f)
        with open(path, encoding="utf-8") as f:
            matrix = json.load(f)
        new, k = insert(matrix, rule)
    except (OSError, ValueError) as e:
        print(f"matrix add: {e}", file=sys.stderr)
        return 1
    # Ghi qua file tạm cùng thư mục + os.replace: lỗi giữa chừng không để lại ma trận dở; giữ quyền file cũ (mkstemp tạo 0600).
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(path)), prefix=".matrix.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(json.dumps(new, indent=2, ensure_ascii=False) + "\n")
        os.chmod(tmp, os.stat(path).st_mode & 0o7777)
        os.replace(tmp, path)
    except OSError as e:
        if os.path.exists(tmp):
            os.unlink(tmp)
        print(f"matrix add: cannot write {path}: {e}", file=sys.stderr)
        return 1
    print(f"inserted {rule['component']} at {k}/{len(matrix['rules'])} in {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
