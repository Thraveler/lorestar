import { DatabaseSync } from 'node:sqlite';
import fs from 'node:fs';
import path from 'node:path';
import type { RuleItem, RuleCtx } from './rules';

// Read-only access to the SQLite built by tools/ingest.py. Override the path with LORESTAR_DB.
export const DB_PATH = process.env.LORESTAR_DB ?? path.resolve(process.cwd(), '../data/lorestar.db');

export function openDb(): DatabaseSync | null {
  if (!fs.existsSync(DB_PATH)) return null;
  return new DatabaseSync(DB_PATH, { readOnly: true });
}

export interface Run {
  id: number;
  label: string;
  addon_version: string | null;
  snapshot_time: string | null;
  scan_time: string | null;
  price_schema: number | null;
  scan_rows: number | null;
  bag_used: number | null;
  bag_slots: number | null;
  section_errors: number | null;
}

export interface RunSummary extends Run {
  bag_items: number;
  recipes: number;
  learned: number;
  prices: number;
}

export interface PriceSource {
  id: number;
  label: string;
  scan_time: string | null;
}

// The scan whose prices apply to a run: its own, or the most recent earlier one.
export function priceSourceFor(db: DatabaseSync, runId: number): PriceSource | null {
  const row = db
    .prepare('SELECT id, label, scan_time FROM runs WHERE id <= ? AND scan_time IS NOT NULL ORDER BY id DESC LIMIT 1')
    .get(runId) as PriceSource | undefined;
  return row ? { ...row } : null;
}

export function listRuns(db: DatabaseSync): RunSummary[] {
  return db
    .prepare(
      `SELECT r.*,
        (SELECT COUNT(*) FROM bag_items b WHERE b.run_id = r.id) AS bag_items,
        (SELECT COUNT(*) FROM recipes c WHERE c.run_id = r.id) AS recipes,
        (SELECT COALESCE(SUM(learned), 0) FROM recipes c WHERE c.run_id = r.id) AS learned,
        (SELECT COUNT(*) FROM prices p WHERE p.run_id = r.id) AS prices
       FROM runs r ORDER BY r.id DESC`,
    )
    .all() as unknown as RunSummary[];
}

export interface BagRow {
  advice?: import('./rules').Advice | null;
  item_id: number;
  name: string | null;
  quality: number | null;
  qty: number;
  vendor: number | null;
  listings: number | null;
  m: number | null;
  p10: number | null;
  med: number | null;
  learned_recipes: number;
  unlearned_recipes: number;
  is_reagent: number | null;
  type: string | null;
}

export function bagRows(db: DatabaseSync, runId: number): BagRow[] {
  const rows = db
    .prepare(
      `SELECT v.item_id, v.name, v.quality, v.qty, v.vendor, v.listings, v.m, v.p10, v.med,
              v.learned_recipes, v.unlearned_recipes, i.is_reagent, i.type
       FROM v_bag_advice v LEFT JOIN items i ON i.item_id = v.item_id
       WHERE v.run_id = ? ORDER BY v.name`,
    )
    .all(runId);
  return rows.map((r) => ({ ...r })) as unknown as BagRow[];
}

export interface Reagent {
  item_id: number;
  qty: number;
  name: string | null;
  have: number;
  med: number | null;
  listings: number | null;
}

export interface RecipeRow {
  recipe_id: number;
  profession: string;
  name: string | null;
  learned: number;
  output_item_id: number | null;
  out_name: string | null;
  out_med: number | null;
  out_listings: number | null;
  reagents: Reagent[];
}

export interface ProfessionSummary {
  name: string;
  skill: number | null;
  max_skill: number | null;
  recipes: number;
  learned: number;
}

