# Idle Farm — Implementation TODO & Handoff

> **Read this first if you are picking up this project.** It is the single source of truth for
> design intent, architecture and progress. Tick boxes as you finish things and add a line to the
> Changelog at the bottom. Keep it honest: unchecked = not done / not verified.

## Concept
A cozy idle game that lives in a narrow, always-on-top, borderless window docked to the side of the
screen (like *Rusty's Retirement*). Cute procedural pixel art. A **Farmer** NPC runs his farm on his
own: clearing the overgrowth grandpa left behind, planning (often silly-shaped) fields, laying
paths, putting up fences, tilling, planting, watering, harvesting, selling, building, rearranging,
chatting in little speech bubbles, and reacting to weather, pests and predators. He can get hurt,
poisoned, exhausted or faint if the player never helps.

Every farm is different: a random **biome** (woodland, rocky, brambles, meadow, marsh) shapes the
heavy overgrowth (tall grass, weeds, bushes, brambles, rocks, boulders, logs, stumps, apple trees,
pines), the house lands somewhere along the top, there may be ponds and junk grandpa left lying
around, and the farmer gets a random **quirk** (tidy, artsy, handy, dreamer, sunflower nut, thrifty).

The **player** does not control the farmer. Instead, a **choice card** slides into the **card box**
every N minutes of real time (default 10, set in the Settings panel). The box holds 3: new cards
push in from the left and the far-right card falls out and is trashed. The player can play cards
from the box or from the **stash** (3 safe slots) at any time, and drag cards freely between them.
Each card offers **two choices - pick one**, and since cards are rare every choice visibly changes
the farm: a new field, paths, fences, buildings, trees, a pond, animals, townsfolk friends who visit
every morning, permanent farmer **abilities**, weather, relics. Some choices have requirements or
costs. Cards can also have **prerequisites** (`needs`): e.g. the Dark Altar sacrifice card only
ever shows up once the farm has at least 1 of the 6 **dark totems**. Weirdness (0-100) unlocks
stranger cards and events.

On launch a **welcome screen** explains how to play; the player clicks through and picks one of
**3 save slots** (each autosaves every 20s, and on menu/quit).

## Factions & the anti-equilibrium design (v0.4)
The long-term goal: the player watches, and guides with a light hand (cards), while systems and
factions interact, reach out to each other, grow, build, die and keep shifting the balance of power.
The farm must **never settle into equilibrium**, and the farmer is **never eliminated** (he can be
changed drastically and lose territory). Four factions compete for the 12x22 farm:
- **The farm**: the farmer's fields, buildings, paths, chickens, friends.
- **The aliens** (`colony.gd` + `alien.gd`): arrive by falling egg, saucer, strange visitor or a
  night lurker that mutates a hen; hatch, grow up into castes (worker/scout/warden/envoy/elder,
  the oldest elder is the matriarch), build a village (pods, hatchery, glow moss, spire, dish,
  pylons), spread a creep over claimed land, eat overgrowth, un-till fields, raid, trade, send
  envoys, abduct (and mutate) the farmer, split in schisms and civil wars, and eventually hear
  "the call" (all leave, or a second wave arrives). With no aliens around, a new arrival is
  always on its way.
- **The Brood** (`swarm.gd` + `insect.gd`), mutant insects the farm itself creates: "radiation"
  (weirdness, alien creep, glowing crops, ore, the obelisk) mutates a wasp nest, a beehive or a
  tree cocoon into a queen; failing that a locust cloud blows in and a fat one stays. Fast
  generations: egg -> grub -> cocoon -> caste by need (ant workers, mantis soldiers, locusts when
  hungry, silk spinners, glowflies, young queens who fly off to found new mounds). They reshape
  the map hardest: mounds grow in 3 sizes, tunnels (`World.insect_land`) undermine fields, webs
  wall off cells and trap critters, wax walls rise on war fronts, locust swarms strip whole bands
  to bare dirt (`World.bare`, nothing regrows for a while), and rain over dense tunnels caves them
  in: **sinkholes become permanent ponds** that swallow whatever stood there. Two relations:
  with the farm (pollination + honey gifts vs. raids, grubs, stings) and with the aliens
  (pollinated glow moss vs. **war**: a front line that moves cell by cell, mantises tearing down
  pods, wardens zapping insects, insects nesting in alien ruins). Common enemies pull factions
  together; a friend of your enemy is your enemy; each new queen re-rolls the temper.
- **The wild**: overgrowth and critters (foxes hunt alien spawnlings, wardens and mantises hunt
  critters, hens gobble grubs, webs eat rabbits, locusts strip the overgrowth).
- **The tides** (`tides.gd`) measure each faction's share of power every 20s and, every few
  minutes, knock down a faction that dominated too long (hubris), shake things hard when shares
  have barely moved (upheaval), or throw a smaller boon/bane (ripple). Farm banes stop below an
  18% share. **Cataclysms** (rolled every 1-2.5 days, aimed mostly at the strongest faction,
  more often when the balance is stale) can wipe a faction out completely: a hive-sickness or a
  homeworld recall (aliens), the long frost (brood), the scorching (all wild burned off, critters
  silent for 1-2 days), the dark harvest (every field, crop, building and hen; the farmer alone
  survives in his house). Every faction can come back; extinctions and returns are logged and
  counted in `Game.tides.extinct`. Internal feedbacks in the colony (crowding -> aggression/schism/civil war, borders
  too big to hold falling to ruin, matriarch successions re-rolling temperament, the call home)
  add their own swings.

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
- Settings (gear button, top bar): card cadence (1-60 min), window side; saved in `user://settings.json`.
- Debug keys (only in debug builds): `F1` push a card into the box, `F2` fill the box, `F3` random event,
  `F4` toggle 10x time speed, `F5` wipe current slot & back to menu, `F6` +10 weirdness,
  `F7` an alien arrival, `F8` force a turn of the tides, `F9` a brood arrival, `F10` a locust swarm,
  `F11` a random cataclysm.
- **Headless tests (the default dev loop):**
  `C:/Dev/Godot/Godot_v4.7.2-stable_win64.exe --headless --path . -s tests/sim_test.gd -- days=8 [seed=N] [verbose]`
  boots the real game on throwaway slot 9, exercises every alien arrival/card/boon/bane, runs N
  in-game days and a save/reload, prints a faction report every 12 in-game hours and exits
  non-zero on failure (~25s per 8 days). After adding a new `class_name` script, run
  `--headless --path . --import` once to refresh the global class cache.
- **Multiplayer test:** `bash tests/run_net_test.sh` runs two headless copies on localhost (~50s): join,
  play, host leaves, guest keeps a fork, roles swap, rejoin. `bash tests/run_click_test.sh` (~25s) does the
  same flow through the real UI with synthetic clicks and keys (profiles 4 and 5). Windowed screenshots:
  `-s tests/ui_shots.gd -- out=<folder>`, or the click test without `--headless` plus `out=<folder>`.
- **Two players on one PC:** run a second standalone copy with `-- profile=2` (own settings and save
  slots: `user://settings2.json`, `slot2_N.json`). Host in one (gear > HOST THIS FARM), join
  `127.0.0.1:24680` in the other. Port: 24680 UDP (`"port"` in the settings file changes it); Windows asks
  to allow the firewall the first time. Details: `MULTIPLAYER.md`.
- MCP testing tip: `game_manage input_mouse` positions are in *window* pixels (2x the 192x432
  canvas in the editor's embedded view).
- Export: see "Exporting" below.

## Architecture (all code-driven, no external art)
| File | Role |
|---|---|
| `scripts/art.gd` (autoload **Art**) | Palette, ASCII sprites → textures, procedural painters (house, coop, trees, ground), 3x5 pixel font (`draw_text`, `text_width`, `wrap`). |
| `scripts/art_farm.gd` | ASCII sprites for overgrowth (tall grass, bush, bramble, boulder, log), compost, dark totem + altar, townsfolk icons. |
| `scripts/art_strange.gd` | Extra ASCII sprites: visitors (`v_*`), relic structures, card art, strange crops, 7x7 relic icons (`r_*`). |
| `scripts/game.gd` (autoload **Game**) | Global state: coins, level, clock/day, weather, hand of cards + drip timer, weirdness, relics, unlocked crops, favoured crop, pending (delayed) effects, buffs, farmer stats, inventory, log; data tables CROPS, STRUCTS, RELICS; slot paths + settings file. |
| `scripts/deck.gd` (class **Deck**) | **The card content** (70 cards, pure data). Its header documents every requirement and effect keyword. Add new cards here. |
| `scripts/commands.gd` (class **Commands**) | Every player action as a command (`submit` / `execute(pid, cmd)`): play a card, move a card, card cadence, speed, debug keys. Validates everything (multiplayer, see `MULTIPLAYER.md`). |
| `scripts/net.gd` (autoload **Net**) | Two-player networking over ENet: host/join, handshake, guest commands -> host, state snapshots + actor deltas + one-shot effects -> guest (puppet mode). See `MULTIPLAYER.md`. |
| `scripts/text_entry.gd` (class **TextEntry**) | One-line text field for the pixel-font UI (join address, player name). |
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
| `scripts/colony.gd` (class **Colony**) | The alien faction: arrivals, castes on maturity, food/matter economy, eggs, building plans + sites, territory claim and the creep (`World.alien_land`), relations/eras/outreach (envoys, raids, abductions, cards pushed into the box), farmer mutations, crowding/schism/civil war/the call, `boon()`/`bane()`. State in `Game.colony`. |
| `scripts/alien.gd` (class **Alien** extends Animal) | One alien: caste behaviour (egg, spawn, worker, scout, warden, envoy, elder/matriarch, ship, stranger, lurker, mutant), ageing, hovering straight-line movement, drawing (saucer + beam). Saved with World.animals. |
| `scripts/tides.gd` (class **Tides**) | Faction power (farm / aliens / wild), share history, hubris / upheaval / ripple turns of fate. State in `Game.tides`. |
| `scripts/art_alien.gd` | ASCII sprites for every alien caste (2 frames each), matriarch, stranger, lurker, mutant hen, eggs, village buildings, glow moss, husk, ruin, icons. |
| `scripts/swarm.gd` (class **Swarm**) | The Brood: radiation + arrivals, castes on emergence, food (fungus gardens, nectar, grazing, raids, swarms), eggs, mounds + build sites, tunnels, sinkholes, bare ground, webs, war fronts with the aliens, two-way relations, outreach, `boon()`/`bane()`. State in `Game.brood`. |
| `scripts/insect.gd` (class **Insect** extends Animal) | One insect: caste behaviour (egg, grub, pupa, worker, soldier, locust, spinner, glowfly, queen, migrant), swarm/flight routes, glow variants, drawing. |
| `scripts/art_insect.gd` | ASCII sprites for every insect caste (2 frames + glowing variants), queen, eggs, grubs, cocoon, mounds x3, web, wax wall, hole, husk, cordyceps, icons, treasures. |
| `tests/sim_test.gd` + `tests/sim_runner.gd` | Headless simulation test (see How to run). |
| `scripts/hud.gd` | In-game UI: top bar (coins/day/clock/weather, drag, menu/dock/min/close), status strip (HP/energy/mood/weirdness eye/buffs/activity/log), card tray (rarity borders, playable pip, OPEN ALL, relic shelf with tooltips), **choice-card modal**, speech bubbles & floating texts. |

Logical resolution 192x432 (viewport stretch, integer scale, nearest filter). Layout:
`0-16` top bar · `16-368` farm (12x22 tiles of 16px; card modal / settings / farmer panel overlay it) ·
`368-394` status · `394-432` card strip (stash left, box right).

Key systems added in v0.3:
- **World** (`world.gd`): ground types grass/tilled/path/water; `new_farm()` biome generation with two
  noise layers; `CLEARABLE` overgrowth table (work time, tool, wood/stone drops, thorns); `fields`
  planned from `SHAPES` (heart, smiley, checker, ring...) with sloppy nudges and a crop plan
  (one crop / mixed / whim); `next_path_cell()` (0-1 BFS door -> bin/fields/well...), `next_fence_cell()`
  (field perimeter with a gate), `pick_build_cell()`, `clear_overgrowth()`, `overgrow()`. Old 16-row
  saves are extended with wild rows.
- **Game**: `box`/`stash` slots, `add_card` push/trash, `move_card`, `card_interval()` from settings,
  `perks`, `friends`, `totems`, `played` (card -> choice, for chains), `quirk`, `farm_name`,
  building materials (wood/stone are kept, not sold; `can_afford`/`pay_for`).
- **Cards**: `choose(where, slot, which)`, `once` cards, new needs (totems, played/chose, perks,
  friends, cleared/overgrown %, fields, paths, pond, day...), farm-shaping effects (field, path,
  fence, build, trees, pond, clear, overgrow, perk, friend, totem). Friends visit each morning.

## Exporting
- `export_presets.cfg` has a **Windows Desktop** preset: x86_64, PCK embedded (single .exe), output
  `build/IdleFarm.exe`, release (debug keys off).
- Needs the Godot 4.7.2 export templates (Editor -> Manage Export Templates -> Download and Install).
- CLI: `Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Windows Desktop" build/IdleFarm.exe`
- Run `.\build-game.ps1` to create `build/`, import resources and export; optional `-GodotPath`
  selects the console executable. Direct CLI exports need `build/` created beforehand.
- Tests, documentation, editor addons and build output are excluded from the package.
- [x] Windows x64 release exported as one executable; standalone headless and windowed launch verified.
- [x] Root PowerShell build script with resource import, configurable Godot path and export error checks.

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

### v0.3: overgrown farms, card box & stash, impactful cards
- [x] AGENTS.md: this is a Godot game; use the Godot AI MCP server
- [x] Bigger farm view (12x22) and a slimmer card strip
- [x] Random farm layouts: biome, house position, ponds, grandpa's leftovers, heavy overgrowth
- [x] Clearing tasks with materials (wood/stone), thorns; never sealed into the yard
- [x] Field planning in random/silly shapes with sloppy tiles and a crop plan per field
- [x] Paths (paid in stone) and field fences with a gate (paid in wood), connected fence drawing
- [x] Farmer quirks + farmer panel (click him): quirk, cleared %, materials, abilities, friends, relics, totems
- [x] Card box (3, push + trash with animation) and stash (3), click to open, drag to move, STASH IT / TO BOX
- [x] Timed arrivals (default 10 min) + Settings panel (cadence, window side); offline arrivals
- [x] Card prerequisites: `needs`, `once`, played/chose chains; dark totem chain (6 sources) + Dark Altar
- [x] Deck rewritten for impact (103 cards): perks, townsfolk friends, fields, paths, fences, buildings
- [x] Verified via MCP: every card choice applied with no runtime errors and no missing art; totem gating;
  box push/trash/stash/play; modal + stash button + settings click-tested; settings persist; save/reload
- [ ] Balance pass for 10-minute cadence (coin rewards, how fast the farmer clears a farm)
- [ ] Dedicated sprites for the townsfolk (they reuse the villager sprite with a tint)
- [ ] Drag-and-drop not click-tested with real mouse drags yet (logic tested via game_eval)

### v0.4: the alien faction + the tides
- [x] Headless-first dev model recorded in AGENTS.md / CLAUDE.md; `tests/sim_test.gd` harness
- [x] Alien sprites: 9 castes/forms x 2 frames, matriarch, eggs (+hatching), 6 buildings, moss, husk, ruin, icons
- [x] Arrivals: falling egg, saucer drop, strange visitor (founds a village, reveals himself), night lurker -> mutant hen
- [x] Life cycle: egg -> spawnling -> caste chosen by colony need -> elder -> matriarch -> death (husk); hunger deaths
- [x] Village building: worker jobs (build sites, moss harvest, clearing), pods/hatchery/moss/spire/dish/pylons
- [x] Territory: claim radii, creep spreads/recedes, absorbs overgrowth, un-tills fields, mutates crops, never touches the farmhouse core
- [x] Relations & outreach: envoys (gift/trade/demand/chat), raids, warden zaps, abductions (even from bed), farmer visits/sabotage, envoy + ultimatum cards
- [x] Farmer mutations (antenna, green skin, third eye, glow, tentacle arm, hive whispers) with drawn overlays and effects; Doc Hollis can cure
- [x] Interactions with existing systems: lightning loves the spire, fire burns pods, boars smash buildings, foxes hunt spawnlings, wardens hunt critters
- [x] Tides: hubris / upheaval / ripple; colony crowding, schisms, civil wars, border decay, matriarch succession, the call home
- [x] 13 alien cards (arrivals, diplomacy, borders, spores, bazaar, plague, tractor beam, join the hive, rash)
- [x] HUD: alien + mutation status icons; farmer panel shows the village, relations, food/matter, mutations, tide shares
- [x] Verified headless: every arrival/card/boon/bane, 4 seeds x 24 days (shares swing, up to 4 villages rise and fall per run), save/reload
- [ ] UI pass via MCP: click-through of the farmer panel with a live colony; card modals for the alien cards
- [ ] Balance: established colonies hover around 40-55% share between swings; farmer mutations are rare without cards
- [ ] Rival alien colonies (a schism could found a second village with its own temper)

### v0.5: the Brood (mutant insects)
- [x] Sprites: 7 castes x 2 frames + glowing variants, eggs, grubs, cocoon, mounds (3 sizes), web, wax wall, hole, husk, cordyceps, icons, 3 treasures
- [x] Origin from the farm's own strangeness (wasps / beehive / tree cocoon) + locust-cloud fallback; a passing cloud may leave a queen
- [x] Life cycle with fast generations; castes by need (hunger breeds locusts, war breeds mantises, creep breeds glowing insects); queens, succession, wedding flights
- [x] Map changes: mounds, tunnels, undermined fields, webs, wax walls, locust strips (bare ground), sinkholes -> permanent ponds (capped at 48 water tiles)
- [x] Relations with the farm and the aliens; war with a moving front line; alliances, common enemies; nesting in alien ruins; cordyceps spores reach the aliens
- [x] Farm side: pollination, honey gifts + Queen's Gift card, raids, grubs vs roots, hens eat grubs, stings, chitin / compound-eye mutations, honey + smoke-out farmer tasks
- [x] Tides: four factions; brood boons (swarm, wedding flight, bloom, molt) and banes (frost, cordyceps, flood, queen dies)
- [x] 11 insect cards; HUD icon + farmer panel section; F9/F10
- [x] Verified headless (all arrivals, castes, swarm, sinkholes, webs, war, cards, boons/banes, save/reload) over several 16-day seeds
- [ ] UI pass via MCP with a live brood (only the staged snapshot so far)
- [x] Brood caps + crowding: max 40 insects / 6 mounds / 4 queens, queen duels, great migrations (half leave, a mound is abandoned)
- [ ] Balance: aliens now tend to stay small (max 9-20) and die out often against the brood; the water cap (48) is reached in long runs

### v0.6: cataclysms and extinctions
- [x] Cataclysm tier in the tides: each faction can be wiped out entirely (aliens, brood, wild, farm down to the farmer + house)
- [x] Extinction / return tracking with log lines; farmer panel shows who has been wiped out and how often
- [x] Comebacks: re-arrivals, wild floods back after the silence, the farmer breaks new ground
- [x] Verified headless: forced cataclysms wipe each faction and both the farm and the wild return; long natural runs (see changelog)

### v0.7: two-player "join world" (in progress)
- [ ] Multiplayer: host-authoritative ENet + UPnP, join by IP, per-player card boxes, both keep a
  copy when someone leaves. **Full plan, decisions and task checklist: `MULTIPLAYER.md`.**
  - [x] Phase 0: player ids + profiles, per-player hands, command layer, actor ids, world ids, puppet mode
  - [x] Phase 1: ENet net core (`net.gd`): handshake, commands, snapshots, actor stream, effects
  - [x] Phase 2: when the host leaves the guest keeps a fork; rejoining restores hands; goodbye messages
  - [x] Phase 3: UPnP port forwarding (thread), addresses to share, help text, join errors (real router untested)
  - [x] Phase 4: UI: JOIN A FRIEND page, PLAY TOGETHER in the gear menu, 2P indicator, toasts, guest limits
  - [x] Phase 5: two-copy tests (`run_net_test.sh`, `run_click_test.sh` click-through), docs
  - [ ] Phase 5.3: a real internet test between two networks (needs a person on each end)

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
- [ ] More settings (volume, scale) — card interval + dock side done in v0.3
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
- Multiplayer: on a guest `Game.puppet` is true and nothing may change the world; gate new `_process`
  logic with `Game.simulating()` and send player actions through `commands.submit()`. A new actor
  field the guest must see goes in that actor's `net_fields()`. Never run the net test with `upnp=1`
  (a real router port mapping) without the user's OK.

## Changelog
- 2026-10-24 - Added `build-game.ps1` at the project root to import resources and export the Windows
  release from any working directory, with an optional `-GodotPath` and failure checks. README
  build instructions now use the script. Verified a complete build under Windows PowerShell 5.1
  from the parent directory.
- 2026-10-24 - Built `build/IdleFarm.exe` (Windows x64 release, embedded PCK). Installed the official
  4.7.2 Windows templates after verifying SHA512, removed references to the absent Godot AI addon,
  excluded development files from exports, and documented the PowerShell build commands. Verified
  the exported executable launches independently and renders the welcome screen; source smoke check
  passed farm startup, five simulated minutes, and save/reload using isolated test saves.
- 2026-10-24 - v0.7 phase 5: `tests/run_click_test.sh` plays the multiplayer flow through the real UI (synthetic
  clicks / drags / keys on two copies). Fixed one frame of simulation on a guest's streamed actors when leaving
  a visit (farmer error). SHARED / SPLIT OFF tag moved off the house picture. `"port"` setting for hosting.
- 2026-10-24 - v0.7 phase 4: multiplayer UI. Welcome > JOIN A FRIEND (name, address, slot for the copy with an
  overwrite confirm), gear menu PLAY TOGETHER (name, host / copy address / stop, or leave a visit), "2P" in the
  top bar, status toasts, guest-only limits, SHARED / SPLIT OFF slot tags. `tests/ui_shots.gd` for screenshots.
- 2026-10-24 - v0.7 phase 3: hosting asks the router to forward the port (UPnP in a thread, unmapped on
  stop), `Net.share_address/lan_addresses/help_lines/parse_address`, an 8s join timeout and clearer error
  texts. Tests never touch the real router unless `upnp=1`.
- 2026-10-24 - v0.7 phase 2: leaving works both ways. When the host goes the guest keeps the farm as its
  own fork (`main.host_left`) and can host it; a returning player gets their hand back; `Net.stop` says
  goodbye (`_bye`, `Net.last_exit`); window close says goodbye too. Net test is now a full role-swap scenario.
- 2026-10-24 - v0.7 phase 1: `scripts/net.gd` (autoload Net): ENet host/join with ZSTD, hello/reject
  handshake, guest commands over RPC, 1/s state snapshots (when changed), 5/s actor deltas with
  interpolation, replayed one-shot effects, guest clock smoothing; `main.start_guest`; two-copy test
  `tests/run_net_test.sh` (6 KB/s on the wire with 21 actors).
- 2026-10-24 - v0.7 phase 0 (multiplayer prep, single player unchanged): `Game.hands` per player
  (save v4 migrates old saves), `scripts/commands.gd` command layer (HUD + debug keys go through it),
  stable actor `uid`s, `world_id`/`fork()`, `Game.puppet` gate on every sim loop, `-- profile=N` for two
  copies on one PC. New sim_test section. Note: sim_test was already flaky on a few faction checks.
- 2026-10-24 - planned v0.7 multiplayer (two players share one world, host-authoritative over
  ENet + UPnP, join by IP; no merging, both keep a copy on leave). Plan + checklist in `MULTIPLAYER.md`.
- 2026-10-21 - v0.6: cataclysms. The tides can now wipe any faction out completely (hive-sickness /
  recall, the long frost, the scorching, the dark harvest), aimed mostly at the dominant faction;
  extinctions and returns are tracked and logged, the wild falls silent and then floods back, and
  the farmer always survives to start again. F11 forces one. New test section + natural-run check
  that at least two factions get wiped out in 12+ days.
- 2026-10-21 - v0.5: the Brood, a mutant insect faction (`swarm.gd`, `insect.gd`, `art_insect.gd`)
  that reshapes the map (mounds, tunnels, webs, wax walls, locust-stripped bare ground, sinkhole
  ponds) and has its own relations with the farm and the aliens (pollination, raids, war fronts,
  alliances). Tides now balance four factions. Hooks in world, colony, alien (wardens fight
  insects), farmer (honey / smoke-out, chitin + compound-eye mutations), animal, director,
  entity layer, cards (brood requirements/effects), deck (11 cards), HUD, main (F9/F10).
  `tests/sim_test.gd` now exits non-zero instead of hanging if the runner fails to compile.
  Verified: 3 seeds x 10 days, 0 script errors; brood share swings 0-60%, 1-3 wars and up to 11
  sinkholes per run, farm 24-85%. An uncapped first version took over (213 insects, 91%) and was
  reined in with caps, queen duels and great migrations.
- 2026-10-21 - v0.4: the alien faction and the tides. New `colony.gd`, `alien.gd`, `tides.gd`,
  `art_alien.gd`; hooks in world (creep, solid buildings, save), farmer (abduction, mutations,
  visits/sabotage), director (spire lightning, burning pods, glow vs foxes), animals (foxes hunt
  spawnlings, boars smash pods), cards (alien requirements/effects), deck (13 cards), HUD, main
  (F7/F8). Fixed an old bug: a fox that was scared off still killed the chicken it had only
  targeted. Default dev loop is now headless (`tests/sim_test.gd`); 0 script errors over 4 seeds
  x 24 days.
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
- 2026-10-18 - v0.3: AGENTS.md. Farms are now randomised and heavily overgrown (biomes, ponds,
  house position, leftovers); the farmer clears it for wood/stone, plans silly-shaped fields, lays
  paths and fences them. Cards: a 3-slot box (new card every 10 min, oldest falls out) + 3-slot
  stash, settings panel for the cadence, prerequisites (dark totems -> Dark Altar), and a rewritten
  103-card deck where every choice visibly changes the farm (fields, buildings, perks, townsfolk).
  UI rebalanced towards the farm (352px farm view). Verified via MCP (see v0.3 checklist).
