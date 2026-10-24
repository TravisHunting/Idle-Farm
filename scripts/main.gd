extends Node
## Entry point. Shows the welcome screen (how to play + save-slot picker), then builds the
## game tree in code for the chosen slot. Docks the window to the right (or left) side of the
## screen, vertically centred with a little padding. Handles save/load per slot (+ offline
## progress), autosave and debug keys.

const BASE := Vector2i(192, 432)
const FARM_RECT := Rect2(0, 16, 192, 352)
const EDGE_PADDING := 24          # screen pixels between the window and the screen edge
const AUTOSAVE_EVERY := 20.0

var world: World
var director: Node
var cards: Node
var colony: Colony
var swarm: Swarm
var tides: Tides
var commands: Commands
var hud: Control
var farm_view: Control
var weather_fx: Node2D
var tint: CanvasModulate
var welcome: Control
var embedded := false
var _game_root: Node
var _autosave_t := AUTOSAVE_EVERY
var _shake := 0.0


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	get_viewport().transparent_bg = true
	embedded = Engine.is_embedded_in_editor()
	Net.main = self
	_setup_window()
	show_welcome()


# ---------------------------------------------------------------- flow
func show_welcome(page: int = 0) -> void:
	Game.running = false
	var layer := CanvasLayer.new()
	layer.layer = 5
	layer.name = "WelcomeLayer"
	add_child(layer)
	welcome = preload("res://scripts/welcome.gd").new()
	welcome.main = self
	welcome.page = page
	layer.add_child(welcome)


## Join a host's world as a guest (Net._welcome): it is kept in slot n, and runs in puppet mode.
func start_guest(n: int, d: Dictionary) -> void:
	if _game_root:
		save_game()   # whatever we were playing is kept
		Game.running = false
		_game_root.queue_free()
		_game_root = null
		world = null
	Game.reset()
	Game.slot = n
	Game.puppet = true
	_build()
	Game.from_dict(d.get("game", {}))
	Game.time_scale = float(d.get("speed", 1.0))
	world.from_dict(d.get("world", {}))
	Game.running = true
	if welcome:
		welcome.get_parent().queue_free()
		welcome = null
	save_game()


## The host went away: this guest's copy of the shared world becomes its own solo world (a fork),
## rebuilt as if loaded from its save, and carries on (MULTIPLAYER.md: both keep a copy).
func host_left() -> void:
	if world == null or not Game.puppet:
		return
	Game.puppet = false
	Game.fork()
	Game.present = {Game.my_pid: true}
	Game.time_scale = float(Game.settings.get("speed", 1))
	world.load_actors(world.to_dict())
	Game.add_log("Your friend went home. The farm carries on with you.")
	world.farmer.say("Just us now, then.", 4.0)
	save_game()


func start_slot(n: int) -> void:
	Game.reset()
	Game.slot = n
	_build()
	if not load_game():
		world.new_farm()
		var intro := {"woodland": "The trees have taken over.", "rocky": "Rocks. So many rocks.",
			"brambles": "Brambles everywhere!", "meadow": "The grass is waist-high.", "marsh": "Squelchy, muddy, froggy."}
		Game.add_log("Day 1 at %s. %s" % [Game.farm_name, intro.get(world.biome, "")])
		world.farmer.say(["Grandpa really let this place go...", "My very own (overgrown) farm!",
			"Right. Where do I even start?"].pick_random(), 5.0)
		# two cards to start with, so there's something to decide straight away
		cards.draw_card()
		cards.draw_card()
		save_game()
	Game.running = true
	if welcome:
		welcome.get_parent().queue_free()
		welcome = null


func back_to_menu() -> void:
	save_game()
	Net.stop()
	Game.running = false
	Game.puppet = false
	if _game_root:
		_game_root.queue_free()
		_game_root = null
	world = null
	show_welcome(1)


