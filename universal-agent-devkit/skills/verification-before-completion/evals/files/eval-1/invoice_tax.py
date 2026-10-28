"""Tính thuế và tổng tiền thanh toán của hoá đơn."""


def compute_tax(subtotal: float, rate: float) -> float:
    if subtotal < 0 or rate < 0:
        raise ValueError("subtotal và rate không được âm")
    return float(int(subtotal * rate))


def invoice_total(subtotal: float, rate: float) -> float:
    return round(subtotal + compute_tax(subtotal, rate), 2)
