import { useState } from "react";
import { loginApi } from "./api";
import { VCRTLogo } from "./VCRTLogo";

interface LoginScreenProps {
  onLoginSuccess: (user: string, token: string) => void;
}

export default function LoginScreen({ onLoginSuccess }: LoginScreenProps) {
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
        background: "#0B0F17",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        padding: "20px 16px",
        position: "relative",
        overflow: "hidden"
      }}
    >
      {/* Background radial glow */}
      <div
        style={{
          position: "absolute",
          top: "20%",
          left: "50%",
          transform: "translate(-50%, -50%)",
          width: "500px",
          height: "500px",
          background: "radial-gradient(circle, rgba(56, 189, 248, 0.08) 0%, rgba(16, 185, 129, 0.03) 40%, transparent 70%)",
          pointerEvents: "none"
        }}
      />

      <div
        style={{
          maxWidth: "420px",
          width: "100%",
          background: "#161F30",
          border: "1px solid #222F46",
          borderRadius: "20px",
          padding: "28px 24px",
          boxShadow: "0 20px 40px -15px rgba(0, 0, 0, 0.7)",
          position: "relative",
          zIndex: 1
        }}
      >
        {/* Top Logo & Title */}
        <div style={{ textAlign: "center", marginBottom: "24px" }}>
          <div className="flex justify-center mb-3">
            <VCRTLogo size={68} showText={false} />
          </div>
          <div style={{ fontSize: "20px", fontWeight: "800", color: "#F9FAFB", letterSpacing: "-0.02em" }}>
            VCRT CONTROL CENTER
          </div>
          <div style={{ fontSize: "12px", color: "#94A3B8", marginTop: "4px" }}>
            Xiaomi MiWiFi Mini · Quản Trị Hệ Thống Router
          </div>
        </div>

        {/* Error Alert */}
        {errorMsg && (
          <div
            style={{
              background: "rgba(239, 68, 68, 0.12)",
              border: "1px solid rgba(239, 68, 68, 0.3)",
              borderRadius: "10px",
              padding: "10px 14px",
              marginBottom: "18px",
              color: "#EF4444",
              fontSize: "12px",
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
        <form onSubmit={handleSubmit} style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
          <div>
            <label style={{ display: "block", fontSize: "12px", fontWeight: "600", color: "#94A3B8", marginBottom: "6px" }}>
              Tài khoản quản trị
            </label>
            <div style={{ position: "relative" }}>
              <input
                type="text"
                value={user}
                onChange={(e) => setUser(e.target.value)}
                placeholder="admin hoặc root"
                autoComplete="username"
                style={{
                  width: "100%",
                  background: "#0B0F17",
                  border: "1px solid #334155",
                  borderRadius: "10px",
                  padding: "10px 14px",
                  color: "#F9FAFB",
                  fontSize: "14px",
                  outline: "none",
                  boxSizing: "border-box"
                }}
              />
            </div>
          </div>

          <div>
            <label style={{ display: "block", fontSize: "12px", fontWeight: "600", color: "#94A3B8", marginBottom: "6px" }}>
              Mật khẩu truy cập
            </label>
            <div style={{ position: "relative" }}>
              <input
                type={showPass ? "text" : "password"}
                value={pass}
                onChange={(e) => setPass(e.target.value)}
                placeholder="Nhập mật khẩu..."
                autoComplete="current-password"
                style={{
                  width: "100%",
                  background: "#0B0F17",
                  border: "1px solid #334155",
                  borderRadius: "10px",
                  padding: "10px 42px 10px 14px",
                  color: "#F9FAFB",
                  fontSize: "14px",
                  outline: "none",
                  boxSizing: "border-box"
                }}
              />
              <button
                type="button"
                onClick={() => setShowPass(!showPass)}
                style={{
                  position: "absolute",
                  right: "10px",
                  top: "50%",
                  transform: "translateY(-50%)",
                  background: "transparent",
                  border: "none",
                  color: "#94A3B8",
                  cursor: "pointer",
                  fontSize: "14px",
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
            <label style={{ display: "flex", alignItems: "center", gap: "8px", cursor: "pointer", fontSize: "12px", color: "#94A3B8" }}>
              <input
                type="checkbox"
                checked={remember}
                onChange={(e) => setRemember(e.target.checked)}
                style={{ accentColor: "#10B981" }}
              />
              Ghi nhớ đăng nhập
            </label>
          </div>

          {/* Submit Button */}
          <button
            type="submit"
            disabled={loading}
            style={{
              background: "linear-gradient(135deg, #0284C7 0%, #10B981 100%)",
              color: "#FFFFFF",
              border: "none",
              borderRadius: "12px",
              padding: "12px 16px",
              fontSize: "14px",
              fontWeight: "700",
              cursor: loading ? "not-allowed" : "pointer",
              boxShadow: "0 4px 14px rgba(14, 165, 233, 0.4)",
              transition: "transform 0.1s ease",
              marginTop: "4px"
            }}
          >
            {loading ? "ĐANG ĐĂNG NHẬP..." : "ĐĂNG NHẬP HỆ THỐNG →"}
          </button>
        </form>

        {/* Info footer */}
        <div
          style={{
            marginTop: "20px",
            padding: "12px",
            background: "#0B0F17",
            borderRadius: "10px",
            border: "1px solid #1E293B",
            fontSize: "11px",
            color: "#64748B",
            lineHeight: 1.5
          }}
        >
          <strong style={{ color: "#38BDF8" }}>💡 Thông tin mặc định:</strong> Tài khoản{" "}
          <span style={{ color: "#F9FAFB", fontFamily: "monospace" }}>admin</span> / Mật khẩu{" "}
          <span style={{ color: "#F9FAFB", fontFamily: "monospace" }}>admin</span> (hoặc tài khoản root của router).
          Sau khi đăng nhập có thể đổi mật khẩu tại trang Cài đặt.
        </div>
      </div>
    </div>
  );
}
