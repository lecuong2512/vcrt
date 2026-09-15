export function SignalBars({ rssi }: { rssi: number }) {
  const bars = rssi > -55 ? 4 : rssi > -65 ? 3 : rssi > -75 ? 2 : 1;
  const color =
    bars >= 3
      ? 'bg-emerald-500'
      : bars === 2
      ? 'bg-amber-500'
      : 'bg-rose-500';

  return (
    <span className="inline-flex items-end gap-[2px] h-3.5" title={`RSSI: ${rssi} dBm`}>
      {[1, 2, 3, 4].map((b) => (
        <span
          key={b}
          className={`w-[3px] rounded-xs transition-colors ${
            b <= bars ? color : 'bg-slate-200 dark:bg-slate-700'
          }`}
          style={{ height: `${3 + b * 2.5}px` }}
        />
      ))}
    </span>
  );
}
