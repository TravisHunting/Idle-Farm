extends Node
## Entry point. Builds the scene tree in code, docks the window to the screen edge,
## handles save/load (+ offline progress), autosave and debug keys.

const BASE := Vector2i(192, 432)
const FARM_RECT := Rect2(0, 16, 192, 256)

var world: World
var director: Node
var hud: Control
var farm_view: Control
var weather_fx: Node2D
var tint: CanvasModulate
var embedded := false
var _autosave_t := 30.0
var _shake := 0.0


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	get_viewport().transparent_bg = true
	embedded = Engine.is_embedded_in_editor()
	_build()
	if not load_game():
		world.new_farm()
		Game.add_log("Day 1. A fresh start on an empty farm!")
		world.farmer.say("My very own farm!", 4.0)
	_setup_window()


func _build() -> void:
	tint = CanvasModulate.new()
	add_child(tint)

	farm_view = Control.new()
	farm_view.name = "FarmView"
	farm_view.position = FARM_RECT.position
	farm_view.size = FARM_RECT.size
	farm_view.clip_contents = true
	farm_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(farm_view)

	world = World.new()
	world.name = "World"
	farm_view.add_child(world)
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
	director.shake.connect(func(a: float) -> void: _shake = maxf(_shake, a))
	add_child(director)
	world.director = director

	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	hud = preload("res://scripts/hud.gd").new()
	hud.name = "HUD"
	hud.world = world
	hud.director = director
	hud.main = self
	layer.add_child(hud)


func _process(delta: float) -> void:
	# day/night + weather tint (does not affect the HUD's CanvasLayer)
	var night := Color(0.38, 0.42, 0.7)
	var c := Color.WHITE.lerp(night, Game.darkness())
	match Game.weather:
		"storm": c *= Color(0.72, 0.74, 0.85)
		"rain": c *= Color(0.86, 0.88, 0.95)
		"cloudy": c *= Color(0.93, 0.93, 0.96)
		"heat": c *= Color(1.0, 0.96, 0.88)
	c.a = 1.0
	tint.color = tint.color.lerp(c, minf(1.0, delta * 2.0))
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 8.0)
		farm_view.position = FARM_RECT.position + Vector2(randi_range(-1, 1), randi_range(-1, 1)) * ceilf(_shake)
	else:
		farm_view.position = FARM_RECT.position
	_autosave_t -= delta
	if _autosave_t <= 0.0:
		_autosave_t = 30.0
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
	var scale := clampi(int(r.size.y / float(BASE.y)), 1, 4)
	var sz := BASE * scale
	win.size = sz
	var x := r.position.x + r.size.x - sz.x
	if Game.settings.get("dock", "right") == "left":
		x = r.position.x
	win.position = Vector2i(x, r.position.y + r.size.y - sz.y)
	print("Docked %s: window %s at %s (scale %dx, usable screen %s)" % [Game.settings.get("dock", "right"), sz, win.position, scale, r])


func toggle_dock() -> void:
	Game.settings["dock"] = "left" if Game.settings.get("dock", "right") == "right" else "right"
	_apply_dock()


func minimize() -> void:
	if embedded:
		return
	get_window().mode = Window.MODE_MINIMIZED


func save_and_quit() -> void:
	save_game()
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


# ---------------------------------------------------------------- save/load
func save_game() -> void:
	if world == null or world.farmer == null:
		return
	var d := {"version": 1, "time": Time.get_unix_time_from_system(), "game": Game.to_dict(), "world": world.to_dict()}
	var fa := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	if fa:
		fa.store_string(JSON.stringify(d))
		fa.close()


func load_game() -> bool:
	if not FileAccess.file_exists(Game.SAVE_PATH):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(Game.SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save file unreadable, starting fresh.")
		return false
	var d: Dictionary = parsed
	Game.from_dict(d.get("game", {}))
	world.from_dict(d.get("world", {}))
	_offline_progress(Time.get_unix_time_from_system() - float(d.get("time", 0.0)))
	return true


func _offline_progress(seconds: float) -> void:
	var el := clampf(seconds, 0.0, Game.OFFLINE_CAP)
	if el < 60.0:
		return
	var avg := (Game.CARD_INTERVAL.x + Game.CARD_INTERVAL.y) * 0.5
	var n := 0
	for i in int(el / avg):
		if Game.add_card(Game.random_card()):
			n += 1
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
	Game.add_log("Welcome back! %d min away, +%d activities." % [mins, n])
	world.farmer.say("Oh, you're back!", 4.0)


# ---------------------------------------------------------------- debug
func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not (event is InputEventKey) or not event.pressed:
		return
	match event.keycode:
		KEY_F1:
			Game.add_card(Game.random_card())
		KEY_F2:
			for i in 10:
				Game.add_card(Game.random_card())
		KEY_F3:
			director.random_event()
		KEY_F4:
			Game.time_scale = 10.0 if Game.time_scale == 1.0 else 1.0
			Game.add_log("Debug time x%d" % int(Game.time_scale))
		KEY_F5:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_PATH))
			Game.reset()
			world = null
			get_tree().reload_current_scene()
