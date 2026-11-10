import { useMemo, useState } from 'preact/hooks';
import type { BagRow } from '../lib/db';
import { money, nf } from '../lib/format';
import { signal, SIGNAL_LABEL, THIN_LISTINGS, type Signal } from '../lib/bags';

type Key = 'name' | 'qty' | 'vendor' | 'm' | 'p10' | 'med' | 'listings' | 'learned_recipes' | 'unlearned_recipes' | 'signal';

const COLUMNS: { key: Key; label: string; num?: boolean }[] = [
  { key: 'name', label: 'Item' },
  { key: 'qty', label: 'Qty', num: true },
  { key: 'vendor', label: 'Vendor', num: true },
  { key: 'm', label: 'AH min', num: true },
  { key: 'p10', label: 'AH p10', num: true },
  { key: 'med', label: 'AH med', num: true },
  { key: 'listings', label: 'Listings', num: true },
  { key: 'learned_recipes', label: 'Learned', num: true },
  { key: 'unlearned_recipes', label: 'Not learned', num: true },
  { key: 'signal', label: 'Signal' },
];

const SIGNAL_CLASS: Record<Signal, string> = {
  'ah-higher': 'border-[var(--color-accent-gold)] text-[var(--color-accent-gold)]',
  close: 'border-[var(--color-border)] text-[var(--color-text)]',
  'vendor-higher': 'border-[var(--color-border)] text-[var(--color-text-muted)]',
  'no-data': 'border-dashed border-[var(--color-border)] text-[var(--color-text-muted)] opacity-70',
};

const SIGNAL_ORDER: Record<Signal, number> = { 'ah-higher': 0, close: 1, 'vendor-higher': 2, 'no-data': 3 };

function sortValue(r: BagRow, key: Key): string | number | null {
  if (key === 'signal') return SIGNAL_ORDER[signal(r)];
  return r[key] as string | number | null;
}

export default function BagsTable({ rows }: { rows: BagRow[] }) {
  const [query, setQuery] = useState('');
  const [onlyPriced, setOnlyPriced] = useState(false);
  const [onlyReagents, setOnlyReagents] = useState(false);
  const [sig, setSig] = useState<'all' | Signal>('all');
  const [sortKey, setSortKey] = useState<Key>('signal');
  const [asc, setAsc] = useState(true);

  const view = useMemo(() => {
    const q = query.trim().toLowerCase();
    const filtered = rows.filter(
      (r) =>
        (!q || (r.name ?? '').toLowerCase().includes(q)) &&
        (!onlyPriced || r.med !== null) &&
        (!onlyReagents || r.is_reagent === 1) &&
        (sig === 'all' || signal(r) === sig),
    );
    return [...filtered].sort((a, b) => {
      const av = sortValue(a, sortKey);
      const bv = sortValue(b, sortKey);
      if (av === null && bv === null) return 0;
      if (av === null) return 1; // nulls last in either direction
      if (bv === null) return -1;
      const cmp = typeof av === 'string' ? av.localeCompare(String(bv)) : (av as number) - (bv as number);
      return (asc ? cmp : -cmp) || (a.name ?? '').localeCompare(b.name ?? '');
    });
  }, [rows, query, onlyPriced, onlyReagents, sig, sortKey, asc]);

  const totals = useMemo(() => {
    let vendor = 0;
    let ah = 0;
    for (const r of view) {
      vendor += r.qty * (r.vendor ?? 0);
      if (r.med !== null) ah += r.qty * r.med;
    }
    return { vendor, ah };
  }, [view]);

  function sortBy(key: Key) {
    if (key === sortKey) setAsc(!asc);
    else {
      setSortKey(key);
      setAsc(true);
    }
  }

  const input =
    'rounded border border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-1.5 text-sm text-[var(--color-text)] placeholder:text-[var(--color-text-muted)] focus:border-[var(--color-accent-gold)] focus:outline-none';

  return (
    <div>
      <div class="mb-4 flex flex-wrap items-center gap-4">
        <input
          class={input}
          type="search"
          placeholder="Search item…"
          value={query}
          onInput={(e) => setQuery((e.target as HTMLInputElement).value)}
        />
        <select class={input} value={sig} onChange={(e) => setSig((e.target as HTMLSelectElement).value as 'all' | Signal)}>
          <option value="all">All signals</option>
          {(Object.keys(SIGNAL_LABEL) as Signal[]).map((s) => (
            <option value={s}>{SIGNAL_LABEL[s]}</option>
          ))}
        </select>
        <label class="flex items-center gap-2 text-sm text-[var(--color-text-muted)]">
          <input type="checkbox" checked={onlyPriced} onChange={(e) => setOnlyPriced((e.target as HTMLInputElement).checked)} />
          With AH data
        </label>
        <label class="flex items-center gap-2 text-sm text-[var(--color-text-muted)]">
          <input type="checkbox" checked={onlyReagents} onChange={(e) => setOnlyReagents((e.target as HTMLInputElement).checked)} />
          Reagents only
        </label>
        <span class="ml-auto font-heading text-xs tracking-widest uppercase text-[var(--color-text-muted)]">
          {view.length} / {rows.length} items
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
                    class={`uppercase tracking-widest transition-colors hover:text-[var(--color-text)] ${
                      sortKey === c.key ? 'text-[var(--color-accent-gold)]' : ''
                    }`}
                  >
                    {c.label}
                    {sortKey === c.key ? (asc ? ' ↑' : ' ↓') : ''}
                  </button>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {view.map((r) => {
              const s = signal(r);
              const thin = r.listings !== null && r.listings < THIN_LISTINGS;
              return (
                <tr>
                  <td class="font-heading" style={{ color: `var(--color-quality-${r.quality ?? 1})` }}>
                    {r.name ?? `#${r.item_id}`}
                  </td>
                  <td class="text-right">{nf.format(r.qty)}</td>
                  <td class="text-right">{money(r.vendor)}</td>
                  <td class="text-right">{money(r.m)}</td>
                  <td class="text-right">{money(r.p10)}</td>
                  <td class="text-right">{money(r.med)}</td>
                  <td class="text-right">
                    {r.listings === null ? '—' : nf.format(r.listings)}
                    {thin && (
                      <span title={`Fewer than ${THIN_LISTINGS} listings: price may be unreliable`} class="ml-1 text-[var(--color-accent-red)]">
                        ●
                      </span>
                    )}
                  </td>
                  <td class="text-right">{r.learned_recipes || '—'}</td>
                  <td class="text-right">{r.unlearned_recipes || '—'}</td>
                  <td>
                    <span class={`rounded border px-2 py-0.5 font-heading text-xs tracking-wide ${SIGNAL_CLASS[s]}`}>
                      {SIGNAL_LABEL[s]}
                    </span>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <p class="mt-4 text-sm text-[var(--color-text-muted)]">
        Nominal totals for the rows shown: vendor <span class="text-[var(--color-text)]">{money(totals.vendor)}</span> · AH median{' '}
        <span class="text-[var(--color-text)]">{money(totals.ah)}</span>. Selling a whole stack would move the AH price, so
        treat the AH figure as an upper bound. <span class="text-[var(--color-accent-red)]">●</span> = fewer than {THIN_LISTINGS} listings.
        Signals compare vendor and AH median only (AH higher: median ≥ 1.5× vendor or vendor pays 0); they are not recommendations.
      </p>
    </div>
  );
}
