import { useState, useEffect, createContext, useContext, ReactNode, useCallback } from 'react';

export type ToastType = 'success' | 'error' | 'info' | 'warning';

interface ToastItem {
  id: string;
  type: ToastType;
  message: string;
  duration?: number;
}

interface ToastContextType {
  toast: (message: string, type?: ToastType, duration?: number) => void;
  success: (message: string, duration?: number) => void;
  error: (message: string, duration?: number) => void;
  info: (message: string, duration?: number) => void;
  warning: (message: string, duration?: number) => void;
}

const ToastContext = createContext<ToastContextType>({
  toast: () => {},
  success: () => {},
  error: () => {},
  info: () => {},
  warning: () => {}
});

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<ToastItem[]>([]);

  const removeToast = useCallback((id: string) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, []);

  const toast = useCallback(
    (message: string, type: ToastType = 'info', duration: number = 3500) => {
      const id = `${Date.now()}_${Math.random().toString(36).substr(2, 5)}`;
      setToasts((prev) => [...prev.slice(-3), { id, type, message, duration }]);
    },
    []
  );

  const success = useCallback((msg: string, dur?: number) => toast(msg, 'success', dur), [toast]);
  const error = useCallback((msg: string, dur?: number) => toast(msg, 'error', dur || 4500), [toast]);
  const info = useCallback((msg: string, dur?: number) => toast(msg, 'info', dur), [toast]);
  const warning = useCallback((msg: string, dur?: number) => toast(msg, 'warning', dur || 4000), [toast]);

  return (
    <ToastContext.Provider value={{ toast, success, error, info, warning }}>
      {children}
      <div className="fixed top-4 right-4 z-50 flex flex-col gap-2 max-w-sm w-full pointer-events-none px-3">
        {toasts.map((t) => (
          <ToastCard key={t.id} item={t} onDismiss={() => removeToast(t.id)} />
        ))}
      </div>
    </ToastContext.Provider>
  );
}

function ToastCard({ item, onDismiss }: { item: ToastItem; onDismiss: () => void }) {
  useEffect(() => {
    const timer = setTimeout(onDismiss, item.duration || 3500);
    return () => clearTimeout(timer);
  }, [item, onDismiss]);

  const typeStyles: Record<ToastType, { bg: string; border: string; text: string; icon: string }> = {
    success: {
      bg: 'bg-emerald-50 dark:bg-emerald-950/80',
      border: 'border-emerald-300 dark:border-emerald-700',
      text: 'text-emerald-800 dark:text-emerald-200',
      icon: '✅'
    },
    error: {
      bg: 'bg-rose-50 dark:bg-rose-950/80',
      border: 'border-rose-300 dark:border-rose-700',
      text: 'text-rose-800 dark:text-rose-200',
      icon: '❌'
    },
    warning: {
      bg: 'bg-amber-50 dark:bg-amber-950/80',
      border: 'border-amber-300 dark:border-amber-700',
      text: 'text-amber-800 dark:text-amber-200',
      icon: '⚠️'
    },
    info: {
      bg: 'bg-blue-50 dark:bg-blue-950/80',
      border: 'border-blue-300 dark:border-blue-700',
      text: 'text-blue-800 dark:text-blue-200',
      icon: 'ℹ️'
    }
  };

  const currentStyle = typeStyles[item.type];

  return (
    <div
      onClick={onDismiss}
      className={`pointer-events-auto flex items-start gap-2.5 p-3.5 rounded-xl border shadow-lg backdrop-blur-md transition-all animate-in fade-in slide-in-from-top-3 cursor-pointer ${currentStyle.bg} ${currentStyle.border} ${currentStyle.text}`}
    >
      <span className="text-base select-none leading-none pt-0.5">{currentStyle.icon}</span>
      <div className="flex-1 text-xs font-semibold leading-relaxed break-words">{item.message}</div>
      <button
        onClick={(e) => {
          e.stopPropagation();
          onDismiss();
        }}
        className="text-xs opacity-60 hover:opacity-100 transition-opacity ml-1"
      >
        ✕
      </button>
    </div>
  );
}

export function useToast() {
  return useContext(ToastContext);
}
