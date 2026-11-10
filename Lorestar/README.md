# Lorestar

Companion addon for WoW Forever (Interface 16001).

Right now Lorestar is an **explorer**: it reads data from the game and stores it in a
local file, so we can see exactly what addons are allowed to do in Forever. That data is
the groundwork for a bag and profession advisor (what to keep, sell or vendor).

It does not change anything in the game, does not press keys or act for you, and has no
network access.

## Install

1. Copy the whole `Lorestar` folder (it contains `Lorestar.toc` and `Lorestar.lua`) into
   Forever's `Interface/AddOns/` directory. The folder must be named exactly `Lorestar`.
2. If you used the old ForeverProbe, delete its folder first. You can also delete
   `ForeverProbe.lua` in `WTF/Account/<account>/SavedVariables/`.
3. Log in or `/reload`. You should see `Lorestar: loaded v0.4.3`.

## Commands

| Command | What it does |
|---|---|
| `/lorestar` | Show help |
| `/lorestar dump [section]` | Collect data. Without a section, all of them. |
| `/lorestar api` | Record every global function, `C_*` namespace and Enum in this client |
| `/lorestar events on\|off` | Count events and their argument types; sample auction house results you search |
| `/lorestar scan` | With the auction house open, record the lowest buyout, listing count and total quantity per item (stored in `LorestarDB.prices`) |
| `/lorestar anon on\|off` | Anonymous mode (default ON) |
| `/lorestar status` | Show what is recorded |
| `/lorestar clear` | Wipe everything recorded |

After any command, `/reload` (or logging out) writes the data to disk.

## Sections (`/lorestar dump <section>`)

`build`, `player`, `stats`, `professions`, `bags`, `equipment`, `reputation`, `quests`,
`currencies`, `spellbook`, `talents`, `secrets`, and new in 0.3.0:

- `items`: for every item in your bags, class and sub-class, vendor sell price, quality,
  binding and whether it is a crafting reagent. Items the client has not cached yet come
  back empty; wait a few seconds and run it again.
- `recipes`: known recipes and their reagents. **Open a profession window first**
  (for example Blacksmithing), otherwise there is nothing to read.
- `auction`: which auction house functions exist in Forever and a few state checks.

## Suggested test run

1. Out of combat, with items in your bags: `/lorestar dump`, then `/lorestar api`.
2. Open your Blacksmithing window, then `/lorestar dump recipes`.
3. `/lorestar dump items`, wait a few seconds, run it once more.
4. `/lorestar events on`. Open the auction house and do a few normal searches (a stackable
   material such as ore, and a piece of gear). Also loot, mine, craft and visit a vendor.
   Then `/lorestar events off`.
5. `/reload`.

## What's new in 0.4.3

- `recipes`: when carrying earlier professions forward, empty entries (such as the `''` key saved by v0.4.1) are dropped, so old data self-heals without `/lorestar clear`.

## What's new in 0.4.2

- `/lorestar scan` now also stores `p10` (unit price under which the cheapest 10% of units sit) and `med` (quantity-weighted median) per item, next to `m` (lowest unit buyout), so one cheap listing no longer defines the price. `prices.schema = 2`.
- `recipes`: a dump with no recipe rows (window closed) no longer saves an empty entry; it only reports a note.

## What's new in 0.4.1

- `recipes` is now stored per profession (`recipes.byProfession[<name>]`). Open each profession window and run `/lorestar dump recipes`; one `/reload` at the end writes them all. A later dump with the window closed no longer wipes earlier recipes.

## What's new in 0.4.0

- Removed the unknown `TRADE_SKILL_UPDATE` event.
- `recipes` now records every recipe (up to 2000) with reagents and learned flag; hyperlinks dropped to keep the file small.
- New `/lorestar scan`: read-only auction house price scan. Seller and bidder values are discarded, never stored. The game throttles the underlying request to about once per 15 minutes.
- Added `AUCTION_HOUSE_CLOSED` to tracked events.

## Anonymous mode

On by default. It hides your character name, realm and gold, drops free-text samples of
events, and replaces any remaining occurrence of your name, realm or character GUID
(`Player-...`, which can appear inside links of items you crafted) in the collected data.
Turn it off with `/lorestar anon off`. Data already saved does not change when you toggle
it: use `/lorestar clear` and collect again.

Auction house samples never include seller or bidder names, in either mode.

## Where the data goes

`WTF/Account/<account>/SavedVariables/Lorestar.lua`, inside Forever's game folder.
Before sharing it, open it with a text editor and search for your character name. Do not
share the folder path: it contains an identifier of your account.

## Troubleshooting

Enable Lua errors with `/console scriptErrors 1` and include the message when reporting a
problem. A section that fails is recorded under `errors` in the file and does not stop
the others.
