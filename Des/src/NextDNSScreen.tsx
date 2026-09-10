import { useState, useEffect, useMemo, useRef } from "react";
import { fetchApi, postApi } from "./api";
import AddBlocklistModal, { CommunityBlocklist } from "./AddBlocklistModal";

const POPULAR_SERVICES = [
  { id: "tiktok", name: "TikTok", icon: "📱", color: "#EE1D52" },
  { id: "facebook", name: "Facebook", icon: "👥", color: "#1877F2" },
  { id: "youtube", name: "YouTube", icon: "▶️", color: "#FF0000" },
  { id: "instagram", name: "Instagram", icon: "📷", color: "#E4405F" },
  { id: "roblox", name: "Roblox", icon: "🎮", color: "#E02424" },
  { id: "discord", name: "Discord", icon: "💬", color: "#5865F2" },
  { id: "steam", name: "Steam", icon: "🕹️", color: "#1B2838" },
  { id: "tinder", name: "Tinder", icon: "🔥", color: "#FE3C72" },
  { id: "netflix", name: "Netflix", icon: "🎬", color: "#E50914" },
  { id: "telegram", name: "Telegram", icon: "✈️", color: "#229ED9" },
  { id: "twitch", name: "Twitch", icon: "👾", color: "#9146FF" },
  { id: "spotify", name: "Spotify", icon: "🎵", color: "#1DB954" },
];

const CATEGORIES = [
  { id: "porn", name: "Web người lớn (Porn)", desc: "Chặn nội dung khiêu dâm, 18+", icon: "🔞" },
  { id: "gambling", name: "Cờ bạc & Cá độ", desc: "Chặn các trang cá cược, sòng bạc trực tuyến", icon: "🎲" },
  { id: "piracy", name: "Trang web lậu", desc: "Chặn torrent, web phim lậu vi phạm bản quyền", icon: "🏴‍☠️" },
  { id: "dating", name: "Hẹn hò", desc: "Chặn các ứng dụng và trang web tìm bạn hẹn hò", icon: "💘" },
  { id: "social-networks", name: "Mạng xã hội", desc: "Chặn toàn bộ các trang mạng xã hội", icon: "🌐" },
  { id: "online-gaming", name: "Game online", desc: "Chặn truy cập máy chủ trò chơi trực tuyến", icon: "🎯" },
];

const SECURITY_FEATURES = [
  { key: "aiThreatDetection", name: "Phát hiện hiểm họa bằng AI", desc: "Chặn các mối đe dọa mạng bằng mô hình học máy thời gian thực", icon: "🤖" },
  { key: "threatIntelligenceFeeds", name: "Tình báo mối đe dọa", desc: "Cập nhật liên tục từ hàng chục nguồn an ninh mạng toàn cầu", icon: "🛡️" },
  { key: "googleSafeBrowsing", name: "Google Safe Browsing", desc: "Bảo vệ khỏi các trang web lừa đảo và mã độc theo dữ liệu Google", icon: "🌐" },
  { key: "cryptojacking", name: "Chống đào tiền ảo ẩn", desc: "Chặn mã độc tự ý dùng CPU thiết bị để đào coin trái phép", icon: "⛏️" },
  { key: "typosquatting", name: "Chống lừa đảo tên miền giả", desc: "Bảo vệ khi gõ nhầm tên miền ngân hàng, mua sắm (như paypa1.com)", icon: "🎭" },
  { key: "dnsRebinding", name: "Chống tấn công DNS Rebinding", desc: "Ngăn chặn hacker xâm nhập router và thiết bị smart home qua web", icon: "🔒" },
];

const TIME_RANGES = [
  { id: "-30m", label: "Last 30 minutes" },
  { id: "-6h", label: "Last 6 hours" },
  { id: "-24h", label: "Last 24 hours" },
  { id: "-7d", label: "Last 7 days" },
  { id: "-30d", label: "Last 30 days" },
  { id: "-3M", label: "Last 3 months" },
];

function formatTimeAgo(isoString: string): string {
  if (!isoString) return "";
  try {
    const d = new Date(isoString);
    const now = new Date();
    const diffSec = Math.floor((now.getTime() - d.getTime()) / 1000);
    if (diffSec < 5) return "a few seconds ago";
    if (diffSec < 60) return `${diffSec} seconds ago`;
    const diffMin = Math.floor(diffSec / 60);
    if (diffMin < 60) return `${diffMin} minutes ago`;
    const diffHr = Math.floor(diffMin / 60);
    if (diffHr < 24) return `${diffHr} hours ago`;
    const diffDays = Math.floor(diffHr / 24);
    return `${diffDays} days ago`;
  } catch {
    return "";
  }
}

interface NextDNSLog {
  timestamp: string;
  domain: string;
  root?: string;
  tracker?: string;
  protocol?: string;
  clientIp?: string;
  status: "default" | "blocked" | string;
  reasons?: { id: string; name: string }[];
}