export function recipeRows(db: DatabaseSync, runId: number): RecipeRow[] {
  const priceRun = priceSourceFor(db, runId)?.id ?? -1;
  const recipes = db
    .prepare(
      `SELECT r.recipe_id, r.profession, r.name, COALESCE(r.learned, 0) AS learned, r.output_item_id,
              o.name AS out_name, p.med AS out_med, p.n AS out_listings
       FROM recipes r
       LEFT JOIN prices p ON p.run_id = :pr AND p.item_id = r.output_item_id
       LEFT JOIN items o ON o.item_id = r.output_item_id
       WHERE r.run_id = :runId ORDER BY r.profession, r.name`,
    )
    .all({ runId, pr: priceRun }) as unknown as Omit<RecipeRow, 'reagents'>[];
  const reagents = db
    .prepare(
      `SELECT rr.recipe_id, rr.item_id, rr.qty, i.name, COALESCE(b.qty, 0) AS have,
              p.med AS med, p.n AS listings
       FROM recipe_reagents rr
       LEFT JOIN items i ON i.item_id = rr.item_id
       LEFT JOIN bag_items b ON b.run_id = rr.run_id AND b.item_id = rr.item_id
       LEFT JOIN prices p ON p.run_id = :pr AND p.item_id = rr.item_id
       WHERE rr.run_id = :runId`,
    )
    .all({ runId, pr: priceRun }) as unknown as (Reagent & { recipe_id: number })[];
  const byRecipe = new Map<number, Reagent[]>();
  for (const { recipe_id, ...rest } of reagents) {
    const list = byRecipe.get(recipe_id) ?? [];
    list.push({ ...rest });
    byRecipe.set(recipe_id, list);
  }
  return recipes.map((r) => ({ ...r, reagents: byRecipe.get(r.recipe_id) ?? [] }));
}

export function professionSummary(db: DatabaseSync, runId: number): ProfessionSummary[] {
  return db
    .prepare(
      `SELECT p.name, p.skill, p.max_skill,
              (SELECT COUNT(*) FROM recipes r WHERE r.run_id = p.run_id AND r.profession = p.name) AS recipes,
              (SELECT COALESCE(SUM(r.learned), 0) FROM recipes r WHERE r.run_id = p.run_id AND r.profession = p.name) AS learned
       FROM professions p WHERE p.run_id = ? ORDER BY COALESCE(p.is_primary, 0) DESC, p.name`,
    )
    .all(runId)
    .map((r) => ({ ...r })) as unknown as ProfessionSummary[];
}

export type PriceScope = 'bags' | 'reagents' | 'all';

export interface PricePoint {
  label: string;
  time: string | null;
  n: number | null;
  m: number | null;
  p10: number | null;
  med: number | null;
}

export interface PriceSeries {
  item_id: number;
  name: string | null;
  vendor: number | null;
  qty: number;
  series: PricePoint[]; // oldest first
}

// Price history for the items in `scope`, as of the latest run. Only runs that priced the item appear.
export function priceHistory(db: DatabaseSync, scope: PriceScope): PriceSeries[] {
  const latest = db.prepare('SELECT id FROM runs ORDER BY id DESC LIMIT 1').get() as { id: number } | undefined;
  if (!latest) return [];
  const scanned = db.prepare('SELECT id FROM runs WHERE scan_time IS NOT NULL ORDER BY id DESC LIMIT 1').get() as { id: number } | undefined;
  if (!scanned) return [];
  const filter =
    scope === 'bags'
      ? 'p.item_id IN (SELECT item_id FROM bag_items WHERE run_id = :latest)'
      : scope === 'reagents'
        ? 'p.item_id IN (SELECT item_id FROM recipe_reagents WHERE run_id = :latest)'
        : 'p.item_id IN (SELECT item_id FROM prices WHERE run_id = :scanned)';
  const rows = db
    .prepare(
      `SELECT p.item_id, i.name, i.vendor_sell_price AS vendor, r.label, r.scan_time AS time,
              p.n, p.m, p.p10, p.med,
              COALESCE((SELECT b.qty FROM bag_items b WHERE b.run_id = :latest AND b.item_id = p.item_id), 0) AS qty
       FROM prices p
       JOIN runs r ON r.id = p.run_id
       LEFT JOIN items i ON i.item_id = p.item_id
       WHERE ${filter}
       ORDER BY p.item_id, r.id`,
    )
    .all(scope === 'all' ? { latest: latest.id, scanned: scanned.id } : { latest: latest.id }) as unknown as (PricePoint & { item_id: number; name: string | null; vendor: number | null; qty: number })[];
  const byItem = new Map<number, PriceSeries>();
  for (const { item_id, name, vendor, qty, ...point } of rows) {
    let entry = byItem.get(item_id);
    if (!entry) {
      entry = { item_id, name, vendor, qty, series: [] };
      byItem.set(item_id, entry);
    }
    entry.series.push({ ...point });
  }
  return [...byItem.values()];
}

