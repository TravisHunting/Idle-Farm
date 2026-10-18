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

The **player** does not control the farmer. Instead, **Activities** (cards) drip-feed in at random
intervals and pile up (cap 24). The player can spend them one at a time or hit **USE ALL** to dump the
whole stack at once. Activities cause events, change the world/environment, or defend the farmer
(e.g. Rain Cloud, Shoo!, Watchdog, Lucky Charm, Summon Storm, Meteorite...).

## How to run
- Open the project in Godot 4.7+ and press Play (main scene `res://scenes/main.tscn`).
- Running from the editor embeds the game in the editor's Game tab, so the side-docking /
  borderless / transparent window behaviour only shows in a standalone run or export
  (`Engine.is_embedded_in_editor()` disables window placement).
- Save file: `user://idle_farm_save.json` (autosave every 30s and on quit). Delete it to start fresh.
- Debug keys (only in debug builds): `F1` +1 random card, `F2` +10 cards, `F3` random event,
  `F4` toggle 10x time speed, `F5` wipe save & restart.

## Architecture (all code-driven, no external art)
| File | Role |
|---|---|
| `scripts/art.gd` (autoload **Art**) | Palette, ASCII sprites → textures, procedural painters (house, coop, trees, ground), 3x5 pixel font (`draw_text`, `text_width`, `wrap`). |
| `scripts/game.gd` (autoload **Game**) | Global state: coins, level, clock/day, weather, cards (drip feed), buffs, farmer stats (health/energy/mood/poison), inventory, log, save/load data, all data tables (CROPS, STRUCTS, CARDS). |
| `scripts/main.gd` | Builds the scene tree in code, window docking (right/left edge of the screen, integer pixel scale), save/load + offline progress, debug keys. |
| `scripts/world.gd` | 12x16 tile grid (ground, wetness, crops, objects), crop growth, pathfinding (BFS), actor list (farmer + animals), particles & floating text spawners, ground/crop drawing. |
| `scripts/entity_layer.gd` | Y-sorted drawing of objects, farmer and animals. |
| `scripts/fx_layer.gd` | Particles. |
| `scripts/weather_fx.gd` | Rain, storm darkness, lightning flashes, heat shimmer, cloud shadows. |
| `scripts/farmer.gd` | Farmer AI (utility-scored task picker + state machine), stats, speech, danger handling, faint/recovery. |
| `scripts/animal.gd` | All critters: crow, rabbit, fox, boar, snake, wasps (threats); chicken, dog, merchant, butterfly, bee (friendly). |
| `scripts/director.gd` | Random event scheduler, weather cycle, lightning & fire, and **card effects** (`play_card`, `play_all`). |
| `scripts/hud.gd` | Everything UI: top bar (coins/day/clock/weather, drag, dock/min/close buttons), status strip (HP/energy/mood/buffs/activity/log), activity tray (card slots, USE ALL, tooltips), speech bubbles & floating texts. |

Logical resolution 192x432 (viewport stretch, integer scale, nearest filter). Layout:
`0-16` top bar · `16-272` farm (12x16 tiles of 16px) · `272-302` status · `302-432` activities tray.

## Checklist

### Foundation
- [x] TODO/handoff doc
- [x] Project settings: 192x432 viewport, integer scale, nearest filtering, borderless, transparent, always-on-top, 30 FPS cap
- [x] Autoloads Art + Game
- [x] Main scene built in code; window docks to right/left screen edge, scale from screen height
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

### Activities (player)
- [x] Drip feed with cap + countdown
- [x] 19 cards: Rain Cloud, Sunshine, Shoo!, Watchdog, Soup, Coffee, Lucky Charm, Fertilizer, Golden Seed, Lucky Coins, Clear Skies, Summon Storm, Meteorite, Spring Bloom, Bee Swarm, Merchant, Sapling, Stir Critters, Tremor
- [x] Play single card (click), USE ALL (staggered)
- [x] Tooltips

### Persistence
- [x] Save/load JSON (state + grid + farmer)
- [x] Offline progress (cards accrue, crops grow; capped at 8h) — *implemented, not yet tested (needs >60s between sessions)*

### Verification
- [x] Runs without script errors in the editor (MCP run + logs)
- [x] Screenshot check of layout

## Next up / ideas (not started)
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

## Changelog
- 2026-10-18 — Project started; handoff doc written.
- 2026-10-18 — v0.1 built and verified via Godot MCP: clean runs (no runtime errors), all 19 cards
  and all 10 random events exercised, faint/recovery, storm + lightning + fire, save -> reload, and a
  standalone run that docked a 384x864 window bottom-right on a 1920x1128 usable screen.
  Balance tweaks after playtest: no building until 4 tilled tiles; sell only when the load is worth it;
  lightning ash is rarer and washes away.
  Known: if the editor shows "Identifier not found: Game" errors, they are a stale editor script cache
  from before the autoloads were registered — restart the editor (the game itself runs clean).
