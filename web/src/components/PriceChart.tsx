import type { PricePoint } from '../lib/db';
import { money } from '../lib/format';

const W = 600;
const H = 150;
const PAD = { l: 8, r: 8, t: 12, b: 22 };

const LINES: { key: 'm' | 'p10' | 'med'; label: string; color: string; dash?: string }[] = [
  { key: 'med', label: 'Median', color: 'var(--color-accent-gold)' },
  { key: 'p10', label: 'p10', color: 'var(--color-text)' },
  { key: 'm', label: 'Min', color: 'var(--color-text-muted)', dash: '4 3' },
];

// One line per price statistic across runs, evenly spaced (runs are not equally far apart in time).
export default function PriceChart({ series }: { series: PricePoint[] }) {
  const values = series.flatMap((p) => LINES.map((l) => p[l.key])).filter((v): v is number => v !== null);
  if (!values.length) return <p class="text-sm text-[var(--color-text-muted)]">No prices.</p>;
  const lo = Math.min(...values);
  const hi = Math.max(...values);
  const span = hi - lo || 1;
  const x = (i: number) => (series.length === 1 ? W / 2 : PAD.l + (i / (series.length - 1)) * (W - PAD.l - PAD.r));
  const y = (v: number) => PAD.t + (1 - (v - lo) / span) * (H - PAD.t - PAD.b);

  return (
    <div>
      <svg viewBox={`0 0 ${W} ${H}`} class="w-full" role="img" aria-label="Price history">
        <line x1={PAD.l} x2={W - PAD.r} y1={H - PAD.b} y2={H - PAD.b} stroke="var(--color-border)" />
        {LINES.map((l) => {
          const pts = series.map((p, i) => (p[l.key] === null ? null : ([x(i), y(p[l.key] as number)] as const)));
          const path = pts.filter(Boolean).map((p) => p!.join(',')).join(' ');
          return (
            <g>
              {pts.filter(Boolean).length > 1 && (
                <polyline points={path} fill="none" stroke={l.color} stroke-width="1.5" stroke-dasharray={l.dash} />
              )}
              {pts.map((p) => p && <circle cx={p[0]} cy={p[1]} r="3" fill="var(--color-surface)" stroke={l.color} stroke-width="1.5" />)}
            </g>
          );
        })}
        {series.map((p, i) => (
          <text x={x(i)} y={H - 6} text-anchor={series.length === 1 ? 'middle' : i === 0 ? 'start' : i === series.length - 1 ? 'end' : 'middle'} font-size="10" fill="var(--color-text-muted)" font-family="var(--font-heading)">
            {(p.time ?? p.label).slice(5, 16)}
          </text>
        ))}
        <text x={PAD.l} y={9} font-size="10" fill="var(--color-text-muted)" font-family="var(--font-heading)">{money(hi)}</text>
      </svg>
      <div class="mt-1 flex flex-wrap items-center gap-4 font-heading text-xs">
        {LINES.map((l) => (
          <span class="flex items-center gap-2 text-[var(--color-text-muted)]">
            <svg width="18" height="6"><line x1="0" x2="18" y1="3" y2="3" stroke={l.color} stroke-width="2" stroke-dasharray={l.dash} /></svg>
            {l.label}: {series.map((p) => money(p[l.key])).join(' → ')}
          </span>
        ))}
      </div>
    </div>
  );
}
