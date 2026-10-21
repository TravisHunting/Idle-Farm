# Idle Farm — notes for AI agents

**This project is a Godot game** (Godot 4.7, GDScript, GL Compatibility renderer). There is no
web/Node/Python app here: everything — the scene tree, the pixel art and the font — is built in
GDScript under `scripts/`. The only scene is `scenes/main.tscn`.

## Default development model: edit files + headless Godot
**This is the default agentic workflow for this project.** Edit the `.gd` files directly and
validate with Godot in **headless** mode from the shell. Full UI testing through the Godot AI MCP
server is reserved for occasional, deliberate passes (it costs a lot of tokens).

- Godot binary: `C:\Dev\Godot\Godot_v4.7.2-stable_win64.exe` (a `_console.exe` sits next to it).
- Parse/compile check of the whole project:
  `"C:/Dev/Godot/Godot_v4.7.2-stable_win64.exe" --headless --path . --quit-after 5`
- Scripted simulation tests live in `tests/` (SceneTree scripts, run with `-s`), e.g.
  `"C:/Dev/Godot/Godot_v4.7.2-stable_win64.exe" --headless --path . -s tests/sim_test.gd`
  They boot the real game tree on a throwaway save slot, fast-forward days of simulation and
  print a report; a non-zero exit code / `SCRIPT ERROR` / `FAIL` lines mean something broke.
- In `-s` mode the entry script compiles before the autoloads exist, so each `tests/*.gd` entry
  point only loads a `*_runner.gd` Node at runtime; put test logic in the runner.
- After adding a new `class_name` script, run `--headless --path . --import` once (refreshes the
  global class cache, otherwise you get "Could not find type").
- Cheap visual check without the MCP (opens a small window for a few seconds):
  `"C:/Dev/Godot/Godot_v4.7.2-stable_win64.exe" --path . -s tests/snapshot.gd -- out=<folder>`
  saves staged 3x screenshots (`snap_day.png`, `snap_night.png`) of an alien village.

## Occasional UI passes: the "Godot AI" MCP server
When a visual / click-through check is really needed, use the **Godot AI** MCP server
(tools named `mcp__godot-ai__*`), which talks to the open Godot editor:

- `project_run` — start the game (main scene), and stop it again when done.
- `logs_read` with `source=game` — read the running game's output and script errors.
- `editor_screenshot` with `source=game` — see what the game looks like.
- `editor_manage` with `op=game_eval` — run GDScript inside the running game for scripted tests
  (e.g. `Game.add_weird(20)`, push a card into the box, fast-forward time).
- `game_manage input_mouse` — click in the game; positions are in *window* pixels (2x the
  192x432 canvas in the editor's embedded view).

If those tools are not loaded yet, search for them (ToolSearch "godot") — the server can take a
moment to connect. If the editor isn't open, ask the user to open the project in Godot.

## Where things are
- `TODO.md` — design doc, architecture map, progress checklist and changelog. **Read it first**,
  and update its checkboxes and Changelog when you finish something.
- `CLAUDE.md` — short agent notes (debug keys, verification workflow).
- Card content: `scripts/deck.gd` (documented mini-language). Card logic: `scripts/cards.gd`.
- Farm generation, fields and paths: `scripts/world.gd`. Farmer AI: `scripts/farmer.gd`.
- UI (box, stash, card modal, settings): `scripts/hud.gd`.
- Alien faction: `scripts/colony.gd` + `scripts/alien.gd`; mutant insects: `scripts/swarm.gd` +
  `scripts/insect.gd`; faction balance: `scripts/tides.gd`.

## Debug keys (debug builds only)
F1 push a card into the box, F2 fill the box, F3 random event, F4 10x speed,
F5 wipe the current slot, F6 +10 weirdness, F7 alien arrival, F8 turn the tides,
F9 brood (insect) arrival, F10 locust swarm, F11 a random cataclysm.
