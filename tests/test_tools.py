"""Tests for the Python tools: the SavedVariables parser and the SQLite ingestor.

Run with: python3 -I -m unittest discover -s tests -p 'test_*.py'
Uses only the standard library and synthetic data (never real dumps).
"""
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "tools")

LUA_SAMPLE = r'''
LorestarDB = {
	["snapshot"] = {
		["time"] = "2026-01-01 10:00:00",
		[1] = "quote \" and \\ backslash",
		[2] = -3.5,
		["flag"] = true, -- trailing comment
		["nothing"] = nil,
	},
	["list"] = { 10, 20, 30, },
	["big"] = { [2770] = { ["n"] = 1, }, },
}
'''


def write(path, text):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def dump_json(path, obj):
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(obj, fh)


def load_json(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def run(*args):
    return subprocess.run([sys.executable, "-I", *args], capture_output=True, text=True)


def synthetic_run(scan=True, loot=False):
    """A minimal parsed.json in the shape the addon produces."""
    D = {
        "anonymous": True,
        "snapshot": {
            "time": "2026-11-09 21:00:00", "addonVersion": "0.0.0", "errors": {},
            "sections": {
                "bags": {"bags": {"0": {"used": 2, "slots": 4}}, "totals": {"2770": 6, "2589": 52}},
                "items": {"items": {
                    "2770": {"info": {"1": "Copper Ore", "3": 1, "4": 1, "5": 0, "6": "Trade Goods", "7": "Metal",
                                      "11": 5, "12": 7, "13": 2, "14": 0, "17": True}},
                    "2589": {"info": {"1": "Linen Cloth", "3": 1, "4": 5, "5": 0, "6": "Trade Goods", "7": "Cloth",
                                      "11": 13, "12": 7, "13": 5, "14": 0, "17": True}}}},
                "itemnames": {"items": {"2840": {"n": "Copper Bar", "q": 1, "s": 25}}},
                "professions": {"info": {"1": {"1": "Mining", "3": 78, "4": 150, "7": 186}}},
                "recipes": {"byProfession": {"Mining": {
                    "baseProfession": {"isPrimaryProfession": True},
                    "modern": {
                        "1": {"id": 2657, "name": "Smelt Copper", "learned": True, "categoryID": 1,
                              "outputItemID": 2840, "reagents": {"1": {"itemID": 2770, "qty": 1}}},
                        "2": {"id": 2658, "name": "Smelt Silver", "learned": False, "categoryID": 1,
                              "outputItemID": 2841, "reagents": {"1": {"itemID": 2775, "qty": 1}}},
                    }}}},
            },
        },
    }
    if scan:
        D["prices"] = {"time": "2026-11-09 21:05:00", "rows": 3, "schema": 2, "distinct": 2,
                       "items": {"2770": {"n": 2, "q": 11, "m": 100, "p10": 150, "med": 150},
                                 "2589": {"n": 1, "q": 5, "m": 10, "p10": 10, "med": 10}}}
    if loot:
        D["loot"] = {"enabled": True, "zones": {"1411": "Durotar"}, "sub": {"1411|27|31": "Razor Hill"},
                     "agg": {"1411|27|31|npc:3111": {"opens": 5, "items": {"2770": 7}},
                             "1411|-1|-1|?": {"opens": 1, "items": {"2589": 1}}},
                     "probe": {"opens": 6, "recorded": 6, "noPosition": 1, "noSource": 1, "secret": 0,
                               "errors": 0, "droppedKeys": 0}}
    return D


class AnalyzeTests(unittest.TestCase):
    def test_parses_saved_variables(self):
        with tempfile.TemporaryDirectory() as d:
            src = os.path.join(d, "Lorestar.lua")
            write(src, LUA_SAMPLE)
            out = os.path.join(d, "out.json")
            r = run(os.path.join(TOOLS, "analyze.py"), src, out)
            self.assertEqual(r.returncode, 0, r.stderr)
            D = load_json(out)
            self.assertEqual(D["snapshot"]["time"], "2026-01-01 10:00:00")
            self.assertEqual(D["snapshot"]["1"], 'quote " and \\ backslash')
            self.assertEqual(D["snapshot"]["2"], -3.5)
            self.assertIs(D["snapshot"]["flag"], True)
            self.assertEqual(D["list"], {"1": 10, "2": 20, "3": 30})
            self.assertEqual(D["big"]["2770"]["n"], 1)

    def test_default_output_is_next_to_the_input(self):
        with tempfile.TemporaryDirectory() as d:
            src = os.path.join(d, "Lorestar.lua")
            write(src, LUA_SAMPLE)
            self.assertEqual(run(os.path.join(TOOLS, "analyze.py"), src).returncode, 0)
            self.assertTrue(os.path.exists(os.path.join(d, "parsed.json")))

    def test_garbage_input_fails_cleanly(self):
        with tempfile.TemporaryDirectory() as d:
            src = os.path.join(d, "bad.lua")
            write(src, "LorestarDB = { @@@ }")
            self.assertNotEqual(run(os.path.join(TOOLS, "analyze.py"), src).returncode, 0)


class IngestTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = os.path.join(self.tmp.name, "t.db")

    def tearDown(self):
        self.tmp.cleanup()

    def make_run(self, label, **kw):
        d = os.path.join(self.tmp.name, label)
        os.makedirs(d)
        dump_json(os.path.join(d, "parsed.json"), synthetic_run(**kw))
        return d

    def ingest(self, *dirs):
        r = run(os.path.join(TOOLS, "ingest.py"), "--db", self.db, *dirs)
        self.assertEqual(r.returncode, 0, r.stderr)
        return sqlite3.connect(self.db)

    def test_loads_every_table(self):
        c = self.ingest(self.make_run("2026-11-09-v0.0.0", loot=True))
        q = lambda sql: c.execute(sql).fetchall()
        self.assertEqual(q("SELECT COUNT(*) FROM bag_items")[0][0], 2)
        self.assertEqual(q("SELECT name, vendor_sell_price FROM items WHERE item_id=2770")[0], ("Copper Ore", 5))
        self.assertEqual(q("SELECT name FROM items WHERE item_id=2840")[0][0], "Copper Bar")   # from itemnames
        self.assertEqual(q("SELECT COUNT(*), SUM(learned) FROM recipes")[0], (2, 1))
        self.assertEqual(q("SELECT is_primary FROM professions")[0][0], 1)
        self.assertEqual(q("SELECT med FROM prices WHERE item_id=2770")[0][0], 150)
        self.assertEqual(q("SELECT opens, subzone FROM loot_sources WHERE source='npc:3111'")[0], (5, "Razor Hill"))
        self.assertEqual(q("SELECT qty FROM loot_items WHERE item_id=2770")[0][0], 7)
        self.assertEqual(q("SELECT name FROM zones")[0][0], "Durotar")
        self.assertEqual(q("PRAGMA foreign_key_check"), [])

    def test_is_idempotent(self):
        d = self.make_run("run-a", loot=True)
        self.ingest(d)
        c = self.ingest(d)
        self.assertEqual(c.execute("SELECT COUNT(*) FROM runs").fetchone()[0], 1)
        self.assertEqual(c.execute("SELECT COUNT(*) FROM prices").fetchone()[0], 2)
        self.assertEqual(c.execute("SELECT COUNT(*) FROM loot_items").fetchone()[0], 2)

    def test_bag_items_keep_their_full_info(self):
        c = self.ingest(self.make_run("run-a"))
        # itemnames never overwrites the fuller info of a bag item
        self.assertEqual(c.execute("SELECT is_reagent FROM items WHERE item_id=2770").fetchone()[0], 1)

    def test_run_without_scan_uses_the_earlier_scan(self):
        a = self.make_run("run-a", scan=True)
        b = self.make_run("run-b", scan=False)
        c = self.ingest(a, b)
        rows = c.execute(
            "SELECT run_id, name, med FROM v_bag_advice WHERE name='Copper Ore' ORDER BY run_id").fetchall()
        self.assertEqual([r[2] for r in rows], [150, 150])   # run-b falls back to run-a's scan

    def test_run_before_any_scan_has_no_prices(self):
        c = self.ingest(self.make_run("run-a", scan=False))
        self.assertIsNone(c.execute("SELECT med FROM v_bag_advice WHERE name='Copper Ore'").fetchone()[0])

    def test_view_counts_learned_and_unlearned_recipes(self):
        c = self.ingest(self.make_run("run-a"))
        row = c.execute("SELECT learned_recipes, unlearned_recipes FROM v_bag_advice WHERE name='Copper Ore'").fetchone()
        self.assertEqual(row, (1, 0))


if __name__ == "__main__":
    unittest.main()
