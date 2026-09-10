import { useTheme, ThemeProvider } from "./ThemeContext";
import { useState, useEffect, useRef, useMemo, useCallback } from "react";
import {
  fetchApi,
  postApi,
  checkAuthApi,
  logoutApi,
  changePasswordApi,
  getTelegramConfigApi,
  saveTelegramConfigApi,
  testTelegramBotApi,
  controlTelegramServiceApi,
  checkUpdateApi,
  doUpdateApi,
  setAutoUpdateApi,
  type TelegramConfig,
  type UpdateStatus
} from "./api";
import { VCRTLogo } from "./VCRTLogo";
import LoginScreen from "./LoginScreen";
import NextDNSScreen from "./NextDNSScreen";

// ─── Types ────────────────────────────────────────────────────────────────────
type Tab = "dashboard" | "clients" | "wifi" | "nextdns" | "settings";

interface ClientDevice {
  id: string;
  name: string;
  ip: string;
  mac: string;
  band: string;
  rssi: number;
  rxMbps?: number;
  txMbps?: number;
  connectedTime?: string;
  online?: boolean;
  blocked: boolean;
  softBlocked: boolean;
  blockRemain?: number;
  blockDuration?: number;
  icon: string;
}

interface ModemStatus {
  connected: boolean;
  model: string;
  operator: string;
  band: string;
  rsrp: number;
  sinr: number;
  messages: { id: number; from: string; time: string; body: string }[];
}

interface HardwareInfo {
  device_name: string;
  os_version: string;
  kernel_version: string;
  flash: {
    chip_mb?: number;
    total_mb: number;
    overlay_total_mb?: number;
    overlay_used_mb?: number;
    overlay_avail_mb?: number;
    overlay_pct?: number;
    used_mb: number;
    avail_mb: number;
    used_pct: number;
  };
}

interface PortStatus {
  wan: { up: boolean; speed: string; label: string };
  lan1: { up: boolean; speed: string; label: string };
  lan2: { up: boolean; speed: string; label: string };
  usb: { connected: boolean; name: string; label: string };
}

interface UplinkInfo {
  type: string;
  title: string;
  isp?: string;
  ssid: string;
  bssid: string;
  channel: string;
  band: string;
  signal_dbm: number;
  signal_pct: number;
  gateway: string;
}

// ─── Utility Helpers ──────────────────────────────────────────────────────────
function sparklinePath(data: number[], w: number, h: number): string {
  if (data.length < 2) return "";
  const max = Math.max(1, ...data);
  const min = Math.min(0, ...data);
  const range = max - min || 1;
  const stepX = w / (data.length - 1);
  const pts = data.map((v, i) => [i * stepX, h - ((v - min) / range) * (h - 6)]);
  let d = `M ${pts[0][0]} ${pts[0][1]}`;
  for (let i = 1; i < pts.length; i++) {
    const cpx = (pts[i - 1][0] + pts[i][0]) / 2;
    d += ` C ${cpx} ${pts[i - 1][1]} ${cpx} ${pts[i][1]} ${pts[i][0]} ${pts[i][1]}`;
  }
  return d;
}

function SignalBars({ rssi }: { rssi: number }) {
  const bars = rssi > -55 ? 4 : rssi > -65 ? 3 : rssi > -75 ? 2 : 1;
  const color = bars >= 3 ? "#10B981" : bars === 2 ? "#F59E0B" : "#EF4444";
  return (
    <span className="flex items-end gap-[2px]">
      {[1, 2, 3, 4].map((b) => (
        <span
          key={b}
          className="signal-bar inline-block w-[3px] rounded-sm"
          style={{
            height: `${4 + b * 3}px`,
            background: b <= bars ? color : "#222F46",
          }}
        />
      ))}
    </span>
  );
}

// ─── Bottom Navigation ────────────────────────────────────────────────────────
const NAV_ITEMS: { id: Tab; label: string; icon: string }[] = [
  { id: "dashboard", label: "Tổng quan", icon: "⚡" },
  { id: "clients", label: "Thiết bị", icon: "📱" },
  { id: "wifi", label: "Wi-Fi", icon: "📶" },
  { id: "nextdns", label: "NextDNS", icon: "🛡" },
  { id: "settings", label: "Cài đặt", icon: "⚙" },
];

function BottomNav({ active, onSelect }: { active: Tab; onSelect: (t: Tab) => void }) {
  return (
    <nav
      className="fixed bottom-0 left-0 right-0 z-50 pb-safe"
      style={{
        background: "var(--nav-bg)",
        borderTop: "1px solid var(--nav-border)",
        backdropFilter: "blur(16px)",
        WebkitBackdropFilter: "blur(16px)",
        boxShadow: "0 -4px 20px rgba(0, 0, 0, 0.08)",
        transition: "background-color 0.3s ease, border-color 0.3s ease"
      }}
    >
      <div className="flex items-stretch" style={{ height: "64px" }}>
        {NAV_ITEMS.map((item) => {
          const isActive = item.id === active;
          return (
            <button
              key={item.id}
              onClick={() => onSelect(item.id)}
              className="flex-1 flex flex-col items-center justify-center gap-[4px] touch-btn relative"
              style={{ minHeight: 44, color: isActive ? "var(--badge-text)" : "var(--text-muted)" }}
            >
              <span style={{ fontSize: 19, lineHeight: 1 }}>{item.icon}</span>
              <span style={{ fontSize: 11, fontWeight: isActive ? 700 : 500, letterSpacing: "0.01em" }}>
                {item.label}
              </span>
              {isActive && (
                <span
                  className="absolute top-0"
                  style={{
                    width: 36,
                    height: 3,
                    background: "linear-gradient(90deg, #0284C7, #38BDF8)",
                    borderRadius: "0 0 3px 3px",
                    marginTop: -1,
                    boxShadow: "0 2px 8px rgba(56, 189, 248, 0.5)"
                  }}
                />
              )}
            </button>
          );
        })}
      </div>
    </nav>
  );
}

