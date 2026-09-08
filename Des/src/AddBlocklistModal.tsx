import { useState, useMemo } from "react";

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
  if (!isoString) return "";
  try {
    const d = new Date(isoString);
    const now = new Date();
    const diffSec = Math.floor((now.getTime() - d.getTime()) / 1000);
    if (diffSec < 60) return "just now";
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

function cleanWebsite(url: string | null): string {
  if (!url) return "";
  return url.replace(/^https?:\/\//, "").replace(/\/$/, "");
}

export default function AddBlocklistModal({
  isOpen,
  onClose,
  availableBlocklists,
  activeBlocklistIds,
  onAddBlocklist,
  onRemoveBlocklist
}: AddBlocklistModalProps) {
  const [search, setSearch] = useState("");
  const [sortBy, setSortBy] = useState<"popularity" | "entries" | "name">("popularity");
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  const filteredLists = useMemo(() => {
    let list = availableBlocklists.map((b) => {
      // Normalize nextdns-recommended
      if (b.id === "nextdns-recommended") {
        return {
          ...b,
          name: b.name || "NextDNS Ads & Trackers Blocklist",
          description:
            b.description ||
            "A comprehensive blocklist to block ads & trackers in all countries. This is the recommended starter blocklist."
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

    if (sortBy === "entries") {
      list.sort((a, b) => (b.entries || 0) - (a.entries || 0));
    } else if (sortBy === "name") {
      list.sort((a, b) => (a.name || a.id).localeCompare(b.name || b.id));
    }
    // "popularity" maintains NextDNS default recommended ranking

    return list;
  }, [availableBlocklists, search, sortBy]);

  if (!isOpen) return null;

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
    <div
      style={{
        position: "fixed",
        inset: 0,
        zIndex: 9999,
        background: "rgba(0, 0, 0, 0.75)",
        backdropFilter: "blur(4px)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        padding: "16px"
      }}
      onClick={onClose}
    >
      <div
        style={{
          width: "100%",
          maxWidth: "680px",
          maxHeight: "88vh",
          background: "#161F30",
          border: "1px solid #222F46",
          borderRadius: "16px",
          display: "flex",
          flexDirection: "column",
          boxShadow: "0 25px 50px -12px rgba(0, 0, 0, 0.8)",
          overflow: "hidden"
        }}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header matching NextDNS */}
        <div
          style={{
            padding: "16px 20px",
            borderBottom: "1px solid #222F46",
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between"
          }}
        >
          <div style={{ fontSize: "18px", fontWeight: "700", color: "#F9FAFB" }}>
            Add a blocklist
          </div>
          <button
            onClick={onClose}
            style={{
              background: "transparent",
              border: "none",
              color: "#94A3B8",
              fontSize: "18px",
              cursor: "pointer",
              padding: "4px"
            }}
          >
            ✕
          </button>
        </div>

        {/* Search & Sort Controls matching Image 2 */}
        <div
          style={{
            padding: "12px 20px",
            borderBottom: "1px solid #222F46",
            display: "flex",
            alignItems: "center",
            gap: "12px"
          }}
        >
          {/* Search box */}
          <div
            style={{
              flex: 1,
              display: "flex",
              alignItems: "center",
              gap: "8px",
              background: "#0B0F17",
              border: "1px solid #334155",
              borderRadius: "20px",
              padding: "6px 14px"
            }}
          >
            <span style={{ color: "#64748B", fontSize: "14px" }}>🔍</span>
            <input
              type="text"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search blocklists..."
              style={{
                flex: 1,
                background: "transparent",
                border: "none",
                color: "#F9FAFB",
                fontSize: "13px",
                outline: "none"
              }}
            />
            {search && (
              <button
                onClick={() => setSearch("")}
                style={{ background: "transparent", border: "none", color: "#64748B", cursor: "pointer", fontSize: "12px" }}
              >
                ✕
              </button>
            )}
          </div>

          {/* Sort selector */}
          <div style={{ position: "relative" }}>
            <select
              value={sortBy}
              onChange={(e) => setSortBy(e.target.value as any)}
              style={{
                background: "#0B0F17",
                border: "1px solid #334155",
                borderRadius: "8px",
                padding: "6px 12px",
                color: "#F9FAFB",
                fontSize: "12px",
                fontWeight: "600",
                cursor: "pointer",
                outline: "none"
              }}
            >
              <option value="popularity">↕ Popularity</option>
              <option value="entries">↕ Entries</option>
              <option value="name">↕ Name</option>
            </select>
          </div>
        </div>

        {/* Scrollable Blocklists List */}
        <div
          style={{
            flex: 1,
            overflowY: "auto",
            padding: "0",
            maxHeight: "calc(88vh - 140px)"
          }}
        >
          {filteredLists.length === 0 ? (
            <div style={{ padding: "40px 20px", textAlign: "center", color: "#64748B", fontSize: "13px" }}>
              Không tìm thấy bộ lọc nào phù hợp với "{search}"
            </div>
          ) : (
            filteredLists.map((b) => {
              const isAdded = activeBlocklistIds.includes(b.id);
              const isLoading = actionLoading === b.id;

              return (
                <div
                  key={b.id}
                  style={{
                    padding: "16px 20px",
                    borderBottom: "1px solid #1E293B",
                    display: "flex",
                    alignItems: "flex-start",
                    justifyContent: "space-between",
                    gap: "16px",
                    background: isAdded ? "rgba(59, 130, 246, 0.04)" : "transparent",
                    borderLeft: isAdded ? "3px solid #3B82F6" : "3px solid transparent",
                    transition: "background 0.15s ease"
                  }}
                >
                  <div style={{ flex: 1 }}>
                    <div style={{ fontSize: "14px", fontWeight: "700", color: "#F9FAFB", marginBottom: "4px" }}>
                      {b.name || b.id}
                    </div>
                    {b.description && (
                      <div style={{ fontSize: "12px", color: "#94A3B8", lineHeight: 1.45, marginBottom: "6px" }}>
                        {b.description}
                      </div>
                    )}
                    <div
                      style={{
                        display: "flex",
                        alignItems: "center",
                        gap: "8px",
                        flexWrap: "wrap",
                        fontSize: "11px",
                        color: "#64748B"
                      }}
                    >
                      {b.website && (
                        <a
                          href={b.website}
                          target="_blank"
                          rel="noreferrer"
                          style={{ color: "#38BDF8", textDecoration: "underline" }}
                          onClick={(e) => e.stopPropagation()}
                        >
                          {cleanWebsite(b.website)}
                        </a>
                      )}
                      {b.website && <span>•</span>}
                      <span>{(b.entries || 0).toLocaleString()} entries</span>
                      {b.updatedOn && (
                        <>
                          <span>•</span>
                          <span>Updated {formatTimeAgo(b.updatedOn)}</span>
                        </>
                      )}
                    </div>
                  </div>

                  <div style={{ flexShrink: 0, marginTop: "2px" }}>
                    {isAdded ? (
                      <button
                        onClick={() => handleToggle(b.id, true)}
                        disabled={isLoading}
                        style={{
                          background: "#DC2626",
                          color: "#FFFFFF",
                          border: "none",
                          borderRadius: "6px",
                          padding: "6px 14px",
                          fontSize: "11px",
                          fontWeight: "800",
                          letterSpacing: "0.05em",
                          cursor: isLoading ? "not-allowed" : "pointer"
                        }}
                      >
                        {isLoading ? "..." : "REMOVE"}
                      </button>
                    ) : (
                      <button
                        onClick={() => handleToggle(b.id, false)}
                        disabled={isLoading}
                        style={{
                          background: "#2563EB",
                          color: "#FFFFFF",
                          border: "none",
                          borderRadius: "6px",
                          padding: "6px 18px",
                          fontSize: "11px",
                          fontWeight: "800",
                          letterSpacing: "0.05em",
                          cursor: isLoading ? "not-allowed" : "pointer"
                        }}
                      >
                        {isLoading ? "..." : "ADD"}
                      </button>
                    )}
                  </div>
                </div>
              );
            })
          )}
        </div>
      </div>
    </div>
  );
}
