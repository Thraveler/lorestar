import { DatabaseSync } from 'node:sqlite';
import fs from 'node:fs';
import path from 'node:path';

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
  const recipes = db
    .prepare(
      `SELECT r.recipe_id, r.profession, r.name, COALESCE(r.learned, 0) AS learned, r.output_item_id,
              p.med AS out_med, p.n AS out_listings
       FROM recipes r LEFT JOIN prices p ON p.run_id = r.run_id AND p.item_id = r.output_item_id
       WHERE r.run_id = ? ORDER BY r.profession, r.name`,
    )
    .all(runId) as unknown as Omit<RecipeRow, 'reagents'>[];
  const reagents = db
    .prepare(
      `SELECT rr.recipe_id, rr.item_id, rr.qty, i.name, COALESCE(b.qty, 0) AS have,
              p.med AS med, p.n AS listings
       FROM recipe_reagents rr
       LEFT JOIN items i ON i.item_id = rr.item_id
       LEFT JOIN bag_items b ON b.run_id = rr.run_id AND b.item_id = rr.item_id
       LEFT JOIN prices p ON p.run_id = rr.run_id AND p.item_id = rr.item_id
       WHERE rr.run_id = ?`,
    )
    .all(runId) as unknown as (Reagent & { recipe_id: number })[];
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
  const filter =
    scope === 'bags'
      ? 'p.item_id IN (SELECT item_id FROM bag_items WHERE run_id = :latest)'
      : scope === 'reagents'
        ? 'p.item_id IN (SELECT item_id FROM recipe_reagents WHERE run_id = :latest)'
        : 'p.item_id IN (SELECT item_id FROM prices WHERE run_id = :latest)';
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
    .all({ latest: latest.id }) as unknown as (PricePoint & { item_id: number; name: string | null; vendor: number | null; qty: number })[];
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