export interface LootItem {
  item_id: number;
  qty: number;
  name: string | null;
  vendor: number | null;
  med: number | null;
  listings: number | null;
}

export interface LootRecord {
  map_id: number;
  zone: string | null;
  cell_x: number;
  cell_y: number;
  source: string;
  source_type: string | null;
  source_id: number | null;
  opens: number;
  subzone: string | null;
  items: LootItem[];
}

export interface LootProbe {
  enabled: number | null;
  windows: number | null;
  recorded: number | null;
  no_position: number | null;
  no_source: number | null;
  secret: number | null;
  errors: number | null;
  dropped: number | null;
}

// Runs that have loot data (the probe exists from addon v0.4.7).
export function runsWithLoot(db: DatabaseSync): number[] {
  return (db.prepare('SELECT DISTINCT run_id FROM loot_sources ORDER BY run_id DESC').all() as { run_id: number }[]).map(
    (r) => r.run_id,
  );
}

export function lootProbe(db: DatabaseSync, runId: number): LootProbe | null {
  const row = db.prepare('SELECT * FROM loot_probe WHERE run_id = ?').get(runId);
  return row ? ({ ...row } as unknown as LootProbe) : null;
}

// Loot records of a run with item names and AH prices (the run's own scan, or the latest earlier one).
export function lootRows(db: DatabaseSync, runId: number): LootRecord[] {
  const priceRun = priceSourceFor(db, runId)?.id ?? -1;
  const records = db
    .prepare(
      `SELECT s.map_id, z.name AS zone, s.cell_x, s.cell_y, s.source, s.source_type, s.source_id, s.opens, s.subzone
       FROM loot_sources s LEFT JOIN zones z ON z.map_id = s.map_id
       WHERE s.run_id = :runId ORDER BY s.opens DESC`,
    )
    .all({ runId }) as unknown as Omit<LootRecord, 'items'>[];
  const items = db
    .prepare(
      `SELECT l.map_id, l.cell_x, l.cell_y, l.source, l.item_id, l.qty,
              i.name, i.vendor_sell_price AS vendor, p.med AS med, p.n AS listings
       FROM loot_items l
       LEFT JOIN items i ON i.item_id = l.item_id
       LEFT JOIN prices p ON p.run_id = :pr AND p.item_id = l.item_id
       WHERE l.run_id = :runId`,
    )
    .all({ runId, pr: priceRun }) as unknown as (LootItem & { map_id: number; cell_x: number; cell_y: number; source: string })[];
  const byKey = new Map<string, LootItem[]>();
  for (const { map_id, cell_x, cell_y, source, ...item } of items) {
    const key = `${map_id}|${cell_x}|${cell_y}|${source}`;
    const list = byKey.get(key) ?? [];
    list.push({ ...item });
    byKey.set(key, list);
  }
  return records.map((r) => ({ ...r, items: byKey.get(`${r.map_id}|${r.cell_x}|${r.cell_y}|${r.source}`) ?? [] }));
}

