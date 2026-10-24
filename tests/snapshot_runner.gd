extends Node
## Stages an alien village on a throwaway slot and saves screenshots (see snapshot.gd).

const SLOT := 9
const STEP := 0.25

var main: Node
var out := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	if out == "":
		out = ProjectSettings.globalize_path("user://")
	_run.call_deferred()


func _run() -> void:
	_wipe()
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	main.start_slot(SLOT)
	Game.running = true
	var col: Colony = main.colony
	col.arrive("saucer")
	step(60.0)
	Game.colony["matter"] = 120.0
	Game.colony["food"] = 80.0
	step(400.0)
	# the brood: a beehive turns into a mound, gets fat, digs in, spins webs
	main.cards.apply([["build", "beehive", 1], ["plant", "turnip", 6]])
	main.swarm.arrive("hive")
	Game.brood["food"] = 60.0
	step(500.0)
	for i in 3:
		var b := Insect.new(main.world, ["spinner", "soldier", "locust"][i], main.swarm.home_pos(Vector2.ZERO) + Vector2(10, 8))
		b.hive = main.swarm.mounds()[0]
		main.world.add_animal(b)
	step(120.0)
	main.swarm.launch_swarm("farm")
	step(14.0)
	var land: Array = main.world.insect_land.keys()
	if land.size() > 0:
		main.swarm.sinkhole(land.pick_random(), 2)
	for m in ["antenna", "green", "compound_eyes", "chitin"]:
		col.mutate_farmer(m)
	Game.time_of_day = 0.45
	Game.weather = "sunny"
	var f: Farmer = main.world.farmer
	f.hidden = false
	f.state = "idle"
	f.pos = main.world.feet(main.world.DOOR) + Vector2(10, 18)
	step(2.0)
	await _snap("snap_day.png")
	# night: a saucer beaming over the village, a lurker in the grass
	Game.time_of_day = 0.97
	col.ship("drop", col.center_pos() + Vector2(0, -10), [])
	var l := Alien.new(main.world, "lurker", main.world.feet(main.world.DOOR) + Vector2(40, 60))
	main.world.add_animal(l)
	step(4.0)
	main.hud.panel_open = true
	await _snap("snap_night.png")
	_wipe()
	get_tree().quit(0)


func step(seconds: float) -> void:
	for i in int(seconds / STEP):
		Game._process(STEP)
		main.world._process(STEP)
		main.director._process(STEP)
		main.cards._process(STEP)
		main.colony._process(STEP)
		main.swarm._process(STEP)
		main.tides._process(STEP)


func _snap(name: String) -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
	var p := out.path_join(name)
	img.save_png(p)
	print("saved ", p, " ", img.get_size())


func _wipe() -> void:
	var p := ProjectSettings.globalize_path(Game.slot_path(SLOT))
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
