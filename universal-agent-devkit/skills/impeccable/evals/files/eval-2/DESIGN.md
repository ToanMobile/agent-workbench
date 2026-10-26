---
name: Calibra Room
description: Sổ biên bản hiệu chuẩn âm học phòng dựng và loa kiểm âm
colors:
  studio-bg: "#10161d"
  panel-surface: "#18212b"
  panel-raised: "#202c39"
  border-slate: "#2f3f50"
  ice-ink: "#e9eff5"
  slate-secondary: "#a9b8c7"
  copper-meter: "#e08432"
  copper-ink: "#10161d"
  sage-pass: "#6cc497"
typography:
  display:
    fontFamily: "Charter, Georgia, Cambria, serif"
    fontSize: "2.375rem"
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
    lineHeight: 1.38
  body:
    fontFamily: "Avenir Next, Segoe UI, Helvetica Neue, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.62
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
    backgroundColor: "{colors.copper-meter}"
    textColor: "{colors.copper-ink}"
    rounded: "{rounded.sm}"
    padding: "12px 20px"
  button-secondary:
    backgroundColor: "{colors.panel-raised}"
    textColor: "{colors.ice-ink}"
    rounded: "{rounded.sm}"
    padding: "12px 18px"
---

# Design System: Calibra Room

## Overview

**Creative North Star: "Mặt Máy Đo Phòng Kiểm Âm"**

Giao diện nền tối than chì lạnh (`#10161d`) phục vụ môi trường phòng dựng ít sáng, kết hợp sắc đồng hổ phách (`#e08432`) gợi kim đồng hồ VU cổ điển và chữ trắng băng (`#e9eff5`) rõ nét.

**Key Characteristics:**
- Nền tối than chì lạnh dịu mắt khi hiển thị lâu trong phòng điều khiển âm thanh.
- Điểm nhấn đồng hổ phách dành riêng cho tác vụ quét dải tần và nhãn vùng tần số.
- Kết hợp tiêu đề chính có chân kiểu đứng với chữ số kỹ thuật monospace rõ gọn.

## Colors

Bảng màu tối kỹ thuật lấy cảm hứng từ bàn điều khiển phòng kiểm âm và thang vạch kim đồng hồ đo mức âm.

### Primary
- **Copper Meter** (`#e08432`): Nút khởi tạo phép quét dải tần mới và nhãn vùng tần số.

### Neutral
- **Studio Background** (`#10161d`): Nền chính toàn trang.
- **Panel Surface** (`#18212b`): Bề mặt bảng thông tin phiên đo.
- **Panel Raised** (`#202c39`): Nền phụ cho nút thứ cấp và vùng dữ liệu nhánh.
- **Ice Ink** (`#e9eff5`): Chữ chính trên nền tối.
- **Slate Secondary** (`#a9b8c7`): Chữ phụ, thông số phòng và ghi chú hạng mục đo.

## Typography

Tiêu đề lớn dùng `Charter, Georgia, Cambria, serif` kiểu đứng (roman); các tiêu đề mục và văn bản thuyết minh dùng `Avenir Next, Segoe UI, Helvetica Neue, sans-serif` theo thang `headline` – `body`; dải tần Hz/kHz, mức dB và mã thiết bị dùng `SFMono-Regular, Menlo, Consolas, monospace`.

## Layout

Khung nội dung rộng tối đa `1060px` căn giữa, gồm thanh tiêu đề phiên đo, khối tóm tắt đáp tuyến, lưới 3 vùng tần số và danh mục kết quả RT60 theo thang `spacing` (`xs` đến `xl`).

## Shapes

Bo góc `6px` (`rounded.sm`) cho nút điều khiển và `10px` (`rounded.md`) cho các mặt bảng nền tối, viền mảnh `1px solid #2f3f50`.

## Components

- **Buttons**: Nút chính dùng nền đồng `#e08432` với chữ tối `#10161d`; nút phụ dùng nền `#202c39` chữ `#e9eff5` viền `#2f3f50`.
- **Status Badges**: Nhãn nghiệm thu đạt chuẩn dùng sắc xanh lá dịu `#6cc497` dạng chữ monospace.
