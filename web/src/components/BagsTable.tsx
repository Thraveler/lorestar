import { useMemo, useState } from 'preact/hooks';
import type { BagRow } from '../lib/db';
import { money, nf } from '../lib/format';
import { ACTION_LABEL, DEFAULTS, NOTES, REASONS, type Action } from '../lib/rules';

type Key = 'name' | 'qty' | 'vendor' | 'm' | 'p10' | 'med' | 'listings' | 'learned_recipes' | 'unlearned_recipes' | 'advice' | 'gain';

const COLUMNS: { key: Key; label: string; num?: boolean }[] = [
  { key: 'name', label: 'Item' },
  { key: 'qty', label: 'Qty', num: true },
  { key: 'vendor', label: 'Vendor', num: true },
  { key: 'med', label: 'AH med', num: true },
  { key: 'listings', label: 'Listings', num: true },
  { key: 'learned_recipes', label: 'Learned', num: true },
  { key: 'unlearned_recipes', label: 'Not learned', num: true },
  { key: 'advice', label: 'Advice' },
  { key: 'gain', label: 'Worth', num: true },
];

const ACTION_CLASS: Record<Action, string> = {
  sell_ah: 'border-[var(--color-accent-gold)] text-[var(--color-accent-gold)]',
  vendor: 'border-[var(--color-text)] text-[var(--color-text)]',
  discard: 'border-[var(--color-accent-red)] text-[var(--color-accent-red)]',
  review: 'border-dashed border-[var(--color-text-muted)] text-[var(--color-text)]',
  keep: 'border-[var(--color-border)] text-[var(--color-text-muted)]',
};

const ACTION_ORDER: Record<Action, number> = { sell_ah: 0, vendor: 1, discard: 2, review: 3, keep: 4 };

function sortValue(r: BagRow, key: Key): string | number | null {
  if (key === 'advice') return r.advice ? ACTION_ORDER[r.advice.action] : 9;
  if (key === 'gain') return r.advice ? r.advice.total : null;
  return r[key] as string | number | null;
}

function adviceText(r: BagRow): string {
  const a = r.advice;
  if (!a) return '';
  if (a.keepQty > 0 && a.sellQty > 0) {
    return `keep ${a.keepQty}, ${a.action === 'review' ? 'review' : a.action === 'sell_ah' ? 'sell' : a.action} ${a.sellQty}`;
  }
  return '';
}

