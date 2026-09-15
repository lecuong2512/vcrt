import { ClientDevice } from '../api/clients';
import { SignalBars } from './SignalBars';

interface DeviceCardProps {
  device: ClientDevice;
  onSoftBlock: (device: ClientDevice) => void;
  onHardBlock: (device: ClientDevice) => void;
  onUnblock: (device: ClientDevice) => void;
}

export function DeviceCard({
  device,
  onSoftBlock,
  onHardBlock,
  onUnblock
}: DeviceCardProps) {
  const isBlocked = device.blocked || device.softBlocked;

  const formatRemain = (sec?: number, dur?: number) => {
    if (!dur || dur === 0) return 'Vĩnh viễn';
    if (!sec || sec <= 0) return 'Hết hạn';
    const h = Math.floor(sec / 3600);
    const m = Math.floor((sec % 3600) / 60);
    const s = sec % 60;
    if (h > 0) return `${h}h ${m}m ${s}s`;
    if (m > 0) return `${m}m ${s}s`;
    return `${s}s`;
  };

  const getDeviceIcon = (name: string = '', icon?: string) => {
    if (icon) return icon;
    const lower = name.toLowerCase();
    if (lower.includes('iphone') || lower.includes('galaxy') || lower.includes('phone') || lower.includes('redmi') || lower.includes('xiaomi')) {
      return '📱';
    }
    if (lower.includes('macbook') || lower.includes('laptop') || lower.includes('pc') || lower.includes('desktop')) {
      return '💻';
    }
    if (lower.includes('ipad') || lower.includes('tablet')) {
      return '📟';
    }
    if (lower.includes('tv') || lower.includes('box') || lower.includes('cast')) {
      return '📺';
    }
    return '📶';
  };

  return (
    <div className="vcrt-card p-4 flex flex-col gap-3 hover:border-slate-300 dark:hover:border-slate-600 transition-all">
      <div className="flex items-start justify-between gap-3">
        <div className="flex items-center gap-3 min-w-0">
          <div className="w-10 h-10 rounded-xl bg-blue-50 dark:bg-slate-700/60 border border-blue-100 dark:border-slate-600 flex items-center justify-center text-xl shrink-0">
            {getDeviceIcon(device.name, device.icon)}
          </div>
          <div className="min-w-0">
            <div className="flex items-center gap-2">
              <span className="font-bold text-sm text-slate-900 dark:text-slate-100 truncate">
                {device.name || 'Thiết bị không tên'}
              </span>
              {device.band && (
                <span
                  className={`text-[10px] font-bold px-1.5 py-0.5 rounded ${
                    device.band.includes('5')
                      ? 'bg-purple-100 dark:bg-purple-950/60 text-purple-700 dark:text-purple-300 border border-purple-200 dark:border-purple-800'
                      : 'bg-amber-100 dark:bg-amber-950/60 text-amber-700 dark:text-amber-300 border border-amber-200 dark:border-amber-800'
                  }`}
                >
                  {device.band}
                </span>
              )}
            </div>
            <div className="flex items-center gap-2 text-xs text-slate-500 dark:text-slate-400 font-mono mt-0.5">
              <span>{device.ip || '---'}</span>
              <span>•</span>
              <span className="uppercase">{device.mac}</span>
            </div>
          </div>
        </div>

        {/* Signal & Bitrate */}
        {!isBlocked && (
          <div className="flex flex-col items-end gap-1 shrink-0">
            <div className="flex items-center gap-1.5">
              <SignalBars rssi={device.rssi || -70} />
              <span className="text-[11px] font-mono text-slate-500 dark:text-slate-400">
                {device.rssi ? `${device.rssi} dBm` : ''}
              </span>
            </div>
            {(device.rxMbps || device.txMbps) && (
              <span className="text-[10px] text-slate-400">
                ↓{device.rxMbps || 0} ↑{device.txMbps || 0} Mbps
              </span>
            )}
          </div>
        )}
      </div>

      {/* Blocked info status */}
      {isBlocked && (
        <div className="p-2.5 rounded-lg bg-rose-50 dark:bg-rose-950/40 border border-rose-200 dark:border-rose-900 flex items-center justify-between text-xs">
          <div className="flex items-center gap-1.5 text-rose-700 dark:text-rose-300 font-medium">
            <span>⛔</span>
            <span>{device.blocked ? 'Đang đá sóng (Hard Block)' : 'Đang cắt mạng (Soft Block)'}</span>
          </div>
          <span className="font-mono text-rose-600 dark:text-rose-400 font-semibold">
            {formatRemain(device.blockRemain, device.blockDuration)}
          </span>
        </div>
      )}

      {/* Action buttons */}
      <div className="flex items-center gap-2 pt-1 border-t border-slate-100 dark:border-slate-700/60">
        {isBlocked ? (
          <button
            onClick={() => onUnblock(device)}
            className="vcrt-btn flex-1 bg-emerald-600 hover:bg-emerald-700 text-white text-xs py-1.5"
          >
            <span>🔓</span> Mở Kết Nối Lại
          </button>
        ) : (
          <>
            <button
              onClick={() => onSoftBlock(device)}
              className="vcrt-btn flex-1 bg-amber-500/10 hover:bg-amber-500/20 text-amber-600 dark:text-amber-400 border border-amber-300 dark:border-amber-800 text-xs py-1.5"
              title="Vẫn nhận sóng Wi-Fi nhưng chặn Internet"
            >
              <span>🚫</span> Cắt Net
            </button>
            <button
              onClick={() => onHardBlock(device)}
              className="vcrt-btn flex-1 bg-rose-500/10 hover:bg-rose-500/20 text-rose-600 dark:text-rose-400 border border-rose-300 dark:border-rose-800 text-xs py-1.5"
              title="Ngắt kết nối sóng Wi-Fi và cấm gia nhập"
            >
              <span>⚡</span> Đá Sóng
            </button>
          </>
        )}
      </div>
    </div>
  );
}
