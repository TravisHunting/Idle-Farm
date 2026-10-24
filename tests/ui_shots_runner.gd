extends Node
## See ui_shots.gd. Drives the real welcome screen and HUD into each state and saves a 3x screenshot.

const SLOT := 9

var out := ""
var main: Node


func _ready() -> void:
	out = ProjectSettings.globalize_path("user://")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	Net.use_upnp = true
	Net.upnp_fake = {"ok": true, "ip": "203.0.113.7"}   # never the real router
	_run.call_deferred()


func _shot(name_: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.resize(img.get_width() * 3 / maxi(1, img.get_width() / 192), img.get_height() * 3 / maxi(1, img.get_width() / 192), Image.INTERPOLATE_NEAREST)
	img.save_png(out.path_join(name_))
	print("saved ", out.path_join(name_))


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().create_timer(0.3).timeout
	# welcome > join a friend, with a bad address typed
	var w: Control = main.welcome
	w.page = 2
	w._refresh()
	w.name_entry.set_text("Travis")
	w.addr_entry.set_text("192.168.1.50:24680x")
	w.focus = "addr"
	w.join_slot = 1
	w._join()
	await _shot("ui_join.png")
	# in a game: the gear menu
	if FileAccess.file_exists(Game.slot_path(SLOT)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.slot_path(SLOT)))
	main.start_slot(SLOT)
	Game.running = true
	await get_tree().create_timer(0.5).timeout
	main.hud.settings_open = true
	await _shot("ui_settings.png")
	Net.host(24693)
	await get_tree().create_timer(0.5).timeout
	await _shot("ui_hosting.png")
	main.hud.settings_open = false
	main.hud.toast = {"text": "PLAYER 2 is here.", "t": 5.0}
	await _shot("ui_toast.png")
	Net.stop()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.slot_path(SLOT)))
	get_tree().quit(0)
