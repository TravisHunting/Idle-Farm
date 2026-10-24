extends SceneTree
## Click-through of the multiplayer UI with two copies of the game (see click_runner.gd). Everything
## after the start is done with synthetic mouse clicks, drags and key presses, like a person would:
##   Godot --headless --path . -s tests/click_test.gd -- role=host port=24700 profile=4
##   Godot --headless --path . -s tests/click_test.gd -- role=guest port=24700 profile=5
## (tests/run_click_test.sh starts both.) Without --headless, out=<folder> also saves screenshots.


func _initialize() -> void:
	var runner: Script = load("res://tests/click_runner.gd")
	if runner == null or not runner.can_instantiate():
		printerr("FAIL: tests/click_runner.gd did not compile")
		quit(1)
		return
	root.add_child.call_deferred(runner.new())
