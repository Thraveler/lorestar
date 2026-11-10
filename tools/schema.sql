-- Lorestar local database. Prices are unit copper. One row set per run (a run = one in-game session).
CREATE TABLE IF NOT EXISTS runs (
    id             INTEGER PRIMARY KEY,
    label          TEXT NOT NULL UNIQUE,   -- run folder name, e.g. 2026-11-09-v0.4.3
    addon_version  TEXT,
    snapshot_time  TEXT,
    scan_time      TEXT,
    price_schema   INTEGER,                -- NULL = v1 (min only), 2 = min + p10 + med
    scan_rows      INTEGER,
    anonymous      INTEGER,
    bag_used       INTEGER,
    bag_slots      INTEGER,
    section_errors INTEGER
);

CREATE TABLE IF NOT EXISTS items (          -- latest known info per item (bag items only)
    item_id           INTEGER PRIMARY KEY,
    name              TEXT,
    quality           INTEGER,              -- 0 poor, 1 common, 2 uncommon, 3 rare, 4 epic, 5 legendary
    item_level        INTEGER,
    min_level         INTEGER,
    type              TEXT,
    subtype           TEXT,
    class_id          INTEGER,
    subclass_id       INTEGER,
    vendor_sell_price INTEGER,
    is_reagent        INTEGER,
    bind_type         INTEGER
);

CREATE TABLE IF NOT EXISTS bag_items (
    run_id  INTEGER NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    item_id INTEGER NOT NULL,
    qty     INTEGER NOT NULL,
    PRIMARY KEY (run_id, item_id)
);

CREATE TABLE IF NOT EXISTS professions (
    run_id     INTEGER NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    skill      INTEGER,
    max_skill  INTEGER,
    skill_line INTEGER,
    is_primary INTEGER,                      -- NULL when the profession window was not dumped
    PRIMARY KEY (run_id, name)
);

CREATE TABLE IF NOT EXISTS recipes (
    run_id         INTEGER NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    recipe_id      INTEGER NOT NULL,
    profession     TEXT NOT NULL,
    name           TEXT,
    learned        INTEGER,
    category_id    INTEGER,
    output_item_id INTEGER,
    PRIMARY KEY (run_id, recipe_id)
);

CREATE TABLE IF NOT EXISTS recipe_reagents (
    run_id    INTEGER NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    recipe_id INTEGER NOT NULL,
    item_id   INTEGER NOT NULL,
    qty       INTEGER,
    PRIMARY KEY (run_id, recipe_id, item_id)
);

CREATE TABLE IF NOT EXISTS prices (
    run_id  INTEGER NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    item_id INTEGER NOT NULL,
    n       INTEGER,                         -- listings
    q       INTEGER,                         -- total quantity
    m       INTEGER,                         -- lowest unit buyout
    p10     INTEGER,
    med     INTEGER,
    PRIMARY KEY (run_id, item_id)
);

CREATE INDEX IF NOT EXISTS idx_reagents_item ON recipe_reagents(item_id);
CREATE INDEX IF NOT EXISTS idx_recipes_profession ON recipes(run_id, profession);

-- Bags with vendor price, AH prices and how many recipes use each item.
DROP VIEW IF EXISTS v_bag_advice;
CREATE VIEW v_bag_advice AS
SELECT b.run_id, b.item_id, i.name, i.quality, b.qty, i.vendor_sell_price AS vendor,
       p.n AS listings, p.m, p.p10, p.med,
       (SELECT COUNT(*) FROM recipe_reagents rr JOIN recipes r
          ON r.run_id = rr.run_id AND r.recipe_id = rr.recipe_id
        WHERE rr.run_id = b.run_id AND rr.item_id = b.item_id AND r.learned = 1) AS learned_recipes,
       (SELECT COUNT(*) FROM recipe_reagents rr JOIN recipes r
          ON r.run_id = rr.run_id AND r.recipe_id = rr.recipe_id
        WHERE rr.run_id = b.run_id AND rr.item_id = b.item_id AND r.learned = 0) AS unlearned_recipes
FROM bag_items b
LEFT JOIN items i ON i.item_id = b.item_id
LEFT JOIN prices p ON p.run_id = b.run_id AND p.item_id = b.item_id;
