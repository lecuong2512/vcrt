import { useState, useCallback } from 'react';
import { usePolling } from '../hooks/usePolling';
import {
  getSystemStatus,
  cleanRam,
  rebootRouter,
  resetPeakBw,
  SystemStatus,
  TrafficHistoryItem
} from '../api/system';
import { TrafficChart } from '../components/TrafficChart';
import { useToast } from '../components/Toast';

export default function DashboardScreen() {
  const { success, error, info } = useToast();

  const [status, setStatus] = useState<SystemStatus | null>(null);
  const [isOnline, setIsOnline] = useState<boolean>(true);
  const [trafficPeriod, setTrafficPeriod] = useState<'today' | '7d' | 'month' | 'quarter' | 'year'>('today');

  // Realtime Bandwidth Stream for Chart (15 latest samples)
  const [dlHistory, setDlHistory] = useState<number[]>([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
  const [ulHistory, setUlHistory] = useState<number[]>([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);

  const fetchStatus = useCallback(async () => {
    try {
      const data = await getSystemStatus();
      if (data) {
        setStatus(data);
        setIsOnline(true);

        const currentDl = data.dl_mbps ?? 0;
        const currentUl = data.ul_mbps ?? 0;

        setDlHistory((prev) => [...prev.slice(1), currentDl]);
        setUlHistory((prev) => [...prev.slice(1), currentUl]);
      } else {
        setIsOnline(false);
      }
    } catch {
      setIsOnline(false);
    }
  }, []);

  // Polling mỗi 2.5s khi tab active
  usePolling(fetchStatus, 2500, true);

  const handleResetPeak = async () => {
    try {
      await resetPeakBw();
      success('Đã đặt lại mốc băng thông đỉnh!');
      if (status) {
        setStatus({
          ...status,
          peak_bandwidth: { dl_mbps: status.dl_mbps, ul_mbps: status.ul_mbps }
        });
      }
    } catch (e: any) {
      error(e?.message || 'Lỗi đặt lại băng thông đỉnh');
    }
  };

  const handleCleanRam = async () => {
    try {
      const res = await cleanRam();
      if (res && res.mem_avail !== undefined) {
        success(`Giải phóng RAM thành công! Bộ nhớ trống: ${res.mem_avail} MB`);
      } else {
        info('Đã gửi lệnh giải phóng bộ nhớ RAM!');
      }
      fetchStatus();
    } catch (e: any) {
      error(e?.message || 'Lỗi giải phóng RAM');
    }
  };

  const handleReboot = async () => {
    if (!window.confirm('Bạn có chắc chắn muốn khởi động lại router?')) return;
    try {
      await rebootRouter();
      info('Router đang khởi động lại. Vui lòng đợi 30-60 giây để kết nối lại...');
    } catch (e: any) {
      error(e?.message || 'Lỗi khởi động lại');
    }
  };

  // Convert real-time history to chart items
  const realtimeChartItems = dlHistory.map((dl, i) => ({
    label: `${(15 - i) * 2.5}s`,
    dl,
    ul: ulHistory[i] || 0
  }));

  // Chuẩn bị dữ liệu lịch sử lưu lượng theo tab chu kỳ
  const periodStats: TrafficHistoryItem[] =
    status?.traffic_stats?.[trafficPeriod] || [
      { label: '00:00', dl: 0, ul: 0 },
      { label: '06:00', dl: 0, ul: 0 },
      { label: '12:00', dl: 0, ul: 0 },
      { label: '18:00', dl: 0, ul: 0 },
      { label: '23:59', dl: 0, ul: 0 }
    ];

  // Tính phần trăm RAM
  const ramTotal = status?.ram_total || 128;
  const ramUsed = status?.ram_used || 0;
  const ramPct = Math.min(100, Math.round((ramUsed / (ramTotal || 1)) * 100));

  // Overlay Flash
  const flashUsedPct = status?.flash?.overlay_pct ?? status?.flash?.used_pct ?? 45;
  const flashTotal = status?.flash?.overlay_total_mb ?? status?.flash?.total_mb ?? 16;
  const flashUsed = status?.flash?.overlay_used_mb ?? status?.flash?.used_mb ?? 7;

  return (
    <div className="flex flex-col gap-4">
      {/* Header Info */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 bg-white dark:bg-slate-800 p-4 rounded-2xl border border-slate-200 dark:border-slate-700/80 shadow-xs">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-blue-50 dark:bg-blue-950/60 border border-blue-200 dark:border-blue-900 flex items-center justify-center text-xl shrink-0">
            ⚡
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h2 className="font-extrabold text-base text-slate-900 dark:text-slate-100">
                {status?.device_name || 'Xiaomi MiWiFi Mini'}
              </h2>
              <span
                className={`pulse-dot w-2.5 h-2.5 rounded-full ${
                  isOnline ? 'bg-emerald-500' : 'bg-rose-500'
                }`}
                title={isOnline ? 'Trực tuyến' : 'Mất kết nối'}
              />
            </div>
            <p className="text-xs text-slate-500 dark:text-slate-400 font-mono mt-0.5">
              {status?.os_version || 'OpenWrt 25.12'} (Linux {status?.kernel_version || '6.12'}) • Uptime:{' '}
              {status?.uptime || 'Đang nạp...'}
            </p>
          </div>
        </div>

        {/* Quick Actions */}
        <div className="flex items-center gap-2">
          <button
            onClick={handleCleanRam}
            className="vcrt-btn vcrt-btn-secondary text-xs py-1.5 px-3"
            title="Giải phóng cache và bộ nhớ RAM"
          >
            <span>🧹</span>
            <span>Dọn RAM</span>
          </button>
          <button
            onClick={handleReboot}
            className="vcrt-btn text-xs py-1.5 px-3 text-amber-600 dark:text-amber-400 border border-amber-300 dark:border-amber-800 hover:bg-amber-50 dark:hover:bg-amber-950/50"
            title="Khởi động lại router"
          >
            <span>🔄</span>
            <span>Khởi động lại</span>
          </button>
        </div>
      </div>

      {/* Gauges Metric Cards (CPU, RAM, Flash, IP/Temp) */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        {/* CPU */}
        <div className="vcrt-card p-4 flex flex-col justify-between">
          <div className="flex items-center justify-between text-xs text-slate-500 dark:text-slate-400 font-semibold">
            <span>CPU Tải</span>
            <span>MT7620A</span>
          </div>
          <div className="my-2">
            <div className="text-2xl font-black font-mono text-slate-900 dark:text-slate-100">
              {status?.cpu ?? 0}%
            </div>
            {status?.cpu_temp !== undefined && (
              <span className="text-[11px] text-amber-500 font-semibold">
                🌡️ {status.cpu_temp}°C
              </span>
            )}
          </div>
          <div className="w-full h-1.5 bg-slate-100 dark:bg-slate-700 rounded-full overflow-hidden">
            <div
              className={`h-full transition-all duration-500 rounded-full ${
                (status?.cpu ?? 0) > 80
                  ? 'bg-rose-500'
                  : (status?.cpu ?? 0) > 50
                  ? 'bg-amber-500'
                  : 'bg-blue-500'
              }`}
              style={{ width: `${Math.min(100, status?.cpu ?? 0)}%` }}
            />
          </div>
        </div>

        {/* RAM */}
        <div className="vcrt-card p-4 flex flex-col justify-between">
          <div className="flex items-center justify-between text-xs text-slate-500 dark:text-slate-400 font-semibold">
            <span>Bộ nhớ RAM</span>
            <span>{ramPct}%</span>
          </div>
          <div className="my-2">
            <div className="text-2xl font-black font-mono text-slate-900 dark:text-slate-100">
              {ramUsed} <span className="text-sm font-normal text-slate-400">/ {ramTotal}MB</span>
            </div>
            <span className="text-[11px] text-emerald-500 font-semibold">
              Trống: {status?.ram_avail ?? 0} MB
            </span>
          </div>
          <div className="w-full h-1.5 bg-slate-100 dark:bg-slate-700 rounded-full overflow-hidden">
            <div
              className={`h-full transition-all duration-500 rounded-full ${
                ramPct > 85 ? 'bg-rose-500' : ramPct > 65 ? 'bg-amber-500' : 'bg-emerald-500'
              }`}
              style={{ width: `${ramPct}%` }}
            />
          </div>
        </div>

        {/* Flash Overlay */}
        <div className="vcrt-card p-4 flex flex-col justify-between">
          <div className="flex items-center justify-between text-xs text-slate-500 dark:text-slate-400 font-semibold">
            <span>Bộ nhớ Flash</span>
            <span>{flashUsedPct}%</span>
          </div>
          <div className="my-2">
            <div className="text-2xl font-black font-mono text-slate-900 dark:text-slate-100">
              {flashUsed.toFixed(1)}{' '}
              <span className="text-sm font-normal text-slate-400">/ {flashTotal.toFixed(1)}MB</span>
            </div>
            <span className="text-[11px] text-slate-400">
              Overlay ROM
            </span>
          </div>
          <div className="w-full h-1.5 bg-slate-100 dark:bg-slate-700 rounded-full overflow-hidden">
            <div
              className="h-full bg-indigo-500 transition-all duration-500 rounded-full"
              style={{ width: `${flashUsedPct}%` }}
            />
          </div>
        </div>

        {/* WAN IP & NextDNS status */}
        <div className="vcrt-card p-4 flex flex-col justify-between">
          <div className="flex items-center justify-between text-xs text-slate-500 dark:text-slate-400 font-semibold">
            <span>Địa chỉ WAN IP</span>
            <span
              className={`w-2 h-2 rounded-full ${
                status?.wan_ip && status.wan_ip !== '0.0.0.0' ? 'bg-emerald-500' : 'bg-slate-400'
              }`}
            />
          </div>
          <div className="my-2">
            <div className="text-base font-bold font-mono text-slate-900 dark:text-slate-100 truncate" title={status?.wan_ip}>
              {status?.wan_ip || 'Chưa nhận IP'}
            </div>
            <div className="flex items-center gap-1.5 text-[11px] mt-0.5">
              <span className="text-slate-400">NextDNS:</span>
              <span
                className={`font-semibold ${
                  status?.nextdns?.active ? 'text-emerald-500' : 'text-slate-400'
                }`}
              >
                {status?.nextdns?.active ? 'Bảo vệ hoạt động' : 'Tắt'}
              </span>
            </div>
          </div>
          <div className="text-[10px] text-slate-400 truncate">
            {status?.nextdns?.node ? `Node: ${status.nextdns.node}` : 'Cổng mạng Internet sẵn sàng'}
          </div>
        </div>
      </div>

      {/* Real-time Bandwidth Monitor Card */}
      <div className="vcrt-card p-4 sm:p-5 flex flex-col gap-3">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
          <div>
            <h3 className="font-bold text-sm text-slate-900 dark:text-slate-100 flex items-center gap-2">
              <span>📶</span> Băng Thông Thời Gian Thực (Real-time)
            </h3>
            <p className="text-xs text-slate-400 mt-0.5">
              Tốc độ mạng cập nhật mỗi 2.5 giây từ giao diện mạng router
            </p>
          </div>

          <div className="flex items-center gap-3">
            {/* Download stat */}
            <div className="flex flex-col items-end">
              <span className="text-[10px] text-slate-400 font-semibold">TẢI VỀ (DL)</span>
              <span className="text-lg font-black font-mono text-blue-600 dark:text-blue-400">
                {(status?.dl_mbps ?? 0).toFixed(2)}{' '}
                <span className="text-xs font-normal text-slate-500">MB/s</span>
              </span>
            </div>
            <div className="h-7 w-px bg-slate-200 dark:bg-slate-700" />
            {/* Upload stat */}
            <div className="flex flex-col items-end">
              <span className="text-[10px] text-slate-400 font-semibold">TẢI LÊN (UL)</span>
              <span className="text-lg font-black font-mono text-emerald-600 dark:text-emerald-400">
                {(status?.ul_mbps ?? 0).toFixed(2)}{' '}
                <span className="text-xs font-normal text-slate-500">MB/s</span>
              </span>
            </div>
          </div>
        </div>

        {/* Canvas Chart */}
        <TrafficChart items={realtimeChartItems} unit="MB/s" height={150} />

        {/* Peak Bandwidth & Reset Button */}
        <div className="flex items-center justify-between pt-2 border-t border-slate-100 dark:border-slate-800 text-xs">
          <div className="flex items-center gap-2 text-slate-500 dark:text-slate-400">
            <span>🚀 Đỉnh cao nhất:</span>
            <span className="font-mono font-bold text-slate-700 dark:text-slate-200">
              ↓{(status?.peak_bandwidth?.dl_mbps ?? 0).toFixed(2)} MB/s • ↑
              {(status?.peak_bandwidth?.ul_mbps ?? 0).toFixed(2)} MB/s
            </span>
          </div>
          <button
            onClick={handleResetPeak}
            className="text-blue-600 dark:text-blue-400 hover:underline font-semibold text-[11px]"
          >
            Đặt lại đỉnh
          </button>
        </div>
      </div>

      {/* Uplink Info & Physical Ports */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        {/* Uplink Source Card */}
        <div className="vcrt-card p-4 flex flex-col gap-3">
          <div className="flex items-center justify-between">
            <h3 className="font-bold text-sm text-slate-900 dark:text-slate-100 flex items-center gap-2">
              <span>🌐</span> Nguồn Mạng Đầu Vào (Uplink)
            </h3>
            <span className="vcrt-badge bg-blue-100 dark:bg-blue-950/60 text-blue-700 dark:text-blue-300 border border-blue-200 dark:border-blue-800">
              {status?.uplink?.type === 'repeater' ? 'WISP REPEATER' : status?.uplink?.type || 'ETHERNET WAN'}
            </span>
          </div>

          <div className="p-3 rounded-xl bg-slate-50 dark:bg-slate-800/50 border border-slate-200/80 dark:border-slate-700/60 flex flex-col gap-1.5 text-xs">
            <div className="font-semibold text-slate-800 dark:text-slate-200">
              {status?.uplink?.title || 'Kích sóng Wi-Fi Không Dây (WISP Repeater)'}
            </div>
            {status?.uplink?.ssid && (
              <div className="flex items-center justify-between text-slate-500 dark:text-slate-400">
                <span>Tên mạng gốc:</span>
                <span className="font-bold text-slate-700 dark:text-slate-200 font-mono">
                  {status.uplink.ssid}
                </span>
              </div>
            )}
            {status?.uplink?.bssid && (
              <div className="flex items-center justify-between text-slate-500 dark:text-slate-400">
                <span>BSSID / MAC:</span>
                <span className="font-mono uppercase">{status.uplink.bssid}</span>
              </div>
            )}
            {status?.uplink?.channel && (
              <div className="flex items-center justify-between text-slate-500 dark:text-slate-400">
                <span>Kênh / Băng tần:</span>
                <span className="font-mono">
                  CH {status.uplink.channel} ({status.uplink.band || '5GHz'})
                </span>
              </div>
            )}
            {status?.uplink?.gateway && (
              <div className="flex items-center justify-between text-slate-500 dark:text-slate-400">
                <span>Gateway mặc định:</span>
                <span className="font-mono">{status.uplink.gateway}</span>
              </div>
            )}
          </div>
        </div>

        {/* Switch Physical Ports Card */}
        <div className="vcrt-card p-4 flex flex-col gap-3">
          <h3 className="font-bold text-sm text-slate-900 dark:text-slate-100 flex items-center gap-2">
            <span>🔌</span> Trạng Thái Cổng Phần Cứng
          </h3>

          <div className="grid grid-cols-2 gap-2 text-xs">
            {/* WAN Port */}
            <div className="p-3 rounded-xl bg-slate-50 dark:bg-slate-800/50 border border-slate-200/80 dark:border-slate-700/60 flex flex-col gap-1">
              <div className="flex items-center justify-between">
                <span className="font-semibold text-slate-700 dark:text-slate-300">Cổng WAN</span>
                <span
                  className={`w-2 h-2 rounded-full ${
                    status?.ports?.wan?.up ? 'bg-emerald-500' : 'bg-slate-400'
                  }`}
                />
              </div>
              <span className="text-[11px] text-slate-500 dark:text-slate-400">
                {status?.ports?.wan?.speed || 'Chưa cắm cáp'}
              </span>
            </div>

            {/* LAN 1 */}
            <div className="p-3 rounded-xl bg-slate-50 dark:bg-slate-800/50 border border-slate-200/80 dark:border-slate-700/60 flex flex-col gap-1">
              <div className="flex items-center justify-between">
                <span className="font-semibold text-slate-700 dark:text-slate-300">Cổng LAN 1</span>
                <span
                  className={`w-2 h-2 rounded-full ${
                    status?.ports?.lan1?.up ? 'bg-emerald-500' : 'bg-slate-400'
                  }`}
                />
              </div>
              <span className="text-[11px] text-slate-500 dark:text-slate-400">
                {status?.ports?.lan1?.speed || 'Chưa cắm cáp'}
              </span>
            </div>

            {/* LAN 2 */}
            <div className="p-3 rounded-xl bg-slate-50 dark:bg-slate-800/50 border border-slate-200/80 dark:border-slate-700/60 flex flex-col gap-1">
              <div className="flex items-center justify-between">
                <span className="font-semibold text-slate-700 dark:text-slate-300">Cổng LAN 2</span>
                <span
                  className={`w-2 h-2 rounded-full ${
                    status?.ports?.lan2?.up ? 'bg-emerald-500' : 'bg-slate-400'
                  }`}
                />
              </div>
              <span className="text-[11px] text-slate-500 dark:text-slate-400">
                {status?.ports?.lan2?.speed || 'Chưa cắm cáp'}
              </span>
            </div>

            {/* USB Port */}
            <div className="p-3 rounded-xl bg-slate-50 dark:bg-slate-800/50 border border-slate-200/80 dark:border-slate-700/60 flex flex-col gap-1">
              <div className="flex items-center justify-between">
                <span className="font-semibold text-slate-700 dark:text-slate-300">Cổng USB 2.0</span>
                <span
                  className={`w-2 h-2 rounded-full ${
                    status?.ports?.usb?.connected ? 'bg-emerald-500' : 'bg-slate-400'
                  }`}
                />
              </div>
              <span className="text-[11px] text-slate-500 dark:text-slate-400 truncate">
                {status?.ports?.usb?.connected
                  ? status.ports.usb.name || 'Đã cắm thiết bị'
                  : 'Chưa cắm thiết bị'}
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Traffic Statistics Multi-Period Chart Card */}
      <div className="vcrt-card p-4 sm:p-5 flex flex-col gap-3">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
          <div>
            <h3 className="font-bold text-sm text-slate-900 dark:text-slate-100 flex items-center gap-2">
              <span>📊</span> Lịch Sử Lưu Lượng Mạng Đa Chu Kỳ
            </h3>
            <p className="text-xs text-slate-400 mt-0.5">
              Thống kê tổng dung lượng tải về & tải lên theo từng mốc thời gian
            </p>
          </div>

          {/* Period tabs */}
          <div className="flex items-center gap-1 bg-slate-100 dark:bg-slate-700/60 p-1 rounded-xl border border-slate-200 dark:border-slate-700 self-start sm:self-auto">
            {(['today', '7d', 'month', 'quarter', 'year'] as const).map((p) => {
              const labels: Record<string, string> = {
                today: 'Hôm nay',
                '7d': '7 ngày',
                month: 'Tháng',
                quarter: 'Quý',
                year: 'Năm'
              };
              const isSelected = trafficPeriod === p;
              return (
                <button
                  key={p}
                  onClick={() => setTrafficPeriod(p)}
                  className={`px-2.5 py-1 rounded-lg text-xs font-semibold transition-all ${
                    isSelected
                      ? 'bg-white dark:bg-slate-800 text-blue-600 dark:text-blue-400 shadow-xs'
                      : 'text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-200'
                  }`}
                >
                  {labels[p]}
                </button>
              );
            })}
          </div>
        </div>

        {/* Period Chart */}
        <TrafficChart items={periodStats} unit="GB" height={160} />
      </div>
    </div>
  );
}
