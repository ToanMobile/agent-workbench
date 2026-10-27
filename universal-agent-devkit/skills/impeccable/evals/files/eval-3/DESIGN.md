---
name: Meridian Cold-Chain
description: Sổ điều độ nhiệt độ container lạnh tuyến đường sắt Bắc – Nam
colors:
  mineral-bg: "#edf3f1"
  card-surface: "#ffffff"
  spruce-tint: "#dfece7"
  border-mineral: "#c3d5ce"
  pine-ink: "#102620"
  pine-muted: "#35544b"
  spruce-action: "#18644c"
  spruce-deep: "#104936"
  rust-alert: "#9e3b1c"
typography:
  display:
    fontFamily: "Avenir Next, Segoe UI, Helvetica Neue, sans-serif"
    fontSize: "2.25rem"
    fontWeight: 700
    lineHeight: 1.2
  headline:
    fontFamily: "Avenir Next, Segoe UI, Helvetica Neue, sans-serif"
    fontSize: "1.375rem"
    fontWeight: 600
    lineHeight: 1.32
  title:
    fontFamily: "Avenir Next, Segoe UI, Helvetica Neue, sans-serif"
    fontSize: "1.0625rem"
    fontWeight: 600
    lineHeight: 1.36
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
    backgroundColor: "{colors.spruce-action}"
    textColor: "#ffffff"
    rounded: "{rounded.sm}"
    padding: "12px 20px"
  button-secondary:
    backgroundColor: "{colors.card-surface}"
    textColor: "{colors.pine-ink}"
    rounded: "{rounded.sm}"
    padding: "12px 18px"
---

# Design System: Meridian Cold-Chain

## Overview

**Creative North Star: "Phiếu Điều Độ Chuỗi Lạnh Đường Sắt"**

Giao diện kết hợp nền xám bạc hà khoáng chất (`#edf3f1`), mặt phiếu trắng sạch (`#ffffff`) và sắc xanh tùng đậm (`#18644c`) gợi sơn container lạnh chuyên dụng và biển hiệu ga hàng hóa.

**Key Characteristics:**
- Bảng màu xám bạc hà khoáng chất kết hợp mặt phiếu sáng và sắc xanh tùng công nghiệp.
- Mã hiệu container, ngưỡng nhiệt độ cài đặt/thực đo và điện áp toa phát hiển thị bằng chữ monospace.
- Phong cách sổ giao nhận đường sắt – kho lạnh rành mạch, trung thực với dữ liệu hiện trường.

## Colors

Bảng màu xanh khoáng chất mát và mực rừng thông đậm dành cho nghiệp vụ vận tải lạnh.

### Primary
- **Spruce Action** (`#18644c`): Nút mở bảng kê container lạnh và tác vụ điều độ chính.
- **Spruce Deep** (`#104936`): Trạng thái nhấn đậm của nút chính.

### Neutral
- **Mineral Background** (`#edf3f1`): Nền trang chính.
- **Card Surface** (`#ffffff`): Bề mặt phiếu điều độ.
- **Spruce Tint** (`#dfece7`): Dải nền phụ cho cụm thông số nguồn điện và nút thứ cấp.
- **Pine Ink** (`#102620`): Chữ chính.
- **Pine Muted** (`#35544b`): Chữ phụ, thông tin đoàn tàu và ghi chú vận hành có pha sắc xanh thông.

## Typography

Sử dụng họ chữ `Avenir Next, Segoe UI, Helvetica Neue, sans-serif` cho tiêu đề và nội dung nghiệp vụ theo thang `display` – `body`; dùng `SFMono-Regular, Menlo, Consolas, monospace` cho số hiệu container, nhiệt độ buồng lạnh và giờ tàu chạy.

## Layout

Khung nội dung rộng tối đa `1080px` căn giữa, sắp xếp theo trình tự thanh thông tin đoàn tàu, khối tổng quan ca trực, lưới 3 ga kiểm soát nhiệt độ và bảng kê container cần lưu ý theo thang `spacing` (`xs` đến `xl`).

## Shapes

Bo góc `6px` (`rounded.sm`) cho nút thao tác và `10px` (`rounded.md`) cho các khối phiếu điều độ, đường viền `1px solid #c3d5ce`.

## Components

- **Buttons**: Nút chính dùng nền xanh tùng `#18644c` chữ `#ffffff`; nút phụ dùng nền `#ffffff` hoặc `#dfece7` chữ `#102620` viền `#c3d5ce`.
- **Alert Markers**: Ghi chú lệch ngưỡng nhiệt độ hoặc cần kiểm tra gioăng cửa dùng sắc nâu gỉ `#9e3b1c` in đậm.
