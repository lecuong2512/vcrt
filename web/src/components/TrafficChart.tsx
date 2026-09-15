import { useRef, useEffect, useState, useCallback } from 'react';

interface TrafficChartProps {
  items: { label: string; dl: number; ul: number }[];
  unit?: string;
  height?: number;
}

export function TrafficChart({ items, unit = 'MB/s', height = 160 }: TrafficChartProps) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [hoverIndex, setHoverIndex] = useState<number | null>(null);

  const safeItems = Array.isArray(items) ? items : [];

  const drawChart = useCallback(() => {
    const canvas = canvasRef.current;
    const container = containerRef.current;
    if (!canvas || !container) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const width = container.clientWidth;
    const dpr = window.devicePixelRatio || 1;

    canvas.width = width * dpr;
    canvas.height = height * dpr;
    ctx.scale(dpr, dpr);

    ctx.clearRect(0, 0, width, height);

    const padLeft = 42;
    const padRight = 16;
    const padTop = 16;
    const padBottom = 26;

    const plotW = Math.max(10, width - padLeft - padRight);
    const plotH = Math.max(10, height - padTop - padBottom);

    if (safeItems.length === 0) return;

    // Tìm max value
    const maxVal = Math.max(
      0.1,
      ...safeItems.map((it) => Math.max(Number(it?.dl || 0), Number(it?.ul || 0)))
    );
    const yCeil = Math.ceil(maxVal * 1.25 * 10) / 10 || 1;

    const getX = (idx: number) => {
      if (safeItems.length <= 1) return padLeft + plotW / 2;
      return padLeft + (idx / (safeItems.length - 1)) * plotW;
    };

    const getY = (val: number) => {
      const clamped = Math.max(0, Math.min(val, yCeil));
      return padTop + plotH - (clamped / yCeil) * plotH;
    };

    // Vẽ lưới ngang & Y-axis labels
    ctx.font = '10px monospace';
    ctx.fillStyle = '#94a3b8';
    ctx.textAlign = 'right';
    ctx.textBaseline = 'middle';

    const gridLines = 4;
    for (let i = 0; i <= gridLines; i++) {
      const ratio = i / gridLines;
      const y = padTop + plotH * (1 - ratio);
      const val = (yCeil * ratio).toFixed(1);

      ctx.beginPath();
      ctx.strokeStyle = 'rgba(148, 163, 184, 0.15)';
      ctx.lineWidth = 1;
      ctx.setLineDash([3, 3]);
      ctx.moveTo(padLeft, y);
      ctx.lineTo(width - padRight, y);
      ctx.stroke();
      ctx.setLineDash([]);

      ctx.fillText(val, padLeft - 6, y);
    }

    // Hàm vẽ đường diện tích và line
    const drawSeries = (
      points: { x: number; y: number }[],
      strokeColor: string,
      fillGradStart: string,
      fillGradEnd: string
    ) => {
      if (points.length < 2) return;

      // Area gradient
      const grad = ctx.createLinearGradient(0, padTop, 0, padTop + plotH);
      grad.addColorStop(0, fillGradStart);
      grad.addColorStop(1, fillGradEnd);

      ctx.beginPath();
      ctx.moveTo(points[0].x, points[0].y);

      for (let i = 0; i < points.length - 1; i++) {
        const xc = (points[i].x + points[i + 1].x) / 2;
        const yc = (points[i].y + points[i + 1].y) / 2;
        ctx.quadraticCurveTo(points[i].x, points[i].y, xc, yc);
      }
      ctx.lineTo(points[points.length - 1].x, points[points.length - 1].y);

      // Lưu path cho line
      const linePath = new Path2D();
      linePath.moveTo(points[0].x, points[0].y);
      for (let i = 0; i < points.length - 1; i++) {
        const xc = (points[i].x + points[i + 1].x) / 2;
        const yc = (points[i].y + points[i + 1].y) / 2;
        linePath.quadraticCurveTo(points[i].x, points[i].y, xc, yc);
      }
      linePath.lineTo(points[points.length - 1].x, points[points.length - 1].y);

      // Hoàn thành vùng fill
      ctx.lineTo(points[points.length - 1].x, padTop + plotH);
      ctx.lineTo(points[0].x, padTop + plotH);
      ctx.closePath();
      ctx.fillStyle = grad;
      ctx.fill();

      // Stroke đường chính
      ctx.beginPath();
      ctx.strokeStyle = strokeColor;
      ctx.lineWidth = 2;
      ctx.stroke(linePath);
    };

    const dlPoints = safeItems.map((it, idx) => ({ x: getX(idx), y: getY(Number(it?.dl || 0)) }));
    const ulPoints = safeItems.map((it, idx) => ({ x: getX(idx), y: getY(Number(it?.ul || 0)) }));

    // Vẽ Download (Xanh Dương) & Upload (Xanh Lá)
    drawSeries(dlPoints, '#3b82f6', 'rgba(59, 130, 246, 0.25)', 'rgba(59, 130, 246, 0.0)');
    drawSeries(ulPoints, '#10b981', 'rgba(16, 185, 129, 0.20)', 'rgba(16, 185, 129, 0.0)');

    // Vẽ nhãn X-axis
    ctx.font = '10px system-ui';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'top';

    const stepLabel = Math.max(1, Math.floor(safeItems.length / 6));
    safeItems.forEach((it, idx) => {
      if (idx % stepLabel === 0 || idx === safeItems.length - 1) {
        const x = getX(idx);
        ctx.fillStyle = idx === hoverIndex ? '#3b82f6' : '#64748b';
        ctx.fillText(it.label, x, padTop + plotH + 6);
      }
    });

    // Vẽ Hover Crosshair
    if (hoverIndex !== null && hoverIndex >= 0 && hoverIndex < safeItems.length) {
      const hX = getX(hoverIndex);
      const hDlY = dlPoints[hoverIndex].y;
      const hUlY = ulPoints[hoverIndex].y;

      // Vertical line
      ctx.beginPath();
      ctx.strokeStyle = '#94a3b8';
      ctx.setLineDash([2, 2]);
      ctx.lineWidth = 1;
      ctx.moveTo(hX, padTop);
      ctx.lineTo(hX, padTop + plotH);
      ctx.stroke();
      ctx.setLineDash([]);

      // Điểm chấm Download
      ctx.beginPath();
      ctx.arc(hX, hDlY, 4.5, 0, Math.PI * 2);
      ctx.fillStyle = '#3b82f6';
      ctx.fill();
      ctx.lineWidth = 1.5;
      ctx.strokeStyle = '#ffffff';
      ctx.stroke();

      // Điểm chấm Upload
      ctx.beginPath();
      ctx.arc(hX, hUlY, 4.5, 0, Math.PI * 2);
      ctx.fillStyle = '#10b981';
      ctx.fill();
      ctx.lineWidth = 1.5;
      ctx.strokeStyle = '#ffffff';
      ctx.stroke();
    }
  }, [safeItems, height, hoverIndex]);

  useEffect(() => {
    drawChart();
    const handleResize = () => drawChart();
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, [drawChart]);

  const handlePointer = (clientX: number) => {
    const container = containerRef.current;
    if (!container || safeItems.length === 0) return;
    const rect = container.getBoundingClientRect();
    const padLeft = 42;
    const padRight = 16;
    const plotW = Math.max(10, rect.width - padLeft - padRight);

    const relX = clientX - rect.left - padLeft;
    const ratio = Math.max(0, Math.min(1, relX / plotW));
    const idx = Math.round(ratio * (safeItems.length - 1));
    setHoverIndex(idx);
  };

  const activeItem = hoverIndex !== null && safeItems[hoverIndex] ? safeItems[hoverIndex] : null;

  return (
    <div className="relative w-full select-none" ref={containerRef}>
      {/* Legend & Active Stats */}
      <div className="flex flex-wrap items-center justify-between gap-2 mb-2 pb-1.5 border-b border-slate-200 dark:border-slate-800 text-xs">
        <div>
          {activeItem ? (
            <div className="flex items-center gap-2">
              <span className="font-semibold bg-slate-100 dark:bg-slate-800 px-1.5 py-0.5 rounded text-[10px]">
                {activeItem.label}
              </span>
              <span className="text-blue-600 dark:text-blue-400 font-medium">
                DL: <strong>{Number(activeItem.dl || 0).toFixed(2)}</strong> {unit}
              </span>
              <span className="text-emerald-600 dark:text-emerald-400 font-medium">
                UL: <strong>{Number(activeItem.ul || 0).toFixed(2)}</strong> {unit}
              </span>
            </div>
          ) : (
            <span className="text-slate-400 text-[11px]">Chạm hoặc rê chuột để xem chi tiết mốc thời gian</span>
          )}
        </div>

        <div className="flex items-center gap-3 text-[11px] font-medium">
          <span className="flex items-center gap-1.5 text-blue-600 dark:text-blue-400">
            <span className="w-2.5 h-1 bg-blue-500 rounded-sm" /> Tải về
          </span>
          <span className="flex items-center gap-1.5 text-emerald-600 dark:text-emerald-400">
            <span className="w-2.5 h-1 bg-emerald-500 rounded-sm" /> Tải lên
          </span>
        </div>
      </div>

      {/* Canvas Element */}
      <div
        className="w-full relative cursor-crosshair"
        onMouseMove={(e) => handlePointer(e.clientX)}
        onMouseLeave={() => setHoverIndex(null)}
        onTouchMove={(e) => {
          if (e.touches && e.touches.length > 0) handlePointer(e.touches[0].clientX);
        }}
        onTouchEnd={() => setHoverIndex(null)}
      >
        <canvas
          ref={canvasRef}
          style={{ width: '100%', height: `${height}px`, display: 'block' }}
        />
      </div>
    </div>
  );
}
