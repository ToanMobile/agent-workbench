# Bộ phân tích chuỗi thời lượng (ví dụ '45s', '15m', '2h') sang tổng số giây.

UNIT_SECONDS = {
    "h": 3600,
    "m": 60,
    "s": 1,
}


def parse_duration(spec: str) -> int:
    """Đổi chuỗi thời lượng sang số giây nguyên không âm."""
    if not isinstance(spec, str):
        raise TypeError("duration spec must be a string")
    text = spec.strip().lower()
    if not text:
        raise ValueError("empty duration")
    # Tách ký hiệu đơn vị ở cuối chuỗi và quy đổi giá trị số tương ứng sang giây
    unit = text[-1]
    if unit not in UNIT_SECONDS:
        raise ValueError(f"unsupported duration unit in {spec!r}")
    num_part = text[:-1].strip()
    if not num_part.isdigit():
        raise ValueError(f"invalid duration value in {spec!r}")
    return int(num_part) * UNIT_SECONDS[unit]
