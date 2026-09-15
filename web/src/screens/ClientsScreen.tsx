import { useState, useEffect, useCallback } from 'react';
import { usePolling } from '../hooks/usePolling';
import {
  getClients,
  softBlockDevice,
  hardBlockDevice,
  unblockDevice,
  ClientDevice
} from '../api/clients';
import { DeviceCard } from '../components/DeviceCard';
import { Modal } from '../components/Modal';
import { useToast } from '../components/Toast';

export default function ClientsScreen() {
  const { success, error, info } = useToast();

  const [clients, setClients] = useState<ClientDevice[]>([]);
  const [filter, setFilter] = useState<'connected' | 'soft' | 'hard'>('connected');
  const [loading, setLoading] = useState(true);

  // Modal chặn hẹn giờ
  const [blockModal, setBlockModal] = useState<{
    device: ClientDevice;
    type: 'soft' | 'hard';
  } | null>(null);
  const [selectedMinutes, setSelectedMinutes] = useState<number>(30);
  const [customMinutes, setCustomMinutes] = useState<string>('');

  const fetchClients = useCallback(async () => {
    try {
      const data = await getClients();
      if (data && data.clients) {
        setClients(data.clients);
      }
    } catch {
      // Ignored
    } finally {
      setLoading(false);
    }
  }, []);

  // Smart polling mỗi 2.5s khi tab active
  usePolling(fetchClients, 2500, true);

  // Countdown timer nội bộ mỗi giây cho các máy đang bị chặn
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
            if (
              (c.blocked || c.softBlocked) &&
              c.blockDuration &&
              c.blockDuration > 0 &&
              c.blockRemain === 0
            ) {
              return false;
            }
            return true;
          })
      );
    }, 1000);
    return () => clearInterval(timer);
  }, []);

  const openBlockModal = (device: ClientDevice, type: 'soft' | 'hard') => {
    setBlockModal({ device, type });
    setSelectedMinutes(30);
    setCustomMinutes('');
  };

  const handleConfirmBlock = async () => {
    if (!blockModal) return;
    const { device, type } = blockModal;

    let mins = selectedMinutes;
    if (customMinutes.trim()) {
      const parsed = parseInt(customMinutes, 10);
      if (!isNaN(parsed) && parsed > 0) mins = parsed;
    }

    try {
      if (type === 'soft') {
        await softBlockDevice(device.mac, mins, device.name, device.ip);
        success(`Đã cắt Internet thiết bị "${device.name || device.mac}" trong ${mins > 0 ? `${mins} phút` : 'vô hạn'}!`);
      } else {
        await hardBlockDevice(device.mac, mins, device.name, device.ip);
        success(`Đã đá sóng Wi-Fi thiết bị "${device.name || device.mac}" trong ${mins > 0 ? `${mins} phút` : 'vô hạn'}!`);
      }

      setBlockModal(null);
      setFilter(type);
      fetchClients();
    } catch (e: any) {
      error(e?.message || 'Lỗi áp dụng lệnh chặn');
    }
  };

  const handleUnblock = async (device: ClientDevice) => {
    try {
      await unblockDevice(device.mac);
      success(`Đã mở kết nối lại cho "${device.name || device.mac}"!`);
      setClients((prev) => prev.filter((c) => c.mac !== device.mac));
      fetchClients();
    } catch (e: any) {
      error(e?.message || 'Lỗi mở mạng');
    }
  };

  // Phân loại danh sách thiết bị
  const connectedList = clients.filter((c) => !c.blocked && !c.softBlocked && c.online !== false);
  const softList = clients.filter((c) => c.softBlocked);
  const hardList = clients.filter((c) => c.blocked);

  const currentList =
    filter === 'connected' ? connectedList : filter === 'soft' ? softList : hardList;

  const presets = [
    { label: '5 phút', mins: 5 },
    { label: '15 phút', mins: 15 },
    { label: '30 phút', mins: 30 },
    { label: '1 giờ', mins: 60 },
    { label: '2 giờ', mins: 120 },
    { label: '24 giờ', mins: 1440 },
    { label: 'Vĩnh viễn', mins: 0 }
  ];

  return (
    <div className="flex flex-col gap-4">
      {/* Header & Tabs */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
        <div>
          <h2 className="text-xl font-extrabold text-slate-900 dark:text-slate-100">
            Quản Lý Thiết Bị ({connectedList.length} trực tuyến)
          </h2>
          <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
            Giám sát thời gian thực các máy kết nối qua 2.4GHz & 5GHz
          </p>
        </div>

        <button
          onClick={fetchClients}
          className="vcrt-btn vcrt-btn-secondary text-xs self-start sm:self-auto"
        >
          <span>🔄</span>
          <span>Làm mới</span>
        </button>
      </div>

      {/* Filter Tabs */}
      <div className="flex items-center gap-1.5 p-1 rounded-xl bg-slate-200/70 dark:bg-slate-800 border border-slate-300 dark:border-slate-700">
        <button
          onClick={() => setFilter('connected')}
          className={`flex-1 py-2 rounded-lg text-xs font-bold transition-all flex items-center justify-center gap-1.5 ${
            filter === 'connected'
              ? 'bg-white dark:bg-slate-700 text-blue-600 dark:text-blue-400 shadow-xs'
              : 'text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-200'
          }`}
        >
          <span>🟢</span>
          <span>Trực Tuyến</span>
          <span className="text-[10px] px-1.5 py-0.2 rounded-full bg-blue-100 dark:bg-blue-950 text-blue-700 dark:text-blue-300 font-mono">
            {connectedList.length}
          </span>
        </button>

        <button
          onClick={() => setFilter('soft')}
          className={`flex-1 py-2 rounded-lg text-xs font-bold transition-all flex items-center justify-center gap-1.5 ${
            filter === 'soft'
              ? 'bg-white dark:bg-slate-700 text-amber-600 dark:text-amber-400 shadow-xs'
              : 'text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-200'
          }`}
        >
          <span>🚫</span>
          <span>Cắt Net</span>
          <span className="text-[10px] px-1.5 py-0.2 rounded-full bg-amber-100 dark:bg-amber-950 text-amber-700 dark:text-amber-300 font-mono">
            {softList.length}
          </span>
        </button>

        <button
          onClick={() => setFilter('hard')}
          className={`flex-1 py-2 rounded-lg text-xs font-bold transition-all flex items-center justify-center gap-1.5 ${
            filter === 'hard'
              ? 'bg-white dark:bg-slate-700 text-rose-600 dark:text-rose-400 shadow-xs'
              : 'text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-200'
          }`}
        >
          <span>⚡</span>
          <span>Đá Sóng</span>
          <span className="text-[10px] px-1.5 py-0.2 rounded-full bg-rose-100 dark:bg-rose-950 text-rose-700 dark:text-rose-300 font-mono">
            {hardList.length}
          </span>
        </button>
      </div>

      {/* Device List Grid */}
      {loading && clients.length === 0 ? (
        <div className="vcrt-card p-12 text-center text-sm text-slate-400 flex flex-col items-center gap-2">
          <span className="text-2xl animate-spin">⏳</span>
          <span>Đang tải danh sách thiết bị từ router...</span>
        </div>
      ) : currentList.length === 0 ? (
        <div className="vcrt-card p-12 text-center text-sm text-slate-400">
          {filter === 'connected'
            ? 'Hiện không có thiết bị nào đang kết nối Wi-Fi.'
            : filter === 'soft'
            ? 'Không có thiết bị nào trong danh sách bị cắt Internet.'
            : 'Không có thiết bị nào bị đá sóng Wi-Fi.'}
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          {currentList.map((device) => (
            <DeviceCard
              key={device.id || device.mac}
              device={device}
              onSoftBlock={(d) => openBlockModal(d, 'soft')}
              onHardBlock={(d) => openBlockModal(d, 'hard')}
              onUnblock={handleUnblock}
            />
          ))}
        </div>
      )}

      {/* Modal Chặn Hẹn Giờ */}
      <Modal
        isOpen={!!blockModal}
        onClose={() => setBlockModal(null)}
        title={
          blockModal?.type === 'soft'
            ? '🚫 Cắt Mạng Internet Có Hẹn Giờ'
            : '⚡ Đá Sóng Wi-Fi Có Hẹn Giờ'
        }
        footer={
          <>
            <button
              onClick={() => setBlockModal(null)}
              className="vcrt-btn vcrt-btn-secondary text-xs"
            >
              Hủy
            </button>
            <button
              onClick={handleConfirmBlock}
              className={`vcrt-btn text-xs text-white ${
                blockModal?.type === 'soft' ? 'bg-amber-600 hover:bg-amber-700' : 'bg-rose-600 hover:bg-rose-700'
              }`}
            >
              Xác Nhận Chặn
            </button>
          </>
        }
      >
        {blockModal && (
          <div className="flex flex-col gap-4 text-xs">
            <div className="p-3 rounded-xl bg-slate-50 dark:bg-slate-700/50 border border-slate-200 dark:border-slate-600">
              <div className="font-bold text-sm text-slate-900 dark:text-slate-100">
                {blockModal.device.name || 'Thiết bị'}
              </div>
              <div className="font-mono text-slate-500 dark:text-slate-400 mt-0.5">
                IP: {blockModal.device.ip || '---'} • MAC: {blockModal.device.mac}
              </div>
            </div>

            <p className="text-slate-600 dark:text-slate-300">
              {blockModal.type === 'soft' ? (
                <span>
                  <strong>Cắt Net (Soft Block):</strong> Thiết bị vẫn kết nối sóng Wi-Fi bình thường
                  nhưng firewall sẽ chặn toàn bộ truy cập Internet ra ngoài. Sau khi hết giờ sẽ tự
                  động mở lại.
                </span>
              ) : (
                <span>
                  <strong>Đá Sóng (Hard Block):</strong> Router sẽ huỷ liên kết Wi-Fi ngay lập tức
                  và chặn không cho kết nối lại SSID. Hết giờ sẽ tự gỡ bỏ danh sách chặn.
                </span>
              )}
            </p>

            <div>
              <label className="block font-bold text-slate-700 dark:text-slate-300 mb-2">
                Chọn thời gian chặn tự động:
              </label>
              <div className="grid grid-cols-3 sm:grid-cols-4 gap-2">
                {presets.map((p) => {
                  const isChosen = selectedMinutes === p.mins && !customMinutes;
                  return (
                    <button
                      key={p.mins}
                      type="button"
                      onClick={() => {
                        setSelectedMinutes(p.mins);
                        setCustomMinutes('');
                      }}
                      className={`p-2 rounded-xl text-xs font-semibold border transition-all ${
                        isChosen
                          ? 'bg-blue-600 text-white border-blue-600 shadow-xs'
                          : 'bg-slate-50 dark:bg-slate-700/50 text-slate-700 dark:text-slate-300 border-slate-200 dark:border-slate-600 hover:bg-slate-100'
                      }`}
                    >
                      {p.label}
                    </button>
                  );
                })}
              </div>
            </div>

            <div>
              <label className="block font-semibold text-slate-600 dark:text-slate-400 mb-1">
                Hoặc tự nhập số phút:
              </label>
              <input
                type="number"
                min="1"
                placeholder="Nhập số phút..."
                className="vcrt-input"
                value={customMinutes}
                onChange={(e) => setCustomMinutes(e.target.value)}
              />
            </div>
          </div>
        )}
      </Modal>
    </div>
  );
}
