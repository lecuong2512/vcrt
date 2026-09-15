# ⚡ VCRT OS v2.0 - Multi-Platform Cyber Router OS for OpenWrt

<p align="center">
  <img src="https://img.shields.io/badge/OpenWrt-21.02%20--%2025.12%20(KWrt)-blue?style=for-the-badge&logo=openwrt&logoColor=white" alt="OpenWrt Support" />
  <img src="https://img.shields.io/badge/Architecture-MIPS%20%7C%20ARM%20%7C%20Filogic%20%7C%20x86-success?style=for-the-badge" alt="Architecture" />
  <img src="https://img.shields.io/badge/React-19-61DAFB?style=for-the-badge&logo=react&logoColor=black" alt="React 19" />
  <img src="https://img.shields.io/badge/Tailwind-v4-38B2AC?style=for-the-badge&logo=tailwind-css&logoColor=white" alt="Tailwind v4" />
  <img src="https://img.shields.io/badge/ZeroTier-Remote%20VPN%20v2.0-orange?style=for-the-badge&logo=zerotier&logoColor=white" alt="ZeroTier" />
  <img src="https://img.shields.io/badge/NextDNS-Cloud%20Suite%20v2.0-blueviolet?style=for-the-badge&logo=nextdns&logoColor=white" alt="NextDNS" />
  <img src="https://img.shields.io/badge/License-MIT-emerald?style=for-the-badge" alt="License" />
</p>

**VCRT OS v2.0** là hệ điều hành bảng điều khiển quản trị router OpenWrt hiện đại, siêu nhẹ, được thiết kế theo phong cách Cyberpunk Dark Theme sắc nét. Hệ thống hỗ trợ đa kiến trúc phần cứng (từ các dòng router kinh điển có bộ nhớ nhỏ như **Xiaomi MiWiFi Mini, Xiaomi Mi Router 4A/Gigabit** đến các dòng hiện đại như **GL.iNet series**, **MediaTek Filogic MT798x**, và **Generic OpenWrt / x86_64**).

---

## 🌟 Điểm Nổi Bật Trên Phiên Bản v2.0

- 🏎️ **Siêu Nhẹ & Tối Ưu RAM (0% Overhead)**: Backend CGI thuần POSIX Shell BusyBox (`/bin/sh`), thời gian phản hồi API trung bình dưới 50ms, không đòi hỏi runtime cồng kềnh (Node.js, Python), giải phóng bộ nhớ RAM quý giá của router.
- 📊 **100% Dữ Liệu Thực Từ Nhân Linux**: Toàn bộ chỉ số xung nhịp CPU, RAM, băng thông tải về/tải lên, kết nối Wi-Fi được đọc trực tiếp từ `/proc/net/dev`, `/proc/stat`, `/proc/meminfo`, bảng ARP và `iwinfo`, loại bỏ hoàn toàn số liệu mock ảo.
- 🧩 **Platform Abstraction Layer (PAL)**: Tự động nhận diện phần cứng router (CPU, RAM, chip Wi-Fi, MTU tối ưu, HWNAT/PPE offloading), tự động thích ứng với cấu hình riêng của từng nhà sản xuất.
- 🛡️ **Watchdog Rollback An Toàn (Safety Rollback Engine)**: Tự động sao lưu và kích hoạt bộ đếm ngược 60 giây khi thay đổi cấu hình Wi-Fi hoặc mạng WAN. Nếu router mất kết nối sau khi áp dụng, hệ thống sẽ tự động khôi phục về trạng thái trước đó, chống nguy cơ "mất mạng từ xa" hoặc lỗi cấu hình.
- ☁️ **NextDNS Cloud Suite v2.0 Toàn Diện**:
  - **Tích hợp Native dnsmasq**: Tận dụng trực tiếp máy chủ DNS có sẵn trên router, không cần cài binary Go nặng hơn 10MB gây tràn bộ nhớ flash.
  - **Quản trị Cloud REST API**: Xem và thay đổi Profiles, công tắc bảo vệ, kiểm soát phụ huynh, danh sách cho phép/chặn không cần mở trang `my.nextdns.io`.
  - **Live Streaming Logs thời gian thực**: Cập nhật trực tiếp nhật ký truy vấn mỗi 3.5s, nhận diện tên miền bị chặn với viền cảnh báo đỏ, hiển thị favicon và tên thiết bị gửi truy vấn.
  - **Thư viện bộ lọc "Add a blocklist"**: Tìm kiếm và kích hoạt hơn 83 bộ lọc cộng đồng hàng đầu thế giới (*NextDNS Ads & Trackers, AdGuard, OISD, HaGeZi, EasyList...*).
  - **Chặn ứng dụng 1 chạm**: TikTok, Facebook, YouTube, Discord, Roblox, Game Online, Web người lớn 18+.
  - **Tự động đồng bộ Link IP**: Tự động cập nhật địa chỉ WAN IP lên NextDNS mỗi khi mạng kết nối lại (hỗ trợ DDNS NextDNS).
