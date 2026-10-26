# Bộ xử lý tạo chuỗi đường dẫn tĩnh (URL slug) cho tiêu đề bài viết.
import re


def slugify(title: str) -> str:
    """Chuyển tiêu đề thành slug chữ thường phân tách bằng dấu gạch ngang."""
    if not isinstance(title, str):
        raise TypeError("title must be a string")
    cleaned = title.strip().lower()
    # Thay thế các dãy ký tự phân cách bằng một dấu gạch ngang duy nhất
    slug = re.sub(r"[^a-z]+", "-", cleaned)
    return slug.strip("-")
