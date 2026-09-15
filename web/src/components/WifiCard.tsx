import { useState } from 'react';

const DEFAULT_POWER_OPTIONS = [
  { val: '24', label: '24 dBm (250 mW - Tối đa)' },
  { val: '23', label: '23 dBm (200 mW - Rất mạnh)' },
  { val: '20', label: '20 dBm (100 mW - Tiêu chuẩn)' },
  { val: '17', label: '17 dBm (50 mW - Vừa phải)' },
  { val: '14', label: '14 dBm (25 mW - Tiết kiệm)' },
  { val: '10', label: '10 dBm (10 mW - Phòng ngủ)' },
];

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
  realChannel?: string;
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
  onPowerChange,
  realChannel
}: WifiCardProps) {
  const [showPassword, setShowPassword] = useState(false);

  // Kiem tra gia tri power hien tai cua router co trong danh sach khong
  const isCustomPower = Boolean(
    power && !DEFAULT_POWER_OPTIONS.some((opt) => opt.val === String(power))
  );

  // Kiem tra channel hien tai co trong danh sach options khong
  const isCustomChannel = Boolean(
    channel && !channels.some((c) => c.val === String(channel))
  );

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
          <div className="flex items-center justify-between mb-1">
            <label className="text-xs font-semibold text-slate-600 dark:text-slate-400">
              Kênh phát sóng (Channel)
            </label>
            {channel === 'auto' && realChannel && (
              <span className="text-[11px] font-medium text-emerald-600 dark:text-emerald-400">
                (Đang phát: Kênh {realChannel})
              </span>
            )}
          </div>
          <select
            className="vcrt-input"
            value={channel}
            onChange={(e) => onChannelChange(e.target.value)}
          >
            {isCustomChannel && (
              <option value={channel}>
                Kênh {channel} (Hiện tại router)
              </option>
            )}
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
            {isCustomPower && (
              <option value={power}>
                {power} dBm (Hiện tại router)
              </option>
            )}
            {DEFAULT_POWER_OPTIONS.map((opt) => (
              <option key={opt.val} value={opt.val}>
                {opt.label}
              </option>
            ))}
          </select>
        </div>
      </div>
    </div>
  );
}