export default function BagsTable({ rows }: { rows: BagRow[] }) {
  const [query, setQuery] = useState('');
  const [onlyPriced, setOnlyPriced] = useState(false);
  const [onlyReagents, setOnlyReagents] = useState(false);
  const [action, setAction] = useState<'all' | Action>('all');
  const [sortKey, setSortKey] = useState<Key>('advice');
  const [asc, setAsc] = useState(true);

  const view = useMemo(() => {
    const q = query.trim().toLowerCase();
    const filtered = rows.filter(
      (r) =>
        (!q || (r.name ?? '').toLowerCase().includes(q)) &&
        (!onlyPriced || r.med !== null) &&
        (!onlyReagents || r.is_reagent === 1) &&
        (action === 'all' || r.advice?.action === action),
    );
    return [...filtered].sort((a, b) => {
      const av = sortValue(a, sortKey);
      const bv = sortValue(b, sortKey);
      if (av === null && bv === null) return 0;
      if (av === null) return 1; // nulls last in either direction
      if (bv === null) return -1;
      const cmp = typeof av === 'string' ? av.localeCompare(String(bv)) : (av as number) - (bv as number);
      return (asc ? cmp : -cmp) || (b.advice?.total ?? 0) - (a.advice?.total ?? 0) || (a.name ?? '').localeCompare(b.name ?? '');
    });
  }, [rows, query, onlyPriced, onlyReagents, action, sortKey, asc]);

  const totals = useMemo(() => {
    const t = { sell_ah: 0, vendor: 0, slots: 0, counts: { sell_ah: 0, vendor: 0, discard: 0, review: 0, keep: 0 } as Record<Action, number> };
    for (const r of view) {
      if (!r.advice) continue;
      t.counts[r.advice.action] += 1;
      if (r.advice.action === 'sell_ah') t.sell_ah += r.advice.total;
      if (r.advice.action === 'vendor') t.vendor += r.advice.total;
      t.slots += r.advice.slotsFreed;
    }
    return t;
  }, [view]);

  function sortBy(key: Key) {
    if (key === sortKey) setAsc(!asc);
    else {
      setSortKey(key);
      setAsc(key === 'name' || key === 'advice');
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
        <select class={input} value={action} onChange={(e) => setAction((e.target as HTMLSelectElement).value as 'all' | Action)}>
          <option value="all">All advice</option>
          {(Object.keys(ACTION_LABEL) as Action[]).map((a) => (
            <option value={a}>{ACTION_LABEL[a]}</option>
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
              const a = r.advice;
              const thin = r.listings !== null && r.listings < DEFAULTS.minListings;
              const split = adviceText(r);
              return (
                <tr>
                  <td class="!whitespace-normal">
                    <div class="font-heading" style={{ color: `var(--color-quality-${r.quality ?? 1})` }}>
                      {r.name ?? `#${r.item_id}`}
                    </div>
                    {a && (
                      <div class="text-sm text-[var(--color-text-muted)]">
                        {REASONS[a.reason] ?? a.reason}
                        {a.notes.length > 0 && <> · {a.notes.map((n) => NOTES[n] ?? n).join(' · ')}</>}
                      </div>
                    )}
                  </td>
                  <td class="text-right">{nf.format(r.qty)}</td>
                  <td class="text-right">{money(r.vendor)}</td>
                  <td class="text-right">{money(r.med)}</td>
                  <td class="text-right">
                    {r.listings === null ? '—' : nf.format(r.listings)}
                    {thin && (
                      <span title={`Fewer than ${DEFAULTS.minListings} listings: price may be unreliable`} class="ml-1 text-[var(--color-accent-red)]">
                        ●
                      </span>
                    )}
                  </td>
                  <td class="text-right">{r.learned_recipes || '—'}</td>
                  <td class="text-right">{r.unlearned_recipes || '—'}</td>
                  <td>
                    {a ? (
                      <span
                        class={`rounded border px-2 py-0.5 font-heading text-xs tracking-wide ${ACTION_CLASS[a.action]}`}
                        title={`Confidence: ${a.confidence}`}
                      >
                        {ACTION_LABEL[a.action]}
                        {split && <span class="ml-1 normal-case">({split})</span>}
                        {a.confidence !== 'high' && <span class="ml-1 text-[var(--color-accent-red)]">●</span>}
                      </span>
                    ) : (
                      '—'
                    )}
                  </td>
                  <td class="text-right">{a && a.total > 0 ? money(a.total) : '—'}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <p class="mt-4 text-sm text-[var(--color-text-muted)]">
        Of the rows shown: <span class="text-[var(--color-text)]">{totals.counts.sell_ah}</span> to sell on the AH (~
        <span class="text-[var(--color-text)]">{money(totals.sell_ah)}</span>), <span class="text-[var(--color-text)]">{totals.counts.vendor}</span> to vendor (~
        <span class="text-[var(--color-text)]">{money(totals.vendor)}</span>), {totals.counts.discard} to discard, {totals.counts.review} to review,{' '}
        {totals.counts.keep} to keep; about <span class="text-[var(--color-text)]">{totals.slots}</span> bag slots would be freed. AH values are after the{' '}
        {Math.round(DEFAULTS.ahCut * 100)}% cut and assume you can sell everything at the median; a big stack would move the price.{' '}
        <span class="text-[var(--color-accent-red)]">●</span> next to a count of listings means fewer than {DEFAULTS.minListings}; next to the advice it means
        low or medium confidence. These are recommendations: nothing is sold or moved for you.
      </p>
    </div>
  );
}
