# Lorestar

Bag / inventory advisor addon for **WoW Forever** (Midnight Retail client, interface 16001). For each bag item it will recommend keep / sell on AH / vendor / discard. Project knowledge, decisions and progress log live in the vault: `/Users/thraveler/workspace/vault/10-projects/lorestar/`. This file only holds what you need to write code.

## Working with the user
- Talk in Latin American Spanish, keep WoW terms in English (Auction House, vendor, reagent, bags). **Code, comments and docs in English.**
- Fullstack dev (Go, Python, JS), new to Lua: explain Lua-specific things briefly. Keep explanations short.
- Small iterations: explore data first, then design. Do not over-build.
- Dev machine is separate from the game PC. The addon travels as a zip; SavedVariables come back and are analyzed here.

## Hard rules
- **Recommend only.** Never automate selling, buying, posting or any gameplay action. Read-only data collection.
- **Privacy:** never store character name, realm, gold, GUIDs, battletags, or AH seller/bidder data. Anonymous mode stays default ON.
- Addons have no network access. External data must enter as a generated Lua data file.
- Midnight "secret values": check `isSecret` before comparing or doing arithmetic on any API return. No combat log, no in-combat unit data.

## Layout
```
Lorestar/        the addon (folder name must match Lorestar.toc exactly): Lorestar.lua (core, slash commands),
                 Lorestar_UI.lua (minimap button + panel, built under pcall; core exposes ns.actions)
tools/           analyze.py: Lua SavedVariables -> JSON parser
tools/ingest.py  parsed.json -> SQLite (schema in tools/schema.sql)
scripts/         build.sh (zip into dist/), new-run.sh (store + parse + ingest one in-game run)
data/runs/       one folder per in-game run (git-ignored, real dumps)
data/lorestar.db local SQLite, one row set per run (git-ignored); view v_bag_advice joins bags, prices and recipes
dist/            built zips (git-ignored)
```

## Workflow
1. `scripts/build.sh` -> `dist/Lorestar-v<version>.zip` (syntax-checks with `luajit -bl`). Copy it to the game PC, unzip into `Interface/AddOns/`.
2. In game, run commands, then `/reload` (SavedVariables are only written on reload/logout).
3. Bring back `WTF/Account/<ACCOUNT>/SavedVariables/Lorestar.lua` and run `scripts/new-run.sh <file>` (stores, parses and ingests it).
4. SavedVariables are large (~450 KB). Never read whole: parse and query `parsed.json` selectively. Parsed arrays have numeric-string keys.
5. Re-run the privacy scan on every new dump (GUID `Player-`, battletag `\w+#\d{3,5}`, emails, owner/bidder keys, `<hidden>`).

## Gotchas
- Lua 5.1: no `goto`, no integer division, `#` on tables with holes is unreliable. Wrap every API in `pcall`.
- Profession window must be open for the `recipes` dump. AH must be open for `/lorestar scan` (throttled ~15 min).
- `GetReplicateItemInfo` indexes start at 0; the positional return order is assumed, verify against `prices.probe`.
- `TRADE_SKILL_UPDATE` does not exist in Forever. Avoid slash commands `/lm`, `/ls`, `/codex`, `/titan`.
- Current version: see `Lorestar/Lorestar.toc`. v0.4.3 ran clean in game on 2026-11-09; v0.4.4 and v0.4.5 passed syntax checks and simulated tests, not yet run in game.