- 🚀 **ZeroTier Remote Access v2.0**:
  - Truy cập quản trị router và toàn bộ mạng LAN nội bộ từ bất cứ đâu trên thế giới qua kết nối mạng ảo P2P an toàn.
  - Tự động cấu hình TUN device (`/dev/net/tun`), zone tường lửa `zerotier` với Masquerading (NAT), chuyển tiếp hai chiều giữa LAN và ZeroTier, mở cổng UDP 9993.
  - Quản lý trạng thái kết nối, tham gia/rời mạng ZeroTier trực tiếp từ Web UI.
- 🤖 **Telegram Bot Daemon v2.0 (Multi-Watcher Engine)**:
  - Chạy nền dưới sự giám sát của OpenWrt `procd`, tự động khởi động cùng hệ thống và tự hồi sinh khi có sự cố.
  - **4 Bộ giám sát độc lập (4 Watchers)**:
    1. *Live Wi-Fi Join Monitor*: Quét chu kỳ 3s, gửi cảnh báo ngay khi có thiết bị kết nối Wi-Fi kèm nút bấm Inline Chặn 1h, 2h hoặc Vĩnh viễn.
    2. *Timed Block Expire Watcher*: Tự động mở chặn khi hết thời gian chỉ định và thông báo đến admin.
    3. *Traffic DB & Daily Report*: Ghi nhận lưu lượng mỗi phút vào CSDL nhẹ, gửi báo cáo tổng kết sử dụng mạng vào 20:00 hàng ngày.
    4. *System Update & Heartbeat*: Theo dõi cập nhật phần mềm và tình trạng vận hành của router.
- 🎨 **Web UI v2.0 Clean Modern**:
  - Xây dựng bằng React 19 + Tailwind CSS v4 + Vite 8.
  - Biểu đồ lưu lượng Canvas HTML5 siêu nhẹ, không phụ thuộc thư viện nặng Chart.js.
  - Logo vector SVG Zero-loss hiển thị sắc nét trên mọi độ phân giải màn hình.
  - Hỗ trợ PWA (Progressive Web App) giúp cài đặt như một ứng dụng độc lập trên iOS, Android và máy tính.
- 🔒 **Quản Trị Thiết Bị & Kiểm Soát Truy Cập**:
  - Đặt tên gợi nhớ cho thiết bị mạng (lưu cục bộ trên router).
  - Chặn mạng linh hoạt: Chặn mềm (Soft Block - chặn DNS) và Chặn cứng (Hard Block - chặn IP/MAC iptables).
  - Hẹn giờ chặn linh hoạt (15 phút, 30 phút, 1 giờ, 2 giờ, 8 giờ, đến sáng).

---

