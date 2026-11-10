import { useMemo, useState } from 'preact/hooks';
import type { RecipeRow } from '../lib/db';
import { money, nf } from '../lib/format';

type Key = 'name' | 'profession' | 'learned' | 'reagents' | 'cost' | 'out_med';

const COLUMNS: { key: Key; label: string; num?: boolean }[] = [
  { key: 'name', label: 'Recipe' },
  { key: 'profession', label: 'Profession' },
  { key: 'learned', label: 'Learned' },
  { key: 'reagents', label: 'Reagents', num: true },
  { key: 'cost', label: 'Reagent cost (AH med)', num: true },
  { key: 'out_med', label: 'Output AH med', num: true },
];

interface Derived {
  recipe: RecipeRow;
  cost: number | null; // null when no reagent has an AH price
  partial: boolean; // some reagent prices are missing
  craftable: boolean; // every reagent is in the bags in the needed quantity
  missing: number; // number of reagents not covered by the bags
}

function derive(recipe: RecipeRow): Derived {
  let cost = 0;
  let priced = 0;
  let missing = 0;
  for (const r of recipe.reagents) {
    if (r.med !== null) {
      cost += r.qty * r.med;
      priced += 1;
    }
    if (r.have < r.qty) missing += 1;
  }
  return {
    recipe,
    cost: priced ? cost : null,
    partial: priced > 0 && priced < recipe.reagents.length,
    craftable: recipe.reagents.length > 0 && missing === 0,
    missing,
  };
}

function sortValue(d: Derived, key: Key): string | number | null {
  switch (key) {
    case 'name': return d.recipe.name ?? '';
    case 'profession': return d.recipe.profession;
    case 'learned': return d.recipe.learned;
    case 'reagents': return d.recipe.reagents.length;
    case 'cost': return d.cost;
    case 'out_med': return d.recipe.out_med;
  }
}

