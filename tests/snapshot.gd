extends SceneTree
## Renders staged screenshots without the MCP (needs a real window, so no --headless):
##   C:/Dev/Godot/Godot_v4.7.2-stable_win64.exe --path . -s tests/snapshot.gd -- out=C:/some/folder
## Writes snap_day.png and snap_night.png (3x scale). The work happens in snapshot_runner.gd,
## loaded at runtime once the autoloads exist (see sim_test.gd).


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/snapshot_runner.gd").new())
