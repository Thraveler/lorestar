"""Load one or more parsed runs (data/runs/<label>/parsed.json) into data/lorestar.db.

Usage: python3 -I tools/ingest.py [--db PATH] RUN_DIR [RUN_DIR ...]
Idempotent: re-ingesting a run replaces its rows. Standard library only.
"""
import argparse, json, os, sqlite3, sys

HERE = os.path.dirname(os.path.abspath(__file__))

# Columns added after the first release; older databases get them with ALTER TABLE.
NEW_COLUMNS = {
    "items": {"stack_size": "INTEGER"},
    "recipes": {"difficulty": "INTEGER", "trivial_level": "INTEGER", "can_skill_up": "INTEGER",
                "out_min": "INTEGER", "out_max": "INTEGER"},
}


def migrate(conn):
    for table, columns in NEW_COLUMNS.items():
        have = {row[1] for row in conn.execute(f"PRAGMA table_info({table})")}
        for name, kind in columns.items():
            if name not in have:
                conn.execute(f"ALTER TABLE {table} ADD COLUMN {name} {kind}")
DEFAULT_DB = os.path.join(HERE, "..", "data", "lorestar.db")


def seq(d):
    """The Lua parser turns arrays into dicts with numeric-string keys; return values in order."""
    if isinstance(d, dict):
        return [d[k] for k in sorted(d, key=lambda k: int(k) if str(k).isdigit() else 0)]
    return list(d or [])


def b(v):
    return None if v is None else int(bool(v))


