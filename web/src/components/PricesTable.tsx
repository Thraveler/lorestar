import { useMemo, useState } from 'preact/hooks';
import type { PriceSeries } from '../lib/db';
import { money, nf } from '../lib/format';
import PriceChart from './PriceChart';

type Key = 'name' | 'qty' | 'vendor' | 'med' | 'p10' | 'm' | 'listings' | 'change';

const COLUMNS: { key: Key; label: string; num?: boolean }[] = [
  { key: 'name', label: 'Item' },
  { key: 'qty', label: 'In bags', num: true },
  { key: 'vendor', label: 'Vendor', num: true },
  { key: 'm', label: 'AH min', num: true },
  { key: 'p10', label: 'AH p10', num: true },
  { key: 'med', label: 'AH med', num: true },
  { key: 'listings', label: 'Listings', num: true },
  { key: 'change', label: 'Med vs previous', num: true },
];

const last = (s: PriceSeries) => s.series[s.series.length - 1];

// Relative change of the median between the last two runs that priced the item.
function change(s: PriceSeries): number | null {
  if (s.series.length < 2) return null;
  const a = s.series[s.series.length - 2].med;
  const b = last(s).med;
  return a && b !== null ? (b - a) / a : null;
}

function sortValue(s: PriceSeries, key: Key): string | number | null {
  switch (key) {
    case 'name': return s.name ?? `~${String(s.item_id).padStart(8, '0')}`;
    case 'qty': return s.qty;
    case 'vendor': return s.vendor;
    case 'med': return last(s).med;
    case 'p10': return last(s).p10;
    case 'm': return last(s).m;
    case 'listings': return last(s).n;
    case 'change': return change(s);
  }
}

export default function PricesTable({ items }: { items: PriceSeries[] }) {
  const [query, setQuery] = useState('');
  const [sortKey, setSortKey] = useState<Key>('qty');
  const [asc, setAsc] = useState(false);
  const [open, setOpen] = useState<Set<number>>(new Set());

  const view = useMemo(() => {
    const q = query.trim().toLowerCase();
    const filtered = items.filter(
      (s) => !q || (s.name ?? '').toLowerCase().includes(q) || String(s.item_id).includes(q),
    );
    return [...filtered].sort((a, b) => {
      const av = sortValue(a, sortKey);
      const bv = sortValue(b, sortKey);
      if (av === null && bv === null) return 0;
      if (av === null) return 1;
      if (bv === null) return -1;
      const cmp = typeof av === 'string' ? av.localeCompare(String(bv)) : (av as number) - (bv as number);
      return (asc ? cmp : -cmp) || a.item_id - b.item_id;
    });
  }, [items, query, sortKey, asc]);

  function sortBy(key: Key) {
    if (key === sortKey) setAsc(!asc);
    else {
      setSortKey(key);
      setAsc(key === 'name');
    }
  }

  function toggle(id: number) {
    const next = new Set(open);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    setOpen(next);
  }

  const input =
    'rounded border border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-1.5 text-sm text-[var(--color-text)] placeholder:text-[var(--color-text-muted)] focus:border-[var(--color-accent-gold)] focus:outline-none';

  return (
    <div>
      <div class="mb-4 flex flex-wrap items-center gap-4">
        <input class={input} type="search" placeholder="Search name or item ID…" value={query} onInput={(e) => setQuery((e.target as HTMLInputElement).value)} />
        <span class="ml-auto font-heading text-xs tracking-widest uppercase text-[var(--color-text-muted)]">
          {nf.format(view.length)} / {nf.format(items.length)} items
        </span>
      </div>

      <div class="overflow-x-auto rounded border border-[var(--color-border)] bg-[var(--color-surface)]">
        <table class="data-table">
          <thead>
            <tr>
              {COLUMNS.map((c) => (
                <th class={c.num ? 'text-right' : ''}>
                  <button
                    type="button"
                    onClick={() => sortBy(c.key)}
                    class={`uppercase tracking-widest transition-colors hover:text-[var(--color-text)] ${sortKey === c.key ? 'text-[var(--color-accent-gold)]' : ''}`}
                  >
                    {c.label}
                    {sortKey === c.key ? (asc ? ' ↑' : ' ↓') : ''}
                  </button>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {view.slice(0, 300).map((s) => {
              const p = last(s);
              const ch = change(s);
              const isOpen = open.has(s.item_id);
              return (
                <>
                  <tr class="cursor-pointer" onClick={() => toggle(s.item_id)}>
                    <td class="font-heading">
                      <span class="mr-2 text-[var(--color-accent-gold)]">{isOpen ? '▾' : '▸'}</span>
                      {s.name ?? <span class="text-[var(--color-text-muted)]">Item #{s.item_id}</span>}
                    </td>
                    <td class="text-right">{s.qty || '—'}</td>
                    <td class="text-right">{s.vendor === null ? '—' : money(s.vendor)}</td>
                    <td class="text-right">{money(p.m)}</td>
                    <td class="text-right">{money(p.p10)}</td>
                    <td class="text-right">{money(p.med)}</td>
                    <td class="text-right">{p.n === null ? '—' : nf.format(p.n)}</td>
                    <td class="text-right">
                      {ch === null ? '—' : ch === 0 ? '0%' : `${ch > 0 ? '▲' : '▼'} ${Math.abs(ch * 100).toFixed(0)}%`}
                    </td>
                  </tr>
                  {isOpen && (
                    <tr>
                      <td colspan={COLUMNS.length} class="!whitespace-normal bg-[var(--color-bg)] p-4">
                        <PriceChart series={s.series} />
                      </td>
                    </tr>
                  )}
                </>
              );
            })}
          </tbody>
        </table>
      </div>
      {view.length > 300 && (
        <p class="mt-3 text-sm text-[var(--color-text-muted)]">Showing the first 300 rows. Use the search to narrow down.</p>
      )}
    </div>
  );
}
