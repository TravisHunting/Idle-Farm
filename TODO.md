# Idle Farm — Implementation TODO & Handoff

> **Read this first if you are picking up this project.** It is the single source of truth for
> design intent, architecture and progress. Tick boxes as you finish things and add a line to the
> Changelog at the bottom. Keep it honest: unchecked = not done / not verified.

## Concept
A cozy idle game that lives in a narrow, always-on-top, borderless window docked to the side of the
screen (like *Rusty's Retirement*). Cute procedural pixel art. A **Farmer** NPC runs his farm on his
own: tilling, planting, watering, harvesting, selling, building, tearing down, rearranging, chatting
in little speech bubbles, and reacting to weather, pests and predators. He can get hurt, poisoned,
exhausted or faint if the player never helps.

The **player** does not control the farmer. Instead, **choice cards** drip-feed in at random
intervals and pile up (hand cap 16). Each card offers **two choices - pick one**. Some choices have
requirements (e.g. "3 sunflowers growing at once", "a lightning rod", "the Fleshy Tome", "night time")
or costs (coins, eggs, ripe pumpkins, chickens, Lucky Charms). Rarer conditions give bigger rewards.
Cards range from minor (coffee or soup?) to consequential and strange: occult visitors, aliens,
devils, fairies. Choices can grant **relics** (permanent oddities with passive powers, some placed on
the farm), unlock strange crops, schedule delayed consequences, and raise **Weirdness** (0-100),
which unlocks stranger cards and weird random events. The player can open cards one by one or hit
**OPEN ALL** to go through the whole hand in a row.

On launch a **welcome screen** explains how to play; the player clicks through and picks one of
**3 save slots** (each autosaves every 20s, and on menu/quit).

## How to run
- Open the project in Godot 4.7+ and press Play (main scene `res://scenes/main.tscn`).
- Running from the editor embeds the game in the editor's Game tab, so the side-docking /
  borderless / transparent window behaviour only shows in a standalone run or export
  (`Engine.is_embedded_in_editor()` disables window placement).
- Save slots: `user://slot_1.json` .. `slot_3.json` (autosave every 20s, on menu and quit); the
  window dock side is global in `user://settings.json`. Slots can be deleted from the welcome screen
  (DEL, then SURE?). On Windows `user://` is `%APPDATA%/Godot/app_userdata/IdleFarm/`.
- Window: right side of the screen, vertically centred, 24px from the edge (`EDGE_PADDING` in
  main.gd); the `<`/`>` button flips it to the left.
- Debug keys (only in debug builds): `F1` draw a card, `F2` +10 cards, `F3` random event,
  `F4` toggle 10x time speed, `F5` wipe current slot & back to menu, `F6` +10 weirdness.
- MCP testing tip: `game_manage input_mouse` positions are in *window* pixels (2x the 192x432
  canvas in the editor's embedded view).
- Export: see "Exporting" below.

## Architecture (all code-driven, no external art)
| File | Role |
|---|---|
| `scripts/art.gd` (autoload **Art**) | Palette, ASCII sprites → textures, procedural painters (house, coop, trees, ground), 3x5 pixel font (`draw_text`, `text_width`, `wrap`). |
| `scripts/art_strange.gd` | Extra ASCII sprites: visitors (`v_*`), relic structures, card art, strange crops, 7x7 relic icons (`r_*`). |
| `scripts/game.gd` (autoload **Game**) | Global state: coins, level, clock/day, weather, hand of cards + drip timer, weirdness, relics, unlocked crops, favoured crop, pending (delayed) effects, buffs, farmer stats, inventory, log; data tables CROPS, STRUCTS, RELICS; slot paths + settings file. |
| `scripts/deck.gd` (class **Deck**) | **The card content** (70 cards, pure data). Its header documents every requirement and effect keyword. Add new cards here. |
| `scripts/cards.gd` | **Card engine**: weighted drawing (rarity, level, weirdness, `needs`), requirement checks with progress text, auto-costs, effect interpreter (`apply`), gamble/delay, relic gain/loss + passives (daily/dawn/night hooks), companion actors. |
| `scripts/welcome.gd` | Welcome screen: how-to-play page, then 3 save slots with summaries + delete. |
| `scripts/main.gd` | Welcome -> slot -> builds the game tree in code (under GameRoot; torn down on menu), window docking (centred right with padding), per-slot save/load + offline progress, debug keys. |
| `scripts/world.gd` | 12x16 tile grid (ground, wetness, crops, objects), crop growth, pathfinding (BFS), actor list (farmer + animals), particles & floating text spawners, ground/crop drawing. |
| `scripts/entity_layer.gd` | Y-sorted drawing of objects, farmer and animals. |
| `scripts/fx_layer.gd` | Particles. |
| `scripts/weather_fx.gd` | Rain, storm darkness, lightning flashes, heat shimmer, cloud shadows. |
| `scripts/farmer.gd` | Farmer AI (utility-scored task picker + state machine), stats, speech, danger handling, faint/recovery. |
| `scripts/animal.gd` | All critters: crow, rabbit, fox, boar, snake, wasps (threats); chicken, dog, merchant, butterfly, bee, wisp (friendly); relic companions homunculus/goat/cat; card visitors (`kind="visitor"`, `sprite` = card art). |
| `scripts/director.gd` | Random event scheduler (+ weird events gated by Weirdness), weather cycle, lightning & fire, relic hooks, and the world **actions** card effects call (`do_action`). |
| `scripts/hud.gd` | In-game UI: top bar (coins/day/clock/weather, drag, menu/dock/min/close), status strip (HP/energy/mood/weirdness eye/buffs/activity/log), card tray (rarity borders, playable pip, OPEN ALL, relic shelf with tooltips), **choice-card modal**, speech bubbles & floating texts. |

Logical resolution 192x432 (viewport stretch, integer scale, nearest filter). Layout:
`0-16` top bar · `16-272` farm (12x16 tiles of 16px; the card modal overlays this) · `272-302` status · `302-432` card tray.

## Exporting
- `export_presets.cfg` has a **Windows Desktop** preset: x86_64, PCK embedded (single .exe), output
  `build/IdleFarm.exe`, release (debug keys off).
- Needs the Godot 4.7.2 export templates (Editor -> Manage Export Templates -> Download and Install).
- CLI: `Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Windows Desktop" build/IdleFarm.exe`

## Checklist

### Foundation
- [x] TODO/handoff doc
- [x] Project settings: 192x432 viewport, integer scale, nearest filtering, borderless, transparent, always-on-top, 30 FPS cap
- [x] Autoloads Art + Game
- [x] Main scene built in code; window docks to right/left screen edge, scale from screen height
- [x] Window vertically centred on the right with edge padding (v0.2)
- [x] Window drag via top bar, dock-side toggle, minimize, close (saves) — *implemented, not yet click-tested in a standalone window*

### Art (procedural pixel art)
- [x] Palette + ASCII sprite pipeline
- [x] 3x5 pixel font
- [x] Ground tiles (grass variants, tilled, wet)
- [x] Farmer frames (idle, walk x2, work) + tools
- [x] Crops: seeds, sprout, growing, ripe (turnip, carrot, wheat, pumpkin, golden melon), dead
- [x] Objects: rock, weed, stump, tree, house, shipping bin, fence, scarecrow, well, coop, beehive, lamp, flowerbed, bench, lightning rod, sign, fire, ash, ore
- [x] Animals: crow, rabbit, fox, boar, snake, chicken, dog, merchant (+ procedural butterflies, bees, wasps)
- [x] Card / HUD icons

### Simulation
- [x] Day/night clock (8 min/day) with night tint
- [x] Weather: sunny, cloudy, rain, storm (lightning), heatwave
- [x] Crop growth, watering/wetness decay, drought damage, death
- [x] Economy: seeds, selling at the shipping bin, levels unlock crops/structures/plot size
- [x] Weeds/debris regrow over time

### Farmer AI
- [x] Utility task picker: sleep, rest, shelter, extinguish, shoo pests, harvest, water, plant, till, clear, sell, build, demolish, rearrange (pickup/place), drink at well, mine ore, chop tree, wander
- [x] BFS pathfinding around solid objects
- [x] Speech bubbles with contextual lines; click the farmer for chatter
- [x] Stats: health, energy, mood, poison; mood/energy affect speed
- [x] Dangers: lightning when working through storms, boar charges, fox bites, wasp stings, snake bites (poison), burns from fires, heatstroke, exhaustion naps
- [x] Faint at 0 HP: out cold, doctor's bill, wakes at home

### Events & critters
- [x] Event director (weighted, conditional on time/weather/level)
- [x] Crows & rabbits eat crops (scarecrows deter)
- [x] Fox at night (steals chickens / digs crops)
- [x] Boar stampede across a row
- [x] Snake hidden in grass, wasp nests
- [x] Lightning strikes & spreading fire (lightning rod protects)
- [x] Friendly: chickens lay eggs, merchant visits, butterflies

### Welcome & saves (v0.2)
- [x] Welcome screen with how-to-play, must click through
- [x] 3 save slots with summaries (day, level, coins, weirdness, relics, saved/played time), delete with confirm
- [x] Autosave every 20s + on menu/quit; in-game menu button returns to the slot picker

### Choice cards (v0.2, replaced the old 19 single-effect activity cards)
- [x] Drip feed into a hand (cap 16) with countdown; OPEN ALL walks through the hand
- [x] Two-choice modal with portrait, flavour text, requirement lines (green met / red unmet with progress), LATER
- [x] Requirement + effect mini-language (see deck.gd header); costs auto-become requirements
- [x] Deck of 70 cards across common / uncommon / rare / legendary + follow-up-only
- [x] Rarity, min level, min weirdness and `needs` gate what can be drawn; seen cards get rarer
- [x] Gambles, delayed consequences (persisted), follow-up cards (e.g. saucer -> They Came Back)
- [x] Weirdness meter (eye icon) unlocks stranger cards & weird events (wisps, knock, crop circle, mutation, whispers, abduction beam); the farm tint shifts violet
- [x] 15 relics with passives (tome, homunculus, black cat, many-eyed goat, crow crown, lantern, idol, obelisk, standing stones, saucer, star map, horseshoe, bone flute, cursed coin, living scarecrow); relic shelf with hover tooltips
- [x] New crops: sunflower (normal), glowshroom / moonflower / starfruit (unlocked by cards, glow at night)
- [x] Visitors walk onto the farm and deliver their line after you choose
- [x] Favoured-crop buff steers what the farmer plants (helps meet "N sunflowers" style goals)

### Persistence
- [x] Save/load JSON per slot (state + grid + farmer + relics/hand/pending)
- [x] Offline progress (cards accrue, crops grow; capped at 8h) — *implemented, not yet tested (needs >60s between sessions)*

### Verification
- [x] Runs without script errors in the editor (MCP run + logs)
- [x] Screenshot check of layout

## Next up / ideas (not started)
- [ ] Balance pass on the deck (reward sizes vs. level scaling; how fast weirdness climbs)
- [ ] More follow-up chains (tome -> ritual -> ?, the homunculus grows up, the stranger's contract)
- [ ] An ending (or several) at Weirdness 100?
- [ ] Dedicated portraits for weather/item cards (some reuse small icons)
- [ ] Night lighting: PointLight2D on lamps + house windows (CanvasModulate is already in place)
- [ ] Mouse passthrough for transparent pixels (`DisplayServer.window_set_mouse_passthrough`)
- [ ] Optional horizontal "bottom dock" layout (Rusty's style strip) — needs a second layout
- [ ] Targeted cards (click a tile to aim Meteorite / Sapling / Rain)
- [ ] Sound: soft ambient + blips (no audio yet)
- [ ] Seasons (crop availability, snow weather)
- [ ] More farmer personality: hobbies, a pet name, diary of the day's events
- [ ] Achievements / farm stats panel
- [ ] Settings panel (card interval, volume, dock, scale)
- [ ] Replace procedural art with hand-drawn PNGs (Art.tex() is the single lookup point)
- [ ] Unit tests for Game economy & World pathfinding

## Gotchas
- Untyped `:=` from Dictionary/Array values breaks GDScript type inference — use `var x = d["k"]`.
- Cells are `Vector2i`; save files store them as `"x,y"` string keys.
- Farmer/animals are `RefCounted` objects updated by `World._process` and drawn by `EntityLayer`
  (not nodes) — keep it that way so y-sorting stays in one place.
- Bubbles/floating texts are drawn by the HUD (CanvasLayer) so they are not darkened by the night tint.
- Connect Game signals with method callables, not lambdas: the game tree is torn down and rebuilt
  when switching slots.
- Card `art` keys must exist in Art (art.gd SPRITES, art_strange.gd SPRITES or painted textures);
  missing ones draw magenta.
- Calls on nodes typed as plain `Node` (e.g. `director.spawn_animal`) return Variant: give the
  variable an explicit type instead of `:=`.

## Changelog
- 2026-10-18 — Project started; handoff doc written.
- 2026-10-18 — v0.1 built and verified via Godot MCP: clean runs (no runtime errors), all 19 cards
  and all 10 random events exercised, faint/recovery, storm + lightning + fire, save -> reload, and a
  standalone run that docked a 384x864 window bottom-right on a 1920x1128 usable screen.
  Balance tweaks after playtest: no building until 4 tilled tiles; sell only when the load is worth it;
  lightning ash is rarer and washes away.
  Known: if the editor shows "Identifier not found: Game" errors, they are a stale editor script cache
  from before the autoloads were registered — restart the editor (the game itself runs clean).
- 2026-10-18 - v0.2: welcome screen + 3 save slots; window centred on the right with padding; the
  activities were replaced by a 70-card two-choice deck with requirements, costs, gambles, delayed
  consequences, relics, weirdness and weird events; strange visitors, crops and companions.
  Verified via MCP: clicked welcome -> slot -> card modal -> choice; applied all 140 choice effects,
  all weird events and all 15 relics in one run with zero runtime errors and no missing art;
  save -> menu -> other slot -> back restores relics/hand/pending/unlocked crops; a new slot starts
  clean. Balance: foxes dig only one crop each and never come on day 1.
