extends SceneTree
## Screenshots of the multiplayer UI (needs a window, not --headless):
##   Godot --path . -s tests/ui_shots.gd -- out=<folder>
## Saves ui_join.png (welcome > join a friend), ui_settings.png (gear menu, not hosting),
## ui_hosting.png (gear menu while hosting, router faked) and ui_toast.png. Logic in ui_shots_runner.gd.


func _initialize() -> void:
	var runner: Script = load("res://tests/ui_shots_runner.gd")
	if runner == null or not runner.can_instantiate():
		printerr("FAIL: tests/ui_shots_runner.gd did not compile")
		quit(1)
		return
	root.add_child.call_deferred(runner.new())
