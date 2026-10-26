---
name: Kestrel Gauge
description: Bảng trực ban quan trắc mực nước và cảnh báo hạ lưu
colors:
  fjord-bg: "#f1f5f9"
  slate-surface: "#ffffff"
  slate-subtle: "#e3ebf3"
  border-hairline: "#cbd6e2"
  fjord-ink: "#0f2233"
  fjord-muted: "#3d5368"
  cobalt-signal: "#135399"
  cobalt-deep: "#0d3e73"
  amber-watch: "#9a5209"
typography:
  display:
    fontFamily: "Avenir Next, Segoe UI, Helvetica Neue, sans-serif"
    fontSize: "2.25rem"
    fontWeight: 700
    lineHeight: 1.18
  headline:
    fontFamily: "Avenir Next, Segoe UI, Helvetica Neue, sans-serif"
    fontSize: "1.375rem"
    fontWeight: 600
    lineHeight: 1.3
  title:
    fontFamily: "Avenir Next, Segoe UI, Helvetica Neue, sans-serif"
    fontSize: "1.0625rem"
    fontWeight: 600
    lineHeight: 1.35
  body:
    fontFamily: "Avenir Next, Segoe UI, Helvetica Neue, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.6
  mono:
    fontFamily: "SFMono-Regular, Menlo, Consolas, monospace"
    fontSize: "0.9375rem"
    fontWeight: 600
    lineHeight: 1.45
rounded:
  sm: "6px"
  md: "10px"
spacing:
  xs: "6px"
  sm: "12px"
  md: "20px"
  lg: "32px"
  xl: "48px"
components:
  button-primary:
    backgroundColor: "{colors.cobalt-signal}"
    textColor: "#ffffff"
    rounded: "{rounded.sm}"
    padding: "12px 20px"
  button-secondary:
    backgroundColor: "{colors.slate-surface}"
    textColor: "{colors.fjord-ink}"
    rounded: "{rounded.sm}"
    padding: "12px 18px"
---

# Design System: Kestrel Gauge

## Overview

**Creative North Star: "Sổ Trực Thủy Văn Lạnh"**

Giao diện lấy cảm hứng từ bảng đo khí tượng thủy văn phòng trực đập: nền xám lam khoáng chất mát (`#f1f5f9`), bề mặt bảng sáng rõ (`#ffffff`), mực chữ xanh biển sâu (`#0f2233`) và chữ số đồng hồ monospace sắc nét.

**Key Characteristics:**
- Tông màu xám lam khoáng chất mát kết hợp mặt bảng sáng và chữ xanh biển sâu.
- Số liệu cao trình, mã trạm và giờ quan trắc hiển thị bằng chữ monospace thẳng cột.
- Giọng điệu trực ban kỹ thuật điềm tĩnh, ưu tiên tra cứu nhanh số đo thực địa.

## Colors

Bảng màu khoáng chất lạnh gợi mặt nước hồ chứa và thép không gỉ của trạm đo.

### Primary
- **Cobalt Signal** (`#135399`): Nút xuất biên bản CSV và tác vụ điều hướng chính.
- **Cobalt Deep** (`#0d3e73`): Trạng thái nhấn đậm của nút chính.

### Neutral
- **Fjord Background** (`#f1f5f9`): Nền trang chính.
- **Slate Surface** (`#ffffff`): Bề mặt bảng số liệu chính.
- **Slate Subtle** (`#e3ebf3`): Dải nền phụ của vùng thông tin ca trực và chỉ số trạm.
- **Fjord Ink** (`#0f2233`): Chữ chính.
- **Fjord Muted** (`#3d5368`): Chữ phụ, mốc thời gian và nhãn đơn vị đo.

## Typography

Sử dụng họ chữ không chân kỹ thuật `Avenir Next, Segoe UI, Helvetica Neue, sans-serif` cho hệ tiêu đề và văn bản thuyết minh theo thang `display` – `body`; dùng `SFMono-Regular, Menlo, Consolas, monospace` cho cao trình mực nước, mã trạm và mốc giờ.

## Layout

Khung nội dung rộng tối đa `1080px` căn giữa theo trục trang, bố trí thanh thông tin ca trực ở đầu trang, lưới 3 cột mặt cắt quan trắc ở giữa và bảng nhật ký đối chiếu phía dưới theo thang `spacing` (`xs` đến `xl`).

## Shapes

Bo góc `6px` (`rounded.sm`) cho nút thao tác và `10px` (`rounded.md`) cho các khối bề mặt chính, kết hợp đường viền mảnh `1px solid #cbd6e2`.

## Components

- **Buttons**: Nút chính dùng nền `#135399` chữ `#ffffff`; nút phụ dùng nền `#ffffff` hoặc `#e3ebf3` chữ `#0f2233` với viền `#cbd6e2`.
- **Watch Indicators**: Trạng thái cần theo dõi sát dùng sắc hổ phách trầm `#9a5209` trên nền bảng sáng.
