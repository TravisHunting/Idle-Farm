# Idle Farm — notes for AI agents

**This project is a Godot game** (Godot 4.7, GDScript, GL Compatibility renderer). There is no
web/Node/Python app here: everything — the scene tree, the pixel art and the font — is built in
GDScript under `scripts/`. The only scene is `scenes/main.tscn`.

## Use the "Godot AI" MCP server
Do not try to run or test the game from a shell. Use the **Godot AI** MCP server
(tools named `mcp__godot-ai__*`), which talks to the open Godot editor:

- `project_run` — start the game (main scene), and stop it again when done.
- `logs_read` with `source=game` — read the running game's output and script errors.
- `editor_screenshot` with `source=game` — see what the game looks like.
- `editor_manage` with `op=game_eval` — run GDScript inside the running game for scripted tests
  (e.g. `Game.add_weird(20)`, push a card into the box, fast-forward time).
- `game_manage input_mouse` — click in the game; positions are in *window* pixels (2x the
  192x432 canvas in the editor's embedded view).
- `script_*`, `filesystem_manage`, `scene_*` — inspect/edit project files through the editor.

If those tools are not loaded yet, search for them (ToolSearch "godot") — the server can take a
moment to connect. If the editor isn't open, ask the user to open the project in Godot.

## Where things are
- `TODO.md` — design doc, architecture map, progress checklist and changelog. **Read it first**,
  and update its checkboxes and Changelog when you finish something.
- `CLAUDE.md` — short agent notes (debug keys, verification workflow).
- Card content: `scripts/deck.gd` (documented mini-language). Card logic: `scripts/cards.gd`.
- Farm generation, fields and paths: `scripts/world.gd`. Farmer AI: `scripts/farmer.gd`.
- UI (box, stash, card modal, settings): `scripts/hud.gd`.

## Debug keys (debug builds only)
F1 push a card into the box, F2 fill the box, F3 random event, F4 10x speed,
F5 wipe the current slot, F6 +10 weirdness.
