import { useState, useEffect } from 'react';
import { changePasswordApi } from '../api/auth';
import { getModemStatus, cleanRam, rebootRouter, ModemStatus } from '../api/system';
import {
  getTelegramConfig,
  saveTelegramConfig,
  testTelegramBot,
  controlTelegramService,
  TelegramConfig
} from '../api/telegram';
import {
  checkUpdate,
  doUpdate,
  setAutoUpdate,
  UpdateStatus
} from '../api/update';
import {
  getZeroTierStatus,
  joinZeroTierNetwork,
  leaveZeroTierNetwork,
  ZeroTierStatus
} from '../api/zerotier';
import { Modal } from '../components/Modal';
import { useToast } from '../components/Toast';

export default function SettingsScreen() {
  const { success, error, info } = useToast();

  // Đổi mật khẩu
  const [oldPass, setOldPass] = useState('');
  const [newPass, setNewPass] = useState('');
  const [confirmPass, setConfirmPass] = useState('');
  const [pwLoading, setPwLoading] = useState(false);

  // Modem 4G USB
  const [modem, setModem] = useState<ModemStatus | null>(null);

  // Telegram Bot
  const [tgConfig, setTgConfig] = useState<TelegramConfig | null>(null);
  const [tgToken, setTgToken] = useState('');
  const [tgChatId, setTgChatId] = useState('');
  const [tgNotifWifi, setTgNotifWifi] = useState(true);
  const [tgNotifExpire, setTgNotifExpire] = useState(true);
  const [tgNotifDaily, setTgNotifDaily] = useState(true);
  const [tgDailyHour, setTgDailyHour] = useState(20);
  const [tgAutoUpdate, setTgAutoUpdate] = useState(false);
  const [tgEnabled, setTgEnabled] = useState(true);
  const [tgLoading, setTgLoading] = useState(false);
  const [tgTesting, setTgTesting] = useState(false);

  // OTA Update
  const [updateStatus, setUpdateStatus] = useState<UpdateStatus | null>(null);
  const [isCheckingUpdate, setIsCheckingUpdate] = useState(false);
  const [isUpdating, setIsUpdating] = useState(false);
  const [updateMsg, setUpdateMsg] = useState<string | null>(null);

  // ZeroTier Remote Access
  const [ztStatus, setZtStatus] = useState<ZeroTierStatus | null>(null);
  const [ztNetworkIdInput, setZtNetworkIdInput] = useState('');
  const [ztLoading, setZtLoading] = useState(false);

  // Load initial data
  useEffect(() => {
    const fetchSettings = async () => {
      // Modem
      getModemStatus().then((res) => {
        if (res) setModem(res);
      }).catch(() => {});

      // Telegram
      getTelegramConfig().then((data) => {
        if (data) {
          setTgConfig(data);
          setTgChatId(data.chat_id || '');
          setTgNotifWifi(data.notif_wifi ?? true);
          setTgNotifExpire(data.notif_expire ?? true);
          setTgNotifDaily(data.notif_daily ?? true);
          setTgDailyHour(data.daily_hour || 20);
          setTgEnabled(data.enabled ?? (data.has_token && !!data.chat_id));
          setTgAutoUpdate(data.auto_update ?? false);
        }
      }).catch(() => {});

      // OTA Update
      checkUpdate().then((res) => {
        if (res && res.status === 'ok') setUpdateStatus(res);
      }).catch(() => {});

      // ZeroTier
      getZeroTierStatus().then((res) => {
        if (res) setZtStatus(res);
      }).catch(() => {});
    };

    fetchSettings();
  }, []);

  // Đổi mật khẩu
  const handleChangePassword = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!oldPass || !newPass) {
      error('Vui lòng nhập mật khẩu cũ và mới!');
      return;
    }
    if (newPass !== confirmPass) {
      error('Mật khẩu xác nhận không khớp!');
      return;
    }
    if (newPass.length < 3) {
      error('Mật khẩu mới tối thiểu 3 ký tự!');
      return;
    }

    setPwLoading(true);
    try {
      const res = await changePasswordApi(oldPass, newPass);
      if (res && res.status === 'ok') {
        success(res.message || 'Đã đổi mật khẩu thành công! Hãy ghi nhớ mật khẩu mới.');
        setOldPass('');
        setNewPass('');
        setConfirmPass('');
      } else {
        error(res?.message || 'Mật khẩu cũ không chính xác!');
      }
    } catch (e: any) {
      error(e?.message || 'Lỗi đổi mật khẩu');
    } finally {
      setPwLoading(false);
    }
  };

  // Lưu Telegram
  const handleSaveTelegram = async () => {
    setTgLoading(true);
    try {
      const hasToken = !!(tgToken?.trim() || tgConfig?.has_token);
      const hasChatId = !!tgChatId?.trim();
      const sendEnabled = hasToken && hasChatId ? true : tgEnabled;

      const res = await saveTelegramConfig({
        bot_token: tgToken || undefined,
        chat_id: tgChatId,
        auto_update: tgAutoUpdate,
        notif_wifi: tgNotifWifi,
        notif_expire: tgNotifExpire,
        notif_daily: tgNotifDaily,
        daily_hour: tgDailyHour,
        bot_enabled: sendEnabled
      });

      if (res && res.status === 'ok') {
        success('Đã lưu cấu hình và đồng bộ dịch vụ Telegram Bot!');
        setTgToken('');
        getTelegramConfig().then((data) => {
          if (data) setTgConfig(data);
        });
      } else {
        error('Lỗi lưu cấu hình Telegram');
      }
    } catch (e: any) {
      error(e?.message || 'Lỗi kết nối Telegram');
    } finally {
      setTgLoading(false);
    }
  };

  // Test Telegram
  const handleTestTelegram = async () => {
    setTgTesting(true);
    try {
      const res = await testTelegramBot(tgToken || undefined, tgChatId || undefined);
      if (res && res.status === 'ok') {
        success('Tin nhắn kiểm tra đã được gửi tới Telegram!');
      } else {
        error(`Gửi tin thất bại: ${res?.message || 'Kiểm tra Token & Chat ID'}`);
      }
    } catch (e: any) {
      error(e?.message || 'Lỗi gửi tin thử nghiệm');
    } finally {
      setTgTesting(false);
    }
  };

  // Control Telegram Service
  const handleToggleTgService = async (type: 'start' | 'stop') => {
    setTgLoading(true);
    try {
      await controlTelegramService(type);
      success(type === 'start' ? 'Đã khởi động dịch vụ Telegram Bot!' : 'Đã dừng dịch vụ Telegram Bot!');
      getTelegramConfig().then((data) => {
        if (data) setTgConfig(data);
      });
    } catch (e: any) {
      error(e?.message || 'Lỗi điều khiển dịch vụ');
    } finally {
      setTgLoading(false);
    }
  };

  // Check OTA Update
  const handleCheckUpdate = async () => {
    setIsCheckingUpdate(true);
    try {
      const res = await checkUpdate();
      if (res && res.status === 'ok') {
        setUpdateStatus(res);
        if (res.has_update) {
          success(`Đã có bản cập nhật mới: v${res.remote_version}!`);
        } else {
          info(`Bạn đang ở phiên bản mới nhất: v${res.current_version}`);
        }
      }
    } catch (e: any) {
      error(e?.message || 'Lỗi kiểm tra bản cập nhật');
    } finally {
      setIsCheckingUpdate(false);
    }
  };

  // Do OTA Update
  const handleDoUpdate = async () => {
    if (!window.confirm('Tiến hành tải và nâng cấp VCRT OS từ GitHub?\nRouter sẽ tự khởi động lại dịch vụ sau khi hoàn thành.')) return;
    setIsUpdating(true);
    setUpdateMsg('Đang tải và xác thực gói cập nhật...');
    try {
      const res = await doUpdate();
      if (res && res.status === 'ok') {
        success('Đã khởi chạy tiến trình cập nhật ngầm! Vui lòng đợi 15-20 giây...');
        setUpdateMsg('Đang cập nhật mã nguồn router...');
      } else {
        error('Lỗi nạp cập nhật');
      }
    } catch (e: any) {
      error(e?.message || 'Lỗi nâng cấp');
    } finally {
      setIsUpdating(false);
    }
  };

  // ZeroTier Join / Leave
  const handleJoinZeroTier = async () => {
    if (!ztNetworkIdInput.trim() || ztNetworkIdInput.trim().length !== 16) {
      error('Network ID của ZeroTier phải là chuỗi 16 ký tự hex!');
      return;
    }
    setZtLoading(true);
    try {
      await joinZeroTierNetwork(ztNetworkIdInput.trim());
      success(`Đã gửi lệnh gia nhập mạng ZeroTier: ${ztNetworkIdInput}!`);
      setZtNetworkIdInput('');
      const res = await getZeroTierStatus();
      if (res) setZtStatus(res);
    } catch (e: any) {
      error(e?.message || 'Lỗi gia nhập mạng ZeroTier');
    } finally {
      setZtLoading(false);
    }
  };

  const handleLeaveZeroTier = async (nwid: string) => {
    if (!window.confirm(`Bạn có chắc muốn rời khỏi mạng ZeroTier ${nwid}?`)) return;
    setZtLoading(true);
    try {
      await leaveZeroTierNetwork(nwid);
      success(`Đã rời khỏi mạng ${nwid}!`);
      const res = await getZeroTierStatus();
      if (res) setZtStatus(res);
    } catch (e: any) {
      error(e?.message || 'Lỗi rời mạng ZeroTier');
    } finally {
      setZtLoading(false);
    }
  };

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text);
    success(`Đã sao chép: ${text}`);
  };

  return (
    <div className="flex flex-col gap-5">
      <div>
        <h2 className="text-xl font-extrabold text-slate-900 dark:text-slate-100">
          Cài Đặt & Quản Trị Hệ Thống
        </h2>
        <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
          Bảo mật, thông báo Telegram, truy cập từ xa ZeroTier và nâng cấp phần mềm
        </p>
      </div>

      {/* 1. ZeroTier Remote Access Card */}
      <div className="vcrt-card p-5 flex flex-col gap-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <span className="text-2xl">🌐</span>
            <div>
              <h3 className="font-bold text-sm text-slate-900 dark:text-slate-100">
                ZeroTier One (Truy Cập Từ Xa Mọi Nơi)
              </h3>
              <p className="text-xs text-slate-400">
                Mạng VPN ngang hàng P2P không cần mở port WAN
              </p>
            </div>
          </div>

          <span
            className={`vcrt-badge ${
              ztStatus?.running
                ? 'bg-emerald-100 dark:bg-emerald-950/60 text-emerald-700 dark:text-emerald-300 border border-emerald-300 dark:border-emerald-800'
                : 'bg-slate-200 dark:bg-slate-700 text-slate-600 dark:text-slate-300'
            }`}
          >
            {ztStatus?.running ? 'ONLINE' : 'STOPPED'}
          </span>
        </div>

        {ztStatus?.node_id && (
          <div className="p-3 rounded-xl bg-slate-50 dark:bg-slate-800/50 border border-slate-200 dark:border-slate-700 flex items-center justify-between text-xs">
            <span className="text-slate-500 dark:text-slate-400">Router Node ID:</span>
            <span className="font-mono font-bold text-slate-800 dark:text-slate-200">
              {ztStatus.node_id} (v{ztStatus.version || '1.14'})
            </span>
          </div>
        )}

        {/* Join new network form */}
        <div className="flex flex-col sm:flex-row gap-2">
          <input
            type="text"
            maxLength={16}
            placeholder="Nhập ZeroTier 16-character Network ID..."
            className="vcrt-input flex-1 font-mono text-xs uppercase"
            value={ztNetworkIdInput}
            onChange={(e) => setZtNetworkIdInput(e.target.value)}
          />
          <button
            onClick={handleJoinZeroTier}
            disabled={ztLoading}
            className="vcrt-btn vcrt-btn-primary text-xs shrink-0"
          >
            {ztLoading ? '...' : 'Gia Nhập Mạng'}
          </button>
        </div>

        {/* Connected Networks List */}
        {ztStatus?.networks && ztStatus.networks.length > 0 && (
          <div className="flex flex-col gap-2">
            <h4 className="text-xs font-bold text-slate-700 dark:text-slate-300">
              Mạng ZeroTier Đã Tham Gia:
            </h4>
            <div className="flex flex-col gap-2">
              {ztStatus.networks.map((net) => (
                <div
                  key={net.nwid}
                  className="p-3 rounded-xl border border-slate-200 dark:border-slate-700 bg-slate-50/50 dark:bg-slate-800/40 flex flex-col sm:flex-row sm:items-center justify-between gap-3 text-xs"
                >
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="font-mono font-bold text-blue-600 dark:text-blue-400">
                        {net.nwid}
                      </span>
                      <span className="vcrt-badge bg-blue-100 dark:bg-blue-950 text-blue-700 dark:text-blue-300 text-[10px]">
                        {net.status}
                      </span>
                    </div>
                    {net.assigned_ip && (
                      <div className="flex items-center gap-2 mt-1">
                        <span className="text-slate-400">IP ảo Router:</span>
                        <span className="font-mono font-bold text-emerald-600 dark:text-emerald-400">
                          {net.assigned_ip}
                        </span>
                        <button
                          onClick={() => copyToClipboard(net.assigned_ip)}
                          className="text-[10px] text-blue-500 hover:underline"
                        >
                          Sao chép
                        </button>
                      </div>
                    )}
                  </div>

                  <button
                    onClick={() => handleLeaveZeroTier(net.nwid)}
                    className="text-rose-600 dark:text-rose-400 hover:underline text-xs self-end sm:self-auto"
                  >
                    Rời Mạng
                  </button>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>

      {/* 2. Telegram Bot Configuration Card */}
      <div className="vcrt-card p-5 flex flex-col gap-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <span className="text-2xl">✈️</span>
            <div>
              <h3 className="font-bold text-sm text-slate-900 dark:text-slate-100">
                Thông Báo & Điều Khiển Qua Telegram
              </h3>
              <p className="text-xs text-slate-400">
                Nhận cảnh báo thiết bị lạ, báo cáo lưu lượng hàng ngày qua bot
              </p>
            </div>
          </div>

          <span
            className={`vcrt-badge ${
              tgConfig?.running
                ? 'bg-emerald-100 dark:bg-emerald-950/60 text-emerald-700 dark:text-emerald-300 border border-emerald-300 dark:border-emerald-800'
                : 'bg-slate-200 dark:bg-slate-700 text-slate-600 dark:text-slate-300'
            }`}
          >
            {tgConfig?.running ? 'DAEMON CHẠY' : 'ĐÃ DỪNG'}
          </span>
        </div>

        {/* Inputs */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          <div>
            <label className="block text-xs font-semibold text-slate-600 dark:text-slate-400 mb-1">
              Bot Token (từ @BotFather)
            </label>
            <input
              type="password"
              className="vcrt-input font-mono text-xs"
              placeholder={tgConfig?.has_token ? `Đang dùng: ${tgConfig.token_masked}` : 'vd: 742789:AA...'}
              value={tgToken}
              onChange={(e) => setTgToken(e.target.value)}
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-600 dark:text-slate-400 mb-1">
              Chat ID hoặc ID Nhóm
            </label>
            <input
              type="text"
              className="vcrt-input font-mono text-xs"
              placeholder="vd: 12345678, -100987654321"
              value={tgChatId}
              onChange={(e) => setTgChatId(e.target.value)}
            />
          </div>
        </div>

        {/* Toggle options */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 text-xs">
          <label className="p-2.5 rounded-xl border border-slate-200 dark:border-slate-700 bg-slate-50/50 dark:bg-slate-800/40 flex items-center justify-between cursor-pointer">
            <span>🔔 Báo thiết bị Wi-Fi mới kết nối</span>
            <input
              type="checkbox"
              checked={tgNotifWifi}
              onChange={(e) => setTgNotifWifi(e.target.checked)}
              className="rounded text-blue-600"
            />
          </label>

          <label className="p-2.5 rounded-xl border border-slate-200 dark:border-slate-700 bg-slate-50/50 dark:bg-slate-800/40 flex items-center justify-between cursor-pointer">
            <span>⏱️ Báo hết giờ ngắt kết nối</span>
            <input
              type="checkbox"
              checked={tgNotifExpire}
              onChange={(e) => setTgNotifExpire(e.target.checked)}
              className="rounded text-blue-600"
            />
          </label>

          <label className="p-2.5 rounded-xl border border-slate-200 dark:border-slate-700 bg-slate-50/50 dark:bg-slate-800/40 flex items-center justify-between cursor-pointer">
            <span>📊 Báo cáo lưu lượng ({tgDailyHour}h tối)</span>
            <input
              type="checkbox"
              checked={tgNotifDaily}
              onChange={(e) => setTgNotifDaily(e.target.checked)}
              className="rounded text-blue-600"
            />
          </label>

          <label className="p-2.5 rounded-xl border border-slate-200 dark:border-slate-700 bg-slate-50/50 dark:bg-slate-800/40 flex items-center justify-between cursor-pointer">
            <span>🚀 Tự động cập nhật OS từ GitHub</span>
            <input
              type="checkbox"
              checked={tgAutoUpdate}
              onChange={(e) => setTgAutoUpdate(e.target.checked)}
              className="rounded text-blue-600"
            />
          </label>
        </div>

        {/* Actions */}
        <div className="flex flex-wrap items-center justify-end gap-2 pt-2 border-t border-slate-100 dark:border-slate-800">
          {tgConfig?.running ? (
            <button
              onClick={() => handleToggleTgService('stop')}
              disabled={tgLoading}
              className="vcrt-btn text-xs text-rose-600 border border-rose-300 dark:border-rose-800"
            >
              Dừng Dịch Vụ
            </button>
          ) : (
            <button
              onClick={() => handleToggleTgService('start')}
              disabled={tgLoading}
              className="vcrt-btn text-xs text-emerald-600 border border-emerald-300 dark:border-emerald-800"
            >
              Bật Dịch Vụ
            </button>
          )}

          <button
            onClick={handleTestTelegram}
            disabled={tgTesting || (!tgToken && !tgConfig?.has_token) || !tgChatId}
            className="vcrt-btn vcrt-btn-secondary text-xs"
          >
            {tgTesting ? 'Đang gửi...' : 'Gửi Thử Tin Nhắn'}
          </button>

          <button
            onClick={handleSaveTelegram}
            disabled={tgLoading}
            className="vcrt-btn vcrt-btn-primary text-xs"
          >
            {tgLoading ? 'Đang lưu...' : 'Lưu Cấu Hình'}
          </button>
        </div>
      </div>

      {/* 3. Modem 4G LTE USB Status Card */}
      <div className="vcrt-card p-5 flex flex-col gap-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <span className="text-2xl">📶</span>
            <div>
              <h3 className="font-bold text-sm text-slate-900 dark:text-slate-100">
                Modem 4G LTE USB (Dcom)
              </h3>
              <p className="text-xs text-slate-400">
                Cổng mạng dự phòng khi mất cáp Internet
              </p>
            </div>
          </div>

          <span
            className={`vcrt-badge ${
              modem?.connected
                ? 'bg-emerald-100 dark:bg-emerald-950/60 text-emerald-700 dark:text-emerald-300 border border-emerald-300 dark:border-emerald-800'
                : 'bg-slate-200 dark:bg-slate-700 text-slate-600 dark:text-slate-300'
            }`}
          >
            {modem?.connected ? 'CONNECTED' : 'DISCONNECTED'}
          </span>
        </div>

        {modem?.connected ? (
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 text-xs">
            <div className="p-2.5 rounded-lg bg-slate-50 dark:bg-slate-800/60">
              <span className="text-slate-400 block">Nhà mạng:</span>
              <span className="font-bold text-slate-800 dark:text-slate-200">{modem.operator}</span>
            </div>
            <div className="p-2.5 rounded-lg bg-slate-50 dark:bg-slate-800/60">
              <span className="text-slate-400 block">Thiết bị:</span>
              <span className="font-bold text-slate-800 dark:text-slate-200">{modem.model}</span>
            </div>
            <div className="p-2.5 rounded-lg bg-slate-50 dark:bg-slate-800/60">
              <span className="text-slate-400 block">Sóng RSRP:</span>
              <span className="font-bold text-emerald-500">{modem.rsrp} dBm</span>
            </div>
            <div className="p-2.5 rounded-lg bg-slate-50 dark:bg-slate-800/60">
              <span className="text-slate-400 block">Chất lượng SINR:</span>
              <span className="font-bold text-emerald-500">{modem.sinr} dB</span>
            </div>
          </div>
        ) : (
          <div className="text-xs text-slate-400 p-4 rounded-xl bg-slate-50 dark:bg-slate-800/40 text-center">
            Chưa cắm modem 4G USB vào router. Khi cắm thiết bị LTE (Huawei, ZTE), thông tin sóng sẽ hiển thị tại đây.
          </div>
        )}
      </div>

      {/* 4. OTA Update & Version Card */}
      <div className="vcrt-card p-5 flex flex-col gap-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <span className="text-2xl">🚀</span>
            <div>
              <h3 className="font-bold text-sm text-slate-900 dark:text-slate-100">
                Phiên Bản & Cập Nhật VCRT OS
              </h3>
              <p className="text-xs text-slate-400">
                Đồng bộ mã nguồn trực tiếp từ GitHub repository chính thức
              </p>
            </div>
          </div>

          <span className="vcrt-badge bg-blue-100 dark:bg-blue-950 text-blue-700 dark:text-blue-300 font-mono">
            v{updateStatus?.current_version || '2.0.0'}
          </span>
        </div>

        {updateMsg && (
          <div className="p-3 rounded-xl bg-blue-50 dark:bg-blue-950/50 border border-blue-200 dark:border-blue-900 text-xs text-blue-800 dark:text-blue-200 flex items-center gap-2">
            <span className="animate-spin">⏳</span>
            <span>{updateMsg}</span>
          </div>
        )}

        {/* Update alert banner */}
        {updateStatus?.has_update && (
          <div className="p-4 rounded-2xl bg-gradient-to-r from-blue-500/15 to-indigo-500/15 border border-blue-500/30 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
            <div>
              <div className="font-bold text-sm text-blue-600 dark:text-blue-400">
                🎉 ĐÃ CÓ BẢN MỚI: v{updateStatus.remote_version}!
              </div>
              <p className="text-xs text-slate-600 dark:text-slate-400 mt-0.5">
                Bản nâng cấp tối ưu hiệu năng, bảo mật và tính năng mới nhất.
              </p>
            </div>
            <button
              onClick={handleDoUpdate}
              disabled={isUpdating}
              className="vcrt-btn vcrt-btn-primary text-xs shrink-0"
            >
              {isUpdating ? 'Đang cập nhật...' : 'Cập Nhật Ngay'}
            </button>
          </div>
        )}

        <div className="flex items-center justify-between pt-1 text-xs">
          <label className="flex items-center gap-2 text-slate-700 dark:text-slate-300 cursor-pointer">
            <input
              type="checkbox"
              checked={updateStatus?.auto_update ?? false}
              onChange={async (e) => {
                const val = e.target.checked;
                await setAutoUpdate(val);
                setUpdateStatus((prev) => (prev ? { ...prev, auto_update: val } : null));
                success(val ? 'Đã bật tự động cập nhật 24/7!' : 'Đã tắt tự động cập nhật.');
              }}
              className="rounded text-blue-600"
            />
            <span>Tự động cập nhật 24/7 khi có bản mới</span>
          </label>

          <div className="flex items-center gap-2">
            <button
              onClick={handleCheckUpdate}
              disabled={isCheckingUpdate}
              className="vcrt-btn vcrt-btn-secondary text-xs py-1.5"
            >
              {isCheckingUpdate ? 'Đang kiểm tra...' : 'Kiểm Tra Bản Mới'}
            </button>
            <a
              href="https://github.com/lecuong2512/vcrt"
              target="_blank"
              rel="noreferrer"
              className="vcrt-btn vcrt-btn-secondary text-xs py-1.5"
            >
              GitHub ↗
            </a>
          </div>
        </div>
      </div>

      {/* 5. Đổi mật khẩu router */}
      <div className="vcrt-card p-5 flex flex-col gap-4">
        <div>
          <h3 className="font-bold text-sm text-slate-900 dark:text-slate-100 flex items-center gap-2">
            <span>🔒</span> Đổi Mật Khẩu Quản Trị Router
          </h3>
          <p className="text-xs text-slate-400 mt-0.5">
            Mật khẩu mới sẽ áp dụng ngay cho giao diện Web và các dịch vụ quản trị
          </p>
        </div>

        <form onSubmit={handleChangePassword} className="flex flex-col gap-3">
          <div>
            <label className="block text-xs font-semibold text-slate-600 dark:text-slate-400 mb-1">
              Mật khẩu cũ
            </label>
            <input
              type="password"
              className="vcrt-input"
              value={oldPass}
              onChange={(e) => setOldPass(e.target.value)}
              placeholder="Nhập mật khẩu hiện tại..."
            />
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-semibold text-slate-600 dark:text-slate-400 mb-1">
                Mật khẩu mới
              </label>
              <input
                type="password"
                className="vcrt-input"
                value={newPass}
                onChange={(e) => setNewPass(e.target.value)}
                placeholder="Mật khẩu mới..."
              />
            </div>
            <div>
              <label className="block text-xs font-semibold text-slate-600 dark:text-slate-400 mb-1">
                Xác nhận mật khẩu mới
              </label>
              <input
                type="password"
                className="vcrt-input"
                value={confirmPass}
                onChange={(e) => setConfirmPass(e.target.value)}
                placeholder="Nhập lại mật khẩu mới..."
              />
            </div>
          </div>

          <div className="flex justify-end pt-1">
            <button
              type="submit"
              disabled={pwLoading}
              className="vcrt-btn vcrt-btn-primary text-xs"
            >
              {pwLoading ? 'Đang đổi...' : 'Lưu Mật Khẩu Mới'}
            </button>
          </div>
        </form>
      </div>

      {/* 6. Thao tác bảo trì hệ thống */}
      <div className="vcrt-card p-5 flex flex-col gap-3">
        <h3 className="font-bold text-sm text-slate-900 dark:text-slate-100 flex items-center gap-2">
          <span>⚙️</span> Bảo Trì & Thao Tác Nhanh
        </h3>

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-2 text-xs">
          <button
            onClick={async () => {
              const res = await cleanRam();
              success(`Đã làm trống bộ nhớ RAM! Trống: ${res?.mem_avail ?? ''} MB`);
            }}
            className="vcrt-btn vcrt-btn-secondary py-2.5 flex items-center justify-center gap-2"
          >
            <span>🧹</span> Giải Phóng Bộ Nhớ RAM
          </button>

          <button
            onClick={() => window.open('/cgi-bin/luci/admin/system/backup', '_blank')}
            className="vcrt-btn vcrt-btn-secondary py-2.5 flex items-center justify-center gap-2"
          >
            <span>💾</span> Tải Sao Lưu Cấu Hình
          </button>

          <button
            onClick={async () => {
              if (window.confirm('Khởi động lại Router?')) {
                await rebootRouter();
                info('Router đang khởi động lại...');
              }
            }}
            className="vcrt-btn text-amber-600 border border-amber-300 dark:border-amber-800 hover:bg-amber-50 py-2.5 flex items-center justify-center gap-2"
          >
            <span>🔄</span> Khởi Động Lại Router
          </button>
        </div>
      </div>
    </div>
  );
}
