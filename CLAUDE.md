# Idle Farm — agent notes
Read `TODO.md` first: it is the design doc, architecture map, progress checklist and changelog.
Update its checkboxes and Changelog whenever you finish something.

- Godot 4.7, GDScript, GL Compatibility. Everything (scene tree, art, font) is built in code.
- **Default workflow:** edit files, then validate with headless Godot
  (`C:\Dev\Godot\Godot_v4.7.2-stable_win64.exe --headless --path . -s tests/sim_test.gd`; see AGENTS.md).
  Full UI testing via the Godot MCP (`project_run`, `editor_screenshot`...) only occasionally — it is token-heavy.
- Debug keys in-game: F1 push a card into the box, F2 fill the box, F3 random event, F4 10x speed, F5 wipe slot, F6 +10 weirdness, F7 alien arrival, F8 turn the tides, F9 brood arrival, F10 locust swarm, F11 cataclysm.
- Aliens: `scripts/colony.gd` (faction) + `scripts/alien.gd` (individuals); mutant insects:
  `scripts/swarm.gd` + `scripts/insect.gd`; balance of power: `scripts/tides.gd`.
- Card content lives in `scripts/deck.gd` (documented mini-language); card logic in `scripts/cards.gd`.
- Also read `AGENTS.md` (this is a Godot game; headless-first dev model).