export interface InGameAdvice {
  action: string;
  keep_qty: number | null;
  sell_qty: number | null;
  unit: number | null;
  reason: string | null;
  confidence: string | null;
}

export interface AdviceInput {
  name: string | null;
  item: RuleItem;
  ctx: RuleCtx;
  inGame: InGameAdvice | null; // what the addon itself recommended, when it saved its advice
}

// Everything the rules need for each item in the bags of a run.
export function adviceInputs(db: DatabaseSync, runId: number): AdviceInput[] {
  const priceRun = priceSourceFor(db, runId)?.id ?? -1;
  const run = db.prepare('SELECT bag_used, bag_slots FROM runs WHERE id = ?').get(runId) as
    | { bag_used: number | null; bag_slots: number | null }
    | undefined;
  const freeSlots = run && run.bag_slots !== null && run.bag_used !== null ? run.bag_slots - run.bag_used : null;
  const learned = (extra: string) =>
    `(SELECT ${extra} FROM recipe_reagents rr JOIN recipes r ON r.run_id = rr.run_id AND r.recipe_id = rr.recipe_id
       WHERE rr.run_id = b.run_id AND rr.item_id = b.item_id AND r.learned = `;
  const rows = db
    .prepare(
      `SELECT b.item_id AS id, b.qty, i.name, i.quality, i.class_id AS classID, i.vendor_sell_price AS vendor,
              i.stack_size AS stack, i.bind_type AS bind,
              p.med, p.p10, p.m, p.n, p.q,
              ${learned('COUNT(*)')}1) AS learnedCount,
              ${learned('COALESCE(MAX(rr.qty), 0)')}1) AS learnedMax,
              ${learned('COUNT(*)')}0) AS unlearnedCount,
              a.action AS a_action, a.keep_qty AS a_keep, a.sell_qty AS a_sell, a.unit AS a_unit,
              a.reason AS a_reason, a.confidence AS a_conf, a.bound AS a_bound
       FROM bag_items b
       LEFT JOIN items i ON i.item_id = b.item_id
       LEFT JOIN prices p ON p.run_id = :pr AND p.item_id = b.item_id
       LEFT JOIN advice_items a ON a.run_id = b.run_id AND a.item_id = b.item_id
       WHERE b.run_id = :runId ORDER BY i.name`,
    )
    .all({ runId, pr: priceRun }) as unknown as Record<string, number | string | null>[];
  return rows.map((r) => {
    // The addon knows whether this very stack is bound; the database only knows the item's binding rule.
    const bound = r.a_bound !== null ? r.a_bound === 1 : r.bind === 1;
    return {
      name: r.name as string | null,
      item: {
        id: r.id as number, qty: r.qty as number, quality: r.quality as number | null, classID: r.classID as number | null,
        vendor: r.vendor as number | null, stack: r.stack as number | null, bound,
      },
      ctx: {
        price: r.med === null && r.n === null ? null : { med: r.med as number | null, p10: r.p10 as number | null, m: r.m as number | null, n: r.n as number | null, q: r.q as number | null },
        recipes: { learnedCount: r.learnedCount as number, learnedMax: r.learnedMax as number, unlearnedCount: r.unlearnedCount as number },
        freeSlots,
      },
      inGame: r.a_action === null ? null : {
        action: r.a_action as string, keep_qty: r.a_keep as number | null, sell_qty: r.a_sell as number | null,
        unit: r.a_unit as number | null, reason: r.a_reason as string | null, confidence: r.a_conf as string | null,
      },
    };
  });
}

export function adviceMeta(db: DatabaseSync, runId: number): { advice_time: string | null; price_time: string | null } | null {
  const row = db.prepare('SELECT advice_time, price_time FROM advice_runs WHERE run_id = ?').get(runId);
  return row ? ({ ...row } as { advice_time: string | null; price_time: string | null }) : null;
}
