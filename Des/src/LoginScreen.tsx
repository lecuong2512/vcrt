import { useState } from "react";
import { loginApi } from "./api";
import { VCRTLogo } from "./VCRTLogo";
import { useTheme } from "./ThemeContext";

interface LoginScreenProps {
  onLoginSuccess: (user: string, token: string) => void;
}

export default function LoginScreen({ onLoginSuccess }: LoginScreenProps) {
  const { theme, toggleTheme, isDark } = useTheme();
  const [user, setUser] = useState("admin");
  const [pass, setPass] = useState("");
  const [showPass, setShowPass] = useState(false);
  const [remember, setRemember] = useState(true);
  const [loading, setLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState("");

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!pass) {
      setErrorMsg("Vui lòng nhập mật khẩu quản trị!");
      return;
    }

    setLoading(true);
    setErrorMsg("");

    try {
      const res = await loginApi(user.trim(), pass);
      if (res && res.authenticated && res.token) {
        if (remember) {
          localStorage.setItem("vcrt_token", res.token);
          localStorage.setItem("vcrt_user", res.user || user);
        } else {
          sessionStorage.setItem("vcrt_token", res.token);
          sessionStorage.setItem("vcrt_user", res.user || user);
          localStorage.removeItem("vcrt_token");
        }
        onLoginSuccess(res.user || user, res.token);
      } else {
        setErrorMsg(res?.message || "Tài khoản hoặc mật khẩu không chính xác!");
      }
    } catch (err: any) {
      setErrorMsg("Không thể kết nối đến router. Vui lòng kiểm tra lại mạng!");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div
      style={{
        width: "100%",
        minHeight: "100vh",
        background: "var(--bg-canvas)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        padding: "24px 16px",
        position: "relative",
        overflow: "hidden",
        transition: "background-color 0.3s ease"
      }}
    >
      {/* Background radial glow */}
      <div
        style={{
          position: "absolute",
          top: "25%",
          left: "50%",
          transform: "translate(-50%, -50%)",
          width: "600px",
          height: "600px",
          background: isDark
            ? "radial-gradient(circle, rgba(56, 189, 248, 0.12) 0%, rgba(139, 92, 246, 0.05) 40%, transparent 70%)"
            : "radial-gradient(circle, rgba(2, 132, 199, 0.1) 0%, rgba(16, 185, 129, 0.06) 40%, transparent 70%)",
          pointerEvents: "none",
          transition: "background 0.3s ease"
        }}
      />

      {/* Top Floating Theme Switcher */}
      <div style={{ position: "absolute", top: 20, right: 20, zIndex: 10 }}>
        <button
          type="button"
          onClick={toggleTheme}
          className="touch-btn"
          style={{
            background: "var(--bg-card)",
            border: "1px solid var(--border-color)",
            color: "var(--text-primary)",
            padding: "8px 14px",
            borderRadius: "20px",
            fontSize: "13px",
            fontWeight: 600,
            display: "flex",
            alignItems: "center",
            gap: "8px",
            boxShadow: "var(--shadow-card)",
            backdropFilter: "blur(10px)"
          }}
          title={isDark ? "Chuyển sang Giao diện Sáng (Light)" : "Chuyển sang Giao diện Tối (Dark)"}
        >
          <span>{isDark ? "☀️" : "🌙"}</span>
          <span style={{ fontSize: 12 }}>{isDark ? "Giao diện Sáng" : "Giao diện Tối"}</span>
        </button>
      </div>

      <div
        className="vcrt-card"
        style={{
          maxWidth: "420px",
          width: "100%",
          padding: "32px 26px",
          position: "relative",
          zIndex: 1
        }}
      >
        {/* Top Logo & Title */}
        <div style={{ textAlign: "center", marginBottom: "28px" }}>
          <div className="flex justify-center mb-3">
            <VCRTLogo size={72} showText={false} />
          </div>
          <div style={{ fontSize: "22px", fontWeight: "800", color: "var(--text-primary)", letterSpacing: "-0.02em" }}>
            VCRT CONTROL CENTER
          </div>
          <div style={{ fontSize: "12px", color: "var(--text-muted)", marginTop: "6px" }}>
            Xiaomi MiWiFi Mini · Quản Trị Hệ Thống Router
          </div>
        </div>

        {/* Error Alert */}
        {errorMsg && (
          <div
            style={{
              background: isDark ? "rgba(239, 68, 68, 0.15)" : "#FEE2E2",
              border: "1px solid #EF4444",
              borderRadius: "12px",
              padding: "11px 14px",
              marginBottom: "20px",
              color: isDark ? "#FCA5A5" : "#B91C1C",
              fontSize: "12.5px",
              fontWeight: 600,
              display: "flex",
              alignItems: "center",
              gap: "8px"
            }}
          >
            <span>⚠️</span>
            <span>{errorMsg}</span>
          </div>
        )}

        {/* Form */}
        <form onSubmit={handleSubmit} style={{ display: "flex", flexDirection: "column", gap: "18px" }}>
          <div>
            <label style={{ display: "block", fontSize: "12px", fontWeight: "600", color: "var(--text-muted)", marginBottom: "6px" }}>
              Tài khoản quản trị
            </label>
            <div style={{ position: "relative" }}>
              <input
                type="text"
                value={user}
                onChange={(e) => setUser(e.target.value)}
                placeholder="admin hoặc root"
                autoComplete="username"
                className="vcrt-input"
                style={{ width: "100%" }}
              />
            </div>
          </div>

          <div>
            <label style={{ display: "block", fontSize: "12px", fontWeight: "600", color: "var(--text-muted)", marginBottom: "6px" }}>
              Mật khẩu truy cập
            </label>
            <div style={{ position: "relative" }}>
              <input
                type={showPass ? "text" : "password"}
                value={pass}
                onChange={(e) => setPass(e.target.value)}
                placeholder="Nhập mật khẩu..."
                autoComplete="current-password"
                className="vcrt-input"
                style={{ width: "100%", paddingRight: "44px" }}
              />
              <button
                type="button"
                onClick={() => setShowPass(!showPass)}
                style={{
                  position: "absolute",
                  right: "12px",
                  top: "50%",
                  transform: "translateY(-50%)",
                  background: "transparent",
                  border: "none",
                  color: "var(--text-muted)",
                  cursor: "pointer",
                  fontSize: "15px",
                  padding: "4px"
                }}
                title={showPass ? "Ẩn mật khẩu" : "Hiện mật khẩu"}
              >
                {showPass ? "👁️" : "👁️‍🗨️"}
              </button>
            </div>
          </div>

          {/* Remember me */}
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
            <label style={{ display: "flex", alignItems: "center", gap: "8px", cursor: "pointer", fontSize: "12.5px", color: "var(--text-muted)" }}>
              <input
                type="checkbox"
                checked={remember}
                onChange={(e) => setRemember(e.target.checked)}
                style={{ accentColor: "#0284C7", width: 16, height: 16, borderRadius: 4 }}
              />
              Ghi nhớ đăng nhập
            </label>
          </div>

          {/* Submit Button */}
          <button
            type="submit"
            disabled={loading}
            className="touch-btn"
            style={{
              background: "linear-gradient(135deg, #0284C7 0%, #10B981 100%)",
              color: "#FFFFFF",
              border: "none",
              borderRadius: "14px",
              padding: "13px 18px",
              fontSize: "14px",
              fontWeight: "700",
              cursor: loading ? "not-allowed" : "pointer",
              boxShadow: "0 6px 20px rgba(2, 132, 199, 0.35)",
              letterSpacing: "0.02em",
              marginTop: "4px"
            }}
          >
            {loading ? "ĐANG ĐĂNG NHẬP..." : "ĐĂNG NHẬP HỆ THỐNG →"}
          </button>
        </form>

        {/* Info footer */}
        <div
          className="vcrt-card-subtle"
          style={{
            marginTop: "22px",
            padding: "12px 14px",
            fontSize: "11px",
            color: "var(--text-subtle)",
            lineHeight: 1.5
          }}
        >
          <strong style={{ color: "var(--badge-text)" }}>💡 Thông tin mặc định:</strong> Tài khoản{" "}
          <span style={{ color: "var(--text-primary)", fontFamily: "monospace", fontWeight: 600 }}>admin</span> / Mật khẩu{" "}
          <span style={{ color: "var(--text-primary)", fontFamily: "monospace", fontWeight: 600 }}>admin</span> (hoặc tài khoản root của router).
          Sau khi đăng nhập có thể đổi mật khẩu tại trang Cài đặt.
        </div>
      </div>
    </div>
  );
}
