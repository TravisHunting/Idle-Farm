extends SceneTree
## Card impact audit (see impact_runner.gd): how much of the farm does a card change, compared with
## what the rest of the simulation changes on its own, and how much of it is still there a day later?
##   C:/Dev/Godot/Godot_v4.7.2-stable_win64.exe --headless --path . -s tests/impact_test.gd -- trials=40 seed=1


func _initialize() -> void:
	var runner: Script = load("res://tests/impact_runner.gd")
	if runner == null or not runner.can_instantiate():
		printerr("FAIL: tests/impact_runner.gd did not compile")
		quit(1)
		return
	root.add_child.call_deferred(runner.new())
