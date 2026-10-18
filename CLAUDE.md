# Idle Farm — agent notes
Read `TODO.md` first: it is the design doc, architecture map, progress checklist and changelog.
Update its checkboxes and Changelog whenever you finish something.

- Godot 4.7, GDScript, GL Compatibility. Everything (scene tree, art, font) is built in code.
- Verify changes by running through the Godot MCP (`project_run`, `logs_read source=game`,
  `editor_screenshot source=game`, `editor_manage op=game_eval` for scripted tests).
- Debug keys in-game: F1 push a card into the box, F2 fill the box, F3 random event, F4 10x speed, F5 wipe slot, F6 +10 weirdness.
- Card content lives in `scripts/deck.gd` (documented mini-language); card logic in `scripts/cards.gd`.
- Also read `AGENTS.md` (use the Godot AI MCP server; this is a Godot game).
