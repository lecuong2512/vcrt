import { useState, useEffect, useMemo, useRef } from 'react';
import {
  getNextDnsConfig,
  setNextDnsProfile,
  disableNextDns,
  setNextDnsApiKey,
  delNextDnsApiKey,
  proxyNextDnsApi,
  syncNextDnsIp
} from '../api/nextdns';
import { AddBlocklistModal, CommunityBlocklist } from '../components/AddBlocklistModal';
import { Modal } from '../components/Modal';
import { useToast } from '../components/Toast';

const POPULAR_SERVICES = [
  { id: 'tiktok', name: 'TikTok', icon: '📱' },
  { id: 'facebook', name: 'Facebook', icon: '👥' },
  { id: 'youtube', name: 'YouTube', icon: '▶️' },
  { id: 'instagram', name: 'Instagram', icon: '📷' },
  { id: 'roblox', name: 'Roblox', icon: '🎮' },
  { id: 'discord', name: 'Discord', icon: '💬' },
  { id: 'steam', name: 'Steam', icon: '🕹️' },
  { id: 'tinder', name: 'Tinder', icon: '🔥' },
  { id: 'netflix', name: 'Netflix', icon: '🎬' },
  { id: 'telegram', name: 'Telegram', icon: '✈️' },
  { id: 'twitch', name: 'Twitch', icon: '👾' },
  { id: 'spotify', name: 'Spotify', icon: '🎵' }
];

const CATEGORIES = [
  { id: 'porn', name: 'Web người lớn (Porn)', desc: 'Chặn nội dung khiêu dâm, 18+', icon: '🔞' },
  { id: 'gambling', name: 'Cờ bạc & Cá độ', desc: 'Chặn các trang cá cược trực tuyến', icon: '🎲' },
  { id: 'piracy', name: 'Trang web lậu', desc: 'Chặn torrent, web phim lậu bản quyền', icon: '🏴‍☠️' },
  { id: 'dating', name: 'Hẹn hò', desc: 'Chặn các ứng dụng tìm bạn hẹn hò', icon: '💘' },
  { id: 'social-networks', name: 'Mạng xã hội', desc: 'Chặn toàn bộ các trang mạng xã hội', icon: '🌐' },
  { id: 'online-gaming', name: 'Game online', desc: 'Chặn truy cập máy chủ game online', icon: '🎯' }
];

const SECURITY_FEATURES = [
  { key: 'aiThreatDetection', name: 'Phát hiện hiểm họa bằng AI', desc: 'Chặn hiểm họa bằng mô hình học máy theo thời gian thực', icon: '🤖' },
  { key: 'threatIntelligenceFeeds', name: 'Tình báo mối đe dọa', desc: 'Cập nhật từ hàng chục nguồn an ninh mạng toàn cầu', icon: '🛡️' },
  { key: 'googleSafeBrowsing', name: 'Google Safe Browsing', desc: 'Bảo vệ khỏi trang web lừa đảo theo dữ liệu Google', icon: '🌐' },
  { key: 'cryptojacking', name: 'Chống đào coin ẩn', desc: 'Chặn mã độc tự ý dùng CPU router & máy để đào coin', icon: '⛏️' },
  { key: 'typosquatting', name: 'Chống tên miền giả mạo', desc: 'Bảo vệ khi gõ nhầm tên miền ngân hàng (như paypa1.com)', icon: '🎭' },
  { key: 'dnsRebinding', name: 'Chống DNS Rebinding', desc: 'Ngăn hacker xâm nhập thiết bị smart home qua web', icon: '🔒' }
];

const TIME_RANGES = [
  { id: '-30m', label: '30 phút qua' },
  { id: '-6h', label: '6 giờ qua' },
  { id: '-24h', label: '24 giờ qua' },
  { id: '-7d', label: '7 ngày qua' },
  { id: '-30d', label: '30 ngày qua' },
  { id: '-3M', label: '3 tháng qua' }
];

interface NextDNSLog {
  timestamp: string;
  domain: string;
  root?: string;
  tracker?: string;
  protocol?: string;
  clientIp?: string;
  status: 'default' | 'blocked' | string;
  reasons?: { id: string; name: string }[];
}

