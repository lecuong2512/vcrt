import { ReactNode } from 'react';
import { Logo } from './Logo';
import { useTheme } from '../hooks/useTheme';
import { useAuth } from '../hooks/useAuth';

export type TabType = 'dashboard' | 'clients' | 'wifi' | 'nextdns' | 'settings';

interface LayoutProps {
  currentTab: TabType;
  onSelectTab: (tab: TabType) => void;
  children: ReactNode;
}

const NAV_ITEMS: { id: TabType; label: string; icon: string }[] = [
  { id: 'dashboard', label: 'Tổng quan', icon: '⚡' },
  { id: 'clients', label: 'Thiết bị', icon: '📱' },
  { id: 'wifi', label: 'Wi-Fi', icon: '📶' },
  { id: 'nextdns', label: 'NextDNS', icon: '🛡️' },
  { id: 'settings', label: 'Cài đặt', icon: '⚙️' }
];

export function Layout({ currentTab, onSelectTab, children }: LayoutProps) {
  const { isDark, toggleTheme } = useTheme();
  const { user, logout } = useAuth();

  return (
    <div className="flex flex-col h-screen w-screen overflow-hidden" style={{ backgroundColor: 'var(--bg-page)', color: 'var(--text-main)' }}>
      {/* Top Header Bar */}
      <header className="sticky top-0 z-40 h-14 px-4 backdrop-blur-md flex items-center justify-between shrink-0" style={{ backgroundColor: 'color-mix(in srgb, var(--bg-surface) 80%, transparent)', borderBottom: '1px solid var(--border-color)' }}>
        <div className="flex items-center gap-3">
          <Logo size={32} showText={true} />
        </div>

        {/* Desktop Nav Items */}
        <div className="hidden md:flex items-center gap-1 p-1 rounded-xl" style={{ backgroundColor: 'var(--bg-surface-muted)', border: '1px solid var(--border-color)' }}>
          {NAV_ITEMS.map((item) => {
            const isActive = currentTab === item.id;
            return (
              <button
                key={item.id}
                onClick={() => onSelectTab(item.id)}
                className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold transition-all ${
                  isActive
                    ? 'bg-blue-600 text-white shadow-sm'
                    : ''
                }` }
                style={!isActive ? { color: 'var(--text-muted)' } : undefined}
              >
                <span>{item.icon}</span>
                <span>{item.label}</span>
              </button>
            );
          })}
        </div>

        {/* Right Actions: Theme Toggle, User, Logout */}
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={toggleTheme}
            className="w-8 h-8 rounded-lg flex items-center justify-center text-sm transition-colors"
            style={{ backgroundColor: 'var(--bg-surface-muted)', border: '1px solid var(--border-color)', color: 'var(--text-muted)' }}
            title={isDark ? 'Chuyển sang Giao diện Sáng' : 'Chuyển sang Giao diện Tối'}
          >
            {isDark ? '☀️' : '🌙'}
          </button>

          <div className="hidden sm:flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-blue-50 dark:bg-blue-950/40 border border-blue-200 dark:border-blue-900/50 text-blue-700 dark:text-blue-300 text-xs font-semibold">
            <span>👤</span>
            <span>{user}</span>
          </div>

          <button
            type="button"
            onClick={logout}
            className="px-2.5 py-1 rounded-lg border border-rose-200 dark:border-rose-900/50 text-rose-600 dark:text-rose-400 hover:bg-rose-50 dark:hover:bg-rose-950/40 text-xs font-semibold transition-colors flex items-center gap-1"
            title="Đăng xuất"
          >
            <span>🚪</span>
            <span className="hidden sm:inline">Đăng xuất</span>
          </button>
        </div>
      </header>

      {/* Main Content Area */}
      <main className="flex-1 overflow-y-auto overflow-x-hidden pb-20 md:pb-6 scroll-smooth">
        <div className="max-w-5xl mx-auto w-full p-4 sm:p-6">{children}</div>
      </main>

      {/* Bottom Navigation for Mobile */}
      <nav className="md:hidden fixed bottom-0 left-0 right-0 z-40 pb-safe backdrop-blur-lg" style={{ backgroundColor: 'color-mix(in srgb, var(--bg-surface) 90%, transparent)', borderTop: '1px solid var(--border-color)' }}>
        <div className="flex items-stretch h-14">
          {NAV_ITEMS.map((item) => {
            const isActive = currentTab === item.id;
            return (
              <button
                key={item.id}
                onClick={() => onSelectTab(item.id)}
                className={`flex-1 flex flex-col items-center justify-center gap-1 relative transition-colors ${
                  isActive ? 'text-blue-500' : ''
                }`}
                style={!isActive ? { color: 'var(--text-soft)' } : undefined}
              >
                <span className="text-base leading-none">{item.icon}</span>
                <span className={`text-[10px] ${isActive ? 'font-bold' : 'font-medium'}`}>
                  {item.label}
                </span>
                {isActive && (
                  <span className="absolute top-0 w-8 h-0.5 bg-blue-500 rounded-b-full shadow-sm" />
                )}
              </button>
            );
          })}
        </div>
      </nav>
    </div>
  );
}
