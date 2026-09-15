import { useEffect, useRef } from 'react';

/**
 * usePolling: Smart Polling Hook
 * - Tự động tạm dừng khi tab bị ẩn (document.hidden) để tiết kiệm tài nguyên router & client
 * - Tự động gọi ngay khi tab hiển thị lại
 * - Cho phép tắt/bật qua điều kiện enabled
 */
export function usePolling(
  callback: () => void | Promise<void>,
  intervalMs: number,
  enabled: boolean = true
) {
  const savedCallback = useRef(callback);

  useEffect(() => {
    savedCallback.current = callback;
  }, [callback]);

  useEffect(() => {
    if (!enabled || intervalMs <= 0) return;

    let timerId: any = null;
    let isMounted = true;

    const execute = async () => {
      if (!isMounted) return;
      if (!document.hidden) {
        try {
          await savedCallback.current();
        } catch (e) {
          console.warn('[Polling Error]', e);
        }
      }
      if (isMounted) {
        timerId = setTimeout(execute, intervalMs);
      }
    };

    // Chạy lần đầu ngay lập tức
    execute();

    const handleVisibilityChange = () => {
      if (!document.hidden && isMounted) {
        if (timerId) clearTimeout(timerId);
        execute();
      }
    };

    document.addEventListener('visibilitychange', handleVisibilityChange);

    return () => {
      isMounted = false;
      if (timerId) clearTimeout(timerId);
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, [intervalMs, enabled]);
}
