# Bộ tính toán thống kê mô tả cơ bản cho báo cáo số liệu.
from typing import Iterable


def median(values: Iterable[float]) -> float:
    """Tính giá trị trung vị của dãy số thực không rỗng."""
    ordered = sorted(values)
    n = len(ordered)
    if n == 0:
        raise ValueError("median() arg is an empty sequence")
    mid = n // 2
    # Lấy phần tử ở vị trí trung tâm sau khi đã sắp xếp tăng dần
    return float(ordered[mid])
