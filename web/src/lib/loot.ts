import type { LootRecord } from './db';

export interface AggItem {
  item_id: number;
  name: string | null;
  qty: number;
  perOpen: number; // average quantity per window opened
  med: number | null; // AH median, per unit
  vendor: number | null;
  ahValue: number; // qty * med (unpriced items count as 0)
  priced: boolean;
}

export interface Place {
  key: string;
  zone: string | null;
  subzone: string | null;
  map_id: number;
  cell_x: number;
  cell_y: number;
  opens: number;
}

export interface SourceInGroup {
  source: string;
  label: string;
  opens: number;
}

export interface Group {
  key: string;
  type: 'npc' | 'obj' | 'unknown' | 'place';
  label: string;
  zones: string[];
  opens: number;
  places: Place[];
  sources: SourceInGroup[];
  items: AggItem[];
  totalQty: number;
  ahValue: number;
  vendorValue: number;
  ahPerOpen: number;
  vendorPerOpen: number;
  anyUnpriced: boolean;
}

export const SMALL_SAMPLE = 5;

// Where a map cell sits, as a percentage of the map (the center of the cell).
export function cellPercent(cell: number): number | null {
  return cell < 0 ? null : (cell + 0.5) * 2;
}

function sourceType(r: Pick<LootRecord, 'source_type' | 'source'>): Group['type'] {
  if (r.source_type === 'npc' || r.source_type === 'obj') return r.source_type;
  return 'unknown';
}

function sourceLabel(r: Pick<LootRecord, 'source_type' | 'source_id'>): string {
  if (r.source_type === 'npc') return `NPC #${r.source_id}`;
  if (r.source_type === 'obj') return `Object #${r.source_id}`;
  return 'Unknown source';
}

function build(key: string, type: Group['type'], label: string, records: LootRecord[]): Group {
  const items = new Map<number, AggItem>();
  const places = new Map<string, Place>();
  const sources = new Map<string, SourceInGroup>();
  let opens = 0;
  for (const r of records) {
    opens += r.opens;
    const src = sources.get(r.source);
    if (src) src.opens += r.opens;
    else sources.set(r.source, { source: r.source, label: sourceLabel(r), opens: r.opens });
    const pk = `${r.map_id}|${r.cell_x}|${r.cell_y}`;
    const place = places.get(pk);
    if (place) place.opens += r.opens;
    else places.set(pk, { key: pk, zone: r.zone, subzone: r.subzone, map_id: r.map_id, cell_x: r.cell_x, cell_y: r.cell_y, opens: r.opens });
    for (const it of r.items) {
      const agg = items.get(it.item_id);
      if (agg) agg.qty += it.qty;
      else
        items.set(it.item_id, {
          item_id: it.item_id,
          name: it.name,
          qty: it.qty,
          perOpen: 0,
          med: it.med,
          vendor: it.vendor,
          ahValue: 0,
          priced: it.med !== null,
        });
    }
  }
  let totalQty = 0;
  let ahValue = 0;
  let vendorValue = 0;
  let anyUnpriced = false;
  for (const it of items.values()) {
    it.perOpen = opens ? it.qty / opens : 0;
    it.ahValue = it.qty * (it.med ?? 0);
    totalQty += it.qty;
    ahValue += it.ahValue;
    vendorValue += it.qty * (it.vendor ?? 0);
    if (!it.priced) anyUnpriced = true;
  }
  const zones = [...new Set(records.map((r) => r.zone).filter((z): z is string => !!z))].sort();
  return {
    key,
    type,
    label,
    zones,
    opens,
    places: [...places.values()].sort((a, b) => b.opens - a.opens),
    sources: [...sources.values()].sort((a, b) => b.opens - a.opens),
    items: [...items.values()].sort((a, b) => b.ahValue - a.ahValue || b.qty - a.qty),
    totalQty,
    ahValue,
    vendorValue,
    ahPerOpen: opens ? ahValue / opens : 0,
    vendorPerOpen: opens ? vendorValue / opens : 0,
    anyUnpriced,
  };
}

// One group per loot source (an NPC or an object), across every place it was looted.
export function groupBySource(records: LootRecord[]): Group[] {
  const by = new Map<string, LootRecord[]>();
  for (const r of records) {
    const list = by.get(r.source) ?? [];
    list.push(r);
    by.set(r.source, list);
  }
  return [...by.entries()].map(([source, recs]) => build(source, sourceType(recs[0]), sourceLabel(recs[0]), recs));
}

// One group per map cell, across every source looted there.
export function groupByPlace(records: LootRecord[]): Group[] {
  const by = new Map<string, LootRecord[]>();
  for (const r of records) {
    const key = `${r.map_id}|${r.cell_x}|${r.cell_y}`;
    const list = by.get(key) ?? [];
    list.push(r);
    by.set(key, list);
  }
  return [...by.entries()].map(([key, recs]) => {
    const r = recs[0];
    const x = cellPercent(r.cell_x);
    const where = x === null ? 'Unknown position' : `x ${x.toFixed(0)}% · y ${cellPercent(r.cell_y)!.toFixed(0)}%`;
    const name = [r.zone ?? `Map ${r.map_id}`, r.subzone].filter(Boolean).join(' · ');
    return build(key, 'place', `${name} (${where})`, recs);
  });
}
