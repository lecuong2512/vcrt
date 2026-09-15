import { useState } from 'react';

interface WifiCardProps {
  bandTitle: string;
  bandBadge: string;
  badgeColor?: string;
  chipInfo: string;
  ssid: string;
  onSsidChange: (val: string) => void;
  pass: string;
  onPassChange: (val: string) => void;
  channel: string;
  onChannelChange: (val: string) => void;
  channels: { val: string; label: string }[];
  power: string;
  onPowerChange: (val: string) => void;
}

export function WifiCard({
  bandTitle,
  bandBadge,
  chipInfo,
  ssid,
  onSsidChange,
  pass,
  onPassChange,
  channel,
  onChannelChange,
  channels,
  power,
  onPowerChange
}: WifiCardProps) {
  const [showPassword, setShowPassword] = useState(false);

  return (
    <div className="vcrt-card p-4 flex flex-col gap-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span className="vcrt-badge bg-blue-100 dark:bg-blue-950/60 text-blue-700 dark:text-blue-300 border border-blue-200 dark:border-blue-800">
            {bandBadge}
          </span>
          <span className="font-bold text-sm text-slate-900 dark:text-slate-100">{bandTitle}</span>
        </div>
        <span className="text-[11px] text-slate-400 font-mono">{chipInfo}</span>
      </div>

      {/* Form Fields */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        {/* SSID */}
        <div>
          <label className="block text-xs font-semibold text-slate-600 dark:text-slate-400 mb-1">
            Tên mạng Wi-Fi (SSID)
          </label>
          <input
            type="text"
            className="vcrt-input"
            value={ssid}
            onChange={(e) => onSsidChange(e.target.value)}
            placeholder="vd: Xiaomi_Mini_5G"
          />
        </div>

        {/* Password */}
        <div>
          <label className="block text-xs font-semibold text-slate-600 dark:text-slate-400 mb-1">
            Mật khẩu Wi-Fi (WPA2-PSK)
          </label>
          <div className="relative">
            <input
              type={showPassword ? 'text' : 'password'}
              className="vcrt-input pr-10"
              value={pass}
              onChange={(e) => onPassChange(e.target.value)}
              placeholder="Tối thiểu 8 ký tự..."
            />
            <button
              type="button"
              onClick={() => setShowPassword(!showPassword)}
              className="absolute right-2.5 top-1/2 -translate-y-1/2 text-sm text-slate-400 hover:text-slate-600 dark:hover:text-slate-200"
              title={showPassword ? 'Ẩn mật khẩu' : 'Hiện mật khẩu'}
            >
              {showPassword ? '🙈' : '👁️'}
            </button>
          </div>
        </div>

        {/* Channel */}
        <div>
          <label className="block text-xs font-semibold text-slate-600 dark:text-slate-400 mb-1">
            Kênh phát sóng (Channel)
          </label>
          <select
            className="vcrt-input"
            value={channel}
            onChange={(e) => onChannelChange(e.target.value)}
          >
            {channels.map((ch) => (
              <option key={ch.val} value={ch.val}>
                {ch.label}
              </option>
            ))}
          </select>
        </div>

        {/* TX Power */}
        <div>
          <label className="block text-xs font-semibold text-slate-600 dark:text-slate-400 mb-1">
            Công suất phát (TX Power)
          </label>
          <select
            className="vcrt-input"
            value={power}
            onChange={(e) => onPowerChange(e.target.value)}
          >
            <option value="20">100% (20 dBm - 100 mW - Mặc định)</option>
            <option value="17">75% (17 dBm - 50 mW - Tiết kiệm điện)</option>
            <option value="14">50% (14 dBm - 25 mW - Tầm gần)</option>
            <option value="10">25% (10 dBm - 10 mW - Phòng ngủ)</option>
          </select>
        </div>
      </div>
    </div>
  );
}
