import React from "react";

export function VCRTLogo({ size = 36, showText = true, className = "" }: { size?: number; showText?: boolean; className?: string }) {
  return (
    <div className={`flex items-center gap-2.5 select-none ${className}`}>
      <div style={{ width: size, height: size, position: "relative", flexShrink: 0 }}>
        <svg
          viewBox="0 0 100 100"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
          style={{ width: "100%", height: "100%", filter: "drop-shadow(0 0 8px rgba(6, 182, 212, 0.45))" }}
        >
          <defs>
            <linearGradient id="vcrtHexGrad" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0%" stopColor="#06B6D4" />
              <stop offset="50%" stopColor="#3B82F6" />
              <stop offset="100%" stopColor="#8B5CF6" />
            </linearGradient>
            <linearGradient id="vcrtShieldGrad" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#083344" stopOpacity="0.9" />
              <stop offset="100%" stopColor="#0F172A" stopOpacity="0.95" />
            </linearGradient>
            <filter id="neonGlow" x="-20%" y="-20%" width="140%" height="140%">
              <feGaussianBlur stdDeviation="3" result="blur" />
              <feComposite in="SourceGraphic" in2="blur" operator="over" />
            </filter>
          </defs>

          {/* Hexagon Outer Circuit Border */}
          <polygon
            points="50,4 92,26 92,74 50,96 8,74 8,26"
            stroke="url(#vcrtHexGrad)"
            strokeWidth="3.5"
            strokeLinecap="round"
            strokeLinejoin="round"
            fill="url(#vcrtShieldGrad)"
          />

          {/* Circuit Tech Accents on Hex Corners */}
          <path d="M20 20 L28 16" stroke="#06B6D4" strokeWidth="2" strokeLinecap="round" />
          <path d="M80 20 L72 16" stroke="#06B6D4" strokeWidth="2" strokeLinecap="round" />
          <path d="M8 50 L16 50" stroke="#38BDF8" strokeWidth="2" strokeLinecap="round" />
          <path d="M92 50 L84 50" stroke="#38BDF8" strokeWidth="2" strokeLinecap="round" />
          <path d="M20 80 L28 84" stroke="#8B5CF6" strokeWidth="2" strokeLinecap="round" />
          <path d="M80 80 L72 84" stroke="#8B5CF6" strokeWidth="2" strokeLinecap="round" />

          {/* Wi-Fi Antenna Radar Waves */}
          <path
            d="M34 38 A20 20 0 0 1 66 38"
            stroke="#38BDF8"
            strokeWidth="3"
            strokeLinecap="round"
            opacity="0.9"
          />
          <path
            d="M40 46 A12 12 0 0 1 60 46"
            stroke="#06B6D4"
            strokeWidth="2.5"
            strokeLinecap="round"
            opacity="0.8"
          />
          <circle cx="50" cy="52" r="2.5" fill="#22D3EE" />

          {/* Stylized Sharp V Emblem */}
          <path
            d="M26 44 L50 82 L74 44 L64 44 L50 68 L36 44 Z"
            fill="url(#vcrtHexGrad)"
            filter="url(#neonGlow)"
          />

          {/* Inner Light Flare */}
          <path
            d="M50 78 L50 66"
            stroke="#E0F2FE"
            strokeWidth="1.5"
            strokeLinecap="round"
            opacity="0.8"
          />
        </svg>
      </div>

      {showText && (
        <div className="flex flex-col leading-none">
          <div className="flex items-center gap-1.5">
            <span style={{ fontSize: 16, fontWeight: 900, letterSpacing: "0.08em", color: "#F8FAFC" }}>
              VCRT
            </span>
            <span
              style={{
                fontSize: 10,
                fontWeight: 800,
                padding: "1px 5px",
                borderRadius: 4,
                background: "linear-gradient(135deg, #06B6D4, #3B82F6)",
                color: "#FFFFFF",
                letterSpacing: "0.05em"
              }}
            >
              OS
            </span>
          </div>
          <span style={{ fontSize: 9, fontWeight: 600, color: "#06B6D4", letterSpacing: "0.12em", marginTop: 2 }}>
            CYBER ROUTER
          </span>
        </div>
      )}
    </div>
  );
}
