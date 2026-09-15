export function Logo({
  size = 32,
  showText = true,
  className = ''
}: {
  size?: number;
  showText?: boolean;
  className?: string;
}) {
  return (
    <div className={`flex items-center gap-2.5 select-none ${className}`}>
      <div style={{ width: size, height: size }} className="relative shrink-0">
        <svg
          viewBox="0 0 40 40"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
          className="w-full h-full drop-shadow-sm"
        >
          <defs>
            <linearGradient id="logoGrad" x1="0" y1="0" x2="40" y2="40" gradientUnits="userSpaceOnUse">
              <stop offset="0%" stopColor="#3b82f6" />
              <stop offset="100%" stopColor="#1d4ed8" />
            </linearGradient>
            <linearGradient id="waveGrad" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#60a5fa" />
              <stop offset="100%" stopColor="#38bdf8" />
            </linearGradient>
          </defs>

          {/* Smooth rounded square background */}
          <rect width="40" height="40" rx="10" fill="url(#logoGrad)" />

          {/* Clean Wi-Fi Waves */}
          <path
            d="M12 16 C16 12 24 12 28 16"
            stroke="#ffffff"
            strokeWidth="2.5"
            strokeLinecap="round"
            opacity="0.9"
          />
          <path
            d="M15.5 20 C18 17.5 22 17.5 24.5 20"
            stroke="#ffffff"
            strokeWidth="2.5"
            strokeLinecap="round"
            opacity="0.95"
          />
          <circle cx="20" cy="24.5" r="2" fill="#ffffff" />

          {/* Router Antenna / Base accent */}
          <path
            d="M14 28.5 L26 28.5"
            stroke="#93c5fd"
            strokeWidth="1.8"
            strokeLinecap="round"
          />
        </svg>
      </div>

      {showText && (
        <div className="flex flex-col leading-none">
          <div className="flex items-center gap-1.5">
            <span className="font-extrabold text-base tracking-tight text-slate-900 dark:text-slate-100">
              VCRT
            </span>
            <span className="text-[10px] font-bold px-1.5 py-0.5 rounded bg-blue-500 text-white tracking-wider">
              OS
            </span>
          </div>
          <span className="text-[9px] font-medium text-blue-600 dark:text-blue-400 tracking-wider mt-0.5">
            ROUTER OS v2.0
          </span>
        </div>
      )}
    </div>
  );
}