func _build() -> void:
	_game_root = Node.new()
	_game_root.name = "GameRoot"
	add_child(_game_root)

	tint = CanvasModulate.new()
	_game_root.add_child(tint)

	farm_view = Control.new()
	farm_view.name = "FarmView"
	farm_view.position = FARM_RECT.position
	farm_view.size = FARM_RECT.size
	farm_view.clip_contents = true
	farm_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_root.add_child(farm_view)

	world = World.new()
	world.name = "World"
	farm_view.add_child(world)
	# the alien colony exists before the world loads, so saved aliens can find it
	colony = Colony.new()
	colony.name = "Colony"
	colony.world = world
	world.colony = colony
	swarm = Swarm.new()
	swarm.name = "Swarm"
	swarm.world = world
	world.swarm = swarm
	var ents := preload("res://scripts/entity_layer.gd").new()
	ents.name = "Entities"
	ents.world = world
	world.add_child(ents)
	world.entity_layer = ents
	var fx := preload("res://scripts/fx_layer.gd").new()
	fx.name = "FX"
	fx.world = world
	world.add_child(fx)
	world.fx_layer = fx

	weather_fx = preload("res://scripts/weather_fx.gd").new()
	weather_fx.name = "Weather"
	farm_view.add_child(weather_fx)

	director = preload("res://scripts/director.gd").new()
	director.name = "Director"
	director.world = world
	director.weather_fx = weather_fx
	director.shake.connect(shake)
	_game_root.add_child(director)
	world.director = director

	cards = preload("res://scripts/cards.gd").new()
	cards.name = "Cards"
	cards.world = world
	cards.director = director
	director.cards = cards
	_game_root.add_child(cards)
	director.colony = colony
	colony.director = director
	colony.cards = cards
	_game_root.add_child(colony)
	swarm.director = director
	swarm.cards = cards
	swarm.colony = colony
	_game_root.add_child(swarm)
	tides = Tides.new()
	tides.name = "Tides"
	tides.world = world
	tides.director = director
	tides.cards = cards
	tides.colony = colony
	tides.swarm = swarm
	_game_root.add_child(tides)
	commands = Commands.new()
	commands.name = "Commands"
	commands.cards = cards
	commands.director = director
	commands.colony = colony
	commands.swarm = swarm
	commands.tides = tides
	_game_root.add_child(commands)

	var layer := CanvasLayer.new()
	layer.layer = 1
	_game_root.add_child(layer)
	hud = preload("res://scripts/hud.gd").new()
	hud.name = "HUD"
	hud.world = world
	hud.director = director
	hud.cards = cards
	hud.main = self
	hud.commands = commands
	layer.add_child(hud)


func _process(delta: float) -> void:
	if world == null or not Game.running:
		return
	# day/night + weather tint (does not affect the HUD's CanvasLayer)
	var night := Color(0.38, 0.42, 0.7)
	if Game.has_relic("lantern"):
		night = Color(0.5, 0.5, 0.72)
	var c := Color.WHITE.lerp(night, Game.darkness())
	match Game.weather:
		"storm": c *= Color(0.72, 0.74, 0.85)
		"rain": c *= Color(0.86, 0.88, 0.95)
		"cloudy": c *= Color(0.93, 0.93, 0.96)
		"heat": c *= Color(1.0, 0.96, 0.88)
	# the farm takes on a faint violet cast as it gets weirder
	c = c.lerp(c * Color(0.9, 0.82, 1.0), clampf(Game.weird / 100.0, 0.0, 1.0))
	c.a = 1.0
	tint.color = tint.color.lerp(c, minf(1.0, delta * 2.0))
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 8.0)
		farm_view.position = FARM_RECT.position + Vector2(randi_range(-1, 1), randi_range(-1, 1)) * ceilf(_shake)
	else:
		farm_view.position = FARM_RECT.position
	_autosave_t -= delta
	if _autosave_t <= 0.0:
		_autosave_t = AUTOSAVE_EVERY
		save_game()


# ---------------------------------------------------------------- window
func _setup_window() -> void:
	if embedded:
		return
	var win := get_window()
	win.borderless = true
	win.always_on_top = true
	win.transparent = true
	_apply_dock()


func _apply_dock() -> void:
	if embedded:
		return
	var win := get_window()
	var screen := DisplayServer.window_get_current_screen()
	var r := DisplayServer.screen_get_usable_rect(screen)
	var scale := clampi(int((r.size.y - EDGE_PADDING * 2) / float(BASE.y)), 1, 4)
	var sz := BASE * scale
	win.size = sz
	var x := r.position.x + r.size.x - sz.x - EDGE_PADDING
	if Game.settings.get("dock", "right") == "left":
		x = r.position.x + EDGE_PADDING
	var y := r.position.y + (r.size.y - sz.y) / 2
	win.position = Vector2i(x, y)
	print("Docked %s: window %s at %s (scale %dx, usable screen %s)" % [Game.settings.get("dock", "right"), sz, win.position, scale, r])