// ─── Screen 1: Dashboard (100% Real Hardware & Network) ──────────────────────
// ─── Traffic Line Chart Component (Biểu đồ đường mượt mà, hỗ trợ rê/chạm hiện tooltip) ──
function TrafficLineChart({
  items,
  unit = "GB"
}: {
  items: { label: string; dl: number; ul: number }[];
  unit?: string;
}) {
  const [hoverIdx, setHoverIdx] = useState<number | null>(null);

  const W = 500, H = 160;
  const padLeft = 45, padRight = 20, padTop = 18, padBottom = 28;
  const plotW = W - padLeft - padRight;
  const plotH = H - padTop - padBottom;

  // Max value calculation for Y axis
  const rawMax = Math.max(0.1, ...items.map((i) => Math.max(i.dl, i.ul, (i.dl + i.ul) * 0.75)));
  let yCeil = Math.ceil(rawMax * 1.25 * 10) / 10;
  if (yCeil < 0.5) yCeil = 0.5;

  const getX = (idx: number) => padLeft + (items.length > 1 ? (idx / (items.length - 1)) * plotW : plotW / 2);
  const getY = (val: number) => padTop + plotH - (Math.min(val, yCeil) / yCeil) * plotH;

  const dlPoints = items.map((it, idx) => ({ x: getX(idx), y: getY(it.dl) }));
  const ulPoints = items.map((it, idx) => ({ x: getX(idx), y: getY(it.ul) }));

  // Cubic Bezier interpolation
  const makeSmoothPath = (pts: { x: number; y: number }[]) => {
    if (pts.length === 0) return "";
    if (pts.length === 1) return `M ${pts[0].x} ${pts[0].y}`;
    let d = `M ${pts[0].x.toFixed(1)} ${pts[0].y.toFixed(1)}`;
    for (let i = 0; i < pts.length - 1; i++) {
      const p0 = i > 0 ? pts[i - 1] : pts[i];
      const p1 = pts[i];
      const p2 = pts[i + 1];
      const p3 = i < pts.length - 2 ? pts[i + 2] : p2;
      const cp1x = p1.x + (p2.x - p0.x) / 6;
      const cp1y = p1.y + (p2.y - p0.y) / 6;
      const cp2x = p2.x - (p3.x - p1.x) / 6;
      const cp2y = p2.y - (p3.y - p1.y) / 6;
      d += ` C ${cp1x.toFixed(1)} ${cp1y.toFixed(1)}, ${cp2x.toFixed(1)} ${cp2y.toFixed(1)}, ${p2.x.toFixed(1)} ${p2.y.toFixed(1)}`;
    }
    return d;
  };

  const dlLinePath = makeSmoothPath(dlPoints);
  const ulLinePath = makeSmoothPath(ulPoints);
  const bottomY = padTop + plotH;
  const dlAreaPath = dlPoints.length > 1
    ? `${dlLinePath} L ${dlPoints[dlPoints.length - 1].x.toFixed(1)} ${bottomY} L ${dlPoints[0].x.toFixed(1)} ${bottomY} Z`
    : "";
  const ulAreaPath = ulPoints.length > 1
    ? `${ulLinePath} L ${ulPoints[ulPoints.length - 1].x.toFixed(1)} ${bottomY} L ${ulPoints[0].x.toFixed(1)} ${bottomY} Z`
    : "";

  const handlePointer = (clientX: number, target: SVGSVGElement) => {
    const rect = target.getBoundingClientRect();
    const relX = clientX - rect.left;
    const svgX = (relX / rect.width) * W;

    let closest = 0;
    let minD = Infinity;
    items.forEach((_, idx) => {
      const px = getX(idx);
      const d = Math.abs(svgX - px);
      if (d < minD) {
        minD = d;
        closest = idx;
      }
    });
    setHoverIdx(closest);
  };

  const activeItem = hoverIdx !== null && items[hoverIdx] ? items[hoverIdx] : null;
  const activeX = hoverIdx !== null ? getX(hoverIdx) : 0;
  const activeYDl = activeItem ? getY(activeItem.dl) : 0;
  const activeYUl = activeItem ? getY(activeItem.ul) : 0;

  return (
    <div className="relative w-full select-none" style={{ minHeight: 180 }}>
      {/* Thanh trạng thái tương tác */}
      <div className="flex flex-wrap items-center justify-between gap-2 mb-2 pb-1 border-b border-[#1E293B]">
        <div style={{ fontSize: 11, color: activeItem ? "#F8FAFC" : "#94A3B8" }}>
          {activeItem ? (
            <span className="flex items-center gap-2">
              <span className="font-bold text-white bg-[#1E293B] px-1.5 py-0.5 rounded text-[10px]">
                📅 {activeItem.label}
              </span>
              <span style={{ color: "#38BDF8" }}>
                Tải về: <strong>{activeItem.dl.toFixed(2)} {unit}</strong>
              </span>
              <span style={{ color: "#10B981" }}>
                Tải lên: <strong>{activeItem.ul.toFixed(2)} {unit}</strong>
              </span>
              <span style={{ color: "#F59E0B" }}>
                Tổng: <strong>{(activeItem.dl + activeItem.ul).toFixed(2)} {unit}</strong>
              </span>
            </span>
          ) : (
            <span style={{ color: "var(--text-subtle)" }}>
              💡 Rê chuột hoặc chạm vào đường biểu đồ để xem chi tiết từng mốc
            </span>
          )}
        </div>
        <div className="flex items-center gap-3" style={{ fontSize: 10 }}>
          <span className="flex items-center gap-1" style={{ color: "#38BDF8" }}>
            <span style={{ width: 10, height: 3, background: "#38BDF8", borderRadius: 2, display: "inline-block" }} /> Tải về
          </span>
          <span className="flex items-center gap-1" style={{ color: "#10B981" }}>
            <span style={{ width: 10, height: 3, background: "#10B981", borderRadius: 2, display: "inline-block" }} /> Tải lên
          </span>
        </div>
      </div>

      {/* SVG Canvas */}
      <div className="relative w-full">
        <svg
          viewBox={`0 0 ${W} ${H}`}
          className="w-full overflow-visible"
          style={{ height: "160px", display: "block" }}
          onMouseMove={(e) => handlePointer(e.clientX, e.currentTarget)}
          onMouseLeave={() => setHoverIdx(null)}
          onTouchMove={(e) => {
            if (e.touches && e.touches.length > 0) {
              handlePointer(e.touches[0].clientX, e.currentTarget);
            }
          }}
          onTouchEnd={() => setHoverIdx(null)}
        >
          <defs>
            <linearGradient id="chartGradDl" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#38BDF8" stopOpacity="0.32" />
              <stop offset="100%" stopColor="#38BDF8" stopOpacity="0.0" />
            </linearGradient>
            <linearGradient id="chartGradUl" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#10B981" stopOpacity="0.25" />
              <stop offset="100%" stopColor="#10B981" stopOpacity="0.0" />
            </linearGradient>
          </defs>

          {/* Grid lines and Y-axis labels */}
          {[1, 0.66, 0.33, 0].map((ratio, i) => {
            const y = padTop + plotH * (1 - ratio);
            const val = (yCeil * ratio).toFixed(1);
            return (
              <g key={i}>
                <line
                  x1={padLeft}
                  y1={y}
                  x2={W - padRight}
                  y2={y}
                  stroke="#1E293B"
                  strokeDasharray="3 3"
                  strokeWidth="1"
                />
                <text
                  x={padLeft - 6}
                  y={y + 3}
                  fill="#64748B"
                  fontSize="9"
                  textAnchor="end"
                  className="mono"
                >
                  {val}
                </text>
              </g>
            );
          })}

          {/* Area Fills */}
          {dlAreaPath && <path d={dlAreaPath} fill="url(#chartGradDl)" />}
          {ulAreaPath && <path d={ulAreaPath} fill="url(#chartGradUl)" />}

          {/* Lines */}
          {dlLinePath && (
            <path
              d={dlLinePath}
              fill="none"
              stroke="#38BDF8"
              strokeWidth="2.5"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          )}
          {ulLinePath && (
            <path
              d={ulLinePath}
              fill="none"
              stroke="#10B981"
              strokeWidth="2.5"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          )}

          {/* Dots on points */}
          {items.map((it, idx) => {
            const px = getX(idx);
            const pyDl = getY(it.dl);
            const pyUl = getY(it.ul);
            const isHov = hoverIdx === idx;
            return (
              <g key={idx}>
                <circle
                  cx={px}
                  cy={pyDl}
                  r={isHov ? 5.5 : 3}
                  fill="#38BDF8"
                  stroke="#0B0F17"
                  strokeWidth={isHov ? 2 : 1}
                />
                <circle
                  cx={px}
                  cy={pyUl}
                  r={isHov ? 5.5 : 3}
                  fill="#10B981"
                  stroke="#0B0F17"
                  strokeWidth={isHov ? 2 : 1}
                />
                {/* X-axis labels */}
                <text
                  x={px}
                  y={H - 8}
                  fill={isHov ? "#38BDF8" : "#94A3B8"}
                  fontWeight={isHov ? 700 : 400}
                  fontSize="9.5"
                  textAnchor="middle"
                >
                  {it.label}
                </text>
              </g>
            );
          })}

          {/* Hover Crosshair & Highlights */}
          {activeItem && hoverIdx !== null && (
            <g>
              <line
                x1={activeX}
                y1={padTop}
                x2={activeX}
                y2={padTop + plotH}
                stroke="#94A3B8"
                strokeDasharray="3 3"
                strokeWidth="1.5"
              />
              <circle
                cx={activeX}
                cy={activeYDl}
                r={7}
                fill="#38BDF8"
                stroke="#FFFFFF"
                strokeWidth={2}
              />
              <circle
                cx={activeX}
                cy={activeYUl}
                r={7}
                fill="#10B981"
                stroke="#FFFFFF"
                strokeWidth={2}
              />
            </g>
          )}
        </svg>

        {/* Floating Tooltip Box (Hiển thị nổi khi trỏ chuột) */}
        {activeItem && hoverIdx !== null && (
          <div
            style={{
              position: "absolute",
              left: `${(activeX / W) * 100}%`,
              top: 10,
              transform:
                activeX > 360
                  ? "translateX(-95%)"
                  : activeX < 130
                  ? "translateX(5%)"
                  : "translateX(-50%)",
              background: "#0F172A",
              border: "1px solid var(--border-color)",
              borderRadius: 8,
              padding: "7px 11px",
              boxShadow: "0 10px 25px -5px rgba(0, 0, 0, 0.7), 0 8px 10px -6px rgba(0, 0, 0, 0.7)",
              pointerEvents: "none",
              zIndex: 30,
              minWidth: 155
            }}
          >
            <div style={{ fontSize: 11, fontWeight: 700, color: "var(--text-primary)", marginBottom: 4, borderBottom: "1px solid #1E293B", paddingBottom: 2 }}>
              📅 {activeItem.label}
            </div>
            <div style={{ display: "flex", justifyContent: "space-between", gap: 12, fontSize: 11 }}>
              <span style={{ color: "#38BDF8" }}>📥 Tải về:</span>
              <span className="mono" style={{ fontWeight: 700, color: "#38BDF8" }}>{activeItem.dl.toFixed(2)} {unit}</span>
            </div>
            <div style={{ display: "flex", justifyContent: "space-between", gap: 12, fontSize: 11 }}>
              <span style={{ color: "#10B981" }}>📤 Tải lên:</span>
              <span className="mono" style={{ fontWeight: 700, color: "#10B981" }}>{activeItem.ul.toFixed(2)} {unit}</span>
            </div>
            <div style={{ display: "flex", justifyContent: "space-between", gap: 12, fontSize: 11, borderTop: "1px dashed #334155", marginTop: 4, paddingTop: 3 }}>
              <span style={{ color: "#F59E0B", fontWeight: 600 }}>🌐 Tổng cộng:</span>
              <span className="mono" style={{ fontWeight: 800, color: "#F59E0B" }}>{(activeItem.dl + activeItem.ul).toFixed(2)} {unit}</span>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function DashboardScreen() {
  const [dlData, setDlData] = useState<number[]>([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
  const [ulData, setUlData] = useState<number[]>([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
  const [cpu, setCpu] = useState(0);
  const [ramUsed, setRamUsed] = useState(0);
  const [ramTotal, setRamTotal] = useState(128);
  const [ramAvail, setRamAvail] = useState(0);
  const [dlMbps, setDlMbps] = useState(0.0);
  const [ulMbps, setUlMbps] = useState(0.0);
  const [uptime, setUptime] = useState("Đang kết nối...");
  const [wanIp, setWanIp] = useState("Đang lấy IP...");
  const [nextDnsInfo, setNextDnsInfo] = useState({ active: false, node: "Chưa kích hoạt" });
  const [trafficTotal, setTrafficTotal] = useState({ dl: "0 MB", ul: "0 MB" });
  const [trafficStats, setTrafficStats] = useState<any>(null);
  const [trafficPeriod, setTrafficPeriod] = useState<"today" | "7d" | "month" | "quarter" | "year">("today");
  const [peakBw, setPeakBw] = useState<{ dl_mbps: number; ul_mbps: number }>({ dl_mbps: 0.0, ul_mbps: 0.0 });
  const [isOnline, setIsOnline] = useState(false);

  // New hardware & port & uplink fields
  const [hwInfo, setHwInfo] = useState<HardwareInfo>({
    device_name: "Xiaomi MiWiFi Mini",
    os_version: "Kwrt 25.12-SNAPSHOT",
    kernel_version: "6.12.103",
    flash: { total_mb: 16.0, used_mb: 7.5, avail_mb: 8.5, used_pct: 47 }
  });

  const [ports, setPorts] = useState<PortStatus>({
    wan: { up: false, speed: "Chưa cắm cáp", label: "Cổng WAN (Vào)" },
    lan1: { up: false, speed: "Chưa cắm cáp", label: "Cổng LAN 1 (Ra)" },
    lan2: { up: false, speed: "Chưa cắm cáp", label: "Cổng LAN 2 (Ra)" },
    usb: { connected: false, name: "Chưa cắm thiết bị", label: "Cổng USB 2.0" }
  });

  const [uplink, setUplink] = useState<UplinkInfo>({
    type: "repeater",
    title: "Kích sóng Wi-Fi Không Dây (WISP Repeater)",
    ssid: "Xom Tro",
    bssid: "c4:eb:ff:41:6b:41",
    channel: "52",
    band: "5 GHz",
    signal_dbm: -65,
    signal_pct: 70,
    gateway: "192.168.1.1"
  });

  useEffect(() => {
    let active = true;
    let failCount = 0;

    const poll = async () => {
      const data = await fetchApi("status");
      if (!active) return;

      if (data) {
        failCount = 0;
        setIsOnline(true);
        if (data.uptime) setUptime(data.uptime);
        if (data.cpu !== undefined) setCpu(data.cpu);
        if (data.ram_used !== undefined) setRamUsed(data.ram_used);
        if (data.ram_total !== undefined) setRamTotal(data.ram_total);
        if (data.ram_avail !== undefined) setRamAvail(data.ram_avail);
        if (data.wan_ip) setWanIp(data.wan_ip);
        if (data.nextdns) setNextDnsInfo(data.nextdns);
        if (data.traffic) setTrafficTotal(data.traffic);
        if (data.peak_bandwidth) setPeakBw(data.peak_bandwidth);
        if (data.traffic_stats) setTrafficStats(data.traffic_stats);

        if (data.device_name) {
          setHwInfo({
            device_name: data.device_name,
            os_version: data.os_version || "OpenWrt 25.12",
            kernel_version: data.kernel_version || "6.12.103",
            flash: data.flash || {
              chip_mb: 16.0,
              total_mb: 16.0,
              overlay_total_mb: 4.0,
              overlay_used_mb: 2.0,
              overlay_avail_mb: 2.0,
              overlay_pct: 50,
              used_mb: 2.0,
              avail_mb: 2.0,
              used_pct: 50
            }
          });
        }
        if (data.ports) setPorts(data.ports);
        if (data.uplink) setUplink(data.uplink);

        const currentDl = data.dl_mbps !== undefined ? data.dl_mbps : 0;
        const currentUl = data.ul_mbps !== undefined ? data.ul_mbps : 0;
        setDlMbps(currentDl);
        setUlMbps(currentUl);
        setDlData((prev) => [...prev.slice(1), currentDl]);
        setUlData((prev) => [...prev.slice(1), currentUl]);
      } else {
        failCount += 1;
        if (failCount >= 3) {
          setIsOnline(false);
        }
      }

      if (active) {
        setTimeout(poll, 3000);
      }
    };

    poll();
    return () => { active = false; };
  }, []);

  const W = 320, H = 72;
  const dlPath = sparklinePath(dlData, W, H);
  const ulPath = sparklinePath(ulData, W, H);
  const cpuColor = cpu > 75 ? "#EF4444" : cpu > 50 ? "#F59E0B" : "#10B981";

  const handleResetPeak = async () => {
    await postApi("reset_peak_bw");
    setPeakBw({ dl_mbps: dlMbps, ul_mbps: ulMbps });
  };

  return (
    <div className="flex flex-col gap-3 p-4 mb-nav">
      {/* Header */}
      <div className="flex items-center justify-between pt-1">
        <div>
          <div className="flex items-center gap-2">
            <span style={{ fontWeight: 800, fontSize: 20, letterSpacing: "0.04em", color: "var(--text-primary)" }}>
              VCRT
            </span>
            <span
              style={{
                fontSize: 10,
                fontWeight: 700,
                padding: "2px 8px",
                borderRadius: 6,
                background: "#1E293B",
                color: "#38BDF8",
                border: "1px solid var(--border-color)"
              }}
            >
              {hwInfo.device_name}
            </span>
            <span
              className="pulse-dot"
              style={{
                width: 8,
                height: 8,
                borderRadius: "50%",
                background: isOnline ? "#10B981" : "#EF4444",
                display: "inline-block"
              }}
            />
          </div>
          <div className="mono" style={{ fontSize: 11, color: "var(--text-muted)", marginTop: 2 }}>
            {hwInfo.os_version} (Linux {hwInfo.kernel_version}) · {uptime}
          </div>
        </div>
        <div
          style={{
            fontSize: 11,
            color: isOnline ? "#10B981" : "#EF4444",
            fontWeight: 600,
            background: isOnline ? "#0D2818" : "#2D0A0A",
            border: `1px solid ${isOnline ? "#10B981" : "#EF4444"}`,
            borderRadius: 8,
            padding: "4px 10px"
          }}
        >
          {isOnline ? "🟢 Trực tuyến" : "🔴 Mất kết nối"}
        </div>
      </div>

      {/* CARD 1: NGUỒN CẤP INTERNET (Đang bắt mạng từ đâu để phát ra) */}
      <div style={{ background: "var(--bg-card)", borderRadius: 16, border: "1px solid #1E3A5F", padding: 16 }}>
        <div className="flex justify-between items-center mb-3">
          <div className="flex items-center gap-2">
            <span style={{ fontSize: 16 }}>
              {uplink.type === "repeater" ? "📡" : uplink.type === "ethernet" ? "🔌" : uplink.type === "cellular" ? "📶" : "⚠️"}
            </span>
            <span style={{ fontSize: 12, color: "var(--text-muted)", fontWeight: 600 }}>NGUỒN CẤP INTERNET (UPLINK)</span>
          </div>
          <div className="flex items-center gap-2">
            <span
              style={{
                fontSize: 10,
                fontWeight: 700,
                padding: "2px 8px",
                borderRadius: 6,
                background: "rgba(16, 185, 129, 0.15)",
                color: "#10B981",
                border: "1px solid rgba(16, 185, 129, 0.3)"
              }}
            >
              🏢 {uplink.isp || "Viettel Group"}
            </span>
            <span
              style={{
                fontSize: 10,
                fontWeight: 700,
                padding: "2px 8px",
                borderRadius: 6,
                background: uplink.type === "repeater" ? "#0369A1" : uplink.type === "ethernet" ? "#047857" : "#6D28D9",
                color: "#fff"
              }}
            >
              {uplink.type === "repeater" ? "WISP REPEATER" : uplink.type === "ethernet" ? "CÁP QUANG WAN" : "4G LTE MODEM"}
            </span>
          </div>
        </div>

        {uplink.type === "repeater" ? (
          <div>
            <div className="flex items-baseline justify-between mb-2">
              <div style={{ fontSize: 11, color: "var(--text-muted)" }}>Đang bắt sóng từ Wi-Fi:</div>
              <div className="mono" style={{ fontSize: 15, fontWeight: 700, color: "#38BDF8" }}>
                {uplink.ssid}
              </div>
            </div>

            <div className="grid grid-cols-2 sm:grid-cols-3 gap-2 mt-3" style={{ background: "var(--bg-canvas)", borderRadius: 12, padding: 12 }}>
              <div>
                <div style={{ fontSize: 10, color: "var(--text-muted)" }}>🏢 Nhà mạng (ISP)</div>
                <div className="mono" style={{ fontSize: 12, fontWeight: 700, color: "#10B981", marginTop: 2 }}>
                  {uplink.isp || "Viettel Group"}
                </div>
              </div>
              <div>
                <div style={{ fontSize: 10, color: "var(--text-muted)" }}>Tần số & Kênh</div>
                <div className="mono" style={{ fontSize: 12, fontWeight: 600, color: "var(--text-primary)", marginTop: 2 }}>
                  {uplink.band} · Kênh {uplink.channel}
                </div>
              </div>
              <div>
                <div style={{ fontSize: 10, color: "var(--text-muted)" }}>Cường độ sóng</div>
                <div className="mono" style={{ fontSize: 12, fontWeight: 600, color: uplink.signal_pct > 60 ? "#10B981" : "#F59E0B", marginTop: 2 }}>
                  {uplink.signal_dbm} dBm ({uplink.signal_pct}%)
                </div>
              </div>
              <div>
                <div style={{ fontSize: 10, color: "var(--text-muted)" }}>Gateway nguồn</div>
                <div className="mono" style={{ fontSize: 12, fontWeight: 600, color: "var(--text-primary)", marginTop: 2 }}>
                  {uplink.gateway}
                </div>
              </div>
              <div>
                <div style={{ fontSize: 10, color: "var(--text-muted)" }}>IP WAN nhận được</div>
                <div className="mono" style={{ fontSize: 12, fontWeight: 600, color: "#38BDF8", marginTop: 2 }}>
                  {wanIp}
                </div>
              </div>
              <div>
                <div style={{ fontSize: 10, color: "var(--text-muted)" }}>Trạng thái mạng</div>
                <div className="mono" style={{ fontSize: 12, fontWeight: 600, color: "#10B981", marginTop: 2 }}>
                  Đang kết nối ●
                </div>
              </div>
            </div>
          </div>
        ) : (
          <div style={{ background: "var(--bg-canvas)", borderRadius: 12, padding: 12 }}>
            <div className="flex justify-between items-center">
              <div style={{ fontSize: 13, fontWeight: 600, color: "var(--text-primary)" }}>{uplink.title}</div>
              <span style={{ fontSize: 11, color: "#10B981", fontWeight: 700 }}>🏢 {uplink.isp || "Viettel Group"}</span>
            </div>
            <div className="mono" style={{ fontSize: 11, color: "var(--text-muted)", marginTop: 4 }}>
              Gateway: {uplink.gateway} · IP WAN: {wanIp}
            </div>
          </div>
        )}
      </div>

      {/* CARD 2: SƠ ĐỒ CÁC CỔNG VẬT LÝ (SWITCH & USB) */}
      <div style={{ background: "var(--bg-card)", borderRadius: 16, border: "1px solid var(--border-color)", padding: 16 }}>
        <div className="flex justify-between items-center mb-3">
          <span style={{ fontSize: 12, color: "var(--text-muted)", fontWeight: 600 }}>TRẠNG THÁI CÁC CỔNG VẬT LÝ</span>
          <span className="mono" style={{ fontSize: 10, color: "var(--text-subtle)" }}>MT7620 SWITCH & USB</span>
        </div>
        <div className="grid grid-cols-2 gap-2">
          {/* Cổng WAN */}
          <div
            style={{
              background: ports.wan.up ? "#0B2117" : "#0B0F17",
              border: `1px solid ${ports.wan.up ? "#10B981" : "#222F46"}`,
              borderRadius: 12,
              padding: "10px 12px"
            }}
          >
            <div className="flex items-center justify-between">
              <span style={{ fontSize: 11, fontWeight: 600, color: "var(--text-primary)" }}>🌐 Cổng WAN</span>
              <span style={{ fontSize: 10 }}>{ports.wan.up ? "🟢 UP" : "⚪ DOWN"}</span>
            </div>
            <div style={{ fontSize: 10, color: ports.wan.up ? "#10B981" : "#64748B", marginTop: 4 }}>
              {ports.wan.speed}
            </div>
          </div>

          {/* Cổng LAN 1 */}
          <div
            style={{
              background: ports.lan1.up ? "#0B2117" : "#0B0F17",
              border: `1px solid ${ports.lan1.up ? "#10B981" : "#222F46"}`,
              borderRadius: 12,
              padding: "10px 12px"
            }}
          >
            <div className="flex items-center justify-between">
              <span style={{ fontSize: 11, fontWeight: 600, color: "var(--text-primary)" }}>💻 LAN 1</span>
              <span style={{ fontSize: 10 }}>{ports.lan1.up ? "🟢 UP" : "⚪ DOWN"}</span>
            </div>
            <div style={{ fontSize: 10, color: ports.lan1.up ? "#10B981" : "#64748B", marginTop: 4 }}>
              {ports.lan1.speed}
            </div>
          </div>

          {/* Cổng LAN 2 */}
          <div
            style={{
              background: ports.lan2.up ? "#0B2117" : "#0B0F17",
              border: `1px solid ${ports.lan2.up ? "#10B981" : "#222F46"}`,
              borderRadius: 12,
              padding: "10px 12px"
            }}
          >
            <div className="flex items-center justify-between">
              <span style={{ fontSize: 11, fontWeight: 600, color: "var(--text-primary)" }}>🖥 LAN 2</span>
              <span style={{ fontSize: 10 }}>{ports.lan2.up ? "🟢 UP" : "⚪ DOWN"}</span>
            </div>
            <div style={{ fontSize: 10, color: ports.lan2.up ? "#10B981" : "#64748B", marginTop: 4 }}>
              {ports.lan2.speed}
            </div>
          </div>

          {/* Cổng USB 2.0 */}
          <div
            style={{
              background: ports.usb.connected ? "#082032" : "#0B0F17",
              border: `1px solid ${ports.usb.connected ? "#38BDF8" : "#222F46"}`,
              borderRadius: 12,
              padding: "10px 12px"
            }}
          >
            <div className="flex items-center justify-between">
              <span style={{ fontSize: 11, fontWeight: 600, color: "var(--text-primary)" }}>🔌 Cổng USB 2.0</span>
              <span style={{ fontSize: 10 }}>{ports.usb.connected ? "🔵 CẮM" : "⚪ TRỐNG"}</span>
            </div>
            <div
              style={{
                fontSize: 10,
                color: ports.usb.connected ? "#38BDF8" : "#64748B",
                marginTop: 4,
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap"
              }}
              title={ports.usb.name}
            >
              {ports.usb.name}
            </div>
          </div>
        </div>
      </div>

      {/* CARD 3: BĂNG THÔNG THỰC TẾ & BĂNG THÔNG TỐI ĐA (SIDE-BY-SIDE) */}
      <div style={{ background: "var(--bg-card)", borderRadius: 16, border: "1px solid var(--border-color)", padding: "16px" }}>
        <div className="flex justify-between items-center mb-3">
          <span style={{ fontSize: 12, color: "var(--text-muted)", fontWeight: 600 }}>BĂNG THÔNG ĐƯỜNG TRUYỀN (LIVE 2s)</span>
          <span style={{ fontSize: 10, color: "#3B82F6" }} className="mono">● HARDWARE NAT</span>
        </div>

        {/* 2 Ô BÊN CẠNH NHAU: TỐC ĐỘ HIỆN TẠI & BĂNG THÔNG TỐI ĐA ĐẠT ĐƯỢC */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-3">
          {/* Ô 1: Tốc độ hiện tại */}
          <div style={{ background: "var(--bg-canvas)", borderRadius: 12, padding: 12, border: "1px solid var(--border-color)" }}>
            <div className="flex justify-between items-center mb-2">
              <span style={{ fontSize: 11, color: "var(--text-muted)", fontWeight: 600 }}>⚡ TỐC ĐỘ THỰC TẾ HIỆN TẠI</span>
              <span className="pulse-dot" style={{ width: 8, height: 8, borderRadius: "50%", background: "#10B981" }} />
            </div>
            <div className="grid grid-cols-2 gap-2">
              <div>
                <div style={{ fontSize: 10, color: "var(--text-muted)" }}>📥 Download</div>
                <div className="mono" style={{ fontSize: 22, fontWeight: 800, color: "#3B82F6", lineHeight: 1.1 }}>
                  {dlMbps}
                  <span style={{ fontSize: 11, color: "var(--text-muted)", marginLeft: 3 }}>Mbps</span>
                </div>
              </div>
              <div>
                <div style={{ fontSize: 10, color: "var(--text-muted)" }}>📤 Upload</div>
                <div className="mono" style={{ fontSize: 22, fontWeight: 800, color: "#10B981", lineHeight: 1.1 }}>
                  {ulMbps}
                  <span style={{ fontSize: 11, color: "var(--text-muted)", marginLeft: 3 }}>Mbps</span>
                </div>
              </div>
            </div>
          </div>

          {/* Ô 2 (BÊN CẠNH): BĂNG THÔNG TỐI ĐA ĐÃ ĐẠT ĐƯỢC */}
          <div style={{ background: "var(--bg-canvas)", borderRadius: 12, padding: 12, border: "1px solid var(--border-color)" }}>
            <div className="flex justify-between items-center mb-2">
              <span style={{ fontSize: 11, color: "#F59E0B", fontWeight: 700 }}>🚀 BĂNG THÔNG TỐI ĐA ĐẠT ĐƯỢC</span>
              <button
                onClick={handleResetPeak}
                title="Đặt lại mức đỉnh"
                style={{ background: "#1E293B", border: "none", color: "var(--text-muted)", fontSize: 10, padding: "2px 6px", borderRadius: 4, cursor: "pointer" }}
              >
                ↺ Đặt lại
              </button>
            </div>
            <div className="grid grid-cols-2 gap-2">
              <div>
                <div style={{ fontSize: 10, color: "var(--text-muted)" }}>📥 Đỉnh Download</div>
                <div className="mono" style={{ fontSize: 22, fontWeight: 800, color: "#60A5FA", lineHeight: 1.1 }}>
                  {peakBw.dl_mbps}
                  <span style={{ fontSize: 11, color: "var(--text-muted)", marginLeft: 3 }}>Mbps</span>
                </div>
              </div>
              <div>
                <div style={{ fontSize: 10, color: "var(--text-muted)" }}>📤 Đỉnh Upload</div>
                <div className="mono" style={{ fontSize: 22, fontWeight: 800, color: "#34D399", lineHeight: 1.1 }}>
                  {peakBw.ul_mbps}
                  <span style={{ fontSize: 11, color: "var(--text-muted)", marginLeft: 3 }}>Mbps</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Live SVG Graph */}
        <svg width="100%" viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" style={{ display: "block", height: H }}>
          <defs>
            <linearGradient id="dlGrad" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#3B82F6" stopOpacity="0.3" />
              <stop offset="100%" stopColor="#3B82F6" stopOpacity="0" />
            </linearGradient>
            <linearGradient id="ulGrad" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#10B981" stopOpacity="0.25" />
              <stop offset="100%" stopColor="#10B981" stopOpacity="0" />
            </linearGradient>
          </defs>
          <path d={dlPath + ` L ${W} ${H} L 0 ${H} Z`} fill="url(#dlGrad)" />
          <path d={dlPath} stroke="#3B82F6" strokeWidth="2" fill="none" strokeLinejoin="round" strokeLinecap="round" />
          <path d={ulPath + ` L ${W} ${H} L 0 ${H} Z`} fill="url(#ulGrad)" />
          <path d={ulPath} stroke="#10B981" strokeWidth="1.5" fill="none" strokeLinejoin="round" strokeLinecap="round" strokeDasharray="4 2" />
        </svg>
      </div>

      {/* CARD 4: PHẦN CỨNG, BỘ NHỚ RAM VÀ FLASH ROM */}
      <div className="grid grid-cols-2 gap-3">
        {/* CPU & RAM */}
        <div style={{ background: "var(--bg-card)", borderRadius: 16, border: "1px solid var(--border-color)", padding: 14 }}>
          <div style={{ fontSize: 11, color: "var(--text-muted)", marginBottom: 6 }}>CPU LOAD THỰC</div>
          <div className="mono" style={{ fontSize: 28, fontWeight: 700, color: cpuColor }}>
            {cpu}<span style={{ fontSize: 14 }}>%</span>
          </div>
          <div style={{ fontSize: 10, color: "var(--text-muted)", marginTop: 2 }}>MT7620A · 580MHz</div>
          <div style={{ height: 4, background: "#222F46", borderRadius: 2, marginTop: 8, overflow: "hidden" }}>
            <div style={{ width: `${Math.min(100, Math.max(0, cpu))}%`, height: "100%", background: cpuColor, borderRadius: 2, transition: "width 0.5s ease" }} />
          </div>
        </div>

        {/* RAM */}
        <div style={{ background: "var(--bg-card)", borderRadius: 16, border: "1px solid var(--border-color)", padding: 14 }}>
          <div style={{ fontSize: 11, color: "var(--text-muted)", marginBottom: 6 }}>BỘ NHỚ RAM</div>
          <div className="mono" style={{ fontSize: 20, fontWeight: 700, color: "var(--text-primary)" }}>
            {ramUsed}<span style={{ fontSize: 12, color: "var(--text-muted)" }}>MB</span>
            <span style={{ fontSize: 11, color: "var(--text-subtle)", fontWeight: 400 }}> / {ramTotal}MB</span>
          </div>
          <div style={{ fontSize: 10, color: "#10B981", marginTop: 2 }}>{ramAvail} MB khả dụng</div>
          <div style={{ height: 4, background: "#222F46", borderRadius: 2, marginTop: 8, overflow: "hidden" }}>
            <div style={{ width: `${Math.min(100, (ramUsed / (ramTotal || 128)) * 100)}%`, height: "100%", background: "#3B82F6", borderRadius: 2 }} />
          </div>
        </div>
      </div>

      {/* FLASH ROM CARD */}
      <div style={{ background: "var(--bg-card)", borderRadius: 16, border: "1px solid var(--border-color)", padding: 14 }}>
        <div className="flex justify-between items-center mb-2">
          <div className="flex items-center gap-2">
            <span style={{ fontSize: 14 }}>💾</span>
            <span style={{ fontSize: 11, color: "var(--text-muted)", fontWeight: 600 }}>BỘ NHỚ FLASH ROM</span>
          </div>
          <span className="mono" style={{ fontSize: 11, color: "#38BDF8", fontWeight: 700 }}>
            {hwInfo.flash.chip_mb || 16.0} MB SPI FLASH
          </span>
        </div>
        <div style={{ height: 6, background: "var(--bg-canvas)", borderRadius: 3, overflow: "hidden" }}>
          <div
            style={{
              width: `${Math.min(100, Math.max(0, hwInfo.flash.overlay_pct || hwInfo.flash.used_pct || 0))}%`,
              height: "100%",
              background: (hwInfo.flash.overlay_pct || hwInfo.flash.used_pct || 0) > 85 ? "#EF4444" : "#10B981",
              borderRadius: 3
            }}
          />
        </div>
        <div className="flex justify-between items-center mt-2">
          <span style={{ fontSize: 10, color: "#10B981" }}>
            Overlay trống: {hwInfo.flash.overlay_avail_mb || hwInfo.flash.avail_mb} MB / {hwInfo.flash.overlay_total_mb || 4} MB
          </span>
          <span style={{ fontSize: 10, color: "var(--text-muted)" }}>
            Đã dùng: {hwInfo.flash.overlay_pct || hwInfo.flash.used_pct}%
          </span>
        </div>
        <div style={{ fontSize: 9, color: "var(--text-subtle)", marginTop: 4, textAlign: "right" }}>
          * Phân vùng Hệ thống (Kernel + SquashFS): ~12 MB (Chỉ đọc bảo vệ)
        </div>
      </div>

      {/* CARD: DỮ LIỆU ĐÃ DÙNG (HIỂN THỊ RÕ SỐ LƯỢNG & BIỂU ĐỒ ĐƯỜNG TƯƠNG TÁC) */}
      <div style={{ background: "var(--bg-card)", borderRadius: 16, border: "1px solid var(--border-color)", padding: 16 }}>
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 mb-3">
          <div>
            <div style={{ fontSize: 12, color: "var(--text-muted)", fontWeight: 600 }}>DỮ LIỆU ĐÃ DÙNG (DATA CONSUMPTION)</div>
            <div style={{ fontSize: 10, color: "var(--text-subtle)" }}>Theo dõi chính xác dung lượng mạng đã dùng qua cổng WAN</div>
          </div>

          {/* Bộ lọc chu kỳ: [ Hôm nay | 7 ngày | 1 tháng | 1 quý | 1 năm ] */}
          <div style={{ display: "flex", gap: 3, background: "var(--bg-canvas)", padding: 3, borderRadius: 10, border: "1px solid var(--border-color)" }}>
            {[
              { id: "today", label: "Hôm nay" },
              { id: "7d", label: "7 ngày" },
              { id: "month", label: "1 tháng" },
              { id: "quarter", label: "1 quý" },
              { id: "year", label: "1 năm" },
            ].map((p) => (
              <button
                key={p.id}
                onClick={() => setTrafficPeriod(p.id as any)}
                style={{
                  background: trafficPeriod === p.id ? "#3B82F6" : "transparent",
                  color: trafficPeriod === p.id ? "#fff" : "#94A3B8",
                  border: "none",
                  borderRadius: 7,
                  padding: "4px 8px",
                  fontSize: 11,
                  fontWeight: 700,
                  cursor: "pointer",
                  transition: "all 0.15s ease"
                }}
              >
                {p.label}
              </button>
            ))}
          </div>
        </div>

        {/* Thẻ số liệu chi tiết & Biểu đồ đường của chu kỳ được chọn */}
        {(() => {
          const stats = trafficStats || {};
          const curPeriod = stats[trafficPeriod] || stats[trafficPeriod === "7d" ? "days7" : trafficPeriod] || null;

          // 100% REAL DATA FROM ROUTER KERNEL & DATABASE
          const curData = {
            dl: (curPeriod?.dl && curPeriod.dl !== "") ? curPeriod.dl : (trafficTotal.dl || "0.0 MB"),
            ul: (curPeriod?.ul && curPeriod.ul !== "") ? curPeriod.ul : (trafficTotal.ul || "0.0 MB"),
            total: (curPeriod?.total && curPeriod.total !== "") ? curPeriod.total : ((trafficTotal as any).total || "0.0 MB")
          };

          // Dữ liệu điểm vẽ biểu đồ đường: 100% LẤY TRỰC TIẾP TỪ ROUTER, KHÔNG DÙNG DỮ LIỆU GIẢ!
          let chartItems: { label: string; dl: number; ul: number }[] = [];
          if (curPeriod?.points && curPeriod.points.length > 0) {
            chartItems = curPeriod.points;
          } else {
            const dlNum = parseFloat(curData.dl) || 0;
            const ulNum = parseFloat(curData.ul) || 0;
            chartItems = [{ label: "Hiện tại", dl: dlNum, ul: ulNum }];
          }

          const unit = curPeriod?.unit || (curData.dl.includes("GB") ? "GB" : "MB");

          const periodNames = {
            today: "Hôm nay",
            "7d": "7 ngày qua",
            month: "1 tháng qua",
            quarter: "1 quý qua",
            year: "1 năm qua"
          };

          return (
            <div>
              {/* Thẻ hiển thị rõ ràng tổng dung lượng đã dùng */}
              <div
                style={{
                  background: "linear-gradient(135deg, rgba(59, 130, 246, 0.08) 0%, rgba(16, 185, 129, 0.08) 100%)",
                  borderRadius: 14,
                  border: "1px solid rgba(59, 130, 246, 0.2)",
                  padding: "12px 16px",
                  marginBottom: 12
                }}
              >
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
                  <div>
                    <div style={{ fontSize: 11, color: "var(--text-muted)", fontWeight: 600 }}>
                      TỔNG DUNG LƯỢNG ĐÃ DÙNG ({periodNames[trafficPeriod].toUpperCase()})
                    </div>
                    <div className="flex items-baseline gap-2 mt-1">
                      <span className="mono" style={{ fontSize: 28, fontWeight: 900, color: "#F59E0B", letterSpacing: "-0.03em" }}>
                        {curData.total}
                      </span>
                      <span style={{ fontSize: 11, color: "var(--text-muted)" }}>
                        (Tải về: <strong style={{ color: "#38BDF8" }}>{curData.dl}</strong> · Tải lên: <strong style={{ color: "#10B981" }}>{curData.ul}</strong>)
                      </span>
                    </div>
                  </div>
                  <div style={{ fontSize: 10, color: "var(--text-subtle)", textAlign: "right" }}>
                    <div>Nhà mạng: <strong style={{ color: "#10B981" }}>{uplink.isp || "Viettel Group"}</strong></div>
                    <div style={{ marginTop: 2 }}>Cổng mạng: <strong style={{ color: "var(--text-muted)" }}>{uplink.type === "repeater" ? "Wi-Fi WISP" : "Cáp WAN"}</strong></div>
                  </div>
                </div>
              </div>

              {/* 3 Thẻ số liệu chi tiết: Tải về, Tải lên, Tổng cộng */}
              <div className="grid grid-cols-3 gap-2 mb-3">
                <div style={{ background: "var(--bg-canvas)", borderRadius: 12, padding: "10px 8px", textAlign: "center", border: "1px solid var(--border-color)" }}>
                  <div style={{ fontSize: 10, color: "var(--text-muted)", marginBottom: 2 }}>📥 TẢI VỀ (DOWNLOAD)</div>
                  <div className="mono" style={{ fontSize: 17, fontWeight: 800, color: "#38BDF8" }}>{curData.dl}</div>
                  <div style={{ fontSize: 9, color: "var(--text-subtle)", marginTop: 2 }}>Dung lượng nhận</div>
                </div>
                <div style={{ background: "var(--bg-canvas)", borderRadius: 12, padding: "10px 8px", textAlign: "center", border: "1px solid var(--border-color)" }}>
                  <div style={{ fontSize: 10, color: "var(--text-muted)", marginBottom: 2 }}>📤 TẢI LÊN (UPLOAD)</div>
                  <div className="mono" style={{ fontSize: 17, fontWeight: 800, color: "#10B981" }}>{curData.ul}</div>
                  <div style={{ fontSize: 9, color: "var(--text-subtle)", marginTop: 2 }}>Dung lượng gửi</div>
                </div>
                <div style={{ background: "var(--bg-canvas)", borderRadius: 12, padding: "10px 8px", textAlign: "center", border: "1px solid var(--border-color)" }}>
                  <div style={{ fontSize: 10, color: "var(--text-muted)", marginBottom: 2 }}>🌐 TỔNG CỘNG</div>
                  <div className="mono" style={{ fontSize: 17, fontWeight: 800, color: "#F59E0B" }}>{curData.total}</div>
                  <div style={{ fontSize: 9, color: "var(--text-subtle)", marginTop: 2 }}>Tổng trong chu kỳ</div>
                </div>
              </div>

              {/* Biểu đồ đường hiển thị trực quan (Line Chart với tương tác trỏ chuột) */}
              <div style={{ background: "var(--bg-canvas)", borderRadius: 12, padding: "12px 14px", border: "1px solid var(--border-color)" }}>
                <TrafficLineChart items={chartItems} unit={unit} />
              </div>
            </div>
          );
        })()}
      </div>
    </div>
  );
}

// ─── Screen 2: Clients (100% Real Online Devices) ─────────────────────────────
function ClientsScreen() {
  const [clients, setClients] = useState<ClientDevice[]>([]);
  const [filter, setFilter] = useState<"connected" | "soft" | "hard">("connected");
  const [loading, setLoading] = useState(true);

  // Modal chọn thời gian chặn
  const [blockModal, setBlockModal] = useState<{
    device: ClientDevice;
    type: "soft" | "hard";
  } | null>(null);
  const [selectedMinutes, setSelectedMinutes] = useState<number>(30);
  const [customMinutes, setCustomMinutes] = useState<string>("");

  const fetchClients = async () => {
    const data = await fetchApi("clients");
    if (data && data.clients) {
      setClients(data.clients);
    }
    setLoading(false);
  };

  useEffect(() => {
    fetchClients();
    const id = setInterval(fetchClients, 2500);
    return () => clearInterval(id);
  }, []);

  // Countdown timer nội bộ giảm dần mỗi giây cho các máy bị chặn
  useEffect(() => {
    const timer = setInterval(() => {
      setClients((prev) =>
        prev
          .map((c) => {
            if ((c.blocked || c.softBlocked) && c.blockRemain && c.blockRemain > 0) {
              return { ...c, blockRemain: c.blockRemain - 1 };
            }
            return c;
          })
          .filter((c) => {
            // Khi hết thời gian chặn (blockRemain === 0 và có hẹn giờ), tự động biến mất khỏi tab chặn
            if ((c.blocked || c.softBlocked) && c.blockDuration && c.blockDuration > 0 && c.blockRemain === 0) {
              return false;
            }
            return true;
          })
      );
    }, 1000);
    return () => clearInterval(timer);
  }, []);

  // Mở modal chọn thời gian
  const openBlockModal = (device: ClientDevice, type: "soft" | "hard") => {
    setBlockModal({ device, type });
    setSelectedMinutes(30);
    setCustomMinutes("");
  };

  // Xác nhận chặn có hẹn giờ
  const handleConfirmBlock = async () => {
    if (!blockModal) return;
    const { device, type } = blockModal;
    let mins = selectedMinutes;
    if (customMinutes.trim()) {
      const parsed = parseInt(customMinutes, 10);
      if (!isNaN(parsed) && parsed > 0) mins = parsed;
    }

    const action = type === "soft" ? "soft_block" : "hard_block";
    await postApi(action, {
      mac: device.mac,
      minutes: mins,
      name: device.name,
      ip: device.ip,
    });

    setBlockModal(null);
    setFilter(type);
    fetchClients();
  };

  // Mở mạng ngay lập tức
  const handleUnblock = async (id: string, mac: string) => {
    await postApi("unblock", { mac });
    setClients((prev) => prev.filter((c) => c.id !== id));
    fetchClients();
  };

  // Định dạng thời gian còn lại
  const formatRemain = (sec?: number, dur?: number) => {
    if (!dur || dur === 0) return "Chặn vĩnh viễn";
    if (!sec || sec <= 0) return "Hết hạn";
    const h = Math.floor(sec / 3600);
    const m = Math.floor((sec % 3600) / 60);
    const s = sec % 60;
    if (h > 0) return `${h} giờ ${m} phút ${s}s`;
    if (m > 0) return `${m} phút ${s}s`;
    return `${s} giây`;
  };

  // Phân loại danh sách thiết bị:
  // 1. Đang kết nối: Online thật, KHÔNG bị chặn
  const connectedList = clients.filter((c) => !c.blocked && !c.softBlocked && c.online !== false);
  // 2. Cắt Net: Bị soft_block
  const softList = clients.filter((c) => c.softBlocked);
  // 3. Đá sóng: Bị hard_block
  const hardList = clients.filter((c) => c.blocked);

  const currentList =
    filter === "connected" ? connectedList : filter === "soft" ? softList : hardList;

  return (
    <div className="flex flex-col gap-3 p-4 mb-nav">
      <div className="pt-1 flex items-center justify-between">
        <div>
          <div style={{ fontSize: 13, color: "var(--text-muted)", fontWeight: 500 }}>KIỂM SOÁT THIẾT BỊ THỰC TẾ</div>
          <div style={{ fontSize: 22, fontWeight: 700, color: "var(--text-primary)" }}>
            Quản lý mạng ({connectedList.length} trực tuyến)
          </div>
        </div>
        <button
          onClick={fetchClients}
          className="touch-btn"
          style={{ background: "var(--bg-card)", border: "1px solid var(--border-color)", borderRadius: 10, padding: "8px 12px", color: "#3B82F6", fontSize: 12, fontWeight: 600 }}
        >
          Làm mới ⟳
        </button>
      </div>

      {/* 3 Tab chính theo đúng yêu cầu */}
      <div className="flex gap-2">
        {[
          { id: "connected" as const, label: `🟢 Đang kết nối (${connectedList.length})` },
          { id: "soft" as const, label: `✂️ Cắt Net (${softList.length})` },
          { id: "hard" as const, label: `🚫 Đá sóng (${hardList.length})` },
        ].map((tab) => (
          <button
            key={tab.id}
            onClick={() => setFilter(tab.id)}
            className="touch-btn flex-1 py-[8px] rounded-xl text-xs font-bold"
            style={{
              background: filter === tab.id ? (tab.id === "connected" ? "#3B82F6" : tab.id === "soft" ? "#D97706" : "#DC2626") : "#161F30",
              color: filter === tab.id ? "#fff" : "#94A3B8",
              border: `1px solid ${filter === tab.id ? "transparent" : "#222F46"}`,
            }}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {loading && clients.length === 0 ? (
        <div style={{ textAlign: "center", padding: 40, color: "var(--text-muted)" }}>Đang quét thiết bị mạng...</div>
      ) : currentList.length === 0 ? (
        <div style={{ textAlign: "center", padding: 40, color: "var(--text-muted)" }}>
          {filter === "connected"
            ? "Không có thiết bị nào đang kết nối lúc này."
            : filter === "soft"
            ? "Không có thiết bị nào trong danh sách Cắt Net."
            : "Không có thiết bị nào trong danh sách Đá Sóng."}
        </div>
      ) : null}

      {/* Danh sách thẻ thiết bị */}
      {currentList.map((c) => (
        <div
          key={c.id}
          style={{
            background: c.blocked ? "#200B0B" : c.softBlocked ? "#231500" : "#161F30",
            border: `1px solid ${c.blocked ? "#EF4444" : c.softBlocked ? "#F59E0B" : "#222F46"}`,
            borderRadius: 16,
            padding: 16,
          }}
        >
          <div className="flex items-center gap-3 mb-3">
            <span style={{ fontSize: 26 }}>{c.icon}</span>
            <div className="flex-1 min-w-0">
              <div style={{ fontSize: 15, fontWeight: 700, color: "var(--text-primary)" }} className="truncate">
                {c.name}
              </div>
              <div className="mono" style={{ fontSize: 11, color: "var(--text-muted)" }}>
                {c.ip} · {c.mac}
              </div>
              {!c.blocked && !c.softBlocked && (
                <div style={{ fontSize: 11, color: "#38BDF8", marginTop: 3, fontWeight: 600 }}>
                  ⏱ Đã kết nối: {c.connectedTime || "Trực tuyến"}
                </div>
              )}
            </div>
            <div className="flex flex-col items-end">
              <span style={{
                fontSize: 10,
                fontWeight: 700,
                padding: "3px 8px",
                borderRadius: 6,
                background: c.blocked ? "#450A0A" : c.softBlocked ? "#451A03" : c.band === "5GHz" ? "#1E3A5F" : c.band === "2.4GHz" ? "#1A2E1E" : "#2D1D3A",
                color: c.blocked ? "#FCA5A5" : c.softBlocked ? "#FDE68A" : c.band === "5GHz" ? "#38BDF8" : c.band === "2.4GHz" ? "#10B981" : "#C084FC"
              }}>
                {c.blocked ? "🚫 ĐÃ ĐÁ SÓNG" : c.softBlocked ? "✂️ ĐÃ CẮT NET" : c.band === "Dây LAN" ? "🔌 Cáp LAN" : `📶 ${c.band}`}
              </span>
              {!c.blocked && !c.softBlocked && c.band !== "Dây LAN" && (
                <div className="flex items-center gap-1 mt-1">
                  <SignalBars rssi={c.rssi} />
                  <span className="mono" style={{ fontSize: 10, color: "var(--text-muted)" }}>{c.rssi}dBm</span>
                </div>
              )}
            </div>
          </div>

          {/* Nếu đang bị Cắt Net hoặc Đá Sóng */}
          {c.blocked || c.softBlocked ? (
            <div className="flex flex-col gap-2 mt-2">
              <div
                style={{
                  background: "var(--bg-canvas)",
                  borderRadius: 12,
                  padding: "10px 12px",
                  border: `1px solid ${c.blocked ? "#7F1D1D" : "#78350F"}`,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "space-between"
                }}
              >
                <div>
                  <div style={{ fontSize: 11, fontWeight: 700, color: c.blocked ? "#F87171" : "#FBBF24" }}>
                    ⚠️ {c.blocked ? "ĐANG CỐ KẾT NỐI (BỊ ĐÁ RA)" : "ĐANG CỐ TRUY CẬP (BỊ CHẶN INTERNET)"}
                  </div>
                  <div style={{ fontSize: 10, color: "var(--text-muted)", marginTop: 2 }}>
                    Tự động biến mất khi hết giờ hoặc ngắt kết nối
                  </div>
                </div>
                <div className="text-right">
                  <div className="mono" style={{ fontSize: 13, fontWeight: 700, color: "#38BDF8" }}>
                    ⏳ {formatRemain(c.blockRemain, c.blockDuration)}
                  </div>
                </div>
              </div>

              {/* Nút Mở Ngay Lập Tức */}
              <button
                onClick={() => handleUnblock(c.id, c.mac)}
                className="touch-btn w-full py-[11px] rounded-xl flex items-center justify-center gap-2"
                style={{ background: "#10B981", color: "#fff", fontSize: 13, fontWeight: 700, border: "none" }}
              >
                <span>🟢</span> MỞ MẠNG NGAY (HỦY CHẶN)
              </button>
            </div>
          ) : (
            /* Nếu đang Online bình thường: 2 nút Cắt Net và Đá Sóng có hẹn giờ */
            <div className="flex gap-2 pt-1">
              <button
                onClick={() => openBlockModal(c, "soft")}
                className="touch-btn flex-1 py-[10px] rounded-xl font-semibold text-xs"
                style={{ background: "#1E1A0F", border: "1px solid #D97706", color: "#FBBF24" }}
              >
                ✂️ Cắt Net (Hẹn giờ)
              </button>
              <button
                onClick={() => openBlockModal(c, "hard")}
                className="touch-btn flex-1 py-[10px] rounded-xl font-semibold text-xs"
                style={{ background: "#1F0F0F", border: "1px solid #DC2626", color: "#F87171" }}
              >
                🚫 Đá Sóng (Hẹn giờ)
              </button>
            </div>
          )}
        </div>
      ))}

      {/* MODAL CHỌN THỜI GIAN CẮT NET / ĐÁ SÓNG */}
      {blockModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center modal-backdrop" style={{ padding: 20 }}>
          <div
            style={{
              background: "var(--bg-card)",
              borderRadius: 24,
              border: `1px solid ${blockModal.type === "soft" ? "#F59E0B" : "#EF4444"}`,
              padding: 24,
              width: "100%",
              maxWidth: 400,
              position: "relative",
              boxShadow: "0 25px 50px -12px rgba(0, 0, 0, 0.75)",
            }}
          >
            <button
              onClick={() => setBlockModal(null)}
              style={{
                position: "absolute", top: 16, right: 16, width: 32, height: 32,
                borderRadius: "50%", background: "#222F46", border: "1px solid var(--border-color)",
                color: "var(--text-muted)", display: "flex", alignItems: "center", justifyContent: "center",
                fontSize: 16, fontWeight: 700, cursor: "pointer"
              }}
            >
              ✕
            </button>

            <div className="flex items-center gap-2 mb-2">
              <span style={{ fontSize: 22 }}>{blockModal.type === "soft" ? "✂️" : "🚫"}</span>
              <span style={{ fontSize: 16, fontWeight: 700, color: "var(--text-primary)" }}>
                {blockModal.type === "soft" ? "Cắt Internet (Cấp 1)" : "Đá Khỏi Wi-Fi (Cấp 2)"}
              </span>
            </div>

            <div style={{ fontSize: 13, color: "var(--text-muted)", marginBottom: 14 }}>
              Thiết bị: <strong style={{ color: "var(--text-primary)" }}>{blockModal.device.name}</strong> ({blockModal.device.ip})
            </div>

            <div style={{ fontSize: 12, fontWeight: 600, color: "#CBD5E1", marginBottom: 8 }}>
              Chọn thời gian áp dụng:
            </div>

            {/* Các nút chọn mốc thời gian nhanh */}
            <div className="grid grid-cols-3 gap-2 mb-3">
              {[
                { min: 5, label: "5 phút" },
                { min: 15, label: "15 phút" },
                { min: 30, label: "30 phút" },
                { min: 60, label: "1 giờ" },
                { min: 120, label: "2 giờ" },
                { min: 1440, label: "24 giờ" },
              ].map((m) => (
                <button
                  key={m.min}
                  onClick={() => {
                    setSelectedMinutes(m.min);
                    setCustomMinutes("");
                  }}
                  className="touch-btn py-2 rounded-xl text-xs font-semibold"
                  style={{
                    background: selectedMinutes === m.min && !customMinutes ? (blockModal.type === "soft" ? "#D97706" : "#DC2626") : "#0B0F17",
                    color: selectedMinutes === m.min && !customMinutes ? "#fff" : "#94A3B8",
                    border: `1px solid ${selectedMinutes === m.min && !customMinutes ? "transparent" : "#334155"}`,
                  }}
                >
                  {m.label}
                </button>
              ))}
            </div>

            {/* Hoặc tự nhập số phút */}
            <div style={{ marginBottom: 16 }}>
              <label style={{ fontSize: 11, color: "var(--text-muted)", display: "block", marginBottom: 4 }}>
                Hoặc tự nhập số phút tùy chỉnh:
              </label>
              <input
                type="number"
                min="1"
                placeholder="Ví dụ: 45 (phút)"
                value={customMinutes}
                onChange={(e) => setCustomMinutes(e.target.value)}
                style={{
                  width: "100%", background: "var(--bg-canvas)", border: "1px solid var(--border-color)",
                  borderRadius: 10, padding: "10px 14px", color: "var(--text-primary)", fontSize: 14, outline: "none"
                }}
              />
            </div>

            <div className="flex gap-3">
              <button
                onClick={() => setBlockModal(null)}
                className="touch-btn flex-1 py-[12px] rounded-xl"
                style={{ background: "#222F46", color: "var(--text-muted)", fontSize: 13, fontWeight: 600, border: "none" }}
              >
                Hủy Bỏ
              </button>
              <button
                onClick={handleConfirmBlock}
                className="touch-btn flex-1 py-[12px] rounded-xl"
                style={{
                  background: blockModal.type === "soft" ? "#D97706" : "#DC2626",
                  color: "#fff", fontSize: 13, fontWeight: 700, border: "none"
                }}
              >
                Xác Nhận Thực Hiện 🚀
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
function WiFiScreen() {
  const [ssid5, setSsid5] = useState("VC 5Ghz");
  const [pass5, setPass5] = useState("25122035");
  const [ch5, setCh5] = useState("157");
  const [power5, setPower5] = useState("20");
  const [show5, setShow5] = useState(false);

  const [ssid24, setSsid24] = useState("VC 2.4Ghz");
  const [pass24, setPass24] = useState("25122035");
  const [ch24, setCh24] = useState("6");
  const [power24, setPower24] = useState("20");
  const [show24, setShow24] = useState(false);

  // Wi-Fi Scanner & Uplink Connector State
  const [scanningBand, setScanningBand] = useState<"2.4g" | "5g" | null>(null);
  const [scannedNetworks, setScannedNetworks] = useState<any[]>([]);
  const [scanModalOpen, setScanModalOpen] = useState(false);
  const [selectedUplinkNet, setSelectedUplinkNet] = useState<any | null>(null);
  const [uplinkPass, setUplinkPass] = useState("");
  const [showUplinkPass, setShowUplinkPass] = useState(false);
  const [isConnectingUplink, setIsConnectingUplink] = useState(false);
  const [uplinkError, setUplinkError] = useState("");

  // 2-Layer Confirmation & Rollback State
  // 0 = Idle, 1 = Review (Lớp 1), 2 = Confirm & Commit (Lớp 2), 3 = Rollback Countdown
  const [wifiStep, setWifiStep] = useState<0 | 1 | 2 | 3>(0);
  const [countdown, setCountdown] = useState(60);
  const [isApplying, setIsApplying] = useState(false);
  const [statusMsg, setStatusMsg] = useState("");

  useEffect(() => {
    const fetchWifi = async () => {
      const res = await fetchApi("wifi_get");
      if (res) {
        if (res.wifi5) {
          if (res.wifi5.ssid) setSsid5(res.wifi5.ssid);
          if (res.wifi5.pass) setPass5(res.wifi5.pass);
          if (res.wifi5.channel) setCh5(res.wifi5.channel);
          if (res.wifi5.power) setPower5(res.wifi5.power);
        }
        if (res.wifi24) {
          if (res.wifi24.ssid) setSsid24(res.wifi24.ssid);
          if (res.wifi24.pass) setPass24(res.wifi24.pass);
          if (res.wifi24.channel) setCh24(res.wifi24.channel);
          if (res.wifi24.power) setPower24(res.wifi24.power);
        }
      }
    };
    fetchWifi();
  }, []);

  // Rollback Countdown Timer
  useEffect(() => {
    let timer: any = null;
    if (wifiStep === 3 && countdown > 0) {
      timer = setInterval(() => {
        setCountdown((prev) => prev - 1);
      }, 1000);
    } else if (wifiStep === 3 && countdown === 0) {
      // Hết 60s mà người dùng chưa bấm xác nhận -> tự động rollback
      handleRollback(true);
    }
    return () => {
      if (timer) clearInterval(timer);
    };
  }, [wifiStep, countdown]);

  // Bắt đầu áp dụng sau khi qua Lớp 2
  const handleStartApply = async () => {
    setIsApplying(true);
    await postApi("wifi_apply", {
      ssid5, pass5, ch5, power5, ssid24, pass24, ch24, power24
    });
    setIsApplying(false);
    setCountdown(60);
    setWifiStep(3); // Chuyển sang màn hình đếm ngược Rollback
  };

  // Xác nhận mạng chạy tốt -> Giữ cấu hình
  const handleKeepConfig = () => {
    setWifiStep(0);
    setStatusMsg("Đã áp dụng và lưu cấu hình Wi-Fi mới thành công!");
    setTimeout(() => setStatusMsg(""), 5000);
  };

  // Hoàn tác về cấu hình cũ ngay lập tức
  const handleRollback = async (isAuto = false) => {
    setIsApplying(true);
    await postApi("wifi_rollback");
    setIsApplying(false);
    setWifiStep(0);
    setStatusMsg(isAuto
      ? "Hết 60s! Router đã tự động hoàn tác về mật khẩu cũ để bảo vệ bạn."
      : "Đã hoàn tác cấu hình Wi-Fi về trạng thái cũ an toàn!"
    );
    setTimeout(() => setStatusMsg(""), 6000);
  };

  const inputStyle = {
    width: "100%", background: "var(--bg-canvas)", border: "1px solid var(--border-color)",
    borderRadius: 10, padding: "11px 14px", color: "var(--text-primary)",
    fontSize: 14, outline: "none", fontFamily: "inherit",
  };
  const labelStyle = { fontSize: 11, color: "var(--text-muted)", marginBottom: 4, display: "block" as const };

  return (
    <div className="flex flex-col gap-3 p-4 mb-nav">
      <div className="pt-1">
        <div style={{ fontSize: 13, color: "var(--text-muted)", fontWeight: 500 }}>CẤU HÌNH PHẦN CỨNG</div>
        <div style={{ fontSize: 22, fontWeight: 700, color: "var(--text-primary)" }}>Quản lý Wi-Fi</div>
      </div>

      {statusMsg && (
        <div
          style={{
            background: "#0D2818", border: "1px solid #10B981", borderRadius: 12,
            padding: "12px 16px", color: "#10B981", fontSize: 13, fontWeight: 600
          }}
        >
          {statusMsg}
        </div>
      )}

      {/* 5GHz Card */}
      <div style={{ background: "var(--bg-card)", borderRadius: 16, border: "1px solid #1E3A5F", padding: 16 }}>
        <div className="flex items-center gap-2 mb-4">
          <span style={{ background: "#1E3A5F", color: "#3B82F6", fontSize: 11, fontWeight: 700, padding: "3px 10px", borderRadius: 6 }}>5 GHz</span>
          <span style={{ fontSize: 13, fontWeight: 600, color: "var(--text-primary)" }}>Băng tần cao tốc (MT7612E)</span>
        </div>
        <div className="flex flex-col gap-3">
          <div>
            <label style={labelStyle}>Tên mạng (SSID)</label>
            <input style={inputStyle} value={ssid5} onChange={(e) => setSsid5(e.target.value)} placeholder="Nhập tên Wi-Fi 5GHz..." />
          </div>
          <div>
            <label style={labelStyle}>Mật khẩu Wi-Fi</label>
            <div style={{ position: "relative" }}>
              <input style={{ ...inputStyle, paddingRight: 44 }} type={show5 ? "text" : "password"} value={pass5} onChange={(e) => setPass5(e.target.value)} placeholder="Tối thiểu 8 ký tự" />
              <button onClick={() => setShow5(!show5)} style={{ position: "absolute", right: 12, top: "50%", transform: "translateY(-50%)", background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer", fontSize: 16 }}>
                {show5 ? "🙈" : "👁"}
              </button>
            </div>
          </div>
          <div className="flex gap-3">
            <div style={{ flex: 1 }}>
              <label style={labelStyle}>Kênh phát</label>
              <select style={{ ...inputStyle }} value={ch5} onChange={(e) => setCh5(e.target.value)}>
                {["auto", "36", "40", "44", "48", "149", "153", "157", "161"].map((ch) => (
                  <option key={ch} value={ch} style={{ background: "var(--bg-card)" }}>{ch === "auto" ? "Tự động (Auto)" : `Kênh ${ch}`}</option>
                ))}
              </select>
            </div>
            <div style={{ flex: 1 }}>
              <label style={labelStyle}>Công suất (dBm)</label>
              <select style={{ ...inputStyle }} value={power5} onChange={(e) => setPower5(e.target.value)}>
                {["14", "17", "20", "23"].map((p) => (
                  <option key={p} value={p} style={{ background: "var(--bg-card)" }}>{p} dBm</option>
                ))}
              </select>
            </div>
          </div>
        </div>
      </div>

      {/* 2.4GHz Card */}
      <div style={{ background: "var(--bg-card)", borderRadius: 16, border: "1px solid #1A2E1E", padding: 16 }}>
        <div className="flex items-center gap-2 mb-4">
          <span style={{ background: "#1A2E1E", color: "#10B981", fontSize: 11, fontWeight: 700, padding: "3px 10px", borderRadius: 6 }}>2.4 GHz</span>
          <span style={{ fontSize: 13, fontWeight: 600, color: "var(--text-primary)" }}>Băng tần xuyên tường (MT7620)</span>
        </div>
        <div className="flex flex-col gap-3">
          <div>
            <label style={labelStyle}>Tên mạng (SSID)</label>
            <input style={inputStyle} value={ssid24} onChange={(e) => setSsid24(e.target.value)} placeholder="Nhập tên Wi-Fi 2.4GHz..." />
          </div>
          <div>
            <label style={labelStyle}>Mật khẩu Wi-Fi</label>
            <div style={{ position: "relative" }}>
              <input style={{ ...inputStyle, paddingRight: 44 }} type={show24 ? "text" : "password"} value={pass24} onChange={(e) => setPass24(e.target.value)} placeholder="Tối thiểu 8 ký tự" />
              <button onClick={() => setShow24(!show24)} style={{ position: "absolute", right: 12, top: "50%", transform: "translateY(-50%)", background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer", fontSize: 16 }}>
                {show24 ? "🙈" : "👁"}
              </button>
            </div>
          </div>
          <div className="flex gap-3">
            <div style={{ flex: 1 }}>
              <label style={labelStyle}>Kênh phát</label>
              <select style={{ ...inputStyle }} value={ch24} onChange={(e) => setCh24(e.target.value)}>
                {["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11"].map((ch) => (
                  <option key={ch} value={ch} style={{ background: "var(--bg-card)" }}>Kênh {ch}</option>
                ))}
              </select>
            </div>
            <div style={{ flex: 1 }}>
              <label style={labelStyle}>Công suất (dBm)</label>
              <select style={{ ...inputStyle }} value={power24} onChange={(e) => setPower24(e.target.value)}>
                {["14", "17", "20", "23"].map((p) => (
                  <option key={p} value={p} style={{ background: "var(--bg-card)" }}>{p} dBm</option>
                ))}
              </select>
            </div>
          </div>
        </div>
      </div>

            {/* NGUỒN WI-FI UPLINK & QUÉT SÓNG (WISP REPEATER) */}
      <div style={{ background: "var(--bg-card)", borderRadius: 16, border: "1px solid var(--border-color)", padding: 16 }}>
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-2">
            <span style={{ fontSize: 16 }}>📡</span>
            <span style={{ fontSize: 13, fontWeight: 700, color: "var(--text-primary)" }}>Nguồn Wi-Fi Kích Sóng (WISP Repeater)</span>
          </div>
          <span style={{ fontSize: 11, background: "#1E293B", color: "#38BDF8", padding: "2px 8px", borderRadius: 6, fontWeight: 600 }}>
            Thay đổi Uplink
          </span>
        </div>
        <p style={{ fontSize: 12, color: "var(--text-muted)", marginBottom: 12, lineHeight: 1.4 }}>
          Quét sóng Wi-Fi môi trường xung quanh để đổi nguồn kết nối Internet không dây cho router.
        </p>
        <div className="flex gap-2">
          <button
            onClick={async () => {
              setScanningBand("2.4g");
              setScanModalOpen(true);
              setScannedNetworks([]);
              setSelectedUplinkNet(null);
              const res = await fetchApi("wifi_scan", { band: "2.4g" });
              setScanningBand(null);
              if (res && res.networks) setScannedNetworks(res.networks);
            }}
            disabled={scanningBand !== null}
            className="touch-btn flex-1 py-[10px] rounded-xl flex items-center justify-center gap-1.5"
            style={{ background: "#065F46", color: "#10B981", fontSize: 12, fontWeight: 600, border: "1px solid #10B981" }}
          >
            <span>🔍</span> {scanningBand === "2.4g" ? "Đang quét 2.4G..." : "Quét sóng 2.4 GHz"}
          </button>
          <button
            onClick={async () => {
              setScanningBand("5g");
              setScanModalOpen(true);
              setScannedNetworks([]);
              setSelectedUplinkNet(null);
              const res = await fetchApi("wifi_scan", { band: "5g" });
              setScanningBand(null);
              if (res && res.networks) setScannedNetworks(res.networks);
            }}
            disabled={scanningBand !== null}
            className="touch-btn flex-1 py-[10px] rounded-xl flex items-center justify-center gap-1.5"
            style={{ background: "#1E3A5F", color: "#38BDF8", fontSize: 12, fontWeight: 600, border: "1px solid #38BDF8" }}
          >
            <span>🔍</span> {scanningBand === "5g" ? "Đang quét 5G..." : "Quét sóng 5 GHz"}
          </button>
        </div>
      </div>

      {/* MODAL DANH SÁCH SÓNG QUÉT ĐƯỢC */}
      {scanModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center modal-backdrop" style={{ padding: 16 }}>
          <div
            style={{
              background: "var(--bg-card)", borderRadius: 24, border: "1px solid var(--border-color)",
              padding: 20, width: "100%", maxWidth: 440, maxHeight: "85vh", display: "flex", flexDirection: "column",
              position: "relative", boxShadow: "0 25px 50px -12px rgba(0, 0, 0, 0.75)"
            }}
          >
            <div className="flex items-center justify-between pb-3 border-b border-[#222F46] mb-3">
              <div>
                <div style={{ fontSize: 16, fontWeight: 700, color: "var(--text-primary)" }}>
                  {scanningBand ? "Đang dò tìm sóng Wi-Fi..." : "Kết Quả Quét Sóng Wi-Fi"}
                </div>
                <div style={{ fontSize: 11, color: "var(--text-muted)" }}>
                  {scanningBand ? "Vui lòng chờ trong giây lát" : `Tìm thấy ${scannedNetworks.length} mạng khả dụng`}
                </div>
              </div>
              <button
                onClick={() => setScanModalOpen(false)}
                style={{
                  width: 30, height: 30, borderRadius: "50%", background: "#222F46", border: "1px solid var(--border-color)",
                  color: "var(--text-muted)", display: "flex", alignItems: "center", justifyContent: "center",
                  fontSize: 14, fontWeight: 700, cursor: "pointer"
                }}
              >
                ✕
              </button>
            </div>

            {/* Loading */}
            {scanningBand && (
              <div className="flex flex-col items-center justify-center py-8 gap-3">
                <div className="animate-spin" style={{ fontSize: 28 }}>🔄</div>
                <div style={{ fontSize: 13, color: "#38BDF8", fontWeight: 600 }}>
                  Router đang quét dải tần {scanningBand}...
                </div>
              </div>
            )}

            {/* List */}
            {!scanningBand && (
              <div className="flex flex-col gap-2 overflow-y-auto pr-1" style={{ flex: 1, minHeight: 180 }}>
                {scannedNetworks.length === 0 ? (
                  <div className="text-center py-8 text-sm" style={{ color: "var(--text-muted)" }}>
                    Không tìm thấy mạng Wi-Fi nào hoặc sóng quá yếu.
                  </div>
                ) : (
                  scannedNetworks.map((net, idx) => (
                    <div
                      key={net.bssid || idx}
                      onClick={() => {
                        setSelectedUplinkNet(net);
                        setUplinkPass("");
                      }}
                      className="touch-card p-3 rounded-xl flex items-center justify-between cursor-pointer"
                      style={{
                        background: selectedUplinkNet?.bssid === net.bssid ? "#1E293B" : "#0B0F17",
                        border: selectedUplinkNet?.bssid === net.bssid ? "1px solid #38BDF8" : "1px solid #222F46"
                      }}
                    >
                      <div className="flex flex-col gap-0.5">
                        <div className="flex items-center gap-1.5">
                          <span style={{ fontSize: 13, fontWeight: 700, color: "var(--text-primary)" }}>{net.ssid}</span>
                          {net.encryption && net.encryption !== "none" && (
                            <span style={{ fontSize: 10 }}>🔒</span>
                          )}
                        </div>
                        <div className="flex items-center gap-2" style={{ fontSize: 11, color: "var(--text-muted)" }}>
                          <span>Kênh {net.channel}</span>
                          <span>·</span>
                          <span className="mono">{net.signal} dBm</span>
                        </div>
                      </div>
                      <button
                        style={{
                          background: selectedUplinkNet?.bssid === net.bssid ? "#38BDF8" : "#222F46",
                          color: selectedUplinkNet?.bssid === net.bssid ? "#0B0F17" : "#F9FAFB",
                          border: "none", borderRadius: 8, padding: "6px 12px", fontSize: 11, fontWeight: 700
                        }}
                      >
                        {selectedUplinkNet?.bssid === net.bssid ? "Đã chọn ✓" : "Chọn 🔗"}
                      </button>
                    </div>
                  ))
                )}
              </div>
            )}

            {/* Input Password & Connect Form */}
            {selectedUplinkNet && (
              <div className="mt-3 pt-3 border-t border-[#222F46] flex flex-col gap-2">
                <div style={{ fontSize: 12, fontWeight: 600, color: "#E2E8F0" }}>
                  Kết nối tới: <strong style={{ color: "#38BDF8" }}>{selectedUplinkNet.ssid}</strong>
                </div>
                {selectedUplinkNet.encryption && selectedUplinkNet.encryption !== "none" ? (
                  <div style={{ position: "relative" }}>
                    <input
                      style={{ ...inputStyle, paddingRight: 44, fontSize: 13, padding: "9px 12px" }}
                      type={showUplinkPass ? "text" : "password"}
                      value={uplinkPass}
                      onChange={(e) => setUplinkPass(e.target.value)}
                      placeholder="Nhập mật khẩu Wi-Fi nguồn..."
                    />
                    <button
                      type="button"
                      onClick={() => setShowUplinkPass(!showUplinkPass)}
                      style={{ position: "absolute", right: 10, top: "50%", transform: "translateY(-50%)", background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer", fontSize: 14 }}
                    >
                      {showUplinkPass ? "🙈" : "👁"}
                    </button>
                  </div>
                ) : (
                  <div style={{ fontSize: 11, color: "#10B981" }}>Mạng công cộng không có mật khẩu.</div>
                )}
                {uplinkError && (
                  <div style={{
                    background: "#450A0A", border: "1px solid #EF4444", borderRadius: 10,
                    padding: "10px 12px", color: "#FCA5A5", fontSize: 12, fontWeight: 600,
                    lineHeight: 1.4
                  }}>
                    ⚠️ {uplinkError}
                  </div>
                )}
                <button
                  onClick={async () => {
                    if (!selectedUplinkNet) return;
                    setIsConnectingUplink(true);
                    setUplinkError("");
                    const res = await postApi("wifi_connect_uplink", {
                      ssid: selectedUplinkNet.ssid,
                      pass: uplinkPass,
                      band: selectedUplinkNet.channel > 14 ? "5g" : "2.4g",
                      bssid: selectedUplinkNet.bssid || ""
                    });
                    setIsConnectingUplink(false);
                    if (res && res.status === "ok") {
                      setSelectedUplinkNet(null);
                      setScanModalOpen(false);
                      setUplinkPass("");
                      setStatusMsg(res.message || "Đã kết nối thành công tới Wi-Fi nguồn!");
                      setTimeout(() => setStatusMsg(""), 6000);
                    } else {
                      setUplinkError(res?.message || "Mật khẩu Wi-Fi không chính xác hoặc không thể kết nối!");
                    }
                  }}
                  disabled={isConnectingUplink}
                  className="touch-btn w-full py-[11px] rounded-xl flex items-center justify-center gap-2"
                  style={{ background: isConnectingUplink ? "#222F46" : "#38BDF8", color: isConnectingUplink ? "#94A3B8" : "#0B0F17", fontSize: 13, fontWeight: 700, border: "none" }}
                >
                  {isConnectingUplink ? "Đang xác thực & kiểm tra kết nối..." : "XÁC NHẬN ĐỔI NGUỒN WI-FI ⚡"}
                </button>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Nút Kích hoạt Xác nhận Lớp 1 */}
      <button
        onClick={() => setWifiStep(1)}
        className="touch-btn w-full py-[14px] rounded-2xl"
        style={{
          background: "#3B82F6",
          color: "#fff",
          fontSize: 14,
          fontWeight: 700,
          border: "none",
          letterSpacing: "0.02em"
        }}
      >
        ÁP DỤNG CẤU HÌNH WI-FI 📶
      </button>

      {/* MODAL LỚP 1: Xem trước & Kiểm tra thông số */}
      {wifiStep === 1 && (
        <div className="fixed inset-0 z-50 flex items-center justify-center modal-backdrop" style={{ padding: 20 }}>
          <div
            style={{
              background: "var(--bg-card)", borderRadius: 24, border: "1px solid var(--border-color)",
              padding: 24, width: "100%", maxWidth: 420, position: "relative",
              boxShadow: "0 25px 50px -12px rgba(0, 0, 0, 0.75)"
            }}
          >
            <button
              onClick={() => setWifiStep(0)}
              style={{
                position: "absolute", top: 16, right: 16, width: 32, height: 32,
                borderRadius: "50%", background: "#222F46", border: "1px solid var(--border-color)",
                color: "var(--text-muted)", display: "flex", alignItems: "center", justifyContent: "center",
                fontSize: 16, fontWeight: 700, cursor: "pointer"
              }}
            >
              ✕
            </button>

            <div className="flex items-center gap-2 mb-3">
              <span style={{ fontSize: 20 }}>🔍</span>
              <span style={{ fontSize: 16, fontWeight: 700, color: "var(--text-primary)" }}>
                Xác Nhận Cấu Hình (Lớp 1/2)
              </span>
            </div>

            <p style={{ fontSize: 12, color: "var(--text-muted)", marginBottom: 16 }}>
              Vui lòng kiểm tra kỹ các thông số Wi-Fi chuẩn bị áp dụng:
            </p>

            <div style={{ background: "var(--bg-canvas)", borderRadius: 14, border: "1px solid var(--border-color)", padding: 14, marginBottom: 16 }}>
              <div style={{ fontSize: 12, fontWeight: 700, color: "#38BDF8", marginBottom: 6 }}>📡 Băng tần 5 GHz</div>
              <div style={{ fontSize: 12, color: "#E2E8F0" }}>Tên: <strong>{ssid5}</strong></div>
              <div style={{ fontSize: 12, color: "#E2E8F0" }}>Mật khẩu: <strong>{pass5}</strong></div>
              <div style={{ fontSize: 11, color: "var(--text-muted)", marginTop: 2 }}>Kênh: {ch5} · Công suất: {power5} dBm</div>

              <div style={{ height: 1, background: "#222F46", margin: "10px 0" }} />

              <div style={{ fontSize: 12, fontWeight: 700, color: "#10B981", marginBottom: 6 }}>📶 Băng tần 2.4 GHz</div>
              <div style={{ fontSize: 12, color: "#E2E8F0" }}>Tên: <strong>{ssid24}</strong></div>
              <div style={{ fontSize: 12, color: "#E2E8F0" }}>Mật khẩu: <strong>{pass24}</strong></div>
              <div style={{ fontSize: 11, color: "var(--text-muted)", marginTop: 2 }}>Kênh: {ch24} · Công suất: {power24} dBm</div>
            </div>

            <div className="flex gap-3">
              <button
                onClick={() => setWifiStep(0)}
                className="touch-btn flex-1 py-[12px] rounded-xl"
                style={{ background: "#222F46", color: "var(--text-muted)", fontSize: 13, fontWeight: 600, border: "none" }}
              >
                Hủy Bỏ
              </button>
              <button
                onClick={() => setWifiStep(2)}
                className="touch-btn flex-1 py-[12px] rounded-xl"
                style={{ background: "#3B82F6", color: "#fff", fontSize: 13, fontWeight: 700, border: "none" }}
              >
                Tiếp tục (Lớp 2) ➜
              </button>
            </div>
          </div>
        </div>
      )}

      {/* MODAL LỚP 2: Kích hoạt Bảo vệ Rollback */}
      {wifiStep === 2 && (
        <div className="fixed inset-0 z-50 flex items-center justify-center modal-backdrop" style={{ padding: 20 }}>
          <div
            style={{
              background: "var(--bg-card)", borderRadius: 24, border: "1px solid #F59E0B",
              padding: 24, width: "100%", maxWidth: 420, position: "relative",
              boxShadow: "0 25px 50px -12px rgba(0, 0, 0, 0.75)"
            }}
          >
            <button
              onClick={() => setWifiStep(0)}
              style={{
                position: "absolute", top: 16, right: 16, width: 32, height: 32,
                borderRadius: "50%", background: "#222F46", border: "1px solid var(--border-color)",
                color: "var(--text-muted)", display: "flex", alignItems: "center", justifyContent: "center",
                fontSize: 16, fontWeight: 700, cursor: "pointer"
              }}
            >
              ✕
            </button>

            <div className="flex items-center gap-2 mb-3">
              <span style={{ fontSize: 22 }}>🛡️</span>
              <span style={{ fontSize: 16, fontWeight: 700, color: "#F59E0B" }}>
                Kích Hoạt Bảo Vệ Rollback (Lớp 2/2)
              </span>
            </div>

            <div style={{ background: "#2D1D00", borderRadius: 14, border: "1px solid #F59E0B", padding: 14, fontSize: 12, color: "#FEF3C7", lineHeight: 1.6, marginBottom: 16 }}>
              <p className="mb-2">
                ⚠️ <strong>Cơ chế an toàn tự động:</strong> Khi bạn bấm Áp Dụng, router sẽ kích hoạt đồng hồ đếm ngược <strong>60 giây</strong>.
              </p>
              <p>
                Nếu sau 60 giây thiết bị của bạn không thể kết nối hoặc bạn không bấm <em>"Xác nhận mạng tốt"</em>, router sẽ <strong>tự động hoàn tác về mật khẩu cũ</strong> để đảm bảo bạn không bao giờ bị mất kết nối!
              </p>
            </div>

            <div className="flex gap-3">
              <button
                onClick={() => setWifiStep(1)}
                className="touch-btn flex-1 py-[12px] rounded-xl"
                style={{ background: "#222F46", color: "var(--text-muted)", fontSize: 13, fontWeight: 600, border: "none" }}
              >
                Quay Lại Lớp 1
              </button>
              <button
                onClick={handleStartApply}
                disabled={isApplying}
                className="touch-btn flex-1 py-[12px] rounded-xl"
                style={{ background: "#F59E0B", color: "#000", fontSize: 13, fontWeight: 700, border: "none" }}
              >
                {isApplying ? "Đang áp dụng..." : "Áp Dụng & Đếm Ngược 🚀"}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* MODAL LỚP 3: Đồng hồ đếm ngược Rollback */}
      {wifiStep === 3 && (
        <div className="fixed inset-0 z-50 flex items-center justify-center modal-backdrop" style={{ padding: 20 }}>
          <div
            style={{
              background: "var(--bg-card)", borderRadius: 24, border: "1px solid #3B82F6",
              padding: 24, width: "100%", maxWidth: 420, textAlign: "center",
              boxShadow: "0 25px 50px -12px rgba(0, 0, 0, 0.75)"
            }}
          >
            <div style={{ fontSize: 13, fontWeight: 600, color: "var(--text-muted)", marginBottom: 8 }}>
              ĐANG ĐẾM NGƯỢC BẢO VỆ ROLLBACK
            </div>

            <div
              className="mono"
              style={{
                fontSize: 48, fontWeight: 800,
                color: countdown <= 15 ? "#EF4444" : countdown <= 30 ? "#F59E0B" : "#10B981",
                margin: "12px 0"
              }}
            >
              {countdown}s
            </div>

            <p style={{ fontSize: 12, color: "#CBD5E1", lineHeight: 1.6, marginBottom: 20 }}>
              Sóng Wi-Fi đang khởi động lại. Nếu bạn vào được mạng ổn định, hãy nhấn <strong>Giữ cấu hình</strong>. Nếu gặp sự cố, nhấn <strong>Hoàn tác ngay</strong>.
            </p>

            <div className="flex flex-col gap-2">
              <button
                onClick={handleKeepConfig}
                className="touch-btn w-full py-[12px] rounded-xl"
                style={{ background: "#10B981", color: "#fff", fontSize: 14, fontWeight: 700, border: "none" }}
              >
                🟢 XÁC NHẬN MẠNG TỐT (GIỮ CẤU HÌNH)
              </button>
              <button
                onClick={() => handleRollback(false)}
                disabled={isApplying}
                className="touch-btn w-full py-[12px] rounded-xl"
                style={{ background: "#222F46", color: "#EF4444", fontSize: 13, fontWeight: 600, border: "1px solid #EF4444" }}
              >
                🔄 HOÀN TÁC VỀ CẤU HÌNH CŨ NGAY (ROLLBACK)
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// NextDNSScreen is now imported from ./NextDNSScreen

function SettingsScreen({ onLogout, currentUser }: { onLogout?: () => void; currentUser?: string }) {
  const [oldPass, setOldPass] = useState("");
  const [newPass, setNewPass] = useState("");
  const [confirmPass, setConfirmPass] = useState("");
  const [pwMsg, setPwMsg] = useState<{ text: string; error?: boolean } | null>(null);
  const [pwLoading, setPwLoading] = useState(false);

  const handleChangePassword = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!oldPass || !newPass) {
      setPwMsg({ text: "Vui lòng nhập mật khẩu cũ và mật khẩu mới!", error: true });
      return;
    }
    if (newPass !== confirmPass) {
      setPwMsg({ text: "Mật khẩu mới không trùng khớp!", error: true });
      return;
    }
    if (newPass.length < 3) {
      setPwMsg({ text: "Mật khẩu mới tối thiểu 3 ký tự!", error: true });
      return;
    }
    setPwLoading(true);
    setPwMsg(null);
    try {
      const res = await changePasswordApi(oldPass, newPass);
      if (res && res.status === "ok") {
        setPwMsg({ text: res.message || "Đã đổi mật khẩu thành công!", error: false });
        setOldPass("");
        setNewPass("");
        setConfirmPass("");
      } else {
        setPwMsg({ text: res?.message || "Đổi mật khẩu thất bại. Mật khẩu cũ không đúng!", error: true });
      }
    } catch {
      setPwMsg({ text: "Lỗi kết nối tới router!", error: true });
    } finally {
      setPwLoading(false);
    }
  };

  const [modem, setModem] = useState<ModemStatus>({
    connected: false,
    model: "Đang kiểm tra...",
    operator: "N/A",
    band: "N/A",
    rsrp: 0,
    sinr: 0,
    messages: []
  });

  // Telegram Bot State
  const [tgConfig, setTgConfig] = useState<TelegramConfig | null>(null);
  const [tgToken, setTgToken] = useState("");
  const [tgChatId, setTgChatId] = useState("");
  const [tgNotifWifi, setTgNotifWifi] = useState(true);
  const [tgNotifExpire, setTgNotifExpire] = useState(true);
  const [tgNotifDaily, setTgNotifDaily] = useState(true);
  const [tgDailyHour, setTgDailyHour] = useState(20);
  const [tgEnabled, setTgEnabled] = useState(true);
  const [tgLoading, setTgLoading] = useState(false);
  const [tgTesting, setTgTesting] = useState(false);
  const [tgMsg, setTgMsg] = useState<{ text: string; error?: boolean } | null>(null);
  const [showTokenInput, setShowTokenInput] = useState(false);
  const [showRawToken, setShowRawToken] = useState(false);
  const [showChatIdInput, setShowChatIdInput] = useState(false);
  const [showRawChatId, setShowRawChatId] = useState(false);
  const [showOldPw, setShowOldPw] = useState(false);
  const [showNewPw, setShowNewPw] = useState(false);
  const [showConfirmPw, setShowConfirmPw] = useState(false);
  const [isEditingTg, setIsEditingTg] = useState(false);
  const [tgAutoUpdate, setTgAutoUpdate] = useState(false);

  const [updateStatus, setUpdateStatus] = useState<UpdateStatus | null>(null);
  const [isCheckingUpdate, setIsCheckingUpdate] = useState(false);
  const [isUpdating, setIsUpdating] = useState(false);
  const [updateMsg, setUpdateMsg] = useState<{ text: string; error?: boolean } | null>(null);

  const handleCheckUpdate = async () => {
    setIsCheckingUpdate(true);
    setUpdateMsg(null);
    try {
      const res = await checkUpdateApi();
      if (res && res.status === "ok") {
        setUpdateStatus(res);
        if (res.has_update) {
          setUpdateMsg({ text: `🎉 Phát hiện bản cập nhật mới: v${res.remote_version}!` });
        } else {
          setUpdateMsg({ text: `✅ Bạn đang sử dụng phiên bản mới nhất: v${res.current_version}` });
        }
      } else {
        setUpdateMsg({ text: "Không thể kiểm tra bản cập nhật lúc này.", error: true });
      }
    } catch (e: any) {
      setUpdateMsg({ text: e?.message || "Lỗi kết nối kiểm tra cập nhật.", error: true });
    } finally {
      setIsCheckingUpdate(false);
    }
  };

  const handleDoUpdate = async () => {
    if (!confirm("Bắt đầu tải gói và cập nhật VCRT OS từ GitHub?\\nRouter sẽ tự khởi động lại dịch vụ sau khi hoàn thành.")) return;
    setIsUpdating(true);
    setUpdateMsg({ text: "🚀 Đang tiến hành tải gói cập nhật từ GitHub..." });
    try {
      const res = await doUpdateApi();
      if (res && res.status === "ok") {
        setUpdateMsg({ text: "🚀 Đã khởi chạy tiến trình cập nhật ngầm! Vui lòng đợi khoảng 10-15 giây..." });
      } else {
        setUpdateMsg({ text: "Lỗi khởi động cập nhật.", error: true });
      }
    } catch (e: any) {
      setUpdateMsg({ text: e?.message || "Lỗi cập nhật.", error: true });
    } finally {
      setIsUpdating(false);
    }
  };


  const fetchTelegramConfig = async () => {
    const data = await getTelegramConfigApi();
    if (data) {
      setTgConfig(data);
      setTgChatId(data.chat_id || "");
      setTgNotifWifi(data.notif_wifi ?? true);
      setTgNotifExpire(data.notif_expire ?? true);
      setTgNotifDaily(data.notif_daily ?? true);
      setTgDailyHour(data.daily_hour || 20);
      setTgEnabled(data.enabled ?? false);
      setTgAutoUpdate(data.auto_update ?? false);
      if (!data.has_token || !data.chat_id) {
        setIsEditingTg(true);
      } else {
        setIsEditingTg(false);
      }
    }
    // Also check update status in background
    checkUpdateApi().then((res) => {
      if (res && res.status === "ok") {
        setUpdateStatus(res);
      }
    }).catch(() => {});
  };

  useEffect(() => {
    const fetchModem = async () => {
      const res = await fetchApi("modem_get");
      if (res) {
        setModem(res);
      }
    };
    fetchModem();
    fetchTelegramConfig();
  }, []);

  const handleSaveTelegram = async () => {
    setTgLoading(true);
    setTgMsg(null);
    try {
      const res = await saveTelegramConfigApi({
        bot_token: tgToken || undefined,
        chat_id: tgChatId,
        auto_update: tgAutoUpdate,
        notif_wifi: tgNotifWifi,
        notif_expire: tgNotifExpire,
        notif_daily: tgNotifDaily,
        daily_hour: tgDailyHour,
        bot_enabled: tgEnabled
      });
      if (res && res.status === "ok") {
        setTgMsg({ text: "✅ Đã lưu cấu hình và đồng bộ dịch vụ Telegram Bot thành công!" });
        setTgToken("");
        setShowTokenInput(false);
        setShowChatIdInput(false);
        await fetchTelegramConfig();
      } else {
        setTgMsg({ text: "❌ Lỗi lưu cấu hình Telegram Bot.", error: true });
      }
    } catch (e: any) {
      setTgMsg({ text: e?.message || "Lỗi kết nối.", error: true });
    } finally {
      setTgLoading(false);
    }
  };

  const handleTestTelegram = async () => {
    setTgTesting(true);
    setTgMsg(null);
    try {
      const res = await testTelegramBotApi(tgToken || undefined, tgChatId || undefined);
      if (res && res.status === "ok") {
        setTgMsg({ text: "✅ Tin nhắn thử nghiệm đã được gửi thành công đến Telegram của bạn!" });
      } else {
        setTgMsg({ text: `❌ Gửi tin thất bại: ${res?.message || "Kiểm tra lại Token và Chat ID"}`, error: true });
      }
    } catch (e: any) {
      setTgMsg({ text: `❌ Lỗi gửi tin: ${e?.message}`, error: true });
    } finally {
      setTgTesting(false);
    }
  };

  const handleToggleService = async (action: "start" | "stop") => {
    setTgLoading(true);
    setTgMsg(null);
    try {
      await controlTelegramServiceApi(action);
      await fetchTelegramConfig();
      setTgMsg({ text: action === "start" ? "✅ Đã khởi động dịch vụ Telegram Bot!" : "⏹️ Đã dừng dịch vụ Telegram Bot!" });
    } catch (e: any) {
      setTgMsg({ text: `Lỗi thao tác dịch vụ: ${e?.message}`, error: true });
    } finally {
      setTgLoading(false);
    }
  };

  const handleCleanRam = async () => {
    const res = await postApi("clean_ram");
    if (res && res.mem_avail !== undefined) {
      alert(`Đã giải phóng RAM thành công! Bộ nhớ trống hiện tại: ${res.mem_avail} MB`);
    } else {
      alert("Đã gửi lệnh làm trống bộ nhớ RAM!");
    }
  };

  const handleReboot = async () => {
    if (confirm("Bạn có chắc chắn muốn khởi động lại Router?")) {
      await postApi("reboot");
      alert("Router đang khởi động lại trong 3 giây...");
    }
  };

  return (
    <div className="flex flex-col gap-3 p-4 mb-nav">
      <div className="pt-1">
        <div style={{ fontSize: 13, color: "var(--text-muted)", fontWeight: 500 }}>QUẢN TRỊ HỆ THỐNG</div>
        <div style={{ fontSize: 22, fontWeight: 700, color: "var(--text-primary)" }}>Cài đặt & Phần cứng</div>
      </div>

      <div style={{ background: "var(--bg-card)", borderRadius: 16, border: "1px solid var(--border-color)", padding: 16 }}>
        <div className="flex items-center gap-2 mb-4">
          <span style={{ fontSize: 18 }}>📡</span>
          <span style={{ fontSize: 13, fontWeight: 700, color: "var(--text-primary)" }}>Modem 4G LTE USB</span>
          <span style={{
            marginLeft: "auto",
            fontSize: 10,
            fontWeight: 600,
            padding: "2px 8px",
            borderRadius: 6,
            background: modem.connected ? "#0D2818" : "#222F46",
            color: modem.connected ? "#10B981" : "#94A3B8",
            border: `1px solid ${modem.connected ? "#10B981" : "#334155"}`
          }}>
            {modem.connected ? "CONNECTED" : "DISCONNECTED"}
          </span>
        </div>

        {modem.connected ? (
          <div>
            <div className="flex justify-between mb-4">
              <div>
                <div style={{ fontSize: 11, color: "var(--text-muted)" }}>Trạng thái</div>
                <div style={{ fontSize: 14, fontWeight: 600, color: "#10B981" }}>{modem.operator}</div>
              </div>
              <div>
                <div style={{ fontSize: 11, color: "var(--text-muted)" }}>Thiết bị</div>
                <div style={{ fontSize: 14, fontWeight: 600, color: "var(--text-primary)" }}>{modem.model}</div>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3 mb-2">
              <div style={{ background: "var(--bg-canvas)", borderRadius: 12, padding: 12 }}>
                <div style={{ fontSize: 10, color: "var(--text-muted)", marginBottom: 4 }}>RSRP</div>
                <div className="mono" style={{ fontSize: 22, fontWeight: 700, color: "#10B981" }}>{modem.rsrp} dBm</div>
              </div>
              <div style={{ background: "var(--bg-canvas)", borderRadius: 12, padding: 12 }}>
                <div style={{ fontSize: 10, color: "var(--text-muted)", marginBottom: 4 }}>SINR</div>
                <div className="mono" style={{ fontSize: 22, fontWeight: 700, color: "#10B981" }}>{modem.sinr} dB</div>
              </div>
            </div>
          </div>
        ) : (
          <div style={{ background: "var(--bg-canvas)", borderRadius: 12, padding: 14, textAlign: "center" }}>
            <div style={{ fontSize: 13, color: "var(--text-muted)" }}>Chưa cắm modem 4G USB vào cổng USB của router.</div>
            <div style={{ fontSize: 11, color: "var(--text-subtle)", marginTop: 4 }}>Khi cắm Dcom 4G (Huawei, ZTE), thông số sóng và nhà mạng sẽ hiển thị tại đây.</div>
          </div>
        )}
      </div>

      {/* TÀI KHOẢN & BẢO MẬT HỆ THỐNG */}
      <div style={{ background: "var(--bg-card)", borderRadius: 16, border: "1px solid var(--border-color)", padding: 16 }}>
        <div className="flex items-center justify-between mb-3">
          <div style={{ fontSize: 11, color: "var(--text-muted)" }}>TÀI KHOẢN & BẢO MẬT ĐĂNG NHẬP</div>
          <span style={{ fontSize: 11, color: "#10B981", background: "rgba(16, 185, 129, 0.15)", padding: "2px 8px", borderRadius: 6, fontWeight: 700 }}>
            👤 {currentUser || "admin"}
          </span>
        </div>

        {pwMsg && (
          <div
            style={{
              padding: "8px 12px",
              borderRadius: 8,
              fontSize: 12,
              marginBottom: 12,
              background: pwMsg.error ? "rgba(239, 68, 68, 0.15)" : "rgba(16, 185, 129, 0.15)",
              color: pwMsg.error ? "#EF4444" : "#10B981",
              border: pwMsg.error ? "1px solid rgba(239, 68, 68, 0.3)" : "1px solid rgba(16, 185, 129, 0.3)"
            }}
          >
            {pwMsg.text}
          </div>
        )}

        <form onSubmit={handleChangePassword} className="flex flex-col gap-2.5">
          <div>
            <div style={{ fontSize: 11, color: "var(--text-subtle)", marginBottom: 4 }}>Mật khẩu hiện tại</div>
            <div style={{ position: "relative" }}>
              <input
                type={showOldPw ? "text" : "password"}
                value={oldPass}
                onChange={(e) => setOldPass(e.target.value)}
                placeholder="Mật khẩu cũ..."
                style={{ width: "100%", background: "var(--bg-canvas)", border: "1px solid var(--border-color)", borderRadius: 8, padding: "8px 38px 8px 12px", color: "#fff", fontSize: 13, outline: "none", boxSizing: "border-box" }}
              />
              <button
                type="button"
                onClick={() => setShowOldPw(!showOldPw)}
                style={{ position: "absolute", right: 10, top: "50%", transform: "translateY(-50%)", background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer", fontSize: 13 }}
              >
                {showOldPw ? "🙈" : "👁"}
              </button>
            </div>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
            <div>
              <div style={{ fontSize: 11, color: "var(--text-subtle)", marginBottom: 4 }}>Mật khẩu mới</div>
              <div style={{ position: "relative" }}>
                <input
                  type={showNewPw ? "text" : "password"}
                  value={newPass}
                  onChange={(e) => setNewPass(e.target.value)}
                  placeholder="Mật khẩu mới..."
                  style={{ width: "100%", background: "var(--bg-canvas)", border: "1px solid var(--border-color)", borderRadius: 8, padding: "8px 38px 8px 12px", color: "#fff", fontSize: 13, outline: "none", boxSizing: "border-box" }}
                />
                <button
                  type="button"
                  onClick={() => setShowNewPw(!showNewPw)}
                  style={{ position: "absolute", right: 10, top: "50%", transform: "translateY(-50%)", background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer", fontSize: 13 }}
                >
                  {showNewPw ? "🙈" : "👁"}
                </button>
              </div>
            </div>
            <div>
              <div style={{ fontSize: 11, color: "var(--text-subtle)", marginBottom: 4 }}>Xác nhận mật khẩu</div>
              <div style={{ position: "relative" }}>
                <input
                  type={showConfirmPw ? "text" : "password"}
                  value={confirmPass}
                  onChange={(e) => setConfirmPass(e.target.value)}
                  placeholder="Nhập lại mật khẩu..."
                  style={{ width: "100%", background: "var(--bg-canvas)", border: "1px solid var(--border-color)", borderRadius: 8, padding: "8px 38px 8px 12px", color: "#fff", fontSize: 13, outline: "none", boxSizing: "border-box" }}
                />
                <button
                  type="button"
                  onClick={() => setShowConfirmPw(!showConfirmPw)}
                  style={{ position: "absolute", right: 10, top: "50%", transform: "translateY(-50%)", background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer", fontSize: 13 }}
                >
                  {showConfirmPw ? "🙈" : "👁"}
                </button>
              </div>
            </div>
          </div>

          <div className="flex items-center gap-2 mt-1">
            <button
              type="submit"
              disabled={pwLoading}
              className="touch-btn flex-1 py-2 rounded-xl flex items-center justify-center gap-1.5"
              style={{ background: "#2563EB", color: "#fff", fontSize: 13, fontWeight: 700, border: "none" }}
            >
              <span>🔑</span> {pwLoading ? "Đang xử lý..." : "Cập Nhật Mật Khẩu"}
            </button>
            {onLogout && (
              <button
                type="button"
                onClick={onLogout}
                className="touch-btn py-2 px-4 rounded-xl flex items-center justify-center gap-1.5"
                style={{ background: "rgba(239, 68, 68, 0.12)", color: "#EF4444", fontSize: 13, fontWeight: 600, border: "1px solid rgba(239, 68, 68, 0.3)" }}
              >
                <span>🚪</span> Đăng Xuất
              </button>
            )}
          </div>
        </form>
      </div>

      {/* TELEGRAM BOT THÔNG BÁO & ĐỒNG BỘ 24/7 (REDESIGNED) */}
      <div style={{ background: "var(--bg-card)", borderRadius: 16, border: "1px solid var(--border-color)", padding: 16 }}>
        <div className="flex items-center justify-between mb-2">
          <div className="flex items-center gap-2">
            <span style={{ fontSize: 20 }}>🤖</span>
            <span style={{ fontSize: 14, fontWeight: 700, color: "var(--text-primary)" }}>Telegram Bot & Thông Báo 24/7</span>
          </div>
          <span
            style={{
              fontSize: 10,
              fontWeight: 700,
              padding: "2px 8px",
              borderRadius: 6,
              background: tgConfig?.running ? "rgba(16, 185, 129, 0.15)" : "rgba(239, 68, 68, 0.15)",
              color: tgConfig?.running ? "#10B981" : "#EF4444",
              border: `1px solid ${tgConfig?.running ? "rgba(16, 185, 129, 0.3)" : "rgba(239, 68, 68, 0.3)"}`,
              display: "flex",
              alignItems: "center",
              gap: 4
            }}
          >
            <span className="pulse-dot" style={{ width: 6, height: 6, borderRadius: "50%", background: tgConfig?.running ? "#10B981" : "#EF4444" }} />
            {tgConfig?.running ? "ĐANG CHẠY 24/7" : "CHƯA KÍCH HOẠT"}
          </span>
        </div>

        <div style={{ fontSize: 11, color: "var(--text-subtle)", marginBottom: 12 }}>
          Giám sát thiết bị theo thời gian thực, tự động mở mạng, phát hiện máy lạ và báo cáo lưu lượng qua Telegram cá nhân hoặc Nhóm chat.
        </div>

        {tgMsg && (
          <div
            style={{
              padding: "8px 12px",
              borderRadius: 8,
              fontSize: 12,
              marginBottom: 12,
              background: tgMsg.error ? "rgba(239, 68, 68, 0.15)" : "rgba(16, 185, 129, 0.15)",
              color: tgMsg.error ? "#EF4444" : "#10B981",
              border: tgMsg.error ? "1px solid rgba(239, 68, 68, 0.3)" : "1px solid rgba(16, 185, 129, 0.3)"
            }}
          >
            {tgMsg.text}
          </div>
        )}

        {/* TRẠNG THÁI ĐÃ KẾT NỐI (ẨN 2 Ô NHẬP NẾU ĐÃ CÓ CẤU HÌNH) */}
        {tgConfig?.has_token && tgConfig?.chat_id && !isEditingTg ? (
          <div style={{ background: "var(--bg-canvas)", borderRadius: 12, padding: 14, border: "1px solid var(--border-color)" }} className="flex flex-col gap-3">
            <div className="flex items-center justify-between pb-2" style={{ borderBottom: "1px solid #1E293B" }}>
              <div className="flex items-center gap-2">
                <span style={{ fontSize: 16 }}>🛡️</span>
                <span style={{ fontSize: 12, fontWeight: 700, color: "#10B981" }}>ĐÃ KẾT NỐI VÀ BẢO MẬT</span>
              </div>
              <button
                type="button"
                onClick={() => {
                  setIsEditingTg(true);
                  setTgToken("");
                  setTgChatId(tgConfig.chat_id);
                }}
                className="touch-btn py-1 px-3 rounded-lg"
                style={{ background: "#2563EB", color: "#fff", fontSize: 11, fontWeight: 600, border: "none" }}
              >
                ⚙️ Cập Nhật Token & Chat ID
              </button>
            </div>

            {/* Token Hiển Thị */}
            <div className="flex items-center justify-between">
              <span style={{ fontSize: 11, color: "var(--text-muted)" }}>Bot Token:</span>
              <span className="mono" style={{ fontSize: 12, color: "var(--text-primary)", background: "var(--bg-card)", padding: "2px 8px", borderRadius: 6 }}>
                🔑 {tgConfig.token_masked}
              </span>
            </div>

            {/* Chat ID / Nhóm Hiển Thị */}
            <div>
              <div className="flex items-center justify-between mb-1">
                <span style={{ fontSize: 11, color: "var(--text-muted)" }}>
                  Chat ID & Nhóm nhận tin:
                </span>
                <button
                  type="button"
                  onClick={() => setShowRawChatId(!showRawChatId)}
                  style={{ background: "none", border: "none", color: "#38BDF8", fontSize: 11, cursor: "pointer" }}
                >
                  {showRawChatId ? "🙈 Ẩn ID" : "👁 Hiện toàn bộ"}
                </button>
              </div>
              <div
                className="mono flex flex-wrap gap-1.5 p-2 rounded-lg"
                style={{ background: "var(--bg-card)", border: "1px solid var(--border-color)" }}
              >
                {tgConfig.chat_id.split(/[,\s;]+/).filter(Boolean).map((cid, idx) => {
                  const isGroup = cid.startsWith("-");
                  const displayCid = showRawChatId
                    ? cid
                    : (cid.length > 5 ? cid.slice(0, 3) + "••••" + cid.slice(-2) : "•••••");
                  return (
                    <span
                      key={idx}
                      style={{
                        fontSize: 11,
                        color: isGroup ? "#A78BFA" : "#38BDF8",
                        background: isGroup ? "rgba(139, 92, 246, 0.15)" : "rgba(56, 189, 248, 0.15)",
                        padding: "2px 8px",
                        borderRadius: 6,
                        border: `1px solid ${isGroup ? "rgba(139, 92, 246, 0.3)" : "rgba(56, 189, 248, 0.3)"}`
                      }}
                    >
                      {isGroup ? "📢 Nhóm: " : "👤 "} {displayCid}
                    </span>
                  );
                })}
              </div>
            </div>

            {/* Nút hành động nhanh */}
            <div className="flex items-center gap-2 pt-1">
              <button
                type="button"
                onClick={handleTestTelegram}
                disabled={tgTesting}
                className="touch-btn flex-1 py-2 px-3 rounded-xl flex items-center justify-center gap-1.5"
                style={{ background: "rgba(56, 189, 248, 0.12)", color: "#38BDF8", fontSize: 12, fontWeight: 600, border: "1px solid rgba(56, 189, 248, 0.3)" }}
              >
                <span>✉️</span> {tgTesting ? "Đang gửi thử..." : "Gửi Tin Thử Nghiệm"}
              </button>
              {tgConfig?.running ? (
                <button
                  type="button"
                  onClick={() => handleToggleService("stop")}
                  disabled={tgLoading}
                  className="touch-btn py-2 px-3 rounded-xl flex items-center justify-center gap-1"
                  style={{ background: "rgba(239, 68, 68, 0.15)", color: "#EF4444", fontSize: 12, fontWeight: 600, border: "1px solid rgba(239, 68, 68, 0.3)" }}
                >
                  <span>⏹️</span> Dừng
                </button>
              ) : (
                <button
                  type="button"
                  onClick={() => handleToggleService("start")}
                  disabled={tgLoading}
                  className="touch-btn py-2 px-3 rounded-xl flex items-center justify-center gap-1"
                  style={{ background: "rgba(16, 185, 129, 0.15)", color: "#10B981", fontSize: 12, fontWeight: 600, border: "1px solid rgba(16, 185, 129, 0.3)" }}
                >
                  <span>▶️</span> Chạy 24/7
                </button>
              )}
            </div>
          </div>
        ) : (
          /* FORM NHẬP / CHỈNH SỬA TOKEN VÀ NHIỀU CHAT ID */
          <div className="flex flex-col gap-3">
            <div>
              <div className="flex justify-between items-center mb-1">
                <span style={{ fontSize: 11, color: "var(--text-muted)" }}>Bot Token (lấy từ @BotFather)</span>
                {tgConfig?.has_token && (
                  <span className="mono" style={{ fontSize: 10, color: "#10B981" }}>Đang dùng: {tgConfig.token_masked}</span>
                )}
              </div>
              <div style={{ position: "relative" }}>
                <input
                  type={showRawToken ? "text" : "password"}
                  value={tgToken}
                  onChange={(e) => setTgToken(e.target.value)}
                  placeholder={tgConfig?.has_token ? "Để trống nếu không muốn đổi Token" : "vd: 7427895422:AAGcWzIvYYhx..."}
                  style={{
                    width: "100%",
                    background: "var(--bg-canvas)",
                    border: "1px solid var(--border-color)",
                    borderRadius: 8,
                    padding: "8px 38px 8px 12px",
                    color: "#fff",
                    fontSize: 12,
                    outline: "none",
                    boxSizing: "border-box"
                  }}
                />
                <button
                  type="button"
                  onClick={() => setShowRawToken(!showRawToken)}
                  style={{ position: "absolute", right: 10, top: "50%", transform: "translateY(-50%)", background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer", fontSize: 13 }}
                >
                  {showRawToken ? "🙈" : "👁"}
                </button>
              </div>
            </div>

            <div>
              <div className="flex justify-between items-center mb-1">
                <span style={{ fontSize: 11, color: "var(--text-muted)" }}>Chat ID hoặc ID Nhóm (hỗ trợ nhiều ID)</span>
                <span style={{ fontSize: 10, color: "#38BDF8" }}>Phân tách bằng dấu phẩy</span>
              </div>
              <input
                type="text"
                value={tgChatId}
                onChange={(e) => setTgChatId(e.target.value)}
                placeholder="vd: 5746523635, -1001234567890"
                style={{
                  width: "100%",
                  background: "var(--bg-canvas)",
                  border: "1px solid var(--border-color)",
                  borderRadius: 8,
                  padding: "8px 12px",
                  color: "#fff",
                  fontSize: 12,
                  outline: "none",
                  boxSizing: "border-box"
                }}
              />
              <div style={{ fontSize: 10, color: "var(--text-subtle)", marginTop: 4 }}>
                💡 <i>Để gửi vào nhóm Telegram: Thêm Bot vào nhóm và nhập ID nhóm (bắt đầu bằng dấu trừ, ví dụ <code>-1002345678901</code>). Nhập nhiều ID cách nhau bằng dấu phẩy.</i>
              </div>
            </div>

            {/* Các tùy chọn bật tắt thông báo */}
            <div style={{ background: "var(--bg-canvas)", borderRadius: 10, padding: "10px 12px", border: "1px solid var(--border-color)" }} className="flex flex-col gap-2.5">
              <label className="flex items-center gap-2 cursor-pointer select-none">
                <input
                  type="checkbox"
                  checked={tgNotifWifi}
                  onChange={(e) => setTgNotifWifi(e.target.checked)}
                  style={{ accentColor: "#3B82F6", width: 15, height: 15 }}
                />
                <span style={{ fontSize: 12, color: "#E2E8F0" }}>
                  🔔 <strong>Báo thiết bị Wi-Fi mới</strong> (Tên, IP, MAC, 2.4G/5G)
                </span>
              </label>

              <label className="flex items-center gap-2 cursor-pointer select-none">
                <input
                  type="checkbox"
                  checked={tgNotifExpire}
                  onChange={(e) => setTgNotifExpire(e.target.checked)}
                  style={{ accentColor: "#3B82F6", width: 15, height: 15 }}
                />
                <span style={{ fontSize: 12, color: "#E2E8F0" }}>
                  ⏱ <strong>Báo hết giờ ngắt kết nối</strong> (Tự mở mạng lại)
                </span>
              </label>

              <label className="flex items-center gap-2 cursor-pointer select-none">
                <input
                  type="checkbox"
                  checked={tgNotifDaily}
                  onChange={(e) => setTgNotifDaily(e.target.checked)}
                  style={{ accentColor: "#3B82F6", width: 15, height: 15 }}
                />
                <span style={{ fontSize: 12, color: "#E2E8F0" }}>
                  📊 <strong>Báo cáo lưu lượng hàng ngày</strong> (Lúc {tgDailyHour}h tối)
                </span>
              </label>

              <label className="flex items-center gap-2 cursor-pointer select-none">
                <input
                  type="checkbox"
                  checked={tgAutoUpdate}
                  onChange={(e) => setTgAutoUpdate(e.target.checked)}
                  style={{ accentColor: "#10B981", width: 15, height: 15 }}
                />
                <span style={{ fontSize: 12, color: "#E2E8F0" }}>
                  🚀 <strong>Tự động cập nhật VCRT OS</strong> (Khi GitHub có bản mới)
                </span>
              </label>
            </div>

            <div className="flex items-center gap-2 mt-1">
              <button
                type="button"
                onClick={handleSaveTelegram}
                disabled={tgLoading}
                className="touch-btn flex-1 py-2 px-3 rounded-xl flex items-center justify-center gap-1.5"
                style={{ background: "#2563EB", color: "#fff", fontSize: 12, fontWeight: 700, border: "none" }}
              >
                <span>💾</span> {tgLoading ? "Đang lưu..." : "Lưu Cấu Hình"}
              </button>
              <button
                type="button"
                onClick={handleTestTelegram}
                disabled={tgTesting || (!tgToken && !tgConfig?.has_token) || !tgChatId}
                className="touch-btn py-2 px-3 rounded-xl flex items-center justify-center gap-1"
                style={{ background: "rgba(56, 189, 248, 0.12)", color: "#38BDF8", fontSize: 12, fontWeight: 600, border: "1px solid rgba(56, 189, 248, 0.3)" }}
              >
                <span>✉️</span> Gửi Thử
              </button>
              {tgConfig?.has_token && tgConfig?.chat_id && (
                <button
                  type="button"
                  onClick={() => setIsEditingTg(false)}
                  className="touch-btn py-2 px-3 rounded-xl"
                  style={{ background: "rgba(148, 163, 184, 0.15)", color: "var(--text-muted)", fontSize: 12, border: "none" }}
                >
                  Đóng
                </button>
              )}
            </div>
          </div>
        )}
      </div>

      {/* KHỐI QUẢN LÝ PHIÊN BẢN & CẬP NHẬT HỆ THỐNG VCRT OS */}
      <div style={{ background: "var(--bg-card)", borderRadius: 16, border: "1px solid var(--border-color)", padding: 16 }}>
        <div className="flex items-center justify-between mb-2">
          <div className="flex items-center gap-2">
            <span style={{ fontSize: 20 }}>🚀</span>
            <span style={{ fontSize: 14, fontWeight: 700, color: "var(--text-primary)" }}>Phiên Bản & Cập Nhật Hệ Thống</span>
          </div>
          <span
            className="mono"
            style={{
              fontSize: 11,
              fontWeight: 700,
              padding: "2px 8px",
              borderRadius: 6,
              background: "rgba(56, 189, 248, 0.15)",
              color: "#38BDF8",
              border: "1px solid rgba(56, 189, 248, 0.3)"
            }}
          >
            v{updateStatus?.current_version || "1.0.0"}
          </span>
        </div>

        <div style={{ fontSize: 11, color: "var(--text-subtle)", marginBottom: 12 }}>
          Đồng bộ và nâng cấp VCRT OS một chạm trực tiếp từ máy chủ GitHub chính thức.
        </div>

        {updateMsg && (
          <div
            style={{
              padding: "8px 12px",
              borderRadius: 8,
              fontSize: 12,
              marginBottom: 12,
              background: updateMsg.error ? "rgba(239, 68, 68, 0.15)" : "rgba(16, 185, 129, 0.15)",
              color: updateMsg.error ? "#EF4444" : "#10B981",
              border: updateMsg.error ? "1px solid rgba(239, 68, 68, 0.3)" : "1px solid rgba(16, 185, 129, 0.3)"
            }}
          >
            {updateMsg.text}
          </div>
        )}

        {/* Thông báo có bản cập nhật mới */}
        {updateStatus?.has_update && (
          <div
            style={{
              background: "linear-gradient(135deg, rgba(6, 182, 212, 0.15), rgba(59, 130, 246, 0.15))",
              border: "1px solid rgba(6, 182, 212, 0.4)",
              borderRadius: 12,
              padding: 14,
              marginBottom: 12
            }}
          >
            <div className="flex items-center gap-2 mb-1">
              <span style={{ fontSize: 18 }}>🎉</span>
              <span style={{ fontSize: 13, fontWeight: 700, color: "#38BDF8" }}>
                ĐÃ CÓ PHIÊN BẢN MỚI: v{updateStatus.remote_version}!
              </span>
            </div>
            <div style={{ fontSize: 11, color: "#CBD5E1", marginBottom: 10 }}>
              Bản cập nhật bao gồm các tối ưu hiệu năng, bảo mật và tính năng mới nhất từ kho mã nguồn.
            </div>
            <button
              type="button"
              onClick={handleDoUpdate}
              disabled={isUpdating}
              className="touch-btn w-full py-2.5 rounded-xl flex items-center justify-center gap-2"
              style={{ background: "linear-gradient(135deg, #06B6D4, #2563EB)", color: "#fff", fontSize: 13, fontWeight: 700, border: "none" }}
            >
              <span>⚡</span> {isUpdating ? "Đang tải và nạp bản cập nhật..." : "Cập Nhật Ngay Lập Tức"}
            </button>
          </div>
        )}

        {/* Nút kiểm tra bản mới & Cài đặt tự động cập nhật */}
        <div className="flex flex-col gap-2.5">
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleCheckUpdate}
              disabled={isCheckingUpdate}
              className="touch-btn flex-1 py-2 px-3 rounded-xl flex items-center justify-center gap-1.5"
              style={{ background: "#222F46", color: "var(--text-primary)", fontSize: 12, fontWeight: 600, border: "1px solid var(--border-color)" }}
            >
              <span>🔍</span> {isCheckingUpdate ? "Đang kiểm tra..." : "Kiểm Tra Bản Mới"}
            </button>
            <button
              type="button"
              onClick={() => window.open("https://github.com/lecuong2512/vcrt", "_blank")}
              className="touch-btn py-2 px-3 rounded-xl flex items-center justify-center gap-1"
              style={{ background: "transparent", color: "var(--text-muted)", fontSize: 12, border: "1px solid var(--border-color)" }}
            >
              <span>🔗</span> GitHub
            </button>
          </div>

          <label className="flex items-center justify-between p-2.5 rounded-xl cursor-pointer select-none" style={{ background: "var(--bg-canvas)", border: "1px solid var(--border-color)" }}>
            <div className="flex flex-col">
              <span style={{ fontSize: 12, fontWeight: 600, color: "#E2E8F0" }}>Tự Động Cập Nhật 24/7</span>
              <span style={{ fontSize: 10, color: "var(--text-subtle)" }}>Tự động nâng cấp khi phát hiện bản mới trên GitHub</span>
            </div>
            <input
              type="checkbox"
              checked={updateStatus?.auto_update ?? false}
              onChange={async (e) => {
                const checked = e.target.checked;
                const res = await setAutoUpdateApi(checked);
                if (res && res.status === "ok") {
                  setUpdateStatus(prev => prev ? { ...prev, auto_update: checked } : null);
                  setUpdateMsg({ text: checked ? "✅ Đã bật chế độ tự động cập nhật 24/7!" : "ℹ️ Đã tắt tự động cập nhật." });
                }
              }}
              style={{ accentColor: "#10B981", width: 18, height: 18 }}
            />
          </label>
        </div>
      </div>

      <div style={{ background: "var(--bg-card)", borderRadius: 16, border: "1px solid var(--border-color)", padding: 16 }}>
        <div style={{ fontSize: 11, color: "var(--text-muted)", marginBottom: 12 }}>BẢO TRÌ & THAO TÁC HỆ THỐNG</div>
        <div className="flex flex-col gap-2">
          <button
            onClick={handleCleanRam}
            className="touch-btn w-full py-[12px] rounded-xl flex items-center justify-center gap-2"
            style={{ background: "#222F46", color: "#10B981", fontSize: 13, fontWeight: 600, border: "1px solid #10B981" }}
          >
            <span>🧹</span> Giải Phóng Bộ Nhớ RAM Ngay
          </button>
          <button
            onClick={() => window.open("/cgi-bin/luci/admin/system/backup", "_blank")}
            className="touch-btn w-full py-[12px] rounded-xl flex items-center justify-center gap-2"
            style={{ background: "#222F46", color: "var(--text-primary)", fontSize: 13, fontWeight: 600, border: "none" }}
          >
            <span>💾</span> Tải File Sao Lưu Cấu Hình (.tar.gz)
          </button>
          <button
            onClick={handleReboot}
            className="touch-btn w-full py-[12px] rounded-xl flex items-center justify-center gap-2"
            style={{ background: "transparent", color: "#F59E0B", fontSize: 13, fontWeight: 600, border: "1px solid #F59E0B" }}
          >
            <span>🔄</span> Khởi Động Lại Router
          </button>
        </div>
      </div>

      <div style={{ textAlign: "center", padding: "12px 0 4px 0" }} className="flex flex-col items-center gap-1.5">
        <VCRTLogo size={32} showText={true} />
        <div style={{ fontSize: 10, color: "#475569", marginTop: 2 }} className="mono">Xiaomi MiWiFi Mini · MediaTek MT7620A · 128MB RAM</div>
      </div>
    </div>
  );
}

// ─── Root App & Shell with Theme Context ───────────────────────────────────────
function AppContent() {
  const { theme, toggleTheme, isDark } = useTheme();
  const [tab, setTab] = useState<Tab>("dashboard");
  const [isAuthenticated, setIsAuthenticated] = useState<boolean>(false);
  const [authLoading, setAuthLoading] = useState<boolean>(true);
  const [currentUser, setCurrentUser] = useState<string>("admin");

  useEffect(() => {
    const token = localStorage.getItem("vcrt_token") || sessionStorage.getItem("vcrt_token");
    if (!token) {
      setIsAuthenticated(false);
      setAuthLoading(false);
      return;
    }
    checkAuthApi(token)
      .then((res) => {
        if (res && res.authenticated) {
          setIsAuthenticated(true);
          setCurrentUser(res.user || localStorage.getItem("vcrt_user") || "admin");
        } else {
          setIsAuthenticated(false);
          localStorage.removeItem("vcrt_token");
          sessionStorage.removeItem("vcrt_token");
        }
      })
      .catch(() => {
        setIsAuthenticated(false);
      })
      .finally(() => {
        setAuthLoading(false);
      });
  }, []);

  const handleLogout = async () => {
    const token = localStorage.getItem("vcrt_token") || sessionStorage.getItem("vcrt_token") || "";
    if (token) {
      await logoutApi(token);
    }
    localStorage.removeItem("vcrt_token");
    localStorage.removeItem("vcrt_user");
    sessionStorage.removeItem("vcrt_token");
    sessionStorage.removeItem("vcrt_user");
    setIsAuthenticated(false);
  };

  if (authLoading) {
    return (
      <div
        style={{
          width: "100%",
          height: "100vh",
          background: "var(--bg-canvas)",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          gap: 14
        }}
      >
        <span className="pulse-dot" style={{ width: 28, height: 28, borderRadius: "50%", background: "#38BDF8" }} />
        <div style={{ color: "var(--text-muted)", fontSize: 13, fontFamily: "JetBrains Mono, monospace", fontWeight: 600 }}>
          Đang kết nối hệ thống VCRT OS...
        </div>
      </div>
    );
  }

  if (!isAuthenticated) {
    return (
      <LoginScreen
        onLoginSuccess={(u, tok) => {
          setIsAuthenticated(true);
          setCurrentUser(u);
        }}
      />
    );
  }

  const screens: Record<Tab, React.ReactNode> = {
    dashboard: <DashboardScreen />,
    clients: <ClientsScreen />,
    wifi: <WiFiScreen />,
    nextdns: <NextDNSScreen />,
    settings: <SettingsScreen onLogout={handleLogout} currentUser={currentUser} />,
  };

  return (
    <div
      style={{
        width: "100%",
        height: "100%",
        background: "var(--bg-canvas)",
        color: "var(--text-primary)",
        display: "flex",
        flexDirection: "column",
        overflow: "hidden",
        position: "relative",
        transition: "background-color 0.3s ease, color 0.3s ease"
      }}
    >
      {/* Top Header Bar with Glassmorphism, Theme Switcher & User Status */}
      <header
        style={{
          background: "var(--bg-header)",
          borderBottom: "1px solid var(--border-color)",
          padding: "10px 16px",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          zIndex: 40,
          flexShrink: 0,
          backdropFilter: "blur(14px)",
          WebkitBackdropFilter: "blur(14px)",
          boxShadow: "0 2px 10px rgba(0, 0, 0, 0.04)"
        }}
      >
        <div className="flex items-center gap-2">
          <VCRTLogo size={30} showText={true} />
        </div>

        <div className="flex items-center gap-2.5">
          {/* THEME TOGGLE BUTTON (LIGHT / DARK) */}
          <button
            type="button"
            onClick={toggleTheme}
            className="touch-btn"
            style={{
              width: 32,
              height: 32,
              borderRadius: "50%",
              background: "var(--bg-card-subtle)",
              border: "1px solid var(--border-color)",
              color: "var(--text-primary)",
              cursor: "pointer",
              fontSize: 15,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              boxShadow: "0 2px 6px rgba(0, 0, 0, 0.05)"
            }}
            title={isDark ? "Chuyển sang Giao diện Sáng (Light)" : "Chuyển sang Giao diện Tối (Dark)"}
          >
            {isDark ? "☀️" : "🌙"}
          </button>

          <span
            style={{
              fontSize: 11,
              color: "var(--badge-text)",
              background: "var(--badge-bg)",
              border: "1px solid var(--border-color)",
              padding: "3px 8px",
              borderRadius: 6,
              fontWeight: 700
            }}
          >
            👤 {currentUser}
          </span>
          <button
            onClick={handleLogout}
            className="touch-btn"
            style={{
              background: "transparent",
              border: "1px solid var(--border-color)",
              color: "#EF4444",
              borderRadius: 6,
              padding: "4px 8px",
              fontSize: 11,
              fontWeight: 700,
              cursor: "pointer",
              display: "flex",
              alignItems: "center",
              gap: 4
            }}
            title="Đăng xuất khỏi router"
          >
            <span>🚪</span> Đăng xuất
          </button>
        </div>
      </header>

      <div
        style={{
          flex: 1,
          overflowY: "auto",
          overflowX: "hidden",
          WebkitOverflowScrolling: "touch",
          scrollbarWidth: "thin",
        }}
      >
        {screens[tab]}
      </div>
      <BottomNav active={tab} onSelect={setTab} />
    </div>
  );
}

export default function App() {
  return (
    <ThemeProvider>
      <AppContent />
    </ThemeProvider>
  );
}
