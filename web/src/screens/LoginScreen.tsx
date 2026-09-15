import { useState } from 'react';
import { Logo } from '../components/Logo';
import { useTheme } from '../hooks/useTheme';
import { useAuth } from '../hooks/useAuth';
import { loginApi } from '../api/auth';
import { useToast } from '../components/Toast';

export default function LoginScreen() {
  const { isDark, toggleTheme } = useTheme();
  const { setSession } = useAuth();
  const { error: toastError, success: toastSuccess } = useToast();

  const [username, setUsername] = useState('admin');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [remember, setRemember] = useState(true);
  const [loading, setLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState('');

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!password) {
      setErrorMessage('Vui lòng nhập mật khẩu quản trị!');
      return;
    }

    setLoading(true);
    setErrorMessage('');

    try {
      const res = await loginApi(username.trim(), password, remember);
      if (res && res.authenticated && res.token) {
        toastSuccess(`Xin chào, ${res.user || username}!`);
        setSession(res.token, res.user || username);
      } else {
        const msg = res?.message || 'Tài khoản hoặc mật khẩu không chính xác!';
        setErrorMessage(msg);
        toastError(msg);
      }
    } catch (err: any) {
      const msg = err?.message || 'Không thể kết nối đến router. Vui lòng kiểm tra lại!';
      setErrorMessage(msg);
      toastError(msg);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen w-full flex items-center justify-center p-4 transition-colors relative" style={{ backgroundColor: 'var(--bg-page)' }}>
      {/* Top right theme switch */}
      <div className="absolute top-4 right-4 z-10">
        <button
          type="button"
          onClick={toggleTheme}
          className="px-3 py-1.5 rounded-xl text-xs font-semibold shadow-sm flex items-center gap-1.5 transition-colors"
          style={{ backgroundColor: 'var(--bg-surface)', border: '1px solid var(--border-color)', color: 'var(--text-main)' }}
        >
          <span>{isDark ? '☀️' : '🌙'}</span>
          <span>{isDark ? 'Giao diện Sáng' : 'Giao diện Tối'}</span>
        </button>
      </div>

      {/* Login Card */}
      <div className="w-full max-w-sm rounded-2xl shadow-xl p-6 sm:p-8 flex flex-col gap-6" style={{ backgroundColor: 'var(--bg-surface)', borderWidth: '1px', borderStyle: 'solid', borderColor: 'var(--border-color)' }}>
        {/* Header Logo */}
        <div className="flex flex-col items-center text-center">
          <Logo size={48} showText={false} className="mb-3" />
          <h1 className="text-xl font-black tracking-tight" style={{ color: 'var(--text-main)' }}>
            VCRT CONTROL CENTER
          </h1>
          <p className="text-xs mt-1" style={{ color: 'var(--text-muted)' }}>
            Xiaomi MiWiFi Mini · Quản Trị Mạng OpenWrt
          </p>
        </div>

        {/* Error Alert Box */}
        {errorMessage && (
          <div className="p-3 rounded-xl bg-rose-50 dark:bg-rose-950/50 border border-rose-200 dark:border-rose-900 text-rose-700 dark:text-rose-300 text-xs flex items-center gap-2 font-medium">
            <span>⚠️</span>
            <span className="flex-1">{errorMessage}</span>
          </div>
        )}

        {/* Form */}
        <form onSubmit={handleLogin} className="flex flex-col gap-4">
          <div>
            <label className="block text-xs font-semibold mb-1.5" style={{ color: 'var(--text-muted)' }}>
              Tài khoản
            </label>
            <input
              type="text"
              className="vcrt-input"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              placeholder="admin"
              autoComplete="username"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold mb-1.5" style={{ color: 'var(--text-muted)' }}>
              Mật khẩu quản trị
            </label>
            <div className="relative">
              <input
                type={showPassword ? 'text' : 'password'}
                className="vcrt-input pr-10"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="Nhập mật khẩu router..."
                autoComplete="current-password"
                autoFocus
              />
              <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                className="absolute right-2.5 top-1/2 -translate-y-1/2 text-sm" style={{ color: 'var(--text-soft)' }}
              >
                {showPassword ? '🙈' : '👁️'}
              </button>
            </div>
          </div>

          <div className="flex items-center justify-between text-xs pt-1">
            <label className="flex items-center gap-2 cursor-pointer select-none" style={{ color: 'var(--text-muted)' }}>
              <input
                type="checkbox"
                checked={remember}
                onChange={(e) => setRemember(e.target.checked)}
                className="w-4 h-4 rounded text-blue-600 focus:ring-blue-500" style={{ borderColor: 'var(--border-color)' }}
              />
              <span>Ghi nhớ đăng nhập</span>
            </label>
          </div>

          <button
            type="submit"
            disabled={loading}
            className="vcrt-btn vcrt-btn-primary w-full py-2.5 mt-2 font-bold text-sm shadow-md"
          >
            {loading ? (
              <>
                <span className="animate-spin text-sm">⏳</span>
                <span>Đang kết nối...</span>
              </>
            ) : (
              <span>Đăng Nhập Hệ Thống</span>
            )}
          </button>
        </form>

        <div className="text-center text-[11px] pt-4" style={{ color: 'var(--text-soft)', borderTop: '1px solid var(--border-subtle)' }}>
          Bảo mật phiên đăng nhập bằng mã hoá Token & HttpOnly Cookie
        </div>
      </div>
    </div>
  );
}