func toggle_dock() -> void:
	Game.settings["dock"] = "left" if Game.settings.get("dock", "right") == "right" else "right"
	Game.save_settings()
	_apply_dock()


func minimize() -> void:
	if embedded:
		return
	get_window().mode = Window.MODE_MINIMIZED


func save_and_quit() -> void:
	save_game()
	Net.stop()
	get_tree().quit()


## Screen shake (also replayed on a guest's screen).
func shake(a: float) -> void:
	_shake = maxf(_shake, a)
	Net.fx("shake", [a])


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
		Net.stop()


# ---------------------------------------------------------------- save/load
func save_game() -> void:
	if world == null or world.farmer == null or not Game.running and _game_root == null:
		return
	var meta := {"day": Game.day, "level": Game.level(), "wealth": Game.wealth(), "weird": int(Game.weird),
		"relics": Game.relics.size(), "play_seconds": Game.play_seconds, "farm": Game.farm_name,
		"shared": Game.owner_pid != Game.my_pid, "forked": Game.forked_from != ""}
	var d := {"version": 4, "time": Time.get_unix_time_from_system(), "meta": meta,
		"game": Game.to_dict(), "world": world.to_dict()}
	var fa := FileAccess.open(Game.slot_path(Game.slot), FileAccess.WRITE)
	if fa:
		fa.store_string(JSON.stringify(d))
		fa.close()


func load_game() -> bool:
	var path := Game.slot_path(Game.slot)
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save slot %d unreadable, starting fresh." % Game.slot)
		return false
	var d: Dictionary = parsed
	Game.from_dict(d.get("game", {}))
	world.from_dict(d.get("world", {}))
	if Game.owner_pid != Game.my_pid:
		Game.fork()   # someone else's world, kept from a shared game: it's ours now
	_offline_progress(Time.get_unix_time_from_system() - float(d.get("time", 0.0)))
	return true


## Summary of a slot for the welcome screen ({} if empty).
func slot_meta(n: int) -> Dictionary:
	var path := Game.slot_path(n)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"broken": true}
	var m: Dictionary = parsed.get("meta", {})
	m["time"] = float(parsed.get("time", 0.0))
	return m


func delete_slot(n: int) -> void:
	var path := Game.slot_path(n)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _offline_progress(seconds: float) -> void:
	var el := clampf(seconds, 0.0, Game.OFFLINE_CAP)
	if el < 60.0:
		return
	# cards kept arriving while we were away (the box only ever holds the newest 3)
	var total := Game.card_timer + el
	var n := mini(int(total / Game.card_interval()), Game.BOX_SIZE + 1)
	Game.card_timer = fmod(total, Game.card_interval())
	for i in n:
		cards.draw_card()
	for c in world.crops:
		var cr: Dictionary = world.crops[c]
		if not cr.get("dead", false):
			cr["growth"] = minf(1.0, cr["growth"] + el / float(Game.CROPS[cr["type"]]["grow"]) * 0.5)
	var cells := world.free_grass_cells()
	cells.shuffle()
	for i in mini(int(el / 300.0), mini(6, cells.size())):
		world.place_obj(cells[i], "weed")
	var t := Game.time_of_day + el / Game.DAY_LENGTH
	Game.day += int(t)
	Game.time_of_day = fmod(t, 1.0)
	var mins := int(el / 60.0)
	Game.add_log("Welcome back! %d min away, +%d cards." % [mins, n])
	world.farmer.say("Oh, you're back!", 4.0)


# ---------------------------------------------------------------- debug
func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not (event is InputEventKey) or not event.pressed or world == null:
		return
	if Game.puppet and event.keycode != KEY_F5:
		return   # a guest's debug keys would only be refused by the host
	const DEBUG_KEYS := {KEY_F1: "draw", KEY_F2: "fill", KEY_F3: "event", KEY_F6: "weird", KEY_F7: "alien",
		KEY_F8: "tides", KEY_F9: "brood", KEY_F10: "locusts", KEY_F11: "cataclysm"}
	if DEBUG_KEYS.has(event.keycode):
		commands.submit({"type": "debug", "key": DEBUG_KEYS[event.keycode]})
		return
	match event.keycode:
		KEY_F4:
			commands.submit({"type": "speed", "n": 10 if Game.time_scale == 1.0 else 1})
		KEY_F5:
			Net.stop()
			Game.puppet = false
			var s := Game.slot
			Game.running = false
			_game_root.queue_free()
			_game_root = null
			world = null
			delete_slot(s)
			show_welcome(1)