export default function RecipesTable({ recipes, professions }: { recipes: RecipeRow[]; professions: string[] }) {
  const [query, setQuery] = useState('');
  const [prof, setProf] = useState('all');
  const [learned, setLearned] = useState<'all' | 'yes' | 'no'>('all');
  const [onlyCraftable, setOnlyCraftable] = useState(false);
  const [sortKey, setSortKey] = useState<Key>('learned');
  const [asc, setAsc] = useState(false);
  const [open, setOpen] = useState<Set<number>>(new Set());

  const derived = useMemo(() => recipes.map(derive), [recipes]);

  const view = useMemo(() => {
    const q = query.trim().toLowerCase();
    const filtered = derived.filter(
      (d) =>
        (!q || (d.recipe.name ?? '').toLowerCase().includes(q)) &&
        (prof === 'all' || d.recipe.profession === prof) &&
        (learned === 'all' || (learned === 'yes') === (d.recipe.learned === 1)) &&
        (!onlyCraftable || d.craftable),
    );
    return [...filtered].sort((a, b) => {
      const av = sortValue(a, sortKey);
      const bv = sortValue(b, sortKey);
      if (av === null && bv === null) return 0;
      if (av === null) return 1;
      if (bv === null) return -1;
      const cmp = typeof av === 'string' ? av.localeCompare(String(bv)) : (av as number) - (bv as number);
      return (asc ? cmp : -cmp) || (a.recipe.name ?? '').localeCompare(b.recipe.name ?? '');
    });
  }, [derived, query, prof, learned, onlyCraftable, sortKey, asc]);

  function sortBy(key: Key) {
    if (key === sortKey) setAsc(!asc);
    else {
      setSortKey(key);
      setAsc(key === 'name' || key === 'profession');
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
        <input class={input} type="search" placeholder="Search recipe…" value={query} onInput={(e) => setQuery((e.target as HTMLInputElement).value)} />
        <select class={input} value={prof} onChange={(e) => setProf((e.target as HTMLSelectElement).value)}>
          <option value="all">All professions</option>
          {professions.map((p) => (
            <option value={p}>{p}</option>
          ))}
        </select>
        <select class={input} value={learned} onChange={(e) => setLearned((e.target as HTMLSelectElement).value as 'all' | 'yes' | 'no')}>
          <option value="all">Learned and not</option>
          <option value="yes">Learned</option>
          <option value="no">Not learned</option>
        </select>
        <label class="flex items-center gap-2 text-sm text-[var(--color-text-muted)]">
          <input type="checkbox" checked={onlyCraftable} onChange={(e) => setOnlyCraftable((e.target as HTMLInputElement).checked)} />
          Reagents in bags
        </label>
        <span class="ml-auto font-heading text-xs tracking-widest uppercase text-[var(--color-text-muted)]">
          {nf.format(view.length)} / {nf.format(recipes.length)} recipes
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
            {view.map((d) => {
              const r = d.recipe;
              const isOpen = open.has(r.recipe_id);
              return (
                <>
                  <tr class="cursor-pointer" onClick={() => toggle(r.recipe_id)}>
                    <td class="font-heading">
                      <span class="mr-2 text-[var(--color-accent-gold)]">{isOpen ? '▾' : '▸'}</span>
                      {r.name ?? `#${r.recipe_id}`}
                      {d.craftable && (
                        <span class="ml-2 rounded border border-[var(--color-accent-gold)] px-1.5 py-0.5 text-xs text-[var(--color-accent-gold)]" title="Every reagent is in your bags in the needed quantity">
                          in bags
                        </span>
                      )}
                    </td>
                    <td class="text-[var(--color-text-muted)]">{r.profession}</td>
                    <td>
                      {r.learned ? (
                        <span class="text-[var(--color-accent-gold)]">Learned</span>
                      ) : (
                        <span class="text-[var(--color-text-muted)]">—</span>
                      )}
                    </td>
                    <td class="text-right">{r.reagents.length}</td>
                    <td class="text-right">
                      {money(d.cost)}
                      {d.partial && <span title="Some reagents have no AH price: the total is incomplete" class="ml-1 text-[var(--color-accent-red)]">+?</span>}
                    </td>
                    <td class="text-right">{money(r.out_med)}</td>
                  </tr>
                  {isOpen && (
                    <tr>
                      <td colspan={COLUMNS.length} class="!whitespace-normal bg-[var(--color-bg)]">
                        <table class="w-full text-sm">
                          <thead>
                            <tr class="font-heading text-xs tracking-widest uppercase text-[var(--color-text-muted)]">
                              <th class="px-3 py-1 text-left">Reagent</th>
                              <th class="px-3 py-1 text-right">Need</th>
                              <th class="px-3 py-1 text-right">In bags</th>
                              <th class="px-3 py-1 text-right">AH med</th>
                              <th class="px-3 py-1 text-right">Listings</th>
                            </tr>
                          </thead>
                          <tbody>
                            {r.reagents.map((g) => (
                              <tr>
                                <td class="px-3 py-1">{g.name ?? <span class="text-[var(--color-text-muted)]">Item #{g.item_id}</span>}</td>
                                <td class="px-3 py-1 text-right">{g.qty}</td>
                                <td class={`px-3 py-1 text-right ${g.have >= g.qty ? 'text-[var(--color-accent-gold)]' : ''}`}>{g.have || '—'}</td>
                                <td class="px-3 py-1 text-right">{money(g.med)}</td>
                                <td class="px-3 py-1 text-right">{g.listings === null ? '—' : nf.format(g.listings)}</td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                        <p class="px-3 pt-2 text-xs text-[var(--color-text-muted)]">
                          Output item: {r.output_item_id ? `#${r.output_item_id}` : '—'}
                          {r.out_listings !== null && ` · ${nf.format(r.out_listings)} listings`}
                        </p>
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
        Reagent names are only known for items that were in your bags; the rest show as an item ID. Costs add up reagent AH medians
        (<span class="text-[var(--color-accent-red)]">+?</span> = some reagent has no price). The list of reagents comes straight from the game
        and may include alternative reagents for the same slot, so a cost can be overestimated. Output AH med is per unit and ignores how many items a craft yields.
      </p>
    </div>
  );
}