## 🏗️ Kiến Trúc Hệ Thống v2.0

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                   VCRT Web Dashboard v2.0 (React 19 + PWA)                  │
│               Dark Cyberpunk UI / Canvas Engine / Responsive                │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │ HTTP / JSON REST API
┌──────────────────────────────────────▼──────────────────────────────────────┐
│                    uHTTPd Web Server (/cgi-bin/vcrt)                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                    VCRT Core Engine (POSIX Shell /bin/sh)                   │
├─────────────────────────┬──────────────────────────────────┬────────────────┤
│    Modules (/modules)   │         Libraries (/lib)         │ Platforms (/platforms)│
│  - mod_auth.sh          │  - constants.sh                  │  - generic.sh  │
│  - mod_system.sh        │  - json_helper.sh (RFC 8259)     │  - xiaomi_mini.sh
│  - mod_wifi.sh          │  - platform.sh (Auto Detection)  │  - xiaomi_4a.sh│
│  - mod_network.sh       │  - watchdog.sh (Safe Rollback)   │  - glinet.sh   │
│  - mod_clients.sh       │                                  │  - filogic.sh  │
│  - mod_nextdns.sh       │                                  │                │
│  - mod_zerotier.sh      │                                  │                │
│  - mod_telegram.sh      │                                  │                │
│  - mod_update.sh        │                                  │                │
└────────────┬────────────┴─────────────────┬────────────────┴────────┬───────┘
             │                              │                         │
┌────────────▼────────────┐   ┌─────────────▼─────────────┐   ┌───────▼───────┐
│     OpenWrt Subsystem   │   │  Telegram Bot procd Daemon│   │  Cloud APIs   │
│  - Linux Kernel /proc   │   │  - Wi-Fi Join Watcher     │   │  - NextDNS    │
│  - UCI Configuration    │   │  - Timed Block Watcher    │   │  - ZeroTier   │
│  - iptables / nftables  │   │  - Traffic DB & Daily Rep │   │  - Telegram   │
│  - dnsmasq / iwinfo     │   │  - Interactive Keyboards  │   │               │
└─────────────────────────┘   └───────────────────────────┘   └───────────────┘
```

---

## 📋 Bảng Tương Thích Phần Cứng (Hardware Matrix)

| Thiết Bị | Chipset (SoC) | RAM / Flash | Chuẩn Wi-Fi | Bản OpenWrt Hỗ Trợ | Tình Trạng |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **Xiaomi MiWiFi Mini** | MT7620A (MIPS 580MHz) | 128MB / 16MB | AC1200 (2.4G + 5G) | KWrt 25.12 / OpenWrt 21.02+ | 🟢 Hoàn Hảo |
| **Xiaomi Mi Router 4A Gigabit** | MT7621AT (Dual-Core 880MHz) | 128MB / 16MB | AC1200 (Full Gigabit) | OpenWrt 22.03 / 23.05 | 🟢 Hoàn Hảo |
| **Xiaomi Mi Router 4C** | MT7628DA (MIPS 580MHz) | 64MB / 16MB | N300 (Single-band) | OpenWrt 21.02 / 22.03 | 🟢 Hoàn Hảo |
| **GL.iNet GL-MT3000 (Beryl AX)**| MT7981B (Filogic 820 Dual) | 512MB / 256MB| Wi-Fi 6 AX3000 | OpenWrt 21.02 / GL.iNet v4 | 🟢 Hoàn Hảo |
| **GL.iNet GL-MT1300 (Beryl)** | MT7621A (Dual-Core 880MHz) | 256MB / 32MB | AC1300 | OpenWrt 21.02 / 23.05 | 🟢 Hoàn Hảo |
| **GL.iNet GL-AR750S (Slate)** | Qualcomm QCA9563 | 128MB / 16MB | AC750 | OpenWrt 21.02 / 22.03 | 🟢 Hoàn Hảo |
| **MediaTek Filogic Series (MT7981/MT7986)** | Filogic 820 / 830 (ARMv8) | 256MB-1GB | Wi-Fi 6 AX3000 / AX6000 | OpenWrt 23.05 / 24.10 / Snap | 🟢 Hoàn Hảo |
| **Generic OpenWrt Router / x86_64** | MIPS / ARM / x86_64 | Mọi cấu hình | Mọi chuẩn Wi-Fi / LAN | OpenWrt 21.02 trở lên | 🟢 Hoàn Hảo |

---

## 🚀 Hướng Dẫn Cài Đặt Nhanh

### Yêu Cầu Tiền Đề
- Router đã cài OpenWrt hoặc các bản biến thể (KWrt, ImmortalWrt) từ **21.02** trở lên.
- Router đã kết nối Internet (có thể ping được `github.com`).
- Dung lượng bộ nhớ trống tối thiểu: **1.5 MB** trên vùng overlay.

---

### Cách 1: Cài Đặt Tự Động 1 Dòng Lệnh Duy Nhất (Khuyên Dùng)

Mở SSH vào router (bằng PuTTY, Termius hoặc Terminal) và dán lệnh sau:

```sh
curl -sSL -k "https://raw.githubusercontent.com/lecuong2512/vcrt/main/install.sh" | sh
```

> [!TIP]
> Script sẽ tự động nhận diện thiết bị phần cứng, tải gói cài đặt chính xác từ GitHub, thiết lập các zone tường lửa cần thiết, cài đặt Web UI, cấu hình daemon Telegram Bot và tối ưu thông số mạng tự động.

---

### Cách 2: Tải Gói Nén Deploy Và Cài Đặt Thủ Công

Nếu gặp sự cố đường truyền mạng hoặc muốn cài đặt qua tệp nén đã tải trước:

```sh
curl -L -k -o /tmp/deploy_vcrt.tar.gz "https://github.com/lecuong2512/vcrt/raw/main/deploy_vcrt.tar.gz" && cd /tmp && tar -xzf deploy_vcrt.tar.gz && sh install.sh
```

---

### 🌐 Truy Cập Bảng Điều Khiển

Sau khi script thông báo hoàn tất, mở trình duyệt và truy cập:
👉 **`http://192.168.1.1/vcrt/`** hoặc **`http://vcrt.lan/vcrt/`**