export default function NextDNSScreen() {
  const [profileId, setProfileId] = useState("");
  const [isActive, setIsActive] = useState(false);
  const [saving, setSaving] = useState(false);
  const [saveSuccess, setSaveSuccess] = useState(false);
  const [showEditId, setShowEditId] = useState(false);
  const [showFullProfileId, setShowFullProfileId] = useState(false);
  const [showRawApiKey, setShowRawApiKey] = useState(false);

  // API Key & Cloud State
  const [hasApiKey, setHasApiKey] = useState(false);
  const [apiKeyInput, setApiKeyInput] = useState("");
  const [maskedKey, setMaskedKey] = useState("");
  const [linkedIp, setLinkedIp] = useState("");
  const [showApiKeyModal, setShowApiKeyModal] = useState(false);

  // Sub-tabs: analytics | logs | privacy | parental | security | lists
  const [activeSubTab, setActiveSubTab] = useState<
    "analytics" | "logs" | "privacy" | "parental" | "security" | "lists"
  >("analytics");

  // Time Range Selector for Analytics (Matching Image 3)
  const [timeRange, setTimeRange] = useState("-30d");
  const [showTimeDropdown, setShowTimeDropdown] = useState(false);
  const timeDropdownRef = useRef<HTMLDivElement>(null);

  // Cloud Data
  const [loadingCloud, setLoadingCloud] = useState(false);
  const [analytics, setAnalytics] = useState<{ queries: number; blocked: number } | null>(null);
  const [resolvedDomains, setResolvedDomains] = useState<{ domain: string; queries: number }[]>([]);
  const [blockedDomains, setBlockedDomains] = useState<{ domain: string; queries: number; tracker?: string }[]>([]);
  const [reasons, setReasons] = useState<{ id: string; name: string; queries: number }[]>([]);
  const [protocols, setProtocols] = useState<{ protocol: string; queries: number }[]>([]);
  const [dnssec, setDnssec] = useState<{ validated: boolean; queries: number }[]>([]);
  const [devices, setDevices] = useState<{ id: string; queries: number }[]>([]);
  const [isRootDomains, setIsRootDomains] = useState(false);
  const [showAllDomains, setShowAllDomains] = useState(false);
  const [profileData, setProfileData] = useState<any>(null);
  const [denylist, setDenylist] = useState<{ id: string; active: boolean }[]>([]);
  const [allowlist, setAllowlist] = useState<{ id: string; active: boolean }[]>([]);
  const [newDomainInput, setNewDomainInput] = useState("");
  const [listType, setListType] = useState<"denylist" | "allowlist">("denylist");
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  // Blocklists State (Matching Image 2)
  const [activeBlocklists, setActiveBlocklists] = useState<CommunityBlocklist[]>([]);
  const [availableBlocklists, setAvailableBlocklists] = useState<CommunityBlocklist[]>([]);
  const [isAddBlocklistOpen, setIsAddBlocklistOpen] = useState(false);

  // Logs State (Matching Image 1)
  const [logs, setLogs] = useState<NextDNSLog[]>([]);
  const [logSearch, setLogSearch] = useState("");
  const [logDevice, setLogDevice] = useState("all");
  const [logFilterBlocked, setLogFilterBlocked] = useState(false);
  const [fetchingLogs, setFetchingLogs] = useState(false);
  const [logMenuOpenId, setLogMenuOpenId] = useState<string | null>(null);

  // Close time dropdown on outside click
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (timeDropdownRef.current && !timeDropdownRef.current.contains(event.target as Node)) {
        setShowTimeDropdown(false);
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  const handleSyncIp = async () => {
    setActionLoading("sync_ip");
    try {
      const res = await fetchApi("nextdns_sync_ip");
      if (res && res.linked_ip) {
        setLinkedIp(res.linked_ip);
      }
    } catch (e) {
      console.error(e);
    } finally {
      setActionLoading(null);
    }
  };

  const fetchNextDns = async () => {
    const res = await fetchApi("nextdns_get");
    if (res) {
      if (res.profile_id) setProfileId(res.profile_id);
      setIsActive(!!res.active);
      setHasApiKey(!!res.has_api_key);
      if (res.masked_api_key) setMaskedKey(res.masked_api_key);
      if (res.linked_ip) setLinkedIp(res.linked_ip);
    }
  };

  // Fetch Full Analytics (Status, Domains, Reasons, Protocols, DNSSEC, Devices)
  const fetchAnalytics = async (prof = profileId, tf = timeRange, root = isRootDomains) => {
    if (!prof) return;
    try {
      const rootParam = root ? "&root=true" : "";
      const [aRes, rRes, bRes, reasonsRes, protoRes, secRes, devRes] = await Promise.all([
        fetchApi("nextdns_proxy", { endpoint: `profiles/${prof}/analytics/status?from=${tf}` }),
        fetchApi("nextdns_proxy", { endpoint: `profiles/${prof}/analytics/domains?status=default${rootParam}&from=${tf}&limit=30` }),
        fetchApi("nextdns_proxy", { endpoint: `profiles/${prof}/analytics/domains?status=blocked${rootParam}&from=${tf}&limit=30` }),
        fetchApi("nextdns_proxy", { endpoint: `profiles/${prof}/analytics/reasons?from=${tf}` }),
        fetchApi("nextdns_proxy", { endpoint: `profiles/${prof}/analytics/protocols?from=${tf}` }),
        fetchApi("nextdns_proxy", { endpoint: `profiles/${prof}/analytics/dnssec?from=${tf}` }),
        fetchApi("nextdns_proxy", { endpoint: `profiles/${prof}/analytics/devices?from=${tf}` }),
      ]);

      if (aRes && Array.isArray(aRes.data)) {
        let defQ = 0;
        let blkQ = 0;
        for (const item of aRes.data) {
          if (item.status === "blocked") blkQ = Number(item.queries) || 0;
          else defQ += Number(item.queries) || 0;
        }
        setAnalytics({ queries: defQ + blkQ, blocked: blkQ });
      }
      if (rRes && Array.isArray(rRes.data)) setResolvedDomains(rRes.data);
      if (bRes && Array.isArray(bRes.data)) setBlockedDomains(bRes.data);
      if (reasonsRes && Array.isArray(reasonsRes.data)) setReasons(reasonsRes.data);
      if (protoRes && Array.isArray(protoRes.data)) setProtocols(protoRes.data);
      if (secRes && Array.isArray(secRes.data)) setDnssec(secRes.data);
      if (devRes && Array.isArray(devRes.data)) setDevices(devRes.data);
    } catch (e) {
      console.error(e);
    }
  };

  // Fetch Logs (Image 1)
  const fetchLogs = async (prof = profileId) => {
    if (!prof) return;
    setFetchingLogs(true);
    try {
      const lRes = await fetchApi("nextdns_proxy", {
        endpoint: `profiles/${prof}/logs`
      });
      if (lRes && Array.isArray(lRes.data)) {
        setLogs(lRes.data);
      }
    } catch (e) {
      console.error(e);
    } finally {
      setFetchingLogs(false);
    }
  };

  // Fetch Blocklists (Image 2)
  const fetchBlocklists = async (prof = profileId) => {
    if (!prof) return;
    try {
      const [curRes, libRes] = await Promise.all([
        fetchApi("nextdns_proxy", { endpoint: `profiles/${prof}/privacy/blocklists` }),
        fetchApi("nextdns_proxy", { endpoint: "privacy/blocklists" })
      ]);
      if (curRes && Array.isArray(curRes.data)) {
        setActiveBlocklists(curRes.data);
      }
      if (libRes && Array.isArray(libRes.data)) {
        setAvailableBlocklists(libRes.data);
      }
    } catch (e) {
      console.error(e);
    }
  };

  const fetchCloudData = async (prof = profileId) => {
    if (!prof) return;
    setLoadingCloud(true);
    try {
      // 1. Fetch Profile info
      const pRes = await fetchApi("nextdns_proxy", { endpoint: `profiles/${prof}` });
      if (pRes && pRes.data) {
        setProfileData(pRes.data);
      }

      // 2. Fetch Analytics
      await fetchAnalytics(prof, timeRange);

      // 3. Fetch Denylist & Allowlist
      const [dRes, alRes] = await Promise.all([
        fetchApi("nextdns_proxy", { endpoint: `profiles/${prof}/denylist` }),
        fetchApi("nextdns_proxy", { endpoint: `profiles/${prof}/allowlist` })
      ]);
      if (dRes && Array.isArray(dRes.data)) setDenylist(dRes.data);
      if (alRes && Array.isArray(alRes.data)) setAllowlist(alRes.data);

      // 4. Fetch Blocklists
      await fetchBlocklists(prof);

      // 5. Fetch Logs if on logs tab
      if (activeSubTab === "logs") {
        await fetchLogs(prof);
      }
    } catch (e) {
      console.error(e);
    } finally {
      setLoadingCloud(false);
    }
  };

  useEffect(() => {
    fetchNextDns();
    const id = setInterval(fetchNextDns, 4000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    if (isActive && hasApiKey && profileId) {
      fetchCloudData(profileId);
    }
  }, [isActive, hasApiKey, profileId]);

  // When timeRange changes, refetch analytics
  useEffect(() => {
    if (isActive && hasApiKey && profileId) {
      fetchAnalytics(profileId, timeRange);
    }
  }, [timeRange]);

  // Auto-refresh logs every 3.5 seconds when on Logs tab
  useEffect(() => {
    if (activeSubTab === "logs" && isActive && hasApiKey && profileId) {
      fetchLogs(profileId);
      const timer = setInterval(() => {
        fetchLogs(profileId);
      }, 3500);
      return () => clearInterval(timer);
    }
  }, [activeSubTab, isActive, hasApiKey, profileId]);

  // When switching to Privacy tab, ensure blocklists are fresh
  useEffect(() => {
    if (activeSubTab === "privacy" && isActive && hasApiKey && profileId) {
      fetchBlocklists(profileId);
    }
  }, [activeSubTab, isActive, hasApiKey, profileId]);

  const handleSaveProfile = async () => {
    if (!profileId.trim()) {
      alert("Vui lòng nhập Profile ID của NextDNS (6 ký tự)!");
      return;
    }
    setSaving(true);
    await postApi("nextdns_set", { profile: profileId.trim() });
    setSaving(false);
    setSaveSuccess(true);
    setShowEditId(false);
    setTimeout(() => {
      setSaveSuccess(false);
      fetchNextDns();
    }, 1500);
  };

  const handleDisable = async () => {
    if (confirm("Bạn có chắc chắn muốn TẮT NextDNS và khôi phục DNS mặc định của nhà mạng?")) {
      setSaving(true);
      await postApi("nextdns_disable");
      setSaving(false);
      fetchNextDns();
    }
  };

  const handleSaveApiKey = async () => {
    if (!apiKeyInput.trim()) {
      alert("Vui lòng nhập API Key!");
      return;
    }
    setSaving(true);
    await postApi("nextdns_apikey_set", { api_key: apiKeyInput.trim() });
    setSaving(false);
    setShowApiKeyModal(false);
    setApiKeyInput("");
    await fetchNextDns();
    if (profileId) fetchCloudData(profileId);
  };

  const handleDeleteApiKey = async () => {
    if (confirm("Bạn có chắc muốn ngắt kết nối API Key NextDNS khỏi router?")) {
      await postApi("nextdns_apikey_del");
      setHasApiKey(false);
      setProfileData(null);
      setAnalytics(null);
      setResolvedDomains([]);
      setBlockedDomains([]);
      setLogs([]);
      setActiveBlocklists([]);
    }
  };

  // Toggle App (Parental Control Service)
  const handleToggleService = async (serviceId: string, currentActive: boolean) => {
    setActionLoading(`svc_${serviceId}`);
    try {
      if (!currentActive) {
        await postApi(
          "nextdns_proxy",
          { endpoint: `profiles/${profileId}/parentalControl/services`, method: "POST" },
          { id: serviceId, active: true }
        );
      } else {
        await postApi(
          "nextdns_proxy",
          { endpoint: `profiles/${profileId}/parentalControl/services/${serviceId}`, method: "DELETE" }
        );
      }
      setProfileData((prev: any) => {
        if (!prev) return prev;
        const currentServices = prev.parentalControl?.services || [];
        let updated;
        if (!currentActive) {
          updated = [...currentServices.filter((s: any) => s.id !== serviceId), { id: serviceId, active: true }];
        } else {
          updated = currentServices.filter((s: any) => s.id !== serviceId);
        }
        return { ...prev, parentalControl: { ...prev.parentalControl, services: updated } };
      });
    } catch (e) {
      console.error(e);
    } finally {
      setActionLoading(null);
    }
  };

  // Toggle Category (Parental Control)
  const handleToggleCategory = async (catId: string, currentActive: boolean) => {
    setActionLoading(`cat_${catId}`);
    try {
      if (!currentActive) {
        await postApi(
          "nextdns_proxy",
          { endpoint: `profiles/${profileId}/parentalControl/categories`, method: "POST" },
          { id: catId, active: true }
        );
      } else {
        await postApi(
          "nextdns_proxy",
          { endpoint: `profiles/${profileId}/parentalControl/categories/${catId}`, method: "DELETE" }
        );
      }
      setProfileData((prev: any) => {
        if (!prev) return prev;
        const currentCats = prev.parentalControl?.categories || [];
        let updated;
        if (!currentActive) {
          updated = [...currentCats.filter((c: any) => c.id !== catId), { id: catId, active: true }];
        } else {
          updated = currentCats.filter((c: any) => c.id !== catId);
        }
        return { ...prev, parentalControl: { ...prev.parentalControl, categories: updated } };
      });
    } catch (e) {
      console.error(e);
    } finally {
      setActionLoading(null);
    }
  };

  // Toggle Parental Flag
  const handleToggleParentalFlag = async (flag: "safeSearch" | "youtubeRestrictedMode", currentVal: boolean) => {
    setActionLoading(flag);
    try {
      await postApi(
        "nextdns_proxy",
        { endpoint: `profiles/${profileId}/parentalControl`, method: "PATCH" },
        { [flag]: !currentVal }
      );
      setProfileData((prev: any) => ({
        ...prev,
        parentalControl: { ...prev?.parentalControl, [flag]: !currentVal }
      }));
    } catch (e) {
      console.error(e);
    } finally {
      setActionLoading(null);
    }
  };

  // Toggle Security Feature
  const handleToggleSecurity = async (key: string, currentVal: boolean) => {
    setActionLoading(`sec_${key}`);
    try {
      await postApi(
        "nextdns_proxy",
        { endpoint: `profiles/${profileId}/security`, method: "PATCH" },
        { [key]: !currentVal }
      );
      setProfileData((prev: any) => ({
        ...prev,
        security: { ...prev?.security, [key]: !currentVal }
      }));
    } catch (e) {
      console.error(e);
    } finally {
      setActionLoading(null);
    }
  };

  // Add Blocklist (Image 2)
  const handleAddBlocklist = async (id: string) => {
    await postApi(
      "nextdns_proxy",
      { endpoint: `profiles/${profileId}/privacy/blocklists`, method: "POST" },
      { id }
    );
    await fetchBlocklists(profileId);
  };

  // Remove Blocklist (Image 2)
  const handleRemoveBlocklist = async (id: string) => {
    await postApi(
      "nextdns_proxy",
      { endpoint: `profiles/${profileId}/privacy/blocklists/${id}`, method: "DELETE" }
    );
    await fetchBlocklists(profileId);
  };

  // Add Domain to Denylist / Allowlist
  const handleAddDomain = async (targetType?: "denylist" | "allowlist", domainToAdd?: string) => {
    const t = targetType || listType;
    const domain = (domainToAdd || newDomainInput).trim().toLowerCase();
    if (!domain) return;
    setActionLoading(`add_${domain}`);
    try {
      await postApi(
        "nextdns_proxy",
        { endpoint: `profiles/${profileId}/${t}`, method: "POST" },
        { id: domain, active: true }
      );
      if (t === "denylist") {
        setDenylist((prev) => [...prev.filter((d) => d.id !== domain), { id: domain, active: true }]);
      } else {
        setAllowlist((prev) => [...prev.filter((d) => d.id !== domain), { id: domain, active: true }]);
      }
      if (!domainToAdd) setNewDomainInput("");
      setLogMenuOpenId(null);
    } catch (e) {
      console.error(e);
    } finally {
      setActionLoading(null);
    }
  };

  // Delete Domain from Denylist / Allowlist
  const handleDeleteDomain = async (type: "denylist" | "allowlist", domain: string) => {
    setActionLoading(`del_${domain}`);
    try {
      await postApi(
        "nextdns_proxy",
        { endpoint: `profiles/${profileId}/${type}/${domain}`, method: "DELETE" }
      );
      if (type === "denylist") {
        setDenylist((prev) => prev.filter((d) => d.id !== domain));
      } else {
        setAllowlist((prev) => prev.filter((d) => d.id !== domain));
      }
    } catch (e) {
      console.error(e);
    } finally {
      setActionLoading(null);
    }
  };

  // Filtered logs
  const filteredLogs = useMemo(() => {
    return logs.filter((l) => {
      if (logDevice !== "all" && l.clientIp !== logDevice) return false;
      if (logFilterBlocked && l.status !== "blocked" && !(l.reasons && l.reasons.length > 0)) return false;
      if (logSearch.trim()) {
        const q = logSearch.toLowerCase();
        return (
          l.domain.toLowerCase().includes(q) ||
          (l.clientIp && l.clientIp.includes(q)) ||
          (l.tracker && l.tracker.toLowerCase().includes(q))
        );
      }
      return true;
    });
  }, [logs, logDevice, logFilterBlocked, logSearch]);

  // Unique devices from logs for device selector dropdown (Image 1)
  const uniqueDevices = useMemo(() => {
    const devs = new Set<string>();
    logs.forEach((l) => {
      if (l.clientIp) devs.add(l.clientIp);
    });
    return Array.from(devs);
  }, [logs]);

  const totalQueries = analytics?.queries || 0;
  const blockedQueries = analytics?.blocked || 0;
  const blockRate = totalQueries > 0 ? ((blockedQueries / totalQueries) * 100).toFixed(2) : "0.00";
  const activeBlocklistIds = useMemo(() => activeBlocklists.map((b) => b.id), [activeBlocklists]);
  const currentTimeLabel = TIME_RANGES.find((t) => t.id === timeRange)?.label || "Last 30 days";

  return (
    <div className="flex flex-col gap-3 p-4 mb-nav">
      {/* Header */}
      <div className="pt-1 flex items-center justify-between">
        <div>
          <div style={{ fontSize: 13, color: "var(--text-muted)", fontWeight: 500 }}>TRUNG TÂM BẢO VỆ INTERNET</div>
          <div style={{ fontSize: 22, fontWeight: 700, color: "var(--text-primary)" }}>NextDNS Bảo Mật</div>
        </div>
        <div className="flex items-center gap-2">
          {hasApiKey && (
            <button
              onClick={() => fetchCloudData()}
              disabled={loadingCloud}
              className="touch-btn"
              style={{
                background: "var(--bg-card)",
                border: "1px solid var(--border-color)",
                borderRadius: 10,
                padding: "8px 12px",
                color: "#38BDF8",
                fontSize: 12,
                fontWeight: 600
              }}
            >
              {loadingCloud ? "Đang tải..." : "Đồng bộ ⟳"}
            </button>
          )}
          <button
            onClick={fetchNextDns}
            className="touch-btn"
            style={{
              background: "var(--bg-card)",
              border: "1px solid var(--border-color)",
              borderRadius: 10,
              padding: "8px 12px",
              color: "#3B82F6",
              fontSize: 12,
              fontWeight: 600
            }}
          >
            Làm mới ⟳
          </button>
        </div>
      </div>

      {isActive ? (
        <div className="flex flex-col gap-3">
          {/* Header Card: Trạng thái & Profile ID */}
          <div
            style={{
              background: "linear-gradient(135deg, rgba(16, 185, 129, 0.15) 0%, rgba(15, 23, 42, 0.8) 100%)",
              border: "1px solid rgba(16, 185, 129, 0.4)",
              borderRadius: 16,
              padding: 16
            }}
          >
            <div className="flex items-center justify-between mb-3">
              <div className="flex items-center gap-2">
                <span
                  className="pulse-dot"
                  style={{ width: 12, height: 12, borderRadius: "50%", background: "#10B981", display: "inline-block" }}
                />
                <span style={{ fontSize: 15, fontWeight: 700, color: "#10B981" }}>
                  NextDNS Đang Bảo Vệ Toàn Bộ Mạng
                </span>
              </div>
              <span
                style={{
                  background: "rgba(16, 185, 129, 0.2)",
                  color: "#10B981",
                  border: "1px solid rgba(16, 185, 129, 0.4)",
                  padding: "3px 8px",
                  borderRadius: 8,
                  fontSize: 11,
                  fontWeight: 700
                }}
              >
                dnsmasq Native
              </span>
            </div>

            <div style={{ background: "var(--bg-canvas)", borderRadius: 12, padding: 12, border: "1px solid var(--border-color)", marginBottom: 12 }}>
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <span style={{ fontSize: 12, color: "var(--text-subtle)" }}>Profile ID:</span>
                  <span style={{ fontSize: 18, fontWeight: 800, color: "#38BDF8", fontFamily: "JetBrains Mono, monospace" }}>
                    {showFullProfileId
                      ? (profileId || "")
                      : (profileId ? profileId.slice(0, 2) + "••••" : "")}
                  </span>
                  {profileId && (
                    <button
                      type="button"
                      onClick={() => setShowFullProfileId(!showFullProfileId)}
                      style={{ background: "transparent", border: "none", color: "var(--text-muted)", cursor: "pointer", fontSize: 13 }}
                      title={showFullProfileId ? "Ẩn ID" : "Hiện ID đầy đủ"}
                    >
                      {showFullProfileId ? "🙈" : "👁"}
                    </button>
                  )}
                </div>
                <button
                  onClick={() => setShowEditId(!showEditId)}
                  style={{ background: "var(--bg-card-subtle)", border: "none", color: "var(--text-muted)", fontSize: 12, padding: "5px 10px", borderRadius: 8, cursor: "pointer" }}
                >
                  {showEditId ? "Hủy" : "Đổi ID ✎"}
                </button>
              </div>

              {showEditId && (
                <div style={{ marginTop: 10, display: "flex", gap: 8 }}>
                  <input
                    value={profileId}
                    onChange={(e) => setProfileId(e.target.value)}
                    placeholder="Nhập ID mới"
                    style={{
                      flex: 1,
                      background: "var(--bg-card)",
                      border: "1px solid var(--border-color)",
                      borderRadius: 8,
                      padding: "6px 10px",
                      color: "#10B981",
                      fontSize: 13,
                      fontWeight: 700,
                      outline: "none",
                      fontFamily: "JetBrains Mono, monospace"
                    }}
                  />
                  <button
                    onClick={handleSaveProfile}
                    disabled={saving}
                    style={{ background: "#10B981", color: "#fff", border: "none", padding: "6px 12px", borderRadius: 8, fontSize: 12, fontWeight: 700 }}
                  >
                    {saving ? "..." : "Lưu"}
                  </button>
                </div>
              )}

              {/* IP công cộng liên kết */}
              <div className="flex items-center justify-between mt-2 pt-2 border-t border-[#1E293B]">
                <div className="flex items-center gap-1.5 flex-wrap">
                  <span style={{ fontSize: 11, color: "var(--text-subtle)" }}>IP công cộng:</span>
                  <span style={{ fontSize: 12, fontWeight: 700, color: "#10B981", fontFamily: "JetBrains Mono, monospace" }}>
                    {linkedIp || ""}
                  </span>
                  <span style={{ fontSize: 10, color: "#10B981", background: "rgba(16, 185, 129, 0.15)", padding: "1px 6px", borderRadius: 4, fontWeight: 600 }}>
                    Đã liên kết NextDNS 🟢
                  </span>
                </div>
                <button
                  onClick={handleSyncIp}
                  disabled={actionLoading === "sync_ip"}
                  style={{
                    background: "var(--bg-card-subtle)",
                    border: "1px solid var(--border-color)",
                    color: "#38BDF8",
                    fontSize: 11,
                    padding: "4px 8px",
                    borderRadius: 6,
                    cursor: "pointer",
                    fontWeight: 600
                  }}
                  title="Đồng bộ IP mạng của router với NextDNS để đảm bảo các bộ lọc luôn có hiệu lực"
                >
                  {actionLoading === "sync_ip" ? "Đang đồng bộ..." : "Đồng bộ IP ⚡"}
                </button>
              </div>
            </div>

            {/* Trạng thái API Key */}
            <div className="flex items-center justify-between pt-1">
              <div className="flex items-center gap-2">
                <span style={{ fontSize: 14 }}>🔑</span>
                <span style={{ fontSize: 12, color: hasApiKey ? "#10B981" : "#F59E0B", fontWeight: 600 }}>
                  {hasApiKey ? `API Key: ${maskedKey || "Đã kết nối"}` : "Chưa kết nối API Key"}
                </span>
              </div>
              {hasApiKey ? (
                <button
                  onClick={handleDeleteApiKey}
                  style={{ background: "transparent", border: "none", color: "#EF4444", fontSize: 11, cursor: "pointer", textDecoration: "underline" }}
                >
                  Ngắt kết nối
                </button>
              ) : (
                <button
                  onClick={() => setShowApiKeyModal(true)}
                  className="touch-btn"
                  style={{ background: "#F59E0B", border: "none", color: "#000", fontSize: 11, fontWeight: 700, padding: "4px 10px", borderRadius: 6 }}
                >
                  Kết nối API Key ⚡
                </button>
              )}
            </div>
          </div>

          {/* Modal nhập API Key nếu chưa có */}
          {showApiKeyModal && (
            <div style={{ background: "var(--bg-card)", border: "1px solid #F59E0B", borderRadius: 16, padding: 16 }}>
              <div className="flex items-center justify-between mb-2">
                <span style={{ fontSize: 13, fontWeight: 700, color: "#F59E0B" }}>
                  KẾT NỐI NEXTDNS REST API
                </span>
                <button onClick={() => setShowApiKeyModal(false)} style={{ background: "transparent", border: "none", color: "var(--text-subtle)", fontSize: 14 }}>✕</button>
              </div>
              <div style={{ fontSize: 11, color: "var(--text-muted)", marginBottom: 8, lineHeight: 1.5 }}>
                Lấy mã API Key tại:{" "}
                <a href="https://my.nextdns.io/account" target="_blank" rel="noreferrer" style={{ color: "#38BDF8", textDecoration: "underline" }}>
                  my.nextdns.io/account
                </a>{" "}
                để mở khóa đầy đủ Thống Kê, Nhật Ký (Logs), Bộ Lọc Blocklists, Chặn App & Web!
              </div>
              <div style={{ display: "flex", gap: 8, position: "relative" }}>
                <div style={{ flex: 1, position: "relative" }}>
                  <input
                    type={showRawApiKey ? "text" : "password"}
                    value={apiKeyInput}
                    onChange={(e) => setApiKeyInput(e.target.value)}
                    placeholder="Dán API Key vào đây..."
                    style={{ width: "100%", background: "var(--bg-canvas)", border: "1px solid var(--border-color)", borderRadius: 8, padding: "8px 38px 8px 12px", color: "#fff", fontSize: 13, outline: "none", boxSizing: "border-box" }}
                  />
                  <button
                    type="button"
                    onClick={() => setShowRawApiKey(!showRawApiKey)}
                    style={{ position: "absolute", right: 10, top: "50%", transform: "translateY(-50%)", background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer", fontSize: 13 }}
                  >
                    {showRawApiKey ? "🙈" : "👁"}
                  </button>
                </div>
                <button
                  onClick={handleSaveApiKey}
                  disabled={saving}
                  style={{ background: "#10B981", color: "#fff", border: "none", padding: "8px 14px", borderRadius: 8, fontSize: 12, fontWeight: 700 }}
                >
                  {saving ? "..." : "Xác nhận"}
                </button>
              </div>
            </div>
          )}

          {hasApiKey ? (
            <div className="flex flex-col gap-3">
              {/* Thanh chọn 6 Sub-Tabs chuẩn NextDNS */}
              <div
                style={{
                  display: "grid",
                  gridTemplateColumns: "repeat(6, 1fr)",
                  background: "var(--bg-canvas)",
                  borderRadius: 12,
                  padding: 4,
                  border: "1px solid var(--border-color)",
                  gap: 2
                }}
              >
                {[
                  { id: "analytics", label: "Thống Kê", icon: "📊" },
                  { id: "logs", label: "Logs", icon: "📋" },
                  { id: "privacy", label: "Bộ Lọc", icon: "🛡️" },
                  { id: "parental", label: "Chặn App", icon: "🚫" },
                  { id: "security", label: "Bảo Mật", icon: "🔒" },
                  { id: "lists", label: "Tên Miền", icon: "📝" },
                ].map((t) => (
                  <button
                    key={t.id}
                    onClick={() => setActiveSubTab(t.id as any)}
                    style={{
                      background: activeSubTab === t.id ? "#1E293B" : "transparent",
                      color: activeSubTab === t.id ? "#38BDF8" : "#94A3B8",
                      border: "none",
                      padding: "8px 2px",
                      borderRadius: 8,
                      fontSize: 11,
                      fontWeight: 700,
                      cursor: "pointer",
                      display: "flex",
                      flexDirection: "column",
                      alignItems: "center",
                      gap: 2
                    }}
                  >
                    <span style={{ fontSize: 14 }}>{t.icon}</span>
                    <span>{t.label}</span>
                  </button>
                ))}
              </div>

              {/* ─────────────────────────────────────────────────────────────
                  TAB 1: THỐNG KÊ (ANALYTICS) VỚI CHỌN KHUNG THỜI GIAN (IMAGE 3)
              ────────────────────────────────────────────────────────────── */}
              {activeSubTab === "analytics" && (
                <div className="flex flex-col gap-3">
                  {/* Top Bar với Bộ chọn khung thời gian chuẩn NextDNS (Image 3) */}
                  <div className="flex items-center justify-between">
                    <div style={{ fontSize: 13, fontWeight: 700, color: "var(--text-primary)" }}>
                      TỔNG HỢP LƯU LƯỢNG TRUY VẤN
                    </div>

                    {/* Time Range Dropdown Button (Matching Image 3) */}
                    <div style={{ position: "relative" }} ref={timeDropdownRef}>
                      <button
                        onClick={() => setShowTimeDropdown(!showTimeDropdown)}
                        style={{
                          background: "#9CA3AF",
                          color: "#111827",
                          border: "none",
                          borderRadius: 8,
                          padding: "6px 14px",
                          fontSize: 13,
                          fontWeight: 600,
                          cursor: "pointer",
                          display: "flex",
                          alignItems: "center",
                          gap: 6,
                          boxShadow: "0 1px 3px rgba(0,0,0,0.2)"
                        }}
                      >
                        <span>{currentTimeLabel}</span>
                        <span style={{ fontSize: 10 }}>▼</span>
                      </button>

                      {/* Floating Dropdown Menu (Image 3) */}
                      {showTimeDropdown && (
                        <div
                          style={{
                            position: "absolute",
                            top: "calc(100% + 4px)",
                            right: 0,
                            zIndex: 100,
                            background: "#FFFFFF",
                            borderRadius: 8,
                            boxShadow: "0 10px 25px -5px rgba(0, 0, 0, 0.4)",
                            border: "1px solid #E5E7EB",
                            minWidth: "160px",
                            overflow: "hidden",
                            padding: "4px 0"
                          }}
                        >
                          {TIME_RANGES.map((r) => {
                            const isSelected = r.id === timeRange;
                            return (
                              <div
                                key={r.id}
                                onClick={() => {
                                  setTimeRange(r.id);
                                  setShowTimeDropdown(false);
                                }}
                                style={{
                                  padding: "8px 16px",
                                  fontSize: "13px",
                                  fontWeight: 500,
                                  cursor: "pointer",
                                  background: isSelected ? "#2563EB" : "transparent",
                                  color: isSelected ? "#FFFFFF" : "#1F2937",
                                  transition: "background 0.1s ease"
                                }}
                                onMouseEnter={(e) => {
                                  if (!isSelected) (e.currentTarget as HTMLElement).style.background = "#F3F4F6";
                                }}
                                onMouseLeave={(e) => {
                                  if (!isSelected) (e.currentTarget as HTMLElement).style.background = "transparent";
                                }}
                              >
                                {r.label}
                              </div>
                            );
                          })}
                        </div>
                      )}
                    </div>
                  </div>

                  {/* 3 Thẻ số liệu chính */}
                  <div className="grid grid-cols-3 gap-2">
                    <div style={{ background: "var(--bg-card)", border: "1px solid var(--border-color)", borderRadius: 14, padding: "12px 10px", textAlign: "center" }}>
                      <div style={{ fontSize: 10, color: "var(--text-muted)", marginBottom: 2 }}>QUERIES</div>
                      <div style={{ fontSize: 20, fontWeight: 800, color: "var(--text-primary)", fontFamily: "JetBrains Mono, monospace" }}>
                        {totalQueries > 0 ? totalQueries.toLocaleString() : (loadingCloud ? "..." : "0")}
                      </div>
                    </div>
                    <div style={{ background: "var(--bg-card)", border: "1px solid var(--border-color)", borderRadius: 14, padding: "12px 10px", textAlign: "center" }}>
                      <div style={{ fontSize: 10, color: "var(--text-muted)", marginBottom: 2 }}>BLOCKED QUERIES</div>
                      <div style={{ fontSize: 20, fontWeight: 800, color: "#EF4444", fontFamily: "JetBrains Mono, monospace" }}>
                        {blockedQueries > 0 ? blockedQueries.toLocaleString() : (loadingCloud ? "..." : "0")}
                      </div>
                    </div>
                    <div style={{ background: "var(--bg-card)", border: "1px solid var(--border-color)", borderRadius: 14, padding: "12px 10px", textAlign: "center" }}>
                      <div style={{ fontSize: 10, color: "var(--text-muted)", marginBottom: 2 }}>% BLOCKED</div>
                      <div style={{ fontSize: 20, fontWeight: 800, color: "#10B981", fontFamily: "JetBrains Mono, monospace" }}>
                        {blockRate}%
                      </div>
                    </div>
                  </div>

                  {/* Thanh tiến trình tỷ lệ chặn */}
                  <div style={{ background: "var(--bg-card)", border: "1px solid var(--border-color)", borderRadius: 14, padding: 14 }}>
                    <div className="flex items-center justify-between mb-2">
                      <span style={{ fontSize: 12, color: "var(--text-muted)" }}>Lưu lượng độc hại & quảng cáo đã lọc ({currentTimeLabel})</span>
                      <span style={{ fontSize: 12, fontWeight: 700, color: "#10B981" }}>{blockRate}%</span>
                    </div>
                    <div style={{ width: "100%", height: 8, background: "var(--bg-canvas)", borderRadius: 4, overflow: "hidden" }}>
                      <div style={{ width: `${Math.min(100, Math.max(0, parseFloat(blockRate)))}%`, height: "100%", background: "#10B981", borderRadius: 4, transition: "width 0.4s ease" }} />
                    </div>
                  </div>

{/* ────────────────── REASONS: LÝ DO BỊ CHẶN (TOP BLOCK REASONS) ────────────────── */}
                  <div style={{ background: "var(--bg-card)", border: "1px solid var(--border-color)", borderRadius: 14, padding: 14 }}>
                    <div className="flex items-center justify-between mb-3">
                      <div>
                        <div style={{ fontSize: 13, fontWeight: 700, color: "var(--text-primary)" }}>Lý Do Bị Chặn (Reasons)</div>
                        <div style={{ fontSize: 10, color: "var(--text-subtle)" }}>Bộ lọc, danh sách hoặc dịch vụ đã chặn truy vấn</div>
                      </div>
                      <span style={{ fontSize: 11, color: "#EF4444", background: "rgba(239, 68, 68, 0.1)", padding: "2px 8px", borderRadius: 6, fontWeight: 700 }}>
                        {reasons.length} nguồn chặn
                      </span>
                    </div>

                    {reasons.length === 0 ? (
                      <div style={{ fontSize: 11, color: "var(--text-subtle)", padding: "12px 0", textAlign: "center" }}>
                        Chưa có lý do chặn nào được ghi nhận trong khoảng thời gian này
                      </div>
                    ) : (
                      <div className="flex flex-col gap-2">
                        {reasons.map((r, idx) => {
                          const rQueries = r.queries || 0;
                          const rPct = blockedQueries > 0 ? Math.min(100, Math.round((rQueries / blockedQueries) * 100)) : 0;
                          const isCustom = r.id === "denylist" || r.id.startsWith("service:");
                          return (
                            <div key={idx} style={{ background: "var(--bg-canvas)", border: "1px solid var(--border-color)", borderRadius: 10, padding: "10px 12px" }}>
                              <div className="flex items-center justify-between mb-1.5">
                                <div className="flex items-center gap-2">
                                  <span style={{ fontSize: 12 }}>{isCustom ? "🔒" : "🛡️"}</span>
                                  <span style={{ fontSize: 12, fontWeight: 700, color: "var(--text-primary)" }}>{r.name || r.id}</span>
                                  <span style={{ fontSize: 10, color: "var(--text-muted)", background: "var(--bg-card-subtle)", padding: "1px 6px", borderRadius: 4 }}>
                                    {r.id.startsWith("service:") ? "Dịch vụ" : r.id === "denylist" ? "Denylist thủ công" : "Bộ lọc cộng đồng"}
                                  </span>
                                </div>
                                <div className="flex items-center gap-2">
                                  <span style={{ fontSize: 12, fontWeight: 800, color: "#EF4444", fontFamily: "JetBrains Mono, monospace" }}>
                                    {rQueries.toLocaleString()}
                                  </span>
                                  <span style={{ fontSize: 10, color: "var(--text-subtle)" }}>({rPct}%)</span>
                                </div>
                              </div>
                              <div style={{ width: "100%", height: 5, background: "var(--bg-card-subtle)", borderRadius: 3, overflow: "hidden" }}>
                                <div style={{ width: `${rPct}%`, height: "100%", background: isCustom ? "#F59E0B" : "#EF4444", borderRadius: 3 }} />
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    )}
                  </div>

                  {/* ────────────────── GIAO THỨC & BẢO MẬT DNSSEC ────────────────── */}
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                    {/* DNS Protocols */}
                    <div style={{ background: "var(--bg-card)", border: "1px solid var(--border-color)", borderRadius: 14, padding: 14 }}>
                      <div className="flex items-center justify-between mb-3">
                        <div>
                          <div style={{ fontSize: 13, fontWeight: 700, color: "var(--text-primary)" }}>Giao Thức DNS (Protocols)</div>
                          <div style={{ fontSize: 10, color: "var(--text-subtle)" }}>Phương thức truyền tải truy vấn</div>
                        </div>
                        <span style={{ fontSize: 11, color: "#38BDF8", background: "rgba(56, 189, 248, 0.1)", padding: "2px 6px", borderRadius: 6 }}>
                          IPv4 & Native
                        </span>
                      </div>
                      <div className="flex flex-col gap-2">
                        {protocols.length === 0 ? (
                          <div style={{ fontSize: 11, color: "var(--text-subtle)", padding: "8px 0", textAlign: "center" }}>Đang tải...</div>
                        ) : (
                          protocols.map((p, idx) => {
                            const pTotal = protocols.reduce((sum, item) => sum + (item.queries || 0), 0) || 1;
                            const pPct = Math.round(((p.queries || 0) / pTotal) * 100);
                            return (
                              <div key={idx} className="flex items-center justify-between p-2 rounded-lg" style={{ background: "var(--bg-canvas)", border: "1px solid var(--border-color)" }}>
                                <div className="flex items-center gap-2">
                                  <span style={{ fontSize: 12, color: "#38BDF8" }}>⚡</span>
                                  <span style={{ fontSize: 12, fontWeight: 700, color: "var(--text-primary)" }}>{p.protocol}</span>
                                </div>
                                <div className="flex items-center gap-2">
                                  <span style={{ fontSize: 11, fontWeight: 700, color: "#38BDF8", fontFamily: "JetBrains Mono, monospace" }}>
                                    {p.queries.toLocaleString()} truy vấn
                                  </span>
                                  <span style={{ fontSize: 10, color: "var(--text-subtle)" }}>({pPct}%)</span>
                                </div>
                              </div>
                            );
                          })
                        )}
                      </div>
                    </div>

                    {/* DNSSEC Validation */}
                    <div style={{ background: "var(--bg-card)", border: "1px solid var(--border-color)", borderRadius: 14, padding: 14 }}>
                      <div className="flex items-center justify-between mb-3">
                        <div>
                          <div style={{ fontSize: 13, fontWeight: 700, color: "var(--text-primary)" }}>Xác Thực DNSSEC</div>
                          <div style={{ fontSize: 10, color: "var(--text-subtle)" }}>Chống giả mạo bản ghi DNS độc hại</div>
                        </div>
                        <span style={{ fontSize: 11, color: "#10B981", background: "rgba(16, 185, 129, 0.1)", padding: "2px 6px", borderRadius: 6 }}>
                          Bảo vệ tự động
                        </span>
                      </div>
                      <div className="flex flex-col gap-2">
                        {dnssec.length === 0 ? (
                          <div style={{ fontSize: 11, color: "var(--text-subtle)", padding: "8px 0", textAlign: "center" }}>Đang tải...</div>
                        ) : (
                          dnssec.map((s, idx) => (
                            <div key={idx} className="flex items-center justify-between p-2 rounded-lg" style={{ background: "var(--bg-canvas)", border: "1px solid var(--border-color)" }}>
                              <div className="flex items-center gap-2">
                                <span style={{ fontSize: 12 }}>{s.validated ? "🔒" : "🌐"}</span>
                                <span style={{ fontSize: 12, fontWeight: 700, color: s.validated ? "#10B981" : "#94A3B8" }}>
                                  {s.validated ? "Đã ký số (Validated)" : "Chưa ký số (Non-validated)"}
                                </span>
                              </div>
                              <span style={{ fontSize: 11, fontWeight: 700, color: s.validated ? "#10B981" : "#94A3B8", fontFamily: "JetBrains Mono, monospace" }}>
                                {s.queries.toLocaleString()}
                              </span>
                            </div>
                          ))
                        )}
                      </div>
                    </div>
                  </div>

                  {/* ────────────────── 2 BẢNG: RESOLVED & BLOCKED DOMAINS (CÓ CHUYỂN TÊN MIỀN GỐC) ────────────────── */}
                  <div className="flex items-center justify-between mt-1">
                    <div style={{ fontSize: 13, fontWeight: 700, color: "var(--text-primary)" }}>
                      CHI TIẾT TÊN MIỀN PHÂN GIẢI & BỊ CHẶN
                    </div>
                    {/* Toggle: Tất cả tên miền vs Tên miền gốc (Root) */}
                    <div style={{ display: "flex", gap: 4, background: "var(--bg-canvas)", padding: 3, borderRadius: 8, border: "1px solid var(--border-color)" }}>
                      <button
                        onClick={() => {
                          setIsRootDomains(false);
                          fetchAnalytics(profileId, timeRange, false);
                        }}
                        style={{
                          background: !isRootDomains ? "#38BDF8" : "transparent",
                          color: !isRootDomains ? "#000" : "#94A3B8",
                          border: "none",
                          padding: "3px 8px",
                          borderRadius: 6,
                          fontSize: 11,
                          fontWeight: 700,
                          cursor: "pointer"
                        }}
                      >
                        Tất cả domain
                      </button>
                      <button
                        onClick={() => {
                          setIsRootDomains(true);
                          fetchAnalytics(profileId, timeRange, true);
                        }}
                        style={{
                          background: isRootDomains ? "#38BDF8" : "transparent",
                          color: isRootDomains ? "#000" : "#94A3B8",
                          border: "none",
                          padding: "3px 8px",
                          borderRadius: 6,
                          fontSize: 11,
                          fontWeight: 700,
                          cursor: "pointer"
                        }}
                      >
                        Tên miền gốc (Root)
                      </button>
                    </div>
                  </div>

                  <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                    {/* Resolved Domains */}
                    <div style={{ background: "var(--bg-card)", border: "1px solid var(--border-color)", borderRadius: 14, padding: 14 }}>
                      <div className="flex items-center justify-between mb-3">
                        <div>
                          <div style={{ fontSize: 13, fontWeight: 700, color: "var(--text-primary)" }}>Resolved Domains</div>
                          <div style={{ fontSize: 10, color: "var(--text-subtle)" }}>Tên miền đã phân giải thành công</div>
                        </div>
                        <span style={{ fontSize: 11, color: "#38BDF8", background: "rgba(56, 189, 248, 0.1)", padding: "2px 6px", borderRadius: 6 }}>
                          Top {(showAllDomains ? resolvedDomains : resolvedDomains.slice(0, 8)).length} / {resolvedDomains.length}
                        </span>
                      </div>
                      <div className="flex flex-col gap-1.5">
                        {resolvedDomains.length === 0 ? (
                          <div style={{ fontSize: 11, color: "var(--text-subtle)", padding: "12px 0", textAlign: "center" }}>
                            {loadingCloud ? "Đang tải dữ liệu..." : "Chưa có dữ liệu trong khoảng thời gian này"}
                          </div>
                        ) : (
                          (showAllDomains ? resolvedDomains : resolvedDomains.slice(0, 8)).map((item, idx) => (
                            <div key={idx} className="flex items-center justify-between p-2 rounded-lg" style={{ background: "var(--bg-canvas)", border: "1px solid var(--border-color)" }}>
                              <div className="flex items-center gap-2 overflow-hidden mr-2">
                                <img
                                  src={`https://www.google.com/s2/favicons?domain=${item.domain}&sz=32`}
                                  alt=""
                                  style={{ width: 16, height: 16, borderRadius: 3, flexShrink: 0 }}
                                  onError={(e) => { (e.currentTarget as HTMLElement).style.display = "none"; }}
                                />
                                <span style={{ fontSize: 11, fontFamily: "JetBrains Mono, monospace", color: "var(--text-primary)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }} title={item.domain}>
                                  {item.domain}
                                </span>
                                {item.tracker && (
                                  <span style={{ fontSize: 9, color: "#38BDF8", background: "rgba(56, 189, 248, 0.12)", padding: "1px 5px", borderRadius: 4, flexShrink: 0 }}>
                                    {item.tracker}
                                  </span>
                                )}
                              </div>
                              <span style={{ fontSize: 11, fontWeight: 700, color: "var(--text-muted)", background: "var(--bg-card-subtle)", padding: "2px 8px", borderRadius: 6, flexShrink: 0 }}>
                                {item.queries.toLocaleString()}
                              </span>
                            </div>
                          ))
                        )}
                      </div>
                    </div>

                    {/* Blocked Domains */}
                    <div style={{ background: "var(--bg-card)", border: "1px solid var(--border-color)", borderRadius: 14, padding: 14 }}>
                      <div className="flex items-center justify-between mb-3">
                        <div>
                          <div style={{ fontSize: 13, fontWeight: 700, color: "#EF4444" }}>Blocked Domains</div>
                          <div style={{ fontSize: 10, color: "var(--text-subtle)" }}>Tên miền quảng cáo/mã độc đã chặn</div>
                        </div>
                        <span style={{ fontSize: 11, color: "#EF4444", background: "rgba(239, 68, 68, 0.1)", padding: "2px 6px", borderRadius: 6 }}>
                          Top {(showAllDomains ? blockedDomains : blockedDomains.slice(0, 8)).length} / {blockedDomains.length}
                        </span>
                      </div>
                      <div className="flex flex-col gap-1.5">
                        {blockedDomains.length === 0 ? (
                          <div style={{ fontSize: 11, color: "var(--text-subtle)", padding: "12px 0", textAlign: "center" }}>
                            {loadingCloud ? "Đang tải dữ liệu..." : "Chưa có tên miền nào bị chặn trong khoảng thời gian này"}
                          </div>
                        ) : (
                          (showAllDomains ? blockedDomains : blockedDomains.slice(0, 8)).map((item, idx) => (
                            <div key={idx} className="flex items-center justify-between p-2 rounded-lg" style={{ background: "var(--bg-canvas)", border: "1px solid var(--border-color)", borderLeft: "3px solid #EF4444" }}>
                              <div className="flex items-center gap-2 overflow-hidden mr-2">
                                <span style={{ fontSize: 12, color: "#EF4444" }}>🚫</span>
                                <span style={{ fontSize: 11, fontFamily: "JetBrains Mono, monospace", color: "var(--text-primary)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }} title={item.domain}>
                                  {item.domain}
                                </span>
                                {item.tracker && (
                                  <span style={{ fontSize: 9, color: "#EF4444", background: "rgba(239, 68, 68, 0.15)", padding: "1px 5px", borderRadius: 4, flexShrink: 0 }}>
                                    {item.tracker}
                                  </span>
                                )}
                              </div>
                              <span style={{ fontSize: 11, fontWeight: 700, color: "#EF4444", background: "rgba(239, 68, 68, 0.15)", padding: "2px 8px", borderRadius: 6, flexShrink: 0 }}>
                                {item.queries.toLocaleString()}
                              </span>
                            </div>
                          ))
                        )}
                      </div>
                    </div>
                  </div>

                  {/* Nút Xem thêm / Thu gọn danh sách tên miền */}
                  {(resolvedDomains.length > 8 || blockedDomains.length > 8) && (
                    <button
                      onClick={() => setShowAllDomains(!showAllDomains)}
                      style={{
                        background: "var(--bg-card)",
                        border: "1px solid var(--border-color)",
                        color: "#38BDF8",
                        padding: "8px 14px",
                        borderRadius: 10,
                        fontSize: 12,
                        fontWeight: 700,
                        cursor: "pointer",
                        margin: "0 auto",
                        display: "block"
                      }}
                    >
                      {showAllDomains ? "▲ Thu gọn danh sách" : `▼ Xem thêm đầy đủ top tên miền (${Math.max(resolvedDomains.length, blockedDomains.length)})`}
                    </button>
                  )}
                </div>
              )}

              {/* ─────────────────────────────────────────────────────────────
                  TAB 2: NHẬT KÝ TRUY VẤN THỜI GIAN THỰC (LOGS - IMAGE 1)
              ────────────────────────────────────────────────────────────── */}
              {activeSubTab === "logs" && (
                <div className="flex flex-col gap-3">
                  {/* Top Bar controls: Device selector dropdown & Search bar (Image 1) */}
                  <div className="flex flex-col sm:flex-row items-stretch sm:items-center gap-2">
                    {/* Device Selector Dropdown (Image 1: "All devices ▾") */}
                    <div style={{ position: "relative", minWidth: "140px" }}>
                      <select
                        value={logDevice}
                        onChange={(e) => setLogDevice(e.target.value)}
                        style={{
                          width: "100%",
                          background: "var(--bg-card)",
                          border: "1px solid var(--border-color)",
                          borderRadius: 10,
                          padding: "8px 12px",
                          color: "var(--text-primary)",
                          fontSize: 12,
                          fontWeight: 600,
                          cursor: "pointer",
                          outline: "none"
                        }}
                      >
                        <option value="all">All devices ▾</option>
                        {uniqueDevices.map((ip) => (
                          <option key={ip} value={ip}>{ip}</option>
                        ))}
                      </select>
                    </div>

                    {/* Search bar matching Image 1 */}
                    <div
                      style={{
                        flex: 1,
                        display: "flex",
                        alignItems: "center",
                        gap: 8,
                        background: "var(--bg-card)",
                        border: "1px solid var(--border-color)",
                        borderRadius: 10,
                        padding: "6px 12px"
                      }}
                    >
                      <span style={{ color: "var(--text-subtle)", fontSize: 13 }}>🔍</span>
                      <input
                        type="text"
                        value={logSearch}
                        onChange={(e) => setLogSearch(e.target.value)}
                        placeholder="Search domains or clients..."
                        style={{
                          flex: 1,
                          background: "transparent",
                          border: "none",
                          color: "var(--text-primary)",
                          fontSize: 13,
                          outline: "none"
                        }}
                      />
                      {logSearch && (
                        <button
                          onClick={() => setLogSearch("")}
                          style={{ background: "transparent", border: "none", color: "var(--text-subtle)", cursor: "pointer" }}
                        >
                          ✕
                        </button>
                      )}

                      {/* Filter Blocked Only toggle button */}
                      <button
                        onClick={() => setLogFilterBlocked(!logFilterBlocked)}
                        title="Chỉ hiện truy vấn bị chặn"
                        style={{
                          background: logFilterBlocked ? "#EF4444" : "#1E293B",
                          color: logFilterBlocked ? "#FFFFFF" : "#94A3B8",
                          border: "none",
                          borderRadius: 6,
                          padding: "4px 8px",
                          fontSize: 11,
                          fontWeight: 700,
                          cursor: "pointer"
                        }}
                      >
                        {logFilterBlocked ? "🚫 Blocked" : "All"}
                      </button>

                      {/* Refresh button */}
                      <button
                        onClick={() => fetchLogs(profileId)}
                        disabled={fetchingLogs}
                        title="Làm mới ngay"
                        style={{
                          background: "var(--bg-card-subtle)",
                          border: "none",
                          color: fetchingLogs ? "#38BDF8" : "#94A3B8",
                          borderRadius: 6,
                          padding: "4px 8px",
                          fontSize: 12,
                          cursor: "pointer"
                        }}
                      >
                        {fetchingLogs ? "..." : "⟳"}
                      </button>
                    </div>
                  </div>

                  {/* Real Logs Feed matching Image 1 */}
                  <div
                    style={{
                      background: "var(--bg-card)",
                      border: "1px solid var(--border-color)",
                      borderRadius: 14,
                      overflow: "hidden",
                      display: "flex",
                      flexDirection: "column"
                    }}
                  >
                    <div
                      style={{
                        padding: "10px 14px",
                        borderBottom: "1px solid #1E293B",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "space-between",
                        fontSize: 11,
                        color: "var(--text-muted)"
                      }}
                    >
                      <div className="flex items-center gap-2">
                        <span className="pulse-dot" style={{ width: 8, height: 8, borderRadius: "50%", background: "#10B981" }} />
                        <span>Live Stream Logs ({filteredLogs.length} queries)</span>
                      </div>
                      <span style={{ fontSize: 10, color: "var(--text-subtle)" }}>Tự động làm mới mỗi 3.5s</span>
                    </div>

                    <div style={{ maxHeight: "580px", overflowY: "auto" }}>
                      {filteredLogs.length === 0 ? (
                        <div style={{ padding: "40px 20px", textAlign: "center", color: "var(--text-subtle)", fontSize: 12 }}>
                          {fetchingLogs ? "Đang tải dữ liệu truy vấn thời gian thực..." : "Không có truy vấn nào phù hợp bộ lọc"}
                        </div>
                      ) : (
                        filteredLogs.map((log, idx) => {
                          const isBlocked = log.status === "blocked" || (log.reasons && log.reasons.length > 0);
                          const isMenuOpen = logMenuOpenId === `${idx}_${log.domain}`;

                          return (
                            <div
                              key={`${idx}_${log.timestamp}_${log.domain}`}
                              style={{
                                padding: "10px 14px",
                                borderBottom: "1px solid #1E293B",
                                display: "flex",
                                alignItems: "center",
                                justifyContent: "space-between",
                                gap: 12,
                                background: isBlocked ? "rgba(239, 68, 68, 0.03)" : "transparent",
                                borderLeft: isBlocked ? "3px solid #EF4444" : "3px solid transparent",
                                transition: "background 0.1s ease"
                              }}
                            >
                              {/* Left: Favicon & Domain Name */}
                              <div style={{ display: "flex", alignItems: "center", gap: 10, minWidth: 0, flex: 1 }}>
                                <img
                                  src={`https://www.google.com/s2/favicons?domain=${log.root || log.domain}&sz=32`}
                                  alt=""
                                  style={{ width: 18, height: 18, borderRadius: 4, flexShrink: 0 }}
                                  onError={(e) => {
                                    (e.currentTarget as HTMLElement).style.display = "none";
                                  }}
                                />
                                <div style={{ minWidth: 0 }}>
                                  <div
                                    style={{
                                      fontSize: 13,
                                      fontWeight: 600,
                                      color: isBlocked ? "#FCA5A5" : "#F9FAFB",
                                      fontFamily: "JetBrains Mono, monospace",
                                      overflow: "hidden",
                                      textOverflow: "ellipsis",
                                      whiteSpace: "nowrap"
                                    }}
                                    title={log.domain}
                                  >
                                    {log.domain}
                                  </div>
                                  <div style={{ display: "flex", alignItems: "center", gap: 6, flexWrap: "wrap", marginTop: 2 }}>
                                    {isBlocked && (
                                      <span style={{ fontSize: 9, fontWeight: 700, color: "#EF4444", background: "rgba(239, 68, 68, 0.15)", padding: "1px 5px", borderRadius: 4 }}>
                                        {log.reasons?.[0]?.name || "Blocked"}
                                      </span>
                                    )}
                                    {log.tracker && (
                                      <span style={{ fontSize: 9, color: "#38BDF8", background: "rgba(56, 189, 248, 0.12)", padding: "1px 5px", borderRadius: 4 }}>
                                        {log.tracker}
                                      </span>
                                    )}
                                  </div>
                                </div>
                              </div>

                              {/* Right: Client IP, Relative Time & Action Menu (Image 1) */}
                              <div style={{ display: "flex", alignItems: "center", gap: 12, flexShrink: 0, position: "relative" }}>
                                <div style={{ textAlign: "right" }}>
                                  <div style={{ fontSize: 11, fontWeight: 600, color: "var(--text-muted)", fontFamily: "JetBrains Mono, monospace" }}>
                                    {log.clientIp || linkedIp}
                                  </div>
                                  <div style={{ fontSize: 10, color: "var(--text-subtle)" }}>
                                    {formatTimeAgo(log.timestamp)}
                                  </div>
                                </div>

                                {/* 3 Dots Action Menu Button (Image 1) */}
                                <button
                                  onClick={() => setLogMenuOpenId(isMenuOpen ? null : `${idx}_${log.domain}`)}
                                  style={{
                                    background: "transparent",
                                    border: "none",
                                    color: "var(--text-subtle)",
                                    fontSize: 16,
                                    cursor: "pointer",
                                    padding: "4px 6px"
                                  }}
                                  title="Thao tác"
                                >
                                  ⋮
                                </button>

                                {/* Action Dropdown */}
                                {isMenuOpen && (
                                  <div
                                    style={{
                                      position: "absolute",
                                      top: "100%",
                                      right: 0,
                                      zIndex: 100,
                                      background: "var(--bg-canvas)",
                                      border: "1px solid var(--border-color)",
                                      borderRadius: 8,
                                      boxShadow: "0 10px 20px rgba(0,0,0,0.5)",
                                      minWidth: "160px",
                                      overflow: "hidden"
                                    }}
                                  >
                                    <button
                                      onClick={() => handleAddDomain("denylist", log.domain)}
                                      style={{
                                        width: "100%",
                                        textAlign: "left",
                                        padding: "8px 12px",
                                        fontSize: 12,
                                        color: "#EF4444",
                                        background: "transparent",
                                        border: "none",
                                        cursor: "pointer",
                                        display: "flex",
                                        alignItems: "center",
                                        gap: 6
                                      }}
                                    >
                                      <span>🚫</span> Thêm vào Denylist
                                    </button>
                                    <button
                                      onClick={() => handleAddDomain("allowlist", log.domain)}
                                      style={{
                                        width: "100%",
                                        textAlign: "left",
                                        padding: "8px 12px",
                                        fontSize: 12,
                                        color: "#10B981",
                                        background: "transparent",
                                        border: "none",
                                        cursor: "pointer",
                                        display: "flex",
                                        alignItems: "center",
                                        gap: 6,
                                        borderTop: "1px solid #1E293B"
                                      }}
                                    >
                                      <span>✓</span> Thêm vào Allowlist
                                    </button>
                                  </div>
                                )}
                              </div>
                            </div>
                          );
                        })
                      )}
                    </div>
                  </div>
                </div>
              )}

              {/* ─────────────────────────────────────────────────────────────
                  TAB 3: BỘ LỌC QUYỀN RIÊNG TƯ & ADD A BLOCKLIST (IMAGE 2)
              ────────────────────────────────────────────────────────────── */}
              {activeSubTab === "privacy" && (
                <div className="flex flex-col gap-3">
                  <div className="flex items-center justify-between">
                    <div>
                      <div style={{ fontSize: 13, fontWeight: 700, color: "var(--text-primary)" }}>
                        BỘ LỌC QUẢNG CÁO & THEO DÕI (BLOCKLISTS)
                      </div>
                      <div style={{ fontSize: 11, color: "var(--text-subtle)" }}>
                        Các bộ lọc cộng đồng toàn cầu được kích hoạt trên hồ sơ NextDNS
                      </div>
                    </div>
                    {/* Add a Blocklist Button matching Image 2 */}
                    <button
                      onClick={() => setIsAddBlocklistOpen(true)}
                      style={{
                        background: "#2563EB",
                        color: "#FFFFFF",
                        border: "none",
                        borderRadius: 8,
                        padding: "8px 14px",
                        fontSize: 12,
                        fontWeight: 700,
                        cursor: "pointer",
                        display: "flex",
                        alignItems: "center",
                        gap: 6,
                        boxShadow: "0 2px 8px rgba(37, 99, 235, 0.4)"
                      }}
                    >
                      <span>➕</span> Add a blocklist
                    </button>
                  </div>

                  {/* Danh sách các bộ lọc đang kích hoạt */}
                  <div style={{ background: "var(--bg-card)", border: "1px solid var(--border-color)", borderRadius: 14, overflow: "hidden" }}>
                    {activeBlocklists.length === 0 ? (
                      <div style={{ padding: "36px 20px", textAlign: "center", color: "var(--text-subtle)", fontSize: 12 }}>
                        Chưa có bộ lọc nào được thêm. Nhấn "Add a blocklist" để kích hoạt!
                      </div>
                    ) : (
                      activeBlocklists.map((b) => {
                        const name = b.id === "nextdns-recommended" ? "NextDNS Ads & Trackers Blocklist" : (b.name || b.id);
                        const desc = b.id === "nextdns-recommended" ? "A comprehensive blocklist to block ads & trackers in all countries. This is the recommended starter blocklist." : (b.description || "");

                        return (
                          <div
                            key={b.id}
                            style={{
                              padding: "16px 18px",
                              borderBottom: "1px solid #1E293B",
                              borderLeft: "3px solid #3B82F6",
                              display: "flex",
                              alignItems: "flex-start",
                              justifyContent: "space-between",
                              gap: 16
                            }}
                          >
                            <div style={{ flex: 1 }}>
                              <div style={{ fontSize: 14, fontWeight: 700, color: "var(--text-primary)", marginBottom: 4 }}>
                                {name}
                              </div>
                              {desc && (
                                <div style={{ fontSize: 12, color: "var(--text-muted)", lineHeight: 1.45, marginBottom: 6 }}>
                                  {desc}
                                </div>
                              )}
                              <div style={{ fontSize: 11, color: "var(--text-subtle)", display: "flex", alignItems: "center", gap: 8 }}>
                                <span>{(b.entries || 80788).toLocaleString()} entries</span>
                                {b.updatedOn && <span>• Updated {formatTimeAgo(b.updatedOn)}</span>}
                              </div>
                            </div>

                            <button
                              onClick={() => handleRemoveBlocklist(b.id)}
                              disabled={actionLoading === `rm_${b.id}`}
                              style={{
                                background: "#DC2626",
                                color: "#FFFFFF",
                                border: "none",
                                borderRadius: 6,
                                padding: "6px 14px",
                                fontSize: 11,
                                fontWeight: 800,
                                letterSpacing: "0.05em",
                                cursor: "pointer",
                                flexShrink: 0
                              }}
                            >
                              REMOVE
                            </button>
                          </div>
                        );
                      })
                    )}
                  </div>
                </div>
              )}

              {/* ─────────────────────────────────────────────────────────────
                  TAB 4: CHẶN ỨNG DỤNG & NỘI DUNG (PARENTAL CONTROL)
              ────────────────────────────────────────────────────────────── */}
              {activeSubTab === "parental" && (
                <div className="flex flex-col gap-3">
                  {/* SafeSearch & YouTube Restricted */}
                  <div style={{ background: "var(--bg-card)", border: "1px solid var(--border-color)", borderRadius: 14, padding: 14 }}>
                    <div style={{ fontSize: 12, fontWeight: 700, color: "var(--text-primary)", marginBottom: 10 }}>TÌM KIẾM & NỘI DUNG AN TOÀN</div>
                    <div className="flex flex-col gap-2.5">
                      <div className="flex items-center justify-between p-2 rounded-xl" style={{ background: "var(--bg-canvas)" }}>
                        <div>
                          <div style={{ fontSize: 13, fontWeight: 700, color: "var(--text-primary)" }}>🔍 SafeSearch</div>
                          <div style={{ fontSize: 11, color: "var(--text-subtle)" }}>Lọc kết quả nhạy cảm trên Google, Bing, DuckDuckGo</div>
                        </div>
                        <button
                          onClick={() => handleToggleParentalFlag("safeSearch", !!profileData?.parentalControl?.safeSearch)}
                          disabled={actionLoading === "safeSearch"}
                          style={{
                            background: profileData?.parentalControl?.safeSearch ? "#10B981" : "#334155",
                            color: "#fff", border: "none", borderRadius: 16, padding: "5px 12px", fontSize: 11, fontWeight: 700, cursor: "pointer"
                          }}
                        >
                          {profileData?.parentalControl?.safeSearch ? "BẬT" : "TẮT"}
                        </button>
                      </div>

                      <div className="flex items-center justify-between p-2 rounded-xl" style={{ background: "var(--bg-canvas)" }}>
                        <div>
                          <div style={{ fontSize: 13, fontWeight: 700, color: "var(--text-primary)" }}>🔞 YouTube Restricted Mode</div>
                          <div style={{ fontSize: 11, color: "var(--text-subtle)" }}>Ẩn video người lớn và nhạy cảm trên YouTube</div>
                        </div>
                        <button
                          onClick={() => handleToggleParentalFlag("youtubeRestrictedMode", !!profileData?.parentalControl?.youtubeRestrictedMode)}
                          disabled={actionLoading === "youtubeRestrictedMode"}
                          style={{
                            background: profileData?.parentalControl?.youtubeRestrictedMode ? "#10B981" : "#334155",
                            color: "#fff", border: "none", borderRadius: 16, padding: "5px 12px", fontSize: 11, fontWeight: 700, cursor: "pointer"
                          }}
                        >
                          {profileData?.parentalControl?.youtubeRestrictedMode ? "BẬT" : "TẮT"}
                        </button>
                      </div>
                    </div>
                  </div>

                  {/* Chặn danh mục */}
                  <div style={{ background: "var(--bg-card)", border: "1px solid var(--border-color)", borderRadius: 14, padding: 14 }}>
                    <div style={{ fontSize: 12, fontWeight: 700, color: "var(--text-primary)", marginBottom: 10 }}>CHẶN THEO DANH MỤC</div>
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                      {CATEGORIES.map((c) => {
                        const isCatBlocked = (profileData?.parentalControl?.categories || []).some((item: any) => item.id === c.id && item.active);
                        return (
                          <div key={c.id} className="flex items-center justify-between p-2.5 rounded-xl" style={{ background: "var(--bg-canvas)", border: isCatBlocked ? "1px solid rgba(239, 68, 68, 0.4)" : "1px solid #1E293B" }}>
                            <div className="flex items-center gap-2">
                              <span style={{ fontSize: 16 }}>{c.icon}</span>
                              <div>
                                <div style={{ fontSize: 12, fontWeight: 700, color: isCatBlocked ? "#EF4444" : "#F9FAFB" }}>{c.name}</div>
                                <div style={{ fontSize: 10, color: "var(--text-subtle)" }}>{c.desc}</div>
                              </div>
                            </div>
                            <button
                              onClick={() => handleToggleCategory(c.id, isCatBlocked)}
                              disabled={actionLoading === `cat_${c.id}`}
                              style={{
                                background: isCatBlocked ? "#EF4444" : "#334155",
                                color: "#fff", border: "none", borderRadius: 14, padding: "4px 10px", fontSize: 11, fontWeight: 700, cursor: "pointer"
                              }}
                            >
                              {isCatBlocked ? "ĐÃ CHẶN" : "CHO PHÉP"}
                            </button>
                          </div>
                        );
                      })}
                    </div>
                  </div>

                  {/* Chặn ứng dụng phổ biến */}
                  <div style={{ background: "var(--bg-card)", border: "1px solid var(--border-color)", borderRadius: 14, padding: 14 }}>
                    <div style={{ fontSize: 12, fontWeight: 700, color: "var(--text-primary)", marginBottom: 10 }}>CHẶN ỨNG DỤNG 1 CHẠM</div>
                    <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
                      {POPULAR_SERVICES.map((s) => {
                        const isAppBlocked = (profileData?.parentalControl?.services || []).some((item: any) => item.id === s.id && item.active);
                        return (
                          <div
                            key={s.id}
                            className="flex items-center justify-between p-2.5 rounded-xl cursor-pointer"
                            style={{
                              background: isAppBlocked ? "rgba(239, 68, 68, 0.1)" : "#0B0F17",
                              border: isAppBlocked ? "1px solid rgba(239, 68, 68, 0.4)" : "1px solid #1E293B"
                            }}
                            onClick={() => handleToggleService(s.id, isAppBlocked)}
                          >
                            <div className="flex items-center gap-2">
                              <span style={{ fontSize: 16 }}>{s.icon}</span>
                              <span style={{ fontSize: 12, fontWeight: 700, color: isAppBlocked ? "#EF4444" : "#F9FAFB" }}>{s.name}</span>
                            </div>
                            <span style={{ fontSize: 10, fontWeight: 700, color: isAppBlocked ? "#EF4444" : "#64748B" }}>
                              {isAppBlocked ? "CHẶN" : "MỞ"}
                            </span>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                </div>
              )}

              {/* ─────────────────────────────────────────────────────────────
                  TAB 5: BẢO MẬT HIỂM HỌA (SECURITY)
              ────────────────────────────────────────────────────────────── */}
              {activeSubTab === "security" && (
                <div className="flex flex-col gap-2.5">
                  {SECURITY_FEATURES.map((sec) => {
                    const isSecActive = !!profileData?.security?.[sec.key];
                    return (
                      <div key={sec.key} className="flex items-start justify-between p-3 rounded-xl" style={{ background: "var(--bg-card)", border: isSecActive ? "1px solid rgba(16, 185, 129, 0.4)" : "1px solid #222F46" }}>
                        <div className="flex items-start gap-2.5 flex-1">
                          <span style={{ fontSize: 20 }}>{sec.icon}</span>
                          <div>
                            <div style={{ fontSize: 13, fontWeight: 700, color: isSecActive ? "#10B981" : "#F9FAFB" }}>{sec.name}</div>
                            <div style={{ fontSize: 11, color: "var(--text-subtle)", marginTop: 2 }}>{sec.desc}</div>
                          </div>
                        </div>
                        <button
                          onClick={() => handleToggleSecurity(sec.key, isSecActive)}
                          disabled={actionLoading === `sec_${sec.key}`}
                          style={{
                            background: isSecActive ? "#10B981" : "#334155",
                            color: "#fff", border: "none", borderRadius: 14, padding: "5px 12px", fontSize: 11, fontWeight: 700, cursor: "pointer", marginLeft: 8
                          }}
                        >
                          {isSecActive ? "BẬT" : "TẮT"}
                        </button>
                      </div>
                    );
                  })}
                </div>
              )}

              {/* ─────────────────────────────────────────────────────────────
                  TAB 6: QUẢN LÝ TÊN MIỀN (DENYLIST & ALLOWLIST)
              ────────────────────────────────────────────────────────────── */}
              {activeSubTab === "lists" && (
                <div className="flex flex-col gap-3">
                  <div style={{ display: "flex", gap: 8, background: "var(--bg-canvas)", padding: 4, borderRadius: 10, border: "1px solid var(--border-color)" }}>
                    <button
                      onClick={() => setListType("denylist")}
                      style={{
                        flex: 1, padding: "6px 0", borderRadius: 8, border: "none",
                        background: listType === "denylist" ? "#EF4444" : "transparent",
                        color: "#fff", fontSize: 12, fontWeight: 700, cursor: "pointer"
                      }}
                    >
                      🚫 Danh Sách Chặn ({denylist.length})
                    </button>
                    <button
                      onClick={() => setListType("allowlist")}
                      style={{
                        flex: 1, padding: "6px 0", borderRadius: 8, border: "none",
                        background: listType === "allowlist" ? "#10B981" : "transparent",
                        color: "#fff", fontSize: 12, fontWeight: 700, cursor: "pointer"
                      }}
                    >
                      ✓ Danh Sách Bỏ Qua ({allowlist.length})
                    </button>
                  </div>

                  <div style={{ background: "var(--bg-card)", border: "1px solid var(--border-color)", borderRadius: 14, padding: 12 }}>
                    <div style={{ fontSize: 11, color: "var(--text-muted)", marginBottom: 6 }}>
                      Thêm tên miền vào {listType === "denylist" ? "danh sách CHẶN" : "danh sách CHO PHÉP"}
                    </div>
                    <div style={{ display: "flex", gap: 8 }}>
                      <input
                        value={newDomainInput}
                        onChange={(e) => setNewDomainInput(e.target.value)}
                        placeholder="Ví dụ: shopee.vn hoặc *.ads.com"
                        style={{ flex: 1, background: "var(--bg-canvas)", border: "1px solid var(--border-color)", borderRadius: 8, padding: "8px 12px", color: "#fff", fontSize: 13, outline: "none" }}
                      />
                      <button
                        onClick={() => handleAddDomain()}
                        disabled={actionLoading === "add_domain"}
                        style={{
                          background: listType === "denylist" ? "#EF4444" : "#10B981",
                          color: "#fff", border: "none", padding: "8px 14px", borderRadius: 8, fontSize: 12, fontWeight: 700
                        }}
                      >
                        Thêm ➕
                      </button>
                    </div>
                  </div>

                  <div style={{ background: "var(--bg-card)", border: "1px solid var(--border-color)", borderRadius: 14, padding: 12 }}>
                    <div style={{ fontSize: 12, fontWeight: 700, color: "var(--text-primary)", marginBottom: 8 }}>
                      {listType === "denylist" ? "TÊN MIỀN ĐANG BỊ CHẶN" : "TÊN MIỀN ĐANG ĐƯỢC PHÉP"}
                    </div>
                    {(listType === "denylist" ? denylist : allowlist).length === 0 ? (
                      <div style={{ fontSize: 11, color: "var(--text-subtle)", textAlign: "center", padding: "16px 0" }}>
                        Chưa có tên miền nào trong danh sách
                      </div>
                    ) : (
                      <div className="flex flex-col gap-1.5 max-h-60 overflow-y-auto pr-1">
                        {(listType === "denylist" ? denylist : allowlist).map((item) => (
                          <div key={item.id} className="flex items-center justify-between p-2 rounded-lg" style={{ background: "var(--bg-canvas)", border: "1px solid var(--border-color)" }}>
                            <span style={{ fontSize: 12, fontFamily: "JetBrains Mono, monospace", color: "var(--text-primary)" }}>
                              {item.id}
                            </span>
                            <button
                              onClick={() => handleDeleteDomain(listType, item.id)}
                              disabled={actionLoading === `del_${item.id}`}
                              style={{ background: "transparent", border: "none", color: "#EF4444", fontSize: 12, cursor: "pointer", padding: "2px 6px" }}
                              title="Xóa khỏi danh sách"
                            >
                              ✕ Xóa
                            </button>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                </div>
              )}
            </div>
          ) : (
            <div style={{ background: "var(--bg-card)", border: "1px solid var(--border-color)", borderRadius: 16, padding: 16, textAlign: "center" }}>
              <div style={{ fontSize: 28, marginBottom: 6 }}>🚀</div>
              <div style={{ fontSize: 14, fontWeight: 700, color: "var(--text-primary)", marginBottom: 4 }}>
                Mở Khóa Bảng Quản Trị Trực Tiếp
              </div>
              <div style={{ fontSize: 11, color: "var(--text-muted)", maxWidth: 360, margin: "0 auto 12px auto", lineHeight: 1.5 }}>
                Nhập API Key để xem thống kê truy vấn thời gian thực, bật/tắt chặn TikTok, Facebook, Game, Web người lớn ngay trên router!
              </div>
              <button
                onClick={() => setShowApiKeyModal(true)}
                className="touch-btn"
                style={{ background: "#10B981", color: "#fff", border: "none", borderRadius: 10, padding: "10px 18px", fontSize: 13, fontWeight: 700 }}
              >
                Kết Nối API Key Ngay ⚡
              </button>
            </div>
          )}

          {/* Quick links & Disable Button */}
          <div className="grid grid-cols-2 gap-2 mt-1">
            <button
              onClick={() => window.open(`https://my.nextdns.io/${profileId || ""}`, "_blank")}
              className="touch-btn flex items-center justify-center gap-1.5"
              style={{ background: "var(--bg-card)", border: "1px solid var(--border-color)", borderRadius: 12, padding: "10px", color: "var(--text-muted)", fontSize: 11, fontWeight: 600 }}
            >
              <span>🔗</span> my.nextdns.io
            </button>
            <button
              onClick={() => window.open("https://test.nextdns.io", "_blank")}
              className="touch-btn flex items-center justify-center gap-1.5"
              style={{ background: "var(--bg-card)", border: "1px solid var(--border-color)", borderRadius: 12, padding: "10px", color: "#38BDF8", fontSize: 11, fontWeight: 600 }}
            >
              <span>🔍</span> test.nextdns.io
            </button>
          </div>

          <button
            onClick={handleDisable}
            disabled={saving}
            className="touch-btn w-full flex items-center justify-center gap-2 mt-1"
            style={{ background: "rgba(239, 68, 68, 0.1)", border: "1px solid rgba(239, 68, 68, 0.3)", borderRadius: 12, padding: "10px", color: "#EF4444", fontSize: 12, fontWeight: 600 }}
          >
            <span>⛔</span> {saving ? "Đang xử lý..." : "Tắt NextDNS (Khôi phục DNS nhà mạng)"}
          </button>
        </div>
      ) : (
        /* KHI CHƯA BẬT NEXTDNS */
        <div className="flex flex-col gap-3">
          <div style={{ background: "var(--bg-card)", border: "1px solid var(--border-color)", borderRadius: 16, padding: 16 }}>
            <div style={{ fontSize: 14, fontWeight: 700, color: "var(--text-primary)", marginBottom: 6 }}>
              Kích hoạt NextDNS bảo vệ toàn diện
            </div>
            <div style={{ fontSize: 12, color: "var(--text-muted)", lineHeight: 1.5, marginBottom: 12 }}>
              Định tuyến toàn bộ truy vấn DNS qua máy chủ bảo mật của NextDNS, tự động lọc quảng cáo, mã độc và các nội dung nguy hiểm cho tất cả thiết bị kết nối router.
            </div>
            <div style={{ display: "flex", gap: 8 }}>
              <input
                value={profileId}
                onChange={(e) => setProfileId(e.target.value)}
                placeholder="Nhập 6 ký tự Profile ID (vd: abc123)"
                style={{ flex: 1, background: "var(--bg-canvas)", border: "1px solid var(--border-color)", borderRadius: 10, padding: "10px 14px", color: "#fff", fontSize: 14, outline: "none", fontFamily: "JetBrains Mono, monospace" }}
              />
              <button
                onClick={handleSaveProfile}
                disabled={saving}
                style={{ background: "linear-gradient(135deg, #0284C7 0%, #10B981 100%)", color: "#fff", border: "none", borderRadius: 10, padding: "10px 18px", fontSize: 13, fontWeight: 700, cursor: "pointer" }}
              >
                {saving ? "..." : "Kích Hoạt"}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Modal Add a blocklist (Image 2) */}
      <AddBlocklistModal
        isOpen={isAddBlocklistOpen}
        onClose={() => setIsAddBlocklistOpen(false)}
        availableBlocklists={availableBlocklists}
        activeBlocklistIds={activeBlocklistIds}
        onAddBlocklist={handleAddBlocklist}
        onRemoveBlocklist={handleRemoveBlocklist}
      />
    </div>
  );
}
