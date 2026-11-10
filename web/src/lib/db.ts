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
