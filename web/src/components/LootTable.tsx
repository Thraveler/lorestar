import { useMemo, useState } from 'preact/hooks';
import type { LootRecord } from '../lib/db';
import { groupBySource, groupByPlace, cellPercent, SMALL_SAMPLE, type Group } from '../lib/loot';
import { money, nf } from '../lib/format';

type Mode = 'source' | 'place';
type Key = 'label' | 'opens' | 'totalQty' | 'ahPerOpen' | 'vendorPerOpen' | 'ahValue';

const COLUMNS: { key: Key; label: string; num?: boolean }[] = [
  { key: 'label', label: 'Source' },
  { key: 'opens', label: 'Opens', num: true },
  { key: 'totalQty', label: 'Items', num: true },
  { key: 'ahPerOpen', label: 'AH / open', num: true },
  { key: 'vendorPerOpen', label: 'Vendor / open', num: true },
  { key: 'ahValue', label: 'AH total', num: true },
];

const TYPE_NAME: Record<Group['type'], string> = { npc: 'NPC', obj: 'Object', unknown: 'Unknown', place: 'Place' };

function itemName(i: { name: string | null; item_id: number }) {
  return i.name ?? `Item #${i.item_id}`;
}

export default function LootTable({ records }: { records: LootRecord[] }) {
  const [mode, setMode] = useState<Mode>('source');
  const [query, setQuery] = useState('');
  const [type, setType] = useState<'all' | 'npc' | 'obj'>('all');
  const [zone, setZone] = useState('all');
  const [hideSmall, setHideSmall] = useState(false);
  const [sortKey, setSortKey] = useState<Key>('ahPerOpen');
  const [asc, setAsc] = useState(false);
  const [open, setOpen] = useState<Set<string>>(new Set());

  const zones = useMemo(() => [...new Set(records.map((r) => r.zone).filter((z): z is string => !!z))].sort(), [records]);

  const groups = useMemo(() => {
    const scoped = records.filter((r) => (zone === 'all' || r.zone === zone) && (type === 'all' || r.source_type === type));
    return mode === 'source' ? groupBySource(scoped) : groupByPlace(scoped);
  }, [records, mode, zone, type]);

  const view = useMemo(() => {
    const q = query.trim().toLowerCase();
    const filtered = groups.filter(
      (g) =>
        (!hideSmall || g.opens >= SMALL_SAMPLE) &&
        (!q || g.label.toLowerCase().includes(q) || g.items.some((i) => itemName(i).toLowerCase().includes(q))),
    );
    return [...filtered].sort((a, b) => {
      const av = a[sortKey];
      const bv = b[sortKey];
      const cmp = typeof av === 'string' ? av.localeCompare(String(bv)) : (av as number) - (bv as number);
      return (asc ? cmp : -cmp) || a.label.localeCompare(b.label);
    });
  }, [groups, query, hideSmall, sortKey, asc]);

  function sortBy(key: Key) {
    if (key === sortKey) setAsc(!asc);
    else {
      setSortKey(key);
      setAsc(key === 'label');
    }
  }

  function toggle(key: string) {
    const next = new Set(open);
    if (next.has(key)) next.delete(key);
    else next.add(key);
    setOpen(next);
  }

  const input =
    'rounded border border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-1.5 text-sm text-[var(--color-text)] placeholder:text-[var(--color-text-muted)] focus:border-[var(--color-accent-gold)] focus:outline-none';
  const tab = (active: boolean) =>
    `rounded border px-3 py-1.5 font-heading text-xs tracking-widest uppercase transition-colors ${
      active
        ? 'border-[var(--color-accent-gold)] text-[var(--color-accent-gold)]'
        : 'border-[var(--color-border)] text-[var(--color-text-muted)] hover:text-[var(--color-text)]'
    }`;
  const columns = COLUMNS.map((c) => (c.key === 'label' ? { ...c, label: mode === 'source' ? 'Source' : 'Place' } : c));

  return (
    <div>
      <div class="mb-4 flex flex-wrap items-center gap-4">
        <div class="flex gap-2">
          <button type="button" class={tab(mode === 'source')} onClick={() => setMode('source')}>By source</button>
          <button type="button" class={tab(mode === 'place')} onClick={() => setMode('place')}>By place</button>
        </div>
        <input class={input} type="search" placeholder="Search source or item…" value={query} onInput={(e) => setQuery((e.target as HTMLInputElement).value)} />
        <select class={input} value={zone} onChange={(e) => setZone((e.target as HTMLSelectElement).value)}>
          <option value="all">All zones</option>
          {zones.map((z) => (
            <option value={z}>{z}</option>
          ))}
        </select>
        <select class={input} value={type} onChange={(e) => setType((e.target as HTMLSelectElement).value as 'all' | 'npc' | 'obj')}>
          <option value="all">NPCs and objects</option>
          <option value="npc">NPCs (mobs)</option>
          <option value="obj">Objects (nodes, chests…)</option>
        </select>
        <label class="flex items-center gap-2 text-sm text-[var(--color-text-muted)]">
          <input type="checkbox" checked={hideSmall} onChange={(e) => setHideSmall((e.target as HTMLInputElement).checked)} />
          Hide small samples
        </label>
        <span class="ml-auto font-heading text-xs tracking-widest uppercase text-[var(--color-text-muted)]">
          {nf.format(view.length)} / {nf.format(groups.length)} {mode === 'source' ? 'sources' : 'places'}
        </span>
      </div>

      <div class="overflow-x-auto rounded border border-[var(--color-border)] bg-[var(--color-surface)]">
        <table class="data-table">
          <thead>
            <tr>
              {columns.map((c) => (
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
            {view.map((g) => {
              const isOpen = open.has(g.key);
              const small = g.opens < SMALL_SAMPLE;
              const top = g.items.slice(0, 3).map(itemName).join(', ');
              return (
                <>
                  <tr class="cursor-pointer" onClick={() => toggle(g.key)}>
                    <td class="!whitespace-normal">
                      <div class="font-heading">
                        <span class="mr-2 text-[var(--color-accent-gold)]">{isOpen ? '▾' : '▸'}</span>
                        {g.label}
                        {g.type !== 'place' && (
                          <span class="ml-2 rounded border border-[var(--color-border)] px-1.5 py-0.5 text-xs text-[var(--color-text-muted)]">{TYPE_NAME[g.type]}</span>
                        )}
                      </div>
                      <div class="ml-5 text-sm text-[var(--color-text-muted)]">
                        {mode === 'source' && g.zones.length > 0 && <>{g.zones.join(', ')} · </>}
                        {top || 'no items'}
                      </div>
                    </td>
                    <td class="text-right">
                      {nf.format(g.opens)}
                      {small && (
                        <span title={`Fewer than ${SMALL_SAMPLE} opens: too few to trust the averages`} class="ml-1 text-[var(--color-accent-red)]">●</span>
                      )}
                    </td>
                    <td class="text-right">{nf.format(g.totalQty)}</td>
                    <td class="text-right">
                      {money(g.ahPerOpen)}
                      {g.anyUnpriced && <span title="Some items have no AH price: the value is incomplete" class="ml-1 text-[var(--color-accent-red)]">+?</span>}
                    </td>
                    <td class="text-right">{money(g.vendorPerOpen)}</td>
                    <td class="text-right">{money(g.ahValue)}</td>
                  </tr>
                  {isOpen && (
                    <tr>
                      <td colspan={columns.length} class="!whitespace-normal bg-[var(--color-bg)] p-4">
                        <table class="w-full text-sm">
                          <thead>
                            <tr class="font-heading text-xs tracking-widest uppercase text-[var(--color-text-muted)]">
                              <th class="px-3 py-1 text-left">Item</th>
                              <th class="px-3 py-1 text-right">Qty</th>
                              <th class="px-3 py-1 text-right">Avg / open</th>
                              <th class="px-3 py-1 text-right">AH med</th>
                              <th class="px-3 py-1 text-right">AH total</th>
                              <th class="px-3 py-1 text-right">Vendor</th>
                            </tr>
                          </thead>
                          <tbody>
                            {g.items.map((i) => (
                              <tr>
                                <td class="px-3 py-1">{itemName(i)}</td>
                                <td class="px-3 py-1 text-right">{nf.format(i.qty)}</td>
                                <td class="px-3 py-1 text-right">{i.perOpen.toFixed(2)}</td>
                                <td class="px-3 py-1 text-right">{i.priced ? money(i.med) : '—'}</td>
                                <td class="px-3 py-1 text-right">{i.priced ? money(i.ahValue) : '—'}</td>
                                <td class="px-3 py-1 text-right">{money(i.vendor)}</td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                        <p class="mt-4 px-3 font-heading text-xs tracking-widest uppercase text-[var(--color-text-muted)]">
                          {mode === 'source' ? 'Where it was looted' : 'What was looted here'}
                        </p>
                        <ul class="mt-1 px-3 text-sm text-[var(--color-text-muted)]">
                          {mode === 'source'
                            ? g.places.map((p) => {
                                const x = cellPercent(p.cell_x);
                                const y = cellPercent(p.cell_y);
                                return (
                                  <li>
                                    {p.zone ?? `Map ${p.map_id}`}
                                    {p.subzone ? ` · ${p.subzone}` : ''} ·{' '}
                                    {x === null || y === null ? 'unknown position' : `x ${x.toFixed(0)}% · y ${y.toFixed(0)}%`} · {p.opens}{' '}
                                    {p.opens === 1 ? 'open' : 'opens'}
                                  </li>
                                );
                              })
                            : g.sources.map((s) => (
                                <li>
                                  {s.label} · {s.opens} {s.opens === 1 ? 'open' : 'opens'}
                                </li>
                              ))}
                        </ul>
                      </td>
                    </tr>
                  )}
                </>
              );
            })}
          </tbody>
        </table>
      </div>
      <p class="mt-4 text-sm text-[var(--color-text-muted)]">
        An open is one loot window. Values use the AH median (unpriced items count as zero, <span class="text-[var(--color-accent-red)]">+?</span>) and
        include everything that source gave, so vendor trash and bind-on-pickup items are valued too. <span class="text-[var(--color-accent-red)]">●</span>{' '}
        = fewer than {SMALL_SAMPLE} opens: these are averages of a few samples, not drop rates. The game gives no names for NPCs and objects, only IDs; the items
        they drop tell you what they are. Positions are 2%-wide map cells, shown as a percentage of the map.
      </p>
    </div>
  );
}
