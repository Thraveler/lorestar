# Lorestar

A bag and profession advisor for **WoW Forever** (Midnight Retail client, interface 16001).
For each item in your bags it recommends keep, sell on the Auction House, vendor, discard or review,
based on the recipes you know, Auction House prices and your free bag space. The advice is available in game
(`/lorestar advise`) and in the web viewer, which runs the same rules.

Lorestar only **reads** data and recommends. It never sells, buys, posts or acts for you.

| Part | What it is |
|---|---|
| `Lorestar/` | The in-game addon (Lua). Collects data into SavedVariables. Has a minimap button and panel. |
| `tools/` | Python tools: SavedVariables parser, privacy scan and the SQLite ingestor. |
| `web/` | Local viewer (Astro + Preact + Tailwind) that reads the SQLite. Runs only on your machine. |
| `scripts/` | `build.sh` (addon zip), `new-run.sh` (store, scan, ingest a run), `test.sh` (all tests). |
| `tests/` | Lua tests (LuaJIT with a fake WoW API) and Python tests. |

## Install the addon

1. Get `Lorestar-v<version>.zip` from the latest [release](../../releases) (or run `scripts/build.sh`).
2. Unzip it into the game's `Interface/AddOns/` so you get `Interface/AddOns/Lorestar/`.
3. In game, click the book button on the minimap (or type `/lorestar ui`).

Details and every command: [`Lorestar/README.md`](Lorestar/README.md).

## Development loop

```bash
scripts/test.sh                      # syntax + all tests (needs luajit and python3)
scripts/build.sh                     # dist/Lorestar-v<version>.zip
scripts/new-run.sh <Lorestar.lua>    # SavedVariables from the game -> data/runs/ + data/lorestar.db
cd web && pnpm install && pnpm dev   # viewer at http://127.0.0.1:4321 (pnpm test, pnpm check)
```

The game PC does not need to build anything: download the zip from the release (for a version without a tag, from the latest CI run under Actions → Artifacts, kept 7 days).

Pushing a tag such as `v0.4.7` (it must match `Lorestar/Lorestar.toc`) builds the zip in CI and attaches it to a release.

## Privacy

- The addon runs in anonymous mode by default: no character name, realm or gold, and character GUIDs are scrubbed.
- The loot probe stores no gold, names or GUIDs, only NPC/object IDs and coarse map cells.
- `tools/privacy_scan.py` runs on every new dump and blocks ingestion when it finds a GUID, battletag, email or seller key.
- Real dumps and the database live in `data/` and are git-ignored. Never commit them.

## Requirements

LuaJIT (tests; optional for `build.sh`, which also needs `zip`), Python 3.12+, Node 24+ with pnpm (viewer). Project context, decisions and history
live in a separate personal knowledge base, not in this repository.