def ingest(conn, run_dir):
    label = os.path.basename(os.path.normpath(run_dir))
    D = json.load(open(os.path.join(run_dir, "parsed.json"), encoding="utf-8"))
    snap = D.get("snapshot") or {}
    S = snap.get("sections") or {}
    P = D.get("prices") or {}
    bags = (S.get("bags") or {}).get("bags") or {}
    used = sum(v.get("used", 0) for v in bags.values())
    slots = sum(v.get("slots", 0) for v in bags.values())

    conn.execute("DELETE FROM runs WHERE label = ?", (label,))
    cur = conn.execute(
        "INSERT INTO runs (label, addon_version, snapshot_time, scan_time, price_schema, scan_rows,"
        " anonymous, bag_used, bag_slots, section_errors) VALUES (?,?,?,?,?,?,?,?,?,?)",
        (label, snap.get("addonVersion"), snap.get("time"), P.get("time"), P.get("schema"),
         P.get("rows"), b(D.get("anonymous")), used or None, slots or None, len(snap.get("errors") or {})),
    )
    rid = cur.lastrowid

    # Items + bag contents
    totals = (S.get("bags") or {}).get("totals") or {}
    infos = (S.get("items") or {}).get("items") or {}
    for iid, qty in totals.items():
        conn.execute("INSERT INTO bag_items VALUES (?,?,?)", (rid, int(iid), qty))
        info = (infos.get(iid) or {}).get("info")
        if info:
            conn.execute(
                "INSERT OR REPLACE INTO items (item_id, name, quality, item_level, min_level, type, subtype,"
                " class_id, subclass_id, vendor_sell_price, is_reagent, bind_type, stack_size)"
                " VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (int(iid), info.get("1"), info.get("3"), info.get("4"), info.get("5"), info.get("6"),
                 info.get("7"), info.get("12"), info.get("13"), info.get("11"), b(info.get("17")), info.get("14"),
                 info.get("8")),
            )

    # v0.4.4 itemnames: names for recipe reagents and outputs. Bag items keep their fuller info (INSERT OR IGNORE).
    names = ((S.get("itemnames") or {}).get("items")) or {}
    for iid, v in names.items():
        if isinstance(v, dict) and v.get("n"):
            conn.execute("INSERT OR IGNORE INTO items (item_id, name, quality, vendor_sell_price) VALUES (?,?,?,?)",
                         (int(iid), v.get("n"), v.get("q"), v.get("s")))

    # Recipes (per profession) and professions
    by_prof = (S.get("recipes") or {}).get("byProfession") or {}
    primary = {}
    n_recipes = 0
    for prof, entry in by_prof.items():
        bp = entry.get("baseProfession") or {}
        if isinstance(bp, dict) and "isPrimaryProfession" in bp:
            primary[prof] = b(bp["isPrimaryProfession"])
        for row in (entry.get("modern") or {}).values():
            rec = row.get("id")
            if rec is None:
                continue
            conn.execute(
                "INSERT OR REPLACE INTO recipes (run_id, recipe_id, profession, name, learned, category_id,"
                " output_item_id, difficulty, trivial_level, can_skill_up, out_min, out_max)"
                " VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                (rid, rec, prof, row.get("name"), b(row.get("learned")), row.get("categoryID"),
                 row.get("outputItemID"), row.get("diff"), row.get("trivial"), b(row.get("skillUp")),
                 row.get("outMin"), row.get("outMax")))
            n_recipes += 1
            for rg in seq(row.get("reagents")):
                if isinstance(rg, dict) and isinstance(rg.get("itemID"), int):
                    conn.execute("INSERT OR REPLACE INTO recipe_reagents VALUES (?,?,?,?)",
                                 (rid, rec, rg["itemID"], rg.get("qty")))
    for row in ((S.get("professions") or {}).get("info") or {}).values():
        if isinstance(row, dict) and row.get("1"):
            name = row["1"]
            conn.execute("INSERT OR REPLACE INTO professions VALUES (?,?,?,?,?,?)",
                         (rid, name, row.get("3"), row.get("4"), row.get("7"), primary.get(name)))

    # Names and facts remembered at loot time (addon v0.4.8); bag and recipe info wins (INSERT OR IGNORE)
    for iid, v in ((D.get("loot") or {}).get("names") or {}).items():
        if isinstance(v, dict) and v.get("n"):
            conn.execute("INSERT OR IGNORE INTO items (item_id, name, quality, vendor_sell_price, class_id, stack_size)"
                         " VALUES (?,?,?,?,?,?)", (int(iid), v.get("n"), v.get("q"), v.get("s"), v.get("c"), v.get("st")))

    # In-game advisor output (addon v0.4.8), kept to compare with the web engine
    advice = D.get("advice") or {}
    n_advice = 0
    if isinstance(advice, dict) and advice.get("items"):
        conn.execute("INSERT OR REPLACE INTO advice_runs VALUES (?,?,?)", (rid, advice.get("time"), advice.get("priceTime")))
        for iid, a in advice["items"].items():
            conn.execute("INSERT OR REPLACE INTO advice_items VALUES (?,?,?,?,?,?,?,?,?)",
                         (rid, int(iid), a.get("a"), a.get("k"), a.get("s"), a.get("u"), a.get("r"), a.get("c"), a.get("b")))
            n_advice += 1

    # Loot probe (addon v0.4.7): cumulative aggregates as of this run
    loot = D.get("loot") or {}
    n_loot = 0
    if isinstance(loot, dict) and loot.get("agg"):
        for mid, name in (loot.get("zones") or {}).items():
            conn.execute("INSERT OR REPLACE INTO zones VALUES (?,?)", (int(mid), name))
        subs = loot.get("sub") or {}
        for key, rec in loot["agg"].items():
            parts = key.split("|")
            if len(parts) != 4:
                continue
            mid, cx, cy, src = int(parts[0]), int(parts[1]), int(parts[2]), parts[3]
            stype, _, sid = src.partition(":")
            conn.execute(
                "INSERT OR REPLACE INTO loot_sources VALUES (?,?,?,?,?,?,?,?,?)",
                (rid, mid, cx, cy, src, stype if sid else None, int(sid) if sid.isdigit() else None,
                 rec.get("opens"), subs.get(f"{mid}|{cx}|{cy}")))
            for iid, qty in (rec.get("items") or {}).items():
                conn.execute("INSERT OR REPLACE INTO loot_items VALUES (?,?,?,?,?,?,?)",
                             (rid, mid, cx, cy, src, int(iid), qty))
            n_loot += 1
    pr = (loot.get("probe") or {}) if isinstance(loot, dict) else {}
    if pr:
        conn.execute("INSERT OR REPLACE INTO loot_probe VALUES (?,?,?,?,?,?,?,?,?)",
                     (rid, b(loot.get("enabled")), pr.get("opens"), pr.get("recorded"), pr.get("noPosition"),
                      pr.get("noSource"), pr.get("secret"), pr.get("errors"), pr.get("droppedKeys")))

    # AH prices
    items = P.get("items") or {}
    conn.executemany(
        "INSERT INTO prices VALUES (?,?,?,?,?,?,?)",
        [(rid, int(i), r.get("n"), r.get("q"), r.get("m"), r.get("p10"), r.get("med")) for i, r in items.items()],
    )
    print(f"{label}: {len(totals)} bag items, {len(names)} extra item names, {n_recipes} recipes, {len(items)} prices, {n_loot} loot records, {n_advice} advice rows")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=DEFAULT_DB)
    ap.add_argument("runs", nargs="+")
    a = ap.parse_args()
    os.makedirs(os.path.dirname(os.path.abspath(a.db)), exist_ok=True)
    conn = sqlite3.connect(a.db)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.executescript(open(os.path.join(HERE, "schema.sql"), encoding="utf-8").read())
    migrate(conn)
    with conn:
        for r in a.runs:
            ingest(conn, r)
    conn.close()


if __name__ == "__main__":
    sys.exit(main())
