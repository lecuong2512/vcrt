import { useState, useEffect } from 'react';
import {
  getWifiConfig,
  applyWifiConfig,
  scanWifi,
  connectWifiUplink,
  rollbackWifiConfig,
  confirmWifiConfig,
  ScannedNetwork
} from '../api/wifi';
import { WifiCard } from '../components/WifiCard';
import { Modal } from '../components/Modal';
import { useToast } from '../components/Toast';

export default function WiFiScreen() {
  const { success, error, info, warning } = useToast();

  const [ssid5, setSsid5] = useState('Xiaomi_Mini_5G');
  const [pass5, setPass5] = useState('25122035');
  const [ch5, setCh5] = useState('157');
  const [power5, setPower5] = useState('20');

  const [ssid24, setSsid24] = useState('Xiaomi_Mini_2.4G');
  const [pass24, setPass24] = useState('25122035');
  const [ch24, setCh24] = useState('6');
  const [power24, setPower24] = useState('20');

  // Scanner state
  const [scanModalOpen, setScanModalOpen] = useState(false);
  const [isScanning, setIsScanning] = useState(false);
  const [scannedNetworks, setScannedNetworks] = useState<ScannedNetwork[]>([]);
  const [scanBand, setScanBand] = useState<'2.4g' | '5g'>('5g');
  const [selectedNetwork, setSelectedNetwork] = useState<ScannedNetwork | null>(null);
  const [uplinkPass, setUplinkPass] = useState('');
  const [isConnectingUplink, setIsConnectingUplink] = useState(false);

  // Rollback countdown state
  // 0: idle, 1: applying, 2: countdown 60s
  const [rollbackStep, setRollbackStep] = useState<0 | 1 | 2>(0);
  const [countdown, setCountdown] = useState(60);

  useEffect(() => {
    const fetchWifi = async () => {
      try {
        const res = await getWifiConfig();
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
      } catch {
        // Ignored
      }
    };
    fetchWifi();
  }, []);

  // 60s Countdown Timer cho Safe Rollback
  useEffect(() => {
    let timer: any = null;
    if (rollbackStep === 2 && countdown > 0) {
      timer = setInterval(() => {
        setCountdown((prev) => prev - 1);
      }, 1000);
    } else if (rollbackStep === 2 && countdown === 0) {
      handleRollback(true);
    }
    return () => {
      if (timer) clearInterval(timer);
    };
  }, [rollbackStep, countdown]);

  const handleApply = async () => {
    setRollbackStep(1);
    try {
      await applyWifiConfig({
        ssid5,
        pass5,
        ch5,
        power5,
        ssid24,
        pass24,
        ch24,
        power24
      });
      setRollbackStep(2);
      setCountdown(60);
      info('Đã phát sóng mới! Bắt đầu 60 giây đếm ngược kiểm tra kết nối.');
    } catch (e: any) {
      setRollbackStep(0);
      error(e?.message || 'Lỗi áp dụng cấu hình Wi-Fi');
    }
  };

  const handleConfirmKeep = async () => {
    try {
      await confirmWifiConfig();
      setRollbackStep(0);
      success('Đã xác nhận và lưu cấu hình Wi-Fi mới an toàn!');
    } catch (e: any) {
      error(e?.message || 'Lỗi xác nhận');
    }
  };

  const handleRollback = async (isTimeout = false) => {
    setRollbackStep(1);
    try {
      await rollbackWifiConfig();
      setRollbackStep(0);
      if (isTimeout) {
        warning('Hết 60 giây chưa xác nhận. Router đã tự hoàn tác về mật khẩu cũ an toàn!');
      } else {
        success('Đã hoàn tác cấu hình Wi-Fi về trạng thái cũ thành công!');
      }
    } catch (e: any) {
      setRollbackStep(0);
      error(e?.message || 'Lỗi hoàn tác');
    }
  };

  const handleStartScan = async (band: '2.4g' | '5g') => {
    setScanBand(band);
    setIsScanning(true);
    setScannedNetworks([]);
    setSelectedNetwork(null);
    setScanModalOpen(true);

    try {
      const res = await scanWifi(band);
      if (res && res.networks) {
        setScannedNetworks(res.networks);
      }
    } catch (e: any) {
      error(e?.message || 'Lỗi quét sóng Wi-Fi xung quanh');
    } finally {
      setIsScanning(false);
    }
  };

  const handleConnectUplink = async () => {
    if (!selectedNetwork) return;
    setIsConnectingUplink(true);
    try {
      await connectWifiUplink({
        band: scanBand,
        ssid: selectedNetwork.ssid,
        bssid: selectedNetwork.bssid,
        key: uplinkPass,
        channel: selectedNetwork.channel
      });
      success(`Đang thiết lập kết nối WISP tới "${selectedNetwork.ssid}"...`);
      setScanModalOpen(false);
      setSelectedNetwork(null);
      setUplinkPass('');
    } catch (e: any) {
      error(e?.message || 'Lỗi kết nối Wi-Fi Uplink');
    } finally {
      setIsConnectingUplink(false);
    }
  };

  const channels5G = [
    { val: '36', label: 'CH 36 (5180 MHz - Tốt cho nhà riêng)' },
    { val: '40', label: 'CH 40 (5200 MHz)' },
    { val: '44', label: 'CH 44 (5220 MHz)' },
    { val: '48', label: 'CH 48 (5240 MHz)' },
    { val: '149', label: 'CH 149 (5745 MHz - Xuyên tường tốt)' },
    { val: '153', label: 'CH 153 (5765 MHz)' },
    { val: '157', label: 'CH 157 (5785 MHz - Mặc định khuyến nghị)' },
    { val: '161', label: 'CH 161 (5805 MHz)' },
    { val: '165', label: 'CH 165 (5825 MHz)' }
  ];

  const channels24G = [
    { val: '1', label: 'CH 1 (2412 MHz)' },
    { val: '6', label: 'CH 6 (2437 MHz - Mặc định khuyến nghị)' },
    { val: '11', label: 'CH 11 (2462 MHz)' },
    { val: '13', label: 'CH 13 (2472 MHz - Ít nhiễu ở VN)' }
  ];

  return (
    <div className="flex flex-col gap-4">
      {/* Header & Scanner Buttons */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
        <div>
          <h2 className="text-xl font-extrabold text-slate-900 dark:text-slate-100">
            Quản Trị Wi-Fi Băng Tần Kép
          </h2>
          <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
            Xiaomi MiWiFi Mini (MT7612E 5GHz AC867 + MT7620A 2.4GHz N300)
          </p>
        </div>

        <div className="flex items-center gap-2 self-start sm:self-auto">
          <button
            onClick={() => handleStartScan('5g')}
            className="vcrt-btn vcrt-btn-secondary text-xs"
          >
            <span>📡</span>
            <span>Quét 5GHz WISP</span>
          </button>
          <button
            onClick={() => handleStartScan('2.4g')}
            className="vcrt-btn vcrt-btn-secondary text-xs"
          >
            <span>📡</span>
            <span>Quét 2.4GHz WISP</span>
          </button>
        </div>
      </div>

      {/* Rollback Countdown Warning Banner */}
      {rollbackStep === 2 && (
        <div className="p-4 rounded-2xl bg-amber-500/15 border border-amber-500/30 flex flex-col sm:flex-row items-center justify-between gap-3 animate-in fade-in">
          <div className="flex items-center gap-3">
            <span className="text-2xl animate-bounce">⏱️</span>
            <div>
              <h4 className="font-bold text-sm text-amber-700 dark:text-amber-300">
                Đang Thử Nghiệm Wi-Fi Mới • Tự hoàn tác sau {countdown}s
              </h4>
              <p className="text-xs text-slate-600 dark:text-slate-400 mt-0.5">
                Nếu mạng hoạt động tốt, hãy bấm <strong>"Xác Nhận Giữ Mạng"</strong>. Ngược lại,
                router sẽ tự quay về cấu hình cũ.
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2 shrink-0">
            <button
              onClick={() => handleRollback(false)}
              className="vcrt-btn bg-rose-600 text-white text-xs hover:bg-rose-700"
            >
              Hoàn Tác Ngay
            </button>
            <button
              onClick={handleConfirmKeep}
              className="vcrt-btn bg-emerald-600 text-white text-xs hover:bg-emerald-700"
            >
              Xác Nhận Giữ Mạng
            </button>
          </div>
        </div>
      )}

      {/* 5GHz Card */}
      <WifiCard
        bandTitle="Băng tần 5GHz Cao Tốc (802.11ac)"
        bandBadge="5 GHz"
        chipInfo="Chipset MT7612E (Tối đa 867 Mbps)"
        ssid={ssid5}
        onSsidChange={setSsid5}
        pass={pass5}
        onPassChange={setPass5}
        channel={ch5}
        onChannelChange={setCh5}
        channels={channels5G}
        power={power5}
        onPowerChange={setPower5}
      />

      {/* 2.4GHz Card */}
      <WifiCard
        bandTitle="Băng tần 2.4GHz Tiêu Chuẩn (802.11n)"
        bandBadge="2.4 GHz"
        chipInfo="Chipset MT7620A (Tối đa 300 Mbps)"
        ssid={ssid24}
        onSsidChange={setSsid24}
        pass={pass24}
        onPassChange={setPass24}
        channel={ch24}
        onChannelChange={setCh24}
        channels={channels24G}
        power={power24}
        onPowerChange={setPower24}
      />

      {/* Submit Button */}
      <div className="flex justify-end pt-2">
        <button
          onClick={handleApply}
          disabled={rollbackStep === 1}
          className="vcrt-btn vcrt-btn-primary py-2.5 px-6 font-bold text-sm shadow-md"
        >
          {rollbackStep === 1 ? (
            <>
              <span className="animate-spin">⏳</span>
              <span>Đang Áp Dụng...</span>
            </>
          ) : (
            <>
              <span>⚡</span>
              <span>Áp Dụng Cấu Hình Wi-Fi (Bảo Vệ 60s)</span>
            </>
          )}
        </button>
      </div>

      {/* Wi-Fi Scanner Modal */}
      <Modal
        isOpen={scanModalOpen}
        onClose={() => setScanModalOpen(false)}
        title={`Quét Mạng Wi-Fi Xung Quanh (${scanBand.toUpperCase()})`}
        maxWidth="max-w-lg"
      >
        <div className="flex flex-col gap-3">
          {isScanning ? (
            <div className="p-8 text-center text-sm text-slate-400 flex flex-col items-center gap-2">
              <span className="text-2xl animate-spin">📡</span>
              <span>Đang dò quét các trạm phát Wi-Fi lân cận...</span>
            </div>
          ) : selectedNetwork ? (
            <div className="flex flex-col gap-3">
              <div className="p-3 rounded-xl bg-slate-50 dark:bg-slate-700/50 border border-slate-200 dark:border-slate-600">
                <div className="font-bold text-sm text-slate-900 dark:text-slate-100">
                  {selectedNetwork.ssid}
                </div>
                <div className="text-xs text-slate-400 font-mono mt-0.5">
                  BSSID: {selectedNetwork.bssid} • CH {selectedNetwork.channel} • Sóng:{' '}
                  {selectedNetwork.signal}%
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 dark:text-slate-300 mb-1">
                  Nhập Mật Khẩu Wi-Fi Để Thu Sóng (WISP):
                </label>
                <input
                  type="password"
                  className="vcrt-input"
                  value={uplinkPass}
                  onChange={(e) => setUplinkPass(e.target.value)}
                  placeholder="Mật khẩu của trạm phát gốc..."
                  autoFocus
                />
              </div>

              <div className="flex items-center justify-end gap-2 pt-2">
                <button
                  type="button"
                  onClick={() => setSelectedNetwork(null)}
                  className="vcrt-btn vcrt-btn-secondary text-xs"
                >
                  Chọn Mạng Khác
                </button>
                <button
                  type="button"
                  onClick={handleConnectUplink}
                  disabled={isConnectingUplink}
                  className="vcrt-btn vcrt-btn-primary text-xs"
                >
                  {isConnectingUplink ? 'Đang kết nối...' : 'Kết Nối & Kích Sóng'}
                </button>
              </div>
            </div>
          ) : scannedNetworks.length === 0 ? (
            <div className="p-8 text-center text-sm text-slate-400">
              Không tìm thấy mạng Wi-Fi nào khả dụng.
            </div>
          ) : (
            <div className="flex flex-col gap-2 max-h-[50vh] overflow-y-auto pr-1">
              {scannedNetworks.map((net) => (
                <div
                  key={net.bssid}
                  onClick={() => setSelectedNetwork(net)}
                  className="p-3 rounded-xl border border-slate-200 dark:border-slate-700 hover:border-blue-500 dark:hover:border-blue-500 bg-slate-50/50 dark:bg-slate-800/40 cursor-pointer flex items-center justify-between transition-all"
                >
                  <div>
                    <div className="font-bold text-sm text-slate-900 dark:text-slate-100">
                      {net.ssid || '<Mạng Ẩn SSID>'}
                    </div>
                    <div className="text-xs text-slate-400 font-mono mt-0.5">
                      CH {net.channel} • {net.security}
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-mono font-bold text-blue-600 dark:text-blue-400">
                      {net.signal}%
                    </span>
                    <span className="text-xs text-slate-400">➔</span>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </Modal>
    </div>
  );
}