- **Tài khoản mặc định:** `admin`
- **Mật khẩu mặc định:** `admin`

*(Khuyến nghị đổi mật khẩu ngay sau lần đầu đăng nhập tại mục Cài đặt).*

---

## ⚙️ Hướng Dẫn Cấu Hình Tính Năng Mở Rộng

### 1. Cấu Hình NextDNS Cloud Suite v2.0
1. Đăng ký tài khoản miễn phí tại [my.nextdns.io](https://my.nextdns.io).
2. Lấy **Profile ID** (chuỗi 6 ký tự tại trang chủ NextDNS) và **API Key** (tại mục `Account` -> `API Key`).
3. Mở Web UI VCRT -> chọn tab **NextDNS**.
4. Nhập Profile ID và API Key, sau đó bấm **Lưu cấu hình**.
5. Bật công tắc **Kích hoạt NextDNS**: Hệ thống sẽ tự động chuyển tiếp truy vấn của `dnsmasq` sang NextDNS, đồng thời tự động cập nhật Link IP khi IP WAN thay đổi.
6. Bạn có thể theo dõi **Live Logs**, bật/tắt **Security**, quản lý **Blocklists** (hơn 83 bộ lọc) và **Chặn ứng dụng** (TikTok, YouTube, Facebook, Roblox...) trực tiếp trên giao diện VCRT.

---

### 2. Cấu Hình ZeroTier Remote Access v2.0
1. Tạo một mạng riêng miễn phí tại [my.zerotier.com](https://my.zerotier.com) và sao chép **Network ID** (16 ký tự hexa).
2. Trên Web UI VCRT -> chọn tab **Cài đặt** -> mục **ZeroTier VPN**.
3. Nhập Network ID và bấm **Tham gia mạng (Join)**.
4. Mở trang quản trị ZeroTier trên trình duyệt, tìm node mới của router và tích chọn ô **Auth**.
5. Bây giờ bạn có thể truy cập router và toàn bộ thiết bị mạng gia đình từ bất cứ đâu thông qua địa chỉ IP ZeroTier (ví dụ: `http://10.147.x.x/vcrt/`) với tốc độ P2P cao nhất mà không cần mở port modem nhà mạng!

---

### 3. Cấu Hình Telegram Bot Daemon v2.0
1. Mở ứng dụng Telegram, tìm bot [@BotFather](https://t.me/BotFather), gửi lệnh `/newbot` và làm theo hướng dẫn để nhận **Bot Token**.
2. Tìm bot [@userinfobot](https://t.me/userinfobot) để lấy **Chat ID** của bạn. (Nếu dùng trong nhóm Telegram, thêm bot vào nhóm và lấy Group ID có dấu trừ ở đầu).
3. Mở Web UI VCRT -> chọn tab **Cài đặt** -> mục **Telegram Bot**.
4. Bật công tắc **Kích hoạt Telegram Bot**, dán Token và Chat ID, sau đó bấm **Lưu & Khởi động lại Bot**.
5. Nhận thông báo khởi động tức thì trên Telegram cùng menu phím bấm tương tác:
   - `/status` : Xem tổng quan CPU, RAM, nhiệt độ, IP WAN/LAN, thời gian hoạt động.
   - `/clients`: Xem danh sách thiết bị đang kết nối mạng (IP, MAC, Tên, Lưu lượng).
   - `/traffic`: Xem lưu lượng tải về/tải lên trong ngày và tháng.
   - `/wifi`   : Xem thông tin 2 băng tần 2.4GHz & 5GHz, số lượng máy kết nối.
   - `/block <MAC>` : Chặn kết nối mạng của thiết bị.
   - `/tempblock <MAC> <phút>` : Chặn mạng có hẹn giờ (hết giờ tự mở).
   - `/unblock <MAC>` : Gỡ chặn thiết bị.
   - `/ping`   : Đo độ trễ Internet tới các máy chủ lớn.
   - `/help`   : Hướng dẫn sử dụng chi tiết.

---

### 4. Cơ Chế Watchdog Rollback An Toàn
Khi bạn cấu hình lại mạng Wi-Fi (đổi SSID, đổi mật khẩu, đổi kênh) hoặc tinh chỉnh cấu hình giao diện mạng WAN/LAN:
1. Hệ thống tự động tạo bản sao lưu cấu hình chuẩn vào `/tmp/vcrt_<dịch vụ>_wd.bak`.
2. Kích hoạt bộ đếm ngược 60 giây ngầm (`watchdog_arm`).
3. Dịch vụ Wi-Fi/Mạng được khởi động lại để áp dụng cấu hình mới.
4. Nếu cấu hình chính xác và trình duyệt kết nối lại thành công, Web UI sẽ tự động gửi lệnh xác nhận (`watchdog_confirm`) để hủy bộ đếm và lưu cấu hình vĩnh viễn.
5. Nếu cấu hình sai khiến router bị rớt mạng hoàn toàn, hết 60 giây Watchdog sẽ tự động kích hoạt `watchdog_rollback`, khôi phục lại cấu hình gốc và bật lại Wi-Fi, giúp bạn không bao giờ phải ấn nút Reset cứng trên router!

---

## 📁 Cấu Trúc Thư Mục Dự Án

```
.
├── backend/                  # Mã nguồn Backend Modular POSIX Shell
│   ├── vcrt_cgi.sh           # Gateway CGI chính tiếp nhận mọi HTTP request
│   ├── constants.sh          # Khai báo biến toàn cục và đường dẫn dùng chung
│   ├── lib/                  # Thư viện dùng chung
│   │   ├── constants.sh      # Định nghĩa các hằng số hệ thống
│   │   ├── json_helper.sh    # Bộ sinh và escape JSON chuẩn RFC 8259
│   │   ├── platform.sh       # Platform Abstraction Layer (tự nhận diện router)
│   │   └── watchdog.sh       # Động cơ tự động Rollback cấu hình an toàn
│   ├── modules/              # Các phân hệ chức năng độc lập
│   │   ├── mod_auth.sh       # Xác thực, băm mật khẩu sha256, quản lý session
│   │   ├── mod_clients.sh    # Quản lý thiết bị, chặn cứng, chặn mềm, hẹn giờ
│   │   ├── mod_network.sh    # Băng thông, WAN status, ping, Traceroute, MTU
│   │   ├── mod_nextdns.sh    # NextDNS REST API, DoH, Live Logs, Blocklists
│   │   ├── mod_system.sh     # CPU, RAM, nhiệt độ, Uptime, reboot, service
│   │   ├── mod_telegram.sh   # Cấu hình Bot Telegram, gửi tin nhắn, test bot
│   │   ├── mod_update.sh     # Kiểm tra và cập nhật OTA từ xa qua GitHub
│   │   ├── mod_wifi.sh       # Quản lý 2.4G/5G, phát sóng, công suất phát
│   │   └── mod_zerotier.sh   # ZeroTier status, join/leave, cấu hình tunnel
│   └── platforms/            # Tệp thích ứng riêng cho từng phần cứng router
│       ├── generic.sh        # Hỗ trợ đa năng cho mọi OpenWrt tiêu chuẩn
│       ├── xiaomi_mini.sh    # Xiaomi MiWiFi Mini (MT7620A, 128MB RAM)
│       ├── xiaomi_4a.sh      # Xiaomi Mi Router 4A Gigabit (MT7621AT)
│       ├── glinet.sh         # Các dòng router du lịch & gia đình GL.iNet
│       └── mediatek_filogic.sh # Router Wi-Fi 6 MediaTek Filogic MT798x
├── bot/                      # Telegram Bot Daemon v2.0
│   ├── vcrt_bot.sh           # Bộ điều phối chính Telegram Bot
│   ├── vcrt_bot_init         # Script khởi chạy dịch vụ qua procd (/etc/init.d/vcrt_bot)
│   └── lib/                  # Phân hệ chức năng của Telegram Bot
│       ├── commands.sh       # Xử lý các câu lệnh bot (/status, /block...)
│       ├── helpers.sh        # Hàm bổ trợ định dạng, che IP/MAC riêng tư
│       └── watchers.sh       # 4 bộ quan sát ngầm (Wi-Fi, Block, Traffic, Update)
├── web/                      # Mã nguồn Frontend Web UI v2.0
│   ├── src/                  # React 19 + TypeScript + Tailwind CSS v4
│   │   ├── api/              # Lớp giao tiếp API với router
│   │   ├── components/       # Các component UI tái sử dụng (Canvas Chart, Modal...)
│   │   ├── screens/          # Các màn hình chính (Dashboard, Clients, NextDNS...)
│   │   └── App.tsx           # Điều hướng chính và quản lý trạng thái
│   ├── public/               # Tài nguyên tĩnh, Web App Manifest cho PWA
│   ├── dist/                 # Bản build nén tối ưu triển khai trực tiếp lên router
│   ├── package.json
│   └── vite.config.ts
├── scripts/                  # Script cài đặt và tiện ích phụ trợ
│   ├── install.sh            # Script cài đặt tự động đa nền tảng
│   ├── optimize.sh           # Script tối ưu hóa bộ đệm mạng và sysctl
│   └── check_flash.sh        # Tiện ích kiểm tra dung lượng bộ nhớ
├── deploy_vcrt.tar.gz        # Gói nén triển khai đầy đủ của phiên bản v2.0
├── install.sh                # Script cài đặt 1 lệnh duy nhất tại thư mục gốc
├── version                   # Tệp phiên bản hiện tại (2.0.0)
└── README.md                 # Tài liệu hướng dẫn sử dụng toàn diện
```

---

## 🔒 Bảo Mật & An Toàn

- **Bảo Mật Xác Thực**: Mật khẩu quản trị được băm bằng thuật toán SHA-256 kết hợp với Salt ngẫu nhiên duy nhất cho mỗi router (`/etc/vcrt/salt`).
- **Quản Lý Phiên Phi Tập Trung**: Token phiên làm việc được tạo ngẫu nhiên, giới hạn thời gian hoạt động và tự động thu hồi khi người dùng đăng xuất.
- **Ẩn Danh Thông Tin Nhạy Cảm**: Telegram Bot hỗ trợ chế độ che dấu địa chỉ MAC và IP khi thông báo trong nhóm công cộng để bảo vệ quyền riêng tư gia đình.
- **Phòng Ngừa Xung Đột LuCI**: Tự động dọn dẹp các gói ngôn ngữ và cache lỗi thời, không gây ảnh hưởng đến hệ thống LuCI mặc định của OpenWrt.

---

## 📄 Giấy Phép & Tác Quyền

Dự án được phân phối dưới giấy phép mã nguồn mở [MIT License](LICENSE).  
Phát triển và duy trì bởi **[lecuong2512](https://github.com/lecuong2512)**.

---
<p align="center">
  <b>⚡ VCRT OS v2.0 — Đưa router OpenWrt của bạn lên tầm cao mới!</b>
</p>