export default function NextDNSScreen() {
  const { success, error, info } = useToast();

  const [profileId, setProfileId] = useState('');
  const [isActive, setIsActive] = useState(false);
  const [hasApiKey, setHasApiKey] = useState(false);
  const [maskedKey, setMaskedKey] = useState('');
  const [linkedIp, setLinkedIp] = useState('');

  // Sub-tabs
  type SubTab = 'analytics' | 'logs' | 'privacy' | 'parental' | 'security' | 'lists';
  const [activeSubTab, setActiveSubTab] = useState<SubTab>('analytics');

  // Modals
  const [apiKeyModalOpen, setApiKeyModalOpen] = useState(false);
  const [apiKeyInput, setApiKeyInput] = useState('');
  const [profileModalOpen, setProfileModalOpen] = useState(false);
  const [profileInput, setProfileInput] = useState('');

  // Analytics State
  const [timeRange, setTimeRange] = useState('-30d');
  const [loadingCloud, setLoadingCloud] = useState(false);
  const [analytics, setAnalytics] = useState<{ queries: number; blocked: number } | null>(null);
  const [resolvedDomains, setResolvedDomains] = useState<{ domain: string; queries: number }[]>([]);
  const [blockedDomains, setBlockedDomains] = useState<{ domain: string; queries: number; tracker?: string }[]>([]);

  // Logs State
  const [logs, setLogs] = useState<NextDNSLog[]>([]);
  const [logSearch, setLogSearch] = useState('');
  const [logFilterBlocked, setLogFilterBlocked] = useState(false);
  const [fetchingLogs, setFetchingLogs] = useState(false);

  // Blocklists State
  const [activeBlocklists, setActiveBlocklists] = useState<CommunityBlocklist[]>([]);
  const [availableBlocklists, setAvailableBlocklists] = useState<CommunityBlocklist[]>([]);
  const [isAddBlocklistOpen, setIsAddBlocklistOpen] = useState(false);

  // Profile data (parental, security, etc.)
  const [profileData, setProfileData] = useState<any>(null);

  // Lists State
  const [denylist, setDenylist] = useState<{ id: string; active: boolean }[]>([]);
  const [allowlist, setAllowlist] = useState<{ id: string; active: boolean }[]>([]);
  const [newDomainInput, setNewDomainInput] = useState('');
  const [listType, setListType] = useState<'denylist' | 'allowlist'>('denylist');

  // Fetch local router NextDNS configuration
  const fetchLocalConfig = async () => {
    try {
      const data = await getNextDnsConfig();
      if (data) {
        setIsActive(data.active);
        if (data.profile_id) {
          setProfileId(data.profile_id);
          setProfileInput(data.profile_id);
        }
        setHasApiKey(!!data.has_apikey);
        setMaskedKey(data.apikey_masked || '');
        setLinkedIp(data.linked_ip || '');
      }
    } catch {
      // Ignored
    }
  };

  useEffect(() => {
    fetchLocalConfig();
  }, []);

  // Fetch NextDNS Cloud Data khi có Profile ID và API Key
  const fetchCloudData = async () => {
    if (!profileId || !hasApiKey) return;
    setLoadingCloud(true);

    try {
      if (activeSubTab === 'analytics') {
        const [statsRes, domainsRes] = await Promise.all([
          proxyNextDnsApi(`profiles/${profileId}/analytics/status?from=${timeRange}`, 'GET'),
          proxyNextDnsApi(`profiles/${profileId}/analytics/domains?from=${timeRange}&limit=10`, 'GET')
        ]);

        if (statsRes && Array.isArray(statsRes)) {
          const totalQ = statsRes.reduce((acc: number, r: any) => acc + (r.queries || 0), 0);
          const blockedQ = statsRes.find((r: any) => r.status === 'blocked')?.queries || 0;
          setAnalytics({ queries: totalQ, blocked: blockedQ });
        }

        if (domainsRes && Array.isArray(domainsRes)) {
          setResolvedDomains(domainsRes);
        }
      } else if (activeSubTab === 'logs') {
        setFetchingLogs(true);
        const logsRes = await proxyNextDnsApi(`profiles/${profileId}/logs?limit=40`, 'GET');
        if (logsRes && logsRes.data) {
          setLogs(logsRes.data);
        }
        setFetchingLogs(false);
      } else if (activeSubTab === 'privacy') {
        const [profRes, parentBlocklists] = await Promise.all([
          proxyNextDnsApi(`profiles/${profileId}/privacy`, 'GET'),
          proxyNextDnsApi('parentalcontrol/blocklists', 'GET').catch(() => null)
        ]);
        if (profRes) {
          setActiveBlocklists(profRes.blocklists || []);
        }
        if (parentBlocklists && Array.isArray(parentBlocklists)) {
          setAvailableBlocklists(parentBlocklists);
        }
      } else if (activeSubTab === 'parental' || activeSubTab === 'security') {
        const res = await proxyNextDnsApi(`profiles/${profileId}/${activeSubTab}`, 'GET');
        if (res) {
          setProfileData(res);
        }
      } else if (activeSubTab === 'lists') {
        const [denyRes, allowRes] = await Promise.all([
          proxyNextDnsApi(`profiles/${profileId}/denylist`, 'GET'),
          proxyNextDnsApi(`profiles/${profileId}/allowlist`, 'GET')
        ]);
        if (denyRes) setDenylist(denyRes);
        if (allowRes) setAllowlist(allowRes);
      }
    } catch (e: any) {
      console.warn('[NextDNS Cloud Fetch]', e);
    } finally {
      setLoadingCloud(false);
    }
  };

  useEffect(() => {
    fetchCloudData();
  }, [profileId, hasApiKey, activeSubTab, timeRange]);

  const handleSaveProfile = async () => {
    if (!profileInput.trim()) {
      error('Vui lòng nhập Profile ID NextDNS (6 ký tự)!');
      return;
    }
    try {
      await setNextDnsProfile(profileInput.trim());
      setProfileId(profileInput.trim());
      setIsActive(true);
      setProfileModalOpen(false);
      success('Đã lưu và kích hoạt Profile ID NextDNS thành công!');
      fetchLocalConfig();
    } catch (e: any) {
      error(e?.message || 'Lỗi lưu Profile ID');
    }
  };

  const handleDisable = async () => {
    if (!window.confirm('Bạn có chắc muốn vô hiệu hoá NextDNS trên router?')) return;
    try {
      await disableNextDns();
      setIsActive(false);
      success('Đã tắt NextDNS trên router!');
      fetchLocalConfig();
    } catch (e: any) {
      error(e?.message || 'Lỗi tắt NextDNS');
    }
  };

  const handleSaveApiKey = async () => {
    if (!apiKeyInput.trim()) {
      error('Vui lòng nhập API Key NextDNS!');
      return;
    }
    try {
      await setNextDnsApiKey(apiKeyInput.trim());
      setHasApiKey(true);
      setApiKeyModalOpen(false);
      setApiKeyInput('');
      success('Đã lưu NextDNS API Key thành công!');
      fetchLocalConfig();
    } catch (e: any) {
      error(e?.message || 'Lỗi lưu API Key');
    }
  };

  const handleDelApiKey = async () => {
    if (!window.confirm('Xoá API Key NextDNS khỏi router?')) return;
    try {
      await delNextDnsApiKey();
      setHasApiKey(false);
      setMaskedKey('');
      success('Đã xoá API Key!');
    } catch (e: any) {
      error(e?.message || 'Lỗi xoá API Key');
    }
  };

  const handleSyncIp = async () => {
    try {
      const res = await syncNextDnsIp();
      if (res && res.linked_ip) {
        setLinkedIp(res.linked_ip);
        success(`Đã đồng bộ IP WAN (${res.linked_ip}) với hồ sơ NextDNS!`);
      } else {
        info('Đã gửi yêu cầu đồng bộ IP!');
      }
    } catch (e: any) {
      error(e?.message || 'Lỗi đồng bộ IP');
    }
  };

  // Toggle Services Parental
  const handleToggleService = async (serviceId: string, currentStatus: boolean) => {
    try {
      await proxyNextDnsApi(
        `profiles/${profileId}/parentalcontrol/services/${serviceId}`,
        currentStatus ? 'DELETE' : 'POST'
      );
      setProfileData((prev: any) => {
        const services = prev?.services || [];
        if (currentStatus) {
          return { ...prev, services: services.filter((s: any) => s.id !== serviceId) };
        }
        return { ...prev, services: [...services, { id: serviceId, active: true }] };
      });
      success(`Đã cập nhật chặn dịch vụ "${serviceId}"!`);
    } catch (e: any) {
      error(e?.message || 'Lỗi cập nhật dịch vụ');
    }
  };

  // Toggle Categories Parental
  const handleToggleCategory = async (catId: string, currentStatus: boolean) => {
    try {
      await proxyNextDnsApi(
        `profiles/${profileId}/parentalcontrol/categories/${catId}`,
        currentStatus ? 'DELETE' : 'POST'
      );
      setProfileData((prev: any) => {
        const categories = prev?.categories || [];
        if (currentStatus) {
          return { ...prev, categories: categories.filter((c: any) => c.id !== catId) };
        }
        return { ...prev, categories: [...categories, { id: catId, active: true }] };
      });
      success(`Đã cập nhật chặn danh mục "${catId}"!`);
    } catch (e: any) {
      error(e?.message || 'Lỗi cập nhật danh mục');
    }
  };

  // Toggle Security Feature
  const handleToggleSecurity = async (key: string, currentVal: boolean) => {
    try {
      await proxyNextDnsApi(`profiles/${profileId}/security`, 'PATCH', { [key]: !currentVal });
      setProfileData((prev: any) => ({ ...prev, [key]: !currentVal }));
      success(`Đã cập nhật tính năng an ninh!`);
    } catch (e: any) {
      error(e?.message || 'Lỗi cập nhật an ninh');
    }
  };

  // Add / Remove Custom List Domain
  const handleAddDomain = async () => {
    if (!newDomainInput.trim()) return;
    const domain = newDomainInput.trim().toLowerCase();
    try {
      await proxyNextDnsApi(`profiles/${profileId}/${listType}`, 'POST', { id: domain, active: true });
      if (listType === 'denylist') {
        setDenylist((prev) => [...prev, { id: domain, active: true }]);
      } else {
        setAllowlist((prev) => [...prev, { id: domain, active: true }]);
      }
      setNewDomainInput('');
      success(`Đã thêm "${domain}" vào ${listType === 'denylist' ? 'Danh sách chặn' : 'Danh sách cho phép'}!`);
    } catch (e: any) {
      error(e?.message || 'Lỗi thêm tên miền');
    }
  };

  const handleRemoveDomain = async (type: 'denylist' | 'allowlist', domain: string) => {
    try {
      await proxyNextDnsApi(`profiles/${profileId}/${type}/${encodeURIComponent(domain)}`, 'DELETE');
      if (type === 'denylist') {
        setDenylist((prev) => prev.filter((d) => d.id !== domain));
      } else {
        setAllowlist((prev) => prev.filter((d) => d.id !== domain));
      }
      success(`Đã xoá "${domain}"!`);
    } catch (e: any) {
      error(e?.message || 'Lỗi xoá tên miền');
    }
  };

  // Add / Remove Blocklist
  const handleAddBlocklist = async (id: string) => {
    try {
      await proxyNextDnsApi(`profiles/${profileId}/privacy/blocklists`, 'POST', { id });
      setActiveBlocklists((prev) => [...prev, { id, name: id, entries: 0, updatedOn: '', website: '', description: '' }]);
      success('Đã thêm danh sách chặn vào Profile!');
    } catch (e: any) {
      error(e?.message || 'Lỗi thêm danh sách chặn');
    }
  };

  const handleRemoveBlocklist = async (id: string) => {
    try {
      await proxyNextDnsApi(`profiles/${profileId}/privacy/blocklists/${id}`, 'DELETE');
      setActiveBlocklists((prev) => prev.filter((b) => b.id !== id));
      success('Đã gỡ bỏ danh sách chặn!');
    } catch (e: any) {
      error(e?.message || 'Lỗi gỡ bỏ danh sách chặn');
    }
  };

  const filteredLogs = useMemo(() => {
    let result = logs;
    if (logFilterBlocked) {
      result = result.filter((l) => l.status === 'blocked');
    }
    if (logSearch.trim()) {
      const q = logSearch.toLowerCase();
      result = result.filter((l) => l.domain.toLowerCase().includes(q));
    }
    return result;
  }, [logs, logFilterBlocked, logSearch]);

  const blockRate = analytics?.queries
    ? Math.round(((analytics.blocked || 0) / analytics.queries) * 100)
    : 0;

  return (
    <div className="flex flex-col gap-4">
      {/* Header Profile Info Banner */}
      <div className="vcrt-card p-4 sm:p-5 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div className="flex items-center gap-3.5">
          <div className="w-12 h-12 rounded-2xl bg-blue-500/10 border border-blue-500/30 flex items-center justify-center text-2xl shrink-0">
            🛡️
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h2 className="text-lg font-extrabold text-slate-900 dark:text-slate-100">
                NextDNS Cloud Shield
              </h2>
              <span
                className={`vcrt-badge ${
                  isActive
                    ? 'bg-emerald-100 dark:bg-emerald-950/60 text-emerald-700 dark:text-emerald-300 border border-emerald-300 dark:border-emerald-800'
                    : 'bg-slate-200 dark:bg-slate-700 text-slate-600 dark:text-slate-300'
                }`}
              >
                {isActive ? 'ĐANG BẢO VỆ' : 'ĐÃ TẮT'}
              </span>
            </div>
            <div className="flex items-center gap-3 text-xs text-slate-500 dark:text-slate-400 font-mono mt-1">
              <span>Profile ID: <strong>{profileId || 'Chưa thiết lập'}</strong></span>
              {linkedIp && <span>• IP liên kết: {linkedIp}</span>}
            </div>
          </div>
        </div>

        {/* Quick config buttons */}
        <div className="flex flex-wrap items-center gap-2 self-start sm:self-auto">
          <button
            onClick={() => setProfileModalOpen(true)}
            className="vcrt-btn vcrt-btn-secondary text-xs"
          >
            <span>✏️</span>
            <span>Đổi Profile ID</span>
          </button>

          <button
            onClick={() => setApiKeyModalOpen(true)}
            className="vcrt-btn vcrt-btn-secondary text-xs"
          >
            <span>🔑</span>
            <span>{hasApiKey ? 'Quản lý API Key' : 'Thêm API Key'}</span>
          </button>

          {isActive && (
            <button
              onClick={handleSyncIp}
              className="vcrt-btn vcrt-btn-secondary text-xs"
              title="Đồng bộ IP WAN hiện tại vào NextDNS Linked IP"
            >
              <span>🔄</span>
              <span>Đồng bộ IP</span>
            </button>
          )}

          {isActive && (
            <button
              onClick={handleDisable}
              className="vcrt-btn text-xs text-rose-600 dark:text-rose-400 border border-rose-300 dark:border-rose-800 hover:bg-rose-50"
            >
              <span>⛔</span>
              <span>Tắt</span>
            </button>
          )}
        </div>
      </div>

      {/* Warning if no API Key */}
      {!hasApiKey && (
        <div className="p-4 rounded-2xl bg-blue-50 dark:bg-blue-950/40 border border-blue-200 dark:border-blue-900/60 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3 text-xs">
          <div className="flex items-center gap-2.5 text-blue-900 dark:text-blue-200">
            <span className="text-lg">💡</span>
            <span>
              Cung cấp <strong>API Key</strong> từ NextDNS Account để xem trực tiếp Thống kê, Nhật ký thời gian thực và Bật/Tắt chặn ngay trên VCRT OS.
            </span>
          </div>
          <button
            onClick={() => setApiKeyModalOpen(true)}
            className="vcrt-btn vcrt-btn-primary text-xs py-1.5 px-3 shrink-0"
          >
            Nhập API Key
          </button>
        </div>
      )}

      {/* Sub-tab Navigation */}
      <div className="flex items-center gap-1.5 overflow-x-auto pb-1 scrollbar-none border-b border-slate-200 dark:border-slate-800">
        {[
          { id: 'analytics', label: 'Thống Kê', icon: '📊' },
          { id: 'logs', label: 'Nhật Ký (Logs)', icon: '📋' },
          { id: 'privacy', label: 'Quyền Riêng Tư', icon: '🔏' },
          { id: 'parental', label: 'Kiểm Soát Phụ Huynh', icon: '👨‍👩‍👧' },
          { id: 'security', label: 'Bảo Mật AI', icon: '🔒' },
          { id: 'lists', label: 'Tùy Chỉnh (Lists)', icon: '📝' }
        ].map((tab) => {
          const isSelected = activeSubTab === tab.id;
          return (
            <button
              key={tab.id}
              onClick={() => setActiveSubTab(tab.id as SubTab)}
              className={`flex items-center gap-1.5 px-3.5 py-2 rounded-xl text-xs font-bold transition-all shrink-0 ${
                isSelected
                  ? 'bg-blue-600 text-white shadow-xs'
                  : 'text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-800'
              }`}
            >
              <span>{tab.icon}</span>
              <span>{tab.label}</span>
            </button>
          );
        })}
      </div>

      {/* Sub-tab Content Area */}
      {loadingCloud && (
        <div className="vcrt-card p-12 text-center text-xs text-slate-400 flex flex-col items-center gap-2">
          <span className="text-2xl animate-spin">⏳</span>
          <span>Đang đồng bộ dữ liệu từ NextDNS Cloud...</span>
        </div>
      )}

      {!loadingCloud && activeSubTab === 'analytics' && (
        <div className="flex flex-col gap-4">
          {/* Time range selector */}
          <div className="flex items-center justify-between">
            <span className="text-xs font-semibold text-slate-500">Khoảng thời gian:</span>
            <select
              value={timeRange}
              onChange={(e) => setTimeRange(e.target.value)}
              className="vcrt-input w-40 text-xs py-1"
            >
              {TIME_RANGES.map((t) => (
                <option key={t.id} value={t.id}>
                  {t.label}
                </option>
              ))}
            </select>
          </div>

          {/* Stats Summary Cards */}
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div className="vcrt-card p-4">
              <span className="text-xs text-slate-500 dark:text-slate-400 font-semibold">
                Tổng Truy Vấn DNS
              </span>
              <div className="text-2xl font-black font-mono text-slate-900 dark:text-slate-100 mt-1">
                {(analytics?.queries || 0).toLocaleString()}
              </div>
            </div>
            <div className="vcrt-card p-4">
              <span className="text-xs text-slate-500 dark:text-slate-400 font-semibold">
                Số Lần Bị Chặn
              </span>
              <div className="text-2xl font-black font-mono text-rose-600 dark:text-rose-400 mt-1">
                {(analytics?.blocked || 0).toLocaleString()}
              </div>
            </div>
            <div className="vcrt-card p-4">
              <span className="text-xs text-slate-500 dark:text-slate-400 font-semibold">
                Tỷ Lệ Chặn
              </span>
              <div className="text-2xl font-black font-mono text-blue-600 dark:text-blue-400 mt-1">
                {blockRate}%
              </div>
            </div>
          </div>

          {/* Top Resolved Domains */}
          <div className="vcrt-card p-4 flex flex-col gap-3">
            <h4 className="font-bold text-sm text-slate-900 dark:text-slate-100">
              Tên Miền Truy Vấn Nhiều Nhất
            </h4>
            {resolvedDomains.length === 0 ? (
              <div className="text-center py-6 text-xs text-slate-400">
                Chưa có dữ liệu thống kê tên miền.
              </div>
            ) : (
              <div className="flex flex-col gap-2">
                {resolvedDomains.map((d, i) => (
                  <div
                    key={d.domain}
                    className="flex items-center justify-between p-2.5 rounded-lg bg-slate-50 dark:bg-slate-800/60 text-xs font-mono"
                  >
                    <div className="flex items-center gap-2 truncate">
                      <span className="text-slate-400">{i + 1}.</span>
                      <span className="font-semibold text-slate-800 dark:text-slate-200 truncate">
                        {d.domain}
                      </span>
                    </div>
                    <span className="text-blue-600 dark:text-blue-400 font-bold shrink-0">
                      {d.queries.toLocaleString()} q
                    </span>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      )}

      {!loadingCloud && activeSubTab === 'logs' && (
        <div className="flex flex-col gap-3">
          {/* Search & Filter Header */}
          <div className="flex flex-col sm:flex-row gap-2 items-center justify-between">
            <input
              type="text"
              className="vcrt-input sm:max-w-xs text-xs"
              placeholder="Tìm kiếm domain trong nhật ký..."
              value={logSearch}
              onChange={(e) => setLogSearch(e.target.value)}
            />
            <div className="flex items-center gap-2 self-start sm:self-auto">
              <label className="flex items-center gap-1.5 text-xs text-slate-600 dark:text-slate-400 cursor-pointer">
                <input
                  type="checkbox"
                  checked={logFilterBlocked}
                  onChange={(e) => setLogFilterBlocked(e.target.checked)}
                  className="rounded text-blue-600"
                />
                <span>Chỉ hiện tên miền bị chặn</span>
              </label>
              <button
                onClick={fetchCloudData}
                className="vcrt-btn vcrt-btn-secondary text-xs py-1 px-2.5"
              >
                Làm mới
              </button>
            </div>
          </div>

          {/* Logs table */}
          <div className="vcrt-card overflow-hidden">
            {filteredLogs.length === 0 ? (
              <div className="p-8 text-center text-xs text-slate-400">
                Không có dữ liệu nhật ký phù hợp.
              </div>
            ) : (
              <div className="divide-y divide-slate-100 dark:divide-slate-800 text-xs max-h-[60vh] overflow-y-auto font-mono">
                {filteredLogs.map((log, idx) => {
                  const isBlocked = log.status === 'blocked';
                  return (
                    <div
                      key={idx}
                      className="p-3 flex items-center justify-between gap-3 hover:bg-slate-50 dark:hover:bg-slate-800/50"
                    >
                      <div className="flex items-center gap-2.5 min-w-0">
                        <span
                          className={`w-2 h-2 rounded-full shrink-0 ${
                            isBlocked ? 'bg-rose-500' : 'bg-emerald-500'
                          }`}
                        />
                        <div className="truncate">
                          <span className="font-semibold text-slate-800 dark:text-slate-200">
                            {log.domain}
                          </span>
                          {log.reasons && log.reasons.length > 0 && (
                            <span className="text-[10px] text-rose-500 block truncate font-sans mt-0.5">
                              Chặn bởi: {log.reasons.map((r) => r.name || r.id).join(', ')}
                            </span>
                          )}
                        </div>
                      </div>

                      <div className="flex items-center gap-2 shrink-0 text-[11px] text-slate-400 font-sans">
                        <span>{log.protocol || 'DoH'}</span>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </div>
      )}

      {!loadingCloud && activeSubTab === 'privacy' && (
        <div className="flex flex-col gap-4">
          <div className="flex items-center justify-between">
            <div>
              <h3 className="font-bold text-sm text-slate-900 dark:text-slate-100">
                Danh Sách Chặn Cộng Đồng (Blocklists)
              </h3>
              <p className="text-xs text-slate-400 mt-0.5">
                Các bộ lọc chặn quảng cáo, mã theo dõi và bảo vệ quyền riêng tư
              </p>
            </div>
            <button
              onClick={() => setIsAddBlocklistOpen(true)}
              className="vcrt-btn vcrt-btn-primary text-xs"
            >
              <span>➕</span>
              <span>Thêm Danh Sách</span>
            </button>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            {activeBlocklists.map((b) => (
              <div
                key={b.id}
                className="vcrt-card p-4 flex items-center justify-between gap-3"
              >
                <div>
                  <div className="font-bold text-sm text-slate-900 dark:text-slate-100">
                    {b.name || b.id}
                  </div>
                  {b.entries > 0 && (
                    <span className="text-[10px] text-blue-500 font-mono">
                      {b.entries.toLocaleString()} quy tắc chặn
                    </span>
                  )}
                </div>
                <button
                  onClick={() => handleRemoveBlocklist(b.id)}
                  className="text-xs text-rose-600 dark:text-rose-400 hover:underline shrink-0"
                >
                  Gỡ bỏ
                </button>
              </div>
            ))}
          </div>

          <AddBlocklistModal
            isOpen={isAddBlocklistOpen}
            onClose={() => setIsAddBlocklistOpen(false)}
            availableBlocklists={availableBlocklists}
            activeBlocklistIds={activeBlocklists.map((b) => b.id)}
            onAddBlocklist={handleAddBlocklist}
            onRemoveBlocklist={handleRemoveBlocklist}
          />
        </div>
      )}

      {!loadingCloud && activeSubTab === 'parental' && (
        <div className="flex flex-col gap-6">
          {/* Dịch vụ phổ biến */}
          <div className="flex flex-col gap-3">
            <h3 className="font-bold text-sm text-slate-900 dark:text-slate-100">
              Chặn Dịch Vụ Cụ Thể (Mạng Xã Hội, Game, Phim)
            </h3>
            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-2.5">
              {POPULAR_SERVICES.map((s) => {
                const blocked = !!profileData?.services?.some((item: any) => item.id === s.id);
                return (
                  <button
                    key={s.id}
                    onClick={() => handleToggleService(s.id, blocked)}
                    className={`p-3 rounded-xl border text-left flex items-center justify-between transition-all ${
                      blocked
                        ? 'bg-rose-50 dark:bg-rose-950/40 border-rose-300 dark:border-rose-900 text-rose-800 dark:text-rose-200'
                        : 'bg-white dark:bg-slate-800 border-slate-200 dark:border-slate-700 text-slate-800 dark:text-slate-200 hover:border-slate-300'
                    }`}
                  >
                    <div className="flex items-center gap-2">
                      <span className="text-lg">{s.icon}</span>
                      <span className="text-xs font-bold">{s.name}</span>
                    </div>
                    <span className="text-[10px] font-bold px-1.5 py-0.5 rounded">
                      {blocked ? 'ĐÃ CHẶN' : 'MỞ'}
                    </span>
                  </button>
                );
              })}
            </div>
          </div>

          {/* Danh mục nhạy cảm */}
          <div className="flex flex-col gap-3">
            <h3 className="font-bold text-sm text-slate-900 dark:text-slate-100">
              Chặn Theo Danh Mục Nội Dung
            </h3>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              {CATEGORIES.map((c) => {
                const blocked = !!profileData?.categories?.some((item: any) => item.id === c.id);
                return (
                  <div
                    key={c.id}
                    className="vcrt-card p-4 flex items-center justify-between gap-3"
                  >
                    <div className="flex items-center gap-3">
                      <span className="text-2xl">{c.icon}</span>
                      <div>
                        <div className="font-bold text-sm text-slate-900 dark:text-slate-100">
                          {c.name}
                        </div>
                        <p className="text-xs text-slate-400 mt-0.5">{c.desc}</p>
                      </div>
                    </div>
                    <input
                      type="checkbox"
                      checked={blocked}
                      onChange={() => handleToggleCategory(c.id, blocked)}
                      className="w-5 h-5 rounded text-blue-600 cursor-pointer"
                    />
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      )}

      {!loadingCloud && activeSubTab === 'security' && (
        <div className="flex flex-col gap-3">
          <h3 className="font-bold text-sm text-slate-900 dark:text-slate-100">
            Lá Chắn An Ninh & AI Threat Detection
          </h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            {SECURITY_FEATURES.map((f) => {
              const enabled = !!profileData?.[f.key];
              return (
                <div
                  key={f.key}
                  className="vcrt-card p-4 flex items-center justify-between gap-3"
                >
                  <div className="flex items-center gap-3">
                    <span className="text-2xl">{f.icon}</span>
                    <div>
                      <div className="font-bold text-sm text-slate-900 dark:text-slate-100">
                        {f.name}
                      </div>
                      <p className="text-xs text-slate-400 mt-0.5">{f.desc}</p>
                    </div>
                  </div>
                  <input
                    type="checkbox"
                    checked={enabled}
                    onChange={() => handleToggleSecurity(f.key, enabled)}
                    className="w-5 h-5 rounded text-blue-600 cursor-pointer"
                  />
                </div>
              );
            })}
          </div>
        </div>
      )}

      {!loadingCloud && activeSubTab === 'lists' && (
        <div className="flex flex-col gap-4">
          {/* Add custom domain */}
          <div className="vcrt-card p-4 flex flex-col sm:flex-row gap-2">
            <select
              value={listType}
              onChange={(e) => setListType(e.target.value as any)}
              className="vcrt-input sm:w-48 text-xs font-semibold"
            >
              <option value="denylist">⛔ Chặn (Denylist)</option>
              <option value="allowlist">✅ Cho phép (Allowlist)</option>
            </select>
            <input
              type="text"
              value={newDomainInput}
              onChange={(e) => setNewDomainInput(e.target.value)}
              placeholder="Nhập tên miền (vd: example.com hoặc *.ads.com)..."
              className="vcrt-input flex-1 text-xs font-mono"
            />
            <button
              onClick={handleAddDomain}
              className="vcrt-btn vcrt-btn-primary text-xs shrink-0"
            >
              Thêm Tên Miền
            </button>
          </div>

          {/* Current lists side by side */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            {/* Denylist */}
            <div className="vcrt-card p-4 flex flex-col gap-3">
              <h4 className="font-bold text-sm text-rose-600 dark:text-rose-400 flex items-center gap-1.5">
                <span>⛔</span> Danh Sách Chặn Riêng ({denylist.length})
              </h4>
              <div className="flex flex-col gap-1.5 max-h-80 overflow-y-auto pr-1">
                {denylist.length === 0 ? (
                  <div className="text-xs text-slate-400 py-4 text-center">Chưa có tên miền chặn</div>
                ) : (
                  denylist.map((d) => (
                    <div
                      key={d.id}
                      className="flex items-center justify-between p-2 rounded-lg bg-slate-50 dark:bg-slate-800/60 text-xs font-mono"
                    >
                      <span className="truncate text-slate-800 dark:text-slate-200">{d.id}</span>
                      <button
                        onClick={() => handleRemoveDomain('denylist', d.id)}
                        className="text-rose-500 hover:text-rose-700 ml-2"
                      >
                        ✕
                      </button>
                    </div>
                  ))
                )}
              </div>
            </div>

            {/* Allowlist */}
            <div className="vcrt-card p-4 flex flex-col gap-3">
              <h4 className="font-bold text-sm text-emerald-600 dark:text-emerald-400 flex items-center gap-1.5">
                <span>✅</span> Danh Sách Cho Phép (Ngoại lệ) ({allowlist.length})
              </h4>
              <div className="flex flex-col gap-1.5 max-h-80 overflow-y-auto pr-1">
                {allowlist.length === 0 ? (
                  <div className="text-xs text-slate-400 py-4 text-center">Chưa có tên miền ngoại lệ</div>
                ) : (
                  allowlist.map((d) => (
                    <div
                      key={d.id}
                      className="flex items-center justify-between p-2 rounded-lg bg-slate-50 dark:bg-slate-800/60 text-xs font-mono"
                    >
                      <span className="truncate text-slate-800 dark:text-slate-200">{d.id}</span>
                      <button
                        onClick={() => handleRemoveDomain('allowlist', d.id)}
                        className="text-rose-500 hover:text-rose-700 ml-2"
                      >
                        ✕
                      </button>
                    </div>
                  ))
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Modal Profile ID */}
      <Modal
        isOpen={profileModalOpen}
        onClose={() => setProfileModalOpen(false)}
        title="Cấu Hình NextDNS Profile ID"
        footer={
          <>
            <button
              onClick={() => setProfileModalOpen(false)}
              className="vcrt-btn vcrt-btn-secondary text-xs"
            >
              Hủy
            </button>
            <button
              onClick={handleSaveProfile}
              className="vcrt-btn vcrt-btn-primary text-xs"
            >
              Lưu & Kích Hoạt
            </button>
          </>
        }
      >
        <div className="flex flex-col gap-3 text-xs">
          <p className="text-slate-600 dark:text-slate-400">
            Nhập <strong>Profile ID</strong> (chuỗi 6 ký tự hex, vd: <code>2512a8</code>) tạo từ tài khoản NextDNS của bạn:
          </p>
          <input
            type="text"
            maxLength={10}
            className="vcrt-input font-mono text-base uppercase"
            placeholder="vd: 2512A8"
            value={profileInput}
            onChange={(e) => setProfileInput(e.target.value)}
            autoFocus
          />
        </div>
      </Modal>

      {/* Modal API Key */}
      <Modal
        isOpen={apiKeyModalOpen}
        onClose={() => setApiKeyModalOpen(false)}
        title="Quản Lý NextDNS API Key"
        footer={
          <>
            {hasApiKey && (
              <button
                onClick={handleDelApiKey}
                className="vcrt-btn bg-rose-600 text-white text-xs mr-auto"
              >
                Xoá API Key
              </button>
            )}
            <button
              onClick={() => setApiKeyModalOpen(false)}
              className="vcrt-btn vcrt-btn-secondary text-xs"
            >
              Hủy
            </button>
            <button
              onClick={handleSaveApiKey}
              className="vcrt-btn vcrt-btn-primary text-xs"
            >
              Lưu Khóa
            </button>
          </>
        }
      >
        <div className="flex flex-col gap-3 text-xs">
          {hasApiKey && maskedKey && (
            <div className="p-2.5 rounded-lg bg-slate-50 dark:bg-slate-700/50 font-mono text-emerald-600 dark:text-emerald-400">
              Đang sử dụng: {maskedKey}
            </div>
          )}
          <p className="text-slate-600 dark:text-slate-400">
            Lấy API Key tại <strong>NextDNS Account → API Keys</strong> để router có quyền truy vấn dữ liệu từ NextDNS Cloud:
          </p>
          <input
            type="password"
            className="vcrt-input font-mono"
            placeholder="Nhập API Key mới..."
            value={apiKeyInput}
            onChange={(e) => setApiKeyInput(e.target.value)}
          />
        </div>
      </Modal>
    </div>
  );
}
