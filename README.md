# ⚡ VCRT OS - Modern Control Center for OpenWrt

<p align="center">
  <img src="https://img.shields.io/badge/OpenWrt-25.12-blue?style=for-the-badge&logo=openwrt&logoColor=white" alt="OpenWrt" />
  <img src="https://img.shields.io/badge/Target-MediaTek%20MT7620A-green?style=for-the-badge" alt="MT7620A" />
  <img src="https://img.shields.io/badge/React-18-61DAFB?style=for-the-badge&logo=react&logoColor=black" alt="React" />
  <img src="https://img.shields.io/badge/NextDNS-Cloud%20Suite-blueviolet?style=for-the-badge&logo=nextdns&logoColor=white" alt="NextDNS" />
  <img src="https://img.shields.io/badge/License-MIT-emerald?style=for-the-badge" alt="License" />
</p>

**VCRT OS** là hệ thống bảng điều khiển quản trị router OpenWrt hiện đại, siêu nhẹ, tối ưu hóa đặc biệt cho các dòng router cấu hình khiêm tốn như **Xiaomi MiWiFi Mini (MediaTek MT7620A, 128MB RAM, 16MB Flash)**.

---

## ✨ Điểm Nổi Bật

- 🏎️ **Siêu Nhẹ & Tối Ưu RAM**: Backend CGI thuần POSIX Shell (`/bin/sh`), không tải nặng CPU hay chiếm dụng RAM hạn chế của router.
- 📊 **100% Dữ Liệu Thật**: Toàn bộ số liệu CPU, RAM, băng thông tải về/tải lên, bảng lưu lượng mạng được lấy trực tiếp từ Kernel Linux (`/proc/net/dev`, `/proc/stat`, `/proc/meminfo`), nói không với dữ liệu mock ảo.
- 🛡️ **Tích Hợp Toàn Diện NextDNS Cloud Suite**:
  - **Quản trị trực tiếp qua REST API**: Đồng bộ cấu hình bảo vệ mà không cần đăng nhập vào `my.nextdns.io`.
  - **Nhật ký truy vấn thời gian thực (Logs Streaming)**: Cập nhật live stream mỗi 3.5s, nhận diện tên miền bị chặn với vạch chỉ báo đỏ, hiển thị favicon và IP thiết bị.
  - **Thư viện bộ lọc "Add a blocklist"**: Tìm kiếm và kích hoạt hơn 83 bộ lọc cộng đồng quốc tế (*NextDNS Ads & Trackers, AdGuard, OISD, EasyList, HaGeZi...*).
  - **Bộ chọn khung thời gian thống kê**: `Last 30m`, `Last 6h`, `Last 24h`, `Last 7d`, `Last 30d`, `Last 3M`.
  - **Phân tích chuyên sâu**: Thống kê nguồn chặn (Reasons), giao thức DNS (UDP vs TCP), xác thực an toàn DNSSEC và lọc Tên miền gốc (Root Domains).
  - **Chặn ứng dụng 1 chạm**: TikTok, Facebook, YouTube, Discord, Roblox, Game Online, Web người lớn 18+.
- 📱 **Giao Diện Dark Cyberpunk Đáp Ứng Cao**: Xây dựng bằng React 18 + Tailwind CSS + Vite, tối ưu vuốt chạm mượt mà trên cả điện thoại lẫn máy tính.
- 🔐 **Bảo Mật Web & Phiên Làm Việc**: Màn hình đăng nhập bảo vệ router, quản lý session token và hỗ trợ đổi mật khẩu linh hoạt.

---

## 🏗️ Kiến Trúc Hệ Thống

```
┌─────────────────────────────────────────────────────────┐
│              VCRT Web Dashboard (React + Vite)          │
│              Dark Cyberpunk UI / Responsive SPA         │
└────────────────────────────┬────────────────────────────┘
                             │ HTTP JSON API
┌────────────────────────────▼────────────────────────────┐
│          OpenWrt uHTTPd Web Server (/cgi-bin/vcrt)      │
│          POSIX sh CGI Engine - ZERO Overhead            │
└──────────────┬─────────────────────────────┬────────────┘
               │                             │
┌──────────────▼──────────────┐ ┌────────────▼────────────┐
│     Linux Kernel Subsystem  │ │  NextDNS Cloud REST API │
│ /proc/net/dev, /proc/stat   │ │ api.nextdns.io (Proxy)  │
│ /proc/meminfo, UCI configs  │ │ Profiles, Logs, Filters │
└─────────────────────────────┘ └─────────────────────────┘
```

---

## 🚀 Hướng Dẫn Cài Đặt

### Yêu cầu
- Router chạy OpenWrt (hoặc bản build Kwrt) phiên bản 21.02 trở lên.
- Đã cài đặt gói `curl`, `uhttpd` và `dnsmasq`.

### Cài đặt qua SSH
Chạy lệnh sau trên terminal SSH của router:

```sh
curl -L -k -o /tmp/deploy_vcrt.tar.gz "https://github.com/lecuong2512/vcrt/raw/main/deploy_vcrt.tar.gz" && cd /tmp && tar -xzf deploy_vcrt.tar.gz && sh install.sh
```

Sau khi cài đặt thành công, truy cập:
👉 **`http://<ip của router>/vcrt/`**
- Tài khoản mặc định: `admin`
- Mật khẩu mặc định: `admin`

---

## 📁 Cấu Trúc Thư Mục

```
.
├── vcrt_cgi.sh              # Backend CGI xử lý dữ liệu hệ thống & NextDNS Proxy
├── fix_wifi_and_clean_lang.sh # Script dọn dẹp ngôn ngữ & tối ưu Wi-Fi
├── optimize_miwifi.sh        # Tinh chỉnh hiệu năng kernel & sysctl
├── setup_telegram_bot.sh     # Script mẫu cài đặt Telegram Bot thông báo
├── Des/                     # Mã nguồn giao diện Web Frontend (React + Vite)
│   ├── src/
│   │   ├── App.tsx          # Dashboard, Thiết bị, Wi-Fi, Cài đặt & Authentication
│   │   ├── NextDNSScreen.tsx# Bảng điều khiển NextDNS Cloud toàn diện
│   │   ├── AddBlocklistModal.tsx # Modal thư viện 83 bộ lọc cộng đồng
│   │   ├── LoginScreen.tsx  # Màn hình đăng nhập bảo mật
│   │   └── api.ts           # Cầu nối gọi API router & quản lý session token
│   ├── package.json
│   └── vite.config.ts
└── README.md
```

---

## 📄 Bản Quyền

Phát hành dưới giấy phép [MIT License](LICENSE). Đóng góp và phát triển bởi [lecuong2512](https://github.com/lecuong2512).
