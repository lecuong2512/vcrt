import { useState, useMemo } from 'react';
import { Modal } from './Modal';

export interface CommunityBlocklist {
  id: string;
  name: string | null;
  description: string | null;
  website: string | null;
  entries: number;
  updatedOn: string;
}

interface AddBlocklistModalProps {
  isOpen: boolean;
  onClose: () => void;
  availableBlocklists: CommunityBlocklist[];
  activeBlocklistIds: string[];
  onAddBlocklist: (id: string) => Promise<void>;
  onRemoveBlocklist: (id: string) => Promise<void>;
}

function formatTimeAgo(isoString: string): string {
  if (!isoString) return '';
  try {
    const d = new Date(isoString);
    const now = new Date();
    const diffSec = Math.floor((now.getTime() - d.getTime()) / 1000);
    if (diffSec < 60) return 'vừa xong';
    const diffMin = Math.floor(diffSec / 60);
    if (diffMin < 60) return `${diffMin} phút trước`;
    const diffHr = Math.floor(diffMin / 60);
    if (diffHr < 24) return `${diffHr} giờ trước`;
    const diffDays = Math.floor(diffHr / 24);
    return `${diffDays} ngày trước`;
  } catch {
    return '';
  }
}

function cleanWebsite(url: string | null): string {
  if (!url) return '';
  return url.replace(/^https?:\/\//, '').replace(/\/$/, '');
}

export function AddBlocklistModal({
  isOpen,
  onClose,
  availableBlocklists,
  activeBlocklistIds,
  onAddBlocklist,
  onRemoveBlocklist
}: AddBlocklistModalProps) {
  const [search, setSearch] = useState('');
  const [sortBy, setSortBy] = useState<'popularity' | 'entries' | 'name'>('popularity');
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  const filteredLists = useMemo(() => {
    let list = availableBlocklists.map((b) => {
      if (b.id === 'nextdns-recommended') {
        return {
          ...b,
          name: b.name || 'NextDNS Ads & Trackers Blocklist',
          description:
            b.description ||
            'Danh sách khuyến nghị chuẩn chặn quảng cáo và theo dõi toàn cầu.'
        };
      }
      return b;
    });

    if (search.trim()) {
      const q = search.toLowerCase();
      list = list.filter(
        (b) =>
          (b.name && b.name.toLowerCase().includes(q)) ||
          (b.description && b.description.toLowerCase().includes(q)) ||
          b.id.toLowerCase().includes(q)
      );
    }

    if (sortBy === 'entries') {
      list.sort((a, b) => (b.entries || 0) - (a.entries || 0));
    } else if (sortBy === 'name') {
      list.sort((a, b) => (a.name || a.id).localeCompare(b.name || b.id));
    }

    return list;
  }, [availableBlocklists, search, sortBy]);

  const handleToggle = async (id: string, isAdded: boolean) => {
    setActionLoading(id);
    try {
      if (isAdded) {
        await onRemoveBlocklist(id);
      } else {
        await onAddBlocklist(id);
      }
    } finally {
      setActionLoading(null);
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Thêm Danh Sách Chặn (NextDNS Blocklists)"
      maxWidth="max-w-2xl"
    >
      <div className="flex flex-col gap-3">
        {/* Search & Sort Header */}
        <div className="flex flex-col sm:flex-row gap-2">
          <input
            type="text"
            className="vcrt-input flex-1"
            placeholder="Tìm kiếm danh sách chặn theo tên hoặc mô tả..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          <select
            className="vcrt-input sm:w-48"
            value={sortBy}
            onChange={(e) => setSortBy(e.target.value as any)}
          >
            <option value="popularity">Sắp xếp: Phổ biến</option>
            <option value="entries">Sắp xếp: Số lượng rules</option>
            <option value="name">Sắp xếp: Tên A-Z</option>
          </select>
        </div>

        {/* List Content */}
        <div className="flex flex-col gap-2.5 max-h-[60vh] overflow-y-auto pr-1">
          {filteredLists.length === 0 ? (
            <div className="p-8 text-center text-sm text-slate-400">
              Không tìm thấy danh sách chặn phù hợp với từ khóa.
            </div>
          ) : (
            filteredLists.map((b) => {
              const isAdded = activeBlocklistIds.includes(b.id);
              const isLoading = actionLoading === b.id;

              return (
                <div
                  key={b.id}
                  className="p-3.5 rounded-xl border border-slate-200 dark:border-slate-700/60 bg-slate-50/50 dark:bg-slate-800/40 flex items-start justify-between gap-3 hover:border-slate-300 dark:hover:border-slate-600 transition-all"
                >
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="font-bold text-sm text-slate-900 dark:text-slate-100">
                        {b.name || b.id}
                      </span>
                      {b.entries > 0 && (
                        <span className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-blue-100 dark:bg-blue-950/60 text-blue-700 dark:text-blue-300 font-semibold">
                          {b.entries.toLocaleString()} entries
                        </span>
                      )}
                    </div>

                    {b.description && (
                      <p className="text-xs text-slate-600 dark:text-slate-400 mt-1 leading-relaxed">
                        {b.description}
                      </p>
                    )}

                    <div className="flex items-center gap-3 text-[11px] text-slate-400 mt-2">
                      {b.website && (
                        <a
                          href={b.website}
                          target="_blank"
                          rel="noreferrer"
                          className="hover:text-blue-500 underline truncate max-w-xs"
                        >
                          🌐 {cleanWebsite(b.website)}
                        </a>
                      )}
                      {b.updatedOn && <span>🕒 {formatTimeAgo(b.updatedOn)}</span>}
                    </div>
                  </div>

                  <button
                    onClick={() => handleToggle(b.id, isAdded)}
                    disabled={isLoading}
                    className={`vcrt-btn text-xs py-1.5 px-3 shrink-0 ${
                      isAdded
                        ? 'bg-rose-50 dark:bg-rose-950/60 text-rose-600 dark:text-rose-300 border border-rose-200 dark:border-rose-800 hover:bg-rose-100'
                        : 'bg-blue-600 text-white hover:bg-blue-700'
                    }`}
                  >
                    {isLoading ? '...' : isAdded ? 'Gỡ Bỏ' : 'Thêm Vào'}
                  </button>
                </div>
              );
            })
          )}
        </div>
      </div>
    </Modal>
  );
}
